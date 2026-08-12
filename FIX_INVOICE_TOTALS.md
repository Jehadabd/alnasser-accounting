# إصلاح مجاميع الفواتير الخاطئة

## المشكلة المكتشفة

الفاتورة #122:
- `total_amount` المخزن في قاعدة البيانات: **145** ❌
- مجموع `item_total` الفعلي: **142.5** ✅
- المعروض عند فتح الفاتورة: **142.5** ✅

## السبب

عدم تزامن بين:
1. `invoices.total_amount` (القيمة المخزنة)
2. مجموع `invoice_items.item_total` (القيمة الصحيحة)

## الحل

إضافة دالة `recalculateAllInvoiceTotals()` في `database_service.dart` لإعادة حساب جميع الفواتير.

## الخطوات

### 1. إضافة الدالة في database_service.dart

```dart
/// إعادة حساب مجاميع جميع الفواتير من البنود
Future<Map<String, dynamic>> recalculateAllInvoiceTotals() async {
  final db = await database;
  int fixed = 0;
  int errors = 0;
  final List<String> details = [];
  
  try {
    // جلب جميع الفواتير
    final invoices = await db.query('invoices');
    
    for (var invoice in invoices) {
      final invoiceId = invoice['id'] as int;
      final currentTotal = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
      final discount = (invoice['discount'] as num?)?.toDouble() ?? 0.0;
      
      // حساب المجموع الصحيح من البنود
      final items = await db.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );
      
      double correctTotal = 0.0;
      for (var item in items) {
        correctTotal += (item['item_total'] as num?)?.toDouble() ?? 0.0;
      }
      
      // طرح الخصم
      correctTotal -= discount;
      
      // التحقق من وجود فرق
      if ((currentTotal - correctTotal).abs() > 0.01) {
        // تحديث المجموع
        await db.update(
          'invoices',
          {'total_amount': correctTotal},
          where: 'id = ?',
          whereArgs: [invoiceId],
        );
        
        fixed++;
        details.add('الفاتورة #$invoiceId: ${currentTotal.toStringAsFixed(2)} → ${correctTotal.toStringAsFixed(2)}');
      }
    }
    
    return {
      'success': true,
      'total_invoices': invoices.length,
      'fixed': fixed,
      'errors': errors,
      'details': details,
    };
  } catch (e) {
    return {
      'success': false,
      'error': e.toString(),
    };
  }
}
```

### 2. إضافة زر في AI Chat

في `ai_chat_service.dart`:

```dart
case 'fix_invoice_totals':
  return await _fixInvoiceTotals();
```

```dart
Future<ChatResponse> _fixInvoiceTotals() async {
  try {
    final result = await _dbService.recalculateAllInvoiceTotals();
    
    if (result['success']) {
      final fixed = result['fixed'] as int;
      final total = result['total_invoices'] as int;
      final details = result['details'] as List<String>;
      
      String message = '✅ تم إعادة حساب $total فاتورة\n\n';
      
      if (fixed > 0) {
        message += '🔧 تم تصحيح $fixed فاتورة:\n\n';
        for (var detail in details.take(10)) {
          message += '• $detail\n';
        }
        if (details.length > 10) {
          message += '\n... و ${details.length - 10} فاتورة أخرى';
        }
      } else {
        message += '✅ جميع الفواتير صحيحة!';
      }
      
      return ChatResponse(
        text: message,
        followups: ['تدقيق الفواتير', 'كشف الأخطاء'],
     