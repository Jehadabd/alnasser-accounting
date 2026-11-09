// lib/services/customer_balance_guard.dart
//
// 🛡️ قبل أن يخرج من البرنامج مستند فيه دين العميل (كشف حساب، فاتورة، وصل، مطالبة واتساب):
// رصيده المسجّل في سجل الديون يجب أن يساوي مجموع معاملاته — بالفلس.
//   • الكشف يُبنى من المعاملات، و«المطلوب الحالي» في الفاتورة والمطالبة من الرصيد المسجّل؛
//     إن اختلفا فأحد الرقمين خطأ، ولا يُرسل للزبون رقم غير مؤكد.
//   • نفس فحص «طبيب البيانات» (database_doctor.dart) لعميل واحد، لكن بلا تسامح.
// قراءة فقط: لا يصحّح شيئاً ولا يغيّر ديناً أو معاملة — التصحيح قرار المستخدم.

import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import 'database_service.dart';

class BalanceCheck {
  const BalanceCheck(this.recorded, this.ledger);

  /// الرصيد المسجّل للعميل (customers.current_total_debt).
  final double recorded;

  /// مجموع معاملاته غير المحذوفة (ما يُبنى منه الكشف).
  final double ledger;

  int get _recordedFils => (recorded * 100).round();
  int get _ledgerFils => (ledger * 100).round();

  bool get ok => _recordedFils == _ledgerFils;
  double get diff => (_recordedFils - _ledgerFils) / 100.0;

  static String _m(double v) {
    final s = v.abs().round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return v < 0 ? '-$s' : s;
  }

  String get message => 'رصيد العميل المسجّل ${_m(recorded)} لا يساوي مجموع معاملاته ${_m(ledger)} '
      '(الفرق ${_m(diff)}) — راجعه قبل إرسال أي كشف أو مطالبة';
}

class CustomerBalanceGuard {
  CustomerBalanceGuard._();

  /// null = العميل غير موجود.
  static Future<BalanceCheck?> check(int customerId, {DatabaseExecutor? db}) async {
    final d = db ?? await DatabaseService().database;
    final c = await d.rawQuery('SELECT current_total_debt AS r FROM customers WHERE id = ?', [customerId]);
    if (c.isEmpty) return null;
    List<Map<String, Object?>> t;
    try {
      t = await d.rawQuery(
          'SELECT COALESCE(SUM(amount_changed), 0) AS s FROM transactions '
          'WHERE customer_id = ? AND COALESCE(is_deleted, 0) = 0',
          [customerId]);
    } catch (_) {
      t = await d.rawQuery(
          'SELECT COALESCE(SUM(amount_changed), 0) AS s FROM transactions WHERE customer_id = ?', [customerId]);
    }
    return BalanceCheck(
      (c.first['r'] as num?)?.toDouble() ?? 0,
      (t.first['s'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// مستند لا يجوز إرساله للزبون كما هو (كشف مفلتر، رصيد غير مؤكد…) — رسالته تظهر للمستخدم كما هي.
class DocNotSendable implements Exception {
  DocNotSendable(this.message);
  final String message;
  @override
  String toString() => message;
}
