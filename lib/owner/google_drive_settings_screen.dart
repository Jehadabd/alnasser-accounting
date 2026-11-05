// lib/owner/google_drive_settings_screen.dart
//
// ☁️ إعدادات Google Drive (ميزة المالك) — تُفتح من «زر رفع البيانات: الوجهات والترتيب»:
//   1) مفاتيح Google: شرح خطوة بخطوة بروابط مباشرة، ولصق ملف JSON أو المفتاحين.
//   2) الحساب: ربط، وإعادة ربط بنفس الحساب بضغطة، وفصل.
//   3) الرفع الآن: قاعدة البيانات مضغوطة وسجل الديون PDF.
//
// التجديد: رمز الدخول (ساعة) يتجدد وحده دائماً، والبرنامج يجدّده بصمت مرة كل 12 ساعة
// (GoogleDriveService.keepAlive). إن ألغت Google الربط نفسه — أشهر سبب: التطبيق في
// وضع «Testing» فينتهي بعد 7 أيام — لا يمكن إعادته بلا موافقة صاحب الحساب في المتصفح،
// فيظهر زر «إعادة الربط بنفس الحساب» (الحساب مختار مسبقاً، يكفي «السماح»).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../widgets/settings_kit.dart';
import '../widgets/setup_guide.dart';
import 'google_drive_service.dart';

class GoogleDriveSettingsScreen extends StatefulWidget {
  const GoogleDriveSettingsScreen({super.key});

  @override
  State<GoogleDriveSettingsScreen> createState() => _GoogleDriveSettingsScreenState();
}

class _GoogleDriveSettingsScreenState extends State<GoogleDriveSettingsScreen> {
  static const _g = Color(0xFF1A73E8);
  static final _when = DateFormat('yyyy/MM/dd HH:mm', 'en_US');

  final _drive = GoogleDriveService.instance;
  final _idCtl = TextEditingController();
  final _secretCtl = TextEditingController();
  final _jsonCtl = TextEditingController();

