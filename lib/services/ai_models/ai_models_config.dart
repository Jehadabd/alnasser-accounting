// lib/services/ai_models/ai_models_config.dart
//
// 🤖 إعداد نماذج الذكاء الاصطناعي (الإعدادات ← النظام والأدوات ← نماذج الذكاء الاصطناعي).
//
//   • المزوّدون: Google Gemini (مباشرة)، Groq، OpenRouter — لكلٍّ مفاتيح متعددة.
//   • النماذج: قائمة مرتّبة بالأولوية، كل نموذج يتبع مزوّداً، يُفعَّل/يُعطَّل، ومعه نتيجة
//     آخر اختبار (قراءة فاتورة تجريبية).
//   • التعاون بين نموذجين: نموذج يقرأ الفاتورة، وآخر يطابق موادها (اختياري: «تلقائي»).
//
// الحفظ:
//   • المفاتيح في خزنة النظام (FlutterSecureStorage) على هذا الجهاز فقط — لا تُزامَن، ولا
//     تدخل قاعدة البيانات، فلا تذهب مع النسخ الاحتياطية إلى Telegram/Dropbox/Discord.
//   • القائمة والترتيب في SharedPreferences لهذا الجهاز.
//   • مفاتيح GEMINI_API_KEY في ملف ‎.env (الطريقة القديمة) تبقى تعمل إن لم يُضف مفتاح Gemini.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AiProvider { gemini, groq, openrouter }

extension AiProviderInfo on AiProvider {
  String get label => switch (this) {
        AiProvider.gemini => 'Google Gemini',
        AiProvider.groq => 'Groq',
        AiProvider.openrouter => 'OpenRouter',
      };

  /// يقرأ ملف PDF مباشرة (غيره: تُحوَّل صفحات الـ PDF إلى صور قبل الإرسال).
  bool get nativePdf => this == AiProvider.gemini;

  /// أقصى عدد صور في الطلب الواحد (Groq: 3 حسب توثيقه).
  int get maxImages => switch (this) {
        AiProvider.gemini => 16,
        AiProvider.groq => 3,
        AiProvider.openrouter => 4,
      };

  /// رابط إنشاء المفتاح.
  String get keysUrl => switch (this) {
        AiProvider.gemini => 'https://aistudio.google.com/app/apikey',
        AiProvider.groq => 'https://console.groq.com/keys',
        AiProvider.openrouter => 'https://openrouter.ai/settings/keys',
      };
}

AiProvider? aiProviderByName(String? n) {
  for (final p in AiProvider.values) {
    if (p.name == n) return p;
  }
  return null;
}

/// مفتاح API لمزوّد.
class AiKey {
  AiKey({required this.id, required this.provider, required this.key, this.label = '', this.fromEnv = false});

  final String id;
  final AiProvider provider;
  final String key;
  final String label;

  /// من ملف ‎.env (للقراءة فقط — لا يُحذف من الإعدادات).
  final bool fromEnv;

  /// آخر 4 أحرف فقط للعرض.
  String get masked => key.length <= 8 ? '••••' : '••••${key.substring(key.length - 4)}';

  Map<String, Object?> toJson() => {'id': id, 'p': provider.name, 'k': key, 'l': label};

  static AiKey? fromJson(Object? j) {
    if (j is! Map) return null;
    final p = aiProviderByName('${j['p']}');
    final k = '${j['k'] ?? ''}'.trim();
    if (p == null || k.isEmpty) return null;
    return AiKey(id: '${j['id'] ?? k.hashCode}', provider: p, key: k, label: '${j['l'] ?? ''}');
  }
}

/// نموذج في قائمة الأولوية.
class AiModelEntry {
  AiModelEntry({
    required this.provider,
    required this.model,
    this.label = '',
    this.enabled = true,
    this.testScore,
    this.testTotal,
    this.testMs,
    this.testedAt,
    this.testNote = '',
  });

  final AiProvider provider;
  final String model;
  String label;
  bool enabled;

  /// نتيجة آخر اختبار: كم رقماً قرأه صحيحاً من [testTotal].
  int? testScore;
  int? testTotal;
  int? testMs;
  DateTime? testedAt;
  String testNote;

  /// معرّف فريد: «المزوّد:النموذج».
  String get id => '${provider.name}:$model';
  String get shownName => label.trim().isEmpty ? model : label;
  bool get tested => testedAt != null && testTotal != null && testTotal! > 0;
  bool get testPassed => tested && (testScore ?? 0) >= (testTotal! * 0.8).ceil();

