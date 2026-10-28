// lib/screens/suppliers/suppliers_dashboard_screen.dart
//
// 🏭 مركز الموردين: مؤشرات في الرأس (ما علينا، ما لنا، المشتريات)، أزرار
// إجراءات ظاهرة (فاتورة شراء، دفعة، مرتجع، سجل الفواتير، الطلبات، المرتجعات)،
// ثم بطاقات الموردين مع بحث وفلترة بالرصيد وترتيب.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../erp/debts/receipt_screen.dart' show SupplierPaymentScreen;
import '../../erp/erp_ui.dart';
import '../../erp/purchases/purchase_register_screen.dart';
import '../../erp/purchases/purchase_return_screen.dart' show PurchaseReturnEditorScreen, PurchaseReturnsListScreen;
import '../../erp/purchases/supplier_statement_screen.dart';
import '../../erp/sales/quotes_orders_screen.dart' show OrdersScreen;
import '../../models/app_user.dart' show AppPermissions;
import '../../models/supplier.dart';
import '../../services/purchase_service.dart';
import '../../theme/ui_tokens.dart' show UiColors;
import '../create_purchase_invoice_screen.dart';
import '../../owner/owner_access.dart';
import '../../owner/ai_invoice/ai_purchase_invoice_screen.dart';
import '../supplier_details_screen.dart';
import 'supplier_ui.dart';

class SuppliersDashboardScreen extends StatefulWidget {
  const SuppliersDashboardScreen({super.key});

  @override
  State<SuppliersDashboardScreen> createState() => _SuppliersDashboardScreenState();
}

class _SuppliersDashboardScreenState extends State<SuppliersDashboardScreen> {
  final _searchController = TextEditingController();
  List<Supplier> _suppliers = [];
  Map<String, double> _purchaseTotals = const {};
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _loadError;
  String _filterType = 'all'; // all, with_debt, no_debt, credit
  String _sort = 'name'; // name, debt, recent, invoices

