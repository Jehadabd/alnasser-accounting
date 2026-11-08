// lib/owner/wa_auto/wa_desktop_io.dart
//
// 💬 إرسال رسالة عبر تطبيق WhatsApp Desktop الرسمي (ويندوز فقط):
//   1) يفتح رابط whatsapp://send?phone=…&text=… ⇒ يفتح التطبيق الرسمي المحادثة والنص مكتوب فيها.
//   2) ينتظر حتى تصبح نافذة «WhatsApp» هي النشطة، ثم مهلة لتحميل المحادثة.
//   3) يتأكد مرة أخرى أن النافذة النشطة هي واتساب، ثم يضغط Enter.
// لا يضغط Enter أبداً في نافذة غير واتساب (لو انتقل المستخدم لبرنامج آخر يفشل الإرسال
// بدل أن يكتب في مكان خاطئ). جلسة واتساب تبقى داخل تطبيق واتساب نفسه — لا شيء يُخزَّن هنا.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:url_launcher/url_launcher.dart';

typedef _GetForegroundWindowC = IntPtr Function();
typedef _GetForegroundWindowD = int Function();
typedef _GetWindowTextC = Int32 Function(IntPtr hwnd, Pointer<Utf16> buf, Int32 max);
typedef _GetWindowTextD = int Function(int hwnd, Pointer<Utf16> buf, int max);
typedef _KeybdEventC = Void Function(Uint8 vk, Uint8 scan, Uint32 flags, IntPtr extra);
typedef _KeybdEventD = void Function(int vk, int scan, int flags, int extra);

class WaDesktop {
  WaDesktop._();

  static const _vkReturn = 0x0D;
  static const _keyUp = 0x0002;

  static bool _ready = false;
  static bool _failed = false;
  static late _GetForegroundWindowD _getForegroundWindow;
  static late _GetWindowTextD _getWindowText;
  static late _KeybdEventD _keybdEvent;

  static bool get supported => Platform.isWindows && _init();

  static bool _init() {
    if (_ready) return true;
    if (_failed || !Platform.isWindows) return false;
    try {
      final u = DynamicLibrary.open('user32.dll');
      _getForegroundWindow = u.lookupFunction<_GetForegroundWindowC, _GetForegroundWindowD>('GetForegroundWindow');
      _getWindowText = u.lookupFunction<_GetWindowTextC, _GetWindowTextD>('GetWindowTextW');
      _keybdEvent = u.lookupFunction<_KeybdEventC, _KeybdEventD>('keybd_event');
      _ready = true;
    } catch (_) {
      _failed = true;
    }
    return _ready;
  }

  /// عنوان النافذة النشطة الآن.
  static String? foregroundTitle() {
    if (!_init()) return null;
    final hwnd = _getForegroundWindow();
    if (hwnd == 0) return null;
    final buf = calloc<Uint16>(256);
    try {
      final n = _getWindowText(hwnd, buf.cast<Utf16>(), 256);
      return n <= 0 ? '' : buf.cast<Utf16>().toDartString(length: n);
    } finally {
      calloc.free(buf);
    }
  }

  static bool _whatsAppActive() {
    final t = (foregroundTitle() ?? '').trim().toLowerCase();
    return t == 'whatsapp' || t.startsWith('whatsapp ') || t.endsWith(' whatsapp') || t.contains('واتساب');
  }

  /// null = ضُغط «إرسال» في واتساب؛ نص = سبب عدم الإرسال (لم يُضغط شيء).
  static Future<String?> send(String phone, String text, {Duration loadWait = const Duration(seconds: 4)}) async {
    if (!_init()) return 'غير متاح على هذا الجهاز';
    final uri = Uri.parse('whatsapp://send?phone=$phone&text=${Uri.encodeComponent(text)}');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) return 'تطبيق WhatsApp Desktop غير مثبّت';
    } catch (_) {
      return 'تطبيق WhatsApp Desktop غير مثبّت';
    }
    // ⏳ حتى 20 ثانية لظهور نافذة واتساب في المقدمة
    final until = DateTime.now().add(const Duration(seconds: 20));
    while (!_whatsAppActive()) {
      if (DateTime.now().isAfter(until)) return 'لم تظهر نافذة واتساب (هل هي مسجّلة الدخول؟)';
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    // ⏳ تحميل المحادثة ووضع النص في خانة الكتابة
    await Future<void>.delayed(loadWait);
    if (!_whatsAppActive()) return 'انتقلت النافذة النشطة من واتساب قبل الإرسال — لم يُرسل شيء';
    _keybdEvent(_vkReturn, 0, 0, 0);
    _keybdEvent(_vkReturn, 0, _keyUp, 0);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return null;
  }
}
