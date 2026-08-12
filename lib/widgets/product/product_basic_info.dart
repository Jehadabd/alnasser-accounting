import 'package:flutter/material.dart';
import '../../models/category.dart';

class ProductBasicInfoWidget extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController barcodeController;
  final int? selectedCategoryId;
  final List<Category> categories;
  final Function(int?) onCategoryChanged;
  final VoidCallback onAddCategory;

  const ProductBasicInfoWidget({
    super.key,
    required this.nameController,
    required this.barcodeController,
    required this.selectedCategoryId,
    required this.categories,
    required this.onCategoryChanged,
    required this.onAddCategory,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'البيانات الأساسية',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'اسم المنتج *',
                prefixIcon: Icon(Icons.shopping_bag_outlined),
                hintText: 'مثال: دجاج تركي، أرز بسمتي...',
              ),
              validator: (val) =>
                  val == null || val.isEmpty ? 'اسم المنتج مطلوب' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'القسم / الفئة',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: categories.map((cat) {
                      return DropdownMenuItem<int>(
                        value: cat.id,
                        child: Text(cat.name),
                      );
                    }).toList(),
                    onChanged: onCategoryChanged,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onAddCategory,
                  icon: const Icon(Icons.add_circle_outline),
                  color: Theme.of(context).primaryColor,
                  tooltip: 'إضافة قسم جديد',
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: barcodeController,
              decoration: const InputDecoration(
                labelText: 'الباركود (اختياري)',
                prefixIcon: Icon(Icons.qr_code_2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
