// lib/erp/debts/due_items_screen.dart
//
// 📅 شاشة الاستحقاقات: شيكات وأوراق القبض والدفع والأقساط — إدخال، تحصيل،
// ارتداد، إلغاء، مع مؤشرات المتأخر والمستحق هذا الأسبوع.

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart';
import '../../accounting/screens/acc_ui.dart';
import '../currency_service.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../report_export.dart';
import 'due_items_service.dart';

class DueItemsScreen extends StatefulWidget {
  const DueItemsScreen({super.key, this.partyType, this.partyId, this.partyName});
  final String? partyType;
  final int? partyId;
  final String? partyName;
  @override
  State<DueItemsScreen> createState() => _DueItemsScreenState();
}

class _DueItemsScreenState extends State<DueItemsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final _svc = DueItemsService();
  List<Map<String, Object?>> _rows = const [];
  Map<String, double> _kpi = const {};
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _load();
    });
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    List<Map<String, Object?>> r;
    switch (_tabs.index) {
      case 0: // قبض مفتوح
        r = (await _svc.list(partyType: widget.partyType ?? 'customer', partyId: widget.partyId, search: _search));
        break;
      case 1: // دفع مفتوح
        r = await _svc.list(partyType: 'supplier', partyId: widget.partyType == 'supplier' ? widget.partyId : null, search: _search);
        break;
      case 2: // المتأخر
        r = (await _svc.list(partyType: widget.partyType, partyId: widget.partyId, search: _search))
            .where((x) => parseDate(x['due_date']).isBefore(DateTime(now.year, now.month, now.day)))
            .toList();
        break;
      default: // الكل مع المغلق
        r = await _svc.list(
            includeClosed: true, partyType: widget.partyType, partyId: widget.partyId, search: _search);
    }
    final k = await _svc.dashboard();
    if (mounted) {
      setState(() {
        _rows = r;
        _kpi = k;
      });
    }
  }

  List<String> get _headers =>
      ['الرقم', 'النوع', 'الطرف', 'المبلغ', 'المسدد', 'المتبقي', 'العملة', 'تاريخ الاستحقاق', 'المستند', 'الحالة'];
  List<List<String>> get _data => [
        for (final r in _rows)
          [
            '${r['due_no']}',
            dueKindLabels[r['kind']] ?? '${r['kind']}',
            '${r['party_name'] ?? ''}',
            fmtMoney(d0(r['amount'])),
            fmtMoney(d0(r['paid_amount'])),
            fmtMoney(d0(r['amount']) - d0(r['paid_amount'])),
            '${r['currency']}',
            fmtDate(parseDate(r['due_date'])),
            '${r['doc_no'] ?? ''}',
            dueStatusLabels[r['status']] ?? '${r['status']}',
          ],
      ];

  Color _statusColor(String s, DateTime due) {
    if (s == 'closed') return ErpColors.green;
    if (s == 'bounced') return ErpColors.red;
    if (s == 'cancelled') return ErpColors.muted;
    final today = DateTime.now();
    if (due.isBefore(DateTime(today.year, today.month, today.day))) return ErpColors.red;
    if (due.difference(today).inDays <= 7) return ErpColors.orange;
    return ErpColors.blue;
  }

  Future<void> _settle(Map<String, Object?> r) async {
    final remaining = d0(r['amount']) - d0(r['paid_amount']);
    final amount = TextEditingController(text: fmtMoney(remaining));
    final note = TextEditingController();
    int? box;
    DateTime date = DateTime.now();
    final receivable = dueIsReceivable(r['kind'] as String);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(receivable ? 'تحصيل الاستحقاق' : 'صرف الاستحقاق'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${dueKindLabels[r['kind']]} رقم ${r['due_no']} — ${r['party_name']}'),
              const SizedBox(height: 6),
              Text('المتبقي: ${fmtMoney(remaining)} ${r['currency']}', style: const TextStyle(color: ErpColors.navy)),
              const SizedBox(height: 12),
              MoneyField(controller: amount, label: 'المبلغ (${r['currency']})'),
              const SizedBox(height: 10),
              CashBoxDropdown(value: box, width: 400, onChanged: (b) => set(() => box = b?.id)),
              const SizedBox(height: 10),
              DateButton(label: 'التاريخ', value: date, onChanged: (d) => set(() => date = d)),
              const SizedBox(height: 10),
              TextBox(controller: note, label: 'ملاحظة'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تنفيذ')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (box == null) {
      showError(context, 'اختر الصندوق');
      return;
    }
    try {
      await _svc.settle(context,
          dueId: r['id'] as int,
          amount: parseMoney(amount.text) ?? 0,
          date: date,
          cashBoxId: box!,
          note: note.text.trim());
      if (mounted) showOk(context, 'تم');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _bounce(Map<String, Object?> r) async {
    final ok = await confirmDialog(context, 'ارتداد الشيك',
        'سيعود المتبقي (${fmtMoney(d0(r['amount']) - d0(r['paid_amount']))}) ديناً على ${r['party_name']}. متابعة؟',
        ok: 'ارتداد', color: ErpColors.red);
    if (!ok || !mounted) return;
    try {
      await _svc.bounce(context, dueId: r['id'] as int, date: DateTime.now());
      if (mounted) showOk(context, 'تم تسجيل الارتداد');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _cancel(Map<String, Object?> r) async {
    final ok = await confirmDialog(context, 'إلغاء الاستحقاق', 'إلغاء هذا الاستحقاق نهائياً؟', color: ErpColors.red);
    if (!ok) return;
    try {
      await _svc.cancel(r['id'] as int);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: widget.partyName == null ? 'الاستحقاقات' : 'استحقاقات ${widget.partyName}',
      subtitle: 'شيكات وأوراق القبض والدفع والأقساط',
      icon: Icons.event_note,
      actions: [
        ...exportActions(context, title: 'الاستحقاقات', headers: () => _headers, rows: () => _data),
      ],
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: ErpColors.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('استحقاق جديد'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => DueItemFormScreen(
                  partyType: widget.partyType, partyId: widget.partyId, partyName: widget.partyName)),
        ).then((_) => _load()),
      ),
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(
            label: 'متأخر التحصيل',
            value: fmtMoney(_kpi['overdue'] ?? 0),
            icon: Icons.warning_amber,
            color: ErpColors.red),
        StatCard(
            label: 'يستحق خلال 7 أيام',
            value: fmtMoney(_kpi['week'] ?? 0),
            icon: Icons.schedule,
            color: ErpColors.orange),
        StatCard(
            label: 'مجموع أوراق القبض المفتوحة',
            value: fmtMoney(_kpi['open'] ?? 0),
            icon: Icons.account_balance_wallet,
            color: ErpColors.green,
            hint: '${(_kpi['count'] ?? 0).toStringAsFixed(0)} استحقاق'),
      ]),
      body: Column(children: [
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabs,
            labelColor: ErpColors.navy,
            indicatorColor: ErpColors.cyan,
            tabs: const [
              Tab(text: 'قبض مفتوح'),
              Tab(text: 'دفع مفتوح'),
              Tab(text: 'المتأخر'),
              Tab(text: 'الكل'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: SearchBox(
              hint: 'بحث بالاسم، رقم الشيك، البنك، الكفيل...',
              onChanged: (v) {
                _search = v;
                _load();
              }),
        ),
        Expanded(
          child: _rows.isEmpty
              ? const EmptyState('لا توجد استحقاقات', icon: Icons.event_available)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 90),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) => _card(_rows[i]),
                ),
        ),
      ]),
    );
  }

  Widget _card(Map<String, Object?> r) {
    final status = r['status'] as String;
    final due = parseDate(r['due_date']);
    final color = _statusColor(status, due);
    final remaining = d0(r['amount']) - d0(r['paid_amount']);
    final open = status == 'open' || status == 'partial';
    final receivable = dueIsReceivable(r['kind'] as String);
    final days = due.difference(DateTime.now()).inDays;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(right: BorderSide(color: color, width: 5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${dueKindLabels[r['kind']]} #${r['due_no']}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(width: 8),
              StatusBadge(dueStatusLabels[status] ?? status, color: color),
              if (r['installment_no'] != null) ...[
                const SizedBox(width: 6),
                StatusBadge('قسط ${r['installment_no']}/${r['installments_total']}', color: ErpColors.purple),
              ],
              if ((r['affects_balance'] as int? ?? 0) == 1) ...[
                const SizedBox(width: 6),
                const StatusBadge('نُزّل من الرصيد', color: ErpColors.green),
              ],
            ]),
            const SizedBox(height: 4),
            Text('${r['party_name'] ?? ''}', style: const TextStyle(fontSize: 15)),
            Text(
              [
                'يستحق ${fmtDate(due)}${open ? (days < 0 ? ' (متأخر ${-days} يوم)' : ' (بعد $days يوم)') : ''}',
                if ((r['doc_no'] as String?)?.isNotEmpty == true) 'رقم ${r['doc_no']}',
                if ((r['bank_name'] as String?)?.isNotEmpty == true) '${r['bank_name']}',
                if ((r['guarantor'] as String?)?.isNotEmpty == true) 'الكفيل: ${r['guarantor']}',
              ].join(' • '),
              style: const TextStyle(color: ErpColors.muted, fontSize: 12.5),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${fmtMoney(d0(r['amount']))} ${r['currency'] == 'IQD' ? '' : r['currency']}',
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          if (d0(r['paid_amount']) > 0)
            Text('المتبقي ${fmtMoney(remaining)}', style: const TextStyle(fontSize: 12, color: ErpColors.orange)),
          if (open)
            Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton.icon(
                onPressed: () => _settle(r),
                icon: Icon(receivable ? Icons.call_received : Icons.call_made, size: 18),
                label: Text(receivable ? 'تحصيل' : 'صرف'),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'bounce') _bounce(r);
                  if (v == 'cancel') _cancel(r);
                },
                itemBuilder: (_) => [
                  if (receivable && r['kind'] != 'installment')
                    const PopupMenuItem(value: 'bounce', child: Text('ارتداد (شيك مرتجع)')),
                  if ((r['affects_balance'] as int? ?? 0) == 0 && d0(r['paid_amount']) == 0)
                    const PopupMenuItem(value: 'cancel', child: Text('إلغاء')),
                ],
              ),
            ]),
        ]),
      ]),
    );
  }
}

