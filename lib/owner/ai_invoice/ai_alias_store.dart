// lib/owner/ai_invoice/ai_alias_store.dart
//
// 🧠 ذاكرة الأسماء: كيف يسمّي كل مورد موادنا.
//
// حين تصحّح مطابقة في شاشة المراجعة (أو تؤكدها والاسم مختلف عن اسم مادتنا)
// يُحفظ «اسم المورد ← مادتنا». في الفاتورة التالية:
//   1) يُرسل هذا الجدول للنموذج ضمن التعليمات (يتعلّم أسلوب المورد).
//   2) وبعد رد النموذج تُفرض المطابقة المحفوظة مباشرة (لا تعتمد على النموذج).
// المطابقة الخاصة بالمورد أولاً، ثم العامة (supplier_id = 0) لكل الموردين.

import 'package:sqflite/sqflite.dart';

import '../../services/database_service.dart';

class AiAlias {
  AiAlias({required this.supplierId, required this.alias, required this.productId, required this.hits});
  final int supplierId;
  final String alias;
  final int productId;
  final int hits;
}

class AiAliasStore {
  AiAliasStore._();

  // مرتبط بالقاعدة المفتوحة: قاعدة مستعادة تُجهَّز جداولها من جديد
  static int _readyGen = -1;
  static bool get _ready => _readyGen == DatabaseService.openGeneration;
  static set _ready(bool v) => _readyGen = v ? DatabaseService.openGeneration : -1;

  static Future<Database> _db() async {
    final db = await DatabaseService().database;
    if (!_ready) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ai_product_aliases (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          supplier_id INTEGER NOT NULL DEFAULT 0,
          alias_text TEXT NOT NULL,
          alias_norm TEXT NOT NULL,
          product_id INTEGER NOT NULL,
          hits INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          UNIQUE (supplier_id, alias_norm)
        )''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_alias_norm ON ai_product_aliases(alias_norm)');
      _ready = true;
    }
    return db;
  }

  /// تطبيع الاسم للمقارنة: الحروف العربية المتشابهة، الأرقام، رموز المقاس، المسافات
  static String normalize(String s) {
    var t = s.trim().toLowerCase();
    const map = {
      'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا', 'ة': 'ه', 'ى': 'ي', 'ی': 'ي', 'ک': 'ك', 'ؤ': 'و', 'ئ': 'ي',
      '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4', '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
      '×': 'x', '*': 'x', '٫': '.', '،': ' ', ',': ' ', '-': ' ', '_': ' ', '/': ' ', '(': ' ', ')': ' ',
    };
    final b = StringBuffer();
    for (final ch in t.split('')) {
      final code = ch.codeUnitAt(0);
      if (code == 0x0640 || (code >= 0x064B && code <= 0x0652)) continue; // تطويل وحركات
      b.write(map[ch] ?? ch);
    }
    t = b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  /// كل الأسماء المحفوظة لهذا المورد + العامة
  static Future<List<AiAlias>> forSupplier(int? supplierId) async {
    final db = await _db();
    final rows = await db.query('ai_product_aliases',
        where: 'supplier_id = ? OR supplier_id = 0', whereArgs: [supplierId ?? 0], orderBy: 'hits DESC, updated_at DESC', limit: 600);
    return rows
        .map((r) => AiAlias(
              supplierId: r['supplier_id'] as int,
              alias: '${r['alias_text']}',
              productId: r['product_id'] as int,
              hits: r['hits'] as int,
            ))
        .toList();
  }

  /// مطابقة محفوظة لاسم من الفاتورة (المورد أولاً ثم العامة)
  static int? lookup(List<AiAlias> aliases, String originalName, int? supplierId) {
    final n = normalize(originalName);
    if (n.isEmpty) return null;
    AiAlias? general;
    for (final a in aliases) {
      if (normalize(a.alias) != n) continue;
      if (supplierId != null && a.supplierId == supplierId) return a.productId;
      general ??= a.supplierId == 0 ? a : null;
    }
    return general?.productId;
  }

  /// تعلّم: «هذا الاسم عند هذا المورد = هذه المادة» (ويُحفظ عاماً أيضاً)
  static Future<void> learn({required int? supplierId, required String alias, required int productId, required String productName}) async {
    final text = alias.trim();
    final norm = normalize(text);
    if (norm.isEmpty || norm == normalize(productName)) return; // الاسم نفسه: لا داعي
    final db = await _db();
    final now = DateTime.now().toIso8601String();
    // بدون ON CONFLICT ... DO UPDATE: غير مدعومة في SQLite أندرويد القديم (< 3.24)
    await db.transaction((txn) async {
      for (final sid in {supplierId ?? 0, 0}) {
        final old = await txn.query('ai_product_aliases',
            columns: ['id', 'product_id', 'hits'], where: 'supplier_id = ? AND alias_norm = ?', whereArgs: [sid, norm], limit: 1);
        if (old.isEmpty) {
          await txn.insert('ai_product_aliases', {
            'supplier_id': sid,
            'alias_text': text,
            'alias_norm': norm,
            'product_id': productId,
            'hits': 1,
            'created_at': now,
            'updated_at': now,
          });
        } else {
          final same = old.first['product_id'] == productId;
          await txn.update(
              'ai_product_aliases',
              {
                'alias_text': text,
                'product_id': productId,
                'hits': same ? ((old.first['hits'] as int?) ?? 0) + 1 : 1,
                'updated_at': now,
              },
              where: 'id = ?',
              whereArgs: [old.first['id']]);
        }
      }
    });
  }

  static Future<int> count() async {
    final db = await _db();
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM ai_product_aliases WHERE supplier_id <> 0');
    return (r.first['c'] as int?) ?? 0;
  }
}
