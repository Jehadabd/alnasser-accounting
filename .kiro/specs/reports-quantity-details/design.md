# Design Document

## Overview

تحسين تقارير الأشخاص والبضاعة بإضافة:
1. نسبة الربح لكل عميل في تقارير الأشخاص
2. زر "المنتجات المشتراة" لعرض تفاصيل مشتريات العميل
3. زر "العملاء المشترين" لعرض من اشترى منتج معين
4. التحويل الهرمي للكميات (متر→لفة، قطعة→كرتون)
5. ثلاثة خيارات للترتيب: كمية، مبلغ، ربح

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      UI Layer                                │
├─────────────────────────────────────────────────────────────┤
│  PeopleReportsScreen    │    ProductReportsScreen           │
│  ├─ PersonCard          │    ├─ ProductCard                 │
│  │  └─ نسبة الربح       │    │  └─ زر العملاء المشترين      │
│  │  └─ زر المنتجات      │    │                              │
│  └─ CustomerProductsDialog│   └─ ProductCustomersDialog     │
├─────────────────────────────────────────────────────────────┤
│                    Service Layer                             │
├─────────────────────────────────────────────────────────────┤
│  ReportsService (existing - lib/services/reports_service.dart)│
│  ├─ getCustomerProductsPurchased()  [NEW - دالة حسابية]     │
│  ├─ getProductCustomersBought()     [NEW - دالة حسابية]     │
│  └─ calculateHierarchicalDisplay()  [NEW - دالة تحويل]      │
│                                                              │
│  ملاحظة: لا تخزين بيانات جديدة - فقط حسابات وقت التشغيل     │
├─────────────────────────────────────────────────────────────┤
│                    Data Layer (existing)                     │
├─────────────────────────────────────────────────────────────┤
│  invoices + invoice_items + products + customers             │
│  (لا تغييرات على قاعدة البيانات)                            │
└─────────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### 1. CustomerProductsDialog (جديد)
Dialog يعرض المنتجات التي اشتراها عميل معين.

```dart
class CustomerProductsDialog extends StatefulWidget {
  final int customerId;
  final String customerName;
  final int? year;   // null = كل السنوات
  final int? month;  // null = كل الأشهر
}
```

### 2. ProductCustomersDialog (جديد)
Dialog يعرض العملاء الذين اشتروا منتج معين.

```dart
class ProductCustomersDialog extends StatefulWidget {
  final int productId;
  final String productName;
  final int? year;
  final int? month;
}
```

### 3. SortOption Enum
```dart
enum SortOption {
  byQuantity,  // الأكثر سحباً (كمية)
  byAmount,    // الأكثر سحباً (مبلغ)
  byProfit,    // الأكثر ربحاً
}
```

### 4. Database Service Methods (جديدة)

```dart
// جلب المنتجات التي اشتراها عميل
Future<List<CustomerProductData>> getCustomerProductsPurchased({
  required int customerId,
  int? year,
  int? month,
});

// جلب العملاء الذين اشتروا منتج
Future<List<ProductCustomerData>> getProductCustomersBought({
  required int productId,
  int? year,
  int? month,
});
```

## Data Models

### CustomerProductData (جديد)
```dart
class CustomerProductData {
  final int productId;
  final String productName;
  final String baseUnit;           // قطعة أو متر
  final double totalQuantity;      // الكمية بالوحدة الأساسية
  final double totalAmount;        // المبلغ الإجمالي
  final double totalProfit;        // الربح
  final String? largeUnitName;     // اسم الوحدة الكبيرة (لفة/كرتون)
  final double? unitsInLargeUnit;  // عدد الوحدات في الوحدة الكبيرة
  
  // حساب التحويل الهرمي
  String get hierarchicalDisplay {
    if (largeUnitName == null || unitsInLargeUnit == null || unitsInLargeUnit! <= 0) {
      return '$totalQuantity $baseUnit';
    }
    final largeUnits = totalQuantity / unitsInLargeUnit!;
    return '$totalQuantity $baseUnit = ${largeUnits.toStringAsFixed(1)} $largeUnitName';
  }
}
```

