// lib/widgets/range_picker_dialog.dart
//
// 📅 نافذة اختيار الفترة (من – إلى) للتقارير — بدل نافذة النظام الافتراضية:
//   • رأس متدرّج يعرض «من» و«إلى» وعدد الأيام لحظة الاختيار.
//   • تقويم شهري: الضغطة الأولى بداية والثانية نهاية، مع شريط يصل بينهما
//     ومعاينة عند مرور الفأرة، والأسبوع يبدأ بالسبت.
//   • اختيارات سريعة (اليوم، هذا الشهر، هذه السنة…) بجانب التقويم.
//   • «كتابة التاريخ»: حقلان يقبلان 15/11/2026 (والأرقام العربية)، مع التاريخ
//     مكتوباً بالكلمات تحت كل حقل أو سبب الخطأ.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'settings_kit.dart' show kSetNavy, kSetText, kSetMuted, kSetBorder, kSetBg, kSetRed, kSetGreen;

const _ink = kSetText;
const _muted = kSetMuted;
const _accent = kSetNavy;
const _teal = Color(0xFF0E7490);

const _monthNames = [
  'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
  'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
];
const _weekdayNames = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
const _weekHeader = ['سبت', 'أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة'];

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);
String _num(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String _words(DateTime d) => '${_weekdayNames[d.weekday - 1]} ${d.day} ${_monthNames[d.month - 1]} ${d.year}';

/// يفتح نافذة الفترة. [presets] = (الاسم، من، إلى) للاختيارات السريعة.
Future<DateTimeRange?> showReportRangePicker(
  BuildContext context, {
  required DateTimeRange initial,
  required DateTime first,
  required DateTime last,
  List<(String, DateTime, DateTime)> presets = const [],
  String confirmText = 'عرض التقرير',
}) {
  return showDialog<DateTimeRange>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: _RangePicker(
          initial: initial,
          first: _d(first),
          last: _d(last),
          presets: presets,
          confirmText: confirmText,
        ),
      ),
    ),
  );
}

class _RangePicker extends StatefulWidget {
  const _RangePicker({
    required this.initial,
    required this.first,
    required this.last,
    required this.presets,
    required this.confirmText,
  });
  final DateTimeRange initial;
  final DateTime first, last;
  final List<(String, DateTime, DateTime)> presets;
  final String confirmText;

  @override
  State<_RangePicker> createState() => _RangePickerState();
}

