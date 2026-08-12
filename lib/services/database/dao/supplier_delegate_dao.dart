import 'package:sqflite/sqflite.dart';
import '../../../models/supplier_delegate.dart';
import '../core/database_helpers.dart';

class SupplierDelegateDao {
  final Future<Database> Function() getDatabase;

  SupplierDelegateDao({required this.getDatabase});

  /// إضافة مندوب جديد
  Future<int> insert(SupplierDelegate delegate) async {
    final _db = await getDatabase();
    return await _db.insert(
      'supplier_delegates',
      delegate.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// الحصول على قائمة المندوبين لمورد معين
  Future<List<SupplierDelegate>> getBySupplierId(int supplierId) async {
    final _db = await getDatabase();
    final List<Map<String, dynamic>> maps = await _db.query(
      'supplier_delegates',
      where: 'supplier_id = ? AND is_active = 1',
      whereArgs: [supplierId],
    );

    return List.generate(maps.length, (i) => SupplierDelegate.fromMap(maps[i]));
  }

  /// تحديث بيانات مندوب
  Future<int> update(SupplierDelegate delegate) async {
    final _db = await getDatabase();
    return await _db.update(
      'supplier_delegates',
      delegate.toMap(),
      where: 'id = ?',
      whereArgs: [delegate.id],
    );
  }

  /// حذف (أو تعطيل) مندوب
  Future<int> delete(int id) async {
    final _db = await getDatabase();
    // نفضل التعطيل بدلاً من الحذف للحفاظ على التكامل المرجعي
    return await _db.update(
      'supplier_delegates',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
