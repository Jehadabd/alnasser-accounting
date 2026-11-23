// lib/lan/shop_hotspot_card.dart
//
// 📶 بطاقتا «شبكة المتجر بلا راوتر» في إعدادات الشبكة (shop_hotspot.dart):
//   • ShopHotspotServerCard (السيرفر): يشغّل الشبكة ويعرض رمز QR فيه اسمها وكلمة سرها
//     وعنوان السيرفر ومنفذه ورمز الربط.
//   • ShopHotspotJoinCard (الطرفية): يمسح الرمز ⇒ ينضم للشبكة ويملأ بيانات الاتصال.

import 'dart:io';

import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/camera_barcode_scanner_dialog.dart';
import 'shop_hotspot.dart';

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);
const _bg = Color(0xFFF5F7FB);
const _teal = Color(0xFF0D9488);
const _indigo = Color(0xFF4F46E5);
const _red = Color(0xFFDC2626);

// ═════════════════════════════ السيرفر ═════════════════════════════

class ShopHotspotServerCard extends StatefulWidget {
  const ShopHotspotServerCard({super.key, required this.port, required this.secret});
  final int port;
  final String secret;
  @override
  State<ShopHotspotServerCard> createState() => _ShopHotspotServerCardState();
}

class _ShopHotspotServerCardState extends State<ShopHotspotServerCard> {
  final _ssid = TextEditingController();
  final _pass = TextEditingController();
  ShopNet? _net;
  bool _busy = false;
  String? _err;
  List<String> _ips = const [];
  String? _ip;
  bool _systemMode = false; // Android: نقطة اتصال النظام (اسم ثابت)

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _ssid.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final (s, p) = await ShopHotspot.savedCredentials();
    _ssid.text = s;
    _pass.text = p;
    ShopNet? cur;
    try {
      if (Platform.isWindows) {
        if (await ShopHotspot.windowsRunning() == true) cur = ShopNet(ssid: s, password: p);
      } else if (Platform.isAndroid) {
        cur = await ShopHotspot.androidLocalInfo();
      }
    } catch (_) {}
    await _refreshIps();
    if (mounted) setState(() => _net = cur);
  }

  Future<void> _refreshIps() async {
    final ips = await ShopHotspot.addresses();
    if (!mounted) return;
    setState(() {
      _ips = ips;
      _ip = ips.contains(_ip) ? _ip : (ips.isEmpty ? null : ips.first);
    });
  }

  Future<void> _run(Future<ShopNet?> Function() job) async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final n = await job();
      // عنوان الشبكة الجديدة يظهر بعد ثوانٍ من تشغيلها
      for (var i = 0; i < 6; i++) {
        await _refreshIps();
        if (_ips.isNotEmpty) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (mounted) setState(() => _net = n);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (Platform.isWindows) {
      if (_ssid.text.trim().isEmpty || _pass.text.length < 8) {
        setState(() => _err = 'اسم الشبكة مطلوب، وكلمة السر 8 أحرف على الأقل.');
        return;
      }
      await _run(() => ShopHotspot.startWindows(ssid: _ssid.text.trim(), password: _pass.text));
    } else {
      await _run(ShopHotspot.startAndroidLocal);
    }
  }

  Future<void> _stop() async {
    await _run(() async {
      if (Platform.isWindows) {
        await ShopHotspot.stopWindows();
      } else {
        await ShopHotspot.stopAndroidLocal();
      }
      return null;
    });
  }

  Future<void> _useSystemHotspot() async {
    if (_ssid.text.trim().isEmpty || _pass.text.length < 8) {
      setState(() => _err = 'اكتب اسم نقطة الاتصال وكلمة سرها كما في إعدادات النظام (8 أحرف على الأقل).');
      return;
    }
    await ShopHotspot.saveCredentials(_ssid.text.trim(), _pass.text);
    await _run(() async => ShopNet(ssid: _ssid.text.trim(), password: _pass.text));
  }

  @override
  Widget build(BuildContext context) {
    if (!ShopHotspot.supported) return const SizedBox.shrink();
    final net = _net;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(
          'شبكة المتجر — بلا راوتر',
          net == null ? 'هذا الجهاز يبث Wi-Fi وتنضم إليه الأجهزة الأخرى' : 'تعمل الآن: «${net.ssid}»',
          net == null ? Icons.wifi_tethering_off_rounded : Icons.wifi_tethering_rounded,
          net == null ? _indigo : _teal,
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: net == null ? _setup() : _running(net),
          ),
        ),
      ]),
    );
  }

  Widget _setup() {
    return Column(key: const ValueKey('setup'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (Platform.isWindows) ...[
        _credFields(),
        const SizedBox(height: 10),
        _note('يحتاج بطاقة Wi-Fi في الحاسوب. Windows يشترط أن يكون الحاسوب متصلاً بأي شبكة يشاركها (ولو بلا إنترنت).'),
        const SizedBox(height: 12),
        _primary('شغّل شبكة المتجر', Icons.wifi_tethering_rounded, _start),
      ] else ...[
        _choice(
          icon: Icons.bolt_rounded,
          title: 'شبكة التطبيق — ضغطة واحدة',
          text: 'يشغّلها التطبيق فوراً. Android يختار اسماً وكلمة سر جديدين كل مرة، وتنطفئ إذا أُغلق التطبيق.',
          selected: !_systemMode,
          onTap: () => setState(() => _systemMode = false),
        ),
        const SizedBox(height: 8),
        _choice(
          icon: Icons.settings_input_antenna_rounded,
          title: 'نقطة اتصال النظام — اسم ثابت',
          text: 'تشغّلها من إعدادات Android مرة؛ اسمها لا يتغير ولا تنطفئ مع التطبيق، والأجهزة تتذكرها.',
          selected: _systemMode,
          onTap: () => setState(() => _systemMode = true),
        ),
        const SizedBox(height: 12),
        if (!_systemMode)
          _primary('شغّل شبكة التطبيق', Icons.wifi_tethering_rounded, _start)
        else ...[
          OutlinedButton.icon(
            onPressed: ShopHotspot.openSystemHotspotSettings,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('1. افتح إعدادات نقطة الاتصال وشغّلها'),
          ),
          const SizedBox(height: 10),
          const Text('2. اكتب اسمها وكلمة سرها كما تظهر هناك:', style: TextStyle(fontWeight: FontWeight.w700, color: _ink)),
          const SizedBox(height: 8),
          _credFields(),
          const SizedBox(height: 12),
          _primary('3. اعرض رمز الربط', Icons.qr_code_2_rounded, _useSystemHotspot),
        ],
      ],
      if (_err != null) ...[
        const SizedBox(height: 10),
        Text(_err!, style: const TextStyle(color: _red, fontWeight: FontWeight.w700, height: 1.5)),
      ],
    ]);
  }

  Widget _running(ShopNet net) {
    final code = ShopNet(ssid: net.ssid, password: net.password, host: _ip, port: widget.port, secret: widget.secret).toCode();
    return Column(key: const ValueKey('running'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 520;
        final qr = Container(
          width: 210,
          height: 210,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _line)),
          child: _ip == null
              ? const Center(child: Text('بانتظار عنوان الشبكة…', textAlign: TextAlign.center, style: TextStyle(color: _muted)))
              : CustomPaint(painter: _QrPainter(code)),
        );
        final info = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _fact(Icons.wifi_rounded, 'اسم الشبكة', net.ssid),
          _fact(Icons.key_rounded, 'كلمة السر', net.password),
          if (_ips.length > 1)
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final ip in _ips)
                ChoiceChip(
                  label: Text(ip, textDirection: TextDirection.ltr),
                  selected: ip == _ip,
                  onSelected: (_) => setState(() => _ip = ip),
                ),
            ])
          else
            _fact(Icons.dns_rounded, 'عنوان السيرفر', _ip ?? '—'),
          const SizedBox(height: 8),
          _note('على كل جهاز آخر: إعدادات الشبكة ← «طرفية» ← «امسح رمز شبكة المتجر».'),
        ]);
        return wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [qr, const SizedBox(width: 16), Expanded(child: info)])
            : Column(children: [qr, const SizedBox(height: 12), info]);
      }),
      const SizedBox(height: 12),
      Row(children: [
        TextButton.icon(onPressed: _refreshIps, icon: const Icon(Icons.refresh_rounded), label: const Text('تحديث العنوان')),
        const Spacer(),
        if (Platform.isWindows || !_systemMode)
          OutlinedButton.icon(
            onPressed: _busy ? null : _stop,
            style: OutlinedButton.styleFrom(foregroundColor: _red),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('أطفئ الشبكة'),
          )
        else
          OutlinedButton.icon(
            onPressed: () => setState(() => _net = null),
            icon: const Icon(Icons.edit_rounded),
            label: const Text('تعديل'),
          ),
      ]),
      if (_err != null) Text(_err!, style: const TextStyle(color: _red, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _credFields() => Row(children: [
        Expanded(
          child: TextField(
            controller: _ssid,
            textDirection: TextDirection.ltr,
            decoration: _dec('اسم الشبكة', Icons.wifi_rounded),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _pass,
            textDirection: TextDirection.ltr,
            decoration: _dec('كلمة السر (8+)', Icons.key_rounded),
          ),
        ),
      ]);

  Widget _primary(String label, IconData icon, VoidCallback onTap) => FilledButton.icon(
        onPressed: _busy ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: _indigo,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      );

  Widget _choice({required IconData icon, required String title, required String text, required bool selected, required VoidCallback onTap}) =>
      InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? _indigo.withValues(alpha: 0.07) : _bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? _indigo : Colors.transparent, width: 1.6),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: selected ? _indigo : _muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? _indigo : _ink)),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.45)),
              ]),
            ),
          ]),
        ),
      );

  Widget _fact(IconData i, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(i, size: 19, color: _muted),
          const SizedBox(width: 8),
          SizedBox(width: 92, child: Text(label, style: const TextStyle(color: _muted))),
          Expanded(
            child: SelectableText(value, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
          ),
          IconButton(
            tooltip: 'نسخ',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
          ),
        ]),
      );
}

