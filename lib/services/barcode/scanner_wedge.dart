// lib/services/barcode/scanner_wedge.dart
//
// 🔫 التقاط قارئ الباركود (USB/بلوتوث، أو المدمج في أجهزة الكاشير) على مستوى الشاشة كلها:
// المادة تُضاف أينما كان المؤشر — حتى إن كانت خانة الباركود مخفية أو غير محددة.
//
//   • التمييز بين القارئ والإنسان في [ScanBurstDetector] (منطق نقي مختبر).
//   • معالج واحد للبرنامج كله: الرمز يذهب لشاشة واحدة فقط — الشاشة الظاهرة التي فيها
//     المؤشر. إن كانت شاشتا بيع ظاهرتين (نافذتان منبثقتان) ولا مؤشر في أي منهما
//     لا يُضاف الرمز لأي منهما (صوت تنبيه) — حتى لا تذهب المادة لفاتورة غير مقصودة.
//   • الخانة التي كان فيها المؤشر تعود كما كانت تماماً (ونُبلغ صاحبها بالتغيير عبر
//     userUpdateTextEditingValue حتى لا تبقى كمية أو سعر بحرف القارئ).
//   • الخانة التي تقرأ الباركود بنفسها (خانة الباركود/الرمز في الجدول) تستعمل
//     [ScanPassThroughFocusNode] فيبقى سلوكها كما هو: المسح فيها يغيّر مادة سطرها.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'scan_burst.dart';
import 'scan_feedback.dart';
import 'scan_settings.dart';

/// FocusNode لخانة تقرأ الباركود بنفسها — الماسح العام لا يتدخل حين يكون المؤشر فيها.
class ScanPassThroughFocusNode extends FocusNode {
  ScanPassThroughFocusNode({super.debugLabel});
}

/// شاشة تستقبل الرموز المقروءة. [isActive]: الشاشة ظاهرة وفي الأعلى.
class ScannerWedge {
  ScannerWedge({required this.context, required this.isActive, required this.onScan});

  final BuildContext Function() context;
  final bool Function() isActive;
  final void Function(String code) onScan;

  bool _attached = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    _hub.add(this);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _hub.remove(this);
  }

  bool _activeSafe() {
    try {
      return _attached && isActive();
    } catch (_) {
      return false;
    }
  }

  bool _contains(BuildContext focused) {
    final BuildContext mine;
    try {
      mine = context();
    } catch (_) {
      return false;
    }
    if (identical(focused, mine)) return true;
    var found = false;
    focused.visitAncestorElements((e) {
      found = identical(e, mine);
      return !found;
    });
    return found;
  }

  static final _WedgeHub _hub = _WedgeHub();
}

class _WedgeHub {
  final List<ScannerWedge> _all = [];
  final Stopwatch _clock = Stopwatch()..start();
  final ScanBurstDetector _d = ScanBurstDetector(
    maxGap: const Duration(milliseconds: ScanSettings.defaultGapMs),
    minLength: ScanSettings.defaultMinLength,
  );
  final Set<PhysicalKeyboardKey> _swallowed = {};
  EditableTextState? _snapField;
  TextEditingValue? _snapValue;
  String? _snapFirst;
  Timer? _idle;

  void add(ScannerWedge w) {
    if (_all.isEmpty) HardwareKeyboard.instance.addHandler(_onKey);
    _all.add(w);
  }

  void remove(ScannerWedge w) {
    _all.remove(w);
    if (_all.isNotEmpty) return;
    HardwareKeyboard.instance.removeHandler(_onKey);
    _idle?.cancel();
    _d.reset();
    _swallowed.clear();
    _clearSnap();
  }

  bool get _anyActive => _all.any((w) => w._activeSafe());