  DriveStatus? _st;
  String? _busy; // نص الخطوة الجارية
  (bool ok, String msg)? _result;
  bool _showSecret = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _idCtl.dispose();
    _secretCtl.dispose();
    _jsonCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final (id, secret) = await _drive.savedKeys();
    final st = await _drive.status();
    if (!mounted) return;
    setState(() {
      if (_idCtl.text.isEmpty) _idCtl.text = id;
      if (_secretCtl.text.isEmpty) _secretCtl.text = secret;
      _st = st;
    });
  }

  Future<void> _run(String start, Future<String?> Function() fn) async {
    setState(() {
      _busy = start;
      _result = null;
    });
    try {
      final done = await fn();
      if (mounted && done != null) setState(() => _result = (true, done));
    } catch (e) {
      if (mounted) setState(() => _result = (false, '$e'));
    }
    if (mounted) setState(() => _busy = null);
    await _load();
  }

  void _step(String s) {
    if (mounted) setState(() => _busy = s);
  }

  void _onJsonPasted(String v) {
    final keys = GoogleDriveService.parseClientJson(v);
    if (keys == null) return;
    setState(() {
      _idCtl.text = keys.$1;
      _secretCtl.text = keys.$2;
      _jsonCtl.clear();
      _result = (true, 'قُرئ المفتاحان من الملف — اضغط «حفظ المفاتيح».');
    });
  }

  Future<void> _saveKeys() async {
    final id = _idCtl.text.trim();
    final secret = _secretCtl.text.trim();
    if (!id.endsWith('.apps.googleusercontent.com')) {
      setState(() => _result = (false, '«Client ID» يجب أن ينتهي بـ .apps.googleusercontent.com — انسخه كاملاً.'));
      return;
    }
    if (secret.isEmpty) {
      setState(() => _result = (false, 'أدخل «Client secret».'));
      return;
    }
    await _run('حفظ المفاتيح...', () async {
      await _drive.saveClientKeys(id, secret);
      return 'حُفظ المفتاحان على هذا الجهاز. الخطوة التالية: «ربط حساب Google».';
    });
  }

  // ─────────── الشرح ───────────

  static const _cloud = 'https://console.cloud.google.com';

  List<GuideStep> _keySteps() => [
        const GuideStep(
          'افتح Google Cloud بحساب Google الذي تريد الرفع إليه (نفس حساب Drive). أول مرة يطلب الموافقة على الشروط — وافق.',
          links: [GuideLink('افتح Google Cloud', _cloud, icon: Icons.cloud_rounded)],
        ),
        const GuideStep(
          'أنشئ مشروعاً جديداً: اكتب اسمه ثم «Create / إنشاء»، وانتظر قليلاً. تأكّد أن المشروع الجديد هو المختار في أعلى الصفحة.',
          links: [GuideLink('إنشاء مشروع', '$_cloud/projectcreate', icon: Icons.add_box_rounded)],
          copies: ['alnaser-backup'],
        ),
        const GuideStep(
          'فعّل خدمة Google Drive للمشروع: اضغط «Enable / تفعيل».',
          links: [GuideLink('تفعيل Google Drive API', '$_cloud/apis/library/drive.googleapis.com', icon: Icons.add_to_drive_rounded)],
        ),
        const GuideStep(
          'جهّز «شاشة الموافقة»: اضغط «Get started / البدء» ← «App name / اسم التطبيق» اكتب اسماً ← «User support email» اختر بريدك ← '
          'Next ← في «Audience» اختر «External / خارجي» ← Next ← اكتب بريدك في «Contact information» ← Next ← وافق ← «Create».',
          links: [GuideLink('افتح شاشة الموافقة (Branding)', '$_cloud/auth/branding', icon: Icons.badge_rounded)],
          copies: ['نسخ الناصر للحسابات'],
        ),
        const GuideStep(
          'مهم جداً — انشر التطبيق: في صفحة «Audience / الجمهور» اضغط «Publish app / نشر التطبيق» ← «Confirm». '
          'تصبح الحالة «In production».',
          links: [GuideLink('افتح صفحة Audience', '$_cloud/auth/audience', icon: Icons.public_rounded)],
          note: 'بدون هذه الخطوة تبقى الحالة «Testing»، وتُلغي Google الربط كل 7 أيام فتضطر لإعادة الربط كل أسبوع. '
              'صلاحية البرنامج (drive.file) «غير حساسة»، فالنشر لا يحتاج مراجعة من Google.',
          warn: true,
        ),
        const GuideStep(
          'أنشئ المفتاح: «Application type / نوع التطبيق» اختر «Desktop app / تطبيق سطح مكتب» ← اكتب اسماً ← «Create». '
          'تظهر نافذة فيها «Client ID» و«Client secret» — اضغط «Download JSON / تنزيل JSON» (أو انسخ الاثنين).',
          links: [GuideLink('إنشاء المفتاح (Clients)', '$_cloud/auth/clients/create', icon: Icons.key_rounded)],
          copies: ['alnaser-desktop'],
          note: 'السرّ لا يظهر مرة أخرى بعد إغلاق النافذة — لذلك نزّل ملف JSON واحتفظ به. لا ترسله لأحد.',
        ),
        const GuideStep(
          'افتح ملف JSON الذي نزل (بالمفكرة Notepad)، انسخ كل ما فيه، والصقه في خانة «محتوى ملف JSON» أدناه — '
          'يُقرأ المفتاحان وحدهما — ثم «حفظ المفاتيح». (أو الصق المفتاحين كلّاً في خانته.)',
        ),
      ];

  List<GuideStep> _accountSteps() => const [
        GuideStep('اضغط «ربط حساب Google» — يفتح المتصفح صفحة Google.'),
        GuideStep('اختر حسابك (نفس الحساب الذي أنشأت به المفاتيح أو أي حساب تريد الرفع إليه).'),
        GuideStep(
          'إن ظهرت صفحة «Google hasn\'t verified this app»: اضغط «Advanced / متقدم» ثم «Go to … (unsafe)» — '
          'التطبيق تطبيقك أنت، والتحذير يظهر لأنه لم يُراجع من Google.',
        ),
        GuideStep('اضغط «Continue / متابعة» ثم «Allow / السماح». تظهر «✅ تم ربط Google Drive» — أغلق الصفحة وارجع للبرنامج.'),
      ];

  // ─────────── الواجهة ───────────

  @override
  Widget build(BuildContext context) {
    final st = _st;
    return SettingsScaffold(
      title: 'Google Drive',
      subtitle: 'رفع قاعدة البيانات وسجل الديون إلى حسابك',
      icon: Icons.add_to_drive_rounded,
      loading: st == null,
      actions: [
        IconButton(tooltip: 'تحديث', onPressed: _busy != null ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      children: st == null
          ? null
          : !_drive.isSupported
              ? const [SetBanner('غير متاح في نسخة المتصفح — استعمل نسخة ويندوز أو أندرويد.', kind: SetBannerKind.warn)]
              : [
                  _hero(st),
                  if (st.needsRelink) _relinkCard(st),
                  _keysCard(st),
                  _accountCard(st),
                  if (st.signedIn) _uploadsCard(st),
                  if (_busy != null) ...[
                    const LinearProgressIndicator(color: _g),
                    const SizedBox(height: 6),
                    Text(_busy!, style: const TextStyle(color: kSetMuted, fontSize: 12.5)),
                    const SizedBox(height: 12),
                  ],
                  if (_result != null)
                    SetBanner(_result!.$2, kind: _result!.$1 ? SetBannerKind.ok : SetBannerKind.error),
                  const SizedBox(height: 30),
                ],
    );
  }

  Widget _hero(DriveStatus st) {
    final (String label, bool ok) = st.signedIn
        ? ('مربوط${st.email == null ? '' : ': ${st.email}'}', true)
        : (st.needsRelink ? 'انتهى الربط — أعد الربط' : (st.configured ? 'المفاتيح جاهزة — اربط الحساب' : 'غير مربوط'), false);
    return SetHero(
      icon: Icons.add_to_drive_rounded,
      color: _g,
      title: 'Google Drive',
      text: 'نسخة مضغوطة من قاعدة البيانات (يُحتفظ بآخر ${GoogleDriveService.keepBackups} نسخ لكل جهاز) وسجل الديون PDF '
          'في مجلد خاص على حسابك. البرنامج لا يرى من Drive إلا الملفات التي رفعها هو.',
      status: Wrap(spacing: 8, runSpacing: 6, children: [
        SetStatusPill(label, ok: ok),
        if (st.signedIn && st.lastCheck != null)
          SetStatusPill('آخر تجديد تلقائي: ${_when.format(st.lastCheck!)}', ok: true, icon: Icons.autorenew_rounded),
      ]),
    );
  }

  Widget _relinkCard(DriveStatus st) => SetCard(
        title: 'انتهى ربط Google Drive',
        subtitle: st.expiredAt == null ? null : 'منذ ${_when.format(st.expiredAt!)}',
        icon: Icons.link_off_rounded,
        color: kSetOrange,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 10),
          Text(
            'ألغت Google الربط، فلا يستطيع البرنامج تجديده وحده — Google تشترط موافقة صاحب الحساب. '
            'اضغط الزر: يُفتح المتصفح وحسابك ${st.email ?? ''} مختار مسبقاً، يكفي «Allow / السماح».',
            style: const TextStyle(fontSize: 13, height: 1.6, color: kSetText),
          ),
          if (st.likelyTestingMode) ...[
            const SizedBox(height: 10),
            const SetBanner(
              'انتهى الربط بعد نحو 7 أيام من تسجيل الدخول — السبب غالباً أن التطبيق في Google Cloud ما زال في وضع «Testing». '
              'انشره («Publish app» في الخطوة 5 من شرح المفاتيح أدناه) ثم أعد الربط، فلا يتكرر.',
              kind: SetBannerKind.warn,
            ),
          ],
          const SizedBox(height: 12),
          SetPrimaryButton(
            label: 'إعادة الربط بنفس الحساب',
            icon: Icons.restart_alt_rounded,
            color: _g,
            busy: _busy != null,
            onPressed: _busy != null || !st.configured
                ? null
                : () => _run('بانتظار الموافقة في المتصفح...', () async {
                      final email = await _drive.signIn(sameAccount: true);
                      return 'أُعيد ربط Google Drive${email == null ? '' : ' ($email)'}';
                    }),
          ),
        ]),
      );

  Widget _keysCard(DriveStatus st) => SetCard(
        title: '1) مفاتيح Google',
        subtitle: st.configured ? 'محفوظة على هذا الجهاز' : 'مرة واحدة — من Google Cloud (مجاني)',
        icon: Icons.key_rounded,
        color: _g,
        trailing: SetStatusPill(st.configured ? 'جاهزة' : 'مطلوبة', ok: st.configured),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GuideToggle(
            label: 'كيف أحصل على المفاتيح؟ (شرح خطوة بخطوة)',
            color: _g,
            initiallyOpen: !st.configured,
            child: SetupGuide(steps: _keySteps(), color: _g),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _jsonCtl,
            minLines: 2,
            maxLines: 4,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
            decoration: const InputDecoration(
              labelText: 'محتوى ملف JSON (اختياري — الأسهل)',
              hintText: '{"installed":{"client_id":"…","client_secret":"…"}}',
              prefixIcon: Icon(Icons.data_object_rounded),
            ),
            onChanged: _onJsonPasted,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _idCtl,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'Client ID',
              hintText: '….apps.googleusercontent.com',
              prefixIcon: Icon(Icons.badge_rounded),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _secretCtl,
            obscureText: !_showSecret,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'Client secret',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _showSecret ? 'إخفاء' : 'إظهار',
                icon: Icon(_showSecret ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                onPressed: () => setState(() => _showSecret = !_showSecret),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SetPrimaryButton(
            label: 'حفظ المفاتيح',
            icon: Icons.save_rounded,
            color: _g,
            onPressed: _busy != null ? null : _saveKeys,
          ),
        ]),
      );

  Widget _accountCard(DriveStatus st) => SetCard(
        title: '2) حساب Google',
        subtitle: st.signedIn ? 'يتجدد الدخول تلقائياً' : 'يفتح المتصفح مرة واحدة',
        icon: Icons.account_circle_rounded,
        color: _g,
        trailing: SetStatusPill(st.signedIn ? 'مربوط' : 'غير مربوط', ok: st.signedIn),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 10),
          if (st.signedIn)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const CircleAvatar(backgroundColor: _g, child: Icon(Icons.person_rounded, color: Colors.white)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('مربوط بحساب', style: TextStyle(fontSize: 12, color: kSetMuted)),
                    Text(st.email ?? 'حساب Google',
                        textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
                  ]),
                ),
              ]),
            )
          else ...[
            if (!st.configured)
              const SetBanner('احفظ مفاتيح Google أولاً (البطاقة 1).', kind: SetBannerKind.warn)
            else
              GuideToggle(
                label: 'ماذا سيظهر في المتصفح؟',
                color: _g,
                initiallyOpen: true,
                child: SetupGuide(steps: _accountSteps(), color: _g),
              ),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (!st.signedIn)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _g, minimumSize: const Size(0, 46)),
                onPressed: _busy != null || !st.configured
                    ? null
                    : () => _run('بانتظار تسجيل الدخول في المتصفح...', () async {
                          final email = await _drive.signIn(sameAccount: st.needsRelink);
                          return 'رُبط Google Drive${email == null ? '' : ' ($email)'}';
                        }),
                icon: const Icon(Icons.login_rounded),
                label: Text(st.needsRelink ? 'إعادة الربط بنفس الحساب' : 'ربط حساب Google'),
              ),
            if (st.needsRelink && st.configured)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                onPressed: _busy != null
                    ? null
                    : () => _run('بانتظار تسجيل الدخول في المتصفح...', () async {
                          final email = await _drive.signIn(sameAccount: false);
                          return 'رُبط Google Drive${email == null ? '' : ' ($email)'}';
                        }),
                icon: const Icon(Icons.switch_account_rounded),
                label: const Text('حساب آخر'),
              ),
            if (st.signedIn)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), foregroundColor: _g),
                onPressed: _busy != null
                    ? null
                    : () => _run('فحص الربط...', () async {
                          final h = await _drive.keepAlive(every: Duration.zero);
                          return switch (h) {
                            DriveHealth.ok => 'الربط سليم وجُدّد الآن ✓',
                            DriveHealth.expired => throw DriveException('انتهى الربط — اضغط «إعادة الربط بنفس الحساب»'),
                            DriveHealth.offline => throw DriveException('تعذّر الوصول إلى Google — تحقّق من الإنترنت ومن المفاتيح'),
                            _ => 'لا ربط لفحصه',
                          };
                        }),
                icon: const Icon(Icons.autorenew_rounded),
                label: const Text('فحص وتجديد الربط الآن'),
              ),
            if (st.signedIn || st.needsRelink)
              TextButton.icon(
                onPressed: _busy != null
                    ? null
                    : () => _run('فصل الحساب...', () async {
                          await _drive.signOut();
                          return 'فُصل حساب Google Drive';
                        }),
                icon: const Icon(Icons.link_off_rounded, color: kSetRed),
                label: const Text('فصل الحساب', style: TextStyle(color: kSetRed)),
              ),
          ]),
        ]),
      );

  Widget _uploadsCard(DriveStatus st) => SetCard(
        title: '3) رفع الآن',
        subtitle: 'زر «رفع البيانات» في الرئيسية يرفع إلى Drive أيضاً حسب ترتيب الوجهات',
        icon: Icons.cloud_upload_rounded,
        color: _g,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 10),
          _uploadTile(
            icon: Icons.storage_rounded,
            color: _g,
            title: 'رفع قاعدة البيانات (مضغوطة)',
            subtitle: 'يُحتفظ بآخر ${GoogleDriveService.keepBackups} نسخ لكل جهاز ويُحذف الأقدم',
            last: st.lastDb,
            onTap: _busy != null
                ? null
                : () => _run('بدء الرفع...', () async {
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
            onTap: _busy != null
                ? null
                : () => _run('بدء الرفع...', () async {
                      await _drive.uploadDebtsPdf(onStep: _step);
                      return 'رُفع سجل الديون إلى Google Drive';
                    }),
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
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: kSetMuted, height: 1.4)),
                  Text(last == null ? 'لم يُرفع بعد' : 'آخر رفع: ${_when.format(last)}',
                      style: const TextStyle(fontSize: 12, color: kSetMuted)),
                ]),
              ),
              Icon(Icons.cloud_upload_rounded, color: onTap == null ? kSetMuted : color),
            ]),
          ),
        ),
      );
}

/// ☁️ عند فتح البرنامج: يجدّد ربط Google Drive بصمت، وإن ألغته Google يعرض رسالة
/// بزر «إعادة الربط» (لا يفتح المتصفح وحده أبداً).
Future<void> checkGoogleDriveOnStart(BuildContext context) async {
  final drive = GoogleDriveService.instance;
  final health = await drive.keepAlive();
  if (health != DriveHealth.expired || !context.mounted) return;
  final st = await drive.status();
  if (!context.mounted || !st.configured) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    duration: const Duration(seconds: 12),
    behavior: SnackBarBehavior.floating,
    backgroundColor: const Color(0xFF9A3412),
    content: Text('انتهى ربط Google Drive${st.email == null ? '' : ' (${st.email})'} — النسخ إلى Drive متوقفة حتى تعيد الربط.'),
    action: SnackBarAction(
      label: 'إعادة الربط',
      textColor: Colors.white,
      onPressed: () async {
        try {
          await drive.signIn(sameAccount: true);
        } catch (e) {
          debugPrint('☁️ إعادة ربط Google Drive: $e');
        }
      },
    ),
  ));
}
