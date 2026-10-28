// بصمة الجهاز: التنفيذ الأصلي (dart:ffi) لويندوز/أندرويد، وبديل بلا ffi للويب
// (dart:ffi غير متاح على الويب فيكسر flutter build web).
export 'device_fingerprint_io.dart' if (dart.library.js_interop) 'device_fingerprint_web.dart';
