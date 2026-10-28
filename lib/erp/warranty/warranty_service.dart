// lib/erp/warranty/warranty_service.dart
//
// 🛠️ الضمان والصيانة — قطعة يرجعها العميل معطوبة، ومتابعتها حتى تعود إليه:
//   في المحل ← عند المورد ← جاهزة (أُصلحت / استُبدلت / رُدّ ثمنها / رُفضت) ← سُلّمت.
//
// قاعدة ثابتة: هذا الملف لا يغيّر أي مبلغ ولا رصيد ولا مخزون ولا قيد.
// ردّ الثمن يُسجَّل من «مرتجع مبيعات» كالعادة، والاستبدال من المخزن بمستنداته.
// كل تغيير حالة يُكتب في خط زمني للطلب وفي سجل النشاط.

import 'package:flutter/material.dart' show Color, IconData, Icons;
import 'package:sqflite/sqflite.dart';

import '../activity/activity_log.dart';
import '../erp_common.dart';
import 'warranty_schema.dart';

/// حالات الطلب بالترتيب.
class WStatus {
  WStatus._();
  static const received = 'received';
  static const atSupplier = 'at_supplier';
  static const ready = 'ready';
  static const delivered = 'delivered';

  static const all = [received, atSupplier, ready, delivered];

  static String label(String s) => switch (s) {
        received => 'في المحل',
        atSupplier => 'عند المورد',
        ready => 'جاهزة للتسليم',
        delivered => 'سُلّمت للعميل',
        _ => s,
      };

  static Color color(String s) => switch (s) {
        received => const Color(0xFFB45309),
        atSupplier => const Color(0xFF7C3AED),
        ready => const Color(0xFF0E7490),
        delivered => const Color(0xFF15803D),
        _ => const Color(0xFF64748B),
      };

  static IconData icon(String s) => switch (s) {
        received => Icons.inventory_2_rounded,
        atSupplier => Icons.local_shipping_rounded,
        ready => Icons.task_alt_rounded,
        delivered => Icons.handshake_rounded,
        _ => Icons.circle_outlined,
      };
}

/// نتيجة الصيانة.
class WResolution {
  WResolution._();
  static const repaired = 'repaired';
  static const replaced = 'replaced';
  static const refunded = 'refunded';
  static const rejected = 'rejected';

  static const all = [repaired, replaced, refunded, rejected];

  static String label(String? r) => switch (r) {
        repaired => 'أُصلحت',
        replaced => 'استُبدلت بقطعة جديدة',
        refunded => 'رُدّ ثمنها',
        rejected => 'رُفض الضمان',
        _ => '—',
      };

  static Color color(String? r) => switch (r) {
        repaired => const Color(0xFF15803D),
        replaced => const Color(0xFF1D4ED8),
        refunded => const Color(0xFFB45309),
        rejected => const Color(0xFFB91C1C),
        _ => const Color(0xFF64748B),
      };
}

class WarrantyClaim {
  WarrantyClaim({
    this.id,
    this.claimNo = 0,
    this.customerId,
    required this.customerName,
    this.phone,
    this.productId,
    required this.productName,
    this.qty = 1,
    this.serialNo,
    this.invoiceId,
    this.saleDate,
    this.warrantyMonths,
    this.withinWarranty,
    required this.claimDate,
    this.problem,
    this.accessories,
    this.status = WStatus.received,
    this.resolution,
    this.supplierId,
    this.supplierName,
    this.sentDate,
    this.backDate,
    this.deliveredDate,
    this.notes,
    this.createdBy,
  });

  int? id;
  int claimNo;
  int? customerId;
  String customerName;
  String? phone;
  int? productId;
  String productName;
  double qty;
  String? serialNo;
  int? invoiceId;
  DateTime? saleDate;
  int? warrantyMonths;

  /// true داخل الضمان، false خارجه، null غير معروف (بلا تاريخ بيع أو مدة).
  bool? withinWarranty;
  DateTime claimDate;
  String? problem;
  String? accessories;
  String status;
  String? resolution;
  int? supplierId;
  String? supplierName;
  DateTime? sentDate;
  DateTime? backDate;
  DateTime? deliveredDate;
  String? notes;
  String? createdBy;

