// lib/erp/control/break_even_screen.dart
//
// 🎯 نقطة التعادل اليومية: كم يجب أن تبيع يومياً لتغطي مصاريفك الثابتة بهامشك الحالي.
//   • المصاريف الثابتة: قائمة يكتبها صاحب العمل (إيجار، رواتب، مولدة...)، أو متوسط
//     مصاريف الدفتر لآخر 3 أشهر مكتملة (كل حسابات المصاريف عدا كلفة البضاعة المباعة).
//   • الهامش: ربح البضاعة ÷ صافي المبيعات لآخر 30 يوماً (المحرك الموحّد للتقارير).
// للقراءة فقط: لا يكتب إلا إعداداته.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart' show fmtMoney, showError, showOk;
import '../../models/app_user.dart' show AppPermissions;
import '../../services/auth_service.dart';
import '../../services/reports_service.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import 'business_math.dart';
import 'control_common.dart';

class _FixedItem {
  _FixedItem(String name, double amount)
      : name = TextEditingController(text: name),
        amount = TextEditingController(text: amount > 0 ? fmtMoney(amount) : '');
  final TextEditingController name;
  final TextEditingController amount;
  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

class BreakEvenScreen extends StatefulWidget {
  const BreakEvenScreen({super.key});
  @override
  State<BreakEvenScreen> createState() => _BreakEvenScreenState();
}

class _BreakEvenScreenState extends State<BreakEvenScreen> {
  static const _kMode = 'be_mode';
  static const _kItems = 'be_fixed_items';

  String _mode = 'manual';
  final List<_FixedItem> _items = [];
  bool _loading = true;
  String? _error;

  double _ledgerAvg = 0;
  double _margin = 0;
  double _todaySales = 0;
  double _mtdSales = 0;
  double _mtdProfit = 0;

