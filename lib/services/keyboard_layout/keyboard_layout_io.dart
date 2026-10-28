// lib/services/keyboard_layout/keyboard_layout_io.dart
//
// ويندوز فقط (user32.dll): يطلب من نافذة البرنامج تغيير لغة الإدخال برسالة
// WM_INPUTLANGCHANGEREQUEST — نفس ما يفعله Alt+Shift — ثم يُرجع اللغة السابقة.

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

  /// يحوّل إلى الإنجليزية ويُرجع اللغة السابقة؛ null إن كانت إنجليزية أصلاً أو تعذّر
  static int? switchToEnglish() {
    if (!_init()) return null;
    try {
      final hwnd = _getForegroundWindow();
      if (hwnd == 0) return null;
      final cur = _current(hwnd);
      if (cur == null || _isEnglish(cur)) return null;
      final en = _englishLayout();
      if (en == null) return null; // لا توجد لوحة إنجليزية مثبّتة
      _hwnd = hwnd;
      _postMessage(hwnd, _wmInputLangChangeRequest, 0, en);
      return cur;
    } catch (_) {
      return null;
    }
  }

  /// يُرجع اللغة التي كانت قبل التحويل
  static void restore(int? previous) {
    if (previous == null || !_init()) return;
    try {
      final hwnd = _hwnd != 0 ? _hwnd : _getForegroundWindow();
      if (hwnd == 0) return;
      _postMessage(hwnd, _wmInputLangChangeRequest, 0, previous);
    } catch (_) {}
  }
}