  bool get isOpen => status != WStatus.delivered;

  /// آخر يوم في الضمان (null إن لم يُعرف).
  DateTime? get warrantyEnd => WarrantyService.endOf(saleDate, warrantyMonths);

  /// أيام بقاء القطعة عندنا (حتى التسليم أو اليوم).
  int get daysOpen => (deliveredDate ?? DateTime.now()).difference(claimDate).inDays;

  static DateTime? _d(Object? v) => v == null || '$v'.isEmpty ? null : DateTime.tryParse('$v');
  static String? _s(DateTime? d) => d?.toIso8601String();

  factory WarrantyClaim.fromMap(Map<String, Object?> m) => WarrantyClaim(
        id: (m['id'] as num?)?.toInt(),
        claimNo: (m['claim_no'] as num?)?.toInt() ?? 0,
        customerId: (m['customer_id'] as num?)?.toInt(),
        customerName: (m['customer_name'] as String?) ?? '',
        phone: m['phone'] as String?,
        productId: (m['product_id'] as num?)?.toInt(),
        productName: (m['product_name'] as String?) ?? '',
        qty: (m['qty'] as num?)?.toDouble() ?? 1,
        serialNo: m['serial_no'] as String?,
        invoiceId: (m['invoice_id'] as num?)?.toInt(),
        saleDate: _d(m['sale_date']),
        warrantyMonths: (m['warranty_months'] as num?)?.toInt(),
        withinWarranty: m['within_warranty'] == null ? null : (m['within_warranty'] as num) != 0,
        claimDate: _d(m['claim_date']) ?? DateTime.now(),
        problem: m['problem'] as String?,
        accessories: m['accessories'] as String?,
        status: (m['status'] as String?) ?? WStatus.received,
        resolution: m['resolution'] as String?,
        supplierId: (m['supplier_id'] as num?)?.toInt(),
        supplierName: m['supplier_name'] as String?,
        sentDate: _d(m['sent_date']),
        backDate: _d(m['back_date']),
        deliveredDate: _d(m['delivered_date']),
        notes: m['notes'] as String?,
        createdBy: m['created_by'] as String?,
      );

  /// الحقول التي يحررها نموذج الاستلام (الحالة وتواريخها تتغير عبر setStatus فقط).
  Map<String, Object?> editableMap() => {
        'customer_id': customerId,
        'customer_name': customerName.trim(),
        'phone': (phone ?? '').trim().isEmpty ? null : phone!.trim(),
        'product_id': productId,
        'product_name': productName.trim(),
        'qty': qty,
        'serial_no': (serialNo ?? '').trim().isEmpty ? null : serialNo!.trim(),
        'invoice_id': invoiceId,
        'sale_date': _s(saleDate),
        'warranty_months': warrantyMonths,
        'within_warranty': withinWarranty == null ? null : (withinWarranty! ? 1 : 0),
        'claim_date': _s(claimDate),
        'problem': (problem ?? '').trim().isEmpty ? null : problem!.trim(),
        'accessories': (accessories ?? '').trim().isEmpty ? null : accessories!.trim(),
        'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
      };
}

class WarrantyEvent {
  WarrantyEvent(this.status, this.note, this.user, this.at);
  final String status;
  final String? note;
  final String? user;
  final DateTime at;
}

/// آخر بيع لهذه المادة لهذا العميل (لاقتراح تاريخ البيع ورقم الفاتورة).
class LastSale {
  LastSale(this.invoiceId, this.date);
  final int invoiceId;
  final DateTime date;
}

class ProductClaimStat {
  ProductClaimStat(this.name, this.claims, this.qty, this.rejected);
  final String name;
  final int claims;
  final double qty;
  final int rejected;
}

class SupplierClaimStat {
  SupplierClaimStat(this.name, this.sent, this.back, this.avgDays, this.stillThere);
  final String name;
  final int sent;
  final int back;
  final double avgDays;
  final int stillThere;
}

