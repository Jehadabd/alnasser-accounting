import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/supplier.dart';
import '../models/purchase_invoice.dart';
import '../models/supplier_payment.dart';
import '../models/supplier_delegate.dart';
import '../services/purchase_service.dart';
import '../services/suppliers_service.dart';
import 'create_purchase_invoice_screen.dart';
import '../erp/debts/receipt_screen.dart' show SupplierPaymentScreen;
import '../erp/pickers.dart' show PartyLite;
import '../erp/purchases/purchase_return_screen.dart' show PurchaseReturnEditorScreen;
import '../erp/purchases/supplier_statement_screen.dart';
import '../erp/erp_common.dart' show parseMoney;
import '../accounting/screens/acc_ui.dart' show fmtMoney, fmtDate, PeriodBar;
import 'invoice_details_split_screen.dart';
import 'delegate_details_screen.dart';

// ═══════════════════════════ مساعدات عرض مشتركة ═══════════════════════════

String _curLabel(String currency) => currency == 'USD' ? '\$' : 'د.ع';

/// مبلغ بفواصل الآلاف ورمز عملته (الدولار يحتفظ بكسوره).
String _money(double v, String currency) => '${fmtMoney(v)} ${_curLabel(currency)}';

/// سطور رصيد المورد بالعملتين — دينه يُحسب لكل عملة على حدة، فعرض عملته
/// المفضلة وحدها كان يُخفي ديناً بالعملة الأخرى.
List<String> _balanceLines(Supplier s) {
  final lines = <String>[];
  if (s.totalDebtIqd.abs() > 0.01) lines.add(_money(s.totalDebtIqd, 'IQD'));
  if (s.totalDebtUsd.abs() > 0.01) lines.add(_money(s.totalDebtUsd, 'USD'));
  if (lines.isEmpty) lines.add(_money(0, s.currency));
  return lines;
}

/// مجموع لكل عملة كنص: «1,000 د.ع + 50 $».
String _totalsText(Map<String, double> byCurrency) {
  final parts = <String>[
    for (final e in byCurrency.entries)
      if (e.value.abs() > 0.004) _money(e.value, e.key),
  ];
  return parts.isEmpty ? '0' : parts.join(' + ');
}

String _methodLabel(String method) {
  switch (method) {
    case 'cash':
      return 'نقداً';
    case 'bank':
      return 'تحويل بنكي';
    case 'transfer':
      return 'حوالة';
    case 'cheque':
      return 'شيك';
    case 'discount':
      return 'خصم مكتسب';
    default:
      return method;
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'draft':
      return Colors.grey;
    case 'confirmed':
      return Colors.blue;
    case 'partial':
      return Colors.orange;
    case 'paid':
      return Colors.green;
    case 'cancelled':
      return Colors.red;
    default:
      return Colors.blue;
  }
}

String _initial(String name) {
  final t = name.trim();
  return t.isEmpty ? '?' : t[0].toUpperCase();
}

Widget _iconBox(Widget child, Color color) {
  return Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
    child: child,
  );
}

Widget _invoiceTile(PurchaseInvoice invoice, VoidCallback? onTap) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey[100]!),
    ),
    child: ListTile(
      leading: _iconBox(Icon(Icons.receipt_long, color: Colors.blue[700]), Colors.blue[50]!),
      title: Text('فاتورة #${invoice.invoiceNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text([
        fmtDate(invoice.date),
        if (invoice.paidAmount > 0.004) 'الواصل: ${_money(invoice.paidAmount, invoice.currency)}',
      ].join('  •  ')),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_money(invoice.totalAmount, invoice.currency), style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(invoice.statusArabic, style: TextStyle(fontSize: 11, color: _statusColor(invoice.status))),
        ],
      ),
      onTap: onTap,
    ),
  );
}

