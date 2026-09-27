// lib/erp/debts/debt_reports_screen.dart
//
// 📊 تقارير الديون: أعمار الديون (عملاء/موردين)، نسب التحصيل، الفواتير غير
// المسددة، والعملاء المتجاوزون لسقف الدين.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../report_export.dart';
import 'customer_card_screen.dart';
import 'debt_analytics.dart';

// ═══════════════════════════ أعمار الديون ═══════════════════════════

class AgingScreen extends StatefulWidget {
  const AgingScreen({super.key, this.suppliers = false});
  final bool suppliers;
  @override
  State<AgingScreen> createState() => _AgingScreenState();
}

class _AgingScreenState extends State<AgingScreen> {
  late bool _suppliers = widget.suppliers;
  String _currency = 'IQD';
  int _periodDays = 30;
  int _periods = 4;
  DateTime _asOf = DateTime.now();
  String _show = 'all'; // all | debit | credit
  List<AgingRow> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final a = DebtAnalytics();
    final r = _suppliers
        ? await a.supplierAging(asOf: _asOf, periodDays: _periodDays, periods: _periods, currency: _currency)
        : await a.customerAging(asOf: _asOf, periodDays: _periodDays, periods: _periods);
    if (mounted) {
      setState(() {
        _rows = r;
        _loading = false;
      });
    }
  }

  List<AgingRow> get _visible => _rows.where((r) {
        if (_show == 'debit') return r.balance > 0;
        if (_show == 'credit') return r.balance < 0;
        return true;
      }).toList();

  List<String> get _bucketNames => [
        for (var i = 0; i < _periods; i++)
          i == _periods - 1 ? 'أكثر من ${i * _periodDays}' : '${i * _periodDays + (i == 0 ? 0 : 1)}-${(i + 1) * _periodDays}'
      ];

  List<String> get _headers => [_suppliers ? 'المورد' : 'العميل', 'الرصيد', ..._bucketNames, 'دائن', 'أقدم دين'];
  List<List<String>> get _data => [
        for (final r in _visible)
          [
            r.name,
            fmtMoney(r.balance),
            ...r.buckets.map(fmtMoney),
            fmtMoney(r.credit),
            r.oldestDate == null ? '' : fmtDate(r.oldestDate!),
          ],
      ];
  List<String> get _footer {
    final v = _visible;
    return [
      'المجموع (${v.length})',
      fmtMoney(v.fold(0.0, (s, r) => s + r.balance)),
      for (var i = 0; i < _periods; i++) fmtMoney(v.fold(0.0, (s, r) => s + r.buckets[i])),
      fmtMoney(v.fold(0.0, (s, r) => s + r.credit)),
      '',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final v = _visible;
    final totals = [for (var i = 0; i < _periods; i++) v.fold(0.0, (s, r) => s + r.buckets[i])];
    final all = totals.fold(0.0, (s, x) => s + x);
    const colors = [ErpColors.green, ErpColors.blue, ErpColors.orange, ErpColors.red, ErpColors.purple, ErpColors.navy];
    return ErpPage(
      title: 'أعمار الديون',
      subtitle: _suppliers ? 'ما علينا للموردين حسب عمر الدين' : 'ديون العملاء حسب عمرها (الأقدم يُسدَّد أولاً)',
      icon: Icons.hourglass_bottom,
      actions: exportActions(context,
          title: 'أعمار الديون', headers: () => _headers, rows: () => _data, footer: () => _footer,
          subtitle: () => 'حتى ${fmtDate(_asOf)} — فترة $_periodDays يوم'),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(10),
          child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('العملاء'), icon: Icon(Icons.people)),
                ButtonSegment(value: true, label: Text('الموردون'), icon: Icon(Icons.local_shipping)),
              ],
              selected: {_suppliers},
              onSelectionChanged: (s) {
                _suppliers = s.first;
                _load();
              },
            ),
            if (_suppliers)
              DropBox<String>(
                label: 'العملة',
                width: 120,
                value: _currency,
                items: const [
                  DropdownMenuItem(value: 'IQD', child: Text('دينار')),
                  DropdownMenuItem(value: 'USD', child: Text('دولار')),
                ],
                onChanged: (x) {
                  _currency = x ?? 'IQD';
                  _load();
                },
              ),
            DropBox<int>(
              label: 'مدة الفترة',
              width: 130,
              value: _periodDays,
              items: const [
                DropdownMenuItem(value: 15, child: Text('15 يوم')),
                DropdownMenuItem(value: 30, child: Text('شهر')),
                DropdownMenuItem(value: 60, child: Text('شهران')),
                DropdownMenuItem(value: 90, child: Text('ربع سنة')),
              ],
              onChanged: (x) {
                _periodDays = x ?? 30;
                _load();
              },
            ),
            DropBox<int>(
              label: 'عدد الفترات',
              width: 120,
              value: _periods,
              items: [for (final n in [3, 4, 5, 6]) DropdownMenuItem(value: n, child: Text('$n'))],
              onChanged: (x) {
                _periods = x ?? 4;
                _load();
              },
            ),
            DateButton(label: 'حتى تاريخ', value: _asOf, onChanged: (d) {
              _asOf = d;
              _load();
            }),
            DropBox<String>(
              label: 'إظهار',
              width: 150,
              value: _show,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('المدينة والدائنة')),
                DropdownMenuItem(value: 'debit', child: Text('المدينة فقط')),
                DropdownMenuItem(value: 'credit', child: Text('الدائنة فقط')),
              ],
              onChanged: (x) => setState(() => _show = x ?? 'all'),
            ),
          ]),
        ),
        if (!_loading && all > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Column(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 16,
                  child: Row(children: [
                    for (var i = 0; i < _periods; i++)
                      if (totals[i] > 0)
                        Expanded(
                          flex: (totals[i] / all * 1000).round().clamp(1, 1000).toInt(),
                          child: Container(color: colors[i % colors.length]),
                        ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 8, children: [
                for (var i = 0; i < _periods; i++)
                  StatCard(
                    width: 190,
                    label: '${_bucketNames[i]} يوم',
                    value: fmtMoney(totals[i]),
                    icon: Icons.timelapse,
                    color: colors[i % colors.length],
                    hint: '${(totals[i] / all * 100).toStringAsFixed(1)}%',
                  ),
              ]),
            ]),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : v.isEmpty
                  ? const EmptyState('لا توجد ديون')
                  : Padding(
                      padding: const EdgeInsets.all(8),
                      child: SimpleTable(
                        headers: _headers,
                        rows: _data,
                        footer: _footer,
                        numericColumns: {for (var i = 1; i < _headers.length - 1; i++) i},
                        onRowTap: _suppliers
                            ? null
                            : (i) => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => CustomerCardScreen(customerId: v[i].partyId))),
                      ),
                    ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════ نسب التحصيل ═══════════════════════════

class CollectionReportScreen extends StatefulWidget {
  const CollectionReportScreen({super.key});
  @override
  State<CollectionReportScreen> createState() => _CollectionReportScreenState();
}

class _CollectionReportScreenState extends State<CollectionReportScreen> {
  DateTime? _from = DateTime(DateTime.now().year, 1, 1);
  DateTime _to = DateTime.now();
  List<CollectionRow> _rows = const [];
  String _sort = 'closing';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await DebtAnalytics().collection(from: _from ?? DateTime(2000), to: _to);
    if (mounted) setState(() => _rows = r);
  }

  List<CollectionRow> get _sorted {
    final l = [..._rows];
    switch (_sort) {
      case 'ratio_low':
        l.sort((a, b) => a.ratio.compareTo(b.ratio));
        break;
      case 'ratio_high':
        l.sort((a, b) => b.ratio.compareTo(a.ratio));
        break;
      case 'collected':
        l.sort((a, b) => b.collected.compareTo(a.collected));
        break;
      default:
        l.sort((a, b) => b.closing.compareTo(a.closing));
    }
    return l;
  }

  List<String> get _headers => ['العميل', 'أول المدة', 'المستحق', 'المحصّل', 'آخر المدة', 'نسبة التحصيل'];
  List<List<String>> get _data => [
        for (final r in _sorted)
          [r.name, fmtMoney(r.opening), fmtMoney(r.charged), fmtMoney(r.collected), fmtMoney(r.closing),
            '${r.ratio.toStringAsFixed(1)}%'],
      ];

  @override
  Widget build(BuildContext context) {
    final charged = _rows.fold(0.0, (s, r) => s + r.charged);
    final collected = _rows.fold(0.0, (s, r) => s + r.collected);
    final openingPos = _rows.fold(0.0, (s, r) => s + (r.opening > 0 ? r.opening : 0));
    final ratio = (openingPos + charged) <= 0 ? 0 : collected / (openingPos + charged) * 100;
    return ErpPage(
      title: 'نسب التحصيل',
      subtitle: 'ما حُصّل من المستحق على كل عميل خلال الفترة',
      icon: Icons.percent,
      actions: exportActions(context, title: 'نسب التحصيل', headers: () => _headers, rows: () => _data),
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'المستحق خلال الفترة', value: fmtMoney(charged), icon: Icons.trending_up, color: ErpColors.orange),
        StatCard(label: 'المحصّل', value: fmtMoney(collected), icon: Icons.savings, color: ErpColors.green),
        StatCard(label: 'نسبة التحصيل العامة', value: '${ratio.toStringAsFixed(1)}%', icon: Icons.speed, color: ErpColors.blue),
      ]),
      body: Column(children: [
        PeriodBar(from: _from, to: _to, onChanged: (f, t) {
          _from = f;
          _to = t;
          _load();
        }),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Wrap(spacing: 8, children: [
            for (final e in const {
              'closing': 'الأكبر رصيداً',
              'ratio_low': 'الأضعف تحصيلاً',
              'ratio_high': 'الأفضل تحصيلاً',
              'collected': 'الأكثر سداداً',
            }.entries)
              ChoiceChip(label: Text(e.value), selected: _sort == e.key, onSelected: (_) => setState(() => _sort = e.key)),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _sorted.length,
            itemBuilder: (_, i) {
              final r = _sorted[i];
              final c = r.ratio >= 70 ? ErpColors.green : (r.ratio >= 40 ? ErpColors.orange : ErpColors.red);
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), side: const BorderSide(color: ErpColors.border)),
                child: ListTile(
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => CustomerCardScreen(customerId: r.customerId))),
                  title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('مستحق ${fmtMoney(r.charged)} • محصّل ${fmtMoney(r.collected)} • الرصيد ${fmtMoney(r.closing)}'),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: (r.ratio / 100).clamp(0.0, 1.0).toDouble(),
                      color: c,
                      backgroundColor: c.withOpacity(0.12),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ]),
                  trailing: Text('${r.ratio.toStringAsFixed(0)}%',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: c)),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════ الفواتير غير المسددة ═══════════════════════════

