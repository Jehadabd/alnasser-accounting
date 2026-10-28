// lib/erp/warranty/warranty_screens.dart
//
// 🛠️ شاشات الضمان والصيانة:
//   • WarrantyHubScreen   — قائمة الطلبات بحسب الحالة + بحث + «استلام قطعة».
//   • WarrantyClaimEditor — استلام قطعة (العميل، المادة، تاريخ البيع، مدة الضمان، العطل).
//   • WarrantyClaimScreen — تفاصيل الطلب، خطه الزمني، نقله بين الحالات، وطباعة الإيصال.
//   • WarrantyStatsScreen — أكثر المواد أعطالاً، والموردون ومدة ردّهم.
// لا شيء هنا يغيّر مالاً أو مخزوناً: ردّ الثمن من «مرتجع مبيعات» كالعادة.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart' show fmtMoney, fmtDate, showError, showOk;
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../report_export.dart';
import '../sales/doc_pdf.dart';
import '../sales/sales_return_screen.dart';
import 'warranty_service.dart';

String _day(DateTime? d) => d == null ? '—' : fmtDate(d);

String _ago(int days) => days <= 0
    ? 'اليوم'
    : days == 1
        ? 'منذ يوم'
        : days == 2
            ? 'منذ يومين'
            : (days <= 10 ? 'منذ $days أيام' : 'منذ $days يوماً');

/// شارة حالة الضمان (داخل / خارج / غير معروف).
Widget _warrantyBadge(bool? within) => StatusBadge(
      within == null ? 'الضمان غير معروف' : (within ? 'داخل الضمان' : 'خارج الضمان'),
      color: within == null ? ErpColors.muted : (within ? ErpColors.green : ErpColors.red),
    );

// ════════════════════════════════════════════════════════════════════
// القائمة
// ════════════════════════════════════════════════════════════════════

class WarrantyHubScreen extends StatefulWidget {
  const WarrantyHubScreen({super.key});
  @override
  State<WarrantyHubScreen> createState() => _WarrantyHubScreenState();
}

class _WarrantyHubScreenState extends State<WarrantyHubScreen> {
  String _filter = 'open';
  String _q = '';
  List<WarrantyClaim> _rows = [];
  Map<String, int> _counts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await WarrantyService.list(filter: _filter, query: _q);
      final counts = await WarrantyService.counts();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _counts = counts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _load();
  }

  int get _openCount => _counts.entries.where((e) => e.key != WStatus.delivered).fold(0, (s, e) => s + e.value);

  int get _allCount => _counts.values.fold(0, (s, v) => s + v);

  @override
  Widget build(BuildContext context) {
    final filters = <(String, String, int, Color)>[
      ('open', 'المفتوحة', _openCount, ErpColors.navy),
      for (final s in WStatus.all) (s, WStatus.label(s), _counts[s] ?? 0, WStatus.color(s)),
      ('all', 'الكل', _allCount, ErpColors.muted),
    ];
    return ErpPage(
      title: 'الضمان والصيانة',
      subtitle: 'قطع العملاء المعطوبة من الاستلام حتى التسليم',
      icon: Icons.build_circle_rounded,
      actions: [
        IconButton(
          tooltip: 'تقرير الأعطال والموردين',
          icon: const Icon(Icons.insights_rounded),
          onPressed: () => _open(const WarrantyStatsScreen()),
        ),
        IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh_rounded), onPressed: _load),
      ],
      headerExtra: SearchBox(
        hint: 'بحث: عميل، مادة، رقم تسلسلي، هاتف، مورد، رقم الطلب',
        onChanged: (v) {
          _q = v;
          _load();
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const WarrantyClaimEditor()),
        backgroundColor: ErpColors.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('استلام قطعة'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in filters)
              ChoiceChip(
                selected: _filter == f.$1,
                showCheckmark: false,
                selectedColor: f.$4.withValues(alpha: 0.16),
                side: BorderSide(color: _filter == f.$1 ? f.$4 : ErpColors.border),
                label: Text('${f.$2}  ${f.$3}',
                    style: TextStyle(
                        fontWeight: _filter == f.$1 ? FontWeight.w800 : FontWeight.w600,
                        color: _filter == f.$1 ? f.$4 : ErpColors.text)),
                onSelected: (_) {
                  setState(() => _filter = f.$1);
                  _load();
                },
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? EmptyState(
                      _q.isNotEmpty
                          ? 'لا نتائج لهذا البحث'
                          : (_allCount == 0
                              ? 'لا طلبات بعد — اضغط «استلام قطعة» عندما يرجع عميل بقطعة معطوبة'
                              : 'لا طلبات في هذه الحالة'),
                      icon: Icons.build_circle_outlined,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
                      itemCount: _rows.length,
                      itemBuilder: (_, i) => _ClaimCard(
                        claim: _rows[i],
                        onTap: () => _open(WarrantyClaimScreen(claimId: _rows[i].id!)),
                      ),
                    ),
        ),
      ]),
    );
  }
}

