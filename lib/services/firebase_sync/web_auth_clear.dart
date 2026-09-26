// web_auth_clear.dart
// 🌐🔀 مُوجِّه مشروط: على الويب ينظف مخزن جلسة Firebase، وعلى الأصلي لا شيء.

export 'web_auth_clear_stub.dart'
    if (dart.library.html) 'web_auth_clear_web.dart';
