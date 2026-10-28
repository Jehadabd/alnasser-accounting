// widgets/continuous_barcode_scanner.dart
// 📷 مسح مستمر بالكاميرا (أندرويد/آيفون): الكاميرا تبقى مفتوحة، وكل باركود يمر أمامها
// يُضاف فوراً إلى السلة. نفس الباركود لا يُعاد خلال ثانيتين (حتى لا تُضاف المادة مرتين
// وهي ما زالت أمام الكاميرا). التفضيل «إبقاء الكاميرا مفتوحة» محفوظ على الجهاز.
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// نتيجة إضافة باركود: null = نجح (والاسم في [name])، وإلا رسالة الخطأ
typedef ScanHandler = Future<({String? name, String? error})> Function(String code);

class ContinuousScanPrefs {
  static const _k = 'pos_camera_continuous';
  static bool get cameraAvailable =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  static Future<bool> get() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_k) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> set(bool v) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_k, v);
    } catch (_) {}
  }
}

class ContinuousBarcodeScanner extends StatefulWidget {
  const ContinuousBarcodeScanner({super.key, required this.onCode});
  final ScanHandler onCode;

  static Future<void> open(BuildContext context, ScanHandler onCode) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: const Color(0xFF0F172A),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        builder: (_) => FractionallySizedBox(heightFactor: 0.88, child: ContinuousBarcodeScanner(onCode: onCode)),
      );

  @override
  State<ContinuousBarcodeScanner> createState() => _ContinuousBarcodeScannerState();
}

class _Hit {
  _Hit(this.code, this.name, this.error);
  final String code;
  final String? name;
  final String? error;
}

class _ContinuousBarcodeScannerState extends State<ContinuousBarcodeScanner> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.normal, facing: CameraFacing.back);
  final _hits = <_Hit>[];
  final _recent = <String, DateTime>{};
  bool _busy = false;
  bool _torch = false;
  bool _keepOpen = true;

  @override
  void initState() {
    super.initState();
    ContinuousScanPrefs.get().then((v) {
      if (mounted) setState(() => _keepOpen = v);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_busy) return;
    String? code;
    for (final b in cap.barcodes) {
      final v = b.rawValue?.trim();
      if (v != null && v.isNotEmpty) {
        code = v;
        break;
      }
    }
    if (code == null) return;
    final now = DateTime.now();
    final last = _recent[code];
    if (last != null && now.difference(last) < const Duration(seconds: 2)) return;
    _recent[code] = now;
    _busy = true;
    try {
      final r = await widget.onCode(code);
      if (!mounted) return;
      if (r.error == null) {
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
      } else {
        HapticFeedback.heavyImpact();
      }
      setState(() => _hits.insert(0, _Hit(code!, r.name, r.error)));
      if (!_keepOpen && r.error == null) Navigator.pop(context);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ok = _hits.where((h) => h.error == null).length;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
          child: Row(children: [
            const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF818CF8)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(ok == 0 ? 'وجّه الكاميرا نحو الباركود' : 'أُضيف $ok إلى السلة',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            IconButton(
              tooltip: 'الفلاش',
              icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: _torch ? Colors.amberAccent : Colors.white60),
              onPressed: () {
                _controller.toggleTorch();
                setState(() => _torch = !_torch);
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('تم', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        SwitchListTile(
          dense: true,
          value: _keepOpen,
          activeThumbColor: const Color(0xFF34D399),
          title: const Text('إبقاء الكاميرا مفتوحة (مسح مستمر)', style: TextStyle(color: Colors.white)),
          subtitle: const Text('كل مادة تمر أمام الكاميرا تُضاف فوراً. أطفئه لتُغلق بعد كل مادة.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          onChanged: (v) {
            setState(() => _keepOpen = v);
            ContinuousScanPrefs.set(v);
          },
        ),
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(fit: StackFit.expand, children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                Center(
                  child: Container(
                    width: 250,
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF34D399), width: 3),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: _hits.isEmpty
              ? const Center(child: Text('ما تمسحه يظهر هنا', style: TextStyle(color: Colors.white38)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: _hits.length,
                  itemBuilder: (_, i) {
                    final h = _hits[i];
                    final good = h.error == null;
                    return ListTile(
                      dense: true,
                      leading: Icon(good ? Icons.check_circle_rounded : Icons.error_rounded,
                          color: good ? const Color(0xFF34D399) : const Color(0xFFF87171)),
                      title: Text(good ? (h.name ?? h.code) : (h.error ?? ''),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      subtitle: Text(h.code, textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.white38)),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
