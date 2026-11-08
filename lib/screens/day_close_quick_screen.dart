// lib/screens/day_close_quick_screen.dart
//
// ⏱️ «إقفال اليوم في دقيقة»: قبل عدّ الدرج، سجّل ما خرج منه اليوم ولم يُسجَّل:
//   • مصروف (إيجار، كهرباء، أجور...)   ← سند مصروف (VouchersService)
//   • دفعة لمورد نقداً                   ← دفعة مورد (ReceiptsService.supplierPayment)
//   • سحب المالك                         ← سند صرف على «مسحوبات المالك»
// كل سطر يُحفظ بالمسار الأصلي نفسه الذي تستعمله شاشاته (لا منطق محاسبي جديد هنا):
// قيد متوازن، تثبيت الفترة، سجل النشاط. الأسطر لا تُحفظ إلا بزر «حفظ»، كل سطر
// على حدة: ما نجح يُزال من القائمة، وما فشل يبقى مع سببه — لا حفظ مكرر ولا نصف سطر.
// بعدها: «عدّ الدرج» يفتح إقفال اليوم والمتوقع فيه يشمل ما سُجّل الآن.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';

import '../accounting/ledger.dart' show Account, Ledger;
import '../accounting/vouchers_service.dart';
import '../erp/debts/receipts_service.dart';
import '../erp/device_defaults.dart';
import '../erp/pickers.dart' show CashBoxDropdown, PartyLite, Pickers;
import '../models/app_user.dart' show AppPermissions;
import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'day_close_screen.dart';

const _navy = Color(0xFF0F3460);
const _teal = Color(0xFF0F766E);
const _red = Color(0xFFB91C1C);
const _orange = Color(0xFFC2410C);
const _purple = Color(0xFF6D28D9);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE6EBF2);
const _ink = Color(0xFF1E293B);

enum _Kind { expense, supplier, drawing }

class _Out {
  _Out(this.kind, this.amount, this.note, {this.account, this.supplier});
  final _Kind kind;
  final double amount;
  final String note;
  final Account? account;
  final PartyLite? supplier;
  String? error;

  String get title => switch (kind) {
        _Kind.expense => account?.name ?? 'مصروف',
        _Kind.supplier => 'دفعة للمورد ${supplier?.name ?? ''}',
        _Kind.drawing => 'سحب المالك',
      };
  IconData get icon => switch (kind) {
        _Kind.expense => Icons.receipt_long_rounded,
        _Kind.supplier => Icons.local_shipping_rounded,
        _Kind.drawing => Icons.account_balance_wallet_rounded,
      };
  Color get color => switch (kind) {
        _Kind.expense => _orange,
        _Kind.supplier => _navy,
        _Kind.drawing => _purple,
      };
}

class DayCloseQuickScreen extends StatefulWidget {
  const DayCloseQuickScreen({super.key, this.initialDate});
  final DateTime? initialDate;

  /// يحق له فتحها: من يسجّل السندات (المحاسبة) أو دفعات الموردين.
  static bool get allowed =>
      AuthService().hasPermission(AppPermissions.accounting) || AuthService().hasPermission(AppPermissions.suppliers);

  @override
  State<DayCloseQuickScreen> createState() => _DayCloseQuickScreenState();
}

class _DayCloseQuickScreenState extends State<DayCloseQuickScreen> {
  static final _n = NumberFormat('#,##0', 'en');
  static const _kRecent = 'day_close_recent_expense_accounts';

  late DateTime _day;
  int? _boxId;
  String _boxName = '';
  bool _boxReady = false;
  final List<_Out> _pending = [];
  List<({String label, double amount})> _done = const [];
  List<Account> _recent = const [];
  bool _saving = false;

  bool get _canVouchers => AuthService().hasPermission(AppPermissions.accounting);
  bool get _canSuppliers => AuthService().hasPermission(AppPermissions.suppliers);

  @override
  void initState() {
    super.initState();
    final d = widget.initialDate ?? DateTime.now();
    _day = DateTime(d.year, d.month, d.day);
    DeviceDefaults.cashBoxId().then((b) {
      if (!mounted) return;
      setState(() {
        _boxId = b;
        _boxReady = true;
      });
      _loadDone();
    });
    _loadRecent();
  }

  // ─────────── ما سُجّل اليوم من هذا الصندوق (حتى لا يُسجَّل مرتين) ───────────

