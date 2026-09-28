// lib/erp/reports/finance_reports.dart
//
// 📊 تقارير مالية على طريقة سهل — قراءة فقط:
//   • تحليل المصاريف: إجمالي الفترة، «أين ذهبت الأموال» بالنسب، وتفاصيل الحركات.
//   • حركة الصندوق والخزنة: رصيد أول المدة، الوارد، الصادر، الرصيد، لكل صندوق أو للكل.
//   • تقرير المبيعات التفصيلي: كل فاتورة بمخزنها وطريقة دفعها والمقبوض والآجل والربح.
//   • أرصدة الديون: الزبائن والموردون في كشف واحد مع «تسديد سريع».
// الأرقام من الدفتر العام (بعد ترحيل تلقائي) أو من الفواتير نفسها.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart' show roundMoney;
import '../../accounting/posting_engine.dart';
import '../../accounting/screens/acc_ui.dart';
import '../../accounting/vouchers_service.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../debts/customer_statement_screen.dart';
import '../debts/receipt_screen.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../report_export.dart';

/// ترحيل صامت قبل تقارير الدفتر (على السيرفر/الجهاز المستقل فقط).
Future<void> _freshLedger() async {
  if (!canRunPosting) return;
  try {
    await PostingEngine().syncAll();
  } catch (_) {}
}

const _palette = [
  Color(0xFF0F3460),
  Color(0xFFE94560),
  Color(0xFF1B6CA8),
  Color(0xFFB7791F),
  Color(0xFF0E7C61),
  Color(0xFF5B3CC4),
  Color(0xFF00B4D8),
  Color(0xFFC0392B),
];

// ═══════════════════════════ تحليل المصاريف ═══════════════════════════

class ExpenseAnalysisScreen extends StatefulWidget {
  const ExpenseAnalysisScreen({super.key});
  @override
  State<ExpenseAnalysisScreen> createState() => _ExpenseAnalysisScreenState();
}

