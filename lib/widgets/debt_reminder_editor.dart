// lib/widgets/debt_reminder_editor.dart
//
// 📅 نافذة «موعد المطالبة»:
//   • اسم الموعد (اختياري)، شهر البداية، والأيام بالنقر (1 و2 و5…)، مرة أو كل شهر.
//   • الأشخاص: عميل أو أكثر، ولكل واحد مبلغ مطلوب اختياري.
//   • معاينة بجملة واضحة + تاريخ أول تذكير.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/debt_reminders.dart';
import 'formatters.dart';

const _accent = Color(0xFF4F46E5);
const _ink = Color(0xFF1E293B);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE6EBF2);
const _bg = Color(0xFFF6F8FB);
const _red = Color(0xFFB91C1C);

String _money(num v) => NumberFormat('#,##0', 'en_US').format(v);

/// [lockMembers]: لا يُضاف ولا يُحذف أشخاص (موعد فاتورة واحدة من «المزيد»)
Future<DebtReminder?> showDebtReminderEditor(BuildContext context,
        {required DebtReminder initial, bool lockMembers = false}) =>
    showDialog<DebtReminder>(
        context: context, builder: (_) => _ReminderEditor(initial: initial, lockMembers: lockMembers));

class _ReminderEditor extends StatefulWidget {
  const _ReminderEditor({required this.initial, required this.lockMembers});
  final DebtReminder initial;
  final bool lockMembers;

  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  late final DebtReminder r;
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _monthsCtrl;
  final _amountCtrls = <ReminderMember, TextEditingController>{};
  Map<int, double> _balances = const {};
  String? _err;

  static const _shortMonths = ['ك٢', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'آب', 'أيلول', 'ت١', 'ت٢', 'ك١'];
  static const _dayPresets = <(String, List<int>)>[
    ('1 إلى 5', [1, 2, 3, 4, 5]),
    ('1 و15', [1, 15]),
    ('أول 3 أيام', [1, 2, 3]),
    ('آخر الشهر', [28, 29, 30, 31]),
  ];
  static const _monthPresets = <int?>[null, 3, 6, 12];

  @override
  void initState() {
    super.initState();
    r = widget.initial.copy();
    _title = TextEditingController(text: r.title ?? '');
    _note = TextEditingController(text: r.note ?? '');
    _monthsCtrl = TextEditingController(text: '${r.months ?? ''}');
    for (final m in r.members) {
      _ctrlFor(m);
    }
    _loadBalances();
  }

  TextEditingController _ctrlFor(ReminderMember m) => _amountCtrls.putIfAbsent(
      m,
      () => TextEditingController(
          text: m.amount == null || m.amount! <= 0 ? '' : NumberFormat('#,##0.##', 'en_US').format(m.amount)));

