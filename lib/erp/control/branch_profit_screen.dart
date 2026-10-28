// lib/erp/control/branch_profit_screen.dart
//
// 🏬 ربحية الفروع: لكل فرع صافي مبيعاته وربح بضاعته (من المحرك الموحّد للتقارير،
// حسب فرع الفاتورة أو فرع مخزنها) ثم مصاريفه من الدفتر (حسب فرع القيد)، والصافي.
// للقراءة فقط.
//
// حدود الدقة (تُعرض في الشاشة):
//   • الفاتورة بلا فرع ولا مخزن تُحسب على الفرع الرئيسي.
//   • المرتجع المستقل يتبع فرع فاتورته الأصلية، وبلا فاتورة: الفرع الرئيسي.
//   • المصاريف حسب فرع القيد؛ القيود المشتقة آلياً (عمولات، خصم مسموح، فروقات) تُسجَّل
//     على الفرع الرئيسي ما لم يُحدَّد غيره.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart' show fmtMoney, showError, PeriodBar;
import '../../models/app_user.dart' show AppPermissions;
import '../../services/auth_service.dart';
import '../../services/reports/sales_facts.dart';
import '../../services/reports_service.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import 'control_common.dart';

class _BranchRow {
  _BranchRow(this.id, this.name);
  final int id;
  final String name;
  final SalesTotals sales = SalesTotals();
  double expenses = 0;
  double get net => sales.profit - expenses;
}

class BranchProfitScreen extends StatefulWidget {
  const BranchProfitScreen({super.key});
  @override
  State<BranchProfitScreen> createState() => _BranchProfitScreenState();
}

class _BranchProfitScreenState extends State<BranchProfitScreen> {
  DateTime? _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  List<_BranchRow> _rows = const [];
  bool _loading = true;

  bool get _allowed {
    final auth = AuthService();
    return auth.currentUser == null || auth.hasPermission(AppPermissions.viewCostProfit);
  }

  @override
  void initState() {
    super.initState();
    if (_allowed) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final db = await controlDb();
      final from = _from ?? DateTime(2000);
      final branches = await db.query('branches', orderBy: 'id');
      final rows = <int, _BranchRow>{
        for (final b in branches) b['id'] as int: _BranchRow(b['id'] as int, '${b['name']}'),
      };
      final mainId = rows.isEmpty ? 1 : rows.keys.first;
      rows.putIfAbsent(mainId, () => _BranchRow(mainId, 'الفرع الرئيسي'));

      // فرع كل فاتورة: فرعها، وإلا فرع مخزنها، وإلا الرئيسي
      final inv = await db.rawQuery('''
        SELECT i.id, COALESCE(i.branch_id, w.branch_id) AS b
        FROM invoices i LEFT JOIN warehouses w ON w.id = i.warehouse_id
        WHERE i.invoice_date >= ? AND i.invoice_date < ?''', [isoDay(DateTime(2000)), isoDayAfter(_to)]);
      final branchOf = <int, int>{for (final r in inv) r['id'] as int: (r['b'] as int?) ?? mainId};
      int bOf(int? invoiceId) {
        final b = invoiceId == null ? null : branchOf[invoiceId];
        return (b != null && rows.containsKey(b)) ? b : mainId;
      }

      final facts = await ReportsService().loadFacts(from: from, to: _to);
      for (final i in facts.invoices) {
        rows[bOf(i.id)]!.sales.addInvoice(i);
      }
      for (final r in facts.returns) {
        rows[bOf(r.originalInvoiceId)]!.sales.addReturn(r);
      }
      for (final e in facts.edits) {
        rows[bOf(e.invoiceId)]!.sales.addEdit(e);
      }

      final exp = await db.rawQuery('''
        SELECT e.branch_id AS b, COALESCE(SUM(l.debit - l.credit), 0) AS s
        FROM journal_lines l
        JOIN journal_entries e ON e.id = l.entry_id
        JOIN accounts a ON a.id = l.account_id
        WHERE a.type = 'expense' AND COALESCE(a.system_key, '') <> 'cogs'
          AND e.entry_date >= ? AND e.entry_date < ?
        GROUP BY e.branch_id''', [isoDay(from), isoDayAfter(_to)]);
      for (final r in exp) {
        final b = r['b'] as int?;
        rows[(b != null && rows.containsKey(b)) ? b : mainId]!.expenses += d0(r['s']);
      }
      if (!mounted) return;
      setState(() {
        _rows = rows.values.toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return const ErpPage(
        title: 'ربحية الفروع',
        icon: Icons.store_mall_directory_rounded,
        body: EmptyState('تحتاج صلاحية «رؤية الكلفة والأرباح»', icon: Icons.lock_rounded),
      );
    }
    final total = _BranchRow(0, 'المجموع');
    for (final r in _rows) {
      total.expenses += r.expenses;
    }
    final totNet = _rows.fold<double>(0, (s, r) => s + r.sales.netSales);
    final totProfit = _rows.fold<double>(0, (s, r) => s + r.sales.profit);
    return ErpPage(
      title: 'ربحية الفروع',
      subtitle: 'ربح البضاعة لكل فرع بعد مصاريفه',
      icon: Icons.store_mall_directory_rounded,
      actions: [IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      body: Column(children: [
        PeriodBar(
            from: _from,
            to: _to,
            onChanged: (f, t) {
              _from = f;
              _to = t;
              _load();
            }),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                  ErpSection(
                    title: 'الفروع (${_rows.length})',
                    icon: Icons.table_chart_rounded,
                    child: SimpleTable(
                      headers: const ['الفرع', 'الفواتير', 'صافي المبيعات', 'ربح البضاعة', 'الهامش', 'المصاريف', 'الصافي'],
                      numericColumns: const {1, 2, 3, 4, 5, 6},
                      rows: [
                        for (final r in _rows)
                          [
                            r.name,
                            '${r.sales.invoiceCount}',
                            fmtMoney(r.sales.netSales),
                            fmtMoney(r.sales.profit),
                            '${r.sales.margin.toStringAsFixed(1)}%',
                            fmtMoney(r.expenses),
                            fmtMoney(r.net),
                          ],
                      ],
                      footer: [
                        'المجموع',
                        '${_rows.fold<int>(0, (s, r) => s + r.sales.invoiceCount)}',
                        fmtMoney(totNet),
                        fmtMoney(totProfit),
                        totNet.abs() > 0 ? '${(totProfit / totNet * 100).toStringAsFixed(1)}%' : '—',
                        fmtMoney(total.expenses),
                        fmtMoney(totProfit - total.expenses),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Text(
                      'الفاتورة تُنسب لفرعها أو لفرع مخزنها، وإلا للفرع الرئيسي. المصاريف حسب فرع القيد في الدفتر '
                      '(كل حسابات المصاريف عدا كلفة البضاعة المباعة)؛ ما يُرحَّل آلياً بلا فرع يُحسب على الفرع الرئيسي.',
                      style: TextStyle(fontSize: 12, color: ErpColors.muted, height: 1.5),
                    ),
                  ),
                ]),
        ),
      ]),
    );
  }
}
