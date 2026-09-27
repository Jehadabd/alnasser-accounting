// lib/erp/debts/receipts_service.dart
//
// 🧾 وصل القبض (مثل الإداري): مفرد أو مركّب (عدة عملاء في وصل واحد)، بعملة
// وسعر تعادل، إلى صندوق/مصرف، مع حسم على الرصيد وعمولة تحصيل ورقم مستند.
//
// لكل سطر:
//   • المبلغ المقبوض ⇒ معاملة تسديد عبر CustomerMoney (الصندوق + العملة)
//   • الحسم ⇒ معاملة تسديد منفصلة موصوفة «خصم» (قيدها على حساب الخصم المسموح)
// عمولة التحصيل ⇒ سند مصروف من الصندوق نفسه (حساب عمولات التحصيل).
//
// الوصل نفسه سجل وصفي يجمع هذه المعاملات للطباعة والمراجعة.

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart';
import '../../accounting/vouchers_service.dart';
import '../../models/supplier_payment.dart';
import '../../services/purchase_service.dart';
import '../erp_common.dart';
import 'customer_money.dart';

class ReceiptLineInput {
  ReceiptLineInput({required this.customerId, required this.customerName, this.amountFc = 0, this.discount = 0, this.note});
  final int customerId;
  final String customerName;

  /// المبلغ المقبوض بعملة الوصل.
  double amountFc;

  /// الحسم بالدينار.
  double discount;
  String? note;
}

class ReceiptResult {
  ReceiptResult(this.receiptId, this.receiptNo, this.errors);
  final int receiptId;
  final int receiptNo;
  final List<String> errors;
}

class ReceiptsService {
  /// يحفظ وصل قبض. يعيد رقم الوصل. الأسطر تُنفَّذ واحداً واحداً؛ إن فشل سطر
  /// (مثلاً عميل مقفل من جهاز آخر) يُبلَّغ عنه ولا يُلغى ما نجح قبله.
  Future<ReceiptResult> createCustomerReceipt(
    BuildContext context, {
    required DateTime date,
    required int cashBoxId,
    required String currency,
    required double fxRate,
    required List<ReceiptLineInput> lines,
    double commission = 0,
    String? docNo,
    String? notes,
  }) async {
    final valid = lines.where((l) => l.amountFc > 0 || l.discount > 0).toList();
    if (valid.isEmpty) throw ErpException('أدخل مبلغاً أو حسماً لعميل واحد على الأقل');
    if (fxRate <= 0) throw ErpException('سعر التعادل غير صحيح');
    for (final l in valid) {
      if (l.amountFc < 0 || l.discount < 0) throw ErpException('لا يجوز مبلغ سالب');
    }
    await PeriodLock.assertOpen(date);
    final isBase = currency == 'IQD';
    final db = await erpDb();

    // رأس الوصل أولاً
    final receiptNo = await db.transaction((txn) => nextDocNumber(txn, 'customer_receipts', 'receipt_no'));
    final totalBase = valid.fold<double>(0, (s, l) => s + (isBase ? l.amountFc : roundMoney(l.amountFc * fxRate)));
    final totalDisc = valid.fold<double>(0, (s, l) => s + l.discount);
    final receiptId = await db.insert('customer_receipts', {
      'receipt_no': receiptNo,
      'receipt_date': date.toIso8601String(),
      'cash_box_id': cashBoxId,
      'currency': currency,
      'fx_rate': isBase ? 1.0 : fxRate,
      'total_amount': roundMoney(totalBase),
      'total_discount': roundMoney(totalDisc),
      'commission': roundMoney(commission),
      'doc_no': docNo,
      'notes': notes,
      'is_compound': valid.length > 1 ? 1 : 0,
      'created_by': currentUserName(),
      'created_at': DateTime.now().toIso8601String(),
    });

    final errors = <String>[];
    for (final l in valid) {
      if (!context.mounted) {
        errors.add('أُغلقت الشاشة قبل إكمال الوصل');
        break;
      }
      try {
        final before = await CustomerMoney.balance(db, l.customerId);
        String? payUuid;
        String? discUuid;
        final amountBase = isBase ? roundMoney(l.amountFc) : roundMoney(l.amountFc * fxRate);
        if (amountBase > 0) {
          payUuid = await CustomerMoney.post(
            context,
            customerId: l.customerId,
            amount: -amountBase,
            kind: CustomerTxKind.cash,
            note: 'وصل قبض رقم $receiptNo${isBase ? '' : ' (${fmtQty(l.amountFc)} $currency × ${fmtQty(fxRate)})'}'
                '${l.note == null || l.note!.isEmpty ? '' : ' — ${l.note}'}',
            date: date,
            cashBoxId: cashBoxId,
            currency: currency,
            fcAmount: isBase ? null : l.amountFc,
            fxRate: isBase ? null : fxRate,
            docNo: docNo,
            receiptId: receiptId,
            refType: 'receipt',
            refId: receiptId,
          );
        }
        if (l.discount > 0) {
          if (!context.mounted) throw ErpException('أُغلقت الشاشة');
          discUuid = await CustomerMoney.post(
            context,
            customerId: l.customerId,
            amount: -roundMoney(l.discount),
            kind: CustomerTxKind.discount,
            note: 'حسم مع وصل القبض رقم $receiptNo',
            date: date,
            docNo: docNo,
            receiptId: receiptId,
            refType: 'receipt',
            refId: receiptId,
          );
        }
        final after = await CustomerMoney.balance(db, l.customerId);
        await db.insert('customer_receipt_lines', {
          'receipt_id': receiptId,
          'customer_id': l.customerId,
          'amount': amountBase,
          'discount': roundMoney(l.discount),
          'fc_amount': isBase ? null : l.amountFc,
          'pay_tx_uuid': payUuid,
          'disc_tx_uuid': discUuid,
          'balance_before': before,
          'balance_after': after,
          'note': l.note,
        });
      } catch (e) {
        errors.add('${l.customerName}: $e');
      }
    }

    // عمولة التحصيل = سند مصروف من الصندوق نفسه
    if (commission > 0) {
      try {
        final acc = await Ledger.systemAccountId(db, 'collection_commission');
        final vid = await VouchersService().create(
          type: VoucherType.expense,
          amount: roundMoney(commission),
          date: date,
          cashBoxId: cashBoxId,
          accountId: acc,
          description: 'عمولة تحصيل وصل القبض رقم $receiptNo',
          reference: docNo,
          userId: currentUserId(),
        );
        await db.update('customer_receipts', {'commission_voucher_id': vid},
            where: 'id = ?', whereArgs: [receiptId]);
      } catch (e) {
        errors.add('عمولة التحصيل: $e');
      }
    }
    // إن لم ينجح أي سطر نحذف رأس الوصل الفارغ
    final n = await db.rawQuery('SELECT COUNT(*) AS n FROM customer_receipt_lines WHERE receipt_id = ?', [receiptId]);
    if (((n.first['n'] as num?) ?? 0) == 0 && commission <= 0) {
      await db.delete('customer_receipts', where: 'id = ?', whereArgs: [receiptId]);
    }
    return ReceiptResult(receiptId, receiptNo, errors);
  }

