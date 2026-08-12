// widgets/invoice_items_table.dart
import 'package:flutter/material.dart';
import '../models/product.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'formatters.dart';
import 'safe_autocomplete.dart';

class InvoiceItem {
  String? productName;
  String? unitType;
  int? quantity;
  double? price;
  double get total => (quantity ?? 0) * (price ?? 0);
  bool get isComplete =>
      productName != null &&
      productName!.isNotEmpty &&
      unitType != null &&
      unitType!.isNotEmpty &&
      quantity != null &&
      price != null;

  InvoiceItem({this.productName, this.unitType, this.quantity, this.price});

  get itemTotal => null;
}

class InvoiceItemsTable extends StatefulWidget {
  final List<Product> products; // قائمة المنتجات الكاملة
  final void Function(List<InvoiceItem> items) onItemsChanged;

  const InvoiceItemsTable({
    Key? key,
    required this.products,
    required this.onItemsChanged,
  }) : super(key: key);

  @override
  State<InvoiceItemsTable> createState() => _InvoiceItemsTableState();
}

class _InvoiceItemsTableState extends State<InvoiceItemsTable> {
  List<InvoiceItem> items = [];
  List<TextEditingController> productControllers = [];
  List<TextEditingController> quantityControllers = [];
  List<TextEditingController> priceControllers = [];
  List<String?> selectedUnitTypes = [];
  List<List<String>> availableUnitsPerRow = [];

  @override
  void initState() {
    super.initState();
    _addEmptyRow();
  }

  void _addEmptyRow() {
    setState(() {
      items.add(InvoiceItem());
      productControllers.add(TextEditingController());
      quantityControllers.add(TextEditingController());
      priceControllers.add(TextEditingController());
      selectedUnitTypes.add(null);
      availableUnitsPerRow.add([]);
    });
  }

  void _removeRow(int index) {
    setState(() {
      items.removeAt(index);
      productControllers.removeAt(index);
      quantityControllers.removeAt(index);
      priceControllers.removeAt(index);
      selectedUnitTypes.removeAt(index);
      availableUnitsPerRow.removeAt(index);
    });
    widget.onItemsChanged(_getCompletedItems());
  }

  void _onRowChanged(int index) {
    widget.onItemsChanged(_getCompletedItems());
    if (index == items.length - 1 && items[index].isComplete) {
      _addEmptyRow();
    }
    setState(() {});
  }

  List<InvoiceItem> _getCompletedItems() {
    return items.where((item) => item.isComplete).toList();
  }

  double get totalSum =>
      _getCompletedItems().fold(0, (sum, item) => sum + item.total);

  String _fmt(num v) => NumberFormat('#,##0.##', 'en_US').format(v);

  bool _canEditRow(int index) {
    if (index == 0) return true;
    if (index == items.length - 1) {
      return items[index - 1].isComplete;
    }
    return true;
  }

