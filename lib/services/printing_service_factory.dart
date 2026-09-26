// services/printing_service_factory.dart
// 🌐🔀 المُوجِّه المشروط لخدمة الطباعة:
// على الويب → PrintingServiceWeb (PDF عبر المتصفح)
// على المنصات الأصلية → نفس مصنع io (أندرويد/ويندوز) كما كان تماماً.

export 'printing_service_platform_web.dart'
    if (dart.library.io) 'printing_service_platform_io.dart';
