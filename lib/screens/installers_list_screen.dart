import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/installer.dart';
import '../services/database_service.dart';
import 'installer_details_screen.dart';
import 'add_installer_screen.dart';

class InstallersListScreen extends StatefulWidget {
  const InstallersListScreen({super.key});

  @override
  State<InstallersListScreen> createState() => _InstallersListScreenState();
}

class _InstallersListScreenState extends State<InstallersListScreen> {
  final DatabaseService _db = DatabaseService();
  final TextEditingController _searchController = TextEditingController();
  List<Installer> _installers = [];
  bool _isLoading = true;
  
  static const Color primaryColor = Color(0xFF3F51B5);

  @override
  void initState() {
    super.initState();
    _loadInstallers();
  }

  Future<void> _loadInstallers() async {
    setState(() => _isLoading = true);
    try {
      final installers = await _db.getAllInstallers();
      setState(() {
        _installers = installers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل قائمة المؤسسين: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _searchInstallers(String query) async {
    if (query.isEmpty) {
      await _loadInstallers();
      return;
    }

    setState(() => _isLoading = true);
    try {
      final results = await _db.searchInstallers(query);
      setState(() {
        _installers = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في البحث: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String formatCurrency(num value) {
    return NumberFormat('#,##0', 'en_US').format(value);
  }

  @override
  Widget build(BuildContext context) {
    // حساب الإجماليات
    final totalAmount = _installers.fold(0.0, (sum, i) => sum + i.totalBilledAmount);
    final totalPoints = _installers.fold(0.0, (sum, i) => sum + i.totalPoints);

    return Scaffold(
      appBar: AppBar(
        title: const Text('المؤسسين'),
        centerTitle: true,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // بطاقات الملخص
          Container(
            color: primaryColor,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'عدد المؤسسين',
                    '${_installers.length}',
                    Icons.people,
                    Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'إجمالي النقاط',
                    totalPoints.toStringAsFixed(1),
                    Icons.star,
                    Colors.amber,
                  ),
                ),
              ],
            ),
          ),
          
          // حقل البحث
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'بحث عن مؤسس...',
                prefixIcon: Icon(Icons.search, color: primaryColor),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primaryColor, width: 2),
                ),
              ),
              onChanged: _searchInstallers,
            ),
          ),
          
          // قائمة المؤسسين
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: primaryColor))
                : _installers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'لا يوجد مؤسسين',
                              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _installers.length,
                        itemBuilder: (context, index) {
                          final installer = _installers[index];
                          return _buildInstallerCard(installer);
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddInstallerScreen(),
            ),
          ).then((_) => _loadInstallers());
        },
        backgroundColor: primaryColor,
        icon: const Icon(Icons.add),
        label: const Text('إضافة مؤسس'),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8)),
              ),
              Text(
                value,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstallerCard(Installer installer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => InstallerDetailsScreen(installer: installer),
            ),
          ).then((_) => _loadInstallers());
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // أيقونة المؤسس
              CircleAvatar(
                radius: 28,
                backgroundColor: primaryColor.withOpacity(0.1),
                child: Text(
                  installer.name.isNotEmpty ? installer.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              
              // معلومات المؤسس
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      installer.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatCurrency(installer.totalBilledAmount)} د.ع',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              
              // النقاط
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, size: 18, color: Colors.amber.shade700),
                    const SizedBox(width: 4),
                    Text(
                      installer.totalPoints.toStringAsFixed(1),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}