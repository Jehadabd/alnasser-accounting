import 'package:sqflite/sqflite.dart';
import '../../../models/supplier_delegate.dart';

class SupplierDelegateDao {
  final Future<Database> Function() getDatabase;

  SupplierDelegateDao({required this.getDatabase});

  /// إضافة مندوب جديد
  Future<int> insert(SupplierDelegate delegate) async {
    final db = await getDatabase();
    return await db.insert(
      'supplier_delegates',
      delegate.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// الحصول على قائمة المندوبين لمورد معين
  Future<List<SupplierDelegate>> getBySupplierId(int supplierId) async {
    final db = await getDatabase();
    final List<Map<String, dynamic>> maps = await db.query(
      'supplier_delegates',
      where: 'supplier_id = ? AND is_active = 1',
      whereArgs: [supplierId],
    );

    return List.generate(maps.length, (i) => SupplierDelegate.fromMap(maps[i]));
  }

  /// تحديث بيانات مندوب
  Future<int> update(SupplierDelegate delegate) async {
    final db = await getDatabase();
    return await db.update(
      'supplier_delegates',
      delegate.toMap(),
      where: 'id = ?',
      whereArgs: [delegate.id],
    );
  }

  /// حذف (أو تعطيل) مندوب
  Future<int> delete(int id) async {
    final db = await getDatabase();
    // نفضل التعطيل بدلاً من الحذف للحفاظ على التكامل المرجعي
    return await db.update(
      'supplier_delegates',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
