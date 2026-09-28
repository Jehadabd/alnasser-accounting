// lib/erp/inventory/stock_docs_service.dart
//
// 📦 المستندات المخزنية (مثل فواتير «إدخال/إخراج» و«بضاعة أول المدة» في الإداري)،
// وجلسات الجرد الفعلي، والتصنيع (نماذج + عمليات).
//
// كل حركة كمية تمر عبر StockLedger (حركة بمعرّف تزامن)، والمستند نفسه +
// حركاته في معاملة قاعدة بيانات واحدة. القيد يشتقه محرك الترحيل من المستند:
//   فرق قيمة المخزون ↔ الحساب المقابل (تالف/هدايا، فروقات جرد، أرصدة افتتاحية،
//   مصاريف صناعية محمّلة...). الإلغاء = حركات عكسية + حذف القيد.

import '../../accounting/ledger.dart';
import '../../services/database_service.dart';
import '../activity/activity_log.dart';
import '../erp_common.dart';
import '../stock_helpers.dart';

const Map<String, String> stockDocLabels = {
  'in': 'سند إدخال',
  'out': 'سند إخراج',
  'opening': 'بضاعة أول المدة',
  'count': 'تسوية جرد',
  'production': 'عملية تصنيع',
};

class StockDocLine {
  StockDocLine({required this.productId, required this.name, required this.baseQty, required this.unitCost, this.warehouseId, this.note});
  final int productId;
  final String name;

  /// بالإشارة: موجب = دخول، سالب = خروج.
  final double baseQty;
  final double unitCost;
  final int? warehouseId;
  final String? note;
}

class StockDocsService {
  /// ينشئ مستنداً مخزنياً. يعيد رقم المعرّف.
  Future<int> create({
    required String docType,
    required DateTime date,
    int? warehouseId,
    int? counterAccountId,
    String? reason,
    String? notes,
    required List<StockDocLine> lines,
    int? modelId,
    double? producedQty,
    double overheadAmount = 0,
    int? overheadAccountId,
    bool allowNegative = false,
  }) async {
    final valid = lines.where((l) => l.baseQty.abs() > 1e-9).toList();
    if (valid.isEmpty) throw ErpException('أضف مادة واحدة على الأقل بكمية غير صفرية');
    for (final l in valid) {
      if (l.unitCost < 0) throw ErpException('كلفة سالبة للمادة ${l.name}');
      if ((docType == 'in' || docType == 'opening') && l.baseQty < 0) {
        throw ErpException('كميات الإدخال تكون موجبة');
      }
      if (docType == 'out' && l.baseQty > 0) throw ErpException('كميات الإخراج تكون سالبة');
    }
    if (counterAccountId != null) {
      final db0 = await erpDb();
      final a = await db0.query('accounts', where: 'id = ?', whereArgs: [counterAccountId], limit: 1);
      if (a.isEmpty) throw ErpException('الحساب المقابل غير موجود');
      if ((a.first['is_group'] as int? ?? 0) == 1) throw ErpException('الحساب المقابل رئيسي — اختر حساباً فرعياً');
      if ((a.first['is_control'] as int? ?? 0) == 1) {
        throw ErpException('لا يجوز حساب ذمم عملاء/موردين مقابلاً لمستند مخزني');
      }
    }
    await PeriodLock.assertOpen(date);
    final db = await erpDb();

    // التحقق من توفر الكميات الخارجة
    if (!allowNegative) {
      final need = <String, double>{};
      for (final l in valid.where((l) => l.baseQty < 0)) {
        final k = '${l.productId}|${l.warehouseId ?? warehouseId}';
        need[k] = (need[k] ?? 0) + (-l.baseQty);
      }
      for (final e in need.entries) {
        final parts = e.key.split('|');
        final pid = int.parse(parts[0]);
        final wid = parts[1] == 'null' ? null : int.tryParse(parts[1]);
        final avail = await ErpStock.available(db, pid, warehouseId: wid);
        if (e.value > avail + 1e-6) {
          final name = valid.firstWhere((l) => l.productId == pid).name;
          throw ErpException('«$name»: المطلوب إخراجه ${fmtQty(e.value)} والمتوفر ${fmtQty(avail)}');
        }
      }
    }

    // 🧮 تسوية الجرد: حسابا الزيادة والعجز من الإعدادات يُثبَّتان على المستند نفسه
    // (تغيير الإعداد لاحقاً لا يغيّر قيود مستندات سابقة).
    int? gainAcc, lossAcc;
    if (docType == 'count' && counterAccountId == null) {
      gainAcc = int.tryParse((await Ledger.getSetting(db, CountAccounts.gainKey)) ?? '');
      lossAcc = int.tryParse((await Ledger.getSetting(db, CountAccounts.lossKey)) ?? '');
    }
    final docId = await db.transaction((txn) async {
      final no = await nextDocNumber(txn, 'stock_docs', 'doc_no', where: 'doc_type = ?', args: [docType]);
      var total = 0.0;
      final id = await txn.insert('stock_docs', {
        'doc_type': docType,
        'doc_no': no,
        'doc_date': date.toIso8601String(),
        'warehouse_id': warehouseId,
        'counter_account_id': counterAccountId,
        'reason': reason,
        'notes': notes,
        'total_cost': 0,
        'model_id': modelId,
        'produced_qty': producedQty,
        'overhead_amount': roundMoney(overheadAmount),
        'overhead_account_id': overheadAccountId,
        'gain_account_id': gainAcc,
        'loss_account_id': lossAcc,
        'status': 'posted',
        'created_by': currentUserName(),
        'created_at': DateTime.now().toIso8601String(),
      });
      for (final l in valid) {
        final wid = l.warehouseId ?? warehouseId;
        final lineCost = roundMoney(l.baseQty.abs() * l.unitCost);
        total += l.baseQty > 0 ? lineCost : -lineCost;
        final mv = await ErpStock.move(txn,
            productId: l.productId,
            baseDelta: l.baseQty,
            kind: 'doc_$docType',
            note: '${stockDocLabels[docType] ?? docType} $no',
            warehouseId: wid);
        await txn.insert('stock_doc_items', {
          'doc_id': id,
          'product_id': l.productId,
          'product_name': l.name,
          'base_qty': l.baseQty,
          'unit_cost': l.unitCost,
          'total_cost': lineCost,
          'movement_uuid': mv,
          'warehouse_id': wid,
          'note': l.note,
        });
      }
      await txn.update('stock_docs', {'total_cost': roundMoney(total)}, where: 'id = ?', whereArgs: [id]);
      return id;
    });
    ActivityLog.log('إنشاء', 'المستندات المخزنية',
        '${stockDocLabels[docType] ?? docType} (#$docId) — ${valid.length} مادة${reason == null || reason.isEmpty ? '' : ' — $reason'}');
    return docId;
  }

