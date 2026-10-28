// lib/services/employee_salary.dart
//
// 💵 راتب الموظف الشهري (اختياري) — يُحفظ في جدول users (عمود monthly_salary)
// ويُطرح من الربح في التقرير الشهري والسنوي كسطر «رواتب الموظفين».
//
// ملاحظة: الراتب المسجّل هنا «تقدير ثابت» وليس دفعاً فعلياً. إن كنت تصرف الرواتب
// أيضاً بسند مصروف (حساب 5202) فلا تجمع الاثنين — التقرير يعرض كلاً منهما في سطر.

import 'database_service.dart';

class SalaryLine {
  const SalaryLine(this.name, this.amount);
  final String name;
  final double amount;
}

class EmployeeSalary {
  // مرتبط بالقاعدة المفتوحة: قاعدة مستعادة تُجهَّز جداولها من جديد
  static int _readyGen = -1;
  static bool get _ready => _readyGen == DatabaseService.openGeneration;
  static set _ready(bool v) => _readyGen = v ? DatabaseService.openGeneration : -1;

  static Future<void> _ensure() async {
    if (_ready) return;
    final db = await DatabaseService().database;
    final cols = (await db.rawQuery('PRAGMA table_info(users)')).map((r) => '${r['name']}').toSet();
    if (!cols.contains('monthly_salary')) {
      await db.execute('ALTER TABLE users ADD COLUMN monthly_salary REAL');
    }
    _ready = true;
  }

  static Future<double?> of(int userId) async {
    try {
      await _ensure();
      final db = await DatabaseService().database;
      final r = await db.query('users', columns: ['monthly_salary'], where: 'id = ?', whereArgs: [userId], limit: 1);
      if (r.isEmpty) return null;
      return (r.first['monthly_salary'] as num?)?.toDouble();
    } catch (_) {
      return null;
    }
  }

  /// كل الرواتب المسجلة: معرّف المستخدم ← الراتب
  static Future<Map<int, double>> all() async {
    try {
      await _ensure();
      final db = await DatabaseService().database;
      final r = await db.query('users', columns: ['id', 'monthly_salary'], where: 'IFNULL(monthly_salary, 0) > 0');
      return {for (final x in r) x['id'] as int: (x['monthly_salary'] as num).toDouble()};
    } catch (_) {
      return const {};
    }
  }

  static Future<void> set(int userId, double? salary) async {
    await _ensure();
    final db = await DatabaseService().database;
    await db.update('users', {'monthly_salary': (salary == null || salary <= 0) ? null : salary},
        where: 'id = ?', whereArgs: [userId]);
  }

  /// رواتب شهر: كل موظف براتب أُنشئ حسابه قبل نهاية ذلك الشهر.
  static Future<List<SalaryLine>> forMonth(DateTime month) async {
    try {
      await _ensure();
      final db = await DatabaseService().database;
      final end = DateTime(month.year, month.month + 1, 1);
      final r = await db.query('users',
          columns: ['username', 'display_name', 'monthly_salary', 'created_at'],
          where: 'IFNULL(monthly_salary, 0) > 0');
      final out = <SalaryLine>[];
      for (final x in r) {
        final created = DateTime.tryParse('${x['created_at'] ?? ''}');
        if (created != null && !created.isBefore(end)) continue;
        final dn = '${x['display_name'] ?? ''}'.trim();
        out.add(SalaryLine(dn.isEmpty ? '${x['username']}' : dn, (x['monthly_salary'] as num).toDouble()));
      }
      out.sort((a, b) => b.amount.compareTo(a.amount));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// مجموع رواتب سنة (الأشهر حتى الشهر الحالي فقط إن كانت السنة الجارية).
  static Future<({double total, int months, List<SalaryLine> current})> forYear(int year) async {
    final now = DateTime.now();
    final last = year < now.year ? 12 : (year == now.year ? now.month : 0);
    var total = 0.0;
    List<SalaryLine> current = const [];
    for (var m = 1; m <= last; m++) {
      final lines = await forMonth(DateTime(year, m, 1));
      total += lines.fold(0.0, (s, l) => s + l.amount);
      if (m == last) current = lines;
    }
    return (total: total, months: last, current: current);
  }
}
