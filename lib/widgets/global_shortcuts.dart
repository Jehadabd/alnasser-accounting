// lib/widgets/global_shortcuts.dart
//
// ⌨️ اختصارات لوحة المفاتيح على مستوى البرنامج كله:
//   F1 الكاشير • F2 إنشاء قائمة • F3 سجل الديون • F4 المحاسبة • F5 تعديل القوائم
//   F6 إدخال بضاعة • F7 سند مصروف • F8 الموردون • F9 التحصيل والتقارير
//   Ctrl+K بحث شامل • Ctrl+Shift+D لوحة المؤشرات • Ctrl+Shift+S المبيعات • Ctrl+Shift+I المخزون
//
// كل اختصار يحترم الصلاحيات: من لا يملك الصلاحية لا ينتقل.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../accounting/screens/vouchers_screen.dart';
import '../accounting/vouchers_service.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import 'global_search.dart';

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
        const SingleActivator(LogicalKeyboardKey.f5): () => _go('/edit_invoices', AppPermissions.editInvoices),
        const SingleActivator(LogicalKeyboardKey.f6): () => _go('/product_entry', AppPermissions.productEntry),
        const SingleActivator(LogicalKeyboardKey.f7): () {
          if (!AuthService().hasPermission(AppPermissions.accountingPost)) return;
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => const VoucherFormScreen(type: VoucherType.expense)),
          );
        },
        const SingleActivator(LogicalKeyboardKey.f8): () => _go('/suppliers', AppPermissions.suppliers),
        const SingleActivator(LogicalKeyboardKey.f9): () => _go('/debts_hub', AppPermissions.collection),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          if (!AuthService().isLoggedIn) return; // لا بحث قبل تسجيل الدخول
          final ctx = navigatorKey.currentContext;
          if (ctx != null) showGlobalSearch(ctx);
        },
        const SingleActivator(LogicalKeyboardKey.keyD, control: true, shift: true): () =>
            _go('/dashboard', AppPermissions.dashboard),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): () =>
            _go('/sales_hub', AppPermissions.salesDocs),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true, shift: true): () =>
            _go('/inventory_hub', AppPermissions.itemCard),
      },
      child: child,
    );
  }
}
