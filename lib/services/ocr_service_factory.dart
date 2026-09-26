// services/ocr_service_factory.dart
// 🌐🔀 المُوجِّه المشروط لخدمة OCR: ويب → stub، أصلي → الخدمة الكاملة كما هي.

export 'ocr_service_web.dart' if (dart.library.io) 'ocr_service.dart';