class _ExpenseAnalysisScreenState extends State<ExpenseAnalysisScreen> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  bool _withCogs = false;
  bool _loading = true;
  List<Map<String, Object?>> _byAcc = const [];
  List<Map<String, Object?>> _lines = const [];

  @override
  void initState() {
    super.initState();
    _load(post: true);
  }

  Future<void> _load({bool post = false}) async {
    setState(() => _loading = true);
    if (post) await _freshLedger();
    final db = await erpDb();
    final cogsFilter = _withCogs ? '' : "AND COALESCE(a.system_key, '') != 'cogs'";
    final args = [isoDay(_from), isoDayAfter(_to)];
    final by = await db.rawQuery('''
      SELECT a.id, a.code, a.name, COALESCE(SUM(l.debit - l.credit), 0) AS amt, COUNT(*) AS n
      FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id JOIN accounts a ON a.id = l.account_id
      WHERE a.type = 'expense' AND e.entry_date >= ? AND e.entry_date < ? AND e.source_type != 'year_close' $cogsFilter
      GROUP BY a.id HAVING ABS(amt) > 0.004 ORDER BY amt DESC''', args);
    final lines = await db.rawQuery('''
      SELECT e.entry_date, a.name AS account, (l.debit - l.credit) AS amt, e.source_type, e.description, l.memo
      FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id JOIN accounts a ON a.id = l.account_id
      WHERE a.type = 'expense' AND e.entry_date >= ? AND e.entry_date < ? AND e.source_type != 'year_close' $cogsFilter
      ORDER BY e.entry_date DESC, l.id DESC LIMIT 2000''', args);
    if (!mounted) return;
    setState(() {
      _byAcc = by;
      _lines = lines;
      _loading = false;
    });
  }

  static const _sourceLabels = {
    'voucher': 'سند',
    'manual': 'قيد يدوي',
    'stock_doc': 'مستند مخزني',
    'invoice': 'فاتورة',
    'invoice_commission': 'عمولة بائع',
    'supplier_tx': 'حركة مورد',
    'customer_tx': 'حركة عميل',
    'fx_reval': 'فروقات عملة',
    'sales_return': 'مرتجع',
  };

  @override
  Widget build(BuildContext context) {
    final total = _byAcc.fold<double>(0, (s, r) => s + d0(r['amt']));
    final top = _byAcc.isEmpty ? null : _byAcc.first;
    return ErpPage(
      title: 'تحليل المصاريف',
      subtitle: 'أين ذهبت الأموال؟ ${fmtDate(_from)} — ${fmtDate(_to)}',
      icon: Icons.pie_chart_rounded,
      actions: [
        ...exportActions(context,
            title: 'تحليل المصاريف',
            subtitle: () => '${fmtDate(_from)} — ${fmtDate(_to)}',
            headers: () => ['التاريخ', 'بند المصروف', 'المبلغ', 'المصدر', 'البيان'],
            rows: () => [
                  for (final l in _lines)
                    [
                      fmtDate(parseDate(l['entry_date'])),
                      '${l['account']}',
                      fmtMoney(d0(l['amt'])),
                      _sourceLabels[l['source_type']] ?? '${l['source_type']}',
                      '${l['memo'] ?? l['description'] ?? ''}',
                    ],
                ],
            footer: () => ['الإجمالي', '', fmtMoney(total), '', '']),
      ],
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'إجمالي المصاريف', value: fmtMoney(total), icon: Icons.money_off_rounded, color: ErpColors.red),
        StatCard(label: 'عدد البنود', value: '${_byAcc.length}', icon: Icons.category_outlined, color: ErpColors.blue),
        if (top != null)
          StatCard(
              label: 'الأعلى',
              value: '${top['name']}',
              hint: fmtMoney(d0(top['amt'])),
              icon: Icons.trending_up_rounded,
              color: ErpColors.orange),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  DateButton(label: 'من', value: _from, onChanged: (d) {
                    _from = d;
                    _load();
                  }),
                  DateButton(label: 'إلى', value: _to, onChanged: (d) {
                    _to = d;
                    _load();
                  }),
                  FilterChip(
                    label: const Text('تضمين كلفة البضاعة المباعة'),
                    selected: _withCogs,
                    onSelected: (v) {
                      _withCogs = v;
                      _load();
                    },
                  ),
                ]),
              ),
              ErpSection(
                title: 'أين ذهبت الأموال؟',
                icon: Icons.donut_large_rounded,
                color: ErpColors.red,
                child: _byAcc.isEmpty
                    ? const Text('لا توجد مصاريف في الفترة', style: TextStyle(color: ErpColors.muted))
                    : Column(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            height: 18,
                            child: Row(children: [
                              for (var i = 0; i < _byAcc.length; i++)
                                if (d0(_byAcc[i]['amt']) > 0)
                                  Expanded(
                                    flex: math.max(1, (d0(_byAcc[i]['amt']) / (total <= 0 ? 1 : total) * 1000).round()),
                                    child: Container(color: _palette[i % _palette.length]),
                                  ),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 14),
                        for (var i = 0; i < _byAcc.length; i++) _barRow(_byAcc[i], total, _palette[i % _palette.length]),
                      ]),
              ),
              ErpSection(
                title: 'تفاصيل حركات المصاريف',
                icon: Icons.list_alt_rounded,
                child: SimpleTable(
                  headers: const ['التاريخ', 'البند', 'المبلغ', 'المصدر', 'البيان'],
                  numericColumns: const {2},
                  rows: [
                    for (final l in _lines.take(300))
                      [
                        fmtDate(parseDate(l['entry_date'])),
                        '${l['account']}',
                        fmtMoney(d0(l['amt'])),
                        _sourceLabels[l['source_type']] ?? '${l['source_type']}',
                        '${l['memo'] ?? l['description'] ?? ''}',
                      ],
                  ],
                ),
              ),
            ]),
    );
  }

  Widget _barRow(Map<String, Object?> r, double total, Color c) {
    final v = d0(r['amt']);
    final pct = total <= 0 ? 0.0 : v / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        SizedBox(width: 190, child: Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0).toDouble(), minHeight: 10, color: c, backgroundColor: ErpColors.bg),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 170,
          child: Text('${fmtMoney(v)} (${(pct * 100).toStringAsFixed(1)}%)',
              textAlign: TextAlign.left, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}

// ═══════════════════════════ حركة الصندوق والخزنة ═══════════════════════════

class CashMovementScreen extends StatefulWidget {
  const CashMovementScreen({super.key});
  @override
  State<CashMovementScreen> createState() => _CashMovementScreenState();
}

