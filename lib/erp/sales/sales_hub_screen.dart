// lib/erp/sales/sales_hub_screen.dart
//
// 🛒 مركز المبيعات والمستندات.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../models/app_user.dart';
import '../../screens/day_close_screen.dart';
import '../../screens/custom_range_report_screen.dart';
import '../../screens/returns_report_screen.dart';
import '../../services/reports_service.dart';
import '../debts/debt_reports_screen.dart';
import '../device_defaults.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../pos/price_checker_screen.dart';
import '../warranty/warranty_screens.dart'; // 🛠️ الضمان والصيانة
import 'invoice_extras.dart';
import 'quotes_orders_screen.dart';
import 'sales_return_screen.dart';

class SalesHubScreen extends StatefulWidget {
  const SalesHubScreen({super.key});

  /// 🧭 أزرار المركز — مصدر واحد للشاشة نفسها وللوحة الجانبية
  static List<HubSection> menu(BuildContext context, void Function(Widget) go) => [
      HubSection('المستندات', [
        HubTile('مرتجع مبيعات', Icons.assignment_return, ErpColors.orange, () => go(const SalesReturnScreen()),
            subtitle: 'نقداً أو من حساب العميل', permission: AppPermissions.salesDocs),
        HubTile('عروض الأسعار', Icons.request_quote_outlined, ErpColors.cyan, () => go(const QuotationsScreen()),
            subtitle: 'طباعة وتحويل إلى قائمة', permission: AppPermissions.salesDocs),
        HubTile('طلبات المبيعات', Icons.assignment_outlined, ErpColors.blue, () => go(const OrdersScreen()),
            subtitle: 'حجز كميات وتسليم جزئي', permission: AppPermissions.salesDocs),
      ]),
      HubSection('السجلات', [
        HubTile('سجل المرتجعات', Icons.history, ErpColors.muted, () => go(const SalesReturnsListScreen()),
            subtitle: 'طباعة وإلغاء', permission: AppPermissions.salesDocs),
        HubTile('الضمان والصيانة', Icons.build_circle_rounded, ErpColors.purple, () => go(const WarrantyHubScreen()),
            subtitle: 'قطع العملاء المعطوبة حتى تعود إليهم', permission: AppPermissions.salesDocs),
        HubTile('الفواتير غير المسددة', Icons.receipt_outlined, ErpColors.red, () => go(const OpenInvoicesScreen()),
            subtitle: 'الفواتير الآجلة وما بقي منها', permission: AppPermissions.debtReports),
      ]),
      HubSection('أدوات البيع', [
        HubTile('المندوبون والعمولات', Icons.badge, ErpColors.gold, () => go(const SellersScreen()),
            permission: AppPermissions.salesDocs),
        HubTile('قارئ الأسعار', Icons.qr_code_scanner_rounded, ErpColors.cyan, () => go(const PriceCheckerScreen()),
            subtitle: 'شاشة للزبائن'),
        HubTile('صندوق ومخزن هذا الجهاز', Icons.devices, ErpColors.navy, () => SalesHubScreen.deviceDefaults(context),
            subtitle: 'لكل كاشير صندوقه', permission: AppPermissions.accountingPost),
        HubTile('إقفال اليوم', Icons.point_of_sale_rounded, ErpColors.green, () => go(const DayCloseScreen()),
            subtitle: 'المتوقع في الدرج ومطابقته مع المعدود', permission: AppPermissions.repDaily),
      ]),
      ];

  static Future<void> deviceDefaults(BuildContext context) async {
    int? box = await DeviceDefaults.cashBoxId();
    int? wh = await DeviceDefaults.warehouseId();
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('صندوق ومخزن هذا الجهاز'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('كل فاتورة بيع تُحفظ من هذا الجهاز (القائمة والكاشير) تُسجَّل على هذا الصندوق '
                  'وتُخصم من هذا المخزن.'),
              const SizedBox(height: 12),
              CashBoxDropdown(value: box, width: 400, onChanged: (b) => set(() => box = b?.id)),
              const SizedBox(height: 10),
              WarehouseDropdown(value: wh, width: 400, onChanged: (w) => set(() => wh = w?.id)),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await DeviceDefaults.set();
                if (ctx.mounted) Navigator.pop(ctx, false);
              },
              child: const Text('بلا (الافتراضي)'),
            ),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await DeviceDefaults.set(cashBoxId: box, warehouseId: wh);
      if (context.mounted) showOk(context, 'حُفظ صندوق ومخزن هذا الجهاز');
    }
  }

  @override
  State<SalesHubScreen> createState() => _SalesHubScreenState();
}

class _SalesHubScreenState extends State<SalesHubScreen> {
  double _today = 0;
  int _todayCount = 0;
  int _openQuotes = 0;
  int _openOrders = 0;
  double _monthReturns = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await erpDb();
      final now = DateTime.now();
      // نفس أرقام التقارير (المحرك الموحّد): الفاتورة المحفوظة القديمة بلا حالة تُحسب أيضاً
      final rs = ReportsService();
      final today = await rs.getPeriodSummary(startDate: now, endDate: now);
      final month = await rs.getPeriodSummary(startDate: DateTime(now.year, now.month, 1), endDate: now);
      final q = await db.rawQuery("SELECT COUNT(*) AS n FROM quotations WHERE status = 'open'");
      final o = await db.rawQuery("SELECT COUNT(*) AS n FROM orders WHERE status IN ('open', 'partial')");
      if (!mounted) return;
      setState(() {
        _today = d0(today['totalSales']);
        _todayCount = ((today['invoiceCount'] as num?) ?? 0).toInt();
        _openQuotes = ((q.first['n'] as num?) ?? 0).toInt();
        _openOrders = ((o.first['n'] as num?) ?? 0).toInt();
        _monthReturns = d0(month['totalReturns']);
      });
    } catch (_) {}
  }

  void _go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w)).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'المبيعات',
      subtitle: 'مرتجعات • عروض أسعار • طلبات • مندوبون',
      icon: Icons.storefront,
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'مبيعات اليوم', value: fmtMoney(_today), hint: '$_todayCount فاتورة', icon: Icons.today, color: ErpColors.green,
            onTap: () => _go(CustomRangeReportScreen(from: DateTime.now(), to: DateTime.now()))),
        StatCard(label: 'عروض مفتوحة', value: '$_openQuotes', icon: Icons.request_quote, color: ErpColors.cyan,
            onTap: () => _go(const QuotationsScreen())),
        StatCard(label: 'طلبات مفتوحة', value: '$_openOrders', icon: Icons.assignment, color: ErpColors.blue,
            onTap: () => _go(const OrdersScreen())),
        StatCard(label: 'مرتجعات الشهر', value: fmtMoney(_monthReturns), icon: Icons.assignment_return, color: ErpColors.orange,
            onTap: () {
              final n = DateTime.now();
              _go(ReturnsReportScreen(from: DateTime(n.year, n.month, 1), to: n));
            }),
      ]),
      body: HubSections(sections: SalesHubScreen.menu(context, _go)),
    );
  }
}
