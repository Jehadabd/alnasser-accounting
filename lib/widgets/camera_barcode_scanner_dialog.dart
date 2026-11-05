// widgets/camera_barcode_scanner_dialog.dart
// نافذة كاشف الباركود عبر الكاميرا (للأجهزة المحمولة والأندرويد)
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraBarcodeScannerDialog extends StatefulWidget {
  final String title;
  const CameraBarcodeScannerDialog({
    super.key,
    this.title = 'مسح الباركود بالكاميرا',
  });

  /// فتح النافذة وإرجاع الباركود الممسوح
  static Future<String?> scan(BuildContext context, {String title = 'مسح الباركود بالكاميرا'}) {
    // 🪟 مكتبة الكاميرا لا تعمل على ويندوز ولينكس (كانت ترمي MissingPluginException):
    //    إدخال يدوي — وقارئ الباركود USB يكتب في الحقل مباشرة.
    final noCamera = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux);
    if (noCamera) return _manual(context);
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => CameraBarcodeScannerDialog(title: title),
    );
  }

  static Future<String?> _manual(BuildContext context) => showDialog<String>(
        context: context,
        barrierColor: const Color(0x660F172A),
        builder: (_) => const _ManualBarcodeDialog(),
      );

  @override
  State<CameraBarcodeScannerDialog> createState() => _CameraBarcodeScannerDialogState();
}

class _CameraBarcodeScannerDialogState extends State<CameraBarcodeScannerDialog> {
  late MobileScannerController _controller;
  bool _isScanned = false;
  bool _torchOn = false;
  final TextEditingController _manualController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? code = barcode.rawValue;
      if (code != null && code.trim().isNotEmpty) {
        setState(() => _isScanned = true);
        Navigator.pop(context, code.trim());
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 40,
        vertical: isMobile ? 24 : 40,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 580),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A), // Slate 900
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // App Bar Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF818CF8), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Torch Switch Button
                  IconButton(
                    tooltip: 'الفلاش',
                    icon: Icon(
                      _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                      color: _torchOn ? Colors.amberAccent : Colors.white60,
                    ),
                    onPressed: () {
                      _controller.toggleTorch();
                      setState(() => _torchOn = !_torchOn);
                    },
                  ),
                  // Close Dialog Button
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context, null),
                  ),
                ],
              ),
            ),

            // Camera Scanner View & Target Frame Overlay
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Live Camera Stream
                  ClipRRect(
                    borderRadius: BorderRadius.zero,
                    child: MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                      errorBuilder: (context, error, child) {
                        return Container(
                          color: const Color(0xFF0F172A),
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.videocam_off_rounded, color: Colors.redAccent, size: 48),
                              const SizedBox(height: 16),
                              const Text(
                                'تعذر فتح الكاميرا',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'تأكد من منح صلاحية استخدام الكاميرا للتطبيق.\n($error)',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Scanner Reticle Overlay Frame
                  Container(
                    width: 260,
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF818CF8), width: 2),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.15),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),

                  // Scanning Guideline Animation Text
                  Positioned(
                    bottom: 24,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.center_focus_weak_rounded, color: Colors.amberAccent, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'وجّه الكاميرا نحو الباركود بشكل مباشر',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Manual Entry Input Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        hintText: 'أو أدخل رقم الباركود يدويًا...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                        fillColor: const Color(0xFF0F172A),
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty) {
                          Navigator.pop(context, val.trim());
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      final val = _manualController.text.trim();
                      if (val.isNotEmpty) {
                        Navigator.pop(context, val);
                      }
                    },
                    child: const Text('تأكيد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// 🪟 الحاسبة: إدخال الباركود بالقارئ أو باليد — نافذة هادئة بخانة كبيرة واضحة.
class _ManualBarcodeDialog extends StatefulWidget {
  const _ManualBarcodeDialog();

  @override
  State<_ManualBarcodeDialog> createState() => _ManualBarcodeDialogState();
}

class _ManualBarcodeDialogState extends State<_ManualBarcodeDialog> {
  final _c = TextEditingController();

  static const _ink = Color(0xFF0F3460);
  static const _accent = Color(0xFF2563EB);
  static const _muted = Color(0xFF64748B);
  static const _line = Color(0xFFE3E8EF);

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() {
    final v = _c.text.trim();
    if (v.isEmpty) return;
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final has = _c.text.trim().isNotEmpty;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shadowColor: const Color(0x400F172A),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xFF2563EB), Color(0xFF0F3460)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [BoxShadow(color: Color(0x332563EB), blurRadius: 12, offset: Offset(0, 4))],
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('إدخال باركود', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
                    SizedBox(height: 2),
                    Text('امسح بالقارئ أو اكتب الرقم ثم Enter',
                        style: TextStyle(fontSize: 12.5, color: _muted)),
                  ]),
                ),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: _muted),
                ),
              ]),
              const SizedBox(height: 18),
              TextField(
                controller: _c,
                autofocus: true,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.done,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 2.5, color: _ink),
                decoration: InputDecoration(
                  hintText: '0000000000000',
                  hintStyle: const TextStyle(color: Color(0xFFCBD5E1), letterSpacing: 2.5, fontWeight: FontWeight.w600),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                  suffixIcon: has
                      ? IconButton(
                          tooltip: 'مسح',
                          onPressed: _c.clear,
                          icon: const Icon(Icons.backspace_outlined, size: 20, color: _muted),
                        )
                      : null,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _line, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _accent, width: 2),
                  ),
                ),
                onSubmitted: (_) => _done(),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: _accent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('الكاميرا غير متاحة على الحاسبة. قارئ الباركود الموصول يكتب هنا مباشرة.',
                        style: TextStyle(fontSize: 12, height: 1.45, color: _ink)),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: _muted,
                      side: const BorderSide(color: _line, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      backgroundColor: _ink,
                      disabledBackgroundColor: const Color(0xFFE2E8F0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    onPressed: has ? _done : null,
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text('موافق', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
