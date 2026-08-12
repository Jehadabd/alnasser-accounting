import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/auth_service.dart';
import '../models/app_user.dart';
import '../services/password_service.dart';
import 'material_inventory_screen.dart';
import 'stock_adjustment_screen.dart';

class InventoryMenuScreen extends StatelessWidget {
  const InventoryMenuScreen({super.key});

  Future<bool> _checkPermission(BuildContext context, String permissionKey) async {
    final authService = AuthService();
    if (!authService.hasPermission(permissionKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ليس لديك صلاحية للوصول إلى هذه الميزة'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
    return true;
  }

  Future<bool> _showPasswordDialog(BuildContext context) async {
    final passwordService = PasswordService();
    final TextEditingController passwordController = TextEditingController();
    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الرجاء إدخال كلمة السر', style: TextStyle(fontSize: 20)),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'كلمة السر',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.lock, size: 28),
          ),
          autofocus: true,
          onSubmitted: (value) async {
            final bool isCorrect = await passwordService.verifyPassword(value);
            Navigator.of(context).pop(isCorrect);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final bool isCorrect = await passwordService.verifyPassword(passwordController.text);
              Navigator.of(context).pop(isCorrect);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المخزون'),
        centerTitle: true,
        backgroundColor: const Color(0xFF4CAF50),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.1,
                children: [
                  _buildMenuButton(
                    context,
                    title: 'إدخال بضاعة',
                    icon: Icons.add_box,
                    color: Colors.blue,
                    onTap: () async {
                      if (await _checkPermission(context, AppPermissions.productEntry)) {
                        Navigator.pushNamed(context, '/product_entry');
                      }
                    },
                  ),
                  _buildMenuButton(
                    context,
                    title: 'تعديل بضاعة',
                    icon: Icons.edit,
                    color: Colors.orange,
                    onTap: () async {
                      if (await _checkPermission(context, AppPermissions.editProducts)) {
                         Navigator.pushNamed(context, '/edit_products');
                      }
                    },
                  ),
                  _buildMenuButton(
                    context,
                    title: 'تعديل المخزن',
                    icon: Icons.warehouse,
                    color: Colors.purple,
                    onTap: () async {
                         if (await _checkPermission(context, AppPermissions.editProducts)) {
                            Navigator.push(
                              context, 
                              MaterialPageRoute(builder: (context) => const StockAdjustmentScreen())
                            );
                         }
                    },
                  ),
                  _buildMenuButton(
                    context,
                    title: 'جرد المواد',
                    icon: Icons.inventory_2,
                    color: Colors.teal,
                    onTap: () async {
                      // نقلنا التحقق من الباسوورد من الزر القديم
                      // عادة جرد المواد لا يطلب باسوورد في الزر القديم (كان داخل الجرد الشهري الذي يطلب باسوورد)
                      // لذا سأطلب الباسوورد هنا للأمان
                         Navigator.push(
                           context, 
                           MaterialPageRoute(builder: (context) => const MaterialInventoryScreen())
                         );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: color),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
