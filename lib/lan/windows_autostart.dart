// تشغيل خادم الشبكة مع ويندوز: التنفيذ الأصلي (dart:ffi)، وبديل فارغ للويب.
export 'windows_autostart_io.dart' if (dart.library.js_interop) 'windows_autostart_web.dart';
