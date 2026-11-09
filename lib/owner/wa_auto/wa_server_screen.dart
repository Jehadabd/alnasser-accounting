// lib/owner/wa_auto/wa_server_screen.dart
//
// 👑🛰️ إعدادات خادم واتساب (حساب المالك فقط): أين يعمل الخادم، رابطه ومفتاحه،
// وربط رقم واتساب برمز من 8 خانات.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/settings_kit.dart';
import 'wa_auto_reminder.dart';
import 'wa_host_guide_screen.dart';
import 'wa_server_client.dart';
import 'wa_usage_banner.dart';

const _green = Color(0xFF047857);
const _amber = Color(0xFFB45309);
const _red = Color(0xFFB91C1C);
const _muted = Color(0xFF64748B);

class _Step {
  const _Step(this.text, [this.linkLabel, this.link]);
  final String text;
  final String? linkLabel, link;
}

class _Host {
  const _Host(this.title, this.badge, this.icon, this.urlHint, this.steps);
  final String title, badge, urlHint;
  final IconData icon;
  final List<_Step> steps;
}

// الحزمة المنزّلة فيها مجلد واحد alnaser-wa-server — كل الخطوات تشير إلى ما «داخله».
const _hosts = [
  _Host('هذه الحاسبة', 'مجاني • الأسهل • يعمل ما دامت الحاسبة شغّالة', Icons.computer_rounded, 'http://127.0.0.1:8080', [
    _Step('ثبّت Node.js (نسخة LTS) — التالي ثم التالي حتى ينتهي.', 'تنزيل Node.js', 'https://nodejs.org/en/download'),
    _Step('ثبّت Git — اترك كل الخيارات كما هي.', 'تنزيل Git', 'https://git-scm.com/download/win'),
    _Step('نزّل الحزمة من الزر أدناه، وفك ضغطها في مكان ثابت (مثل C:\\alnaser-wa). لا شيء يُرفع.'),
    _Step('افتح مجلد alnaser-wa-server وانقر start-windows.bat مرتين، والصق «مفتاح الخادم» عند السؤال (أول مرة فقط). أبقِ النافذة مفتوحة.'),
    _Step('ضع الرابط http://127.0.0.1:8080 في الأسفل واضغط «حفظ وفحص الاتصال».'),
  ]),
  _Host('Oracle Cloud', 'مجاني دائماً (Always Free) • يعمل والحاسبة مطفأة • يطلب بطاقة للتحقق', Icons.cloud_rounded,
      'https://1-2-3-4.sslip.io', [
    _Step('أنشئ حساباً مجانياً. اختر «Home Region» الأقرب (لا يتغيّر بعدها).', 'إنشاء حساب Oracle', 'https://signup.cloud.oracle.com'),
    _Step('ادخل لوحة التحكم ← القائمة ☰ ← Compute ← Instances ← Create instance:\n'
        '• Image: Ubuntu  • Shape: VM.Standard.A1.Flex أو VM.Standard.E2.1.Micro (عليها «Always Free»)\n'
        '• SSH keys: «Generate a key pair for me» ← Save private key (احفظ ملف .key)\n'
        '• Create، ثم انسخ «Public IP address».', 'فتح لوحة Oracle', 'https://cloud.oracle.com'),
    _Step('افتح المنفذين: صفحة الخادم ← Subnet ← Security Lists ← Default ← Add Ingress Rules:\n'
        'Source CIDR = 0.0.0.0/0، IP Protocol = TCP، Destination Port = 80,443.'),
    _Step('لا ترفع شيئاً بيدك: افتح مجلد alnaser-wa-server وانقر deploy-oracle.bat مرتين، وأدخل: الـ IP، مسار ملف .key، '
        'ubuntu، و«مفتاح الخادم». ينتظر 3 إلى 8 دقائق.'),
    _Step('في آخر النافذة رابط مثل https://1-2-3-4.sslip.io — الصقه في الأسفل واضغط «حفظ وفحص الاتصال».'),
  ]),
  _Host('Render', 'مجاني • ينام بعد 15 دقيقة ويستيقظ عند الطلب • يحتاج GitHub', Icons.rocket_launch_rounded,
      'https://alnaser-wa-xxxx.onrender.com', [
    _Step('أنشئ حساب GitHub (إن لم يكن لديك).', 'إنشاء حساب GitHub', 'https://github.com/signup'),
    _Step('أنشئ مستودعاً جديداً: الاسم alnaser-wa، واختر Private (خاص) — مهم — ثم Create repository.', 'مستودع جديد', 'https://github.com/new'),
    _Step('في صفحة المستودع اضغط «uploading an existing file». افتح مجلد alnaser-wa-server، حدّد كل ما بداخله (Ctrl+A) '
        'واسحبه إلى الصفحة — الملفات لا المجلد نفسه — ثم «Commit changes». يجب أن يظهر package.json في الصفحة الرئيسية للمستودع.'),
    _Step('ادخل Render بحساب GitHub ← New ← Blueprint ← اختر المستودع alnaser-wa ← اسمح لـRender بالوصول إليه.', 'فتح Render',
        'https://dashboard.render.com/blueprints'),
    _Step('يطلب Render قيمة API_KEY: الصق «مفتاح الخادم» ← Apply. البناء يأخذ 3 إلى 6 دقائق.'),
    _Step('افتح الخدمة alnaser-wa وانسخ رابطها (…onrender.com) — الصقه في الأسفل واضغط «حفظ وفحص الاتصال».'),
  ]),
  _Host('Docker', 'Koyeb • Fly.io • Railway • أي خادم', Icons.inventory_2_rounded, 'https://…', [
    _Step('ارفع ملفات المجلد alnaser-wa-server (لا المجلد نفسه) إلى مستودع GitHub خاص كما في Render.'),
    _Step('في المنصة اختر النشر من GitHub بـ Dockerfile، وأضف المتغير API_KEY = «مفتاح الخادم»، والمنفذ 8080.', 'فتح Koyeb',
        'https://app.koyeb.com'),
    _Step('إن أتاحت المنصة تخزيناً دائماً فاربطه بـ /data (وإلا يعيد البرنامج الجلسة وحده). الصق رابط الخدمة في الأسفل.'),
  ]),
];

