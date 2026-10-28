// lib/services/invoice_edit_log.dart
//
// ✏️ تصنيف تعديل الفاتورة المحفوظة: ما زاد = «إضافة»، ما نقص = «مرتجع»،
// وتغيّر السعر وحده = «تعديل سعر».
//
// ⚠️ سجلّ توضيحي فقط — لا يغيّر رصيداً ولا مخزوناً. الأثر المالي للتعديل
// يحسبه InvoiceDebtReconciler من الفاتورة نفسها (مرة واحدة)، والمخزون تتبعه
// مشغّلات دفتر المخزون. لو سُجّل النقص «مرتجعاً» حقيقياً (سند مرتجع) فوق
// ذلك لنقص دين العميل ومخزون المادة مرتين.

import 'package:sqflite/sqflite.dart';

class InvoiceEditChange {
  final String productName;
  final String unit;
  final double qtyBefore;
  final double qtyAfter;
  final double amountBefore;
  final double amountAfter;
  final String kind; // إضافة | مرتجع | تعديل سعر
  final DateTime editedAt;
  final String? editedBy;

  const InvoiceEditChange({
    required this.productName,
    required this.unit,
    required this.qtyBefore,
    required this.qtyAfter,
    required this.amountBefore,
    required this.amountAfter,
    required this.kind,
    required this.editedAt,
    this.editedBy,
  });

  double get qtyDelta => qtyAfter - qtyBefore;
  double get amountDelta => amountAfter - amountBefore;
}

class InvoiceEditLog {
  InvoiceEditLog._();

