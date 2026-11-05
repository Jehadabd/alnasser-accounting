// lib/screens/dropbox_backup_screen.dart
// ☁️ النسخ الاحتياطي السحابي إلى Dropbox — بالشكل الموحّد لشاشات الإعدادات.
//
//   • الاتصال: فتح صفحة Dropbox ← الموافقة ← لصق الكود أو رابط الصفحة كاملاً.
//   • نسخة جديدة: تقدّم ظاهر داخل البطاقة (لا تختفي الشاشة خلف دائرة تحميل).
//   • عدد النسخ المحتفظ بها يُحفظ ويستعمله الرفع التلقائي أيضاً.
//   • الاستعادة عبر مسار الاستعادة الآمن ثم إعادة تحميل التطبيق.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import '../erp/erp_kit.dart' show ErpDialog;
import '../services/dropbox_backup_service.dart';
import '../services/backup_space_planner.dart';
import '../widgets/settings_kit.dart';
import '../widgets/setup_guide.dart'; // 🧭 الشرح خطوة بخطوة
import '../widgets/migration_guard_views.dart' show restoreSummaryText;

class DropboxBackupScreen extends StatefulWidget {
  const DropboxBackupScreen({super.key});

  @override
  State<DropboxBackupScreen> createState() => _DropboxBackupScreenState();
}

class _DropboxBackupScreenState extends State<DropboxBackupScreen> {
  static const _dbx = Color(0xFF0061FE);

  final DropboxBackupService _backupService = DropboxBackupService();
  final _codeController = TextEditingController();
  final _df = DateFormat('yyyy/MM/dd  HH:mm');

  DropboxAuthStatus _authStatus = DropboxAuthStatus.notConfigured;
  List<BackupInfo> _backups = [];
  String? _account;
  String? _listError;
  DropboxSpace? _space; // 💾 مساحة الحساب
  String _appKey = DropboxBackupService.defaultAppKey; // 🔑 تطبيق Dropbox المستعمل
  String _appName = DropboxBackupService.defaultAppName;
  bool _otherApp = false; // ربط محفوظ بتطبيق قديم ⇒ اربط من جديد
  DropboxPermissionReport? _perm; // 🩺 نتيجة فحص الأذونات (يعمل تلقائياً عند الاتصال)
  bool _checkingPerm = false;

  bool _firstLoad = true;
  bool _refreshing = false;
  bool _connecting = false;
  bool _showCodeInput = false;
  String? _authError;

  // النسخ الجاري
  bool _backingUp = false;
  int _progress = 0;
  String _progressText = '';

  /// نتيجة آخر عملية (نجاح/فشل) تظهر داخل البطاقة.
  (bool ok, String msg)? _lastResult;

  int _maxBackups = 20;

  bool get _busy => _backingUp || _connecting || _refreshing;

  @override
  void initState() {
    super.initState();
    _backupService.getMaxBackups().then((v) {
      if (mounted) setState(() => _maxBackups = v);
    });
    _loadApp();
    _checkAuthAndLoadBackups();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadApp() async {
    final k = await _backupService.appKey();
    final n = await _backupService.appName();
    if (!mounted) return;
    setState(() {
      _appKey = k;
      _appName = n;
    });
  }

  Future<void> _checkAuthAndLoadBackups() async {
    setState(() => _refreshing = true);
    final status = await _backupService.checkAuthStatus();
    final otherApp = await _backupService.linkedToOtherApp();
    if (mounted) setState(() => _otherApp = otherApp);
    List<BackupInfo> list = _backups;
    String? listError;
    String? account = _account;
    if (status == DropboxAuthStatus.authenticated) {
      try {
        list = await _backupService.listBackups();
      } catch (e) {
        listError = 'تعذّر جلب قائمة النسخ: $e';
      }
      account ??= await _backupService.getAccountLabel();
      final space = await _backupService.getSpaceUsage();
      if (mounted) setState(() => _space = space);
    }
    if (!mounted) return;
    setState(() {
      _authStatus = status;
      _backups = status == DropboxAuthStatus.authenticated ? list : [];
      _listError = listError;
      _account = status == DropboxAuthStatus.authenticated ? account : null;
      _refreshing = false;
      _firstLoad = false;
      if (status != DropboxAuthStatus.authenticated) _perm = null;
    });
    // 🩺 فحص الأذونات تلقائياً مرة عند فتح الشاشة / بعد الاتصال
    if (status == DropboxAuthStatus.authenticated && _perm == null && !_checkingPerm) _checkPermissions();
  }

  Future<void> _startOAuthFlow() async {
    final uri = Uri.parse(await _backupService.getAuthorizationUrl());
    setState(() {
      _showCodeInput = true;
      _authError = null;
    });
    final ok = await canLaunchUrl(uri) && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) setState(() => _authError = 'تعذّر فتح المتصفح — تحقّق من وجود متصفح افتراضي.');
  }

