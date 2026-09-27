// lib/erp/accounting_plus/currency_voucher_screens.dart
//
// 💱 العملات وأسعار الصرف • 🧾 سند القيد المركّب • 📑 قوالب السندات.

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart';
import '../../accounting/screens/acc_ui.dart';
import '../../accounting/screens/vouchers_screen.dart';
import '../../accounting/vouchers_service.dart';
import '../currency_service.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import 'accounting_plus_service.dart';
import 'voucher_pdf.dart';

// ═══════════════════════════ العملات ═══════════════════════════

class CurrenciesScreen extends StatefulWidget {
  const CurrenciesScreen({super.key});
  @override
  State<CurrenciesScreen> createState() => _CurrenciesScreenState();
}

class _CurrenciesScreenState extends State<CurrenciesScreen> {
  final _svc = CurrencyService();
  List<Currency> _list = const [];
  List<Map<String, Object?>> _hist = const [];
  String? _code;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await _svc.all(activeOnly: false);
    final h = await _svc.history(code: _code);
    if (mounted) {
      setState(() {
        _list = l;
        _hist = h;
      });
    }
  }

  Future<void> _edit([Currency? c]) async {
    final code = TextEditingController(text: c?.code ?? '');
    final name = TextEditingController(text: c?.name ?? '');
    final symbol = TextEditingController(text: c?.symbol ?? '');
    final frac = TextEditingController(text: c?.fractionName ?? '');
    final rate = TextEditingController(text: c == null ? '' : fmtMoney(c.rate));
    var active = c?.isActive ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(c == null ? 'عملة جديدة' : 'تعديل ${c.name}'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextBox(controller: code, label: 'الرمز (مثل USD)', enabled: c == null),
              const SizedBox(height: 8),
              TextBox(controller: name, label: 'الاسم'),
              const SizedBox(height: 8),
              TextBox(controller: symbol, label: 'الرمز المختصر (\$)'),
              const SizedBox(height: 8),
              TextBox(controller: frac, label: 'اسم الجزء (سنت، فلس)'),
              const SizedBox(height: 8),
              if (c?.isBase != true) MoneyField(controller: rate, label: 'سعر التعادل بالدينار'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('فعّالة'),
                value: active,
                onChanged: (v) => setS(() => active = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _svc.save(
        Currency(
          code: code.text.trim().toUpperCase(),
          name: name.text.trim(),
          symbol: symbol.text.trim(),
          fractionName: frac.text.trim(),
          rate: c?.isBase == true ? 1 : (parseMoney(rate.text) ?? 0),
          isBase: c?.isBase ?? false,
          isActive: active,
        ),
        isNew: c == null,
      );
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _newRate(Currency c) async {
    DateTime date = DateTime.now();
    final rate = TextEditingController(text: fmtMoney(c.rate));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('سعر جديد — ${c.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            MoneyField(controller: rate, label: 'السعر بالدينار', autofocus: true),
            const SizedBox(height: 10),
            DateButton(label: 'نافذ من', value: date, onChanged: (d) => setS(() => date = d)),
            const SizedBox(height: 10),
            const Text(
                'تنبيه: السعر بتاريخ سابق يعيد تسعير قيود مستندات الدولار من ذلك التاريخ حتى السعر التالي.',
                style: TextStyle(color: ErpColors.orange, fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _svc.setRate(c.code, parseMoney(rate.text) ?? 0, date);
      await _load();
      if (mounted) showOk(context, 'سُجِّل السعر');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'العملات وأسعار الصرف',
      subtitle: 'سعر لكل تاريخ — المستندات بالعملة تُقيَّم بسعر يومها',
      icon: Icons.currency_exchange_rounded,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('عملة'),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            for (final c in _list)
              Container(
                width: 260,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: c.isBase
                      ? const LinearGradient(colors: [ErpColors.navy, ErpColors.blue])
                      : null,
                  color: c.isBase ? null : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.isBase ? Colors.transparent : ErpColors.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(c.code,
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold, color: c.isBase ? Colors.white : ErpColors.navy)),
                    const Spacer(),
                    if (!c.isActive) const StatusBadge('موقوفة', color: ErpColors.muted),
                    if (c.isBase) const StatusBadge('الأساسية', color: Colors.white),
                  ]),
                  Text(c.name, style: TextStyle(color: c.isBase ? Colors.white70 : ErpColors.muted)),
                  const SizedBox(height: 8),
                  Text(c.isBase ? '1' : fmtMoney(c.rate),
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.isBase ? Colors.white : ErpColors.green)),
                  const SizedBox(height: 6),
                  Row(children: [
                    if (!c.isBase)
                      TextButton.icon(
                          onPressed: () => _newRate(c), icon: const Icon(Icons.trending_up), label: const Text('سعر جديد')),
                    if (!c.isBase)
                      TextButton(
                          onPressed: () {
                            _code = c.code;
                            _load();
                          },
                          child: const Text('السجل')),
                    const Spacer(),
                    IconButton(
                        icon: Icon(Icons.edit_outlined, color: c.isBase ? Colors.white : ErpColors.navy),
                        onPressed: () => _edit(c)),
                  ]),
                ]),
              ),
          ]),
        ),
        ErpSection(
          title: _code == null ? 'سجل الأسعار' : 'سجل أسعار $_code',
          icon: Icons.history_rounded,
          trailing: _code == null
              ? null
              : TextButton(
                  onPressed: () {
                    _code = null;
                    _load();
                  },
                  child: const Text('الكل')),
          child: _hist.isEmpty
              ? const Text('لا يوجد سجل')
              : Column(children: [
                  for (final h in _hist)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: ErpColors.green.withOpacity(.1),
                          child: Text('${h['code']}'.substring(0, 1), style: const TextStyle(color: ErpColors.green))),
                      title: Text('${h['code']} = ${fmtMoney(d0(h['rate']))} دينار'),
                      subtitle: Text('نافذ من ${fmtDate(parseDate(h['rate_date']))}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: ErpColors.red),
                        onPressed: () async {
                          final ok = await confirmDialog(context, 'حذف السعر', 'حذف هذا السعر من السجل؟',
                              color: ErpColors.red);
                          if (!ok) return;
                          try {
                            await _svc.deleteRate(h['id'] as int);
                            await _load();
                          } catch (e) {
                            if (context.mounted) showError(context, e);
                          }
                        },
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════ سند القيد المركّب ═══════════════════════════

class CompoundVouchersScreen extends StatefulWidget {
  const CompoundVouchersScreen({super.key});
  @override
  State<CompoundVouchersScreen> createState() => _CompoundVouchersScreenState();
}

class _CompoundVouchersScreenState extends State<CompoundVouchersScreen> {
  final _svc = CompoundVoucherService();
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  List<Map<String, Object?>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _svc.list(from: _from, to: _to);
    if (mounted) setState(() => _rows = r);
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'سندات القيد المركّبة',
      subtitle: 'عدة حسابات مدينة ودائنة بعملات مختلفة في سند واحد',
      icon: Icons.account_tree_rounded,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: ErpColors.navy,
        onPressed: () async {
          final ok = await Navigator.push<bool>(
              context, MaterialPageRoute(builder: (_) => const CompoundVoucherEditorScreen()));
          if (ok == true) _load();
        },
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('سند قيد', style: TextStyle(color: Colors.white)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, children: [
            DateButton(label: 'من', value: _from, onChanged: (d) {
              _from = d;
              _load();
            }),
            DateButton(label: 'إلى', value: _to, onChanged: (d) {
              _to = d;
              _load();
            }),
          ]),
        ),
        Expanded(
          child: _rows.isEmpty
              ? const EmptyState('لا توجد سندات قيد في هذه الفترة', icon: Icons.receipt_long_outlined)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final v = _rows[i];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14), side: const BorderSide(color: ErpColors.border)),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: ErpColors.navy.withOpacity(.1),
                          child: Text('${v['voucher_number']}',
                              style: const TextStyle(color: ErpColors.navy, fontWeight: FontWeight.bold)),
                        ),
                        title: Text('${v['description'] ?? 'سند قيد'}'),
                        subtitle: Text('${fmtDate(parseDate(v['voucher_date']))} • ${v['n_lines']} سطر'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(fmtMoney(d0(v['amount'])), style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.print_outlined),
                            onPressed: () => VoucherPdf.printVoucher(context, v['id'] as int),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: ErpColors.red),
                            onPressed: () async {
                              final ok = await confirmDialog(
                                  context, 'حذف السند', 'سيُحذف قيده من الدفتر ويبقى السند في السجل كمحذوف.',
                                  color: ErpColors.red);
                              if (!ok) return;
                              try {
                                await _svc.delete(v['id'] as int);
                                _load();
                              } catch (e) {
                                if (context.mounted) showError(context, e);
                              }
                            },
                          ),
                        ]),
                        children: [
                          FutureBuilder<List<Map<String, Object?>>>(
                            future: _svc.lines(v['id'] as int),
                            builder: (_, s) => Padding(
                              padding: const EdgeInsets.all(8),
                              child: SimpleTable(
                                headers: const ['الحساب', 'مدين', 'دائن', 'العملة', 'البيان'],
                                numericColumns: const {1, 2},
                                rows: [
                                  for (final l in s.data ?? const <Map<String, Object?>>[])
                                    [
                                      '${l['code']} ${l['name']}',
                                      d0(l['debit']) > 0 ? fmtMoney(d0(l['debit'])) : '',
                                      d0(l['credit']) > 0 ? fmtMoney(d0(l['credit'])) : '',
                                      l['currency'] == 'IQD'
                                          ? ''
                                          : '${fmtMoney(d0(l['fc_amount']))} ${l['currency']} × ${fmtMoney(d0(l['fx_rate']))}',
                                      '${l['memo'] ?? ''}',
                                    ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class CompoundVoucherEditorScreen extends StatefulWidget {
  const CompoundVoucherEditorScreen({super.key});
  @override
  State<CompoundVoucherEditorScreen> createState() => _CompoundVoucherEditorScreenState();
}

class _CompoundVoucherEditorScreenState extends State<CompoundVoucherEditorScreen> {
  final _svc = CompoundVoucherService();
  final _lines = <VLine>[];
  final _desc = TextEditingController();
  final _ref = TextEditingController();
  DateTime _date = DateTime.now();
  List<Currency> _currencies = const [];
  bool _saving = false;
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    CurrencyService().all().then((c) {
      if (mounted) setState(() => _currencies = c);
    });
  }

  double get _dr => _lines.fold<double>(0, (s, l) => s + l.debit);
  double get _cr => _lines.fold<double>(0, (s, l) => s + l.credit);

  Future<void> _addLine() async {
    final a = await Pickers.account(context, title: 'اختر حساباً');
    if (a == null) return;
    setState(() {
      final diff = roundMoney(_dr - _cr);
      _lines.add(VLine(account: a, debit: diff < 0 ? -diff : 0, credit: diff > 0 ? diff : 0));
      _rev++;
    });
  }

  void _recalcFc(VLine l) {
    if (l.currency == CurrencyService.base) return;
    final iqd = roundMoney((l.fcAmount ?? 0) * (l.fxRate ?? 0));
    if (l.debit > 0 || (l.debit == 0 && l.credit == 0)) {
      l.debit = iqd;
      l.credit = 0;
    } else {
      l.credit = iqd;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final id = await _svc.create(
        date: _date,
        lines: _lines,
        description: _desc.text.trim(),
        reference: _ref.text.trim(),
      );
      if (!mounted) return;
      showOk(context, 'حُفظ السند');
      final print = await confirmDialog(context, 'طباعة', 'هل تريد طباعة السند؟', ok: 'طباعة');
      if (print && mounted) await VoucherPdf.printVoucher(context, id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = roundMoney(_dr - _cr);
    final balanced = diff.abs() < kMoneyEpsilon && _dr > 0;
    return ErpPage(
      title: 'سند قيد مركّب',
      icon: Icons.account_tree_rounded,
      bottom: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: Wrap(spacing: 18, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('مدين: ${fmtMoney(_dr)}', style: const TextStyle(fontWeight: FontWeight.bold, color: ErpColors.green)),
                Text('دائن: ${fmtMoney(_cr)}', style: const TextStyle(fontWeight: FontWeight.bold, color: ErpColors.red)),
                StatusBadge(balanced ? 'متوازن ✓' : 'الفرق ${fmtMoney(diff.abs())}',
                    color: balanced ? ErpColors.green : ErpColors.orange),
              ]),
            ),
            PrimaryButton(
                label: 'حفظ السند', icon: Icons.save_rounded, busy: _saving, onPressed: balanced ? _save : null),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 20), children: [
        ErpSection(
          title: 'بيانات السند',
          icon: Icons.description_outlined,
          child: FieldGrid(children: [
            DateButton(label: 'التاريخ', value: _date, onChanged: (d) => setState(() => _date = d)),
            TextBox(controller: _desc, label: 'البيان', width: 360),
            TextBox(controller: _ref, label: 'المرجع', width: 180),
          ]),
        ),
        ErpSection(
          title: 'الأسطر',
          icon: Icons.list_alt_rounded,
          trailing: TextButton.icon(onPressed: _addLine, icon: const Icon(Icons.add), label: const Text('إضافة حساب')),
          child: _lines.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('أضف الحسابات. ديون العملاء والموردين لا تُسجَّل هنا (لها شاشاتها).',
                      style: TextStyle(color: ErpColors.muted)))
              : Column(children: [
                  for (var i = 0; i < _lines.length; i++) _lineRow(i),
                ]),
        ),
      ]),
    );
  }

  Widget _lineRow(int i) {
    final l = _lines[i];
    final fc = l.currency != CurrencyService.base;
    InputDecoration deco(String t) =>
        InputDecoration(isDense: true, labelText: t, border: const OutlineInputBorder(), filled: true, fillColor: Colors.white);
    return Container(
      key: ValueKey('vl-$i-$_rev'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: l.debit > 0 ? ErpColors.green.withOpacity(.04) : (l.credit > 0 ? ErpColors.red.withOpacity(.04) : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ErpColors.border),
      ),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 240,
          child: Text('${l.account.code} — ${l.account.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        SizedBox(
          width: 110,
          child: DropdownButtonFormField<String>(
            value: _currencies.any((c) => c.code == l.currency) ? l.currency : CurrencyService.base,
            decoration: deco('العملة'),
            items: [
              if (_currencies.isEmpty) const DropdownMenuItem(value: CurrencyService.base, child: Text('IQD')),
              for (final c in _currencies) DropdownMenuItem(value: c.code, child: Text(c.code)),
            ],
            onChanged: (v) async {
              final code = v ?? CurrencyService.base;
              final db = await erpDb();
              final rate = await CurrencyService.rateAt(db, code, _date);
              setState(() {
                l.currency = code;
                l.fxRate = code == CurrencyService.base ? null : rate;
                l.fcAmount = code == CurrencyService.base ? null : 0;
                if (code != CurrencyService.base) _recalcFc(l);
                _rev++;
              });
            },
          ),
        ),
        if (fc) ...[
          SizedBox(
            width: 120,
            child: TextFormField(
              initialValue: l.fcAmount == null || l.fcAmount == 0 ? '' : fmtMoney(l.fcAmount!),
              decoration: deco('المبلغ ${l.currency}'),
              onChanged: (v) => setState(() {
                l.fcAmount = parseMoney(v) ?? 0;
                _recalcFc(l);
              }),
            ),
          ),
          SizedBox(
            width: 110,
            child: TextFormField(
              initialValue: fmtMoney(l.fxRate ?? 0),
              decoration: deco('السعر'),
              onChanged: (v) => setState(() {
                l.fxRate = parseMoney(v) ?? 0;
                _recalcFc(l);
              }),
            ),
          ),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: true, label: Text('مدين')), ButtonSegment(value: false, label: Text('دائن'))],
            selected: {l.credit == 0},
            onSelectionChanged: (s) => setState(() {
              final amt = l.debit + l.credit;
              l.debit = s.first ? amt : 0;
              l.credit = s.first ? 0 : amt;
            }),
          ),
          Text(fmtMoney(l.debit + l.credit), style: const TextStyle(fontWeight: FontWeight.bold)),
        ] else ...[
          SizedBox(
            width: 140,
            child: TextFormField(
              initialValue: l.debit == 0 ? '' : fmtMoney(l.debit),
              decoration: deco('مدين'),
              onChanged: (v) => setState(() => l.debit = parseMoney(v) ?? 0),
            ),
          ),
          SizedBox(
            width: 140,
            child: TextFormField(
              initialValue: l.credit == 0 ? '' : fmtMoney(l.credit),
              decoration: deco('دائن'),
              onChanged: (v) => setState(() => l.credit = parseMoney(v) ?? 0),
            ),
          ),
        ],
        SizedBox(
          width: 200,
          child: TextFormField(initialValue: l.memo ?? '', decoration: deco('بيان السطر'), onChanged: (v) => l.memo = v),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: ErpColors.red),
          onPressed: () => setState(() {
            _lines.removeAt(i);
            _rev++;
          }),
        ),
      ]),
    );
  }
}