  static const _sorts = {
    'name': 'الاسم',
    'debt': 'الأعلى ديناً علينا',
    'recent': 'الأحدث إضافة',
    'invoices': 'الأكثر فواتير',
  };

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
        // مؤشر ثانوي: فشله لا يمنع عرض الموردين
      }
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
        _purchaseTotals = totals;
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

  bool _matchesFilter(Supplier s, String type) => switch (type) {
        'with_debt' => s.hasDebt,
        'no_debt' => !s.hasDebt && !_hasCredit(s),
        'credit' => _hasCredit(s),
        _ => true,
      };

  List<Supplier> get _shown {
    final query = _searchController.text.trim().toLowerCase();
    final list = _suppliers.where((s) {
      final matchesSearch = query.isEmpty ||
          s.name.toLowerCase().contains(query) ||
          (s.phone ?? '').contains(query) ||
          (s.address ?? '').toLowerCase().contains(query);
      return matchesSearch && _matchesFilter(s, _filterType);
    }).toList();
    switch (_sort) {
      case 'debt':
        list.sort((a, b) => b.totalDebtIqd.compareTo(a.totalDebtIqd));
      case 'recent':
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case 'invoices':
        list.sort((a, b) => b.totalInvoices.compareTo(a.totalInvoices));
      default:
        list.sort((a, b) => a.name.compareTo(b.name));
    }
    return list;
  }

  Future<void> _push(Widget screen) async {
    if (!requirePermission(context, AppPermissions.suppliers)) return;
    await Navigator.push(context, accRoute<void>(screen));
    if (mounted) _loadSuppliers();
  }

  Widget _headerStats() {
    final debtIqd = _suppliers.fold(0.0, (sum, s) => sum + (s.totalDebtIqd > 0 ? s.totalDebtIqd : 0.0));
    final debtUsd = _suppliers.fold(0.0, (sum, s) => sum + (s.totalDebtUsd > 0 ? s.totalDebtUsd : 0.0));
    final creditIqd = _suppliers.fold(0.0, (sum, s) => sum + (s.totalDebtIqd < 0 ? -s.totalDebtIqd : 0.0));
    final creditUsd = _suppliers.fold(0.0, (sum, s) => sum + (s.totalDebtUsd < 0 ? -s.totalDebtUsd : 0.0));
    final owing = _suppliers.where((s) => s.hasDebt).length;
    return Wrap(spacing: 10, runSpacing: 8, children: [
      HeaderStat(
        label: 'علينا للموردين',
        value: supTotals({'IQD': debtIqd, 'USD': debtUsd}),
        icon: Icons.north_east_rounded,
        accent: const Color(0xFFFCA5A5),
        tooltip: 'مجموع الأرصدة الموجبة (ما يجب أن ندفعه)',
      ),
      if (creditIqd > 0.01 || creditUsd > 0.01)
        HeaderStat(
          label: 'لنا عند الموردين',
          value: supTotals({'IQD': creditIqd, 'USD': creditUsd}),
          icon: Icons.south_west_rounded,
          accent: const Color(0xFF86EFAC),
          tooltip: 'دفعنا أكثر من المستحق أو مرتجعات لم تُسترد',
        ),
      HeaderStat(
        label: 'المشتريات المؤكدة',
        value: supTotals(_purchaseTotals),
        icon: Icons.shopping_bag_rounded,
        accent: const Color(0xFF93C5FD),
      ),
      HeaderStat(
        label: 'الموردون',
        value: '${_suppliers.length}',
        icon: Icons.storefront_rounded,
        tooltip: '$owing منهم لهم دين علينا',
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'الموردون',
      subtitle: 'الأرصدة والفواتير والدفعات في مكان واحد',
      icon: Icons.local_shipping_rounded,
      actions: [
        IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: 'تحديث', onPressed: _loadSuppliers),
      ],
      headerExtra: _isLoading || _loadError != null
          ? null
          : Align(alignment: AlignmentDirectional.centerStart, child: _headerStats()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSupplier,
        backgroundColor: supplierAccent,
        tooltip: 'إضافة مورد جديد',
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('مورد جديد'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildErrorState()
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: RefreshIndicator(
                      onRefresh: _loadSuppliers,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        children: [
                          _sectionTitle('إجراءات سريعة', Icons.bolt_rounded),
                          const SizedBox(height: 10),
                          SupActionGrid(children: [
                            SupActionCard(
                              icon: Icons.note_add_rounded,
                              label: 'فاتورة شراء جديدة',
                              subtitle: 'اختر المورد داخل الفاتورة',
                              color: const Color(0xFF2563EB),
                              onTap: () => _push(const CreatePurchaseInvoiceScreen()),
                            ),
                            // 👑 حساب المالك فقط
                            if (OwnerAccess.enabled)
                              SupActionCard(
                                icon: Icons.auto_awesome_rounded,
                                label: 'فاتورة بالذكاء الاصطناعي',
                                subtitle: 'يقرأ فاتورة المورد ويطابق المواد',
                                color: const Color(0xFF4F46E5),
                                onTap: () => _push(const AiPurchaseInvoiceScreen()),
                              ),
                            SupActionCard(
                              icon: Icons.payments_rounded,
                              label: 'دفعة لمورد',
                              subtitle: 'نقد، تحويل، شيك، خصم',
                              color: supCredit,
                              onTap: () => _push(const SupplierPaymentScreen()),
                            ),
                            SupActionCard(
                              icon: Icons.assignment_return_rounded,
                              label: 'مرتجع مشتريات',
                              subtitle: 'إرجاع بضاعة لمورد',
                              color: const Color(0xFFEA580C),
                              onTap: () => _push(const PurchaseReturnEditorScreen()),
                            ),
                            SupActionCard(
                              icon: Icons.receipt_long_rounded,
                              label: 'سجل فواتير الشراء',
                              subtitle: 'كل الموردين، بفترة وتصدير',
                              color: AccColors.navy,
                              onTap: () => _push(const PurchaseRegisterScreen()),
                            ),
                            SupActionCard(
                              icon: Icons.shopping_cart_checkout_rounded,
                              label: 'طلبات الشراء',
                              subtitle: 'طلب تلقائي للنواقص',
                              color: const Color(0xFF7C3AED),
                              onTap: () => _push(const OrdersScreen(orderType: 'purchase')),
                            ),
                            SupActionCard(
                              icon: Icons.history_rounded,
                              label: 'سجل المرتجعات',
                              subtitle: 'عرض، طباعة، إلغاء',
                              color: const Color(0xFF64748B),
                              onTap: () => _push(const PurchaseReturnsListScreen()),
                            ),
                          ]),
                          const SizedBox(height: 22),
                          Row(children: [
                            Expanded(child: _sectionTitle('الموردون (${_suppliers.length})', Icons.storefront_rounded)),
                            _sortButton(),
                          ]),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: 340,
                                child: SearchBox(
                                  controller: _searchController,
                                  hint: 'بحث بالاسم أو الهاتف أو العنوان…',
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              _filterPill('all', 'الكل', Icons.apps_rounded, AccColors.navy),
                              _filterPill('with_debt', 'لهم دين علينا', Icons.north_east_rounded, supOwe),
                              _filterPill('credit', 'لنا رصيد عندهم', Icons.south_west_rounded, supCredit),
                              _filterPill('no_debt', 'بلا رصيد', Icons.check_circle_outline_rounded, AccColors.muted),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _suppliersGrid(),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _sectionTitle(String t, IconData icon) => Row(children: [
        Icon(icon, size: 19, color: AccColors.navy),
        const SizedBox(width: 8),
        Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AccColors.text)),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: Color(0xFFE3E9F1))),
      ]);

  Widget _sortButton() => Padding(
        padding: const EdgeInsetsDirectional.only(start: 10),
        child: PopupMenuButton<String>(
          tooltip: 'ترتيب',
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) => [
            for (final e in _sorts.entries)
              CheckedPopupMenuItem(value: e.key, checked: _sort == e.key, child: Text(e.value)),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ErpColors.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.sort_rounded, size: 18, color: AccColors.navy),
              const SizedBox(width: 6),
              Text('ترتيب: ${_sorts[_sort]}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
          ),
        ),
      );

  Widget _filterPill(String type, String label, IconData icon, Color color) {
    final count = _suppliers.where((s) => _matchesFilter(s, type)).length;
    final sel = _filterType == type;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _filterType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: sel ? color : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? color : ErpColors.border),
            boxShadow: sel ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))] : const [],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: sel ? Colors.white : color),
            const SizedBox(width: 6),
            Text('$label ($count)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  color: sel ? Colors.white : ErpColors.text,
                )),
          ]),
        ),
      ),
    );
  }

  Widget _suppliersGrid() {
    final list = _shown;
    if (list.isEmpty) return _buildEmptyState();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        mainAxisExtent: 172,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: list.length,
      itemBuilder: (context, index) {
        // 🛡️ يُلتقط المورد لحظة البناء: القائمة قد تتغير قبل الضغط
        final s = list[index];
        final card = _SupplierCard(
          supplier: s,
          onTap: () => _openSupplier(s),
          onEdit: () => _editSupplier(s),
          onDelete: () => _deleteSupplier(s),
          onStatement: s.id == null
              ? null
              : () => _push(SupplierStatementScreen(supplierId: s.id!, supplierName: s.name)),
        );
        return index < 16 ? FadeSlideIn(key: ValueKey(s.id), index: index, child: card) : card;
      },
    );
  }

  Future<void> _openSupplier(Supplier supplier) async {
    await Navigator.push(context, accRoute<void>(SupplierDetailsScreen(supplier: supplier)));
    if (mounted) _loadSuppliers();
  }

  Future<void> _addSupplier() async {
    if (!requirePermission(context, AppPermissions.suppliers)) return;
    final saved = await showSupplierFormDialog(context);
    if (saved != null && mounted) {
      showOk(context, 'أُضيف المورد «${saved.name}»');
      _loadSuppliers();
    }
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
            const Icon(Icons.error_outline_rounded, size: 56, color: supOwe),
            const SizedBox(height: 12),
            Text(_loadError ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _isLoading = true);
                _loadSuppliers();
              },
              icon: const Icon(Icons.refresh_rounded),
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
      height: 260,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ErpColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(noSuppliers ? Icons.store_mall_directory_outlined : Icons.search_off_rounded,
              size: 60, color: ErpColors.muted.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(
            noSuppliers ? 'لا يوجد موردون بعد' : 'لا توجد نتائج مطابقة',
            style: const TextStyle(fontSize: 17, color: ErpColors.muted, fontWeight: FontWeight.w700),
          ),
          if (noSuppliers) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: supplierAccent),
              onPressed: _addSupplier,
              icon: const Icon(Icons.add_business_rounded),
              label: const Text('إضافة أول مورد'),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════ بطاقة مورد ═══════════════════════════

