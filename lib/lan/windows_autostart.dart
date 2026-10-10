// lib/lan/windows_autostart.dart
//
// ▶️ تشغيل البرنامج تلقائياً عند دخول ويندوز — لحاسبة السيرفر.
//
// حين تكون الحاسبة «سيرفر» يُضاف البرنامج إلى قائمة بدء التشغيل للمستخدم الحالي
// (HKCU\Software\Microsoft\Windows\CurrentVersion\Run — لا يحتاج صلاحيات مدير)،
// فإذا أُطفئت الحاسبة ثم شُغّلت يفتح البرنامج وحده ويبدأ خدمة الطرفيات فوراً.
// يُزال تلقائياً عند تحويل الحاسبة إلى «مستقل» أو «طرفية»، أو بإطفاء الخيار.
// يعمل في نسخة الإصدار فقط (لا تُسجَّل نسخة التطوير في بدء التشغيل).

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, kReleaseMode;

typedef _RegGetValueC = Int32 Function(IntPtr hkey, Pointer<Utf16> subKey, Pointer<Utf16> value,
    Uint32 flags, Pointer<Uint32> type, Pointer<Void> data, Pointer<Uint32> cbData);
typedef _RegGetValueD = int Function(int hkey, Pointer<Utf16> subKey, Pointer<Utf16> value, int flags,
    Pointer<Uint32> type, Pointer<Void> data, Pointer<Uint32> cbData);
typedef _RegSetKeyValueC = Int32 Function(
    IntPtr hkey, Pointer<Utf16> subKey, Pointer<Utf16> value, Uint32 type, Pointer<Void> data, Uint32 cbData);
typedef _RegSetKeyValueD = int Function(
    int hkey, Pointer<Utf16> subKey, Pointer<Utf16> value, int type, Pointer<Void> data, int cbData);
typedef _RegDeleteKeyValueC = Int32 Function(IntPtr hkey, Pointer<Utf16> subKey, Pointer<Utf16> value);
typedef _RegDeleteKeyValueD = int Function(int hkey, Pointer<Utf16> subKey, Pointer<Utf16> value);

class WindowsAutostart {
  WindowsAutostart._();

  static const _valueName = 'AlnaserServer';
  static const _runKey = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const _hkcu = -2147483647; // HKEY_CURRENT_USER (0x80000001 موسَّعة بالإشارة)
  static const _regSz = 1;
  static const _rrfRtRegSz = 0x00000002;

  /// متاح على ويندوز في نسخة الإصدار فقط
  static bool get supported => !kIsWeb && Platform.isWindows && kReleaseMode;

  static String get _command => '"${Platform.resolvedExecutable}"';

  static DynamicLibrary get _advapi => DynamicLibrary.open('advapi32.dll');

  /// الأمر المسجَّل حالياً في بدء التشغيل (null إن لم يُسجَّل)
  static String? current() {
    if (kIsWeb || !Platform.isWindows) return null;
    final fn = _advapi.lookupFunction<_RegGetValueC, _RegGetValueD>('RegGetValueW');
    final pSub = _runKey.toNativeUtf16();
    final pName = _valueName.toNativeUtf16();
    final pcb = calloc<Uint32>();
    try {
      if (fn(_hkcu, pSub, pName, _rrfRtRegSz, nullptr, nullptr, pcb) != 0 || pcb.value == 0) return null;
      final buf = calloc<Uint8>(pcb.value + 4);
      try {
        if (fn(_hkcu, pSub, pName, _rrfRtRegSz, nullptr, buf.cast(), pcb) != 0) return null;
        return buf.cast<Utf16>().toDartString();
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(pSub);
      calloc.free(pName);
      calloc.free(pcb);
    }
  }

  static bool isEnabled() {
    try {
      return current() != null;
    } catch (_) {
      return false;
    }
  }

  static bool _enable() {
    final fn = _advapi.lookupFunction<_RegSetKeyValueC, _RegSetKeyValueD>('RegSetKeyValueW');
    final pSub = _runKey.toNativeUtf16();
    final pName = _valueName.toNativeUtf16();
    final cmd = _command;
    final pData = cmd.toNativeUtf16();
    try {
      return fn(_hkcu, pSub, pName, _regSz, pData.cast(), (cmd.length + 1) * 2) == 0;
    } finally {
      calloc.free(pSub);
      calloc.free(pName);
      calloc.free(pData);
    }
  }

  static bool _disable() {
    final fn = _advapi.lookupFunction<_RegDeleteKeyValueC, _RegDeleteKeyValueD>('RegDeleteKeyValueW');
    final pSub = _runKey.toNativeUtf16();
    final pName = _valueName.toNativeUtf16();
    try {
      final rc = fn(_hkcu, pSub, pName);
      return rc == 0 || rc == 2; // 2 = غير موجود أصلاً
    } finally {
      calloc.free(pSub);
      calloc.free(pName);
    }
  }

  /// يجعل بدء التشغيل مطابقاً للإعداد، ويحدّث المسار إن نُقل البرنامج أو حُدِّث.
  static void sync(bool want) {
    if (!supported) return;
    try {
      final cur = current();
      if (want) {
        if (cur != _command) {
          debugPrint('▶️ [Autostart] تسجيل البرنامج في بدء تشغيل ويندوز: ${_enable() ? 'تم' : 'فشل'}');
        }
      } else if (cur != null) {
        debugPrint('▶️ [Autostart] إزالة البرنامج من بدء تشغيل ويندوز: ${_disable() ? 'تم' : 'فشل'}');
      }
    } catch (e) {
      debugPrint('⚠️ [Autostart] $e');
    }
  }
}
