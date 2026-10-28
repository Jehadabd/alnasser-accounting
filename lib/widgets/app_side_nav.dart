import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/license_service.dart';
import 'home_destinations.dart';

/// 🧭 شريط التنقل الجانبي التكيفي (Adaptive Side Navigation Rail)
/// يظهر على الشاشات الكبيرة (تابلت / ديسكتوب) تلقائياً، أو عندما يُفعّله المستخدم من الإعدادات.
class AppSideNav extends StatelessWidget {
  final String currentRoute;

  const AppSideNav({
    super.key,
    required this.currentRoute,
  });

  /// 🧭 اللوحة صارت عامة لكل الشاشات (widgets/global_side_nav.dart، تُوضع في
  /// main.dart حول الملاح). هذه النسخة داخل كل شاشة أُطفئت كي لا تظهر مرتين.
  static bool shouldShow(BuildContext context, AppSettings settings) => false;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  // النسخة القديمة (لم تعد تُستعمل)
  // ignore: unused_element
  Widget _legacyBuild(BuildContext context) {
    final license = LicenseService().getStoredLicense();
    final bool isDebtsOnly = license?.isDebtsOnly ?? false;

    // نفس أزرار الشاشة الرئيسية وبنفس الترتيب (6 يومية + 5 أقسام)
    // الألوان والأيقونات من HomeDests — نفس ما في الشاشة الرئيسية
    _NavItem item(HomeDest d, {String? permission, bool fullOnly = false}) => _NavItem(
        route: d.route!, title: d.title, icon: d.icon, color: d.color, permission: permission, isFullAppOnly: fullOnly);
    final allItems = [
      item(HomeDests.pos, permission: AppPermissions.posAccess, fullOnly: true),
      item(HomeDests.createInvoice, permission: AppPermissions.createInvoice, fullOnly: true),
      item(HomeDests.debtRegister, permission: AppPermissions.debtRegister),
      item(HomeDests.editInvoices, permission: AppPermissions.editInvoices, fullOnly: true),
      item(HomeDests.productEntry, permission: AppPermissions.productEntry, fullOnly: true),
      item(HomeDests.suppliers, permission: AppPermissions.suppliers, fullOnly: true),
      item(HomeDests.sales, permission: AppPermissions.salesDocs, fullOnly: true),
      item(HomeDests.inventory, fullOnly: true),
      item(HomeDests.accounting, permission: AppPermissions.accounting, fullOnly: true),
      item(HomeDests.reports, permission: AppPermissions.reports),
      item(HomeDests.settings, permission: AppPermissions.settings),
    ];

    // 👤 الموظف يرى فقط ما تسمح به صلاحياته
    final auth = AuthService();
    final items = allItems
        .where((item) => !(isDebtsOnly && item.isFullAppOnly))
        .where((item) => item.permission == null || auth.hasPermission(item.permission!))
        .toList();

    return Container(
      width: 72,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF020F2B), Color(0xFF0F3460)], // نفس كحلي الرؤوس
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Header / Home icon
            Tooltip(
              message: 'الرئيسية',
              child: InkWell(
                onTap: () {
                  if (currentRoute != '/' && currentRoute != '/main') {
                    Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.home_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.white24, height: 1, indent: 12, endIndent: 12),
            const SizedBox(height: 8),

            // Navigation Items List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isSelected = currentRoute == item.route;

                  return Tooltip(
                    message: item.title,
                    preferBelow: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      child: InkWell(
                        onTap: () {
                          if (isSelected) return;
                          if (item.permission != null && !AuthService().hasPermission(item.permission!)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('ليس لديك صلاحية للوصول إلى هذه الميزة')),
                            );
                            return;
                          }
                          // من الرئيسية: فتح فوقها (حتى يعمل زر الرجوع)؛ من غيرها: استبدال الشاشة الحالية
                          if (currentRoute == '/' || currentRoute == '/main') {
                            Navigator.of(context).pushNamed(item.route);
                          } else {
                            Navigator.of(context).pushReplacementNamed(item.route);
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? item.color.withValues(alpha: 0.25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? item.color : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item.icon,
                                color: isSelected ? item.color : Colors.white70,
                                size: 22,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.title,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white60,
                                  fontSize: 9,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final String route;
  final String title;
  final IconData icon;
  final Color color;
  final bool isFullAppOnly;
  final String? permission;

  const _NavItem({
    required this.route,
    required this.title,
    required this.icon,
    required this.color,
    this.isFullAppOnly = false,
    this.permission,
  });
}
