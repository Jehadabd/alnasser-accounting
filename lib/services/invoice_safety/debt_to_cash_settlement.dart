// lib/services/invoice_safety/debt_to_cash_settlement.dart
//
// 🔁 تحويل فاتورة دين محفوظة إلى «نقد» بعد أن سدّد العميل جزءاً منها بوصل قبض منفصل.
//
// المشكلة: وصل القبض لا يُربط بفاتورة — يُنقص رصيد العميل كله. تحويل فاتورة الدين إلى نقد
// كان يعتبر إجماليها كله مقبوضاً الآن، فيُحتسب ما سُدّد منها بالوصل مرتين:
//   فاتورة 100,000 دين، وصل 25,000، ثم «نقد» ⇒ الصندوق 125,000 والعميل له 25,000. ❌
//
// القاعدة (بموافقة صاحب المحل — التحويل إلى نقد = سُدّدت بالكامل، بلا سؤال):
//   S = ما سُدّد من هذه الفاتورة سابقاً، بتوزيع الوصولات على ديون العميل «الأقدم أولاً»
//   (FIFO — القاعدة المحاسبية المعتادة للمقبوضات غير المخصصة لفاتورة):
//     • تسديد مربوط بفاتورة بعينها يذهب لها أولاً.
//     • باقي التسديدات (وصولات القبض، الخصومات...) تُوزَّع على الديون بترتيب تاريخها:
//       الدين اليدوي والفواتير الآجلة الأقدم تُسدَّد قبل الأحدث.
//     • S = ما وصل هذه الفاتورة من ذلك التوزيع (بين 0 ودين الفاتورة R، دينار صحيح للأدنى).
//   تُحفظ «آجل — مسددة بالكامل»: نوع الدفع دين، والمسدد عليها = الإجمالي − S،
//   فيبقى عليها S بالضبط يقابله الوصل القديم. لا تُلمس أي معاملة سابقة ولا تُنشأ معاملة.
//   ⇒ فاتورة 100,000 + وصل 25,000: الصندوق = 25,000 + 75,000 = 100,000، والعميل صفر. ✅
//   ⇒ وللعميل فاتورة أخرى: الوصل يُحسب على الأقدم منهما — فلا تُقبض الفاتورة الأحدث مرتين
//     إن كانت هي الأقدم سداداً، ولا يُطرح الوصل من فاتورة لم يُدفع لها.
//
// كل الحساب هنا دوال صافية (بلا واجهة)، تستعملها الشاشة واختبارات المال بالطريقة نفسها.

import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../../accounting/ledger.dart' show roundMoney;
import '../../models/invoice_input_data.dart';
import '../../utils/iqd.dart';
import '../credit_limit_guard.dart';
import '../database/business/invoice_debt_reconciler.dart';
import 'iqd_normalize.dart';

/// خطة التحويل لفاتورة واحدة (لقطة قبل الحفظ).
class DebtToCashPlan {
  const DebtToCashPlan({
    required this.recordedDebt,
    required this.customerBalance,
    required this.suggestedPrepaid,
    required this.paidBefore,
    required this.newTotal,
  });

  /// R: دين الفاتورة المسجّل في حساب العميل الآن.
  final double recordedDebt;

  /// B: رصيد العميل كله الآن.
  final double customerBalance;

  /// S المقترح: ما سُدّد من الفاتورة سابقاً بوصولات (بين 0 و R).
  final double suggestedPrepaid;

  /// المسدد على الفاتورة نفسها قبل هذا الحفظ.
  final double paidBefore;

  /// إجمالي الفاتورة بعد هذا الحفظ (بقواعد الدينار الصحيح).
  final double newTotal;

  /// المسدد على الفاتورة بعد الحفظ لمبلغ [prepaid] مسدد سابقاً.
  double paidAfter(double prepaid) => math.max(0.0, newTotal - clampPrepaid(prepaid));

  /// ما يُقبض نقداً الآن (قد يكون سالباً إن نقص الإجمالي: يُرد للعميل).
  double collectNow(double prepaid) => paidAfter(prepaid) - paidBefore;

  /// S المسموح: بين 0 ودين الفاتورة المسجّل، ديناراً صحيحاً لا يتجاوزه أبداً.
  double clampPrepaid(double prepaid) => DebtToCashSettlement.wholeDinarsWithin(prepaid, recordedDebt);
}