  Future<void> _loadDone() async {
    final box = _boxId;
    if (box == null) return;
    final db = await DatabaseService().database;
    final day = DateFormat('yyyy-MM-dd', 'en').format(_day);
    final out = <({String label, double amount})>[];
    try {
      final v = await db.rawQuery('''
        SELECT v.voucher_type AS t, v.amount AS a, v.description AS d, ac.name AS acc
        FROM vouchers v LEFT JOIN accounts ac ON ac.id = v.account_id
        WHERE substr(v.voucher_date, 1, 10) = ? AND v.cash_box_id = ? AND COALESCE(v.is_deleted, 0) = 0
          AND v.voucher_type IN ('expense', 'payment')
        ORDER BY v.id''', [day, box]);
      for (final r in v) {
        final desc = '${r['d'] ?? ''}'.trim();
        out.add((
          label: '${r['t'] == 'expense' ? 'مصروف' : 'صرف'}: ${r['acc'] ?? ''}${desc.isEmpty ? '' : ' — $desc'}',
          amount: (r['a'] as num?)?.toDouble() ?? 0,
        ));
      }
    } catch (_) {}
    try {
      final p = await db.rawQuery('''
        SELECT s.name AS n, p.amount AS a FROM supplier_payments p
        JOIN supplier_payment_ext e ON e.payment_id = p.id
        LEFT JOIN suppliers s ON s.id = p.supplier_id
        WHERE substr(p.date, 1, 10) = ? AND e.cash_box_id = ? AND p.currency = 'IQD'
          AND p.payment_method IN ('cash', 'bank')
        ORDER BY p.id''', [day, box]);
      for (final r in p) {
        out.add((label: 'دفعة للمورد ${r['n'] ?? ''}', amount: (r['a'] as num?)?.toDouble() ?? 0));
      }
    } catch (_) {}
    if (mounted) setState(() => _done = out);
  }

  // ─────────── آخر حسابات مصاريف استُعملت (أزرار سريعة) ───────────

  Future<void> _loadRecent() async {
    try {
      final ids = (await SharedPreferences.getInstance()).getStringList(_kRecent) ?? const [];
      if (ids.isEmpty) return;
      final all = await Ledger().postableAccounts(excludeControl: true);
      final byId = {for (final a in all) '${a.id}': a};
      final list = [
        for (final id in ids)
          if (byId[id] != null && byId[id]!.type == 'expense') byId[id]!
      ];
      if (mounted) setState(() => _recent = list);
    } catch (_) {}
  }

  Future<void> _remember(Account a) async {
    try {
      final p = await SharedPreferences.getInstance();
      final ids = [...(p.getStringList(_kRecent) ?? const <String>[])]..remove('${a.id}');
      ids.insert(0, '${a.id}');
      await p.setStringList(_kRecent, ids.take(6).toList());
    } catch (_) {}
  }

  // ─────────── إضافة سطر ───────────

  Future<void> _addExpense([Account? preset]) async {
    final acc = preset ?? await Pickers.account(context, title: 'نوع المصروف', type: 'expense');
    if (acc == null || !mounted) return;
    final r = await _amountDialog('مصروف: ${acc.name}', _orange, Icons.receipt_long_rounded);
    if (r == null) return;
    setState(() => _pending.add(_Out(_Kind.expense, r.amount, r.note, account: acc)));
  }

  Future<void> _addSupplier() async {
    final s = await Pickers.supplier(context, title: 'دفعة لأي مورد؟');
    if (s == null || !mounted) return;
    final r = await _amountDialog('دفعة نقدية للمورد ${s.name}', _navy, Icons.local_shipping_rounded,
        hint: 'رصيد المورد الآن ${_n.format(s.balance.round())}');
    if (r == null) return;
    setState(() => _pending.add(_Out(_Kind.supplier, r.amount, r.note, supplier: s)));
  }

  Future<void> _addDrawing() async {
    final r = await _amountDialog('سحب المالك من الدرج', _purple, Icons.account_balance_wallet_rounded);
    if (r == null) return;
    setState(() => _pending.add(_Out(_Kind.drawing, r.amount, r.note)));
  }

