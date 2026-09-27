// lib/erp/inventory/inventory_hub_screen.dart
//
// 📦 مركز المخزون: بطاقات المواد، المستندات المخزنية، الجرد، التصنيع، الأسعار،
// الأقسام، التقارير، المخازن والتحويلات — مع مؤشرات سريعة.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../inventory/item_card_screen.dart';
import '../../models/app_user.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pos/scale_barcode.dart';
import '../sales/quotes_orders_screen.dart';
import 'categories_screen.dart';
import 'inventory_reports.dart';
import 'inventory_reports_screen.dart';
import 'manufacturing_screen.dart';
import 'price_tools_screen.dart';
import 'stock_count_screen.dart';
import 'stock_docs_screen.dart';

class InventoryHubScreen extends StatefulWidget {
  const InventoryHubScreen({super.key});
  @override
  State<InventoryHubScreen> createState() => _InventoryHubScreenState();
}

class _InventoryHubScreenState extends State<InventoryHubScreen> {
  int _items = 0;
  double _value = 0;
  int _below = 0;
  int _zero = 0;
  int _openCounts = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await erpDb();
      final a = await db.rawQuery('''
        SELECT COUNT(*) AS n,
               COALESCE(SUM(CASE WHEN p.stock_quantity > 0 THEN p.stock_quantity * COALESCE(p.cost_price, 0) ELSE 0 END), 0) AS v,
               COALESCE(SUM(CASE WHEN COALESCE(p.stock_quantity, 0) <= 0 THEN 1 ELSE 0 END), 0) AS z
        FROM products p LEFT JOIN product_details d ON d.product_id = p.id
        WHERE COALESCE(p.is_deleted, 0) = 0 AND COALESCE(d.item_type, 'trade') != 'service'
      ''');
      final below = await InventoryReports().limits('below_min');
      final c = await db.rawQuery("SELECT COUNT(*) AS n FROM stock_counts WHERE status = 'draft'");
      if (!mounted) return;
      setState(() {
        _items = ((a.first['n'] as num?) ?? 0).toInt();
        _value = d0(a.first['v']);
        _zero = ((a.first['z'] as num?) ?? 0).toInt();
        _below = below.length;
        _openCounts = ((c.first['n'] as num?) ?? 0).toInt();
      });
    } catch (_) {}
  }

  Future<void> _scaleSettings() async {
    final s = await ScaleSettings.load();
    final prefix = TextEditingController(text: s.prefix);
    final plu = TextEditingController(text: '${s.pluLength}');
    final val = TextEditingController(text: '${s.valueLength}');
    var div = s.divisor;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('إعداد باركود الميزان'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('مثال: 2 12345 00750 C ⇒ بادئة 2، رمز المادة 12345، القيمة 750',
                  style: TextStyle(color: ErpColors.muted, fontSize: 12)),
              const SizedBox(height: 10),
              TextBox(controller: prefix, label: 'البادئة'),
              const SizedBox(height: 8),
              TextBox(controller: plu, label: 'عدد أرقام رمز المادة'),
              const SizedBox(height: 8),
              TextBox(controller: val, label: 'عدد أرقام القيمة'),
              const SizedBox(height: 8),
              DropBox<double>(
                label: 'القيمة تمثّل',
                width: 360,
                value: div,
                items: const [
                  DropdownMenuItem(value: 1000, child: Text('الوزن بالغرام')),
                  DropdownMenuItem(value: 1, child: Text('العدد (قطع)')),
                ],
                onChanged: (v) => setS(() => div = v ?? 1000),
              ),
              const SizedBox(height: 8),
              const Text('الكاشير يقبل الكميات الصحيحة فقط: المادة الموزونة تُعرَّف بوحدة «غرام».',
                  style: TextStyle(color: ErpColors.orange, fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    s
      ..prefix = prefix.text.trim()
      ..pluLength = int.tryParse(plu.text.trim()) ?? 5
      ..valueLength = int.tryParse(val.text.trim()) ?? 5
      ..divisor = div;
    await s.save();
    if (mounted) showOk(context, 'حُفظ إعداد الميزان');
  }

  void _go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w)).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'المخزون',
      subtitle: 'بطاقات المواد • المستندات • الجرد • التصنيع • الأسعار • التقارير',
      icon: Icons.warehouse_rounded,
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: Colors.white))],
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'المواد المخزنية', value: '$_items', icon: Icons.inventory_2_outlined, color: ErpColors.blue,
            onTap: () => _go(const ItemCardsListScreen())),
        StatCard(label: 'قيمة المخزون', value: fmtMoney(_value), icon: Icons.account_balance_wallet_outlined, color: ErpColors.green,
            onTap: () => _go(const InventoryReportsScreen(initial: 'valuation'))),
        StatCard(label: 'تحت الحد الأدنى', value: '$_below', icon: Icons.warning_amber_rounded, color: ErpColors.red,
            onTap: () => _go(const InventoryReportsScreen(initial: 'limits'))),
        StatCard(label: 'نافدة', value: '$_zero', icon: Icons.remove_shopping_cart_outlined, color: ErpColors.orange),
        if (_openCounts > 0)
          StatCard(label: 'جرد مفتوح', value: '$_openCounts', icon: Icons.fact_check_outlined, color: ErpColors.purple,
              onTap: () => _go(const StockCountsScreen())),
      ]),
      body: HubGrid(tiles: [
        HubTile('بطاقات المواد', Icons.style_rounded, ErpColors.navy, () => _go(const ItemCardsListScreen()),
            subtitle: 'تعريف، أسعار، باركودات، حركة', permission: AppPermissions.itemCard),
        HubTile('إدخال بضاعة', Icons.add_box_rounded, ErpColors.blue, () => Navigator.pushNamed(context, '/product_entry'),
            permission: AppPermissions.productEntry),
        HubTile('سند إدخال', Icons.move_to_inbox_rounded, ErpColors.green, () => _go(const StockDocEditorScreen(docType: 'in')),
            subtitle: 'هدايا، فائض، إدخال بلا مورد', permission: AppPermissions.inventoryDocs),
        HubTile('سند إخراج', Icons.outbox_rounded, ErpColors.red, () => _go(const StockDocEditorScreen(docType: 'out')),
            subtitle: 'تالف، ضيافة، استهلاك', permission: AppPermissions.inventoryDocs),
        HubTile('بضاعة أول المدة', Icons.inventory_rounded, ErpColors.cyan,
            () => _go(const StockDocEditorScreen(docType: 'opening')),
            permission: AppPermissions.inventoryDocs),
        HubTile('سجل المستندات', Icons.receipt_long_rounded, ErpColors.muted, () => _go(const StockDocsListScreen()),
            permission: AppPermissions.inventoryDocs),
        HubTile('الجرد الفعلي', Icons.fact_check_rounded, ErpColors.orange, () => _go(const StockCountsScreen()),
            subtitle: 'بالباركود مع تسوية تلقائية', permission: AppPermissions.inventoryDocs),
        HubTile('التصنيع', Icons.precision_manufacturing_rounded, ErpColors.purple, () => _go(const ManufacturingScreen()),
            subtitle: 'نماذج وعمليات وهدر', permission: AppPermissions.inventoryDocs),
        HubTile('أدوات الأسعار', Icons.price_change_rounded, ErpColors.gold, () => _go(const PriceToolsScreen()),
            subtitle: 'تعديل جماعي + تراجع', permission: AppPermissions.priceTools),
        HubTile('الأقسام والتعديل الجماعي', Icons.account_tree_rounded, ErpColors.navy, () => _go(const CategoriesScreen()),
            permission: AppPermissions.editProducts),
        HubTile('تقارير المخزون', Icons.analytics_rounded, ErpColors.blue, () => _go(const InventoryReportsScreen()),
            subtitle: 'حركة، تقييم، راكدة، حدود', permission: AppPermissions.inventoryReports),
        HubTile('طلبات المشتريات', Icons.shopping_cart_checkout_rounded, ErpColors.purple,
            () => _go(const OrdersScreen(orderType: 'purchase')),
            permission: AppPermissions.suppliers),
        HubTile('مرتجع مشتريات', Icons.assignment_return_outlined, ErpColors.orange,
            () => Navigator.pushNamed(context, '/purchase_return'),
            permission: AppPermissions.suppliers),
        HubTile('المخازن والتحويلات', Icons.warehouse_outlined, ErpColors.green, () => Navigator.pushNamed(context, '/branches'),
            permission: AppPermissions.stockTransfer),
        HubTile('باركود الميزان', Icons.scale_rounded, ErpColors.cyan, _scaleSettings,
            subtitle: 'مواد موزونة في الكاشير', permission: AppPermissions.editProducts),
        HubTile('الجرد الشهري (القديم)', Icons.inventory, ErpColors.muted, () => Navigator.pushNamed(context, '/inventory'),
            permission: AppPermissions.monthlyInventory),
      ]),
    );
  }
}
