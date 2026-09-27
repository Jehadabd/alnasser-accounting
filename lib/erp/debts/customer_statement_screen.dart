// lib/erp/debts/customer_statement_screen.dart
//
// 📄 كشف حساب العميل المتقدم + مطابقة الرصيد.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../models/app_user.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../report_export.dart';
import 'statement_service.dart';

class CustomerStatementScreen extends StatefulWidget {
  const CustomerStatementScreen({super.key, this.customerId, this.customerName});
  final int? customerId;
  final String? customerName;
  @override
  State<CustomerStatementScreen> createState() => _CustomerStatementScreenState();
}

class _CustomerStatementScreenState extends State<CustomerStatementScreen> {
  final _svc = StatementService();
  int? _customerId;
  String _customerName = '';
  DateTime? _from = DateTime(DateTime.now().year, 1, 1);
  DateTime _to = DateTime.now();
  CustomerStatement? _st;
  bool _monthly = false;
  bool _detailed = false;
  final _text = TextEditingController();
  final _product = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();
  bool _advanced = false;
  final Map<int, List<Map<String, Object?>>> _items = {};

  @override
  void initState() {
    super.initState();
    _customerId = widget.customerId;
    _customerName = widget.customerName ?? '';
    if (_customerId != null) _load();
  }

  Future<void> _load() async {
    if (_customerId == null) return;
    final st = await _svc.statement(
      _customerId!,
      from: _from,
      to: _to,
      text: _text.text.trim(),
      productName: _product.text.trim(),
      minAmount: parseMoney(_min.text),
      maxAmount: parseMoney(_max.text),
    );
    if (_detailed) {
      for (final l in st.lines) {
        if (l.invoiceId != null && !_items.containsKey(l.invoiceId)) {
          _items[l.invoiceId!] = await _svc.invoiceItems(l.invoiceId!);
        }
      }
    }
    if (mounted) setState(() => _st = st);
  }

  Future<void> _sinceRecon() async {
    if (_customerId == null) return;
    final d = await _svc.lastReconciliation(_customerId!);
    if (d == null) {
      if (mounted) showError(context, 'لا توجد مطابقة مسجّلة لهذا العميل');
      return;
    }
    _from = d.add(const Duration(days: 1));
    _load();
  }