  /// إلغاء مستند: حركات عكسية لكل سطر، والقيد يُحذف في الترحيل التالي.
  Future<void> voidDoc(int id, {String? reason}) async {
    final db = await erpDb();
    final h = await db.query('stock_docs', where: 'id = ?', whereArgs: [id], limit: 1);
    if (h.isEmpty) throw ErpException('المستند غير موجود');
    if (h.first['status'] != 'posted') throw ErpException('المستند ملغى مسبقاً');
    await PeriodLock.assertOpen(parseDate(h.first['doc_date']));
    await db.transaction((txn) async {
      final items = await txn.query('stock_doc_items', where: 'doc_id = ?', whereArgs: [id]);
      for (final it in items) {
        if (it['movement_uuid'] == null) continue;
        await ErpStock.move(txn,
            productId: it['product_id'] as int,
            baseDelta: -d0(it['base_qty']),
            kind: 'doc_void',
            note: 'إلغاء ${stockDocLabels[h.first['doc_type']] ?? ''} ${h.first['doc_no']}',
            warehouseId: it['warehouse_id'] as int?);
      }
      await txn.update('stock_docs', {'status': 'void', 'notes': '${h.first['notes'] ?? ''} [ملغى: ${reason ?? ''}]'},
          where: 'id = ?', whereArgs: [id]);
      // مستند جرد أُلغي ⇒ تعود جلسته مسودة
      await txn.update('stock_counts', {'status': 'draft', 'stock_doc_id': null, 'approved_at': null},
          where: 'stock_doc_id = ?', whereArgs: [id]);
    });
    ActivityLog.log('إلغاء', 'المستندات المخزنية',
        'إلغاء ${stockDocLabels[h.first['doc_type']] ?? ''} رقم ${h.first['doc_no']}${reason == null ? '' : ' — $reason'}');
  }

