// services/temp_invoice_service.dart
import 'package:get_storage/get_storage.dart';
import '../models/invoice_item.dart';

class TempInvoiceService {
  static const String _storageKey = 'temp_invoice_data';
  static final GetStorage _box = GetStorage();

  // حفظ البيانات المؤقتة
  static Future<void> saveTempInvoiceData({
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    required String installerName,
    required DateTime invoiceDate,
    required String paymentType,
    required double discount,
    required String paidAmount,
    required List<InvoiceItem> invoiceItems,
  }) async {
    final data = {
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerAddress': customerAddress,
      'installerName': installerName,
      'invoiceDate': invoiceDate.millisecondsSinceEpoch,
      'paymentType': paymentType,
      'discount': discount,
      'paidAmount': paidAmount,
      'invoiceItems': invoiceItems
          .map((item) => {
                'productName': item.productName,
                'unit': item.unit,
                'unitPrice': item.unitPrice,
                'costPrice': item.costPrice,
                'quantityIndividual': item.quantityIndividual,
                'quantityLargeUnit': item.quantityLargeUnit,
                'appliedPrice': item.appliedPrice,
                'itemTotal': item.itemTotal,
                'saleType': item.saleType,
              })
          .toList(),
      'lastModified': DateTime.now().millisecondsSinceEpoch,
    };

    await _box.write(_storageKey, data);
    print(
        'DEBUG: TempInvoiceService - Saved temp data with ${invoiceItems.length} items');
  }

  // تحميل البيانات المؤقتة
  static Map<String, dynamic>? loadTempInvoiceData() {
    final data = _box.read(_storageKey);
    if (data != null) {
      print(
          'DEBUG: TempInvoiceService - Loaded temp data with ${(data['invoiceItems'] as List).length} items');
    }
    return data;
  }

  // حذف البيانات المؤقتة
  static Future<void> clearTempInvoiceData() async {
    await _box.remove(_storageKey);
    print('DEBUG: TempInvoiceService - Cleared temp data');
  }

  // التحقق من وجود بيانات مؤقتة
  static bool hasTempInvoiceData() {
    return _box.hasData(_storageKey);
  }

  // تحويل البيانات المحفوظة إلى InvoiceItem
  static List<InvoiceItem> parseInvoiceItems(List<dynamic> itemsData) {
    return itemsData
        .map((itemData) => InvoiceItem(
              invoiceId: 0,
              productName: itemData['productName'] ?? '',
              unit: itemData['unit'] ?? '',
              unitPrice: itemData['unitPrice'] ?? 0.0,
              costPrice: itemData['costPrice'],
              quantityIndividual: itemData['quantityIndividual'],
              quantityLargeUnit: itemData['quantityLargeUnit'],
              appliedPrice: itemData['appliedPrice'] ?? 0.0,
              itemTotal: itemData['itemTotal'] ?? 0.0,
              saleType: itemData['saleType'],
            ))
        .toList();
  }

  // تحويل التاريخ من milliseconds
  static DateTime parseInvoiceDate(int milliseconds) {
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
}
