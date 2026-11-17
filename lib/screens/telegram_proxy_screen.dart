// lib/screens/telegram_proxy_screen.dart
//
// 🧦 تيليجرام عند الحظر — رفع تيليجرام عبر بروكسي SOCKS5 أو HTTP.
// إضافة اختيارية: وهي مطفأة يرفع البرنامج مباشرة كما كان دائماً.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings_manager.dart';
import '../services/telegram_net/tdlib_engine.dart';
import '../services/telegram_net/telegram_mtproto.dart';
import '../services/telegram_net/telegram_proxy.dart';
import '../services/telegram_net/tor_engine.dart';
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
      setState(() => _result = (false, 'هذا رابط MTProto (فيه secret) — الصقه في بطاقة «MTProto — الطريقة المميزة» أعلاه.'));
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
      subtitle: 'طريقتان إضافيتان — والمباشرة باقية كما هي',
      icon: Icons.vpn_lock_rounded,
      loading: !_loaded,
      children: !_loaded ? null : _content(),
    );
  }

  List<Widget> _content() => [
        SetHero(
          icon: Icons.vpn_lock_rounded,
          color: _tg,
          title: 'رفع تيليجرام رغم الحظر',
          text: 'ثلاث طرق تخصّان رفع تيليجرام وحده (بقية البرنامج لا تتأثر): MTProto المميزة بروابط القنوات، '
              'و Tor التلقائي بلا أي إعداد، وبروكسي SOCKS5/HTTP. وكلها مطفأة يرفع البرنامج مباشرة كما كان.',
          status: SetStatusPill(_enabled ? 'بروكسي SOCKS/HTTP يعمل' : 'بروكسي SOCKS/HTTP مطفأ', ok: _enabled),
        ),
        const _MtprotoCard(),
        const _TorCard(),
        SetCard(
          title: 'الطريقة الثانية — بروكسي SOCKS5 / HTTP',
          subtitle: 'من قنوات تيليجرام، أو من برنامج VPN على هذه الحاسبة (تُستعمل حين تكون MTProto و Tor مطفأتين)',
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

// ═══════════════════════ ⭐ MTProto — الطريقة المميزة ═══════════════════════

class _MtprotoCard extends StatefulWidget {
  const _MtprotoCard();

  @override
  State<_MtprotoCard> createState() => _MtprotoCardState();
}

class _MtprotoCardState extends State<_MtprotoCard> {
  static const _a = Color(0xFF6D28D9); // بنفسجي مميز
  static const _b = Color(0xFF229ED9); // أزرق تيليجرام

  final _link = TextEditingController();
  bool _loaded = false;
  bool _installed = false;
  bool _installing = false;
  String _step = '';
  double? _progress;
  bool _enabled = false;
  List<String> _links = const [];
  bool _busy = false;
  (bool, String)? _result;

  bool get _creds => TelegramMtproto.hasCredentials;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final inst = await TdlibEngine.isInstalled();
    final en = await TelegramMtproto.isEnabled();
    final links = await TelegramMtproto.proxies();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _installed = inst;
      _enabled = en;
      _links = links;
    });
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _step = 'جارٍ البدء…';
      _progress = null;
      _result = null;
    });
    try {
      await TdlibEngine.install(step: (t, [f]) {
        if (mounted) {
          setState(() {
            _step = t;
            _progress = f;
          });
        }
      });
      if (mounted) setToast(context, 'تم تثبيت محرك MTProto');
    } catch (e) {
      if (mounted) setState(() => _result = (false, '$e'));
    }
    if (mounted) setState(() => _installing = false);
    await _load();
  }

  Future<void> _addLink([String? raw]) async {
    final v = (raw ?? _link.text).trim();
    if (v.isEmpty) return;
    if (TelegramMtproto.proxyJson(v) == null) {
      setState(() => _result = (false, 'هذا ليس رابط بروكسي تيليجرام (يبدأ بـ tg://proxy أو t.me/proxy أو tg://socks)'));
      return;
    }
    if (_links.contains(v)) {
      setState(() => _result = (false, 'الرابط موجود في القائمة'));
      return;
    }
    final l = [..._links, v];
    await TelegramMtproto.setProxies(l);
    _link.clear();
    setState(() {
      _links = l;
      _result = (true, 'أُضيف: ${TelegramMtproto.proxyLabel(v)}');
    });
    await TelegramMtproto.reapply().catchError((_) {});
  }

  Future<void> _remove(String v) async {
    final l = [..._links]..remove(v);
    await TelegramMtproto.setProxies(l);
    setState(() => _links = l);
  }

  Future<void> _moveFirst(String v) async {
    final l = [v, ..._links.where((x) => x != v)];
    await TelegramMtproto.setProxies(l);
    setState(() => _links = l);
  }

  Future<String?> _token() async {
    final t = (await SettingsManager.getAppSettings()).telegramBotToken ?? '';
    return t.isEmpty ? null : t;
  }

  Future<void> _test() async {
    final token = await _token();
    if (token == null) {
      setState(() => _result = (false, 'أدخل توكن البوت أولاً في إعدادات تيليجرام'));
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final name = await TelegramMtproto.test(token);
      if (!mounted) return;
      setState(() => _result = (true, 'نجح: البوت $name متصل عبر ${TelegramMtproto.lastProxyUsed ?? 'MTProto'}'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _result = (false, '$e'.replaceFirst(RegExp(r'^TDLib \d+: '), '')));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggle(bool v) async {
    await TelegramMtproto.setEnabled(v);
    if (!mounted) return;
    setState(() => _enabled = v);
    setToast(context, v ? 'رفع تيليجرام صار عبر MTProto' : 'أُطفئت MTProto — الرفع كما كان');
  }

  @override
  Widget build(BuildContext context) {
    final ready = _creds && _installed;
    return Semantics(
      container: true,
      label: 'MTProto الطريقة المميزة',
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(1.6), // إطار متدرّج
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [_a, _b], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
          boxShadow: [BoxShadow(color: _a.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20.5)),
          child: !_loaded
              ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _header(),
                  const SizedBox(height: 10),
                  const Text(
                    'تعمل مع روابط البروكسي المنشورة في قنوات تيليجرام (tg://proxy… فيها secret). '
                    'الاتصال مشفّر من البرنامج إلى تيليجرام نفسه — البروكسي لا يقرأ شيئاً — وحد الملف 2 غيغا بدل 50 ميغا.',
                    style: TextStyle(color: kSetMuted, height: 1.55, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  if (!_creds)
                    const SetBanner(
                      'هذه النسخة من البرنامج بُنيت بلا بيانات التطبيق (api_id / api_hash) — تُضاف عند البناء، ولا يُدخلها الزبون.',
                      kind: SetBannerKind.warn,
                    )
                  else ...[
                    _stepTitle('1', 'محرك MTProto على هذه الحاسبة'),
                    AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: _engine()),
                    const SizedBox(height: 16),
                    _stepTitle('2', 'روابط البروكسي (يُجرَّب الأول فالأول)'),
                    _linkField(ready),
                    const SizedBox(height: 8),
                    ..._links.map(_linkTile),
                    if (_links.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text('بلا روابط: يتصل مباشرة بلغة MTProto (يكفي إن حُظرت واجهة البوت فقط).',
                            style: TextStyle(color: kSetMuted, fontSize: 12.5)),
                      ),
                    const SizedBox(height: 14),
                    _stepTitle('3', 'التشغيل'),
                    SetSwitch(
                      title: 'رفع تيليجرام عبر MTProto',
                      subtitle: _enabled ? 'مفعّل — نفس البوت والقناة والمحتوى' : 'مطفأ — الرفع كما كان',
                      icon: Icons.bolt_rounded,
                      color: _a,
                      value: _enabled,
                      onChanged: (!ready || _busy) ? null : _toggle,
                    ),
                    const SizedBox(height: 8),
                    SetPrimaryButton(
                      label: 'اختبار الاتصال',
                      icon: Icons.network_check_rounded,
                      color: _a,
                      busy: _busy,
                      onPressed: (!ready || _busy) ? null : _test,
                    ),
                  ],
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    child: _result == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: SetBanner(_result!.$2, kind: _result!.$1 ? SetBannerKind.ok : SetBannerKind.error),
                          ),
                  ),
                ]),
        ),
      ),
    );
  }

  Widget _header() => Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(colors: [_a, _b]),
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('MTProto', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kSetText)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(colors: [_a, _b]),
          ),
          child: const Text('الطريقة المميزة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
        ),
      ]);

  Widget _stepTitle(String n, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          CircleAvatar(radius: 11, backgroundColor: _a.withValues(alpha: 0.12), child: Text(n, style: const TextStyle(color: _a, fontSize: 12, fontWeight: FontWeight.w900))),
          const SizedBox(width: 8),
          Text(t, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
        ]),
      );

  Widget _engine() {
    if (_installing) {
      return Column(key: const ValueKey('ing'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: _progress, color: _a, minHeight: 6)),
        const SizedBox(height: 6),
        Text(_step, style: const TextStyle(color: kSetMuted, fontSize: 12.5)),
      ]);
    }
    if (_installed) {
      return Row(key: const ValueKey('ok'), children: [
        const Icon(Icons.verified_rounded, color: kSetGreen, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text('مثبّت (TDLib ${TdlibEngine.version}) وبصمته مطابقة لفهرس NuGet',
              style: const TextStyle(color: kSetGreen, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ]);
    }
    return SetPrimaryButton(
      key: const ValueKey('btn'),
      label: 'تثبيت محرك MTProto (مرة واحدة)',
      icon: Icons.download_rounded,
      color: _a,
      onPressed: _install,
    );
  }

  Widget _linkField(bool ready) => TextField(
        controller: _link,
        textDirection: TextDirection.ltr,
        enabled: _installed,
        decoration: InputDecoration(
          labelText: 'ألصق رابط بروكسي من القنوات',
          hintText: 'tg://proxy?server=…&port=…&secret=…',
          prefixIcon: const Icon(Icons.link_rounded),
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'لصق',
              icon: const Icon(Icons.content_paste_rounded),
              onPressed: !_installed
                  ? null
                  : () async {
                      final d = await Clipboard.getData(Clipboard.kTextPlain);
                      if (d?.text != null) await _addLink(d!.text);
                    },
            ),
            IconButton(
              tooltip: 'إضافة',
              icon: const Icon(Icons.add_circle_rounded, color: _a),
              onPressed: !_installed ? null : () => _addLink(),
            ),
          ]),
        ),
        onSubmitted: (_) => _addLink(),
      );

  Widget _linkTile(String v) {
    final first = _links.isNotEmpty && _links.first == v;
    final used = TelegramMtproto.lastProxyUsed == TelegramMtproto.proxyLabel(v);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: used ? kSetGreen.withValues(alpha: 0.07) : kSetBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: used ? kSetGreen.withValues(alpha: 0.35) : kSetBorder),
      ),
      child: Row(children: [
        Icon(used ? Icons.check_circle_rounded : Icons.vpn_key_outlined, size: 18, color: used ? kSetGreen : kSetMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(TelegramMtproto.proxyLabel(v),
              textDirection: TextDirection.ltr, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        if (!first)
          IconButton(
            tooltip: 'جعله الأول',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.vertical_align_top_rounded, size: 20),
            onPressed: () => _moveFirst(v),
          ),
        IconButton(
          tooltip: 'حذف',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.delete_outline_rounded, size: 20, color: kSetRed),
          onPressed: () => _remove(v),
        ),
      ]),
    );
  }
}

