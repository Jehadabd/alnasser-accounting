// lib/services/keyboard_layout/keyboard_layout_io.dart
//
// ويندوز فقط (user32.dll): يطلب من نافذة البرنامج تغيير لغة الإدخال برسالة
// WM_INPUTLANGCHANGEREQUEST — نفس ما يفعله Alt+Shift — ثم يُرجع اللغة السابقة.
// الرسالة تُرسل إلى الخانة التي عليها التركيز (هذا ما تتوقعه ويندوز) وإلى النافذة
// الرئيسية معاً، فلا يتوقف التحويل على أيهما يعالجها. «اختبار» في الإعدادات يقول
// بالضبط لماذا لا يتحول (لا لوحة إنجليزية مثبّتة، نافذة غير نشطة...).

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _GetForegroundWindowC = IntPtr Function();
typedef _GetForegroundWindowD = int Function();
typedef _GetWindowThreadProcessIdC = Uint32 Function(IntPtr hwnd, Pointer<Uint32> pid);
typedef _GetWindowThreadProcessIdD = int Function(int hwnd, Pointer<Uint32> pid);
typedef _GetKeyboardLayoutC = IntPtr Function(Uint32 threadId);
typedef _GetKeyboardLayoutD = int Function(int threadId);
typedef _GetKeyboardLayoutListC = Int32 Function(Int32 n, Pointer<IntPtr> list);
typedef _GetKeyboardLayoutListD = int Function(int n, Pointer<IntPtr> list);
typedef _PostMessageC = Int32 Function(IntPtr hwnd, Uint32 msg, IntPtr wParam, IntPtr lParam);
typedef _PostMessageD = int Function(int hwnd, int msg, int wParam, int lParam);
typedef _GetGUIThreadInfoC = Int32 Function(Uint32 tid, Pointer<Uint8> info);
typedef _GetGUIThreadInfoD = int Function(int tid, Pointer<Uint8> info);

class KeyboardLayoutSwitcher {
  KeyboardLayoutSwitcher._();

  static const int _wmInputLangChangeRequest = 0x0050;
  static const int _langEnglish = 0x09; // اللغة الأساسية في أدنى 10 بتات من معرّف اللغة

  static bool _ready = false;
  static int _hwnd = 0; // نافذة البرنامج وقت التحويل (الإرجاع لها لا لنافذة برنامج آخر)
  static bool _failed = false;
  static late _GetForegroundWindowD _getForegroundWindow;
  static late _GetWindowThreadProcessIdD _getWindowThreadProcessId;
  static late _GetKeyboardLayoutD _getKeyboardLayout;
  static late _GetKeyboardLayoutListD _getKeyboardLayoutList;
  static late _PostMessageD _postMessage;
  static _GetGUIThreadInfoD? _getGUIThreadInfo;

  /// سبب آخر محاولة لم تحوّل (للاختبار في الإعدادات)؛ null = حوّلت أو كانت إنجليزية.
  static String? lastProblem;

  static bool _init() {
    if (_ready) return true;
    if (_failed || !Platform.isWindows) return false;
    try {
      final u = DynamicLibrary.open('user32.dll');
      _getForegroundWindow =
          u.lookupFunction<_GetForegroundWindowC, _GetForegroundWindowD>('GetForegroundWindow');
      _getWindowThreadProcessId =
          u.lookupFunction<_GetWindowThreadProcessIdC, _GetWindowThreadProcessIdD>('GetWindowThreadProcessId');
      _getKeyboardLayout = u.lookupFunction<_GetKeyboardLayoutC, _GetKeyboardLayoutD>('GetKeyboardLayout');
      _getKeyboardLayoutList =
          u.lookupFunction<_GetKeyboardLayoutListC, _GetKeyboardLayoutListD>('GetKeyboardLayoutList');
      _postMessage = u.lookupFunction<_PostMessageC, _PostMessageD>('PostMessageW');
      try {
        _getGUIThreadInfo = u.lookupFunction<_GetGUIThreadInfoC, _GetGUIThreadInfoD>('GetGUIThreadInfo');
      } catch (_) {}
      _ready = true;
    } catch (_) {
      _failed = true;
    }
    return _ready;
  }

  static bool _isEnglish(int hkl) => (hkl & 0x3FF) == _langEnglish;

  /// لغة الإدخال الحالية لنافذة البرنامج
  static int? _current(int hwnd) {
    final tid = _getWindowThreadProcessId(hwnd, nullptr);
    if (tid == 0) return null;
    return _getKeyboardLayout(tid);
  }

  /// أول لوحة إنجليزية مثبّتة في ويندوز (الإنجليزية الأمريكية إن وُجدت)
  static int? _englishLayout() {
    final n = _getKeyboardLayoutList(0, nullptr);
    if (n <= 0) return null;
    final buf = calloc<IntPtr>(n);
    try {
      final got = _getKeyboardLayoutList(n, buf);
      int? any;
      for (var i = 0; i < got; i++) {
        final h = buf[i];
        if (!_isEnglish(h)) continue;
        if ((h & 0xFFFF) == 0x0409) return h; // English (United States)
        any ??= h;
      }
      return any;
    } finally {
      calloc.free(buf);
    }
  }

