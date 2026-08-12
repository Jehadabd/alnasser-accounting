import 'package:flutter/material.dart';
import '../models/product.dart';
import '../screens/product_entry_screen.dart'; // للانتقال للتعديل اذا لزم

class AlertsDisplayDialog extends StatefulWidget {
  final List<Product> lowStockProducts;
  final List<Product> stagnantProducts;
  final List<Product> expiryProducts; // 🚨 Added

  const AlertsDisplayDialog({
    super.key,
    required this.lowStockProducts,
    required this.stagnantProducts,
    required this.expiryProducts, // 🚨 Added
  });

  @override
  State<AlertsDisplayDialog> createState() => _AlertsDisplayDialogState();
}

class _AlertsDisplayDialogState extends State<AlertsDisplayDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // Changed to 3
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        height: 600,
        width: 800, // عرض مناسب للتابلت والديسكتوب
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.deepPurple, size: 32),
                const SizedBox(width: 12),
                const Text(
                  'تنبيهات النظام',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Tabs
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Colors.deepPurple,
                  borderRadius: BorderRadius.circular(12),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.black,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_outlined),
                        const SizedBox(width: 8),
                        Text('مواد أوشكت على النفاذ (${widget.lowStockProducts.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.timer_off_outlined),
                        const SizedBox(width: 8),
                        Text('مواد راكدة (${widget.stagnantProducts.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.event_busy_outlined),
                        const SizedBox(width: 8),
                        Text(' تحذير صلاحية المنتجات (${widget.expiryProducts.length})'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildProductList(widget.lowStockProducts, alertType: 'low_stock'),
                  _buildProductList(widget.stagnantProducts, alertType: 'stagnant'),
                  _buildProductList(widget.expiryProducts, alertType: 'expiry'),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Footer
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('حسناً', style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductList(List<Product> products, {required String alertType}) {
    if (products.isEmpty) {
      String emptyText = 'لا توجد تنبيهات';
      if (alertType == 'low_stock') emptyText = 'لا توجد مواد ناقصة';
      if (alertType == 'stagnant') emptyText = 'لا توجد مواد راكدة';
      if (alertType == 'expiry') emptyText = 'لا توجد مواد قريبة الانتهاء';

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green[300]),
            const SizedBox(height: 16),
            Text(
              emptyText,
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: products.length,
      separatorBuilder: (c, i) => const Divider(),
      itemBuilder: (context, index) {
        final product = products[index];
        String subtitle = '';
        IconData icon = Icons.warning_amber;
        Color color = Colors.red;
        Color bgColor = Colors.red[50]!;

        if (alertType == 'low_stock') {
          subtitle = 'المخزون الحالي: ${product.stockQuantity} ${product.unit}\n'
                     'حد التنبيه: ${product.alertQuantity ?? 0} ${product.alertUnit ?? product.unit}';
          icon = Icons.warning_amber;
          color = Colors.red;
          bgColor = Colors.red[50]!;
        } else if (alertType == 'stagnant') {
          subtitle = 'المخزون: ${product.stockQuantity} ${product.unit}\n'
                     'لم يتم بيعها منذ أكثر من 30 يوماً';
          icon = Icons.history_toggle_off;
          color = Colors.amber[800]!;
          bgColor = Colors.amber[50]!;
        } else if (alertType == 'expiry') {
          final daysLeft = product.expiryDate != null ? product.expiryDate!.difference(DateTime.now()).inDays : 0;
          subtitle = 'تنتهي في: ${product.expiryDate?.toString().split(' ')[0]}\n'
                     'متبقي: $daysLeft يوماً';
          icon = Icons.event_busy;
          color = Colors.orange[800]!;
          bgColor = Colors.orange[50]!;
        }

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: bgColor,
            child: Icon(icon, color: color),
          ),
          title: Text(
            product.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(color: color),
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          onTap: () {
            // يمكننا فتح شاشة تعديل المنتج أو تفاصيله
             // Navigator.push...
          },
        );
      },
    );
  }
}
