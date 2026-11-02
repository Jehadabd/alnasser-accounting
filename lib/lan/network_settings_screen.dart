// lib/lan/network_settings_screen.dart
//
// 🖧 إعداد الشبكة المحلية: مستقل / سيرفر / طرفية.
// الواجهة بطقم شاشات الإعدادات الموحّد (settings_kit): بطاقة حالة في الأعلى،
// اختيار الوضع، ثم بطاقات الوضع المختار — والمنطق (التحميل، البحث، الاختبار،
// الحفظ) كما هو.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lan_bootstrap.dart';
import 'lan_client.dart';
import 'lan_codec.dart';
import 'lan_server.dart';
import 'lan_settings.dart';
import 'windows_autostart.dart';
import '../services/license_service.dart';
import '../widgets/settings_kit.dart';

class NetworkSettingsScreen extends StatefulWidget {
  const NetworkSettingsScreen({super.key});

  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  LanSettings _s = const LanSettings();
  LanMode _mode = LanMode.standalone;
  final _host = TextEditingController();
  final _port = TextEditingController(text: '$lanDefaultPort');
  final _secret = TextEditingController();
  final _serverName = TextEditingController();
  final _clientName = TextEditingController();
  List<String> _ips = const [];
  List<Map<String, Object?>> _found = const [];
  bool _searching = false;
  String? _testResult;
  bool _autoStart = true;
  String? _pickedServerName;
  String? _autoSecret; // رمز وُلّد تلقائياً للسيرفر — لا يُعرض في وضع الطرفية
  final _secretFocus = FocusNode();
  StreamSubscription<List<LanClientInfo>>? _sub;
  List<LanClientInfo> _clients = const [];