class DebtToCashSettlement {
  DebtToCashSettlement._();

  /// S بتوزيع «الأقدم أولاً» (FIFO). دالة صافية بأرقام ثابتة (مختبرة):
  /// [items] ديون العميل (فواتير آجلة ودين يدوي) كلٌّ بتاريخه وما سُدّد له بعينه،
  /// [pool] مجموع التسديدات غير المخصصة (موجب)، [target] مفتاح هذه الفاتورة.
  static double fifoPrepaid({
    required List<DebtItem> items,
    required double pool,
    required String target,
    required double recordedDebt,
  }) {
    final sorted = [...items]..sort((a, b) {
        final c = a.date.compareTo(b.date);
        return c != 0 ? c : a.order.compareTo(b.order);
      });
    var free = math.max(0.0, pool);
    // تسديد مخصص زاد على دين فاتورته: يصير غير مخصص
    for (final it in sorted) {
      free += math.max(0.0, it.specificPaid - it.amount);
    }
    var s = 0.0;
    for (final it in sorted) {
      final covered = it.specificPaid.clamp(0.0, math.max(0.0, it.amount)).toDouble();
      final take = math.min(math.max(0.0, it.amount - covered), free);
      free -= take;
      if (it.key == target) s = covered + take;
    }
    return wholeDinarsWithin(s, recordedDebt);
  }

  /// صيغة الحالة البسيطة (فاتورة العميل الوحيدة أو الأحدث): S = R − max(B، 0).
  /// تساوي [fifoPrepaid] حين لا دين أحدث من الفاتورة. دالة صافية (مختبرة بأرقام ثابتة).
  static double suggestPrepaid({required double recordedDebt, required double customerBalance}) {
    if (recordedDebt <= 0) return 0;
    return wholeDinarsWithin(recordedDebt - math.max(0.0, customerBalance), recordedDebt);
  }

  /// [v] مقصوصاً إلى [0، max] ثم إلى الدينار الصحيح الأدنى — لا يُقرّب للأعلى أبداً كي لا
  /// يُعتبر مسدداً أكثر مما سُجّل (99,999.6 ⇒ 99,999). فرق تمثيل double ضئيل لا يُسقط ديناراً.
  static double wholeDinarsWithin(double v, double max) {
    if (!v.isFinite || max <= 0) return 0.0;
    final w = (v.clamp(0.0, max) + Iqd.wholeTolerance).floorToDouble();
    return w > max ? max.floorToDouble() : w;
  }

  /// خطة التحويل إن كان الحفظ تحويلاً من دين إلى نقد لفاتورة محفوظة لها دين مسجّل
  /// ولعميلها نفسه؛ وإلا null (حفظ عادي بلا تغيير).
  static Future<DebtToCashPlan?> plan(DatabaseExecutor db, InvoiceInputData data) async {
    final inv = data.invoiceToManage;
    if (inv == null || inv.id == null || inv.customerId == null) return null;
    if (data.paymentType != 'نقد' || inv.status != 'محفوظة') return null;
    // العميل نفسه؟ (الاسم المكتوب يطابق اسم الفاتورة أو يشير إلى بطاقة عميلها نفسه)
    final same = _key(inv.customerName) == _key(data.customerName) ||
        await CreditLimitGuard.customerIdByName(db, data.customerName) == inv.customerId;
    if (!same) return null;
    final r = await InvoiceDebtReconciler.recordedContribution(db, inv.id!, inv.customerId!);
    if (r < 0.5) return null;
    final b = await customerBalance(db, inv.customerId!);
    final s = await _fifoForInvoice(db, inv.customerId!, inv.id!, roundMoney(r));
    final n = IqdNormalize.invoiceInput(data);
    final items = n.invoiceItems.fold<double>(0, (s, i) => s + i.itemTotal);
    return DebtToCashPlan(
      recordedDebt: roundMoney(r),
      customerBalance: b,
      suggestedPrepaid: s,
      paidBefore: inv.amountPaidOnInvoice,
      newTotal: roundMoney(items + n.loadingFee - n.discount),
    );
  }

