// lib/services/database/dao/category_dao.dart
// عمليات CRUD للتصنيفات

import 'package:sqflite/sqflite.dart';
import '../../database_service.dart';
import '../core/database_helpers.dart';
import '../../../models/category.dart';

class CategoryDao {
  final Future<Database> Function() getDatabase;

  CategoryDao({required this.getDatabase});

  /// إدراج تصنيف
  Future<int> insertCategory(Category category) async {
    final db = await getDatabase();
    try {
      return await db.insert('categories', category.toMap());
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب جميع التصنيفات
  Future<List<Category>> getAllCategories() async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps = await db.query('categories');
      return List.generate(maps.length, (i) => Category.fromMap(maps[i]));
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// تحديث تصنيف
  Future<int> updateCategory(Category category) async {
    final db = await getDatabase();
    try {
      return await db.update(
        'categories',
        category.toMap(),
        where: 'id = ?',
        whereArgs: [category.id],
      );
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// حذف تصنيف
  Future<int> deleteCategory(int id) async {
    final db = await getDatabase();
    try {
      // التحقق من وجود أبناء
      final childrenCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM categories WHERE parent_id = ?', 
        [id]
      ));
      if (childrenCount != null && childrenCount > 0) {
        throw Exception('لا يمكن حذف تصنيف يحتوي على تصنيفات فرعية');
      }

      // التحقق من وجود منتجات مرتبطة
      final productsCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM products WHERE category_id = ?', 
        [id]
      ));
      if (productsCount != null && productsCount > 0) {
        throw Exception('لا يمكن حذف تصنيف مرتبط بمنتجات');
      }

      return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب شجرة التصنيفات
  Future<List<Category>> getCategoryTree() async {
    final allCategories = await getAllCategories();
    final Map<int, Category> categoryMap = {for (var c in allCategories) c.id!: c};
    final List<Category> roots = [];

    for (var cat in allCategories) {
      if (cat.parentId == null) {
        roots.add(cat);
      } else {
        if (categoryMap.containsKey(cat.parentId)) {
          // في هذا النموذج البسيط، الـ Model قد لا يدعم children list مباشرة
          // لكن هذا الهيكل يسمح ببناء الشجرة في الـ UI
        }
      }
    }
    return roots;
  }
}
