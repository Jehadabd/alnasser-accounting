// lib/org/org_service.dart
//
// 🏢 الفروع والمخازن والتحويلات المخزنية.
//
// الكمية في المخازن:
//   • المخزن الافتراضي (الرئيسي) = كمية المادة الكلية − مجموع ما في المخازن الأخرى.
//   • أي مخزن آخر = حركاته (تحويلات واردة − صادرة) − ما بيع منه.
// التحويل حركتان متعاكستان (−من، +إلى) فلا تتغير الكمية الكلية للمادة أبداً،
// ولا يتأثر أي منطق مخزون قائم (الكاشير، المزامنة، الجرد).

import 'package:sqflite/sqflite.dart';

import '../services/database/business/stock_ledger.dart';
import '../services/database_service.dart';

class Branch {
  Branch(this.id, this.code, this.name, this.address, this.phone, this.isActive, this.isCurrent);
  final int id;
  final String code;
  final String name;
  final String? address;
  final String? phone;
  final bool isActive;
  final bool isCurrent;

  factory Branch.fromMap(Map<String, Object?> m) => Branch(
        m['id'] as int,
        m['code'] as String,
        m['name'] as String,
        m['address'] as String?,
        m['phone'] as String?,
        (m['is_active'] as int? ?? 1) == 1,
        (m['is_current'] as int? ?? 0) == 1,
      );
  @override
  String toString() => name;
}

class Warehouse {
  Warehouse(this.id, this.branchId, this.code, this.name, this.isDefault, this.isActive, this.notes);
  final int id;
  final int branchId;
  final String code;
  final String name;
  final bool isDefault;
  final bool isActive;
  final String? notes;

  factory Warehouse.fromMap(Map<String, Object?> m) => Warehouse(
        m['id'] as int,
        (m['branch_id'] as int?) ?? 1,
        m['code'] as String,
        m['name'] as String,
        (m['is_default'] as int? ?? 0) == 1,
        (m['is_active'] as int? ?? 1) == 1,
        m['notes'] as String?,
      );
  @override
  String toString() => name;
}

class OrgException implements Exception {
  OrgException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TransferLine {
  TransferLine(this.productId, this.quantity);
  final int productId;
  final double quantity;
}

class OrgService {
  OrgService({Future<Database> Function()? getDatabase})
      : _getDb = getDatabase ?? (() => DatabaseService().database);
  final Future<Database> Function() _getDb;

  // ───────────────────────── الفروع ─────────────────────────

  Future<List<Branch>> branches() async {
    final db = await _getDb();
    return (await db.query('branches', orderBy: 'id')).map(Branch.fromMap).toList();
  }

  Future<Branch?> currentBranch() async {
    final db = await _getDb();
    final r = await db.query('branches', where: 'is_current = 1', limit: 1);
    return r.isEmpty ? null : Branch.fromMap(r.first);
  }

  Future<int> saveBranch({int? id, required String name, String? code, String? address, String? phone}) async {
    final db = await _getDb();
    if (name.trim().isEmpty) throw OrgException('اكتب اسم الفرع');
    if (id == null) {
      final n = await db.rawQuery('SELECT COALESCE(MAX(id), 0) + 1 AS n FROM branches');
      final next = (n.first['n'] as num).toInt();
      return db.insert('branches', {
        'code': (code == null || code.trim().isEmpty) ? 'B$next' : code.trim(),
        'name': name.trim(),
        'address': address,
        'phone': phone,
        'is_active': 1,
        'is_current': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    await db.update('branches', {'name': name.trim(), 'address': address, 'phone': phone},
        where: 'id = ?', whereArgs: [id]);
    return id;
  }

  /// الفرع الذي تعمل عليه هذه القاعدة (سيرفر الفرع).
  Future<void> setCurrentBranch(int id) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      await txn.update('branches', {'is_current': 0});
      await txn.update('branches', {'is_current': 1}, where: 'id = ?', whereArgs: [id]);
    });
  }