  /// الشاشة التي تأخذ الرمز: الظاهرة الوحيدة، أو الظاهرة التي فيها المؤشر.
  ScannerWedge? _target() {
    final active = [for (final w in _all) if (w._activeSafe()) w];
    if (active.length <= 1) return active.isEmpty ? null : active.first;
    final f = FocusManager.instance.primaryFocus?.context;
    if (f == null) return null;
    for (final w in active.reversed) {
      if (w._contains(f)) return w;
    }
    return null;
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyUpEvent) return _swallowed.remove(e.physicalKey);
    final s = ScanSettings.current;
    if (!s.keyboardScanner || FocusManager.instance.primaryFocus is ScanPassThroughFocusNode || !_anyActive) {
      _apply(_d.other());
      return false;
    }
    _d
      ..maxGap = Duration(milliseconds: s.maxGapMs)
      ..minLength = s.minLength;
    if (isScanModifier(e.physicalKey)) return false;
    final hk = HardwareKeyboard.instance;
    if (e is KeyRepeatEvent || hk.isControlPressed || hk.isAltPressed || hk.isMetaPressed) {
      _apply(_d.other());
      return false;
    }
    final t = _clock.elapsed;
    if (isScanTerminator(e.physicalKey)) return _apply(_d.terminator(t), key: e.physicalKey);
    final mapped = usKeyChar(e.physicalKey, shift: hk.isShiftPressed);
    if (mapped == null) {
      _apply(_d.other());
      return false;
    }
    final ch = e.character;
    final typed = (ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 0x20) ? ch : mapped;
    return _apply(_d.char(mapped, typed, t), key: e.physicalKey);
  }

  bool _apply(BurstStep st, {PhysicalKeyboardKey? key}) {
    try {
      if (st.flush.isNotEmpty) _typeIntoFocused(st.flush);
      if (st.snapshot) _takeSnapshot();
      final code = st.code;
      if (code != null) {
        final target = _target(); // قبل الإرجاع: المؤشر ما زال حيث كان
        _restoreSnapshot();
        if (target == null) {
          ScanFeedback.fail();
          debugPrint('🔫 رمز «$code» بلا شاشة واحدة محددة — لم يُضف');
        } else {
          try {
            target.onScan(code);
          } catch (e) {
            debugPrint('⚠️ ScannerWedge.onScan: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ ScannerWedge: $e');
    }
    _idle?.cancel();
    if (_d.active) {
      _idle = Timer(_d.idleAfter + const Duration(milliseconds: 5), () {
        if (_all.isNotEmpty) _apply(_d.idle(_clock.elapsed));
      });
    }
    if (st.swallow && key != null) _swallowed.add(key);
    return st.swallow;
  }

  static EditableTextState? _focusedField() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    if (ctx is StatefulElement && ctx.state is EditableTextState) return ctx.state as EditableTextState;
    return ctx.findAncestorStateOfType<EditableTextState>();
  }

  void _clearSnap() {
    _snapField = null;
    _snapValue = null;
    _snapFirst = null;
  }

  void _takeSnapshot() {
    final f = _focusedField();
    _snapField = f;
    _snapValue = f?.textEditingValue;
    _snapFirst = _d.firstTyped;
  }

  /// قيمة الخانة بعد كتابة [s] مكان التحديد في [v].
  static TextEditingValue _inserted(TextEditingValue v, String s) {
    final sel = v.selection;
    final len = v.text.length;
    final a = sel.isValid ? sel.start.clamp(0, len).toInt() : len;
    final b = sel.isValid ? sel.end.clamp(0, len).toInt() : len;
    return TextEditingValue(
      text: v.text.replaceRange(a, b, s),
      selection: TextSelection.collapsed(offset: a + s.length),
    );
  }

  void _typeIntoFocused(String s) {
    final f = _focusedField();
    if (f == null || !f.mounted || f.widget.readOnly) return;
    f.userUpdateTextEditingValue(_inserted(f.textEditingValue, s), SelectionChangedCause.keyboard);
  }

  /// يعيد الخانة لقيمتها قبل الحرف الأول من القارئ. إن لم يكن الحرف قد وصل الخانة بعد،
  /// نتحقق بعد قليل ونزيله فقط إن ظهر في موضعه بالضبط.
  void _restoreSnapshot() {
    final f = _snapField, v = _snapValue, first = _snapFirst;
    _clearSnap();
    if (f == null || v == null || !f.mounted || f.widget.readOnly) return;
    if (f.textEditingValue.text != v.text) {
      f.userUpdateTextEditingValue(v, SelectionChangedCause.keyboard);
      return;
    }
    if (first == null) return;
    final expected = _inserted(v, first).text;
    void later() {
      if (f.mounted && f.textEditingValue.text == expected) {
        f.userUpdateTextEditingValue(v, SelectionChangedCause.keyboard);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => later());
    Timer(const Duration(milliseconds: 60), later);
  }
}
