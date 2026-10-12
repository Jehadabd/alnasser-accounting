// lib/widgets/stay_logged_in_tile.dart
//
// ⚙️ «البقاء مسجلاً للدخول على هذا الجهاز» — إعداد لكل جهاز.
// مفعّل: يبقى المستخدم داخلاً بعد إغلاق البرنامج أو إطفاء الحاسبة، حتى يضغط
// «تبديل المستخدم / خروج» بنفسه. مطفأ: تُطلب كلمة السر في كل فتح.

import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class StayLoggedInTile extends StatefulWidget {
  const StayLoggedInTile({super.key});

  @override
  State<StayLoggedInTile> createState() => _StayLoggedInTileState();
}

class _StayLoggedInTileState extends State<StayLoggedInTile> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    AuthService().stayLoggedIn().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.login_rounded, color: Color(0xFF0F3460)),
      title: const Text('البقاء مسجلاً للدخول على هذا الجهاز'),
      subtitle: const Text(
        'لا تُطلب كلمة السر عند فتح البرنامج أو بعد إطفاء الحاسبة، حتى تضغط «تبديل المستخدم» بنفسك. '
        'أطفئه على جهاز يستعمله أكثر من شخص.',
      ),
      value: _on ?? true,
      onChanged: _on == null
          ? null
          : (v) async {
              setState(() => _on = v);
              await AuthService().setStayLoggedIn(v);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(v
                    ? 'سيبقى هذا الجهاز مسجلاً للدخول حتى تضغط «تبديل المستخدم».'
                    : 'ستُطلب كلمة السر في كل فتح للبرنامج على هذا الجهاز.'),
              ));
            },
    );
  }
}