  // ───────────────────────── المخازن ─────────────────────────

  Future<List<Warehouse>> warehouses({bool activeOnly = false}) async {
    final db = await _getDb();
    return (await db.query('warehouses',
            where: activeOnly ? 'is_active = 1' : null, orderBy: 'is_default DESC, id'))
        .map(Warehouse.fromMap)
        .toList();
  }

  Future<int> defaultWarehouseId(DatabaseExecutor db) async {
    final r = await db.query('warehouses',
        columns: ['id'], where: 'is_default = 1', orderBy: 'id', limit: 1);
    return r.isEmpty ? 1 : r.first['id'] as int;
  }

  Future<int> saveWarehouse({int? id, required String name, int branchId = 1, String? notes}) async {
    final db = await _getDb();
    if (name.trim().isEmpty) throw OrgException('اكتب اسم المخزن');
    if (id == null) {
      final n = await db.rawQuery('SELECT COALESCE(MAX(id), 0) + 1 AS n FROM warehouses');
      final next = (n.first['n'] as num).toInt();
      return db.insert('warehouses', {
        'branch_id': branchId,
        'code': 'W$next',
        'name': name.trim(),
        'is_default': 0,
        'is_active': 1,
        'notes': notes,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    await db.update('warehouses', {'name': name.trim(), 'branch_id': branchId, 'notes': notes},
        where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<void> setWarehouseActive(int id, bool active) async {
    final db = await _getDb();
    if (!active) {
      final w = await db.query('warehouses', where: 'id = ?', whereArgs: [id]);
      if (w.isNotEmpty && (w.first['is_default'] as int) == 1) {
        throw OrgException('لا يمكن إيقاف المخزن الرئيسي');
      }
      final stock = await warehouseStock(id);
      if (stock.any((r) => ((r['qty'] as num?) ?? 0).abs() > 1e-6)) {
        throw OrgException('في المخزن بضاعة — حوّلها أولاً ثم أوقفه');
      }
    }
    await db.update('warehouses', {'is_active': active ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  /// كميات المواد في مخزن. يعيد: id, name, unit, qty, cost_price.
  Future<List<Map<String, Object?>>> warehouseStock(int warehouseId, {String? search}) async {
    final db = await _getDb();
    final mainId = await defaultWarehouseId(db);
    final like = (search == null || search.trim().isEmpty) ? null : '%${search.trim()}%';
    const inWarehouse = '''
      COALESCE((SELECT SUM(m.delta) FROM stock_movements m
                WHERE m.product_sync_uuid = p.sync_uuid AND m.warehouse_id = w.id
                  AND m.kind = 'transfer'), 0)
      - COALESCE((SELECT SUM(CASE WHEN COALESCE(ii.quantity_large_unit, 0) > 0
                                  THEN ii.quantity_large_unit * COALESCE(NULLIF(ii.units_in_large_unit, 0), 1)
                                  ELSE COALESCE(ii.quantity_individual, 0) END)
                  FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
                  WHERE ii.product_sync_uuid = p.sync_uuid AND i.warehouse_id = w.id
                    AND COALESCE(i.is_deleted, 0) = 0 AND COALESCE(i.status, '') != 'معلقة'), 0)''';
    if (warehouseId == mainId) {
      // الرئيسي = الكلي − مجموع المخازن الأخرى
      return db.rawQuery('''
        SELECT p.id, p.name, p.unit, p.cost_price,
               COALESCE(p.stock_quantity, 0) - COALESCE((
                 SELECT SUM($inWarehouse) FROM warehouses w WHERE w.id != ?
               ), 0) AS qty
        FROM products p
        ${like == null ? '' : 'WHERE p.name LIKE ?'}
        ORDER BY p.name
      ''', [mainId, if (like != null) like]);
    }
    return db.rawQuery('''
      SELECT p.id, p.name, p.unit, p.cost_price, ($inWarehouse) AS qty
      FROM products p, warehouses w
      WHERE w.id = ? ${like == null ? '' : 'AND p.name LIKE ?'}
      ORDER BY p.name
    ''', [warehouseId, if (like != null) like]);
  }

  // ───────────────────────── التحويلات ─────────────────────────

  Future<int> createTransfer({
    required int fromWarehouseId,
    required int toWarehouseId,
    required List<TransferLine> lines,
    String? notes,
    int? userId,
  }) async {
    if (fromWarehouseId == toWarehouseId) throw OrgException('اختر مخزنين مختلفين');
    final valid = lines.where((l) => l.quantity > 0).toList();
    if (valid.isEmpty) throw OrgException('أضف مادة واحدة على الأقل بكمية أكبر من صفر');

    // التحقق من الرصيد قبل الكتابة (خارج المعاملة: القراءات لا تنتظر أحداً)
    final available = {
      for (final r in await warehouseStock(fromWarehouseId))
        r['id'] as int: ((r['qty'] as num?) ?? 0).toDouble()
    };
    for (final l in valid) {
      final a = available[l.productId] ?? 0;
      if (l.quantity > a + 1e-6) {
        throw OrgException('الكمية المطلوبة من المادة #${l.productId} (${l.quantity}) أكبر من المتوفر ($a)');
      }
    }

    final db = await _getDb();
    return db.transaction((txn) async {
      final n = await txn.rawQuery('SELECT COALESCE(MAX(transfer_number), 0) + 1 AS n FROM stock_transfers');
      final number = (n.first['n'] as num).toInt();
      final now = DateTime.now().toIso8601String();
      final tid = await txn.insert('stock_transfers', {
        'transfer_number': number,
        'transfer_date': now,
        'from_warehouse_id': fromWarehouseId,
        'to_warehouse_id': toWarehouseId,
        'notes': notes,
        'created_by_user_id': userId,
        'created_at': now,
      });
      for (final l in valid) {
        final uuid = await StockLedger.productSyncUuidForId(txn, l.productId);
        if (uuid == null) throw OrgException('مادة غير موجودة (#${l.productId})');
        await txn.insert('stock_transfer_items', {
          'transfer_id': tid,
          'product_id': l.productId,
          'quantity': l.quantity,
        });
        final out = await StockLedger.addMovement(txn,
            productSyncUuid: uuid, delta: -l.quantity, kind: 'transfer', note: 'تحويل مخزني $number');
        final inn = await StockLedger.addMovement(txn,
            productSyncUuid: uuid, delta: l.quantity, kind: 'transfer', note: 'تحويل مخزني $number');
        if (out != null) {
          await txn.update('stock_movements', {'warehouse_id': fromWarehouseId},
              where: 'movement_uuid = ?', whereArgs: [out]);
        }
        if (inn != null) {
          await txn.update('stock_movements', {'warehouse_id': toWarehouseId},
              where: 'movement_uuid = ?', whereArgs: [inn]);
        }
      }
      return tid;
    });
  }

  Future<List<Map<String, Object?>>> transfers() async {
    final db = await _getDb();
    return db.rawQuery('''
      SELECT t.*, wf.name AS from_name, wt.name AS to_name,
             (SELECT COUNT(*) FROM stock_transfer_items i WHERE i.transfer_id = t.id) AS items
      FROM stock_transfers t
      LEFT JOIN warehouses wf ON wf.id = t.from_warehouse_id
      LEFT JOIN warehouses wt ON wt.id = t.to_warehouse_id
      ORDER BY t.id DESC
    ''');
  }

  Future<List<Map<String, Object?>>> transferItems(int transferId) async {
    final db = await _getDb();
    return db.rawQuery('''
      SELECT i.quantity, p.name, p.unit FROM stock_transfer_items i
      LEFT JOIN products p ON p.id = i.product_id WHERE i.transfer_id = ?
    ''', [transferId]);
  }
}
