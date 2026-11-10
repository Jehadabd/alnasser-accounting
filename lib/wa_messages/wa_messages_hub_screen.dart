// lib/wa_messages/wa_messages_hub_screen.dart
//
// 💬 «رسائل واتساب للزبائن» — المدخل الواحد (الإعدادات، والتحصيل والتقارير):
// الحالة، الإرسال الجاري، وروابط: إرسال الآن، القواعد التلقائية، السجل، طريقة الإرسال
// والأمان، خادم واتساب، ومواعيد المطالبة.

import 'package:flutter/material.dart';

import '../owner/wa_auto/wa_auto_reminder.dart';
import '../owner/wa_auto/wa_auto_screen.dart';
import '../owner/wa_auto/wa_server_client.dart';
import '../owner/wa_auto/wa_server_screen.dart';
import '../owner/wa_auto/wa_usage_banner.dart';
import '../screens/debt_reminders_screen.dart';
import '../widgets/settings_kit.dart';
import 'wa_auto_docs_screen.dart';
import 'wa_message_log.dart';
import 'wa_phone_book_screen.dart';
import 'wa_rules.dart';
import 'wa_rules_screen.dart';
import 'wa_send_screen.dart';
import 'wa_widgets.dart';

class WaMessagesHubScreen extends StatefulWidget {
  const WaMessagesHubScreen({super.key});
  @override
  State<WaMessagesHubScreen> createState() => _WaMessagesHubScreenState();
}

class _WaMessagesHubScreenState extends State<WaMessagesHubScreen> {
  WaAutoSettings? _s;
  List<WaRule> _rules = const [];
  int _today = 0;
  String? _server; // حالة الخادم نصاً

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await WaAutoReminder.load();
    final rules = await WaRules.load();
    final today = await WaMessageLog.sentToday();
    if (!mounted) return;
    setState(() {
      _s = s;
      _rules = rules;
      _today = today;
    });
    if (s.viaServer) {
      String t;
      try {
        final st = await WaServerClient.status();
        t = !st.linked ? 'الخادم يعمل — غير مربوط برقم' : (st.connected ? 'الخادم جاهز • ${st.me}' : 'الخادم يعيد الاتصال بواتساب');
      } on WaServerException catch (e) {
        t = 'الخادم: ${e.message}';
      } catch (_) {
        t = 'الخادم لا يرد';
      }
      if (mounted) setState(() => _server = t);
    }
  }

  Future<void> _go(Widget w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!WaAutoReminder.allowed) {
      return const SettingsScaffold(
        title: 'رسائل واتساب للزبائن',
        icon: Icons.chat_rounded,
        children: [SetBanner('هذه الإعدادات لمدير البرنامج.', kind: SetBannerKind.warn)],
      );
    }
    final s = _s;
    if (s == null) return const SettingsScaffold(title: 'رسائل واتساب للزبائن', icon: Icons.chat_rounded, loading: true);
    final on = s.enabled && s.riskAccepted;
    final active = _rules.where((r) => r.enabled).length;
    return SettingsScaffold(
      title: 'رسائل واتساب للزبائن',
      icon: Icons.chat_rounded,
      subtitle: 'مطالبات تلقائية بقواعد، وإرسال فوري لمن تختار',
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      children: [
        const WaUsageBanner(),
        SetHero(
          icon: on ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
          color: on ? kWaGreen : const Color(0xFFB45309),
          title: on ? 'الإرسال الآلي مفعّل' : 'الإرسال الآلي مطفأ',
          text: [
            s.viaServer ? 'الطريقة: الخادم' : 'الطريقة: WhatsApp Desktop',
            if (_server != null) _server!,
            '$active قاعدة مفعّلة',
            'أُرسل اليوم $_today من ${s.maxPerDay}',
          ].join(' • '),
        ),
        const SizedBox(height: 12),
        const WaOutboxCard(),
        SetCard(
          title: 'الإرسال',
          icon: Icons.send_rounded,
          color: kWaGreen,
          child: Column(children: [
            SetActionRow(
              icon: Icons.send_rounded,
              title: 'إرسال الآن',
              subtitle: 'اختر عملاء (أو المتأخرين) والرسالة والكشف، ويبدأ فوراً',
              color: kWaGreen,
              onTap: () => _go(const WaSendNowScreen()),
            ),
            SetActionRow(
              icon: Icons.rule_rounded,
              title: 'القواعد التلقائية ($active مفعّلة)',
              subtitle: 'مثل: من لم يسدّد منذ 3 أشهر ⇐ مطالبة وحدها، يوم 5، مرة حتى يسدّد',
              color: kWaGreen,
              onTap: () => _go(const WaRulesScreen()),
            ),
            SetActionRow(
              icon: Icons.event_repeat_rounded,
              title: 'مواعيد المطالبة بالسداد',
              subtitle: 'أشخاص وأيام تختارها — ويمكن ربطها بقاعدة «مواعيد المطالبة اليوم»',
              color: const Color(0xFF4F46E5),
              onTap: () => _go(const DebtRemindersScreen()),
            ),
            SetActionRow(
              icon: Icons.history_rounded,
              title: 'سجل الرسائل',
              subtitle: 'ما أُرسل، وما فشل ولماذا، ومن تُخطّي لأنه سدّد',
              onTap: () => _go(const WaLogScreen()),
            ),
            SetActionRow(
              icon: Icons.auto_mode_rounded,
              title: 'الإرسال التلقائي للعملاء',
              subtitle: 'عملاء تختارهم: تصلهم الفاتورة أو وصل القبض لحظة الحفظ، بلا ضغطة',
              onTap: () => _go(const WaAutoDocsScreen()),
            ),
            SetActionRow(
              icon: Icons.verified_user_rounded,
              title: 'أرقام واتساب المؤكَّدة',
              subtitle: 'من تُرسل لهم الفواتير والكشوفات مباشرة بلا سؤال — احذف رقماً ليُسأل عنه مجدداً',
              onTap: () => _go(const WaPhoneBookScreen()),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: 'الإعداد',
          icon: Icons.settings_rounded,
          child: Column(children: [
            SetActionRow(
              icon: Icons.tune_rounded,
              title: 'طريقة الإرسال والأمان',
              subtitle: 'التفعيل، الخادم أو WhatsApp Desktop، الفواصل، الحد اليومي، النص الافتراضي، عنوان المحل',
              onTap: () => _go(const WaAutoScreen()),
            ),
            SetActionRow(
              icon: Icons.dns_rounded,
              title: 'خادم واتساب',
              subtitle: 'تشغيله على هذه الحاسبة بضغطة، وربط رقم المحل',
              onTap: () => _go(const WaServerScreen()),
            ),
          ]),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