### ProductCustomerData (جديد)
```dart
class ProductCustomerData {
  final int customerId;
  final String customerName;
  final double totalQuantity;
  final double totalAmount;
  final double totalProfit;
  
  // التحويل الهرمي يُحسب من بيانات المنتج
}
```



## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Profit Margin Calculation
*For any* customer with totalSales > 0, the profit margin SHALL equal (totalProfit / totalSales * 100) rounded to one decimal place.
**Validates: Requirements 1.2**

### Property 2: Hierarchical Display Formatting
*For any* product with a defined unit hierarchy (largeUnitName and unitsInLargeUnit > 0), the hierarchicalDisplay SHALL show "X baseUnit = Y largeUnitName" where Y = X / unitsInLargeUnit with one decimal precision.
**Validates: Requirements 2.4, 4.4, 7.5**

### Property 3: Sorting by Quantity
*For any* list of items sorted by quantity, each item's quantity SHALL be greater than or equal to the next item's quantity (descending order).
**Validates: Requirements 2.6, 3.2, 4.5, 5.2**

### Property 4: Sorting by Amount
*For any* list of items sorted by amount, each item's totalAmount SHALL be greater than or equal to the next item's totalAmount (descending order).
**Validates: Requirements 3.3, 5.3**

### Property 5: Sorting by Profit
*For any* list of items sorted by profit, each item's totalProfit SHALL be greater than or equal to the next item's totalProfit (descending order).
**Validates: Requirements 3.4, 5.4**

### Property 6: Unit Conversion Accuracy
*For any* product, the conversion from base units to large units SHALL use the product's defined unitsInLargeUnit (for pieces) or lengthPerUnit (for meters).
**Validates: Requirements 7.1, 7.2, 7.3, 7.4**

### Property 7: Time Period Filtering
*For any* query with year and/or month filters, all returned records SHALL have invoice dates within the specified time period.
**Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5**

## Error Handling

1. **Division by Zero**: When totalSales = 0, profit margin displays as "0%"
2. **Missing Hierarchy**: Products without unit hierarchy show only base quantity
3. **Empty Results**: Display "لا توجد بيانات" message when no data found
4. **Database Errors**: Show error snackbar and allow retry

## Testing Strategy

### Unit Tests
- Test profit margin calculation with various inputs
- Test hierarchical display formatting
- Test sorting functions for all three options

### Property-Based Tests
Using `flutter_test` with custom generators:
- Generate random customer/product data
- Verify sorting properties hold for all generated data
- Verify conversion calculations are accurate

### Integration Tests
- Test database queries return correct filtered data
- Test UI displays correct information from database

## UI Mockups

### CustomerProductsDialog Layout
```
┌─────────────────────────────────────────┐
│  المنتجات المشتراة - [اسم العميل]        │
├─────────────────────────────────────────┤
│  [الأكثر سحباً (كمية) ▼]                │
├─────────────────────────────────────────┤
│  ┌─────────────────────────────────┐    │
│  │ 📦 واير دش                      │    │
│  │ الكمية: 500 متر = 5 لفات       │    │
│  │ المبلغ: 500,000 د.ع            │    │
│  │ الربح: 75,000 د.ع              │    │
│  └─────────────────────────────────┘    │
│  ┌─────────────────────────────────┐    │
│  │ 📦 سيات                         │    │
│  │ الكمية: 24 قطعة = 2 كرتون      │    │
│  │ المبلغ: 120,000 د.ع            │    │
│  │ الربح: 18,000 د.ع              │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

### ProductCustomersDialog Layout
```
┌─────────────────────────────────────────┐
│  العملاء المشترين - [اسم المنتج]         │
├─────────────────────────────────────────┤
│  [الأكثر سحباً (كمية) ▼]                │
├─────────────────────────────────────────┤
│  ┌─────────────────────────────────┐    │
│  │ 👤 أحمد محمد                    │    │
│  │ الكمية: 200 متر = 2 لفات       │    │
│  │ المبلغ: 200,000 د.ع            │    │
│  │ الربح: 30,000 د.ع              │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```