  Future<List<Map<String, Object?>>> list({String? docType, DateTime? from, DateTime? to}) async {
    final db = await erpDb();
    final where = <String>[];
    final args = <Object?>[];
    if (docType != null) {
      where.add('d.doc_type = ?');
      args.add(docType);
    }
    if (from != null) {
      where.add('d.doc_date >= ?');
      args.add(isoDay(from));
    }
    if (to != null) {
      where.add('d.doc_date < ?');
      args.add(isoDayAfter(to));
    }
    return db.rawQuery('''
      SELECT d.*, w.name AS warehouse_name, a.name AS account_name,
             (SELECT COUNT(*) FROM stock_doc_items i WHERE i.doc_id = d.id) AS n_items
      FROM stock_docs d LEFT JOIN warehouses w ON w.id = d.warehouse_id
      LEFT JOIN accounts a ON a.id = d.counter_account_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY d.doc_date DESC, d.id DESC LIMIT 1000
    ''', args);
  }

  Future<List<Map<String, Object?>>> items(int docId) async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT i.*, w.name AS warehouse_name FROM stock_doc_items i LEFT JOIN warehouses w ON w.id = i.warehouse_id
      WHERE i.doc_id = ? ORDER BY i.id''', [docId]);
  }

  /// إن كانت كلفة المادة صفراً وأُدخلت بكلفة في مستند إدخال/أول مدة، تُعتمد كلفتها.
  Future<void> adoptCostIfMissing(int productId, double unitCost) async {
    if (unitCost <= 0) return;
    final dbs = DatabaseService();
    final p = await dbs.getProductById(productId);
    if (p == null || (p.costPrice ?? 0) > 0) return;
    await dbs.updateProduct(p.copyWith(costPrice: unitCost, lastModifiedAt: DateTime.now()));
  }

  // ═══════════════════════════ الجرد الفعلي ═══════════════════════════

  /// جلسة جرد جديدة: لقطة للكميات الحالية في المخزن (كل المواد أو قسم).
  Future<int> createCount({int? warehouseId, int? categoryId, String? notes}) async {
    final db = await erpDb();
    final products = await ErpStock.all(db,
        where: categoryId == null ? "COALESCE(d.item_type, 'trade') != 'service'" : "p.category_id = ? AND COALESCE(d.item_type, 'trade') != 'service'",
        args: categoryId == null ? null : [categoryId]);
    return db.transaction((txn) async {
      final no = await nextDocNumber(txn, 'stock_counts', 'count_no');
      final id = await txn.insert('stock_counts', {
        'count_no': no,
        'count_date': DateTime.now().toIso8601String(),
        'warehouse_id': warehouseId,
        'scope': categoryId == null ? 'all' : 'category:$categoryId',
        'status': 'draft',
        'notes': notes,
        'created_by': currentUserName(),
        'created_at': DateTime.now().toIso8601String(),
      });
      for (final p in products) {
        final q = warehouseId == null ? p.stock : await ErpStock.available(txn, p.id, warehouseId: warehouseId);
        await txn.insert('stock_count_items', {
          'count_id': id,
          'product_id': p.id,
          'product_name': p.name,
          'system_qty': q,
          'counted_qty': null,
          'unit_cost': p.cost,
        });
      }
      return id;
    });
  }

  Future<List<Map<String, Object?>>> counts() async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT c.*, w.name AS warehouse_name,
        (SELECT COUNT(*) FROM stock_count_items i WHERE i.count_id = c.id) AS n,
        (SELECT COUNT(*) FROM stock_count_items i WHERE i.count_id = c.id AND i.counted_qty IS NOT NULL) AS counted
      FROM stock_counts c LEFT JOIN warehouses w ON w.id = c.warehouse_id
      ORDER BY c.id DESC
    ''');
  }

  Future<List<Map<String, Object?>>> countItems(int countId) async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT i.*, p.barcode, p.unit FROM stock_count_items i LEFT JOIN products p ON p.id = i.product_id
      WHERE i.count_id = ? ORDER BY i.product_name''', [countId]);
  }

  Future<void> setCounted(int itemId, double? qty) async {
    final db = await erpDb();
    await db.update('stock_count_items', {'counted_qty': qty}, where: 'id = ?', whereArgs: [itemId]);
  }

  /// اعتماد الجرد: الفرق بين المعدود والكمية **الحالية** (لا كمية اللقطة، حتى لا
  /// تُحسب مبيعات أثناء الجرد مرتين) يُسجَّل مستند «تسوية جرد».
  /// يعيد معرّف مستند التسوية (أو null إن لم توجد فروقات).
  Future<int?> approveCount(int countId) async {
    final db = await erpDb();
    final c = await db.query('stock_counts', where: 'id = ?', whereArgs: [countId], limit: 1);
    if (c.isEmpty) throw ErpException('الجلسة غير موجودة');
    if (c.first['status'] != 'draft') throw ErpException('الجلسة معتمدة مسبقاً');
    final wid = c.first['warehouse_id'] as int?;
    final items = await db.query('stock_count_items',
        where: 'count_id = ? AND counted_qty IS NOT NULL', whereArgs: [countId]);
    final lines = <StockDocLine>[];
    for (final it in items) {
      final pid = it['product_id'] as int;
      final now = await ErpStock.available(db, pid, warehouseId: wid);
      final diff = d0(it['counted_qty']) - now;
      if (diff.abs() < 1e-9) continue;
      final p = await ErpStock.byId(db, pid);
      lines.add(StockDocLine(
          productId: pid, name: '${it['product_name']}', baseQty: diff, unitCost: p?.cost ?? d0(it['unit_cost'])));
    }
    int? docId;
    if (lines.isNotEmpty) {
      docId = await create(
        docType: 'count',
        date: DateTime.now(),
        warehouseId: wid,
        reason: 'جرد رقم ${c.first['count_no']}',
        lines: lines,
        allowNegative: true,
      );
    }
    await db.update('stock_counts', {
      'status': 'approved',
      'stock_doc_id': docId,
      'approved_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [countId]);
    ActivityLog.log('اعتماد', 'الجرد الفعلي', 'اعتماد جرد رقم ${c.first['count_no']} — ${lines.length} فرق');
    return docId;
  }

  Future<void> deleteCount(int countId) async {
    final db = await erpDb();
    final c = await db.query('stock_counts', where: 'id = ?', whereArgs: [countId], limit: 1);
    if (c.isNotEmpty && c.first['status'] != 'draft') throw ErpException('الجلسة معتمدة — ألغِ مستند التسوية أولاً');
    await db.delete('stock_count_items', where: 'count_id = ?', whereArgs: [countId]);
    await db.delete('stock_counts', where: 'id = ?', whereArgs: [countId]);
  }

  // ═══════════════════════════ التصنيع ═══════════════════════════

  Future<List<Map<String, Object?>>> models() async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT m.*, p.name AS product_name,
        (SELECT COUNT(*) FROM bom_components c WHERE c.model_id = m.id) AS n_components
      FROM bom_models m LEFT JOIN products p ON p.id = m.product_id
      WHERE m.is_active = 1 ORDER BY m.model_no
    ''');
  }

  Future<int> saveModel({
    int? id,
    required String name,
    required int productId,
    double outputQty = 1,
    int? rawWarehouseId,
    int? finishedWarehouseId,
    String? notes,
    required List<Map<String, Object?>> components, // product_id, qty, is_essential
    required List<Map<String, Object?>> expenses, // name, amount
  }) async {
    if (name.trim().isEmpty) throw ErpException('اكتب اسم النموذج');
    if (outputQty <= 0) throw ErpException('كمية الإنتاج يجب أن تكون أكبر من صفر');
    if (components.isEmpty) throw ErpException('أضف مادة أولية واحدة على الأقل');
    if (components.any((c) => c['product_id'] == productId)) {
      throw ErpException('المادة المصنّعة لا تكون من موادها الأولية');
    }
    final db = await erpDb();
    return db.transaction((txn) async {
      final row = {
        'name': name.trim(),
        'product_id': productId,
        'output_qty': outputQty,
        'raw_warehouse_id': rawWarehouseId,
        'finished_warehouse_id': finishedWarehouseId,
        'notes': notes,
      };
      int mid;
      if (id == null) {
        mid = await txn.insert('bom_models', {
          ...row,
          'model_no': await nextDocNumber(txn, 'bom_models', 'model_no'),
          'is_active': 1,
          'created_at': DateTime.now().toIso8601String(),
        });
      } else {
        mid = id;
        await txn.update('bom_models', row, where: 'id = ?', whereArgs: [id]);
        await txn.delete('bom_components', where: 'model_id = ?', whereArgs: [id]);
        await txn.delete('bom_expenses', where: 'model_id = ?', whereArgs: [id]);
      }
      for (final c in components) {
        if (d0(c['qty']) <= 0) continue;
        await txn.insert('bom_components', {
          'model_id': mid,
          'product_id': c['product_id'],
          'qty': d0(c['qty']),
          'is_essential': (c['is_essential'] as int?) ?? 1,
        });
      }
      for (final e in expenses) {
        if (d0(e['amount']) <= 0) continue;
        await txn.insert('bom_expenses', {'model_id': mid, 'name': e['name'], 'amount': d0(e['amount'])});
      }
      return mid;
    });
  }

  Future<void> deleteModel(int id) async {
    final db = await erpDb();
    await db.update('bom_models', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> modelComponents(int modelId) async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT c.*, p.name AS product_name, p.cost_price, p.stock_quantity, p.unit
      FROM bom_components c LEFT JOIN products p ON p.id = c.product_id WHERE c.model_id = ? ORDER BY c.id
    ''', [modelId]);
  }

  Future<List<Map<String, Object?>>> modelExpenses(int modelId) async {
    final db = await erpDb();
    return db.query('bom_expenses', where: 'model_id = ?', whereArgs: [modelId], orderBy: 'id');
  }

  /// المواد اللازمة لتصنيع [qty] (بوحدة الإنتاج) مع المتوفر والناقص.
  Future<List<Map<String, Object?>>> requirements(int modelId, double qty) async {
    final db = await erpDb();
    final m = await db.query('bom_models', where: 'id = ?', whereArgs: [modelId], limit: 1);
    if (m.isEmpty) throw ErpException('النموذج غير موجود');
    final out = d0(m.first['output_qty']) <= 0 ? 1.0 : d0(m.first['output_qty']);
    final wid = m.first['raw_warehouse_id'] as int?;
    final comps = await modelComponents(modelId);
    final res = <Map<String, Object?>>[];
    for (final c in comps) {
      final need = d0(c['qty']) * qty / out;
      final avail = await ErpStock.available(db, c['product_id'] as int, warehouseId: wid);
      res.add({
        ...c,
        'need': need,
        'available': avail,
        'shortage': need > avail ? need - avail : 0.0,
        'surplus': avail > need ? avail - need : 0.0,
      });
    }
    return res;
  }

  /// أكبر كمية يمكن تصنيعها من المتوفر ([essentialOnly]: بالمواد الأساسية وحدها).
  Future<double> maxProducible(int modelId, {bool essentialOnly = false}) async {
    final req = await requirements(modelId, 1);
    double? best;
    for (final r in req) {
      if (essentialOnly && (r['is_essential'] as int? ?? 1) == 0) continue;
      final per = d0(r['need']);
      if (per <= 0) continue;
      final can = d0(r['available']) / per;
      best = best == null || can < best ? can : best;
    }
    final v = best ?? 0;
    return v < 0 ? 0 : v.floorToDouble();
  }

  /// تنفيذ عملية تصنيع: إخراج المواد الأولية وإدخال المادة الجاهزة بكلفة
  /// = كلفة المواد + المصاريف الصناعية. تُحدَّث كلفة المادة الجاهزة بالمتوسط المرجّح.
  Future<int> produce({
    required int modelId,
    required double qty,
    required DateTime date,
    double? overrideOverhead,
    int? overheadAccountId,
    bool allowShortage = false,
    String? notes,
  }) async {
    if (qty <= 0) throw ErpException('الكمية يجب أن تكون أكبر من صفر');
    final db = await erpDb();
    final m = await db.query('bom_models', where: 'id = ?', whereArgs: [modelId], limit: 1);
    if (m.isEmpty) throw ErpException('النموذج غير موجود');
    final model = m.first;
    final out = d0(model['output_qty']) <= 0 ? 1.0 : d0(model['output_qty']);
    final req = await requirements(modelId, qty);
    final lines = <StockDocLine>[];
    var rawCost = 0.0;
    for (final r in req) {
      final essential = (r['is_essential'] as int? ?? 1) == 1;
      if (!allowShortage && essential && d0(r['shortage']) > 1e-9) {
        throw ErpException('«${r['product_name']}» ناقصة ${fmtQty(d0(r['shortage']))} — لا يمكن التصنيع');
      }
      final need = d0(r['need']);
      final cost = d0(r['cost_price']);
      rawCost += need * cost;
      lines.add(StockDocLine(
        productId: r['product_id'] as int,
        name: '${r['product_name']}',
        baseQty: -need,
        unitCost: cost,
        warehouseId: model['raw_warehouse_id'] as int?,
      ));
    }
    final exps = await modelExpenses(modelId);
    final overhead = overrideOverhead ?? exps.fold<double>(0, (s, e) => s + d0(e['amount'])) * qty / out;
    final product = await ErpStock.byId(db, model['product_id'] as int);
    if (product == null) throw ErpException('المادة المصنّعة غير موجودة');
    final unitCost = qty <= 0 ? 0.0 : (roundMoney(rawCost) + roundMoney(overhead)) / qty;
    lines.add(StockDocLine(
      productId: product.id,
      name: product.name,
      baseQty: qty,
      unitCost: unitCost,
      warehouseId: model['finished_warehouse_id'] as int?,
    ));
    // الكلفة المرجّحة للمادة الجاهزة قبل إدخال الكمية الجديدة
    final oldQty = product.stock > 0 ? product.stock : 0.0;
    final newAvg = (oldQty * product.cost + qty * unitCost) / (oldQty + qty);
    final id = await create(
      docType: 'production',
      date: date,
      warehouseId: model['finished_warehouse_id'] as int?,
      reason: 'تصنيع ${fmtQty(qty)} × ${model['name']}',
      notes: notes,
      lines: lines,
      modelId: modelId,
      producedQty: qty,
      overheadAmount: overhead,
      overheadAccountId: overheadAccountId,
      allowNegative: allowShortage,
    );
    // تحديث كلفة المادة الجاهزة (المسار الأصلي — يزامن المادة ولا يلمس الكمية)
    final p = await DatabaseService().getProductById(product.id);
    if (p != null && newAvg > 0) {
      await DatabaseService().updateProduct(p.copyWith(costPrice: roundMoney(newAvg), lastModifiedAt: DateTime.now()));
    }
    return id;
  }

  /// مراقبة الهدر: الكميات المصروفة فعلاً مقابل المقدّرة في النموذج لكل عمليات النموذج.
  Future<List<Map<String, Object?>>> wasteReport(int modelId) async {
    final db = await erpDb();
    final m = await db.query('bom_models', where: 'id = ?', whereArgs: [modelId], limit: 1);
    if (m.isEmpty) return const [];
    final out = d0(m.first['output_qty']) <= 0 ? 1.0 : d0(m.first['output_qty']);
    final produced = await db.rawQuery(
        "SELECT COALESCE(SUM(produced_qty), 0) AS q FROM stock_docs WHERE model_id = ? AND status = 'posted'", [modelId]);
    final q = d0(produced.first['q']);
    final actual = await db.rawQuery('''
      SELECT i.product_id, SUM(-i.base_qty) AS used FROM stock_doc_items i JOIN stock_docs d ON d.id = i.doc_id
      WHERE d.model_id = ? AND d.status = 'posted' AND i.base_qty < 0 GROUP BY i.product_id
    ''', [modelId]);
    final used = {for (final r in actual) r['product_id'] as int: d0(r['used'])};
    final comps = await modelComponents(modelId);
    return [
      for (final c in comps)
        {
          'product_name': c['product_name'],
          'planned': d0(c['qty']) * q / out,
          'actual': used[c['product_id']] ?? 0.0,
        },
    ];
  }
}

/// حسابا فروقات الجرد (مثل إعدادات سهل): زيادة الجرد ← حساب إيراد، العجز ← حساب مصروف.
/// فارغان = حساب «فروقات جرد المخزون» الافتراضي للاثنين.
class CountAccounts {
  static const gainKey = 'acc_count_gain';
  static const lossKey = 'acc_count_loss';

  static Future<(int?, int?)> get() async {
    final db = await erpDb();
    return (
      int.tryParse((await Ledger.getSetting(db, gainKey)) ?? ''),
      int.tryParse((await Ledger.getSetting(db, lossKey)) ?? ''),
    );
  }

  static Future<void> set(int? gain, int? loss) async {
    final db = await erpDb();
    await Ledger.setSetting(db, gainKey, gain?.toString() ?? '');
    await Ledger.setSetting(db, lossKey, loss?.toString() ?? '');
  }
}
