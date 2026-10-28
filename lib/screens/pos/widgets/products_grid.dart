// lib/screens/pos/widgets/products_grid.dart
//
// 🛍️ مواد الكاشير: حقل بحث/باركود دائم التركيز، وشبكة بطاقات مضغوطة
// تُظهر السعر (حسب مستوى السعر المختار) والمخزون وكم أُضيف منها للسلة.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/product.dart';
import '../../../providers/pos_provider.dart';
import 'categories_sidebar.dart';
import 'pos_style.dart';

class ProductsGrid extends StatelessWidget {
  const ProductsGrid({
    super.key,
    required this.searchController,
    required this.searchFocus,
    required this.onSubmitSearch,
    required this.onProductTap,
    this.showCategoryChips = false,
  });

  final TextEditingController searchController;
  final FocusNode searchFocus;

  /// Enter في حقل البحث (أو قارئ الباركود)
  final ValueChanged<String> onSubmitSearch;
  final ValueChanged<Product> onProductTap;
  final bool showCategoryChips;

  @override
  Widget build(BuildContext context) {
    // شاشة الكاشير يراها الزبون: لا تُعرض الكلفة فيها لأي مستخدم
    const showCost = false;
    return Consumer<POSProvider>(
      builder: (context, pos, _) {
        final products = pos.displayedProducts;
        final inCart = <int, int>{};
        for (final it in pos.cartItems) {
          final id = it.product.id;
          if (id != null) inCart[id] = (inCart[id] ?? 0) + it.quantity;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: _SearchField(
                controller: searchController,
                focusNode: searchFocus,
                onChanged: pos.setSearchQuery,
                onSubmitted: onSubmitSearch,
              ),
            ),
            if (showCategoryChips) ...[
              const CategoryChipsBar(),
              const SizedBox(height: 8),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
              child: Row(
                children: [
                  Text(
                    '${products.length} مادة',
                    style: const TextStyle(fontSize: 12, color: PosColors.muted, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  const Flexible(
                    child: Text(
                      'F2 بحث  ·  F9 دفع',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: PosColors.faint),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: pos.isLoading && products.isEmpty
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
                  : products.isEmpty
                      ? const _EmptyProducts()
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 200,
                            mainAxisExtent: 140,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: products.length,
                          itemBuilder: (context, i) {
                            final p = products[i];
                            final out = p.stockQuantity <= 0;
                            return _ProductCard(
                              product: p,
                              price: pos.basePriceOf(p),
                              inCart: inCart[p.id] ?? 0,
                              disabled: out && !pos.allowNegativeStock,
                              showCost: showCost,
                              onTap: () => onProductTap(p),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onEditingComplete: () {}, // يبقى التركيز في الحقل بعد Enter (لقارئ الباركود)
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14.5, color: PosColors.text),
      decoration: InputDecoration(
        hintText: 'ابحث بالاسم أو امسح الباركود',
        hintStyle: const TextStyle(color: PosColors.faint, fontSize: 14),
        prefixIcon: const Icon(Icons.search_rounded, color: PosColors.muted),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, v, _) => v.text.isEmpty
              ? const Icon(Icons.qr_code_2_rounded, color: PosColors.faint, size: 20)
              : IconButton(
                  tooltip: 'مسح البحث',
                  icon: const Icon(Icons.close_rounded, size: 20, color: PosColors.muted),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                    focusNode.requestFocus();
                  },
                ),
        ),
        filled: true,
        fillColor: PosColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: border(PosColors.border),
        enabledBorder: border(PosColors.border),
        focusedBorder: border(PosColors.accent, 1.6),
      ),
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 56, color: Color(0xFFCBD5E1)),
          SizedBox(height: 12),
          Text('لا توجد مواد مطابقة', style: TextStyle(color: PosColors.muted, fontSize: 15, fontWeight: FontWeight.w600)),
          SizedBox(height: 4),
          Text('جرّب اسماً آخر أو قسماً آخر', style: TextStyle(color: PosColors.faint, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _ProductCard extends StatefulWidget {
  const _ProductCard({
    required this.product,
    required this.price,
    required this.inCart,
    required this.disabled,
    required this.showCost,
    required this.onTap,
  });

  final Product product;
  final double price;
  final int inCart;
  final bool disabled;
  final bool showCost;
  final VoidCallback onTap;

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final tint = PosColors.tint(p.categoryId ?? p.id);
    final selected = widget.inCart > 0;
    final hover = _hover && !widget.disabled;
    final name = p.name.trim();
    final letter = name.isEmpty ? '؟' : name.characters.first;
    final cost = p.costPrice ?? 0;

    return MouseRegion(
      cursor: widget.disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: hover ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 140),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: PosColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? PosColors.accent : (hover ? tint.withValues(alpha: 0.45) : PosColors.border),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: hover ? tint.withValues(alpha: 0.16) : const Color(0x0A0F172A),
                blurRadius: hover ? 16 : 6,
                offset: Offset(0, hover ? 6 : 2),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: widget.disabled ? null : widget.onTap,
              child: Opacity(
                opacity: widget.disabled ? 0.45 : 1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: tint.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(letter, style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: 13)),
                          ),
                          if (selected) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: PosColors.accent, borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                '×${widget.inCart}',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                          const Spacer(),
                          Flexible(child: _StockChip(qty: p.stockQuantity)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            color: PosColors.text,
                          ),
                        ),
                      ),
                      if (widget.showCost && cost > 0)
                        Text(
                          'الكلفة ${posMoney(cost)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, height: 1.2, color: PosColors.faint),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                widget.price > 0 ? posMoney(widget.price) : 'بلا سعر',
                                style: TextStyle(
                                  fontSize: 17,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                  color: widget.price > 0 ? PosColors.primary : PosColors.danger,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            p.translatedUnit,
                            style: const TextStyle(fontSize: 11, height: 1.2, color: PosColors.muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StockChip extends StatelessWidget {
  const _StockChip({required this.qty});

  final double qty;

  @override
  Widget build(BuildContext context) {
    final out = qty <= 0;
    final low = !out && qty <= 5;
    final Color fg = out ? PosColors.danger : (low ? PosColors.warn : PosColors.muted);
    final Color bg = out
        ? const Color(0xFFFEE2E2)
        : (low ? const Color(0xFFFEF3C7) : PosColors.surfaceAlt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          out ? 'نفذت' : posQty(qty),
          style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