class WaServerScreen extends StatefulWidget {
  const WaServerScreen({super.key});

  @override
  State<WaServerScreen> createState() => _WaServerScreenState();
}

class _WaServerScreenState extends State<WaServerScreen> {
  final _url = TextEditingController();
  final _phone = TextEditingController();
  String _key = '';
  bool _showKey = false;
  int _host = 0;
  bool _busy = false;
  WaServerStatus? _st;
  String? _msg;
  bool _msgBad = false;
  String? _code;
  Timer? _poll;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _url.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _url.text = await WaServerClient.url();
    _key = await WaServerClient.key();
    if (_url.text.contains('127.0.0.1') || _url.text.contains('localhost')) {
      _host = 0;
    } else if (_url.text.contains('sslip.io')) {
      _host = 1;
    } else if (_url.text.contains('onrender.com')) {
      _host = 2;
    } else if (_url.text.isNotEmpty) {
      _host = 3;
    }
    if (mounted) setState(() => _loaded = true);
    if (_url.text.isNotEmpty) await _check(quiet: true);
  }

  void _say(String m, {bool bad = false}) {
    if (!mounted) return;
    setState(() {
      _msg = m;
      _msgBad = bad;
    });
  }

  Future<void> _check({bool quiet = false}) async {
    await WaServerClient.setUrl(_url.text);
    _url.text = await WaServerClient.url();
    if (_url.text.isEmpty) {
      _say('اكتب رابط الخادم أولاً', bad: true);
      return;
    }
    setState(() => _busy = true);
    if (!quiet) _say('يتصل… (قد يحتاج دقيقة إن كان الخادم نائماً)');
    try {
      final s = await WaServerClient.ensureReady();
      if (!mounted) return;
      setState(() => _st = s);
      _say(s.linked ? 'الخادم يعمل ومربوط بالرقم ${s.me}' : 'الخادم يعمل — بقي ربط رقم واتساب');
    } on WaServerException catch (e) {
      if (!mounted) return;
      setState(() => _st = null);
      _say(e.message, bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pair() async {
    final phone = WaAutoReminder.normalizePhone(_phone.text);
    if (phone == null) {
      _say('اكتب رقم واتساب المحل، مثل 07701234567', bad: true);
      return;
    }
    if (_st?.linked == true) {
      final ok = await _confirm('الخادم مربوط بالرقم ${_st!.me}', 'الربط الجديد يلغي الحالي. متابعة؟');
      if (ok != true) return;
    }
    setState(() {
      _busy = true;
      _code = null;
    });
    _say('يطلب رمز الربط…');
    try {
      final code = await WaServerClient.pair(phone);
      if (!mounted) return;
      setState(() => _code = code);
      _say('أدخل الرمز في هاتف المحل خلال دقيقتين');
      _poll?.cancel();
      final until = DateTime.now().add(const Duration(minutes: 3));
      _poll = Timer.periodic(const Duration(seconds: 4), (t) async {
        if (!mounted || DateTime.now().isAfter(until)) {
          t.cancel();
          if (mounted && _code != null) _say('انتهت المهلة — اطلب رمزاً جديداً', bad: true);
          return;
        }
        try {
          final s = await WaServerClient.status();
          if (s.linked && s.connected) {
            t.cancel();
            await WaServerClient.pullState(); // نسخة الجلسة عند البرنامج
            if (!mounted) return;
            setState(() {
              _st = s;
              _code = null;
            });
            _say('تم الربط ✓ بالرقم ${s.me}');
          }
        } catch (_) {}
      });
    } on WaServerException catch (e) {
      _say(e.message, bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final ok = await _confirm('فك ربط الرقم', 'يُزال الخادم من «الأجهزة المرتبطة» في واتساب، ولن تُرسل تذكيرات حتى تربط من جديد.');
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await WaServerClient.logout();
      if (!mounted) return;
      setState(() => _st = const WaServerStatus(reachable: true));
      _say('فُكّ الربط');
    } on WaServerException catch (e) {
      _say(e.message, bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newKey() async {
    final ok = await _confirm('مفتاح جديد',
        'الخادم الحالي سيرفض البرنامج حتى تضع المفتاح الجديد فيه، ويلزم ربط رقم واتساب من جديد. متابعة؟');
    if (ok != true) return;
    final k = await WaServerClient.newKey();
    if (!mounted) return;
    setState(() {
      _key = k;
      _showKey = true;
      _st = null;
    });
    _say('مفتاح جديد — ضعه في الخادم ثم اضغط «فحص الاتصال»');
  }

  Future<void> _download() async {
    try {
      final path = await WaServerClient.savePackage();
      if (!mounted) return;
      _say('حُفظت الحزمة: $path');
      final dir = File(path).parent.path;
      await launchUrl(Uri.file(dir));
    } catch (e) {
      _say('تعذّر حفظ الحزمة: $e', bad: true);
    }
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body, style: const TextStyle(height: 1.6)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('متابعة')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!WaAutoReminder.allowed) {
      return const SettingsScaffold(
        title: 'خادم واتساب',
        icon: Icons.dns_rounded,
        children: [SetBanner('هذه الإعدادات للمالك ولأصحاب اشتراك المزامنة (مدير البرنامج).', kind: SetBannerKind.warn)],
      );
    }
    if (!_loaded) return const SettingsScaffold(title: 'خادم واتساب', icon: Icons.dns_rounded, loading: true);
    final st = _st;
    final h = _hosts[_host];
    return SettingsScaffold(
      title: 'خادم واتساب',
      icon: Icons.dns_rounded,
      subtitle: 'يرسل التذكيرات من رقم المحل في الخلفية — بلا WhatsApp Desktop',
      children: [
        const WaUsageBanner(),
        const SetBanner(
          'الخادم يرسل فقط: لا يقرأ رسائلك ولا يحفظها. ليس طريقة رسمية من واتساب — الإرسال الكثير قد يقيّد الرقم.',
          kind: SetBannerKind.warn,
        ),
        const SizedBox(height: 12),
        _statusCard(st),
        const SizedBox(height: 12),
        SetCard(
          title: '1. أين يعمل الخادم؟',
          icon: Icons.public_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < _hosts.length; i++)
                ChoiceChip(
                  avatar: Icon(_hosts[i].icon, size: 18, color: _host == i ? Colors.white : kSetNavy),
                  label: Text(_hosts[i].title),
                  selected: _host == i,
                  selectedColor: kSetNavy,
                  labelStyle: TextStyle(color: _host == i ? Colors.white : null, fontWeight: FontWeight.w700),
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _host = i),
                ),
            ]),
            const SizedBox(height: 6),
            Text(h.badge, style: const TextStyle(fontSize: 12, color: _muted)),
            const Divider(),
            for (var i = 0; i < h.steps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                      radius: 11,
                      backgroundColor: kSetNavy,
                      child: Text('${i + 1}', style: const TextStyle(fontSize: 11, color: Colors.white))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(h.steps[i].text, style: const TextStyle(height: 1.55)),
                      if (h.steps[i].link != null)
                        TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                          onPressed: () => launchUrl(Uri.parse(h.steps[i].link!), mode: LaunchMode.externalApplication),
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: Text(h.steps[i].linkLabel ?? 'فتح'),
                        ),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kSetNavy, minimumSize: const Size.fromHeight(46)),
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => WaHostGuideScreen(index: _host))),
              icon: const Icon(Icons.menu_book_rounded),
              label: Text('الشرح الكامل خطوة بخطوة: ${h.title}'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _download,
              icon: const Icon(Icons.download_rounded),
              label: const Text('تنزيل ملفات الخادم (zip)'),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: '2. الاتصال بالخادم',
          icon: Icons.link_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _url,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'رابط الخادم',
                hintText: h.urlHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'مفتاح الخادم (API_KEY)', border: OutlineInputBorder(), isDense: true),
                  child: SelectableText(
                    _showKey ? _key : '•' * 20,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
              IconButton(
                tooltip: _showKey ? 'إخفاء' : 'إظهار',
                icon: Icon(_showKey ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                onPressed: () => setState(() => _showKey = !_showKey),
              ),
              IconButton(
                tooltip: 'نسخ المفتاح',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _key));
                  _say('نُسخ المفتاح — الصقه في الخادم (API_KEY)');
                },
              ),
            ]),
            const SizedBox(height: 4),
            const Text('سرّي: من يملكه يرسل من رقمك. لا تضعه في مستودع GitHub عام.',
                style: TextStyle(fontSize: 12, color: _muted)),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _check(),
                icon: const Icon(Icons.wifi_tethering_rounded),
                label: const Text('حفظ وفحص الاتصال'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _newKey,
                icon: const Icon(Icons.key_rounded),
                label: const Text('مفتاح جديد'),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: '3. رقم واتساب المحل',
          icon: Icons.chat_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (st?.linked == true) ...[
              Text('مربوط بالرقم ${st!.me}', style: const TextStyle(fontWeight: FontWeight.w800, color: _green)),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: _red),
                  onPressed: _busy ? null : _logout,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('فك الربط'),
                ),
              ),
              const Divider(height: 24),
            ],
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'رقم واتساب المحل',
                hintText: '07701234567',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _green),
                onPressed: _busy || st == null ? null : _pair,
                icon: const Icon(Icons.qr_code_2_rounded),
                label: Text(st?.linked == true ? 'ربط رقم آخر' : 'اطلب رمز الربط'),
              ),
            ),
            if (st == null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('افحص الاتصال بالخادم أولاً.', style: TextStyle(fontSize: 12, color: _muted)),
              ),
            if (_code != null) _codeCard(_code!),
          ]),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _statusCard(WaServerStatus? st) {
    final (Color c, IconData ic, String t) = st == null
        ? (_muted, Icons.help_outline_rounded, 'لم يُفحص الاتصال بعد')
        : !st.linked
            ? (_amber, Icons.link_off_rounded, 'الخادم يعمل — غير مربوط برقم')
            : st.connected
                ? (_green, Icons.check_circle_rounded, 'جاهز للإرسال • ${st.me}')
                : (_amber, Icons.sync_problem_rounded, 'مربوط بـ ${st.me} — يعيد الاتصال بواتساب');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(ic, color: c),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, color: c))),
          if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        if (st != null && st.linked) ...[
          const SizedBox(height: 4),
          Text('أُرسل في آخر ساعة: ${st.sentLastHour} من ${st.maxPerHour}',
              style: const TextStyle(fontSize: 12, color: _muted)),
        ],
        if (_msg != null) ...[
          const SizedBox(height: 6),
          Text(_msg!, style: TextStyle(fontSize: 12.5, color: _msgBad ? _red : const Color(0xFF334155))),
        ],
      ]),
    );
  }

  Widget _codeCard(String code) => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _green.withValues(alpha: 0.4)),
        ),
        child: Column(children: [
          const Text('رمز الربط', style: TextStyle(color: _muted)),
          const SizedBox(height: 6),
          SelectableText(code,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 4, color: _green)),
          const SizedBox(height: 10),
          const Text(
            'في هاتف المحل: واتساب ← الإعدادات ← الأجهزة المرتبطة ← ربط جهاز ← '
            '«الربط برقم الهاتف بدلاً من ذلك» ← أدخل الرمز.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ]),
      );
}
