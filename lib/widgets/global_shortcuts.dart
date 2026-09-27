// lib/widgets/global_shortcuts.dart
//
// ⌨️ اختصارات لوحة المفاتيح على مستوى البرنامج كله:
//   F1 الكاشير • F2 إنشاء قائمة • F3 سجل الديون • F4 المحاسبة
//   F6 بطاقات المواد • F7 سند مصروف • F8 الفروع والمخازن
//
// كل اختصار يحترم الصلاحيات: من لا يملك الصلاحية لا ينتقل.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../accounting/screens/vouchers_screen.dart';
import '../accounting/vouchers_service.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';

class GlobalShortcuts extends StatelessWidget {
  const GlobalShortcuts({super.key, required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  void _go(String route, String permission) {
    if (!AuthService().hasPermission(permission)) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f1): () => _go('/pos', AppPermissions.posAccess),
        const SingleActivator(LogicalKeyboardKey.f2): () => _go('/create_invoice', AppPermissions.createInvoice),
        const SingleActivator(LogicalKeyboardKey.f3): () => _go('/debt_register', AppPermissions.debtRegister),
        const SingleActivator(LogicalKeyboardKey.f4): () => _go('/accounting', AppPermissions.accounting),
        const SingleActivator(LogicalKeyboardKey.f6): () => _go('/item_cards', AppPermissions.itemCard),
        const SingleActivator(LogicalKeyboardKey.f7): () {
          if (!AuthService().hasPermission(AppPermissions.accountingPost)) return;
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => const VoucherFormScreen(type: VoucherType.expense)),
          );
        },
        const SingleActivator(LogicalKeyboardKey.f8): () => _go('/branches', AppPermissions.manageBranches),
      },
      child: child,
    );
  }
}
