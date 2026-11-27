// lib/screens/pos/widgets/cart_table.dart
//
// 🧺▦ أسطر سلة الكاشير جدولاً مصغّراً بأعمدة (مثل جدول «إنشاء فاتورة»):
//   • رأس ثابت؛ يُسحب من حافة أي عمود لتغيير عرضه (الماوس أو اللمس)، ويُحفظ على الجهاز
//   • زر «الأعمدة» في الرأس: إظهار/إخفاء الأعمدة، ارتفاع السطر، والإعادة للافتراضي
//   • «اسم المادة» يملأ الباقي؛ إن زادت الأعمدة عن عرض السلة يظهر تمرير أفقي
//   • سعر السطر يُعتمد عند الخروج من الحقل أو Enter (لا يقفز المؤشر أثناء الكتابة)
// العمليات نفسها كما كانت (POSProvider) — التغيير في الشكل فقط.

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../../providers/pos_provider.dart';
import '../../../widgets/formatters.dart';
import '../pos_cart_layout.dart';
import '../pos_cart_layout_screen.dart'; // ⚙️ تصميم أعمدة السلة
import 'pos_style.dart';

class CartTable extends StatefulWidget {
  const CartTable({super.key, required this.pos, this.onLayoutChanged, this.empty});

  final POSProvider pos;

  /// ما يظهر تحت رأس الأعمدة حين تكون السلة فارغة
  final Widget? empty;

  /// يُستدعى بعد حفظ تغيير في التخطيط (مثل إعادة عرض السلة للافتراضي)
  final VoidCallback? onLayoutChanged;

  @override
  State<CartTable> createState() => _CartTableState();
}

class _CartTableState extends State<CartTable> {
  static const double _trail = 34; // عمود الحذف
  static const double _headerH = 34;
  static const Color _headBg = Color(0xFFF1F5F9);
  static const Color _grid = Color(0xFFE6EAF0);

  final _hScroll = ScrollController();

  /// عروض أثناء السحب (تُحفظ عند رفع الإصبع)
  Map<String, double>? _live;

  PosCartLayout get _layout {
    final l = PosCartLayout.current;
    final live = _live;
    return live == null ? l : l.copyWith(widths: {...l.widths, ...live});
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  void _drag(String key, double shownWidth, double dx) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final delta = rtl ? -dx : dx; // حافة نهاية العمود: يسار في العربية
    final l = _layout;
    // «اسم المادة» قد يُعرض أعرض من عرضه المحفوظ (يملأ الباقي): نبدأ من المعروض
    final base = key == 'name' && shownWidth > l.w(key) ? shownWidth : l.w(key);
    final next = (base + delta).clamp(PosCartLayout.minWidths[key] ?? 30, PosCartLayout.maxWidth).toDouble();
    setState(() => _live = {...?_live, key: next});
  }

  Future<void> _dragEnd() async {
    final live = _live;
    if (live == null) return;
    final l = PosCartLayout.current;
    await l.copyWith(widths: {...l.widths, ...live}).save();
    if (mounted) setState(() => _live = null);
  }