// ═════════════════════════════ الطرفية ═════════════════════════════

class ShopHotspotJoinCard extends StatefulWidget {
  const ShopHotspotJoinCard({super.key, required this.onJoined});

  /// بعد مسح الرمز (والانضمام): عنوان السيرفر والمنفذ ورمز الربط.
  final void Function(ShopNet net) onJoined;
  @override
  State<ShopHotspotJoinCard> createState() => _ShopHotspotJoinCardState();
}

class _ShopHotspotJoinCardState extends State<ShopHotspotJoinCard> {
  bool _busy = false;
  String? _msg;
  bool _ok = false;
  ShopNet? _last;

  @override
  void initState() {
    super.initState();
    ShopHotspot.lastJoined().then((n) {
      if (mounted) setState(() => _last = n);
    });
  }

  Future<void> _scan() async {
    final raw = await CameraBarcodeScannerDialog.scan(context, title: 'امسح رمز شبكة المتجر من شاشة السيرفر');
    if (raw == null || !mounted) return;
    final n = ShopNet.parse(raw);
    if (n == null) {
      setState(() {
        _ok = false;
        _msg = 'هذا ليس رمز شبكة المتجر — افتح «شبكة المتجر» على جهاز السيرفر وامسح رمزه.';
      });
      return;
    }
    await _join(n);
  }

