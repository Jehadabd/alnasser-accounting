// lib/widgets/scan_settings_tile.dart
//
// ⚙️ الإعدادات ← الواجهة: «قراءة الباركود» — القارئ والكاميرا وتجربة سرعة القارئ.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/barcode/scan_burst.dart';
import '../services/barcode/scan_settings.dart';
import 'camera_scan_button.dart';

class ScanSettingsTile extends StatefulWidget {
  const ScanSettingsTile({super.key});

  @override
  State<ScanSettingsTile> createState() => _ScanSettingsTileState();
}

class _ScanSettingsTileState extends State<ScanSettingsTile> {
  ScanSettings _s = ScanSettings.current;
  bool _advanced = false;

  // تجربة القارئ: أزمنة الحروف ما دام المؤشر في خانة التجربة
  final _testCtl = TextEditingController();
  final _testFocus = FocusNode();
  final _clock = Stopwatch()..start();
  final List<Duration> _times = [];
  String? _testResult;
  int? _measuredGap;

  @override
  void initState() {
    super.initState();
    ScanSettings.load().then((s) {
      if (mounted) setState(() => _s = s);
    });
    HardwareKeyboard.instance.addHandler(_onTestKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onTestKey);
    _testCtl.dispose();
    _testFocus.dispose();
    super.dispose();
  }

  bool _onTestKey(KeyEvent e) {
    if (!_testFocus.hasFocus || e is! KeyDownEvent) return false;
    if (isScanModifier(e.physicalKey)) return false;
    if (isScanTerminator(e.physicalKey)) {
      _finishTest();
      return true;
    }
    if (usKeyChar(e.physicalKey, shift: false) != null) _times.add(_clock.elapsed);
    return false;
  }

  void _finishTest() {
    final t = List<Duration>.from(_times);
    final text = _testCtl.text.trim();
    _times.clear();
    if (t.length < 2) {
      setState(() => _testResult = 'امسح باركوداً في الخانة (لا تكتب بيدك).');
      return;
    }
    var maxGap = Duration.zero;
    for (var i = 1; i < t.length; i++) {
      final g = t[i] - t[i - 1];
      if (g > maxGap) maxGap = g;
    }
    final ms = maxGap.inMilliseconds;
    final ok = ms <= _s.maxGapMs && text.length >= _s.minLength;
    setState(() {
      _measuredGap = ms;
      _testResult = ok
          ? '✓ قُرئ «$text» — أبطأ فاصل بين حرفين $ms ملّي ثانية. القارئ سيعمل في كل الشاشة.'
          : (text.length < _s.minLength
              ? 'قُرئ «$text» وهو أقصر من ${_s.minLength} حروف — قلّل «أقل طول للرمز».'
              : 'أبطأ فاصل $ms ملّي ثانية أكبر من الإعداد ${_s.maxGapMs} — اضغط «اعتماد سرعة قارئي».');
    });
    _testCtl.clear();
  }

  Future<void> _save(ScanSettings s) async {
    setState(() => _s = s);
    await ScanSettings.save(s);
  }

  static const _bold = TextStyle(fontWeight: FontWeight.bold, fontSize: 14);
  static const _small = TextStyle(fontSize: 12, height: 1.45);

