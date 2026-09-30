import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/supplier.dart';
import '../../services/purchase_service.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/supplier_rich_card.dart';
import '../supplier_details_screen.dart';
import '../../accounting/screens/acc_ui.dart' show requirePermission, fmtMoney;
import '../../models/app_user.dart' show AppPermissions;
import '../../erp/debts/receipt_screen.dart' show SupplierPaymentScreen;
import '../../erp/purchases/purchase_return_screen.dart' show PurchaseReturnEditorScreen, PurchaseReturnsListScreen;
import '../../erp/sales/quotes_orders_screen.dart' show OrdersScreen;

class SuppliersDashboardScreen extends StatefulWidget {
  const SuppliersDashboardScreen({super.key});

  @override
  State<SuppliersDashboardScreen> createState() => _SuppliersDashboardScreenState();
}

class _SuppliersDashboardScreenState extends State<SuppliersDashboardScreen> {
  final _searchController = TextEditingController();
  List<Supplier> _suppliers = [];
  List<Supplier> _filteredSuppliers = [];
  Map<String, double> _purchaseTotals = const {};
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _loadError;
  String _filterType = 'all'; // all, with_debt, no_debt, credit

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    final service = context.read<PurchaseService>();
    try {
      final suppliers = await service.getSuppliers();
      Map<String, double> totals = const {};
      try {
        totals = await service.getConfirmedPurchaseTotals();
      } catch (_) {
        // بطاقة إحصائية ثانوية: فشلها لا يمنع عرض الموردين
      }
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
        _purchaseTotals = totals;
        _filteredSuppliers = _computeFiltered();
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'تعذّر تحميل الموردين: $e';
      });
    } finally {
      _isRefreshing = false;
    }
  }

  static bool _hasCredit(Supplier s) => s.totalDebtIqd < -0.01 || s.totalDebtUsd < -0.01;

  bool _matchesFilter(Supplier s, String type) {
    switch (type) {
      case 'with_debt':
        return s.hasDebt;
      case 'no_debt':
        return !s.hasDebt;
      case 'credit':
        return _hasCredit(s);
      default:
        return true;
    }
  }

  List<Supplier> _computeFiltered() {
    final query = _searchController.text.trim().toLowerCase();
    return _suppliers.where((s) {
      final matchesSearch = query.isEmpty ||
          s.name.toLowerCase().contains(query) ||
          (s.phone ?? '').contains(query) ||
          (s.address ?? '').toLowerCase().contains(query);
      return matchesSearch && _matchesFilter(s, _filterType);
    }).toList();
  }

  void _applyFilter() {
    setState(() => _filteredSuppliers = _computeFiltered());
  }

  Widget _quickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 📊 الإحصاءات — كل عملة على حدة (لا يُجمع الدينار مع الدولار)
    // إجمالي الديون = ما علينا للموردين (الأرصدة الموجبة فقط؛ السالب رصيد لنا عندهم)
    final debtIqd = _suppliers.fold(0.0, (sum, s) => sum + (s.totalDebtIqd > 0 ? s.totalDebtIqd : 0.0));
    final debtUsd = _suppliers.fold(0.0, (sum, s) => sum + (s.totalDebtUsd > 0 ? s.totalDebtUsd : 0.0));
    // حجم المشتريات من فواتير الشراء المؤكدة نفسها (عمود total_purchases لا يُحدَّث)
    final purchasesIqd = _purchaseTotals['IQD'] ?? 0.0;
    final purchasesUsd = _purchaseTotals['USD'] ?? 0.0;
    final totalInvoices = _suppliers.fold(0, (sum, s) => sum + s.totalInvoices);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC), // Light Slate Background
      appBar: AppBar(
        title: const Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircleAvatar(
                backgroundColor: Color(0xFF455A64),
                child: Icon(Icons.factory, color: Colors.white, size: 18),
              ),
            ),
            SizedBox(width: 12),
            Text('الموردون', style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey[200], height: 1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            tooltip: 'تحديث',
            onPressed: _loadSuppliers,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadSuppliers,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ⚡ أعمال الموردين في مكان واحد (كانت موزعة على المخزون والمحاسبة والتحصيل)
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _quickAction(Icons.outbox, 'دفعة لمورد', Colors.orange, () {
                              if (!requirePermission(context, AppPermissions.suppliers)) return;
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const SupplierPaymentScreen()))
                                  .then((_) => _loadSuppliers());
                            }),
                            _quickAction(Icons.shopping_cart_checkout, 'طلبات المشتريات', Colors.purple, () {
                              if (!requirePermission(context, AppPermissions.suppliers)) return;
                              Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const OrdersScreen(orderType: 'purchase')));
                            }),
                            _quickAction(Icons.assignment_return_outlined, 'مرتجع مشتريات', Colors.deepOrange, () {
                              if (!requirePermission(context, AppPermissions.suppliers)) return;
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseReturnEditorScreen()))
                                  .then((_) => _loadSuppliers());
                            }),
                            _quickAction(Icons.history, 'سجل مرتجعات المشتريات', Colors.blueGrey, () {
                              if (!requirePermission(context, AppPermissions.suppliers)) return;
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseReturnsListScreen()))
                                  .then((_) => _loadSuppliers());
                            }),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // STATS GRID
                        LayoutBuilder(builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final int crossAxisCount = width > 1200 ? 4 : (width > 800 ? 2 : 1);

                          return GridView(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              // ارتفاع ثابت يتسع لسطر الدولار الإضافي في أي عرض
                              mainAxisExtent: 132,
                            ),
                            children: [
                              StatCard(
                                title: 'إجمالي الديون علينا',
                                value: '${fmtMoney(debtIqd)} د.ع',
                                subValue: debtUsd > 0.01 ? '\$ ${fmtMoney(debtUsd)}' : null,
                                icon: Icons.monetization_on_outlined,
                                color: Colors.red,
                              ),
                              StatCard(
                                title: 'حجم المشتريات المؤكدة',
                                value: '${fmtMoney(purchasesIqd)} د.ع',
                                subValue: purchasesUsd > 0.01 ? '\$ ${fmtMoney(purchasesUsd)}' : null,
                                icon: Icons.shopping_bag_outlined,
                                color: Colors.blue,
                              ),
                              StatCard(
                                title: 'الفواتير المؤكدة',
                                value: fmtMoney(totalInvoices),
                                icon: Icons.receipt_long_outlined,
                                color: Colors.orange,
                              ),
                              StatCard(
                                title: 'عدد الموردين',
                                value: fmtMoney(_suppliers.length),
                                subValue: '${fmtMoney(_suppliers.where((s) => s.hasDebt).length)} لهم دين علينا',
                                icon: Icons.people_outline,
                                color: Colors.purple,
                              ),
                            ],
                          );
                        }),

                        const SizedBox(height: 32),

                        // SECTION TITLE + SEARCH
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 16,
                          runSpacing: 12,
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
                                  hintText: 'بحث بالاسم أو الهاتف أو العنوان...',
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
                        const SizedBox(height: 12),

                        // FILTER CHIPS
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _filterChip('all', 'الكل'),
                            _filterChip('with_debt', 'لهم دين علينا'),
                            _filterChip('no_debt', 'بدون دين'),
                            _filterChip('credit', 'لنا رصيد عندهم'),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // SUPPLIERS GRID
                        LayoutBuilder(builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          // عدد الأعمدة حسب أقل عرض مريح للبطاقة (كانت 3 أعمدة عند 700px
                          // فتضيق البطاقة ويتداخل محتواها)
                          final int fit = ((width + 16) / (SupplierRichCard.minWidth + 16)).floor();
                          final int crossAxisCount = fit < 1 ? 1 : (fit > 5 ? 5 : fit);

                          if (_filteredSuppliers.isEmpty) {
                            return _buildEmptyState();
                          }

                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              // ارتفاع ثابت بدل نسبة العرض: لا فيضان عند الشاشات الضيقة
                              mainAxisExtent: SupplierRichCard.preferredHeight,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: _filteredSuppliers.length,
                            itemBuilder: (context, index) {
                              // 🛡️ يُلتقط المورد لحظة البناء: القائمة قد تتغير (تحديث/بحث)
                              //    قبل الضغط، فالفهرس وحده قد يشير لمورد آخر أو يتجاوز الحد
                              final supplier = _filteredSuppliers[index];
                              return SupplierRichCard(
                                supplier: supplier,
                                onTap: () => _openSupplier(supplier),
                                onEdit: () => _editSupplier(supplier),
                                onDelete: () => _deleteSupplier(supplier),
                              );
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSupplier,
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        tooltip: 'إضافة مورد جديد',
        icon: const Icon(Icons.add),
        label: const Text('مورد جديد'),
      ),
    );
  }

  Widget _filterChip(String type, String label) {
    final count = _suppliers.where((s) => _matchesFilter(s, type)).length;
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: _filterType == type,
      onSelected: (_) {
        _filterType = type;
        _applyFilter();
      },
    );
  }

  Future<void> _openSupplier(Supplier supplier) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SupplierDetailsScreen(supplier: supplier)),
    );
    if (mounted) _loadSuppliers();
  }

  Future<void> _addSupplier() async {
    if (!requirePermission(context, AppPermissions.suppliers)) return;
    final saved = await showSupplierFormDialog(context);
    if (saved != null && mounted) _loadSuppliers();
  }

  Future<void> _editSupplier(Supplier supplier) async {
    if (!requirePermission(context, AppPermissions.suppliers)) return;
    final saved = await showSupplierFormDialog(context, supplier: supplier);
    if (saved != null && mounted) _loadSuppliers();
  }

  Future<void> _deleteSupplier(Supplier supplier) async {
    if (!requirePermission(context, AppPermissions.suppliers)) return;
    final deleted = await confirmAndDeleteSupplier(context, supplier);
    if (deleted && mounted) _loadSuppliers();
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text(_loadError ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _isLoading = true);
                _loadSuppliers();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final noSuppliers = _suppliers.isEmpty;
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
          Icon(noSuppliers ? Icons.store_mall_directory_outlined : Icons.search_off, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            noSuppliers ? 'لا يوجد موردون بعد' : 'لا توجد نتائج',
            style: TextStyle(fontSize: 18, color: Colors.grey[500], fontWeight: FontWeight.bold),
          ),
          if (noSuppliers) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _addSupplier,
              icon: const Icon(Icons.add),
              label: const Text('إضافة أول مورد'),
            ),
          ],
        ],
      ),
    );
  }
}
