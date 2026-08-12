// widgets/app_drawer.dart
import 'package:flutter/material.dart';
// removed font settings navigation

class AppDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              gradient: LinearGradient(
                colors: [Color(0xFF2E5BFF), Color(0xFF8C54FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.store,
                      size: 36, color: Theme.of(context).primaryColor),
                ),
                SizedBox(height: 16),
                Text('بابت',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    )),
                Text('نظام إدارة المتاجر',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    )),
              ],
            ),
          ),
          _buildDrawerItem(context, 'الصفحة الرئيسية', Icons.home, () {}),
          _buildDrawerItem(context, 'الفواتير', Icons.receipt, () {}),
          _buildDrawerItem(context, 'المنتجات', Icons.inventory, () {}),
          _buildDrawerItem(context, 'العملاء', Icons.people, () {}),
          _buildDrawerItem(context, 'التقارير', Icons.analytics, () {}),
          Divider(),
          
          _buildDrawerItem(context, 'الإعدادات', Icons.settings, () {}),
          _buildDrawerItem(context, 'الدعم', Icons.help, () {}),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
      BuildContext context, String title, IconData icon, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey.shade700),
      title: Text(title, style: TextStyle(fontSize: 16)),
      onTap: onTap,
      contentPadding: EdgeInsets.symmetric(horizontal: 20),
    );
  }
}