class WarrantyService {
  WarrantyService._();

  static bool _ready = false;

  static Future<Database> db() async {
    final d = await erpDb();
    if (!_ready) {
      for (final s in WarrantySchema.statements) {
        await d.execute(s);
      }
      _ready = true;
    }
    return d;
  }

  /// نهاية الضمان = تاريخ البيع + الأشهر.
  static DateTime? endOf(DateTime? sale, int? months) {
    if (sale == null || months == null || months <= 0) return null;
    return DateTime(sale.year, sale.month + months, sale.day);
  }

  /// داخل الضمان؟ (null = لا يُعرف)
  static bool? within(DateTime? sale, int? months, DateTime claimDay) {
    final end = endOf(sale, months);
    if (end == null) return null;
    final c = DateTime(claimDay.year, claimDay.month, claimDay.day);
    return !c.isAfter(end);
  }

  // ───────── مدة ضمان المادة ─────────

  static Future<int?> productMonths(int productId) async {
    final d = await db();
    final r = await d.query('product_warranty', where: 'product_id = ?', whereArgs: [productId], limit: 1);
    final m = r.isEmpty ? null : (r.first['months'] as num?)?.toInt();
    return (m == null || m <= 0) ? null : m;
  }

  static Future<void> setProductMonths(int productId, int months) async {
    final d = await db();
    await d.insert(
      'product_warranty',
      {'product_id': productId, 'months': months, 'updated_at': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ───────── آخر بيع ─────────

  static Future<LastSale?> lastSale({int? customerId, required String customerName, int? productId, required String productName}) async {
    final d = await db();
    final who = customerId != null ? 'i.customer_id = ?' : 'TRIM(i.customer_name) = ?';
    final what = productId != null ? '(it.product_id = ? OR TRIM(it.product_name) = ?)' : 'TRIM(it.product_name) = ?';
    final args = <Object?>[
      customerId ?? customerName.trim(),
      if (productId != null) productId,
      productName.trim(),
    ];
    try {
      final r = await d.rawQuery('''
        SELECT i.id, i.invoice_date FROM invoices i
        JOIN invoice_items it ON it.invoice_id = i.id
        WHERE $who AND $what
        ORDER BY i.invoice_date DESC, i.id DESC LIMIT 1''', args);
      if (r.isEmpty) return null;
      final dt = DateTime.tryParse('${r.first['invoice_date']}');
      return dt == null ? null : LastSale((r.first['id'] as num).toInt(), dt);
    } catch (_) {
      return null;
    }
  }

  // ───────── القراءة ─────────

  /// [filter]: 'open' | حالة | 'all'
  static Future<List<WarrantyClaim>> list({String filter = 'open', String query = ''}) async {
    final d = await db();
    final where = <String>[];
    final args = <Object?>[];
    if (filter == 'open') {
      where.add("status <> '${WStatus.delivered}'");
    } else if (filter != 'all') {
      where.add('status = ?');
      args.add(filter);
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      where.add('(customer_name LIKE ? OR product_name LIKE ? OR IFNULL(serial_no,\'\') LIKE ? '
          'OR IFNULL(phone,\'\') LIKE ? OR IFNULL(supplier_name,\'\') LIKE ? OR CAST(claim_no AS TEXT) = ?)');
      final like = '%$q%';
      args.addAll([like, like, like, like, like, q]);
    }
    final r = await d.query(
      'warranty_claims',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'claim_date DESC, id DESC',
      limit: 500,
    );
    return r.map(WarrantyClaim.fromMap).toList();
  }

  static Future<Map<String, int>> counts() async {
    final d = await db();
    final r = await d.rawQuery('SELECT status, COUNT(*) AS n FROM warranty_claims GROUP BY status');
    return {for (final x in r) '${x['status']}': (x['n'] as num).toInt()};
  }

  static Future<WarrantyClaim?> get(int id) async {
    final d = await db();
    final r = await d.query('warranty_claims', where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : WarrantyClaim.fromMap(r.first);
  }

  static Future<List<WarrantyEvent>> events(int claimId) async {
    final d = await db();
    final r = await d.query('warranty_claim_events', where: 'claim_id = ?', whereArgs: [claimId], orderBy: 'at, id');
    return [
      for (final e in r)
        WarrantyEvent('${e['status']}', e['note'] as String?, e['user_name'] as String?,
            DateTime.tryParse('${e['at']}') ?? DateTime.now()),
    ];
  }

  /// طلبات سابقة لنفس العميل والمادة (قطعة تتكرر أعطالها).
  static Future<int> previousClaims({int? customerId, required String customerName, required String productName, int? exceptId}) async {
    final d = await db();
    final r = await d.rawQuery('''
      SELECT COUNT(*) AS n FROM warranty_claims
      WHERE ${customerId != null ? 'customer_id = ?' : 'TRIM(customer_name) = ?'}
        AND TRIM(product_name) = ? AND id <> ?''', [customerId ?? customerName.trim(), productName.trim(), exceptId ?? -1]);
    return (r.first['n'] as num).toInt();
  }

  // ───────── الكتابة (سجل متابعة فقط — لا مال ولا مخزون) ─────────

  static Future<void> _event(DatabaseExecutor t, int claimId, String status, String? note) => t.insert('warranty_claim_events', {
        'claim_id': claimId,
        'status': status,
        'note': note,
        'user_name': currentUserName(),
        'at': DateTime.now().toIso8601String(),
      });

  /// استلام جديد أو تعديل بيانات الاستلام. يعيد رقم الطلب.
  static Future<int> save(WarrantyClaim c) async {
    if (c.customerName.trim().isEmpty) throw ErpException('اسم العميل مطلوب');
    if (c.productName.trim().isEmpty) throw ErpException('اسم المادة مطلوب');
    if (c.qty <= 0) throw ErpException('الكمية يجب أن تكون أكبر من صفر');
    final d = await db();
    final now = DateTime.now().toIso8601String();
    final isNew = c.id == null;
    late int id;
    await d.transaction((t) async {
      if (c.id == null) {
        final no = await nextDocNumber(t, 'warranty_claims', 'claim_no');
        id = await t.insert('warranty_claims', {
          ...c.editableMap(),
          'claim_no': no,
          'status': WStatus.received,
          'created_by': currentUserName(),
          'created_at': now,
          'updated_at': now,
        });
        c
          ..id = id
          ..claimNo = no;
        await _event(t, id, WStatus.received, c.problem);
      } else {
        id = c.id!;
        await t.update('warranty_claims', {...c.editableMap(), 'updated_at': now}, where: 'id = ?', whereArgs: [id]);
        await _event(t, id, 'edit', 'عُدّلت بيانات الاستلام');
      }
    });
    ActivityLog.log(isNew ? 'ضمان: استلام قطعة' : 'ضمان: تعديل استلام', 'الضمان والصيانة',
            'طلب ${c.claimNo} — ${c.productName} — ${c.customerName}')
        .catchError((_) {});
    return id;
  }

  /// نقل الطلب إلى حالة جديدة مع تواريخها.
  static Future<void> setStatus(
    int id,
    String status, {
    String? resolution,
    int? supplierId,
    String? supplierName,
    String? note,
  }) async {
    final d = await db();
    final now = DateTime.now();
    final iso = now.toIso8601String();
    final c = await get(id);
    if (c == null) throw ErpException('الطلب غير موجود');
    final values = <String, Object?>{'status': status, 'updated_at': iso};
    if (status == WStatus.atSupplier) {
      values['sent_date'] = iso;
      if (supplierName != null) {
        values['supplier_id'] = supplierId;
        values['supplier_name'] = supplierName;
      }
    }
    if (status == WStatus.ready) {
      values['resolution'] = resolution;
      if (c.status == WStatus.atSupplier) values['back_date'] = iso;
    }
    if (status == WStatus.delivered) values['delivered_date'] = iso;
    if (status == WStatus.received) {
      // إعادة فتح: تبقى التواريخ السابقة في الخط الزمني
      values['resolution'] = null;
      values['delivered_date'] = null;
    }
    final label = [
      WStatus.label(status),
      if (status == WStatus.ready && resolution != null) WResolution.label(resolution),
      if (status == WStatus.atSupplier && supplierName != null) supplierName,
      if ((note ?? '').trim().isNotEmpty) note!.trim(),
    ].join(' — ');
    await d.transaction((t) async {
      await t.update('warranty_claims', values, where: 'id = ?', whereArgs: [id]);
      await _event(t, id, status, [
        if (status == WStatus.ready && resolution != null) WResolution.label(resolution),
        if (status == WStatus.atSupplier && supplierName != null) 'المورد: $supplierName',
        if ((note ?? '').trim().isNotEmpty) note!.trim(),
      ].join(' — '));
    });
    ActivityLog.log('ضمان: ${WStatus.label(status)}', 'الضمان والصيانة', 'طلب ${c.claimNo} — ${c.productName} — $label')
        .catchError((_) {});
  }

  /// ملاحظة على الخط الزمني بلا تغيير حالة.
  static Future<void> addNote(int id, String note) async {
    if (note.trim().isEmpty) return;
    final d = await db();
    await _event(d, id, 'note', note.trim());
    await d.update('warranty_claims', {'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
  }

  /// حذف طلب سُجّل خطأً (لا أثر مالي له أصلاً).
  static Future<void> delete(int id) async {
    final d = await db();
    final c = await get(id);
    await d.transaction((t) async {
      await t.delete('warranty_claim_events', where: 'claim_id = ?', whereArgs: [id]);
      await t.delete('warranty_claims', where: 'id = ?', whereArgs: [id]);
    });
    if (c != null) {
      ActivityLog.log('ضمان: حذف طلب', 'الضمان والصيانة', 'طلب ${c.claimNo} — ${c.productName} — ${c.customerName}')
          .catchError((_) {});
    }
  }

  // ───────── التقرير ─────────

  static Future<List<ProductClaimStat>> topProducts({int limit = 15}) async {
    final d = await db();
    final r = await d.rawQuery('''
      SELECT TRIM(product_name) AS name, COUNT(*) AS n, SUM(qty) AS q,
             SUM(CASE WHEN resolution = '${WResolution.rejected}' THEN 1 ELSE 0 END) AS rej
      FROM warranty_claims GROUP BY TRIM(product_name)
      ORDER BY n DESC, q DESC LIMIT $limit''');
    return [
      for (final x in r)
        ProductClaimStat('${x['name']}', (x['n'] as num).toInt(), d0(x['q']), (x['rej'] as num?)?.toInt() ?? 0),
    ];
  }

  static Future<List<SupplierClaimStat>> suppliers() async {
    final d = await db();
    final r = await d.rawQuery('''
      SELECT supplier_name AS name, COUNT(*) AS sent,
             SUM(CASE WHEN back_date IS NOT NULL THEN 1 ELSE 0 END) AS back,
             AVG(CASE WHEN back_date IS NOT NULL AND sent_date IS NOT NULL
                      THEN julianday(back_date) - julianday(sent_date) END) AS avg_days,
             SUM(CASE WHEN status = '${WStatus.atSupplier}' THEN 1 ELSE 0 END) AS there
      FROM warranty_claims WHERE IFNULL(supplier_name,'') <> ''
      GROUP BY supplier_name ORDER BY sent DESC''');
    return [
      for (final x in r)
        SupplierClaimStat('${x['name']}', (x['sent'] as num).toInt(), (x['back'] as num?)?.toInt() ?? 0, d0(x['avg_days']),
            (x['there'] as num?)?.toInt() ?? 0),
    ];
  }

  static Future<Map<String, int>> resolutions() async {
    final d = await db();
    final r = await d.rawQuery(
        'SELECT resolution, COUNT(*) AS n FROM warranty_claims WHERE resolution IS NOT NULL GROUP BY resolution');
    return {for (final x in r) '${x['resolution']}': (x['n'] as num).toInt()};
  }
}
