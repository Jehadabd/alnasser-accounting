// lib/screens/invoice_history/invoice_history_model.dart
// 🕘 منطق سجل تعديلات الفاتورة (بلا واجهة، للعرض فقط):
// يحوّل النسخ المحفوظة للفاتورة إلى أحداث زمنية مفهومة لصاحب المحل،
// ويقارن كل نسختين متتاليتين في Dart (بيانات الرأس + الأصناف)،
// ويصوغ لكل حدث سطراً ملخّصاً بالعربية.
//
// مصادر البيانات (تُقرأ في الشاشة وتُمرَّر هنا صفوفاً خاماً):
//  • invoice_snapshots — المصدر الأساسي. تُكتب النسخة 'original' عند الإنشاء
//    (أو قبل أول تعديل للفواتير القديمة)، ثم 'before_edit' و'after_edit' عند كل
//    تعديل، والنسخة المطابقة لسابقتها لا تُكتب أصلاً (وحذفت الهجرة
//    compactInvoiceSnapshotsOnce المكرر القديم). أصناف النسخة قد تكون نصاً JSON
//    (قديم) أو BLOB مضغوطاً gzip — تُقرأ عبر AuditDao.decodeSnapshotItemRows.
//  • invoices + invoice_items — الحالة الحالية، لرصد أي تغيير حدث خارج شاشة التعديل.
//  • invoice_adjustments — التسويات (إن وُجدت) كأحداث مستقلة.
//  • financial_audit_log — احتياطي (مبالغ فقط) للفواتير التي لا تملك أي نسخة محفوظة.

import 'dart:convert';

import 'package:intl/intl.dart' show NumberFormat;

import '../../services/database/dao/audit_dao.dart';

// ═══════════════════════════════════════════════════════════════════════════
// تنسيق الأرقام والتواريخ
// ═══════════════════════════════════════════════════════════════════════════

class HistFmt {
  HistFmt._();

  static final NumberFormat _nf = NumberFormat('#,##0.##', 'en_US');

  /// رقم بفواصل الآلاف (450,000) — و«—» إن كان غير معروف
  static String number(double? v) {
    if (v == null) return '—';
    if (v.abs() < 0.005) return '0';
    return _nf.format(v);
  }

