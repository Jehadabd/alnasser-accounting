// lib/screens/telegram_settings_screen.dart
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/settings_manager.dart';
import '../services/telegram_invoice_export_service.dart';
import '../widgets/settings_kit.dart';
import 'package:url_launcher/url_launcher.dart';

class TelegramSettingsScreen extends StatefulWidget {
  const TelegramSettingsScreen({super.key});

  @override
  State<TelegramSettingsScreen> createState() => _TelegramSettingsScreenState();
}

class _TelegramSettingsScreenState extends State<TelegramSettingsScreen> {
  final _botTokenController = TextEditingController();
  final _channelIdController = TextEditingController();
  
  // Backup flags state
  bool _backupDebtRecordsPdf = true;
  bool _backupAccountStatementsPdf = true;
  bool _reportOnlyLocalInvoices = false;
  bool _reportDetailedDivided = false;

  bool _isLoading = false;
  bool _loaded = false;
  bool _testing = false;
  String? _channelName;

  /// نتيجة آخر اختبار للقناة: null = لم يُختبر.
  (bool ok, String msg)? _lastTest;
  static const _tg = Color(0xFF229ED9);
  String? _botName;
  
  // للتحكم في عرض التعليمات
  bool _showBotInstructions = false;
  bool _showChannelInstructions = false;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    final settings = await SettingsManager.getAppSettings();
    final onlyLocal = await SettingsManager.isReportOnlyLocalInvoices();
    final detailed = await SettingsManager.isReportDetailedDivided();
    
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _botTokenController.text = settings.telegramBotToken ?? '';
      _channelIdController.text = settings.telegramChannelId ?? '';
      _backupDebtRecordsPdf = settings.backupDebtRecordsPdf;
      _backupAccountStatementsPdf = settings.backupAccountStatementsPdf;
      _reportOnlyLocalInvoices = onlyLocal;
      _reportDetailedDivided = detailed;
    });
    // إذا كانت البيانات موجودة، حاول جلب الأسماء بشكل صامت
    if (_botTokenController.text.isNotEmpty) {
      _validateBotToken(silent: true);
    }
  }

  @override
  void dispose() {
    _botTokenController.dispose();
    _channelIdController.dispose();
    super.dispose();
  }

  // ... (نفس دوال الاستخراج والتحقق ولكن مع تحديثات طفيفة) ...

  String? _extractBotToken(String input) {
    final regex = RegExp(r'(\d{8,}:[A-Za-z0-9_-]{35,})');
    final match = regex.firstMatch(input);
    return match?.group(1);
  }

  String? _extractChannelId(String input) {
    try {
      final Map<String, dynamic> jsonData = json.decode(input);
      if (jsonData['ok'] == true && jsonData['result'] is List) {
        final results = jsonData['result'] as List;
        for (var update in results) {
          final message = update['channel_post'] ?? update['message'];
          if (message != null && message['chat'] != null) {
            final chatId = message['chat']['id'];
            if (chatId != null) return chatId.toString();
          }
        }
      }
    } catch (_) {}
    
    final regex = RegExp(r'(-100\d{10,13})');
    final match = regex.firstMatch(input);
    if (match != null) return match.group(1);
    
    final negativeRegex = RegExp(r'(-\d{10,})');
    final negativeMatch = negativeRegex.firstMatch(input);
    return negativeMatch?.group(1);
  }

  Future<bool> _validateBotToken({bool silent = false}) async {
    final token = _extractBotToken(_botTokenController.text.trim());
    if (token == null) {
      if (!silent) _showSnackBar('لم يتم العثور على توكن صالح', isError: true);
      return false;
    }

    if (!silent) setState(() => _isLoading = true);

    try {
      final response = await http.get(
        Uri.parse('https://api.telegram.org/bot$token/getMe'),
      ).timeout(const Duration(seconds: 10));

      final data = json.decode(response.body);
      if (data['ok'] == true) {
        if (mounted) {
          setState(() {
            _botTokenController.text = token;
            _botName = data['result']['first_name'] ?? data['result']['username'];
            _isLoading = false;
          });
        }
        return true;
      } else {
        if (mounted && !silent) { // Added !silent check
             setState(() => _isLoading = false); // Ensure stop loading
             _showSnackBar('التوكن غير صالح: ${data['description']}', isError: true);
        }
        return false;
      }
    } catch (e) {
      if (mounted && !silent) {
         setState(() => _isLoading = false);
         _showSnackBar('خطأ في الاتصال', isError: true);
      }
      return false;
    }
  }

  Future<void> _saveSettings() async {
    final token = _botTokenController.text.trim();
    final channelId = _channelIdController.text.trim();

    if (token.isEmpty || channelId.isEmpty) {
      _showSnackBar('الرجاء إكمال جميع الحقول', isError: true);
      return;
    }
    
    setState(() => _isLoading = true);
    
    // حفظ مباشر
    try {
      final updatedSettings = (await SettingsManager.getAppSettings()).copyWith(
        telegramBotToken: _botTokenController.text.trim(),
        telegramChannelId: _channelIdController.text.trim(),
        backupDebtRecordsPdf: _backupDebtRecordsPdf,
        backupAccountStatementsPdf: _backupAccountStatementsPdf,
      );
      await SettingsManager.saveAppSettings(updatedSettings);
      
      await SettingsManager.setReportOnlyLocalInvoices(_reportOnlyLocalInvoices);
      await SettingsManager.setReportDetailedDivided(_reportDetailedDivided);

      _showSnackBar('✅ تم حفظ الإعدادات بنجاح!');
      // فحص الاتصال كجزء من الحفظ
      await _sendTestMessage(silentSuccess: true); 
    } catch (e) {
      _showSnackBar('خطأ في الحفظ: $e', isError: true);
    } finally {
        if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendTestMessage({bool silentSuccess = false}) async {
    final token = _botTokenController.text.trim();
    final channelId = _channelIdController.text.trim();

    if (token.isEmpty || channelId.isEmpty) {
      if (!silentSuccess) _showSnackBar('أدخل التوكن ومعرّف القناة أولاً', isError: true);
      return;
    }
    if (mounted) setState(() => _testing = true);

    try {
      final response = await http.post(
        Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
        body: {
          'chat_id': channelId,
          'text': '✅ اختبار الاتصال من تطبيق إدارة المتجر.\n\nالإعدادات صحيحة وتعمل بنجاح!',
        },
      ).timeout(const Duration(seconds: 10));

      final data = json.decode(response.body);
      if (!mounted) return;
      if (data['ok'] == true) {
        setState(() {
          _channelName = data['result']['chat']['title'];
          _lastTest = (true, 'وصلت الرسالة التجريبية${_channelName == null ? '' : ' إلى «$_channelName»'} بنجاح.');
        });
        if (!silentSuccess) _showSnackBar('تم إرسال رسالة تجريبية بنجاح');
      } else {
        final desc = '${data['description'] ?? response.statusCode}';
        setState(() => _lastTest = (false, 'فشل الاتصال: ${_explainTelegramError(desc)}'));
        _showSnackBar('فشل الاتصال', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastTest = (false, 'خطأ في الإرسال — تحقّق من الإنترنت.\n$e'));
      _showSnackBar('خطأ في الإرسال', isError: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// ترجمة أشهر أخطاء Telegram إلى خطوة واضحة.
  String _explainTelegramError(String desc) {
    final d = desc.toLowerCase();
    if (d.contains('chat not found')) return 'القناة غير موجودة — تأكّد من المعرّف (يبدأ عادة بـ -100) ومن إضافة البوت إليها.';
    if (d.contains('not enough rights') || d.contains('not a member') || d.contains('forbidden')) {
      return 'البوت ليس مشرفاً في القناة — أضفه كـ Admin مع صلاحية النشر.';
    }
    if (d.contains('unauthorized')) return 'التوكن غير صحيح — انسخه من جديد من BotFather.';
    return desc;
  }

    Future<void> _exportAllInvoices() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ تأكيد رفع الأرشيف'),
        content: const Text(
          'سيتم إعادة إنشاء جميع ملفات PDF للفواتير وإرسالها إلى القناة.\nهذه العملية قد تستغرق وقتاً طويلاً.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('بدء الرفع')
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    final progress = ValueNotifier<(int, int, String)>((0, 0, 'جارٍ التحضير...'));
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(canPop: false, child: _ExportProgressDialog(progress: progress)),
    );

    try {
      final service = TelegramInvoiceExportService();
      final r = await service.exportAndSendAllInvoices(
        onProgress: (current, total, status) => progress.value = (current, total, status),
      );
      if (!mounted) return;
      Navigator.pop(context);
      // كانت الشاشة تقول «اكتملت العملية» حتى لو فشل الإرسال كله — الآن تعرض النتيجة الفعلية.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            r.success && r.failedCount == 0 ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            color: r.success && r.failedCount == 0 ? kSetGreen : kSetOrange,
            size: 40,
          ),
          title: Text(r.success ? 'انتهى رفع الأرشيف' : 'لم يكتمل رفع الأرشيف',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (r.message.isNotEmpty) Text(r.message, style: const TextStyle(height: 1.5)),
            if (r.totalCount > 0) ...[
              const SizedBox(height: 10),
              Text('الإجمالي: ${r.totalCount}  •  أُرسل: ${r.sentCount}  •  فشل: ${r.failedCount}  •  تُخطّي: ${r.skippedCount}',
                  style: const TextStyle(color: kSetMuted)),
            ],
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar('خطأ: $e', isError: true);
    }
    // لا نستدعي progress.dispose() هنا: نافذة التقدّم قد تكون ما زالت في حركة الإغلاق وتستمع إليه.
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    setToast(context, message, error: isError);
  }

  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _botName != null && _channelName != null;
    final busy = _isLoading || _testing;
    return SettingsScaffold(
      title: 'النسخ الاحتياطي عبر تيليجرام',
      subtitle: 'رفع قاعدة البيانات والتقارير إلى قناتك الخاصة',
      icon: Icons.telegram,
      loading: !_loaded,
      children: !_loaded
          ? null
          : [
              SetHero(
                icon: Icons.telegram,
                color: _tg,
                title: 'ربط مع تيليجرام',
                text: 'احصل على نسخ احتياطية وتقارير فورية على قناتك الخاصة. '
                    'تحتاج بوتاً (توكن) وقناة يكون البوت مشرفاً فيها.',
                status: Wrap(spacing: 8, runSpacing: 6, children: [
                  SetStatusPill(_botName != null ? 'البوت: $_botName' : 'البوت غير مُتحقَّق', ok: _botName != null),
                  SetStatusPill(_channelName != null ? 'القناة: $_channelName' : 'القناة غير مُختبرة',
                      ok: _channelName != null),
                ]),
              ),

              // 1) التوكن
              SetCard(
                title: 'توكن البوت (Bot Token)',
                subtitle: 'الخطوة 1 — من @BotFather',
                icon: Icons.smart_toy_outlined,
                color: _tg,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 8),
                  TextField(
                    controller: _botTokenController,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'التوكن',
                      hintText: 'ألصق التوكن (أو رسالة BotFather كاملة) هنا...',
                      prefixIcon: const Icon(Icons.vpn_key_rounded),
                      suffixIcon: _botName != null
                          ? const Icon(Icons.verified_rounded, color: kSetGreen)
                          : IconButton(
                              tooltip: 'تحقّق من التوكن',
                              icon: const Icon(Icons.fact_check_outlined),
                              onPressed: busy ? null : () => _validateBotToken(),
                            ),
                    ),
                    onChanged: (val) {
                      if (_botName != null) setState(() => _botName = null);
                      final token = _extractBotToken(val);
                      if (token != null && token != val) {
                        _botTokenController.text = token;
                        _botTokenController.selection = TextSelection.fromPosition(TextPosition(offset: token.length));
                      }
                    },
                  ),
                  _HelpToggle(
                    open: _showBotInstructions,
                    label: 'كيف أحصل على التوكن؟',
                    color: _tg,
                    onTap: () => setState(() => _showBotInstructions = !_showBotInstructions),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SetSteps(['ابحث عن ‎@BotFather‎ في تيليجرام.', 'أرسل ‎/newbot‎ واتبع التعليمات.', 'انسخ التوكن والصقه أعلاه.'],
                          color: _tg),
                      OutlinedButton.icon(
                        onPressed: () => _openUrl('https://t.me/BotFather'),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('فتح BotFather'),
                      ),
                    ]),
                  ),
                ]),
              ),

              // 2) القناة
              SetCard(
                title: 'معرّف القناة (Channel ID)',
                subtitle: 'الخطوة 2 — القناة التي ستصلها النسخ',
                icon: Icons.campaign_outlined,
                color: _tg,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 8),
                  TextField(
                    controller: _channelIdController,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'المعرّف',
                      hintText: 'مثال: ‎-100123456789',
                      prefixIcon: Icon(Icons.tag_rounded),
                    ),
                    onChanged: (val) {
                      if (_channelName != null) setState(() => _channelName = null);
                      // لصق ردّ getUpdates كاملاً → نستخرج المعرّف تلقائياً
                      if (val.length > 20 && !RegExp(r'^-?\d+$').hasMatch(val.trim())) {
                        final id = _extractChannelId(val);
                        if (id != null) {
                          _channelIdController.text = id;
                          _channelIdController.selection = TextSelection.collapsed(offset: id.length);
                        }
                      }
                    },
                  ),
                  _HelpToggle(
                    open: _showChannelInstructions,
                    label: 'كيف أحصل على المعرّف؟',
                    color: _tg,
                    onTap: () => setState(() => _showChannelInstructions = !_showChannelInstructions),
                    child: const SetSteps([
                      'أضف البوت كـ Admin في قناتك (مع صلاحية النشر).',
                      'أرسل أي رسالة في القناة.',
                      'استخرج معرّف القناة (مثلاً عبر ‎@getidsbot‎) والصقه أعلاه — يبدأ عادة بـ ‎-100‎.',
                    ], color: _tg),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _lastTest == null
                        ? const SizedBox.shrink()
                        : Padding(
                            key: ValueKey(_lastTest),
                            padding: const EdgeInsets.only(top: 12),
                            child: SetBanner(_lastTest!.$2, kind: _lastTest!.$1 ? SetBannerKind.ok : SetBannerKind.error),
                          ),
                  ),
                ]),
              ),

              // 3) المحتوى
              SetCard(
                title: 'محتوى النسخ والتقارير',
                subtitle: 'ما يُرفق مع كل نسخة احتياطية',
                icon: Icons.inventory_2_outlined,
                color: _tg,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(children: [
                  SetSwitch(
                    title: 'إرفاق تقرير الديون (PDF)',
                    subtitle: 'ملف PDF يحتوي على قائمة الديون الحالية',
                    icon: Icons.receipt_long_rounded,
                    color: _tg,
                    value: _backupDebtRecordsPdf,
                    onChanged: (v) => setState(() => _backupDebtRecordsPdf = v),
                  ),
                  const Divider(height: 1),
                  SetSwitch(
                    title: 'إرفاق كشوفات الحسابات (PDF)',
                    subtitle: 'ملف PDF شامل لكشوفات حسابات جميع العملاء',
                    icon: Icons.description_outlined,
                    color: _tg,
                    value: _backupAccountStatementsPdf,
                    onChanged: (v) => setState(() => _backupAccountStatementsPdf = v),
                  ),
                  const Divider(height: 1),
                  SetSwitch(
                    title: 'إحصائيات فواتير هذا الجهاز فقط',
                    subtitle: 'استثناء الفواتير المزامَنة من حواسيب أخرى من التقارير',
                    icon: Icons.computer_rounded,
                    color: _tg,
                    value: _reportOnlyLocalInvoices,
                    onChanged: (v) => setState(() => _reportOnlyLocalInvoices = v),
                  ),
                  const Divider(height: 1),
                  SetSwitch(
                    title: 'تقرير مفصّل ومقسّم',
                    subtitle: 'تقرير لكل قسم بدلاً من إجمالي واحد',
                    icon: Icons.segment_rounded,
                    color: _tg,
                    value: _reportDetailedDivided,
                    onChanged: (v) => setState(() => _reportDetailedDivided = v),
                  ),
                ]),
              ),

              // الحفظ والاختبار
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50), foregroundColor: _tg),
                    onPressed: busy ? null : () => _sendTestMessage(),
                    icon: _testing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                    label: const Text('رسالة تجريبية'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SetPrimaryButton(
                    label: connected ? 'حفظ' : 'حفظ وربط الاتصال',
                    icon: Icons.save_rounded,
                    color: _tg,
                    busy: _isLoading,
                    onPressed: busy ? null : _saveSettings,
                  ),
                ),
              ]),
              const SizedBox(height: 16),

              // إجراءات متقدمة
              SetCard(
                title: 'إجراءات متقدمة',
                icon: Icons.tune_rounded,
                color: kSetOrange,
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                child: SetActionRow(
                  icon: Icons.cloud_upload_outlined,
                  title: 'رفع أرشيف الفواتير بالكامل',
                  subtitle: 'إعادة إنشاء PDF لكل الفواتير القديمة وإرسالها للقناة — قد يستغرق وقتاً طويلاً',
                  color: kSetOrange,
                  onTap: busy ? null : _exportAllInvoices,
                ),
              ),
            ],
    );
  }
}

