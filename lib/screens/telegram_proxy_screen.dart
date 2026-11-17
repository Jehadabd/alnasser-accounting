// lib/screens/telegram_proxy_screen.dart
//
// 🧦 تيليجرام عند الحظر — رفع تيليجرام عبر بروكسي SOCKS5 أو HTTP.
// إضافة اختيارية: وهي مطفأة يرفع البرنامج مباشرة كما كان دائماً.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings_manager.dart';
import '../services/telegram_net/telegram_proxy.dart';
import '../widgets/settings_kit.dart';
import '../widgets/setup_guide.dart';

class TelegramProxyScreen extends StatefulWidget {
  const TelegramProxyScreen({super.key});

  @override
  State<TelegramProxyScreen> createState() => _TelegramProxyScreenState();
}

class _TelegramProxyScreenState extends State<TelegramProxyScreen> {
  static const _tg = Color(0xFF229ED9);

  final _paste = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  bool _loaded = false;
  bool _enabled = false;
  TgProxyType _type = TgProxyType.socks5;
  bool _busy = false;
  bool _showPass = false;
  (bool, String)? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_paste, _host, _port, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await TelegramProxy.saved();
    final en = await TelegramProxy.isEnabled();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _enabled = en;
      if (cfg != null) _fill(cfg);
    });
  }

  void _fill(TgProxyConfig c) {
    _type = c.type;
    _host.text = c.host;
    _port.text = '${c.port}';
    _user.text = c.user ?? '';
    _pass.text = c.pass ?? '';
  }

  TgProxyConfig? _form() {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
    final user = _user.text.trim();
    return TgProxyConfig(type: _type, host: host, port: port, user: user.isEmpty ? null : user, pass: user.isEmpty ? null : _pass.text);
  }

  void _onPaste(String v) {
    if (TelegramProxy.isMtprotoLink(v)) {
      setState(() => _result = (false, 'هذا رابط MTProto (فيه secret) — لا يعمل هنا. هذه الشاشة لبروكسي SOCKS5/HTTP فقط.'));
      return;
    }
    final c = TelegramProxy.parse(v, fallback: _type);
    if (c == null) return;
    setState(() {
      _fill(c);
      _result = (true, 'قُرئ الرابط: ${c.label}${c.hasAuth ? ' (باسم مستخدم)' : ''} — اضغط «اختبار»');
    });
    _paste.clear();
  }

  Future<void> _test() async {
    final c = _form();
    if (c == null) {
      setState(() => _result = (false, 'أدخل العنوان والمنفذ'));
      return;
    }
    final token = (await SettingsManager.getAppSettings()).telegramBotToken ?? '';
    if (token.isEmpty) {
      setState(() => _result = (false, 'أدخل توكن البوت أولاً في إعدادات تيليجرام — الاختبار يتصل ببوتك عبر البروكسي'));
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    final err = await TelegramProxy.test(c, token);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = err == null ? (true, 'نجح: وصل البرنامج إلى تيليجرام عبر ${c.label}') : (false, err);
    });
  }

  Future<void> _save({bool? enable}) async {
    final c = _form();
    if (c == null) {
      setState(() => _result = (false, 'أدخل العنوان والمنفذ'));
      return;
    }
    await TelegramProxy.save(c);
    if (enable != null) await TelegramProxy.setEnabled(enable);
    if (!mounted) return;
    setState(() => _enabled = enable ?? _enabled);
    setToast(context, _enabled ? 'حُفظ — رفع تيليجرام يمر عبر البروكسي' : 'حُفظ (البروكسي مطفأ)');
  }

  Future<void> _toggle(bool v) async {
    if (v && _form() == null) {
      setState(() => _result = (false, 'أدخل بروكسي واضغط «اختبار» قبل التشغيل'));
      return;
    }
    if (v) {
      await _save(enable: true);
    } else {
      await TelegramProxy.setEnabled(false);
      if (!mounted) return;
      setState(() => _enabled = false);
      setToast(context, 'أُطفئ البروكسي — تيليجرام يرفع مباشرة');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'تيليجرام عند الحظر',
      subtitle: 'رفع تيليجرام عبر بروكسي SOCKS5 أو HTTP',
      icon: Icons.vpn_lock_rounded,
      loading: !_loaded,
      children: !_loaded ? null : _content(),
    );
  }

  List<Widget> _content() => [
        SetHero(
          icon: Icons.vpn_lock_rounded,
          color: _tg,
          title: 'بروكسي لرفع تيليجرام فقط',
          text: 'عندما يُحظر تيليجرام: شغّل هذا الخيار فيمر رفع تيليجرام وحده عبر البروكسي، وبقية البرنامج لا يتأثر. '
              'وهو مطفأ يرفع البرنامج مباشرة كما كان.',
          status: SetStatusPill(_enabled ? 'يعمل عبر البروكسي' : 'مطفأ — اتصال مباشر', ok: _enabled),
        ),
        SetCard(
          title: 'البروكسي',
          subtitle: 'من قنوات تيليجرام، أو من برنامج VPN على هذه الحاسبة',
          icon: Icons.settings_ethernet_rounded,
          color: _tg,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 6),
            SetSwitch(
              title: 'رفع تيليجرام عبر البروكسي',
              subtitle: _enabled ? 'مفعّل' : 'مطفأ',
              icon: Icons.power_settings_new_rounded,
              color: _tg,
              value: _enabled,
              onChanged: _busy ? null : _toggle,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _paste,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'ألصق رابط البروكسي هنا (اختياري)',
                hintText: 'tg://socks?server=… أو socks5://… أو 127.0.0.1:10808',
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: IconButton(
                  tooltip: 'لصق',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async {
                    final d = await Clipboard.getData(Clipboard.kTextPlain);
                    if (d?.text != null) _onPaste(d!.text!);
                  },
                ),
              ),
              onChanged: (v) {
                if (v.length > 8) _onPaste(v);
              },
            ),
            const SizedBox(height: 12),
            SegmentedButton<TgProxyType>(
              segments: const [
                ButtonSegment(value: TgProxyType.socks5, label: Text('SOCKS5'), icon: Icon(Icons.hub_outlined)),
                ButtonSegment(value: TgProxyType.http, label: Text('HTTP'), icon: Icon(Icons.http_rounded)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _host,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'العنوان', hintText: '127.0.0.1', prefixIcon: Icon(Icons.dns_rounded)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _port,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                  decoration: const InputDecoration(labelText: 'المنفذ', hintText: '10808'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _user,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'اسم المستخدم (إن وُجد)', prefixIcon: Icon(Icons.person_outline_rounded)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _pass,
                  textDirection: TextDirection.ltr,
                  obscureText: !_showPass,
                  decoration: InputDecoration(
                    labelText: 'كلمة السر (إن وُجدت)',
                    suffixIcon: IconButton(
                      icon: Icon(_showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                      onPressed: () => setState(() => _showPass = !_showPass),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: SetPrimaryButton(
                  label: 'اختبار',
                  icon: Icons.network_check_rounded,
                  color: _tg,
                  busy: _busy,
                  onPressed: _busy ? null : _test,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50), foregroundColor: _tg),
                  onPressed: _busy ? null : () => _save(),
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('حفظ'),
                ),
              ),
            ]),
            if (_result != null) ...[
              const SizedBox(height: 12),
              SetBanner(_result!.$2, kind: _result!.$1 ? SetBannerKind.ok : SetBannerKind.error),
            ],
          ]),
        ),
        SetCard(
          title: 'من أين أحصل على بروكسي؟',
          icon: Icons.help_outline_rounded,
          color: kSetNavy,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 6),
            SetupGuide(color: _tg, steps: const [
              GuideStep(
                'من برنامج VPN على هذه الحاسبة (مثل v2rayN أو Hiddify): شغّله، ثم اكتب هنا العنوان 127.0.0.1 والمنفذ الذي يعرضه البرنامج.',
                note: 'في v2rayN عادةً: SOCKS5 على 10808، و HTTP على 10809.',
              ),
              GuideStep(
                'من قنوات تيليجرام: انسخ رابط بروكسي من نوع SOCKS5 (يبدأ بـ tg://socks أو t.me/socks) والصقه في الخانة أعلاه.',
                note: 'روابط tg://proxy التي فيها secret هي MTProto — لا تعمل في هذه الشاشة.',
              ),
              GuideStep('اضغط «اختبار». إن نجح فشغّل المفتاح أعلاه — من الآن كل رفع إلى تيليجرام يمر عبره.'),
            ]),
            const SizedBox(height: 10),
            const SetBanner(
              'الاتصال مشفّر من البرنامج إلى تيليجرام نفسه، والتحقق من شهادته كامل: البروكسي لا يقرأ توكن البوت ولا الملفات. '
              'إن ظهر خطأ «فشل التحقق من الشهادة» فالبروكسي يحاول التجسس — لا تستعمله.',
              kind: SetBannerKind.info,
            ),
          ]),
        ),
      ];
}