  bool get _allowed {
    final auth = AuthService();
    return auth.currentUser == null || auth.hasPermission(AppPermissions.viewCostProfit);
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  double get _manualTotal => _items.fold<double>(0, (s, i) => s + (parseMoney(i.amount.text) ?? 0));
  double get _fixed => _mode == 'ledger' ? _ledgerAvg : _manualTotal;

  Future<void> _init() async {
    try {
      _mode = (await ControlSettings.get(_kMode)) == 'ledger' ? 'ledger' : 'manual';
      final raw = await ControlSettings.get(_kItems);
      if (raw != null && raw.isNotEmpty) {
        for (final e in (jsonDecode(raw) as List)) {
          _items.add(_FixedItem('${e['name']}', ((e['amount'] as num?) ?? 0).toDouble()));
        }
      }
      if (_items.isEmpty) {
        for (final n in ['الإيجار', 'الرواتب', 'الكهرباء والمولدة']) {
          _items.add(_FixedItem(n, 0));
        }
      }
      await _loadNumbers();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadNumbers() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final svc = ReportsService();
    final last30 = await svc.loadFacts(from: today.subtract(const Duration(days: 29)), to: today);
    final t30 = last30.totals();
    _margin = t30.netSales.abs() > 0.01 ? t30.profit / t30.netSales * 100 : 0;
    final mtd = await svc.loadFacts(from: DateTime(now.year, now.month, 1), to: today);
    final tm = mtd.totals();
    _mtdSales = tm.netSales;
    _mtdProfit = tm.profit;
    final td = await svc.loadFacts(from: today, to: today);
    _todaySales = td.totals().netSales;
    _ledgerAvg = await _ledgerExpenses(now);
  }

  /// متوسط المصاريف الشهرية من الدفتر لآخر 3 أشهر مكتملة (عدا كلفة البضاعة المباعة).
  Future<double> _ledgerExpenses(DateTime now) async {
    final db = await controlDb();
    final from = DateTime(now.year, now.month - 3, 1);
    final to = DateTime(now.year, now.month, 1);
    final r = await db.rawQuery('''
      SELECT COALESCE(SUM(l.debit - l.credit), 0) AS s
      FROM journal_lines l
      JOIN journal_entries e ON e.id = l.entry_id
      JOIN accounts a ON a.id = l.account_id
      WHERE a.type = 'expense' AND COALESCE(a.system_key, '') <> 'cogs'
        AND e.entry_date >= ? AND e.entry_date < ?''', [from.toIso8601String(), to.toIso8601String()]);
    return d0(r.first['s']) / 3;
  }

  Future<void> _save() async {
    try {
      await ControlSettings.set(_kMode, _mode);
      await ControlSettings.set(
          _kItems,
          jsonEncode([
            for (final i in _items)
              if (i.name.text.trim().isNotEmpty) {'name': i.name.text.trim(), 'amount': parseMoney(i.amount.text) ?? 0},
          ]));
      if (mounted) showOk(context, 'حُفظت المصاريف الثابتة');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return const ErpPage(
        title: 'نقطة التعادل اليومية',
        icon: Icons.flag_rounded,
        body: EmptyState('تحتاج صلاحية «رؤية الكلفة والأرباح»', icon: Icons.lock_rounded),
      );
    }
    final now = DateTime.now();
    final be = BreakEven(fixedMonthly: _fixed, marginPct: _margin, daysInMonth: daysInMonthOf(now));
    final reqToDate = be.requiredToDate(now.day);
    return ErpPage(
      title: 'نقطة التعادل اليومية',
      subtitle: 'كم يجب أن تبيع يومياً لتغطي مصاريفك الثابتة',
      icon: Icons.flag_rounded,
      actions: [
        IconButton(
          tooltip: 'تحديث',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () async {
            setState(() => _loading = true);
            try {
              await _loadNumbers();
            } catch (e) {
              _error = '$e';
            }
            if (mounted) setState(() => _loading = false);
          },
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState('تعذّر الحساب: $_error', icon: Icons.error_outline_rounded)
              : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(spacing: 10, runSpacing: 10, children: [
                      StatCard(
                        label: 'المبيعات اللازمة يومياً',
                        value: be.valid ? fmtMoney(be.dailySales.roundToDouble()) : '—',
                        icon: Icons.flag_rounded,
                        color: ErpColors.navy,
                        hint: be.valid ? 'بهامش ${_margin.toStringAsFixed(1)}%' : 'اكتب المصاريف الثابتة',
                      ),
                      StatCard(
                        label: 'مبيعات اليوم',
                        value: fmtMoney(_todaySales),
                        icon: Icons.today_rounded,
                        color: !be.valid ? ErpColors.muted : (_todaySales >= be.dailySales ? ErpColors.green : ErpColors.orange),
                        hint: !be.valid
                            ? null
                            : (_todaySales >= be.dailySales
                                ? 'تجاوزت نقطة التعادل'
                                : 'ينقصك ${fmtMoney((be.dailySales - _todaySales).roundToDouble())}'),
                      ),
                      StatCard(
                        label: 'مبيعات الشهر حتى اليوم',
                        value: fmtMoney(_mtdSales),
                        icon: Icons.calendar_month_rounded,
                        color: !be.valid ? ErpColors.muted : (_mtdSales >= reqToDate ? ErpColors.green : ErpColors.red),
                        hint: be.valid ? 'اللازم حتى اليوم ${fmtMoney(reqToDate.roundToDouble())}' : null,
                      ),
                      StatCard(
                        label: 'تغطية المصاريف من ربح الشهر',
                        value: be.fixedMonthly > 0 ? '${be.coveredPct(_mtdProfit).toStringAsFixed(0)}%' : '—',
                        icon: Icons.pie_chart_rounded,
                        color: be.coveredPct(_mtdProfit) >= 100 ? ErpColors.green : ErpColors.purple,
                        hint: 'ربح البضاعة ${fmtMoney(_mtdProfit)} من ${fmtMoney(be.fixedMonthly)}',
                      ),
                    ]),
                  ),
                  if (_margin <= 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('لا هامش ربح موجب في آخر 30 يوماً — لا يمكن حساب نقطة التعادل.',
                          style: TextStyle(color: ErpColors.red)),
                    ),
                  ErpSection(
                    title: 'المصاريف الثابتة الشهرية',
                    icon: Icons.receipt_long_rounded,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SegmentedButton<String>(
                        segments: [
                          const ButtonSegment(value: 'manual', label: Text('أكتبها بنفسي'), icon: Icon(Icons.edit_rounded)),
                          ButtonSegment(
                              value: 'ledger',
                              label: Text('من الدفتر (${fmtMoney(_ledgerAvg.roundToDouble())})'),
                              icon: const Icon(Icons.menu_book_rounded)),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (s) => setState(() => _mode = s.first),
                      ),
                      const SizedBox(height: 8),
                      if (_mode == 'ledger')
                        const Text(
                          'متوسط آخر 3 أشهر مكتملة لكل حسابات المصاريف في الدفتر عدا كلفة البضاعة المباعة '
                          '(يشمل الخصم المسموح والعمولات وفروقات الجرد والصندوق والإهلاك إن وُجدت).',
                          style: TextStyle(fontSize: 12.5, color: ErpColors.muted, height: 1.5),
                        )
                      else ...[
                        for (var i = 0; i < _items.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              Expanded(child: TextBox(controller: _items[i].name, label: 'البند')),
                              const SizedBox(width: 8),
                              SizedBox(
                                  width: 170,
                                  child: MoneyField(
                                      controller: _items[i].amount, label: 'شهرياً', onChanged: (_) => setState(() {}))),
                              IconButton(
                                tooltip: 'حذف',
                                icon: const Icon(Icons.delete_outline_rounded, color: ErpColors.red),
                                onPressed: () => setState(() => _items.removeAt(i).dispose()),
                              ),
                            ]),
                          ),
                        Row(children: [
                          TextButton.icon(
                            onPressed: () => setState(() => _items.add(_FixedItem('', 0))),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('إضافة بند'),
                          ),
                          const Spacer(),
                          Text('المجموع ${fmtMoney(_manualTotal)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        ]),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: PrimaryButton(label: 'حفظ', icon: Icons.save_rounded, onPressed: _save),
                      ),
                    ]),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Text(
                      'الحساب: المبيعات اللازمة = المصاريف الثابتة ÷ هامش ربح البضاعة. الهامش من آخر 30 يوماً، '
                      'فإن تغيّرت أسعارك أو كلفتك يتغيّر الرقم معه.',
                      style: TextStyle(fontSize: 12, color: ErpColors.muted, height: 1.5),
                    ),
                  ),
                ]),
    );
  }
}
