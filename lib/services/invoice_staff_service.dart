// lib/services/invoice_staff_service.dart
//
// 👷 من جهّز الفاتورة ومن حاسبها: يُختاران من «المزيد» في شاشة الفاتورة
// (المحاسب = المستخدم الحالي تلقائياً)، ويُطبعان في التصاميم الجاهزة
// (حقلا «المجهز» و«المحاسب»). والمسمى الوظيفي للموظف (محاسب، مجهز، مدقق...)
// من «الموظفون والصلاحيات» يحدد من يظهر في قائمة الاختيار.
//
// جدول محلي مستقل (لا يمس الفاتورة ولا أرقامها).

import 'package:sqflite/sqflite.dart';

import 'database_service.dart';

class InvoiceStaff {
  InvoiceStaff._();

  /// المسميات المقترحة (يمكن كتابة غيرها)
  static const jobTitles = <String>[
    'محاسب',
    'مجهز',
    'مدقق',
    'كاشير',
    'مندوب مبيعات',
    'أمين مخزن',
    'سائق',
    'مدير',
  ];

  static Future<void> _ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_staff (
        invoice_id INTEGER PRIMARY KEY,
        preparer TEXT,
        accountant TEXT,
        updated_at TEXT
      )''');
  }

  static Future<void> save(int invoiceId, {String? preparer, String? accountant}) async {
    final db = await DatabaseService().database;
    await _ensure(db);
    String? nz(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    await db.rawInsert(
      'INSERT OR REPLACE INTO invoice_staff(invoice_id, preparer, accountant, updated_at) VALUES(?, ?, ?, ?)',
      [invoiceId, nz(preparer), nz(accountant), DateTime.now().toIso8601String()],
    );
  }

  static Future<({String preparer, String accountant})?> load(int invoiceId) async {
    try {
      final db = await DatabaseService().database;
      await _ensure(db);
      final r = await db.query('invoice_staff', where: 'invoice_id = ?', whereArgs: [invoiceId], limit: 1);
      if (r.isEmpty) return null;
      return (preparer: '${r.first['preparer'] ?? ''}', accountant: '${r.first['accountant'] ?? ''}');
    } catch (_) {
      return null;
    }
  }

  /// أسماء الموظفين (الاسم الظاهر) ومسمياتهم — للاختيار السريع
  static Future<List<({String name, String title})>> staff() async {
    try {
      final db = await DatabaseService().database;
      final cols = (await db.rawQuery('PRAGMA table_info(users)')).map((r) => '${r['name']}').toSet();
      final rows = await db.query('users',
          columns: [
            'username',
            if (cols.contains('display_name')) 'display_name',
            if (cols.contains('job_title')) 'job_title',
          ],
          orderBy: 'id');
      return [
        for (final r in rows)
          (
            name: ('${r['display_name'] ?? ''}'.trim().isNotEmpty ? '${r['display_name']}' : '${r['username']}').trim(),
            title: '${r['job_title'] ?? ''}'.trim(),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }
}
