import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/supplier.dart';
import '../services/purchase_service.dart';
import 'supplier_details_screen.dart';
import '../models/app_settings.dart';
import '../services/settings_manager.dart';
import '../widgets/app_side_nav.dart';

/// شاشة قائمة الموردين (Odoo-Style Kanban View)
class SuppliersListScreen extends StatefulWidget {
  const SuppliersListScreen({super.key});

  @override
  State<SuppliersListScreen> createState() => _SuppliersListScreenState();
}

class _SuppliersListScreenState extends State<SuppliersListScreen> {
  final _searchController = TextEditingController();
  List<Supplier> _suppliers = [];
  List<Supplier> _filteredSuppliers = [];
  bool _isLoading = true;
  bool _isFirstLoad = true; // 🚀 لتمييز أول تحميل
  String _filterType = 'all'; // all, with_debt, no_debt
  AppSettings? _appSettings;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  /// 🚀 تحميل الموردين مع Cache ذكي
  Future<void> _loadSuppliers({bool forceRefresh = false}) async {
    final settings = await SettingsManager.getAppSettings();
    if (mounted) setState(() => _appSettings = settings);
    // إذا لم يكن هناك طلب للتحديث القسري، نستخدم Cache
    if (!forceRefresh && !_isFirstLoad) {
      // Cache موجود بالفعل في SuppliersService
      // لا حاجة لإظهار loading
    } else {
      setState(() => _isLoading = true);
    }
    
    // 🚀 Cache يتم إدارته تلقائياً في SuppliersService
    final suppliers = await context.read<PurchaseService>().getSuppliers();
    
    if (mounted) {
      setState(() {
        _suppliers = suppliers;
        _applyFilter();
        _isLoading = false;
        _isFirstLoad = false;
      });
    }
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    _filteredSuppliers = _suppliers.where((s) {
      // Apply search
      final matchesSearch = s.name.toLowerCase().contains(query) ||
          (s.phone?.contains(query) ?? false);
      
      // Apply filter
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('الموردون', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF455A64),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Filter menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              _filterType = value;
              _applyFilter();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('الكل')),
              const PopupMenuItem(value: 'with_debt', child: Text('عليهم دين')),
              const PopupMenuItem(value: 'no_debt', child: Text('بدون دين')),
            ],
          ),
        ],
      ),
      body: Row(
        children: [
          if (_appSettings != null && AppSideNav.shouldShow(context, _appSettings!))
            const AppSideNav(currentRoute: '/suppliers'),
          Expanded(
            child: Column(
        children: [
          // Header Stats
          _buildStatsHeader(),
          
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'بحث باسم المورد أو رقم الهاتف...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: (_) => _applyFilter(),
            ),
          ),
          
          // Suppliers Grid (Kanban Style)
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSuppliers.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadSuppliers,
                        child: GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.85,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _filteredSuppliers.length,
                          itemBuilder: (context, index) {
                            return _buildSupplierCard(_filteredSuppliers[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSupplierDialog(),
        backgroundColor: const Color(0xFF455A64),
        icon: const Icon(Icons.add),
        label: const Text('مورد جديد'),
      ),
    );
  }

  Widget _buildStatsHeader() {
    final totalSuppliers = _suppliers.length;
    final withDebt = _suppliers.where((s) => s.hasDebt).length;
    final totalDebtIqd = _suppliers.fold(0.0, (sum, s) => sum + s.totalDebtIqd);
    final totalDebtUsd = _suppliers.fold(0.0, (sum, s) => sum + s.totalDebtUsd);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF455A64),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          _buildStatItem('عدد الموردين', '$totalSuppliers', Icons.people),
          _buildStatItem('عليهم دين', '$withDebt', Icons.warning_amber, color: Colors.orange),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (totalDebtIqd > 0)
                  Text(
                    '${_formatNumber(totalDebtIqd)} IQD',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                if (totalDebtUsd > 0)
                  Text(
                    '${_formatNumber(totalDebtUsd)} USD',
                    style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                  ),
                const Text('إجمالي الديون', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, {Color? color}) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color ?? Colors.white, size: 28),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSupplierCard(Supplier supplier) {
    final hasDebt = supplier.hasDebt;
    final debtColor = hasDebt ? Colors.red : Colors.green;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SupplierDetailsScreen(supplier: supplier)),
        ).then((_) => _loadSuppliers(forceRefresh: true)); // 🚀 تحديث قسري بعد التعديل
      },
      child: Container(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with avatar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF455A64).withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF455A64),
                    child: Text(
                      supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      supplier.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            
            // Body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Phone
                    if (supplier.phone != null && supplier.phone!.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.phone, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(supplier.phone!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    const Spacer(),
                    
                    // Debt info
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: debtColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(hasDebt ? Icons.arrow_upward : Icons.check_circle, 
                               size: 14, color: debtColor),
                          const SizedBox(width: 4),
                          Text(
                            hasDebt 
                                ? '${_formatNumber(supplier.totalDebt)} ${supplier.currency}'
                                : 'لا يوجد دين',
                            style: TextStyle(
                              color: debtColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Stats row
                    Row(
                      children: [
                        _buildMiniStat(Icons.receipt, '${supplier.totalInvoices}'),
                        const SizedBox(width: 12),
                        _buildMiniStat(Icons.payments, '${supplier.totalPayments}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 12, color: Colors.grey),
        const SizedBox(width: 2),
        Text(value, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.store_mall_directory, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'لا يوجد موردين',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'اضغط على الزر أدناه لإضافة مورد جديد',
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
          ),
        ],
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
              Text(isEdit ? 'تعديل مورد' : 'إضافة مورد جديد'),
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
                _loadSuppliers(forceRefresh: true); // 🚀 تحديث قسري بعد الإضافة
              },
              child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(double number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(0)}K';
    }
    return number.toStringAsFixed(0);
  }
}