  Map<String, Object?> toJson() => {
        'p': provider.name,
        'm': model,
        'l': label,
        'e': enabled,
        if (testScore != null) 'ts': testScore,
        if (testTotal != null) 'tt': testTotal,
        if (testMs != null) 'tm': testMs,
        if (testedAt != null) 'ta': testedAt!.toIso8601String(),
        if (testNote.isNotEmpty) 'tn': testNote,
      };

  static AiModelEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final p = aiProviderByName('${j['p']}');
    final m = '${j['m'] ?? ''}'.trim();
    if (p == null || m.isEmpty) return null;
    return AiModelEntry(
      provider: p,
      model: m,
      label: '${j['l'] ?? ''}',
      enabled: j['e'] != false,
      testScore: (j['ts'] as num?)?.toInt(),
      testTotal: (j['tt'] as num?)?.toInt(),
      testMs: (j['tm'] as num?)?.toInt(),
      testedAt: DateTime.tryParse('${j['ta'] ?? ''}'),
      testNote: '${j['tn'] ?? ''}',
    );
  }
}

/// الإعداد الكامل.
class AiModelsConfig {
  AiModelsConfig({
    required this.models,
    this.collaboration = true,
    this.readerId = '',
    this.matcherId = '',
  });

  /// بالأولوية: الأول يُجرَّب أولاً.
  final List<AiModelEntry> models;

  /// التعاون بين نموذجين: قارئ يستخرج الأسطر، ومطابِق يربطها بموادنا.
  bool collaboration;

  /// '' = تلقائي (حسب الترتيب).
  String readerId;
  String matcherId;

  /// الترتيب الافتراضي (يُختبر ويُعدَّل من الإعدادات). الأسماء الخاطئة أو غير المتاحة
  /// لحساب المستخدم يتخطاها البرنامج وحده (404) إلى ما بعدها.
  static List<AiModelEntry> defaults() => [
        AiModelEntry(provider: AiProvider.gemini, model: 'gemini-3.8-flash', label: 'Gemini 3.8 Flash'),
        AiModelEntry(provider: AiProvider.gemini, model: 'gemini-3.5-flash-lite', label: 'Gemini 3.5 Flash-Lite'),
        AiModelEntry(provider: AiProvider.gemini, model: 'gemini-2.5-flash', label: 'Gemini 2.5 Flash'),
        AiModelEntry(provider: AiProvider.gemini, model: 'gemini-flash-latest', label: 'Gemini Flash (أحدث)'),
        AiModelEntry(provider: AiProvider.groq, model: 'qwen/qwen3.8-27b', label: 'Qwen 3.8 27B (Groq)'),
        AiModelEntry(provider: AiProvider.openrouter, model: 'google/gemma-4-31b-it:free', label: 'Gemma 4 31B (مجاني)'),
        AiModelEntry(provider: AiProvider.openrouter, model: 'nvidia/nemotron-3.5-super-vl:free', label: 'Nemotron 3.5 Super VL (مجاني)'),
      ];

  AiModelEntry? byId(String id) {
    for (final m in models) {
      if (m.id == id) return m;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'models': [for (final m in models) m.toJson()],
        'collab': collaboration,
        'reader': readerId,
        'matcher': matcherId,
      };

  static AiModelsConfig fromJson(Object? j) {
    if (j is! Map) return AiModelsConfig(models: defaults());
    final list = j['models'];
    final models = <AiModelEntry>[
      if (list is List)
        for (final x in list)
          if (AiModelEntry.fromJson(x) != null) AiModelEntry.fromJson(x)!,
    ];
    return AiModelsConfig(
      models: models,
      collaboration: j['collab'] != false,
      readerId: '${j['reader'] ?? ''}',
      matcherId: '${j['matcher'] ?? ''}',
    );
  }
}

/// حفظ وتحميل الإعداد والمفاتيح.
class AiModelsStore {
  AiModelsStore._();

  static const _kCfg = 'ai_models_cfg_v1';
  static const _kKeys = 'ai_models_keys_v1';
  static const _secure = FlutterSecureStorage();

  /// للاختبارات: تخزين المفاتيح في الذاكرة بدل خزنة النظام.
  @visibleForTesting
  static Map<String, String>? memorySecureForTest;

  static AiModelsConfig? _cfg;
  static List<AiKey>? _keys;

