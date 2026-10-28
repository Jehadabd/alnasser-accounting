// services/database/supplier_compat.dart
//
// 🛡️ جدول suppliers ليس بمخطط واحد في كل القواعد: القواعد القديمة/المستوردة
// فيها company_name NOT NULL (مخطط SuppliersService القديم) بجانب name، والجديدة
// فيها name فقط. أي إدراج لا يملأ عموداً إلزامياً بلا قيمة افتراضية يفشل
// («NOT NULL constraint failed: suppliers.company_name»).
//
// هذه الدالة تكيّف خريطة الإدراج مع أعمدة الجدول الفعلية: تملأ الأعمدة الإلزامية
// الناقصة (company_name = name، نص فارغ أو صفر لغيرها)، وتحذف المفاتيح التي لا
// عمود لها.
import 'package:sqflite/sqflite.dart';

Future<Map<String, dynamic>> supplierInsertCompat(DatabaseExecutor db, Map<String, dynamic> m) async {
  final cols = await db.rawQuery('PRAGMA table_info(suppliers)');
  if (cols.isEmpty) return m;
  final names = {for (final c in cols) '${c['name']}'};
  final out = <String, dynamic>{
    for (final e in m.entries)
      if (names.contains(e.key)) e.key: e.value,
  };
  for (final c in cols) {
    final n = '${c['name']}';
    final notNull = c['notnull'] == 1;
    final pk = c['pk'] == 1;
    if (!notNull || pk || c['dflt_value'] != null || out[n] != null) continue;
    if (n == 'company_name') {
      out[n] = m['name'] ?? m['company_name'] ?? '';
    } else if (n == 'name') {
      out[n] = m['company_name'] ?? '';
    } else if (n.endsWith('_at')) {
      out[n] = DateTime.now().toIso8601String();
    } else {
      final t = '${c['type'] ?? ''}'.toUpperCase();
      out[n] = (t.contains('INT') || t.contains('REAL') || t.contains('NUM')) ? 0 : '';
    }
  }
  return out;
}

/// عند تعديل اسم المورد في قاعدة فيها company_name قديم: نُبقيه مطابقاً لـ name
/// حتى لا يظهر الاسم القديم في أي شاشة تقرأ company_name.
Future<Map<String, dynamic>> supplierUpdateCompat(DatabaseExecutor db, Map<String, dynamic> m) async {
  if (!m.containsKey('name')) return m;
  final cols = await db.rawQuery('PRAGMA table_info(suppliers)');
  if (cols.any((c) => c['name'] == 'company_name')) {
    return {...m, 'company_name': m['name'] ?? ''};
  }
  return m;
}
