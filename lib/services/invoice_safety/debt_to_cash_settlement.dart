// lib/services/invoice_safety/debt_to_cash_settlement.dart
//
// 🔁 تحويل فاتورة دين محفوظة إلى «نقد» بعد أن سدّد العميل جزءاً منها بوصل قبض منفصل.
//
// المشكلة: وصل القبض لا يُربط بفاتورة — يُنقص رصيد العميل كله. تحويل فاتورة الدين إلى نقد
// كان يعتبر إجماليها كله مقبوضاً الآن، فيُحتسب ما سُدّد منها بالوصل مرتين:
//   فاتورة 100,000 دين، وصل 25,000، ثم «نقد» ⇒ الصندوق 125,000 والعميل له 25,000. ❌
//
// القاعدة (بموافقة صاحب المحل):
//   R = دين الفاتورة المسجّل في حساب العميل، B = رصيد العميل كله الآن.
//   S = ما سُدّد منها سابقاً = R − B إن كان B أقل من R (بين 0 و R).
//   تُحفظ «آجل — مسددة بالكامل»: نوع الدفع دين، والمسدد عليها = الإجمالي − S،
//   فيبقى عليها S بالضبط يقابله الوصل القديم. لا تُلمس أي معاملة سابقة ولا تُنشأ معاملة.
//   ⇒ الصندوق = 25,000 (الوصل) + 75,000 (الآن) = 100,000، والعميل صفر. ✅
//
// حدّ معروف: إن كان للعميل فواتير دين أخرى فرصيده قد لا يكشف أن الوصل كان لهذه الفاتورة
// (B ≥ R ⇒ S = 0). لهذا يُعرض S على المستخدم قابلاً للتعديل بين 0 و R قبل الحفظ.
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

  /// S المقترح من دين الفاتورة R ورصيد العميل B. دالة صافية (مختبرة بأرقام ثابتة).
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
    final n = IqdNormalize.invoiceInput(data);
    final items = n.invoiceItems.fold<double>(0, (s, i) => s + i.itemTotal);
    return DebtToCashPlan(
      recordedDebt: roundMoney(r),
      customerBalance: b,
      suggestedPrepaid: suggestPrepaid(recordedDebt: r, customerBalance: b),
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