Widget _paymentTile(SupplierPayment payment) {
  final notes = (payment.notes ?? '').trim();
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: ListTile(
      leading: _iconBox(const Icon(Icons.check, color: Colors.green), Colors.green[50]!),
      title: Text(
        payment.receiptNumber != null ? 'سند دفع رقم ${payment.receiptNumber}' : 'دفعة للمورد',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        [fmtDate(payment.date), _methodLabel(payment.paymentMethod), if (notes.isNotEmpty) notes].join('  •  '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _money(payment.amount, payment.currency),
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
      ),
    ),
  );
}

// ═══════════════════════════ إضافة / تعديل / حذف مورد ═══════════════════════════

/// نافذة إضافة مورد أو تعديل بياناته (الاسم، الهاتف، العنوان، العملة، شروط الدفع،
/// الملاحظات). تعيد المورد المحفوظ (بمعرّفه) أو null عند الإلغاء.
///
/// التعديل يمرّ عبر PurchaseService.updateSupplier الذي لا يلمس الرصيد ولا
/// العدّادات (يملكها دفتر المورد وحده).
Future<Supplier?> showSupplierFormDialog(BuildContext context, {Supplier? supplier}) {
  return showDialog<Supplier>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SupplierFormDialog(supplier: supplier),
  );
}

class _SupplierFormDialog extends StatefulWidget {
  const _SupplierFormDialog({this.supplier});
  final Supplier? supplier;

  @override
  State<_SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<_SupplierFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _notes;
  late final TextEditingController _creditDays;
  late String _currency;
  late String _terms;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.supplier != null;

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _name = TextEditingController(text: s?.name ?? '');
    _phone = TextEditingController(text: s?.phone ?? '');
    _address = TextEditingController(text: s?.address ?? '');
    _notes = TextEditingController(text: s?.notes ?? '');
    _creditDays = TextEditingController(text: (s != null && s.creditDays > 0) ? '${s.creditDays}' : '');
    // 🛡️ قيمة خارج عناصر القائمة تُسقط DropdownButton بخطأ assertion
    _currency = s?.currency == 'USD' ? 'USD' : 'IQD';
    _terms = s?.paymentTerms == 'credit' ? 'credit' : 'cash';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    _creditDays.dispose();
    super.dispose();
  }

  String? _clean(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'الرجاء إدخال اسم المورد');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final service = context.read<PurchaseService>();
    final old = widget.supplier;
    try {
      final all = await service.getSuppliers();
      final duplicate = all.any((s) => s.id != old?.id && s.name.trim() == name);
      if (duplicate) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = 'يوجد مورد آخر بالاسم «$name» — استخدم اسماً مميِّزاً';
        });
        return;
      }
      final now = DateTime.now();
      final days = _terms == 'credit' ? (parseMoney(_creditDays.text) ?? 0).round() : 0;
      final data = Supplier(
        id: old?.id,
        name: name,
        phone: _clean(_phone),
        address: _clean(_address),
        currency: _currency,
        paymentTerms: _terms,
        creditDays: days < 0 ? 0 : days,
        notes: _clean(_notes),
        // الأرصدة والعدّادات للعرض فقط — updateSupplier لا يكتبها
        totalDebtIqd: old?.totalDebtIqd ?? 0.0,
        totalDebtUsd: old?.totalDebtUsd ?? 0.0,
        totalPurchases: old?.totalPurchases ?? 0.0,
        currentBalance: old?.currentBalance ?? 0.0,
        totalInvoices: old?.totalInvoices ?? 0,
        totalPayments: old?.totalPayments ?? 0,
        createdAt: old?.createdAt ?? now,
        updatedAt: now,
      );
      Supplier saved;
      if (old == null) {
        final id = await service.addSupplier(data);
        saved = data.copyWith(id: id);
      } else {
        await service.updateSupplier(data);
        saved = data;
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'تعذّر الحفظ: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(_isEdit ? Icons.edit : Icons.person_add, color: const Color(0xFF455A64)),
          const SizedBox(width: 8),
          Expanded(child: Text(_isEdit ? 'تعديل بيانات المورد' : 'إضافة مورد جديد')),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: !_isEdit,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'اسم المورد *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _currency,
                decoration: InputDecoration(
                  labelText: 'العملة المفضلة',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.attach_money),
                  helperText: _isEdit
                      ? 'تغييرها لا يحوّل الأرصدة: رصيد الدينار ورصيد الدولار يبقيان كما هما'
                      : 'العملة الافتراضية لفواتير هذا المورد',
                  helperMaxLines: 2,
                ),
                items: const [
                  DropdownMenuItem(value: 'IQD', child: Text('IQD - دينار عراقي')),
                  DropdownMenuItem(value: 'USD', child: Text('USD - دولار أمريكي')),
                ],
                onChanged: _saving ? null : (v) => setState(() => _currency = v ?? 'IQD'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _terms,
                decoration: const InputDecoration(
                  labelText: 'شروط الدفع',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.payment),
                ),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                  DropdownMenuItem(value: 'credit', child: Text('آجل')),
                ],
                onChanged: _saving ? null : (v) => setState(() => _terms = v ?? 'cash'),
              ),
              if (_terms == 'credit') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _creditDays,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'مدة الآجل (بالأيام)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.timer_outlined),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF455A64),
            foregroundColor: Colors.white,
          ),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save),
          label: Text(_isEdit ? 'حفظ التعديلات' : 'إضافة'),
        ),
      ],
    );
  }
}

