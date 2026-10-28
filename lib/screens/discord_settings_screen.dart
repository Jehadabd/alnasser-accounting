// lib/screens/discord_settings_screen.dart
//
// 💬 ربط Discord (Webhook) لاستقبال التقارير والنسخ — بالشكل الموحّد للإعدادات.
// المنطق كما كان (حفظ الرابط في SharedPreferences ثم رسالة تجريبية)، مع إضافات:
//   • نتيجة آخر اختبار تظهر داخل الشاشة (لا تختفي مع رسالة سريعة).
//   • التحقق من أن الرابط رابط Webhook فعلاً قبل الحفظ.
//   • زر «إلغاء الربط» (الخدمة تعتبر الرابط الفارغ = غير مُعدّ).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/settings_manager.dart';
import '../widgets/settings_kit.dart';

class DiscordSettingsScreen extends StatefulWidget {
  const DiscordSettingsScreen({super.key});

  @override
  State<DiscordSettingsScreen> createState() => _DiscordSettingsScreenState();
}

class _DiscordSettingsScreenState extends State<DiscordSettingsScreen> {
  static const _discord = Color(0xFF5865F2);

  final _webhookUrlController = TextEditingController();

  bool _loaded = false;
  bool _isLoading = false;
  bool _testing = false;
  bool _obscure = true;
  String _savedUrl = '';

  /// نتيجة آخر اختبار: null = لم يُختبر بعد.
  (bool ok, String msg)? _lastTest;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    final url = await SettingsManager.getDiscordWebhookUrl();
    if (!mounted) return;
    setState(() {
      _savedUrl = url ?? '';
      _webhookUrlController.text = _savedUrl;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _webhookUrlController.dispose();
    super.dispose();
  }

  bool get _configured => _savedUrl.isNotEmpty && _savedUrl.startsWith('http');

  /// رابط Webhook صالح: https://discord.com/api/webhooks/<id>/<token> (أو discordapp.com).
  bool _looksLikeWebhook(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !u.hasScheme || !u.scheme.startsWith('http')) return false;
    final hostOk = u.host.endsWith('discord.com') || u.host.endsWith('discordapp.com');
    return hostOk && u.path.contains('/api/webhooks/');
  }

