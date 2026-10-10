// lib/screens/license_devices_screen.dart
//
// 💻 أجهزة الترخيص:
//   • معلومات الترخيص: الحساب، النمط، النوع/الانتهاء، دور هذا الجهاز.
//   • الجهاز الرئيسي فقط: قائمة الأجهزة المرتبطة، «إضافة جهاز» (رمز صالح
//     10 دقائق يُكتب في الجهاز الجديد)، و«فك الربط» لتحرير مكان جهاز.
//   • عدد الأجهزة يحدده صاحب البرنامج؛ زيادته بالتواصل معه.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/license_service.dart';
import 'license_screen.dart' show openSupportWhatsApp;

class LicenseDevicesScreen extends StatefulWidget {
  const LicenseDevicesScreen({super.key});

  @override
  State<LicenseDevicesScreen> createState() => _LicenseDevicesScreenState();
}

class _LicenseDevicesScreenState extends State<LicenseDevicesScreen> {
  static const _navy = Color(0xFF0F3460);
  final _license = LicenseService();
  final _df = DateFormat('yyyy/MM/dd HH:mm');

  bool _loading = false;
  String? _error;
  DevicesResult? _devices;

  @override
  void initState() {
    super.initState();
    if (_license.isMainDevice) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _license.listDevices();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _devices = r.success ? r : null;
      _error = r.success ? null : r.message;
    });
  }

  Future<void> _refreshLicense() async {
    setState(() => _loading = true);
    final r = await _license.refreshNow();
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.success ? 'تم تحديث الترخيص من السيرفر' : (r.message ?? 'تعذّر التحديث')),
      backgroundColor: r.success ? Colors.green : Colors.orange,
    ));
    if (!_license.isLicenseActivated()) {
      Navigator.of(context).pushNamedAndRemoveUntil('/license', (route) => false);
      return;
    }
    if (_license.isMainDevice) _load();
  }

  Future<void> _addDevice() async {
    setState(() => _loading = true);
    final r = await _license.createPairCode();
    if (!mounted) return;
    setState(() => _loading = false);
    if (!r.success) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('لا يمكن إضافة جهاز'),
          content: Text(r.message ?? 'تعذّر إنشاء الرمز', style: const TextStyle(height: 1.6)),
          actions: [
            TextButton.icon(onPressed: openSupportWhatsApp, icon: const Icon(Icons.chat, color: Colors.green), label: const Text('واتساب')),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً')),
          ],
        ),
      );
      return;
    }
    await showDialog(context: context, barrierDismissible: false, builder: (_) => _PairCodeDialog(result: r));
    if (mounted) _load();
  }

  Future<void> _unbind(LicenseDeviceInfo d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('فك ربط الجهاز'),
        content: Text('سيتوقف البرنامج على «${d.name.isEmpty ? d.id : d.name}» ويتحرر مكانه لجهاز آخر. متابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('فك الربط'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    final r = await _license.unbindDevice(d.id);
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.success ? 'فُكّ ربط الجهاز' : (r.message ?? 'تعذّر فك الربط')),
      backgroundColor: r.success ? Colors.green : Colors.red,
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _license.getStoredLicense();
    return Scaffold(
      appBar: AppBar(
        title: const Text('الترخيص والأجهزة'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'تحديث الترخيص الآن',
            onPressed: _loading ? null : _refreshLicense,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: data == null
          ? const Center(child: Text('الترخيص غير مفعّل'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _infoCard(data),
                const SizedBox(height: 16),
                if (data.isMainDevice) ..._devicesSection(data) else _secondaryNote(),
              ],
            ),
    );
  }

  Widget _infoCard(LicenseData d) {
    Widget row(IconData i, String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(i, size: 20, color: _navy),
            const SizedBox(width: 10),
            SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Colors.black54))),
            Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.bold))),
          ]),
        );
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          row(Icons.verified_user, 'حساب الترخيص', d.username),
          if (d.customer.isNotEmpty) row(Icons.storefront, 'العميل', d.customer),
          row(Icons.apps, 'النمط', d.modeLabel),
          row(Icons.event, 'النوع', d.typeLabel),
          row(d.isMainDevice ? Icons.star : Icons.devices_other, 'هذا الجهاز', d.isMainDevice ? 'الجهاز الرئيسي' : 'جهاز إضافي'),
          row(Icons.devices, 'الأجهزة المسموحة', '${d.maxDevices}'),
        ]),
      ),
    );
  }

  Widget _secondaryNote() => Card(
        color: Colors.blue.shade50,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'هذا جهاز إضافي. إضافة الأجهزة وفك ربطها من الجهاز الرئيسي فقط.',
            style: TextStyle(height: 1.6),
          ),
        ),
      );

  List<Widget> _devicesSection(LicenseData d) {
    final list = _devices?.devices ?? const <LicenseDeviceInfo>[];
    final max = _devices?.max ?? d.maxDevices;
    return [
      Row(children: [
        Text('الأجهزة المرتبطة (${list.length}/$max)',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _navy)),
        const Spacer(),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _navy),
          onPressed: _loading ? null : _addDevice,
          icon: const Icon(Icons.add_to_queue),
          label: const Text('إضافة جهاز'),
        ),
      ]),
      const SizedBox(height: 8),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      for (final dev in list)
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: dev.isMain ? _navy : Colors.blue.shade50,
              child: Icon(dev.isMain ? Icons.star : Icons.computer, color: dev.isMain ? Colors.white : Colors.blue),
            ),
            title: Row(children: [
              Flexible(child: Text(dev.name.isEmpty ? dev.id : dev.name, style: const TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(width: 8),
              _chip(dev.isMain ? 'رئيسي' : 'إضافي', dev.isMain ? _navy : Colors.teal),
              if (dev.isThis) ...[const SizedBox(width: 6), _chip('هذا الجهاز', Colors.green)],
            ]),
            subtitle: Text([
              if (dev.firstSeen != null) 'رُبط ${_df.format(dev.firstSeen!)}',
              if (dev.lastSeen != null) 'آخر تحقق ${_df.format(dev.lastSeen!)}',
            ].join(' • ')),
            trailing: dev.isMain
                ? null
                : IconButton(
                    tooltip: 'فك الربط',
                    icon: const Icon(Icons.link_off, color: Colors.red),
                    onPressed: _loading ? null : () => _unbind(dev),
                  ),
          ),
        ),
      const SizedBox(height: 12),
      Text(
        'لإضافة جهاز: اضغط «إضافة جهاز»، ثم في الجهاز الجديد افتح البرنامج واختر «جهاز إضافي» واكتب الرمز. '
        'لزيادة عدد الأجهزة تواصل مع صاحب البرنامج: ${LicenseConfig.supportPhone}',
        style: TextStyle(color: Colors.grey.shade700, height: 1.6),
      ),
    ];
  }

  static Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.bold)),
      );
}

