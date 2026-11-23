// lib/erp/sales/invoice_returns.dart
//
// ↩️ مرتجعات المبيعات المربوطة بفاتورة — كما في أنظمة ERP العالمية:
//   • الفاتورة المُرحَّلة تبقى كما صدرت (قطعة واحدة تبقى قطعة واحدة)، والمرتجع مستند مستقل
//     (إشعار دائن) مربوط بها. صافي الفاتورة = المبيع − المرتجع، ويظهر عليها.
//   • 🛡️ حارس: فاتورة عليها مرتجع مُرحَّل لا تُحذف، ولا يتغيّر عميلها، ولا تُنقص كمية مادة
//     فيها تحت ما أُرجع منها — وإلا عادت البضاعة للمخزن مرتين ونزل دين العميل مرتين.
//     الحل الصحيح: ألغِ المرتجع أولاً (من «سجل المرتجعات») ثم عدّل الفاتورة.
// قراءة فقط هنا (لا يغيّر شيئاً) — يُستدعى من حفظ الفاتورة وحذفها ومن شاشات العرض.

import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

double _d(Object? v) => (v as num?)?.toDouble() ?? 0.0;

/// سطر من مرتجع: مادة وكميتها.
class ReturnLine {
  const ReturnLine(this.productId, this.name, this.qty, this.saleType, this.baseQty, this.total);
  final int productId;
  final String name;
  final double qty;
  final String saleType;
  final double baseQty;
  final double total;
}

/// مستند مرتجع مبيعات مربوط بفاتورة.
class InvoiceReturnDoc {
  InvoiceReturnDoc({
    required this.id,
    required this.no,
    required this.date,
    required this.total,
    required this.refundMode,
    required this.cashPart,
    required this.status,
    required this.notes,
    required this.lines,
  });
  final int id;
  final String no;
  final DateTime? date;
  final double total;
  final String refundMode; // cash | credit | mixed
  final double cashPart;
  final String status; // posted | void
  final String notes;
  final List<ReturnLine> lines;

  bool get posted => status == 'posted';
  bool get warranty => notes.startsWith('ضمان');

  /// كم رُدّ نقداً وكم نزل من دين العميل.
  double get cash => refundMode == 'cash' ? total : (refundMode == 'mixed' ? cashPart : 0.0);
  double get credit => total - cash;

  String get modeArabic => switch (refundMode) {
        'cash' => 'رُدّ نقداً',
        'credit' => 'نزل من دين العميل',
        _ => 'نقداً ومن الدين',
      };
}

class InvoiceReturns {
  InvoiceReturns._();

  static Future<bool> _ready(DatabaseExecutor d) async {
    final t = await d.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('sales_returns', 'sales_return_items')");
    return t.length == 2;
  }

  /// كل مستندات المرتجع على الفاتورة (الأحدث أولاً). [productId] لمادة واحدة فقط.
  static Future<List<InvoiceReturnDoc>> forInvoice(DatabaseExecutor d, int invoiceId,
      {int? productId, bool includeVoid = false}) async {
    if (!await _ready(d)) return const [];
    final heads = await d.rawQuery('''
      SELECT r.* FROM sales_returns r
      WHERE r.original_invoice_id = ? ${includeVoid ? '' : "AND r.status = 'posted'"}
        ${productId == null ? '' : 'AND EXISTS (SELECT 1 FROM sales_return_items i WHERE i.return_id = r.id AND i.product_id = ?)'}
      ORDER BY r.return_date DESC, r.id DESC''', [invoiceId, if (productId != null) productId]);
    final out = <InvoiceReturnDoc>[];
    for (final h in heads) {
      final id = h['id'] as int;
      final items = await d.query('sales_return_items', where: 'return_id = ?', whereArgs: [id], orderBy: 'id');
      out.add(InvoiceReturnDoc(
        id: id,
        no: '${h['return_no'] ?? id}',
        date: DateTime.tryParse('${h['return_date'] ?? ''}'),
        total: _d(h['total']),
        refundMode: '${h['refund_mode'] ?? 'credit'}',
        cashPart: _d(h['cash_amount']),
        status: '${h['status'] ?? 'posted'}',
        notes: '${h['notes'] ?? ''}'.trim(),
        lines: [
          for (final i in items)
            ReturnLine(i['product_id'] as int, '${i['product_name'] ?? ''}', _d(i['quantity']), '${i['sale_type'] ?? ''}',
                _d(i['base_qty']), _d(i['total'])),
        ],
      ));
    }
    return out;
  }

