// services/ensemble_ai_service_factory.dart
// 🌐🔀 المُوجِّه المشروط لخدمة AI:
// ويب → نسخة ويب (مطابقة نصية فقط، لا onnxruntime)
// منصات أصلية → الخدمة الكاملة كما هي تماماً.

export 'ensemble_ai_service_web.dart'
    if (dart.library.io) 'ensemble_ai_service.dart';
