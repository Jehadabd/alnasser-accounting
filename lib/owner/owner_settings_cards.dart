// lib/owner/owner_settings_cards.dart
//
// 👑 بطاقات «ميزات المالك» في الإعدادات العامة (تظهر لحساب المالك فقط):
//   1) المؤسسون: النقاط لكل 100,000 (الافتراضي للفواتير الجديدة) + فتح التقارير.
//   2) Google Drive: ربط الحساب، رفع قاعدة البيانات مضغوطة، رفع سجل الديون PDF.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../accounting/screens/acc_ui.dart' show accRoute;
import '../widgets/settings_kit.dart';
import 'founder_service.dart';
import 'founders_screen.dart';
import 'google_drive_service.dart';

final _whenFmt = DateFormat('yyyy/MM/dd HH:mm', 'en_US');

String _fmtRate(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

class OwnerSettingsCards extends StatelessWidget {
  const OwnerSettingsCards({super.key});

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_OwnerBadge(), _FoundersCard(), _DriveCard()],
      );
}

class _OwnerBadge extends StatelessWidget {
  const _OwnerBadge();
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF0F3460), Color(0xFF92400E)]),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(children: [
          Icon(Icons.workspace_premium_rounded, color: Color(0xFFFDE68A), size: 30),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'حساب مالك: هذه الميزات مفعّلة من سيرفر الترخيص لهذا الحساب فقط، ولا تظهر في الحسابات الأخرى.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, height: 1.5),
            ),
          ),
        ]),
      );
}

// ═════════════════════════════ المؤسسون ═════════════════════════════

class _FoundersCard extends StatefulWidget {
  const _FoundersCard();
  @override
  State<_FoundersCard> createState() => _FoundersCardState();
}

class _FoundersCardState extends State<_FoundersCard> {
  final _rate = TextEditingController();
  double? _saved;

  @override
  void initState() {
    super.initState();
    FounderService.defaultRate().then((v) {
      if (!mounted) return;
      setState(() {
        _saved = v;
        _rate.text = _fmtRate(v);
      });
    });
  }

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  double? get _value => double.tryParse(_rate.text.replaceAll(',', '.'));

  Future<void> _save() async {
    final v = _value;
    if (v == null || v < 0) return setToast(context, 'اكتب رقماً صحيحاً', error: true);
    await FounderService.setDefaultRate(v);
    if (!mounted) return;
    setState(() => _saved = v);
    setToast(context, 'حُفظ: ${_fmtRate(v)} نقطة لكل 100,000');
  }

  @override
  Widget build(BuildContext context) {
    final v = _value;
    final dirty = _saved != null && v != null && v != _saved;
    return SetCard(
      title: 'المؤسسون والفنيون',
      subtitle: 'نقاط المؤسس تُحسب من صافي كل فاتورة',
      icon: Icons.engineering_rounded,
      color: const Color(0xFFD97706),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _rate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: 'النقاط لكل 100,000 دينار',
                helperText: v == null ? null : 'مثال: فاتورة بمليون = ${_fmtRate(FounderService.pointsFor(1000000, v))} نقطة',
                prefixIcon: const Icon(Icons.stars_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilledButton.icon(
              onPressed: dirty ? _save : null,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('حفظ'),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        const SetBanner('هذا المعدل الافتراضي للفواتير الجديدة. يمكن تغييره لكل فاتورة من زر «المؤسس» أعلى شاشة الفاتورة، '
            'ويُحفظ مع الفاتورة نفسها، فتغييره هنا لا يغيّر نقاط الفواتير القديمة.'),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(context, accRoute(const FoundersScreen())),
            icon: const Icon(Icons.leaderboard_rounded),
            label: const Text('فتح تقارير المؤسسين'),
          ),
        ),
      ]),
    );
  }
}

// ═════════════════════════════ Google Drive ═════════════════════════════

class _DriveCard extends StatefulWidget {
  const _DriveCard();
  @override
  State<_DriveCard> createState() => _DriveCardState();
}

