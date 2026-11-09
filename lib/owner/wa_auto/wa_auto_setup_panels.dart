// lib/owner/wa_auto/wa_auto_setup_panels.dart
//
// 🪄 الطريقة الآلية في شاشة «خادم واتساب»:
//   • WaLocalAutoPanel — تشغيل الخادم على هذه الحاسبة بضغطة (wa_local_server.dart).
//   • WaRenderAutoPanel — إنشاء الخادم على Render بمفتاح API (wa_render_deployer.dart).
// كل لوحة تنادي [onReady] بالرابط عند النجاح، والشاشة تفحص الاتصال.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/settings_kit.dart';
import 'wa_local_server.dart';
import 'wa_render_deployer.dart';
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
  bool _installed = false, _running = false, _enabled = false, _busy = false, _bad = false;
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
    if (mounted) {
      setState(() {
        _installed = i;
        _running = r;
        _enabled = e;
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
        _title('الطريقة الآلية (موصى بها)'),
        const SizedBox(height: 6),
        const Text(
          'ضغطة واحدة: ينزّل البرنامج ما يلزم من المواقع الرسمية ويتحقق من بصمته، يثبّته داخل مجلد البرنامج، '
          'ويشغّل الخادم بلا نافذة. يحتاج إنترنت أول مرة (≈70 ميغابايت). لا حسابات ولا بطاقات.',
          style: TextStyle(fontSize: 12.5, height: 1.6, color: _muted),
        ),
        const SizedBox(height: 6),
        const Text(
          'يعمل ما دام البرنامج مفتوحاً، ويتوقف وحده عند إغلاقه ويعود عند أول تذكير.',
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
        _Progress(_text, _frac, bad: _bad, busy: _busy),
      ]),
    );
  }
}

// ═════════════════════ Render ═════════════════════

class WaRenderAutoPanel extends StatefulWidget {
  const WaRenderAutoPanel({super.key, required this.onReady});
  final Future<void> Function(String url) onReady;

  @override
  State<WaRenderAutoPanel> createState() => _WaRenderAutoPanelState();
}

class _WaRenderAutoPanelState extends State<WaRenderAutoPanel> {
  final _key = TextEditingController();
  bool _hasKey = false, _busy = false, _bad = false, _show = false;
  String? _service, _dash, _text;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final h = await WaRenderDeployer.hasApiKey();
    final s = await WaRenderDeployer.serviceId();
    final d = await WaRenderDeployer.dashboardUrl();
    if (mounted) {
      setState(() {
        _hasKey = h;
        _service = s;
        _dash = d;
      });
    }
  }

  void _open(String u) => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);

  Future<void> _deploy() async {
    setState(() {
      _busy = true;
      _bad = false;
      _text = 'يبدأ…';
    });
    try {
      if (_key.text.trim().isNotEmpty) {
        await WaRenderDeployer.setApiKey(_key.text);
        _key.clear();
      }
      final url = await WaRenderDeployer.deploy(onStep: (m) {
        if (mounted) setState(() => _text = m);
      });
      await widget.onReady(url);
      if (mounted) setState(() => _text = 'تم ✓ الخادم يعمل على $url — بقي ربط رقم واتساب في البطاقة 3');
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

  Future<void> _forget() async {
    await WaRenderDeployer.forgetApiKey();
    await _refresh();
    if (mounted) setState(() => _text = 'حُذف مفتاح Render من البرنامج. الخادم في Render يبقى يعمل.');
  }

  Widget _stepLine(String n, String t, [String? label, String? link]) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
              radius: 10,
              backgroundColor: kSetNavy,
              child: Text(n, style: const TextStyle(fontSize: 10.5, color: Colors.white))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: const TextStyle(fontSize: 13, height: 1.55)),
              if (link != null)
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () => _open(link),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(label ?? 'فتح'),
                ),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final again = _service != null;
    return _box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title('الطريقة الآلية — بلا GitHub وبلا رفع ملفات'),
        const SizedBox(height: 6),
        _stepLine('1', 'أنشئ حساباً في Render (بالبريد أو Google). لا يلزم GitHub.', 'فتح Render', WaRenderDeployer.registerPage),
        _stepLine('2', 'في Render: Account Settings ← API Keys ← «Create API Key»، سمّه alnaser، وانسخه (يبدأ بـ rnd_).',
            'فتح صفحة المفاتيح', WaRenderDeployer.keysPage),
        _stepLine('3', 'الصقه هنا واضغط الزر. البرنامج ينشئ الخادم المجاني وينتظره ويضع رابطه وحده (2 إلى 6 دقائق).'),
        const SizedBox(height: 8),
        if (_hasKey)
          Row(children: [
            const Icon(Icons.vpn_key_rounded, size: 18, color: _green),
            const SizedBox(width: 8),
            const Expanded(child: Text('مفتاح Render محفوظ في التخزين الآمن', style: TextStyle(color: _green))),
            TextButton(onPressed: _busy ? null : _forget, child: const Text('حذف المفتاح')),
          ])
        else
          TextField(
            controller: _key,
            obscureText: !_show,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'مفتاح Render API',
              hintText: 'rnd_…',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _green, minimumSize: const Size(0, 46)),
            onPressed: _busy ? null : _deploy,
            icon: Icon(again ? Icons.sync_rounded : Icons.rocket_launch_rounded),
            label: Text(again ? 'تحديث الخادم في Render' : 'إنشاء الخادم على Render تلقائياً'),
          ),
          if (_dash != null)
            OutlinedButton.icon(
              onPressed: () => _open(_dash!),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('فتح الخدمة في Render'),
            ),
        ]),
        const SizedBox(height: 8),
        const Text(
          'المفتاح يتحكم في حساب Render كله: يُحفظ مشفّراً في هذا الجهاز ولا يُرسل إلا إلى api.render.com، '
          'واحذفه متى شئت. إن طلب Render بطاقة دفع فاستعمل «هذه الحاسبة».',
          style: TextStyle(fontSize: 12, height: 1.6, color: _muted),
        ),
        _Progress(_text, null, bad: _bad, busy: _busy),
      ]),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