/// حذف مورد بعد التأكيد. يُمنع الحذف (برسالة واضحة) إن كان للمورد أي فاتورة أو
/// دفعة أو مرتجع أو رصيد غير صفري. يعيد true إن حُذف فعلاً.
Future<bool> confirmAndDeleteSupplier(BuildContext context, Supplier supplier) async {
  final id = supplier.id;
  if (id == null) return false;
  final service = context.read<PurchaseService>();
  final messenger = ScaffoldMessenger.of(context);

  String? blocker;
  try {
    blocker = await service.supplierDeleteBlocker(id);
  } catch (e) {
    blocker = 'تعذّر التحقق من ارتباطات المورد، لذلك لم يُحذف: $e';
  }
  if (!context.mounted) return false;

  if (blocker != null) {
    final msg = blocker;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.block, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text('لا يمكن حذف المورد')),
          ],
        ),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً')),
        ],
      ),
    );
    return false;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.delete_forever, color: Colors.red),
          SizedBox(width: 8),
          Expanded(child: Text('حذف المورد')),
        ],
      ),
      content: Text(
        'هل تريد حذف المورد «${supplier.name}» نهائياً؟\n'
        'ليس عليه فواتير أو دفعات أو رصيد، ولا يمكن التراجع عن الحذف.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  if (ok != true) return false;

  try {
    await service.deleteSupplier(id);
    messenger.showSnackBar(SnackBar(
      content: Text('تم حذف المورد «${supplier.name}»'),
      backgroundColor: Colors.green,
    ));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    return false;
  }
}

// ═══════════════════════════ صفحة المورد ═══════════════════════════

class SupplierDetailsScreen extends StatefulWidget {
  final Supplier supplier;

  const SupplierDetailsScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailsScreen> createState() => _SupplierDetailsScreenState();
}

class _SupplierDetailsScreenState extends State<SupplierDetailsScreen> {
  static const int _recentCount = 5;

