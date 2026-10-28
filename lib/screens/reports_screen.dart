// screens/reports_screen.dart
//
// 📊 مركز التقارير — مجموعات واضحة بدل شبكة أزرار متشابهة:
//   نظرة سريعة (أرقام اليوم والشهر) ← حسب الفترة ← حسب الجهة ← المرتجعات ←
//   القوائم المالية. كل الأرقام من المحرك الموحّد فتطابق ما داخل التقارير.

import 'package:flutter/material.dart';

import '../accounting/screens/acc_ui.dart' show requirePermission, accRoute;
import '../accounting/screens/balance_sheet_screen.dart';
import '../accounting/screens/income_statement_screen.dart';
import '../accounting/screens/trial_balance_screen.dart';
import '../erp/erp_common.dart' show HubSection, HubTile;
import '../erp/reports/finance_reports.dart';
import '../models/app_settings.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/reports_service.dart';
import '../services/settings_manager.dart';
import '../widgets/app_side_nav.dart';
import '../widgets/report_kit.dart';
import '../owner/owner_access.dart';
import '../owner/founders_screen.dart';
import '../radar/radar_screen.dart';
import 'custom_range_report_screen.dart';
import 'day_close_screen.dart';
import '../erp/control/control_screens.dart' show ControlHubScreen;
import 'people_reports_screen.dart';
import 'product_reports_screen.dart';
import 'returns_report_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  /// 🧭 أزرار التقارير — مصدر واحد للشاشة نفسها وللوحة الجانبية
  static List<HubSection> menu(BuildContext context, void Function(Widget) go) => [
        HubSection('نظرة عامة', subtitle: 'كل المؤشرات المهمة في صفحة واحدة', [
          HubTile('لوحة المؤشرات', Icons.dashboard_rounded, const Color(0xFF1B6CA8),
              () => Navigator.of(context).pushNamed('/dashboard'),
              subtitle: 'مبيعات وأرباح اليوم والشهر، رسم آخر 14 يوماً، الديون، الصناديق، والمواد الناقصة',
              permission: AppPermissions.dashboard),
        ]),
        // 📡 يحتاج صلاحية رؤية الكلفة والأرباح
        HubSection('رادار التاجر', subtitle: 'ما يحتاج انتباهك، والسيولة القادمة، ومن تتابع، وماذا تشتري', [
          HubTile('رادار التاجر', Icons.radar_rounded, const Color(0xFF0E7490), () => go(const RadarScreen()),
              subtitle: 'المحقق المالي (بيع تحت الكلفة، خصومات، هبوط الربح، نقص المخزون)، السيولة بعد 30/60/90 يوماً، '
                  'أولوية تحصيل الديون مع تذكير واتساب، والشراء الذكي حسب الموسم',
              permission: AppPermissions.viewCostProfit),
          HubTile('الرقابة والأدوات المالية', Icons.shield_rounded, const Color(0xFFB91C1C), () => go(const ControlHubScreen()),
              subtitle: 'عجز الدرج لكل محاسب، فواتير أُنقصت بعد طباعتها، نقطة التعادل، اقتراح الطلبيات، ربحية الفروع',
              permission: AppPermissions.viewCostProfit),
        ]),
        HubSection('حسب الفترة', subtitle: 'المبيعات والأرباح، ماذا حدث، وما دخل الصندوق فعلاً', [
          HubTile('التقارير', Icons.insights_rounded, const Color(0xFF4F46E5), () => go(const CustomRangeReportScreen()),
              subtitle: 'يوم، أسبوع، شهر، سنة، أو من تاريخ إلى تاريخ: المبيعات والأرباح، ماذا حدث، المقبوض، '
                  'تحليل التوجهات، وأثر سعر الدولار'),
          HubTile('إقفال اليوم', Icons.point_of_sale_rounded, const Color(0xFF0F766E), () => go(const DayCloseScreen()),
              subtitle: 'ما يجب أن يكون في الدرج: المقبوض والمدفوع نقداً، ومطابقته مع المعدود',
              permission: AppPermissions.repDaily),
        ]),
        HubSection('حسب الجهة', subtitle: 'ماذا بِعت ولمن', [
          HubTile('تقارير البضاعة', Icons.inventory_2_rounded, kSetGreen, () => go(const ProductReportsScreen()),
              subtitle: 'كل مادة أو قسم: الكمية والمبيعات والكلفة والربح لأي فترة',
              permission: AppPermissions.repProducts),
          HubTile('تقارير الأشخاص', Icons.people_alt_rounded, kSetBlue, () => go(const PeopleReportsScreen()),
              subtitle: 'كل عميل: السنوات ← الأشهر ← الفواتير بربح كل فاتورة',
              permission: AppPermissions.repPeople),
        ]),
        // 👷 لحساب المالك فقط
        if (OwnerAccess.enabled)
          HubSection('المؤسسون', subtitle: 'نقاط المؤسسين والفنيين ومبيعاتهم', [
            HubTile('تقارير المؤسسين', Icons.engineering_rounded, const Color(0xFFD97706), () => go(const FoundersScreen()),
                subtitle: 'رصيد النقاط، الترتيب، النقاط شهرياً، مبيعات وعملاء كل مؤسس، وصرف الجوائز',
                permission: AppPermissions.repFounders),
          ]),
        HubSection('المرتجعات', subtitle: 'ما رجع من المبيعات', [
          HubTile('المرتجعات', Icons.assignment_return_rounded, kSetRed, () => go(const ReturnsReportScreen()),
              subtitle: 'مستندات المرتجع، الراجع على الفواتير، والتخفيض بعد الحفظ',
              permission: AppPermissions.repReturns),
        ]),
        HubSection('القوائم المالية', subtitle: 'من دفتر المحاسبة (القيود)', [
          HubTile('ميزان المراجعة', Icons.balance_rounded, const Color(0xFF0891B2), () => go(const TrialBalanceScreen()),
              subtitle: 'رصيد كل حساب محاسبي (مدين ودائن) — قائمة محاسبية، لا علاقة لها بالمرتجعات',
              permission: AppPermissions.accounting),
          HubTile('قائمة الدخل', Icons.trending_up_rounded, kSetGreen, () => go(const IncomeStatementScreen()),
              subtitle: 'الإيرادات − الكلفة − المصاريف = صافي الربح', permission: AppPermissions.viewCostProfit),
          HubTile('الميزانية العمومية', Icons.account_balance_rounded, kSetNavy, () => go(const BalanceSheetScreen()),
              subtitle: 'الأصول والخصوم وحقوق الملكية', permission: AppPermissions.viewCostProfit),
          HubTile('تقرير المبيعات التفصيلي', Icons.receipt_long_rounded, const Color(0xFF0E7C61),
              () => go(const SalesDetailReportScreen()),
              subtitle: 'كل فاتورة بسطر: المدفوع والمتبقي والربح، مع التصدير', permission: AppPermissions.viewCostProfit),
          HubTile('تحليل المصاريف', Icons.pie_chart_rounded, kSetRed, () => go(const ExpenseAnalysisScreen()),
              subtitle: 'أين ذهبت الأموال؟', permission: AppPermissions.accounting),
          HubTile('حركة الصندوق', Icons.account_balance_wallet_outlined, kSetGreen, () => go(const CashMovementScreen()),
              subtitle: 'الوارد والصادر والرصيد', permission: AppPermissions.accounting),
        ]),
      ];

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  AppSettings? _settings;
  Map<String, dynamic>? _today;
  Map<String, dynamic>? _month;

  @override
  void initState() {
    super.initState();
    SettingsManager.getAppSettings().then((s) {
      if (mounted) setState(() => _settings = s);
    });
    _loadGlance();
  }

  Future<void> _loadGlance() async {
    try {
      final rs = ReportsService();
      final now = DateTime.now();
      final today = await rs.getPeriodSummary(startDate: now, endDate: now);
      final month = await rs.getPeriodSummary(startDate: DateTime(now.year, now.month, 1), endDate: now);
      if (!mounted) return;
      setState(() {
        _today = today;
        _month = month;
      });
    } catch (_) {}
  }

  bool _allowed(HubTile t) => t.permission == null || AuthService().hasPermission(t.permission!);

  void _open(Widget page) => Navigator.push(context, accRoute(page)).then((_) => _loadGlance());


  @override
  Widget build(BuildContext context) {
    final showSideNav = _settings != null && AppSideNav.shouldShow(context, _settings!);
    final profit = repCanSeeProfit();

    final content = ReportScaffold(
      title: 'التقارير',
      subtitle: 'المبيعات والأرباح والمواد والعملاء والقوائم المالية',
      icon: Icons.insights_rounded,
      actions: [
        IconButton(
          tooltip: 'تحديث الأرقام',
          onPressed: _loadGlance,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      onRefresh: _loadGlance,
      children: [
        _glance(profit),
        // 🧭 الأزرار من ReportsScreen.menu — نفس ما في اللوحة الجانبية
        // 🔐 التقارير غير المسموحة لا تظهر أصلاً (ولا قسمها إن فرغ)
        for (final g in ReportsScreen.menu(context, _open))
          if (g.tiles.any(_allowed))
          _group(g.title, g.subtitle ?? '', [
            for (final t in g.tiles.where(_allowed))
              _Hub(
                title: t.title,
                text: t.subtitle ?? '',
                icon: t.icon,
                color: t.color,
                onTap: () {
                  if (t.permission != null && !requirePermission(context, t.permission!)) return;
                  t.onTap();
                },
              ),
          ]),
      ],
    );

    if (!showSideNav) return content;
    return Material(
      color: kSetBg,
      child: Row(children: [
        const AppSideNav(currentRoute: '/reports'),
        Expanded(child: content),
      ]),
    );
  }

  Widget _glance(bool profit) {
    double n(Map<String, dynamic>? m, String k) => (m?[k] as num?)?.toDouble() ?? 0;
    final loading = _today == null;
    final auth = AuthService();
    final day = auth.hasPermission(AppPermissions.repDaily);
    final mon = auth.hasPermission(AppPermissions.repMonthly);
    if (!day && !mon) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: loading ? 0.55 : 1,
        child: KpiGrid(minTileWidth: 210, children: [
          if (day)
          KpiTile(
            label: 'مبيعات اليوم',
            value: n(_today, 'totalSales'),
            icon: Icons.today_rounded,
            color: kSetNavy,
            emphasis: true,
            hint: '${repQty(n(_today, 'invoiceCount'))} فاتورة',
            onTap: () => _open(CustomRangeReportScreen(from: DateTime.now(), to: DateTime.now())),
          ),
          if (profit && day)
            KpiTile(
              label: 'ربح اليوم',
              value: n(_today, 'netProfit'),
              icon: Icons.trending_up_rounded,
              color: kSetGreen,
              hint: n(_today, 'netSales') > 0 ? 'هامش ${repPercent(n(_today, 'profitMargin'))}' : null,
              onTap: () => _open(CustomRangeReportScreen(from: DateTime.now(), to: DateTime.now())),
            ),
          if (mon)
          KpiTile(
            label: 'مبيعات الشهر',
            value: n(_month, 'totalSales'),
            icon: Icons.calendar_month_rounded,
            color: const Color(0xFF4F46E5),
            hint: 'نقد ${repMoney(n(_month, 'cashSales'))} • آجل ${repMoney(n(_month, 'creditSales'))}',
            onTap: () => _open(const CustomRangeReportScreen()),
          ),
          if (profit && mon)
            KpiTile(
              label: 'ربح الشهر',
              value: n(_month, 'netProfit'),
              icon: Icons.savings_rounded,
              color: kRepAmber,
              hint: n(_month, 'totalReturns') > 0 ? 'بعد مرتجعات ${repMoney(n(_month, 'totalReturns'))}' : null,
              onTap: () => _open(const CustomRangeReportScreen()),
            ),
        ]),
      ),
    );
  }

  Widget _group(String title, String subtitle, List<_Hub> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: kSetText)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(subtitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: kSetMuted)),
            ),
          ]),
        ),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 980 ? 3 : (c.maxWidth >= 620 ? 2 : 1);
          final w = (c.maxWidth - (cols - 1) * 12) / cols;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final it in items) SizedBox(width: w, child: it),
          ]);
        }),
      ]),
    );
  }
}

