import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../providers/pos_provider.dart';
import '../../../models/product.dart';

class ProductsGrid extends StatelessWidget {
  const ProductsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<POSProvider>(
      builder: (context, provider, child) {
        final products = provider.displayedProducts;

        return Column(
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                onChanged: provider.setSearchQuery,
                decoration: InputDecoration(
                  hintText: 'بحث عن منتج (الاسم أو الباركود)...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
              ),
            ),
            
            // Grid
            Expanded(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : products.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(
                                'لا توجد منتجات',
                                style: TextStyle(color: Colors.grey[500], fontSize: 18),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            childAspectRatio: 0.75,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            return _ProductCard(product: products[index]);
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;

  const _ProductCard({required this.product});

  // Helper to generate a nice pastel color based on ID
  Color _getCardColor(int? id) {
    final colors = [
      const Color(0xFFE3F2FD), // Blue
      const Color(0xFFE8F5E9), // Green
      const Color(0xFFFFF3E0), // Orange
      const Color(0xFFF3E5F5), // Purple
      const Color(0xFFE0F2F1), // Teal
      const Color(0xFFFCE4EC), // Pink
    ];
    if (id == null) return colors[0];
    return colors[id % colors.length];
  }

  // Helper to get a relevant icon (Mock logic for now)
  IconData _getIcon() {
    // If we had category names mapping, we could do better.
    // For now, generic.
    return Icons.shopping_bag_outlined;
  }

  // Number formatter with thousands separator
  static final _numberFormat = NumberFormat('#,###', 'ar');
  String _formatPrice(num value) => _numberFormat.format(value.toInt());

  @override
  Widget build(BuildContext context) {
    final isLowStock = (product.stockQuantity ?? 0) <= 5;
    final bool isOutOfStock = (product.stockQuantity ?? 0) <= 0;
    final bool isNegativeAllowed = context.select<POSProvider, bool>((p) => p.allowNegativeStock);
    final bool isDisabled = isOutOfStock && !isNegativeAllowed;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: isDisabled ? null : () {
          context.read<POSProvider>().addToCart(product);
        },
        borderRadius: BorderRadius.circular(16),
        child: Opacity(
          opacity: isDisabled ? 0.5 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Top Section: Image/Icon Placeholder
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: _getCardColor(product.id),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                    child: Center(
                      child: isDisabled 
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.block, size: 40, color: Colors.redAccent),
                              SizedBox(height: 4),
                              Text('نفذت الكمية', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          )
                        : Icon(
                            _getIcon(), 
                            size: 48, 
                            color: Colors.black12,
                          ),
                    ),
              ),
            ),
            
            // Bottom Section: Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Name
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        height: 1.2,
                      ),
                    ),
                    
                    // Stock & Price Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Stock
                        if (isLowStock)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${product.stockQuantity.toStringAsFixed(0)} ${product.unit}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.red[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        else
                           Text(
                              '${product.stockQuantity.toInt()}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                            
                        // Price
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft, // Align left since it's RTL (price on left visually in LTR, but code structure...) - actually alignment depends on locale but scaleDown is safe.
                            child: Text(
                              _formatPrice(product.unitPrice),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Colors.blue[800],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
