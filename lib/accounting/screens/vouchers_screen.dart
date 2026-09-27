// lib/accounting/screens/vouchers_screen.dart
//
// 🧾 السندات: قائمة + إنشاء (مصروف، إيراد، صرف، قبض، تحويل، رصيد افتتاحي).

import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../ledger.dart';
import '../vouchers_service.dart';
import 'acc_ui.dart';

class VouchersScreen extends StatefulWidget {
  const VouchersScreen({super.key, this.initialNew = false});

  /// يفتح نموذج سند مصروف مباشرة.
  final bool initialNew;

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen> {
  final _svc = VouchersService();
  DateTime? _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  VoucherType? _type;
  List<Map<String, Object?>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.initialNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _new(VoucherType.expense));
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _svc.list(from: _from, to: _to, type: _type);
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _new(VoucherType type) async {
    if (!requirePermission(context, AppPermissions.accountingPost)) return;
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => VoucherFormScreen(type: type)));
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, Object?> v) async {
    if (!requirePermission(context, AppPermissions.accountingPost)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف السند'),
        content: Text('حذف ${voucherTypeLabels[VoucherType.values.byName(v['voucher_type'] as String)]} '
            'رقم ${v['voucher_number']} بمبلغ ${fmtMoney((v['amount'] as num))}؟\n'
            'سيُحذف قيده من الدفتر ويبقى السند محفوظاً في السجل كـ«محذوف».'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AccColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.delete(v['id'] as int, userId: AuthService().currentUser?.id);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('السندات'),
      floatingActionButton: PopupMenuButton<VoucherType>(
        onSelected: _new,
        itemBuilder: (_) => [
          for (final t in VoucherType.values)
            PopupMenuItem(value: t, child: Text(voucherTypeLabels[t]!)),
        ],
        child: const FloatingActionButton.extended(
          onPressed: null,
          backgroundColor: AccColors.navy,
          foregroundColor: Colors.white,
          icon: Icon(Icons.add),
          label: Text('سند جديد'),
        ),
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
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: ChoiceChip(
                label: const Text('الكل'),
                selected: _type == null,
                onSelected: (_) {
                  setState(() => _type = null);
                  _load();
                },
              ),
            ),
            for (final t in VoucherType.values)
              Padding(
                padding: const EdgeInsets.all(4),
                child: ChoiceChip(
                  label: Text(voucherTypeLabels[t]!),
                  selected: _type == t,
                  onSelected: (_) {
                    setState(() => _type = t);
                    _load();
                  },
                ),
              ),
          ]),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _rows.isEmpty && !_loading
              ? const Center(child: Text('لا توجد سندات في هذه الفترة'))
              : ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final v = _rows[i];
                    final type = VoucherType.values.byName(v['voucher_type'] as String);
                    final isOut = type == VoucherType.expense || type == VoucherType.payment;
                    final target = type == VoucherType.transfer
                        ? '${v['cash_box_name']} ← ${v['to_cash_box_name']}'
                        : '${v['account_name'] ?? ''} • ${v['cash_box_name'] ?? ''}';
                    return ListTile(
                      tileColor: Colors.white,
                      leading: Icon(
                        isOut ? Icons.arrow_upward : Icons.arrow_downward,
                        color: isOut ? AccColors.red : AccColors.green,
                      ),
                      title: Text('${voucherTypeLabels[type]} رقم ${v['voucher_number']} — $target'),
                      subtitle: Text(
                          '${fmtDate(DateTime.parse(v['voucher_date'] as String))}'
                          '${(v['description'] as String?)?.isNotEmpty == true ? ' • ${v['description']}' : ''}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        MoneyText((v['amount'] as num).toDouble(), bold: true),
                        IconButton(
                          tooltip: 'حذف',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(v),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════ نموذج السند ═══════════════════════════════

class VoucherFormScreen extends StatefulWidget {
  const VoucherFormScreen({super.key, required this.type});
  final VoucherType type;

  @override
  State<VoucherFormScreen> createState() => _VoucherFormScreenState();
}

class _VoucherFormScreenState extends State<VoucherFormScreen> {
  final _svc = VouchersService();
  final _ledger = Ledger();
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  final _ref = TextEditingController();
  DateTime _date = DateTime.now();
  List<CashBox> _boxes = const [];
  List<Account> _accounts = const [];
  CashBox? _box;
  CashBox? _toBox;
  Account? _account;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final boxes = await _svc.cashBoxes();
    final all = await _ledger.postableAccounts(excludeControl: true);
    final boxAccIds = boxes.map((b) => b.accountId).toSet();
    List<Account> accs;
    switch (widget.type) {
      case VoucherType.expense:
        accs = all.where((a) => a.type == 'expense').toList();
        break;
      case VoucherType.income:
        accs = all.where((a) => a.type == 'revenue').toList();
        break;
      default:
        accs = all.where((a) => !boxAccIds.contains(a.id)).toList();
    }
    if (!mounted) return;
    setState(() {
      _boxes = boxes;
      _box = boxes.isEmpty ? null : boxes.first;
      _accounts = accs;
    });
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '')) ?? 0;
    if (_box == null) {
      showError(context, 'اختر الصندوق');
      return;
    }
    if (amount <= 0) {
      showError(context, 'أدخل المبلغ');
      return;
    }
    final needsAccount =
        widget.type != VoucherType.transfer && widget.type != VoucherType.opening;
    if (needsAccount && _account == null) {
      showError(context, 'اختر الحساب');
      return;
    }
    setState(() => _saving = true);
    try {
      await _svc.create(
        type: widget.type,
        amount: amount,
        date: _date,
        cashBoxId: _box!.id,
        toCashBoxId: _toBox?.id,
        accountId: _account?.id,
        description: _desc.text.trim(),
        reference: _ref.text.trim(),
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
    final t = widget.type;
    final accountLabel = switch (t) {
      VoucherType.expense => 'نوع المصروف',
      VoucherType.income => 'نوع الإيراد',
      VoucherType.payment => 'الحساب المدفوع له',
      VoucherType.receipt => 'الحساب المقبوض منه',
      _ => 'الحساب',
    };
    final boxLabel = switch (t) {
      VoucherType.transfer => 'من الصندوق',
      VoucherType.expense || VoucherType.payment => 'يُدفع من',
      _ => 'يُقبض في',
    };
    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar(voucherTypeLabels[t]!),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                  labelText: 'المبلغ (دينار)', filled: true, fillColor: Colors.white),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CashBox>(
              value: _box,
              decoration: InputDecoration(labelText: boxLabel, filled: true, fillColor: Colors.white),
              items: [for (final b in _boxes) DropdownMenuItem(value: b, child: Text(b.name))],
              onChanged: (b) => setState(() => _box = b),
            ),
            const SizedBox(height: 12),
            if (t == VoucherType.transfer)
              DropdownButtonFormField<CashBox>(
                value: _toBox,
                decoration: const InputDecoration(
                    labelText: 'إلى الصندوق', filled: true, fillColor: Colors.white),
                items: [
                  for (final b in _boxes.where((b) => b.id != _box?.id))
                    DropdownMenuItem(value: b, child: Text(b.name))
                ],
                onChanged: (b) => setState(() => _toBox = b),
              )
            else if (t != VoucherType.opening)
              DropdownButtonFormField<Account>(
                value: _account,
                isExpanded: true,
                decoration: InputDecoration(labelText: accountLabel, filled: true, fillColor: Colors.white),
                items: [
                  for (final a in _accounts)
                    DropdownMenuItem(value: a, child: Text('${a.code}  ${a.name}'))
                ],
                onChanged: (a) => setState(() => _account = a),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(labelText: 'البيان', filled: true, fillColor: Colors.white),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ref,
              decoration: const InputDecoration(
                  labelText: 'رقم مرجعي (وصل/فاتورة خارجية) — اختياري',
                  filled: true,
                  fillColor: Colors.white),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text('التاريخ: ${fmtDate(_date)}'),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context, initialDate: _date, firstDate: DateTime(2015), lastDate: DateTime(2100));
                if (d != null) setState(() => _date = d);
              },
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: AccColors.navy, padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('حفظ السند'),
            ),
          ]),
        ),
      ),
    );
  }
}
