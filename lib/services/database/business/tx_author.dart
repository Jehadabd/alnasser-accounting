// lib/services/database/business/tx_author.dart
// 👤 اسم المستخدم الذي أنشأ معاملة الدين أو التسديد.
//
// يُكتب في عمود transactions.created_by_username عند الإدراج في هذا الجهاز
// فقط. المعاملات القادمة بالمزامنة من جهاز آخر تبقى بلا اسم (لا نخمّنه).
// العمود يُضاف عند التشغيل (ensureSchema)؛ قاعدة سيرفر أقدم بلا العمود لا
// يُكتب فيها شيء، فلا يفشل الإدراج.

import 'package:sqflite/sqflite.dart';

class TxAuthor {
  TxAuthor._();

  static const String column = 'created_by_username';

  /// يُضبط عند بدء البرنامج: يعيد اسم المستخدم الحالي.
  static String? Function()? currentName;

  /// نسخة من [row] فيها اسم المستخدم الحالي (إن عُرف ووُجد العمود).
  static Future<Map<String, Object?>> stamped(DatabaseExecutor db, Map<String, Object?> row) async {
    if ((row[column] as String?)?.isNotEmpty ?? false) return row;
    final name = currentName?.call()?.trim() ?? '';
    if (name.isEmpty) return row;
    try {
      final cols = await db.rawQuery('PRAGMA table_info(transactions)');
      if (!cols.any((c) => c['name'] == column)) return row;
    } catch (_) {
      return row;
    }
    return {...row, column: name};
  }
}
