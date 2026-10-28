// lib/screens/supplier_details_screen.dart
//
// 🏭 صفحة المورد ونوافذه:
//   • showSupplierFormDialog — إضافة/تعديل بيانات المورد.
//   • confirmAndDeleteSupplier — حذف آمن (ممنوع لمن له أثر مالي).
//   • SupplierDetailsScreen — الرصيد في الرأس، أزرار الإجراءات ظاهرة
//     (فاتورة، دفعة، مرتجع، كشف، رصيد افتتاحي، المستندات)، آخر الفواتير
//     والمدفوعات بإجراءاتها (تعديل/إلغاء فاتورة، إلغاء سند)، والمندوبون.
//   • SupplierDocumentsScreen — كل الفواتير والسندات بفلاتر وبحث.

import '../services/save_lock.dart'; // 🔒 قفل الحفظ
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../accounting/screens/acc_ui.dart';
import '../erp/debts/receipt_screen.dart' show SupplierPaymentScreen;
import '../erp/erp_common.dart' show parseMoney, confirmDialog;
import '../erp/erp_ui.dart';
import '../erp/pickers.dart' show PartyLite;
import '../erp/purchases/purchase_return_screen.dart' show PurchaseReturnEditorScreen;
import '../erp/purchases/supplier_statement_screen.dart';
import '../models/purchase_invoice.dart';
import '../models/supplier.dart';
import '../models/supplier_delegate.dart';
import '../models/supplier_payment.dart';
import '../services/purchase_service.dart';
import '../services/suppliers_service.dart';
import 'create_purchase_invoice_screen.dart';
import '../owner/owner_access.dart';
import '../owner/ai_invoice/ai_purchase_invoice_screen.dart';
import 'delegate_details_screen.dart';
import 'invoice_details_split_screen.dart';
import 'suppliers/supplier_ui.dart';

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
    // 🛡️ قيمة خارج الخيارات كانت تُسقط القائمة المنسدلة
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

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط (القفل قبل أي انتظار)
  Future<void> _save() async {
    await SaveLock.run(() => _saveUnlocked(), message: 'جارٍ الحفظ…');
  }
  Future<void> _saveUnlocked() async {
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
    return ErpDialog(
      title: _isEdit ? 'تعديل بيانات المورد' : 'مورد جديد',
      subtitle: _isEdit ? 'الأرصدة لا تتغير بتعديل البيانات' : 'الاسم وحده إلزامي — الباقي يمكن إكماله لاحقاً',
      icon: _isEdit ? Icons.edit_rounded : Icons.add_business_rounded,
      color: supplierAccent,
      width: 560,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: !_isEdit,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'اسم المورد *', prefixIcon: Icon(Icons.storefront_rounded)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone_rounded)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _address,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'العنوان', prefixIcon: Icon(Icons.location_on_rounded)),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          const Text('العملة المفضلة', style: TextStyle(fontWeight: FontWeight.w700, color: ErpColors.text)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'IQD', label: Text('دينار عراقي'), icon: Icon(Icons.payments_outlined)),
              ButtonSegment(value: 'USD', label: Text('دولار'), icon: Icon(Icons.attach_money_rounded)),
            ],
            selected: {_currency},
            onSelectionChanged: _saving ? null : (v) => setState(() => _currency = v.first),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _isEdit
                  ? 'تغييرها لا يحوّل الأرصدة: رصيد الدينار ورصيد الدولار يبقيان كما هما'
                  : 'العملة الافتراضية لفواتير هذا المورد',
              style: const TextStyle(fontSize: 11.5, color: ErpColors.muted),
            ),
          ),
          const SizedBox(height: 16),
          const Text('شروط الدفع', style: TextStyle(fontWeight: FontWeight.w700, color: ErpColors.text)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ChoiceTile(
                title: 'نقدي',
                subtitle: 'يُدفع عند الشراء',
                icon: Icons.payments_rounded,
                dense: true,
                color: supplierAccent,
                selected: _terms == 'cash',
                onTap: () => setState(() => _terms = 'cash'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChoiceTile(
                title: 'آجل',
                subtitle: 'يُدفع لاحقاً',
                icon: Icons.schedule_rounded,
                dense: true,
                color: supplierAccent,
                selected: _terms == 'credit',
                onTap: () => setState(() => _terms = 'credit'),
              ),
            ),
          ]),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child: _terms == 'credit'
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      controller: _creditDays,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'مدة الآجل (بالأيام)', prefixIcon: Icon(Icons.timer_outlined)),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'ملاحظات', prefixIcon: Icon(Icons.notes_rounded)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: supOwe, fontWeight: FontWeight.bold)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: supplierAccent),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_rounded),
          label: Text(_isEdit ? 'حفظ التعديلات' : 'إضافة المورد'),
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
      builder: (ctx) => ErpDialog(
        title: 'لا يمكن حذف المورد',
        icon: Icons.block_rounded,
        color: supOwe,
        width: 480,
        content: Text(msg, style: const TextStyle(height: 1.7)),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
      ),
    );
    return false;
  }

  final ok = await confirmDialog(
    context,
    'حذف المورد',
    'هل تريد حذف المورد «${supplier.name}» نهائياً؟\n'
        'ليس عليه فواتير أو دفعات أو رصيد، ولا يمكن التراجع عن الحذف.',
    ok: 'حذف',
    color: AccColors.red,
  );
  if (!ok || !context.mounted) return false;

  try {
    await service.deleteSupplier(id);
    if (context.mounted) showOk(context, 'تم حذف المورد «${supplier.name}»');
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
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
  static const int _recentCount = 6;

  late Supplier _supplier;
  List<PurchaseInvoice> _invoices = [];
  List<SupplierPayment> _payments = [];
  List<SupplierDelegate> _delegates = [];
  Map<String, double> _opening = const {};
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
    setState(() => _error = null);
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
      Map<String, double> opening = const {};
      try {
        opening = await purchaseService.getOpeningBalances(id);
      } catch (_) {}
      final fresh = await purchaseService.getSupplierById(id);
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _payments = payments;
        _delegates = delegates;
        _opening = opening;
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

  String get _termsText => _supplier.paymentTerms == 'credit'
      ? (_supplier.creditDays > 0 ? 'آجل ${_supplier.creditDays} يوم' : 'آجل')
      : 'نقدي';

  Widget _headerStats() {
    final purchases = <String, double>{};
    for (final inv in _invoices) {
      if (inv.status != 'confirmed') continue;
      purchases[inv.currency] = (purchases[inv.currency] ?? 0) + inv.totalAmount;
    }
    final paid = <String, double>{};
    for (final p in _payments) {
      if (p.isVoid) continue;
      paid[p.currency] = (paid[p.currency] ?? 0) + p.amount;
    }
    return Wrap(spacing: 10, runSpacing: 8, children: [
      for (final (cur, v) in supBalances(_supplier))
        HeaderStat(
          label: '${cur == 'USD' ? 'الرصيد بالدولار' : 'الرصيد'} — ${supBalanceCaption(v)}',
          value: supMoney(v.abs(), cur),
          icon: Icons.account_balance_wallet_rounded,
          accent: v > 0.01 ? const Color(0xFFFCA5A5) : (v < -0.01 ? const Color(0xFF86EFAC) : Colors.white),
        ),
      HeaderStat(
        label: 'المشتريات المؤكدة',
        value: supTotals(purchases),
        icon: Icons.shopping_bag_rounded,
        accent: const Color(0xFF93C5FD),
      ),
      HeaderStat(
        label: 'المدفوع',
        value: supTotals(paid),
        icon: Icons.payments_rounded,
        accent: const Color(0xFF86EFAC),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final phone = (_supplier.phone ?? '').trim();
    return ErpPage(
      title: _supplier.name,
      subtitle: [if (phone.isNotEmpty) phone, _termsText, _supplier.currency == 'USD' ? 'دولار' : 'دينار'].join('  •  '),
      icon: Icons.storefront_rounded,
      actions: [
        if (phone.isNotEmpty)
          IconButton(
            tooltip: 'نسخ رقم الهاتف',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: phone));
              showOk(context, 'نُسخ الرقم $phone');
            },
          ),
        IconButton(tooltip: 'تعديل بيانات المورد', icon: const Icon(Icons.edit_rounded), onPressed: _editSupplier),
        IconButton(tooltip: 'حذف المورد', icon: const Icon(Icons.delete_outline_rounded), onPressed: _deleteSupplier),
        IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh_rounded), onPressed: _loadData),
      ],
      headerExtra: _isLoading || _error != null
          ? null
          : Align(alignment: AlignmentDirectional.centerStart, child: _headerStats()),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1240),
                    child: RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 32),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: SupActionGrid(children: _actions()),
                          ),
                          const SizedBox(height: 8),
                          if (_hasInfo) FadeSlideIn(index: 2, child: _buildInfoCard()),
                          LayoutBuilder(builder: (context, c) {
                            final invoices = FadeSlideIn(index: 3, child: _invoicesSection());
                            final payments = FadeSlideIn(index: 4, child: _paymentsSection());
                            if (c.maxWidth < 980) return Column(children: [invoices, payments]);
                            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(child: invoices),
                              Expanded(child: payments),
                            ]);
                          }),
                          FadeSlideIn(index: 5, child: _delegatesSection()),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  List<Widget> _actions() {
    final openingText = [
      for (final c in const ['IQD', 'USD'])
        if ((_opening[c] ?? 0).abs() > 0.004) supMoney((_opening[c] ?? 0).abs(), c),
    ];
    return [
      SupActionCard(
        icon: Icons.note_add_rounded,
        label: 'فاتورة شراء',
        subtitle: 'إدخال بضاعة من المورد',
        color: const Color(0xFF2563EB),
        onTap: _createInvoice,
      ),
      // 👑 حساب المالك فقط
      if (OwnerAccess.enabled)
        SupActionCard(
          icon: Icons.auto_awesome_rounded,
          label: 'فاتورة بالذكاء الاصطناعي',
          subtitle: 'من صورة أو PDF فاتورة المورد',
          color: const Color(0xFF4F46E5),
          onTap: () => _push(AiPurchaseInvoiceScreen(supplier: _supplier)),
        ),
      SupActionCard(
        icon: Icons.payments_rounded,
        label: 'دفعة للمورد',
        subtitle: 'نقد، تحويل، شيك، خصم',
        color: supCredit,
        onTap: _registerPayment,
      ),
      SupActionCard(
        icon: Icons.assignment_return_rounded,
        label: 'مرتجع مشتريات',
        subtitle: 'إرجاع بضاعة للمورد',
        color: const Color(0xFFEA580C),
        onTap: _purchaseReturn,
      ),
      SupActionCard(
        icon: Icons.list_alt_rounded,
        label: 'كشف الحساب',
        subtitle: 'بفترة، طباعة وExcel',
        color: AccColors.navy,
        onTap: _openStatement,
      ),
      SupActionCard(
        icon: Icons.flag_rounded,
        label: 'رصيد افتتاحي',
        subtitle: openingText.isEmpty ? 'قبل بدء العمل بالبرنامج' : openingText.join(' + '),
        color: const Color(0xFF7C3AED),
        onTap: _openingBalance,
      ),
      SupActionCard(
        icon: Icons.folder_open_rounded,
        label: 'كل المستندات',
        subtitle: '${_invoices.length} فاتورة • ${_payments.length} سند',
        color: supplierAccent,
        onTap: () => _openAllDocs(0),
      ),
    ];
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 56, color: supOwe),
            const SizedBox(height: 12),
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _isLoading = true);
                _loadData();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasInfo =>
      (_supplier.address ?? '').trim().isNotEmpty || (_supplier.notes ?? '').trim().isNotEmpty;

  Widget _buildInfoCard() {
    final address = (_supplier.address ?? '').trim();
    final notes = (_supplier.notes ?? '').trim();
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: ErpColors.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
          ]),
        );
    return ErpSection(
      title: 'معلومات المورد',
      icon: Icons.info_outline_rounded,
      color: supplierAccent,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (address.isNotEmpty) line(Icons.location_on_outlined, address),
        if (notes.isNotEmpty) line(Icons.notes_rounded, notes),
      ]),
    );
  }

  Widget _smallEmpty(String text, IconData icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Column(children: [
            Icon(icon, size: 40, color: ErpColors.muted.withValues(alpha: 0.4)),
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(color: ErpColors.muted)),
          ]),
        ),
      );

  Widget _invoicesSection() {
    final recent = _invoices.take(_recentCount).toList();
    return ErpSection(
      title: 'آخر الفواتير',
      icon: Icons.receipt_long_rounded,
      color: const Color(0xFF2563EB),
      trailing: _invoices.isEmpty
          ? null
          : TextButton(onPressed: () => _openAllDocs(0), child: Text('عرض الكل (${_invoices.length})')),
      child: recent.isEmpty
          ? _smallEmpty('لا توجد فواتير بعد', Icons.receipt_long_outlined)
          : Column(children: [
              for (final inv in recent)
                PurchaseInvoiceTile(
                  invoice: inv,
                  onOpen: inv.id == null ? null : () => _openInvoice(inv.id!),
                  onEdit: inv.id == null ? null : () => _editInvoice(inv),
                  onCancel: inv.id == null ? null : () => _cancelInvoice(inv),
                ),
            ]),
    );
  }

  Widget _paymentsSection() {
    final recent = _payments.take(_recentCount).toList();
    return ErpSection(
      title: 'سجل المدفوعات',
      icon: Icons.payments_rounded,
      color: supCredit,
      trailing: _payments.isEmpty
          ? null
          : TextButton(onPressed: () => _openAllDocs(1), child: Text('عرض الكل (${_payments.length})')),
      child: recent.isEmpty
          ? _smallEmpty('لا توجد مدفوعات', Icons.payments_outlined)
          : Column(children: [
              for (final p in recent) SupplierPaymentTile(payment: p, onVoid: () => _voidPayment(p)),
            ]),
    );
  }

  Widget _delegatesSection() {
    return ErpSection(
      title: 'المندوبون',
      icon: Icons.badge_rounded,
      color: const Color(0xFF7C3AED),
      trailing: TextButton.icon(
        onPressed: () => _delegateDialog(),
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
        label: const Text('إضافة مندوب'),
      ),
      child: _delegates.isEmpty
          ? _smallEmpty('لا يوجد مندوبون — يُضاف المندوب هنا أو من فاتورة الشراء', Icons.badge_outlined)
          : Wrap(spacing: 10, runSpacing: 10, children: [
              for (final d in _delegates) _delegateCard(d),
            ]),
    );
  }

  Widget _delegateCard(SupplierDelegate d) {
    final phone = (d.phone ?? '').trim();
    return SizedBox(
      width: 250,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: ErpColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Navigator.push(context, accRoute<void>(DelegateDetailsScreen(delegate: d)));
            if (mounted) _loadData();
          },
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 0, 8),
            child: Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                child: Text(supInitial(d.name),
                    style: const TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  Text(phone.isEmpty ? 'بلا هاتف' : phone,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
                ]),
              ),
              PopupMenuButton<String>(
                tooltip: 'إجراءات',
                icon: const Icon(Icons.more_vert_rounded, color: ErpColors.muted, size: 20),
                onSelected: (v) {
                  if (v == 'edit') _delegateDialog(existing: d);
                  if (v == 'delete') _deleteDelegate(d);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'edit', child: ListTile(dense: true, leading: Icon(Icons.edit_rounded), title: Text('تعديل'))),
                  PopupMenuItem(
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
        ),
      ),
    );
  }

  Future<void> _delegateDialog({SupplierDelegate? existing}) async {
    final supplierId = _supplier.id;
    if (supplierId == null) return;
    final service = context.read<SuppliersService>();
    final name = TextEditingController(text: existing?.name ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    String? error;
    bool saving = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setD) {
          Future<void> save() => SaveLock.run(() async {
            final n = name.text.trim();
            if (n.isEmpty) {
              setD(() => error = 'أدخل اسم المندوب');
              return;
            }
            if (_delegates.any((x) => x.id != existing?.id && x.name.trim() == n)) {
              setD(() => error = 'يوجد مندوب بهذا الاسم لهذا المورد');
              return;
            }
            setD(() {
              saving = true;
              error = null;
            });
            final p = phone.text.trim();
            try {
              if (existing == null) {
                await service.addDelegate(
                    SupplierDelegate(supplierId: supplierId, name: n, phone: p.isEmpty ? null : p));
              } else {
                await service.updateDelegate(SupplierDelegate(
                  id: existing.id,
                  supplierId: existing.supplierId,
                  name: n,
                  phone: p.isEmpty ? null : p,
                  notes: existing.notes,
                  isActive: existing.isActive,
                  createdAt: existing.createdAt,
                ));
              }
              if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
            } catch (e) {
              setD(() {
                saving = false;
                error = 'تعذّر الحفظ: $e';
              });
            }
          }, message: 'جارٍ الحفظ…');

          return ErpDialog(
            title: existing == null ? 'مندوب جديد' : 'تعديل المندوب',
            subtitle: _supplier.name,
            icon: Icons.badge_rounded,
            color: const Color(0xFF7C3AED),
            width: 440,
            content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'اسم المندوب *',
                  prefixIcon: const Icon(Icons.person_rounded),
                  errorText: error,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'رقم الهاتف (اختياري)', prefixIcon: Icon(Icons.phone_rounded)),
                onSubmitted: (_) => save(),
              ),
            ]),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(dialogCtx, false), child: const Text('إلغاء')),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
                onPressed: saving ? null : save,
                icon: const Icon(Icons.check_rounded),
                label: Text(existing == null ? 'إضافة' : 'حفظ'),
              ),
            ],
          );
        },
      ),
    );
    // لا dispose هنا: حقول النافذة تبقى معروضة أثناء حركة إغلاقها
    if (saved == true && mounted) _loadData();
  }

  Future<void> _deleteDelegate(SupplierDelegate d) async {
    final id = d.id;
    if (id == null) return;
    final purchase = context.read<PurchaseService>();
    final service = context.read<SuppliersService>();
    final blocker = await purchase.delegateDeleteBlocker(id);
    if (!mounted) return;
    if (blocker != null) {
      showError(context, blocker);
      return;
    }
    final ok = await confirmDialog(context, 'حذف المندوب', 'حذف المندوب «${d.name}»؟', ok: 'حذف', color: AccColors.red);
    if (!ok) return;
    try {
      await service.deleteDelegate(id);
      if (mounted) {
        showOk(context, 'حُذف المندوب');
        _loadData();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  PartyLite _party(int id) =>
      PartyLite(id, _supplier.name, _supplier.phone, _supplier.totalDebtIqd, balanceUsd: _supplier.totalDebtUsd);

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, accRoute<void>(screen));
    if (mounted) _loadData();
  }

  Future<void> _openInvoice(int invoiceId) => _push(InvoiceDetailsSplitScreen(invoiceId: invoiceId));

  Future<void> _editInvoice(PurchaseInvoice inv) => _push(CreatePurchaseInvoiceScreen(existingInvoice: inv));

  Future<void> _cancelInvoice(PurchaseInvoice inv) async {
    if (await cancelPurchaseInvoiceFlow(context, inv) && mounted) _loadData();
  }

  Future<void> _voidPayment(SupplierPayment p) async {
    if (await voidSupplierPaymentFlow(context, p) && mounted) _loadData();
  }

  Future<void> _openAllDocs(int tab) => _push(SupplierDocumentsScreen(supplier: _supplier, initialTab: tab));

  Future<void> _createInvoice() => _push(CreatePurchaseInvoiceScreen(preselectedSupplier: _supplier));

  // 💸 طريق واحد لدفعة المورد: شاشة «دفعة لمورد» (صندوق، عملة، شيك، خصم مكتسب).
  Future<void> _registerPayment() async {
    final id = _supplier.id;
    if (id == null) return;
    await _push(SupplierPaymentScreen(supplier: _party(id)));
  }

  Future<void> _purchaseReturn() async {
    final id = _supplier.id;
    if (id == null) return;
    await _push(PurchaseReturnEditorScreen(supplier: _party(id)));
  }

  Future<void> _openStatement() async {
    final id = _supplier.id;
    if (id == null) return;
    await _push(SupplierStatementScreen(supplierId: id, supplierName: _supplier.name));
  }

  Future<void> _openingBalance() async {
    if (await showOpeningBalanceDialog(context, _supplier) && mounted) {
      showOk(context, 'حُفظ الرصيد الافتتاحي');
      _loadData();
    }
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
  String _status = 'all'; // all | confirmed | draft | cancelled
  late int _tab = widget.initialTab == 1 ? 1 : 0;

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

  List<PurchaseInvoice> _filteredInvoices({bool ignoreStatus = false}) {
    final q = _query;
    return _invoices.where((i) {
      if (!_inRange(i.date)) return false;
      if (!ignoreStatus && _status != 'all' && i.status != _status) return false;
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

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, accRoute<void>(screen));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final invoices = _filteredInvoices();
    final payments = _filteredPayments();
    final allInPeriod = _filteredInvoices(ignoreStatus: true);
    int count(String s) => s == 'all' ? allInPeriod.length : allInPeriod.where((i) => i.status == s).length;

    return ErpPage(
      title: 'مستندات المورد',
      subtitle: widget.supplier.name,
      icon: Icons.folder_open_rounded,
      actions: [IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      headerExtra: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Wrap(spacing: 8, children: [
          _TabPill(
            label: 'الفواتير',
            count: invoices.length,
            icon: Icons.receipt_long_rounded,
            selected: _tab == 0,
            onTap: () => setState(() => _tab = 0),
          ),
          _TabPill(
            label: 'المدفوعات',
            count: payments.length,
            icon: Icons.payments_rounded,
            selected: _tab == 1,
            onTap: () => setState(() => _tab = 1),
          ),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error ?? ''))
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(children: [
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          SizedBox(
                            width: 320,
                            child: SearchBox(
                              controller: _search,
                              hint: _tab == 0 ? 'بحث برقم الفاتورة أو الملاحظات' : 'بحث برقم السند أو الملاحظات',
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          if (_tab == 0)
                            for (final (s, label) in const [
                              ('all', 'الكل'),
                              ('confirmed', 'مؤكدة'),
                              ('draft', 'مسودات'),
                              ('cancelled', 'ملغاة'),
                            ])
                              ChoiceChip(
                                label: Text('$label (${count(s)})'),
                                selected: _status == s,
                                onSelected: (_) => setState(() => _status = s),
                              ),
                        ]),
                      ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _tab == 0
                              ? KeyedSubtree(key: const ValueKey('inv'), child: _invoicesList(invoices))
                              : KeyedSubtree(key: const ValueKey('pay'), child: _paymentsList(payments)),
                        ),
                      ),
                    ]),
                  ),
                ),
    );
  }

  Widget _summary(String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: AccColors.soft, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, color: ErpColors.text)),
      );

  Widget _invoicesList(List<PurchaseInvoice> list) {
    if (list.isEmpty) return const EmptyState('لا توجد فواتير مطابقة', icon: Icons.receipt_long_outlined);
    final totals = <String, double>{};
    final remaining = <String, double>{};
    for (final i in list) {
      if (i.status != 'confirmed') continue;
      totals[i.currency] = (totals[i.currency] ?? 0) + i.totalAmount;
      remaining[i.currency] = (remaining[i.currency] ?? 0) + i.remainingAmount;
    }
    return Column(children: [
      _summary('المؤكدة المعروضة: ${supTotals(totals)}   •   المتبقي عليها: ${supTotals(remaining)}'),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
          itemCount: list.length,
          itemBuilder: (_, index) {
            final inv = list[index];
            final id = inv.id;
            return PurchaseInvoiceTile(
              invoice: inv,
              onOpen: id == null ? null : () => _push(InvoiceDetailsSplitScreen(invoiceId: id)),
              onEdit: id == null ? null : () => _push(CreatePurchaseInvoiceScreen(existingInvoice: inv)),
              onCancel: id == null
                  ? null
                  : () async {
                      if (await cancelPurchaseInvoiceFlow(context, inv) && mounted) _load();
                    },
            );
          },
        ),
      ),
    ]);
  }

  Widget _paymentsList(List<SupplierPayment> list) {
    if (list.isEmpty) return const EmptyState('لا توجد مدفوعات مطابقة', icon: Icons.payments_outlined);
    final totals = <String, double>{};
    var voided = 0;
    for (final p in list) {
      if (p.isVoid) {
        voided++;
        continue;
      }
      totals[p.currency] = (totals[p.currency] ?? 0) + p.amount;
    }
    return Column(children: [
      _summary('المدفوعات المعروضة: ${supTotals(totals)}${voided > 0 ? '   •   ملغاة: $voided' : ''}'),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
          itemCount: list.length,
          itemBuilder: (_, index) {
            final p = list[index];
            return SupplierPaymentTile(
              payment: p,
              onVoid: () async {
                if (await voidSupplierPaymentFlow(context, p) && mounted) _load();
              },
            );
          },
        ),
      ),
    ]);
  }
}

/// تبويب داخل الرأس المتدرّج (أبيض للمختار).
class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AccColors.navy : Colors.white;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: selected ? 0 : 0.18)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: fg, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? AccColors.navy.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$count', style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ),
    );
  }
}
