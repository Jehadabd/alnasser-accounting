// lib/services/database/business/invoice_verification.dart
import 'package:sqflite/sqflite.dart';
import '../../../utils/money_calculator.dart';

class InvoiceVerification {
  final Future<Database> Function() getDatabase;

  InvoiceVerification({required this.getDatabase});

  /// إعادة حساب المجاميع لجميع الفواتير في النظام
  Future<Map<String, dynamic>> recalculateAllInvoiceTotals() async {
    final db = await getDatabase();
    int fixedCount = 0;
    int checkedCount = 0;
    
    // 1. جلب كل الفواتير
    final invoices = await db.query('invoices');
    
    for (final invoice in invoices) {
      checkedCount++;
      final id = invoice['id'] as int;
      final currentTotal = (invoice['total_amount'] as num).toDouble();
      
      // 2. حساب المجموع من العناصر
      final items = await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);
      double calculatedTotal = 0.0;
      
      for (final item in items) {
         calculatedTotal += (item['item_total'] as num).toDouble();
      }
      
      // 3. إضافة الرسوم والخصومات
      // final loadingFee = (invoice['loading_fee'] as num?)?.toDouble() ?? 0.0;
      // final discount = (invoice['discount'] as num?)?.toDouble() ?? 0.0;
      // calculatedTotal = calculatedTotal + loadingFee - discount;
      
      // 4. المقارنة والتصحيح
      if (!MoneyCalculator.areEqual(currentTotal, calculatedTotal)) {
        await db.update(
          'invoices', 
          {'total_amount': calculatedTotal},
          where: 'id = ?',
          whereArgs: [id]
        );
        fixedCount++;
      }
    }
    
    return {
      'checked': checkedCount,
      'fixed': fixedCount,
    };
  }
}