class OpenInvoicesScreen extends StatefulWidget {
  const OpenInvoicesScreen({super.key, this.customerId});
  final int? customerId;
  @override
  State<OpenInvoicesScreen> createState() => _OpenInvoicesScreenState();
}

class _OpenInvoicesScreenState extends State<OpenInvoicesScreen> {
  List<OpenInvoice> _rows = const [];
  String _q = '';
  @override
  void initState() {
    super.initState();
    DebtAnalytics().openInvoices(customerId: widget.customerId).then((r) {
      if (mounted) setState(() => _rows = r);
    });
  }

  List<OpenInvoice> get _visible =>
      _q.isEmpty ? _rows : _rows.where((r) => r.customerName.contains(_q) || '${r.invoiceId}' == _q).toList();

  List<String> get _headers => ['الفاتورة', 'العميل', 'التاريخ', 'العمر (يوم)', 'المبلغ الآجل', 'المسدد', 'المتبقي'];
  List<List<String>> get _data => [
        for (final r in _visible)
          [
            '#${r.invoiceId}',
            r.customerName,
            fmtDate(r.date),
            '${r.ageDays}',
            fmtMoney(r.debtAmount),
            fmtMoney(r.debtAmount - r.remaining),
            fmtMoney(r.remaining),
          ],
      ];

