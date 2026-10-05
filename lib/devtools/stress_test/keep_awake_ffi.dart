// ويندوز: SetThreadExecutionState(ES_SYSTEM_REQUIRED) يعيد ضبط مؤقت السكون.
// يُستدعى كل 30 ثانية ما دام الاختبار يعمل؛ ويتوقف عند انتهائه فيعود السكون كالمعتاد.

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

Timer? _timer;

void _ping(int flags) {
  try {
    final k32 = ffi.DynamicLibrary.open('kernel32.dll');
    final f = k32.lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>('SetThreadExecutionState');
    f(flags);
  } catch (_) {}
}

void setSystemAwake(bool on) {
  _timer?.cancel();
  _timer = null;
  if (!Platform.isWindows) return;
  const esSystemRequired = 0x00000001;
  const esContinuous = 0x80000000;
  if (on) {
    _ping(esSystemRequired);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _ping(esSystemRequired));
  } else {
    _ping(esContinuous); // يُلغي أي طلب مستمر سابق
  }
}