class _CashMovementScreenState extends State<CashMovementScreen> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  int? _boxId; // null = كل الصناديق والبنوك
  List<CashBox> _boxes = const [];
  double _opening = 0, _in = 0, _out = 0;
  List<Map<String, Object?>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _freshLedger();
    _boxes = await VouchersService().cashBoxes(activeOnly: false);
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final db = await erpDb();
    final accs = [
      for (final b in _boxes)
        if (_boxId == null || b.id == _boxId) b.accountId,
    ];
    if (accs.isEmpty) {
      setState(() {
        _rows = const [];
        _loading = false;
      });
      return;
    }
    final ph = List.filled(accs.length, '?').join(',');
    final op = await db.rawQuery('''
      SELECT COALESCE(SUM(l.debit - l.credit), 0) AS b FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      WHERE l.account_id IN ($ph) AND e.entry_date < ?''', [...accs, isoDay(_from)]);
    // صافي كل قيد على الصناديق المختارة: التحويل بين صندوقين (عند «الكل») صافيه صفر فلا يُعد وارداً وصادراً
    final rows = await db.rawQuery('''
      SELECT e.id, e.entry_date, e.source_type, e.description, MIN(l.memo) AS memo,
             SUM(l.debit - l.credit) AS net, GROUP_CONCAT(DISTINCT a.name) AS box
      FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id JOIN accounts a ON a.id = l.account_id
      WHERE l.account_id IN ($ph) AND e.entry_date >= ? AND e.entry_date < ?
      GROUP BY e.id HAVING ABS(net) > 0.004
      ORDER BY e.entry_date, e.id''', [...accs, isoDay(_from), isoDayAfter(_to)]);
    var bal = d0(op.first['b']);
    var tin = 0.0, tout = 0.0;
    final out = <Map<String, Object?>>[];
    for (final r0 in rows) {
      final net = d0(r0['net']);
      final r = {...r0, 'debit': net > 0 ? net : 0.0, 'credit': net < 0 ? -net : 0.0};
      final dr = d0(r['debit']), cr = d0(r['credit']);
      tin += dr;
      tout += cr;
      bal += dr - cr;
      out.add({...r, 'balance': bal});
    }
    if (!mounted) return;
    setState(() {
      _opening = d0(op.first['b']);
      _in = tin;
      _out = tout;
      _rows = out.reversed.toList();
      _loading = false;
    });
  }

  static const _kinds = {
    'invoice': 'فاتورة مبيعات',
    'customer_tx': 'حركة عميل',
    'voucher': 'سند',
    'purchase_invoice': 'فاتورة شراء',
    'supplier_tx': 'حركة مورد',
    'sales_return': 'مرتجع',
    'manual': 'قيد يدوي',
  };

  @override
  Widget build(BuildContext context) {
    final closing = _opening + _in - _out;
    return ErpPage(
      title: 'حركة الصندوق والخزنة',
      subtitle: '${fmtDate(_from)} — ${fmtDate(_to)}',
      icon: Icons.account_balance_wallet_rounded,
      actions: [
        ...exportActions(context,
            title: 'حركة الصندوق والخزنة',
            subtitle: () =>
                '${_boxId == null ? 'كل الصناديق والبنوك' : _boxes.firstWhere((b) => b.id == _boxId).name} • ${fmtDate(_from)} — ${fmtDate(_to)}',
            headers: () => ['التاريخ', 'الحساب', 'نوع الحركة', 'وارد (+)', 'صادر (-)', 'الرصيد', 'البيان'],
            rows: () => [
                  for (final r in _rows.reversed)
                    [
                      fmtDate(parseDate(r['entry_date'])),
                      '${r['box']}',
                      _kinds[r['source_type']] ?? '${r['source_type']}',
                      d0(r['debit']) > 0 ? fmtMoney(d0(r['debit'])) : '',
                      d0(r['credit']) > 0 ? fmtMoney(d0(r['credit'])) : '',
                      fmtMoney(d0(r['balance'])),
                      '${r['memo'] ?? r['description'] ?? ''}',
                    ],
                ],
            footer: () => ['', '', 'الإجمالي', fmtMoney(_in), fmtMoney(_out), fmtMoney(closing), '']),
      ],
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'رصيد بداية المدة', value: fmtMoney(_opening), icon: Icons.flag_outlined, color: ErpColors.muted),
        StatCard(label: 'الداخل (مقبوضات)', value: fmtMoney(_in), icon: Icons.south_west_rounded, color: ErpColors.green),
        StatCard(label: 'الخارج (مدفوعات)', value: fmtMoney(_out), icon: Icons.north_east_rounded, color: ErpColors.red),
        StatCard(
            label: 'الرصيد الحالي',
            value: fmtMoney(closing),
            icon: Icons.account_balance_wallet_outlined,
            color: closing < 0 ? ErpColors.red : ErpColors.navy),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DateButton(label: 'من', value: _from, onChanged: (d) {
              _from = d;
              _load();
            }),
            DateButton(label: 'إلى', value: _to, onChanged: (d) {
              _to = d;
              _load();
            }),
            DropBox<int?>(
              label: 'الصندوق / البنك',
              value: _boxId,
              width: 260,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('كل الصناديق والبنوك')),
                for (final b in _boxes) DropdownMenuItem<int?>(value: b.id, child: Text(b.name)),
              ],
              onChanged: (v) {
                _boxId = v;
                _load();
              },
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? const EmptyState('لا توجد حركات في الفترة', icon: Icons.account_balance_wallet_outlined)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      itemCount: _rows.length,
                      itemBuilder: (_, i) {
                        final r = _rows[i];
                        final dr = d0(r['debit']), cr = d0(r['credit']);
                        final inflow = dr > 0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border(right: BorderSide(color: inflow ? ErpColors.green : ErpColors.red, width: 4)),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Icon(inflow ? Icons.south_west_rounded : Icons.north_east_rounded,
                                color: inflow ? ErpColors.green : ErpColors.red),
                            title: Text('${r['memo'] ?? r['description'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${fmtDate(parseDate(r['entry_date']))} • ${r['box']} • ${_kinds[r['source_type']] ?? r['source_type']}'),
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('${inflow ? '+' : '−'}${fmtMoney(inflow ? dr : cr)}',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: inflow ? ErpColors.green : ErpColors.red)),
                              Text('الرصيد ${fmtMoney(d0(r['balance']))}',
                                  style: const TextStyle(fontSize: 11, color: ErpColors.muted)),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════ تقرير المبيعات التفصيلي ═══════════════════════════