  Future<void> _loadBalances() async {
    final b = await DebtReminders.balances(r.members.where((m) => m.customerId > 0).map((m) => m.customerId));
    if (mounted) setState(() => _balances = b);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _monthsCtrl.dispose();
    for (final c in _amountCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addPeople() async {
    final picked = await showCustomersMultiPicker(
      context,
      already: r.members.map((m) => m.customerId).toSet(),
    );
    if (picked == null || picked.isEmpty) return;
    setState(() {
      for (final c in picked) {
        final m = ReminderMember(customerId: c.id, customerName: c.name);
        r.members.add(m);
        _ctrlFor(m);
      }
      _err = null;
    });
    _loadBalances();
  }

  void _save() {
    if (r.days.isEmpty) {
      setState(() => _err = 'اختر يوماً واحداً على الأقل');
      return;
    }
    if (r.members.isEmpty) {
      setState(() => _err = 'أضف شخصاً واحداً على الأقل');
      return;
    }
    for (final m in r.members) {
      final a = double.tryParse((_amountCtrls[m]?.text ?? '').trim().replaceAll(',', ''));
      m.amount = (a == null || a <= 0) ? null : a;
    }
    r
      ..title = _title.text.trim().isEmpty ? null : _title.text.trim()
      ..note = _note.text.trim().isEmpty ? null : _note.text.trim();
    Navigator.pop(context, r);
  }

  @override
  Widget build(BuildContext context) {
    final next = r.nextDate(DateTime.now());
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (!widget.lockMembers)
                  _section(
                    'اسم الموعد (اختياري)',
                    Icons.label_outline_rounded,
                    TextField(controller: _title, decoration: _dec('مثال: مطالبة بداية الشهر — عملاء السوق')),
                  ),
                _section('يبدأ من شهر', Icons.calendar_month_rounded, _monthPicker()),
                _section('أيام التذكير — انقر على الأيام التي تريدها', Icons.touch_app_outlined, _daysPicker()),
                _section('التكرار', Icons.repeat_rounded, _repeatPicker()),
                _section(
                  widget.lockMembers ? 'الشخص' : 'الأشخاص (${r.members.length})',
                  Icons.groups_2_outlined,
                  _membersBox(),
                ),
                _section(
                  'ملاحظة (اختياري)',
                  Icons.notes_rounded,
                  TextField(controller: _note, decoration: _dec('مثال: وعدوا بالسداد بعد استلام الرواتب')),
                ),
                _preview(next),
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_err!, style: const TextStyle(color: _red, fontWeight: FontWeight.w700)),
                  ),
                const SizedBox(height: 6),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Row(children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: next == null ? null : _save,
                icon: const Icon(Icons.event_available_rounded, size: 20),
                label: const Text('حفظ الموعد', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 8, 16),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.06),
          border: const Border(bottom: BorderSide(color: _line)),
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: _accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.event_repeat_rounded, color: _accent, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('موعد المطالبة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
              SizedBox(height: 2),
              Text('يظهر لك تذكير عند تشغيل البرنامج في الأيام التي تختارها',
                  style: TextStyle(fontSize: 12.5, color: _muted, height: 1.4)),
            ]),
          ),
          IconButton(
            tooltip: 'إغلاق',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: _muted),
          ),
        ]),
      );

  Widget _section(String title, IconData icon, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, size: 17, color: _accent),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _ink))),
          ]),
          const SizedBox(height: 8),
          child,
        ]),
      );

  Widget _monthPicker() {
    Widget yearBtn(IconData i, int d, String tip) => IconButton(
          tooltip: tip,
          style: IconButton.styleFrom(backgroundColor: _bg),
          onPressed: () => setState(() => r.startYear += d),
          icon: Icon(i, size: 20),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        yearBtn(Icons.chevron_right_rounded, -1, 'السنة السابقة'),
        Expanded(
          child: Text('${r.startYear}',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _ink)),
        ),
        yearBtn(Icons.chevron_left_rounded, 1, 'السنة التالية'),
      ]),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 440 ? 6 : 4;
        final w = (c.maxWidth - (cols - 1) * 6) / cols;
        return Wrap(spacing: 6, runSpacing: 6, children: [
          for (var m = 1; m <= 12; m++)
            SizedBox(
              width: w,
              child: _Pill(
                label: '$m',
                sub: _shortMonths[m - 1],
                selected: r.startMonth == m,
                onTap: () => setState(() => r.startMonth = m),
              ),
            ),
        ]);
      }),
    ]);
  }

  /// شبكة أيام الشهر 1..31 — اختيار متعدد بالنقر
  Widget _daysPicker() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(r.days.isEmpty ? 'لم تختر أياماً بعد' : r.daysText(),
                style: TextStyle(fontWeight: FontWeight.w800, color: r.days.isEmpty ? _red : _accent, fontSize: 15)),
          ),
          if (r.days.isNotEmpty)
            TextButton(onPressed: () => setState(() => r.setDays(const [])), child: const Text('مسح')),
        ]),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (context, c) {
          const cols = 7;
          final w = (c.maxWidth - (cols - 1) * 6) / cols;
          return Wrap(spacing: 6, runSpacing: 6, children: [
            for (var d = 1; d <= 31; d++)
              SizedBox(
                width: w,
                height: 40,
                child: _DayCell(
                  day: d,
                  selected: r.days.contains(d),
                  onTap: () => setState(() {
                    final s = r.days.toSet();
                    if (!s.remove(d)) s.add(d);
                    r.setDays(s);
                    _err = null;
                  }),
                ),
              ),
          ]);
        }),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in _dayPresets)
            _Pill(
              label: p.$1,
              selected: r.days.length == p.$2.length && r.days.every(p.$2.contains),
              onTap: () => setState(() => r.setDays(p.$2)),
            ),
        ]),
        if (r.days.any((d) => d > 28))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('في الأشهر الأقصر يصير يوم 29–31 آخر يوم من الشهر',
                style: TextStyle(fontSize: 11.5, color: _muted)),
          ),
      ]);

  Widget _repeatPicker() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: _Choice(
              title: 'مرة واحدة',
              subtitle: 'في الشهر المختار فقط',
              icon: Icons.looks_one_outlined,
              selected: !r.monthly,
              onTap: () => setState(() => r.repeat = 'once'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Choice(
              title: 'كل شهر',
              subtitle: 'نفس الأيام شهرياً',
              icon: Icons.event_repeat_rounded,
              selected: r.monthly,
              onTap: () => setState(() => r.repeat = 'monthly'),
            ),
          ),
        ]),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: !r.monthly
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    for (final m in _monthPresets)
                      _Pill(
                        label: m == null ? 'بلا نهاية' : '$m أشهر',
                        selected: r.months == m,
                        onTap: () => setState(() {
                          r.months = m;
                          _monthsCtrl.text = '${m ?? ''}';
                        }),
                      ),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _monthsCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: _dec('عدد آخر').copyWith(suffixText: 'شهر'),
                        onChanged: (t) => setState(() {
                          final v = int.tryParse(t.trim());
                          r.months = (v == null || v <= 0) ? null : v;
                        }),
                      ),
                    ),
                  ]),
                ),
        ),
      ]);

  Widget _membersBox() => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (r.members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('لا أشخاص بعد — أضف العملاء الذين تريد مطالبتهم في هذه الأيام',
                  textAlign: TextAlign.center, style: TextStyle(color: _muted)),
            ),
          for (final m in r.members) _memberRow(m),
          if (!widget.lockMembers) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                backgroundColor: Colors.white,
                side: BorderSide(color: _accent.withValues(alpha: 0.4)),
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _addPeople,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
              label: const Text('إضافة أشخاص'),
            ),
          ],
        ]),
      );

  Widget _memberRow(ReminderMember m) {
    final bal = _balances[m.customerId];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
      child: Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: _accent.withValues(alpha: 0.12),
          child: Text(m.customerName.isEmpty ? '?' : m.customerName.characters.first,
              style: const TextStyle(color: _accent, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.customerName.isEmpty ? 'عميل الفاتورة' : m.customerName,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
            Text(
              [
                if (!m.active) 'موقوف في هذا الموعد',
                if (bal != null) 'رصيده ${_money(bal)}',
                if (m.invoiceId != null) 'فاتورة #${m.invoiceId}',
              ].join(' • '),
              style: const TextStyle(fontSize: 11.5, color: _muted),
            ),
          ]),
        ),
        SizedBox(
          width: 140,
          child: TextField(
            controller: _ctrlFor(m),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
            textAlign: TextAlign.center,
            decoration: _dec('المبلغ (اختياري)'),
          ),
        ),
        if (!m.active)
          IconButton(
            tooltip: 'إعادة تفعيله',
            onPressed: () => setState(() => m.active = true),
            icon: const Icon(Icons.play_circle_outline, size: 20, color: _accent),
          ),
        if (!widget.lockMembers)
          IconButton(
            tooltip: 'إزالة من الموعد',
            onPressed: () => setState(() {
              r.members.remove(m);
              _amountCtrls.remove(m)?.dispose();
            }),
            icon: const Icon(Icons.close_rounded, size: 19, color: _muted),
          ),
      ]),
    );
  }

  Widget _preview(DateTime? next) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accent.withValues(alpha: 0.25)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.notifications_active_outlined, color: _accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.describe(), style: const TextStyle(fontWeight: FontWeight.w800, color: _ink, height: 1.5)),
              const SizedBox(height: 2),
              Text(
                r.days.isEmpty
                    ? 'اختر الأيام أولاً'
                    : next == null
                        ? 'هذا الموعد انتهى — اختر شهراً قادماً'
                        : 'أول تذكير: ${DateFormat('yyyy/MM/dd').format(next)} عند تشغيل البرنامج'
                            '${r.members.length > 1 ? ' — ${r.members.length} أشخاص' : ''}',
                style: TextStyle(fontSize: 12.5, color: next == null ? _red : _muted),
              ),
            ]),
          ),
        ]),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _accent, width: 1.5)),
      );
}