/// زر «كيف…؟» يفتح شرحاً تحته بحركة ناعمة.
class _HelpToggle extends StatelessWidget {
  const _HelpToggle({
    required this.open,
    required this.label,
    required this.onTap,
    required this.child,
    required this.color,
  });
  final bool open;
  final String label;
  final VoidCallback onTap;
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 6),
      TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: color),
        onPressed: onTap,
        icon: AnimatedRotation(
          turns: open ? 0.5 : 0,
          duration: const Duration(milliseconds: 200),
          child: const Icon(Icons.expand_more_rounded),
        ),
        label: Text(label),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: AlignmentDirectional.topStart,
        child: !open
            ? const SizedBox(width: double.infinity)
            : Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.18)),
                ),
                child: child,
              ),
      ),
    ]);
  }
}

/// نافذة تقدّم رفع الأرشيف (كانت دائرة تحميل بلا أي معلومة).
class _ExportProgressDialog extends StatelessWidget {
  const _ExportProgressDialog({required this.progress});
  final ValueListenable<(int, int, String)> progress;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: ValueListenableBuilder<(int, int, String)>(
            valueListenable: progress,
            builder: (context, v, _) {
              final (cur, total, status) = v;
              final frac = total > 0 ? (cur / total).clamp(0.0, 1.0) : null;
              return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Row(children: [
                  Icon(Icons.cloud_upload_rounded, color: Color(0xFF229ED9), size: 28),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('جارٍ رفع الأرشيف إلى تيليجرام',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kSetText)),
                  ),
                ]),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 10,
                    color: const Color(0xFF229ED9),
                    backgroundColor: const Color(0xFFE0F2FE),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: Text(status,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kSetMuted, fontSize: 12.5)),
                  ),
                  if (total > 0)
                    Text('$cur / $total', style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
                ]),
                const SizedBox(height: 10),
                const Text('لا تغلق التطبيق حتى تنتهي العملية.', style: TextStyle(fontSize: 12, color: kSetOrange)),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
