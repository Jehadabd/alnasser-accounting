// lib/erp/batches/batch_store.dart
//
// 🗄️ جدول الدفعات (stock_lots) — سجل صلاحيات فقط: لا يغيّر كمية أي مادة. المتبقي يُقدَّر من
// الكمية الحالية في دفتر المخزون (Lots.allocate).

import 'package:sqflite/sqflite.dart';

import '../../services/database_service.dart';
import '../erp_common.dart';
import 'batch_models.dart';

class ProductLots {
  ProductLots(this.productId, this.name, this.stock, this.lots);
  final int productId;
  final String name;
  final double stock;
  final List<LotRemaining> lots;
}

class BatchStore {
  BatchStore({Future<Database> Function()? db}) : _getDb = db ?? (() => DatabaseService().database);
  final Future<Database> Function() _getDb;
  static int _readyGen = -1;

  Future<Database> _db() async {
    final db = await _getDb();
    if (_readyGen != DatabaseService.openGeneration) {
      await ensureSchema(db);
      _readyGen = DatabaseService.openGeneration;
    }
    return db;
  }

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_lots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        lot_no TEXT,
        expiry TEXT NOT NULL,
        qty REAL NOT NULL CHECK (qty > 0),
        received_at TEXT NOT NULL,
        note TEXT
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS ix_stock_lots_product ON stock_lots (product_id)');
  }

  Future<int> add(StockLot l) async {
    if (l.qty <= 0) throw ErpException('الكمية يجب أن تكون أكبر من صفر');
    final db = await _db();
    return db.insert('stock_lots', l.toMap());
  }

  Future<void> remove(int id) async {
    final db = await _db();
    await db.delete('stock_lots', where: 'id = ?', whereArgs: [id]);
  }

  /// كل المواد التي لها دفعات، مع المتبقي المقدَّر لكل دفعة.
  Future<List<ProductLots>> all() async {
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT l.*, p.name AS pname, COALESCE(p.stock_quantity, 0) AS stock
      FROM stock_lots l JOIN products p ON p.id = l.product_id
      WHERE COALESCE(p.is_deleted, 0) = 0
      ORDER BY p.name, l.expiry''');
    final by = <int, ({String name, double stock, List<StockLot> lots})>{};
    for (final r in rows) {
      final id = r['product_id'] as int;
      final cur = by[id] ?? (name: '${r['pname']}', stock: (r['stock'] as num).toDouble(), lots: <StockLot>[]);
      cur.lots.add(StockLot.fromMap(r));
      by[id] = cur;
    }
    return [
      for (final e in by.entries) ProductLots(e.key, e.value.name, e.value.stock, Lots.allocate(e.value.stock, e.value.lots)),
    ];
  }
}
