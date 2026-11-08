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

  /// الجزء الثابت لوجهة (اتصال، تقارير، تأكيد) بلا رفع الملف نفسه.
  int baseMs(String target, {required bool withTelegram}) {
    if (target == UploadTargets.discord && withTelegram) return 500;
    return (_v('base_$target') ?? _defBaseMs[target] ?? 4000.0).round();
  }

  /// زمن رفع [bytes] إلى [target] فقط: بسرعة مقيسة الآن [liveBytesPerSec] إن وُجدت، وإلا من التاريخ.
  int uploadMs(String target, int bytes, {required bool withTelegram, double? liveBytesPerSec}) {
    if (target == UploadTargets.discord && withTelegram) return 0;
    if (liveBytesPerSec != null && liveBytesPerSec > 0) return (bytes / liveBytesPerSec * 1000).round();
    return (bytes / _mb * (_v('upload_ms_per_mb_$target') ?? _defUploadMsPerMb)).round();
  }

  // ─────────────────────────── التسجيل (بعد نجاح فقط) ───────────────────────────

  void recordBuild({required int dbBytes, required int ms, required int compressed}) {
    if (dbBytes <= 0) return;
    _ema('build_ms_per_mb', ms / (dbBytes / _mb));
    _ema('ratio', compressed / dbBytes);
  }

  /// [ms]: زمن الوجهة بلا الضغط وبلا الفواتير. يُقسم إلى ثابت (تقارير/اتصال) وزمن لكل ميغا:
  /// الثابت يبقى من تقديره السابق، والباقي يُنسب إلى حجم الملف (سرعة الإنترنت).
  void recordTarget(String target,
      {required int ms, required int compressed, required bool withTelegram, int? netMs}) {
    if (target == UploadTargets.discord && withTelegram) return;
    final mbs = compressed / _mb;
    if (netMs != null && netMs > 0 && mbs > 0) {
      // قياس مباشر: زمن خروج الملف نفسه، والباقي هو الثابت
      _ema('upload_ms_per_mb_$target', netMs / mbs);
      _ema('base_$target', (ms - netMs).clamp(0, 1 << 31).toDouble());
      return;
    }
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

/// 📡 خطة عملية «رفع البيانات» الجارية: ما انتهى، وما يجري الآن بقياس حيّ، وما بقي بتقدير.
/// الوقت المتبقي = (الجاري: من سرعته الفعلية الآن) + (الباقي: بسرعة الإنترنت المقيسة في
/// هذه العملية نفسها إن وُجدت، وإلا من الرفعات السابقة).
class UploadPlan {
  UploadPlan({
    required this.eta,
    required this.targets,
    required this.dbBytes,
    required this.withTelegram,
    required int pendingInvoices,
  })  : compressed = eta.estimateCompressed(dbBytes),
        _invoices = pendingInvoices;

  final UploadEta eta;
  final List<String> targets;
  final int dbBytes;
  final bool withTelegram;

  /// حجم الملف المضغوط: تقدير، ثم الحجم الفعلي بعد الصنع.
  int compressed;
  int _invoices; // فواتير منتظرة لم يبدأ إرسالها

  // الصنع
  bool buildDone = false;
  DateTime? _buildStart;
  double _buildFrac = 0;

  // الوجهة الجارية
  int _index = -1;
  bool _uploaded = false; // انتهى خروج الملف إلى الوجهة الجارية
  DateTime? _uploadedAt;

  // الشبكة
  DateTime? _netStart;
  int _netTotal = 0;
  int _netSent = 0;
  DateTime _lastNetChange = DateTime.now();
  final List<(DateTime, int)> _samples = [];
  double? _lastNetRate; // متوسط آخر رفع اكتمل في هذه العملية (بايت/ث)

  // الفواتير
  DateTime? _invStart;
  int _invTotal = 0;
  int _invDone = 0;

  // ─── الأحداث ───

  void startTarget(int index) {
    _index = index;
    _uploaded = false;
    _uploadedAt = null;
    _netStart = null;
  }

  void buildProgress(double p) {
    _buildStart ??= DateTime.now();
    _buildFrac = p.clamp(0.0, 1.0);
    if (p >= 1.0) buildDone = true;
  }

  void buildFinished(int compressedBytes) {
    buildDone = true;
    compressed = compressedBytes;
  }

  /// ما خرج من الملف إلى الوجهة الجارية.
  void sent(int done, int total) {
    final now = DateTime.now();
    if (_netStart == null || done < _netSent) {
      _netStart = now;
      _samples.clear();
      _netSent = 0;
      _lastNetChange = now;
    }
    _netTotal = total;
    if (done != _netSent) _lastNetChange = now;
    _netSent = done;
    _samples.add((now, done));
    // نافذة 8 ثوانٍ تكفي لتتبع التغيّر دون قفز
    while (_samples.length > 2 && now.difference(_samples.first.$1).inMilliseconds > 8000) {
      _samples.removeAt(0);
    }
    if (total > 0 && done >= total) {
      final ms = now.difference(_netStart!).inMilliseconds;
      if (ms > 300) _lastNetRate = total / ms * 1000;
      _uploaded = true;
      _uploadedAt = now;
    }
  }

  void invoicesProgress(int done, int total) {
    _invStart ??= DateTime.now();
    _invTotal = total;
    _invDone = done;
  }

  void invoicesKnown(int count) => _invoices = count;

  void endTarget() {
    if (_index >= 0 && _index < targets.length && targets[_index] == UploadTargets.telegram) {
      _invoices = 0;
      _invStart = null;
    }
  }

  // ─── القياس ───

  /// سرعة الرفع الآن (بايت/ث) من آخر 8 ثوانٍ، أو null إن كانت المدة أقصر من أن تُقاس.
  double? get liveRate {
    if (_netStart == null || _samples.length < 2) return null;
    final a = _samples.first, b = _samples.last;
    final ms = b.$1.difference(a.$1).inMilliseconds;
    if (ms < 1500) return null;
    return (b.$2 - a.$2) / ms * 1000;
  }

  /// الرفع الجاري لم يتقدّم منذ 6 ثوانٍ (انقطاع أو بطء شديد).
  bool get stalled =>
      _netStart != null && !_uploaded && DateTime.now().difference(_lastNetChange).inMilliseconds > 6000;

  /// أفضل سرعة لتقدير ما بقي: الحية، ثم آخر رفع في هذه العملية، ثم التاريخ (null).
  double? get _bestRate {
    final l = liveRate;
    if (l != null && l > 0) return l;
    return _lastNetRate;
  }

  /// الوقت المتبقي، أو null إن كان الرفع متوقفاً (لا يمكن التقدير).
  Duration? remaining() {
    final now = DateTime.now();
    if (stalled) return null;
    var ms = 0.0;

    // 1) الصنع (ضغط + تحقق)
    if (!buildDone) {
      final st = _buildStart;
      final el = st == null ? 0 : now.difference(st).inMilliseconds;
      if (st != null && _buildFrac > 0.05 && el > 1500) {
        ms += el * (1 - _buildFrac) / _buildFrac;
      } else {
        ms += (eta.estimateBuildMs(dbBytes) - el).clamp(0, 1 << 31);
      }
    }

    // 2) الوجهة الجارية
    if (_index >= 0 && _index < targets.length) {
      final t = targets[_index];
      final base = eta.baseMs(t, withTelegram: withTelegram);
      if (!_uploaded) {
        if (_netStart != null && _netTotal > 0) {
          final r = liveRate;
          final left = _netTotal - _netSent;
          ms += r != null && r > 0
              ? left / r * 1000
              : eta.uploadMs(t, left, withTelegram: withTelegram, liveBytesPerSec: _lastNetRate);
        } else {
          ms += eta.uploadMs(t, compressed, withTelegram: withTelegram, liveBytesPerSec: _bestRate);
        }
        ms += base;
      } else {
        // بعد خروج الملف: التقارير والتأكيد (الثابت) — لا يقل عن 10% منه ما دامت الوجهة جارية
        final since = now.difference(_uploadedAt ?? now).inMilliseconds;
        ms += (base - since).clamp(base * 0.1, base.toDouble());
      }
      if (t == UploadTargets.telegram) {
        if (_invStart != null && _invTotal > 0) {
          final el = now.difference(_invStart!).inMilliseconds;
          ms += _invDone > 0 && el > 1500
              ? el * (_invTotal - _invDone) / _invDone
              : eta.estimateInvoicesMs(_invTotal - _invDone);
        } else {
          ms += eta.estimateInvoicesMs(_invoices);
        }
      }
    }

    // 3) الوجهات التالية
    for (var j = _index + 1; j < targets.length; j++) {
      final t = targets[j];
      ms += eta.baseMs(t, withTelegram: withTelegram) +
          eta.uploadMs(t, compressed, withTelegram: withTelegram, liveBytesPerSec: _bestRate);
      if (t == UploadTargets.telegram) ms += eta.estimateInvoicesMs(_invoices);
    }
    return Duration(milliseconds: ms.round());
  }
}
