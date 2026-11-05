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

import '../services/auth_service.dart';
import '../services/settings_manager.dart';
import '../widgets/settings_kit.dart';
import '../widgets/setup_guide.dart'; // 🧭 الشرح خطوة بخطوة

class DiscordSettingsScreen extends StatefulWidget {
  const DiscordSettingsScreen({super.key, this.embedded = false});

  /// داخل «النسخ الاحتياطي والمزامنة» تحت مفتاح ديسكورد (بلا شريط علوي).
  final bool embedded;

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

  List<GuideStep> _steps() {
    final owner = (AuthService().currentUser?.username ?? '').trim();
    return [
      const GuideStep(
        'تحتاج حساباً في Discord (مجاني). إن لم يكن عندك أنشئه من الرابط الأول، ثم افتح Discord في المتصفح أو ثبّت تطبيقه.',
        links: [
          GuideLink('إنشاء حساب Discord', 'https://discord.com/register', icon: Icons.person_add_alt_1_rounded),
          GuideLink('Discord في المتصفح', 'https://discord.com/app', icon: Icons.language_rounded),
          GuideLink('تحميل Discord', 'https://discord.com/download', icon: Icons.download_rounded),
        ],
      ),
      GuideStep(
        'أنشئ «سيرفراً» خاصاً بك (إن لم يكن عندك): اضغط زر «+» في العمود الأيسر ← «Create My Own / أنشئ الخاص بي» ← '
        '«For me and my friends» ← اكتب اسماً ← «Create / إنشاء». مثلاً:',
        copies: [owner.isEmpty ? 'نسخ المتجر' : 'متجر $owner'],
      ),
      const GuideStep(
        'افتح إعدادات السيرفر: اضغط اسم السيرفر في أعلى العمود ← «Server Settings / إعدادات الخادم».',
        note: 'يجب أن تكون صاحب السيرفر أو لديك صلاحية «Manage Webhooks» — صاحب السيرفر لديه كل الصلاحيات.',
      ),
      const GuideStep('من القائمة اختر «Integrations / عمليات الدمج» ← «Webhooks» ← «New Webhook / ويب هوك جديد» '
          '(أو «Create Webhook»).'),
      const GuideStep(
        'اضغط على الـ Webhook الجديد: غيّر اسمه إن أردت (مثلاً «نسخ المتجر»)، واختر من «Channel / القناة» '
        'القناة التي تصلها النسخ (مثل #general)، ثم «Save Changes / حفظ التغييرات» إن ظهر.',
      ),
      const GuideStep(
        'اضغط «Copy Webhook URL / نسخ رابط الويب هوك»، ثم ارجع هنا والصق الرابط في الخانة أعلاه واضغط «حفظ واختبار». '
        'تصلك رسالة تجريبية في القناة.',
        links: [GuideLink('شرح Discord الرسمي', 'https://support.discord.com/hc/articles/228383668', icon: Icons.help_outline_rounded)],
        note: 'الرابط مثل كلمة السر: من يملكه يستطيع الكتابة في قناتك. لا ترسله لأحد.',
        warn: true,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return SetEmbedded(loading: !_loaded, children: _loaded ? _content() : const []);
    return SettingsScaffold(
      title: 'إعدادات Discord',
      subtitle: 'استقبال التقارير والفواتير في قناة Discord',
      icon: Icons.discord,
      loading: !_loaded,
      children: !_loaded ? null : _content(),
    );
  }

  List<Widget> _content() {
    final busy = _isLoading || _testing;
    return [
              if (widget.embedded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SetStatusPill(_configured ? 'مرتبط' : 'غير مرتبط', ok: _configured),
                  ),
                )
              else
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
              SetCard(
                title: 'كيف أحصل على رابط Webhook؟',
                subtitle: 'شرح خطوة بخطوة مع الروابط',
                icon: Icons.help_outline_rounded,
                color: _discord,
                child: GuideToggle(
                  label: 'اعرض الخطوات',
                  color: _discord,
                  initiallyOpen: !_configured,
                  child: SetupGuide(steps: _steps(), color: _discord),
                ),
              ),
    ];
  }
}
