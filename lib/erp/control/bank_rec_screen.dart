// lib/erp/control/bank_rec_screen.dart
//
// 🏦 شاشات مطابقة كشف البنك: القائمة، ومطابقة واحدة (تعليم الحركات حتى يصير الفرق صفراً).

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart' show fmtMoney, fmtDate, showError, showOk;
import '../erp_common.dart';
import '../erp_kit.dart' show erpDialogActions;
import '../erp_ui.dart';
import 'bank_rec_service.dart';
import 'control_common.dart';

class BankRecListScreen extends StatefulWidget {
  const BankRecListScreen({super.key});
  @override
  State<BankRecListScreen> createState() => _BankRecListScreenState();
}

class _BankRecListScreenState extends State<BankRecListScreen> {
  List<BankRec> _rows = const [];
  bool _loading = true;
  bool _admin = false;

  @override
  void initState() {
    super.initState();
    currentIsAdmin().then((a) {
      if (mounted) setState(() => _admin = a);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await BankRecService.list();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  Future<void> _new() async {
    final boxes = await BankRecService.boxes();
    if (!mounted) return;
    if (boxes.isEmpty) {
      showError(context, 'لا صناديق');
      return;
    }
    int boxId = boxes.first['id'] as int;
    DateTime date = DateTime.now();
    final bal = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('مطابقة كشف جديد'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<int>(
                initialValue: boxId,
                decoration: const InputDecoration(labelText: 'الحساب البنكي / الصندوق'),
                items: [
                  for (final b in boxes)
                    DropdownMenuItem(
                        value: b['id'] as int, child: Text('${b['name']}${b['kind'] == 'bank' ? ' (بنك)' : ''}')),
                ],
                onChanged: (v) => setD(() => boxId = v ?? boxId),
              ),
              const SizedBox(height: 10),
              DateButton(label: 'تاريخ الكشف', value: date, onChanged: (d) => setD(() => date = d)),
              const SizedBox(height: 10),
              MoneyField(controller: bal, label: 'الرصيد في نهاية الكشف', autofocus: true),
            ]),
          ),
          actions: erpDialogActions(ctx, ok: 'ابدأ المطابقة'),
        ),
      ),
    );
    final v = parseMoney(bal.text);
    bal.dispose();
    if (ok != true || !mounted) return;
    if (v == null) {
      showError(context, 'اكتب رصيد الكشف');
      return;
    }
    try {
      final id = await BankRecService.create(boxId: boxId, statementDate: date, statementBalance: v);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => BankRecScreen(recId: id)));
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'مطابقة كشف البنك',
      subtitle: 'علّم حركات الدفتر التي ظهرت في الكشف حتى يصير الفرق صفراً',
      icon: Icons.account_balance_rounded,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        backgroundColor: ErpColors.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('مطابقة كشف'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const EmptyState('لا مطابقات بعد.\nابدأ بكشف البنك الأخير ورصيده.', icon: Icons.account_balance_rounded)
              : ListView(padding: const EdgeInsets.fromLTRB(8, 8, 8, 80), children: [
                  for (final r in _rows)
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12), side: const BorderSide(color: ErpColors.border)),
                      child: ListTile(
                        leading: Icon(r.isFinal ? Icons.verified_rounded : Icons.pending_actions_rounded,
                            color: r.isFinal ? ErpColors.green : ErpColors.orange),
                        title: Text('${r.boxName ?? ''} — كشف ${fmtDate(r.statementDate)}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text([
                          'رصيد الكشف ${fmtMoney(r.statementBalance)}',
                          r.isFinal ? 'معتمدة' : 'مفتوحة',
                          if (r.createdBy != null) r.createdBy!,
                        ].join(' • ')),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (r.isFinal && _admin)
                            IconButton(
                              tooltip: 'إلغاء الاعتماد',
                              icon: const Icon(Icons.lock_open_rounded),
                              onPressed: () async {
                                try {
                                  await BankRecService.reopen(r.id);
                                  _load();
                                } catch (e) {
                                  if (context.mounted) showError(context, e);
                                }
                              },
                            ),
                          if (!r.isFinal)
                            IconButton(
                              tooltip: 'حذف',
                              icon: const Icon(Icons.delete_outline_rounded, color: ErpColors.red),
                              onPressed: () async {
                                final ok = await confirmDialog(context, 'حذف المطابقة المفتوحة', 'تُحذف العلامات فقط — لا يتغير أي قيد.',
                                    ok: 'حذف', color: ErpColors.red);
                                if (!ok) return;
                                try {
                                  await BankRecService.deleteDraft(r.id);
                                  _load();
                                } catch (e) {
                                  if (context.mounted) showError(context, e);
                                }
                              },
                            ),
                        ]),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => BankRecScreen(recId: r.id)));
                          _load();
                        },
                      ),
                    ),
                ]),
    );
  }
}

