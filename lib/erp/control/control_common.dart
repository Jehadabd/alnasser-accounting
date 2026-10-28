// lib/erp/control/control_common.dart
//
// 🛡️ أدوات مشتركة لميزات «الرقابة والأدوات المالية»: القاعدة الجاهزة، الإعدادات،
// ومن يحق له الاعتماد.

import 'package:sqflite/sqflite.dart';

import '../../accounting/ledger.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../erp_common.dart';
import 'control_schema.dart';

/// القاعدة بعد التأكد من وجود جداول الرقابة.
Future<Database> controlDb() async {
  final db = await erpDb();
  await ControlSchema.ensure(db, gen: DatabaseService.openGeneration);
  return db;
}

/// هل المستخدم الحالي مدير؟ (بلا مستخدمين أصلاً: صاحب الجهاز هو المدير)
Future<bool> currentIsAdmin() async {
  final auth = AuthService();
  if (auth.currentUser != null) return auth.currentUser!.isAdmin;
  try {
    return !(await auth.hasAnyUsers());
  } catch (_) {
    return false;
  }
}

/// إعدادات الرقابة (في accounting_settings — مشتركة لكل الأجهزة على القاعدة نفسها).
class ControlSettings {
  ControlSettings._();

  static Future<String?> get(String key, [DatabaseExecutor? db]) async {
    try {
      return await Ledger.getSetting(db ?? await erpDb(), key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> set(String key, String value, [DatabaseExecutor? db]) async =>
      Ledger.setSetting(db ?? await erpDb(), key, value);

  static Future<bool> getBool(String key, bool fallback, [DatabaseExecutor? db]) async {
    final v = await get(key, db);
    if (v == null || v.isEmpty) return fallback;
    return v == '1';
  }

  static Future<double> getNum(String key, double fallback, [DatabaseExecutor? db]) async {
    final v = double.tryParse(await get(key, db) ?? '');
    return v ?? fallback;
  }

  static Future<void> setBool(String key, bool v) => set(key, v ? '1' : '0');
  static Future<void> setNum(String key, double v) => set(key, '$v');
}

/// تقريب المبالغ إلى الدينار (فروقات أقل من دينار = مطابق).
const double kCountTolerance = 1.0;

double round2(double v) => (v * 100).roundToDouble() / 100;
