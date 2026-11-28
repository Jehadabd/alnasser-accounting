// lib/services/database/core/pricing_stats_views.dart
//
// 📊 مصادر أنماط التسعير «آخر سعر / متوسط آخر 3 / الأكثر تكراراً» ومستوى السعر:
//   product_price_stats  و  recent_sales_buffer  = Views تُحسب لحظياً من الفواتير.
//
// 🩹 القواعد القادمة من debt_book فيها الاسمان نفسهما «جداول» قديمة (ذاكرة تسعير ذلك
// التطبيق) لا يكتب فيها تطبيقنا شيئاً. النتيجة:
//   • CREATE VIEW IF NOT EXISTS لا يفعل شيئاً (الاسم موجود) ⇒ الأنماط تقرأ أرقاماً قديمة.
//   • «إصلاح إحصائيات التسعير» ينفّذ DROP VIEW على جدول ⇒ خطأ SQLite.
// الحل: إن كان الاسم جدولاً يُعاد تسميته _legacy_… (يبقى محفوظاً، لا يُحذف شيء)، ثم
// تُنشأ الـ View. لا يمس أي فاتورة أو دين أو سعر. آمن التكرار.

import 'package:sqflite/sqflite.dart';

class PricingStatsViews {
  PricingStatsViews._();

  static const _views = <String, String>{
    'product_price_stats': '''
      CREATE VIEW product_price_stats AS
      SELECT
        product_id,
        AVG(applied_price) as median_price,
        COUNT(*) as sales_count
      FROM invoice_items
      GROUP BY product_id
    ''',
    'recent_sales_buffer': '''
      CREATE VIEW recent_sales_buffer AS
      SELECT
        ii.product_id,
        ii.applied_price as price,
        i.invoice_date
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
    ''',
  };

  /// عند الفتح: يصلح فقط ما يحتاج (جدول قديم بدل View، أو View مفقودة).
  static Future<void> ensure(DatabaseExecutor db) => _run(db, rebuild: false);

  /// زر «إصلاح إحصائيات التسعير»: يعيد إنشاء الـ Views دائماً.
  static Future<void> repair(DatabaseExecutor db) => _run(db, rebuild: true);

  static Future<void> _run(DatabaseExecutor db, {required bool rebuild}) async {
    for (final e in _views.entries) {
      final name = e.key;
      final type = await _typeOf(db, name);
      if (type == 'table') {
        final legacy = '_legacy_$name';
        if (await _typeOf(db, legacy) == null) {
          await db.execute('ALTER TABLE $name RENAME TO $legacy');
        } else {
          // نسخة قديمة محفوظة مسبقاً: هذا تكرار لذاكرة debt_book نفسها
          await db.execute('DROP TABLE $name');
        }
      } else if (type == 'view') {
        if (!rebuild) continue;
        await db.execute('DROP VIEW $name');
      } else if (type != null) {
        continue; // اسم محجوز لنوع آخر (فهرس/مشغّل): لا نلمسه
      }
      await db.execute(e.value);
    }
  }

  static Future<String?> _typeOf(DatabaseExecutor db, String name) async {
    final r = await db.rawQuery('SELECT type FROM sqlite_master WHERE name = ? LIMIT 1', [name]);
    return r.isEmpty ? null : r.first['type'] as String?;
  }
}