class _DriveCardState extends State<_DriveCard> {
  final _drive = GoogleDriveService.instance;
  DriveStatus? _st;
  String? _busy; // نص الخطوة الجارية
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await _drive.status();
    if (mounted) setState(() => _st = s);
  }

  Future<void> _run(String start, Future<String?> Function() fn) async {
    setState(() {
      _busy = start;
      _error = null;
    });
    try {
      final done = await fn();
      if (mounted && done != null) setToast(context, done);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = null);
    await _refresh();
  }

  void _step(String s) {
    if (mounted) setState(() => _busy = s);
  }

  Future<void> _keys() async {
    // 🔑 المحفوظ يظهر في الخانتين: تُدخلان مرة واحدة وتبقيان محفوظتين على هذا الجهاز
    final (savedId, savedSecret) = await _drive.savedKeys();
    if (!mounted) return;
    final id = TextEditingController(text: savedId);
    final secret = TextEditingController(text: savedSecret);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مفاتيح Google OAuth'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'من Google Cloud Console: أنشئ «OAuth client ID» من نوع Desktop app، وفعّل Google Drive API، ثم الصق المفتاحين هنا '
              '(أو ضعهما في ملف ‎.env باسم GOOGLE_CLIENT_ID و GOOGLE_CLIENT_SECRET).',
              style: TextStyle(height: 1.6, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(controller: id, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'Client ID')),
            const SizedBox(height: 8),
            TextField(controller: secret, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'Client secret')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && id.text.trim().isNotEmpty && secret.text.trim().isNotEmpty) {
      await _drive.saveClientKeys(id.text, secret.text);
      await _refresh();
    }
    id.dispose();
    secret.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    final busy = _busy != null;
    return SetCard(
      title: 'Google Drive',
      subtitle: 'رفع قاعدة البيانات مضغوطة وسجل الديون PDF',
      icon: Icons.add_to_drive_rounded,
      color: const Color(0xFF1A73E8),
      trailing: st == null
          ? null
          : SetStatusPill(st.signedIn ? 'مربوط' : 'غير مربوط', ok: st.signedIn),
      child: !_drive.isSupported
          ? const SetBanner('غير متاح في نسخة المتصفح — استعمل نسخة ويندوز أو أندرويد.', kind: SetBannerKind.warn)
          : st == null
              ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 6),
                  if (!st.configured)
                    const SetBanner('أدخل مفتاحَي Google (Client ID و Client secret) مرة واحدة من «إدخال مفاتيح Google» أدناه — يبقيان محفوظين.',
                        kind: SetBannerKind.warn)
                  else if (st.signedIn)
                    _accountRow(st)
                  else
                    const SetBanner('اربط حساب Google مرة واحدة؛ يفتح المتصفح لتسجيل الدخول ثم يعود تلقائياً.'),
                  const SizedBox(height: 12),
                  if (st.signedIn) ...[
                    _uploadTile(
                      icon: Icons.storage_rounded,
                      color: const Color(0xFF1A73E8),
                      title: 'رفع قاعدة البيانات (مضغوطة)',
                      subtitle: 'يُحتفظ بآخر ${GoogleDriveService.keepBackups} نسخ لكل جهاز ويُحذف الأقدم',
                      last: st.lastDb,
                      onTap: busy ? null : () => _run('بدء الرفع...', () async {
                            final name = await _drive.uploadDatabase(onStep: _step);
                            return 'رُفعت قاعدة البيانات: $name';
                          }),
                    ),
                    const SizedBox(height: 8),
                    _uploadTile(
                      icon: Icons.picture_as_pdf_rounded,
                      color: kSetRed,
                      title: 'رفع سجل الديون (PDF)',
                      subtitle: 'ملف واحد «سجل الديون.pdf» يُستبدل بأحدث نسخة',
                      last: st.lastDebts,
                      onTap: busy ? null : () => _run('بدء الرفع...', () async {
                            await _drive.uploadDebtsPdf(onStep: _step);
                            return 'رُفع سجل الديون إلى Google Drive';
                          }),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.icon(
                        onPressed: busy
                            ? null
                            : () => _run('بدء الرفع...', () async {
                                  await _drive.uploadDatabase(onStep: _step);
                                  await _drive.uploadDebtsPdf(onStep: _step);
                                  return 'رُفعت قاعدة البيانات وسجل الديون';
                                }),
                        icon: const Icon(Icons.cloud_upload_rounded),
                        label: const Text('رفع الاثنين الآن'),
                      ),
                    ),
                  ],
                  if (busy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    Text(_busy!, style: const TextStyle(color: kSetMuted, fontSize: 12.5)),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    SetBanner(_error!, kind: SetBannerKind.error),
                  ],
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (st.configured && !st.signedIn)
                      FilledButton.icon(
                        onPressed: busy
                            ? null
                            : () => _run('بانتظار تسجيل الدخول في المتصفح...', () async {
                                  final email = await _drive.signIn();
                                  return 'رُبط Google Drive${email == null ? '' : ' ($email)'}';
                                }),
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('ربط حساب Google'),
                      ),
                    if (st.signedIn)
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => _run('فصل الحساب...', () async {
                                  await _drive.signOut();
                                  return 'فُصل حساب Google Drive';
                                }),
                        icon: const Icon(Icons.link_off_rounded, color: kSetRed),
                        label: const Text('فصل الحساب', style: TextStyle(color: kSetRed)),
                      ),
                    TextButton.icon(
                      onPressed: busy ? null : _keys,
                      icon: const Icon(Icons.key_rounded),
                      label: Text(st.configured ? 'تغيير مفاتيح Google' : 'إدخال مفاتيح Google'),
                    ),
                  ]),
                ]),
    );
  }

  Widget _accountRow(DriveStatus st) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const CircleAvatar(backgroundColor: Color(0xFF1A73E8), child: Icon(Icons.person_rounded, color: Colors.white)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('مربوط بحساب', style: TextStyle(fontSize: 12, color: kSetMuted)),
              Text(st.email ?? 'حساب Google', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
            ]),
          ),
        ]),
      );

  Widget _uploadTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required DateTime? last,
    required VoidCallback? onTap,
  }) =>
      Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: kSetBorder)),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('$subtitle\n${last == null ? 'لم يُرفع بعد' : 'آخر رفع: ${_whenFmt.format(last)}'}'),
          isThreeLine: true,
          trailing: Icon(Icons.cloud_upload_rounded, color: onTap == null ? kSetMuted : color),
        ),
      );
}
