// lib/screens/simplex_settings_screen.dart
//
// 🛡️ إعدادات النسخ الاحتياطي عبر SimpleX — بديل تيليجرام المجاني.
// خطوتان فقط: تثبيت المحرك على هذه الحاسبة (ضغطة واحدة)، ثم مسح رمز QR من هاتفك.
// المحتوى (التقارير، الفواتير، الملخص) هو نفسه المضبوط لتيليجرام — الإعدادات مشتركة.

import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings_manager.dart';
import '../services/simplex/simplex_backup_service.dart';
import '../services/simplex/simplex_engine.dart';
import '../services/simplex/upload_route.dart';
import '../services/telegram_backup_service.dart';
import '../services/telegram_invoice_export_service.dart';
import '../widgets/settings_kit.dart';
import '../widgets/setup_guide.dart';

class SimplexSettingsScreen extends StatefulWidget {
  const SimplexSettingsScreen({super.key});

  @override
  State<SimplexSettingsScreen> createState() => _SimplexSettingsScreenState();
}

class _SimplexSettingsScreenState extends State<SimplexSettingsScreen> {
  static const _sx = Color(0xFF0053D0);

  bool _loaded = false;
  bool _installed = false;
  String? _version;
  String? _phone; // اسم الهاتف المربوط
  bool _linked = false;

  bool _installing = false;
  String _installStep = '';
  double? _installProgress;

  String? _invite; // رابط الدعوة المعروض رمزاً
  bool _waiting = false;
  bool _busy = false;
  (bool, String)? _lastResult;

