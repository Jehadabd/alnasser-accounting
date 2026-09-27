// lib/erp/doc_lines.dart
//
// 🧾 محرر أسطر المستندات المشترك (مرتجع، عرض سعر، طلب، مستند مخزني):
// بحث سريع بالاسم/الرقم/الباركود، اختيار الوحدة، الكمية، السعر، الحسم %.

import 'package:flutter/material.dart';

import '../accounting/ledger.dart';
import '../accounting/screens/acc_ui.dart';
import 'erp_common.dart';
import 'erp_ui.dart';
import 'pickers.dart';
import 'stock_helpers.dart';

class DocLine {
  DocLine({
    required this.product,
    required this.unit,
    this.quantity = 1,
    this.price = 0,
    this.discountPercent = 0,
    this.note,
  });
  final ProductLite product;
  UnitOption unit;
  double quantity;
  double price;
  double discountPercent;
  String? note;

  /// يزداد عند تغيير القيم برمجياً (دمج، تغيير وحدة) لتحديث الحقول.
  int rev = 0;

  double get baseQty => quantity * unit.factor;
  double get gross => roundMoney(quantity * price);
  double get total => roundMoney(gross * (1 - discountPercent / 100));
  double get netPrice => quantity == 0 ? 0 : total / quantity;
}

enum PriceSource { sale, cost, none }

class DocLinesEditor extends StatefulWidget {
  const DocLinesEditor({
    super.key,
    required this.lines,
    required this.onChanged,
    this.priceSource = PriceSource.sale,
    this.priceLevel = 1,
    this.showDiscount = false,
    this.showStock = true,
    this.readOnly = false,
    this.priceLabel = 'السعر',
    this.allowNegativeQty = false,
  });
  final List<DocLine> lines;
  final VoidCallback onChanged;
  final PriceSource priceSource;
  final int priceLevel;
  final bool showDiscount;
  final bool showStock;
  final bool readOnly;
  final String priceLabel;
  final bool allowNegativeQty;

  @override
  State<DocLinesEditor> createState() => _DocLinesEditorState();
}

class _DocLinesEditorState extends State<DocLinesEditor> {
  final _search = TextEditingController();
  List<ProductLite> _hits = const [];
  int _seq = 0;

  double _defaultPrice(ProductLite p, UnitOption u) {
    switch (widget.priceSource) {
      case PriceSource.cost:
        return roundMoney(p.costFor(u));
      case PriceSource.none:
        return 0;
      case PriceSource.sale:
        return roundMoney(p.priceLevel(widget.priceLevel) * u.factor);
    }
  }

  void _add(ProductLite p) {
    final u = p.units.first;
    setState(() {
      final i = widget.lines.indexWhere((l) => l.product.id == p.id && l.unit.name == u.name);
      if (i >= 0) {
        widget.lines[i].quantity += 1;
        widget.lines[i].rev++;
      } else {
        widget.lines.add(DocLine(product: p, unit: u, quantity: 1, price: _defaultPrice(p, u)));
      }
      _search.clear();
      _hits = const [];
    });
    widget.onChanged();
  }

  Future<void> _runSearch(String q) async {
    final my = ++_seq;
    if (q.trim().isEmpty) {
      setState(() => _hits = const []);
      return;
    }
    final r = await ErpStock.search(q, limit: 12);
    if (!mounted || my != _seq) return;
    setState(() => _hits = r);
  }