/// بطاقة تقرير: أيقونة ملوّنة + اسم + شرح قصير (ترتفع قليلاً عند المرور).
class _Hub extends StatefulWidget {
  const _Hub({required this.title, required this.text, required this.icon, required this.color, required this.onTap});
  final String title;
  final String text;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_Hub> createState() => _HubState();
}

class _HubState extends State<_Hub> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hover ? c.withValues(alpha: 0.45) : kSetBorder),
          boxShadow: [
            BoxShadow(
              color: (_hover ? c : const Color(0xFF0F172A)).withValues(alpha: _hover ? 0.14 : 0.04),
              blurRadius: _hover ? 18 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [c, Color.alphaBlend(Colors.white24, c)],
                      begin: AlignmentDirectional.topStart,
                      end: AlignmentDirectional.bottomEnd,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(widget.icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.title,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: kSetText)),
                    const SizedBox(height: 3),
                    Text(widget.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.3, color: kSetMuted, height: 1.45)),
                  ]),
                ),
                const SizedBox(width: 8),
                AnimatedSlide(
                  duration: const Duration(milliseconds: 160),
                  offset: Offset(_hover ? -0.2 : 0, 0),
                  child: Icon(Icons.arrow_forward_ios_rounded, size: 15, color: _hover ? c : const Color(0xFFB8C2CF)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
