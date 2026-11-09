// lib/wa_messages/wa_message_log.dart
//
// 🗂️ سجل رسائل واتساب المرسلة (جدول wa_message_log في قاعدة البيانات المحلية):
// من، متى، بأي قاعدة، النتيجة، المبلغ وقتها، والمرفق. منه يُعرف «أُرسل له من قبل؟»
// (التكرار) و«كم أُرسل اليوم؟» (الحد اليومي). لا يمس أي دين أو معاملة.

import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../owner/wa_auto/wa_auto_reminder.dart';
import '../services/database_service.dart';
import 'wa_rules.dart';

class WaLogEntry {
  WaLogEntry(this.at, this.customerId, this.name, this.source, this.ruleName, this.status, this.error, this.amount,
      this.attach);
  final DateTime at;
  final int? customerId;
  final String name, source, ruleName, status, attach;
  final String? error;
  final double amount;
  bool get sent => status == 'sent';
}

class WaMessageLog {
  WaMessageLog._();

  static int _readyGen = -1;

  static Future<Database> _db() async {
    final db = await DatabaseService().database;
    if (_readyGen != DatabaseService.openGeneration) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS wa_message_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          at TEXT NOT NULL,
          customer_id INTEGER,
          name TEXT,
          phone TEXT,
          source TEXT,
          rule_id TEXT,
          rule_name TEXT,
          status TEXT NOT NULL,
          error TEXT,
          amount REAL,
          attach TEXT
        )''');
      await db.execute('CREATE INDEX IF NOT EXISTS ix_wa_log_rule ON wa_message_log (rule_id, customer_id, status)');
      await db.execute('CREATE INDEX IF NOT EXISTS ix_wa_log_at ON wa_message_log (at)');
      _readyGen = DatabaseService.openGeneration;
      await _importLegacy(db);
    }
    return db;
  }

  static Future<void> add({
    required int? customerId,
    required String name,
    required String phone,
    required String source,
    String? ruleId,
    String? ruleName,
    required String status,
    String? error,
    required double amount,
    String attach = '',
    DateTime? at,
  }) async {
    final db = await _db();
    await db.insert('wa_message_log', {
      'at': (at ?? DateTime.now()).toIso8601String(),
      'customer_id': customerId,
      'name': name,
      'phone': phone,
      'source': source,
      'rule_id': ruleId,
      'rule_name': ruleName,
      'status': status,
      'error': error,
      'amount': amount,
      'attach': attach,
    });
  }

  /// آخر إرسال ناجح بهذه القاعدة لكل عميل.
  static Future<Map<int, DateTime>> lastSent(String ruleId) async {
    final db = await _db();
    final r = await db.rawQuery(
        "SELECT customer_id AS c, MAX(at) AS t FROM wa_message_log WHERE rule_id = ? AND status = 'sent' "
        'AND customer_id IS NOT NULL GROUP BY customer_id',
        [ruleId]);
    return {
      for (final x in r)
        if (DateTime.tryParse('${x['t']}') != null) x['c'] as int: DateTime.parse('${x['t']}'),
    };
  }

  /// رسائل أُرسلت اليوم (لكل الطرق) — للحد اليومي.
  static Future<int> sentToday() async {
    final db = await _db();
    final today = DateFormat('yyyy-MM-dd', 'en').format(DateTime.now());
    final r = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM wa_message_log WHERE status = 'sent' AND at >= ?", [today]);
    return ((r.first['n'] as num?) ?? 0).toInt();
  }

  static Future<List<WaLogEntry>> recent({int limit = 300, int? customerId}) async {
    final db = await _db();
    final r = await db.query('wa_message_log',
        where: customerId == null ? null : 'customer_id = ?',
        whereArgs: customerId == null ? null : [customerId],
        orderBy: 'at DESC, id DESC',
        limit: limit);
    return [
      for (final x in r)
        WaLogEntry(
          DateTime.tryParse('${x['at']}') ?? DateTime(2000),
          x['customer_id'] as int?,
          '${x['name'] ?? ''}',
          '${x['source'] ?? ''}',
          '${x['rule_name'] ?? ''}',
          '${x['status'] ?? ''}',
          x['error'] as String?,
          (x['amount'] as num?)?.toDouble() ?? 0,
          '${x['attach'] ?? ''}',
        ),
    ];
  }

  /// يحذف السجلات الأقدم من سنة (لا شيء غيره).
  static Future<void> prune() async {
    final db = await _db();
    final cut = DateTime.now().subtract(const Duration(days: 400)).toIso8601String();
    await db.delete('wa_message_log', where: 'at < ?', whereArgs: [cut]);
  }

  /// من أُرسل له بالتذكير الشهري القديم هذا الشهر لا يُعاد له (مرة واحدة).
  static Future<void> _importLegacy(Database db) async {
    try {
      final done = await db.rawQuery("SELECT 1 FROM wa_message_log WHERE source = 'legacy' LIMIT 1");
      if (done.isNotEmpty) return;
      final m = await WaAutoReminder.legacyMonthLog();
      for (final e in m.entries) {
        if (e.value['s'] != 'sent') continue;
        await db.insert('wa_message_log', {
          'at': '${e.value['t']}',
          'customer_id': int.tryParse(e.key),
          'name': '',
          'phone': '',
          'source': 'legacy',
          'rule_id': WaRules.legacyId,
          'rule_name': 'التذكير الشهري',
          'status': 'sent',
          'amount': (e.value['a'] as num?)?.toDouble() ?? 0,
          'attach': '',
        });
      }
    } catch (_) {}
  }
}