  List<String> _getUnitsForProduct(Product? product) {
    if (product == null) return [];
    if (product.unit == 'piece') {
      List<String> units = ['قطعة'];
      if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
        try {
          final List<dynamic> parsed =
              json.decode(product.unitHierarchy!.replaceAll("'", '"'));
          units.addAll(parsed
              .map((e) => (e['unit_name'] ?? e['name'] ?? '').toString()));
        } catch (e) {}
      }
      return units;
    } else if (product.unit == 'meter') {
      List<String> units = ['متر'];
      if (product.lengthPerUnit != null && product.lengthPerUnit! > 0) {
        units.add('لفة');
      }
      return units;
    } else {
      return [product.unit];
    }
  }

  Product? _findProductByName(String? name) {
    if (name == null) return null;
    try {
      return widget.products.firstWhere((p) => p.name == name);
    } catch (e) {
      return null;
    }
  }

  String _getUnitsCount(Product? product, String? unitType) {
    if (product == null || unitType == null) return '-';
    if (product.unit == 'meter' && unitType == 'لفة') {
      return product.lengthPerUnit?.toString() ?? '-';
    }
    if (product.unit == 'piece' &&
        product.unitHierarchy != null &&
        product.unitHierarchy!.isNotEmpty) {
      try {
        final List<dynamic> parsed =
            json.decode(product.unitHierarchy!.replaceAll("'", '"'));
        int result = 1;
        for (final e in parsed) {
          final name = e['unit_name'] ?? e['name'];
          final qty = int.tryParse(e['quantity'].toString()) ?? 1;
          result *= qty;
          if (name == unitType) break;
        }
        return result > 1 ? result.toString() : '-';
      } catch (e) {
        return '-';
      }
    }
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    final completedItems = _getCompletedItems();
    return Container(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minWidth: MediaQuery.of(context).size.width),
          child: Column(
            children: [
              DataTable(
                columnSpacing: 8,
                headingRowHeight: 38,
                dataRowHeight: 44,
                columns: const [
                  DataColumn(label: SizedBox(width: 28)), // الترقيم
                  DataColumn(label: SizedBox(width: 32)), // زر الحذف
                  DataColumn(
                      label: SizedBox(width: 200, child: Text('التفاصيل')),
                      numeric: false), // اسم الصنف عريض
                  DataColumn(
                      label: SizedBox(width: 60, child: Text('العدد')),
                      numeric: true),
                  DataColumn(
                      label: SizedBox(width: 80, child: Text('نوع البيع')),
                      numeric: false),
                  DataColumn(
                      label: SizedBox(width: 70, child: Text('السعر')),
                      numeric: true),
                  DataColumn(
                      label: SizedBox(width: 70, child: Text('عدد الوحدات')),
                      numeric: true),
                  DataColumn(
                      label: SizedBox(width: 80, child: Text('المبلغ')),
                      numeric: true),
                ],
                rows: [
                  ...List.generate(completedItems.length, (index) {
                    final item = completedItems[index];
                    int displayIndex = index + 1;
                    final product = _findProductByName(item.productName);
                    return DataRow(
                      cells: [
                        DataCell(SizedBox(
                            width: 28,
                            child:
                                Center(child: Text(displayIndex.toString())))),
                        DataCell(IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'حذف',
                          onPressed: () => _removeRow(index),
                        )),
                        DataCell(Text(item.productName ?? '',
                            style: const TextStyle(fontSize: 15))),
                        DataCell(Text(item.quantity?.toString() ?? '',
                            style: const TextStyle(fontSize: 15),
                            textAlign: TextAlign.center)),
                        DataCell(Text(item.unitType ?? '',
                            style: const TextStyle(fontSize: 15))),
                        DataCell(Text(item.price == null ? '' : _fmt(item.price!),
                            style: const TextStyle(fontSize: 15),
                            textAlign: TextAlign.center)),
                        DataCell(Center(
                            child: Text(_getUnitsCount(product, item.unitType),
                                style: const TextStyle(fontSize: 15)))),
                        DataCell(Center(
                            child: Text(
                                item.isComplete ? _fmt(item.total) : '',
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold)))),
                      ],
                    );
                  }),
                  // صف الإدخال الفارغ الدائم
                  DataRow(
                    color: MaterialStateProperty.all(Colors.grey[100]),
                    cells: [
                      DataCell(SizedBox(width: 28)),
                      DataCell(const SizedBox(width: 32)),
                      DataCell(
                        SafeAutocomplete<String>(
                          optionsBuilder: (textEditingValue) {
                            if (textEditingValue.text == '') {
                              return const Iterable<String>.empty();
                            }
                            return widget.products.map((p) => p.name).where(
                                (option) =>
                                    option.contains(textEditingValue.text));
                          },
                          fieldViewBuilder: (context, controller, focusNode,
                              onFieldSubmitted) {
                            productControllers.last = controller;
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                  border: InputBorder.none),
                              style: const TextStyle(fontSize: 15),
                              onChanged: (val) {
                                items.last.productName = val;
                                final prod = _findProductByName(val);
                                final units = _getUnitsForProduct(prod);
                                availableUnitsPerRow.last = units;
                                if (!units.contains(items.last.unitType)) {
                                  items.last.unitType = null;
                                  selectedUnitTypes.last = null;
                                }
                                _onRowChanged(items.length - 1);
                              },
                              onSubmitted: (_) {
                                FocusScope.of(context).nextFocus();
                              },
                            );
                          },
                          onSelected: (val) {
                            setState(() {
                              items.last.productName = val;
                              final prod = _findProductByName(val);
                              final units = _getUnitsForProduct(prod);
                              availableUnitsPerRow.last = units;
                              if (!units.contains(items.last.unitType)) {
                                items.last.unitType = null;
                                selectedUnitTypes.last = null;
                              }
                              _onRowChanged(items.length - 1);
                            });
                          },
                        ),
                      ),
                      DataCell(TextField(
                        controller: quantityControllers.last,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration:
                            const InputDecoration(border: InputBorder.none),
                        style: const TextStyle(fontSize: 15),
                        textAlign: TextAlign.center,
                        onChanged: (val) {
                          items.last.quantity = int.tryParse(val.replaceAll(',', ''));
                          _onRowChanged(items.length - 1);
                        },
                        onSubmitted: (_) {
                          FocusScope.of(context).nextFocus();
                        },
                        inputFormatters: [
                          ThousandSeparatorDecimalInputFormatter(),
                        ],
                      )),
                      DataCell(DropdownButton<String>(
                        value: selectedUnitTypes.last ?? items.last.unitType,
                        hint: const Text('اختر'),
                        items: availableUnitsPerRow.last.map((type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedUnitTypes.last = val;
                            items.last.unitType = val;
                            _onRowChanged(items.length - 1);
                          });
                        },
                        style:
                            const TextStyle(fontSize: 15, color: Colors.black),
                      )),
                      DataCell(TextField(
                        controller: priceControllers.last,
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true),
                        decoration:
                            const InputDecoration(border: InputBorder.none),
                        style: const TextStyle(fontSize: 15),
                        textAlign: TextAlign.center,
                        onChanged: (val) {
                          items.last.price = double.tryParse(val.replaceAll(',', ''));
                          _onRowChanged(items.length - 1);
                        },
                        onSubmitted: (_) {
                          FocusScope.of(context).nextFocus();
                        },
                        inputFormatters: [
                          ThousandSeparatorDecimalInputFormatter(),
                        ],
                      )),
                      DataCell(Center(
                          child: Text(
                              _getUnitsCount(
                                  _findProductByName(items.last.productName),
                                  items.last.unitType),
                              style: const TextStyle(fontSize: 15)))),
                      DataCell(Center(
                          child: Text(
                              items.last.isComplete
                                  ? items.last.total.toStringAsFixed(2)
                                  : '',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold)))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('الإجمالي: ',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(_fmt(totalSum),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
