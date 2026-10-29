// lib/services/printed_vouchers.dart
//
// 🧾 سجل السندات المطبوعة — كل سند يخرج من الطابعة يُسجَّل لحظة طباعته، وما لا يُطبع
// لا يُسجَّل (العملية المالية نفسها محفوظة في مكانها دائماً؛ هذا سجل «الورقة» فقط).
//
// لكل طباعة: نوع السند، رقمه المطبوع، مبلغه، العميل، الفاتورة (إن وُجدت)، من طبعه ومتى،
// ورقم النسخة (الأولى، ثم «نسخة 2»...)، ورمز تحقق من 6 أحرف يُطبع على الورقة.
//
// رمز التحقق = بصمة (النوع، الرقم، المبلغ، العميل) مع ملح سري عشوائي يُنشأ مرة واحدة في
// قاعدة المحل (لا في الكود — الكود منشور). من يغيّر المبلغ أو الاسم على ورقة مزوّرة لا
// يستطيع حساب رمزها؛ وشاشة التحقق تعرض المحفوظ ليُقارن بالورقة.
//
// الأنواع: سند قبض (تسديد دين / وصل قبض)، سند قبض لإضافة على فاتورة نقدية، سند صرف لمرتجع
// فاتورة نقدية، إشعار مدين، إشعار دائن، و«سند قبض — أرشيف قديم» (customer_receipt_vouchers).
//
// لا يغيّر رصيداً ولا قيداً. فشل التسجيل يوقف الطباعة (ورقة بلا سجل = ورقة لا يمكن التحقق منها).

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../accounting/ledger.dart';
import '../erp/control/control_common.dart';
import '../erp/erp_common.dart';
import 'invoice_edit_events.dart';

/// ما يُطبع على الورقة.
class PrintStamp {
  PrintStamp(this.code, this.copyNo, this.printId);
  final String code;
  final int copyNo;
  final int printId;

  /// «K7Q2XM» أو «K7Q2XM — نسخة 2»
  String get line => copyNo > 1 ? '$code — نسخة $copyNo' : code;
}

class PrintedVoucherKind {
  PrintedVoucherKind._();
  static const receipt = 'receipt';
  static const cashReceipt = 'cash_receipt';
  static const cashRefund = 'cash_refund';
  static const debitNote = 'debit_note';
  static const creditNote = 'credit_note';
  static const legacyReceipt = 'legacy_receipt';

  static String label(String k) => switch (k) {
        receipt => 'سند قبض — تسديد دين',
        cashReceipt => 'سند قبض — إضافة على فاتورة نقدية',
        cashRefund => 'سند صرف — مرتجع من فاتورة نقدية',
        debitNote => 'إشعار مدين — إضافة على فاتورة آجلة',
        creditNote => 'إشعار دائن — مرتجع من فاتورة آجلة',
        legacyReceipt => 'سند قبض — الأرشيف القديم',
        _ => k,
      };
}

/// مرجع العملية التي يمثلها السند.
class PrintedRef {
  PrintedRef._();
  static const customerReceipt = 'customer_receipt'; // customer_receipts.id
  static const editEvent = 'edit_event'; // invoice_edit_events.id
  static const legacyReceipt = 'legacy_receipt'; // customer_receipt_vouchers.id
}

/// حال العملية الآن مقارنةً بما طُبع.
enum VoucherState { ok, changed, deleted, laterEdit, unknown }

class PrintedVoucher {
  PrintedVoucher.fromRow(Map<String, Object?> r)
      : id = r['id'] as int,
        kind = '${r['kind']}',
        voucherNo = '${r['voucher_no']}',
        amount = d0(r['amount']),
        customerId = r['customer_id'] as int?,
        customerName = (r['customer_name'] as String?) ?? '',
        invoiceId = r['invoice_id'] as int?,
        invoiceNo = r['invoice_no'] as String?,
        refType = '${r['ref_type']}',
        refId = r['ref_id'] as int?,
        copyNo = ((r['copy_no'] as num?) ?? 1).toInt(),
        code = (r['verify_code'] as String?) ?? '',
        printedBy = (r['printed_by'] as String?) ?? '',
        printedAt = parseDate(r['printed_at']),
        details = _json(r['details']),
        copies = ((r['copies'] as num?) ?? 1).toInt(),
        firstPrintedAt = r['first_printed_at'] == null ? null : parseDate(r['first_printed_at']);

  static Map<String, Object?> _json(Object? v) {
    try {
      return Map<String, Object?>.from(jsonDecode('$v') as Map);
    } catch (_) {
      return const {};
    }
  }

