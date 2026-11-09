// lib/owner/wa_auto/wa_phone_panels.dart
//
// 📱 بطاقة «الخادم» في شاشة «خادم واتساب» على أندرويد — تختار أين يعمل الخادم:
//   • على هذا الهاتف نفسه (wa_phone_server.dart): تشغيل بضغطة، إشعار ثابت، استثناء البطارية.
//   • على حاسبة المحل (نفس الواي فاي): امسح رمز QR من شاشة الحاسبة (wa_lan_share_panel.dart).
// تنادي [onReady] بعد النجاح، والشاشة تفحص الاتصال.

import 'package:flutter/material.dart';

import '../../widgets/camera_barcode_scanner_dialog.dart';
import '../../widgets/settings_kit.dart';
import 'wa_pair_code.dart';
import 'wa_phone_server.dart';
import 'wa_server_client.dart';

const _green = Color(0xFF047857);
const _red = Color(0xFFB91C1C);
const _amber = Color(0xFFB45309);
const _muted = Color(0xFF64748B);

class WaPhoneServerPanel extends StatefulWidget {
  const WaPhoneServerPanel({super.key, required this.onReady});
  final Future<void> Function() onReady;

  @override
  State<WaPhoneServerPanel> createState() => _WaPhoneServerPanelState();
}

