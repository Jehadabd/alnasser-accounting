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
import '../lan/lan_bootstrap.dart' show LanRuntime;
import '../erp/erp_kit.dart' show ErpDialog;
import '../widgets/settings_kit.dart';
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
    setToast(context, r.success ? 'تم تحديث الترخيص من السيرفر' : (r.message ?? 'تعذّر التحديث'), error: !r.success);
    if (!_license.isLicenseActivated()) {
      Navigator.of(context).pushNamedAndRemoveUntil('/license', (route) => false);
      return;
    }
    if (_license.isMainDevice) _load();
  }

  Future<void> _addDevice() async {
    setState(() => _loading = true);
    // 🖧 الرئيسي يخدم الأجهزة على شبكة المحل: الجهاز الجديد يرتبط به وحده بعد الرمز
    await LanRuntime.ensureServerForPairing();
    final r = await _license.createPairCode();
    if (!mounted) return;
    setState(() => _loading = false);
    if (!r.success) {
      await showDialog(
        context: context,
        builder: (ctx) => ErpDialog(
          title: 'لا يمكن إضافة جهاز',
          icon: Icons.devices_other_rounded,
          color: kSetOrange,
          content: Text(r.message ?? 'تعذّر إنشاء الرمز', style: const TextStyle(height: 1.6)),
          actions: [
            TextButton.icon(
              onPressed: openSupportWhatsApp,
              icon: const Icon(Icons.chat_rounded, color: kSetGreen),
              label: const Text('تواصل عبر واتساب'),
            ),
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
      builder: (ctx) => ErpDialog(
        title: 'فك ربط الجهاز',
        subtitle: d.name.isEmpty ? d.id : d.name,
        icon: Icons.link_off_rounded,
        color: kSetRed,
        content: const SetBanner(
          'سيتوقف البرنامج على هذا الجهاز ويتحرّر مكانه لجهاز آخر. يمكنك ربطه من جديد لاحقاً برمز إضافة جهاز.',
          kind: SetBannerKind.warn,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kSetRed),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.link_off_rounded, size: 19),
            label: const Text('فك الربط'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    final r = await _license.unbindDevice(d.id);
    if (!mounted) return;
    setState(() => _loading = false);
    setToast(context, r.success ? 'فُكّ ربط الجهاز' : (r.message ?? 'تعذّر فك الربط'), error: !r.success);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _license.getStoredLicense();
    return SettingsScaffold(
      title: 'الترخيص والأجهزة',
      subtitle: 'معلومات الترخيص والأجهزة المرتبطة بالحساب',
      icon: Icons.verified_user_rounded,
      actions: [
        IconButton(
          tooltip: 'تفعيل هذا الجهاز بحساب ترخيص آخر أو برمز من جهاز رئيسي',
          onPressed: _loading ? null : () => Navigator.of(context).pushNamed('/license'),
          icon: const Icon(Icons.swap_horiz_rounded),
        ),
        IconButton(
          tooltip: 'تحديث الترخيص الآن',
          onPressed: _loading ? null : _refreshLicense,
          icon: const Icon(Icons.sync_rounded),
        ),
      ],
      body: data == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: SetBanner('الترخيص غير مفعّل على هذا الجهاز.', kind: SetBannerKind.warn),
              ),
            )
          : null,
      children: data == null
          ? null
          : [
              SetHero(
                icon: data.isMainDevice ? Icons.workspace_premium_rounded : Icons.devices_other_rounded,
                title: data.username,
                text: [
                  if (data.customer.isNotEmpty) data.customer,
                  '${data.modeLabel} • ${data.typeLabel}',
                ].join('\n'),
                status: Wrap(spacing: 8, runSpacing: 6, children: [
                  const SetStatusPill('الترخيص مفعّل', ok: true, icon: Icons.verified_rounded),
                  SetStatusPill(data.isMainDevice ? 'هذا هو الجهاز الرئيسي' : 'هذا جهاز إضافي',
                      ok: true, icon: data.isMainDevice ? Icons.star_rounded : Icons.computer_rounded),
                ]),
              ),
              _infoCard(data),
              if (data.isMainDevice) _devicesCard(data) else _secondaryNote(),
            ],
    );
  }

  Widget _infoCard(LicenseData d) {
    final items = <(IconData, String, String)>[
      (Icons.badge_outlined, 'حساب الترخيص', d.username),
      if (d.customer.isNotEmpty) (Icons.storefront_outlined, 'العميل', d.customer),
      (Icons.apps_rounded, 'النمط', d.modeLabel),
      (Icons.event_available_outlined, 'النوع', d.typeLabel),
      (d.isMainDevice ? Icons.star_outline_rounded : Icons.devices_other_outlined, 'هذا الجهاز',
          d.isMainDevice ? 'الجهاز الرئيسي' : 'جهاز إضافي'),
      (Icons.devices_rounded, 'الأجهزة المسموحة', '${d.maxDevices}'),
    ];
    return SetCard(
      title: 'معلومات الترخيص',
      icon: Icons.info_outline_rounded,
      child: LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 560 ? 2 : 1;
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            for (final it in items)
              Container(
                width: w,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kSetBorder),
                ),
                child: Row(children: [
                  Icon(it.$1, size: 20, color: _navy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(it.$2, style: const TextStyle(fontSize: 12, color: kSetMuted)),
                      Text(it.$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
                    ]),
                  ),
                ]),
              ),
          ]),
        );
      }),
    );
  }

  Widget _secondaryNote() => const SetCard(
        title: 'الأجهزة المرتبطة',
        icon: Icons.devices_rounded,
        child: Padding(
          padding: EdgeInsets.only(top: 10),
          child: SetBanner('هذا جهاز إضافي. إضافة الأجهزة وفك ربطها تتم من الجهاز الرئيسي فقط.'),
        ),
      );

  Widget _devicesCard(LicenseData d) {
    final list = _devices?.devices ?? const <LicenseDeviceInfo>[];
    final max = _devices?.max ?? d.maxDevices;
    final frac = max <= 0 ? 0.0 : (list.length / max).clamp(0.0, 1.0);
    final full = max > 0 && list.length >= max;
    return SetCard(
      title: 'الأجهزة المرتبطة',
      subtitle: '${list.length} من $max أجهزة',
      icon: Icons.devices_rounded,
      trailing: FilledButton.icon(
        onPressed: _loading ? null : _addDevice,
        icon: const Icon(Icons.add_to_queue_rounded, size: 19),
        label: const Text('إضافة جهاز'),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _loading ? null : frac,
            minHeight: 8,
            color: full ? kSetOrange : _navy,
            backgroundColor: const Color(0xFFE8EDF5),
          ),
        ),
        if (full) ...[
          const SizedBox(height: 10),
          const SetBanner('وصلت إلى الحد الأقصى للأجهزة — فكّ ربط جهاز أو تواصل مع صاحب البرنامج لزيادة العدد.',
              kind: SetBannerKind.warn),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          SetBanner(_error!, kind: SetBannerKind.error),
        ],
        const SizedBox(height: 12),
        if (list.isEmpty && !_loading && _error == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text('لا توجد أجهزة لعرضها', textAlign: TextAlign.center, style: TextStyle(color: kSetMuted)),
          ),
        for (final dev in list) _deviceTile(dev),
        const SizedBox(height: 6),
        const SetBanner(
          'لإضافة جهاز: اضغط «إضافة جهاز»، ثم في الجهاز الجديد افتح البرنامج واختر «جهاز إضافي» واكتب الرمز. '
          'لزيادة عدد الأجهزة تواصل مع صاحب البرنامج: ${LicenseConfig.supportPhone}',
        ),
      ]),
    );
  }

  Widget _deviceTile(LicenseDeviceInfo dev) {
    final c = dev.isMain ? _navy : const Color(0xFF0E7490);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: dev.isThis ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dev.isThis ? kSetGreen.withValues(alpha: 0.35) : kSetBorder),
      ),
      child: Material(type: MaterialType.transparency, child: ListTile(
        contentPadding: const EdgeInsetsDirectional.fromSTEB(12, 6, 6, 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: dev.isMain ? c : c.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(dev.isMain ? Icons.star_rounded : Icons.computer_rounded,
              color: dev.isMain ? Colors.white : c),
        ),
        title: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(dev.name.isEmpty ? dev.id : dev.name,
              style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
          _chip(dev.isMain ? 'رئيسي' : 'إضافي', c),
          if (dev.isThis) _chip('هذا الجهاز', kSetGreen),
        ]),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            [
              if (dev.firstSeen != null) 'رُبط ${_df.format(dev.firstSeen!)}',
              if (dev.lastSeen != null) 'آخر تحقق ${_df.format(dev.lastSeen!)}',
            ].join('  •  '),
            style: const TextStyle(fontSize: 12, color: kSetMuted),
          ),
        ),
        trailing: dev.isMain
            ? null
            : IconButton(
                tooltip: 'فك الربط',
                style: IconButton.styleFrom(backgroundColor: const Color(0xFFFEF2F2)),
                icon: const Icon(Icons.link_off_rounded, color: kSetRed),
                onPressed: _loading ? null : () => _unbind(dev),
              ),
      )),
    );
  }

  static Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w800)),
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
  bool _copied = false;
  // السيرفر يعيد وقت الانتهاء؛ إن غاب (احتياط) نفترض 10 دقائق من الآن بدل الانهيار عند «!».
  late final DateTime _expiresAt = widget.result.expiresAt ?? DateTime.now().add(const Duration(minutes: 10));
  late final int _totalSeconds = _expiresAt.difference(DateTime.now()).inSeconds.clamp(1, 1 << 30).toInt();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.result.code ?? '';
    final left = _expiresAt.difference(DateTime.now());
    final expired = left.isNegative;
    final mm = left.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = left.inSeconds.remainder(60).toString().padLeft(2, '0');
    final frac = expired ? 0.0 : (left.inSeconds / _totalSeconds).clamp(0.0, 1.0);
    final c = expired ? kSetMuted : const Color(0xFF0F3460);

    return ErpDialog(
      title: 'رمز إضافة جهاز',
      subtitle: 'يُستعمل مرة واحدة • الأجهزة ${widget.result.used}/${widget.result.max}',
      icon: Icons.add_to_queue_rounded,
      width: 460,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SetSteps([
          'في الجهاز الجديد افتح البرنامج.',
          'اختر «جهاز إضافي».',
          'اكتب الرمز التالي — على شبكة هذا المحل يرتبط بهذه الحاسبة وحده، ومن فرع آخر يتصل بالمزامنة عبر الإنترنت.',
        ]),
        const SizedBox(height: 8),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            for (final ch in code.split(''))
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 46,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: expired ? const Color(0xFFF1F5F9) : const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.withValues(alpha: 0.30), width: 1.4),
                ),
                child: Text(ch,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: c,
                      decoration: expired ? TextDecoration.lineThrough : null,
                    )),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 6,
            color: frac < 0.2 ? kSetOrange : const Color(0xFF0F3460),
            backgroundColor: const Color(0xFFE8EDF5),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          expired ? 'انتهت صلاحية الرمز — أغلق وأنشئ رمزاً جديداً' : 'صالح لمدة $mm:$ss',
          textAlign: TextAlign.center,
          style: TextStyle(color: expired ? kSetRed : kSetMuted, fontWeight: FontWeight.w700),
        ),
      ]),
      actions: [
        TextButton.icon(
          onPressed: expired || code.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (mounted) setState(() => _copied = true);
                },
          icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 18),
          label: Text(_copied ? 'نُسخ' : 'نسخ الرمز'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تم')),
      ],
    );
  }
}