  /// بيانات الحفظ بعد موافقة المستخدم على [prepaid]: صفر ⇒ تحويل عادي إلى نقد؛
  /// غير الصفر ⇒ «آجل — مسددة بالكامل».
  static InvoiceInputData apply(InvoiceInputData data, DebtToCashPlan plan, double prepaid) {
    final s = plan.clampPrepaid(prepaid);
    if (s < 0.5) return data.copyWith(prepaidByReceipts: 0.0);
    return data.copyWith(
      paymentType: 'دين',
      paidAmount: plan.paidAfter(s),
      prepaidByReceipts: math.min(s, plan.newTotal),
    );
  }

  /// ديون العميل وتسديداته من معاملاته الحيّة، ثم [fifoPrepaid] لهذه الفاتورة.
  static Future<double> _fifoForInvoice(DatabaseExecutor db, int customerId, int invoiceId, double r) async {
    final rows = await db.rawQuery('''
      SELECT t.id, t.invoice_id, t.amount_changed AS a, t.transaction_type AS ty, t.transaction_date AS d,
             i.invoice_date AS idate
      FROM transactions t LEFT JOIN invoices i ON i.id = t.invoice_id
      WHERE t.customer_id = ? AND COALESCE(t.is_deleted, 0) = 0
      ORDER BY t.id''', [customerId]);
    final nonContribution = InvoiceDebtReconciler.nonContributionTypes.toSet();
    final inv = <int, ({double debt, double specific, DateTime date, int order})>{};
    final items = <DebtItem>[];
    var pool = 0.0;
    DateTime when(Object? v) => DateTime.tryParse('${v ?? ''}') ?? DateTime(1970);
    for (final row in rows) {
      final a = (row['a'] as num?)?.toDouble() ?? 0.0;
      final iid = row['invoice_id'] as int?;
      final id = row['id'] as int;
      if (iid != null) {
        final cur = inv[iid] ?? (debt: 0.0, specific: 0.0, date: when(row['idate'] ?? row['d']), order: id);
        inv[iid] = nonContribution.contains(row['ty'])
            ? (debt: cur.debt, specific: cur.specific - a, date: cur.date, order: cur.order)
            : (debt: cur.debt + a, specific: cur.specific, date: cur.date, order: cur.order);
      } else if (a > 0) {
        items.add(DebtItem(key: 'tx$id', date: when(row['d']), order: id, amount: a));
      } else {
        pool += -a;
      }
    }
    for (final e in inv.entries) {
      final v = e.value;
      // صافي المخصص سالب (مبلغ أُعيد للعميل على فاتورته) = دين إضافي عليها
      final debt = v.debt + math.max(0.0, -v.specific);
      final specific = math.max(0.0, v.specific);
      if (debt > 0) {
        items.add(DebtItem(key: 'inv${e.key}', date: v.date, order: v.order, amount: debt, specificPaid: specific));
      } else {
        pool += -debt + specific; // صافي فاتورة سالب = تسديد غير مخصص
      }
    }
    return fifoPrepaid(items: items, pool: pool, target: 'inv$invoiceId', recordedDebt: r);
  }

  /// رصيد العميل = مجموع معاملاته الحيّة (المرجع المحاسبي، كما في CustomerMoney.balance).
  static Future<double> customerBalance(DatabaseExecutor db, int customerId) async {
    final r = await db.rawQuery(
        'SELECT COALESCE(SUM(amount_changed), 0) AS b FROM transactions '
        'WHERE customer_id = ? AND COALESCE(is_deleted, 0) = 0',
        [customerId]);
    return roundMoney((r.first['b'] as num?)?.toDouble() ?? 0.0);
  }

  static String _key(String s) => s.replaceAll(RegExp(r'\s+'), '');
}

/// دين واحد للعميل في توزيع «الأقدم أولاً»: فاتورة آجلة (صافي دينها) أو دين يدوي.
class DebtItem {
  const DebtItem({
    required this.key,
    required this.date,
    required this.order,
    required this.amount,
    this.specificPaid = 0,
  });

  final String key;
  final DateTime date;

  /// ترتيب الإدخال عند تساوي التاريخ.
  final int order;

  /// الدين.
  final double amount;

  /// ما سُدّد لهذا الدين بعينه (تسديد مربوط بالفاتورة).
  final double specificPaid;
}
