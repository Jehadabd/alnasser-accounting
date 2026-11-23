// lib/owner/ai_invoice/ai_supplier_picker.dart
//
// 🏪 اختيار المورد — نافذة بحث بدل القائمة المنسدلة الطويلة:
//   بحث بالاسم أو الهاتف، بطاقة لكل مورد (حرفه الأول، هاتفه، رصيده وعدد فواتيره)،
//   المختار مميَّز، وEnter يختار أول نتيجة.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../../models/supplier.dart';

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);
const _bg = Color(0xFFF5F7FB);
const _a = Color(0xFF4F46E5);
const _b = Color(0xFF7C3AED);
const _debt = Color(0xFFDC2626);
const _ok = Color(0xFF16A34A);

final _money = intl.NumberFormat('#,##0', 'en_US');

Future<Supplier?> showSupplierPicker(BuildContext context, {required List<Supplier> suppliers, Supplier? selected}) =>
    showDialog<Supplier>(
      context: context,
      builder: (_) => _SupplierPicker(suppliers: suppliers, selected: selected),
    );

/// حقل المورد في الشاشة: بطاقة قابلة للضغط تفتح النافذة.
class SupplierPickField extends StatelessWidget {
  const SupplierPickField({super.key, required this.supplier, required this.onTap, this.dense = false});
  final Supplier? supplier;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final s = supplier;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 8 : 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: s == null ? _a.withValues(alpha: 0.55) : _line, width: s == null ? 1.6 : 1),
          ),
          child: Row(children: [
            _Avatar(name: s?.name, size: dense ? 30 : 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(s == null ? 'اختر المورد' : 'المورد',
                    style: TextStyle(fontSize: 11.5, color: s == null ? _a : _muted, fontWeight: FontWeight.w700)),
                Text(s?.name ?? 'اضغط للبحث في الموردين',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: s == null ? _muted : _ink)),
              ]),
            ),
            const Icon(Icons.unfold_more_rounded, color: _muted),
          ]),
        ),
      ),
    );
  }
}

class _SupplierPicker extends StatefulWidget {
  const _SupplierPicker({required this.suppliers, this.selected});
  final List<Supplier> suppliers;
  final Supplier? selected;
  @override
  State<_SupplierPicker> createState() => _SupplierPickerState();
}

class _SupplierPickerState extends State<_SupplierPicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  static String _norm(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'\s+'), ' ');

  List<Supplier> get _list {
    final all = widget.suppliers.where((s) => s.id != null).toList()
      ..sort((a, b) => b.totalInvoices.compareTo(a.totalInvoices)); // الأكثر تعاملاً أولاً
    final q = _norm(_q.text);
    if (q.isEmpty) return all;
    return all.where((s) => _norm(s.name).contains(q) || (s.phone ?? '').replaceAll(' ', '').contains(q.replaceAll(' ', ''))).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [_a, _b])),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.storefront_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('اختر المورد (${widget.suppliers.length})',
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _q,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (list.isNotEmpty) Navigator.pop(context, list.first);
                },
                style: const TextStyle(fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم أو الهاتف…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _q.text.isEmpty
                      ? null
                      : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(_q.clear)),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ]),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.search_off_rounded, size: 48, color: _muted),
                      SizedBox(height: 8),
                      Text('لا مورد بهذا الاسم', style: TextStyle(color: _muted)),
                    ]),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _tile(list[i]),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _tile(Supplier s) {
    final sel = s.id == widget.selected?.id;
    final bal = s.currentBalance;
    final cur = s.currency == 'USD' ? r'$' : 'د.ع';
    return Material(
      color: sel ? _a.withValues(alpha: 0.07) : _bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pop(context, s),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: sel ? _a : Colors.transparent, width: 1.6),
          ),
          child: Row(children: [
            _Avatar(name: s.name, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _ink)),
                const SizedBox(height: 2),
                Text(
                  [
                    if ((s.phone ?? '').trim().isNotEmpty) s.phone!.trim(),
                    '${s.totalInvoices} فاتورة',
                  ].join('  •  '),
                  style: const TextStyle(color: _muted, fontSize: 12.5),
                ),
              ]),
            ),
            if (bal.abs() >= 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (bal > 0 ? _debt : _ok).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${bal > 0 ? 'له' : 'عليه'} ${_money.format(bal.abs())} $cur',
                    style: TextStyle(color: bal > 0 ? _debt : _ok, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            if (sel) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle_rounded, color: _a),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.size});
  final String? name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final n = (name ?? '').trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: n.isEmpty ? null : const LinearGradient(colors: [_a, _b]),
        color: n.isEmpty ? _bg : null,
      ),
      child: n.isEmpty
          ? Icon(Icons.storefront_rounded, size: size * 0.5, color: _a)
          : Text(n.characters.first, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.42)),
    );
  }
}