  late Supplier _supplier;
  List<PurchaseInvoice> _invoices = [];
  List<SupplierPayment> _payments = [];
  List<SupplierDelegate> _delegates = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _supplier = widget.supplier;
    _loadData();
  }

  Future<void> _loadData() async {
    final id = _supplier.id;
    if (id == null) {
      setState(() {
        _isLoading = false;
        _error = 'هذا المورد غير محفوظ بعد';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final purchaseService = context.read<PurchaseService>();
    final suppliersService = context.read<SuppliersService>();
    try {
      final invoices = await purchaseService.getInvoicesForSupplier(id);
      final payments = await purchaseService.getPaymentsForSupplier(id);
      List<SupplierDelegate> delegates = const [];
      try {
        delegates = await suppliersService.getDelegates(id);
      } catch (_) {
        // المندوبون ميزة ثانوية: فشلها لا يمنع عرض حساب المورد
      }
      final fresh = await purchaseService.getSupplierById(id);
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _payments = payments;
        _delegates = delegates;
        if (fresh != null) _supplier = fresh;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'تعذّر تحميل بيانات المورد: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Slate 50
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          if (_isLoading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            SliverFillRemaining(hasScrollBody: false, child: _buildError())
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatsGrid(),
                    if ((_supplier.address ?? '').trim().isNotEmpty ||
                        (_supplier.notes ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildInfoCard(),
                    ],
                    const SizedBox(height: 32),

                    _buildSectionHeader(
                      'المندوبين',
                      Icons.people_outline,
                      action: TextButton.icon(
                        onPressed: _showAddDelegateDialog,
                        icon: const Icon(Icons.add_circle_outline, size: 16),
                        label: const Text('إضافة مندوب'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDelegatesList(),
                    const SizedBox(height: 32),

                    _buildSectionHeader(
                      'آخر الفواتير',
                      Icons.receipt_long_outlined,
                      action: _invoices.isEmpty
                          ? null
                          : TextButton.icon(
                              onPressed: () => _openAllDocs(0),
                              icon: const Icon(Icons.list_alt, size: 16),
                              label: Text('عرض الكل (${_invoices.length})'),
                            ),
                    ),
                    const SizedBox(height: 16),
                    _buildRecentInvoicesList(),
                    const SizedBox(height: 32),

                    _buildSectionHeader(
                      'سجل المدفوعات',
                      Icons.payment_outlined,
                      action: _payments.isEmpty
                          ? null
                          : TextButton.icon(
                              onPressed: () => _openAllDocs(1),
                              icon: const Icon(Icons.list_alt, size: 16),
                              label: Text('عرض الكل (${_payments.length})'),
                            ),
                    ),
                    const SizedBox(height: 16),
                    _buildRecentPaymentsList(),
                    const SizedBox(height: 80), // مساحة للزر العائم
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _error != null ? null : _buildFAB(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    final phone = (_supplier.phone ?? '').trim();
    return SliverAppBar(
      expandedHeight: 200.0,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF0F172A)),
            Positioned(
              right: -50,
              top: -50,
              child: Icon(Icons.business, size: 200, color: Colors.white.withOpacity(0.05)),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: CircleAvatar(
                          radius: 32,
                          backgroundColor: const Color(0xFF3B82F6),
                          child: Text(
                            _initial(_supplier.name),
                            style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _supplier.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (phone.isNotEmpty)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.phone, size: 14, color: Colors.grey[400]),
                                      const SizedBox(width: 4),
                                      Text(phone, style: TextStyle(color: Colors.grey[400])),
                                    ],
                                  ),
                                _headerChip(_supplier.paymentTerms == 'credit'
                                    ? (_supplier.creditDays > 0 ? 'آجل ${_supplier.creditDays} يوم' : 'آجل')
                                    : 'نقدي'),
                                _headerChip(_supplier.currency == 'USD' ? 'دولار' : 'دينار'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit, color: Colors.white),
          tooltip: 'تعديل بيانات المورد',
          onPressed: _editSupplier,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.white),
          tooltip: 'حذف المورد',
          onPressed: _deleteSupplier,
        ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          tooltip: 'تحديث',
          onPressed: _loadData,
        ),
      ],
    );
  }

  Widget _headerChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  Widget _buildStatsGrid() {
    final balance = _balanceLines(_supplier);
    final owes = _supplier.hasDebt;
    final credit = _supplier.totalDebtIqd < -0.01 || _supplier.totalDebtUsd < -0.01;
    final purchases = <String, double>{};
    for (final inv in _invoices) {
      if (inv.status != 'confirmed') continue;
      purchases[inv.currency] = (purchases[inv.currency] ?? 0) + inv.totalAmount;
    }
    final paid = <String, double>{};
    for (final p in _payments) {
      paid[p.currency] = (paid[p.currency] ?? 0) + p.amount;
    }
    final String balanceSub = balance.length > 1
        ? balance[1]
        : (owes ? 'مستحق للمورد' : (credit ? 'رصيد لنا عنده' : 'لا يوجد دين'));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildStatBox(
            'الرصيد الكلي',
            balance.first,
            Icons.account_balance_wallet,
            owes ? Colors.red : Colors.green,
            sub: balanceSub,
            valueColor: owes ? Colors.red[700] : null,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatBox(
            'الفواتير',
            '${_invoices.length}',
            Icons.receipt_long,
            Colors.blue,
            sub: 'المؤكدة: ${_totalsText(purchases)}',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatBox(
            'المدفوعات',
            '${_payments.length}',
            Icons.payments,
            Colors.purple,
            sub: 'المدفوع: ${_totalsText(paid)}',
          ),
        ),
      ],
    );
  }

  Widget _buildStatBox(String title, String value, IconData icon, Color color, {String? sub, Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'Segoe UI',
                color: valueColor ?? const Color(0xFF1E293B),
              ),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          ],
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final address = (_supplier.address ?? '').trim();
    final notes = (_supplier.notes ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (address.isNotEmpty)
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(child: Text(address)),
              ],
            ),
          if (address.isNotEmpty && notes.isNotEmpty) const SizedBox(height: 8),
          if (notes.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(child: Text(notes, style: TextStyle(color: Colors.grey[800]))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, {Widget? action}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        const Spacer(),
        if (action != null) action,
      ],
    );
  }

  Widget _buildDelegatesList() {
    if (_delegates.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text('لا يوجد مندوبين مرتبطين', style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }

    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _delegates.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final delegate = _delegates[index];
          final phone = (delegate.phone ?? '').trim();
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DelegateDetailsScreen(delegate: delegate),
                ),
              );
            },
            child: Container(
              width: 130,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.blue[50],
                    child: Text(_initial(delegate.name),
                        style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Text(delegate.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  if (phone.isNotEmpty)
                    Text(phone, maxLines: 1, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentInvoicesList() {
    if (_invoices.isEmpty) {
      return const Center(child: Text('لا توجد فواتير بعد'));
    }
    final recent = _invoices.take(_recentCount).toList();
    return Column(
      children: [
        for (final invoice in recent)
          _invoiceTile(invoice, invoice.id == null ? null : () => _openInvoice(invoice.id!)),
        if (_invoices.length > _recentCount)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => _openAllDocs(0),
              child: Text('+ ${_invoices.length - _recentCount} فاتورة أخرى — عرض الكل'),
            ),
          ),
      ],
    );
  }

  Widget _buildRecentPaymentsList() {
    if (_payments.isEmpty) return const Center(child: Text('لا توجد مدفوعات'));
    final recent = _payments.take(_recentCount).toList();
    return Column(
      children: [
        for (final payment in recent) _paymentTile(payment),
        if (_payments.length > _recentCount)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => _openAllDocs(1),
              child: Text('+ ${_payments.length - _recentCount} دفعة أخرى — عرض الكل'),
            ),
          ),
      ],
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: () {
        // 🛡️ كل الانتقالات تستخدم سياق الشاشة لا سياق اللوحة السفلية
        //    (الذي يُزال مع إغلاقها).
        showModalBottomSheet<void>(
          context: context,
          builder: (sheetCtx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.note_add),
                  title: const Text('إنشاء فاتورة شراء'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _createInvoice();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.payment),
                  title: const Text('دفعة لمورد'),
                  subtitle: const Text('نقداً أو بشيك أو خصم، من صندوق محدد'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _registerPayment();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.assignment_return_outlined),
                  title: const Text('مرتجع مشتريات'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _purchaseReturn();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.list_alt),
                  title: const Text('كشف حساب المورد'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _openStatement();
                  },
                ),
              ],
            ),
          ),
        );
      },
      icon: const Icon(Icons.add),
      label: const Text('إجراء جديد'),
      backgroundColor: const Color(0xFF0F172A),
      foregroundColor: Colors.white,
    );
  }

  void _showAddDelegateDialog() {
    final supplierId = _supplier.id;
    if (supplierId == null) return;
    final service = context.read<SuppliersService>();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    bool saving = false;
    String? error;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('إضافة مندوب جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'اسم المندوب *',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'رقم الهاتف (اختياري)', border: OutlineInputBorder()),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        setDialogState(() => error = 'أدخل اسم المندوب');
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      final phone = phoneController.text.trim();
                      try {
                        await service.addDelegate(SupplierDelegate(
                          supplierId: supplierId,
                          name: name,
                          phone: phone.isEmpty ? null : phone,
                        ));
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        if (mounted) _loadData();
                      } catch (e) {
                        if (dialogCtx.mounted) {
                          setDialogState(() {
                            saving = false;
                            error = 'تعذّر الحفظ: $e';
                          });
                        }
                      }
                    },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  PartyLite _party(int id) =>
      PartyLite(id, _supplier.name, _supplier.phone, _supplier.totalDebtIqd, balanceUsd: _supplier.totalDebtUsd);

  Future<void> _openInvoice(int invoiceId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceDetailsSplitScreen(invoiceId: invoiceId)),
    );
    // قد تكون الفاتورة عُدّلت من شاشة التفاصيل ⇒ الرصيد تغيّر
    if (mounted) _loadData();
  }

  Future<void> _openAllDocs(int tab) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SupplierDocumentsScreen(supplier: _supplier, initialTab: tab)),
    );
    if (mounted) _loadData();
  }

  Future<void> _createInvoice() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePurchaseInvoiceScreen(preselectedSupplier: _supplier),
      ),
    );
    if (mounted) _loadData();
  }

  // 💸 طريق واحد لدفعة المورد: شاشة «دفعة لمورد» (صندوق، عملة، شيك، خصم مكتسب).
  //    النافذة القديمة RegisterPaymentDialog لم تكن تسجّل الصندوق.
  Future<void> _registerPayment() async {
    final id = _supplier.id;
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SupplierPaymentScreen(supplier: _party(id))),
    );
    if (mounted) _loadData();
  }

  Future<void> _purchaseReturn() async {
    final id = _supplier.id;
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PurchaseReturnEditorScreen(supplier: _party(id))),
    );
    if (mounted) _loadData();
  }

  void _openStatement() {
    final id = _supplier.id;
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierStatementScreen(supplierId: id, supplierName: _supplier.name),
      ),
    );
  }

  Future<void> _editSupplier() async {
    final updated = await showSupplierFormDialog(context, supplier: _supplier);
    if (updated == null || !mounted) return;
    setState(() => _supplier = updated);
    await _loadData();
  }

  Future<void> _deleteSupplier() async {
    final deleted = await confirmAndDeleteSupplier(context, _supplier);
    if (deleted && mounted) Navigator.of(context).pop(true);
  }
}

