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
import 'wa_server_client.dart';

const _green = Color(0xFF047857);
const _amber = Color(0xFFB45309);
const _red = Color(0xFFB91C1C);
const _muted = Color(0xFF64748B);

class _Host {
  const _Host(this.title, this.badge, this.icon, this.urlHint, this.steps);
  final String title, badge, urlHint;
  final IconData icon;
  final List<String> steps;
}

const _hosts = [
  _Host('هذه الحاسبة', 'مجاني • الأسهل', Icons.computer_rounded, 'http://127.0.0.1:8080', [
    'ثبّت Node.js 20 أو أحدث (nodejs.org) وGit (git-scm.com).',
    'نزّل ملفات الخادم من الزر أدناه وفك ضغطها في مجلد ثابت.',
    'شغّل start-windows.bat والصق «مفتاح الخادم» عند السؤال (أول مرة فقط).',
    'الرابط: http://127.0.0.1:8080 — يعمل ما دامت النافذة مفتوحة والحاسبة شغّالة.',
  ]),
  _Host('Oracle Cloud (Always Free)', 'مجاني • يعمل دائماً', Icons.cloud_rounded, 'https://1-2-3-4.sslip.io', [
    'أنشئ حساباً في Oracle Cloud ثم Compute ← Instance بنظام Ubuntu، ونزّل ملف المفتاح الخاص (.key).',
    'في VCN ← Security List أضف قاعدة Ingress للمنفذين 80 و443 من 0.0.0.0/0.',
    'نزّل ملفات الخادم وفك ضغطها، ثم شغّل deploy-oracle.bat: عنوان IP، مسار ملف المفتاح، و«مفتاح الخادم».',
    'في النهاية يطبع رابطاً مثل https://1-2-3-4.sslip.io — الصقه هنا.',
  ]),
  _Host('Render', 'مجاني • ينام ويستيقظ', Icons.rocket_launch_rounded, 'https://alnaser-wa-xxxx.onrender.com', [
    'أنشئ مستودعاً خاصاً (Private) في GitHub وارفع إليه ملفات الخادم بالسحب والإفلات — بلا ملف .env.',
    'في Render: New ← Blueprint ← اختر المستودع. ضع API_KEY = «مفتاح الخادم».',
    'انسخ رابط الخدمة (…onrender.com) والصقه هنا.',
    'ينام بعد 15 دقيقة بلا طلبات ويستيقظ خلال دقيقة؛ البرنامج يعيد جلسة الربط وحده.',
  ]),
  _Host('Docker (أي منصة)', 'Koyeb • Fly.io • Railway • VPS', Icons.inventory_2_rounded, 'https://…', [
    'في الحزمة Dockerfile جاهز: ابنِ الصورة وشغّلها مع المتغير API_KEY = «مفتاح الخادم».',
    'اربط مجلد /data بتخزين دائم إن أتاحته المنصة (وإلا يعيد البرنامج الجلسة).',
    'الصق رابط الخدمة هنا.',
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
        children: [SetBanner('هذه الإعدادات لحساب المالك فقط.', kind: SetBannerKind.warn)],
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
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                      radius: 11,
                      backgroundColor: kSetNavy,
                      child: Text('${i + 1}', style: const TextStyle(fontSize: 11, color: Colors.white))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(h.steps[i], style: const TextStyle(height: 1.5))),
                ]),
              ),
            const SizedBox(height: 10),
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