  Future<void> _reconcile() async {
    if (_customerId == null) return;
    if (!requirePermission(context, AppPermissions.collection)) return;
    DateTime date = DateTime.now();
    var ours = await _svc.balanceAt(_customerId!, date);
    final agreed = TextEditingController(text: fmtMoney(ours));
    final notes = TextEditingController();
    bool adjust = false;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final diff = (parseMoney(agreed.text) ?? 0) - ours;
          return AlertDialog(
            title: const Text('مطابقة رصيد'),
            content: SizedBox(
              width: 440,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DateButton(
                    label: 'تاريخ المطابقة',
                    value: date,
                    onChanged: (d) async {
                      final b = await _svc.balanceAt(_customerId!, d);
                      set(() {
                        date = d;
                        ours = b;
                      });
                    }),
                const SizedBox(height: 10),
                InfoTile('رصيدنا بهذا التاريخ', fmtMoney(ours), width: 400),
                const SizedBox(height: 10),
                MoneyField(controller: agreed, label: 'الرصيد المتفق عليه مع العميل', onChanged: (_) => set(() {})),
                const SizedBox(height: 6),
                Text('الفرق: ${fmtMoney(diff)}',
                    style: TextStyle(color: diff.abs() < 0.01 ? ErpColors.green : ErpColors.orange)),
                if (diff.abs() >= 0.01)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: adjust,
                    onChanged: (v) => set(() => adjust = v ?? false),
                    title: const Text('تسوية الفرق الآن (قيد على حساب فروقات المطابقة)'),
                  ),
                TextBox(controller: notes, label: 'ملاحظات'),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسجيل المطابقة')),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _svc.reconcile(context,
          customerId: _customerId!,
          date: date,
          agreedBalance: parseMoney(agreed.text) ?? ours,
          adjust: adjust,
          notes: notes.text.trim());
      if (mounted) showOk(context, 'سُجّلت المطابقة');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  List<String> get _headers => ['التاريخ', 'البيان', 'التفاصيل', 'مدين (عليه)', 'دائن (له)', 'الرصيد'];
  List<List<String>> get _data {
    final st = _st;
    if (st == null) return const [];
    return [
      if (st.from != null) [fmtDate(st.from!), 'رصيد أول المدة', '', '', '', fmtMoney(st.opening)],
      for (final l in st.lines) ...[
        [fmtDate(l.date), l.label, l.note, l.debit > 0 ? fmtMoney(l.debit) : '', l.credit > 0 ? fmtMoney(l.credit) : '',
          fmtMoney(l.balance)],
        if (_detailed && l.invoiceId != null)
          for (final it in _items[l.invoiceId] ?? const <Map<String, Object?>>[])
            [
              '',
              '   ↳ ${it['product_name']}',
              '${fmtQty(d0(it['quantity_large_unit']) > 0 ? d0(it['quantity_large_unit']) : d0(it['quantity_individual']))} ${it['sale_type'] ?? ''} × ${fmtMoney(d0(it['applied_price']))}',
              fmtMoney(d0(it['item_total'])),
              '',
              '',
            ],
      ],
    ];
  }

  List<String> get _footer {
    final st = _st;
    if (st == null) return const [];
    return ['', 'المجموع', '', fmtMoney(st.totalDebit), fmtMoney(st.totalCredit), fmtMoney(st.closing)];
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    return ErpPage(
      title: 'كشف حساب عميل',
      subtitle: _customerName.isEmpty ? 'اختر العميل' : _customerName,
      icon: Icons.list_alt,
      actions: [
        IconButton(tooltip: 'مطابقة رصيد', icon: const Icon(Icons.handshake_outlined), onPressed: _reconcile),
        ...exportActions(context,
            title: 'كشف حساب $_customerName',
            headers: () => _headers,
            rows: () => _data,
            footer: () => _footer,
            subtitle: () => 'من ${_from == null ? 'البداية' : fmtDate(_from!)} إلى ${fmtDate(_to)}'),
      ],
      headerExtra: st == null
          ? null
          : Wrap(spacing: 10, runSpacing: 10, children: [
              StatCard(label: 'رصيد أول المدة', value: fmtMoney(st.opening), icon: Icons.flag_outlined, color: ErpColors.muted),
              StatCard(label: 'مدين (عليه)', value: fmtMoney(st.totalDebit), icon: Icons.north_east, color: ErpColors.orange),
              StatCard(label: 'دائن (له)', value: fmtMoney(st.totalCredit), icon: Icons.south_west, color: ErpColors.green),
              StatCard(label: 'الرصيد الختامي', value: fmtMoney(st.closing), icon: Icons.account_balance_wallet, color: ErpColors.navy),
            ]),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(8),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.person_search),
              label: Text(_customerName.isEmpty ? 'اختيار العميل' : _customerName),
              onPressed: () async {
                final c = await Pickers.customer(context);
                if (c == null) return;
                setState(() {
                  _customerId = c.id;
                  _customerName = c.name;
                });
                _load();
              },
            ),
            TextButton.icon(onPressed: _sinceRecon, icon: const Icon(Icons.history), label: const Text('منذ آخر مطابقة')),
            FilterChip(
                label: const Text('مجموع كل شهر'),
                selected: _monthly,
                onSelected: (v) => setState(() => _monthly = v)),
            FilterChip(
                label: const Text('موضّح (مواد الفواتير)'),
                selected: _detailed,
                onSelected: (v) {
                  setState(() => _detailed = v);
                  _load();
                }),
            FilterChip(
                label: const Text('بحث متقدم'), selected: _advanced, onSelected: (v) => setState(() => _advanced = v)),
          ]),
        ),
        PeriodBar(from: _from, to: _to, onChanged: (f, t) {
          _from = f;
          _to = t;
          _load();
        }),
        if (_advanced)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: FieldGrid(children: [
              TextBox(controller: _text, label: 'نص في الشرح', width: 200),
              TextBox(controller: _product, label: 'اسم مادة في الفاتورة', width: 200),
              MoneyField(controller: _min, label: 'مبلغ من', width: 140),
              MoneyField(controller: _max, label: 'مبلغ إلى', width: 140),
              ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.search), label: const Text('بحث')),
            ]),
          ),
        Expanded(
          child: st == null
              ? const EmptyState('اختر عميلاً لعرض كشف حسابه', icon: Icons.person_search)
              : _monthly
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: SimpleTable(
                        headers: const ['الشهر', 'مدين', 'دائن', 'الصافي'],
                        numericColumns: const {1, 2, 3},
                        rows: [
                          for (final m in st.months)
                            ['${m.year}/${m.month.toString().padLeft(2, '0')}', fmtMoney(m.debit), fmtMoney(m.credit),
                              fmtMoney(m.debit - m.credit)],
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(8),
                      child: SimpleTable(
                        headers: _headers,
                        rows: _data,
                        footer: _footer,
                        numericColumns: const {3, 4, 5},
                      ),
                    ),
        ),
      ]),
    );
  }
}
