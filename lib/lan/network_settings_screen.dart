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
      _secret.text = s.secret.isEmpty ? LanSettings.generateSecret() : s.secret;
      _serverName.text = s.serverName.isEmpty ? Platform.localHostname : s.serverName;
      _clientName.text = s.clientName;
      _ips = ips;
    });
  }

  Future<void> _discover() async {
    setState(() {
      _searching = true;
      _found = const [];
    });
    final f = await discoverLanServers();
    if (!mounted) return;
    setState(() {
      _searching = false;
      _found = f;
    });
    if (f.length == 1) {
      _host.text = '${f.first['host']}';
      _port.text = '${f.first['port']}';
    }
  }

  Future<void> _test() async {
    setState(() => _testResult = 'جارٍ الاختبار...');
    final conn = LanClientConnection(
      host: _host.text.trim(),
      port: int.tryParse(_port.text) ?? lanDefaultPort,
      secret: _secret.text.trim(),
      clientName: '${_clientName.text.trim()} (اختبار)',
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
      secret: _secret.text.trim(),
      serverName: _serverName.text.trim(),
      clientName: _clientName.text.trim(),
    );
    if (next.isClient && (next.host.isEmpty || next.secret.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أدخل عنوان السيرفر ورمز الربط'), backgroundColor: Colors.red));
      return;
    }
    await next.save();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حُفظ إعداد الشبكة'),
        content: Text(switch (_mode) {
          LanMode.server =>
            'أعد تشغيل البرنامج على هذه الحاسبة ليعمل كسيرفر. ثم على كل طرفية اختر «طرفية» وأدخل رمز الربط:\n\n${next.secret}',
          LanMode.client =>
            'أعد تشغيل البرنامج ليتصل بالسيرفر. من الآن كل البيانات تُقرأ وتُكتب في قاعدة السيرفر.',
          LanMode.standalone => 'أعد تشغيل البرنامج ليعمل على قاعدة هذه الحاسبة وحدها.',
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لاحقاً')),
          FilledButton(onPressed: () => exit(0), child: const Text('إغلاق البرنامج الآن')),
        ],
      ),
    );
  }

  Widget _modeCard(LanMode m, IconData icon, String title, String desc) {
    final sel = _mode == m;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _mode = m),
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
                      ListTile(
                        leading: const Icon(Icons.dns, color: _navy),
                        title: Text('${f['name']}'),
                        subtitle: Text('${f['host']}:${f['port']}'),
                        trailing: TextButton(
                          onPressed: () => setState(() {
                            _host.text = '${f['host']}';
                            _port.text = '${f['port']}';
                          }),
                          child: const Text('اختر'),
                        ),
                      ),
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
                      style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(labelText: 'رمز الربط (من شاشة السيرفر)'),
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