// ═══════════════════════════ اختيار عدة عملاء ═══════════════════════════

typedef PickedCustomer = ({int id, String name, double debt});

/// قائمة كل العملاء مع بحث وتحديد متعدد (الأكبر ديناً أولاً). [already] لا يظهرون.
Future<List<PickedCustomer>?> showCustomersMultiPicker(BuildContext context, {Set<int> already = const {}}) =>
    showDialog<List<PickedCustomer>>(context: context, builder: (_) => _MultiPicker(already: already));

class _MultiPicker extends StatefulWidget {
  const _MultiPicker({required this.already});
  final Set<int> already;

  @override
  State<_MultiPicker> createState() => _MultiPickerState();
}

class _MultiPickerState extends State<_MultiPicker> {
  List<PickedCustomer> _all = const [];
  final _sel = <int, PickedCustomer>{};
  String _q = '';
  bool _onlyDebt = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    DebtReminders.customers().then((l) {
      if (mounted) {
        setState(() {
          _all = l.where((c) => !widget.already.contains(c.id)).toList();
          _loading = false;
        });
      }
    });
  }

  List<PickedCustomer> get _shown {
    final q = _q.trim();
    return _all
        .where((c) => (!_onlyDebt || c.debt > 0.5) && (q.isEmpty || c.name.contains(q)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 660),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 8, 8),
            child: Row(children: [
              const Icon(Icons.person_add_alt_1_rounded, color: _accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('اختر الأشخاص', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: _muted)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                filled: true,
                fillColor: _bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
                enabledBorder:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
              ),
              onChanged: (t) => setState(() => _q = t),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(children: [
              FilterChip(
                label: const Text('من عليهم دين فقط'),
                selected: _onlyDebt,
                onSelected: (v) => setState(() => _onlyDebt = v),
              ),
              const Spacer(),
              TextButton(
                onPressed: shown.isEmpty
                    ? null
                    : () => setState(() {
                          final allOn = shown.every((c) => _sel.containsKey(c.id));
                          for (final c in shown) {
                            if (allOn) {
                              _sel.remove(c.id);
                            } else {
                              _sel[c.id] = c;
                            }
                          }
                        }),
                child: Text(shown.isNotEmpty && shown.every((c) => _sel.containsKey(c.id)) ? 'إلغاء الظاهر' : 'تحديد الظاهر'),
              ),
            ]),
          ),
          const Divider(height: 8),
          Flexible(
            child: _loading
                ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
                : shown.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(30),
                        child: Text('لا نتائج', textAlign: TextAlign.center, style: TextStyle(color: _muted)))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final c = shown[i];
                          final on = _sel.containsKey(c.id);
                          return CheckboxListTile(
                            value: on,
                            dense: true,
                            activeColor: _accent,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('الرصيد ${_money(c.debt)}'),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _sel[c.id] = c;
                              } else {
                                _sel.remove(c.id);
                              }
                            }),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _accent, minimumSize: const Size(0, 46)),
                onPressed: _sel.isEmpty ? null : () => Navigator.pop(context, _sel.values.toList()),
                icon: const Icon(Icons.check_rounded),
                label: Text('إضافة ${_sel.length}'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.selected, required this.onTap});
  final int day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: 'يوم $day',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: selected ? _accent : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? _accent : _line),
            boxShadow: selected
                ? [BoxShadow(color: _accent.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))]
                : const [],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: Center(
                child: Text('$day',
                    style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : _ink, fontSize: 14)),
              ),
            ),
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap, this.sub});
  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _accent : _line),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : _ink)),
                if (sub != null)
                  Text(sub!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: selected ? Colors.white70 : _muted)),
              ]),
            ),
          ),
        ),
      );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.07) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? _accent : _line, width: selected ? 1.6 : 1),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(icon, color: selected ? _accent : _muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? _accent : _ink)),
                    Text(subtitle, style: const TextStyle(fontSize: 11.5, color: _muted)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
}
