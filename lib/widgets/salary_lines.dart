// lib/widgets/salary_lines.dart
//
// 💵 سطرا «رواتب الموظفين» و«الربح بعد الرواتب» داخل التقرير الشهري/السنوي.
// لا يظهر شيء إن لم يُسجَّل راتب لأي موظف.

import 'package:flutter/material.dart';

import '../services/employee_salary.dart';
import 'report_kit.dart';

class SalaryProfitLines extends StatefulWidget {
  const SalaryProfitLines.month({super.key, required DateTime this.month, required this.profit, this.boxed = false})
      : year = null;
  const SalaryProfitLines.year({super.key, required int this.year, required this.profit, this.boxed = false})
      : month = null;

  final DateTime? month;
  final int? year;
  final double profit;

  /// بطاقة مستقلة (للتقرير السنوي) بدل أسطر داخل بطاقة قائمة
  final bool boxed;

  @override
  State<SalaryProfitLines> createState() => _SalaryProfitLinesState();
}

class _SalaryProfitLinesState extends State<SalaryProfitLines> {
  double? _total;
  String _hint = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SalaryProfitLines old) {
    super.didUpdateWidget(old);
    if (old.month != widget.month || old.year != widget.year) _load();
  }

  Future<void> _load() async {
    if (widget.month != null) {
      final lines = await EmployeeSalary.forMonth(widget.month!);
      if (!mounted) return;
      setState(() {
        _total = lines.fold<double>(0, (s, l) => s + l.amount);
        _hint = lines.length == 1 ? lines.first.name : '${lines.length} موظفين';
      });
    } else {
      final y = await EmployeeSalary.forYear(widget.year!);
      if (!mounted) return;
      setState(() {
        _total = y.total;
        _hint = y.months == 0 ? '' : '${y.months} شهر • ${y.current.length} موظفين حالياً';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _total ?? 0.0;
    if (t <= 0) return const SizedBox.shrink();
    final after = widget.profit - t;
    final lines = [
      ReportLine('− رواتب الموظفين', t,
          icon: Icons.payments_outlined, color: kSetRed, hint: 'من بطاقات الموظفين • $_hint'),
      ReportLine('الربح بعد الرواتب', after, bold: true, color: after >= 0 ? kSetGreen : kSetRed),
    ];
    if (!widget.boxed) return Column(children: [const Divider(height: 18), ...lines]);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSetBorder),
      ),
      child: Column(children: [
        ReportLine('الربح قبل الرواتب', widget.profit, icon: Icons.trending_up_rounded),
        ...lines,
      ]),
    );
  }
}
