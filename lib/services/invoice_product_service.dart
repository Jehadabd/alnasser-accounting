// services/invoice_product_service.dart
import '../models/product.dart';
import 'package:flutter/material.dart';
import 'dart:convert';

class InvoiceProductService {
  static void onProductSelected({
    required Product product,
    required TextEditingController quantityController,
    required void Function(Product?) setSelectedProduct,
    required void Function(List<Map<String, dynamic>>) setCurrentUnitHierarchy,
    required void Function(List<String>) setCurrentUnitOptions,
    required void Function(String) setSelectedUnitForItem,
    required void Function(double?) setSelectedPriceLevel,
    required String selectedListType,
    required void Function(bool) setSuppressSearch,
    required TextEditingController productSearchController,
    required void Function(bool) setQuantityAutofocus,
    required BuildContext context,
  }) {
    setSelectedProduct(product);
    quantityController.clear();
    setCurrentUnitHierarchy([]);
    setCurrentUnitOptions([]);
    if (product.unit == 'piece') {
      setCurrentUnitOptions(['قطعة']);
      setSelectedUnitForItem('قطعة');
      if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
        try {
          final List<dynamic> parsed =
              json.decode(product.unitHierarchy!.replaceAll("'", '"'));
          final hierarchy =
              parsed.map((e) => Map<String, dynamic>.from(e)).toList();
          setCurrentUnitHierarchy(hierarchy);
          setCurrentUnitOptions([
            'قطعة',
            ...hierarchy
                .map((e) => (e['unit_name'] ?? e['name'] ?? '').toString())
          ]);
        } catch (e) {
          print('Error parsing unit hierarchy for ${product.name}: $e');
        }
      }
    } else if (product.unit == 'meter') {
      setCurrentUnitOptions(['متر']);
      setSelectedUnitForItem('متر');
      if (product.lengthPerUnit != null && product.lengthPerUnit! > 0) {
        setCurrentUnitOptions(['متر', 'لفة']);
      }
    } else {
      setCurrentUnitOptions([product.unit]);
      setSelectedUnitForItem(product.unit);
    }
    double? newPriceLevel;
    switch (selectedListType) {
      case 'مفرد':
        newPriceLevel = product.price1;
        break;
      case 'جملة':
        newPriceLevel = product.price2;
        break;
      case 'جملة بيوت':
        newPriceLevel = product.price3;
        break;
      case 'بيوت':
        newPriceLevel = product.price4;
        break;
      case 'أخرى':
        newPriceLevel = product.price5;
        break;
      default:
        newPriceLevel = product.price1;
    }
    if (newPriceLevel == null || newPriceLevel == 0) {
      setSelectedPriceLevel(null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('المنتج المحدد لا يملك سعر "$selectedListType".'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      final validPrices = [
        product.price1,
        product.price2,
        product.price3,
        product.price4,
        product.price5
      ].where((p) => p != null && p > 0).toList();
      if (validPrices.contains(newPriceLevel)) {
        setSelectedPriceLevel(newPriceLevel);
      } else {
        setSelectedPriceLevel(null);
      }
    }
    setSuppressSearch(true);
    productSearchController.text = product.name;
    setQuantityAutofocus(true);
    Future.delayed(Duration(milliseconds: 100), () {
      FocusScope.of(context).requestFocus(FocusNode());
    });
  }

  static Future<void> searchProducts({
    required String query,
    required Future<List<Product>> Function(String) dbSearchProducts,
    required void Function(List<Product>) setSearchResults,
    required void Function(void Function()) setState,
  }) async {
    if (query.isEmpty) {
      setState(() {
        setSearchResults([]);
      });
      return;
    }
    final results = await dbSearchProducts(query);
    setState(() {
      setSearchResults(results);
    });
  }

  static Future<void> selectDate({
    required BuildContext context,
    required DateTime selectedDate,
    required void Function(DateTime) setSelectedDate,
    required void Function(void Function()) setState,
  }) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('ar', 'SA'),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        setSelectedDate(picked);
      });
    }
  }
}