class _SupplierCard extends StatefulWidget {
  const _SupplierCard({
    required this.supplier,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.onStatement,
  });
  final Supplier supplier;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onStatement;

  @override
  State<_SupplierCard> createState() => _SupplierCardState();
}

class _SupplierCardState extends State<_SupplierCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.supplier;
    final tint = UiColors.tint(s.id);
    final phone = (s.phone ?? '').trim();
    final balances = supBalances(s);
    final main = balances.first;
    final mainColor = supBalanceColor(main.$2);
    final terms = s.paymentTerms == 'credit' ? (s.creditDays > 0 ? 'آجل ${s.creditDays} يوم' : 'آجل') : 'نقدي';

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _hover ? tint.withValues(alpha: 0.20) : const Color(0x0A0F172A),
              blurRadius: _hover ? 20 : 8,
              offset: Offset(0, _hover ? 9 : 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: _hover ? tint.withValues(alpha: 0.5) : ErpColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(height: 4, color: mainColor.withValues(alpha: main.$2.abs() > 0.01 ? 0.85 : 0.25)),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 4, 6),
                child: Row(children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: tint.withValues(alpha: 0.14),
                    child: Text(supInitial(s.name),
                        style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: 17)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: ErpColors.text)),
                      const SizedBox(height: 2),
                      Row(children: [
                        Flexible(
                          child: Text(phone.isEmpty ? 'بلا هاتف' : phone,
                              maxLines: 1,
                              textDirection: TextDirection.ltr,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
                        ),
                        const SizedBox(width: 6),
                        StatusBadge(terms, color: supplierAccent),
                      ]),
                    ]),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'إجراءات',
                    icon: const Icon(Icons.more_vert_rounded, color: ErpColors.muted),
                    onSelected: (v) {
                      switch (v) {
                        case 'edit':
                          widget.onEdit();
                        case 'delete':
                          widget.onDelete();
                        case 'statement':
                          widget.onStatement?.call();
                        case 'copy':
                          Clipboard.setData(ClipboardData(text: phone));
                          showOk(context, 'نُسخ الرقم $phone');
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'edit', child: ListTile(dense: true, leading: Icon(Icons.edit_rounded), title: Text('تعديل'))),
                      if (widget.onStatement != null)
                        const PopupMenuItem(
                            value: 'statement',
                            child: ListTile(dense: true, leading: Icon(Icons.list_alt_rounded), title: Text('كشف الحساب'))),
                      if (phone.isNotEmpty)
                        const PopupMenuItem(
                            value: 'copy',
                            child: ListTile(dense: true, leading: Icon(Icons.copy_rounded), title: Text('نسخ رقم الهاتف'))),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.delete_outline_rounded, color: supOwe),
                          title: Text('حذف', style: TextStyle(color: supOwe)),
                        ),
                      ),
                    ],
                  ),
                ]),
              ),
              const Spacer(),
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: mainColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(supBalanceCaption(main.$2), style: TextStyle(fontSize: 11.5, color: mainColor)),
                      Text(
                        supMoney(main.$2.abs(), main.$1),
                        textDirection: TextDirection.ltr,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: mainColor),
                      ),
                      if (balances.length > 1)
                        Text(
                          '${supBalanceCaption(balances[1].$2)}: ${supMoney(balances[1].$2.abs(), balances[1].$1)}',
                          style: TextStyle(fontSize: 11.5, color: supBalanceColor(balances[1].$2)),
                        ),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${s.totalInvoices}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: ErpColors.text)),
                    const Text('فاتورة', style: TextStyle(fontSize: 11, color: ErpColors.muted)),
                  ]),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${s.totalPayments}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: ErpColors.text)),
                    const Text('دفعة', style: TextStyle(fontSize: 11, color: ErpColors.muted)),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
