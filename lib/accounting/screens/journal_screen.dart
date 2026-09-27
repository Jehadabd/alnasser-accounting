// lib/accounting/screens/journal_screen.dart
//
// 📖 القيود اليومية: القائمة، التفاصيل، والقيد اليدوي.

import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../ledger.dart';
import 'acc_ui.dart';

const Map<String, String> sourceTypeLabels = {
  'invoice': 'فاتورة بيع',
  'customer_tx': 'دين عميل',
  'purchase_invoice': 'فاتورة مشتريات',
  'supplier_tx': 'حساب مورد',
  'voucher': 'سند',
  'manual': 'قيد يدوي',
  'inventory_valuation': 'مطابقة مخزون',
};

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final _ledger = Ledger();
  DateTime? _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String? _source;
  List<Map<String, Object?>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _ledger.entries(from: _from, to: _to, sourceType: _source, limit: 1000);
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showEntry(Map<String, Object?> e) async {
    final lines = await _ledger.entryLines(e['id'] as int);
    if (!mounted) return;
    final isManual = e['source_type'] == 'manual';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('قيد رقم ${e['entry_number']}'),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e['description'] as String? ?? ''),
            const SizedBox(height: 4),
            Text(
              '${fmtDate(DateTime.parse(e['entry_date'] as String))} • ${sourceTypeLabels[e['source_type']] ?? e['source_type']}',
              style: const TextStyle(color: AccColors.muted),
            ),
            const Divider(),
            Table(
              columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(1.3), 2: FlexColumnWidth(1.3)},
              children: [
                const TableRow(children: [
                  Text('الحساب', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('مدين', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('دائن', style: TextStyle(fontWeight: FontWeight.bold)),
                ]),
                for (final l in lines)
                  TableRow(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('${l['account_code']} ${l['account_name']}'
                          '${l['memo'] == null ? '' : ' — ${l['memo']}'}'),
                    ),
                    MoneyText((l['debit'] as num).toDouble()),
                    MoneyText((l['credit'] as num).toDouble()),
                  ]),
              ],
            ),
          ]),
        ),
        actions: [
          if (isManual)
            TextButton(
              onPressed: () async {
                if (!requirePermission(context, AppPermissions.accountingPost)) return;
                try {
                  await _ledger.deleteManualEntry(e['id'] as int);
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } catch (err) {
                  if (mounted) showError(context, err);
                }
              },
              child: const Text('حذف القيد', style: TextStyle(color: AccColors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('القيود اليومية', actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AccColors.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('قيد يدوي'),
        onPressed: () async {
          if (!requirePermission(context, AppPermissions.accountingPost)) return;
          final saved = await Navigator.push<bool>(
              context, MaterialPageRoute(builder: (_) => const ManualEntryScreen()));
          if (saved == true) _load();
        },
      ),
      body: Column(children: [
        PeriodBar(
          from: _from,
          to: _to,
          onChanged: (f, t) {
            setState(() {
              _from = f;
              _to = t;
            });
            _load();
          },
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: ChoiceChip(
                label: const Text('الكل'),
                selected: _source == null,
                onSelected: (_) {
                  setState(() => _source = null);
                  _load();
                },
              ),
            ),
            for (final e in sourceTypeLabels.entries)
              Padding(
                padding: const EdgeInsets.all(4),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: _source == e.key,
                  onSelected: (_) {
                    setState(() => _source = e.key);
                    _load();
                  },
                ),
              ),
          ]),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _rows.isEmpty && !_loading
              ? const Center(child: Text('لا توجد قيود في هذه الفترة'))
              : ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = _rows[i];
                    return ListTile(
                      tileColor: Colors.white,
                      leading: CircleAvatar(
                        backgroundColor: AccColors.navy.withOpacity(0.1),
                        child: Text('${e['entry_number']}',
                            style: const TextStyle(fontSize: 11, color: AccColors.navy)),
                      ),
                      title: Text(e['description'] as String? ?? ''),
                      subtitle: Text(
                          '${fmtDate(DateTime.parse(e['entry_date'] as String))} • ${sourceTypeLabels[e['source_type']] ?? e['source_type']}'),
                      trailing: MoneyText((e['total'] as num).toDouble(), bold: true),
                      onTap: () => _showEntry(e),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════ القيد اليدوي ═══════════════════════════════

class _LineDraft {
  Account? account;
  final debit = TextEditingController();
  final credit = TextEditingController();
  final memo = TextEditingController();
  double get d => double.tryParse(debit.text.replaceAll(',', '')) ?? 0;
  double get c => double.tryParse(credit.text.replaceAll(',', '')) ?? 0;
}

class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  final _ledger = Ledger();
  final _desc = TextEditingController();
  DateTime _date = DateTime.now();
  List<Account> _accounts = const [];
  final List<_LineDraft> _lines = [_LineDraft(), _LineDraft()];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ledger.postableAccounts(excludeControl: true).then((a) {
      if (mounted) setState(() => _accounts = a);
    });
  }

  double get _dr => _lines.fold(0.0, (s, l) => s + l.d);
  double get _cr => _lines.fold(0.0, (s, l) => s + l.c);

  Future<void> _save() async {
    if (_desc.text.trim().isEmpty) {
      showError(context, 'اكتب بيان القيد');
      return;
    }
    final inputs = <JournalLineInput>[];
    for (final l in _lines) {
      if (l.account == null && l.d == 0 && l.c == 0) continue;
      if (l.account == null) {
        showError(context, 'اختر الحساب في كل سطر فيه مبلغ');
        return;
      }
      inputs.add(JournalLineInput(
          accountId: l.account!.id,
          debit: l.d,
          credit: l.c,
          memo: l.memo.text.trim().isEmpty ? null : l.memo.text.trim()));
    }
    setState(() => _saving = true);
    try {
      await _ledger.postManualEntry(
        date: _date,
        description: _desc.text.trim(),
        lines: inputs,
        userId: AuthService().currentUser?.id,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = _dr - _cr;
    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('قيد يدوي'),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          Expanded(
            child: TextField(
                controller: _desc,
                decoration: const InputDecoration(labelText: 'البيان', filled: true, fillColor: Colors.white)),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text(fmtDate(_date)),
            onPressed: () async {
              final d = await showDatePicker(
                  context: context, initialDate: _date, firstDate: DateTime(2015), lastDate: DateTime(2100));
              if (d != null) setState(() => _date = d);
            },
          ),
        ]),
        const SizedBox(height: 12),
        for (var i = 0; i < _lines.length; i++) _lineRow(i),
        TextButton.icon(
          onPressed: () => setState(() => _lines.add(_LineDraft())),
          icon: const Icon(Icons.add),
          label: const Text('سطر جديد'),
        ),
        const Divider(),
        Row(children: [
          const Text('مجموع المدين: '),
          MoneyText(_dr, bold: true),
          const SizedBox(width: 24),
          const Text('مجموع الدائن: '),
          MoneyText(_cr, bold: true),
          const SizedBox(width: 24),
          if (diff.abs() > kMoneyEpsilon)
            Text('الفرق: ${fmtMoney(diff)}', style: const TextStyle(color: AccColors.red))
          else
            const Text('متوازن ✓', style: TextStyle(color: AccColors.green)),
        ]),
        const SizedBox(height: 16),
        const Text(
          'ملاحظة: حسابات ذمم العملاء والموردين لا تظهر هنا — ديونهم تُسجَّل من سجل الديون وشاشة الموردين حتى تبقى أرصدتهم صحيحة.',
          style: TextStyle(color: AccColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving || diff.abs() > kMoneyEpsilon || _dr <= 0 ? null : _save,
          icon: const Icon(Icons.save),
          label: const Text('حفظ القيد'),
        ),
      ]),
    );
  }

  Widget _lineRow(int i) {
    final l = _lines[i];
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          Expanded(
            flex: 4,
            child: Autocomplete<Account>(
              displayStringForOption: (a) => '${a.code} ${a.name}',
              optionsBuilder: (v) {
                final q = v.text.trim();
                if (q.isEmpty) return _accounts.take(30);
                return _accounts.where((a) => a.name.contains(q) || a.code.startsWith(q)).take(30);
              },
              onSelected: (a) => setState(() => l.account = a),
              fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
                controller: ctrl,
                focusNode: focus,
                decoration: InputDecoration(
                  labelText: 'الحساب',
                  suffixIcon: l.account == null ? null : const Icon(Icons.check, color: AccColors.green),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextField(
              controller: l.debit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'مدين'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextField(
              controller: l.credit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'دائن'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: TextField(controller: l.memo, decoration: const InputDecoration(labelText: 'ملاحظة')),
          ),
          IconButton(
            onPressed: _lines.length <= 2 ? null : () => setState(() => _lines.removeAt(i)),
            icon: const Icon(Icons.delete_outline),
          ),
        ]),
      ),
    );
  }
}