  /// المُرجَع المُرحَّل من كل مادة (بالوحدة الأساسية).
  static Future<Map<int, double>> returnedBase(DatabaseExecutor d, int invoiceId) async {
    if (!await _ready(d)) return const {};
    final rows = await d.rawQuery('''
      SELECT i.product_id AS pid, SUM(i.base_qty) AS q, MAX(i.product_name) AS n
      FROM sales_return_items i JOIN sales_returns r ON r.id = i.return_id
      WHERE r.original_invoice_id = ? AND r.status = 'posted' GROUP BY i.product_id''', [invoiceId]);
    return {for (final r in rows) if (_d(r['q']) > 1e-9) r['pid'] as int: _d(r['q'])};
  }

  static Future<String> _names(DatabaseExecutor d, int invoiceId) async {
    final docs = await forInvoice(d, invoiceId);
    return docs.map((x) => 'رقم ${x.no}').join('، ');
  }

  /// 🛡️ هل يُسمح بحذف الفاتورة أو إلغائها؟ null = مسموح.
  static Future<String?> deleteBlockReason(DatabaseExecutor d, int invoiceId) async {
    final ret = await returnedBase(d, invoiceId);
    if (ret.isEmpty) return null;
    return 'على هذه الفاتورة مرتجع مبيعات مُرحَّل (${await _names(d, invoiceId)}).\n'
        'لا تُحذف الفاتورة قبل إلغاء المرتجع — وإلا عادت البضاعة للمخزن مرتين ونزل دين العميل مرتين.\n'
        'الحل: المبيعات ← سجل المرتجعات ← ألغِ المرتجع، ثم احذف الفاتورة.';
  }

  /// 🛡️ هل يُسمح بهذا التعديل؟ [newBase]: الكمية الجديدة لكل مادة بالأساسية. null = مسموح.
  static Future<String?> editBlockReason(
    DatabaseExecutor d,
    int invoiceId, {
    required Map<int, double> newBase,
    required bool customerChanged,
    Map<int, String> names = const {},
  }) async {
    final ret = await returnedBase(d, invoiceId);
    if (ret.isEmpty) return null;
    final docs = await _names(d, invoiceId);
    if (customerChanged) {
      return 'على هذه الفاتورة مرتجع مبيعات مُرحَّل ($docs) سُجّل على حساب العميل نفسه.\n'
          'لا يتغيّر عميل الفاتورة وعليها مرتجع — ألغِ المرتجع أولاً من «سجل المرتجعات».';
    }
    for (final e in ret.entries) {
      final now = newBase[e.key] ?? 0;
      if (now + 1e-6 < e.value) {
        final n = names[e.key] ?? 'مادة';
        String q(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
        return 'لا يمكن إنقاص «$n» في الفاتورة إلى ${q(now)} — أُرجع منها ${q(e.value)} بمرتجع مبيعات ($docs).\n'
            'الفاتورة تبقى كما بيعت، والمرتجع مستند مستقل يُنقص صافيها (هكذا تعمل أنظمة ERP).\n'
            'إن كان المرتجع خطأً: ألغِه من «سجل المرتجعات» ثم عدّل الفاتورة.';
      }
    }
    return null;
  }

  /// الكمية الأساسية لكل مادة في أسطر فاتورة (مادة بـ sync_uuid أو بالاسم).
  static Future<({Map<int, double> base, Map<int, String> names})> baseOfLines(
      DatabaseExecutor d, Iterable<({String? syncUuid, String name, double? large, double? single, double? per})> lines) async {
    final base = <int, double>{};
    final names = <int, String>{};
    for (final l in lines) {
      final rows = (l.syncUuid ?? '').isNotEmpty
          ? await d.query('products', columns: ['id', 'name'], where: 'sync_uuid = ?', whereArgs: [l.syncUuid], limit: 1)
          : await d.query('products', columns: ['id', 'name'], where: 'name = ?', whereArgs: [l.name], limit: 1);
      if (rows.isEmpty) continue;
      final pid = rows.first['id'] as int;
      final large = l.large ?? 0;
      final q = large > 0 ? large * ((l.per ?? 0) > 0 ? l.per! : 1) : (l.single ?? 0);
      base[pid] = (base[pid] ?? 0) + q;
      names[pid] = l.name;
    }
    return (base: base, names: names);
  }
}
