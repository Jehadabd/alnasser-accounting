// lib/widgets/user_menu_button.dart
//
// 👤 زر المستخدم الحالي في الشريط العلوي: الاسم والدور، تغيير كلمة السر،
// الموظفون والصلاحيات (للمدير)، وتبديل المستخدم / تسجيل الخروج.

import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/auth_service.dart';

class UserMenuButton extends StatelessWidget {
  const UserMenuButton({super.key, this.color = Colors.white});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    if (user == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'المستخدم',
      offset: const Offset(0, 48),
      onSelected: (v) => _onSelected(context, v),
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Text(_initial(user.shownName))),
            title: Text(user.shownName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
            subtitle: Text(user.roleLabel),
          ),
        ),
        const PopupMenuDivider(),
        if (user.id != null)
          const PopupMenuItem(value: 'password', child: ListTile(leading: Icon(Icons.password), title: Text('تغيير كلمة السر'))),
        if (AuthService().hasPermission(AppPermissions.manageUsers) && user.id != null)
          const PopupMenuItem(
              value: 'users', child: ListTile(leading: Icon(Icons.manage_accounts), title: Text('الموظفون والصلاحيات'))),
        const PopupMenuItem(
            value: 'logout',
            child: ListTile(leading: Icon(Icons.logout, color: Colors.red), title: Text('تبديل المستخدم / خروج'))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: color.withOpacity(0.2),
            child: Text(_initial(user.shownName), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 6),
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user.shownName, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
            Text(user.roleLabel, style: TextStyle(color: color.withOpacity(0.75), fontSize: 11)),
          ]),
          Icon(Icons.arrow_drop_down, color: color),
        ]),
      ),
    );
  }

  Future<void> _onSelected(BuildContext context, String v) async {
    switch (v) {
      case 'users':
        Navigator.of(context).pushNamed('/user_management');
        break;
      case 'password':
        await showChangeOwnPasswordDialog(context);
        break;
      case 'logout':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تبديل المستخدم'),
            content: const Text('سيُغلق حسابك وتظهر شاشة الدخول ليدخل مستخدم آخر.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('خروج')),
            ],
          ),
        );
        if (ok != true) return;
        await AuthService().logout();
        if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
        break;
    }
  }
}

String _initial(String s) => s.trim().isEmpty ? '?' : s.trim().characters.first;

/// تغيير كلمة سر المستخدم الحالي (يطلب الكلمة الحالية أولاً)
Future<void> showChangeOwnPasswordDialog(BuildContext context) async {
  final auth = AuthService();
  final user = auth.currentUser;
  if (user?.id == null) return;
  final cur = TextEditingController(), np = TextEditingController(), np2 = TextEditingController();
  String? err;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('تغيير كلمة السر'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: cur, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة السر الحالية')),
            const SizedBox(height: 10),
            TextField(controller: np, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة السر الجديدة')),
            const SizedBox(height: 10),
            TextField(
              controller: np2,
              obscureText: true,
              decoration: InputDecoration(labelText: 'تأكيد كلمة السر الجديدة', errorText: err),
            ),
            if (user!.isAdmin)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'ملاحظة: هذه كلمة سر الدخول للبرنامج على هذا الجهاز فقط، ولا تغيّر كلمة سر الترخيص.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              if (np.text.isEmpty || np.text != np2.text) {
                setD(() => err = 'الكلمتان الجديدتان غير متطابقتين');
                return;
              }
              if (!await auth.checkPassword(user.id!, cur.text)) {
                setD(() => err = 'كلمة السر الحالية غير صحيحة');
                return;
              }
              await auth.setPassword(user.id!, np.text);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم تغيير كلمة السر'), backgroundColor: Colors.green),
              );
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
}