  Future<void> _onMenu(String v) async {
    final l = PosCartLayout.current;
    if (v.startsWith('col:')) {
      final k = v.substring(4);
      final hidden = {...l.hidden};
      if (!hidden.remove(k)) hidden.add(k);
      await l.copyWith(hidden: hidden).save();
    } else if (v.startsWith('h:')) {
      await l.copyWith(rowHeight: double.parse(v.substring(2))).save();
    } else if (v == 'resetCols') {
      await PosCartLayout(rowHeight: l.rowHeight, cartWidth: l.cartWidth).save();
    } else if (v == 'resetCart') {
      await l.copyWith(resetCartWidth: true).save();
      widget.onLayoutChanged?.call();
    } else if (v == 'settings') {
      await Navigator.push(context, MaterialPageRoute<bool>(builder: (_) => const PosCartLayoutScreen()));
      widget.onLayoutChanged?.call(); // عرض السلة قد تغيّر
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.pos.cartItems;
    return LayoutBuilder(builder: (context, box) {
      final layout = _layout;
      final avail = box.maxWidth - _trail;
      final cols = layout.resolve(avail);
      final tableW = cols.values.fold<double>(0, (a, b) => a + b) + _trail;
      final table = SizedBox(
        width: tableW < box.maxWidth ? box.maxWidth : tableW,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(cols),
            Expanded(
              child: items.isEmpty
                  ? (widget.empty ?? const SizedBox.shrink())
                  : ListView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: items.length,
                itemBuilder: (context, i) => _CartRow(
                  key: ValueKey(items[i].id),
                  index: i,
                  item: items[i],
                  units: widget.pos.getProductUnits(items[i].product),
                  pos: widget.pos,
                  cols: cols,
                  height: layout.rowHeight,
                  trail: _trail,
                ),
              ),
            ),
          ],
        ),
      );
      if (tableW <= box.maxWidth + 0.5) return table;
      return Scrollbar(
        controller: _hScroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          child: table,
        ),
      );
    });
  }

  Widget _header(Map<String, double> cols) {
    return Container(
      height: _headerH,
      decoration: const BoxDecoration(
        color: _headBg,
        border: Border(bottom: BorderSide(color: Color(0xFFD5DCE5))),
      ),
      child: Row(children: [
        for (final e in cols.entries) _headCell(e.key, e.value),
        SizedBox(width: _trail, child: Center(child: _columnsMenu())),
      ]),
    );
  }

  Widget _headCell(String key, double width) {
    final dragging = _live?.containsKey(key) ?? false;
    return SizedBox(
      width: width,
      child: Stack(children: [
        Positioned.fill(
          child: Container(
            alignment: key == 'name' ? AlignmentDirectional.centerStart : Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: const BoxDecoration(border: BorderDirectional(end: BorderSide(color: _grid))),
            child: Text(
              PosCartLayout.headers[key]!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
            ),
          ),
        ),
        // ↔️ مقبض تغيير العرض على حافة نهاية العمود
        PositionedDirectional(
          end: 0,
          top: 0,
          bottom: 0,
          width: 12,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (d) => _drag(key, width, d.delta.dx),
              onHorizontalDragEnd: (_) => _dragEnd(),
              onHorizontalDragCancel: _dragEnd,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: dragging ? 3 : 2,
                  height: dragging ? _headerH : 14,
                  decoration: BoxDecoration(
                    color: dragging ? PosColors.accent : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _columnsMenu() => IconButton(
        tooltip: 'أعمدة السلة',
        padding: EdgeInsets.zero,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.view_column_outlined, color: Color(0xFF475569)),
        onPressed: _openColumnsPanel,
      );

  /// ⚙️ لوحة أعمدة السلة: التبديل يُحفظ ويظهر فوراً؛ الإعادة والتصميم المفصّل بعد الإغلاق
  Future<void> _openColumnsPanel() async {
    final action = await showDialog<String>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => _ColumnsPanel(onChanged: () {
        if (mounted) setState(() {});
      }),
    );
    if (action != null) await _onMenu(action);
  }
}

class _ColumnsPanel extends StatefulWidget {
  const _ColumnsPanel({required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<_ColumnsPanel> createState() => _ColumnsPanelState();
}

class _ColumnsPanelState extends State<_ColumnsPanel> {
  PosCartLayout get _l => PosCartLayout.current;

  Future<void> _apply(PosCartLayout next) async {
    await next.save();
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: PosColors.accentSoft, borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.view_column_rounded, color: PosColors.accent, size: 21),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('أعمدة السلة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: PosColors.text)),
                  Text('يظهر التغيير فوراً في السلة', style: TextStyle(fontSize: 12, color: PosColors.muted)),
                ]),
              ),
              IconButton(
                tooltip: 'إغلاق',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: PosColors.muted),
              ),
            ]),
            const SizedBox(height: 14),
            _sectionTitle('الأعمدة الظاهرة'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in PosCartLayout.keys) _columnChip(l, k),
            ]),
            const SizedBox(height: 16),
            _sectionTitle('ارتفاع السطر'),
            const SizedBox(height: 8),
            SegmentedButton<double>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: PosColors.accentSoft,
                selectedForegroundColor: PosColors.accent,
                textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              segments: [
                for (final e in PosCartLayout.rowHeights.entries)
                  ButtonSegment<double>(
                    value: e.key,
                    label: Text(e.value.replaceAll('سطر ', '')),
                    icon: Icon(
                      e.key < 44
                          ? Icons.density_small_rounded
                          : (e.key > 44 ? Icons.density_large_rounded : Icons.density_medium_rounded),
                      size: 18,
                    ),
                  ),
              ],
              selected: {l.rowHeight},
              onSelectionChanged: (v) => _apply(l.copyWith(rowHeight: v.first)),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: PosColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.touch_app_rounded, size: 18, color: PosColors.muted),
                SizedBox(width: 8),
                Expanded(
                  child: Text('لتغيير عرض عمود: اسحب حافته في رأس السلة. ولتكبير السلة: اسحب الفاصل بين المواد والسلة.',
                      style: TextStyle(fontSize: 12, color: PosColors.muted, height: 1.45)),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.spaceBetween, children: [
              TextButton.icon(
                onPressed: () => Navigator.pop(context, 'resetCols'),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('الأعمدة الافتراضية'),
              ),
              if (l.cartWidth != null)
                TextButton.icon(
                  onPressed: () => Navigator.pop(context, 'resetCart'),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('عرض السلة الافتراضي'),
                ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: PosColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context, 'settings'),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('تصميم مفصّل…'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) =>
      Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: PosColors.text));

  Widget _columnChip(PosCartLayout l, String k) {
    final locked = PosCartLayout.required.contains(k);
    final on = l.show(k);
    return FilterChip(
      selected: on,
      showCheckmark: !locked,
      avatar: locked ? const Icon(Icons.lock_rounded, size: 14, color: PosColors.muted) : null,
      label: Text(PosCartLayout.headers[k]!),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: on ? (locked ? PosColors.muted : PosColors.accent) : PosColors.text,
      ),
      selectedColor: locked ? PosColors.surfaceAlt : PosColors.accentSoft,
      checkmarkColor: PosColors.accent,
      backgroundColor: Colors.white,
      side: BorderSide(color: on && !locked ? PosColors.accent.withValues(alpha: 0.35) : PosColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      tooltip: locked ? 'عمود ضروري للبيع' : PosCartLayout.labels[k],
      onSelected: locked
          ? null
          : (_) {
              final hidden = {...l.hidden};
              if (!hidden.remove(k)) hidden.add(k);
              _apply(l.copyWith(hidden: hidden));
            },
    );
  }
}

