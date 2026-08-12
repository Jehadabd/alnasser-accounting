// lib/services/database/dao/receipt_dao.dart
// عمليات سندات القبض

import 'package:sqflite/sqflite.dart';
import '../../database_service.dart';
import '../core/database_helpers.dart';

class ReceiptDao {
  final Future<Database> Function() getDatabase;

  ReceiptDao({required this.getDatabase});

  /// إدراج سند قبض (أرشفة)
  Future<int> insertReceiptVoucher(Map<String, dynamic> voucher) async {
    final db = await getDatabase();
    try {
      if (!voucher.containsKey('created_at')) {
        voucher['created_at'] = DateTime.now().toIso8601String();
      }
      return await db.insert('customer_receipt_vouchers', voucher);
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب سندات قبض لعميل
  Future<List<Map<String, dynamic>>> getReceiptsByCustomer(int customerId) async {
    final db = await getDatabase();
    try {
      return await db.query(
        'customer_receipt_vouchers',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب سند قبض برقم الإيصال
  Future<Map<String, dynamic>?> getReceiptByNumber(int receiptNumber) async {
    final db = await getDatabase();
    try {
      final results = await db.query(
        'customer_receipt_vouchers',
        where: 'receipt_number = ?',
        whereArgs: [receiptNumber],
        limit: 1,
      );
      if (results.isNotEmpty) return results.first;
      return null;
    } catch (e) {
      return null;
    }
  }
}
