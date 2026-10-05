// lib/devtools/stress_test/keep_awake.dart
//
// منع الحاسوب من السكون أثناء عمل اختبار التحمّل فقط (مثل برامج الفيديو) —
// لا يغيّر إعدادات الطاقة في ويندوز؛ يعود السلوك طبيعياً عند توقف الاختبار.

export 'keep_awake_stub.dart' if (dart.library.ffi) 'keep_awake_ffi.dart';