class _ClaimCard extends StatelessWidget {
  const _ClaimCard({required this.claim, required this.onTap});
  final WarrantyClaim claim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = claim;
    final sc = WStatus.color(c.status);
    final days = c.daysOpen;
    // تنبيه: عند المورد أكثر من أسبوعين، أو مفتوح أكثر من شهر
    final overdue = c.isOpen &&
        ((c.status == WStatus.atSupplier && c.sentDate != null && DateTime.now().difference(c.sentDate!).inDays > 14) ||
            days > 30);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: overdue ? ErpColors.orange : ErpColors.border, width: overdue ? 1.4 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: sc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(WStatus.icon(c.status), color: sc),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(c.productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  Text('#${c.claimNo}', style: const TextStyle(color: ErpColors.muted, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 3),
                Text(
                  [
                    c.customerName,
                    if ((c.phone ?? '').isNotEmpty) c.phone!,
                    if (c.qty != 1) 'الكمية ${fmtQty(c.qty)}',
                    if ((c.serialNo ?? '').isNotEmpty) 'S/N ${c.serialNo}',
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: ErpColors.muted, fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  StatusBadge(WStatus.label(c.status), color: sc),
                  if (c.resolution != null) StatusBadge(WResolution.label(c.resolution), color: WResolution.color(c.resolution)),
                  _warrantyBadge(c.withinWarranty),
                  if (c.status == WStatus.atSupplier && (c.supplierName ?? '').isNotEmpty)
                    StatusBadge('عند ${c.supplierName}', color: WStatus.color(WStatus.atSupplier)),
                  Text(
                    c.isOpen ? 'استُلمت ${_ago(days)}' : 'سُلّمت ${_day(c.deliveredDate)} بعد $days يوم',
                    style: TextStyle(
                        fontSize: 12,
                        color: overdue ? ErpColors.orange : ErpColors.muted,
                        fontWeight: overdue ? FontWeight.w800 : FontWeight.w500),
                  ),
                ]),
              ]),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_left_rounded, color: ErpColors.muted),
          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// الاستلام / التعديل
// ════════════════════════════════════════════════════════════════════

class WarrantyClaimEditor extends StatefulWidget {
  const WarrantyClaimEditor({super.key, this.claim});
  final WarrantyClaim? claim;
  @override
  State<WarrantyClaimEditor> createState() => _WarrantyClaimEditorState();
}

class _WarrantyClaimEditorState extends State<WarrantyClaimEditor> {
  final _customer = TextEditingController();
  final _phone = TextEditingController();
  final _product = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _serial = TextEditingController();
  final _months = TextEditingController();
  final _problem = TextEditingController();
  final _accessories = TextEditingController();
  final _notes = TextEditingController();

  int? _customerId;
  String? _pickedCustomerName;
  int? _productId;
  String? _pickedProductName;
  int? _invoiceId;
  DateTime? _saleDate;
  DateTime _claimDate = DateTime.now();
  bool _saveMonths = false;
  bool _busy = false;
  String? _hint; // «من آخر فاتورة…»
  int _previous = 0;

  bool get _isEdit => widget.claim != null;

  @override
  void initState() {
    super.initState();
    final c = widget.claim;
    if (c != null) {
      _customer.text = c.customerName;
      _phone.text = c.phone ?? '';
      _product.text = c.productName;
      _qty.text = fmtQty(c.qty);
      _serial.text = c.serialNo ?? '';
      _months.text = c.warrantyMonths?.toString() ?? '';
      _problem.text = c.problem ?? '';
      _accessories.text = c.accessories ?? '';
      _notes.text = c.notes ?? '';
      _customerId = c.customerId;
      _pickedCustomerName = c.customerId == null ? null : c.customerName;
      _productId = c.productId;
      _pickedProductName = c.productId == null ? null : c.productName;
      _invoiceId = c.invoiceId;
      _saleDate = c.saleDate;
      _claimDate = c.claimDate;
      if (c.invoiceId != null) _hint = 'مرتبطة بالفاتورة رقم ${c.invoiceId}';
    }
  }