class SalesDetailReportScreen extends StatefulWidget {
  const SalesDetailReportScreen({super.key});
  @override
  State<SalesDetailReportScreen> createState() => _SalesDetailReportScreenState();
}

class _SalesDetailReportScreenState extends State<SalesDetailReportScreen> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  int? _warehouseId;
  bool _allWarehouses = true;
  String? _payment; // null | نقد | دين
  List<Map<String, Object?>> _rows = const [];
  bool _loading = true;

  bool get _showProfit => AuthService().hasPermission(AppPermissions.viewCostProfit);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_allWarehouses && _warehouseId == null) return; // ينتظر اختيار المخزن
    setState(() => _loading = true);
    final db = await erpDb();
    final where = <String>[
      "i.status = 'محفوظة'",
      'COALESCE(i.is_deleted, 0) = 0',
      'i.invoice_date >= ?',
      'i.invoice_date < ?',
    ];
    final args = <Object?>[isoDay(_from), isoDayAfter(_to)];
    if (!_allWarehouses) {
      final main = await db.query('warehouses', columns: ['id'], where: 'is_default = 1', orderBy: 'id', limit: 1);
      final mainId = main.isEmpty ? 1 : main.first['id'] as int;
      if (_warehouseId == mainId) {
        where.add('(i.warehouse_id IS NULL OR i.warehouse_id = ?)');
      } else {
        where.add('i.warehouse_id = ?');
      }
      args.add(_warehouseId);
    }
    if (_payment != null) {
      where.add('i.payment_type = ?');
      args.add(_payment);
    }
    // الكلفة بنفس منطق تقرير المبيعات اليومي في البرنامج
    final rows = await db.rawQuery('''
      SELECT i.id, i.invoice_number, i.invoice_date, i.customer_name, i.payment_type, i.total_amount,
             COALESCE(i.discount, 0) AS discount, COALESCE(i.loading_fee, 0) AS loading_fee,
             COALESCE(i.amount_paid_on_invoice, 0) AS paid, w.name AS warehouse,
             (SELECT COALESCE(SUM(ii.item_total), 0) FROM invoice_items ii WHERE ii.invoice_id = i.id) AS gross,
             (SELECT COALESCE(SUM(
                CASE WHEN COALESCE(ii.actual_cost_price, 0) > 0
                     -- كلفة الوحدة المباعة (قطعة أو كرتون أو لفة) × عدد الوحدات المباعة
                     THEN ii.actual_cost_price * (CASE WHEN COALESCE(ii.quantity_large_unit, 0) > 0
                                                       THEN ii.quantity_large_unit ELSE COALESCE(ii.quantity_individual, 0) END)
                     WHEN COALESCE(p.cost_price, 0) > 0
                     -- كلفة الوحدة الأساسية × الكمية بالوحدة الأساسية
                     THEN p.cost_price * (COALESCE(ii.quantity_individual, 0) + COALESCE(ii.quantity_large_unit, 0)
                          * CASE WHEN COALESCE(ii.units_in_large_unit, 0) > 0 THEN ii.units_in_large_unit ELSE 1 END)
                     ELSE ii.item_total * 0.9 END), 0)
              FROM invoice_items ii LEFT JOIN products p ON p.name = ii.product_name
              WHERE ii.invoice_id = i.id) AS cost
      FROM invoices i LEFT JOIN warehouses w ON w.id = i.warehouse_id
      WHERE ${where.join(' AND ')}
      ORDER BY i.invoice_date DESC, i.id DESC LIMIT 5000''', args);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  double _paid(Map<String, Object?> r) =>
      r['payment_type'] == 'نقد' ? d0(r['total_amount']) : math.min(d0(r['paid']), d0(r['total_amount']));
  double _profit(Map<String, Object?> r) => roundMoney(d0(r['gross']) - d0(r['discount']) - d0(r['cost']));

  @override
  Widget build(BuildContext context) {
    final total = _rows.fold<double>(0, (s, r) => s + d0(r['total_amount']));
    final paid = _rows.fold<double>(0, (s, r) => s + _paid(r));
    final profit = _rows.fold<double>(0, (s, r) => s + _profit(r));
    final headers = [
      'رقم الفاتورة',
      'التاريخ',
      'الزبون',
      'المخزن',
      'طريقة الدفع',
      'الإجمالي',
      'المدفوع',
      'المتبقي',
      if (_showProfit) 'الربح',
    ];
    List<String> row(Map<String, Object?> r) => [
          '${r['invoice_number'] ?? '#${r['id']}'}',
          fmtDate(parseDate(r['invoice_date'])),
          '${r['customer_name'] ?? ''}',
          '${r['warehouse'] ?? 'الرئيسي'}',
          '${r['payment_type'] ?? ''}',
          fmtMoney(d0(r['total_amount'])),
          fmtMoney(_paid(r)),
          fmtMoney(d0(r['total_amount']) - _paid(r)),
          if (_showProfit) fmtMoney(_profit(r)),
        ];
    return ErpPage(
      title: 'تقرير المبيعات التفصيلي',
      subtitle: '${fmtDate(_from)} — ${fmtDate(_to)} • ${_rows.length} فاتورة',
      icon: Icons.receipt_long_rounded,
      actions: [
        ...exportActions(context,
            title: 'كشف المبيعات',
            subtitle: () => '${fmtDate(_from)} — ${fmtDate(_to)}',
            headers: () => headers,
            rows: () => [for (final r in _rows) row(r)],
            footer: () => [
                  'الإجمالي',
                  '',
                  '',
                  '',
                  '',
                  fmtMoney(total),
                  fmtMoney(paid),
                  fmtMoney(total - paid),
                  if (_showProfit) fmtMoney(profit),
                ]),
      ],
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'إجمالي المبيعات', value: fmtMoney(total), icon: Icons.point_of_sale_rounded, color: ErpColors.navy),
        StatCard(label: 'المقبوضات', value: fmtMoney(paid), icon: Icons.payments_outlined, color: ErpColors.green),
        StatCard(label: 'الديون المتبقية (آجل)', value: fmtMoney(total - paid), icon: Icons.schedule, color: ErpColors.orange),
        if (_showProfit)
          StatCard(
              label: 'صافي الربح (تقديري)',
              value: fmtMoney(profit),
              icon: Icons.trending_up_rounded,
              color: profit >= 0 ? ErpColors.green : ErpColors.red),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DateButton(label: 'من', value: _from, onChanged: (d) {
              _from = d;
              _load();
            }),
            DateButton(label: 'إلى', value: _to, onChanged: (d) {
              _to = d;
              _load();
            }),
            FilterChip(
              label: const Text('كل المخازن'),
              selected: _allWarehouses,
              onSelected: (v) {
                _allWarehouses = v;
                _load();
              },
            ),
            if (!_allWarehouses)
              WarehouseDropdown(
                  value: _warehouseId,
                  onChanged: (w) {
                    _warehouseId = w?.id;
                    _load();
                  }),
            SegmentedButton<String?>(
              segments: const [
                ButtonSegment(value: null, label: Text('الكل')),
                ButtonSegment(value: 'نقد', label: Text('نقد')),
                ButtonSegment(value: 'دين', label: Text('آجل')),
              ],
              selected: {_payment},
              onSelectionChanged: (s) {
                _payment = s.first;
                _load();
              },
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? const EmptyState('لا توجد فواتير في الفترة')
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      SimpleTable(
                        headers: headers,
                        numericColumns: {5, 6, 7, if (_showProfit) 8},
                        rows: [for (final r in _rows.take(500)) row(r)],
                      ),
                      if (_rows.length > 500)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('يُعرض أول 500 فاتورة — التصدير يشمل الكل',
                              style: TextStyle(color: ErpColors.muted)),
                        ),
                      if (_showProfit)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('الربح تقديري: سعر البيع − كلفة البند المسجّلة عند البيع (أو كلفة المادة الحالية).',
                              style: TextStyle(color: ErpColors.muted, fontSize: 12)),
                        ),
                    ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════ أرصدة الديون (زبائن + موردون) ═══════════════════════════

