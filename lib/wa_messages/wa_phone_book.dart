// lib/wa_messages/wa_phone_book.dart
//
// 📒 «أرقام واتساب المؤكَّدة»: أول إرسال مستند لعميل يُسأل فيه عن الرقم، وبعد التأكيد يُحفظ
// الرقم هنا (جدول wa_confirmed_phones) فيُرسل له بعدها مباشرة بلا سؤال.
//   • لا يمس جدول العملاء ولا أي دين — سجل مستقل يُحذف منه الرقم متى شئت.
//   • تغيّر رقم العميل في سجل الديون بعد التأكيد ⇒ أول إرسال بعدها يسأل من جديد (مرة واحدة)،
//     ثم يعود مباشراً. لذلك يُحفظ مع الرقم المؤكَّد رقم العميل في السجل وقت التأكيد.
//   • المفتاح: معرّف العميل؛ وإن لم يكن للمستند عميل مسجّل فالاسم (لا يُستعمل الاسم بديلاً
//     عن رقم مفقود — أسماء مثل «نقدي» تتكرر — بل يمنع السؤال فقط إن طابق الرقمُ المحفوظ).

import 'package:sqflite/sqflite.dart' show Database, DatabaseExecutor, ConflictAlgorithm;

import '../owner/wa_auto/wa_auto_reminder.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

class WaConfirmedPhone {
  WaConfirmedPhone(this.key, this.name, this.phone, this.at, this.by);
  final String key, name, phone, by;
  final DateTime? at;
  bool get byCustomer => key.startsWith('c:');
}

class WaPhoneBook {
  WaPhoneBook._();

  static int _readyGen = -1;

  static Future<Database> _db() async {
    final db = await DatabaseService().database;
    if (_readyGen != DatabaseService.openGeneration) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS wa_confirmed_phones (
          key TEXT PRIMARY KEY,
          name TEXT,
          phone TEXT NOT NULL,
          confirmed_at TEXT,
          confirmed_by TEXT
        )''');
      try {
        // رقم العميل في سجل الديون وقت التأكيد
        await db.execute('ALTER TABLE wa_confirmed_phones ADD COLUMN customer_phone TEXT');
      } catch (_) {}
      _readyGen = DatabaseService.openGeneration;
    }
    return db;
  }

  /// مفتاح صاحب المستند: العميل بمعرّفه، وإلا اسمه. null = لا صاحب يُعرف.
  static String? keyOf(int? customerId, String? name) {
    if (customerId != null) return 'c:$customerId';
    final n = (name ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    return n.isEmpty ? null : 'n:$n';
  }

  /// الرقم المؤكَّد لهذا المفتاح (دولي)، أو null.
  static Future<String?> phoneOf(String? key) async {
    if (key == null) return null;
    try {
      final db = await _db();
      final r = await db.query('wa_confirmed_phones', columns: ['phone'], where: 'key = ?', whereArgs: [key], limit: 1);
      return r.isEmpty ? null : r.first['phone'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// رقم العميل الحالي في سجل الديون (دولي)، أو null.
  static Future<String?> _registryPhone(DatabaseExecutor db, String key) async {
    if (!key.startsWith('c:')) return null;
    final id = int.tryParse(key.substring(2));
    if (id == null) return null;
    final r = await db.query('customers', columns: ['phone'], where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : WaAutoReminder.normalizePhone(r.first['phone'] as String?);
  }

  /// يحفظ الرقم بعد تأكيد المستخدم (ويستبدل القديم إن تغيّر)، مع رقم العميل في السجل الآن.
  static Future<void> confirm(String key, String name, String phone) async {
    final db = await _db();
    await db.insert(
      'wa_confirmed_phones',
      {
        'key': key,
        'name': name,
        'phone': phone,
        'confirmed_at': DateTime.now().toIso8601String(),
        'confirmed_by': AuthService().currentUser?.username ?? '',
        'customer_phone': await _registryPhone(db, key),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// رقم العميل في سجل الديون تغيّر منذ التأكيد؟ يعيد الرقم الجديد، أو null إن لم يتغير.
  /// (تأكيد قديم بلا رقم محفوظ: يُسجَّل الحالي الآن ولا يُعدّ تغييراً.)
  static Future<String?> changedRegistryPhone(String? key) async {
    if (key == null || !key.startsWith('c:')) return null;
    try {
      final db = await _db();
      final r = await db.query('wa_confirmed_phones',
          columns: ['customer_phone'], where: 'key = ?', whereArgs: [key], limit: 1);
      if (r.isEmpty) return null;
      final now = await _registryPhone(db, key);
      final then = r.first['customer_phone'] as String?;
      if (then == null) {
        await db.update('wa_confirmed_phones', {'customer_phone': now}, where: 'key = ?', whereArgs: [key]);
        return null;
      }
      if (now == null || now == then) return null;
      return now;
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String key) async {
    final db = await _db();
    await db.delete('wa_confirmed_phones', where: 'key = ?', whereArgs: [key]);
  }

  static Future<List<WaConfirmedPhone>> all() async {
    final db = await _db();
    final rows = await db.query('wa_confirmed_phones', orderBy: 'name');
    return [
      for (final r in rows)
        WaConfirmedPhone('${r['key']}', '${r['name'] ?? ''}', '${r['phone']}',
            DateTime.tryParse('${r['confirmed_at'] ?? ''}'), '${r['confirmed_by'] ?? ''}'),
    ];
  }
}
