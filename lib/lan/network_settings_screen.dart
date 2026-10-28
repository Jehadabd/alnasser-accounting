// lib/lan/network_settings_screen.dart
//
// 🖧 إعداد الشبكة المحلية: مستقل / سيرفر / طرفية.

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

const _navy = Color(0xFF0F3460);

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
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.green.shade700,
      duration: const Duration(seconds: 6),
      content: Text(hasCode
          ? '✓ اخترت «${f['name']}» (${f['host']}). جارٍ اختبار الاتصال...'
          : '✓ اخترت «${f['name']}» (${f['host']}).\nالآن اكتب «رمز الربط» الظاهر في شاشة السيرفر، ثم اضغط «اختبار الاتصال» ثم «حفظ».'),
    ));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('هذا العنوان هو هذه الحاسبة نفسها. إن كانت قاعدة البيانات هنا فاختر «سيرفر»، '
              'و«طرفية» فقط على الأجهزة الأخرى.'),
          backgroundColor: Colors.red));
      return;
    }
    if (next.isClient && (next.host.isEmpty || (next.secret.isEmpty && !hasLic))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أدخل عنوان السيرفر ورمز الربط'), backgroundColor: Colors.red));
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

  Widget _modeCard(LanMode m, IconData icon, String title, String desc) {
    final sel = _mode == m;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _mode = m;
          if (m == LanMode.client && _secret.text == _autoSecret) _secret.text = '';
          if (m == LanMode.server && _secret.text.trim().isEmpty) {
            _autoSecret ??= LanSettings.generateSecret();
            _secret.text = _autoSecret!;
          }
        }),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.all(6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sel ? _navy : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: sel ? _navy : Colors.grey.shade300),
          ),
          child: Column(children: [
            Icon(icon, size: 34, color: sel ? Colors.white : _navy),
            const SizedBox(height: 6),
            Text(title,
                style: TextStyle(fontWeight: FontWeight.bold, color: sel ? Colors.white : _navy, fontSize: 16)),
            const SizedBox(height: 4),
            Text(desc,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: sel ? Colors.white70 : Colors.black54)),
          ]),
        ),
      ),
    );
  }

  Widget _guide() {
    Widget step(String n, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 13, backgroundColor: _navy, child: Text(n, style: const TextStyle(color: Colors.white, fontSize: 13))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(color: Colors.black87, height: 1.5)),
              ]),
            ),
          ]),
        );
    Widget head(IconData i, String t) => Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Row(children: [
            Icon(i, color: _navy),
            const SizedBox(width: 8),
            Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _navy)),
          ]),
        );
    return Card(
      child: ExpansionTile(
        initiallyExpanded: _mode != LanMode.standalone && _s.mode == LanMode.standalone,
        leading: const Icon(Icons.help_outline, color: _navy),
        title: const Text('كيف أربط الأجهزة؟ شرح خطوة بخطوة', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('حاسبة سيرفر واحدة + طرفيات (حاسبات أخرى أو تابلت أندرويد)'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'السيرفر هو الحاسبة التي تحفظ قاعدة البيانات (عادةً حاسبة الكاشير الرئيسية). '
            'كل الأجهزة الأخرى «طرفيات» تقرأ وتكتب في قاعدة السيرفر مباشرةً عبر شبكة المحل، '
            'فيرى الجميع نفس الأرصدة والمخزون لحظياً. لا تحتاج الشبكة المحلية إلى إنترنت.',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 10),
          head(Icons.dns, 'أولاً: على حاسبة السيرفر (مرة واحدة)'),
          step('1', 'اختر «حاسبة السيرفر» واضغط «حفظ»',
              'ثم أعد تشغيل البرنامج. يظهر في الأعلى «السيرفر يعمل»، ويظهر رمز الربط وعنوان الحاسبة (مثل 192.168.1.10).'),
          step('2', 'جدار الحماية',
              'برنامج التثبيت يفتح منافذ الشبكة (47800 و47801) تلقائياً. إن ظهرت رسالة من ويندوز تسأل عن البرنامج فاختر «السماح».'),
          step('3', 'يبقى سيرفراً دائماً',
              'مع خيار «تشغيل البرنامج تلقائياً» يفتح البرنامج وحده كلما شُغّلت الحاسبة ويبدأ خدمة الطرفيات فوراً، '
                  'ولا يتوقف إلا إذا غيّرت الوضع من هنا. اترك البرنامج مفتوحاً (يمكن تصغيره)؛ إغلاقه يوقف الطرفيات.'),
          head(Icons.tablet_android, 'ثانياً: على كل طرفية (حاسبة أخرى أو تابلت أندرويد)'),
          step('1', 'اربط الجهاز بنفس شبكة المحل',
              'نفس الراوتر: الحاسبة بالكابل أو الواي فاي، والتابلت بالواي فاي. لا تستعمل «شبكة الضيوف» في الراوتر لأنها تعزل الأجهزة.'),
          step('2', 'فعّل الترخيص على الجهاز',
              'كل طرفية جهاز ضمن ترخيصك: من حاسبة السيرفر (الجهاز الرئيسي) ← الإعدادات ← الترخيص والأجهزة ← «إضافة جهاز»، '
                  'ثم في الطرفية اختر «جهاز إضافي» واكتب الرمز.'),
          step('3', 'افتح هذه الشاشة في الطرفية واختر «طرفية»',
              'اضغط «ابحث عن السيرفر» ثم «اختر». إن لم يظهر شيء فاكتب عنوان السيرفر بيدك (الرقم الظاهر في شاشة السيرفر) والمنفذ ${_port.text}.'),
          step('4', 'اكتب رمز الربط واضغط «اختبار الاتصال»',
              'الرمز يظهر في شاشة السيرفر (مثل ABCD-EFGH-JKLM). عند ظهور «✓ الاتصال ناجح» اضغط «حفظ» وأعد تشغيل البرنامج في الطرفية.'),
          step('5', 'ادخل باسم الموظف',
              'الطرفية تستعمل حسابات المستخدمين الموجودة في السيرفر: كل موظف يدخل باسمه وصلاحياته.'),
          head(Icons.build_circle_outlined, 'إن لم تتصل الطرفية'),
          const Text(
            '• تأكد أن البرنامج مفتوح على حاسبة السيرفر وأن الجهازين على نفس الراوتر.\n'
            '• جرّب كتابة العنوان يدوياً بدل البحث (بعض الراوترات تمنع البحث).\n'
            '• جدار الحماية: إن كان عندك برنامج حماية آخر (مثل ESET أو Kaspersky) فاسمح فيه للبرنامج أو للمنفذين 47800 و47801.\n'
            '• إن تغيّر عنوان السيرفر بعد إطفاء الراوتر تبحث الطرفية عنه وحدها عند التشغيل. '
            'وللثبات التام اطلب من فني الشبكة «عنواناً ثابتاً» لحاسبة السيرفر في الراوتر.\n'
            '• المزامنة مع Firebase والنسخ الاحتياطي تعمل على حاسبة السيرفر وحدها لكل المحل.',
            style: TextStyle(height: 1.7),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final running = LanRuntime.server?.isRunning == true;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('إعداد الشبكة', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Row(children: [
              _modeCard(LanMode.standalone, Icons.computer, 'جهاز مستقل', 'قاعدة بيانات على هذا الجهاز وحده'),
              _modeCard(LanMode.server, Icons.dns, 'حاسبة السيرفر', 'تحمل قاعدة البيانات وتخدم باقي الحاسبات'),
              _modeCard(LanMode.client, Icons.lan, 'طرفية', 'تعمل على قاعدة السيرفر عبر الشبكة'),
            ]),
            const SizedBox(height: 8),
            if (_mode == LanMode.server) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(running ? Icons.check_circle : Icons.pause_circle,
                          color: running ? Colors.green : Colors.orange),
                      const SizedBox(width: 8),
                      Text(running
                          ? 'السيرفر يعمل — ${_clients.length} طرفية متصلة'
                          : 'السيرفر لا يعمل الآن (يبدأ بعد الحفظ وإعادة التشغيل)'),
                    ]),
                    const SizedBox(height: 12),
                    TextField(controller: _serverName, decoration: const InputDecoration(labelText: 'اسم السيرفر (يظهر للطرفيات)')),
                    if (!Platform.isAndroid && !Platform.isIOS)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _autoStart,
                        onChanged: (v) => setState(() => _autoStart = v),
                        title: const Text('تشغيل البرنامج تلقائياً عند تشغيل الحاسبة'),
                        subtitle: Text(WindowsAutostart.supported
                            ? (WindowsAutostart.isEnabled()
                                ? 'مفعّل: بعد إطفاء الحاسبة وتشغيلها يفتح البرنامج ويعمل كسيرفر وحده'
                                : 'يبقى هذا الجهاز سيرفراً بعد إطفاء الحاسبة وتشغيلها، حتى تغيّر الوضع من هنا')
                            : 'يعمل في النسخة المثبّتة من البرنامج'),
                      ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _secret,
                          readOnly: true,
                          style: const TextStyle(fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(labelText: 'رمز الربط — اكتبه في كل طرفية'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'نسخ',
                        icon: const Icon(Icons.copy),
                        onPressed: () => Clipboard.setData(ClipboardData(text: _secret.text)),
                      ),
                      IconButton(
                        tooltip: 'رمز جديد (ستحتاج إدخاله في كل الطرفيات)',
                        icon: const Icon(Icons.refresh),
                        onPressed: () => setState(() => _secret.text = LanSettings.generateSecret()),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    const Text('عناوين هذه الحاسبة على الشبكة:', style: TextStyle(fontWeight: FontWeight.bold)),
                    for (final ip in _ips) SelectableText('• $ip'),
                    const SizedBox(height: 8),
                    Text('المنفذ: ${_port.text} (TCP) + $lanDiscoveryPort (UDP للاكتشاف). '
                        'إن لم تجد الطرفيات السيرفر، اسمح بهما في جدار الحماية.',
                        style: const TextStyle(color: Colors.black54, fontSize: 12)),
                    if (_clients.isNotEmpty) ...[
                      const Divider(),
                      const Text('الطرفيات المتصلة:', style: TextStyle(fontWeight: FontWeight.bold)),
                      for (final c in _clients)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.computer, color: Colors.green),
                          title: Text(c.clientName),
                          subtitle: Text('${c.address} • منذ ${TimeOfDay.fromDateTime(c.connectedAt).format(context)} • ${c.requestCount} طلب'),
                        ),
                    ],
                  ]),
                ),
              ),
            ],
            if (_mode == LanMode.client) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      FilledButton.icon(
                        onPressed: _searching ? null : _discover,
                        icon: _searching
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.search),
                        label: const Text('ابحث عن السيرفر'),
                      ),
                      const SizedBox(width: 12),
                      if (!_searching && _found.isEmpty)
                        const Flexible(child: Text('أو أدخل العنوان يدوياً', style: TextStyle(color: Colors.black54))),
                    ]),
                    for (final f in _found)
                      Builder(builder: (context) {
                        final picked = _host.text.trim() == '${f['host']}';
                        return ListTile(
                          onTap: () => _pick(f),
                          selected: picked,
                          selectedTileColor: Colors.green.shade50,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          leading: Icon(picked ? Icons.check_circle : Icons.dns, color: picked ? Colors.green : _navy),
                          title: Text('${f['name']}'),
                          subtitle: Text('${f['host']}:${f['port']}${picked ? '  — مُختار' : ''}'),
                          trailing: picked
                              ? const Icon(Icons.check, color: Colors.green)
                              : FilledButton(onPressed: () => _pick(f), child: const Text('اختر')),
                        );
                      }),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          flex: 3,
                          child: TextField(controller: _host, decoration: const InputDecoration(labelText: 'عنوان السيرفر (IP)'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: _port, decoration: const InputDecoration(labelText: 'المنفذ'))),
                    ]),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _secret,
                      focusNode: _secretFocus,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        labelText: 'رمز الربط (من شاشة السيرفر)',
                        hintText: 'غير مطلوب إن كان هذا الجهاز مضافاً لنفس الترخيص',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _clientName,
                      decoration: const InputDecoration(labelText: 'اسم هذا الجهاز (مثلاً: كاشير 2)'),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      OutlinedButton.icon(onPressed: _test, icon: const Icon(Icons.network_check), label: const Text('اختبار الاتصال')),
                      const SizedBox(width: 12),
                      if (_testResult != null) Expanded(child: Text(_testResult!)),
                    ]),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 4),
            _guide(),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _navy, padding: const EdgeInsets.all(16)),
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
            ),
            const SizedBox(height: 12),
            const Text(
              'مهم: على الطرفية لا تعمل المزامنة مع Firebase ولا النسخ الاحتياطي — السيرفر وحده يقوم بهما لكل الفرع. '
              'انقل قاعدة البيانات إلى حاسبة السيرفر قبل تحويل الأجهزة الأخرى إلى طرفيات.',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ]),
        ),
      ),
    );
  }
}