class PartyBalancesScreen extends StatefulWidget {
  const PartyBalancesScreen({super.key});
  @override
  State<PartyBalancesScreen> createState() => _PartyBalancesScreenState();
}

class _PartyBalancesScreenState extends State<PartyBalancesScreen> {
  String _type = 'all'; // all | customer | supplier
  String _status = 'nonzero'; // nonzero | all | debit | credit
  String _q = '';
  List<Map<String, Object?>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = await erpDb();
    final c = await db.rawQuery('''
      SELECT id, name, phone, current_total_debt AS bal FROM customers WHERE COALESCE(is_deleted, 0) = 0 ORDER BY name''');
    final s = await db.rawQuery('SELECT id, name, phone, total_debt_iqd AS bal, total_debt_usd AS usd FROM suppliers ORDER BY name');
    final rows = <Map<String, Object?>>[
      for (final r in c) {...r, 'type': 'customer', 'usd': 0.0},
      for (final r in s) {...r, 'type': 'supplier'},
    ];
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  List<Map<String, Object?>> get _visible {
    final t = _q.trim();
    return _rows.where((r) {
      if (_type != 'all' && r['type'] != _type) return false;
      final st = _state(r);
      if (_status == 'nonzero' && st == 'مُصفَّر') return false;
      // مدين = نطلبه، دائن = له/يطلبنا (بمنظور المحل للزبون والمورد معاً)
      if (_status == 'debit' && !st.startsWith('نطلبه')) return false;
      if (_status == 'credit' && (st == 'مُصفَّر' || st.startsWith('نطلبه'))) return false;
      if (t.isNotEmpty && !'${r['name']}'.contains(t) && !'${r['phone'] ?? ''}'.contains(t)) return false;
      return true;
    }).toList();
  }