  final int id;
  final String kind;
  final String voucherNo;
  final double amount;
  final int? customerId;
  final String customerName;
  final int? invoiceId;
  final String? invoiceNo;
  final String refType;
  final int? refId;
  final int copyNo;
  final String code;
  final String printedBy;
  final DateTime printedAt;
  final Map<String, Object?> details;

  /// عدد مرات طباعة هذا السند (في القوائم المجمّعة).
  final int copies;
  final DateTime? firstPrintedAt;

  /// السند نفسه (لا الطباعة): نوعه ومرجعه.
  String get voucherKey => '$kind|$refType|${refId ?? voucherNo}';
}

class PrintedVouchers {
  PrintedVouchers._();

  static const table = 'printed_vouchers';
  static const _saltKey = 'pv_salt';
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  static Future<String> _salt(DatabaseExecutor db) async {
    final s = await Ledger.getSetting(db, _saltKey);
    if (s != null && s.length >= 16) return s;
    final rnd = Random.secure();
    final v = base64Url.encode(List<int>.generate(24, (_) => rnd.nextInt(256)));
    await db.rawInsert('INSERT OR IGNORE INTO accounting_settings(key, value) VALUES (?, ?)', [_saltKey, v]);
    // إن سبقنا جهاز آخر نأخذ ملحه هو (INSERT OR IGNORE)
    return (await Ledger.getSetting(db, _saltKey)) ?? v;
  }

  static String _norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// رمز التحقق — دالة صافية (تُختبر وحدها).
  static String codeOf(String salt, String kind, String voucherNo, double amount, String customer) {
    final payload = '$salt|$kind|${voucherNo.trim()}|${amount.toStringAsFixed(2)}|${_norm(customer)}';
    final bytes = sha256.convert(utf8.encode(payload)).bytes;
    final b = StringBuffer();
    for (var i = 0; i < 6; i++) {
      b.write(_alphabet[bytes[i] % _alphabet.length]);
    }
    return b.toString();
  }

  /// يسجّل طباعة ويعيد ما يُطبع على الورقة. يرمي إن فشل (فتتوقف الطباعة).
  static Future<PrintStamp> register({
    required String kind,
    required String voucherNo,
    required double amount,
    int? customerId,
    required String customerName,
    int? invoiceId,
    String? invoiceNo,
    required String refType,
    int? refId,
    Map<String, Object?> details = const {},
  }) async {
    final db = await controlDb();
    return db.transaction((txn) async {
      final salt = await _salt(txn);
      final prev = await txn.rawQuery(
          'SELECT COUNT(*) AS n FROM printed_vouchers WHERE kind = ? AND ref_type = ? AND '
          '${refId == null ? 'ref_id IS NULL AND voucher_no = ?' : 'ref_id = ?'}',
          [kind, refType, refId ?? voucherNo]);
      final copy = ((prev.first['n'] as num?) ?? 0).toInt() + 1;
      final code = codeOf(salt, kind, voucherNo, round2(amount), customerName);
      final id = await txn.insert(table, {
        'kind': kind,
        'voucher_no': voucherNo.trim(),
        'amount': round2(amount),
        'customer_id': customerId,
        'customer_name': _norm(customerName),
        'invoice_id': invoiceId,
        'invoice_no': invoiceNo,
        'ref_type': refType,
        'ref_id': refId,
        'copy_no': copy,
        'verify_code': code,
        'printed_by': currentUserName(),
        'printed_at': DateTime.now().toIso8601String(),
        'details': jsonEncode(details),
      });
      return PrintStamp(code, copy, id);
    });
  }

  // ───────────────────────── مساعدات لكل نوع ─────────────────────────

  /// وصل قبض (تسديد دين، أو وصل عدة عملاء).
  static Future<PrintStamp> forCustomerReceipt(int receiptId) async {
    final db = await controlDb();
    final h = await db.query('customer_receipts', where: 'id = ?', whereArgs: [receiptId], limit: 1);
    if (h.isEmpty) throw ErpException('الوصل غير موجود — لا يُطبع');
    final r = h.first;
    final lines = await db.rawQuery('''
      SELECT l.customer_id, c.name AS customer_name, l.amount, l.discount, l.balance_before, l.balance_after
      FROM customer_receipt_lines l LEFT JOIN customers c ON c.id = l.customer_id
      WHERE l.receipt_id = ? ORDER BY l.id''', [receiptId]);
    final single = lines.length == 1 ? lines.first : null;
    final names = lines.map((l) => '${l['customer_name'] ?? ''}').where((n) => n.isNotEmpty).toList();
    return register(
      kind: PrintedVoucherKind.receipt,
      voucherNo: '${r['receipt_no']}',
      amount: d0(r['total_amount']),
      customerId: single?['customer_id'] as int?,
      customerName: single != null ? names.join() : 'عدة عملاء: ${names.join('، ')}',
      refType: PrintedRef.customerReceipt,
      refId: receiptId,
      details: {
        'date': r['receipt_date'],
        'discount': d0(r['total_discount']),
        'doc_no': r['doc_no'],
        'notes': r['notes'],
        'recorded_by': r['created_by'],
        'lines': [
          for (final l in lines)
            {
              'customer': l['customer_name'],
              'amount': d0(l['amount']),
              'discount': d0(l['discount']),
              'before': l['balance_before'],
              'after': l['balance_after'],
            }
        ],
      },
    );
  }

