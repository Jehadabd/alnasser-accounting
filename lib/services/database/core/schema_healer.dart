// lib/services/database/core/schema_healer.dart
// 🩹 مُصلِح المخطط: يكمّل الجداول والأعمدة الناقصة في القواعد القديمة.
//
// المشكلة: بعض الجداول والأعمدة (categories, units, products.barcode ...)
// لا تُنشأ إلا في onCreate (قاعدة جديدة). القاعدة القديمة التي فُتحت قبل
// إضافتها لا تحصل عليها أبداً ⇒ «no such table / no such column».
//
// الحل: نبني «قاعدة مرجعية» في الذاكرة بنفس createTables، ثم نقارنها
// بالقاعدة الحقيقية ونضيف ما ينقص فقط:
//   • جدول ناقص  ⇒ يُنشأ بتعريفه الكامل.
//   • عمود ناقص  ⇒ ALTER TABLE ADD COLUMN (بلا قيود لا يسمح بها SQLite).
//   • فهرس ناقص  ⇒ يُنشأ (ويُتجاهل لو فشل بسبب بيانات مكررة).
// لا حذف ولا تعديل لأي بيانات أو أعمدة موجودة. آمن التكرار.
//
// يُستدعى بعد ensureSchema (حتى تعمل الترحيلات التي تعتمد على غياب عمود
// أولاً)، ثم تعمل بقية مخططات النظام على قاعدة مكتملة.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';

import 'database_doctor.dart' show MaintenanceLog;

class SchemaHealer {
  SchemaHealer._();

  /// [buildReference] يبني المخطط المرجعي الكامل على قاعدة فارغة.
  /// يعيد عدد التغييرات التي أُجريت.
  static Future<int> heal(
    Database db,
    Future<void> Function(Database ref) buildReference,
  ) async {
    Database? ref;
    var changes = 0;
    try {
      ref = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await buildReference(ref);

      final refTables = await ref.rawQuery(
          "SELECT name, sql FROM sqlite_master WHERE type = 'table' AND sql IS NOT NULL");
      final virtualNames = <String>[
        for (final t in refTables)
          if ((t['sql'] as String).toUpperCase().contains('VIRTUAL TABLE'))
            t['name'] as String,
      ];
      bool skip(String name) =>
          name.startsWith('sqlite_') ||
          virtualNames.any((v) => name == v || name.startsWith('${v}_'));

      final existing = {
        for (final r in await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'"))
          r['name'] as String,
      };

      for (final t in refTables) {
        final name = t['name'] as String;
        if (skip(name)) continue;

        if (!existing.contains(name)) {
          try {
            await db.execute(t['sql'] as String);
            changes++;
            debugPrint('🩹 [SchemaHealer] أُنشئ الجدول الناقص: $name');
          } catch (e) {
            debugPrint('⚠️ [SchemaHealer] تعذّر إنشاء $name: $e');
          }
          continue;
        }

        final have = {
          for (final c in await db.rawQuery('PRAGMA table_info("$name")'))
            (c['name'] as String).toLowerCase(),
        };
        for (final c in await ref.rawQuery('PRAGMA table_info("$name")')) {
          final col = c['name'] as String;
          if (have.contains(col.toLowerCase())) continue;
          if ((c['pk'] as int? ?? 0) > 0) continue; // لا يُضاف مفتاح أساسي
          final def = _columnDef(c);
          try {
            await db.execute('ALTER TABLE "$name" ADD COLUMN "$col" $def');
            changes++;
            debugPrint('🩹 [SchemaHealer] أُضيف العمود الناقص: $name.$col');
          } catch (e) {
            debugPrint('⚠️ [SchemaHealer] تعذّر إضافة $name.$col: $e');
          }
        }
      }

      // الفهارس (تحسين أداء فقط — فشلها لا يضر)
      final haveIdx = {
        for (final r in await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'index'"))
          r['name'] as String,
      };
      final refIdx = await ref.rawQuery(
          "SELECT name, tbl_name, sql FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL");
      for (final i in refIdx) {
        final name = i['name'] as String;
        if (haveIdx.contains(name) || skip(i['tbl_name'] as String)) continue;
        try {
          await db.execute(i['sql'] as String);
          changes++;
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('⚠️ [SchemaHealer] تعذّر فحص المخطط: $e');
    } finally {
      try {
        await ref?.close();
      } catch (_) {}
    }
    if (changes > 0) {
      debugPrint('🩹 [SchemaHealer] اكتمل: $changes تغيير');
      MaintenanceLog.add('أُكمل $changes من الجداول والأعمدة والفهارس الناقصة (قاعدة من إصدار آخر)');
    }
    return changes;
  }

  /// تعريف عمود صالح لـ ALTER TABLE ADD COLUMN:
  /// النوع + الافتراضي الثابت فقط؛ NOT NULL فقط مع افتراضي ثابت.
  static String _columnDef(Map<String, Object?> c) {
    final type = (c['type'] as String?)?.trim() ?? '';
    final dflt = c['dflt_value']?.toString();
    final notNull = (c['notnull'] as int? ?? 0) == 1;
    final constDefault = dflt != null &&
        !dflt.toUpperCase().contains('CURRENT_') &&
        !dflt.contains('(');
    final parts = <String>[if (type.isNotEmpty) type];
    if (constDefault) {
      if (notNull) parts.add('NOT NULL');
      parts.add('DEFAULT $dflt');
    }
    return parts.join(' ');
  }
}
