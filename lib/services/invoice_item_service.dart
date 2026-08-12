// services/invoice_item_service.dart
import '../models/invoice_item.dart';
import '../models/product.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/invoice.dart';
import '../models/line_item_focus_nodes.dart';

class InvoiceItemService {
  static void addInvoiceItem({
    required GlobalKey<FormState> formKey,
    required Product? selectedProduct,
    required double? selectedPriceLevel,
    required TextEditingController quantityController,
    required String selectedUnitForItem,
    required List<Map<String, dynamic>> currentUnitHierarchy,
    required List<InvoiceItem> invoiceItems,
    required List<LineItemFocusNodes> focusNodesList,
    required TextEditingController productSearchController,
    required void Function(Product?) setSelectedProduct,
    required void Function(double?) setSelectedPriceLevel,
    required void Function(List<Product>) setSearchResults,
    required void Function(String) setSelectedUnitForItem,
    required void Function(List<Map<String, dynamic>>) setCurrentUnitHierarchy,
    required void Function(List<String>) setCurrentUnitOptions,
    required void Function(void Function()) setState,
    required void Function() guardDiscount,
    required void Function() updatePaidAmountIfCash,
    required void Function() autoSave,
    required Invoice? invoiceToManage,
    required bool isViewOnly,
    required bool Function(InvoiceItem) isInvoiceItemComplete,
  }) {
    if (formKey.currentState!.validate() &&
        selectedProduct != null &&
        selectedPriceLevel != null) {
      final double inputQuantity =
          double.tryParse(quantityController.text.trim()) ?? 0.0;
      if (inputQuantity <= 0) return;
      double finalAppliedPrice = selectedPriceLevel;
      double baseUnitsPerSelectedUnit = 1.0;
      if (selectedProduct.unit == 'piece' &&
          selectedUnitForItem != 'قطعة') {
        if (selectedProduct.unitHierarchy != null &&
            selectedProduct.unitHierarchy!.isNotEmpty) {
          try {
            final List<dynamic> hierarchy =
                json.decode(selectedProduct.unitHierarchy!.replaceAll("'", '"'));
            List<num> factors = [];
            for (int i = 0; i < hierarchy.length; i++) {
              final unitName =
                  hierarchy[i]['unit_name'] ?? hierarchy[i]['name'];
              final quantity =
                  num.tryParse(hierarchy[i]['quantity'].toString()) ?? 1;
              factors.add(quantity);
              if (unitName == selectedUnitForItem) {
                break;
              }
            }
            baseUnitsPerSelectedUnit = factors.fold(1, (a, b) => a * b);
            finalAppliedPrice = selectedPriceLevel * baseUnitsPerSelectedUnit;
          } catch (e) {
            final selectedHierarchyUnit = currentUnitHierarchy.firstWhere(
              (element) =>
                  (element['unit_name'] ?? element['name']) == selectedUnitForItem,
              orElse: () => {},
            );
            if (selectedHierarchyUnit.isNotEmpty) {
              baseUnitsPerSelectedUnit = double.tryParse(
                      selectedHierarchyUnit['quantity'].toString()) ??
                  1.0;
              finalAppliedPrice =
                  selectedPriceLevel * baseUnitsPerSelectedUnit;
            }
          }
        }
      } else if (selectedProduct.unit == 'meter' &&
          selectedUnitForItem == 'لفة') {
        baseUnitsPerSelectedUnit = selectedProduct.lengthPerUnit ?? 1.0;
        finalAppliedPrice = selectedPriceLevel * baseUnitsPerSelectedUnit;
      }
      final double totalBaseUnitsSold =
          inputQuantity * baseUnitsPerSelectedUnit;
      final double finalItemCostPrice =
          (selectedProduct.costPrice ?? 0) * totalBaseUnitsSold;
      final double finalItemTotal = inputQuantity * finalAppliedPrice;
      double? quantityIndividual;
      double? quantityLargeUnit;
      if ((selectedProduct.unit == 'piece' &&
              selectedUnitForItem == 'قطعة') ||
          (selectedProduct.unit == 'meter' &&
              selectedUnitForItem == 'متر')) {
        quantityIndividual = inputQuantity;
      } else {
        quantityLargeUnit = inputQuantity;
      }
      final newItem = InvoiceItem(
        invoiceId: 0,
        productName: selectedProduct.name,
        unit: selectedProduct.unit,
        unitPrice: selectedProduct.unitPrice,
        costPrice: finalItemCostPrice,
        quantityIndividual: quantityIndividual,
        quantityLargeUnit: quantityLargeUnit,
        appliedPrice: finalAppliedPrice,
        itemTotal: finalItemTotal,
        saleType: selectedUnitForItem,
        unitsInLargeUnit:
            baseUnitsPerSelectedUnit != 1.0 ? baseUnitsPerSelectedUnit : null,
      );
      setState(() {
        final existingIndex = invoiceItems.indexWhere((item) =>
            item.productName == newItem.productName &&
            item.saleType == newItem.saleType &&
            item.unit == newItem.unit);
        if (existingIndex != -1) {
          final existingItem = invoiceItems[existingIndex];
          invoiceItems[existingIndex] = existingItem.copyWith(
            quantityIndividual: (existingItem.quantityIndividual ?? 0) +
                (newItem.quantityIndividual ?? 0),
            quantityLargeUnit: (existingItem.quantityLargeUnit ?? 0) +
                (newItem.quantityLargeUnit ?? 0),
            itemTotal: (existingItem.itemTotal) + (newItem.itemTotal),
            costPrice: (existingItem.costPrice ?? 0) + (newItem.costPrice ?? 0),
            unitsInLargeUnit: newItem.unitsInLargeUnit,
          );
        } else {
          invoiceItems.add(newItem);
        }
        productSearchController.clear();
        quantityController.clear();
        setSelectedProduct(null);
        setSelectedPriceLevel(null);
        setSearchResults([]);
        setSelectedUnitForItem('قطعة');
        setCurrentUnitOptions(['قطعة']);
        setCurrentUnitHierarchy([]);
        guardDiscount();
        updatePaidAmountIfCash();
        autoSave();
        if (invoiceToManage != null &&
            invoiceToManage.status == 'معلقة' &&
            (invoiceToManage.isLocked)) {
          autoSave();
        }
        for (int i = invoiceItems.length - 1; i >= 0; i--) {
          if (!isInvoiceItemComplete(invoiceItems[i])) {
            if (focusNodesList.length > i) {
              focusNodesList[i].dispose();
              focusNodesList.removeAt(i);
            }
            invoiceItems.removeAt(i);
          }
        }
        if (invoiceItems.isEmpty ||
            isInvoiceItemComplete(invoiceItems.last)) {
          invoiceItems.add(InvoiceItem(
            invoiceId: 0,
            productName: '',
            unit: '',
            unitPrice: 0.0,
            appliedPrice: 0.0,
            itemTotal: 0.0,
          ));
          focusNodesList.add(LineItemFocusNodes());
        }
        // أضف FocusNode جديد فقط إذا كانت القوائم متزامنة
        if (focusNodesList.length < invoiceItems.length) {
          focusNodesList.add(LineItemFocusNodes());
        }
      });
    }
  }

  static void removeInvoiceItem({
    required int index,
    required List<InvoiceItem> invoiceItems,
    required List<LineItemFocusNodes> focusNodesList,
    required void Function(void Function()) setState,
    required void Function() guardDiscount,
    required void Function() updatePaidAmountIfCash,
    required void Function() autoSave,
    required Invoice? invoiceToManage,
  }) {
    setState(() {
      focusNodesList[index].dispose();
      focusNodesList.removeAt(index);
      invoiceItems.removeAt(index);
      guardDiscount();
      updatePaidAmountIfCash();
      autoSave();
      if (invoiceToManage != null &&
          invoiceToManage.status == 'معلقة' &&
          (invoiceToManage.isLocked)) {
        autoSave();
      }
    });
  }

  static double recalculateTotals(List<InvoiceItem> invoiceItems) {
    return invoiceItems.fold(0, (sum, item) => sum + item.itemTotal);
  }
}
