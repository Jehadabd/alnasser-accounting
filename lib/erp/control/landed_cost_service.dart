// lib/erp/control/landed_cost_service.dart
//
// 🚢 مصاريف الشحن والجمارك على كلفة مادة («إدخال بضاعة» ← المزيد).
//
//   كلفة الوحدة النهائية = سعر شراء الوحدة + (مجموع المصاريف ÷ الكمية بالوحدة الأساسية).
//
// طريقة الدفع يختارها المستخدم في كل مرة:
//   • box     — دُفعت الآن من صندوق ⇒ قيد: مدين المخزون / دائن الصندوق.
//   • reclass — سُجّلت سابقاً بسند مصروف ⇒ قيد إعادة تصنيف: مدين المخزون / دائن حساب
//               ذلك المصروف (حتى لا تُحسب مرتين: مصروفاً ثم كلفة بضاعة مباعة).
//   • none    — كلفة فقط بلا قيد (الدفع يُسجَّل بطريقة أخرى).
// القيد يُشتق في ErpPosting من السجل؛ إلغاء السجل يحذف قيده (لا يعيد الكلفة تلقائياً —
// الكلفة صارت في بطاقة المادة وتُعدَّل من هناك بعلم المستخدم).

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../activity/activity_log.dart';
import '../erp_common.dart';
import 'control_common.dart';

class LandedMode {
  LandedMode._();
  static const box = 'box';
  static const reclass = 'reclass';
  static const none = 'none';

  static String label(String m) => switch (m) {
        box => 'دُفعت الآن من صندوق',
        reclass => 'مسجّلة سابقاً بسند مصروف (تُنقل إلى المخزون)',
        none => 'كلفة فقط بلا قيد',
        _ => m,
      };
}

class LandedExtra {
  LandedExtra(this.name, this.amount);
  final String name;
  final double amount;
  Map<String, Object?> toJson() => {'name': name, 'amount': amount};
}

/// ما يُطبَّق على المادة قبل حفظها (يُحفظ سجله بعد نجاح حفظ المادة).
class LandedPlan {
  LandedPlan({
    required this.purchaseUnitCost,
    required this.baseQty,
    required this.extras,
    required this.mode,
    this.boxId,
    this.expenseAccountId,
  });

  final double purchaseUnitCost;
  final double baseQty;
  final List<LandedExtra> extras;
  final String mode;
  final int? boxId;
  final int? expenseAccountId;

  double get totalExtra => round2(extras.fold<double>(0, (s, e) => s + e.amount));
  double get perUnit => landedPerUnit(totalExtra, baseQty);
  double get finalUnitCost => round2(purchaseUnitCost + perUnit);
}

/// حصة الوحدة الأساسية من المصاريف.
double landedPerUnit(double totalExtra, double baseQty) {
  if (baseQty <= 0 || totalExtra <= 0) return 0;
  return round2(totalExtra / baseQty);
}

class LandedCostService {
  LandedCostService._();

  static void validate(LandedPlan p) {
    if (p.baseQty <= 0) throw ErpException('اكتب الكمية في «المخزون» أولاً — المصاريف توزَّع على الكمية');
    if (p.extras.isEmpty || p.totalExtra <= 0) throw ErpException('أضف مصروفاً واحداً على الأقل بمبلغ أكبر من صفر');
    if (p.extras.any((e) => e.amount < 0)) throw ErpException('مبلغ المصروف لا يكون سالباً');
    if (p.mode == LandedMode.box && p.boxId == null) throw ErpException('اختر الصندوق الذي دُفعت منه المصاريف');
    if (p.mode == LandedMode.reclass && p.expenseAccountId == null) {
      throw ErpException('اختر حساب المصروف الذي سُجّلت عليه سابقاً');
    }
  }

  /// يسجّل المصاريف بعد حفظ المادة بنجاح. يعيد معرّف السجل.
  static Future<int> record({required int productId, required String productName, required LandedPlan plan}) async {
    validate(plan);
    final db = await controlDb();
    final today = DateTime.now();
    final id = await db.transaction((txn) async {
      if (plan.mode != LandedMode.none) await PeriodLock.assertOpen(today, txn);
      return txn.insert('landed_costs', {
        'product_id': productId,
        'product_name': productName,
        'cost_date': isoDay(today),
        'base_qty': plan.baseQty,
        'purchase_unit_cost': round2(plan.purchaseUnitCost),
        'extras': jsonEncode([for (final e in plan.extras) e.toJson()]),
        'total_extra': plan.totalExtra,
        'per_unit': plan.perUnit,
        'mode': plan.mode,
        'box_id': plan.mode == LandedMode.box ? plan.boxId : null,
        'expense_account_id': plan.mode == LandedMode.reclass ? plan.expenseAccountId : null,
        'status': 'posted',
        'created_by': currentUserName(),
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    ActivityLog.log('إضافة', 'مصاريف الشحن',
            '«$productName»: ${plan.totalExtra.round()} على ${plan.baseQty} وحدة (+${plan.perUnit} للوحدة) — ${LandedMode.label(plan.mode)}')
        .catchError((_) {});
    return id;
  }

  static Future<List<Map<String, Object?>>> list() async {
    final db = await controlDb();
    return db.query('landed_costs', orderBy: 'id DESC');
  }

  /// إلغاء سجل (يحذف قيده عند الترحيل التالي؛ الكلفة في بطاقة المادة لا تتغير).
  static Future<void> voidRecord(int id) async {
    if (!await currentIsAdmin()) throw ErpException('الإلغاء للمدير فقط');
    final db = await controlDb();
    await db.transaction((txn) async {
      final r = await txn.query('landed_costs', where: 'id = ?', whereArgs: [id], limit: 1);
      if (r.isEmpty) return;
      if (r.first['mode'] != LandedMode.none) await PeriodLock.assertOpen(parseDate(r.first['cost_date']), txn);
      await txn.update('landed_costs', {'status': 'void'}, where: 'id = ?', whereArgs: [id]);
    });
    ActivityLog.log('إلغاء', 'مصاريف الشحن', 'سجل رقم $id').catchError((_) {});
  }

  /// حسابات المصاريف (لاختيار الحساب الذي سُجّل عليه الشحن سابقاً).
  static Future<List<Map<String, Object?>>> expenseAccounts() async {
    final db = await controlDb();
    return db.rawQuery('''
      SELECT id, code, name FROM accounts
      WHERE type = 'expense' AND is_group = 0 AND COALESCE(is_active, 1) = 1
        AND COALESCE(system_key, '') NOT IN ('cogs', 'cash_over_short', 'depreciation_expense', 'asset_disposal')
      ORDER BY code''');
  }

  static Future<List<Map<String, Object?>>> postableRows(DatabaseExecutor db) async {
    final t = await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='landed_costs'");
    if (t.isEmpty) return const [];
    return db.rawQuery(
        "SELECT * FROM landed_costs WHERE status = 'posted' AND mode IN ('box', 'reclass') AND total_extra > 0");
  }
}