class _PairCodeDialog extends StatefulWidget {
  const _PairCodeDialog({required this.result});
  final PairCodeResult result;

  @override
  State<_PairCodeDialog> createState() => _PairCodeDialogState();
}

class _PairCodeDialogState extends State<_PairCodeDialog> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.result.expiresAt!.difference(DateTime.now());
    final expired = left.isNegative;
    final mm = left.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = left.inSeconds.remainder(60).toString().padLeft(2, '0');
    return AlertDialog(
      title: const Text('رمز إضافة جهاز'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('في الجهاز الجديد: افتح البرنامج ← «جهاز إضافي» ← اكتب هذا الرمز.', style: TextStyle(height: 1.6)),
          const SizedBox(height: 16),
          SelectableText(
            widget.result.code!,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 40,
              letterSpacing: 6,
              fontWeight: FontWeight.bold,
              color: expired ? Colors.grey : const Color(0xFF0F3460),
              decoration: expired ? TextDecoration.lineThrough : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(expired ? 'انتهت صلاحية الرمز — أنشئ رمزاً جديداً' : 'صالح لمدة $mm:$ss • يُستعمل مرة واحدة',
              style: TextStyle(color: expired ? Colors.red : Colors.black54)),
          const SizedBox(height: 4),
          Text('الأجهزة: ${widget.result.used}/${widget.result.max}', style: const TextStyle(color: Colors.black54)),
        ]),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(text: widget.result.code!)),
          icon: const Icon(Icons.copy),
          label: const Text('نسخ'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تم')),
      ],
    );
  }
}
