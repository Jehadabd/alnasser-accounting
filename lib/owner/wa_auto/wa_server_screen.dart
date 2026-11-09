// lib/owner/wa_auto/wa_server_screen.dart
//
// 👑🛰️ إعدادات خادم واتساب (المالك ومدير البرنامج): الخادم يعمل على هذه الحاسبة فقط —
// تثبيت وتشغيل بضغطة (wa_auto_setup_panels.dart)، ثم ربط رقم واتساب برمز من 8 خانات.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/settings_kit.dart';
import 'wa_auto_reminder.dart';
import 'wa_auto_setup_panels.dart';
import 'wa_local_server.dart';
import 'wa_server_client.dart';
import 'wa_usage_banner.dart';

const _green = Color(0xFF047857);
const _amber = Color(0xFFB45309);
const _red = Color(0xFFB91C1C);
const _muted = Color(0xFF64748B);

class WaServerScreen extends StatefulWidget {
  const WaServerScreen({super.key});

  @override
  State<WaServerScreen> createState() => _WaServerScreenState();
}

class _WaServerScreenState extends State<WaServerScreen> {
  final _phone = TextEditingController();
  String _url = '';
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
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _url = await WaServerClient.url();
    if (mounted) setState(() => _loaded = true);
    // مثبّت على هذه الحاسبة ⇒ الرابط المحلي دائماً، والفحص يشغّل الخادم إن كان متوقفاً
    if (await WaLocalServer.enabled()) {
      if (!WaLocalServer.isLocalUrl(_url)) {
        await WaServerClient.setUrl(WaLocalServer.url);
        _url = WaLocalServer.url;
      }
      await _check(quiet: true);
    }
  }

  void _say(String m, {bool bad = false}) {
    if (!mounted) return;
    setState(() {
      _msg = m;
      _msgBad = bad;
    });
  }

  Future<void> _check({bool quiet = false}) async {
    if (!await WaLocalServer.enabled()) {
      _say('شغّل الخادم على هذه الحاسبة أولاً (الزر الأخضر)', bad: true);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    if (!quiet) _say('يتصل بالخادم…');
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
        'يُعاد تشغيل الخادم بمفتاح جديد، ويلزم ربط رقم واتساب من جديد. استعمله فقط إن ظننت أن المفتاح انكشف. متابعة؟');
    if (ok != true) return;
    await WaServerClient.newKey();
    if (!mounted) return;
    setState(() => _st = null);
    _say('مفتاح جديد — يعيد تشغيل الخادم به…');
    if (await WaLocalServer.ensureRunning()) await _check();
  }

  /// اللوحة أنهت التثبيت والتشغيل: يحفظ الرابط ويفحص الاتصال.
  Future<void> _onAutoReady(String url) async {
    _url = url;
    await _check();
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
    final external = _url.isNotEmpty && !WaLocalServer.isLocalUrl(_url);
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
        if (external) ...[
          SetBanner(
            'البرنامج مضبوط على خادم خارجي ($_url). الخادم الآن على هذه الحاسبة فقط: '
            'اضغط الزر الأخضر لنقله إليها، ثم أوقف الخادم القديم أو احذفه حتى لا يعمل اثنان برقم واحد.',
            kind: SetBannerKind.warn,
          ),
          const SizedBox(height: 12),
        ],
        SetCard(
          title: '1. الخادم',
          icon: Icons.computer_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            WaLocalAutoPanel(onReady: _onAutoReady),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 6, children: [
              TextButton.icon(
                onPressed: _busy ? null : () => _check(),
                icon: const Icon(Icons.wifi_tethering_rounded),
                label: const Text('فحص الاتصال'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: _muted),
                onPressed: _busy ? null : _newKey,
                icon: const Icon(Icons.key_rounded),
                label: const Text('مفتاح جديد'),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: '2. رقم واتساب المحل',
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
                child: Text('شغّل الخادم أولاً (البطاقة 1).', style: TextStyle(fontSize: 12, color: _muted)),
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