  @override
  void initState() {
    super.initState();
    _load();
    final srv = LanRuntime.server;
    if (srv != null) {
      _clients = srv.clients;
      _sub = srv.clientsStream.listen((c) {
        if (mounted) setState(() => _clients = c);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _secretFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await LanSettings.load();
    final ips = <String>[];
    try {
      for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in ni.addresses) {
          if (!a.isLoopback) ips.add('${a.address}  (${ni.name})');
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _s = s;
      _mode = s.mode;
      _host.text = s.host;
      _port.text = '${s.port}';
      if (s.secret.isEmpty) {
        // الطرفية تكتب رمز السيرفر بنفسها؛ الرمز المولَّد للسيرفر فقط
        _autoSecret = LanSettings.generateSecret();
        _secret.text = s.mode == LanMode.client ? '' : _autoSecret!;
      } else {
        _secret.text = s.secret;
      }
      _serverName.text = s.serverName.isEmpty ? Platform.localHostname : s.serverName;
      _clientName.text = s.clientName;
      _autoStart = s.autoStart;
      _ips = ips;
    });
  }

  Future<void> _discover() async {
    setState(() {
      _searching = true;
      _found = const [];
    });
    // هذه الحاسبة نفسها ليست سيرفراً لنفسها: لا تظهر في القائمة
    final me = Platform.localHostname.trim().toLowerCase();
    final f = (await discoverLanServers())
        .where((x) => !_ips.contains('${x['host']}') && '${x['name'] ?? ''}'.trim().toLowerCase() != me)
        .toList();
    if (!mounted) return;
    setState(() {
      _searching = false;
      _found = f;
    });
    if (f.length == 1) _pick(f.first);
  }

  /// اختيار سيرفر من نتائج البحث: يملأ العنوان والمنفذ ويوضح الخطوة التالية.
  void _pick(Map<String, Object?> f) {
    setState(() {
      _host.text = '${f['host']}';
      _port.text = '${f['port'] ?? lanDefaultPort}';
      _pickedServerName = '${f['name'] ?? ''}';
      _testResult = null;
    });
    final hasCode = (_secret.text.trim().isNotEmpty && _secret.text != _autoSecret) ||
        (LicenseService().currentToken ?? '').isNotEmpty; // أجهزة الترخيص نفسه لا تحتاج الرمز
    setToast(
        context,
        hasCode
            ? 'اخترت «${f['name']}» (${f['host']}). جارٍ اختبار الاتصال...'
            : 'اخترت «${f['name']}» (${f['host']}). الآن اكتب «رمز الربط» الظاهر في شاشة السيرفر، ثم «اختبار الاتصال» ثم «حفظ».');
    if (hasCode) {
      _test();
    } else {
      _secretFocus.requestFocus();
    }
  }

  Future<void> _test() async {
    setState(() => _testResult = 'جارٍ الاختبار...');
    final conn = LanClientConnection(
      host: _host.text.trim(),
      port: int.tryParse(_port.text) ?? lanDefaultPort,
      secret: _secret.text.trim().toUpperCase(),
      clientName: '${_clientName.text.trim()} (اختبار)',
      licenseToken: LicenseService().currentToken ?? '',
    );
    try {
      await conn.connect();
      await conn.close();
      if (mounted) setState(() => _testResult = '✓ الاتصال ناجح ورمز الربط صحيح');
    } catch (e) {
      if (mounted) setState(() => _testResult = '✗ $e');
    }
  }

  Future<void> _save() async {
    final next = _s.copyWith(
      mode: _mode,
      host: _host.text.trim(),
      port: int.tryParse(_port.text) ?? lanDefaultPort,
      secret: _secret.text.trim().toUpperCase(),
      // الطرفية تحفظ اسم السيرفر الذي اختارته لتجده إن تغيّر عنوانه
      serverName: _mode == LanMode.client ? (_pickedServerName ?? _s.serverName) : _serverName.text.trim(),
      clientName: _clientName.text.trim(),
      autoStart: _autoStart,
    );
    final hasLic = (LicenseService().currentToken ?? '').isNotEmpty;
    if (next.isClient && Platform.isWindows && await LanRuntime.pointsToThisPc(next)) {
      if (!mounted) return;
      setToast(
          context,
          'هذا العنوان هو هذه الحاسبة نفسها. إن كانت قاعدة البيانات هنا فاختر «سيرفر»، '
          'و«طرفية» فقط على الأجهزة الأخرى.',
          error: true);
      return;
    }
    if (next.isClient && (next.host.isEmpty || (next.secret.isEmpty && !hasLic))) {
      if (!mounted) return;
      setToast(context, 'أدخل عنوان السيرفر ورمز الربط', error: true);
      return;
    }
    await next.save();
    WindowsAutostart.sync(next.isServer && next.autoStart);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حُفظ إعداد الشبكة'),
        content: Text(switch (_mode) {
          LanMode.server =>
            'أعد تشغيل البرنامج على هذه الحاسبة ليعمل كسيرفر'
                '${next.autoStart ? ' (ومن الآن يفتح وحده عند تشغيل الحاسبة)' : ''}. '
                'ثم على كل طرفية اختر «طرفية» وأدخل رمز الربط:\n\n${next.secret}',
          LanMode.client =>
            'أعد تشغيل البرنامج ليتصل بالسيرفر. من الآن كل البيانات تُقرأ وتُكتب في قاعدة السيرفر.',
          LanMode.standalone => 'أعد تشغيل البرنامج ليعمل على قاعدة هذه الحاسبة وحدها.',
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لاحقاً')),
          FilledButton(
            onPressed: LanRuntime.relaunch,
            child: Text(Platform.isWindows ? 'إعادة تشغيل البرنامج الآن' : 'إغلاق البرنامج الآن'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════ الواجهة ═══════════════════════════

  static const _modes = <LanMode, (IconData, String, String, Color)>{
    LanMode.standalone: (Icons.computer_rounded, 'جهاز مستقل', 'قاعدة بيانات على هذا الجهاز وحده', kSetNavy),
    LanMode.server: (Icons.dns_rounded, 'حاسبة السيرفر', 'تحمل قاعدة البيانات وتخدم باقي الأجهزة', kSetGreen),
    LanMode.client: (Icons.lan_rounded, 'طرفية', 'تعمل على قاعدة السيرفر عبر شبكة المحل', kSetBlue),
  };

  void _selectMode(LanMode m) => setState(() {
        _mode = m;
        if (m == LanMode.client && _secret.text == _autoSecret) _secret.text = '';
        if (m == LanMode.server && _secret.text.trim().isEmpty) {
          _autoSecret ??= LanSettings.generateSecret();
          _secret.text = _autoSecret!;
        }
      });

  Widget _hero(bool running) {
    final saved = _modes[_s.mode]!;
    final (String status, bool ok) = switch (_s.mode) {
      LanMode.server => (
          running ? 'السيرفر يعمل — ${_clients.length} طرفية متصلة' : 'محفوظ كسيرفر لكنه لا يعمل الآن — أعد تشغيل البرنامج',
          running
        ),
      LanMode.client => (
          _s.host.isEmpty
              ? 'طرفية بلا عنوان سيرفر'
              : 'متصلة بـ ${_s.serverName.isEmpty ? _s.host : '«${_s.serverName}» (${_s.host})'}',
          _s.host.isNotEmpty
        ),
      LanMode.standalone => ('يعمل وحده — لا شبكة', true),
    };
    return SetHero(
      icon: saved.$1,
      color: saved.$4,
      title: 'هذا الجهاز: ${saved.$2}',
      text: 'اربط حاسبات المحل وأجهزة التابلت على قاعدة بيانات واحدة عبر الراوتر — بلا إنترنت. '
          'جهاز واحد «سيرفر» يحمل البيانات، والباقي «طرفيات».',
      status: SetStatusPill(status, ok: ok),
    );
  }

  Widget _modeTile(LanMode m) {
    final (icon, title, desc, color) = _modes[m]!;
    final sel = _mode == m;
    final current = _s.mode == m;
    return Expanded(
      child: Semantics(
        button: true,
        selected: sel,
        label: title,
        child: InkWell(
          onTap: () => _selectMode(m),
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
            decoration: BoxDecoration(
              color: sel ? color : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: sel ? color : kSetBorder, width: sel ? 1.6 : 1),
              boxShadow: [
                BoxShadow(
                  color: sel ? color.withValues(alpha: 0.28) : const Color(0x0A0F172A),
                  blurRadius: sel ? 18 : 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: sel ? Colors.white.withValues(alpha: 0.16) : color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 28, color: sel ? Colors.white : color),
              ),
              const SizedBox(height: 10),
              Text(title,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: sel ? Colors.white : kSetText)),
              const SizedBox(height: 4),
              Text(desc,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.4, color: sel ? Colors.white70 : kSetMuted)),
              const SizedBox(height: 8),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: current ? 1 : 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: sel ? Colors.white.withValues(alpha: 0.18) : color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('الوضع الحالي',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: sel ? Colors.white : color)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ─── السيرفر ───

  Widget _secretCard() => SetCard(
        title: 'رمز الربط',
        subtitle: 'يُكتب في كل طرفية مرة واحدة (أجهزة الترخيص نفسه لا تحتاجه)',
        icon: Icons.key_rounded,
        color: kSetGreen,
        child: Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kSetGreen.withValues(alpha: 0.25)),
              ),
              child: SelectableText(
                _secret.text,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                    fontSize: 24, letterSpacing: 3, fontWeight: FontWeight.w900, color: kSetGreen, fontFamily: 'monospace'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(mainAxisSize: MainAxisSize.min, children: [
            IconButton.filledTonal(
              tooltip: 'نسخ',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _secret.text));
                setToast(context, 'نُسخ رمز الربط');
              },
            ),
            const SizedBox(height: 6),
            IconButton(
              tooltip: 'رمز جديد',
              icon: const Icon(Icons.refresh_rounded, color: kSetOrange),
              onPressed: _newSecret,
            ),
          ]),
        ]),
      );

  Future<void> _newSecret() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رمز ربط جديد؟'),
        content: const Text('بعد الحفظ وإعادة التشغيل لن تتصل الطرفيات الحالية حتى تكتب الرمز الجديد في كل واحدة منها '
            '(عدا أجهزة الترخيص نفسه).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kSetOrange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('رمز جديد'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _secret.text = LanSettings.generateSecret());
  }

  Widget _addressCard() => SetCard(
        title: 'عنوان هذه الحاسبة',
        subtitle: 'الطرفيات تجده وحدها بالبحث — أو تكتبه يدوياً',
        icon: Icons.router_rounded,
        color: kSetGreen,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_ips.isEmpty) const SetBanner('لم يُعثر على شبكة — تأكد أن الحاسبة متصلة بالراوتر.', kind: SetBannerKind.warn),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final ip in _ips)
              ActionChip(
                avatar: const Icon(Icons.lan_outlined, size: 18, color: kSetGreen),
                label: Text(ip, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
                tooltip: 'نسخ العنوان',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: ip.split(' ').first));
                  setToast(context, 'نُسخ العنوان');
                },
              ),
          ]),
          const SizedBox(height: 10),
          Text(
            'المنفذ ${_port.text} (TCP) و$lanDiscoveryPort (UDP للبحث). إن لم تجد الطرفيات السيرفر فاسمح بهما في جدار الحماية.',
            style: const TextStyle(color: kSetMuted, fontSize: 12.5, height: 1.5),
          ),
        ]),
      );

  Widget _serverOptionsCard() => SetCard(
        title: 'السيرفر',
        icon: Icons.tune_rounded,
        color: kSetGreen,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          TextField(
            controller: _serverName,
            decoration: const InputDecoration(
              labelText: 'اسم السيرفر (يظهر للطرفيات عند البحث)',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          if (!Platform.isAndroid && !Platform.isIOS) ...[
            const SizedBox(height: 6),
            SetSwitch(
              title: 'تشغيل البرنامج تلقائياً عند تشغيل الحاسبة',
              subtitle: WindowsAutostart.supported
                  ? (WindowsAutostart.isEnabled()
                      ? 'مفعّل: بعد إطفاء الحاسبة وتشغيلها يفتح البرنامج ويعمل كسيرفر وحده'
                      : 'يبقى هذا الجهاز سيرفراً بعد إطفاء الحاسبة وتشغيلها، حتى تغيّر الوضع من هنا')
                  : 'يعمل في النسخة المثبّتة من البرنامج',
              icon: Icons.power_settings_new_rounded,
              color: kSetGreen,
              value: _autoStart,
              onChanged: (v) => setState(() => _autoStart = v),
            ),
          ],
        ]),
      );

  Widget _clientsCard(bool running) => SetCard(
        title: 'الطرفيات المتصلة',
        subtitle: running ? null : 'تظهر هنا بعد تشغيل السيرفر',
        icon: Icons.devices_other_rounded,
        color: kSetGreen,
        trailing: SetStatusPill(running ? '${_clients.length} متصلة' : 'متوقف', ok: running),
        child: _clients.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('لا طرفية متصلة الآن.', style: TextStyle(color: kSetMuted)),
              )
            : Column(children: [
                for (final c in _clients)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration:
                          BoxDecoration(color: kSetGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
                      child: const Icon(Icons.computer_rounded, color: kSetGreen, size: 20),
                    ),
                    title: Text(c.clientName.isEmpty ? 'طرفية' : c.clientName,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${c.address} • منذ ${TimeOfDay.fromDateTime(c.connectedAt).format(context)} • ${c.requestCount} طلب',
                        style: const TextStyle(fontSize: 12.5, color: kSetMuted)),
                  ),
              ]),
      );

  // ─── الطرفية ───

  Widget _findCard() => SetCard(
        title: '1. ابحث عن السيرفر',
        subtitle: 'على نفس شبكة المحل — أو اكتب عنوانه يدوياً في الخطوة التالية',
        icon: Icons.travel_explore_rounded,
        color: kSetBlue,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kSetBlue),
              onPressed: _searching ? null : _discover,
              icon: _searching
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search_rounded),
              label: Text(_searching ? 'جارٍ البحث...' : 'ابحث عن السيرفر'),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: Column(children: [
              for (final f in _found) _foundTile(f),
            ]),
          ),
        ]),
      );

  Widget _foundTile(Map<String, Object?> f) {
    final picked = _host.text.trim() == '${f['host']}';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: picked ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: picked ? kSetGreen : kSetBorder, width: picked ? 1.5 : 1),
      ),
      child: ListTile(
        onTap: () => _pick(f),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(picked ? Icons.check_circle_rounded : Icons.dns_rounded, color: picked ? kSetGreen : kSetBlue),
        title: Text('${f['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${f['host']}:${f['port']}', textDirection: TextDirection.ltr, textAlign: TextAlign.end),
        trailing: picked
            ? const SetStatusPill('مُختار', ok: true)
            : FilledButton(onPressed: () => _pick(f), child: const Text('اختر')),
      ),
    );
  }

  Widget _connectCard() => SetCard(
        title: '2. بيانات الاتصال',
        icon: Icons.settings_ethernet_rounded,
        color: kSetBlue,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _host,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'عنوان السيرفر (IP)', prefixIcon: Icon(Icons.dns_outlined)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _port,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المنفذ'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _secret,
            focusNode: _secretFocus,
            textCapitalization: TextCapitalization.characters,
            textDirection: TextDirection.ltr,
            style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(
              labelText: 'رمز الربط (من شاشة السيرفر)',
              hintText: 'غير مطلوب إن كان هذا الجهاز مضافاً لنفس الترخيص',
              prefixIcon: Icon(Icons.key_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _clientName,
            decoration: const InputDecoration(
              labelText: 'اسم هذا الجهاز (مثلاً: كاشير 2)',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
        ]),
      );

  Widget _testCard() {
    final r = _testResult;
    final kind = r == null
        ? null
        : r.startsWith('✓')
            ? SetBannerKind.ok
            : r.startsWith('✗')
                ? SetBannerKind.error
                : SetBannerKind.info;
    return SetCard(
      title: '3. اختبر الاتصال ثم احفظ',
      icon: Icons.network_check_rounded,
      color: kSetBlue,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: r == 'جارٍ الاختبار...' ? null : _test,
            icon: const Icon(Icons.wifi_tethering_rounded),
            label: const Text('اختبار الاتصال'),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: r == null
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey(r),
                  padding: const EdgeInsets.only(top: 10),
                  child: SetBanner(r.replaceFirst(RegExp(r'^[✓✗]\s*'), ''), kind: kind!),
                ),
        ),
      ]),
    );
  }

  // ─── الشرح ───

  Widget _guide() => SetCard(
        title: 'كيف أربط الأجهزة؟',
        subtitle: 'حاسبة سيرفر واحدة + طرفيات (حاسبات أخرى أو تابلت أندرويد)',
        icon: Icons.menu_book_rounded,
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: _mode != LanMode.standalone && _s.mode == LanMode.standalone,
            title: const Text('شرح خطوة بخطوة', style: TextStyle(fontWeight: FontWeight.w700)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'السيرفر هو الحاسبة التي تحفظ قاعدة البيانات (عادةً حاسبة الكاشير الرئيسية). '
                'كل الأجهزة الأخرى «طرفيات» تقرأ وتكتب في قاعدة السيرفر مباشرةً عبر شبكة المحل، '
                'فيرى الجميع نفس الأرصدة والمخزون لحظياً. لا تحتاج الشبكة المحلية إلى إنترنت.',
                style: TextStyle(height: 1.6, color: kSetText),
              ),
              _guideHead(Icons.dns_rounded, 'أولاً: على حاسبة السيرفر (مرة واحدة)', kSetGreen),
              const SetSteps([
                'اختر «حاسبة السيرفر» واضغط «حفظ» ثم أعد تشغيل البرنامج. يظهر في الأعلى «السيرفر يعمل» ورمز الربط وعنوان الحاسبة (مثل 192.168.1.10).',
                'جدار الحماية: برنامج التثبيت يفتح المنفذين 47800 و47801 تلقائياً. إن سأل ويندوز عن البرنامج فاختر «السماح».',
                'مع «تشغيل البرنامج تلقائياً» يفتح البرنامج وحده كلما شُغّلت الحاسبة ويخدم الطرفيات فوراً. اترك البرنامج مفتوحاً (يمكن تصغيره)؛ إغلاقه يوقف الطرفيات.',
              ], color: kSetGreen),
              _guideHead(Icons.tablet_android_rounded, 'ثانياً: على كل طرفية', kSetBlue),
              SetSteps([
                'اربط الجهاز بنفس راوتر المحل (كابل أو واي فاي). لا تستعمل «شبكة الضيوف» لأنها تعزل الأجهزة.',
                'فعّل الترخيص: من حاسبة السيرفر ← الإعدادات ← الترخيص والأجهزة ← «إضافة جهاز»، ثم في الطرفية اختر «جهاز إضافي» واكتب الرمز.',
                'افتح هذه الشاشة واختر «طرفية» ثم «ابحث عن السيرفر» و«اختر». إن لم يظهر فاكتب عنوانه بيدك والمنفذ ${_port.text}.',
                'اكتب رمز الربط (مثل ABCD-EFGH-JKLM) واضغط «اختبار الاتصال». عند النجاح اضغط «حفظ» وأعد تشغيل البرنامج.',
                'ادخل باسم الموظف: الطرفية تستعمل حسابات المستخدمين الموجودة في السيرفر وصلاحياتهم.',
              ], color: kSetBlue),
              _guideHead(Icons.build_circle_outlined, 'إن لم تتصل الطرفية', kSetOrange),
              const Text(
                '• تأكد أن البرنامج مفتوح على حاسبة السيرفر وأن الجهازين على نفس الراوتر.\n'
                '• جرّب كتابة العنوان يدوياً بدل البحث (بعض الراوترات تمنع البحث).\n'
                '• برنامج حماية آخر (ESET أو Kaspersky...): اسمح فيه للبرنامج أو للمنفذين 47800 و47801.\n'
                '• إن تغيّر عنوان السيرفر بعد إطفاء الراوتر تبحث الطرفية عنه وحدها عند التشغيل. '
                'وللثبات التام اطلب «عنواناً ثابتاً» لحاسبة السيرفر في الراوتر.\n'
                '• المزامنة مع Firebase والنسخ الاحتياطي تعمل على حاسبة السيرفر وحدها لكل المحل.',
                style: TextStyle(height: 1.7, color: kSetText, fontSize: 13),
              ),
            ],
          ),
        ),
      );

  Widget _guideHead(IconData i, String t, Color c) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Row(children: [
          Icon(i, color: c, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: c))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final running = LanRuntime.server?.isRunning == true;
    final changed = _mode != _s.mode;
    return SettingsScaffold(
      title: 'إعداد الشبكة',
      icon: Icons.lan_rounded,
      subtitle: 'جهاز مستقل، سيرفر، أو طرفية',
      children: [
        _hero(running),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final m in LanMode.values) _modeTile(m),
            ]),
          ),
        ),
        if (changed)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SetBanner(
              'غيّرت الوضع إلى «${_modes[_mode]!.$2}» — لا يُطبَّق حتى تضغط «حفظ» وتعيد تشغيل البرنامج.',
              kind: SetBannerKind.warn,
            ),
          ),
        if (_mode == LanMode.standalone)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: SetBanner('قاعدة البيانات على هذا الجهاز وحده. لا يتصل به جهاز آخر ولا يتصل هو بسيرفر.'),
          ),
        if (_mode == LanMode.server) ...[
          _secretCard(),
          _addressCard(),
          _clientsCard(running),
          _serverOptionsCard(),
        ],
        if (_mode == LanMode.client) ...[
          _findCard(),
          _connectCard(),
          _testCard(),
        ],
        _guide(),
        SetPrimaryButton(
          label: changed ? 'حفظ والتحويل إلى «${_modes[_mode]!.$2}»' : 'حفظ',
          icon: Icons.save_rounded,
          color: _modes[_mode]!.$4,
          onPressed: _save,
        ),
        const SizedBox(height: 12),
        const Text(
          'مهم: على الطرفية لا تعمل المزامنة مع Firebase ولا النسخ الاحتياطي — السيرفر وحده يقوم بهما لكل الفرع. '
          'انقل قاعدة البيانات إلى حاسبة السيرفر قبل تحويل الأجهزة الأخرى إلى طرفيات.',
          style: TextStyle(color: kSetMuted, fontSize: 12, height: 1.5),
        ),
      ],
    );
  }
}
