// lib/erp/inventory/batch_details_dialog.dart
//
// 📦 «الصلاحية والضمان» لسطر في فاتورة الشراء: تاريخ صلاحية هذه الدفعة، ومدة ضمانها
// وبدايته وشروطه. تُحفظ على سطر الشراء، وعند «تأكيد واستلام» تنتقل إلى حركة الشراء
// (ProductBatches) فتعرف كل الأجهزة صلاحية الدفعة وضمانها، ويأخذ البيع ضمان الدفعة
// التي يخرج منها (الأقدم أولاً).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product.dart';
import '../../models/purchase_invoice_item.dart';
import '../warranty/item_warranty.dart';

class _T {
  _T._();
  static const navy = Color(0xFF0F3460);
  static const teal = Color(0xFF0F766E);
  static const amber = Color(0xFFB45309);
  static const text = Color(0xFF1E293B);
  static const muted = Color(0xFF64748B);
  static const line = Color(0xFFE2E8F0);
  static const soft = Color(0xFFF8FAFC);
  static const red = Color(0xFFB42318);
}

class BatchDetailsDialog extends StatefulWidget {
  const BatchDetailsDialog({super.key, required this.item, this.product, required this.purchaseDate});

  final PurchaseInvoiceItem item;
  final Product? product;
  final DateTime purchaseDate;

  /// يعيد السطر بتفاصيل دفعته الجديدة، أو null إن أُلغي.
  static Future<PurchaseInvoiceItem?> edit(
    BuildContext context, {
    required PurchaseInvoiceItem item,
    Product? product,
    required DateTime purchaseDate,
  }) =>
      showDialog<PurchaseInvoiceItem>(
        context: context,
        builder: (_) => BatchDetailsDialog(item: item, product: product, purchaseDate: purchaseDate),
      );

  /// سطر قصير تحت اسم المادة: «صلاحية 2027/03 • ضمان سنة».
  static String summary(PurchaseInvoiceItem item) {
    final parts = <String>[];
    final e = DateTime.tryParse(item.expiryDate ?? '');
    if (e != null) parts.add('صلاحية ${e.year}/${e.month.toString().padLeft(2, '0')}');
    final w = WarrantySpec.parse(item.warrantySpec);
    if (w != null && !w.isNone) parts.add('ضمان ${w.label}');
    return parts.join(' • ');
  }

  @override
  State<BatchDetailsDialog> createState() => _BatchDetailsDialogState();
}