  @override
  Widget build(BuildContext context) {
    final total = _visible.fold(0.0, (s, r) => s + r.remaining);
    return ErpPage(
      title: 'الفواتير غير المسددة',
      subtitle: '${_visible.length} فاتورة — المتبقي ${fmtMoney(total)} (التسديدات تُخصم من الأقدم أولاً)',
      icon: Icons.receipt_outlined,
      actions: exportActions(context, title: 'الفواتير غير المسددة', headers: () => _headers, rows: () => _data),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: SearchBox(hint: 'بحث باسم العميل أو رقم الفاتورة', onChanged: (v) => setState(() => _q = v.trim())),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SimpleTable(headers: _headers, rows: _data, numericColumns: const {3, 4, 5, 6}),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════ المتجاوزون لسقف الدين ═══════════════════════════

class OverLimitScreen extends StatefulWidget {
  const OverLimitScreen({super.key});
  @override
  State<OverLimitScreen> createState() => _OverLimitScreenState();
}

class _OverLimitScreenState extends State<OverLimitScreen> {
  List<Map<String, Object?>> _rows = const [];
  @override
  void initState() {
    super.initState();
    DebtAnalytics().overCreditLimit().then((r) {
      if (mounted) setState(() => _rows = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'المتجاوزون لسقف الدين',
      subtitle: '${_rows.length} عميل',
      icon: Icons.block,
      actions: exportActions(context,
          title: 'المتجاوزون لسقف الدين',
          headers: () => ['العميل', 'الهاتف', 'الرصيد', 'السقف', 'التجاوز'],
          rows: () => [
                for (final r in _rows)
                  [
                    '${r['name']}',
                    '${r['phone'] ?? ''}',
                    fmtMoney(d0(r['balance'])),
                    fmtMoney(d0(r['credit_limit'])),
                    fmtMoney(d0(r['balance']) - d0(r['credit_limit'])),
                  ],
              ]),
      body: _rows.isEmpty
          ? const EmptyState('لا يوجد عميل تجاوز سقفه', icon: Icons.verified_user_outlined)
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _rows.length,
              itemBuilder: (_, i) {
                final r = _rows[i];
                final over = d0(r['balance']) - d0(r['credit_limit']);
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12), side: const BorderSide(color: ErpColors.border)),
                  child: ListTile(
                    leading: const CircleAvatar(
                        backgroundColor: Color(0x1FB91C1C), child: Icon(Icons.warning_amber, color: ErpColors.red)),
                    title: Text('${r['name']}'),
                    subtitle: Text('الرصيد ${fmtMoney(d0(r['balance']))} • السقف ${fmtMoney(d0(r['credit_limit']))}'),
                    trailing: Text('+${fmtMoney(over)}',
                        style: const TextStyle(color: ErpColors.red, fontWeight: FontWeight.bold)),
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => CustomerCardScreen(customerId: r['id'] as int))),
                  ),
                );
              },
            ),
    );
  }
}