class _WaPhoneServerPanelState extends State<WaPhoneServerPanel> {
  WaPhoneMode _mode = WaPhoneMode.none;
  bool _loaded = false, _available = false, _running = false, _auto = true, _battery = true, _busy = false, _bad = false;
  String _url = '';
  String? _text;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final m = await WaPhoneServer.mode();
    final a = await WaPhoneServer.available();
    final r = m == WaPhoneMode.phone && await WaPhoneServer.isRunning();
    final au = await WaPhoneServer.autoStart();
    final b = await WaPhoneServer.batteryExempt();
    final u = await WaServerClient.url();
    if (!mounted) return;
    setState(() {
      _mode = m;
      _available = a;
      _running = r;
      _auto = au;
      _battery = b;
      _url = u;
      _loaded = true;
    });
  }

  Future<void> _run(Future<void> Function() job, {String? done}) async {
    setState(() {
      _busy = true;
      _bad = false;
      _text = 'يبدأ…';
    });
    try {
      await job();
      if (mounted && done != null) setState(() => _text = done);
    } on WaServerException catch (e) {
      if (mounted) {
        setState(() {
          _bad = true;
          _text = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _bad = true;
          _text = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  // ───────────── على هذا الهاتف ─────────────

  Future<void> _usePhone() => _run(() async {
        await WaPhoneServer.setup(onStep: (m) {
          if (mounted) setState(() => _text = m);
        });
        await widget.onReady();
      }, done: 'الخادم يعمل على هذا الهاتف ✓ — بقي ربط رقم واتساب في البطاقة 2');

  Future<void> _restart() => _run(() async {
        await WaPhoneServer.stop();
        await WaPhoneServer.start(force: true, onStep: (m) {
          if (mounted) setState(() => _text = m);
        });
        await widget.onReady();
      }, done: 'أُعيد تشغيل الخادم ✓');

  Future<void> _stopPhone() => _run(WaPhoneServer.disable, done: 'أُوقف خادم الهاتف');

  Future<void> _showLog() async {
    final t = await WaPhoneServer.logTail(80);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سجل خادم الهاتف'),
        content: SizedBox(
          width: 640,
          height: 420,
          child: SingleChildScrollView(
            child: SelectableText(t.isEmpty ? 'لا شيء بعد' : t,
                textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
      ),
    );
  }

  // ───────────── على حاسبة المحل ─────────────

  Future<void> _usePc({bool paste = false}) async {
    String? raw;
    if (paste) {
      raw = await _pasteDialog();
    } else {
      raw = await CameraBarcodeScannerDialog.scan(context, title: 'امسح رمز الربط من شاشة الحاسبة');
    }
    if (raw == null || !mounted) return;
    final code = WaPairCode.decode(raw);
    if (code == null) {
      setState(() {
        _bad = true;
        _text = 'هذا ليس رمز ربط خادم الحاسبة. في الحاسبة: خادم واتساب ← «مشاركة الخادم مع هواتف المحل».';
      });
      return;
    }
    await _run(() async {
      setState(() => _text = 'يتصل بخادم الحاسبة ${code.url}…');
      final s = await WaPhoneServer.usePc(code);
      await widget.onReady();
      if (mounted) {
        setState(() => _text = s.linked
            ? 'متصل بخادم الحاسبة ✓ — مربوط بالرقم ${s.me}'
            : 'متصل بخادم الحاسبة ✓ — اربط رقم واتساب من الحاسبة أو من البطاقة 2');
      }
    });
  }

  Future<String?> _pasteDialog() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('لصق رمز الربط'),
        content: TextField(
          controller: c,
          maxLines: 3,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(hintText: 'ALNWA1:…', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('ربط')),
        ],
      ),
    ); // لا dispose هنا: النافذة تستعمله أثناء حركة الإغلاق
  }

  // ───────────── الواجهة ─────────────

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const LinearProgressIndicator();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SetBanner('📱 إعدادات هذا الهاتف (أندرويد): الإرسال عبر خادم دائماً. اختر أين يعمل الخادم.'),
      const SizedBox(height: 10),
      _option(
        WaPhoneMode.phone,
        Icons.phone_android_rounded,
        'خادم على هذا الهاتف',
        _available
            ? 'كل شيء داخل التطبيق — لا حاسبة ولا تنزيل. يعمل بإشعار ثابت «خادم واتساب يعمل». '
                'يستهلك بعض الذاكرة والبطارية، وبعض الهواتف توقفه إن لم تستثنه من توفير البطارية.'
            : 'هذه النسخة من التطبيق بُنيت بلا خادم الهاتف — استعمل خادم الحاسبة، أو ثبّت النسخة الكاملة.',
        enabled: _available,
      ),
      _option(
        WaPhoneMode.pc,
        Icons.computer_rounded,
        'خادم حاسبة المحل (نفس الواي فاي)',
        'الحاسبة ترسل عن الهاتف — أخف على الهاتف. تحتاج الحاسبة شغّالة والبرنامج مفتوحاً عليها، '
            'والهاتف على نفس شبكة المحل.',
      ),
      const Divider(height: 24),
      if (_mode == WaPhoneMode.phone) _phoneDetails(),
      if (_mode == WaPhoneMode.pc) _pcDetails(),
      if (_text != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_busy) const LinearProgressIndicator(minHeight: 4),
            const SizedBox(height: 6),
            SelectableText(_text!, style: TextStyle(fontSize: 12.5, height: 1.5, color: _bad ? _red : const Color(0xFF334155))),
          ]),
        ),
    ]);
  }

  Widget _option(WaPhoneMode m, IconData icon, String title, String sub, {bool enabled = true}) {
    final on = _mode == m;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Card(
        elevation: 0,
        color: on ? kSetNavy.withValues(alpha: 0.06) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: on ? kSetNavy : const Color(0xFFE2E8F0), width: on ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: !enabled || _busy || on
              ? null
              : () => m == WaPhoneMode.phone ? _usePhone() : _usePc(),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: on ? kSetNavy : _muted),
              const SizedBox(width: 10),
              Icon(icon, color: on ? kSetNavy : _muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: on ? kSetNavy : null)),
                  const SizedBox(height: 2),
                  Text(sub, style: const TextStyle(fontSize: 12, height: 1.5, color: _muted)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _phoneDetails() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(_running ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
              color: _running ? _green : _muted, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_running ? 'يعمل على هذا الهاتف' : 'متوقف الآن (يبدأ عند الحاجة)',
                style: TextStyle(fontWeight: FontWeight.w700, color: _running ? _green : _muted)),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _busy ? null : _restart,
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(_running ? 'إعادة التشغيل' : 'تشغيل الآن'),
          ),
          OutlinedButton.icon(
              onPressed: _busy ? null : _showLog, icon: const Icon(Icons.receipt_long_rounded), label: const Text('السجل')),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: _red),
            onPressed: _busy ? null : _stopPhone,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('إيقاف'),
          ),
        ]),
        if (!_battery) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _amber.withValues(alpha: 0.4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('⚠️ توفير البطارية قد يوقف الخادم والشاشة مطفأة، فلا تصل الرسائل.',
                  style: TextStyle(fontWeight: FontWeight.w700, color: _amber)),
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await WaPhoneServer.requestBatteryExempt();
                    await Future.delayed(const Duration(seconds: 2));
                    await _refresh();
                  },
                  icon: const Icon(Icons.battery_saver_rounded),
                  label: const Text('استثناء التطبيق من توفير البطارية'),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        SetSwitch(
          title: 'يبدأ مع فتح البرنامج',
          subtitle: _auto ? 'الربط بواتساب يبقى نشطاً (موصى به)' : 'عند أول إرسال فقط — أول رسالة تتأخر ثوانيَ',
          value: _auto,
          onChanged: _busy
              ? null
              : (v) async {
                  await WaPhoneServer.setAutoStart(v);
                  if (mounted) setState(() => _auto = v);
                },
        ),
      ]);

  Widget _pcDetails() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.lan_rounded, color: kSetNavy, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('خادم الحاسبة: $_url',
                textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _busy ? null : () => _usePc(),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('مسح رمز جديد'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _usePc(paste: true),
            icon: const Icon(Icons.content_paste_rounded),
            label: const Text('لصق الرمز'),
          ),
        ]),
        const SizedBox(height: 6),
        const Text('إن تغيّر عنوان الحاسبة على الشبكة أو مفتاحها، امسح الرمز من جديد.',
            style: TextStyle(fontSize: 12, color: _muted)),
      ]);
}