/// سطر مادة في الجدول
class _CartRow extends StatefulWidget {
  const _CartRow({
    super.key,
    required this.index,
    required this.item,
    required this.units,
    required this.pos,
    required this.cols,
    required this.height,
    required this.trail,
  });

  final int index;
  final CartItem item;
  final List<Map<String, dynamic>> units;
  final POSProvider pos;
  final Map<String, double> cols;
  final double height;
  final double trail;

  @override
  State<_CartRow> createState() => _CartRowState();
}

class _CartRowState extends State<_CartRow> {
  late final TextEditingController _price = TextEditingController(text: posMoney(widget.item.price));
  final FocusNode _priceFocus = FocusNode();
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _priceFocus.addListener(() {
      if (!_priceFocus.hasFocus) _commitPrice();
    });
  }

  @override
  void didUpdateWidget(covariant _CartRow old) {
    super.didUpdateWidget(old);
    // لا نلمس الحقل أثناء الكتابة فيه (كان المؤشر يقفز مع كل حرف)
    if (!_priceFocus.hasFocus) {
      final t = posMoney(widget.item.price);
      if (_price.text != t) _price.text = t;
    }
  }

  @override
  void dispose() {
    _price.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  /// رفض الزيادة (البيع بالسالب ممنوع) ⇒ رسالة واضحة بدل تجاهل صامت
  void _guard(bool ok) {
    if (ok || !mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(widget.pos.lastErrorMessage ?? 'تعذّر التعديل'),
      backgroundColor: PosColors.danger,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _commitPrice() {
    final it = widget.item;
    final v = double.tryParse(_price.text.replaceAll(',', ''));
    if (v != null && v >= 0 && (v - it.price).abs() > 1e-9) {
      _guard(widget.pos.updateCartItemUnit(it.id, it.selectedUnit, v, it.unitsInLargeUnit));
    } else {
      _price.text = posMoney(it.price);
    }
  }

  Future<void> _editQty() async {
    final it = widget.item;
    final c = TextEditingController(text: '${it.quantity}');
    final q = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(it.product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          decoration: InputDecoration(labelText: 'الكمية (${it.selectedUnit})', border: const OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())), child: const Text('تم')),
        ],
      ),
    );
    c.dispose();
    if (q == null || !mounted) return;
    _guard(widget.pos.updateQuantity(it.id, q - it.quantity)); // صفر ⇒ يُحذف السطر
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final h = widget.height;
    final fieldH = (h - 10).clamp(26.0, 40.0).toDouble();
    final bg = _hover
        ? const Color(0xFFF1F6FF)
        : (widget.index.isOdd ? PosColors.surfaceAlt : PosColors.surface);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: bg,
          border: const Border(bottom: BorderSide(color: Color(0xFFEDF0F4))),
        ),
        child: Row(children: [
          for (final e in widget.cols.entries)
            SizedBox(
              width: e.value,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _cell(e.key, it, fieldH),
              ),
            ),
          SizedBox(
            width: widget.trail,
            child: IconButton(
              tooltip: 'حذف',
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              onPressed: () => widget.pos.removeFromCart(it.id),
              icon: const Icon(Icons.close_rounded, size: 17, color: PosColors.faint),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _cell(String key, CartItem it, double fieldH) {
    switch (key) {
      case 'index':
        return Center(
          child: Text('${widget.index + 1}',
              style: const TextStyle(fontSize: 11.5, color: PosColors.muted, fontWeight: FontWeight.w700)),
        );
      case 'name':
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Tooltip(
            message: it.product.name,
            waitDuration: const Duration(milliseconds: 600),
            child: Text(
              it.product.name,
              maxLines: widget.height >= 44 ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w600, color: PosColors.text),
            ),
          ),
        );
      case 'unit':
        return _unitCell(it, fieldH);
      case 'price':
        return Center(child: SizedBox(height: fieldH, child: _priceField(it)));
      case 'qty':
        return Center(
          child: _QtyStepper(
            qty: it.quantity,
            height: fieldH,
            onMinus: () => widget.pos.updateQuantity(it.id, -1),
            onPlus: () => _guard(widget.pos.updateQuantity(it.id, 1)),
            onEdit: _editQty,
          ),
        );
      case 'total':
        return Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(posMoney(it.total),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: PosColors.primary,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
        );
      case 'stock':
        final per = it.unitsInLargeUnit > 0 ? it.unitsInLargeUnit : 1;
        final inUnit = it.product.stockQuantity / per;
        final short = inUnit < it.quantity;
        return Center(
          child: Text(posQty(inUnit),
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: short ? PosColors.danger : PosColors.muted)),
        );
      case 'barcode':
        final code = (it.product.barcode ?? '').trim();
        return Center(
          child: Text(code.isEmpty ? '—' : code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 12, color: PosColors.muted)),
        );
    }
    return const SizedBox.shrink();
  }

  Widget _unitCell(CartItem it, double fieldH) {
    final units = widget.units;
    if (units.length <= 1) {
      return Center(
        child: Text(it.selectedUnit,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: PosColors.muted)),
      );
    }
    final baseName = units.first['name'] as String;
    return Center(
      child: PopupMenuButton<String>(
        tooltip: 'الوحدة',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 4),
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: const Color(0x330F172A),
        constraints: const BoxConstraints(minWidth: 230, maxWidth: 300),
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: PosColors.border),
        ),
        onSelected: (name) {
          final u = units.firstWhere((x) => x['name'] == name);
          _guard(widget.pos.updateCartItemUnit(
            it.id,
            name,
            (u['price'] as num).toDouble(),
            (u['quantity'] as num).toInt(),
          ));
        },
        itemBuilder: (_) => [
          const PopupMenuItem<String>(
            enabled: false,
            height: 28,
            child: Text('اختر الوحدة', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: PosColors.muted)),
          ),
          for (final u in units)
            PopupMenuItem<String>(
              value: u['name'] as String,
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _UnitOption(
                name: u['name'] as String,
                factor: (u['quantity'] as num).toInt(),
                baseName: baseName,
                price: (u['price'] as num).toDouble(),
                selected: u['name'] == it.selectedUnit,
              ),
            ),
        ],
        child: Container(
          height: fieldH,
          padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 4, 0),
          decoration: BoxDecoration(
            color: PosColors.accentSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: PosColors.accent.withValues(alpha: 0.25)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(it.selectedUnit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: PosColors.accent)),
            ),
            const Icon(Icons.expand_more_rounded, size: 16, color: PosColors.accent),
          ]),
        ),
      ),
    );
  }

  Widget _priceField(CartItem it) {
    final ok = it.price > 0;
    OutlineInputBorder b(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c, width: w));
    return TextField(
      controller: _price,
      focusNode: _priceFocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
      textAlign: TextAlign.center,
      textAlignVertical: TextAlignVertical.center,
      textDirection: TextDirection.ltr,
      onSubmitted: (_) => _commitPrice(),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: ok ? PosColors.text : PosColors.danger,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: ok ? PosColors.surfaceAlt : const Color(0xFFFEF2F2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        hintText: 'السعر',
        hintStyle: const TextStyle(fontSize: 12, color: PosColors.faint),
        // حدود هادئة: تظهر بوضوح عند الكتابة فقط (أو بالأحمر إن كان بلا سعر)
        enabledBorder: b(ok ? Colors.transparent : PosColors.danger),
        focusedBorder: b(PosColors.accent, 1.5),
      ),
    );
  }
}

