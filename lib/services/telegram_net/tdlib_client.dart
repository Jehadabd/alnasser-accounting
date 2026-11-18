// lib/services/telegram_net/tdlib_client.dart
//
// 🔀 عميل TDLib: التنفيذ الحقيقي (dart:ffi) حيث يتوفر، وبديل فارغ في نسخة الويب
// (dart:ffi غير موجود في المتصفح — كان استيراده يوقف بناء الويب كله).
// الواجهة نفسها في الملفين؛ MTProto مطفأ أصلاً على غير Windows (TelegramMtproto.supported).

export 'tdlib_client_stub.dart' if (dart.library.ffi) 'tdlib_client_io.dart';