  Future<({double amount, String note})?> _amountDialog(String title, Color color, IconData icon,
      {String? hint}) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    try {
      return await showDialog<({double amount, String note})>(
        context: context,
        builder: (ctx) {
          double value() => double.tryParse(amount.text.replaceAll(',', '').trim()) ?? 0;
          return StatefulBuilder(
            builder: (ctx, setD) => AlertDialog(
              icon: Icon(icon, color: color, size: 30),
              title: Text(title, textAlign: TextAlign.center),
              content: SizedBox(
                width: 380,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(hint, style: const TextStyle(color: _muted, fontSize: 12.5)),
                    ),
                  TextField(
                    controller: amount,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))],
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(
                      labelText: 'المبلغ (دينار)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (_) => setD(() {}),
                    onSubmitted: (_) {
                      if (value() > 0) Navigator.pop(ctx, (amount: value(), note: note.text.trim()));
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    decoration: InputDecoration(
                      labelText: 'ملاحظة (اختياري)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (_) {
                      if (value() > 0) Navigator.pop(ctx, (amount: value(), note: note.text.trim()));
                    },
                  ),
                ]),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: color),
                  onPressed: value() > 0 ? () => Navigator.pop(ctx, (amount: value(), note: note.text.trim())) : null,
                  child: const Text('أضف'),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      // بعد انتهاء حركة إغلاق النافذة (الخانات ما زالت تُرسم أثناءها)
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        amount.dispose();
        note.dispose();
      });
    }
  }

  // ─────────── الحفظ: كل سطر بمساره الأصلي ───────────

  Future<void> _save() async {
    final box = _boxId;
    if (_saving || box == null || _pending.isEmpty) return;
    setState(() => _saving = true);
    final userId = AuthService().currentUser?.id;
    final date = DateTime(_day.year, _day.month, _day.day, DateTime.now().hour, DateTime.now().minute);
    var ok = 0;
    for (final o in List<_Out>.of(_pending)) {
      try {
        switch (o.kind) {
          case _Kind.expense:
            await VouchersService().create(
              type: VoucherType.expense,
              amount: o.amount,
              date: date,
              cashBoxId: box,
              accountId: o.account!.id,
              description: o.note.isEmpty ? 'إقفال اليوم' : o.note,
              userId: userId,
            );
            await _remember(o.account!);
          case _Kind.supplier:
            await ReceiptsService().supplierPayment(
              supplierId: o.supplier!.id,
              amount: o.amount,
              currency: 'IQD',
              method: 'cash',
              date: date,
              cashBoxId: box,
              notes: o.note.isEmpty ? 'إقفال اليوم' : o.note,
            );
          case _Kind.drawing:
            final db = await DatabaseService().database;
            final acc = await Ledger.systemAccountId(db, 'owner_drawings');
            await VouchersService().create(
              type: VoucherType.payment,
              amount: o.amount,
              date: date,
              cashBoxId: box,
              accountId: acc,
              description: o.note.isEmpty ? 'سحب المالك — إقفال اليوم' : 'سحب المالك — ${o.note}',
              userId: userId,
            );
        }
        ok++;
        if (mounted) setState(() => _pending.remove(o)); // نجح ⇒ يُزال فوراً (لا حفظ مكرر)
      } catch (e) {
        if (mounted) setState(() => o.error = '$e'.replaceFirst('Exception: ', ''));
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    await _loadDone();
    await _loadRecent();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_pending.isEmpty ? 'حُفظ $ok ✓' : 'حُفظ $ok، وبقي ${_pending.length} لم يُحفظ — انظر السبب تحت كل سطر'),
      backgroundColor: _pending.isEmpty ? const Color(0xFF047857) : _red,
    ));
  }

  Future<void> _count() async {
    if (_pending.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('أسطر لم تُحفظ'),
          content: Text('${_pending.length} سطر لم يُحفظ بعد، ولن يدخل في المتوقع. المتابعة إلى العدّ؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('متابعة')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DayCloseScreen(initialDate: _day)));
  }

  Future<void> _pickDay() async {
    if (_pending.isNotEmpty) return; // لا تغيير لليوم والأسطر غير محفوظة
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: now.subtract(const Duration(days: 31)),
      lastDate: now,
    );
    if (d == null || !mounted) return;
    setState(() => _day = DateTime(d.year, d.month, d.day));
    await _loadDone();
  }

  // ─────────── الواجهة ───────────

  @override
  Widget build(BuildContext context) {
    final pendingTotal = _pending.fold<double>(0, (s, o) => s + o.amount);
    final doneTotal = _done.fold<double>(0, (s, o) => s + o.amount);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6FA),
        appBar: AppBar(
          backgroundColor: _teal,
          foregroundColor: Colors.white,
          title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('إقفال اليوم في دقيقة', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('ما خرج من الدرج اليوم، ثم العدّ', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _header(),
              const SizedBox(height: 14),
              _steps(),
              const SizedBox(height: 14),
              _addCard(),
              if (_pending.isNotEmpty) ...[const SizedBox(height: 14), _pendingCard(pendingTotal)],
              const SizedBox(height: 14),
              _doneCard(doneTotal),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: _teal, minimumSize: const Size.fromHeight(52), textStyle: const TextStyle(fontSize: 16)),
                onPressed: _saving ? null : _count,
                icon: const Icon(Icons.point_of_sale_rounded),
                label: const Text('التالي: عدّ الدرج ومطابقته'),
              ),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line),
          boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: child,
      );

  Widget _header() => _card(
        child: Wrap(spacing: 14, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            onPressed: _pending.isEmpty && !_saving ? _pickDay : null,
            icon: const Icon(Icons.event_rounded),
            label: Text(DateFormat('yyyy/MM/dd', 'en').format(_day)),
          ),
          if (_boxReady)
            CashBoxDropdown(
              value: _boxId,
              width: 240,
              label: 'الدرج (الصندوق)',
              onChanged: (b) {
                if (_pending.isNotEmpty) return; // الصندوق ثابت ما دامت أسطر غير محفوظة
                setState(() {
                  _boxId = b?.id;
                  _boxName = b?.name ?? '';
                });
                _loadDone();
              },
            ),
        ]),
      );

  Widget _steps() => _card(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: const Row(children: [
          _Step(n: 1, text: 'ما خرج من الدرج', on: true),
          Expanded(child: Divider(indent: 8, endIndent: 8)),
          _Step(n: 2, text: 'احفظ', on: true),
          Expanded(child: Divider(indent: 8, endIndent: 8)),
          _Step(n: 3, text: 'عدّ الدرج', on: false),
        ]),
      );

  Widget _addCard() => _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('هل خرج من الدرج اليوم مال لم يُسجَّل؟',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: _ink)),
          const SizedBox(height: 4),
          const Text('أضف كل ما دفعته نقداً اليوم من الدرج، ثم «حفظ». بدونه يبدو الدرج ناقصاً ويظهر الربح أكبر من حقيقته.',
              style: TextStyle(color: _muted, fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            if (_canVouchers)
              _AddButton(label: 'مصروف', icon: Icons.receipt_long_rounded, color: _orange, onTap: _saving ? null : () => _addExpense()),
            if (_canSuppliers)
              _AddButton(label: 'دفعة لمورد', icon: Icons.local_shipping_rounded, color: _navy, onTap: _saving ? null : _addSupplier),
            if (_canVouchers)
              _AddButton(label: 'سحب المالك', icon: Icons.account_balance_wallet_rounded, color: _purple, onTap: _saving ? null : _addDrawing),
          ]),
          if (_canVouchers && _recent.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('مصاريف تتكرر:', style: TextStyle(fontSize: 12, color: _muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in _recent)
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 16, color: _orange),
                  label: Text(a.name),
                  onPressed: _saving ? null : () => _addExpense(a),
                ),
            ]),
          ],
        ]),
      );

  Widget _pendingCard(double total) => _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(
              child: Text('لم يُحفظ بعد', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _ink)),
            ),
            Text('${_n.format(total.round())} دينار',
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontWeight: FontWeight.w900, color: _red, fontSize: 15)),
          ]),
          const SizedBox(height: 8),
          for (final o in _pending) _pendingRow(o),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _navy, minimumSize: const Size.fromHeight(46)),
            onPressed: _saving || _boxId == null ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded),
            label: Text('حفظ ${_pending.length} ${_pending.length == 1 ? 'سطر' : 'أسطر'} في ${_boxName.isEmpty ? 'الصندوق' : _boxName}'),
          ),
        ]),
      );

  Widget _pendingRow(_Out o) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: o.error == null ? const Color(0xFFF8FAFC) : const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: o.error == null ? _line : _red.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(o.icon, color: o.color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.title, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
              if (o.note.isNotEmpty) Text(o.note, style: const TextStyle(fontSize: 12, color: _muted)),
              if (o.error != null) Text(o.error!, style: const TextStyle(fontSize: 12, color: _red)),
            ]),
          ),
          Text(_n.format(o.amount.round()),
              textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800)),
          IconButton(
            tooltip: 'حذف السطر',
            onPressed: _saving ? null : () => setState(() => _pending.remove(o)),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ]),
      );

  Widget _doneCard(double total) => _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(
              child: Text('سُجّل اليوم من هذا الدرج',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _ink)),
            ),
            Text('${_n.format(total.round())} دينار',
                textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w900, color: _teal)),
          ]),
          const SizedBox(height: 6),
          if (_done.isEmpty)
            const Text('لا شيء بعد — راجع أنك لم تنسَ مصروفاً.', style: TextStyle(color: _muted, fontSize: 12.5))
          else
            for (final d in _done)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, size: 16, color: _teal),
                  const SizedBox(width: 8),
                  Expanded(child: Text(d.label, style: const TextStyle(fontSize: 13))),
                  Text(_n.format(d.amount.round()), textDirection: TextDirection.ltr),
                ]),
              ),
        ]),
      );
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text, required this.on});
  final int n;
  final String text;
  final bool on;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: on ? _teal : const Color(0xFFE2E8F0),
          child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: on ? Colors.white : _muted)),
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? _ink : _muted)),
      ]);
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.icon, required this.color, required this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_circle_rounded, color: color, size: 20),
              const SizedBox(width: 6),
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
            ]),
          ),
        ),
      );
}
