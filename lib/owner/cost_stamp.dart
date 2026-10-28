// lib/owner/cost_stamp.dart
//
// 🕒 «آخر تحديث لسعر الكلفة» لكل مادة — يظهر تحت الكلفة عند Ctrl+D (حساب المالك).
//
// الكلفة تتغير من أماكن كثيرة (فاتورة شراء، سعر الدولار، تعديل المادة، أدوات
// الأسعار، المزامنة). بدل تعديل كل مسار: مشغّل (TRIGGER) في قاعدة البيانات يكتب
// الوقت كلما تغيّرت قيمة cost_price فعلاً — أي مسار، بلا استثناء.
// المواد القديمة تأخذ أول مرة تاريخ آخر فاتورة شراء مؤكدة لها (إن وُجدت).

import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';

class CostStamp {
  CostStamp._();

  static Future<void> ensure(DatabaseExecutor db) async {
    final cols = await db.rawQuery('PRAGMA table_info(products)');
    if (cols.isEmpty) return;
    final had = cols.any((c) => c['name'] == 'cost_updated_at');
    if (!had) {
      await db.execute('ALTER TABLE products ADD COLUMN cost_updated_at TEXT');
    }
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_products_cost_stamp_upd
      AFTER UPDATE OF cost_price ON products
      WHEN COALESCE(OLD.cost_price, 0) <> COALESCE(NEW.cost_price, 0)
      BEGIN
        UPDATE products SET cost_updated_at = strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime') WHERE id = NEW.id;
      END''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_products_cost_stamp_ins
      AFTER INSERT ON products
      WHEN COALESCE(NEW.cost_price, 0) > 0 AND NEW.cost_updated_at IS NULL
      BEGIN
        UPDATE products SET cost_updated_at = strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime') WHERE id = NEW.id;
      END''');
    if (!had) {
      // تعبئة أولى: تاريخ آخر شراء مؤكد للمادة
      try {
        await db.execute('''
          UPDATE products SET cost_updated_at = (
            SELECT MAX(pi.date) FROM purchase_invoice_items pii
            JOIN purchase_invoices pi ON pi.id = pii.invoice_id
            WHERE pii.product_id = products.id AND pi.status = 'confirmed'
          ) WHERE cost_updated_at IS NULL''');
      } catch (_) {}
    }
  }

  /// id المادة ← آخر تحديث لكلفتها
  static Future<Map<int, DateTime>> all() async {
    final db = await DatabaseService().database;
    try {
      final rows = await db.rawQuery('SELECT id, cost_updated_at FROM products WHERE cost_updated_at IS NOT NULL');
      final out = <int, DateTime>{};
      for (final r in rows) {
        final d = DateTime.tryParse('${r['cost_updated_at']}');
        if (d != null && r['id'] is int) out[r['id'] as int] = d;
      }
      return out;
    } catch (_) {
      return {};
    }
  }
}