class _RangePickerState extends State<_RangePicker> {
  DateTime? _start, _end, _hover;
  late DateTime _month; // أول يوم في الشهر المعروض
  bool _typing = false;
  int _slide = 0; // اتجاه حركة الشهر
  final _fromCtl = TextEditingController();
  final _toCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _start = _d(widget.initial.start);
    _end = _d(widget.initial.end);
    _month = DateTime(_end!.year, _end!.month, 1);
    _syncFields();
  }

  @override
  void dispose() {
    _fromCtl.dispose();
    _toCtl.dispose();
    super.dispose();
  }

  void _syncFields() {
    _fromCtl.text = _start == null ? '' : _num(_start!);
    _toCtl.text = _end == null ? '' : _num(_end!);
  }

  bool _enabled(DateTime d) => !d.isBefore(widget.first) && !d.isAfter(widget.last);

  void _tapDay(DateTime d) {
    setState(() {
      if (_start == null || _end != null) {
        _start = d;
        _end = null;
      } else if (d.isBefore(_start!)) {
        _start = d;
      } else {
        _end = d;
      }
      _syncFields();
    });
  }

  void _applyPreset((String, DateTime, DateTime) p) {
    setState(() {
      _start = _d(p.$2);
      _end = _d(p.$3);
      final m = DateTime(_end!.year, _end!.month, 1);
      _slide = m.isAfter(_month) ? 1 : -1;
      _month = m;
      _syncFields();
    });
  }

  void _moveMonth(int by) {
    final m = DateTime(_month.year, _month.month + by, 1);
    if (by > 0 && m.isAfter(DateTime(widget.last.year, widget.last.month, 1))) return;
    if (by < 0 && DateTime(m.year, m.month + 1, 0).isBefore(widget.first)) return;
    setState(() {
      _slide = by;
      _month = m;
    });
  }

  // ───────── كتابة التاريخ ─────────

  /// 15/11/2026 أو 15-11-2026 أو 2026-11-15، والأرقام العربية.
  static DateTime? _parse(String raw) {
    var t = raw.trim();
    const ar = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) {
      t = t.replaceAll(ar[i], '$i');
    }
    final parts = t.split(RegExp(r'[/\-.\s]+')).where((x) => x.isNotEmpty).toList();
    if (parts.length != 3) return null;
    final n = parts.map(int.tryParse).toList();
    if (n.any((x) => x == null)) return null;
    int y, m, day;
    if (parts.first.length == 4) {
      (y, m, day) = (n[0]!, n[1]!, n[2]!);
    } else {
      (day, m, y) = (n[0]!, n[1]!, n[2]!);
      if (parts.last.length == 2) y += 2000;
    }
    if (m < 1 || m > 12 || day < 1 || day > DateTime(y, m + 1, 0).day) return null;
    return DateTime(y, m, day);
  }

  String? _fieldError(String raw, {DateTime? notBefore}) {
    if (raw.trim().isEmpty) return 'اكتب التاريخ';
    final d = _parse(raw);
    if (d == null) return 'تاريخ غير صحيح — مثال: 15/11/2026';
    if (d.isAfter(widget.last)) return 'بعد آخر تاريخ مسموح (${_num(widget.last)})';
    if (d.isBefore(widget.first)) return 'قبل أول تاريخ مسموح (${_num(widget.first)})';
    if (notBefore != null && d.isBefore(notBefore)) return '«إلى» قبل «من»';
    return null;
  }

  void _onTyped() {
    final a = _parse(_fromCtl.text), b = _parse(_toCtl.text);
    setState(() {
      if (a != null && _enabled(a)) _start = a;
      if (b != null && _enabled(b) && (a == null || !b.isBefore(a))) _end = b;
      if (_end != null && _start != null && _end!.isBefore(_start!)) _end = null;
    });
  }

  void _setTyping(bool v) {
    if (v == _typing) return;
    setState(() {
      if (!v && _start != null) _month = DateTime((_end ?? _start!).year, (_end ?? _start!).month, 1);
      if (v) _syncFields();
      _typing = v;
    });
  }

  // ───────── التأكيد ─────────

  DateTimeRange? get _result {
    if (_typing) {
      final a = _parse(_fromCtl.text), b = _parse(_toCtl.text);
      if (_fieldError(_fromCtl.text) != null || _fieldError(_toCtl.text, notBefore: a) != null) return null;
      return DateTimeRange(start: a!, end: b!);
    }
    if (_start == null) return null;
    return DateTimeRange(start: _start!, end: _end ?? _start!);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(color: _accent.withValues(alpha: 0.25), blurRadius: 40, offset: const Offset(0, 18)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SizeTransition(sizeFactor: a, axisAlignment: -1, child: c),
              ),
              child: _typing ? _inputPane() : _calendarPane(),
            ),
          ),
        ),
        _footer(),
      ]),
    );
  }

  // ───────── الرأس ─────────

  Widget _header() {
    final days = (_start != null) ? ((_end ?? _start!).difference(_start!).inDays + 1) : 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B2545), _accent, _teal],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: const Icon(Icons.date_range_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('اختر الفترة',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          ),
          _ModeSwitch(typing: _typing, onChanged: _setTyping),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _datePill('من', _start)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_back_rounded, color: Colors.white.withValues(alpha: 0.7)),
          ),
          Expanded(child: _datePill('إلى', _end)),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Container(
              key: ValueKey(days),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                days == 0 ? '—' : (days == 1 ? 'يوم واحد' : (days == 2 ? 'يومان' : '$days ${days <= 10 ? 'أيام' : 'يوماً'}')),
                style: const TextStyle(color: _accent, fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _datePill(String label, DateTime? d) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: d == null ? 0.06 : 0.13),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: d == null ? 0.15 : 0.28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            d == null ? (label == 'إلى' ? 'اختر يوم النهاية' : 'اختر يوم البداية') : _words(d),
            style: TextStyle(
              color: Colors.white.withValues(alpha: d == null ? 0.6 : 1),
              fontWeight: FontWeight.w800,
              fontSize: 14.5,
            ),
          ),
        ),
      ]),
    );
  }

  // ───────── التقويم ─────────

  Widget _calendarPane() {
    return LayoutBuilder(
      key: const ValueKey('cal'),
      builder: (context, c) {
        final wide = c.maxWidth >= 600 && widget.presets.isNotEmpty;
        final cal = _calendar();
        if (widget.presets.isEmpty) return cal;
        if (!wide) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.presets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _presetChip(widget.presets[i]),
              ),
            ),
            const SizedBox(height: 12),
            cal,
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 172,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8, right: 4, left: 4),
                child: Text('اختيار سريع', style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              for (final p in widget.presets)
                Padding(padding: const EdgeInsets.only(bottom: 6), child: _presetTile(p)),
            ]),
          ),
          Container(width: 1, height: 360, margin: const EdgeInsets.symmetric(horizontal: 16), color: kSetBorder),
          Expanded(child: cal),
        ]);
      },
    );
  }

  bool _isPreset((String, DateTime, DateTime) p) =>
      _start != null && _end != null && _d(p.$2) == _start && _d(p.$3) == _end;

  Widget _presetTile((String, DateTime, DateTime) p) {
    final on = _isPreset(p);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _applyPreset(p),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: on ? _accent : kSetBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Expanded(
              child: Text(p.$1,
                  style: TextStyle(
                    color: on ? Colors.white : _ink,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13.5,
                  )),
            ),
            if (on) const Icon(Icons.check_rounded, color: Colors.white, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _presetChip((String, DateTime, DateTime) p) {
    final on = _isPreset(p);
    return ChoiceChip(
      label: Text(p.$1),
      selected: on,
      onSelected: (_) => _applyPreset(p),
      showCheckmark: false,
      labelStyle: TextStyle(color: on ? Colors.white : _ink, fontWeight: FontWeight.w700),
      selectedColor: _accent,
      backgroundColor: kSetBg,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _calendar() {
    final canNext = !DateTime(_month.year, _month.month + 1, 1).isAfter(widget.last);
    final canPrev = !DateTime(_month.year, _month.month, 0).isBefore(widget.first);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        _navBtn(Icons.keyboard_double_arrow_right_rounded, 'السنة السابقة', canPrev ? () => _moveMonth(-12) : null),
        _navBtn(Icons.chevron_right_rounded, 'الشهر السابق', canPrev ? () => _moveMonth(-1) : null),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Column(key: ValueKey(_month), children: [
              Text('${_monthNames[_month.month - 1]} ${_month.year}',
                  style: const TextStyle(color: _ink, fontSize: 16.5, fontWeight: FontWeight.w900)),
              Text('شهر ${_month.month}', style: const TextStyle(color: _muted, fontSize: 11.5)),
            ]),
          ),
        ),
        _navBtn(Icons.chevron_left_rounded, 'الشهر التالي', canNext ? () => _moveMonth(1) : null),
        _navBtn(Icons.keyboard_double_arrow_left_rounded, 'السنة التالية', canNext ? () => _moveMonth(12) : null),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        for (final w in _weekHeader)
          Expanded(
            child: Center(
              child: Text(w,
                  style: TextStyle(
                    color: w == 'جمعة' ? kSetRed.withValues(alpha: 0.7) : _muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  )),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (c, a) {
          final from = Offset(_slide >= 0 ? -0.08 : 0.08, 0);
          return FadeTransition(
            opacity: a,
            child: SlideTransition(position: Tween(begin: from, end: Offset.zero).animate(a), child: c),
          );
        },
        child: KeyedSubtree(key: ValueKey(_month), child: _grid()),
      ),
      const SizedBox(height: 4),
    ]);
  }

  Widget _navBtn(IconData i, String tip, VoidCallback? onTap) => IconButton(
        tooltip: tip,
        onPressed: onTap,
        icon: Icon(i),
        color: _accent,
        disabledColor: kSetBorder,
        style: IconButton.styleFrom(
          backgroundColor: onTap == null ? Colors.transparent : kSetBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  Widget _grid() {
    final firstDay = _month;
    final lead = (firstDay.weekday - DateTime.saturday + 7) % 7; // السبت أول الأسبوع
    final daysIn = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = lead + daysIn;
    final rows = (cells / 7).ceil();
    // نهاية المعاينة: يوم المرور حين اختيرت البداية فقط
    final DateTime? endView = _end ?? ((_start != null && _hover != null && !_hover!.isBefore(_start!)) ? _hover : null);
    return Column(children: [
      for (var r = 0; r < rows; r++)
        Row(children: [
          for (var c = 0; c < 7; c++)
            Expanded(
              child: () {
                final n = r * 7 + c - lead + 1;
                if (n < 1 || n > daysIn) return const SizedBox(height: 44);
                return _dayCell(DateTime(_month.year, _month.month, n), endView);
              }(),
            ),
        ]),
    ]);
  }

  Widget _dayCell(DateTime d, DateTime? endView) {
    final enabled = _enabled(d);
    final isStart = _start != null && d == _start;
    final isEnd = endView != null && d == endView;
    final inRange = _start != null && endView != null && d.isAfter(_start!) && d.isBefore(endView);
    final preview = _end == null && endView != null;
    final hasBand = _start != null && endView != null && endView != _start && (inRange || isStart || isEnd);
    final today = d == _d(DateTime.now());
    final selected = isStart || (isEnd && _end != null);
    final bandColor = _accent.withValues(alpha: preview ? 0.06 : 0.10);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (_start != null && _end == null) setState(() => _hover = d);
      },
      child: Semantics(
        button: enabled,
        selected: selected,
        label: _words(d),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => _tapDay(d) : null,
          child: SizedBox(
            height: 44,
            child: Stack(alignment: Alignment.center, children: [
              if (hasBand)
                Align(
                  alignment: isStart
                      ? AlignmentDirectional.centerEnd
                      : (isEnd ? AlignmentDirectional.centerStart : Alignment.center),
                  child: FractionallySizedBox(
                    widthFactor: (isStart || isEnd) ? 0.5 : 1,
                    child: Container(height: 36, color: bandColor),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: selected ? const LinearGradient(colors: [_accent, _teal]) : null,
                  color: selected
                      ? null
                      : (isEnd && preview ? _accent.withValues(alpha: 0.18) : Colors.transparent),
                  border: today && !selected ? Border.all(color: _teal, width: 1.6) : null,
                  boxShadow: selected
                      ? [BoxShadow(color: _accent.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${d.day}',
                  style: TextStyle(
                    color: selected ? Colors.white : (enabled ? _ink : _muted.withValues(alpha: 0.35)),
                    fontWeight: selected || today ? FontWeight.w900 : FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ───────── الكتابة ─────────

  Widget _inputPane() {
    final fromErr = _fieldError(_fromCtl.text);
    final toErr = _fieldError(_toCtl.text, notBefore: _parse(_fromCtl.text));
    final from = _DateField(
      label: 'من',
      icon: Icons.first_page_rounded,
      controller: _fromCtl,
      error: _fromCtl.text.isEmpty ? null : fromErr,
      parsed: fromErr == null ? _parse(_fromCtl.text) : null,
      onChanged: (_) => _onTyped(),
      autofocus: true,
    );
    final to = _DateField(
      label: 'إلى',
      icon: Icons.last_page_rounded,
      controller: _toCtl,
      error: _toCtl.text.isEmpty ? null : toErr,
      parsed: toErr == null ? _parse(_toCtl.text) : null,
      onChanged: (_) => _onTyped(),
    );
    return LayoutBuilder(
      key: const ValueKey('type'),
      builder: (context, c) {
        final wide = c.maxWidth >= 560;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kSetBg, borderRadius: BorderRadius.circular(14)),
            child: const Row(children: [
              Icon(Icons.lightbulb_outline_rounded, color: _teal, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('اكتب يوم / شهر / سنة، مثل 15/11/2026 — تُقبل الأرقام العربية والشرطة والنقطة.',
                    style: TextStyle(color: _muted, fontSize: 12.5, height: 1.4)),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: from),
              const SizedBox(width: 14),
              Expanded(child: to),
            ])
          else ...[
            from,
            const SizedBox(height: 12),
            to,
          ],
          const SizedBox(height: 8),
        ]);
      },
    );
  }

  // ───────── الأسفل ─────────

  Widget _footer() {
    final r = _result;
    final hint = _typing
        ? (r == null ? 'أكمل التاريخين' : 'جاهز')
        : (_start == null ? 'اضغط يوم البداية' : (_end == null ? 'اضغط يوم النهاية — أو اعرض يوماً واحداً' : 'جاهز'));
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: kSetBorder))),
      child: Row(children: [
        Icon(r == null ? Icons.touch_app_rounded : Icons.check_circle_rounded,
            size: 18, color: r == null ? _muted : kSetGreen),
        const SizedBox(width: 6),
        Expanded(
          child: Text(hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: r == null ? _muted : kSetGreen, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: _muted,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('إلغاء', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          onPressed: r == null ? null : () => Navigator.pop(context, r),
          icon: const Icon(Icons.insights_rounded, size: 18),
          label: Text(widget.confirmText, style: const TextStyle(fontWeight: FontWeight.w800)),
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ]),
    );
  }
}

/// زر التبديل بين التقويم والكتابة (شفاف فوق الرأس المتدرّج).
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.typing, required this.onChanged});
  final bool typing;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(bool v, IconData i, String t) {
      final on = typing == v;
      return Semantics(
        button: true,
        selected: on,
        label: t,
        child: GestureDetector(
          onTap: () => onChanged(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(i, size: 17, color: on ? _accent : Colors.white),
              const SizedBox(width: 6),
              Text(t,
                  style: TextStyle(
                      color: on ? _accent : Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ]),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(false, Icons.calendar_month_rounded, 'التقويم'),
        seg(true, Icons.keyboard_rounded, 'كتابة'),
      ]),
    );
  }
}

/// حقل تاريخ مكتوب: بطاقة بعنوان، والتاريخ بالكلمات أو سبب الخطأ تحته.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.icon,
    required this.controller,
    required this.onChanged,
    this.error,
    this.parsed,
    this.autofocus = false,
  });
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? error;
  final DateTime? parsed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final ok = parsed != null;
    final c = error != null ? kSetRed : (ok ? kSetGreen : _accent);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: error != null || ok ? 0.55 : 0.18), width: 1.4),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: c, size: 18),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: _ink, fontWeight: FontWeight.w900, fontSize: 15)),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          autofocus: autofocus,
          onChanged: onChanged,
          keyboardType: TextInputType.datetime,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩/\-. ]')),
            LengthLimitingTextInputFormatter(10),
          ],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: _ink),
          decoration: InputDecoration(
            hintText: 'يوم / شهر / سنة',
            hintStyle: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 15, letterSpacing: 0),
            filled: true,
            fillColor: kSetBg,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: c.withValues(alpha: 0.6), width: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Row(
            key: ValueKey('${error ?? ''}${parsed ?? ''}'),
            children: [
              Icon(
                error != null ? Icons.error_outline_rounded : (ok ? Icons.event_available_rounded : Icons.edit_calendar_rounded),
                size: 16,
                color: error != null ? kSetRed : (ok ? kSetGreen : _muted),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  error ?? (ok ? _words(parsed!) : 'مثال: 15/11/2026'),
                  style: TextStyle(
                    color: error != null ? kSetRed : (ok ? kSetGreen : _muted),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