  /// للزبون: موجب = نطلبه. للمورد: موجب = يطلبنا.
  String _state(Map<String, Object?> r) {
    final b = d0(r['bal']), u = d0(r['usd']);
    if (b.abs() < 0.005 && u.abs() < 0.005) return 'مُصفَّر';
    if (r['type'] == 'customer') return b > 0 ? 'نطلبه (مدين)' : 'له رصيد (دائن)';
    final dominant = b.abs() >= 0.005 ? b : u;
    return dominant >= 0 ? 'يطلبنا (دائن)' : 'نطلبه (مدين)';
  }

  Future<void> _quickPay(Map<String, Object?> r) async {
    final party = PartyLite(r['id'] as int, '${r['name']}', r['phone'] as String?, d0(r['bal']), balanceUsd: d0(r['usd']));
    if (r['type'] == 'customer') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptScreen(customer: party)));
    } else {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => SupplierPaymentScreen(supplier: party)));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final vis = _visible;
    final ar = _rows.where((r) => r['type'] == 'customer').fold<double>(0, (s, r) => s + math.max(0, d0(r['bal'])));
    final ap = _rows.where((r) => r['type'] == 'supplier').fold<double>(0, (s, r) => s + d0(r['bal']));
    final apUsd = _rows.where((r) => r['type'] == 'supplier').fold<double>(0, (s, r) => s + d0(r['usd']));
    return ErpPage(
      title: 'أرصدة الديون',
      subtitle: 'الزبائن والموردون في كشف واحد',
      icon: Icons.balance_rounded,
      actions: [
        ...exportActions(context,
            title: 'أرصدة الديون',
            headers: () => ['ت', 'الاسم', 'النوع', 'حالة الرصيد', 'المبلغ (IQD)', 'بالدولار'],
            rows: () => [
                  for (var i = 0; i < vis.length; i++)
                    [
                      '${i + 1}',
                      '${vis[i]['name']}',
                      vis[i]['type'] == 'customer' ? 'زبون' : 'مورد',
                      _state(vis[i]),
                      fmtMoney(d0(vis[i]['bal']).abs()),
                      d0(vis[i]['usd']).abs() > 0.004 ? fmtMoney(d0(vis[i]['usd'])) : '',
                    ],
                ]),
      ],
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'ديون الزبائن (نطلبها)', value: fmtMoney(ar), icon: Icons.people_alt_rounded, color: ErpColors.red),
        StatCard(
            label: 'ديون الموردين (تطلبنا)',
            value: fmtMoney(ap),
            hint: apUsd.abs() > 0.004 ? '+ \$${fmtMoney(apUsd)}' : null,
            icon: Icons.local_shipping_rounded,
            color: ErpColors.orange),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 240, child: SearchBox(hint: 'بحث بالاسم أو الهاتف', onChanged: (v) => setState(() => _q = v))),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('الكل')),
                ButtonSegment(value: 'customer', label: Text('الزبائن')),
                ButtonSegment(value: 'supplier', label: Text('الموردون')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            DropBox<String>(
              label: 'حالة الرصيد',
              value: _status,
              width: 180,
              items: const [
                DropdownMenuItem(value: 'nonzero', child: Text('غير المُصفَّر')),
                DropdownMenuItem(value: 'debit', child: Text('مدين فقط')),
                DropdownMenuItem(value: 'credit', child: Text('دائن فقط')),
                DropdownMenuItem(value: 'all', child: Text('الكل')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'nonzero'),
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : vis.isEmpty
                  ? const EmptyState('لا توجد أرصدة')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      itemCount: vis.length,
                      itemBuilder: (_, i) {
                        final r = vis[i];
                        final isCust = r['type'] == 'customer';
                        final st = _state(r);
                        final color = st == 'مُصفَّر'
                            ? ErpColors.muted
                            : (st.startsWith('نطلبه') ? ErpColors.red : ErpColors.green);
                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12), side: const BorderSide(color: ErpColors.border)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: (isCust ? ErpColors.blue : ErpColors.orange).withOpacity(.12),
                              child: Icon(isCust ? Icons.person_outline : Icons.local_shipping_outlined,
                                  color: isCust ? ErpColors.blue : ErpColors.orange),
                            ),
                            title: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Row(children: [
                              StatusBadge(st, color: color),
                              const SizedBox(width: 8),
                              Text(isCust ? 'زبون' : 'مورد', style: const TextStyle(color: ErpColors.muted)),
                            ]),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text(fmtMoney(d0(r['bal']).abs()),
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
                                if (d0(r['usd']).abs() > 0.004)
                                  Text('\$${fmtMoney(d0(r['usd']))}', style: const TextStyle(fontSize: 12)),
                              ]),
                              const SizedBox(width: 8),
                              if (st != 'مُصفَّر')
                                FilledButton.tonalIcon(
                                  onPressed: () => _quickPay(r),
                                  icon: const Icon(Icons.bolt_rounded, size: 18),
                                  label: const Text('تسديد سريع'),
                                ),
                              if (isCust)
                                IconButton(
                                  tooltip: 'كشف الحساب',
                                  icon: const Icon(Icons.list_alt_rounded),
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          CustomerStatementScreen(customerId: r['id'] as int, customerName: '${r['name']}'),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