  Future<void> _submitSearch(String q) async {
    final r = await ErpStock.search(q, limit: 5);
    if (!mounted) return;
    // تطابق تام بالباركود/الرقم/الرمز ⇒ إضافة مباشرة
    final exact = r.where((p) =>
        p.barcode == q.trim() || '${p.id}' == q.trim() || (p.itemCode != null && p.itemCode == q.trim()));
    if (exact.isNotEmpty) {
      _add(exact.first);
    } else if (r.length == 1) {
      _add(r.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!widget.readOnly) ...[
        Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'اكتب اسم المادة أو رقمها أو امسح الباركود ثم Enter',
                prefixIcon: const Icon(Icons.qr_code_scanner),
                filled: true,
                fillColor: const Color(0xFFF8FAFD),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onChanged: _runSearch,
              onSubmitted: _submitSearch,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.list),
            label: const Text('من القائمة'),
            onPressed: () async {
              final p = await Pickers.product(context);
              if (p != null) _add(p);
            },
          ),
        ]),
        if (_hits.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ErpColors.border),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10)],
            ),
            child: ListView(shrinkWrap: true, children: [
              for (final p in _hits)
                ListTile(
                  dense: true,
                  title: Text(p.name),
                  subtitle: Text('رقم ${p.id} • المخزون ${fmtQty(p.stock)} ${p.baseUnitName}'),
                  trailing: Text(fmtMoney(_defaultPrice(p, p.units.first)), textDirection: TextDirection.ltr),
                  onTap: () => _add(p),
                ),
            ]),
          ),
        const SizedBox(height: 10),
      ],
      if (lines.isEmpty)
        const EmptyState('لا توجد مواد بعد', icon: Icons.add_shopping_cart)
      else
        for (var i = 0; i < lines.length; i++) _row(i),
    ]);
  }

  Widget _row(int i) {
    final l = widget.lines[i];
    return Container(
      key: ObjectKey(l),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ErpColors.border),
      ),
      child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 260,
          child: Row(children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: ErpColors.navy.withOpacity(0.1),
              child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: ErpColors.navy)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.product.name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2),
                if (widget.showStock)
                  Text('المخزون ${fmtQty(l.product.stock)} ${l.product.baseUnitName}',
                      style: const TextStyle(fontSize: 11, color: ErpColors.muted)),
              ]),
            ),
          ]),
        ),
        DropBox<String>(
          label: 'الوحدة',
          width: 140,
          value: l.unit.name,
          items: [for (final u in l.product.units) DropdownMenuItem(value: u.name, child: Text(u.toString()))],
          onChanged: widget.readOnly
              ? null
              : (v) {
                  final u = l.product.unitNamed(v);
                  setState(() {
                    l.unit = u;
                    l.price = _defaultPrice(l.product, u);
                    l.rev++;
                  });
                  widget.onChanged();
                },
        ),
        _num(l, 'الكمية', l.quantity, (v) {
          l.quantity = widget.allowNegativeQty ? v : v.abs();
        }, width: 110),
        if (widget.priceSource != PriceSource.none)
          _num(l, widget.priceLabel, l.price, (v) => l.price = v.abs(), width: 140),
        if (widget.showDiscount) _num(l, 'حسم %', l.discountPercent, (v) => l.discountPercent = v.clamp(0, 100).toDouble(), width: 90),
        if (widget.priceSource != PriceSource.none)
          InfoTile('الإجمالي', fmtMoney(l.total), width: 120, color: ErpColors.navy),
        if (!widget.readOnly)
          IconButton(
            tooltip: 'حذف',
            icon: const Icon(Icons.delete_outline, color: ErpColors.red),
            onPressed: () {
              setState(() => widget.lines.removeAt(i));
              widget.onChanged();
            },
          ),
      ]),
    );
  }

  Widget _num(DocLine l, String label, double value, void Function(double) set, {double width = 120}) {
    return SizedBox(
      width: width,
      child: TextFormField(
        // مفتاح ثابت للسطر والحقل (والوحدة للسعر) حتى لا يفقد الحقل تركيزه أثناء الكتابة
        key: ValueKey('${identityHashCode(l)}-$label-${l.rev}'),
        initialValue: value == 0 ? '' : fmtMoney(value),
        enabled: !widget.readOnly,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: const OutlineInputBorder(),
        ),
        onChanged: (t) {
          set(parseMoney(t) ?? 0);
          widget.onChanged();
        },
      ),
    );
  }
}

/// مجموع الأسطر.
double linesTotal(List<DocLine> lines) => roundMoney(lines.fold(0.0, (s, l) => s + l.total));