  Future<List<Map<String, Object?>>> receipts({DateTime? from, DateTime? to, int? customerId}) async {
    final db = await erpDb();
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('r.receipt_date >= ?');
      args.add(isoDay(from));
    }
    if (to != null) {
      where.add('r.receipt_date < ?');
      args.add(isoDayAfter(to));
    }
    if (customerId != null) {
      where.add('r.id IN (SELECT receipt_id FROM customer_receipt_lines WHERE customer_id = ?)');
      args.add(customerId);
    }
    return db.rawQuery('''
      SELECT r.*, b.name AS box_name,
             (SELECT GROUP_CONCAT(c.name, '، ') FROM customer_receipt_lines l
              JOIN customers c ON c.id = l.customer_id WHERE l.receipt_id = r.id) AS customers
      FROM customer_receipts r LEFT JOIN cash_boxes b ON b.id = r.cash_box_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY r.receipt_date DESC, r.id DESC LIMIT 1000
    ''', args);
  }

  Future<List<Map<String, Object?>>> receiptLines(int receiptId) async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT l.*, c.name AS customer_name FROM customer_receipt_lines l
      LEFT JOIN customers c ON c.id = l.customer_id WHERE l.receipt_id = ? ORDER BY l.id
    ''', [receiptId]);
  }

  // ═══════════════════════════ دفعات الموردين ═══════════════════════════

  /// دفعة لمورد: نقداً من صندوق، بشيك (ورقة دفع)، أو خصم مكتسب.
  /// تمر عبر PurchaseService.registerPayment (المسار الأصلي لرصيد المورد).
  Future<void> supplierPayment({
    required int supplierId,
    required double amount,
    required String currency,
    required String method, // cash | bank | cheque | discount
    required DateTime date,
    int? cashBoxId,
    double? fxRate,
    String? docNo,
    String? notes,
  }) async {
    if (amount <= 0) throw ErpException('المبلغ يجب أن يكون أكبر من صفر');
    await PeriodLock.assertOpen(date);
    final db = await erpDb();
    final before = await db.rawQuery('SELECT COALESCE(MAX(id), 0) AS m FROM supplier_payments');
    final maxBefore = ((before.first['m'] as num?) ?? 0).toInt();
    await PurchaseService().registerPayment(SupplierPayment(
      supplierId: supplierId,
      amount: roundMoney(amount),
      currency: currency,
      paymentMethod: method,
      date: date,
      notes: [
        if (method == 'discount') 'خصم مكتسب',
        if (method == 'cheque') 'شيك/ورقة دفع',
        if (docNo != null && docNo.isNotEmpty) 'مستند $docNo',
        if (notes != null && notes.isNotEmpty) notes,
      ].join(' — '),
      createdByUserId: currentUserId(),
    ));
    // ربط الدفعة بصندوقها وسعر صرفها (للقيد)
    final after = await db.rawQuery(
        'SELECT id FROM supplier_payments WHERE id > ? AND supplier_id = ? ORDER BY id DESC LIMIT 1',
        [maxBefore, supplierId]);
    if (after.isNotEmpty && (cashBoxId != null || fxRate != null || docNo != null)) {
      await db.insert('supplier_payment_ext', {
        'payment_id': after.first['id'],
        'cash_box_id': (method == 'discount' || method == 'cheque') ? null : cashBoxId,
        'fx_rate': currency == 'IQD' ? null : fxRate,
        'doc_no': docNo,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }
}