// ═══════════════════════════ قوالب السندات ═══════════════════════════

class VoucherTemplatesScreen extends StatefulWidget {
  const VoucherTemplatesScreen({super.key});
  @override
  State<VoucherTemplatesScreen> createState() => _VoucherTemplatesScreenState();
}

class _VoucherTemplatesScreenState extends State<VoucherTemplatesScreen> {
  final _svc = VoucherTemplatesService();
  List<Map<String, Object?>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _svc.list();
    if (mounted) setState(() => _rows = r);
  }

  Future<void> _edit([Map<String, Object?>? t]) async {
    final name = TextEditingController(text: '${t?['name'] ?? ''}');
    final abbrev = TextEditingController(text: '${t?['abbrev'] ?? ''}');
    final notes = TextEditingController(text: '${t?['notes'] ?? ''}');
    var type = (t?['voucher_type'] as String?) ?? VoucherType.expense.name;
    int? box = t?['cash_box_id'] as int?;
    Account? acc;
    if (t?['account_id'] != null) acc = await Ledger().accountById(t!['account_id'] as int);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(t == null ? 'قالب سند جديد' : 'تعديل القالب'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextBox(controller: name, label: 'اسم القالب (مثل: إيجار المحل)'),
              const SizedBox(height: 8),
              TextBox(controller: abbrev, label: 'اختصار'),
              const SizedBox(height: 8),
              DropBox<String>(
                label: 'نوع السند',
                width: 380,
                value: type,
                items: [
                  for (final v in [VoucherType.expense, VoucherType.income, VoucherType.payment, VoucherType.receipt])
                    DropdownMenuItem(value: v.name, child: Text(voucherTypeLabels[v]!)),
                ],
                onChanged: (v) => setS(() => type = v ?? type),
              ),
              const SizedBox(height: 8),
              CashBoxDropdown(value: box, width: 380, onChanged: (b) => setS(() => box = b?.id)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.account_tree_outlined),
                label: Text(acc == null ? 'الحساب' : '${acc!.code} ${acc!.name}'),
                onPressed: () async {
                  final a = await Pickers.account(ctx);
                  if (a != null) setS(() => acc = a);
                },
              ),
              const SizedBox(height: 8),
              TextBox(controller: notes, label: 'البيان الافتراضي'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _svc.save(
        id: t?['id'] as int?,
        name: name.text,
        abbrev: abbrev.text,
        voucherType: type,
        cashBoxId: box,
        accountId: acc?.id,
        notes: notes.text.trim(),
      );
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _use(Map<String, Object?> t) async {
    VoucherType? type;
    for (final v in VoucherType.values) {
      if (v.name == t['voucher_type']) type = v;
    }
    if (type == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VoucherFormScreen(
          type: type!,
          initialCashBoxId: t['cash_box_id'] as int?,
          initialAccountId: t['account_id'] as int?,
          initialDescription: (t['notes'] as String?)?.isNotEmpty == true ? t['notes'] as String : t['name'] as String?,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'قوالب السندات',
      subtitle: 'سند جاهز بنقرة: الصندوق والحساب والبيان محفوظة',
      icon: Icons.bookmarks_rounded,
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('قالب')),
      body: _rows.isEmpty
          ? const EmptyState('لا توجد قوالب — أنشئ قالباً للسندات المتكررة (إيجار، رواتب، كهرباء...)',
              icon: Icons.bookmark_border)
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300, mainAxisExtent: 150, crossAxisSpacing: 12, mainAxisSpacing: 12),
              itemCount: _rows.length,
              itemBuilder: (_, i) {
                final t = _rows[i];
                final label = voucherLabel(t['voucher_type'] as String?);
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _use(t),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16), border: Border.all(color: ErpColors.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          StatusBadge(label, color: ErpColors.blue),
                          const Spacer(),
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'edit') _edit(t);
                              if (v == 'del') {
                                final ok = await confirmDialog(context, 'حذف القالب', 'حذف «${t['name']}»؟',
                                    color: ErpColors.red);
                                if (ok) {
                                  await _svc.delete(t['id'] as int);
                                  _load();
                                }
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('تعديل')),
                              PopupMenuItem(value: 'del', child: Text('حذف')),
                            ],
                          ),
                        ]),
                        const Spacer(),
                        Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('${t['account_name'] ?? ''} • ${t['box_name'] ?? ''}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ErpColors.muted)),
                        const SizedBox(height: 4),
                        const Text('انقر لإنشاء السند', style: TextStyle(fontSize: 11, color: ErpColors.blue)),
                      ]),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
