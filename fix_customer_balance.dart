import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

/// سكريبت لإصلاح رصيد العميل: محمد العسكر /محلات
/// المشكلة: الرصيد في قاعدة البيانات = 15,754,600 (خاطئ)
/// الرصيد الصحيح من المعاملات = 7,864,600 (صحيح)

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = p.join(
    Platform.environment['APPDATA'] ?? '',
    'com.example',
    'debt_book',
    'debt_book.db',
  );

  print('📂 مسار قاعدة البيانات: $dbPath\n');

  if (!File(dbPath).existsSync()) {
    print('❌ قاعدة البيانات غير موجودة!');
    return;
  }

  // فتح قاعدة البيانات للقراءة والكتابة
  final db = await openDatabase(dbPath);

  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔧 إصلاح رصيد العميل: محمد العسكر /محلات');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // البحث عن العميل
  final customers = await db.query(
    'customers',
    where: 'phone LIKE ?',
    whereArgs: ['%687222%'],
  );

  if (customers.isEmpty) {
    print('❌ لم يتم العثور على العميل!');
    await db.close();
    return;
  }

  final customer = customers.first;
  final customerId = customer['id'] as int;
  final customerName = customer['name'] as String;
  final currentDebt = (customer['current_total_debt'] as num?)?.toDouble() ?? 0.0;

  print('📋 معلومات العميل:');
  print('  الاسم: $customerName');
  print('  ID: $customerId');
  print('  الرصيد الحالي (خاطئ): ${currentDebt.toStringAsFixed(2)}');
  print('');

  // حساب الرصيد الصحيح من المعاملات
  final transactions = await db.query(
    'transactions',
    where: 'customer_id = ?',
    whereArgs: [customerId],
    orderBy: 'transaction_date ASC, created_at ASC',
  );

  print('📊 عدد المعاملات: ${transactions.length}');

  double calculatedBalance = 0.0;
  for (var tx in transactions) {
    final amountChanged = (tx['amount_changed'] as num?)?.toDouble() ?? 0.0;
    calculatedBalance += amountChanged;
  }

  print('💰 الرصيد المحسوب من المعاملات: ${calculatedBalance.toStringAsFixed(2)}');
  print('');

  final difference = (currentDebt - calculatedBalance).abs();
  print('⚠️ الفرق: ${difference.toStringAsFixed(2)}');
  print('');

  // طلب تأكيد من المستخدم
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('هل تريد تحديث الرصيد إلى القيمة الصحيحة؟');
  print('الرصيد الجديد سيكون: ${calculatedBalance.toStringAsFixed(2)}');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('');
  print('اكتب "نعم" للتأكيد أو أي شيء آخر للإلغاء:');
  
  final confirmation = stdin.readLineSync();
  
  if (confirmation?.trim().toLowerCase() == 'نعم' || 
      confirmation?.trim().toLowerCase() == 'yes') {
    
    print('');
    print('🔄 جاري تحديث الرصيد...');
    
    // تحديث الرصيد
    await db.update(
      'customers',
      {
        'current_total_debt': calculatedBalance,
        'last_modified_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );

    print('✅ تم تحديث الرصيد بنجاح!');
    print('');
    
    // التحقق من التحديث
    final updatedCustomer = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );

    if (updatedCustomer.isNotEmpty) {
      final newDebt = (updatedCustomer.first['current_total_debt'] as num?)?.toDouble() ?? 0.0;
      print('💾 الرصيد الجديد في قاعدة البيانات: ${newDebt.toStringAsFixed(2)}');
      
      if ((newDebt - calculatedBalance).abs() < 0.01) {
        print('✅ التحديث ناجح! الرصيد الآن صحيح.');
      } else {
        print('⚠️ تحذير: الرصيد لا يزال غير متطابق!');
      }
    }
  } else {
    print('');
    print('❌ تم إلغاء العملية. لم يتم تحديث الرصيد.');
  }

  await db.close();
  print('');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('تم الانتهاء');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}
