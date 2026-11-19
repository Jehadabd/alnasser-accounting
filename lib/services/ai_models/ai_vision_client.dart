// lib/services/ai_models/ai_vision_client.dart
//
// 🤖 الاتصال بنماذج تقرأ الصور: Google Gemini، Groq، OpenRouter — بطلب واحد موحّد.
//
//   • Gemini: generateContent مع inline_data (صور، أو PDF مباشرة).
//   • Groq و OpenRouter: صيغة OpenAI (chat/completions) مع image_url بصيغة data:.
//     لا يُرسل إليهما PDF أبداً (OpenRouter يقرؤه بـ OCR مدفوع إن لم يُحدَّد غير ذلك) —
//     الصفحات تُحوَّل صوراً قبل الإرسال (ai_pdf_pages.dart).
//   • الأخطاء تُصنَّف (حصة، مفتاح، طلب مرفوض، نموذج غير موجود، خادم، مهلة) ليقرر
//     الموجّه (ai_router.dart): مفتاح آخر أم نموذج آخر.
//   • قائمة نماذج كل مزوّد: ما يقرأ الصور ومجاني (OpenRouter يعلن ذلك في قائمته).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_models_config.dart';

/// صورة أو ملف يُرسل للنموذج.
class AiBlob {
  const AiBlob(this.bytes, this.mime);
  final Uint8List bytes;
  final String mime;
  bool get isPdf => mime == 'application/pdf';
}

enum AiErrorKind {
  quota, // نفدت الحصة (429/402)
  auth, // المفتاح مرفوض (401/403)
  badRequest, // الطلب نفسه مرفوض (ملف، صورة، صيغة)
  notVision, // النموذج لا يقرأ الصور
  notFound, // النموذج غير موجود أو غير متاح لهذا المفتاح
  tooLarge, // الطلب أكبر من حد النموذج
  server, // خادم المزوّد مشغول
  timeout,
  network,
  empty, // رد فارغ
}

class AiCallException implements Exception {
  AiCallException(this.kind, this.message, {this.daily = false});
  final AiErrorKind kind;
  final String message;

  /// حصة اليوم انتهت (لا حصة الدقيقة).
  final bool daily;

  @override
  String toString() => message;
}

/// نموذج في قائمة المزوّد.
class AiModelInfo {
  const AiModelInfo({required this.provider, required this.id, this.name = '', this.vision, this.free, this.contextLength});
  final AiProvider provider;
  final String id;
  final String name;

  /// يقرأ الصور: true/false، أو null = غير معروف (يقرره الاختبار).
  final bool? vision;
  final bool? free;
  final int? contextLength;
}

class AiVisionClient {
  AiVisionClient._();

  /// للاختبارات.
  @visibleForTesting
  static http.Client? clientForTest;

  static Future<http.Response> _post(Uri u, {required Map<String, String> headers, required String body}) {
    final c = clientForTest;
    return c != null ? c.post(u, headers: headers, body: body) : http.post(u, headers: headers, body: body);
  }

  static Future<http.Response> _get(Uri u, {required Map<String, String> headers}) {
    final c = clientForTest;
    return c != null ? c.get(u, headers: headers) : http.get(u, headers: headers);
  }

  static const geminiBase = 'https://generativelanguage.googleapis.com/v1beta';
  static const groqBase = 'https://api.groq.com/openai/v1';
  static const openRouterBase = 'https://openrouter.ai/api/v1';

