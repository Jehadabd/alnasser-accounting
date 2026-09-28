// lib/erp/sales/sales_hub_screen.dart
//
// 🛒 مركز المبيعات والمستندات.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../models/app_user.dart';
import '../debts/debt_reports_screen.dart';
import '../device_defaults.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../erp_settings_screen.dart';
import '../pos/price_checker_screen.dart';
import '../reports/finance_reports.dart';
import 'invoice_extras.dart';
import 'quotes_orders_screen.dart';
import 'sales_return_screen.dart';

class SalesHubScreen extends StatefulWidget {
  const SalesHubScreen({super.key});
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
      final t = await db.rawQuery('''
        SELECT COALESCE(SUM(total_amount), 0) AS s, COUNT(*) AS n FROM invoices
        WHERE status = 'محفوظة' AND COALESCE(is_deleted, 0) = 0 AND invoice_date >= ? AND invoice_date < ?
      ''', [isoDay(now), isoDayAfter(now)]);
      final q = await db.rawQuery("SELECT COUNT(*) AS n FROM quotations WHERE status = 'open'");
      final o = await db.rawQuery("SELECT COUNT(*) AS n FROM orders WHERE status IN ('open', 'partial')");
      final r = await db.rawQuery('''
        SELECT COALESCE(SUM(total), 0) AS s FROM sales_returns WHERE status = 'posted' AND return_date >= ?
      ''', [isoDay(DateTime(now.year, now.month, 1))]);
      if (!mounted) return;
      setState(() {
        _today = d0(t.first['s']);
        _todayCount = ((t.first['n'] as num?) ?? 0).toInt();
        _openQuotes = ((q.first['n'] as num?) ?? 0).toInt();
        _openOrders = ((o.first['n'] as num?) ?? 0).toInt();
        _monthReturns = d0(r.first['s']);
      });
    } catch (_) {}
  }

  void _go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w)).then((_) => _load());

  Future<void> _deviceDefaults() async {
    int? box = await DeviceDefaults.cashBoxId();
    int? wh = await DeviceDefaults.warehouseId();
    if (!mounted) return;
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
      if (mounted) showOk(context, 'حُفظ صندوق ومخزن هذا الجهاز');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'المبيعات والمستندات',
      subtitle: 'مرتجعات، عروض أسعار، طلبات، بائعون',
      icon: Icons.storefront,
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'مبيعات اليوم', value: fmtMoney(_today), hint: '$_todayCount فاتورة', icon: Icons.today, color: ErpColors.green),
        StatCard(label: 'عروض مفتوحة', value: '$_openQuotes', icon: Icons.request_quote, color: ErpColors.cyan,
            onTap: () => _go(const QuotationsScreen())),
        StatCard(label: 'طلبات مفتوحة', value: '$_openOrders', icon: Icons.assignment, color: ErpColors.blue,
            onTap: () => _go(const OrdersScreen())),
        StatCard(label: 'مرتجعات الشهر', value: fmtMoney(_monthReturns), icon: Icons.assignment_return, color: ErpColors.orange),
      ]),
      body: HubGrid(tiles: [
        HubTile('إنشاء قائمة', Icons.post_add, ErpColors.navy, () => Navigator.pushNamed(context, '/create_invoice'),
            subtitle: 'F2', permission: AppPermissions.createInvoice),
        HubTile('الكاشير', Icons.point_of_sale, ErpColors.green, () => Navigator.pushNamed(context, '/pos'),
            subtitle: 'F1', permission: AppPermissions.posAccess),
        HubTile('مرتجع مبيعات', Icons.assignment_return, ErpColors.orange, () => _go(const SalesReturnScreen()),
            subtitle: 'نقداً أو من حساب العميل', permission: AppPermissions.salesDocs),
        HubTile('سجل المرتجعات', Icons.history, ErpColors.muted, () => _go(const SalesReturnsListScreen()),
            permission: AppPermissions.salesDocs),
        HubTile('عروض الأسعار', Icons.request_quote_outlined, ErpColors.cyan, () => _go(const QuotationsScreen()),
            subtitle: 'طباعة وتحويل لفاتورة', permission: AppPermissions.salesDocs),
        HubTile('طلبات المبيعات', Icons.assignment_outlined, ErpColors.blue, () => _go(const OrdersScreen()),
            subtitle: 'حجز كميات وتسليم جزئي', permission: AppPermissions.salesDocs),
        HubTile('طلبات المشتريات', Icons.shopping_cart_checkout, ErpColors.purple,
            () => _go(const OrdersScreen(orderType: 'purchase')),
            subtitle: 'وطلب تلقائي للنواقص', permission: AppPermissions.suppliers),
        HubTile('الفواتير غير المسددة', Icons.receipt_outlined, ErpColors.red, () => _go(const OpenInvoicesScreen()),
            permission: AppPermissions.debtReports),
        HubTile('البائعون والعمولات', Icons.badge, ErpColors.gold, () => _go(const SellersScreen()),
            permission: AppPermissions.salesDocs),
        HubTile('تقرير المبيعات التفصيلي', Icons.receipt_long_rounded, ErpColors.green,
            () => _go(const SalesDetailReportScreen()),
            subtitle: 'ربح كل فاتورة وفلتر المخزن', permission: AppPermissions.reports),
        HubTile('قارئ الأسعار', Icons.qr_code_scanner_rounded, ErpColors.cyan, () => _go(const PriceCheckerScreen()),
            subtitle: 'شاشة للزبائن'),
        HubTile('إعدادات الطباعة والمخزون', Icons.tune_rounded, ErpColors.muted, () => _go(const ErpSettingsScreen()),
            subtitle: 'A4 أو 80mm، الملصقات', permission: AppPermissions.settings),
        HubTile('صندوق ومخزن هذا الجهاز', Icons.devices, ErpColors.navy, _deviceDefaults,
            subtitle: 'لكل كاشير صندوقه', permission: AppPermissions.accountingPost),
      ]),
    );
  }
}
