// lib/owner/wa_auto/wa_auto_entry_card.dart
//
// 💬 بطاقة الدخول إلى «رسائل واتساب للزبائن»: للمدير كلها، وللموظف ما تسمح به صلاحياته
// (wa_access.dart) — مثلاً «إرسال الآن» وحده.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart' show accRoute;
import '../../wa_messages/wa_auto_docs_screen.dart';
import '../../wa_messages/wa_messages_hub_screen.dart';
import '../../wa_messages/wa_rules_screen.dart';
import '../../wa_messages/wa_send_screen.dart';
import '../../widgets/settings_kit.dart';
import '../../wa_messages/wa_access.dart';

class WaAutoEntryCard extends StatelessWidget {
  const WaAutoEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    if (!WaAccess.any) return const SizedBox.shrink();
    const green = Color(0xFF047857);
    return SetCard(
      title: 'رسائل واتساب للزبائن',
      icon: Icons.chat_rounded,
      color: green,
      child: Column(children: [
        if (WaAccess.full)
        SetActionRow(
          icon: Icons.dashboard_customize_rounded,
          title: 'كل الإعدادات',
          subtitle: 'الحالة، القواعد، الإرسال، السجل، طريقة الإرسال، الخادم',
          color: green,
          onTap: () => Navigator.push(context, accRoute(const WaMessagesHubScreen())),
        ),
        if (WaAccess.sendNow)
        SetActionRow(
          icon: Icons.send_rounded,
          title: 'إرسال الآن',
          subtitle: 'مطالبة لمن تختار، مع العنوان وكشف الحساب',
          color: green,
          onTap: () => Navigator.push(context, accRoute(const WaSendNowScreen())),
        ),
        if (WaAccess.rules)
        SetActionRow(
          icon: Icons.rule_rounded,
          title: 'القواعد التلقائية',
          subtitle: 'مطالبات ترسل وحدها حسب التأخر واليوم والساعة',
          color: green,
          onTap: () => Navigator.push(context, accRoute(const WaRulesScreen())),
        ),
        if (WaAccess.autoDocs)
        SetActionRow(
          icon: Icons.auto_mode_rounded,
          title: 'الإرسال التلقائي للعملاء',
          subtitle: 'عملاء تختارهم: الفاتورة (نقد/دين) والسندات تصلهم لحظة الحفظ، بلا ضغطة',
          color: green,
          onTap: () => Navigator.push(context, accRoute(const WaAutoDocsScreen())),
        ),
      ]),
    );
  }
}
