// web_db_init.dart
// 🌐🔀 مُوجِّه مشروط: على الويب يُفعّل محرك SQLite-WASM، وعلى المنصات
// الأصلية دالة فارغة (المحرك الافتراضي يعمل كما كان).

export 'web_db_init_stub.dart'
    if (dart.library.html) 'web_db_init_web.dart';
