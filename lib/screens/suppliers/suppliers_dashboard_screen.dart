import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/supplier.dart';
import '../../services/purchase_service.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/supplier_rich_card.dart';
import '../supplier_details_screen.dart';
import 'package:intl/intl.dart' as intl;

class SuppliersDashboardScreen extends StatefulWidget {
  const SuppliersDashboardScreen({super.key});

  @override
  State<SuppliersDashboardScreen> createState() => _SuppliersDashboardScreenState();
}

class _SuppliersDashboardScreenState extends State<SuppliersDashboardScreen> {
  final _searchController = TextEditingController();
  List<Supplier> _suppliers = [];
  List<Supplier> _filteredSuppliers = [];
  bool _isLoading = true;
  String _filterType = 'all'; // all, with_debt, no_debt

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    setState(() => _isLoading = true);
    final suppliers = await context.read<PurchaseService>().getSuppliers();
    setState(() {
      _suppliers = suppliers;
      _applyFilter();
      _isLoading = false;
    });
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    _filteredSuppliers = _suppliers.where((s) {
      final matchesSearch = s.name.toLowerCase().contains(query) ||
          (s.phone?.contains(query) ?? false);
      
      switch (_filterType) {
        case 'with_debt':
          return matchesSearch && s.hasDebt;
        case 'no_debt':
          return matchesSearch && !s.hasDebt;
        default:
          return matchesSearch;
      }
    }).toList();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Stats Calculations
    final totalDebt = _suppliers.fold(0.0, (sum, s) => sum + s.totalDebtIqd); // Focus on IQD for dashboard summary
    final totalPayments = _suppliers.fold(0.0, (sum, s) => sum + s.totalPayments); // This is count, we need Amount if available. Supplier model has totalPayments as int count. 
    // Wait, Supplier model has `totalPaid`? No, it has `totalPayments` (int) and `totalPurchases` (double).
    // Let's use totalPurchases for "Volume" stat.
    final totalPurchases = _suppliers.fold(0.0, (sum, s) => sum + s.totalPurchases);
    final totalInvoices = _suppliers.fold(0, (sum, s) => sum + s.totalInvoices);
    
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC), // Light Slate Background
      appBar: AppBar(
        title: const Row(
          children: [
            SizedBox(
              width: 32, height: 32,
              child: CircleAvatar(
                backgroundColor: Color(0xFF3B82F6),
                child: Text('N', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            SizedBox(width: 12),
            Text('نظام الموردين الذكي', style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey[200], height: 1),
        ),
        actions: [
           IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            onPressed: _loadSuppliers,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // BREADCRUMBS
                  Row(
                    children: [
                      Icon(Icons.dashboard_outlined, size: 20, color: Colors.blue[600]),
                      const SizedBox(width: 8),
                      Text(
                        'الرئيسية',
                        style: TextStyle(color: Colors.blue[600], fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // STATS GRID
                  LayoutBuilder(builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    int crossAxisCount = width > 1200 ? 4 : (width > 800 ? 2 : 1);
                    
                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 2.2, // Wide cards
                      children: [
                        StatCard(
                          title: 'إجمالي الديون',
                          value: '${_formatNumber(totalDebt)} IQD',
                          icon: Icons.monetization_on_outlined,
                          color: Colors.red,
                          trend: '+12% هذا الشهر',
                          isPositiveTrend: false, // Debt going up is bad? Or shows activity. Let's assume standard trend.
                        ),
                        StatCard(
                          title: 'حجم المشتريات',
                          value: '${_formatNumber(totalPurchases)} IQD',
                          icon: Icons.shopping_bag_outlined,
                          color: Colors.blue,
                          trend: '+5% عن العام الماضي',
                        ),
                        StatCard(
                          title: 'إجمالي الفواتير',
                          value: '$totalInvoices',
                          icon: Icons.receipt_long_outlined,
                          color: Colors.orange,
                        ),
                        StatCard(
                          title: 'عدد الموردين',
                          value: '${_suppliers.length}',
                          icon: Icons.people_outline,
                          color: Colors.purple,
                        ),
                      ],
                    );
                  }),
                  
                  const SizedBox(height: 32),
                  
                  // SECTION TITLE + SEARCH
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'الموردون المعتمدون',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Container(
                        width: 300,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => _applyFilter(),
                          decoration: InputDecoration(
                            hintText: 'بحث...',
                            prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () {
                                      _searchController.clear();
                                      _applyFilter();
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // SUPPLIERS GRID
                  LayoutBuilder(builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    // Responsive grid: 3 cards on wide, 2 on medium, 1 on mobile
                    int crossAxisCount = width > 1400 ? 5 : (width > 1100 ? 4 : (width > 700 ? 3 : 1));
                    
                    if (_filteredSuppliers.isEmpty) {
                      return _buildEmptyState();
                    }

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: 0.8, // Slightly more compact height
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: _filteredSuppliers.length,
                      itemBuilder: (context, index) {
                        return SupplierRichCard(
                          supplier: _filteredSuppliers[index],
                          onTap: () {
                             Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SupplierDetailsScreen(supplier: _filteredSuppliers[index]),
                              ),
                            ).then((_) => _loadSuppliers());
                          },
                          onDelete: () {
                            // TODO: Show Delete Confirmation
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('الحذف غير مفعل في هذه النسخة التجريبية UI')),
                            );
                          },
                          onEdit: () {
                             // Edit Logic
                          },
                        );
                      },
                    );
                  }),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSupplierDialog(),
        backgroundColor: const Color(0xFF3B82F6),
        child: const Icon(Icons.add, size: 32),
      ),
    );
  }

  void _showAddSupplierDialog({Supplier? supplier}) {
    final isEdit = supplier != null;
    final nameController = TextEditingController(text: supplier?.name ?? '');
    final phoneController = TextEditingController(text: supplier?.phone ?? '');
    final addressController = TextEditingController(text: supplier?.address ?? '');
    String currency = supplier?.currency ?? 'IQD';
    String paymentTerms = supplier?.paymentTerms ?? 'cash';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(isEdit ? Icons.edit : Icons.person_add, color: const Color(0xFF455A64)),
              const SizedBox(width: 8),
              Text(isEdit ? 'تعديل مورد' : 'إضافة مورد جديد', style: const TextStyle(fontFamily: 'Cairo')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المورد *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'العنوان',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: currency,
                  decoration: const InputDecoration(
                    labelText: 'العملة المفضلة',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'IQD', child: Text('IQD - دينار عراقي')),
                    DropdownMenuItem(value: 'USD', child: Text('USD - دولار أمريكي')),
                  ],
                  onChanged: isEdit ? null : (val) => setDialogState(() => currency = val!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: paymentTerms,
                  decoration: const InputDecoration(
                    labelText: 'شروط الدفع',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payment),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                    DropdownMenuItem(value: 'credit', child: Text('آجل')),
                  ],
                  onChanged: (val) => setDialogState(() => paymentTerms = val!),
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF455A64)),
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('الرجاء إدخال اسم المورد')),
                  );
                  return;
                }

                final now = DateTime.now();
                final newSupplier = Supplier(
                  id: supplier?.id,
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim(),
                  address: addressController.text.trim(),
                  currency: currency,
                  paymentTerms: paymentTerms,
                  totalDebtIqd: supplier?.totalDebtIqd ?? 0.0,
                  totalDebtUsd: supplier?.totalDebtUsd ?? 0.0,
                  totalInvoices: supplier?.totalInvoices ?? 0,
                  totalPayments: supplier?.totalPayments ?? 0,
                  createdAt: supplier?.createdAt ?? now,
                  updatedAt: now,
                );

                final purchaseService = context.read<PurchaseService>();
                if (isEdit) {
                  await purchaseService.updateSupplier(newSupplier);
                } else {
                  await purchaseService.addSupplier(newSupplier);
                }

                Navigator.pop(context);
                _loadSuppliers();
              },
              child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 300,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'لا توجد نتائج',
            style: TextStyle(fontSize: 18, color: Colors.grey[500], fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _formatNumber(double number) {
    return intl.NumberFormat.compact().format(number);
  }
}
