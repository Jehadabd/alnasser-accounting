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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;
import 'package:uuid/uuid.dart';

import '../../accounting/ledger.dart';
import '../../accounting/vouchers_service.dart';
import '../../models/supplier_payment.dart';
import '../../providers/app_provider.dart';
import '../../services/purchase_service.dart';
import '../activity/activity_log.dart';
import '../erp_common.dart';
import 'customer_money.dart';
import '../../utils/iqd.dart'; // 💵

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
    BuildContext? context, {
    // بلا شاشة (الاختبار على الكود الحقيقي): المزوّد يُمرَّر صراحةً
    AppProvider? provider,
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
    if (valid.isEmpty) throw ErpException('أدخل مبلغاً أو خصماً لعميل واحد على الأقل');
    if (fxRate <= 0) throw ErpException('سعر التعادل غير صحيح');
    for (final l in valid) {
      if (l.amountFc < 0 || l.discount < 0) throw ErpException('لا يجوز مبلغ سالب');
    }
    await PeriodLock.assertOpen(date);
    final isBase = currency == 'IQD';
    final db = await erpDb();

    // 💵 مبلغ كل سطر وخصمه بالدينار الصحيح قبل كتابة أي شيء (كما يقرّبهما
    //    CustomerMoney.post): التسديد والخصم ينقصان الدين، والنصف لصالح المحل،
    //    والكسر يُقبل فقط إن صفّى كسراً قديماً في رصيد العميل.
    final payOf = <ReceiptLineInput, double>{};
    final discOf = <ReceiptLineInput, double>{};
    for (final l in valid) {
      final b = await CustomerMoney.balance(db, l.customerId);
      final raw = isBase ? roundMoney(l.amountFc) : roundMoney(l.amountFc * fxRate);
      final pay = raw > 0 ? -Iqd.ledgerAmount(-raw, b) : 0.0;
      final disc = l.discount > 0 ? -Iqd.ledgerAmount(-roundMoney(l.discount), b - pay) : 0.0;
      payOf[l] = pay;
      discOf[l] = disc;
    }
    if (valid.every((l) => payOf[l]! <= 0 && discOf[l]! <= 0)) {
      throw ErpException('المبلغ أقل من نصف دينار');
    }

    // 🧾 خطة الوصل تُحفظ مع رأسه قبل أي معاملة: لكل سطر مبلغه وخصمه ومعرّفا معاملتيه
    //    محجوزين مسبقاً. إن انقطع التسجيل في منتصفه (انطفاء، إغلاق) يبقى الوصل
    //    «in_progress» ويُعرض للمستخدم: يكمله (الأسطر الناقصة فقط، بلا تكرار) أو يبقي ما
    //    سُجّل. لا يُضاف ولا يُحذف شيء مالي وحده.
    final plan = <_PlannedLine>[
      for (final l in valid)
        _PlannedLine(
          customerId: l.customerId,
          customerName: l.customerName,
          pay: payOf[l]!,
          discount: discOf[l]!,
          fcAmount: isBase ? null : l.amountFc,
          note: l.note,
          payUuid: payOf[l]! > 0 ? const Uuid().v4() : null,
          discUuid: discOf[l]! > 0 ? const Uuid().v4() : null,
        ),
    ];

    // رأس الوصل أولاً — الرقم يُحسب ويُحجز في المعاملة نفسها (لا رقم مكرر لو حُفظ وصلان معاً)
    final totalBase = plan.fold<double>(0, (s, l) => s + l.pay);
    final totalDisc = plan.fold<double>(0, (s, l) => s + l.discount);
    late final int receiptNo;
    final receiptId = await db.transaction((txn) async {
      receiptNo = await nextDocNumber(txn, 'customer_receipts', 'receipt_no');
      return txn.insert('customer_receipts', {
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
      'status': _inProgress,
      'plan_json': jsonEncode([for (final l in plan) l.toJson()]),
      });
    });

    final errors = await _postPlanned(context,
        provider: provider,
        receiptId: receiptId,
        receiptNo: receiptNo,
        date: date,
        cashBoxId: cashBoxId,
        currency: currency,
        fxRate: fxRate,
        docNo: docNo,
        commission: commission,
        plan: plan);
    final n = await _finalize(db, receiptId, errors.isEmpty ? _complete : _partial, commission: commission);
    ActivityLog.log('إنشاء', 'وصل قبض', 'وصل قبض رقم $receiptNo — $n عميل${errors.isEmpty ? '' : ' (${errors.length} خطأ)'}');
    return ReceiptResult(receiptId, receiptNo, errors);
  }

  static const _inProgress = 'in_progress';
  static const _complete = 'complete';
  static const _partial = 'partial';

  /// 🧪 للاختبار فقط: «انقطاع» بعد هذا العدد من الأسطر (يرمي خارج معالجة الأخطاء فيبقى
  /// الوصل in_progress كما لو انطفأ الحاسوب).
  @visibleForTesting
  static int? debugStopAfterLines;

  /// 🧪 للاختبار فقط: «انقطاع» داخل السطر رقم [n] (من صفر) بعد تسجيل تسديده وقبل خصمه ووصفه.
  @visibleForTesting
  static int? debugStopInsideLine;

  /// يسجّل أسطر الخطة التي لم تُسجَّل بعد (المعرّفات المحجوزة تمنع التكرار) ثم العمولة.
  Future<List<String>> _postPlanned(
    BuildContext? context, {
    AppProvider? provider,
    required int receiptId,
    required int receiptNo,
    required DateTime date,
    required int cashBoxId,
    required String currency,
    required double fxRate,
    required String? docNo,
    required double commission,
    required List<_PlannedLine> plan,
    bool resuming = false,
  }) async {
    final db = await erpDb();
    final isBase = currency == 'IQD';
    final errors = <String>[];
    var done = 0;
    for (final l in plan) {
      if (debugStopAfterLines != null && done >= debugStopAfterLines!) {
        throw const SimulatedReceiptCrash();
      }
      done++;
      if (context != null && !context.mounted) {
        errors.add('أُغلقت الشاشة قبل إكمال الوصل');
        break;
      }
      // إكمال وصل منقطع: سطر سُجّل وصفه من قبل لا يُعاد، وسطر بلا مبلغ (أقل من نصف دينار)
      // لا شيء مالياً فيه. الهوية بمعرّفات المعاملات المحجوزة لا بالعميل (قد يتكرر العميل).
      if (resuming && (l.uuids.isEmpty || await _lineRecorded(db, receiptId, l))) continue;
      try {
        final before = await CustomerMoney.balance(db, l.customerId);
        if (context != null && !context.mounted) {
          errors.add('أُغلقت الشاشة قبل إكمال الوصل');
          break;
        }
        // ما سُجّل من هذا السطر قبل الانقطاع يُعاد إلى «قبل» (الرصيد قبل السطر كله)
        final already = await _postedSum(db, [l.payUuid, l.discUuid]);
        String? payUuid;
        String? discUuid;
        if (l.pay > 0) {
          payUuid = await CustomerMoney.post(
            context,
            provider: provider,
            customerId: l.customerId,
            amount: -l.pay,
            kind: CustomerTxKind.cash,
            note: 'وصل قبض رقم $receiptNo${isBase ? '' : ' (${fmtQty(l.fcAmount ?? 0)} $currency × ${fmtQty(fxRate)})'}'
                '${l.note == null || l.note!.isEmpty ? '' : ' — ${l.note}'}',
            date: date,
            cashBoxId: cashBoxId,
            currency: currency,
            fcAmount: isBase ? null : l.fcAmount,
            fxRate: isBase ? null : fxRate,
            docNo: docNo,
            receiptId: receiptId,
            refType: 'receipt',
            refId: receiptId,
            presetUuid: l.payUuid,
          );
        }
        if (debugStopInsideLine != null && debugStopInsideLine == done - 1) {
          throw const SimulatedReceiptCrash();
        }
        if (l.discount > 0) {
          if (context != null && !context.mounted) throw ErpException('أُغلقت الشاشة');
          discUuid = await CustomerMoney.post(
            context,
            provider: provider,
            customerId: l.customerId,
            amount: -l.discount,
            kind: CustomerTxKind.discount,
            note: 'خصم مع وصل القبض رقم $receiptNo',
            date: date,
            docNo: docNo,
            receiptId: receiptId,
            refType: 'receipt',
            refId: receiptId,
            presetUuid: l.discUuid,
          );
        }
        final after = await CustomerMoney.balance(db, l.customerId);
        await db.insert('customer_receipt_lines', {
          'receipt_id': receiptId,
          'customer_id': l.customerId,
          'amount': l.pay,
          'discount': l.discount,
          'fc_amount': l.fcAmount,
          'pay_tx_uuid': payUuid,
          'disc_tx_uuid': discUuid,
          'balance_before': roundMoney(before + already), // already موجب = ما نقص من الدين قبل الانقطاع
          'balance_after': after,
          'note': l.note,
        });
      } on SimulatedReceiptCrash {
        rethrow;
      } catch (e) {
        errors.add('${l.customerName}: $e');
      }
    }

    // عمولة التحصيل = سند مصروف من الصندوق نفسه (مرة واحدة)
    if (commission > 0) {
      final h = await db.query('customer_receipts',
          columns: ['commission_voucher_id'], where: 'id = ?', whereArgs: [receiptId], limit: 1);
      if (h.isNotEmpty && h.first['commission_voucher_id'] == null) {
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
    }
    return errors;
  }

  /// هل لسطر الخطة وصف مسجّل في الوصل؟ (بمعرّفَي معاملتيه المحجوزين)
  static Future<bool> _lineRecorded(DatabaseExecutor db, int receiptId, _PlannedLine l) async {
    final ids = l.uuids;
    final ph = List.filled(ids.length, '?').join(',');
    final r = await db.rawQuery(
        'SELECT 1 FROM customer_receipt_lines WHERE receipt_id = ? '
        'AND (pay_tx_uuid IN ($ph) OR disc_tx_uuid IN ($ph)) LIMIT 1',
        [receiptId, ...ids, ...ids]);
    return r.isNotEmpty;
  }

  /// مجموع ما سُجّل فعلاً من هذه المعرّفات (معاملات حيّة) — موجب = ما نقص من الدين.
  static Future<double> _postedSum(DatabaseExecutor db, List<String?> uuids) async {
    final ids = uuids.whereType<String>().toList();
    if (ids.isEmpty) return 0;
    final r = await db.rawQuery(
        'SELECT COALESCE(SUM(amount_changed), 0) AS s FROM transactions '
        'WHERE COALESCE(is_deleted, 0) = 0 AND transaction_uuid IN (${List.filled(ids.length, '?').join(',')})',
        ids);
    return -((r.first['s'] as num?)?.toDouble() ?? 0.0);
  }

  /// رأس الوصل يصف ما سُجّل فعلاً: المجاميع من أسطره، والعمولة صفر إن لم يُنشأ سندها.
  /// وصل بلا سطر ولا عمولة يُحذف رأسه (لا شيء مالي فيه). يعيد عدد الأسطر.
  Future<int> _finalize(DatabaseExecutor db, int receiptId, String status, {required double commission}) async {
    final t = await db.rawQuery(
        'SELECT COUNT(*) AS n, COALESCE(SUM(amount), 0) AS a, COALESCE(SUM(discount), 0) AS d '
        'FROM customer_receipt_lines WHERE receipt_id = ?',
        [receiptId]);
    final n = ((t.first['n'] as num?) ?? 0).toInt();
    final h = await db.query('customer_receipts',
        columns: ['commission_voucher_id'], where: 'id = ?', whereArgs: [receiptId], limit: 1);
    final hasCommission = h.isNotEmpty && h.first['commission_voucher_id'] != null;
    if (n == 0 && !hasCommission) {
      await db.delete('customer_receipts', where: 'id = ?', whereArgs: [receiptId]);
      return 0;
    }
    await db.update(
        'customer_receipts',
        {
          'total_amount': roundMoney((t.first['a'] as num?)?.toDouble() ?? 0),
          'total_discount': roundMoney((t.first['d'] as num?)?.toDouble() ?? 0),
          if (!hasCommission) 'commission': 0.0,
          'status': status,
        },
        where: 'id = ?',
        whereArgs: [receiptId]);
    return n;
  }

  // ══════════════════════ 🧾 وصل انقطع في منتصفه ══════════════════════

  /// وصولات بقيت «in_progress»: انقطع تسجيلها (انطفاء/إغلاق) — تُعرض للمستخدم ليقرر.
  Future<List<IncompleteReceipt>> incompleteReceipts() async {
    final db = await erpDb();
    final heads = await db.query('customer_receipts', where: 'status = ?', whereArgs: [_inProgress], orderBy: 'id');
    final out = <IncompleteReceipt>[];
    for (final h in heads) {
      final plan = _PlannedLine.listFrom(h['plan_json'] as String?);
      var postedLines = 0;
      var postedSum = 0.0;
      var missingSum = 0.0;
      for (final l in plan) {
        final got = await _postedSum(db, [l.payUuid, l.discUuid]);
        final want = l.pay + l.discount;
        if ((got - want).abs() < 0.005) {
          postedLines++;
        } else {
          missingSum += want - got;
        }
        postedSum += got;
      }
      out.add(IncompleteReceipt(
        receiptId: h['id'] as int,
        receiptNo: (h['receipt_no'] as num).toInt(),
        date: DateTime.tryParse('${h['receipt_date']}') ?? DateTime.now(),
        plannedLines: plan.length,
        postedLines: postedLines,
        postedAmount: roundMoney(postedSum),
        missingAmount: roundMoney(missingSum),
        customers: [for (final l in plan) l.customerName],
      ));
    }
    return out;
  }

  /// «أكمل الوصل»: يسجّل الأسطر الناقصة فقط (المعرّفات المحجوزة تمنع التكرار) ثم العمولة.
  Future<ReceiptResult> completeIncomplete(BuildContext? context, int receiptId, {AppProvider? provider}) async {
    final db = await erpDb();
    final h = (await db.query('customer_receipts', where: 'id = ?', whereArgs: [receiptId], limit: 1)).firstOrNull;
    if (h == null || h['status'] != _inProgress) throw ErpException('الوصل ليس منقطعاً');
    final plan = _PlannedLine.listFrom(h['plan_json'] as String?);
    final no = (h['receipt_no'] as num).toInt();
    final commission = (h['commission'] as num?)?.toDouble() ?? 0;
    final errors = await _postPlanned(context,
        provider: provider,
        receiptId: receiptId,
        receiptNo: no,
        date: DateTime.parse('${h['receipt_date']}'),
        cashBoxId: (h['cash_box_id'] as num).toInt(),
        currency: '${h['currency']}',
        fxRate: (h['fx_rate'] as num?)?.toDouble() ?? 1,
        docNo: h['doc_no'] as String?,
        commission: commission,
        plan: plan,
        resuming: true);
    final n = await _finalize(db, receiptId, errors.isEmpty ? _complete : _partial, commission: commission);
    ActivityLog.log('إكمال', 'وصل قبض', 'أُكمل وصل القبض رقم $no بعد انقطاع — $n عميل${errors.isEmpty ? '' : ' (${errors.length} خطأ)'}');
    return ReceiptResult(receiptId, no, errors);
  }

  /// «أبقِ ما سُجّل»: لا معاملة تُضاف ولا تُحذف. ما سُجّل من الخطة يُوصف بأسطره، ويُصحَّح
  /// رأس الوصل ليطابقه (ناقص)، والعمولة تُلغى إن لم يُنشأ سندها.
  Future<void> keepPostedOnly(int receiptId) async {
    final db = await erpDb();
    final h = (await db.query('customer_receipts', where: 'id = ?', whereArgs: [receiptId], limit: 1)).firstOrNull;
    if (h == null || h['status'] != _inProgress) throw ErpException('الوصل ليس منقطعاً');
    final plan = _PlannedLine.listFrom(h['plan_json'] as String?);
    for (final l in plan) {
      if (l.uuids.isEmpty || await _lineRecorded(db, receiptId, l)) continue;
      final pay = await _postedSum(db, [l.payUuid]);
      final disc = await _postedSum(db, [l.discUuid]);
      if (pay.abs() < 0.005 && disc.abs() < 0.005) continue;
      final after = await CustomerMoney.balance(db, l.customerId);
      await db.insert('customer_receipt_lines', {
        'receipt_id': receiptId,
        'customer_id': l.customerId,
        'amount': roundMoney(pay),
        'discount': roundMoney(disc),
        'fc_amount': l.fcAmount,
        'pay_tx_uuid': pay.abs() < 0.005 ? null : l.payUuid,
        'disc_tx_uuid': disc.abs() < 0.005 ? null : l.discUuid,
        'balance_before': roundMoney(after + pay + disc),
        'balance_after': after,
        'note': l.note,
      });
    }
    final n = await _finalize(db, receiptId, _partial, commission: 0);
    ActivityLog.log('إنهاء', 'وصل قبض', 'وصل القبض رقم ${h['receipt_no']} أُبقي على ما سُجّل قبل الانقطاع — $n عميل');
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
    // المعرّف يعود من التسجيل نفسه (كان يُخمَّن بـ «أكبر معرّف بعد» — يخطئ لو سجّلت طرفية أخرى دفعة في اللحظة نفسها)
    final paymentId = await PurchaseService().registerPayment(SupplierPayment(
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
    if (cashBoxId != null || fxRate != null || docNo != null) {
      await db.insert('supplier_payment_ext', {
        'payment_id': paymentId,
        'cash_box_id': (method == 'discount' || method == 'cheque') ? null : cashBoxId,
        'fx_rate': currency == 'IQD' ? null : fxRate,
        'doc_no': docNo,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    ActivityLog.log('إنشاء', 'دفعة لمورد', 'دفعة للمورد #$supplierId — $amount $currency ($method)');
  }
}

/// 🧪 «انقطاع» مصطنع في منتصف وصل (ReceiptsService.debugStopAfterLines).
class SimulatedReceiptCrash implements Exception {
  const SimulatedReceiptCrash();
  @override
  String toString() => 'انقطاع مصطنع في منتصف الوصل';
}

/// وصل انقطع تسجيله في منتصفه — ينتظر قرار المستخدم.
class IncompleteReceipt {
  IncompleteReceipt({
    required this.receiptId,
    required this.receiptNo,
    required this.date,
    required this.plannedLines,
    required this.postedLines,
    required this.postedAmount,
    required this.missingAmount,
    required this.customers,
  });
  final int receiptId;
  final int receiptNo;
  final DateTime date;
  final int plannedLines;
  final int postedLines;

  /// ما سُجّل فعلاً (تسديد + خصم) وما بقي من الخطة.
  final double postedAmount;
  final double missingAmount;
  final List<String> customers;
}

class _PlannedLine {
  _PlannedLine({
    required this.customerId,
    required this.customerName,
    required this.pay,
    required this.discount,
    required this.fcAmount,
    required this.note,
    required this.payUuid,
    required this.discUuid,
  });
  final int customerId;
  final String customerName;
  final double pay;
  final double discount;
  final double? fcAmount;
  final String? note;
  final String? payUuid;
  final String? discUuid;

  /// معرّفا معاملتي السطر المحجوزان (تسديد/خصم) — فارغ لسطر بلا مبلغ.
  List<String> get uuids => [payUuid, discUuid].whereType<String>().toList();

  Map<String, Object?> toJson() => {
        'cid': customerId,
        'name': customerName,
        'pay': pay,
        'disc': discount,
        'fc': fcAmount,
        'note': note,
        'payUuid': payUuid,
        'discUuid': discUuid,
      };

  static List<_PlannedLine> listFrom(String? json) {
    if (json == null || json.isEmpty) return const [];
    return [
      for (final m in (jsonDecode(json) as List).cast<Map>())
        _PlannedLine(
          customerId: (m['cid'] as num).toInt(),
          customerName: '${m['name'] ?? ''}',
          pay: (m['pay'] as num?)?.toDouble() ?? 0,
          discount: (m['disc'] as num?)?.toDouble() ?? 0,
          fcAmount: (m['fc'] as num?)?.toDouble(),
          note: m['note'] as String?,
          payUuid: m['payUuid'] as String?,
          discUuid: m['discUuid'] as String?,
        ),
    ];
  }
}