class BankRecScreen extends StatefulWidget {
  const BankRecScreen({super.key, required this.recId});
  final int recId;
  @override
  State<BankRecScreen> createState() => _BankRecScreenState();
}

class _BankRecScreenState extends State<BankRecScreen> {
  BankRecState? _st;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final st = await BankRecService.load(widget.recId);
      if (mounted) setState(() => _st = st);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggle(BankLine l, bool v) async {
    if (_busy) return;
    _busy = true;
    try {
      await BankRecService.toggle(widget.recId, l, v);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      _busy = false;
    }
  }

  Future<void> _finalize() async {
    try {
      await BankRecService.finalize(widget.recId);
      if (mounted) {
        showOk(context, 'اعتُمدت المطابقة');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    return ErpPage(
      title: 'مطابقة ${st?.rec.boxName ?? ''}',
      subtitle: st == null ? null : 'كشف ${fmtDate(st.rec.statementDate)} — رصيده ${fmtMoney(st.rec.statementBalance)}',
      icon: Icons.account_balance_rounded,
      bottom: st == null || st.rec.isFinal
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      st.balanced ? 'الفرق صفر — جاهزة للاعتماد' : 'الفرق ${fmtMoney(st.difference)}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16, color: st.balanced ? ErpColors.green : ErpColors.red),
                    ),
                  ),
                  PrimaryButton(
                    label: 'اعتماد المطابقة',
                    icon: Icons.verified_rounded,
                    color: ErpColors.green,
                    onPressed: st.balanced ? _finalize : null,
                  ),
                ]),
              ),
            ),
      body: st == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 10, runSpacing: 10, children: [
                  StatCard(label: 'رصيد الكشف', value: fmtMoney(st.rec.statementBalance), icon: Icons.description_rounded),
                  StatCard(
                      label: 'الرصيد المطابَق',
                      value: fmtMoney(st.clearedBalance),
                      icon: Icons.done_all_rounded,
                      color: ErpColors.green,
                      hint: 'سابقاً ${fmtMoney(st.priorCleared)} + الآن ${fmtMoney(st.clearedNow)}'),
                  StatCard(
                      label: 'الفرق',
                      value: fmtMoney(st.difference),
                      icon: Icons.compare_arrows_rounded,
                      color: st.balanced ? ErpColors.green : ErpColors.red),
                  StatCard(
                      label: 'رصيد الدفتر حتى تاريخ الكشف',
                      value: fmtMoney(st.bookBalance),
                      icon: Icons.menu_book_rounded,
                      color: ErpColors.purple,
                      hint: 'إيداعات لم تظهر ${fmtMoney(st.unclearedIn)} • مدفوعات لم تظهر ${fmtMoney(st.unclearedOut)}'),
                ]),
              ),
              ErpSection(
                title: 'حركات الدفتر غير المطابقة (${st.lines.length})',
                icon: Icons.checklist_rounded,
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: st.lines.isEmpty
                    ? const EmptyState('لا حركات حتى تاريخ الكشف', icon: Icons.inbox_outlined)
                    : Column(children: [
                        for (final l in st.lines)
                          CheckboxListTile(
                            dense: true,
                            value: st.marked.contains(l.key),
                            onChanged: st.rec.isFinal ? null : (v) => _toggle(l, v ?? false),
                            title: Text('${l.amount >= 0 ? 'إيداع' : 'سحب'} ${fmtMoney(l.amount.abs())}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, color: l.amount >= 0 ? ErpColors.green : ErpColors.red)),
                            subtitle: Text('${fmtDate(l.date)} • قيد ${l.entryNo} • ${l.description}'),
                          ),
                      ]),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  'علّم كل حركة ظهرت في كشف البنك. ما ظهر في الكشف وليس في الدفتر (عمولة بنك، فائدة) سجّله أولاً بسند '
                  'ثم عُد هنا. المطابقة لا تغيّر أي قيد.',
                  style: TextStyle(fontSize: 12, color: ErpColors.muted, height: 1.5),
                ),
              ),
            ]),
    );
  }
}
