// lib/owner/wa_auto/wa_auto_setup_panels.dart
//
// 🖥️ لوحة «الخادم على هذه الحاسبة» في شاشة «خادم واتساب»: زر واحد يثبّت ويشغّل
// (wa_local_server.dart)، ثم: متى يبدأ، إعادة التشغيل، السجل، الإزالة.
// تنادي [onReady] بالرابط عند النجاح، والشاشة تفحص الاتصال.

import 'package:flutter/material.dart';

import '../../widgets/settings_kit.dart';
import 'wa_local_server.dart';
import 'wa_server_client.dart';

const _green = Color(0xFF047857);
const _red = Color(0xFFB91C1C);
const _muted = Color(0xFF64748B);

class _Progress extends StatelessWidget {
  const _Progress(this.text, this.frac, {this.bad = false, this.busy = false});
  final String? text;
  final double? frac;
  final bool bad, busy;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (busy && !bad) LinearProgressIndicator(value: frac, minHeight: 5),
        const SizedBox(height: 6),
        SelectableText(
          frac == null || !busy ? text! : '${text!} ${(frac! * 100).toStringAsFixed(0)}٪',
          style: TextStyle(fontSize: 12.5, height: 1.5, color: bad ? _red : const Color(0xFF334155)),
        ),
      ]),
    );
  }
}

Widget _box({required Widget child}) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kSetNavy.withValues(alpha: 0.18)),
      ),
      child: child,
    );

Widget _title(String t) => Row(children: [
      const Icon(Icons.auto_fix_high_rounded, size: 18, color: kSetNavy),
      const SizedBox(width: 8),
      Expanded(child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetNavy))),
    ]);

// ═════════════════════ هذه الحاسبة ═════════════════════

class WaLocalAutoPanel extends StatefulWidget {
  const WaLocalAutoPanel({super.key, required this.onReady});
  final Future<void> Function(String url) onReady;

  @override
  State<WaLocalAutoPanel> createState() => _WaLocalAutoPanelState();
}

