// lib/services/customer_merge_service.dart
// 🔗 دمج الحسابات المكررة في سجل الديون (بتأكيد المستخدم فقط)
//
// كل دمج: نسخة احتياطية كاملة أولاً ← الدمج في معاملة واحدة (يُلغى كله إن
// لم يساوِ الرصيد بعده مجموع الأرصدة قبله) ← إعادة بناء السلسلة التراكمية
// (الرصيد قبل/بعد لكل معاملة) للحساب الباقي ← تفعيل قيد «الاسم فريد» في
// القاعدة إن لم يبقَ تكرار.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database/business/customer_name_rule.dart';
import 'database_service.dart';
import 'firebase_sync/firebase_sync_config.dart';

class CustomerMergeService {
  CustomerMergeService._();

  /// هل الدمج متاح على هذا الجهاز؟ (معطّل مع المزامنة السحابية — انظر
  /// [CustomerNameRule.applyIndexForMode]).
  static Future<bool> isAvailable() async => !(await FirebaseSyncConfig.isEnabled());

  static Future<List<DuplicateCustomerGroup>> duplicateGroups() async {
    final db = await DatabaseService().database;
    await CustomerNameRule.ensureSchema(db);
    return CustomerNameRule.duplicateGroups(db);
  }

  /// نسخة احتياطية كاملة قبل الدمج (لا تُحذف تلقائياً). تعيد مسارها.
  static Future<String> backupBeforeMerge() async {
    final db = await DatabaseService().database;
    final source = File(db.path);
    if (!await source.exists()) {
      throw StateError('الدمج يتم من الحاسبة التي تحمل قاعدة البيانات (حاسبة السيرفر)');
    }
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    Directory dir;
    try {
      final docs = await getApplicationDocumentsDirectory();
      dir = Directory(p.join(docs.path, 'دفتر_ديوني_نسخ_احتياطية', 'قبل_دمج_الحسابات'));
    } catch (_) {
      dir = Directory(p.join(Directory.current.path, 'backups', 'قبل_دمج_الحسابات'));
    }
    await dir.create(recursive: true);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}-${two(now.minute)}-${two(now.second)}';
    final target = p.join(dir.path, 'قبل_الدمج_$stamp.db');
    await source.copy(target);
    final wal = File('${db.path}-wal');
    if (await wal.exists()) await wal.copy('$target-wal');
    return target;
  }

  /// يدمج [mergedIds] في [survivorId] بعد نسخة احتياطية. يعيد نتيجة الدمج
  /// ومسار النسخة.
  static Future<({CustomerMergeResult result, String backupPath})> merge(
    int survivorId,
    List<int> mergedIds,
  ) async {
    if (!await isAvailable()) {
      throw StateError('دمج الحسابات معطّل مع المزامنة السحابية');
    }
    final backupPath = await backupBeforeMerge();
    final dbService = DatabaseService();
    final db = await dbService.database;
    final result = await CustomerNameRule.mergeInto(db, survivorId, mergedIds);

    // السلسلة التراكمية للحساب الباقي (المعاملات المنقولة تأخذ مكانها بالتاريخ)
    await dbService.recalculateCustomerTransactionBalances(survivorId);
    await dbService.recalculateAndApplyCustomerDebt(survivorId);

    final indexActive = await CustomerNameRule.applyIndexForMode(db, cloudSync: false);
    return (
      result: CustomerMergeResult(
        survivorId: result.survivorId,
        mergedIds: result.mergedIds,
        balanceBefore: result.balanceBefore,
        balanceAfter: result.balanceAfter,
        uniqueIndexActive: indexActive,
      ),
      backupPath: backupPath,
    );
  }
}
