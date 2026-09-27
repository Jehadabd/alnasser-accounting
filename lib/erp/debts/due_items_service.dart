// lib/erp/debts/due_items_service.dart
//
// 📅 الاستحقاقات (مثل الإداري): أوراق وشيكات القبض والدفع، والأقساط.
//
// المسارات المالية (كلها عبر البوابات الأصلية):
//   • شيك/ورقة قبض «تُنزّل من الدين الآن»: تسديد موصوف «شيك» على العميل
//       ⇒ القيد: مدين أوراق القبض / دائن ذمم العملاء
//     عند التحصيل: سند قبض على حساب أوراق القبض ⇒ مدين الصندوق / دائن أوراق القبض
//     عند الارتداد: دين موصوف «شيك مرتجع» ⇒ مدين ذمم العملاء / دائن أوراق القبض
//   • استحقاق «لا يُنزّل من الدين» (قسط، وعد بالسداد): تذكير فقط؛ التحصيل = تسديد
//     عادي على العميل.
//   • شيك/ورقة دفع لمورد «تُنزّل الآن»: دفعة مورد بطريقة «شيك»
//       ⇒ مدين ذمم الموردين / دائن أوراق الدفع
//     عند الصرف من البنك: سند صرف على حساب أوراق الدفع ⇒ مدين أوراق الدفع / دائن البنك

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart';
import '../../accounting/screens/acc_ui.dart';
import '../../accounting/vouchers_service.dart';
import '../erp_common.dart';
import 'customer_money.dart';
import 'receipts_service.dart';

const Map<String, String> dueKindLabels = {
  'cheque_in': 'شيك قبض',
  'receivable_note': 'ورقة قبض (كمبيالة)',
  'installment': 'قسط',
  'cheque_out': 'شيك دفع',
  'payable_note': 'ورقة دفع',
};

const Map<String, String> dueStatusLabels = {
  'open': 'مفتوح',
  'partial': 'مسدد جزئياً',
  'closed': 'مغلق',
  'bounced': 'مرتجع',
  'cancelled': 'ملغى',
};

bool dueIsReceivable(String kind) => kind == 'cheque_in' || kind == 'receivable_note' || kind == 'installment';

