// lib/erp/sales/return_tx_ref.dart
//
// ↩️ ربط معاملة دين بمستند «مرتجع مبيعات» للعرض في سجل الديون — قراءة فقط.
//
// المرتجع على الحساب يُسجَّل بالمسار الأصلي (CustomerMoney): نوع المعاملة يبقى
// manual_payment (تفهمه كل الأجهزة والنسخ)، ووصفها المحاسبي «sales_return» في
// customer_tx_ext — ولذلك لا تحسبه تقارير النقد قبضاً، ويُرحَّل مرتجعاً لا تسديداً.
// كان سجل الديون يعرضه «تسديد دين يدوي». هنا نعرّفه للعرض: «مرتجع مبيعات — من
// فاتورة رقم … • سند مرتجع رقم …». لا شيء هنا يكتب أو يغيّر مالاً.

import 'package:sqflite/sqflite.dart';

class ReturnTxRef {
  const ReturnTxRef({
    required this.returnNo,
    this.returnId,
    this.invoiceId,
    this.invoiceNumber,
    this.isVoid = false,
  });

  /// رقم سند المرتجع
  final String returnNo;
  final int? returnId;

  /// الفاتورة الأصلية (null = مرتجع بلا فاتورة)
  final int? invoiceId;
  final String? invoiceNumber;

  /// معاملة إلغاء مرتجع (يعود المبلغ ديناً)
  final bool isVoid;

  String get title => isVoid ? 'إلغاء مرتجع مبيعات' : 'مرتجع مبيعات';

  /// «من فاتورة رقم 1202611042 • سند مرتجع رقم 3»
  String get details => [
        if ((invoiceNumber ?? '').trim().isNotEmpty) 'من فاتورة رقم ${invoiceNumber!.trim()}',
        'سند مرتجع رقم $returnNo',
      ].join(' • ');

  static final _noteRe = RegExp(r'^\s*(إلغاء\s+)?مرتجع مبيعات رقم\s+(\S+?)(?:\s+من فاتورة\s+(\S+))?(?:\s|$)');

  /// احتياطي من نص الملاحظة (معاملة وصلت بلا وصفها المحاسبي، أو قديمة).
  /// الصيغة كما يكتبها SalesReturnService: «مرتجع مبيعات رقم 3 من فاتورة 1202611042»
  /// و«إلغاء مرتجع مبيعات رقم 3 — السبب».
  static ReturnTxRef? fromNote(String? note) {
    final m = _noteRe.firstMatch(note ?? '');
    if (m == null) return null;
    final inv = m.group(3);
    return ReturnTxRef(
      returnNo: m.group(2)!,
      invoiceNumber: inv,
      invoiceId: inv != null && inv.startsWith('#') ? int.tryParse(inv.substring(1)) : null,
      isVoid: m.group(1) != null,
    );
  }

  /// مرتجعات معاملات [uuids] من وصفها المحاسبي ومستند المرتجع (رقمه وفاتورته).
  /// أي خطأ (قاعدة بلا هذه الجداول) ⇒ خريطة فارغة.
  static Future<Map<String, ReturnTxRef>> forUuids(DatabaseExecutor db, Iterable<String> uuids) async {
    final list = uuids.where((u) => u.isNotEmpty).toSet().toList();
    if (list.isEmpty) return const {};
    final out = <String, ReturnTxRef>{};
    try {
      for (var i = 0; i < list.length; i += 400) {
        final chunk = list.sublist(i, i + 400 > list.length ? list.length : i + 400);
        final ph = List.filled(chunk.length, '?').join(',');
        final rows = await db.rawQuery('''
          SELECT x.transaction_uuid AS u, x.ref_type AS t, r.id AS rid, r.return_no AS no,
                 r.original_invoice_id AS inv, i.invoice_number AS inv_no
          FROM customer_tx_ext x
          JOIN sales_returns r ON r.id = x.ref_id
          LEFT JOIN invoices i ON i.id = r.original_invoice_id
          WHERE x.ref_type IN ('sales_return', 'sales_return_void') AND x.transaction_uuid IN ($ph)
        ''', chunk);
        for (final r in rows) {
          final invId = (r['inv'] as num?)?.toInt();
          final invNo = (r['inv_no'] as String?)?.trim();
          out['${r['u']}'] = ReturnTxRef(
            returnNo: '${r['no']}',
            returnId: (r['rid'] as num?)?.toInt(),
            invoiceId: invId,
            invoiceNumber: invNo != null && invNo.isNotEmpty ? invNo : (invId == null ? null : '#$invId'),
            isVoid: r['t'] == 'sales_return_void',
          );
        }
      }
    } catch (_) {
      return const {};
    }
    return out;
  }
}
