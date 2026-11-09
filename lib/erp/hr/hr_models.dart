// lib/erp/hr/hr_models.dart
//
// 👥 الموارد البشرية — النماذج وحساب الراتب (دوال صافية مختبَرة). المبالغ بالفلس.
//
//   صافي الراتب = الأساسي + المكافأة − الخصم − السلف غير المخصومة حتى نهاية الشهر.
//   صرف السلفة سند مصروف على حساب الرواتب، وصرف الراتب سند بالصافي على الحساب نفسه،
//   فمجموع مصروف الرواتب للشهر = الأساسي + المكافأة − الخصم (السلفة لا تُحتسب مرتين).

class HrEmployee {
  HrEmployee({this.id, required this.name, this.phone = '', this.job = '', required this.salaryFils, this.username, this.active = true, DateTime? startDate})
      : startDate = startDate ?? DateTime.now();
  final int? id;
  final String name, phone, job;
  final int salaryFils;

  /// اسم دخوله في البرنامج (اختياري) — لمسابقات المبيعات.
  final String? username;
  final bool active;
  final DateTime startDate;

  Map<String, Object?> toMap() => {
        'name': name.trim(),
        'phone': phone.trim(),
        'job': job.trim(),
        'salary_fils': salaryFils,
        'username': (username ?? '').trim().isEmpty ? null : username!.trim(),
        'active': active ? 1 : 0,
        'start_date': startDate.toIso8601String(),
      };

  factory HrEmployee.fromMap(Map<String, Object?> m) => HrEmployee(
        id: m['id'] as int?,
        name: '${m['name'] ?? ''}',
        phone: '${m['phone'] ?? ''}',
        job: '${m['job'] ?? ''}',
        salaryFils: (m['salary_fils'] as num?)?.toInt() ?? 0,
        username: m['username'] as String?,
        active: (m['active'] as int? ?? 1) == 1,
        startDate: DateTime.tryParse('${m['start_date']}'),
      );
}

class HrAdvance {
  HrAdvance(this.id, this.employeeId, this.date, this.amountFils, this.note, this.payslipId);
  final int id, employeeId, amountFils;
  final DateTime date;
  final String note;
  final int? payslipId;
}

/// قسيمة راتب محسوبة (قبل الحفظ أو بعده).
class Payslip {
  const Payslip({
    required this.employeeId,
    required this.month,
    required this.baseFils,
    this.bonusFils = 0,
    this.deductionFils = 0,
    this.advancesFils = 0,
  });
  final int employeeId;

  /// yyyy-MM
  final String month;
  final int baseFils, bonusFils, deductionFils, advancesFils;

  int get netFils => baseFils + bonusFils - deductionFils - advancesFils;

  /// مصروف الشهر الكلي (السلف داخلة فيه لأنها صُرفت مصروفاً عند دفعها).
  int get expenseFils => baseFils + bonusFils - deductionFils;

  String? get error {
    if (baseFils < 0 || bonusFils < 0 || deductionFils < 0 || advancesFils < 0) return 'لا مبلغ سالب في القسيمة';
    if (netFils < 0) return 'السلف والخصم أكبر من الراتب — الصافي سالب';
    return null;
  }

  static String monthKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  /// آخر لحظة في الشهر yyyy-MM (لاختيار السلف المستحقة).
  static DateTime monthEnd(String month) {
    final p = month.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]) + 1, 1).subtract(const Duration(milliseconds: 1));
  }

  /// السلف غير المخصومة حتى نهاية الشهر.
  static int openAdvances(Iterable<HrAdvance> all, int employeeId, String month) {
    final end = monthEnd(month);
    return all
        .where((a) => a.employeeId == employeeId && a.payslipId == null && !a.date.isAfter(end))
        .fold(0, (s, a) => s + a.amountFils);
  }
}

/// دقائق العمل في يوم (حضور وانصراف). null إن لم يكتمل.
int? workedMinutes(DateTime? inAt, DateTime? outAt) {
  if (inAt == null || outAt == null || outAt.isBefore(inAt)) return null;
  return outAt.difference(inAt).inMinutes;
}
