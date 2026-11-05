// lib/services/barcode/scan_settings.dart
//
// ⚙️ إعدادات قراءة الباركود — إعداد لهذا الجهاز (الماسح والكاميرا من عتاد الجهاز):
//   • قارئ الباركود (USB/بلوتوث أو المدمج في أجهزة الكاشير) يعمل كلوحة مفاتيح سريعة:
//     يُلتقط على مستوى الشاشة كلها دون الحاجة لخانة الباركود.
//   • الكاميرا (أندرويد/آيفون): «ضغطة تشغيل وإيقاف» أو «اضغط مع الاستمرار».
//   • تكرار مسح المادة نفسها يزيد كميتها بدل سطر جديد (كأنظمة نقاط البيع).

import 'package:shared_preferences/shared_preferences.dart';

enum CameraScanMode {
  toggle('ضغطة تشغيل وإيقاف', 'اضغط الزر مرة: الكاميرا تبقى تقرأ كل ما يمر أمامها حتى تضغطه مرة ثانية.'),
  hold('اضغط مع الاستمرار', 'الكاميرا تقرأ ما دام إصبعك على الزر، وتتوقف حين ترفعه.');

  const CameraScanMode(this.label, this.help);
  final String label;
  final String help;
}

class ScanSettings {
  const ScanSettings({
    this.keyboardScanner = true,
    this.maxGapMs = defaultGapMs,
    this.minLength = defaultMinLength,
    this.repeatAddsQty = true,
    this.cameraMode = CameraScanMode.toggle,
    this.sound = true,
  });

  static const int defaultGapMs = 40;
  static const int defaultMinLength = 4;
  static const int minGapMs = 15;
  static const int maxGapMsLimit = 120;

  /// التقاط القارئ في أي مكان من الشاشة.
  final bool keyboardScanner;

  /// أقصى زمن بين حرفين ليُعدّ الإدخال من القارئ (ملّي ثانية).
  final int maxGapMs;

  /// أقل طول للرمز المقروء.
  final int minLength;

  /// مسح مادة موجودة في الفاتورة بالوحدة نفسها يزيد كميتها 1.
  final bool repeatAddsQty;

  final CameraScanMode cameraMode;

  /// صوت عند النجاح والفشل.
  final bool sound;

  static const _kWedge = 'scan_keyboard_wedge_v1';
  static const _kGap = 'scan_max_gap_ms_v1';
  static const _kMin = 'scan_min_length_v1';
  static const _kRepeat = 'scan_repeat_adds_qty_v1';
  static const _kCam = 'scan_camera_mode_v1';
  static const _kSound = 'scan_sound_v1';

  /// الإعداد المحمّل (يُقرأ مرة ويُحدَّث عند الحفظ).
  static ScanSettings current = const ScanSettings();
  static bool _loaded = false;

  static int clampGap(int v) => v.clamp(minGapMs, maxGapMsLimit).toInt();
  static int clampMin(int v) => v.clamp(2, 32).toInt();

  static Future<ScanSettings> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final cam = p.getString(_kCam);
      current = ScanSettings(
        keyboardScanner: p.getBool(_kWedge) ?? true,
        maxGapMs: clampGap(p.getInt(_kGap) ?? defaultGapMs),
        minLength: clampMin(p.getInt(_kMin) ?? defaultMinLength),
        repeatAddsQty: p.getBool(_kRepeat) ?? true,
        cameraMode: CameraScanMode.values.firstWhere((m) => m.name == cam, orElse: () => CameraScanMode.toggle),
        sound: p.getBool(_kSound) ?? true,
      );
    } catch (_) {}
    _loaded = true;
    return current;
  }

  static Future<ScanSettings> ensureLoaded() {
    if (_loaded) return Future.value(current);
    return load();
  }

  static Future<void> save(ScanSettings s) async {
    final v = s.copyWith(maxGapMs: clampGap(s.maxGapMs), minLength: clampMin(s.minLength));
    current = v;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kWedge, v.keyboardScanner);
    await p.setInt(_kGap, v.maxGapMs);
    await p.setInt(_kMin, v.minLength);
    await p.setBool(_kRepeat, v.repeatAddsQty);
    await p.setString(_kCam, v.cameraMode.name);
    await p.setBool(_kSound, v.sound);
  }

  ScanSettings copyWith({
    bool? keyboardScanner,
    int? maxGapMs,
    int? minLength,
    bool? repeatAddsQty,
    CameraScanMode? cameraMode,
    bool? sound,
  }) =>
      ScanSettings(
        keyboardScanner: keyboardScanner ?? this.keyboardScanner,
        maxGapMs: maxGapMs ?? this.maxGapMs,
        minLength: minLength ?? this.minLength,
        repeatAddsQty: repeatAddsQty ?? this.repeatAddsQty,
        cameraMode: cameraMode ?? this.cameraMode,
        sound: sound ?? this.sound,
      );
}