/// إدخال استحقاق جديد (مفرد أو أقساط).
class DueItemFormScreen extends StatefulWidget {
  const DueItemFormScreen({super.key, this.partyType, this.partyId, this.partyName});
  final String? partyType;
  final int? partyId;
  final String? partyName;
  @override
  State<DueItemFormScreen> createState() => _DueItemFormScreenState();
}

class _DueItemFormScreenState extends State<DueItemFormScreen> {
  String _kind = 'cheque_in';
  PartyLite? _party;
  DateTime _issue = DateTime.now();
  DateTime _due = DateTime.now().add(const Duration(days: 30));
  String _currency = 'IQD';
  final _amount = TextEditingController();
  final _rate = TextEditingController(text: '1');
  final _installments = TextEditingController(text: '1');
  final _interval = TextEditingController(text: '1');
  final _docNo = TextEditingController();
  final _bank = TextEditingController();
  final _guarantor = TextEditingController();
  final _statement = TextEditingController();
  bool _affect = true;
  bool _saving = false;

  bool get _receivable => dueIsReceivable(_kind);

  @override
  void initState() {
    super.initState();
    if (widget.partyId != null) {
      _party = PartyLite(widget.partyId!, widget.partyName ?? '', null, 0);
      if (widget.partyType == 'supplier') _kind = 'cheque_out';
    }
  }