  Future<void> _saveSettings() async {
    final url = _webhookUrlController.text.trim();
    if (url.isEmpty || !url.startsWith('http')) {
      setToast(context, 'الرجاء إدخال رابط Webhook صحيح', error: true);
      return;
    }
    if (!_looksLikeWebhook(url)) {
      final go = await _confirm(
        'الرابط لا يشبه رابط Webhook',
        'رابط Discord الصحيح يبدأ بـ https://discord.com/api/webhooks/ — هل تريد حفظه رغم ذلك؟',
      );
      if (go != true) return;
    }

    setState(() => _isLoading = true);
    try {
      await SettingsManager.setDiscordWebhookUrl(url);
      if (!mounted) return;
      setState(() => _savedUrl = url);
      setToast(context, 'تم حفظ الرابط — جارٍ اختبار الاتصال…');
      await _sendTestMessage(silentSuccess: true);
    } catch (e) {
      if (mounted) setToast(context, 'خطأ في الحفظ: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unlink() async {
    final go = await _confirm('إلغاء ربط Discord', 'لن تُرسل التقارير إلى Discord بعد الآن. متابعة؟');
    if (go != true) return;
    await SettingsManager.setDiscordWebhookUrl('');
    if (!mounted) return;
    setState(() {
      _savedUrl = '';
      _webhookUrlController.clear();
      _lastTest = null;
    });
    setToast(context, 'تم إلغاء الربط');
  }

  Future<void> _sendTestMessage({bool silentSuccess = false}) async {
    final url = _webhookUrlController.text.trim();
    if (url.isEmpty) {
      setToast(context, 'أدخل رابط Webhook أولاً', error: true);
      return;
    }
    setState(() => _testing = true);
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'content': '✅ اختبار الاتصال من تطبيق إدارة المتجر.\n\nالإعدادات صحيحة وتعمل بنجاح!'}),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() => _lastTest = (true, 'وصلت الرسالة التجريبية إلى القناة بنجاح.'));
        if (!silentSuccess) setToast(context, 'تم إرسال رسالة تجريبية بنجاح');
      } else {
        final hint = switch (response.statusCode) {
          401 || 403 => 'الرابط مرفوض — ربما حُذف الـ Webhook أو نُسخ ناقصاً.',
          404 => 'الـ Webhook غير موجود — أنشئ واحداً جديداً وانسخ رابطه.',
          429 => 'طلبات كثيرة — انتظر قليلاً ثم أعد المحاولة.',
          _ => 'رمز الاستجابة ${response.statusCode}.',
        };
        setState(() => _lastTest = (false, 'فشل الاتصال: $hint'));
        setToast(context, 'فشل الاتصال (${response.statusCode})', error: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastTest = (false, 'خطأ في الإرسال: تحقّق من الإنترنت والرابط.\n$e'));
      setToast(context, 'خطأ في الإرسال', error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Text(body, style: const TextStyle(height: 1.6)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('متابعة')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final busy = _isLoading || _testing;
    return SettingsScaffold(
      title: 'إعدادات Discord',
      subtitle: 'استقبال التقارير والفواتير في قناة Discord',
      icon: Icons.discord,
      loading: !_loaded,
      children: !_loaded
          ? null
          : [
              SetHero(
                icon: Icons.discord,
                color: _discord,
                title: 'النسخ والتقارير عبر Discord',
                text: 'أنشئ Webhook في قناة على سيرفرك والصق رابطه هنا؛ يرسل التطبيق التقارير '
                    'والملخصات إلى تلك القناة بجانب تيليجرام.',
                status: SetStatusPill(_configured ? 'مرتبط' : 'غير مرتبط', ok: _configured),
              ),
              SetCard(
                title: 'رابط Webhook',
                subtitle: 'يُحفظ على هذا الجهاز فقط',
                icon: Icons.link_rounded,
                color: _discord,
                trailing: _configured
                    ? TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: kSetRed),
                        onPressed: busy ? null : _unlink,
                        icon: const Icon(Icons.link_off_rounded, size: 18),
                        label: const Text('إلغاء الربط'),
                      )
                    : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 8),
                  TextField(
                    controller: _webhookUrlController,
                    obscureText: _obscure,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'رابط الـ Webhook',
                      hintText: 'https://discord.com/api/webhooks/...',
                      prefixIcon: const Icon(Icons.webhook_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'إظهار' : 'إخفاء',
                        icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _lastTest == null
                        ? const SizedBox.shrink()
                        : Padding(
                            key: ValueKey(_lastTest),
                            padding: const EdgeInsets.only(top: 12),
                            child: SetBanner(
                              _lastTest!.$2,
                              kind: _lastTest!.$1 ? SetBannerKind.ok : SetBannerKind.error,
                            ),
                          ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50), foregroundColor: _discord),
                        onPressed: busy ? null : () => _sendTestMessage(silentSuccess: false),
                        icon: _testing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send_rounded),
                        label: const Text('رسالة تجريبية'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SetPrimaryButton(
                        label: 'حفظ واختبار',
                        icon: Icons.save_rounded,
                        color: _discord,
                        busy: _isLoading,
                        onPressed: busy ? null : _saveSettings,
                      ),
                    ),
                  ]),
                ]),
              ),
              const SetCard(
                title: 'كيف أحصل على رابط Webhook؟',
                icon: Icons.help_outline_rounded,
                color: _discord,
                child: Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: SetSteps([
                    'افتح إعدادات سيرفر Discord (Server Settings).',
                    'اذهب إلى Integrations ثم Webhooks.',
                    'اضغط New Webhook.',
                    'سمّه واختر القناة (Channel) التي ستصلها التقارير.',
                    'اضغط Copy Webhook URL والصقه في الحقل أعلاه ثم «حفظ واختبار».',
                  ], color: _discord),
                ),
              ),
            ],
    );
  }
}