  /// طلب واحد: تعليمات + صور (أو PDF لـ Gemini فقط). يُرجع نص الرد.
  static Future<String> complete({
    required AiProvider provider,
    required String model,
    required String apiKey,
    required String prompt,
    List<AiBlob> files = const [],
    bool jsonOutput = true,
    Duration timeout = const Duration(seconds: 150),
  }) async {
    if (!provider.nativePdf && files.any((f) => f.isPdf)) {
      // حماية: لا PDF لغير Gemini (OpenRouter يحوّله بـ OCR مدفوع)
      throw AiCallException(AiErrorKind.badRequest, 'هذا المزوّد لا يستقبل PDF — يجب تحويل الصفحات إلى صور');
    }
    final http.Response res;
    try {
      final Future<http.Response> req = switch (provider) {
        AiProvider.gemini => _post(
            Uri.parse('$geminiBase/models/$model:generateContent'),
            headers: {'Content-Type': 'application/json', 'X-goog-api-key': apiKey},
            body: jsonEncode(geminiBody(prompt, files, jsonOutput: jsonOutput)),
          ),
        AiProvider.groq => _post(
            Uri.parse('$groqBase/chat/completions'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
            body: jsonEncode(openAiBody(model, prompt, files)),
          ),
        AiProvider.openrouter => _post(
            Uri.parse('$openRouterBase/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
              'X-Title': 'Alnaser Accounting',
            },
            body: jsonEncode(openAiBody(model, prompt, files)),
          ),
      };
      res = await req.timeout(timeout);
    } on TimeoutException {
      throw AiCallException(AiErrorKind.timeout, 'انتهت المهلة');
    } catch (e) {
      throw AiCallException(AiErrorKind.network, 'تعذّر الاتصال ($e)');
    }
    if (res.statusCode != 200) throw classify(res.statusCode, utf8.decode(res.bodyBytes, allowMalformed: true));
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    final text = provider == AiProvider.gemini ? geminiText(body) : openAiText(body);
    if (text.trim().isEmpty) {
      // OpenRouter قد يرجع 200 وفيه خطأ
      final err = embeddedError(body);
      if (err != null) throw err;
      throw AiCallException(AiErrorKind.empty, 'رد فارغ');
    }
    return text;
  }

  @visibleForTesting
  static Map<String, Object?> geminiBody(String prompt, List<AiBlob> files, {bool jsonOutput = true}) => {
        'contents': [
          {
            'parts': [
              {'text': prompt},
              for (final f in files)
                {
                  'inline_data': {'mime_type': f.mime, 'data': base64Encode(f.bytes)}
                },
            ]
          }
        ],
        'generationConfig': {
          if (jsonOutput) 'response_mime_type': 'application/json',
          'temperature': 0.1,
        },
      };

  @visibleForTesting
  static Map<String, Object?> openAiBody(String model, String prompt, List<AiBlob> files) => {
        'model': model,
        'temperature': 0.1,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              for (final f in files)
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:${f.mime};base64,${base64Encode(f.bytes)}'}
                },
            ],
          }
        ],
      };

  @visibleForTesting
  static String geminiText(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return '';
      final candidates = decoded['candidates'];
      if (candidates is! List || candidates.isEmpty) return '';
      final content = (candidates.first as Map)['content'];
      final parts = content is Map ? content['parts'] : null;
      if (parts is! List) return '';
      return parts.map((p) => p is Map ? (p['text']?.toString() ?? '') : '').join();
    } catch (_) {
      return '';
    }
  }

  @visibleForTesting
  static String openAiText(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return '';
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return '';
      final msg = (choices.first as Map)['message'];
      final c = msg is Map ? msg['content'] : null;
      if (c is String) return c;
      if (c is List) return c.map((p) => p is Map ? (p['text']?.toString() ?? '') : '').join();
      return '';
    } catch (_) {
      return '';
    }
  }

  /// خطأ داخل رد 200 (OpenRouter أحياناً).
  @visibleForTesting
  static AiCallException? embeddedError(String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map && d['error'] is Map) {
        final e = d['error'] as Map;
        final code = (e['code'] as num?)?.toInt() ?? 500;
        return classify(code, jsonEncode(d));
      }
    } catch (_) {}
    return null;
  }

  /// تصنيف خطأ HTTP إلى ما يقرر الخطوة التالية.
  static AiCallException classify(int code, String body) {
    final lower = body.toLowerCase();
    var msg = '';
    try {
      final d = jsonDecode(body);
      if (d is Map) {
        final e = d['error'];
        msg = e is Map ? '${e['message'] ?? ''}' : (e?.toString() ?? '');
      }
    } catch (_) {}
    if (msg.length > 160) msg = msg.substring(0, 160);
    final daily = lower.contains('perday') || lower.contains('per day') || lower.contains('daily') || lower.contains('per-day');
    final visionWords = lower.contains('image') || lower.contains('vision') || lower.contains('modalit') || lower.contains('multimodal');
    final notSupported = lower.contains('not support') || lower.contains('unsupported') || lower.contains('does not accept') || lower.contains('no endpoints');
    if (code == 429) {
      return AiCallException(AiErrorKind.quota, daily ? 'نفدت حصة اليوم لهذا المفتاح (429)' : 'تجاوزت حد الطلبات في الدقيقة (429)', daily: daily);
    }
    if (code == 402) return AiCallException(AiErrorKind.quota, 'الرصيد غير كافٍ لهذا المفتاح (402)', daily: true);
    if (code == 401 || code == 403) {
      return AiCallException(AiErrorKind.auth, 'المفتاح مرفوض أو غير مفعّل ($code)${msg.isEmpty ? '' : ' — $msg'}');
    }
    if (lower.contains('data policy') || lower.contains('privacy settings')) {
      // OpenRouter: النماذج المجانية تحتاج السماح بها من إعدادات الخصوصية في الحساب
      return AiCallException(AiErrorKind.notFound,
          'OpenRouter يمنع هذا النموذج حسب إعداد الخصوصية في حسابك — افتح openrouter.ai ← Settings ← Privacy واسمح بالنماذج المجانية');
    }
    if (code == 404) {
      if (visionWords && notSupported) return AiCallException(AiErrorKind.notVision, 'هذا النموذج لا يقرأ الصور');
      return AiCallException(AiErrorKind.notFound, 'النموذج غير موجود أو غير متاح لهذا المفتاح (404)');
    }
    if (code == 413 || lower.contains('context length') || lower.contains('context_length') || lower.contains('too large') || lower.contains('maximum context')) {
      return AiCallException(AiErrorKind.tooLarge, 'الطلب أكبر من حد النموذج ($code)');
    }
    if (code == 400 || code == 422) {
      if (visionWords && notSupported) return AiCallException(AiErrorKind.notVision, 'هذا النموذج لا يقرأ الصور');
      if (lower.contains('api key') || lower.contains('api_key')) {
        return AiCallException(AiErrorKind.auth, 'المفتاح غير صالح ($code)');
      }
      return AiCallException(AiErrorKind.badRequest, 'رفض النموذج الطلب ($code)${msg.isEmpty ? '' : ' — $msg'}');
    }
    if (code >= 500) return AiCallException(AiErrorKind.server, 'خادم المزوّد مشغول ($code) — أعد المحاولة');
    return AiCallException(AiErrorKind.badRequest, 'HTTP $code ${msg.isEmpty ? '' : msg}');
  }

  // ───────────────────────── قائمة النماذج ─────────────────────────

  /// نماذج المزوّد التي قد تقرأ الصور (للاختبار). يرمي AiCallException إن رُفض المفتاح.
  static Future<List<AiModelInfo>> listModels(AiProvider provider, String apiKey) async {
    final http.Response res;
    try {
      final Future<http.Response> req = switch (provider) {
        AiProvider.gemini => _get(Uri.parse('$geminiBase/models?pageSize=200'), headers: {'X-goog-api-key': apiKey}),
        AiProvider.groq => _get(Uri.parse('$groqBase/models'), headers: {'Authorization': 'Bearer $apiKey'}),
        AiProvider.openrouter => _get(Uri.parse('$openRouterBase/models'), headers: {'Authorization': 'Bearer $apiKey'}),
      };
      res = await req.timeout(const Duration(seconds: 40));
    } on TimeoutException {
      throw AiCallException(AiErrorKind.timeout, 'انتهت المهلة');
    } catch (e) {
      throw AiCallException(AiErrorKind.network, 'تعذّر الاتصال ($e)');
    }
    if (res.statusCode != 200) throw classify(res.statusCode, utf8.decode(res.bodyBytes, allowMalformed: true));
    return parseModels(provider, utf8.decode(res.bodyBytes, allowMalformed: true));
  }

  /// OpenRouter لا يتحقق من المفتاح في قائمة النماذج — نتحقق منه هنا (رصيد/حدود المفتاح).
  static Future<void> checkOpenRouterKey(String apiKey) async {
    final http.Response res;
    try {
      res = await _get(Uri.parse('$openRouterBase/key'), headers: {'Authorization': 'Bearer $apiKey'})
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw AiCallException(AiErrorKind.network, 'تعذّر الاتصال ($e)');
    }
    if (res.statusCode != 200) throw classify(res.statusCode, utf8.decode(res.bodyBytes, allowMalformed: true));
  }

  static const _geminiSkip = ['tts', 'image', 'live', 'embedding', 'audio', 'native', 'robotics', 'computer', 'aqa', 'imagen', 'veo', 'learnlm', 'transcribe', 'translate', 'lyria'];

  /// Groq: ما يقرأ الصور حسب توثيقه (والباقي «غير معروف» يقرره الاختبار).
  static const _groqVision = {'qwen/qwen3.8-27b', 'meta-models/muse-spark-open'};

  @visibleForTesting
  static List<AiModelInfo> parseModels(AiProvider provider, String body) {
    final out = <AiModelInfo>[];
    final d = jsonDecode(body);
    switch (provider) {
      case AiProvider.gemini:
        final gList = d is Map ? d['models'] : null;
        if (gList is! List) return out;
        for (final m in gList) {
          if (m is! Map) continue;
          final name = '${m['name'] ?? ''}'.replaceFirst('models/', '');
          final methods = m['supportedGenerationMethods'];
          if (!name.contains('gemini')) continue;
          if (methods is List && !methods.contains('generateContent')) continue;
          if (_geminiSkip.any(name.contains)) continue;
          out.add(AiModelInfo(
            provider: provider,
            id: name,
            name: '${m['displayName'] ?? name}',
            vision: true,
            contextLength: (m['inputTokenLimit'] as num?)?.toInt(),
          ));
        }
      case AiProvider.groq:
        final qList = d is Map ? d['data'] : null;
        if (qList is! List) return out;
        for (final m in qList) {
          if (m is! Map) continue;
          final id = '${m['id'] ?? ''}';
          if (id.isEmpty || m['active'] == false) continue;
          final lower = id.toLowerCase();
          if (lower.contains('whisper') || lower.contains('guard') || lower.contains('orpheus') || lower.contains('tts')) continue;
          final known = _groqVision.contains(id);
          final hinted = lower.contains('vision') || lower.contains('-vl') || lower.contains('scout') || lower.contains('maverick');
          out.add(AiModelInfo(
            provider: provider,
            id: id,
            name: id,
            vision: known ? true : (hinted ? null : false),
            contextLength: (m['context_window'] as num?)?.toInt(),
          ));
        }
      case AiProvider.openrouter:
        final oList = d is Map ? d['data'] : null;
        if (oList is! List) return out;
        for (final m in oList) {
          if (m is! Map) continue;
          final id = '${m['id'] ?? ''}';
          if (id.isEmpty || id == 'openrouter/free' || id.startsWith('openrouter/auto')) continue;
          final arch = m['architecture'];
          final inputs = arch is Map ? arch['input_modalities'] : null;
          final vision = inputs is List ? inputs.contains('image') : null;
          final pricing = m['pricing'];
          bool isZero(Object? v) => v == null || (double.tryParse('$v') ?? 1) == 0;
          final free = id.endsWith(':free') || (pricing is Map && isZero(pricing['prompt']) && isZero(pricing['completion']) && isZero(pricing['image']));
          out.add(AiModelInfo(
            provider: provider,
            id: id,
            name: '${m['name'] ?? id}',
            vision: vision,
            free: free,
            contextLength: (m['context_length'] as num?)?.toInt(),
          ));
        }
    }
    return out;
  }

  /// المرشحون للاختبار: يقرؤون الصور (أو غير معروف)، ومجانيون في OpenRouter — بترتيب
  /// الأفضلية المعروفة.
  static List<AiModelInfo> candidates(List<AiModelInfo> all) {
    final c = all.where((m) {
      if (m.vision == false) return false;
      if (m.provider == AiProvider.openrouter && m.free != true) return false;
      return true;
    }).toList()
      ..sort((a, b) => priorScore(b).compareTo(priorScore(a)));
    return c;
  }

  /// أفضلية مبدئية قبل الاختبار (الاختبار هو الحَكَم).
  static int priorScore(AiModelInfo m) {
    final id = m.id.toLowerCase();
    if (m.provider == AiProvider.gemini) {
      if (id.contains('preview') || id.contains('exp')) return 30;
      if (id == 'gemini-3.8-flash') return 100;
      if (id == 'gemini-3.5-flash-lite') return 92;
      if (id == 'gemini-3.6-flash') return 94;
      if (id == 'gemini-2.5-flash') return 85;
      if (id == 'gemini-2.5-pro') return 80;
      if (id == 'gemini-flash-latest') return 78;
      if (id.contains('flash-lite')) return 70;
      if (id.contains('flash')) return 75;
      if (id.contains('pro')) return 60;
      return 40;
    }
    if (m.provider == AiProvider.groq) return m.vision == true ? 72 : 35;
    // OpenRouter
    if (id.startsWith('google/gemma-4-31b')) return 66;
    if (id.contains('nemotron') && id.contains('vl')) return 64;
    if (id.startsWith('google/gemma-4')) return 62;
    if (id.contains('qwen') && id.contains('vl')) return 60;
    if (m.vision == true) return 50;
    return 20;
  }
}
