// screens/reports_screen.dart
import 'package:flutter/material.dart';
import 'product_reports_screen.dart';
import 'people_reports_screen.dart';
import 'daily_report_screen.dart';
import 'weekly_report_screen.dart';
import 'monthly_report_screen.dart';
import 'yearly_report_screen.dart';
import 'overdue_debts_screen.dart';
import 'returns_report_screen.dart';
import '../services/settings_manager.dart';
import '../models/app_settings.dart';
import '../widgets/app_side_nav.dart';
import '../accounting/screens/acc_ui.dart' show requirePermission;
import '../accounting/screens/trial_balance_screen.dart';
import '../accounting/screens/income_statement_screen.dart';
import '../accounting/screens/balance_sheet_screen.dart';
import '../erp/reports/finance_reports.dart';
import '../models/app_user.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = const Color(0xFF6C63FF);
    final Color backgroundColor = const Color(0xFFF5F7FB);

    return FutureBuilder<AppSettings>(
      future: SettingsManager.getAppSettings(),
      builder: (context, snapshot) {
        final settings = snapshot.data;
        final showSideNav = settings != null && AppSideNav.shouldShow(context, settings);

        return Scaffold(
          backgroundColor: backgroundColor,
          appBar: AppBar(
            title: const Text('التقارير', style: TextStyle(fontSize: 24)),
            centerTitle: true,
            backgroundColor: primaryColor,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: Row(
            children: [
              if (showSideNav)
                const AppSideNav(currentRoute: '/reports'),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
          children: [
            const SizedBox(height: 20),
            const Text(
              'اختر نوع التقرير',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50),
              ),
            ),
            const SizedBox(height: 30),
            
            // 📈 لوحة المؤشرات في أعلى التقارير (بدل زر مستقل في الرئيسية)
            Row(
              children: [
                Expanded(
                  child: _buildReportCard(
                    title: 'لوحة المؤشرات',
                    subtitle: 'مبيعات وأرباح اليوم والشهر، الديون، النواقص',
                    icon: Icons.dashboard_rounded,
                    color: const Color(0xFF1B6CA8),
                    onTap: () {
                      if (requirePermission(context, AppPermissions.dashboard)) {
                        Navigator.pushNamed(context, '/dashboard');
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // الصف الأول: تقارير البضاعة والأشخاص
            Row(
              children: [
                Expanded(
                  child: _buildReportCard(
                    title: 'تقارير البضاعة',
                    subtitle: 'تقارير المنتجات والمبيعات',
                    icon: Icons.inventory,
                    color: const Color(0xFF4CAF50),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProductReportsScreen(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildReportCard(
                    title: 'تقارير الأشخاص',
                    subtitle: 'تقارير العملاء والأرباح',
                    icon: Icons.people,
                    color: const Color(0xFF2196F3),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PeopleReportsScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // الصف الثاني: تقرير اليوم والأسبوع
            Row(
              children: [
                Expanded(
                  child: _buildReportCard(
                    title: 'تقرير اليوم',
                    subtitle: 'مبيعات وأرباح اليوم',
                    icon: Icons.today,
                    color: const Color(0xFFFF9800),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DailyReportScreen(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildReportCard(
                    title: 'تقرير الأسبوع',
                    subtitle: 'مبيعات وأرباح الأسبوع',
                    icon: Icons.date_range,
                    color: const Color(0xFF9C27B0),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const WeeklyReportScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // الصف الثالث: تقرير السنة
            Row(
              children: [
                Expanded(
                  child: _buildReportCard(
                    title: 'تقرير السنة',
                    subtitle: 'ملخص سنوي شامل',
                    icon: Icons.calendar_today,
                    color: const Color(0xFF3F51B5),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const YearlyReportScreen(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildReportCard(
                    title: 'تقارير شهرية',
                    subtitle: 'ملخص شهري وتفاصيل',
                    icon: Icons.calendar_month,
                    color: const Color(0xFF673AB7),
                    onTap: () => Navigator.pushNamed(context, '/inventory'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // الصف الرابع: تقارير المرتجعات (Box Match)
            Row(
              children: [
                Expanded(
                  child: _buildReportCard(
                    title: 'تقارير المرتجعات',
                    subtitle: 'Box Match - مطابقة الصندوق',
                    icon: Icons.undo,
                    color: Colors.red,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ReturnsReportScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 🏛️ القوائم المالية والتقارير المحاسبية (نُقلت من المحاسبة)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('القوائم المالية',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
            ),
            Row(
              children: [
                Expanded(child: _finCard(context, 'ميزان المراجعة', 'أرصدة كل الحسابات', Icons.balance,
                    const Color(0xFF0891B2), AppPermissions.accounting, const TrialBalanceScreen())),
                Expanded(child: _finCard(context, 'قائمة الدخل', 'الأرباح والخسائر', Icons.trending_up,
                    const Color(0xFF047857), AppPermissions.viewCostProfit, const IncomeStatementScreen())),
                Expanded(child: _finCard(context, 'الميزانية العمومية', 'الأصول والخصوم', Icons.account_balance,
                    const Color(0xFF0F3460), AppPermissions.viewCostProfit, const BalanceSheetScreen())),
              ],
            ),
            Row(
              children: [
                Expanded(child: _finCard(context, 'تقرير المبيعات التفصيلي', 'ربح كل قائمة', Icons.receipt_long,
                    const Color(0xFF0E7C61), AppPermissions.viewCostProfit, const SalesDetailReportScreen())),
                Expanded(child: _finCard(context, 'تحليل المصاريف', 'أين ذهبت الأموال؟', Icons.pie_chart,
                    const Color(0xFFB91C1C), AppPermissions.accounting, const ExpenseAnalysisScreen())),
                Expanded(child: _finCard(context, 'حركة الصندوق', 'وارد وصادر ورصيد', Icons.account_balance_wallet_outlined,
                    const Color(0xFF047857), AppPermissions.accounting, const CashMovementScreen())),
              ],
            ),
            const SizedBox(height: 16),

            // تم حذف زر الديون المتأخرة وزر تقرير الشهر بناءً على الطلب
          ],
        ),
      ),
          ),
        ],
      ),
        );
      },
    );
  }

  Widget _finCard(BuildContext context, String title, String subtitle, IconData icon, Color color,
      String permission, Widget screen) {
    return _buildReportCard(
      title: title,
      subtitle: subtitle,
      icon: icon,
      color: color,
      onTap: () {
        if (!requirePermission(context, permission)) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
      },
    );
  }

  Widget _buildReportCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.3), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.1),
                color.withOpacity(0.05),
              ],
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: color,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
