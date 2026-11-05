// lib/widgets/camera_scan_button.dart
//
// 📷 زر المسح بالكاميرا (أندرويد/آيفون) لشاشات البيع: الكاشير، إنشاء فاتورة، تعديل فاتورة.
// طريقة العمل من الإعدادات (ScanSettings.cameraMode):
//   • ضغطة تشغيل وإيقاف: الكاميرا تبقى تقرأ كل ما يمر أمامها حتى يُضغط الزر مرة ثانية.
//   • اضغط مع الاستمرار: تقرأ ما دام الإصبع على الزر.
// الكاميرا في لوحة صغيرة أعلى الشاشة — الفاتورة تبقى ظاهرة، وكل مادة تُقرأ تظهر نتيجتها.
// الرمز نفسه لا يُقرأ مرتين خلال ثانية ونصف (وهو ما زال أمام الكاميرا).

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/barcode/scan_feedback.dart';
import '../services/barcode/scan_settings.dart';
import 'continuous_barcode_scanner.dart' show ScanHandler;

class CameraScanButton extends StatefulWidget {
  const CameraScanButton({super.key, required this.onCode, this.color = const Color(0xFF4F46E5)});

  final ScanHandler onCode;
  final Color color;

  /// الكاميرا متاحة على هذا الجهاز (المكتبة لا تعمل على ويندوز ولينكس).
  static bool get available =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  @override
  State<CameraScanButton> createState() => _CameraScanButtonState();
}

class _CameraScanButtonState extends State<CameraScanButton> {
  OverlayEntry? _entry;
  CameraScanMode _mode = ScanSettings.current.cameraMode;

  bool get _on => _entry != null;

  @override
  void initState() {
    super.initState();
    ScanSettings.ensureLoaded().then((s) {
      if (mounted) setState(() => _mode = s.cameraMode);
    });
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _start() {
    if (_on) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight + 6;
    _entry = OverlayEntry(
      builder: (_) => Positioned(
        top: top,
        left: 12,
        right: 12,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: _CameraPanel(onCode: widget.onCode, hold: _mode == CameraScanMode.hold, onClose: _stop),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
    setState(() {});
  }

  void _stop() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hold = _mode == CameraScanMode.hold;
    final icon = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _on ? widget.color : widget.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(_on ? Icons.qr_code_scanner_rounded : Icons.photo_camera_rounded,
          color: _on ? Colors.white : widget.color, size: 22),
    );
    return Semantics(
      button: true,
      label: hold ? 'اضغط مع الاستمرار للمسح بالكاميرا' : (_on ? 'إيقاف المسح بالكاميرا' : 'تشغيل المسح بالكاميرا'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: hold
            ? Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _start(),
                onPointerUp: (_) => _stop(),
                onPointerCancel: (_) => _stop(),
                child: icon,
              )
            : Tooltip(
                message: _on ? 'إيقاف المسح' : 'مسح بالكاميرا',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _on ? _stop() : _start(),
                  child: icon,
                ),
              ),
      ),
    );
  }
}

class _CameraPanel extends StatefulWidget {
  const _CameraPanel({required this.onCode, required this.hold, required this.onClose});
  final ScanHandler onCode;
  final bool hold;
  final VoidCallback onClose;

  @override
  State<_CameraPanel> createState() => _CameraPanelState();
}

class _CameraPanelState extends State<_CameraPanel> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.normal, facing: CameraFacing.back);
  final _recent = <String, DateTime>{};
  bool _busy = false;
  bool _torch = false;
  int _ok = 0;
  String? _last;
  bool _lastOk = true;

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
    final prev = _recent[code];
    if (prev != null && now.difference(prev) < const Duration(milliseconds: 1500)) return;
    _recent
      ..removeWhere((_, t) => now.difference(t) > const Duration(seconds: 10))
      ..[code] = now;
    _busy = true;
    try {
      final r = await widget.onCode(code);
      if (r.error == null) {
        ScanFeedback.ok();
      } else {
        ScanFeedback.fail();
      }
      if (!mounted) return;
      setState(() {
        if (r.error == null) _ok++;
        _lastOk = r.error == null;
        _last = r.error ?? '✓ ${r.name ?? code}';
      });
    } catch (e) {
      ScanFeedback.fail();
      if (mounted) {
        setState(() {
          _lastOk = false;
          _last = 'تعذّرت الإضافة: $e';
        });
      }
    } finally {
      _recent[code] = DateTime.now(); // المهلة تبدأ بعد انتهاء الإضافة
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0F172A),
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 2),
            child: Row(children: [
              const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF818CF8), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.hold
                      ? 'يقرأ ما دمت ضاغطاً${_ok > 0 ? ' • أُضيف $_ok' : ''}'
                      : (_ok == 0 ? 'وجّه الكاميرا نحو الباركود' : 'أُضيف $_ok — يستمر حتى تُوقفه'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
              IconButton(
                tooltip: 'الفلاش',
                visualDensity: VisualDensity.compact,
                icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: _torch ? Colors.amberAccent : Colors.white60, size: 20),
                onPressed: () {
                  _controller.toggleTorch();
                  setState(() => _torch = !_torch);
                },
              ),
              if (!widget.hold)
                IconButton(
                  tooltip: 'إيقاف',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                  onPressed: widget.onClose,
                ),
            ]),
          ),
          SizedBox(
            height: 170,
            child: Stack(fit: StackFit.expand, children: [
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error, child) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('تعذّر فتح الكاميرا — امنح التطبيق صلاحية الكاميرا.\n($error)',
                        textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.5)),
                  ),
                ),
              ),
              IgnorePointer(
                child: Center(
                  child: Container(
                    width: 230,
                    height: 110,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF34D399), width: 2.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Container(
              key: ValueKey(_last),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: _last == null
                  ? Colors.transparent
                  : (_lastOk ? const Color(0xFF065F46) : const Color(0xFF7F1D1D)),
              child: Text(_last ?? 'ما تمسحه يُضاف إلى الفاتورة مباشرة',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _last == null ? Colors.white38 : Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}
