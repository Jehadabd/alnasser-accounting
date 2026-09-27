// lib/erp/debts/customer_money.dart
//
// 💰 البوابة الوحيدة لتغيير رصيد عميل من ميزات النسخة المحاسبية.
//
// كل تغيير يمر عبر AppProvider.addTransaction — المسار الأصلي نفسه الذي يستعمله
// «إضافة معاملة» في سجل الديون: قفل العميل، الرصيد = مجموع المعاملات، التحقق
// المزدوج، checksum، الرفع الفوري للمزامنة، وسجل التدقيق. لا نكتب في جدول
// transactions أو customers مباشرة أبداً.
//
// النوع الأصلي للمعاملة يبقى manual_payment / manual_debt (تفهمه كل الأجهزة
// والنسخ). وصفها المحاسبي (خصم، شيك، مرتجع، صندوق، عملة...) يُحفظ في
// customer_tx_ext بمفتاح transaction_uuid قبل إدراج المعاملة، فيعرف محرك
// الترحيل حسابها المقابل الصحيح.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../accounting/ledger.dart';
import '../../models/transaction.dart';
import '../../providers/app_provider.dart';
import '../erp_common.dart';

/// وصف محاسبي لمعاملة دين.
enum CustomerTxKind { cash, discount, cheque, chequeBounce, salesReturn, reconcile }

extension CustomerTxKindX on CustomerTxKind {
  String get key {
    switch (this) {
      case CustomerTxKind.cash:
        return 'cash';
      case CustomerTxKind.discount:
        return 'discount';
      case CustomerTxKind.cheque:
        return 'cheque';
      case CustomerTxKind.chequeBounce:
        return 'cheque_bounce';
      case CustomerTxKind.salesReturn:
        return 'sales_return';
      case CustomerTxKind.reconcile:
        return 'reconcile';
    }
  }
}

class CustomerMoney {
  CustomerMoney._();

  /// يضيف معاملة على العميل. [amount] بإشارة: موجب = يزيد الدين، سالب = ينقصه.
  /// يعيد transaction_uuid.
  static Future<String> post(
    BuildContext context, {
    required int customerId,
    required double amount,
    required CustomerTxKind kind,
    required String note,
    DateTime? date,
    int? cashBoxId,
    String currency = 'IQD',
    double? fcAmount,
    double? fxRate,
    String? docNo,
    int? receiptId,
    String? refType,
    int? refId,
  }) async {
    final amt = roundMoney(amount);
    if (amt.abs() < kMoneyEpsilon) throw ErpException('المبلغ صفر');
    final provider = context.read<AppProvider>();
    final when = date ?? DateTime.now();
    await PeriodLock.assertOpen(when);
    final db = await erpDb();
    final uuid = const Uuid().v4();

    // 1) الوصف أولاً: إن فشل إدراج المعاملة بعده يبقى سطر وصف بلا معاملة (لا أثر له)،
    //    أما العكس فيجعل معاملة خصم تُرحَّل مؤقتاً كتسديد نقدي.
    await db.insert(
      'customer_tx_ext',
      {
        'transaction_uuid': uuid,
        'kind': kind.key,
        'cash_box_id': cashBoxId,
        'currency': currency,
        'fc_amount': fcAmount,
        'fx_rate': fxRate,
        'doc_no': docNo,
        'receipt_id': receiptId,
        'ref_type': refType,
        'ref_id': refId,
        'note': note,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    // 2) المعاملة عبر المسار الأصلي
    final tx = DebtTransaction(
      customerId: customerId,
      amountChanged: amt,
      transactionNote: note,
      transactionType: amt > 0 ? 'manual_debt' : 'manual_payment',
      transactionDate: date == null
          ? DateTime.now()
          : DateTime(when.year, when.month, when.day, DateTime.now().hour, DateTime.now().minute,
              DateTime.now().second),
      createdAt: DateTime.now(),
      transactionUuid: uuid,
    );
    try {
      await provider.addTransaction(tx);
    } catch (e) {
      try {
        await db.delete('customer_tx_ext', where: 'transaction_uuid = ?', whereArgs: [uuid]);
      } catch (_) {}
      rethrow;
    }
    return uuid;
  }

  /// الرصيد الحالي للعميل = مجموع معاملاته الفعّالة (مصدر الحقيقة).
  static Future<double> balance(DatabaseExecutor db, int customerId) async {
    final r = await db.rawQuery(
        'SELECT COALESCE(SUM(amount_changed), 0) AS b FROM transactions '
        'WHERE customer_id = ? AND COALESCE(is_deleted, 0) = 0',
        [customerId]);
    return roundMoney(d0(r.first['b']));
  }
}