class _WaLocalAutoPanelState extends State<WaLocalAutoPanel> {
  bool _installed = false, _running = false, _enabled = false, _busy = false, _bad = false, _auto = true;
  String? _text;
  double? _frac;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final i = await WaLocalServer.isInstalled();
    final r = await WaLocalServer.isRunning();
    final e = await WaLocalServer.enabled();
    final a = await WaLocalServer.autoStart();
    if (mounted) {
      setState(() {
        _installed = i;
        _running = r;
        _enabled = e;
        _auto = a;
      });
    }
  }

  Future<void> _run(Future<void> Function() job, {String? done}) async {
    setState(() {
      _busy = true;
      _bad = false;
      _text = 'يبدأ…';
      _frac = null;
    });
    try {
      await job();
      if (mounted) setState(() => _text = done ?? _text);
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

  Future<void> _setup() => _run(() async {
        await WaLocalServer.setup(onStep: (m, f) {
          if (mounted) {
            setState(() {
              _text = m;
              _frac = f;
            });
          }
        });
        if (mounted) setState(() => _frac = null);
        await widget.onReady(WaLocalServer.url);
      }, done: 'الخادم يعمل على هذه الحاسبة ✓ — بقي ربط رقم واتساب في البطاقة 3');

  Future<void> _restart() => _run(() async {
        await WaLocalServer.stop();
        await WaLocalServer.start(force: true);
        await widget.onReady(WaLocalServer.url);
      }, done: 'أُعيد تشغيل الخادم ✓');

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إزالة الخادم من هذه الحاسبة'),
        content: const Text(
          'يُوقف الخادم وتُحذف ملفاته المنزّلة (Node.js وGit والمكتبات) من مجلد البرنامج. '
          'جلسة الربط المشفّرة تبقى، فإن أعدت التشغيل لاحقاً لا يلزم ربط جديد.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إزالة')),
        ],
      ),
    );
    if (ok == true) await _run(WaLocalServer.remove, done: 'أُزيل الخادم من هذه الحاسبة');
  }

  Future<void> _showLog() async {
    final t = await WaLocalServer.logTail(80);
    final mem = WaLocalServer.log.join('\n');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سجل الخادم'),
        content: SizedBox(
          width: 640,
          height: 420,
          child: SingleChildScrollView(
            child: SelectableText(
              [if (t.isNotEmpty) t, if (mem.isNotEmpty) '── التثبيت ──\n$mem'].join('\n\n').ifEmpty('لا شيء بعد'),
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!WaLocalServer.supported) {
      return _box(child: const Text('التشغيل الآلي على هذه الحاسبة متاح في Windows فقط.'));
    }
    final ready = _installed && _enabled;
    return _box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title('الخادم على هذه الحاسبة'),
        const SizedBox(height: 6),
        const Text(
          'ضغطة واحدة: يتأكد البرنامج من وجود Node.js وGit، وينزّل الناقص من مواقعه الرسمية ويطابق بصمته، '
          'ويثبّت الخادم داخل مجلد البرنامج، ثم يشغّله بلا نافذة. يحتاج إنترنت أول مرة (≈70 ميغابايت). '
          'لا حسابات ولا بطاقات ولا صلاحيات مدير.',
          style: TextStyle(fontSize: 12.5, height: 1.6, color: _muted),
        ),
        const SizedBox(height: 6),
        const Text(
          'خفيف: نحو 100 إلى 200 ميغابايت من الذاكرة، ولا يستهلك المعالج إلا لحظة الإرسال. يكفيه أي حاسوب '
          'بنظام Windows 10 أو 11 (64-bit). يعمل ما دام البرنامج مفتوحاً، ويتوقف وحده عند إغلاقه.',
          style: TextStyle(fontSize: 12.5, height: 1.6, color: _muted),
        ),
        const SizedBox(height: 10),
        if (ready)
          Row(children: [
            Icon(_running ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                color: _running ? _green : _muted, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_running ? 'يعمل على ${WaLocalServer.url}' : 'مثبّت — متوقف الآن (يبدأ عند الحاجة)',
                  style: TextStyle(fontWeight: FontWeight.w700, color: _running ? _green : _muted)),
            ),
          ]),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (!ready)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _green, minimumSize: const Size(0, 46)),
              onPressed: _busy ? null : _setup,
              icon: const Icon(Icons.bolt_rounded),
              label: const Text('تشغيل على هذه الحاسبة بضغطة'),
            )
          else ...[
            FilledButton.icon(
              onPressed: _busy ? null : _restart,
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(_running ? 'إعادة التشغيل' : 'تشغيل الآن'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _showLog,
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('السجل'),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: _red),
              onPressed: _busy ? null : _remove,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('إزالة'),
            ),
          ],
        ]),
        if (ready) ...[
          const Divider(height: 26),
          const Text('متى يبدأ الخادم؟', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          _choice(true, 'مع فتح البرنامج (موصى به)',
              'يبدأ وحده كل مرة تفتح فيها البرنامج — بعد تشغيل الحاسبة أيضاً — فيبقى الربط بواتساب نشطاً.'),
          _choice(false, 'عند الحاجة فقط',
              'لا يعمل حتى أول إرسال أو حتى تضغط «تشغيل الآن». يوفّر الذاكرة، لكن أول إرسال يتأخر ثوانيَ.'),
        ],
        _Progress(_text, _frac, bad: _bad, busy: _busy),
      ]),
    );
  }

  Widget _choice(bool v, String title, String sub) {
    final on = _auto == v;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _busy
          ? null
          : () async {
              await WaLocalServer.setAutoStart(v);
              if (mounted) setState(() => _auto = v);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: on ? kSetNavy : _muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: on ? kSetNavy : null)),
              Text(sub, style: const TextStyle(fontSize: 12, height: 1.5, color: _muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
