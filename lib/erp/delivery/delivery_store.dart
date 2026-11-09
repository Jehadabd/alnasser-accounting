// lib/erp/delivery/delivery_store.dart
//
// 🗄️ جداول شركات التوصيل (محلية، لا تمس الفواتير ولا الديون):
//   delivery_companies • delivery_orders • delivery_settlements
// التسوية تُعلِّم الطلبات «مُسوّاة» وتحفظ مبالغها داخل معاملة واحدة. قبض المال نفسه
// يُسجَّل بوصل قبض من سجل الديون (المسار المحاسبي المعتمد) — هذا الملف لا يقبض شيئاً.

import 'package:sqflite/sqflite.dart';

import '../../services/database_service.dart';
import '../erp_common.dart';
import 'delivery_models.dart';

class DeliveryStore {
  DeliveryStore({Future<Database> Function()? db}) : _getDb = db ?? (() => DatabaseService().database);
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
      CREATE TABLE IF NOT EXISTS delivery_companies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        notes TEXT,
        customer_id INTEGER,
        default_fee_fils INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS delivery_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        invoice_id INTEGER,
        invoice_number TEXT,
        customer_name TEXT NOT NULL,
        phone TEXT,
        area TEXT,
        address TEXT,
        cod_fils INTEGER NOT NULL DEFAULT 0 CHECK (cod_fils >= 0),
        fee_fils INTEGER NOT NULL DEFAULT 0 CHECK (fee_fils >= 0),
        status TEXT NOT NULL DEFAULT 'pending',
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        settlement_id INTEGER
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS ix_delivery_orders_company ON delivery_orders (company_id, settlement_id)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS delivery_settlements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        settled_at TEXT NOT NULL,
        cod_fils INTEGER NOT NULL,
        fee_fils INTEGER NOT NULL,
        net_fils INTEGER NOT NULL,
        orders_count INTEGER NOT NULL,
        note TEXT,
        created_by TEXT
      )''');
  }

  // ───────────── الشركات ─────────────

  Future<List<DeliveryCompany>> companies({bool activeOnly = false}) async {
    final db = await _db();
    return (await db.query('delivery_companies', where: activeOnly ? 'active = 1' : null, orderBy: 'active DESC, name'))
        .map(DeliveryCompany.fromMap)
        .toList();
  }

  Future<int> saveCompany(DeliveryCompany c) async {
    if (c.name.trim().isEmpty) throw ErpException('اكتب اسم الشركة');
    if (c.defaultFeeFils < 0) throw ErpException('الأجرة لا تكون سالبة');
    final db = await _db();
    if (c.id == null) return db.insert('delivery_companies', c.toMap());
    await db.update('delivery_companies', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
    return c.id!;
  }

  // ───────────── الطلبات ─────────────

  Future<List<DeliveryOrder>> orders({int? companyId, DeliveryStatus? status, bool unsettledOnly = false, int limit = 1000}) async {
    final db = await _db();
    final w = <String>[];
    final a = <Object?>[];
    if (companyId != null) {
      w.add('company_id = ?');
      a.add(companyId);
    }
    if (status != null) {
      w.add('status = ?');
      a.add(status.name);
    }
    if (unsettledOnly) w.add('settlement_id IS NULL');
    return (await db.query('delivery_orders',
            where: w.isEmpty ? null : w.join(' AND '), whereArgs: a, orderBy: 'created_at DESC, id DESC', limit: limit))
        .map(DeliveryOrder.fromMap)
        .toList();
  }

  Future<int> saveOrder(DeliveryOrder o) async {
    if (o.customerName.trim().isEmpty) throw ErpException('اكتب اسم الزبون');
    if (o.codFils < 0 || o.feeFils < 0) throw ErpException('المبالغ لا تكون سالبة');
    final db = await _db();
    if (o.id == null) return db.insert('delivery_orders', o.toMap());
    final cur = await db.query('delivery_orders', columns: ['settlement_id'], where: 'id = ?', whereArgs: [o.id]);
    if (cur.isNotEmpty && cur.first['settlement_id'] != null) throw ErpException('طلب مُسوّى — لا يُعدَّل');
    await db.update('delivery_orders', o.toMap(), where: 'id = ?', whereArgs: [o.id]);
    return o.id!;
  }

  /// يغيّر الحالة إن كان الانتقال مسموحاً والطلب غير مُسوّى.
  Future<void> setStatus(DeliveryOrder o, DeliveryStatus to) async {
    if (o.settled) throw ErpException('طلب مُسوّى — لا تتغير حالته');
    if (!o.status.next.contains(to)) throw ErpException('لا ينتقل الطلب من «${o.status.label}» إلى «${to.label}»');
    final db = await _db();
    final n = await db.update(
      'delivery_orders',
      {'status': to.name, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ? AND status = ? AND settlement_id IS NULL',
      whereArgs: [o.id, o.status.name],
    );
    if (n != 1) throw ErpException('تغيّر الطلب من مكان آخر — حدّث القائمة');
  }

  // ───────────── التسوية ─────────────

  /// يسوّي طلبات الشركة غير المُسوّاة (سُلّم/راجع) في معاملة واحدة، ويعيد رقم التسوية
  /// والأرقام المحسوبة من قاعدة البيانات لحظة التسوية (لا من الشاشة).
  Future<({int id, DeliveryBalance balance})> settle(int companyId, {String note = ''}) async {
    final db = await _db();
    return db.transaction((txn) async {
      final rows = await txn.query('delivery_orders',
          where: "company_id = ? AND settlement_id IS NULL AND status IN ('delivered', 'returned')", whereArgs: [companyId]);
      final b = DeliveryBalance.of(rows.map(DeliveryOrder.fromMap));
      if (b.orders.isEmpty) throw ErpException('لا طلبات مسلّمة أو راجعة تنتظر التسوية');
      final id = await txn.insert('delivery_settlements', {
        'company_id': companyId,
        'settled_at': DateTime.now().toIso8601String(),
        'cod_fils': b.codFils,
        'fee_fils': b.feeFils,
        'net_fils': b.netFils,
        'orders_count': b.orders.length,
        'note': note.trim(),
        'created_by': currentUserName(),
      });
      final ids = [for (final o in b.orders) o.id];
      final n = await txn.rawUpdate(
          'UPDATE delivery_orders SET settlement_id = ? WHERE settlement_id IS NULL AND id IN (${List.filled(ids.length, '?').join(',')})',
          [id, ...ids]);
      if (n != ids.length) throw ErpException('تغيّرت الطلبات أثناء التسوية — أعد المحاولة');
      return (id: id, balance: b);
    });
  }

  Future<List<Map<String, Object?>>> settlements(int companyId) async {
    final db = await _db();
    return db.query('delivery_settlements', where: 'company_id = ?', whereArgs: [companyId], orderBy: 'id DESC', limit: 200);
  }
}
