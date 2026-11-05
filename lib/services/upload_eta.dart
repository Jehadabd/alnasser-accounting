// lib/services/upload_eta.dart
//
// ⏱️ تقدير زمن «رفع البيانات» على هذا الجهاز، من قياس العمليات السابقة فعلاً:
//   • الضغط والتحقق: بالميلي ثانية لكل ميغا من ملف القاعدة (سرعة هذا الحاسوب).
//   • حجم الملف المضغوط: نسبة إلى حجم القاعدة (تتغير مع نوع البيانات).
//   • كل وجهة: زمن آخر رفع ناجح إليها، مقيساً على حجم الملف (سرعة الإنترنت إليها،
//     ومعه تقاريرها الثابتة كسجل الديون PDF).
//   • الفواتير: زمن الفاتورة الواحدة × عدد ما لم يُرسل بعد.
// أول مرة (بلا تاريخ) تُستعمل قيم افتراضية متحفّظة، ثم يتحسّن التقدير مع كل رفع.
// المتوسط متحرك (الأحدث وزنه أكبر) فيتبع تغيّر سرعة الإنترنت.

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'database_service.dart';
import 'upload_targets.dart';

class UploadEta {
  UploadEta._(this._m);
  final Map<String, double> _m;

  static const _key = 'upload_eta_v1';
  static const _mb = 1024.0 * 1024.0;

  // قيم أولى متحفّظة (تُستبدل بالقياس بعد أول رفع)
  static const _defBuildMsPerMb = 700.0; // ضغط XZ + فكّ للتحقق لكل ميغا من القاعدة
  static const _defRatio = 0.14; // المضغوط ÷ القاعدة
  static const _defUploadMsPerMb = 3000.0; // ~2.7 ميغابت/ث
  static const _defBaseMs = {
    UploadTargets.telegram: 5000.0, // + الملخص والتقارير
    UploadTargets.dropbox: 4000.0,
    UploadTargets.gdrive: 8000.0, // + سجل الديون PDF
    UploadTargets.discord: 3000.0,
  };
  static const _defInvoiceMs = 1500.0;

  static Future<UploadEta> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null) {
        final j = jsonDecode(raw);
        if (j is Map) {
          return UploadEta._({
            for (final e in j.entries)
              if (e.value is num) '${e.key}': (e.value as num).toDouble(),
          });
        }
      }
    } catch (_) {}
    return UploadEta._({});
  }

  Future<void> save() async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(_m));
    } catch (_) {}
  }

  /// حجم القاعدة الآن (الملف + ما في WAL).
  static Future<int> databaseBytes() async {
    try {
      final f = await DatabaseService().getDatabaseFile();
      var n = await f.length();
      final wal = File('${f.path}-wal');
      if (await wal.exists()) n += await wal.length();
      return n;
    } catch (_) {
      return 0;
    }
  }

  double? _v(String k) => _m[k];

  /// متوسط متحرك: أول قياس يُعتمد كما هو، وبعده الأحدث وزنه 40%.
  void _ema(String k, double v) {
    if (!v.isFinite || v < 0) return;
    final old = _m[k];
    _m[k] = old == null ? v : old * 0.6 + v * 0.4;
  }

  // ─────────────────────────── التقدير ───────────────────────────

  int estimateBuildMs(int dbBytes) => (dbBytes / _mb * (_v('build_ms_per_mb') ?? _defBuildMsPerMb)).round();

  int estimateCompressed(int dbBytes) => (dbBytes * (_v('ratio') ?? _defRatio)).round();

  /// زمن وجهة واحدة لملف بحجم [compressed]. ديسكورد مع تيليجرام = نسخة في الخلفية ⇒ صفر تقريباً.
  int estimateTargetMs(String target, int compressed, {required bool withTelegram}) {
    if (target == UploadTargets.discord && withTelegram) return 500;
    final base = _v('base_$target') ?? _defBaseMs[target] ?? 4000.0;
    final perMb = _v('upload_ms_per_mb_$target') ?? _defUploadMsPerMb;
    return (base + compressed / _mb * perMb).round();
  }

  int estimateInvoicesMs(int count) => (count * (_v('invoice_ms') ?? _defInvoiceMs)).round();

  // ─────────────────────────── التسجيل (بعد نجاح فقط) ───────────────────────────

  void recordBuild({required int dbBytes, required int ms, required int compressed}) {
    if (dbBytes <= 0) return;
    _ema('build_ms_per_mb', ms / (dbBytes / _mb));
    _ema('ratio', compressed / dbBytes);
  }

  /// [ms]: زمن الوجهة بلا الضغط وبلا الفواتير. يُقسم إلى ثابت (تقارير/اتصال) وزمن لكل ميغا:
  /// الثابت يبقى من تقديره السابق، والباقي يُنسب إلى حجم الملف (سرعة الإنترنت).
  void recordTarget(String target, {required int ms, required int compressed, required bool withTelegram}) {
    if (target == UploadTargets.discord && withTelegram) return;
    final mbs = compressed / _mb;
    final base = _v('base_$target') ?? _defBaseMs[target] ?? 4000.0;
    if (mbs >= 0.5 && ms > base) {
      _ema('upload_ms_per_mb_$target', (ms - base) / mbs);
    } else {
      // الملف صغير جداً أو الزمن أقل من الثابت: هذا الزمن هو الثابت فعلياً
      _ema('base_$target', ms.toDouble());
    }
  }

  void recordInvoices({required int count, required int ms}) {
    if (count <= 0) return;
    _ema('invoice_ms', ms / count);
  }
}