// ═══════════════════════ 🧅 Tor — تلقائي بلا إعداد ═══════════════════════

class _TorCard extends StatefulWidget {
  const _TorCard();

  @override
  State<_TorCard> createState() => _TorCardState();
}

class _TorCardState extends State<_TorCard> {
  static const _c = Color(0xFF7D4698); // بنفسجي Tor

  bool _loaded = false;
  bool _installed = false;
  String? _version;
  bool _installing = false;
  String _step = '';
  double? _progress;
  bool _enabled = false;
  TorStartMode _mode = TorStartMode.onUpload;
  bool _busy = false;
  (bool, String)? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inst = await TorEngine.isInstalled();
    final ver = await TorEngine.installedVersion();
    final en = await TorEngine.isEnabled();
    final mode = await TorEngine.startMode();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _installed = inst;
      _version = ver;
      _enabled = en;
      _mode = mode;
    });
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _step = 'جارٍ البدء…';
      _progress = null;
      _result = null;
    });
    try {
      await TorEngine.install(step: (t, [f]) {
        if (mounted) {
          setState(() {
            _step = t;
            _progress = f;
          });
        }
      });
      if (mounted) setToast(context, 'تم تثبيت Tor');
    } catch (e) {
      if (mounted) setState(() => _result = (false, '$e'));
    }
    if (mounted) setState(() => _installing = false);
    await _load();
  }

  Future<void> _toggle(bool v) async {
    await TorEngine.setEnabled(v);
    if (!mounted) return;
    setState(() => _enabled = v);
    setToast(context, v ? 'رفع تيليجرام صار عبر Tor' : 'أُطفئ Tor — الرفع كما كان');
    if (v && _mode == TorStartMode.onAppStart) TorEngine.autoStart();
  }

  Future<void> _setMode(TorStartMode m) async {
    await TorEngine.setStartMode(m);
    if (!mounted) return;
    setState(() => _mode = m);
    if (_enabled && m == TorStartMode.onAppStart) TorEngine.autoStart();
  }

  Future<void> _test() async {
    final token = (await SettingsManager.getAppSettings()).telegramBotToken ?? '';
    if (token.isEmpty) {
      setState(() => _result = (false, 'أدخل توكن البوت أولاً في إعدادات تيليجرام'));
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final port = await TorEngine.ensureRunning();
      final err = await TelegramProxy.test(TgProxyConfig(type: TgProxyType.socks5, host: '127.0.0.1', port: port), token);
      if (!mounted) return;
      setState(() => _result = err == null ? (true, 'نجح: وصل البرنامج إلى تيليجرام عبر Tor') : (false, err));
    } catch (e) {
      if (!mounted) return;
      setState(() => _result = (false, '$e'));
    }
    if (mounted) setState(() => _busy = false);
  }

  void _showLog() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('سجل Tor'),
        content: SizedBox(
          width: 560,
          height: 360,
          child: ValueListenableBuilder<List<String>>(
            valueListenable: TorEngine.log,
            builder: (_, l, __) => l.isEmpty
                ? const Center(child: Text('لا شيء بعد', style: TextStyle(color: kSetMuted)))
                : SelectableText(l.join('\n'), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SetCard(
      title: 'Tor — تلقائي بلا إعداد',
      subtitle: 'لا روابط ولا أرقام: يتصل بنفسه عبر جسر Snowflake (أبطأ من غيره)',
      icon: Icons.shield_moon_rounded,
      color: _c,
      child: !_loaded
          ? const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 6),
              const Text(
                'Tor شبكة مجانية مفتوحة المصدر لتجاوز الحجب. الاتصال مشفّر من البرنامج إلى تيليجرام نفسه: '
                'محطات Tor ترى «اتصالاً بتيليجرام» فقط ولا تقرأ التوكن ولا الملفات.',
                style: TextStyle(color: kSetMuted, height: 1.55, fontSize: 13),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _installing
                    ? Column(key: const ValueKey('ing'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: _progress, color: _c, minHeight: 6)),
                        const SizedBox(height: 6),
                        Text(_step, style: const TextStyle(color: kSetMuted, fontSize: 12.5)),
                      ])
                    : _installed
                        ? Row(key: const ValueKey('ok'), children: [
                            const Icon(Icons.verified_rounded, color: kSetGreen, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Tor مثبّت${_version != null ? ' ($_version)' : ''} وبصمته مطابقة للمنشورة',
                                  style: const TextStyle(color: kSetGreen, fontWeight: FontWeight.w700, fontSize: 13)),
                            ),
                          ])
                        : SetPrimaryButton(
                            key: const ValueKey('btn'),
                            label: 'تثبيت Tor (مرة واحدة)',
                            icon: Icons.download_rounded,
                            color: _c,
                            onPressed: _install,
                          ),
              ),
              const SizedBox(height: 10),
              SetSwitch(
                title: 'رفع تيليجرام عبر Tor',
                subtitle: _enabled ? 'مفعّل' : 'مطفأ — الرفع كما كان',
                icon: Icons.power_settings_new_rounded,
                color: _c,
                value: _enabled,
                onChanged: (!_installed || _busy) ? null : _toggle,
              ),
              const SizedBox(height: 8),
              const Text('متى يبدأ الاتصال؟', style: TextStyle(fontWeight: FontWeight.w700, color: kSetText)),
              const SizedBox(height: 6),
              SegmentedButton<TorStartMode>(
                segments: const [
                  ButtonSegment(value: TorStartMode.onUpload, label: Text('عند ضغط «رفع البيانات»'), icon: Icon(Icons.cloud_upload_outlined)),
                  ButtonSegment(value: TorStartMode.onAppStart, label: Text('عند فتح البرنامج'), icon: Icon(Icons.rocket_launch_outlined)),
                ],
                selected: {_mode},
                onSelectionChanged: (!_installed) ? null : (s) => _setMode(s.first),
              ),
              const SizedBox(height: 4),
              Text(
                _mode == TorStartMode.onUpload
                    ? 'يتصل أولاً ثم يرفع — قد يأخذ دقيقة أو اثنتين في أول رفع.'
                    : 'يتصل في الخلفية مع فتح البرنامج، فيبدأ الرفع فوراً عند الضغط.',
                style: const TextStyle(color: kSetMuted, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<int>(
                valueListenable: TorEngine.bootstrap,
                builder: (_, b, __) => (_busy && b < 100)
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: b / 100, color: _c, minHeight: 6)),
                          const SizedBox(height: 4),
                          Text('الاتصال بشبكة Tor: $b%', style: const TextStyle(color: kSetMuted, fontSize: 12.5)),
                        ]),
                      )
                    : const SizedBox.shrink(),
              ),
              Row(children: [
                Expanded(
                  child: SetPrimaryButton(
                    label: 'اختبار الاتصال',
                    icon: Icons.network_check_rounded,
                    color: _c,
                    busy: _busy,
                    onPressed: (!_installed || _busy) ? null : _test,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(tooltip: 'سجل Tor', onPressed: _showLog, icon: const Icon(Icons.article_outlined)),
              ]),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                child: _result == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SetBanner(_result!.$2, kind: _result!.$1 ? SetBannerKind.ok : SetBannerKind.error),
                      ),
              ),
            ]),
    );
  }
}