class DueItemsService {
  Future<List<Map<String, Object?>>> list({
    String? status, // null = المفتوحة (open/partial)
    String? kind,
    String? partyType,
    int? partyId,
    DateTime? dueFrom,
    DateTime? dueTo,
    String? search,
    bool includeClosed = false,
  }) async {
    final db = await erpDb();
    final where = <String>[];
    final args = <Object?>[];
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    } else if (!includeClosed) {
      where.add("status IN ('open', 'partial')");
    }
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind);
    }
    if (partyType != null) {
      where.add('party_type = ?');
      args.add(partyType);
    }
    if (partyId != null) {
      where.add('party_id = ?');
      args.add(partyId);
    }
    if (dueFrom != null) {
      where.add('due_date >= ?');
      args.add(isoDay(dueFrom));
    }
    if (dueTo != null) {
      where.add('due_date < ?');
      args.add(isoDayAfter(dueTo));
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(party_name LIKE ? OR doc_no LIKE ? OR statement LIKE ? OR guarantor LIKE ? OR bank_name LIKE ?)');
      final l = '%${search.trim()}%';
      args.addAll([l, l, l, l, l]);
    }
    return db.rawQuery('''
      SELECT * FROM due_items ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY due_date, id LIMIT 2000
    ''', args);
  }

  Future<List<Map<String, Object?>>> events(int dueId) async {
    final db = await erpDb();
    return db.query('due_events', where: 'due_id = ?', whereArgs: [dueId], orderBy: 'id');
  }

  Future<void> _event(int dueId, String type, DateTime date, double amount,
      {int? cashBoxId, int? voucherId, String? balanceRef, String? note}) async {
    final db = await erpDb();
    await db.insert('due_events', {
      'due_id': dueId,
      'event_type': type,
      'event_date': date.toIso8601String(),
      'amount': amount,
      'cash_box_id': cashBoxId,
      'voucher_id': voucherId,
      'balance_ref': balanceRef,
      'note': note,
      'created_by': currentUserName(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// إنشاء استحقاق (أو عدة أقساط إن كان [installments] > 1).
  Future<List<int>> create(
    BuildContext context, {
    required String kind,
    required String partyType, // customer | supplier
    required int partyId,
    required String partyName,
    required double amount,
    String currency = 'IQD',
    double fxRate = 1,
    required DateTime issueDate,
    required DateTime dueDate,
    int installments = 1,
    int intervalMonths = 1,
    String? docNo,
    String? bankName,
    String? guarantor,
    String? statement,
    bool affectBalance = false,
  }) async {
    if (amount <= 0) throw ErpException('المبلغ يجب أن يكون أكبر من صفر');
    if (installments < 1) throw ErpException('عدد الأقساط غير صحيح');
    final receivable = dueIsReceivable(kind);
    if (receivable && partyType != 'customer') throw ErpException('أوراق القبض تكون على عميل');
    if (!receivable && partyType != 'supplier') throw ErpException('أوراق الدفع تكون لمورد');
    if (kind == 'installment') affectBalance = false;
    await PeriodLock.assertOpen(issueDate);
    final db = await erpDb();
    final base = currency == 'IQD' ? roundMoney(amount) : roundMoney(amount * fxRate);

    // الأثر على الرصيد (مرة واحدة للمبلغ كله)
    String? balanceRef;
    if (affectBalance) {
      if (partyType == 'customer') {
        if (!context.mounted) throw ErpException('أُغلقت الشاشة');
        balanceRef = await CustomerMoney.post(
          context,
          customerId: partyId,
          amount: -base,
          kind: CustomerTxKind.cheque,
          note: '${dueKindLabels[kind]}${docNo == null || docNo.isEmpty ? '' : ' رقم $docNo'}'
              ' — يستحق ${fmtDate(dueDate)}${bankName == null || bankName.isEmpty ? '' : ' — $bankName'}',
          date: issueDate,
          currency: currency,
          fcAmount: currency == 'IQD' ? null : amount,
          fxRate: currency == 'IQD' ? null : fxRate,
          docNo: docNo,
          refType: 'due',
        );
      } else {
        await ReceiptsService().supplierPayment(
          supplierId: partyId,
          amount: amount,
          currency: currency,
          method: 'cheque',
          date: issueDate,
          fxRate: fxRate,
          docNo: docNo,
          notes: '${dueKindLabels[kind]} يستحق ${fmtDate(dueDate)}',
        );
        balanceRef = 'supplier_payment';
      }
    }

    final ids = <int>[];
    final planRef = installments > 1 ? 'P${DateTime.now().millisecondsSinceEpoch}' : null;
    // تقسيم المبلغ: الأقساط متساوية والفرق (كسور) على القسط الأخير
    final each = roundMoney(amount / installments);
    await db.transaction((txn) async {
      for (var i = 0; i < installments; i++) {
        final isLast = i == installments - 1;
        final part = isLast ? roundMoney(amount - each * (installments - 1)) : each;
        final due = DateTime(dueDate.year, dueDate.month + i * intervalMonths, dueDate.day);
        final no = await nextDocNumber(txn, 'due_items', 'due_no');
        ids.add(await txn.insert('due_items', {
          'due_no': no,
          'kind': kind,
          'party_type': partyType,
          'party_id': partyId,
          'party_name': partyName,
          'amount': part,
          'currency': currency,
          'fx_rate': currency == 'IQD' ? 1.0 : fxRate,
          'issue_date': issueDate.toIso8601String(),
          'due_date': isoDay(due),
          'doc_no': docNo,
          'bank_name': bankName,
          'guarantor': guarantor,
          'statement': statement,
          'installment_no': installments > 1 ? i + 1 : null,
          'installments_total': installments > 1 ? installments : null,
          'plan_ref': planRef,
          'status': 'open',
          'paid_amount': 0,
          'affects_balance': affectBalance ? 1 : 0,
          'balance_ref': balanceRef,
          'created_by': currentUserName(),
          'created_at': DateTime.now().toIso8601String(),
        }));
      }
    });
    for (final id in ids) {
      await _event(id, 'create', issueDate, 0, balanceRef: balanceRef);
    }
    return ids;
  }

  Future<Map<String, Object?>> _get(int id) async {
    final db = await erpDb();
    final r = await db.query('due_items', where: 'id = ?', whereArgs: [id], limit: 1);
    if (r.isEmpty) throw ErpException('الاستحقاق غير موجود');
    return r.first;
  }

  /// تحصيل/صرف استحقاق (كلياً أو جزئياً).
  Future<void> settle(
    BuildContext context, {
    required int dueId,
    required double amount,
    required DateTime date,
    required int cashBoxId,
    String? note,
  }) async {
    final d = await _get(dueId);
    final status = d['status'] as String;
    if (status != 'open' && status != 'partial') throw ErpException('الاستحقاق ليس مفتوحاً');
    final total = d0(d['amount']);
    final paid = d0(d['paid_amount']);
    final remaining = roundMoney(total - paid);
    if (amount <= 0) throw ErpException('المبلغ يجب أن يكون أكبر من صفر');
    if (amount > remaining + kMoneyEpsilon) {
      throw ErpException('المبلغ أكبر من المتبقي (${fmtMoney(remaining)})');
    }
    await PeriodLock.assertOpen(date);
    final kind = d['kind'] as String;
    final currency = (d['currency'] as String?) ?? 'IQD';
    final rate = d0(d['fx_rate']) <= 0 ? 1.0 : d0(d['fx_rate']);
    final base = currency == 'IQD' ? roundMoney(amount) : roundMoney(amount * rate);
    final affects = (d['affects_balance'] as int? ?? 0) == 1;
    final receivable = dueIsReceivable(kind);
    final label = '${dueKindLabels[kind]} رقم ${d['due_no']}${(d['doc_no'] as String?)?.isNotEmpty == true ? ' (${d['doc_no']})' : ''}';
    final db = await erpDb();

    int? voucherId;
    String? balanceRef;
    if (affects) {
      // المال انتقل سابقاً من الذمم إلى حساب الأوراق؛ الآن من/إلى الصندوق
      final acc = await Ledger.systemAccountId(db, receivable ? 'cheques_receivable' : 'cheques_payable');
      voucherId = await VouchersService().create(
        type: receivable ? VoucherType.receipt : VoucherType.payment,
        amount: base,
        date: date,
        cashBoxId: cashBoxId,
        accountId: acc,
        description: '${receivable ? 'تحصيل' : 'صرف'} $label — ${d['party_name'] ?? ''}',
        reference: d['doc_no'] as String?,
        userId: currentUserId(),
      );
    } else if (receivable) {
      if (!context.mounted) throw ErpException('أُغلقت الشاشة');
      balanceRef = await CustomerMoney.post(
        context,
        customerId: d['party_id'] as int,
        amount: -base,
        kind: CustomerTxKind.cash,
        note: 'تحصيل $label${note == null || note.isEmpty ? '' : ' — $note'}',
        date: date,
        cashBoxId: cashBoxId,
        currency: currency,
        fcAmount: currency == 'IQD' ? null : amount,
        fxRate: currency == 'IQD' ? null : rate,
        docNo: d['doc_no'] as String?,
        refType: 'due',
        refId: dueId,
      );
    } else {
      await ReceiptsService().supplierPayment(
        supplierId: d['party_id'] as int,
        amount: amount,
        currency: currency,
        method: 'cash',
        date: date,
        cashBoxId: cashBoxId,
        fxRate: rate,
        docNo: d['doc_no'] as String?,
        notes: 'صرف $label',
      );
      balanceRef = 'supplier_payment';
    }

    final newPaid = roundMoney(paid + amount);
    final closed = newPaid >= total - kMoneyEpsilon;
    await db.update(
      'due_items',
      {
        'paid_amount': newPaid,
        'status': closed ? 'closed' : 'partial',
        'closed_at': closed ? DateTime.now().toIso8601String() : null,
      },
      where: 'id = ?',
      whereArgs: [dueId],
    );
    await _event(dueId, closed ? 'close' : 'partial', date, amount,
        cashBoxId: cashBoxId, voucherId: voucherId, balanceRef: balanceRef, note: note);
  }

  /// ارتداد شيك قبض (أو إلغاء ورقة) قبل تحصيل أي جزء منها: يعود المبلغ ديناً على العميل.
  Future<void> bounce(BuildContext context, {required int dueId, required DateTime date, String? note}) async {
    final d = await _get(dueId);
    final status = d['status'] as String;
    if (status != 'open' && status != 'partial') throw ErpException('الاستحقاق ليس مفتوحاً');
    final kind = d['kind'] as String;
    if (!dueIsReceivable(kind) || kind == 'installment') {
      throw ErpException('الارتداد يكون لشيكات وأوراق القبض فقط');
    }
    await PeriodLock.assertOpen(date);
    final remaining = roundMoney(d0(d['amount']) - d0(d['paid_amount']));
    final currency = (d['currency'] as String?) ?? 'IQD';
    final rate = d0(d['fx_rate']) <= 0 ? 1.0 : d0(d['fx_rate']);
    final base = currency == 'IQD' ? remaining : roundMoney(remaining * rate);
    String? ref;
    if ((d['affects_balance'] as int? ?? 0) == 1 && base > 0) {
      if (!context.mounted) throw ErpException('أُغلقت الشاشة');
      ref = await CustomerMoney.post(
        context,
        customerId: d['party_id'] as int,
        amount: base,
        kind: CustomerTxKind.chequeBounce,
        note: 'ارتداد ${dueKindLabels[kind]} رقم ${d['due_no']}'
            '${(d['doc_no'] as String?)?.isNotEmpty == true ? ' (${d['doc_no']})' : ''}'
            '${note == null || note.isEmpty ? '' : ' — $note'}',
        date: date,
        docNo: d['doc_no'] as String?,
        refType: 'due',
        refId: dueId,
      );
    }
    final db = await erpDb();
    await db.update('due_items', {'status': 'bounced', 'closed_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [dueId]);
    await _event(dueId, 'bounce', date, remaining, balanceRef: ref, note: note);
  }

  /// إلغاء استحقاق لم يؤثر على الرصيد ولم يُحصَّل منه شيء (قسط، وعد).
  Future<void> cancel(int dueId, {String? note}) async {
    final d = await _get(dueId);
    if ((d['affects_balance'] as int? ?? 0) == 1) {
      throw ErpException('هذا الاستحقاق نزّل من الرصيد — استعمل «ارتداد» لإعادته');
    }
    if (d0(d['paid_amount']) > 0) throw ErpException('حُصّل جزء منه — لا يمكن إلغاؤه');
    final db = await erpDb();
    await db.update('due_items', {'status': 'cancelled', 'closed_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [dueId]);
    await _event(dueId, 'cancel', DateTime.now(), 0, note: note);
  }

  /// ملخص للوحة: المتأخر، المستحق هذا الأسبوع، مجموع المفتوح.
  Future<Map<String, double>> dashboard() async {
    final db = await erpDb();
    final now = DateTime.now();
    final r = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN due_date < ? THEN (amount - paid_amount) * fx_rate ELSE 0 END), 0) AS overdue,
        COALESCE(SUM(CASE WHEN due_date >= ? AND due_date < ? THEN (amount - paid_amount) * fx_rate ELSE 0 END), 0) AS week,
        COALESCE(SUM((amount - paid_amount) * fx_rate), 0) AS open_total,
        COUNT(*) AS n
      FROM due_items WHERE status IN ('open', 'partial') AND kind IN ('cheque_in', 'receivable_note', 'installment')
    ''', [isoDay(now), isoDay(now), isoDayAfter(now.add(const Duration(days: 6)))]);
    return {
      'overdue': d0(r.first['overdue']),
      'week': d0(r.first['week']),
      'open': d0(r.first['open_total']),
      'count': d0(r.first['n']),
    };
  }
}