  Future<void> _loadRate() async {
    if (_currency == 'IQD') {
      _rate.text = '1';
      return;
    }
    final db = await erpDb();
    final r = await CurrencyService.rateAt(db, _currency, _issue);
    if (mounted) setState(() => _rate.text = fmtMoney(r));
  }

  Future<void> _save() async {
    final amt = parseMoney(_amount.text) ?? 0;
    if (_party == null) {
      showError(context, 'اختر ${_receivable ? 'العميل' : 'المورد'}');
      return;
    }
    if (amt <= 0) {
      showError(context, 'أدخل المبلغ');
      return;
    }
    final n = int.tryParse(_installments.text) ?? 1;
    if (_affect && _kind != 'installment') {
      final ok = await confirmDialog(
          context,
          'تنزيل من الرصيد',
          'سيُنزَّل ${fmtMoney(amt)} من رصيد «${_party!.name}» الآن ويُحفظ في حساب '
              '${_receivable ? 'أوراق القبض' : 'أوراق الدفع'} حتى التحصيل. متابعة؟');
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final ids = await DueItemsService().create(
        context,
        kind: _kind,
        partyType: _receivable ? 'customer' : 'supplier',
        partyId: _party!.id,
        partyName: _party!.name,
        amount: amt,
        currency: _currency,
        fxRate: parseMoney(_rate.text) ?? 1,
        issueDate: _issue,
        dueDate: _due,
        installments: n < 1 ? 1 : n,
        intervalMonths: int.tryParse(_interval.text) ?? 1,
        docNo: _docNo.text.trim(),
        bankName: _bank.text.trim(),
        guarantor: _guarantor.text.trim(),
        statement: _statement.text.trim(),
        affectBalance: _affect && _kind != 'installment',
      );
      if (!mounted) return;
      showOk(context, 'حُفظ ${ids.length} استحقاق');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = int.tryParse(_installments.text) ?? 1;
    final amt = parseMoney(_amount.text) ?? 0;
    return ErpPage(
      title: 'استحقاق جديد',
      subtitle: 'شيك، كمبيالة، أو تقسيط دين على أقساط',
      icon: Icons.post_add,
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        ErpSection(
          title: 'النوع',
          icon: Icons.category_outlined,
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in dueKindLabels.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _kind == e.key,
                selectedColor: ErpColors.navy.withOpacity(0.15),
                onSelected: (_) => setState(() {
                  final wasReceivable = _receivable;
                  _kind = e.key;
                  if (wasReceivable != _receivable) _party = null;
                }),
              ),
          ]),
        ),
        ErpSection(
          title: _receivable ? 'العميل' : 'المورد',
          icon: _receivable ? Icons.person_outline : Icons.local_shipping_outlined,
          color: _receivable ? ErpColors.blue : ErpColors.orange,
          child: Row(children: [
            Expanded(
              child: Text(_party?.name ?? 'لم يُختر',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _party == null ? ErpColors.muted : ErpColors.text)),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('اختيار'),
              onPressed: () async {
                final p = _receivable ? await Pickers.customer(context) : await Pickers.supplier(context);
                if (p != null) setState(() => _party = p);
              },
            ),
          ]),
        ),
        ErpSection(
          title: 'التفاصيل',
          icon: Icons.edit_note,
          child: FieldGrid(children: [
            MoneyField(controller: _amount, label: 'المبلغ الإجمالي', width: 180, onChanged: (_) => setState(() {})),
            DropBox<String>(
              label: 'العملة',
              width: 140,
              value: _currency,
              items: const [
                DropdownMenuItem(value: 'IQD', child: Text('دينار')),
                DropdownMenuItem(value: 'USD', child: Text('دولار')),
              ],
              onChanged: (v) {
                setState(() => _currency = v ?? 'IQD');
                _loadRate();
              },
            ),
            if (_currency != 'IQD') MoneyField(controller: _rate, label: 'سعر التعادل', width: 130),
            DateButton(label: 'تاريخ التسجيل', value: _issue, onChanged: (d) => setState(() => _issue = d)),
            DateButton(
                label: n > 1 ? 'استحقاق القسط الأول' : 'تاريخ الاستحقاق',
                value: _due,
                onChanged: (d) => setState(() => _due = d)),
            SizedBox(
              width: 130,
              child: TextField(
                controller: _installments,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'عدد الأقساط', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (n > 1)
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _interval,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'كل (شهر)', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white),
                ),
              ),
            if (n > 1) InfoTile('قيمة القسط', fmtMoney(roundMoney(amt / n))),
            TextBox(controller: _docNo, label: 'رقم الشيك / المستند', width: 180),
            TextBox(controller: _bank, label: 'المصرف', width: 180),
            TextBox(controller: _guarantor, label: 'الكفيل', width: 200),
            TextBox(controller: _statement, label: 'البيان', width: 320),
          ]),
        ),
        if (_kind != 'installment')
          ErpSection(
            title: 'الأثر على الرصيد',
            icon: Icons.account_balance,
            color: ErpColors.green,
            child: SwitchListTile(
              value: _affect,
              onChanged: (v) => setState(() => _affect = v),
              title: Text(_receivable
                  ? 'تنزيل المبلغ من دين العميل الآن (استلمنا الشيك)'
                  : 'تنزيل المبلغ من رصيد المورد الآن (سلّمناه الشيك)'),
              subtitle: const Text('يُحفظ المبلغ في حساب الأوراق حتى التحصيل أو الارتداد. '
                  'أوقفه إن كان الاستحقاق مجرد تذكير بموعد سداد.'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: PrimaryButton(label: 'حفظ', icon: Icons.save, busy: _saving, onPressed: _save),
        ),
      ]),
    );
  }
}

double dueRound(double v) => roundMoney(v);