  /// الخانة التي عليها التركيز في نافذة البرنامج (نافذة Flutter الداخلية)
  static int _focusOf(int tid) {
    final f = _getGUIThreadInfo;
    if (f == null) return 0;
    // GUITHREADINFO على 64 بت: cbSize(4) flags(4) ثم 6 مقابض × 8 ثم RECT(16) = 72
    final buf = calloc<Uint8>(72);
    try {
      buf.cast<Uint32>().value = 72;
      if (f(tid, buf) == 0) return 0;
      return Pointer<IntPtr>.fromAddress(buf.address + 16).value; // hwndFocus
    } catch (_) {
      return 0;
    } finally {
      calloc.free(buf);
    }
  }

  /// يرسل طلب تغيير اللغة إلى الخانة النشطة وإلى النافذة الرئيسية
  static void _request(int hwnd, int hkl) {
    final tid = _getWindowThreadProcessId(hwnd, nullptr);
    final focus = tid == 0 ? 0 : _focusOf(tid);
    if (focus != 0 && focus != hwnd) _postMessage(focus, _wmInputLangChangeRequest, 0, hkl);
    _postMessage(hwnd, _wmInputLangChangeRequest, 0, hkl);
  }

  /// نافذة البرنامج إن كانت هي النشطة (لا نغيّر لغة برنامج آخر أبداً)
  static int _ourForeground() {
    final hwnd = _getForegroundWindow();
    if (hwnd == 0) return 0;
    final p = calloc<Uint32>();
    try {
      _getWindowThreadProcessId(hwnd, p);
      return p.value == pid ? hwnd : 0;
    } finally {
      calloc.free(p);
    }
  }

  /// يحوّل إلى الإنجليزية ويُرجع اللغة السابقة؛ null إن كانت إنجليزية أصلاً أو تعذّر
  static int? switchToEnglish() {
    lastProblem = null;
    if (!_init()) {
      lastProblem = 'تعذّر الوصول إلى user32.dll';
      return null;
    }
    try {
      final hwnd = _ourForeground();
      if (hwnd == 0) {
        lastProblem = 'نافذة البرنامج ليست النافذة النشطة';
        return null;
      }
      final cur = _current(hwnd);
      if (cur == null) {
        lastProblem = 'تعذّر قراءة لغة الإدخال الحالية';
        return null;
      }
      if (_isEnglish(cur)) return null; // إنجليزية أصلاً
      final en = _englishLayout();
      if (en == null) {
        lastProblem = 'لا توجد لوحة مفاتيح إنجليزية مثبّتة في ويندوز — أضفها من إعدادات ويندوز ← اللغة';
        return null;
      }
      _hwnd = hwnd;
      _request(hwnd, en);
      return cur;
    } catch (e) {
      lastProblem = 'خطأ: $e';
      return null;
    }
  }

  /// يُرجع اللغة التي كانت قبل التحويل
  static void restore(int? previous) {
    if (previous == null || !_init()) return;
    try {
      final hwnd = _hwnd != 0 ? _hwnd : _ourForeground();
      if (hwnd == 0) return;
      _request(hwnd, previous);
    } catch (_) {}
  }

  /// 🧪 للإعدادات: يحوّل، ينتظر قليلاً، يقرأ اللغة فعلاً، ثم يُرجعها. يعيد جملة تشرح النتيجة.
  static Future<String> selfTest() async {
    if (!_init()) return 'تعذّر الوصول إلى user32.dll — الميزة لا تعمل على هذا الجهاز.';
    final hwnd = _ourForeground();
    if (hwnd == 0) return 'نافذة البرنامج ليست النافذة النشطة — اضغط داخل البرنامج ثم أعد الاختبار.';
    final cur = _current(hwnd);
    if (cur == null) return 'تعذّر قراءة لغة الإدخال الحالية.';
    if (_englishLayout() == null) {
      return 'لا توجد لوحة مفاتيح إنجليزية مثبّتة في ويندوز. أضف «English (United States)» من '
          'إعدادات ويندوز ← الوقت واللغة ← اللغة، ثم أعد الاختبار.';
    }
    if (_isEnglish(cur)) {
      return 'اللغة الآن إنجليزية أصلاً، فلا يوجد ما يُختبر. حوّلها إلى العربية (Alt+Shift) ثم اضغط «اختبار» مرة أخرى.';
    }
    final prev = switchToEnglish();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final now = _current(hwnd);
    final ok = now != null && _isEnglish(now);
    restore(prev);
    return ok
        ? 'يعمل ✓ — تحوّلت اللغة إلى الإنجليزية ثم عادت إلى العربية.'
        : 'لم تتحول اللغة (ما زالت 0x${(now ?? 0).toRadixString(16)}). أرسل هذه الجملة للدعم.';
  }
}