  Future<void> _submitAuthCode() async {
    final input = _codeController.text.trim();
    if (input.isEmpty) {
      setState(() => _authError = 'الصق الكود أو رابط الصفحة أولاً');
      return;
    }
    setState(() {
      _connecting = true;
      _authError = null;
    });
    final success = await _backupService.exchangeCodeForToken(input);
    if (!mounted) return;
    setState(() => _connecting = false);
    if (success) {
      _codeController.clear();
      setState(() {
        _showCodeInput = false;
        _perm = null; // يُعاد الفحص تلقائياً على الربط الجديد
        _lastResult = (true, 'تم الاتصال بـ Dropbox بنجاح — جارٍ فحص الأذونات...');
      });
      await _checkAuthAndLoadBackups();
    } else {
      final why = _backupService.lastAuthError;
      setState(() => _authError = 'رُفض الكود — قد يكون انتهى (صالح دقائق قليلة) أو نُسخ ناقصاً. اضغط «فتح صفحة Dropbox» مجدداً.'
          '${why == null || why.isEmpty ? '' : '\nردّ Dropbox: $why'}');
    }
  }

  Future<void> _createBackup() async {
    setState(() {
      _backingUp = true;
      _progress = 0;
      _progressText = 'جارٍ البدء...';
      _lastResult = null;
    });

    final result = await _backupService.createAndUploadBackup(
      maxBackups: _maxBackups,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _progressText = status;
          });
        }
      },
    );
    if (!mounted) return;

    setState(() {
      _backingUp = false;
      if (result.success) {
        final deleted = result.deletedCount ?? 0;
        _lastResult = (
          true,
          'تم رفع النسخة ${result.backupName} (${_size(result.backupSize ?? 0)})'
              '${deleted > 0 ? ' — وحُذفت $deleted نسخة قديمة' : ''}'
              '${result.freedForSpace > 0 ? ' (${result.freedForSpace} منها لإفساح المكان)' : ''}.'
        );
      } else {
        _lastResult = (false, result.error ?? 'فشل النسخ');
      }
    });
    await _checkAuthAndLoadBackups();
  }

  Future<void> _restoreBackup(BackupInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ErpDialog(
        title: 'استعادة نسخة احتياطية',
        subtitle: '${_df.format(backup.modifiedTime)}  •  ${_size(backup.size)}',
        icon: Icons.settings_backup_restore_rounded,
        color: kSetOrange,
        width: 480,
        content: const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SetBanner(
            'ستُستبدل قاعدة البيانات الحالية بهذه النسخة. أي عملية تمت بعد تاريخ النسخة ستختفي من هذا الجهاز.',
            kind: SetBannerKind.warn,
          ),
          SizedBox(height: 10),
          SetBanner('تُحفظ نسخة أمان من القاعدة الحالية تلقائياً، ويُتراجع عن الاستعادة إن كان الملف تالفاً.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kSetOrange),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.restore_rounded, size: 19),
            label: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: _BusyDialog(text: 'جارٍ تحميل النسخة واستعادتها...')),
    );
    final result = await _backupService.restoreBackup(backup);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // إغلاق نافذة الانتظار

    if (!result.success) {
      setState(() => _lastResult = (false, result.error ?? 'فشلت الاستعادة'));
      setToast(context, 'فشلت الاستعادة', error: true);
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ErpDialog(
        title: 'تمت الاستعادة',
        icon: Icons.check_circle_rounded,
        color: kSetGreen,
        width: 440,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 460),
          child: SingleChildScrollView(
            child: SelectableText(restoreSummaryText(), style: const TextStyle(height: 1.6)),
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
  }

  Future<void> _deleteBackup(BackupInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ErpDialog(
        title: 'حذف النسخة',
        subtitle: '${_df.format(backup.modifiedTime)}  •  ${_size(backup.size)}',
        icon: Icons.delete_outline_rounded,
        color: kSetRed,
        width: 440,
        content: const SetBanner('ستُحذف هذه النسخة من Dropbox نهائياً.', kind: SetBannerKind.warn),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kSetRed),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            label: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final success = await _backupService.deleteBackup(backup);
    if (!mounted) return;
    setToast(context, success ? 'حُذفت النسخة' : 'تعذّر الحذف', error: !success);
    if (success) await _checkAuthAndLoadBackups();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ErpDialog(
        title: 'قطع الاتصال بـ Dropbox',
        icon: Icons.link_off_rounded,
        color: kSetRed,
        width: 440,
        content: const SetBanner('لن تُرفع نسخ جديدة إلى Dropbox. النسخ الموجودة هناك لا تُحذف.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kSetRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('قطع الاتصال'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _backupService.logout();
    if (!mounted) return;
    setState(() {
      _authStatus = DropboxAuthStatus.notConfigured;
      _backups = [];
      _account = null;
      _lastResult = null;
      _perm = null;
    });
  }

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  // ─────────────────────────── الواجهة ───────────────────────────

  List<Widget> _content() {
    final connected = _authStatus == DropboxAuthStatus.authenticated;
    return [
      _hero(),
      _appCard(),
      if (_otherApp && !connected)
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: SetBanner(
            'تغيّر تطبيق Dropbox الذي يستعمله البرنامج — اربط حسابك من جديد مرة واحدة (الربط القديم كان بتطبيق آخر).',
            kind: SetBannerKind.warn,
          ),
        ),
      if (_lastResult != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SetBanner(_lastResult!.$2, kind: _lastResult!.$1 ? SetBannerKind.ok : SetBannerKind.error),
        ),
      if (!connected) _authCard() else ...[
        _permissionsCard(),
        _backupCard(),
        _settingsCard(),
        _listCard(),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final connected = _authStatus == DropboxAuthStatus.authenticated;
    return SettingsScaffold(
      title: 'النسخ الاحتياطي السحابي',
      subtitle: 'Dropbox — نسخ قاعدة البيانات مع تدوير تلقائي',
      icon: Icons.cloud_upload_rounded,
      loading: _firstLoad,
      actions: [
        IconButton(
          tooltip: 'تحديث',
          onPressed: _busy ? null : _checkAuthAndLoadBackups,
          icon: const Icon(Icons.refresh_rounded),
        ),
        if (connected)
          IconButton(
            tooltip: 'قطع الاتصال',
            onPressed: _busy ? null : _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
      ],
      children: _firstLoad ? null : _content(),
    );
  }

  Widget _statusPills() {
    final (String label, bool ok) = switch (_authStatus) {
      DropboxAuthStatus.authenticated => ('متصل${_account == null ? '' : ': $_account'}', true),
      DropboxAuthStatus.needsAuth => ('انتهى الاتصال — سجّل الدخول من جديد', false),
      DropboxAuthStatus.error => ('تعذّر الوصول — تحقّق من الإنترنت', false),
      DropboxAuthStatus.notConfigured => ('غير متصل', false),
    };
    return Wrap(spacing: 8, runSpacing: 6, children: [
      SetStatusPill(label, ok: ok),
      if (_authStatus == DropboxAuthStatus.authenticated)
        SetStatusPill('${_backups.length} نسخة محفوظة', ok: _backups.isNotEmpty, icon: Icons.inventory_2_rounded),
    ]);
  }

  Widget _hero() => SetHero(
        icon: Icons.cloud_rounded,
        color: _dbx,
        title: 'Dropbox — $_appName',
        text: _account ?? 'احفظ نسخة من قاعدة بياناتك في حسابك على Dropbox، مع حذف النسخ الأقدم تلقائياً.',
        status: _statusPills(),
      );

  Future<void> _checkPermissions() async {
    setState(() => _checkingPerm = true);
    final report = await _backupService.checkPermissionsDetailed();
    if (!mounted) return;
    setState(() {
      _checkingPerm = false;
      _perm = report;
      if (report.allOk && _lastResult?.$1 == true) _lastResult = (true, 'تم الاتصال بـ Dropbox — والأذونات كلها سليمة.');
    });
  }

  /// 🩺 أذونات تطبيق Dropbox: فحص تلقائي بطلبات حقيقية، وما ينقص بالاسم، وإصلاحه.
  Widget _permissionsCard() {
    final r = _perm;
    final missing = r?.missing ?? const <String>[];
    final other = r?.otherFailure;
    final bad = r != null && !r.allOk;
    final listScopeError = (_listError ?? '').contains(DropboxBackupService.missingScopeMarker);

    final String subtitle;
    if (_checkingPerm) {
      subtitle = 'جارٍ الفحص...';
    } else if (r == null) {
      subtitle = listScopeError ? 'ينقص تطبيق Dropbox إذن — اضغط «فحص الأذونات»' : 'يُفحص تلقائياً عند الاتصال';
    } else if (r.allOk) {
      subtitle = 'كل الأذونات موجودة — الرفع والتنزيل والحذف تعمل';
    } else if (missing.isNotEmpty) {
      subtitle = missing.length == 1 ? 'ينقص إذن واحد فقط' : 'ينقص ${missing.length} أذونات';
    } else {
      subtitle = 'الأذونات ليست السبب — انظر ردّ Dropbox';
    }

    return SetCard(
      title: 'أذونات Dropbox',
      subtitle: subtitle,
      icon: Icons.verified_user_rounded,
      color: r == null ? (listScopeError ? kSetOrange : _dbx) : (r.allOk ? kSetGreen : kSetOrange),
      trailing: TextButton.icon(
        onPressed: _busy || _checkingPerm ? null : _checkPermissions,
        icon: _checkingPerm
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.health_and_safety_rounded, size: 18),
        label: Text(r == null ? 'فحص الأذونات' : 'أعد الفحص'),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (r != null) ...[
          const SizedBox(height: 10),
          if (r.fatal != null)
            SetBanner('تعذّر الفحص: ${r.fatal}', kind: SetBannerKind.error)
          else if (r.allOk)
            const SetBanner('رُفع ملف اختبار صغير ثم نُزّل ثم حُذف بنجاح — Dropbox جاهز للنسخ.', kind: SetBannerKind.ok)
          else if (missing.isNotEmpty)
            SetBanner(
              'ينقص تطبيق Dropbox ${missing.length == 1 ? 'هذا الإذن فقط' : 'هذه الأذونات فقط'}: ${missing.join('، ')}. '
              'الإصلاح بالخطوات أدناه.',
              kind: SetBannerKind.warn,
            )
          else if (other != null)
            SetBanner('فشلت خطوة «${other.label}» لسبب غير الأذونات.', kind: SetBannerKind.error),
          const SizedBox(height: 10),
          for (final e in r.scopes.entries) _ScopeRow(scope: e.key, state: e.value),
          const SizedBox(height: 6),
          for (final p in r.probes) _ProbeRow(probe: p),
          if (r.tokenScopes == null && !r.allOk)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('هذا ربط قديم: لا نعرف ما منحه Dropbox لحظة الاتصال. اقطع الاتصال واربط من جديد لترى القائمة كاملة.',
                  style: TextStyle(fontSize: 12, color: kSetMuted, height: 1.5)),
            ),
        ],
        GuideToggle(
          label: missing.isNotEmpty ? 'كيف أضيف ${missing.length == 1 ? 'الإذن الناقص' : 'الأذونات الناقصة'}؟' : 'كيف أصلح أذونات Dropbox؟ (مرة واحدة)',
          color: _dbx,
          initiallyOpen: missing.isNotEmpty || listScopeError,
          child: SetupGuide(color: _dbx, steps: [
            const GuideStep(
              'هذه الخطوات لصاحب تطبيق Dropbox الذي يستعمله البرنامج (المطوّر) مرة واحدة فقط — '
              'من يستعمل البرنامج لا يدخل App Console أبداً، يضغط «ربط» فقط. '
              'Dropbox لا يسمح لأي برنامج بتعديل أذونات تطبيقه تلقائياً؛ لذلك هذه الخطوة يدوية.',
            ),
            GuideStep(
              'افتح App Console بحساب Dropbox الذي أنشأ التطبيق «$_appName»، واضغط على اسمه.',
              links: const [GuideLink('افتح App Console', DropboxBackupService.appConsoleUrl, icon: Icons.open_in_new_rounded)],
            ),
            GuideStep(
              'تأكّد أنه التطبيق نفسه: عمود «App key» في قائمة Apps يجب أن يساوي هذا المفتاح. '
              'إن اختلف فأنت تعدّل تطبيقاً آخر — غيّره من بطاقة «تطبيق Dropbox» أعلى الشاشة.',
              copies: [_appKey],
              warn: true,
            ),
            GuideStep(
              'افتح تبويب «Permissions» وضع ✔ أمام ${missing.isNotEmpty ? 'الناقص فقط' : 'هذه الأذونات'}:',
              copies: missing.isNotEmpty ? missing : DropboxBackupService.requiredScopes,
            ),
            const GuideStep('اضغط «Submit» أسفل صفحة Permissions — بدونه لا يُحفظ شيء.'),
            GuideStep(
              'ارجع هنا: «قطع الاتصال» ثم اربط من جديد. الربط القديم يحتفظ بأذوناته القديمة، '
              'والفحص يعمل تلقائياً بعد الربط.',
              warn: true,
              extra: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _logout,
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('قطع الاتصال الآن'),
                ),
              ),
            ),
          ]),
        ),
        if (bad && other != null && missing.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('أرسل ردّ Dropbox الظاهر أعلاه كما هو لمعرفة السبب.',
                style: TextStyle(fontSize: 12, color: kSetMuted)),
          ),
      ]),
    );
  }

  /// 🔑 تطبيق Dropbox المستعمل (الاسم والمفتاح كما في App Console) وتغييره.
  Widget _appCard() => SetCard(
        title: 'تطبيق Dropbox',
        subtitle: _appName,
        icon: Icons.apps_rounded,
        color: _dbx,
        trailing: TextButton.icon(
          onPressed: _busy ? null : _changeApp,
          icon: const Icon(Icons.edit_rounded, size: 18),
          label: const Text('تغيير'),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            const Text('App key: ', style: TextStyle(fontSize: 12.5, color: kSetMuted)),
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(_appKey,
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 13, color: kSetText)),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('يجب أن يطابق عمود «App key» في App Console',
                  style: TextStyle(fontSize: 12, color: kSetMuted), overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      );

  Future<void> _changeApp() async {
    final keyCtl = TextEditingController(text: _appKey);
    final nameCtl = TextEditingController(text: _appName);
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => ErpDialog(
          title: 'تطبيق Dropbox',
          icon: Icons.apps_rounded,
          color: _dbx,
          width: 480,
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SetBanner('انسخ «App key» من قائمة Apps في App Console. لا حاجة لـ App secret إطلاقاً. '
                'تغيير المفتاح يقطع الاتصال الحالي فتربط من جديد.'),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: 'اسم التطبيق (للعرض)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: keyCtl,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: 'App key', errorText: err, border: const OutlineInputBorder()),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _dbx),
              onPressed: () {
                if (!DropboxBackupService.isValidAppKey(keyCtl.text)) {
                  setD(() => err = 'مفتاح غير صحيح (حروف إنجليزية صغيرة وأرقام فقط)');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    final key = keyCtl.text;
    final name = nameCtl.text;
    // بعد انتهاء حركة إغلاق النافذة (الحقول ما زالت مرسومة أثناءها)
    Future.delayed(const Duration(milliseconds: 400), () {
      keyCtl.dispose();
      nameCtl.dispose();
    });
    if (ok != true || !mounted) return;
    try {
      await _backupService.setApp(key: key, name: name);
    } on DropboxException catch (e) {
      if (mounted) setToast(context, e.message, error: true);
      return;
    }
    await _loadApp();
    if (!mounted) return;
    setState(() {
      _perm = null;
      _lastResult = null;
    });
    await _checkAuthAndLoadBackups();
  }

  Widget _authCard() {
    return SetCard(
      title: 'ربط حساب Dropbox',
      subtitle: 'مرة واحدة على هذا الجهاز',
      icon: Icons.link_rounded,
      color: _dbx,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 10),
        if (_authStatus == DropboxAuthStatus.error) ...[
          const SetBanner('تعذّر الوصول إلى Dropbox الآن. إن كنت متصلاً سابقاً فلا داعي لتسجيل الدخول — أعد المحاولة بعد عودة الإنترنت.',
              kind: SetBannerKind.warn),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _checkAuthAndLoadBackups,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
          ),
          const SizedBox(height: 14),
        ],
        const SetupGuide(color: _dbx, steps: [
          GuideStep(
            'تحتاج حساباً في Dropbox (المجاني يكفي، 2 غيغابايت). إن لم يكن عندك أنشئه من الرابط، وإن كان عندك تخطَّ هذه الخطوة.',
            links: [
              GuideLink('إنشاء حساب Dropbox', 'https://www.dropbox.com/register', icon: Icons.person_add_alt_1_rounded),
              GuideLink('تسجيل الدخول', 'https://www.dropbox.com/login', icon: Icons.login_rounded),
            ],
          ),
          GuideStep('اضغط الزر الأزرق «فتح صفحة Dropbox» أدناه — يفتح المتصفح. سجّل الدخول إن طُلب منك.'),
          GuideStep('تظهر صفحة تسأل: هل تسمح لهذا التطبيق بالوصول؟ اضغط «Continue / متابعة» ثم «Allow / السماح».'),
          GuideStep(
            'تظهر صفحة فيها «Access Code Generated» وتحتها كود طويل. اضغط زر النسخ بجانبه (أو ظلّله وانسخه Ctrl+C)، '
            'وارجع هنا والصقه في الخانة (Ctrl+V) ثم اضغط «تأكيد».',
            note: 'الكود صالح دقائق قليلة فقط. إن ظهر أنه مرفوض اضغط «فتح صفحة Dropbox مجدداً» وكرّر.',
            warn: true,
          ),
        ]),
        const SizedBox(height: 6),
        SetPrimaryButton(
          label: _showCodeInput ? 'فتح صفحة Dropbox مجدداً' : 'فتح صفحة Dropbox',
          icon: Icons.open_in_new_rounded,
          color: _dbx,
          onPressed: _busy ? null : _startOAuthFlow,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: AlignmentDirectional.topStart,
          child: !_showCodeInput
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextField(
                      controller: _codeController,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'الكود من صفحة Dropbox',
                        hintText: 'الصق الكود هنا',
                        prefixIcon: Icon(Icons.key_rounded),
                      ),
                      onSubmitted: (_) => _submitAuthCode(),
                    ),
                    if (_authError != null) ...[
                      const SizedBox(height: 10),
                      SetBanner(_authError!, kind: SetBannerKind.error),
                    ],
                    const SizedBox(height: 10),
                    Row(children: [
                      TextButton(
                        onPressed: _busy ? null : () => setState(() => _showCodeInput = false),
                        child: const Text('إلغاء'),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 180,
                        child: SetPrimaryButton(
                          label: 'تأكيد',
                          icon: Icons.check_rounded,
                          color: _dbx,
                          busy: _connecting,
                          onPressed: _busy ? null : _submitAuthCode,
                        ),
                      ),
                    ]),
                  ]),
                ),
        ),
        if (!_showCodeInput && _authError != null) ...[
          const SizedBox(height: 10),
          SetBanner(_authError!, kind: SetBannerKind.error),
        ],
      ]),
    );
  }

  Widget _backupCard() {
    return SetCard(
      title: 'نسخة احتياطية جديدة',
      subtitle: 'لقطة كاملة من قاعدة البيانات الحالية',
      icon: Icons.backup_rounded,
      color: _dbx,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: !_backingUp
              ? SetPrimaryButton(
                  key: const ValueKey('btn'),
                  label: 'إنشاء نسخة ورفعها الآن',
                  icon: Icons.cloud_upload_rounded,
                  color: _dbx,
                  onPressed: _busy ? null : _createBackup,
                )
              : Column(
                  key: const ValueKey('prog'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _progress <= 0 ? null : _progress / 100,
                        minHeight: 10,
                        color: _dbx,
                        backgroundColor: const Color(0xFFE0ECFF),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: Text(_progressText, style: const TextStyle(color: kSetMuted))),
                      Text('$_progress%', style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
                    ]),
                  ],
                ),
        ),
        const SizedBox(height: 10),
        const Text(
          'تُرفع نسخة تلقائياً أيضاً مع «رفع قاعدة البيانات» إلى تيليجرام عندما يكون Dropbox متصلاً.',
          style: TextStyle(fontSize: 12, color: kSetMuted, height: 1.5),
        ),
      ]),
    );
  }

  Widget _settingsCard() {
    return SetCard(
      title: 'المساحة وعدد النسخ',
      subtitle: 'تُحذف الأقدم تلقائياً عند تجاوز العدد أو امتلاء المساحة — ولا تُحذف أحدث نسختين أبداً',
      icon: Icons.layers_rounded,
      color: _dbx,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_space != null) ...[_spaceBar(_space!), const SizedBox(height: 14)],
          const Text('أقصى عدد للنسخ:', style: TextStyle(fontWeight: FontWeight.w700, color: kSetText)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
          for (final n in DropboxBackupService.maxBackupsChoices)
            ChoiceChip(
              label: Text('$n نسخة'),
              selected: _maxBackups == n,
              showCheckmark: false,
              selectedColor: _dbx.withValues(alpha: 0.12),
              side: BorderSide(color: _maxBackups == n ? _dbx : kSetBorder),
              labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _maxBackups == n ? _dbx : kSetText),
              onSelected: _busy
                  ? null
                  : (_) {
                      setState(() => _maxBackups = n);
                      _backupService.setMaxBackups(n);
                    },
            ),
          ]),
        ]),
      ),
    );
  }

  /// 💾 شريط المساحة: المستعمل من الكلي، وما تشغله النسخ منه.
  Widget _spaceBar(DropboxSpace sp) {
    final total = sp.allocated;
    final backups = _backups.fold<int>(0, (a, b) => a + b.size);
    final frac = (total == null || total <= 0) ? null : (sp.used / total).clamp(0.0, 1.0);
    final ours = (total == null || total <= 0) ? 0.0 : (backups / total).clamp(0.0, 1.0);
    final color = frac != null && frac > 0.9 ? kSetRed : (frac != null && frac > 0.75 ? kSetOrange : _dbx);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.storage_rounded, size: 18, color: kSetMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            total == null
                ? 'المستعمل ${BackupSpacePlanner.human(sp.used)}'
                : 'مستعمل ${BackupSpacePlanner.human(sp.used)} من ${BackupSpacePlanner.human(total)}'
                    ' — الفارغ ${BackupSpacePlanner.human(sp.free ?? 0)}',
            style: const TextStyle(fontWeight: FontWeight.w700, color: kSetText, fontSize: 13),
          ),
        ),
      ]),
      if (frac != null) ...[
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 10,
            child: Stack(fit: StackFit.expand, children: [
              Container(color: const Color(0xFFE8EEF7)),
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: frac,
                child: Container(color: color.withValues(alpha: 0.35)),
              ),
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: ours,
                child: Container(color: color),
              ),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 6),
      Text('النسخ الاحتياطية تشغل ${BackupSpacePlanner.human(backups)} (${_backups.length} نسخة) — اللون الغامق في الشريط.',
          style: const TextStyle(fontSize: 12, color: kSetMuted)),
    ]);
  }

  Widget _listCard() {
    return SetCard(
      title: 'النسخ المحفوظة',
      subtitle: _backups.isEmpty ? null : 'الأحدث أولاً',
      icon: Icons.history_rounded,
      color: _dbx,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      trailing: _refreshing
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_listError != null) ...[
          SetBanner(_listError!, kind: SetBannerKind.error),
          const SizedBox(height: 10),
        ],
        if (_backups.isEmpty && _listError == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 26),
            child: Column(children: [
              Icon(Icons.cloud_queue_rounded, size: 44, color: Color(0xFFB8C2CF)),
              SizedBox(height: 10),
              Text('لا توجد نسخ بعد', style: TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
              SizedBox(height: 4),
              Text('اضغط «إنشاء نسخة ورفعها الآن» لأول نسخة.', style: TextStyle(color: kSetMuted)),
            ]),
          ),
        for (var i = 0; i < _backups.length; i++) _backupTile(_backups[i], latest: i == 0),
      ]),
    );
  }

  Widget _backupTile(BackupInfo b, {required bool latest}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: latest ? const Color(0xFFF5F9FF) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: latest ? _dbx.withValues(alpha: 0.30) : kSetBorder),
      ),
      child: Material(type: MaterialType.transparency, child: ListTile(
        contentPadding: const EdgeInsetsDirectional.fromSTEB(12, 4, 6, 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: _dbx.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.inventory_2_outlined, color: _dbx),
        ),
        title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(_df.format(b.modifiedTime),
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
          if (latest)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: _dbx.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: const Text('الأحدث', style: TextStyle(fontSize: 11, color: _dbx, fontWeight: FontWeight.w800)),
            ),
        ]),
        subtitle: Text('${_size(b.size)}  •  ${b.name}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kSetMuted)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'استعادة هذه النسخة',
            style: IconButton.styleFrom(backgroundColor: const Color(0xFFFFF7ED)),
            icon: const Icon(Icons.settings_backup_restore_rounded, color: kSetOrange),
            onPressed: _busy ? null : () => _restoreBackup(b),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'حذف',
            style: IconButton.styleFrom(backgroundColor: const Color(0xFFFEF2F2)),
            icon: const Icon(Icons.delete_outline_rounded, color: kSetRed),
            onPressed: _busy ? null : () => _deleteBackup(b),
          ),
        ]),
      )),
    );
  }
}

