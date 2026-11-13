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

/// 📷 حجم مربع الكاميرا في شاشات البيع.
enum CameraBoxSize {
  small('صغير', 300, 120),
  medium('متوسط', 460, 170),
  large('كبير', 640, 260);

  const CameraBoxSize(this.label, this.maxWidth, this.previewHeight);
  final String label;
  final double maxWidth;
  final double previewHeight;
}

/// 📍 مكان مربع الكاميرا على الشاشة.
enum CameraBoxPosition {
  topRight('أعلى اليمين', 1, -1),
  topCenter('أعلى الوسط', 0, -1),
  topLeft('أعلى اليسار', -1, -1),
  bottomRight('أسفل اليمين', 1, 1),
  bottomCenter('أسفل الوسط', 0, 1),
  bottomLeft('أسفل اليسار', -1, 1);

  const CameraBoxPosition(this.label, this.x, this.y);
  final String label;

  /// موضعه في الشاشة (Alignment مطلق): x من ‎-1 (يسار) إلى 1 (يمين)، y من ‎-1 (أعلى) إلى 1 (أسفل).
  final double x;
  final double y;
}

class ScanSettings {
  const ScanSettings({
    this.keyboardScanner = true,
    this.maxGapMs = defaultGapMs,
    this.minLength = defaultMinLength,
    this.repeatAddsQty = true,
    this.cameraMode = CameraScanMode.toggle,
    this.sound = true,
    this.cameraAutoOpen = false,
    this.cameraBoxSize = CameraBoxSize.medium,
    this.cameraBoxPosition = CameraBoxPosition.topCenter,
    this.cameraHidePreview = false,
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

  // 📷 مربع الكاميرا في شاشات البيع (الكاشير والفاتورة) — أندرويد/آيفون
  /// يُفتح المربع تلقائياً عند دخول شاشة البيع ويبقى يقرأ (يُغلق من زره).
  final bool cameraAutoOpen;
  final CameraBoxSize cameraBoxSize;
  final CameraBoxPosition cameraBoxPosition;

  /// «تمرير فقط»: الكاميرا تقرأ دون عرض صورتها (شريط صغير يبيّن أنها تعمل وما أُضيف).
  final bool cameraHidePreview;

  static const _kWedge = 'scan_keyboard_wedge_v1';
  static const _kGap = 'scan_max_gap_ms_v1';
  static const _kMin = 'scan_min_length_v1';
  static const _kRepeat = 'scan_repeat_adds_qty_v1';
  static const _kCam = 'scan_camera_mode_v1';
  static const _kSound = 'scan_sound_v1';
  static const _kCamAuto = 'scan_camera_auto_open_v1';
  static const _kCamSize = 'scan_camera_box_size_v1';
  static const _kCamPos = 'scan_camera_box_pos_v1';
  static const _kCamHide = 'scan_camera_hide_preview_v1';

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
        cameraAutoOpen: p.getBool(_kCamAuto) ?? false,
        cameraBoxSize: CameraBoxSize.values
            .firstWhere((v) => v.name == p.getString(_kCamSize), orElse: () => CameraBoxSize.medium),
        cameraBoxPosition: CameraBoxPosition.values
            .firstWhere((v) => v.name == p.getString(_kCamPos), orElse: () => CameraBoxPosition.topCenter),
        cameraHidePreview: p.getBool(_kCamHide) ?? false,
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
    await p.setBool(_kCamAuto, v.cameraAutoOpen);
    await p.setString(_kCamSize, v.cameraBoxSize.name);
    await p.setString(_kCamPos, v.cameraBoxPosition.name);
    await p.setBool(_kCamHide, v.cameraHidePreview);
  }

  ScanSettings copyWith({
    bool? keyboardScanner,
    int? maxGapMs,
    int? minLength,
    bool? repeatAddsQty,
    CameraScanMode? cameraMode,
    bool? sound,
    bool? cameraAutoOpen,
    CameraBoxSize? cameraBoxSize,
    CameraBoxPosition? cameraBoxPosition,
    bool? cameraHidePreview,
  }) =>
      ScanSettings(
        keyboardScanner: keyboardScanner ?? this.keyboardScanner,
        maxGapMs: maxGapMs ?? this.maxGapMs,
        minLength: minLength ?? this.minLength,
        repeatAddsQty: repeatAddsQty ?? this.repeatAddsQty,
        cameraMode: cameraMode ?? this.cameraMode,
        sound: sound ?? this.sound,
        cameraAutoOpen: cameraAutoOpen ?? this.cameraAutoOpen,
        cameraBoxSize: cameraBoxSize ?? this.cameraBoxSize,
        cameraBoxPosition: cameraBoxPosition ?? this.cameraBoxPosition,
        cameraHidePreview: cameraHidePreview ?? this.cameraHidePreview,
      );
}
