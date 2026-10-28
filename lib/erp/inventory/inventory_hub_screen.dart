// lib/erp/inventory/inventory_hub_screen.dart
//
// 📦 مركز المخزون: بطاقات المواد، المستندات المخزنية، الجرد، التصنيع، الأسعار،
// الأقسام، التقارير، المخازن والتحويلات — مع مؤشرات سريعة.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../inventory/item_card_screen.dart';
import '../../models/app_user.dart';
import '../../org/screens/branches_warehouses_screen.dart';
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

  /// 🧭 أزرار المركز — مصدر واحد للشاشة نفسها وللوحة الجانبية
  static List<HubSection> menu(BuildContext context, void Function(Widget) go) => [
      HubSection('المواد', [
        HubTile('المواد', Icons.inventory_2_rounded, ErpColors.navy, () => go(const ItemCardsListScreen()),
            subtitle: 'كل المواد: بحث، تعديل، حذف، فلاتر (بلا سعر، نفدت…)', permission: AppPermissions.itemCard),
        HubTile('الأقسام والتعديل الجماعي', Icons.account_tree_rounded, ErpColors.navy, () => go(const CategoriesScreen()),
            subtitle: 'شجرة الأقسام، نقل مواد، تفعيل وإيقاف، ترميز', permission: AppPermissions.editProducts),
        HubTile('أدوات الأسعار', Icons.price_change_rounded, ErpColors.gold, () => go(const PriceToolsScreen()),
            subtitle: 'رفع أو خفض أسعار مجموعة مواد بمعاينة وتراجع', permission: AppPermissions.priceTools),
      ]),
      HubSection('حركة المخزون', [
        HubTile('سند إدخال', Icons.move_to_inbox_rounded, ErpColors.green, () => go(const StockDocEditorScreen(docType: 'in')),
            subtitle: 'زيادة كمية: هدايا، فائض، بلا مورد', permission: AppPermissions.inventoryDocs),
        HubTile('سند إخراج', Icons.outbox_rounded, ErpColors.red, () => go(const StockDocEditorScreen(docType: 'out')),
            subtitle: 'نقص كمية: تالف، ضيافة، استهلاك', permission: AppPermissions.inventoryDocs),
        HubTile('بضاعة أول المدة', Icons.inventory_rounded, ErpColors.cyan,
            () => go(const StockDocEditorScreen(docType: 'opening')),
            subtitle: 'الكميات الموجودة عند بدء العمل بالبرنامج', permission: AppPermissions.inventoryDocs),
        HubTile('الجرد الفعلي', Icons.fact_check_rounded, ErpColors.orange, () => go(const StockCountsScreen()),
            subtitle: 'عدّ البضاعة على الرفوف بالباركود وتصحيح الفروقات', permission: AppPermissions.inventoryDocs),
        HubTile('تحويل بين المخازن', Icons.swap_horiz_rounded, ErpColors.green, () {
          if (!requireAnyPermission(context, const [AppPermissions.stockTransfer, AppPermissions.manageBranches])) return;
          go(const BranchesWarehousesScreen(initialTab: 2));
        }, subtitle: 'نقل بضاعة من مخزن إلى آخر'),
        HubTile('التصنيع', Icons.precision_manufacturing_rounded, ErpColors.purple, () => go(const ManufacturingScreen()),
            subtitle: 'نماذج وعمليات وهدر', permission: AppPermissions.inventoryDocs),
        HubTile('سجل المستندات', Icons.receipt_long_rounded, ErpColors.muted, () => go(const StockDocsListScreen()),
            subtitle: 'كل السندات السابقة: عرض، طباعة، إلغاء', permission: AppPermissions.inventoryDocs),
      ]),
      HubSection('الفروع والمخازن', [
        HubTile('الفروع والمخازن', Icons.warehouse_outlined, ErpColors.green, () {
          if (!requireAnyPermission(context, const [AppPermissions.manageBranches, AppPermissions.stockTransfer])) return;
          go(const BranchesWarehousesScreen());
        }, subtitle: 'الفروع والمخازن، وأرصدة كل مخزن وتعديلها'),
      ]),
      HubSection('تقارير المخزون', [
        HubTile('لوحة المخزون والتقارير', Icons.analytics_rounded, ErpColors.blue,
            () => go(const InventoryReportsScreen(initial: 'overview')),
            subtitle: 'مؤشرات دائرية + حركة، تقييم، راكدة، حدود، صلاحية', permission: AppPermissions.inventoryReports),
        HubTile('قيمة المخزون الحالية', Icons.account_balance_wallet_rounded, ErpColors.green,
            () => go(const InventoryReportsScreen(initial: 'valuation')),
            subtitle: 'كم تساوي بضاعتك الآن بالكلفة وبسعر البيع', permission: AppPermissions.inventoryReports),
      ]),
      ];

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
        StatCard(label: 'المواد المخزنية', value: fmtQty(_items), icon: Icons.inventory_2_outlined, color: ErpColors.blue,
            onTap: () => _go(const ItemCardsListScreen())),
        StatCard(label: 'قيمة المخزون', value: fmtMoney(_value), icon: Icons.account_balance_wallet_outlined, color: ErpColors.green,
            onTap: () => _go(const InventoryReportsScreen(initial: 'valuation'))),
        StatCard(label: 'تحت الحد الأدنى', value: fmtQty(_below), icon: Icons.warning_amber_rounded, color: ErpColors.red,
            onTap: () => _go(const InventoryReportsScreen(initial: 'limits'))),
        StatCard(label: 'نافدة', value: fmtQty(_zero), icon: Icons.remove_shopping_cart_outlined, color: ErpColors.orange),
        if (_openCounts > 0)
          StatCard(label: 'جرد مفتوح', value: fmtQty(_openCounts), icon: Icons.fact_check_outlined, color: ErpColors.purple,
              onTap: () => _go(const StockCountsScreen())),
      ]),
      body: HubSections(sections: InventoryHubScreen.menu(context, _go)),
    );
  }
}
