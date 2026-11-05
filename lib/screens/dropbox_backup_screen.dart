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
  static const _redirectUri = 'http://localhost';

  final DropboxBackupService _backupService = DropboxBackupService();
  final _codeController = TextEditingController();
  final _df = DateFormat('yyyy/MM/dd  HH:mm');

  DropboxAuthStatus _authStatus = DropboxAuthStatus.notConfigured;
  List<BackupInfo> _backups = [];
  String? _account;
  String? _listError;
  DropboxSpace? _space; // 💾 مساحة الحساب

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
    _checkAuthAndLoadBackups();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthAndLoadBackups() async {
    setState(() => _refreshing = true);
    final status = await _backupService.checkAuthStatus();
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
    });
  }

  Future<void> _startOAuthFlow() async {
    final uri = Uri.parse(_backupService.getAuthorizationUrl(_redirectUri));
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
    final success = await _backupService.exchangeCodeForToken(input, _redirectUri);
    if (!mounted) return;
    setState(() => _connecting = false);
    if (success) {
      _codeController.clear();
      setState(() {
        _showCodeInput = false;
        _lastResult = (true, 'تم الاتصال بـ Dropbox بنجاح.');
      });
      await _checkAuthAndLoadBackups();
    } else {
      setState(() => _authError = 'رُفض الكود — قد يكون انتهى (صالح دقائق قليلة) أو نُسخ ناقصاً. اضغط «فتح صفحة Dropbox» مجدداً.');
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
      if (_lastResult != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SetBanner(_lastResult!.$2, kind: _lastResult!.$1 ? SetBannerKind.ok : SetBannerKind.error),
        ),
      if (!connected) _authCard() else ...[
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
        title: 'Dropbox',
        text: _account ?? 'احفظ نسخة من قاعدة بياناتك في حسابك على Dropbox، مع حذف النسخ الأقدم تلقائياً.',
        status: _statusPills(),
      );

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
            'يفتح المتصفح صفحة عنوانها يبدأ بـ http://localhost وقد يكتب «لا يمكن الوصول إلى هذا الموقع» — هذا طبيعي ومطلوب.',
            note: 'لا تغلق هذه الصفحة: المطلوب منها هو العنوان المكتوب في أعلاها فقط.',
          ),
          GuideStep(
            'اضغط على شريط العنوان أعلى المتصفح، ثم Ctrl+A ثم Ctrl+C لنسخه كاملاً، وارجع هنا والصقه في الخانة '
            '(Ctrl+V) ثم اضغط «تأكيد».',
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
                        labelText: 'الكود أو رابط الصفحة',
                        hintText: 'http://localhost/?code=...',
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