  // المحتوى (مشترك مع تيليجرام)
  bool _debtPdf = true;
  bool _statementsPdf = true;
  bool _summary = true;
  String _regularMode = 'each';
  String _posMode = 'each';
  bool _resendEdited = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = SimplexBackupService();
    final installed = await SimplexEngine.isInstalled();
    final version = await SimplexEngine.installedVersion();
    final id = await svc.contactId();
    final name = await svc.contactName();
    final s = await SettingsManager.getAppSettings();
    final summary = await TelegramBackupService.monthlySummaryEnabled();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _installed = installed;
      _version = version;
      _linked = id != null;
      _phone = name;
      _debtPdf = s.backupDebtRecordsPdf;
      _statementsPdf = s.backupAccountStatementsPdf;
      _summary = summary;
      _regularMode = s.telegramRegularInvoicesMode;
      _posMode = s.telegramPosInvoicesMode;
      _resendEdited = s.telegramResendEdited;
    });
  }

  void _toast(String m, {bool error = false}) {
    if (mounted) setToast(context, m, error: error);
  }

  // ───────────── المحرك ─────────────

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _installStep = 'جارٍ البدء…';
      _installProgress = null;
    });
    try {
      await SimplexEngine.install(step: (t, [f]) {
        if (mounted) {
          setState(() {
            _installStep = t;
            _installProgress = f;
          });
        }
      });
      if (mounted) setState(() => _installStep = 'تشغيل المحرك لأول مرة…');
      await SimplexEngine.ensureRunning();
      _toast('تم تثبيت محرك SimpleX وتشغيله');
    } catch (e) {
      _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _installing = false);
      await _load();
    }
  }

  // ───────────── الربط ─────────────

  Future<void> _makeInvite() async {
    setState(() {
      _busy = true;
      _lastResult = null;
    });
    try {
      final link = await SimplexBackupService().createInvite();
      if (!mounted) return;
      setState(() {
        _invite = link;
        _waiting = true;
        _busy = false;
      });
      final name = await SimplexBackupService().waitForPhone();
      if (!mounted) return;
      setState(() {
        _invite = null;
        _waiting = false;
        _lastResult = (true, 'تم ربط الهاتف${name.isEmpty ? '' : ' «$name»'} — وصلته رسالة تأكيد في SimpleX');
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _invite = null;
        _waiting = false;
        _busy = false;
        _lastResult = (false, '$e');
      });
    }
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _lastResult = null;
    });
    final r = await SimplexBackupService().sendText('🧪 رسالة تجريبية من برنامج الناصر — الربط يعمل.');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastResult = r.success ? (true, 'أُرسلت الرسالة — افتح SimpleX على هاتفك') : (false, r.error ?? 'فشل الإرسال');
    });
  }

  Future<void> _unlink() async {
    final ok = await _confirm('فصل الهاتف', 'لن تصل النسخ إلى هذا الهاتف بعد الآن، وتُحذف محادثته عند البوت. يمكنك الربط من جديد في أي وقت.');
    if (!ok) return;
    setState(() => _busy = true);
    await SimplexBackupService().unlink();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastResult = null;
    });
    await _load();
  }

  Future<void> _reset() async {
    final ok = await _confirm('إعادة ضبط SimpleX',
        'يُحذف حساب البوت وجهات الاتصال على هذه الحاسبة (الملف التنفيذي يبقى). تحتاج بعدها إلى ربط هاتفك من جديد. استعملها فقط إن تعطّل المحرك.');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await SimplexEngine.reset();
      await SimplexBackupService().forgetLocal();
      _toast('أُعيد الضبط — اربط هاتفك من جديد');
    } catch (e) {
      _toast('$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  Future<bool> _confirm(String title, String text) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(text, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('متابعة')),
        ],
      ),
    );
    return r == true;
  }

  // ───────────── المحتوى (مشترك مع تيليجرام) ─────────────

  Future<void> _saveContent({bool? debtPdf, bool? statementsPdf, bool? summary}) async {
    setState(() {
      _debtPdf = debtPdf ?? _debtPdf;
      _statementsPdf = statementsPdf ?? _statementsPdf;
      _summary = summary ?? _summary;
    });
    try {
      if (debtPdf != null || statementsPdf != null) {
        await SettingsManager.saveAppSettings((await SettingsManager.getAppSettings())
            .copyWith(backupDebtRecordsPdf: _debtPdf, backupAccountStatementsPdf: _statementsPdf));
      }
      if (summary != null) await TelegramBackupService.setMonthlySummaryEnabled(summary);
      _toast('حُفظ');
    } catch (e) {
      _toast('تعذّر الحفظ: $e', error: true);
    }
  }

  Future<void> _saveModes({String? regular, String? pos, bool? resend}) async {
    setState(() {
      _regularMode = regular ?? _regularMode;
      _posMode = pos ?? _posMode;
      _resendEdited = resend ?? _resendEdited;
    });
    try {
      await SettingsManager.saveAppSettings((await SettingsManager.getAppSettings()).copyWith(
        telegramRegularInvoicesMode: _regularMode,
        telegramPosInvoicesMode: _posMode,
        telegramResendEdited: _resendEdited,
      ));
      _toast('حُفظ');
    } catch (e) {
      _toast('تعذّر الحفظ: $e', error: true);
    }
  }

  Future<void> _exportArchive() async {
    final ok = await _confirm('رفع أرشيف الفواتير بالكامل',
        'يُعاد إنشاء PDF لكل الفواتير المحفوظة وإرسالها إلى هاتفك عبر SimpleX. قد يستغرق وقتاً طويلاً.');
    if (!ok || !mounted) return;
    final progress = ValueNotifier<(int, int, String)>((0, 0, 'جارٍ التحضير…'));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('جارٍ رفع الأرشيف إلى SimpleX'),
          content: ValueListenableBuilder<(int, int, String)>(
            valueListenable: progress,
            builder: (_, v, __) => Column(mainAxisSize: MainAxisSize.min, children: [
              LinearProgressIndicator(value: v.$2 > 0 ? (v.$1 / v.$2).clamp(0.0, 1.0) : null, color: _sx),
              const SizedBox(height: 10),
              Text(v.$2 > 0 ? '${v.$3}  (${v.$1} / ${v.$2})' : v.$3, style: const TextStyle(color: kSetMuted)),
            ]),
          ),
        ),
      ),
    );
    try {
      final r = await UploadRoute.runSimplex(() => TelegramInvoiceExportService()
          .exportAndSendAllInvoices(onProgress: (c, t, s) => progress.value = (c, t, s)));
      if (!mounted) return;
      Navigator.pop(context);
      _toast(r.failedCount == 0 ? 'انتهى: أُرسلت ${r.sentCount} فاتورة' : 'أُرسلت ${r.sentCount} وفشلت ${r.failedCount}',
          error: r.failedCount > 0);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _toast('خطأ: $e', error: true);
    }
  }

  void _showLog() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('سجل محرك SimpleX'),
        content: SizedBox(
          width: 560,
          height: 360,
          child: ValueListenableBuilder<List<String>>(
            valueListenable: SimplexEngine.log,
            builder: (_, l, __) => l.isEmpty
                ? const Center(child: Text('لا شيء بعد', style: TextStyle(color: kSetMuted)))
                : SelectableText(l.join('\n'), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق'))],
      ),
    );
  }

  // ───────────── الواجهة ─────────────

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'النسخ الاحتياطي عبر SimpleX',
      subtitle: 'بديل تيليجرام المجاني — إلى هاتفك مباشرة',
      icon: Icons.shield_rounded,
      loading: !_loaded,
      children: !_loaded ? null : _content(),
    );
  }

  List<Widget> _content() {
    if (!SimplexEngine.supported) {
      return [
        const SetBanner('النسخ عبر SimpleX متاح حالياً من برنامج Windows فقط (هو الذي يرسل). '
            'على الهاتف ثبّت تطبيق SimpleX لتستقبل.', kind: SetBannerKind.warn),
      ];
    }
    final busy = _busy || _installing || _waiting;
    return [
      SetHero(
        icon: Icons.shield_rounded,
        color: _sx,
        title: 'ربط مع SimpleX',
        text: 'المرسل: هذه الحاسبة (بوت باسم «${SimplexEngine.botName}»). المستقبل: هاتفك فقط، في محادثة خاصة مشفّرة. '
            'مجاني بالكامل، بلا رقم هاتف ولا حساب ولا توكن، وحد الملف 1 غيغابايت.',
        status: Wrap(spacing: 8, runSpacing: 6, children: [
          SetStatusPill(_installed ? 'المحرك مثبّت${_version != null ? ' ($_version)' : ''}' : 'المحرك غير مثبّت', ok: _installed),
          SetStatusPill(_linked ? 'الهاتف مربوط${(_phone ?? '').isNotEmpty ? ': $_phone' : ''}' : 'لا هاتف مربوط', ok: _linked),
        ]),
      ),

      // 1) المحرك
      SetCard(
        title: 'محرك SimpleX على هذه الحاسبة',
        subtitle: 'الخطوة 1 — مرة واحدة',
        icon: Icons.memory_rounded,
        color: _sx,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 6),
          const Text(
            'برنامج SimpleX الرسمي (نسخة سطر الأوامر) يُنزَّل من صفحة إصداراته على GitHub، وتُطابق بصمته قبل تشغيله. '
            'يعمل في الخلفية بلا نافذة، ولا يقبل اتصالاً إلا من هذه الحاسبة نفسها.',
            style: TextStyle(color: kSetMuted, height: 1.5, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (_installing) ...[
            LinearProgressIndicator(value: _installProgress, color: _sx),
            const SizedBox(height: 8),
            Text(_installStep, style: const TextStyle(color: kSetMuted, fontSize: 12.5)),
          ] else if (_installed) ...[
            // مثبّت: لا زر بارز (كان «إعادة التنزيل والتحقق» يبدو كأنه مطلوب فيُنزَّل الملف مرة ثانية بلا داعٍ)
            const SetBanner('المحرك مثبّت وبصمته مطابقة للإصدار الرسمي — لا حاجة لفعل شيء هنا. انتقل إلى الخطوة 2.',
                kind: SetBannerKind.ok),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        if (await _confirm('إعادة تنزيل المحرك',
                            'لا تحتاجها إلا إذا تعطّل المحرك أو حُذف ملفه. سيُنزَّل الملف (نحو 130 ميغا) من جديد وتُطابق بصمته. ربط هاتفك لا يتأثر.')) {
                          await _install();
                        }
                      },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('إعادة التنزيل (عند العطل فقط)'),
              ),
            ),
          ] else
            SetPrimaryButton(
              label: 'تثبيت المحرك',
              icon: Icons.download_rounded,
              color: _sx,
              onPressed: busy ? null : _install,
            ),
        ]),
      ),

      // 2) الهاتف
      SetCard(
        title: 'ربط هاتفك',
        subtitle: 'الخطوة 2 — امسح الرمز من تطبيق SimpleX',
        icon: Icons.qr_code_2_rounded,
        color: _sx,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 6),
          GuideToggle(
            label: 'كيف أربط هاتفي؟ (شرح خطوة بخطوة)',
            color: _sx,
            initiallyOpen: !_linked,
            child: SetupGuide(steps: _phoneSteps(), color: _sx),
          ),
          const SizedBox(height: 10),
          if (_invite != null) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kSetBorder)),
                child: SizedBox(width: 240, height: 240, child: CustomPaint(painter: _QrPainter(_invite!))),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              const Flexible(child: Text('بانتظار مسح الرمز من هاتفك… (الرمز لمرة واحدة)', style: TextStyle(color: kSetMuted))),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _invite!));
                  _toast('نُسخ الرابط');
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('نسخ الرابط'),
              ),
              TextButton(
                // إخفاء فقط: إن مُسح الرمز لاحقاً يُحفظ الربط ويظهر عند فتح الشاشة
                onPressed: () => setState(() {
                  _invite = null;
                  _waiting = false;
                }),
                child: const Text('إلغاء'),
              ),
            ]),
          ] else if (_linked)
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: _sx),
                  onPressed: busy ? null : _test,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('رسالة تجريبية'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: busy ? null : _makeInvite,
                  icon: const Icon(Icons.phonelink_setup_rounded),
                  label: const Text('ربط هاتف آخر'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'فصل الهاتف',
                onPressed: busy ? null : _unlink,
                icon: const Icon(Icons.link_off_rounded, color: kSetRed),
              ),
            ])
          else
            SetPrimaryButton(
              label: 'إنشاء رمز الربط',
              icon: Icons.qr_code_rounded,
              color: _sx,
              busy: _busy,
              onPressed: (!_installed || busy) ? null : _makeInvite,
            ),
          if (!_installed && _invite == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('ثبّت المحرك أولاً (الخطوة 1).', style: TextStyle(color: kSetMuted, fontSize: 12.5)),
            ),
          if (_lastResult != null) ...[
            const SizedBox(height: 12),
            SetBanner(_lastResult!.$2, kind: _lastResult!.$1 ? SetBannerKind.ok : SetBannerKind.error),
          ],
        ]),
      ),

      const SetBanner(
        'الملفات تمر عبر خوادم نقل SimpleX المجانية وتبقى عليها نحو يومين فقط حتى ينزّلها هاتفك. '
        'افتح SimpleX على هاتفك وانقر الملف لتنزيله. الأرشيف الدائم مكانه Google Drive أو Dropbox.',
        kind: SetBannerKind.warn,
      ),
      const SizedBox(height: 12),

      // 3) المحتوى — مشترك مع تيليجرام
      SetCard(
        title: 'محتوى النسخ والتقارير',
        subtitle: 'الإعدادات نفسها في تيليجرام (مشتركة) — تُحفظ فور التغيير',
        icon: Icons.inventory_2_outlined,
        color: _sx,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(children: [
          SetSwitch(
            title: 'إرفاق تقرير الديون (PDF)',
            subtitle: 'ملف PDF يحتوي على قائمة الديون الحالية',
            icon: Icons.receipt_long_rounded,
            color: _sx,
            value: _debtPdf,
            onChanged: (v) => _saveContent(debtPdf: v),
          ),
          const Divider(height: 1),
          SetSwitch(
            title: 'إرفاق كشوفات الحسابات (PDF)',
            subtitle: 'ملف PDF شامل لكشوفات حسابات جميع العملاء',
            icon: Icons.description_outlined,
            color: _sx,
            value: _statementsPdf,
            onChanged: (v) => _saveContent(statementsPdf: v),
          ),
          const Divider(height: 1),
          SetSwitch(
            title: 'إرسال الملخص الشهري',
            subtitle: 'رسالة بمبيعات الشهر وأرباحه مع كل رفع',
            icon: Icons.summarize_rounded,
            color: _sx,
            value: _summary,
            onChanged: (v) => _saveContent(summary: v),
          ),
          const Divider(height: 1),
          _modeRow(Icons.receipt_long_rounded, 'الفواتير العادية والجملة', _regularMode, (v) => _saveModes(regular: v)),
          const Divider(height: 1),
          _modeRow(Icons.point_of_sale_rounded, 'إيصالات الكاشير', _posMode, (v) => _saveModes(pos: v)),
          const Divider(height: 1),
          SetSwitch(
            title: 'إعادة رفع الفاتورة بعد تعديلها',
            subtitle: 'فاتورة رُفعت ثم عُدّلت تُرفع نسختها الجديدة مع علامة «معدّلة»',
            icon: Icons.edit_note_rounded,
            color: _sx,
            value: _resendEdited,
            onChanged: (v) => _saveModes(resend: v),
          ),
        ]),
      ),

      // متقدم
      SetCard(
        title: 'إجراءات متقدمة',
        icon: Icons.tune_rounded,
        color: kSetOrange,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
        child: Column(children: [
          SetActionRow(
            icon: Icons.cloud_upload_outlined,
            title: 'رفع أرشيف الفواتير بالكامل',
            subtitle: 'إعادة إنشاء PDF لكل الفواتير القديمة وإرسالها لهاتفك — قد يستغرق وقتاً طويلاً',
            color: kSetOrange,
            onTap: (busy || !_linked) ? null : _exportArchive,
          ),
          SetActionRow(
            icon: Icons.article_outlined,
            title: 'سجل المحرك',
            subtitle: 'للتشخيص عند وجود مشكلة',
            color: kSetNavy,
            onTap: _showLog,
          ),
          SetActionRow(
            icon: Icons.restart_alt_rounded,
            title: 'إعادة ضبط SimpleX',
            subtitle: 'عند تعطّل المحرك فقط — يلزم ربط الهاتف من جديد',
            color: kSetRed,
            danger: true,
            onTap: busy ? null : _reset,
          ),
        ]),
      ),
    ];
  }

  Widget _modeRow(IconData icon, String title, String value, ValueChanged<String> onChanged) {
    const labels = {'each': 'كل فاتورة وحدها', 'combined': 'ملف PDF واحد', 'off': 'لا ترفع'};
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 20, color: _sx),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: kSetText))),
        DropdownButton<String>(
          value: labels.containsKey(value) ? value : 'each',
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(12),
          items: [for (final e in labels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ]),
    );
  }

  List<GuideStep> _phoneSteps() => const [
        GuideStep(
          'ثبّت تطبيق SimpleX Chat على هاتفك (مجاني، بلا رقم هاتف).',
          links: [
            GuideLink('Google Play', 'https://play.google.com/store/apps/details?id=chat.simplex.app', icon: Icons.download_rounded),
            GuideLink('App Store', 'https://apps.apple.com/app/simplex-chat/id1605771084', icon: Icons.phone_iphone_rounded),
            GuideLink('الموقع الرسمي', 'https://simplex.chat', icon: Icons.language_rounded),
          ],
        ),
        GuideStep('افتح التطبيق وأنشئ ملفاً شخصياً بأي اسم (اسمك أو اسم المحل).'),
        GuideStep('اضغط «إنشاء رمز الربط» هنا في البرنامج.'),
        GuideStep(
          'في SimpleX على الهاتف اضغط زر القلم (أو +) ثم «مسح / لصق رابط» (Scan / paste link) وامسح الرمز الظاهر على الشاشة.',
          note: 'الرمز يصلح لمرة واحدة فقط: بعد مسحه لا يمكن لغيرك استعماله.',
        ),
        GuideStep('خلال ثوانٍ تصلك رسالة تأكيد من «Alnaser Backup» — انتهى الربط. من الآن كل «رفع البيانات» يصل هناك.'),
      ];
}

/// رمز QR مرسوم مباشرة (مكتبة barcode الموجودة في البرنامج).
class _QrPainter extends CustomPainter {
  _QrPainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    final els = Barcode.qrCode(errorCorrectLevel: BarcodeQRCorrectionLevel.low).make(data, width: size.width, height: size.height);
    for (final e in els) {
      if (e is BarcodeBar && e.black) {
        canvas.drawRect(Rect.fromLTWH(e.left, e.top, e.width + 0.5, e.height + 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