  Future<void> _join(ShopNet n) async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final ok = await ShopHotspot.join(n);
      if (!mounted) return;
      widget.onJoined(n); // بيانات الاتصال تُملأ في الحالتين
      setState(() {
        _ok = ok;
        _last = n;
        _msg = ok
            ? 'اتصل بشبكة «${n.ssid}» — بيانات السيرفر مُلئت أدناه. اضغط «اختبار الاتصال» ثم «حفظ».'
            : 'لم يتم الاتصال بـ«${n.ssid}» (رُفض أو الشبكة غير ظاهرة). بيانات السيرفر مُلئت؛ اتصل بالشبكة من إعدادات الواي فاي '
                'بكلمة السر: ${n.password}';
      });
    } catch (e) {
      if (!mounted) return;
      widget.onJoined(n);
      setState(() {
        _ok = false;
        _msg = '$e\nبيانات السيرفر مُلئت. اتصل بالشبكة «${n.ssid}» يدوياً بكلمة السر: ${n.password}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _last;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header('شبكة المتجر — بلا راوتر', 'السيرفر يبث شبكة؟ امسح رمزها هنا', Icons.qr_code_scanner_rounded, _teal),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilledButton.icon(
              onPressed: _busy ? null : _scan,
              style: FilledButton.styleFrom(
                backgroundColor: _teal,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.qr_code_scanner_rounded),
              label: Text(Platform.isWindows ? 'الصق رمز شبكة المتجر' : 'امسح رمز شبكة المتجر',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            if (last != null && !_busy) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _join(last),
                icon: const Icon(Icons.wifi_rounded),
                label: Text('أعد الانضمام إلى «${last.ssid}»'),
              ),
            ],
            if (_msg != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_ok ? _teal : _red).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(_ok ? Icons.check_circle_rounded : Icons.info_outline_rounded, color: _ok ? _teal : _red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: SelectableText(_msg!, style: const TextStyle(height: 1.5, color: _ink))),
                ]),
              ),
              if (!_ok && Platform.isAndroid)
                TextButton.icon(
                  onPressed: ShopHotspot.openWifiSettings,
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('افتح إعدادات الواي فاي'),
                ),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ═════════════════════════════ مشترك ═════════════════════════════

Widget _header(String title, String sub, IconData icon, Color c) => Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(gradient: LinearGradient(colors: [c, Color.lerp(c, Colors.black, 0.28)!])),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 12.5)),
          ]),
        ),
      ]),
    );

Widget _note(String t) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline_rounded, size: 18, color: _muted),
        const SizedBox(width: 8),
        Expanded(child: Text(t, style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.5))),
      ]),
    );

InputDecoration _dec(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      isDense: true,
      filled: true,
      fillColor: _bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
    );

/// رمز QR مرسوم بمكتبة barcode (كما في مشاركة خادم واتساب).
class _QrPainter extends CustomPainter {
  _QrPainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    final els = Barcode.qrCode(errorCorrectLevel: BarcodeQRCorrectionLevel.medium).make(data, width: size.width, height: size.height);
    for (final e in els) {
      if (e is BarcodeBar && e.black) {
        canvas.drawRect(Rect.fromLTWH(e.left, e.top, e.width + 0.5, e.height + 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