  /// سند تعديل بالقلم (قبض/صرف/إشعار مدين/دائن).
  static Future<PrintStamp> forEditEvent({
    required int eventId,
    required String kind,
    required String voucherNo,
    required double amount,
    required String customerName,
    int? customerId,
    required int invoiceId,
    required String invoiceNo,
    Map<String, Object?> details = const {},
  }) =>
      register(
        kind: kind,
        voucherNo: voucherNo,
        amount: amount,
        customerId: customerId,
        customerName: customerName,
        invoiceId: invoiceId,
        invoiceNo: invoiceNo,
        refType: PrintedRef.editEvent,
        refId: eventId,
        details: details,
      );

  /// سند من «أرشيف سندات القبض القديم».
  static Future<PrintStamp> forLegacyReceipt({
    required int archiveId,
    required int receiptNumber,
    required int customerId,
    required String customerName,
    required double paid,
    required double before,
    required double after,
  }) =>
      register(
        kind: PrintedVoucherKind.legacyReceipt,
        voucherNo: '$receiptNumber',
        amount: paid,
        customerId: customerId,
        customerName: customerName,
        refType: PrintedRef.legacyReceipt,
        refId: archiveId,
        details: {'before': before, 'after': after},
      );

  // ───────────────────────── القراءة ─────────────────────────

  /// السندات (كل سند سطر واحد بآخر طباعة له وعدد نسخه).
  /// [customerId]: سندات العميل (ومنها وصولات عدة عملاء هو أحدهم). [invoiceId]: سندات الفاتورة.
  /// [query]: رقم سند، أو رمز تحقق، أو اسم.
  /// [byName]: البحث بالاسم أيضاً (السجل العام فقط؛ داخل العميل/الفاتورة الاسم معروف).
  static Future<List<PrintedVoucher>> list(
      {int? customerId, int? invoiceId, String? query, bool byName = false, int limit = 500}) async {
    final db = await controlDb();
    final where = <String>[];
    final args = <Object?>[];
    if (customerId != null) {
      where.add('''(p.customer_id = ? OR (p.ref_type = 'customer_receipt' AND p.ref_id IN
                   (SELECT receipt_id FROM customer_receipt_lines WHERE customer_id = ?))
                   OR (p.invoice_id IN (SELECT id FROM invoices WHERE customer_id = ?)))''');
      args.addAll([customerId, customerId, customerId]);
    }
    if (invoiceId != null) {
      where.add('p.invoice_id = ?');
      args.add(invoiceId);
    }
    final q = (query ?? '').trim();
    if (q.isNotEmpty) {
      where.add('(p.voucher_no = ? OR p.verify_code = ? OR p.invoice_no = ?${byName ? ' OR p.customer_name LIKE ?' : ''})');
      args.addAll([q, q.toUpperCase(), q, if (byName) '%$q%']);
    }
    final rows = await db.rawQuery('''
      SELECT p.*, g.copies, g.first_printed_at FROM printed_vouchers p
      JOIN (SELECT kind, ref_type, COALESCE(CAST(ref_id AS TEXT), voucher_no) AS k,
                   MAX(id) AS last_id, COUNT(*) AS copies, MIN(printed_at) AS first_printed_at
            FROM printed_vouchers GROUP BY kind, ref_type, k) g ON g.last_id = p.id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY p.printed_at DESC LIMIT $limit''', args);
    return rows.map(PrintedVoucher.fromRow).toList();
  }

  /// كل طباعات سند واحد (الأقدم أولاً).
  static Future<List<PrintedVoucher>> printsOf(PrintedVoucher v) async {
    final db = await controlDb();
    final rows = await db.rawQuery(
        'SELECT * FROM printed_vouchers WHERE kind = ? AND ref_type = ? AND '
        '${v.refId == null ? 'ref_id IS NULL AND voucher_no = ?' : 'ref_id = ?'} ORDER BY id',
        [v.kind, v.refType, v.refId ?? v.voucherNo]);
    return rows.map(PrintedVoucher.fromRow).toList();
  }