  @override
  void dispose() {
    for (final c in [_customer, _phone, _product, _qty, _serial, _months, _problem, _accessories, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _monthsValue {
    final v = parseMoney(_months.text);
    return (v == null || v <= 0) ? null : v.round();
  }

  bool? get _within => WarrantyService.within(_saleDate, _monthsValue, _claimDate);

  Future<void> _pickCustomer() async {
    final p = await Pickers.customer(context);
    if (p == null || !mounted) return;
    setState(() {
      _customerId = p.id;
      _pickedCustomerName = p.name;
      _customer.text = p.name;
      if ((p.phone ?? '').isNotEmpty) _phone.text = p.phone!;
    });
    _lookupSale();
  }

  Future<void> _pickProduct() async {
    final p = await Pickers.product(context);
    if (p == null || !mounted) return;
    setState(() {
      _productId = p.id;
      _pickedProductName = p.name;
      _product.text = p.name;
    });
    final m = await WarrantyService.productMonths(p.id);
    if (!mounted) return;
    setState(() {
      if (m != null) {
        _months.text = '$m';
        _saveMonths = false;
      }
    });
    _lookupSale();
  }

  /// آخر فاتورة بيعت فيها هذه المادة لهذا العميل → تاريخ البيع.
  Future<void> _lookupSale() async {
    final name = _customer.text.trim();
    final prod = _product.text.trim();
    if (name.isEmpty || prod.isEmpty) return;
    final s = await WarrantyService.lastSale(
        customerId: _customerId, customerName: name, productId: _productId, productName: prod);
    final prev = await WarrantyService.previousClaims(
        customerId: _customerId, customerName: name, productName: prod, exceptId: widget.claim?.id);
    if (!mounted) return;
    setState(() {
      _previous = prev;
      if (s != null) {
        _invoiceId = s.invoiceId;
        _saleDate = s.date;
        _hint = 'من آخر فاتورة بيعت فيها لهذا العميل: رقم ${s.invoiceId} بتاريخ ${_day(s.date)}';
      } else {
        _invoiceId = null;
        _hint = 'لم تُوجد فاتورة لهذه المادة باسم هذا العميل — أدخل تاريخ البيع يدوياً إن عرفته';
      }
    });
  }

  Future<void> _save() async {
    final qty = parseMoney(_qty.text) ?? 0;
    final c = widget.claim ??
        WarrantyClaim(customerName: '', productName: '', claimDate: _claimDate);
    // الاسم المكتوب يدوياً بعد الاختيار يفك الربط بالعميل/المادة
    final custId = _pickedCustomerName != null && _pickedCustomerName == _customer.text.trim() ? _customerId : null;
    final prodId = _pickedProductName != null && _pickedProductName == _product.text.trim() ? _productId : null;
    c
      ..customerId = custId
      ..customerName = _customer.text.trim()
      ..phone = _phone.text
      ..productId = prodId
      ..productName = _product.text.trim()
      ..qty = qty
      ..serialNo = _serial.text
      ..invoiceId = _invoiceId
      ..saleDate = _saleDate
      ..warrantyMonths = _monthsValue
      ..withinWarranty = _within
      ..claimDate = _claimDate
      ..problem = _problem.text
      ..accessories = _accessories.text
      ..notes = _notes.text;
    setState(() => _busy = true);
    try {
      final id = await WarrantyService.save(c);
      if (_saveMonths && prodId != null && _monthsValue != null) {
        await WarrantyService.setProductMonths(prodId, _monthsValue!);
      }
      if (!mounted) return;
      showOk(context, _isEdit ? 'حُفظ التعديل' : 'استُلمت القطعة — طلب رقم ${c.claimNo}');
      if (_isEdit) {
        Navigator.pop(context, true);
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => WarrantyClaimScreen(claimId: id)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  Widget _pickRow(TextBox box, IconData icon, String tip, VoidCallback onPick) => Row(children: [
        Expanded(child: box),
        const SizedBox(width: 8),
        IconButton.filledTonal(onPressed: onPick, tooltip: tip, icon: Icon(icon)),
      ]);

  @override
  Widget build(BuildContext context) {
    final within = _within;
    final end = WarrantyService.endOf(_saleDate, _monthsValue);
    final wc = within == null ? ErpColors.muted : (within ? ErpColors.green : ErpColors.red);
    return ErpPage(
      title: _isEdit ? 'تعديل طلب #${widget.claim!.claimNo}' : 'استلام قطعة للضمان أو الصيانة',
      subtitle: 'سجل متابعة فقط — لا يغيّر حساب العميل ولا المخزون',
      icon: Icons.build_circle_rounded,
      bottom: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: ErpColors.navy, minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded),
            label: Text(_isEdit ? 'حفظ التعديل' : 'حفظ الاستلام', style: const TextStyle(fontSize: 16)),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ErpSection(
                title: 'العميل',
                icon: Icons.person_rounded,
                child: Column(children: [
                  _pickRow(
                    TextBox(controller: _customer, label: 'اسم العميل', onChanged: (_) => setState(() {})),
                    Icons.person_search_rounded,
                    'اختر من العملاء',
                    _pickCustomer,
                  ),
                  const SizedBox(height: 10),
                  TextBox(controller: _phone, label: 'الهاتف'),
                ]),
              ),
              const SizedBox(height: 10),
              ErpSection(
                title: 'القطعة',
                icon: Icons.memory_rounded,
                child: Column(children: [
                  _pickRow(
                    TextBox(controller: _product, label: 'المادة', onChanged: (_) => setState(() {})),
                    Icons.inventory_2_rounded,
                    'اختر من المواد',
                    _pickProduct,
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    SizedBox(width: 120, child: TextBox(controller: _qty, label: 'الكمية')),
                    const SizedBox(width: 10),
                    Expanded(child: TextBox(controller: _serial, label: 'الرقم التسلسلي (إن وُجد)')),
                  ]),
                  const SizedBox(height: 10),
                  TextBox(controller: _problem, label: 'العطل كما وصفه العميل', maxLines: 3),
                  const SizedBox(height: 10),
                  TextBox(controller: _accessories, label: 'ما استُلم معها (علبة، شاحن، كابل…)'),
                  if (_previous > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: ErpColors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const Icon(Icons.history_rounded, color: ErpColors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('لهذا العميل $_previous طلب سابق لنفس المادة',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: ErpColors.orange)),
                        ),
                      ]),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 10),
              ErpSection(
                title: 'الضمان',
                icon: Icons.verified_user_rounded,
                trailing: TextButton.icon(
                  onPressed: _lookupSale,
                  icon: const Icon(Icons.manage_search_rounded, size: 18),
                  label: const Text('ابحث عن فاتورة البيع'),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FieldGrid(children: [
                    DateButton(
                      label: 'تاريخ البيع',
                      value: _saleDate,
                      onChanged: (d) => setState(() {
                        _saleDate = d;
                        _invoiceId = null;
                        _hint = null;
                      }),
                    ),
                    SizedBox(
                      width: 170,
                      child: TextBox(controller: _months, label: 'مدة الضمان (أشهر)', onChanged: (_) => setState(() {})),
                    ),
                    DateButton(label: 'تاريخ الاستلام', value: _claimDate, onChanged: (d) => setState(() => _claimDate = d)),
                  ]),
                  if (_hint != null) ...[
                    const SizedBox(height: 8),
                    Text(_hint!, style: const TextStyle(fontSize: 12.5, color: ErpColors.muted)),
                  ],
                  if (_productId != null && _monthsValue != null)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _saveMonths,
                      onChanged: (v) => setState(() => _saveMonths = v == true),
                      title: Text('احفظ $_monthsValue شهراً مدةَ ضمانٍ لهذه المادة (تُقترح تلقائياً بعدها)'),
                    ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: wc.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: wc.withValues(alpha: 0.35)),
                    ),
                    child: Row(children: [
                      Icon(
                          within == null
                              ? Icons.help_outline_rounded
                              : (within ? Icons.verified_rounded : Icons.gpp_bad_rounded),
                          color: wc),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          within == null
                              ? 'أدخل تاريخ البيع ومدة الضمان لمعرفة هل القطعة داخل الضمان'
                              : (within
                                  ? 'داخل الضمان — ينتهي في ${_day(end)}'
                                  : 'خارج الضمان — انتهى في ${_day(end)}'),
                          style: TextStyle(fontWeight: FontWeight.w800, color: wc),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              ErpSection(
                title: 'ملاحظات',
                icon: Icons.notes_rounded,
                child: TextBox(controller: _notes, label: 'ملاحظات داخلية', maxLines: 2),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// التفاصيل والحالات
// ════════════════════════════════════════════════════════════════════

class WarrantyClaimScreen extends StatefulWidget {
  const WarrantyClaimScreen({super.key, required this.claimId});
  final int claimId;
  @override
  State<WarrantyClaimScreen> createState() => _WarrantyClaimScreenState();
}

class _WarrantyClaimScreenState extends State<WarrantyClaimScreen> {
  WarrantyClaim? _c;
  List<WarrantyEvent> _events = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await WarrantyService.get(widget.claimId);
    final ev = c == null ? <WarrantyEvent>[] : await WarrantyService.events(widget.claimId);
    if (!mounted) return;
    setState(() {
      _c = c;
      _events = ev;
    });
  }

  Future<void> _run(Future<void> Function() f, String ok) async {
    setState(() => _busy = true);
    try {
      await f();
      if (mounted) showOk(context, ok);
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  Future<void> _sendToSupplier() async {
    final s = await Pickers.supplier(context, title: 'إلى أي مورد تُرسل القطعة؟');
    if (s == null || !mounted) return;
    await _run(
      () => WarrantyService.setStatus(widget.claimId, WStatus.atSupplier, supplierId: s.id, supplierName: s.name),
      'أُرسلت إلى ${s.name}',
    );
  }

  /// نتيجة الصيانة + ملاحظة.
  Future<(String, String)?> _askResolution(String title) async {
    String? picked;
    final note = TextEditingController();
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final res in WResolution.all)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: picked == res ? WResolution.color(res) : ErpColors.border),
                    ),
                    tileColor: picked == res ? WResolution.color(res).withValues(alpha: 0.08) : null,
                    leading: Icon(
                        picked == res ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                        color: WResolution.color(res)),
                    title: Text(WResolution.label(res), style: const TextStyle(fontWeight: FontWeight.w700)),
                    onTap: () => setD(() => picked = res),
                  ),
                ),
              const SizedBox(height: 6),
              TextField(
                controller: note,
                decoration: InputDecoration(
                  labelText: 'ملاحظة (ما الذي أُصلح، سبب الرفض…)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              onPressed: picked == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    final text = note.text;
    note.dispose();
    if (r != true || picked == null) return null;
    return (picked!, text);
  }

  Future<void> _markReady() async {
    final fromSupplier = _c?.status == WStatus.atSupplier;
    final r = await _askResolution(fromSupplier ? 'عادت من المورد — ما النتيجة؟' : 'ما نتيجة الصيانة؟');
    if (r == null || !mounted) return;
    await _run(
      () => WarrantyService.setStatus(widget.claimId, WStatus.ready, resolution: r.$1, note: r.$2),
      'جاهزة للتسليم — ${WResolution.label(r.$1)}',
    );
  }

  Future<void> _deliver() async {
    final c = _c!;
    final ok = await confirmDialog(
      context,
      'تسليم للعميل',
      'تسليم «${c.productName}» إلى ${c.customerName}؟\nالنتيجة: ${WResolution.label(c.resolution)}',
      ok: 'تم التسليم',
      color: ErpColors.green,
    );
    if (!ok || !mounted) return;
    await _run(() => WarrantyService.setStatus(widget.claimId, WStatus.delivered), 'سُلّمت للعميل');
  }

  Future<void> _reopen() async {
    final note = await askText(context, 'إعادة فتح الطلب', label: 'السبب (عادت القطعة بعطل…)');
    if (note == null || !mounted) return;
    await _run(() => WarrantyService.setStatus(widget.claimId, WStatus.received, note: note), 'أُعيد فتح الطلب');
  }

  Future<void> _note() async {
    final note = await askText(context, 'ملاحظة على الطلب', label: 'الملاحظة');
    if (note == null || note.trim().isEmpty || !mounted) return;
    await _run(() => WarrantyService.addNote(widget.claimId, note), 'أُضيفت الملاحظة');
  }

  Future<void> _edit() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => WarrantyClaimEditor(claim: _c)));
    _load();
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      'حذف الطلب',
      'حذف طلب #${_c!.claimNo} وخطه الزمني نهائياً؟ (يُستعمل لطلب سُجّل خطأً — لا أثر مالي له)',
      ok: 'حذف',
      color: ErpColors.red,
    );
    if (!ok || !mounted) return;
    try {
      await WarrantyService.delete(widget.claimId);
      if (!mounted) return;
      showOk(context, 'حُذف الطلب');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _print() async {
    final c = _c!;
    try {
      final bytes = await DocPdf.build(
        title: 'إيصال استلام ضمان وصيانة',
        number: '${c.claimNo}',
        date: c.claimDate,
        partyLabel: 'العميل',
        partyName: c.customerName,
        partyExtra: (c.phone ?? '').isEmpty ? null : c.phone,
        infos: [
          MapEntry('الحالة', WStatus.label(c.status)),
          MapEntry('الضمان', c.withinWarranty == null ? 'غير معروف' : (c.withinWarranty! ? 'داخل الضمان' : 'خارج الضمان')),
          if (c.saleDate != null) MapEntry('تاريخ البيع', _day(c.saleDate)),
          if (c.warrantyEnd != null) MapEntry('نهاية الضمان', _day(c.warrantyEnd)),
          if (c.invoiceId != null) MapEntry('فاتورة البيع', '${c.invoiceId}'),
        ],
        headers: const ['المادة', 'الكمية', 'الرقم التسلسلي', 'العطل'],
        rows: [
          [c.productName, fmtQty(c.qty), c.serialNo ?? '—', c.problem ?? '—'],
        ],
        total: 0,
        showTotals: false,
        showWords: false,
        notes: (c.accessories ?? '').isEmpty ? null : 'استُلم معها: ${c.accessories}',
        terms: 'يُرجى إحضار هذا الإيصال عند استلام القطعة.',
      );
      if (!mounted) return;
      await ReportExport.openPdf(context, bytes, 'ضمان_${c.claimNo}');
    } catch (e) {
      if (mounted) showError(context, 'تعذّرت الطباعة: $e');
    }
  }

  List<Widget> _actions(WarrantyClaim c) {
    Widget btn(String t, IconData i, Color col, VoidCallback f) => FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: col,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: _busy ? null : f,
          icon: Icon(i, size: 19),
          label: Text(t),
        );
    final res = <Widget>[];
    if (c.status == WStatus.received) {
      res.add(btn('أرسلها للمورد', Icons.local_shipping_rounded, WStatus.color(WStatus.atSupplier), _sendToSupplier));
      res.add(btn('جاهزة (صُلحت هنا)', Icons.task_alt_rounded, WStatus.color(WStatus.ready), _markReady));
    } else if (c.status == WStatus.atSupplier) {
      res.add(btn('عادت من المورد', Icons.move_to_inbox_rounded, WStatus.color(WStatus.ready), _markReady));
    } else if (c.status == WStatus.ready) {
      res.add(btn('سلّمها للعميل', Icons.handshake_rounded, WStatus.color(WStatus.delivered), _deliver));
      res.add(OutlinedButton.icon(
          onPressed: _busy ? null : _markReady, icon: const Icon(Icons.edit_note_rounded), label: const Text('غيّر النتيجة')));
    }
    if (c.status != WStatus.received) {
      res.add(OutlinedButton.icon(
          onPressed: _busy ? null : _reopen, icon: const Icon(Icons.replay_rounded), label: const Text('إعادة فتح')));
    }
    return res;
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return const ErpPage(
        title: 'طلب ضمان',
        icon: Icons.build_circle_rounded,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final sc = WStatus.color(c.status);
    final step = WStatus.all.indexOf(c.status);
    return ErpPage(
      title: 'طلب #${c.claimNo} — ${c.productName}',
      subtitle: '${c.customerName}${(c.phone ?? '').isEmpty ? '' : ' • ${c.phone}'}',
      icon: Icons.build_circle_rounded,
      actions: [
        IconButton(tooltip: 'طباعة إيصال الاستلام', icon: const Icon(Icons.print_rounded), onPressed: _print),
        IconButton(tooltip: 'ملاحظة', icon: const Icon(Icons.add_comment_rounded), onPressed: _note),
        IconButton(tooltip: 'تعديل بيانات الاستلام', icon: const Icon(Icons.edit_rounded), onPressed: _edit),
        IconButton(tooltip: 'حذف (سُجّل خطأً)', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // ── مسار الحالة ──
              ErpSection(
                title: 'الحالة',
                icon: WStatus.icon(c.status),
                color: sc,
                trailing: c.resolution == null
                    ? null
                    : StatusBadge(WResolution.label(c.resolution), color: WResolution.color(c.resolution)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    for (var i = 0; i < WStatus.all.length; i++) ...[
                      Expanded(child: _StepDot(status: WStatus.all[i], done: i <= step, current: i == step)),
                      if (i < WStatus.all.length - 1)
                        Expanded(
                          child: Container(
                            height: 3,
                            margin: const EdgeInsets.only(bottom: 22),
                            decoration: BoxDecoration(
                              color: i < step ? sc : ErpColors.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                    ],
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 10, runSpacing: 10, children: _actions(c)),
                  if (c.resolution == WResolution.refunded) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: ErpColors.orange.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded, color: ErpColors.orange),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'ردّ الثمن لا يُسجَّل من هنا: سجّله «مرتجع مبيعات» حتى يُصحَّح حساب العميل والمخزون.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => SalesReturnScreen(invoiceId: c.invoiceId))),
                          icon: const Icon(Icons.assignment_return_rounded),
                          label: const Text('مرتجع مبيعات'),
                        ),
                      ]),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 10),
              ErpSection(
                title: 'البيانات',
                icon: Icons.info_outline_rounded,
                child: FieldGrid(children: [
                  InfoTile('المادة', c.productName, width: 260),
                  InfoTile('الكمية', fmtQty(c.qty), width: 110),
                  InfoTile('الرقم التسلسلي', (c.serialNo ?? '').isEmpty ? '—' : c.serialNo!),
                  InfoTile('تاريخ الاستلام', _day(c.claimDate)),
                  InfoTile('عمرها عندنا', '${c.daysOpen} يوم', color: c.isOpen && c.daysOpen > 30 ? ErpColors.orange : null),
                  InfoTile('تاريخ البيع', _day(c.saleDate)),
                  InfoTile('مدة الضمان', c.warrantyMonths == null ? '—' : '${c.warrantyMonths} شهر'),
                  InfoTile(
                    'الضمان',
                    c.withinWarranty == null
                        ? 'غير معروف'
                        : (c.withinWarranty! ? 'داخل — حتى ${_day(c.warrantyEnd)}' : 'خارج — انتهى ${_day(c.warrantyEnd)}'),
                    color: c.withinWarranty == null ? null : (c.withinWarranty! ? ErpColors.green : ErpColors.red),
                    width: 240,
                  ),
                  if (c.invoiceId != null) InfoTile('فاتورة البيع', '${c.invoiceId}'),
                  if ((c.supplierName ?? '').isNotEmpty) InfoTile('المورد', c.supplierName!),
                  if (c.sentDate != null) InfoTile('أُرسلت للمورد', _day(c.sentDate)),
                  if (c.backDate != null)
                    InfoTile('عادت من المورد',
                        '${_day(c.backDate)}${c.sentDate == null ? '' : ' (بعد ${c.backDate!.difference(c.sentDate!).inDays} يوم)'}'),
                  if (c.deliveredDate != null) InfoTile('سُلّمت', _day(c.deliveredDate)),
                  if ((c.createdBy ?? '').isNotEmpty) InfoTile('استلمها', c.createdBy!),
                ]),
              ),
              if ((c.problem ?? '').isNotEmpty || (c.accessories ?? '').isNotEmpty || (c.notes ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                ErpSection(
                  title: 'العطل والملاحظات',
                  icon: Icons.report_problem_outlined,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if ((c.problem ?? '').isNotEmpty) _para('العطل', c.problem!),
                    if ((c.accessories ?? '').isNotEmpty) _para('استُلم معها', c.accessories!),
                    if ((c.notes ?? '').isNotEmpty) _para('ملاحظات', c.notes!),
                  ]),
                ),
              ],
              const SizedBox(height: 10),
              ErpSection(
                title: 'الخط الزمني',
                icon: Icons.timeline_rounded,
                child: _events.isEmpty
                    ? const Text('لا أحداث', style: TextStyle(color: ErpColors.muted))
                    : Column(children: [
                        for (var i = _events.length - 1; i >= 0; i--) _TimelineRow(e: _events[i], last: i == 0),
                      ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _para(String label, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: text),
        ]), style: const TextStyle(height: 1.5)),
      );
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.status, required this.done, required this.current});
  final String status;
  final bool done;
  final bool current;
  @override
  Widget build(BuildContext context) {
    final c = WStatus.color(status);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: current ? 40 : 32,
        height: current ? 40 : 32,
        decoration: BoxDecoration(
          color: done ? c : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: done ? c : ErpColors.border, width: 2),
          boxShadow: current ? [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 10)] : null,
        ),
        child: Icon(WStatus.icon(status), size: current ? 20 : 16, color: done ? Colors.white : ErpColors.muted),
      ),
      const SizedBox(height: 4),
      Text(WStatus.label(status),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 11.5, fontWeight: current ? FontWeight.w800 : FontWeight.w500, color: done ? c : ErpColors.muted)),
    ]);
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.e, required this.last});
  final WarrantyEvent e;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final isNote = e.status == 'note';
    final isEdit = e.status == 'edit';
    final c = isNote || isEdit ? ErpColors.muted : WStatus.color(e.status);
    final title = isNote ? 'ملاحظة' : (isEdit ? 'تعديل' : WStatus.label(e.status));
    final icon = isNote ? Icons.chat_bubble_outline_rounded : (isEdit ? Icons.edit_rounded : WStatus.icon(e.status));
    final t = e.at;
    final time = '${_day(t)}  ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: c),
          ),
          if (!last) Expanded(child: Container(width: 2, color: ErpColors.border)),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14, top: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: c))),
                Text(time, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11.5, color: ErpColors.muted)),
              ]),
              if ((e.note ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(e.note!, style: const TextStyle(height: 1.4)),
              ],
              if ((e.user ?? '').isNotEmpty)
                Text('بواسطة ${e.user}', style: const TextStyle(fontSize: 11.5, color: ErpColors.muted)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// التقرير
// ════════════════════════════════════════════════════════════════════

class WarrantyStatsScreen extends StatefulWidget {
  const WarrantyStatsScreen({super.key});
  @override
  State<WarrantyStatsScreen> createState() => _WarrantyStatsScreenState();
}

class _WarrantyStatsScreenState extends State<WarrantyStatsScreen> {
  Map<String, int> _counts = {};
  Map<String, int> _res = {};
  List<ProductClaimStat> _products = [];
  List<SupplierClaimStat> _suppliers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final counts = await WarrantyService.counts();
      final res = await WarrantyService.resolutions();
      final products = await WarrantyService.topProducts();
      final suppliers = await WarrantyService.suppliers();
      if (!mounted) return;
      setState(() {
        _counts = counts;
        _res = res;
        _products = products;
        _suppliers = suppliers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _counts.values.fold(0, (s, v) => s + v);
    return ErpPage(
      title: 'تقرير الضمان والصيانة',
      subtitle: 'أكثر المواد أعطالاً، ونتائج الصيانة، والموردون',
      icon: Icons.insights_rounded,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : total == 0
              ? const EmptyState('لا طلبات ضمان بعد', icon: Icons.insights_outlined)
              : ListView(padding: const EdgeInsets.all(12), children: [
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    StatCard(label: 'كل الطلبات', value: '$total', icon: Icons.build_circle_rounded),
                    for (final s in WStatus.all)
                      StatCard(
                          label: WStatus.label(s), value: '${_counts[s] ?? 0}', icon: WStatus.icon(s), color: WStatus.color(s)),
                  ]),
                  const SizedBox(height: 10),
                  if (_res.isNotEmpty)
                    ErpSection(
                      title: 'نتائج الصيانة',
                      icon: Icons.fact_check_rounded,
                      child: Wrap(spacing: 10, runSpacing: 10, children: [
                        for (final r in WResolution.all)
                          if ((_res[r] ?? 0) > 0)
                            StatusBadge('${WResolution.label(r)}: ${_res[r]}', color: WResolution.color(r)),
                      ]),
                    ),
                  const SizedBox(height: 10),
                  ErpSection(
                    title: 'أكثر المواد أعطالاً',
                    icon: Icons.memory_rounded,
                    child: SimpleTable(
                      headers: const ['المادة', 'الطلبات', 'الكمية', 'رُفض ضمانها'],
                      numericColumns: const {1, 2, 3},
                      rows: [
                        for (final p in _products) [p.name, '${p.claims}', fmtQty(p.qty), '${p.rejected}'],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ErpSection(
                    title: 'الموردون',
                    icon: Icons.local_shipping_rounded,
                    child: _suppliers.isEmpty
                        ? const Text('لم تُرسل قطع إلى موردين بعد', style: TextStyle(color: ErpColors.muted))
                        : SimpleTable(
                            headers: const ['المورد', 'أُرسل', 'عاد', 'ما زال عنده', 'متوسط مدة الرد (يوم)'],
                            numericColumns: const {1, 2, 3, 4},
                            rows: [
                              for (final s in _suppliers)
                                [s.name, '${s.sent}', '${s.back}', '${s.stillThere}', s.back == 0 ? '—' : fmtMoney(s.avgDays)],
                            ],
                          ),
                  ),
                ]),
    );
  }
}
