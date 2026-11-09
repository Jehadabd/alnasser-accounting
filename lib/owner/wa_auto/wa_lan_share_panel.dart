// lib/owner/wa_auto/wa_lan_share_panel.dart
//
// 📱 (Windows) «مشاركة الخادم مع هواتف المحل»: الخادم على هذه الحاسبة يقبل طلبات الهواتف على
// نفس شبكة الواي فاي — كل طلب بمفتاح الخادم. يعرض رمز QR يمسحه الهاتف من
// «خادم واتساب ← خادم حاسبة المحل».

import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/settings_kit.dart';
import 'wa_local_server.dart';
import 'wa_pair_code.dart';
import 'wa_server_client.dart';

const _muted = Color(0xFF64748B);
const _amber = Color(0xFFB45309);

class WaLanSharePanel extends StatefulWidget {
  const WaLanSharePanel({super.key});
  @override
  State<WaLanSharePanel> createState() => _WaLanSharePanelState();
}

class _WaLanSharePanelState extends State<WaLanSharePanel> {
  bool? _on;
  bool _busy = false;
  List<String> _ips = const [];
  String? _ip;
  String? _key;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = await WaLocalServer.lanShared();
    final ips = await WaLocalServer.lanAddresses();
    final key = await WaServerClient.localKey();
    if (!mounted) return;
    setState(() {
      _on = on;
      _ips = ips;
      _ip = ips.contains(_ip) ? _ip : (ips.isEmpty ? null : ips.first);
      _key = key;
    });
  }

  Future<void> _toggle(bool v) async {
    if (v) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('مشاركة الخادم مع هواتف المحل'),
          content: const Text(
            '• يقبل الخادم طلبات الأجهزة على نفس شبكة المحل، بشرط مفتاح الخادم (داخل رمز QR).\n'
            '• من يحصل على الرمز وهو على شبكتك يستطيع الإرسال من رقم المحل — لا تعرضه لغير موظفيك.\n'
            '• سيسألك Windows مرة واحدة عن «جدار الحماية»: اختر «السماح» للشبكات الخاصة.\n'
            '• الهاتف يرسل فقط ما دام البرنامج مفتوحاً على هذه الحاسبة.',
            style: TextStyle(height: 1.7),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مشاركة')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await WaLocalServer.setLanShared(v);
    } catch (e) {
      _err = '$e';
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    if (on == null) return const SizedBox.shrink();
    final code = (_ip == null || _key == null) ? null : WaPairCode('http://$_ip:${WaLocalServer.port}', _key!).encode();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SetSwitch(
        title: 'مشاركة الخادم مع هواتف المحل (نفس الواي فاي)',
        subtitle: on ? 'الهواتف المربوطة ترسل عبر هذه الحاسبة' : 'الخادم لهذه الحاسبة فقط',
        value: on,
        onChanged: _busy ? null : _toggle,
      ),
      if (_err != null) Text(_err!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
      if (on) ...[
        const SizedBox(height: 8),
        if (_ips.isEmpty)
          const Text('لم يُعثر على عنوان شبكة محلية لهذه الحاسبة — تأكد أنها متصلة بشبكة المحل.',
              style: TextStyle(color: _amber, fontWeight: FontWeight.w700))
        else ...[
          if (_ips.length > 1)
            Wrap(spacing: 8, children: [
              const Text('عنوان الحاسبة:', style: TextStyle(color: _muted)),
              for (final ip in _ips)
                ChoiceChip(label: Text(ip), selected: _ip == ip, onSelected: (_) => setState(() => _ip = ip)),
            ]),
          const SizedBox(height: 10),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: SizedBox(width: 220, height: 220, child: CustomPaint(painter: _QrPainter(code!))),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'في الهاتف: الإعدادات ← رسائل واتساب للزبائن ← خادم واتساب ← «خادم حاسبة المحل» ← امسح الرمز.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 6),
          Align(
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) setToast(context, 'نُسخ رمز الربط — الصقه في الهاتف إن لم تعمل الكاميرا');
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('نسخ الرمز نصاً'),
            ),
          ),
          const Text(
            'إن غيّرت «مفتاح جديد» يتوقف ربط الهواتف: امسح الرمز الجديد في كل هاتف.',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
        ],
      ],
    ]);
  }
}

/// رمز QR مرسوم مباشرة (مكتبة barcode — بلا حزمة واجهة إضافية).
class _QrPainter extends CustomPainter {
  _QrPainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    final els = Barcode.qrCode(errorCorrectLevel: BarcodeQRCorrectionLevel.medium)
        .make(data, width: size.width, height: size.height);
    for (final e in els) {
      if (e is BarcodeBar && e.black) {
        // +0.5 تمنع خطوطاً بيضاء رفيعة بين المربعات
        canvas.drawRect(Rect.fromLTWH(e.left, e.top, e.width + 0.5, e.height + 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