  /// رقم بإشارة (+30,000 / −30,000) — يُعرض باتجاه LTR في الواجهة
  static String signed(double v) {
    if (v.abs() < 0.005) return '0';
    return v > 0 ? '+${_nf.format(v)}' : '−${_nf.format(v.abs())}';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// yyyy/MM/dd
  static String date(DateTime d) =>
      '${d.year}/${_two(d.month)}/${_two(d.day)}';

  /// yyyy/MM/dd — hh:mm ص/م
  static String dateTime(DateTime d) {
    final int h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final String period = d.hour < 12 ? 'ص' : 'م';
    return '${date(d)} — ${_two(h)}:${_two(d.minute)} $period';
  }

  static DateTime? parse(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    final String s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  static double? toDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final String s = v.toString().replaceAll(',', '').trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  static double toDouble(dynamic v) => toDoubleOrNull(v) ?? 0.0;
}

String? _nonEmpty(dynamic v) {
  if (v == null) return null;
  final String s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// نص معروف (null يُقرأ فارغاً)
String _str(dynamic v) => v == null ? '' : v.toString().trim();

double? _centsOrNull(dynamic v) {
  final double? c = HistFmt.toDoubleOrNull(v);
  return c == null ? null : c / 100.0;
}

Map<String, dynamic>? _decodeJsonMap(dynamic raw) {
  if (raw == null) return null;
  try {
    final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

// ═══════════════════════════════════════════════════════════════════════════
// نماذج البيانات
// ═══════════════════════════════════════════════════════════════════════════

/// صنف واحد في نسخة من الفاتورة (بعد توحيد الحقول)
class HistItem {
  final String name;
  final String unit; // وحدة البيع: قطعة / كرتون / متر / لفة ...
  final double qty;
  final double price;
  final double total;

  const HistItem({
    required this.name,
    required this.unit,
    required this.qty,
    required this.price,
    required this.total,
  });

  factory HistItem.fromRow(Map<String, dynamic> row) {
    String name = _str(row['product_name']).replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) name = '(بدون اسم)';

    final String saleType = _str(row['sale_type']);
    final String rawUnit = _str(row['unit']);
    String unit = saleType.isNotEmpty ? saleType : rawUnit;
    if (unit == 'piece') unit = 'قطعة';
    if (unit == 'meter') unit = 'متر';

    // الكمية في أحد حقلين حسب نوع البيع؛ الآخر يُحفظ صفراً (أو null في القديم)
    final double qInd = HistFmt.toDouble(row['quantity_individual']);
    final double qLarge = HistFmt.toDouble(row['quantity_large_unit']);
    final bool smallUnit =
        saleType.isEmpty || saleType == 'قطعة' || saleType == 'متر';
    final double qty = smallUnit
        ? (qInd != 0 ? qInd : qLarge)
        : (qLarge != 0 ? qLarge : qInd);

    final double price = HistFmt.toDoubleOrNull(row['applied_price']) ??
        _centsOrNull(row['applied_price_cents']) ??
        HistFmt.toDouble(row['unit_price']);
    final double total = HistFmt.toDoubleOrNull(row['item_total']) ??
        _centsOrNull(row['item_total_cents']) ??
        qty * price;

    return HistItem(
        name: name, unit: unit, qty: qty, price: price, total: total);
  }
}

/// حالة الفاتورة في لحظة ما (نسخة محفوظة، أو الحالة الحالية، أو أرقام سجل التدقيق)
/// الحقل null = غير معروف في هذا المصدر فلا يُقارن.
class HistState {
  final String kind; // original / before_edit / after_edit / current / audit
  final DateTime? at;
  final String? by;
  final String? sysNotes;
  final String? customerName;
  final String? customerPhone;
  final DateTime? invoiceDate;
  final String? paymentType;
  final double? total;
  final double? discount;
  final double? paid;
  final double? loadingFee;
  final String? invoiceNotes;
  final List<HistItem>? items; // null = تفاصيل الأصناف غير محفوظة
  final int? itemsCount;

  const HistState({
    required this.kind,
    this.at,
    this.by,
    this.sysNotes,
    this.customerName,
    this.customerPhone,
    this.invoiceDate,
    this.paymentType,
    this.total,
    this.discount,
    this.paid,
    this.loadingFee,
    this.invoiceNotes,
    this.items,
    this.itemsCount,
  });

  int? get knownItemsCount => items?.length ?? itemsCount;

  factory HistState.fromSnapshot(Map<String, dynamic> row) {
    final double? total = HistFmt.toDoubleOrNull(row['total_amount']);
    final dynamic raw = row['items_json'] ?? row['items'];
    final bool hasRaw = raw != null &&
        !(raw is String && raw.trim().isEmpty) &&
        !(raw is List && raw.isEmpty);

    List<HistItem>? items;
    if (hasRaw) {
      // AuditDao تفكّ الشكلين: نص JSON قديم أو BLOB مضغوط
      final rows = AuditDao.decodeSnapshotItemRows(raw);
      // قائمة فارغة لفاتورة ذات إجمالي = بيانات أصناف تالفة أو مفقودة
      if (rows.isNotEmpty || (total ?? 0).abs() < 0.005) {
        items = rows.map((r) => HistItem.fromRow(r)).toList();
      }
    } else if ((total ?? 0).abs() < 0.005) {
      items = const <HistItem>[];
    }

    return HistState(
      kind: _str(row['snapshot_type']),
      at: HistFmt.parse(row['created_at']),
      by: _nonEmpty(row['created_by']),
      sysNotes: _nonEmpty(row['notes']),
      customerName: _str(row['customer_name']),
      customerPhone: _str(row['customer_phone']),
      invoiceDate: HistFmt.parse(row['invoice_date']),
      paymentType: _str(row['payment_type']),
      total: total,
      discount: HistFmt.toDouble(row['discount']),
      paid: HistFmt.toDouble(row['amount_paid']),
      loadingFee: HistFmt.toDouble(row['loading_fee']),
      invoiceNotes: _str(row['invoice_notes']),
      items: items,
    );
  }

  factory HistState.fromInvoice(
      Map<String, dynamic> inv, List<Map<String, dynamic>> itemRows) {
    return HistState(
      kind: 'current',
      at: HistFmt.parse(inv['last_modified_at']),
      customerName: _str(inv['customer_name']),
      customerPhone: _str(inv['customer_phone']),
      invoiceDate: HistFmt.parse(inv['invoice_date']),
      paymentType: _str(inv['payment_type']),
      total: HistFmt.toDoubleOrNull(inv['total_amount']),
      discount: HistFmt.toDouble(inv['discount']),
      paid: HistFmt.toDouble(inv['amount_paid_on_invoice']),
      loadingFee: HistFmt.toDouble(inv['loading_fee']),
      invoiceNotes: _str(inv['notes']),
      items: itemRows.map((r) => HistItem.fromRow(r)).toList(),
    );
  }

  /// أرقام من financial_audit_log (old_values / new_values) — بلا أصناف
  static HistState? fromAuditJson(dynamic raw, {DateTime? at}) {
    final Map<String, dynamic>? m = _decodeJsonMap(raw);
    if (m == null) return null;
    final double? count = HistFmt.toDoubleOrNull(m['items_count']);
    return HistState(
      kind: 'audit',
      at: at,
      customerName:
          m.containsKey('customer_name') ? _str(m['customer_name']) : null,
      paymentType:
          m['payment_type'] == null ? null : _str(m['payment_type']),
      total: HistFmt.toDoubleOrNull(m['total_amount']),
      discount: HistFmt.toDoubleOrNull(m['discount']),
      paid: HistFmt.toDoubleOrNull(m['paid_amount']),
      itemsCount: count?.round(),
    );
  }
}

/// تغيير في حقل من بيانات الفاتورة (العميل، نوع الدفع، الخصم ...)
class HistFieldChange {
  final String key; // customer, phone, date, payment, discount, loading, paid, notes, total
  final String label;
  final String before;
  final String after;
  final double? delta;

  const HistFieldChange({
    required this.key,
    required this.label,
    required this.before,
    required this.after,
    this.delta,
  });
}

enum HistItemChangeKind { added, removed, changed }

/// تغيير في صنف واحد
class HistItemChange {
  final HistItemChangeKind kind;
  final HistItem? before;
  final HistItem? after;

  const HistItemChange(this.kind, {this.before, this.after});

  HistItem get item => (after ?? before)!;
  String get name => item.name;

  bool get qtyChanged =>
      before != null && after != null && (before!.qty - after!.qty).abs() > 0.0005;
  bool get priceChanged =>
      before != null && after != null && (before!.price - after!.price).abs() > 0.005;
  bool get totalChanged =>
      before != null && after != null && (before!.total - after!.total).abs() > 0.005;
  bool get unitChanged =>
      before != null && after != null && before!.unit != after!.unit;
}

/// نتيجة مقارنة نسختين
class HistDiff {
  final List<HistFieldChange> fields;
  final List<HistItemChange> items;
  final bool itemsUnknown;

  const HistDiff(this.fields, this.items, this.itemsUnknown);

  bool get isEmpty => fields.isEmpty && items.isEmpty;

  HistFieldChange? field(String key) {
    for (final f in fields) {
      if (f.key == key) return f;
    }
    return null;
  }
}

/// تسوية على الفاتورة (invoice_adjustments)
class HistAdjustment {
  final DateTime? at;
  final String type;
  final double delta;
  final String? productName;
  final double? qty;
  final double? price;
  final String? unit;
  final String? note;
  final String? paymentType;

  const HistAdjustment({
    this.at,
    required this.type,
    required this.delta,
    this.productName,
    this.qty,
    this.price,
    this.unit,
    this.note,
    this.paymentType,
  });

  bool get isCredit => delta < 0 || type == 'credit';
}

enum HistEventKind { created, edited, external, adjustment }

/// حدث واحد في الخط الزمني
class HistEvent {
  final HistEventKind kind;
  final DateTime? at; // وقت الحدث المعروض (null = غير معروف بدقة)
  final DateTime? sortAt; // للترتيب فقط
  final String? timeNote; // توضيح عن وقت الحدث إن لم يكن دقيقاً
  final String? by;
  final String headline;
  final List<HistFieldChange> fields;
  final List<HistItemChange> items;
  final bool itemsUnknown;
  final HistState? state; // لحدث الإنشاء: بيانات الفاتورة الأصلية
  final double? totalBefore;
  final double? totalAfter;
  final double? delta; // تغيّر الإجمالي
  final String? note;
  final int editNumber;
  final HistAdjustment? adjustment;

  const HistEvent({
    required this.kind,
    this.at,
    this.sortAt,
    this.timeNote,
    this.by,
    required this.headline,
    this.fields = const <HistFieldChange>[],
    this.items = const <HistItemChange>[],
    this.itemsUnknown = false,
    this.state,
    this.totalBefore,
    this.totalAfter,
    this.delta,
    this.note,
    this.editNumber = 0,
    this.adjustment,
  });

  HistFieldChange? field(String key) {
    for (final f in fields) {
      if (f.key == key) return f;
    }
    return null;
  }
}

/// كل ما تحتاجه الشاشة
class InvoiceHistoryData {
  final List<HistEvent> events; // الأحدث أولاً، والإنشاء في الأسفل
  final int editCount;
  final int externalCount;
  final double? originalTotal;
  final double? currentTotal;
  final DateTime? lastChangeAt;
  final String? customerName;
  final String? invoiceNumber;

  const InvoiceHistoryData({
    required this.events,
    required this.editCount,
    required this.externalCount,
    this.originalTotal,
    this.currentTotal,
    this.lastChangeAt,
    this.customerName,
    this.invoiceNumber,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// بناء الخط الزمني والمقارنة
// ═══════════════════════════════════════════════════════════════════════════

class InvoiceHistoryBuilder {
  InvoiceHistoryBuilder._();

  static InvoiceHistoryData build({
    required List<Map<String, dynamic>> snapshots, // مرتبة تصاعدياً حسب version_number
    Map<String, dynamic>? invoice,
    List<Map<String, dynamic>> currentItems = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> adjustments = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> auditRows = const <Map<String, dynamic>>[],
  }) {
    final List<HistEvent> events = <HistEvent>[]; // ترتيب زمني تصاعدي
    final HistState? current =
        invoice != null ? HistState.fromInvoice(invoice, currentItems) : null;
    final DateTime? invCreatedAt =
        invoice != null ? HistFmt.parse(invoice['created_at']) : null;
    final String? invCreatedBy =
        invoice != null ? _nonEmpty(invoice['created_by_username']) : null;
    final bool foreign = invoice != null &&
        HistFmt.toDouble(invoice['is_created_by_me'] ?? 1) == 0;
    final List<HistAdjustment> adjs = _parseAdjustments(adjustments);
    int editNo = 0;

    if (snapshots.isNotEmpty) {
      // ───── المسار الأساسي: سلسلة النسخ المحفوظة + الحالة الحالية في آخرها ─────
      final List<HistState> chain =
          snapshots.map((r) => HistState.fromSnapshot(r)).toList();
      if (current != null) chain.add(current);
      final int? era = _eraStart(chain);

      final HistState first = chain.first;
      final bool firstIsCreation = first.kind == 'original' &&
          (first.sysNotes ?? '').contains('الإنشاء');
      final DateTime? createdAt = invCreatedAt ?? first.at;
      final String? createdBy =
          invCreatedBy ?? (firstIsCreation ? first.by : null);
      String? note;
      if (!firstIsCreation &&
          first.at != null &&
          createdAt != null &&
          first.at!.difference(createdAt).inMinutes.abs() > 2) {
        note = 'الأرقام من أقدم نسخة محفوظة لهذه الفاتورة، وقد حُفظت عند أول تعديل '
            '(${HistFmt.dateTime(first.at!)}).';
      }
      if (foreign) {
        note = _joinNotes(note, 'فاتورة واردة من جهاز آخر.');
      }
      events.add(_creationEvent(first, at: createdAt, by: createdBy, note: note));

      for (int j = 1; j < chain.length; j++) {
        final HistState prev = chain[j - 1];
        final HistState next = chain[j];
        final HistDiff d = diff(prev, next);
        if (d.isEmpty) continue; // حفظ بلا تغيير ظاهر (تكلفة داخلية مثلاً)

        if (next.kind == 'after_edit') {
          // تعديل من شاشة الفاتورة: النسخة تُحفظ لحظة الحفظ وباسم من حفظ
          editNo++;
          events.add(_editEvent(d, prev, next, editNo, at: next.at, by: next.by));
        } else if (era != null && j > era) {
          // النسخة التالية لم تُكتب بعد تعديل ← تغيّرت الفاتورة من مكان آخر
          if (_explainedByAdjustments(d, prev, next, adjs)) continue;
          events.add(_externalEvent(d, prev, next, foreign: foreign));
        } else {
          // نسخ قديمة (قبل حفظ «بعد التعديل»): النسخة السابقة حُفظت لحظة هذا التعديل
          editNo++;
          events.add(_editEvent(d, prev, next, editNo, at: prev.at, by: prev.by));
        }
      }
    } else {
      // ───── احتياطي: لا توجد أي نسخة — نستعمل سجل التدقيق المالي أو الحالة الحالية ─────
      Map<String, dynamic>? createRow;
      final List<Map<String, dynamic>> updates = <Map<String, dynamic>>[];
      for (final r in auditRows) {
        final String op = _str(r['operation_type']);
        if (op == 'invoice_create') {
          createRow ??= r;
        } else if (op == 'invoice_update') {
          updates.add(r);
        }
      }

      HistState? origin;
      String? note;
      if (updates.isEmpty && current != null) {
        // لم تُسجَّل أي تعديلات: الحالة الحالية (بأصنافها) هي حالة الإنشاء
        origin = current;
        if (foreign) {
          note = 'فاتورة واردة من جهاز آخر: تُعرض حالتها كما وصلت، '
              'والتعديلات التي تجري على الجهاز المُنشئ لا تُسجَّل هنا.';
        } else {
          final DateTime? lm = current.at;
          if (lm != null &&
              invCreatedAt != null &&
              lm.difference(invCreatedAt).inMinutes > 2) {
            note = 'لا توجد نسخ محفوظة لهذه الفاتورة، والمعروض هو حالتها الحالية.';
          }
        }
      }
      if (origin == null && createRow != null) {
        origin = HistState.fromAuditJson(createRow['new_values'],
            at: HistFmt.parse(createRow['created_at']));
      }
      if (origin == null && updates.isNotEmpty) {
        origin = HistState.fromAuditJson(updates.first['old_values'],
            at: HistFmt.parse(updates.first['created_at']));
        note = 'لا تتوفر نسخة كاملة من الفاتورة الأصلية — تُعرض المبالغ المسجّلة قبل أول تعديل.';
      }

      if (origin != null) {
        events.add(_creationEvent(origin,
            at: invCreatedAt ?? origin.at, by: invCreatedBy, note: note));
      }

      HistState? last = origin;
      for (final u in updates) {
        final DateTime? at = HistFmt.parse(u['created_at']);
        final HistState? before = HistState.fromAuditJson(u['old_values'], at: at);
        final HistState? after = HistState.fromAuditJson(u['new_values'], at: at);
        if (after == null) continue;
        final HistDiff d = before != null
            ? diff(before, after)
            : const HistDiff(<HistFieldChange>[], <HistItemChange>[], true);
        editNo++;
        events.add(HistEvent(
          kind: HistEventKind.edited,
          at: at,
          sortAt: at,
          headline: d.isEmpty
              ? 'حُفظ تعديل دون تغيير في المبالغ'
              : headlineFor(d, totalAfter: after.total),
          fields: d.fields,
          itemsUnknown: true,
          totalBefore: before?.total,
          totalAfter: after.total,
          delta: _delta(before?.total, after.total),
          editNumber: editNo,
        ));
        last = after;
      }

      if (current != null && last != null && !identical(last, current)) {
        final HistDiff d = diff(last, current);
        if (!d.isEmpty && !_explainedByAdjustments(d, last, current, adjs)) {
          events.add(_externalEvent(d, last, current, foreign: foreign));
        }
      }
    }

    // ───── إدراج التسويات في مكانها الزمني (الإنشاء يبقى أولاً) ─────
    for (final a in adjs) {
      final HistEvent ev = _adjustmentEvent(a);
      int idx = events.length;
      final DateTime? aAt = a.at;
      if (aAt != null) {
        for (int i = 1; i < events.length; i++) {
          final DateTime? t = events[i].sortAt;
          if (t != null && t.isAfter(aAt)) {
            idx = i;
            break;
          }
        }
      }
      events.insert(idx, ev);
    }

    // ───── ملخّص ─────
    int editCount = 0;
    int externalCount = 0;
    DateTime? lastChangeAt;
    for (final e in events) {
      if (e.kind == HistEventKind.edited) editCount++;
      if (e.kind == HistEventKind.external) externalCount++;
      if (e.kind == HistEventKind.created) continue;
      final DateTime? t = e.at ?? e.sortAt;
      if (t != null && (lastChangeAt == null || t.isAfter(lastChangeAt))) {
        lastChangeAt = t;
      }
    }
    final double? originalTotal =
        events.isNotEmpty && events.first.kind == HistEventKind.created
            ? events.first.state?.total
            : null;

    return InvoiceHistoryData(
      events: events.reversed.toList(),
      editCount: editCount,
      externalCount: externalCount,
      originalTotal: originalTotal,
      currentTotal: current?.total,
      lastChangeAt: lastChangeAt,
      customerName: invoice != null ? _nonEmpty(invoice['customer_name']) : null,
      invoiceNumber: invoice != null ? _nonEmpty(invoice['invoice_number']) : null,
    );
  }

  /// أول نسخة كُتبت بالطريقة الحالية (بعد التعديل / الأصلية عند الإنشاء).
  /// بعدها، النسخة التي ليست «بعد التعديل» تعني تغيّراً من خارج شاشة التعديل.
  static int? _eraStart(List<HistState> chain) {
    for (int i = 0; i < chain.length; i++) {
      final HistState s = chain[i];
      if (s.kind == 'after_edit') return i;
      if (s.kind == 'original' && (s.sysNotes ?? '').contains('الإنشاء')) {
        return i;
      }
    }
    return null;
  }

  static double? _delta(double? before, double? after) {
    if (before == null || after == null) return null;
    return after - before;
  }

  static String? _joinNotes(String? a, String b) =>
      (a == null || a.isEmpty) ? b : '$a $b';

  // ───────────────────────── المقارنة ─────────────────────────

  static HistDiff diff(HistState a, HistState b) {
    final List<HistFieldChange> fields = <HistFieldChange>[];
    _textChange(fields, 'customer', 'العميل', a.customerName, b.customerName);
    _textChange(fields, 'phone', 'هاتف العميل', a.customerPhone, b.customerPhone);
    final DateTime? ad = a.invoiceDate;
    final DateTime? bd = b.invoiceDate;
    if (ad != null &&
        bd != null &&
        !(ad.year == bd.year && ad.month == bd.month && ad.day == bd.day)) {
      fields.add(HistFieldChange(
        key: 'date',
        label: 'تاريخ الفاتورة',
        before: HistFmt.date(ad),
        after: HistFmt.date(bd),
      ));
    }
    _textChange(fields, 'payment', 'نوع الدفع', a.paymentType, b.paymentType);
    _moneyChange(fields, 'discount', 'الخصم', a.discount, b.discount);
    _moneyChange(fields, 'loading', 'أجور التحميل', a.loadingFee, b.loadingFee);
    _moneyChange(fields, 'paid', 'المبلغ المدفوع', a.paid, b.paid);
    _textChange(fields, 'notes', 'الملاحظات', a.invoiceNotes, b.invoiceNotes);
    _moneyChange(fields, 'total', 'الإجمالي', a.total, b.total);

    final List<HistItem>? ai = a.items;
    final List<HistItem>? bi = b.items;
    if (ai == null || bi == null) {
      return HistDiff(fields, const <HistItemChange>[], true);
    }
    return HistDiff(fields, diffItems(ai, bi), false);
  }

  static void _textChange(List<HistFieldChange> out, String key, String label,
      String? a, String? b) {
    if (a == null || b == null) return;
    final String x = a.trim();
    final String y = b.trim();
    if (x == y) return;
    out.add(HistFieldChange(
      key: key,
      label: label,
      before: x.isEmpty ? '—' : x,
      after: y.isEmpty ? '—' : y,
    ));
  }

  static void _moneyChange(List<HistFieldChange> out, String key, String label,
      double? a, double? b) {
    if (a == null || b == null) return;
    if ((a - b).abs() < 0.005) return;
    out.add(HistFieldChange(
      key: key,
      label: label,
      before: HistFmt.number(a),
      after: HistFmt.number(b),
      delta: b - a,
    ));
  }

  /// مطابقة الأصناف: أولاً بالاسم + وحدة البيع، ثم بالاسم وحده (تغيّر الوحدة).
  /// الأسطر المكررة لنفس الصنف تُطابَق بالترتيب.
  static List<HistItemChange> diffItems(
      List<HistItem> before, List<HistItem> after) {
    final List<bool> usedBefore = List<bool>.filled(before.length, false);
    final List<int> matchOfAfter = List<int>.filled(after.length, -1);

    for (final bool strict in const <bool>[true, false]) {
      for (int j = 0; j < after.length; j++) {
        if (matchOfAfter[j] >= 0) continue;
        final HistItem y = after[j];
        for (int i = 0; i < before.length; i++) {
          if (usedBefore[i]) continue;
          final HistItem x = before[i];
          if (x.name == y.name && (!strict || x.unit == y.unit)) {
            usedBefore[i] = true;
            matchOfAfter[j] = i;
            break;
          }
        }
      }
    }

    final List<HistItemChange> changed = <HistItemChange>[];
    final List<HistItemChange> added = <HistItemChange>[];
    for (int j = 0; j < after.length; j++) {
      final int i = matchOfAfter[j];
      if (i < 0) {
        added.add(HistItemChange(HistItemChangeKind.added, after: after[j]));
      } else {
        final HistItemChange c = HistItemChange(HistItemChangeKind.changed,
            before: before[i], after: after[j]);
        if (c.qtyChanged || c.priceChanged || c.totalChanged || c.unitChanged) {
          changed.add(c);
        }
      }
    }
    final List<HistItemChange> removed = <HistItemChange>[];
    for (int i = 0; i < before.length; i++) {
      if (!usedBefore[i]) {
        removed.add(HistItemChange(HistItemChangeKind.removed, before: before[i]));
      }
    }
    return <HistItemChange>[...changed, ...added, ...removed];
  }

  /// تغيّر الإجمالي فقط وتفسّره تسويات مسجّلة بين النسختين؟ (فلا نكرر الحدث)
  static bool _explainedByAdjustments(
      HistDiff d, HistState prev, HistState next, List<HistAdjustment> adjs) {
    if (adjs.isEmpty || d.items.isNotEmpty) return false;
    if (d.fields.length != 1 || d.fields.first.key != 'total') return false;
    final double? pt = prev.total;
    final double? nt = next.total;
    if (pt == null || nt == null) return false;
    final DateTime? from = prev.at;
    final DateTime? to = next.kind == 'current' ? null : next.at;
    double sum = 0;
    bool any = false;
    for (final a in adjs) {
      final DateTime? t = a.at;
      if (t == null) continue;
      if (from != null && !t.isAfter(from)) continue;
      if (to != null && t.isAfter(to)) continue;
      sum += a.delta;
      any = true;
    }
    return any && (sum - (nt - pt)).abs() < 0.01;
  }

  static List<HistAdjustment> _parseAdjustments(
      List<Map<String, dynamic>> rows) {
    final List<HistAdjustment> out = <HistAdjustment>[];
    for (final r in rows) {
      final double? delta = HistFmt.toDoubleOrNull(r['amount_delta']);
      if (delta == null) continue;
      out.add(HistAdjustment(
        at: HistFmt.parse(r['created_at']),
        type: _nonEmpty(r['type']) ??
            _nonEmpty(r['adjustment_type']) ??
            (delta < 0 ? 'credit' : 'debit'),
        delta: delta,
        productName: _nonEmpty(r['product_name']),
        qty: HistFmt.toDoubleOrNull(r['quantity']),
        price: HistFmt.toDoubleOrNull(r['price']),
        unit: _nonEmpty(r['sale_type']) ?? _nonEmpty(r['unit']),
        note: _nonEmpty(r['note']) ?? _nonEmpty(r['reason']),
        paymentType: _nonEmpty(r['settlement_payment_type']),
      ));
    }
    final DateTime epoch = DateTime(1970);
    out.sort((a, b) => (a.at ?? epoch).compareTo(b.at ?? epoch));
    return out;
  }

  // ───────────────────────── صناعة الأحداث ─────────────────────────

  static HistEvent _creationEvent(HistState s,
      {DateTime? at, String? by, String? note}) {
    String head = 'أُنشئت الفاتورة';
    if (s.total != null) head += ' بإجمالي ${HistFmt.number(s.total)}';
    final List<String> extras = <String>[];
    final int? n = s.knownItemsCount;
    if (n != null) extras.add(_countItems(n));
    final String pay = s.paymentType ?? '';
    if (pay.isNotEmpty) extras.add(pay);
    if (extras.isNotEmpty) head += ' (${extras.join('، ')})';
    return HistEvent(
      kind: HistEventKind.created,
      at: at,
      sortAt: at,
      by: by,
      headline: head,
      itemsUnknown: s.items == null,
      state: s,
      totalAfter: s.total,
      note: note,
    );
  }

  static HistEvent _editEvent(
      HistDiff d, HistState prev, HistState next, int no,
      {DateTime? at, String? by}) {
    return HistEvent(
      kind: HistEventKind.edited,
      at: at,
      sortAt: at ?? next.at,
      by: by,
      headline: headlineFor(d, totalAfter: next.total),
      fields: d.fields,
      items: d.items,
      itemsUnknown: d.itemsUnknown,
      totalBefore: prev.total,
      totalAfter: next.total,
      delta: _delta(prev.total, next.total),
      editNumber: no,
    );
  }

  static HistEvent _externalEvent(HistDiff d, HistState prev, HistState next,
      {required bool foreign}) {
    final DateTime? pa = prev.at;
    final DateTime? na = next.at;
    DateTime? at;
    String? timeNote;
    if (next.kind == 'current') {
      if (na != null &&
          (pa == null || na.isAfter(pa.add(const Duration(minutes: 1))))) {
        at = na;
      } else if (pa != null) {
        timeNote = 'بعد ${HistFmt.dateTime(pa)} (الوقت الدقيق غير مسجّل)';
      }
    } else if (pa != null && na != null) {
      timeNote = 'بين ${HistFmt.dateTime(pa)} و${HistFmt.dateTime(na)}';
    } else {
      at = na;
    }
    return HistEvent(
      kind: HistEventKind.external,
      at: at,
      sortAt: na ?? pa,
      timeNote: timeNote,
      headline: headlineFor(d, totalAfter: next.total),
      fields: d.fields,
      items: d.items,
      itemsUnknown: d.itemsUnknown,
      totalBefore: prev.total,
      totalAfter: next.total,
      delta: _delta(prev.total, next.total),
      note: foreign
          ? 'تحديث وصل من الجهاز الذي أنشأ الفاتورة (مزامنة).'
          : 'تغيّرت الفاتورة دون المرور بشاشة التعديل (مثل تسوية أو مزامنة أو تصحيح تلقائي)، لذلك لا يُعرف من قام به.',
    );
  }

  static HistEvent _adjustmentEvent(HistAdjustment a) {
    final String amount = HistFmt.number(a.delta.abs());
    String head;
    final String? product = a.productName;
    if (product != null) {
      final double? q = a.qty;
      final String qty = q != null
          ? '${HistFmt.number(q)}${a.unit != null ? ' ${a.unit}' : ''} من '
          : '';
      head = a.isCredit
          ? 'إرجاع $qty«${_short(product)}» بقيمة $amount'
          : 'إضافة $qty«${_short(product)}» بقيمة $amount';
    } else {
      head = a.isCredit
          ? 'تسوية بالنقص على الفاتورة بقيمة $amount'
          : 'تسوية بالزيادة على الفاتورة بقيمة $amount';
    }
    return HistEvent(
      kind: HistEventKind.adjustment,
      at: a.at,
      sortAt: a.at,
      headline: head,
      delta: a.isCredit ? -a.delta.abs() : a.delta.abs(),
      adjustment: a,
    );
  }

  // ───────────────────────── صياغة السطر الملخّص ─────────────────────────

  /// مثال: «عُدّلت الكمية لصنفين وتغيّر الإجمالي من 450,000 إلى 480,000»
  static String headlineFor(HistDiff d, {double? totalAfter}) {
    final List<String> parts = <String>[];
    final List<HistItemChange> changed =
        d.items.where((c) => c.kind == HistItemChangeKind.changed).toList();
    final List<HistItemChange> added =
        d.items.where((c) => c.kind == HistItemChangeKind.added).toList();
    final List<HistItemChange> removed =
        d.items.where((c) => c.kind == HistItemChangeKind.removed).toList();

    if (changed.isNotEmpty) {
      final bool q = changed.any((c) => c.qtyChanged);
      final bool p = changed.any((c) => c.priceChanged);
      final bool u = changed.any((c) => c.unitChanged);
      String what;
      if (q && p) {
        what = 'عُدّلت الكمية والسعر';
      } else if (q) {
        what = 'عُدّلت الكمية';
      } else if (p) {
        what = 'عُدّل السعر';
      } else if (u) {
        what = 'تغيّرت وحدة البيع';
      } else {
        what = 'تغيّر المجموع';
      }
      parts.add('$what ${_forItems(changed)}');
    }
    if (added.isNotEmpty) parts.add(_addedPhrase(added));
    if (removed.isNotEmpty) parts.add(_removedPhrase(removed));

    for (final f in d.fields) {
      if (f.key == 'total') continue;
      parts.add(_fieldPhrase(f));
    }

    final HistFieldChange? t = d.field('total');
    if (t != null) {
      parts.add('تغيّر الإجمالي من ${t.before} إلى ${t.after}');
    } else if (d.items.isNotEmpty && totalAfter != null) {
      parts.add('بقي الإجمالي ${HistFmt.number(totalAfter)}');
    }

    if (parts.isEmpty) return 'حُفظت الفاتورة دون تغيير ظاهر';
    return _joinParts(parts);
  }

  static String _joinParts(List<String> parts) {
    if (parts.length == 1) return parts.first;
    if (parts.length == 2) return '${parts[0]} و${parts[1]}';
    final StringBuffer b = StringBuffer(parts.first);
    for (int i = 1; i < parts.length; i++) {
      b.write('، و${parts[i]}');
    }
    return b.toString();
  }

  static String _fieldPhrase(HistFieldChange f) {
    if (f.key == 'customer') {
      return f.before == '—'
          ? 'أُضيف اسم العميل «${_short(f.after)}»'
          : 'تغيّر العميل من «${_short(f.before)}» إلى «${_short(f.after)}»';
    }
    if (f.key == 'phone') return 'عُدّل هاتف العميل';
    if (f.key == 'date') return 'تغيّر تاريخ الفاتورة إلى ${f.after}';
    if (f.key == 'payment') return 'تحوّل الدفع من ${f.before} إلى ${f.after}';
    if (f.key == 'discount') return 'تغيّر الخصم من ${f.before} إلى ${f.after}';
    if (f.key == 'loading') {
      return 'تغيّرت أجور التحميل من ${f.before} إلى ${f.after}';
    }
    if (f.key == 'paid') return 'تغيّر المدفوع من ${f.before} إلى ${f.after}';
    if (f.key == 'notes') return 'عُدّلت الملاحظات';
    return 'تغيّر ${f.label}';
  }

  static String _short(String s) =>
      s.length > 28 ? '${s.substring(0, 27)}…' : s;

  /// «للصنف "X"» / «لصنفين» / «لـ 3 أصناف» / «لـ 12 صنفاً»
  static String _forItems(List<HistItemChange> list) {
    final int n = list.length;
    if (n == 1) return 'للصنف «${_short(list.first.name)}»';
    if (n == 2) return 'لصنفين';
    return n <= 10 ? 'لـ $n أصناف' : 'لـ $n صنفاً';
  }

  static String _addedPhrase(List<HistItemChange> list) {
    final int n = list.length;
    if (n == 1) return 'أُضيف الصنف «${_short(list.first.name)}»';
    if (n == 2) return 'أُضيف صنفان';
    return n <= 10 ? 'أُضيفت $n أصناف' : 'أُضيف $n صنفاً';
  }

  static String _removedPhrase(List<HistItemChange> list) {
    final int n = list.length;
    if (n == 1) return 'حُذف الصنف «${_short(list.first.name)}»';
    if (n == 2) return 'حُذف صنفان';
    return n <= 10 ? 'حُذفت $n أصناف' : 'حُذف $n صنفاً';
  }

  static String _countItems(int n) {
    if (n == 0) return 'بلا أصناف';
    if (n == 1) return 'صنف واحد';
    if (n == 2) return 'صنفان';
    return n <= 10 ? '$n أصناف' : '$n صنفاً';
  }
}
