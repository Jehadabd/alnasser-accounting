// screens/installer_details_screen.dart
import 'package:flutter/material.dart';
import '../models/installer.dart';
import '../models/invoice.dart';
import '../services/database_service.dart';
import 'package:intl/intl.dart';

class InstallerDetailsScreen extends StatefulWidget {
  final Installer installer;

  const InstallerDetailsScreen({
    super.key,
    required this.installer,
  });

  @override
  State<InstallerDetailsScreen> createState() => _InstallerDetailsScreenState();
}

class _InstallerDetailsScreenState extends State<InstallerDetailsScreen> with SingleTickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  late Installer _currentInstaller;
  List<Invoice> _invoices = [];
  List<Map<String, dynamic>> _pointsHistory = [];
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _currentInstaller = widget.installer;
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final invoices = await _db.getInvoicesByInstaller(_currentInstaller.name);
      final points = await _db.getInstallerPointsHistory(_currentInstaller.id!);
      
      // Reload installer to get latest totals
      final installers = await _db.getAllInstallers();
      final updatedInstaller = installers.firstWhere((i) => i.id == _currentInstaller.id, orElse: () => _currentInstaller);

      setState(() {
        _invoices = invoices;
        _pointsHistory = points;
        _currentInstaller = updatedInstaller;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل البيانات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showAddPointsDialog() async {
    final pointsController = TextEditingController();
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة نقاط يدوياً'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: pointsController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'عدد النقاط'),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'يرجى إدخال عدد النقاط';
                  if (double.tryParse(value) == null) return 'رقم غير صحيح';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'السبب / الملاحظات'),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'يرجى إدخال السبب';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final points = double.parse(pointsController.text);
                final reason = reasonController.text;
                
                try {
                  await _db.addInstallerPoints(_currentInstaller.id!, points, reason);
                  if (mounted) {
                    Navigator.pop(context);
                    _loadData(); // Reload to show new points
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم إضافة النقاط بنجاح'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeductPointsDialog() async {
    final pointsController = TextEditingController();
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('خصم نقاط'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: pointsController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'عدد النقاط المراد خصمها'),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'يرجى إدخال عدد النقاط';
                  if (double.tryParse(value) == null) return 'رقم غير صحيح';
                  if (double.parse(value) <= 0) return 'يجب أن يكون الرقم أكبر من صفر';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'السبب / الملاحظات'),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'يرجى إدخال السبب';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final points = double.parse(pointsController.text);
                final reason = reasonController.text;
                
                try {
                  await _db.deductInstallerPoints(_currentInstaller.id!, points, reason);
                  if (mounted) {
                    Navigator.pop(context);
                    _loadData(); // Reload to show new points
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم خصم النقاط بنجاح'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('خصم'),
          ),
        ],
      ),
    );
  }

  String formatCurrency(num value) {
    return NumberFormat('#,##0.##', 'en_US').format(value);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF3F51B5);

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentInstaller.name),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'الفواتير', icon: Icon(Icons.receipt_long)),
            Tab(text: 'سجل النقاط', icon: Icon(Icons.stars)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Summary Cards
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          'إجمالي المبلغ',
                          '${formatCurrency(_currentInstaller.totalBilledAmount)} د.ع',
                          Icons.attach_money,
                          Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildSummaryCard(
                          'مجموع النقاط',
                          _currentInstaller.totalPoints.toStringAsFixed(1),
                          Icons.star,
                          Colors.amber.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildInvoicesList(),
                      _buildPointsHistoryList(),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            onPressed: _showDeductPointsDialog,
            label: const Text('خصم نقاط'),
            icon: const Icon(Icons.remove_circle_outline),
            backgroundColor: Colors.red.shade700,
            heroTag: 'deduct_points',
          ),
          const SizedBox(width: 16),
          FloatingActionButton.extended(
            onPressed: _showAddPointsDialog,
            label: const Text('إضافة نقاط'),
            icon: const Icon(Icons.add_circle_outline),
            backgroundColor: primaryColor,
            heroTag: 'add_points',
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoicesList() {
    if (_invoices.isEmpty) {
      return const Center(child: Text('لا توجد فواتير مرتبطة'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _invoices.length,
      itemBuilder: (context, index) {
        final invoice = _invoices[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.receipt)),
            title: Text(invoice.customerName),
            subtitle: Text(DateFormat('yyyy/MM/dd').format(invoice.invoiceDate)),
            trailing: Text(
              '${formatCurrency(invoice.totalAmount)} د.ع',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPointsHistoryList() {
    if (_pointsHistory.isEmpty) {
      return const Center(child: Text('لا يوجد سجل نقاط'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pointsHistory.length,
      itemBuilder: (context, index) {
        final point = _pointsHistory[index];
        final double points = (point['points'] as num).toDouble();
        final bool isPositive = points > 0;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isPositive ? Colors.green.shade100 : Colors.red.shade100,
              child: Icon(
                isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                color: isPositive ? Colors.green : Colors.red,
              ),
            ),
            title: Text(point['reason'] ?? 'بدون سبب'),
            subtitle: Text(DateFormat('yyyy/MM/dd HH:mm').format(DateTime.parse(point['created_at']))),
            trailing: Text(
              '${points > 0 ? '+' : ''}${points.toStringAsFixed(1)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
          ),
        );
      },
    );
  }
}