/// سطر وحدة في قائمة الوحدات: الاسم، وكم فيها من الوحدة الأصغر، وسعرها
class _UnitOption extends StatelessWidget {
  const _UnitOption({
    required this.name,
    required this.factor,
    required this.baseName,
    required this.price,
    required this.selected,
  });

  final String name;
  final int factor;
  final String baseName;
  final double price;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = selected ? PosColors.accent : PosColors.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? PosColors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
            size: 18, color: selected ? PosColors.accent : PosColors.faint),
        const SizedBox(width: 8),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: c)),
            if (factor > 1)
              Text('= $factor $baseName', style: const TextStyle(fontSize: 11, color: PosColors.muted)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(
          posMoney(price),
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: selected ? PosColors.accent : PosColors.primary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ]),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.qty,
    required this.height,
    required this.onMinus,
    required this.onPlus,
    required this.onEdit,
  });

  final int qty;
  final double height;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, VoidCallback onTap, Color color) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(width: 26, height: height, child: Icon(icon, size: 16, color: color)),
        );
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: PosColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PosColors.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn(Icons.remove_rounded, onMinus, PosColors.muted),
            InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                constraints: const BoxConstraints(minWidth: 28),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                alignment: Alignment.center,
                child: Text('$qty',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: PosColors.text)),
              ),
            ),
            btn(Icons.add_rounded, onPlus, PosColors.accent),
          ],
        ),
      ),
    );
  }
}
