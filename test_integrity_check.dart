// سكريبت لاختبار فحص السلامة المالية
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  final dbPath = '${Platform.environment['APPDATA']}/com.example/debt_book/debt_book.db';
  print('📂 مسار قاعدة البيانات: $dbPath');
  
  final db = await openDatabase(dbPath, readOnly: true);
  
  final customerId = 448; // الهايس / شركه السنابل الذهبية
  
  print('\n' + '=' * 80);
  print('🔍 فحص السلامة المالية للعميل ID: $customerId');
  print('=' * 80);
  
  // التحقق من أعمدة جدول الفواتير
  final cols = await db.rawQuery("PRAGMA table_info(invoices)");
  print('أعمدة جدول الفواتير:');
  for (final col in cols) {
    print('  - ${col['name']}');
  }
  print('');
  
  // جلب جميع فواتير الدين للعميل
  final invoicesResult = await db.rawQuery('''
    SELECT id, invoice_date, total_amount, payment_type, status
    FROM invoices 
    WHERE customer_id = ? AND status = 'محفوظة'
    ORDER BY invoice_date DESC
  ''', [customerId]);
  
  print('\n📄 فحص الفواتير (${invoicesResult.length} فاتورة):');
  print('-' * 80);
  
  int issuesFound = 0;
  
  for (final inv in invoicesResult) {
    final int invoiceId = inv['id'] as int;
    final String invoiceDate = (inv['invoice_date'] as String?) ?? '';
    final double totalAmount = ((inv['total_amount'] as num?) ?? 0).toDouble();
    
    // جلب مجموع المعاملات المرتبطة بهذه الفاتورة
    final txSumResult = await db.rawQuery('''
      SELECT COALESCE(SUM(amount_changed), 0) AS total
      FROM transactions 
      WHERE customer_id = ? AND invoice_id = ?
    ''', [customerId, invoiceId]);
    final double transactionsSum = ((txSumResult.first['total'] as num?) ?? 0).toDouble();
    
    // المقارنة
    final double difference = (totalAmount - transactionsSum).abs();
    
    if (difference > 1) {
      issuesFound++;
      print('\n⚠️ فاتورة #$invoiceId ($invoiceDate):');
      print('   مبلغ الفاتورة (total_amount): $totalAmount');
      print('   مجموع المعاملات: $transactionsSum');
      print('   الفرق: $difference ❌');
      
      // جلب تفاصيل المعاملات
      final txDetails = await db.rawQuery('''
        SELECT id, amount_changed, transaction_type, transaction_date
        FROM transactions 
        WHERE customer_id = ? AND invoice_id = ?
        ORDER BY id ASC
      ''', [customerId, invoiceId]);
      
      print('   المعاملات المرتبطة (${txDetails.length}):');
      for (final tx in txDetails) {
        print('     - #${tx['id']}: ${tx['amount_changed']} (${tx['transaction_type']})');
      }
    } else {
      print('✅ فاتورة #$invoiceId: $totalAmount = $transactionsSum (متطابق)');
    }
  }
  
  print('\n' + '=' * 80);
  if (issuesFound > 0) {
    print('❌ تم العثور على $issuesFound مشكلة!');
  } else {
    print('✅ جميع الفواتير سليمة');
  }
  print('=' * 80);
  
  await db.close();
}