// ═══════════════════════════ كل الفواتير والمدفوعات ═══════════════════════════

/// كل فواتير المورد ودفعاته، مع البحث بالرقم والتصفية بالتاريخ والحالة.
/// الضغط على فاتورة يفتح تفاصيلها (InvoiceDetailsSplitScreen) كما في صفحة المورد.
class SupplierDocumentsScreen extends StatefulWidget {
  const SupplierDocumentsScreen({super.key, required this.supplier, this.initialTab = 0});
  final Supplier supplier;

  /// 0 = الفواتير، 1 = المدفوعات
  final int initialTab;

  @override
  State<SupplierDocumentsScreen> createState() => _SupplierDocumentsScreenState();
}

class _SupplierDocumentsScreenState extends State<SupplierDocumentsScreen> {
  final _search = TextEditingController();
  List<PurchaseInvoice> _invoices = [];
  List<SupplierPayment> _payments = [];
  bool _loading = true;
  String? _error;
  DateTime? _from;
  DateTime? _to;
  String _status = 'all'; // all | confirmed | draft

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.supplier.id;
    if (id == null) {
      setState(() {
        _loading = false;
        _error = 'هذا المورد غير محفوظ بعد';
      });
      return;
    }
    final service = context.read<PurchaseService>();
    try {
      final invoices = await service.getInvoicesForSupplier(id);
      final payments = await service.getPaymentsForSupplier(id);
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _payments = payments;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر التحميل: $e';
      });
    }
  }

  bool _inRange(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final f = _from;
    final t = _to;
    if (f != null && day.isBefore(DateTime(f.year, f.month, f.day))) return false;
    if (t != null && day.isAfter(DateTime(t.year, t.month, t.day))) return false;
    return true;
  }

  String get _query => _search.text.trim().toLowerCase();

  List<PurchaseInvoice> _filteredInvoices() {
    final q = _query;
    return _invoices.where((i) {
      if (!_inRange(i.date)) return false;
      if (_status != 'all' && i.status != _status) return false;
      if (q.isEmpty) return true;
      return i.invoiceNumber.toLowerCase().contains(q) || (i.notes ?? '').toLowerCase().contains(q);
    }).toList();
  }

  List<SupplierPayment> _filteredPayments() {
    final q = _query;
    return _payments.where((p) {
      if (!_inRange(p.date)) return false;
      if (q.isEmpty) return true;
      return '${p.receiptNumber ?? ''}'.contains(q) || (p.notes ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openInvoice(int invoiceId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceDetailsSplitScreen(invoiceId: invoiceId)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final invoices = _filteredInvoices();
    final payments = _filteredPayments();
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab == 1 ? 1 : 0,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          title: Text('مستندات المورد: ${widget.supplier.name}'),
          actions: [
            IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh), onPressed: _load),
          ],
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'الفواتير (${invoices.length})'),
              Tab(text: 'المدفوعات (${payments.length})'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error ?? ''))
                : Column(
                    children: [
                      _buildFilters(),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildInvoicesTab(invoices),
                            _buildPaymentsTab(payments),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'بحث برقم الفاتورة أو السند أو الملاحظات',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _status,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('كل حالات الفواتير')),
                    DropdownMenuItem(value: 'confirmed', child: Text('فواتير مؤكدة')),
                    DropdownMenuItem(value: 'draft', child: Text('مسودات')),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'all'),
                ),
              ],
            ),
          ),
          PeriodBar(
            from: _from,
            to: _to ?? DateTime.now(),
            onChanged: (f, t) => setState(() {
              final now = DateTime.now();
              final isToday = t.year == now.year && t.month == now.month && t.day == now.day;
              _from = f;
              // «الكل» (بلا بداية وحتى اليوم) = بلا حدود، فلا تختفي فاتورة بتاريخ لاحق
              _to = (f == null && isToday) ? null : t;
            }),
          ),
        ],
      ),
    );
  }

  Widget _summaryBar(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFE2E8F0),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
    );
  }

  Widget _buildInvoicesTab(List<PurchaseInvoice> list) {
    if (list.isEmpty) return const Center(child: Text('لا توجد فواتير مطابقة'));
    final totals = <String, double>{};
    for (final i in list) {
      if (i.status != 'confirmed') continue;
      totals[i.currency] = (totals[i.currency] ?? 0) + i.totalAmount;
    }
    return Column(
      children: [
        _summaryBar('مجموع الفواتير المؤكدة المعروضة: ${_totalsText(totals)}'),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (_, index) {
              final invoice = list[index];
              final id = invoice.id;
              return _invoiceTile(invoice, id == null ? null : () => _openInvoice(id));
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentsTab(List<SupplierPayment> list) {
    if (list.isEmpty) return const Center(child: Text('لا توجد مدفوعات مطابقة'));
    final totals = <String, double>{};
    for (final p in list) {
      totals[p.currency] = (totals[p.currency] ?? 0) + p.amount;
    }
    return Column(
      children: [
        _summaryBar('مجموع المدفوعات المعروضة: ${_totalsText(totals)}'),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (_, index) => _paymentTile(list[index]),
          ),
        ),
      ],
    );
  }
}