  static Future<AiModelsConfig> config() async {
    if (_cfg != null) return _cfg!;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_kCfg);
      _cfg = raw == null || raw.isEmpty ? AiModelsConfig(models: AiModelsConfig.defaults()) : AiModelsConfig.fromJson(jsonDecode(raw));
    } catch (_) {
      _cfg = AiModelsConfig(models: AiModelsConfig.defaults());
    }
    return _cfg!;
  }

  static Future<void> saveConfig(AiModelsConfig c) async {
    _cfg = c;
    await (await SharedPreferences.getInstance()).setString(_kCfg, jsonEncode(c.toJson()));
  }

  static Future<String?> _readSecure() async {
    final mem = memorySecureForTest;
    if (mem != null) return mem[_kKeys];
    return _secure.read(key: _kKeys);
  }

  static Future<void> _writeSecure(String v) async {
    final mem = memorySecureForTest;
    if (mem != null) {
      mem[_kKeys] = v;
      return;
    }
    await _secure.write(key: _kKeys, value: v);
  }

  /// المفاتيح المحفوظة (بدون مفاتيح ‎.env).
  static Future<List<AiKey>> savedKeys() async {
    if (_keys != null) return List.of(_keys!);
    var out = <AiKey>[];
    try {
      final raw = await _readSecure();
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          out = [
            for (final x in list)
              if (AiKey.fromJson(x) != null) AiKey.fromJson(x)!,
          ];
        }
      }
    } catch (e) {
      debugPrint('⚠️ مفاتيح الذكاء الاصطناعي: $e');
    }
    _keys = out;
    return List.of(out);
  }

  static Future<void> _saveKeys(List<AiKey> keys) async {
    _keys = List.of(keys);
    await _writeSecure(jsonEncode([for (final k in keys) k.toJson()]));
  }

  /// يضيف مفتاحاً (المكرر لا يُضاف). يُرجع المفتاح المحفوظ.
  static Future<AiKey> addKey(AiProvider p, String key, {String label = ''}) async {
    final k = key.trim();
    final keys = await savedKeys();
    for (final x in keys) {
      if (x.provider == p && x.key == k) return x;
    }
    final rnd = Random().nextInt(1 << 30);
    final added = AiKey(id: '${DateTime.now().microsecondsSinceEpoch}_$rnd', provider: p, key: k, label: label.trim());
    await _saveKeys([...keys, added]);
    return added;
  }

  static Future<void> removeKey(String id) async {
    final keys = await savedKeys();
    keys.removeWhere((k) => k.id == id);
    await _saveKeys(keys);
  }

  /// مفاتيح Gemini القديمة من ملف ‎.env.
  static List<AiKey> envGeminiKeys() {
    final out = <AiKey>[];
    for (final n in const ['GEMINI_API_KEY', 'GEMINI_API_KEY_2', 'GEMINI_API_KEY_3', 'GEMINI_API_KEY_4']) {
      var v = '';
      try {
        v = (dotenv.env[n] ?? '').trim();
      } catch (_) {}
      if (v.isNotEmpty && !out.any((k) => k.key == v)) {
        out.add(AiKey(id: 'env_$n', provider: AiProvider.gemini, key: v, label: 'من ملف ‎.env', fromEnv: true));
      }
    }
    return out;
  }

  /// كل المفاتيح الصالحة للاستعمال، مجمّعة بالمزوّد. مفاتيح ‎.env تُستعمل لـ Gemini
  /// فقط إن لم يُضف مفتاح Gemini من الإعدادات.
  static Future<Map<AiProvider, List<AiKey>>> keysByProvider() async {
    final keys = await savedKeys();
    final out = <AiProvider, List<AiKey>>{for (final p in AiProvider.values) p: []};
    for (final k in keys) {
      out[k.provider]!.add(k);
    }
    if (out[AiProvider.gemini]!.isEmpty) out[AiProvider.gemini]!.addAll(envGeminiKeys());
    return out;
  }

  static Future<bool> hasAnyKey() async => (await keysByProvider()).values.any((l) => l.isNotEmpty);

  /// النماذج المفعّلة التي لمزوّدها مفتاح، بالترتيب.
  static Future<List<AiModelEntry>> usableChain() async {
    final cfg = await config();
    final keys = await keysByProvider();
    return [
      for (final m in cfg.models)
        if (m.enabled && (keys[m.provider]?.isNotEmpty ?? false)) m,
    ];
  }

  @visibleForTesting
  static void resetForTest() {
    _cfg = null;
    _keys = null;
  }
}
