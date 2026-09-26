// firebase_options_helper.dart
// 🌐🔀 مُوجِّه مشروط: ويب → خيارات الويب (مع authDomain)، أصلي → null.

export 'firebase_options_helper_stub.dart'
    if (dart.library.html) 'firebase_options_helper_web.dart';
