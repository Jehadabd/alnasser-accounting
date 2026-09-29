// lib/erp/inventory/inventory_hub_screen.dart
//
// 📦 مركز المخزون: بطاقات المواد، المستندات المخزنية، الجرد، التصنيع، الأسعار،
// الأقسام، التقارير، المخازن والتحويلات — مع مؤشرات سريعة.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../inventory/item_card_screen.dart';
import '../../models/app_user.dart';
import '../../org/screens/branches_warehouses_screen.dart';
import '../../screens/material_inventory_screen.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
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

  void _go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w)).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'المخزون',
      subtitle: 'المواد • حركة المخزون • الفروع والمخازن • التقارير',
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
      body: HubSections(sections: [
        HubSection('المواد', [
          HubTile('بطاقات المواد', Icons.style_rounded, ErpColors.navy, () => _go(const ItemCardsListScreen()),
              subtitle: 'تعريف، أسعار، باركودات، حركة', permission: AppPermissions.itemCard),
          HubTile('تعديل المواد وحذفها', Icons.edit_note_rounded, ErpColors.blue,
              () => Navigator.pushNamed(context, '/edit_products'),
              subtitle: 'القائمة القديمة: وحدات، حذف مادة', permission: AppPermissions.editProducts),
          HubTile('الأقسام والتعديل الجماعي', Icons.account_tree_rounded, ErpColors.navy, () => _go(const CategoriesScreen()),
              permission: AppPermissions.editProducts),
          HubTile('أدوات الأسعار', Icons.price_change_rounded, ErpColors.gold, () => _go(const PriceToolsScreen()),
              subtitle: 'تعديل جماعي + تراجع', permission: AppPermissions.priceTools),
        ]),
        HubSection('حركة المخزون', [
          HubTile('سند إدخال', Icons.move_to_inbox_rounded, ErpColors.green, () => _go(const StockDocEditorScreen(docType: 'in')),
              subtitle: 'زيادة كمية: هدايا، فائض، بلا مورد', permission: AppPermissions.inventoryDocs),
          HubTile('سند إخراج', Icons.outbox_rounded, ErpColors.red, () => _go(const StockDocEditorScreen(docType: 'out')),
              subtitle: 'نقص كمية: تالف، ضيافة، استهلاك', permission: AppPermissions.inventoryDocs),
          HubTile('بضاعة أول المدة', Icons.inventory_rounded, ErpColors.cyan,
              () => _go(const StockDocEditorScreen(docType: 'opening')),
              permission: AppPermissions.inventoryDocs),
          HubTile('الجرد الفعلي', Icons.fact_check_rounded, ErpColors.orange, () => _go(const StockCountsScreen()),
              subtitle: 'بالباركود مع تسوية تلقائية', permission: AppPermissions.inventoryDocs),
          HubTile('تحويل بين المخازن', Icons.swap_horiz_rounded, ErpColors.green, () {
            if (!requireAnyPermission(context, const [AppPermissions.stockTransfer, AppPermissions.manageBranches])) return;
            _go(const BranchesWarehousesScreen(initialTab: 2));
          }),
          HubTile('التصنيع', Icons.precision_manufacturing_rounded, ErpColors.purple, () => _go(const ManufacturingScreen()),
              subtitle: 'نماذج وعمليات وهدر', permission: AppPermissions.inventoryDocs),
          HubTile('سجل المستندات', Icons.receipt_long_rounded, ErpColors.muted, () => _go(const StockDocsListScreen()),
              subtitle: 'كل السندات مع الإلغاء', permission: AppPermissions.inventoryDocs),
        ]),
        HubSection('الفروع والمخازن', [
          HubTile('الفروع والمخازن', Icons.warehouse_outlined, ErpColors.green, () {
            if (!requireAnyPermission(context, const [AppPermissions.manageBranches, AppPermissions.stockTransfer])) return;
            _go(const BranchesWarehousesScreen());
          }, subtitle: 'الفروع، المخازن، أرصدة كل مخزن'),
        ]),
        HubSection('تقارير المخزون', [
          HubTile('تقارير المخزون', Icons.analytics_rounded, ErpColors.blue, () => _go(const InventoryReportsScreen()),
              subtitle: 'حركة، تقييم، راكدة، حدود، صلاحية', permission: AppPermissions.inventoryReports),
          HubTile('جرد المواد (القيمة الحالية)', Icons.inventory, ErpColors.muted,
              () => _go(const MaterialInventoryScreen()),
              subtitle: 'المواد الموجودة وقيمتها بالكلفة', permission: AppPermissions.inventoryReports),
        ]),
      ]),
    );
  }
}