class _BatchDetailsDialogState extends State<BatchDetailsDialog> {
  late bool _hasExpiry;
  DateTime? _expiry;
  late bool _hasWarranty;
  final _qty = TextEditingController();
  WarrantyUnit _unit = WarrantyUnit.year;
  WarrantyBasis _basis = WarrantyBasis.purchase;
  final _terms = TextEditingController();

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    final p = widget.product;
    // السطر أولاً؛ وإلا ما في بطاقة المادة (اقتراح يُعدَّل)
    _expiry = DateTime.tryParse(it.expiryDate ?? '');
    _hasExpiry = _expiry != null || (it.expiryDate == null && (p?.hasExpiry ?? false));
    final w = WarrantySpec.parse(it.warrantySpec) ?? (it.hasBatchDetails ? null : WarrantySpec.parse(p?.warrantySpec));
    _hasWarranty = w != null && !w.isNone;
    if (_hasWarranty) {
      _qty.text = '${w!.value}';
      _unit = w.unit;
      _basis = w.basis;
    } else {
      _qty.text = '1';
    }
    _terms.text = it.warrantyTerms ?? (it.hasBatchDetails ? '' : (p?.warrantyTerms ?? ''));
  }

  @override
  void dispose() {
    _qty.dispose();
    _terms.dispose();
    super.dispose();
  }

  WarrantySpec? get _spec {
    final v = int.tryParse(_qty.text.trim()) ?? 0;
    return (v > 0 && v <= 999) ? WarrantySpec(v, _unit, basis: _basis) : null;
  }

  String get _example {
    final s = _spec;
    if (s == null) return 'اكتب مدة من 1 إلى 999.';
    final from = _basis == WarrantyBasis.purchase ? widget.purchaseDate : DateTime.now();
    final end = ItemWarranty.show(ItemWarranty.iso(s.endFrom(from)));
    return _basis == WarrantyBasis.purchase
        ? 'من تاريخ هذه الفاتورة ⇒ الضمان ${s.label} حتى $end'
        : 'بيعت اليوم ⇒ الضمان ${s.label} حتى $end';
  }

  bool get _valid => (!_hasExpiry || _expiry != null) && (!_hasWarranty || _spec != null);

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _expiry ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 30),
      helpText: 'تاريخ انتهاء صلاحية هذه الدفعة',
    );
    if (d != null) setState(() => _expiry = d);
  }

  void _save() {
    final s = _hasWarranty ? _spec : null;
    final t = _terms.text.trim();
    Navigator.pop(
      context,
      widget.item.copyWith(
        expiryDate: _hasExpiry && _expiry != null ? ItemWarranty.iso(_expiry!) : null,
        warrantySpec: s?.encode(),
        warrantyTerms: s != null && t.isNotEmpty ? t : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _section(
                  icon: Icons.event_available_rounded,
                  color: _T.amber,
                  title: 'تاريخ الصلاحية',
                  subtitle: 'لهذه الكمية فقط؛ التنبيه يأخذ أقرب صلاحية بين الدفعات الباقية في المخزن.',
                  on: _hasExpiry,
                  onToggle: (v) => setState(() => _hasExpiry = v),
                  child: _expiryPicker(),
                ),
                const SizedBox(height: 12),
                _section(
                  icon: Icons.verified_user_rounded,
                  color: _T.teal,
                  title: 'الضمان',
                  subtitle: 'يُطبع على فاتورة البيع للقطع التي تخرج من هذه الدفعة (الأقدم يخرج أولاً).',
                  on: _hasWarranty,
                  onToggle: (v) => setState(() => _hasWarranty = v),
                  child: _warrantyEditor(),
                ),
              ]),
            ),
          ),
          _actions(),
        ]),
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_T.navy, Color(0xFF1B5E8C)]),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.inventory_2_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('الصلاحية والضمان',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(widget.item.productName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
            ]),
          ),
        ]),
      );

  Widget _section({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool on,
    required ValueChanged<bool> onToggle,
    required Widget child,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: on ? color.withValues(alpha: 0.05) : _T.soft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on ? color.withValues(alpha: 0.35) : _T.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, color: on ? color : _T.muted, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: _T.text, fontSize: 14.5)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: _T.muted, height: 1.4)),
            ]),
          ),
          Semantics(label: title, toggled: on, child: Switch(value: on, activeColor: color, onChanged: onToggle)),
        ]),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: on ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Padding(padding: const EdgeInsets.only(top: 12), child: child),
          secondChild: const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }

  Widget _expiryPicker() => InkWell(
        onTap: _pickExpiry,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _expiry == null ? _T.red.withValues(alpha: 0.5) : _T.line),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_month_rounded, size: 20, color: _T.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _expiry == null ? 'اختر تاريخ الانتهاء' : 'تنتهي في ${ItemWarranty.show(ItemWarranty.iso(_expiry!))}',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: _expiry == null ? _T.red : _T.text, fontSize: 14),
              ),
            ),
            const Icon(Icons.edit_calendar_rounded, size: 18, color: _T.muted),
          ]),
        ),
      );

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _T.line)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _T.line)),
      );

  Widget _warrantyEditor() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(
            width: 100,
            child: TextField(
              controller: _qty,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
              decoration: _dec('المدة'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SegmentedButton<WarrantyUnit>(
              segments: const [
                ButtonSegment(value: WarrantyUnit.day, label: Text('يوم')),
                ButtonSegment(value: WarrantyUnit.month, label: Text('شهر')),
                ButtonSegment(value: WarrantyUnit.year, label: Text('سنة')),
              ],
              selected: {_unit},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _unit = s.first),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        SegmentedButton<WarrantyBasis>(
          segments: const [
            ButtonSegment(value: WarrantyBasis.purchase, label: Text('من تاريخ الشراء'), icon: Icon(Icons.local_shipping_outlined)),
            ButtonSegment(value: WarrantyBasis.sale, label: Text('من تاريخ البيع'), icon: Icon(Icons.point_of_sale_rounded)),
          ],
          selected: {_basis},
          onSelectionChanged: (s) => setState(() => _basis = s.first),
        ),
        const SizedBox(height: 8),
        Text(_example, style: TextStyle(fontSize: 12.5, color: _spec == null ? _T.red : _T.teal, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        TextField(
          controller: _terms,
          maxLines: 3,
          minLines: 2,
          decoration: _dec('شروط الضمان (تُطبع تحت المواد)', hint: 'مثال: لا يشمل الكسر والماء وسوء الاستعمال'),
        ),
      ]);

  Widget _actions() => Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: _T.line))),
        child: Row(children: [
          if (widget.item.hasBatchDetails)
            TextButton.icon(
              onPressed: () => Navigator.pop(
                  context, widget.item.copyWith(expiryDate: null, warrantySpec: null, warrantyTerms: null)),
              icon: const Icon(Icons.delete_sweep_outlined, color: _T.red),
              label: const Text('مسح التفاصيل', style: TextStyle(color: _T.red)),
            ),
          const Spacer(),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _valid ? _save : null,
            style: FilledButton.styleFrom(
              backgroundColor: _T.navy,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.check_rounded),
            label: const Text('حفظ للسطر'),
          ),
        ]),
      );
}
