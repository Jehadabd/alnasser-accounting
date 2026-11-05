// lib/services/barcode/scan_burst.dart
//
// ⌨️ تمييز قارئ الباركود عن كتابة الإنسان — منطق نقي بلا واجهة (قابل للاختبار).
//
// القارئ يعمل كلوحة مفاتيح: يكتب الرمز حرفاً حرفاً بسرعة كبيرة (عادة أقل من 20 ملّي ثانية
// بين الحرفين) ثم Enter (أو Tab). الإنسان أبطأ بكثير (عادة أكثر من 80 ملّي ثانية).
//
//   • الحرف الأول يمر للخانة كالمعتاد (لا نعرف بعد من يكتب) — ونحفظ قيمة الخانة قبله.
//   • ما يتبعه بسرعة القارئ يُحجز (لا يُكتب).
//   • Enter/Tab بعد رشقة سريعة بطول كافٍ ⇒ رمز مقروء: تعود الخانة كما كانت ويُعالَج الرمز.
//   • وإلا (إنسان كتب بسرعة صدفة) ⇒ تُكتب الحروف المحجوزة في الخانة كما هي، فلا يضيع شيء.
//   • قارئ بلا Enter: رشقة سريعة من 8 حروف فأكثر ثم توقف ⇒ رمز مقروء.
//
// الحروف تُقرأ من موضع المفتاح (تخطيط إنجليزي) لا من لغة لوحة المفاتيح: إن كانت العربية
// مفعّلة يبقى الرمز صحيحاً (A لا ش).

import 'package:flutter/services.dart' show PhysicalKeyboardKey;

class BurstStep {
  const BurstStep({this.swallow = false, this.flush = '', this.snapshot = false, this.code});

  /// لا يُسلَّم هذا المفتاح للخانة.
  final bool swallow;

  /// حروف محجوزة تبيّن أنها كتابة إنسان: تُكتب في الخانة قبل هذا المفتاح.
  final String flush;

  /// بداية رشقة محتملة: احفظ قيمة الخانة الآن (بعد [flush] وقبل الحرف الحالي).
  final bool snapshot;

  /// رمز مقروء كامل: أرجع الخانة لقيمتها المحفوظة وعالج الرمز.
  final String? code;

  static const none = BurstStep();
}

class ScanBurstDetector {
  ScanBurstDetector({required this.maxGap, required this.minLength});

  /// أقصى زمن بين حرفين في رشقة القارئ.
  Duration maxGap;

  /// أقل طول لرمز ينتهي بـ Enter/Tab.
  int minLength;

  /// أقل طول لرمز بلا Enter (يُكتشف بالتوقف) — أطول عمداً حتى لا تُحسب كتابة سريعة رمزاً.
  static const int minLengthNoSuffix = 8;

  /// أطول رمز معقول؛ ما زاد يُعدّ كتابة لا مسحاً.
  static const int maxLength = 64;

  final StringBuffer _mapped = StringBuffer();
  final List<String> _typed = [];
  Duration? _last;

  bool get active => _typed.isNotEmpty;

  /// الحرف الأول الذي مرّ للخانة (لتأكيد الإرجاع).
  String? get firstTyped => _typed.isEmpty ? null : _typed.first;

  /// مدة التوقف التي تُنهي الرشقة.
  Duration get idleAfter => maxGap * 3;

  void reset() {
    _mapped.clear();
    _typed.clear();
    _last = null;
  }

  String _held() => _typed.length <= 1 ? '' : _typed.sublist(1).join();

  Duration _gap(Duration t) {
    final g = t - (_last ?? t);
    return g.isNegative ? Duration.zero : g;
  }

  void _start(String mapped, String typed, Duration t) {
    reset();
    _mapped.write(mapped);
    _typed.add(typed);
    _last = t;
  }

