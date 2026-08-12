
class OcrInvoiceItem {
  final String rawName;
  final String? detectedUnit;
  final double quantity;
  final double totalPrice;
  final double? unitPrice; // Calculated or extracted
  
  // Status: 
  // 'matched': Found in DB exactly.
  // 'ambiguous': Found similar names.
  // 'new': Not found.
  String status; 
  
  // If matched or user selects a product
  int? matchedProductId;
  String? matchedProductName;
  
  // Conversion Factor (if unit differs)
  // e.g. Invoice has "Carton", System has "Piece". Factor = 12.
  double? conversionFactor; 

  OcrInvoiceItem({
    required this.rawName,
    this.detectedUnit,
    this.quantity = 0.0,
    this.totalPrice = 0.0,
    this.unitPrice,
    this.status = 'new',
    this.matchedProductId,
    this.matchedProductName,
    this.conversionFactor,
  });

  OcrInvoiceItem copyWith({
    String? rawName,
    String? detectedUnit,
    double? quantity,
    double? totalPrice,
    double? unitPrice,
    String? status,
    int? matchedProductId,
    String? matchedProductName,
    double? conversionFactor,
  }) {
    return OcrInvoiceItem(
      rawName: rawName ?? this.rawName,
      detectedUnit: detectedUnit ?? this.detectedUnit,
      quantity: quantity ?? this.quantity,
      totalPrice: totalPrice ?? this.totalPrice,
      unitPrice: unitPrice ?? this.unitPrice,
      status: status ?? this.status,
      matchedProductId: matchedProductId ?? this.matchedProductId,
      matchedProductName: matchedProductName ?? this.matchedProductName,
      conversionFactor: conversionFactor ?? this.conversionFactor,
    );
  }
}
