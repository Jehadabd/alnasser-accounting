// lib/services/database/dao/supplier_dao.dart
// عمليات CRUD للموردين (Odoo Style)

import 'package:sqflite/sqflite.dart';
import '../../database_service.dart';
import '../core/database_helpers.dart';
import '../../../models/supplier.dart'; // ستحتاج لإنشاء هذا الموديل لاحقاً

class SupplierDao {
  final Future<Database> Function() getDatabase;

  SupplierDao({required this.getDatabase});

  /// إدراج مورد
  Future<int> insertSupplier(Map<String, dynamic> supplierMap) async {
    final db = await getDatabase();
    try {
      supplierMap['created_at'] = DateTime.now().toIso8601String();
      supplierMap['updated_at'] = DateTime.now().toIso8601String();
      return await db.insert('suppliers', supplierMap);
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب جميع الموردين
  Future<List<Map<String, dynamic>>> getAllSuppliers() async {
    final db = await getDatabase();
    try {
      return await db.query('suppliers', orderBy: 'name ASC');
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// تحديث مورد
  Future<int> updateSupplier(int id, Map<String, dynamic> supplierMap) async {
    final db = await getDatabase();
    try {
      supplierMap['updated_at'] = DateTime.now().toIso8601String();
      return await db.update(
        'suppliers',
        supplierMap,
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// حذف مورد
  Future<int> deleteSupplier(int id) async {
    final db = await getDatabase();
    try {
      return await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// البحث عن الموردين
  Future<List<Map<String, dynamic>>> searchSuppliers(String query) async {
    final db = await getDatabase();
    try {
      return await db.query(
        'suppliers',
        where: 'name LIKE ? OR phone LIKE ?',
        whereArgs: ['%$query%', '%$query%'],
        limit: 50,
      );
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }
}
