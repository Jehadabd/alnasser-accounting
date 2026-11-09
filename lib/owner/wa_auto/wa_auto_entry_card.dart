// lib/owner/wa_auto/wa_auto_entry_card.dart
//
// 💬 بطاقة الدخول إلى تذكير الديون عبر واتساب وخادمه — للمالك ولأصحاب اشتراك المزامنة
// (مدير البرنامج). لا تظهر لغيرهم إطلاقاً.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart' show accRoute;
import '../../widgets/settings_kit.dart';
import 'wa_auto_reminder.dart';
import 'wa_auto_screen.dart';
import 'wa_server_screen.dart';

class WaAutoEntryCard extends StatelessWidget {
  const WaAutoEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    if (!WaAutoReminder.allowed) return const SizedBox.shrink();
    return SetCard(
      title: 'تذكير الديون عبر واتساب',
      icon: Icons.chat_rounded,
      color: const Color(0xFF047857),
      child: Column(children: [
        SetActionRow(
          icon: Icons.send_rounded,
          title: 'رسالة لكل مدين باسمه ومبلغه',
          subtitle: 'تفعيل، شرط التأخر، نص الرسالة، يوم الإرسال، الحد اليومي، وسجل الإرسال',
          color: const Color(0xFF047857),
          onTap: () => Navigator.push(context, accRoute(const WaAutoScreen())),
        ),
        SetActionRow(
          icon: Icons.dns_rounded,
          title: 'خادم واتساب',
          subtitle: 'هذه الحاسبة، Oracle Cloud، Render، أو Docker — مع شرح كامل خطوة بخطوة',
          color: const Color(0xFF047857),
          onTap: () => Navigator.push(context, accRoute(const WaServerScreen())),
        ),
      ]),
    );
  }
}