class _BusyDialog extends StatelessWidget {
  const _BusyDialog({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 16),
            Flexible(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
      );
}

/// سطر إذن: ✔ موجود / ✖ ناقص / ؟ غير معروف.
class _ScopeRow extends StatelessWidget {
  const _ScopeRow({required this.scope, required this.state});
  final String scope;
  final DropboxScopeState state;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color c, String label) = switch (state) {
      DropboxScopeState.granted => (Icons.check_circle_rounded, kSetGreen, 'موجود'),
      DropboxScopeState.missing => (Icons.cancel_rounded, kSetRed, 'ناقص'),
      DropboxScopeState.unknown => (Icons.help_rounded, kSetMuted, 'لم يُختبر'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: state == DropboxScopeState.missing ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: state == DropboxScopeState.missing ? const Color(0xFFFECACA) : kSetBorder),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: c),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(scope,
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 13, color: kSetText)),
            ),
            Text(DropboxBackupService.scopeMeaning[scope] ?? '', style: const TextStyle(fontSize: 12, color: kSetMuted)),
          ]),
        ),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
      ]),
    );
  }
}

/// سطر خطوة فحص: ما جُرّب ونتيجته، وردّ Dropbox عند الفشل.
class _ProbeRow extends StatelessWidget {
  const _ProbeRow({required this.probe});
  final DropboxProbe probe;

  @override
  Widget build(BuildContext context) {
    final c = probe.ok ? kSetGreen : kSetRed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(probe.ok ? Icons.check_rounded : Icons.close_rounded, size: 16, color: c),
          const SizedBox(width: 6),
          Expanded(child: Text(probe.label, style: const TextStyle(fontSize: 12.5, color: kSetText))),
          Text(probe.ok ? 'نجح' : 'فشل', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
        ]),
        if (!probe.ok && probe.detail != null)
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(probe.detail!,
                  style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: Color(0xFF7F1D1D), height: 1.4)),
            ),
          ),
      ]),
    );
  }
}
