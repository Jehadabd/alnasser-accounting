// widgets/camera_barcode_scanner_dialog.dart
// نافذة كاشف الباركود عبر الكاميرا (للأجهزة المحمولة والأندرويد)
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
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => CameraBarcodeScannerDialog(title: title),
    );
  }

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
              color: Colors.black.withOpacity(0.5),
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
                      color: const Color(0xFF4F46E5).withOpacity(0.2),
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
                          color: const Color(0xFF4F46E5).withOpacity(0.15),
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
                        color: Colors.black.withOpacity(0.7),
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
