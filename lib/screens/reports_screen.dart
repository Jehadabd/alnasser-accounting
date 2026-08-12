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

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = const Color(0xFF6C63FF);
    final Color backgroundColor = const Color(0xFFF5F7FB);

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
      body: SingleChildScrollView(
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
            
            // تم حذف زر الديون المتأخرة وزر تقرير الشهر بناءً على الطلب
            const SizedBox(height: 20),
          ],
        ),
      ),
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