  /// أرشيف سندات القبض القديم لعميل (ما طُبع قبل هذا السجل).
  static Future<List<Map<String, Object?>>> legacyArchive({int? customerId, String? query, bool byName = false}) async {
    final db = await controlDb();
    final t = await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='customer_receipt_vouchers'");
    if (t.isEmpty) return const [];
    final where = <String>[];
    final args = <Object?>[];
    if (customerId != null) {
      where.add('customer_id = ?');
      args.add(customerId);
    }
    final q = (query ?? '').trim();
    if (q.isNotEmpty) {
      where.add('(CAST(receipt_number AS TEXT) = ?${byName ? ' OR customer_name LIKE ?' : ''})');
      args.addAll([q, if (byName) '%$q%']);
    }
    return db.rawQuery(
        'SELECT * FROM customer_receipt_vouchers ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
        'ORDER BY created_at DESC LIMIT 500',
        args);
  }

  /// حال العملية الآن مقارنةً بالمطبوع.
  static Future<(VoucherState, String)> stateOf(PrintedVoucher v) async {
    final db = await controlDb();
    try {
      switch (v.refType) {
        case PrintedRef.customerReceipt:
          final r = await db.query('customer_receipts',
              columns: ['total_amount'], where: 'id = ?', whereArgs: [v.refId], limit: 1);
          if (r.isEmpty) return (VoucherState.deleted, 'الوصل حُذف من سجل الوصولات بعد طباعته');
          final deleted = await db.rawQuery('''
            SELECT COUNT(*) AS n FROM customer_receipt_lines l
            JOIN transactions t ON t.transaction_uuid = l.pay_tx_uuid
            WHERE l.receipt_id = ? AND COALESCE(t.is_deleted, 0) = 1''', [v.refId]);
          if (((deleted.first['n'] as num?) ?? 0) > 0) {
            return (VoucherState.deleted, 'حركة التسديد في سجل الديون حُذفت بعد طباعة السند');
          }
          final now = d0(r.first['total_amount']);
          if ((now - v.amount).abs() >= 0.5) {
            return (VoucherState.changed, 'مبلغ الوصل الآن ${fmtQty(now)} لا ${fmtQty(v.amount)} كما طُبع');
          }
          return (VoucherState.ok, 'الوصل موجود بالمبلغ نفسه');
        case PrintedRef.editEvent:
          final e = await InvoiceEditEvents.byId(db, v.refId ?? -1);
          if (e == null) return (VoucherState.deleted, 'حدث التعديل غير موجود');
          final inv = await db.query('invoices',
              columns: ['is_deleted'], where: 'id = ?', whereArgs: [e['invoice_id']], limit: 1);
          if (inv.isEmpty || ((inv.first['is_deleted'] as num?) ?? 0) == 1) {
            return (VoucherState.deleted, 'الفاتورة حُذفت بعد طباعة السند');
          }
          final amt = (d0(e['total_after']) - d0(e['total_before'])).abs();
          if ((amt - v.amount).abs() >= 0.5) {
            return (VoucherState.changed, 'مبلغ التعديل في السجل ${fmtQty(amt)} لا ${fmtQty(v.amount)} كما طُبع');
          }
          final later = await db.rawQuery(
              'SELECT COUNT(*) AS n FROM ${InvoiceEditEvents.table} WHERE invoice_id = ? AND id > ?', [e['invoice_id'], v.refId]);
          final n = ((later.first['n'] as num?) ?? 0).toInt();
          if (n > 0) return (VoucherState.laterEdit, 'السند صحيح، لكن الفاتورة عُدّلت $n مرة بعده');
          return (VoucherState.ok, 'التعديل موجود بالمبلغ نفسه');
        case PrintedRef.legacyReceipt:
          final r = await db.query('customer_receipt_vouchers',
              columns: ['paid_amount'], where: 'id = ?', whereArgs: [v.refId], limit: 1);
          if (r.isEmpty) return (VoucherState.deleted, 'السند حُذف من الأرشيف القديم');
          return (VoucherState.unknown, 'من الأرشيف القديم: غير مربوط بحركة التسديد — طابِق المبلغ مع كشف الحساب');
      }
    } catch (e) {
      return (VoucherState.unknown, 'تعذّر الفحص: $e');
    }
    return (VoucherState.unknown, '');
  }
}
