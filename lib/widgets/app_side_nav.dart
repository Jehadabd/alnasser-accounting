import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../services/settings_manager.dart';
import '../screens/inventory_menu_screen.dart';

/// 🧭 شريط التنقل الجانبي التكيفي (Adaptive Side Navigation Rail)
/// يظهر على الشاشات الكبيرة (تابلت / ديسكتوب) تلقائياً، أو عندما يُفعّله المستخدم من الإعدادات.
class AppSideNav extends StatelessWidget {
  final String currentRoute;

  const AppSideNav({
    super.key,
    required this.currentRoute,
  });

  /// التحقق مما إذا كان يجب عرض شريط التنقل بناءً على حجم الشاشة والإعدادات
  static bool shouldShow(BuildContext context, AppSettings settings) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTabletOrDesktop = screenWidth >= 600;
    return isTabletOrDesktop || settings.showSideNav;
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _NavItem(
        route: '/pos',
        title: 'الكاشير',
        icon: Icons.point_of_sale,
        color: const Color(0xFFFF5722),
      ),
      _NavItem(
        route: '/debt_register',
        title: 'سجل الديون',
        icon: Icons.book,
        color: const Color(0xFF4A90E2),
      ),
      _NavItem(
        route: '/inventory_menu',
        title: 'المخزون',
        icon: Icons.inventory_2,
        color: const Color(0xFF4CAF50),
      ),
      _NavItem(
        route: '/create_invoice',
        title: 'إنشاء قائمة',
        icon: Icons.list_alt,
        color: const Color(0xFF2196F3),
      ),
      _NavItem(
        route: '/edit_invoices',
        title: 'تعديل القوائم',
        icon: Icons.edit_note,
        color: const Color(0xFF8D6E63),
      ),
      _NavItem(
        route: '/suppliers',
        title: 'الموردون',
        icon: Icons.local_shipping,
        color: const Color(0xFF9C27B0),
      ),
      _NavItem(
        route: '/reports',
        title: 'التقارير',
        icon: Icons.bar_chart,
        color: const Color(0xFFFF9800),
      ),
      _NavItem(
        route: '/general_settings',
        title: 'الإعدادات',
        icon: Icons.settings,
        color: const Color(0xFF607D8B),
      ),
    ];

    return Container(
      width: 72,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1E2E), Color(0xFF2D2D44)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
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
                    color: Colors.white.withOpacity(0.1),
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
                          if (item.route == '/inventory_menu') {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (context) => const InventoryMenuScreen()),
                            );
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
                                ? item.color.withOpacity(0.25)
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

  _NavItem({
    required this.route,
    required this.title,
    required this.icon,
    required this.color,
  });
}