  @override
  Widget build(BuildContext context) {
    final camera = CameraScanButton.available;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('قارئ الباركود يضيف المادة من أي مكان في الشاشة', style: _bold),
        subtitle: const Text(
            'في الكاشير وإنشاء الفاتورة وتعديلها: امسح المادة وهي تُضاف — حتى لو كانت خانة الباركود '
            'مخفية أو المؤشر في خانة أخرى. الخانة التي كان فيها المؤشر لا يتغير ما فيها.',
            style: _small),
        value: _s.keyboardScanner,
        onChanged: (v) => _save(_s.copyWith(keyboardScanner: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('مسح المادة مرة ثانية يزيد كميتها', style: _bold),
        subtitle: const Text('إن كانت المادة في الفاتورة بالوحدة نفسها تصبح كميتها +1 بدل سطر جديد.', style: _small),
        value: _s.repeatAddsQty,
        onChanged: (v) => _save(_s.copyWith(repeatAddsQty: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('صوت واهتزاز عند المسح', style: _bold),
        subtitle: const Text('صوت تنبيه عند رمز غير معروف حتى تعرف دون النظر للشاشة.', style: _small),
        value: _s.sound,
        onChanged: (v) => _save(_s.copyWith(sound: v)),
      ),
      const Divider(height: 22),
      Text('المسح بالكاميرا${camera ? '' : ' (للأندرويد والآيفون)'}', style: _bold),
      const SizedBox(height: 4),
      RadioGroup<CameraScanMode>(
        groupValue: _s.cameraMode,
        onChanged: (v) {
          if (v != null) _save(_s.copyWith(cameraMode: v));
        },
        child: Column(children: [
          for (final m in CameraScanMode.values)
            RadioListTile<CameraScanMode>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: m,
              title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(m.help, style: _small),
            ),
        ]),
      ),
      const Divider(height: 22),
      const Text('تجربة القارئ', style: _bold),
      const SizedBox(height: 6),
      TextField(
        controller: _testCtl,
        focusNode: _testFocus,
        textDirection: TextDirection.ltr,
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.qr_code_scanner_rounded),
          hintText: 'ضع المؤشر هنا وامسح أي باركود',
          border: OutlineInputBorder(),
        ),
      ),
      if (_testResult != null) ...[
        const SizedBox(height: 6),
        Text(_testResult!, style: const TextStyle(fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w600)),
      ],
      if (_measuredGap != null && _measuredGap! > _s.maxGapMs && _measuredGap! + 15 <= ScanSettings.maxGapMsLimit)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.speed_rounded),
            label: Text('اعتماد سرعة قارئي (${_measuredGap! + 15} ملّي ثانية)'),
            onPressed: () => _save(_s.copyWith(maxGapMs: _measuredGap! + 15)),
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(
          onPressed: () => setState(() => _advanced = !_advanced),
          child: Text(_advanced ? 'إخفاء الإعدادات المتقدمة' : 'إعدادات متقدمة'),
        ),
      ),
      if (_advanced) ...[
        Text('أقصى زمن بين حرفين من القارئ: ${_s.maxGapMs} ملّي ثانية', style: _small),
        Slider(
          min: ScanSettings.minGapMs.toDouble(),
          max: ScanSettings.maxGapMsLimit.toDouble(),
          divisions: (ScanSettings.maxGapMsLimit - ScanSettings.minGapMs) ~/ 5,
          value: _s.maxGapMs.toDouble(),
          label: '${_s.maxGapMs}',
          onChanged: (v) => setState(() => _s = _s.copyWith(maxGapMs: v.round())),
          onChangeEnd: (v) => _save(_s.copyWith(maxGapMs: v.round())),
        ),
        const Text('أكبر = يقبل قارئات أبطأ (بلوتوث)، لكن الكتابة السريعة جداً باليد قد تُحسب مسحاً.',
            style: TextStyle(fontSize: 11.5, color: Colors.black54)),
        const SizedBox(height: 8),
        Text('أقل طول للرمز: ${_s.minLength} حروف', style: _small),
        Slider(
          min: 2,
          max: 12,
          divisions: 10,
          value: _s.minLength.toDouble().clamp(2.0, 12.0),
          label: '${_s.minLength}',
          onChanged: (v) => setState(() => _s = _s.copyWith(minLength: v.round())),
          onChangeEnd: (v) => _save(_s.copyWith(minLength: v.round())),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => _save(_s.copyWith(maxGapMs: ScanSettings.defaultGapMs, minLength: ScanSettings.defaultMinLength)),
            child: const Text('إرجاع الافتراضي'),
          ),
        ),
      ],
    ]);
  }
}