  static const kindAdd = 'إضافة';
  static const kindReturn = 'مرتجع';
  static const kindPrice = 'تعديل سعر';

  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_edit_changes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        edited_at TEXT NOT NULL,
        edited_by TEXT,
        product_name TEXT NOT NULL,
        unit TEXT,
        qty_before REAL NOT NULL DEFAULT 0,
        qty_after REAL NOT NULL DEFAULT 0,
        amount_before REAL NOT NULL DEFAULT 0,
        amount_after REAL NOT NULL DEFAULT 0,
        kind TEXT NOT NULL
      )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoice_edit_changes_inv ON invoice_edit_changes(invoice_id)');
  }

  static double _q(Map<String, Object?> m) {
    final a = (m['quantity_individual'] as num?)?.toDouble();
    final b = (m['quantity_large_unit'] as num?)?.toDouble();
    // المباع بوحدة كبيرة يحمل quantity_individual = 0 (لا null): كان يُقرأ صفراً
    // فيُسجَّل «مرتجع» بكمية صفر لمادة لم تتغير.
    if (b != null && b > 0) return b;
    return a ?? b ?? 0.0;
  }

  static Map<String, List<double>> _group(Iterable<Map<String, Object?>> rows) {
    final out = <String, List<double>>{};
    for (final r in rows) {
      final name = '${r['product_name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final key = '$name\u0001${r['sale_type'] ?? ''}';
      final v = out.putIfAbsent(key, () => [0.0, 0.0]);
      v[0] += _q(r);
      v[1] += (r['item_total'] as num?)?.toDouble() ?? 0.0;
    }
    return out;
  }

  /// يُستدعى داخل معاملة الحفظ، بعد قراءة البنود القديمة وقبل حذفها.
  /// يعيد ملخصاً قصيراً لوصف معاملة التسوية («إضافة 2 مادة، مرتجع 1 مادة»)،
  /// أو null إن لم يتغير شيء في المواد.
  static Future<String?> record(
    DatabaseExecutor db, {
    required int invoiceId,
    required List<Map<String, Object?>> oldItems,
    required List<Map<String, Object?>> newItems,
    String? editedBy,
  }) async {
    final before = _group(oldItems);
    final after = _group(newItems);
    final keys = <String>{...before.keys, ...after.keys};
    final now = DateTime.now().toIso8601String();
    var adds = 0, rets = 0, prices = 0;
    double addAmt = 0, retAmt = 0;
    final changes = <Map<String, Object?>>[];
    for (final k in keys) {
      final b = before[k] ?? const [0.0, 0.0];
      final a = after[k] ?? const [0.0, 0.0];
      final dq = a[0] - b[0];
      final da = a[1] - b[1];
      String? kind;
      if (dq > 1e-9) {
        kind = kindAdd;
        adds++;
        addAmt += da;
      } else if (dq < -1e-9) {
        kind = kindReturn;
        rets++;
        retAmt += da;
      } else if (da.abs() > 0.004) {
        kind = kindPrice;
        prices++;
      }
      if (kind == null) continue;
      final parts = k.split('\u0001');
      changes.add({
        'invoice_id': invoiceId,
        'edited_at': now,
        'edited_by': editedBy,
        'product_name': parts.first,
        'unit': parts.length > 1 ? parts[1] : null,
        'qty_before': b[0],
        'qty_after': a[0],
        'amount_before': b[1],
        'amount_after': a[1],
        'kind': kind,
      });
    }
    if (changes.isEmpty) return null;
    await ensure(db);
    for (final c in changes) {
      await db.insert('invoice_edit_changes', c);
    }
    String n(double v) => v.abs().round().toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    final s = <String>[
      if (adds > 0) 'إضافة $adds مادة (+${n(addAmt)})',
      if (rets > 0) 'مرتجع $rets مادة (−${n(retAmt)})',
      if (prices > 0) 'تعديل سعر $prices مادة',
    ];
    return s.join('، ');
  }

  /// ↩️ ما نقص من الفواتير بتعديلها بعد الحفظ (حذف مادة أو إنقاص كميتها) في فترة.
  /// للعرض في المرتجعات والتقارير: مبلغه منقوص من مجموع الفاتورة أصلاً، ومخزونه
  /// ودين العميل عُدّلا مع الحفظ، فلا يُطرح ولا يُرحَّل مرة ثانية.
  static Future<List<Map<String, Object?>>> returnsInPeriod(
    DatabaseExecutor db, {
    required DateTime from,
    required DateTime to,
    String invoiceFilter = '',
  }) async {
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    try {
      await ensure(db);
      return await db.rawQuery('''
        SELECT c.*, i.invoice_number, i.customer_name, i.payment_type
        FROM invoice_edit_changes c JOIN invoices i ON i.id = c.invoice_id
        WHERE c.kind = ? AND c.edited_at >= ? AND c.edited_at <= ?
          AND c.amount_before - c.amount_after > 0.004 $invoiceFilter
        ORDER BY c.edited_at DESC, c.id DESC''', [kindReturn, '${day(from)}T00:00:00', '${day(to)}T23:59:59.999']);
    } catch (_) {
      return const [];
    }
  }

  /// مبلغ سطر مرتجع بالتعديل (ما نقص من مجموع المادة).
  static double returnedAmount(Map<String, Object?> r) =>
      ((r['amount_before'] as num?)?.toDouble() ?? 0) - ((r['amount_after'] as num?)?.toDouble() ?? 0);

  /// تعديلات فاتورة (الأحدث أولاً).
  static Future<List<InvoiceEditChange>> forInvoice(DatabaseExecutor db, int invoiceId) =>
      forInvoices(db, [invoiceId]).then((m) => m[invoiceId] ?? const []);

  static Future<Map<int, List<InvoiceEditChange>>> forInvoices(
      DatabaseExecutor db, List<int> invoiceIds) async {
    final out = <int, List<InvoiceEditChange>>{};
    if (invoiceIds.isEmpty) return out;
    try {
      await ensure(db);
      for (var i = 0; i < invoiceIds.length; i += 500) {
        final chunk = invoiceIds.sublist(i, (i + 500).clamp(0, invoiceIds.length));
        final rows = await db.rawQuery(
            'SELECT * FROM invoice_edit_changes WHERE invoice_id IN (${List.filled(chunk.length, '?').join(',')}) '
            'ORDER BY edited_at DESC, id DESC',
            chunk);
        for (final r in rows) {
          out.putIfAbsent(r['invoice_id'] as int, () => []).add(InvoiceEditChange(
                productName: '${r['product_name']}',
                unit: '${r['unit'] ?? ''}',
                qtyBefore: (r['qty_before'] as num?)?.toDouble() ?? 0,
                qtyAfter: (r['qty_after'] as num?)?.toDouble() ?? 0,
                amountBefore: (r['amount_before'] as num?)?.toDouble() ?? 0,
                amountAfter: (r['amount_after'] as num?)?.toDouble() ?? 0,
                kind: '${r['kind']}',
                editedAt: DateTime.tryParse('${r['edited_at']}') ?? DateTime.now(),
                editedBy: r['edited_by'] as String?,
              ));
        }
      }
    } catch (_) {}
    return out;
  }
}
