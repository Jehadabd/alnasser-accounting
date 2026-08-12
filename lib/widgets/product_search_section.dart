// widgets/product_search_section.dart
import 'package:flutter/material.dart';
import '../models/product.dart';

class ProductSearchSection extends StatelessWidget {
  final TextEditingController productSearchController;
  final TextEditingController quantityController;
  final Product? selectedProduct;
  final double? selectedPriceLevel;
  final String selectedListType;
  final List<String> listTypes;
  final List<String> currentUnitOptions;
  final String selectedUnitForItem;
  final bool isViewOnly;
  final List<Product> searchResults;
  final VoidCallback onClearSearch;
  final void Function(String) onSearchChanged;
  final void Function(Product) onProductSelected;
  final void Function(String) onUnitSelected;
  final void Function(String) onQuantityChanged;
  final void Function(double?) onPriceLevelChanged;
  final void Function(String?) onListTypeChanged;
  final VoidCallback onAddItem;

  const ProductSearchSection({
    Key? key,
    required this.productSearchController,
    required this.quantityController,
    required this.selectedProduct,
    required this.selectedPriceLevel,
    required this.selectedListType,
    required this.listTypes,
    required this.currentUnitOptions,
    required this.selectedUnitForItem,
    required this.isViewOnly,
    required this.searchResults,
    required this.onClearSearch,
    required this.onSearchChanged,
    required this.onProductSelected,
    required this.onUnitSelected,
    required this.onQuantityChanged,
    required this.onPriceLevelChanged,
    required this.onListTypeChanged,
    required this.onAddItem,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: productSearchController,
          decoration: InputDecoration(
            labelText: 'البحث عن صنف',
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: isViewOnly ? null : onClearSearch,
            ),
          ),
          enabled: !isViewOnly,
          onChanged: isViewOnly ? null : onSearchChanged,
        ),
        if (searchResults.isNotEmpty)
          Container(
            height: 150,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: ListView.builder(
              itemCount: searchResults.length,
              itemBuilder: (context, index) {
                final product = searchResults[index];
                return ListTile(
                  title: Text(product.name),
                  onTap: isViewOnly ? null : () => onProductSelected(product),
                );
              },
            ),
          ),
        const SizedBox(height: 16.0),
        if (selectedProduct != null) ...[
          Text('الصنف المحدد: ${selectedProduct!.name}'),
          const SizedBox(height: 8.0),
          if ((selectedProduct != null && currentUnitOptions.length > 1) ||
              (selectedProduct!.unit == 'meter' && selectedProduct!.lengthPerUnit != null))
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('نوع الوحدة:', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: currentUnitOptions.map((unitName) {
                        return ChoiceChip(
                          label: Text(
                            unitName,
                            style: TextStyle(
                              color: selectedUnitForItem == unitName ? Colors.white : Colors.black,
                            ),
                          ),
                          selected: selectedUnitForItem == unitName,
                          onSelected: isViewOnly
                              ? null
                              : (selected) {
                                  if (selected) {
                                    onUnitSelected(unitName);
                                    quantityController.clear();
                                  }
                                },
                          selectedColor: Theme.of(context).primaryColor,
                          backgroundColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: quantityController,
                  decoration: InputDecoration(
                    labelText: 'الكمية ($selectedUnitForItem)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'الرجاء إدخال الكمية';
                    }
                    if (double.tryParse(value) == null || double.parse(value) <= 0) {
                      return 'الرجاء إدخال رقم موجب صحيح';
                    }
                    return null;
                  },
                  enabled: !isViewOnly,
                  onChanged: isViewOnly ? null : onQuantityChanged,
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                flex: 1,
                child: Builder(
                  builder: (context) {
                    final product = selectedProduct!;
                    final List<Map<String, dynamic>> priceOptions = [
                      {'value': product.price1, 'label': 'سعر المفرد (سعر 1)', 'number': 1},
                      {'value': product.price2, 'label': 'سعر الجملة (سعر 2)', 'number': 2},
                      {'value': product.price3, 'label': 'سعر الجملة بيوت (سعر 3)', 'number': 3},
                      {'value': product.price4, 'label': 'سعر البيوت (سعر 4)', 'number': 4},
                      {'value': product.price5, 'label': 'سعر أخرى (سعر 5)', 'number': 5},
                    ];
                    final List<DropdownMenuItem<double?>> priceItems = [];
                    final Set<double?> seenValues = {};
                    for (var option in priceOptions) {
                      final val = option['value'];
                      if ((val != null && val > 0 && !seenValues.contains(val)) || option['alwaysShow'] == true) {
                        String text = option['label'] + ': ${val}';
                        priceItems.add(DropdownMenuItem(
                          value: val,
                          child: Text(text),
                        ));
                        seenValues.add(val);
                      }
                    }
                    if (selectedPriceLevel != null && selectedPriceLevel! > 0 && !seenValues.contains(selectedPriceLevel)) {
                      priceItems.add(
                        DropdownMenuItem(
                          value: selectedPriceLevel,
                          child: Text('سعر مخصص: ${selectedPriceLevel!.toStringAsFixed(2)}'),
                        ),
                      );
                      seenValues.add(selectedPriceLevel);
                    }
                    priceItems.add(const DropdownMenuItem(value: -1, child: Text('سعر مخصص')));
                    final validValues = priceItems.map((item) => item.value).toList();
                    final dropdownValue = validValues.where((v) => v == selectedPriceLevel).length == 1 ? selectedPriceLevel : null;
                    return DropdownButtonFormField<double?>(
                      decoration: const InputDecoration(labelText: 'مستوى السعر'),
                      value: dropdownValue,
                      items: priceItems,
                      onChanged: isViewOnly ? null : onPriceLevelChanged,
                      validator: (value) {
                        if (value == null) {
                          return 'الرجاء اختيار مستوى السعر';
                        }
                        return null;
                      },
                      isDense: isViewOnly,
                      menuMaxHeight: isViewOnly ? 0 : 200,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String?>(
                  value: selectedListType,
                  decoration: const InputDecoration(labelText: 'نوع القائمة'),
                  items: listTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                  onChanged: isViewOnly ? null : (val) => onListTypeChanged(val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          ElevatedButton(
            onPressed: isViewOnly ? null : onAddItem,
            child: const Text('إضافة الصنف للفاتورة'),
          ),
        ],
      ],
    );
  }
}