  /// حرف قابل للطباعة: [mapped] حسب موضع المفتاح، [typed] كما تكتبه لوحة المفاتيح الحالية.
  BurstStep char(String mapped, String typed, Duration t) {
    if (_typed.isEmpty) {
      _start(mapped, typed, t);
      return const BurstStep(snapshot: true);
    }
    if (_gap(t) <= maxGap && _typed.length < maxLength) {
      _mapped.write(mapped);
      _typed.add(typed);
      _last = t;
      return const BurstStep(swallow: true);
    }
    final f = _held();
    _start(mapped, typed, t);
    return BurstStep(flush: f, snapshot: true);
  }

  /// Enter أو Tab.
  BurstStep terminator(Duration t) {
    if (_typed.isEmpty) return BurstStep.none;
    final code = _mapped.toString().trim();
    if (_gap(t) <= maxGap * 2 && code.length >= minLength) {
      reset();
      return BurstStep(swallow: true, code: code);
    }
    final f = _held();
    reset();
    return BurstStep(flush: f);
  }

  /// مفتاح آخر (أسهم، حذف، اختصار…): ما حُجز كان كتابة إنسان.
  BurstStep other() {
    if (_typed.isEmpty) return BurstStep.none;
    final f = _held();
    reset();
    return BurstStep(flush: f);
  }

  /// لا مفتاح منذ [idleAfter]: رمز بلا Enter إن كان طويلاً، وإلا كتابة إنسان.
  BurstStep idle(Duration t) {
    if (_typed.isEmpty || _gap(t) < idleAfter) return BurstStep.none;
    final code = _mapped.toString().trim();
    if (code.length >= minLengthNoSuffix && code.length >= minLength) {
      reset();
      return BurstStep(code: code);
    }
    final f = _held();
    reset();
    return BurstStep(flush: f);
  }
}

/// مفاتيح إنهاء الرمز (Enter، Enter الأرقام، Tab).
bool isScanTerminator(PhysicalKeyboardKey k) {
  final u = k.usbHidUsage;
  return u == 0x00070028 || u == 0x00070058 || u == 0x0007002b;
}

/// مفاتيح التعديل (Shift/Ctrl/Alt/Meta/CapsLock/NumLock) — لا تقطع الرشقة.
bool isScanModifier(PhysicalKeyboardKey k) {
  final u = k.usbHidUsage;
  return (u >= 0x000700e0 && u <= 0x000700e7) || u == 0x00070039 || u == 0x00070053;
}

const _shiftDigits = '!@#\$%^&*()';
const _sym = <int, (String, String)>{
  0x2c: (' ', ' '),
  0x2d: ('-', '_'),
  0x2e: ('=', '+'),
  0x2f: ('[', '{'),
  0x30: (']', '}'),
  0x31: ('\\', '|'),
  0x33: (';', ':'),
  0x34: ("'", '"'),
  0x35: ('`', '~'),
  0x36: (',', '<'),
  0x37: ('.', '>'),
  0x38: ('/', '?'),
  0x54: ('/', '/'),
  0x55: ('*', '*'),
  0x56: ('-', '-'),
  0x57: ('+', '+'),
  0x63: ('.', '.'),
};

/// الحرف الذي يكتبه المفتاح على تخطيط إنجليزي (US) — null لغير الحروف/الأرقام/الرموز.
String? usKeyChar(PhysicalKeyboardKey k, {required bool shift}) {
  final u = k.usbHidUsage;
  if (u >> 16 != 0x0007) return null;
  final c = u & 0xffff;
  if (c >= 0x04 && c <= 0x1d) {
    final ch = String.fromCharCode(0x61 + c - 0x04);
    return shift ? ch.toUpperCase() : ch;
  }
  if (c >= 0x1e && c <= 0x27) {
    final i = c - 0x1e; // 0..9 ⇒ 1..9 ثم 0
    return shift ? _shiftDigits[i] : (i == 9 ? '0' : '${i + 1}');
  }
  if (c >= 0x59 && c <= 0x62) {
    final i = c - 0x59;
    return i == 9 ? '0' : '${i + 1}';
  }
  final s = _sym[c];
  if (s == null) return null;
  return shift ? s.$2 : s.$1;
}
