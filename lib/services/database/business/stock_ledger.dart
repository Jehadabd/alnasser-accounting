// lib/services/database/business/stock_ledger.dart
//
// 📦 دفتر المخزون — مخزن واحد مشترك بين كل الأجهزة.
//
// القاعدة (مثل رصيد العميل = مجموع معاملاته):
//
//   كمية المنتج = مجموع حركات المخزون (stock_movements)
//               − مجموع بنود الفواتير المحفوظة غير المحذوفة (بالوحدة الأساسية)
//
// • حركات المخزون: الرصيد الافتتاحي، الشراء، التعديل اليدوي، إلغاء شراء...
//   كل حركة بمعرّف فريد، لا تُعدَّل أبداً، وتصل لكل الأجهزة
//   (StockMovementSyncService).
// • البيع لا يكتب حركة: بنود الفواتير تصل لكل الأجهزة داخل حزمة الفاتورة
//   أصلاً، فتعديل الفاتورة أو حذفها أو تعليقها ينعكس على المخزون تلقائياً.
// • الحساب داخل SQLite نفسها (مشغّلات): أي مسار يكتب بنداً أو يغيّر حالة
//   فاتورة يُبقي الكمية صحيحة، حتى المسارات التي لا يعرفها هذا الملف.
// • لا حدّ عند الصفر: الكمية قد تصير سالبة (بيع متزامن على جهازين) —
//   الحدّ عند الصفر يجعل النتيجة تتوقف على ترتيب وصول الفواتير، فتختلف
//   الأجهزة. منع البيع بلا رصيد قرار للواجهة (إعداد «السماح بالسالب»).
//
// الرصيد الافتتاحي معرّفه ثابت: opening_<معرّف المنتج>. أول جهاز يرفعه يثبّته
// للمجموعة كلها، والبقية يتبنّونه — فلا يتكرر الرصيد الافتتاحي أبداً.
// منتج بلا رصيد افتتاحي بعد (وصل من السحابة للتو) تبقى كميته كما هي حتى يصل.

import 'package:sqflite/sqflite.dart';

import '../../firebase_sync/uuid_helper.dart';

class StockLedger {
  StockLedger._();

  static const String openingKind = 'opening';

  /// يُستدعى بعد تسجيل حركة محلية (خدمة مزامنة الحركات تضبطه: رفع مؤجَّل
  /// قليلاً ليكتمل أولاً أي commit جارٍ). بلا اعتماد من هذه الطبقة على Firebase.
  static void Function()? onMovementAdded;

  /// معرّف الرصيد الافتتاحي لمنتج — واحد للمجموعة كلها.
  static String openingUuid(String productSyncUuid) => 'opening_$productSyncUuid';

  /// كمية بند فاتورة بالوحدة الأساسية (قطعة/متر). الشاشة تحفظ معامل التحويل
  /// لحظة البيع في units_in_large_unit (كرتون = 24، لفة = طولها)، فلا يتغير
  /// الحساب إن عُدّلت وحدات المنتج لاحقاً، وهو نفسه على كل الأجهزة.
  static const String _itemBaseQty = '''
    CASE WHEN COALESCE(ii.quantity_large_unit, 0) > 0
         THEN ii.quantity_large_unit * COALESCE(NULLIF(ii.units_in_large_unit, 0), 1)
         ELSE COALESCE(ii.quantity_individual, 0) END''';

  /// المبيع من منتج في كل الفواتير المحفوظة غير المحذوفة.
  static String _soldExpr(String u) => '''
    COALESCE((SELECT SUM($_itemBaseQty)
              FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
              WHERE ii.product_sync_uuid = $u
                AND COALESCE(i.is_deleted, 0) = 0
                AND COALESCE(i.status, '') != 'معلقة'), 0)''';

  /// الحركات: الرصيد الافتتاحي المعتمد وحده (معرّفه الثابت) + كل ما سواه.
  static String _movementsExpr(String u) => '''
    COALESCE((SELECT SUM(m.delta) FROM stock_movements m
              WHERE m.product_sync_uuid = $u
                AND (m.kind != '$openingKind' OR m.movement_uuid = 'opening_' || $u)), 0)''';

  /// الكمية المحسوبة لمنتج في صف products الحالي (للاستعمال داخل UPDATE products).
  static String _stockExpr() => '''
    CASE WHEN EXISTS (SELECT 1 FROM stock_movements m0
                      WHERE m0.movement_uuid = 'opening_' || products.sync_uuid)
         THEN ${_movementsExpr('products.sync_uuid')} - ${_soldExpr('products.sync_uuid')}
         ELSE products.stock_quantity END''';

  static String _recomputeWhere(String condition) =>
      'UPDATE products SET stock_quantity = ${_stockExpr()} WHERE $condition;';

  // ════════════════════════════════════════════════════════════════════
  //  المخطط والمشغّلات
  // ════════════════════════════════════════════════════════════════════

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        movement_uuid TEXT NOT NULL UNIQUE,
        product_sync_uuid TEXT NOT NULL,
        delta REAL NOT NULL,
        kind TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL,
        origin_device_id TEXT,
        is_uploaded INTEGER DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_product '
        'ON stock_movements(product_sync_uuid)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_pending '
        'ON stock_movements(is_uploaded) WHERE is_uploaded = 0');
    // معرّفات منتج دُمج في غيره (الاسم نفسه أُنشئ على جهازين): old ← new.
    // pending_doc: نسخة محلية دُمجت قبل أن يُرفع مستندها — يُرفع رغم ذلك
    // (ProductSyncService.uploadPendingCopies) لتعرف الأجهزة الأخرى معرّفها.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_uuid_alias (
        old_uuid TEXT PRIMARY KEY,
        new_uuid TEXT NOT NULL,
        pending_doc TEXT
      )
    ''');
  }

  /// مشغّلات إعادة حساب الكمية. تحلّ محل مشغّلَي الخصم/الإرجاع القديمين،
  /// اللذين كانا يخصمان مرة ثانية فوق خصم كود التطبيق (خصم مزدوج على الجهاز
  /// البائع، ومرة واحدة على غيره) ولا يعرفان التحويل بين الوحدات.
  static Future<void> setupTriggers(DatabaseExecutor db) async {
    for (final t in const [
      'trg_invoice_items_stock_deduct',
      'trg_invoice_items_stock_restore',
      'trg_stock_item_fill_product',
      'trg_stock_item_ins',
      'trg_stock_item_del',
      'trg_stock_item_upd',
      'trg_stock_invoice_state',
      'trg_stock_invoice_del',
      'trg_stock_mv_ins',
      'trg_stock_mv_del',
      'trg_stock_mv_upd',
      'trg_stock_product_ins',
      'trg_stock_product_uuid',
      'trg_stock_item_alias',
      'trg_stock_mv_alias',
    ]) {
      await db.execute('DROP TRIGGER IF EXISTS $t;');
    }

    // بند بلا معرّف منتج (مسار قديم، أو فاتورة من إصدار سابق): نربطه بالمنتج
    // المحلي بالرقم ثم بالاسم — كما كان خصم المخزون القديم يطابق.
    await db.execute('''
      CREATE TRIGGER trg_stock_item_fill_product
      AFTER INSERT ON invoice_items
      WHEN (NEW.product_sync_uuid IS NULL OR NEW.product_sync_uuid = '')
      BEGIN
        UPDATE invoice_items SET product_sync_uuid = COALESCE(
            (SELECT sync_uuid FROM products WHERE id = NEW.product_id
               AND sync_uuid IS NOT NULL AND sync_uuid != ''),
            (SELECT sync_uuid FROM products WHERE name = NEW.product_name
               AND sync_uuid IS NOT NULL AND sync_uuid != '' LIMIT 1))
        WHERE id = NEW.id;
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER trg_stock_item_ins AFTER INSERT ON invoice_items
      WHEN NEW.product_sync_uuid IS NOT NULL AND NEW.product_sync_uuid != ''
      BEGIN
        ${_recomputeWhere('sync_uuid = NEW.product_sync_uuid')}
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER trg_stock_item_del AFTER DELETE ON invoice_items
      WHEN OLD.product_sync_uuid IS NOT NULL AND OLD.product_sync_uuid != ''
      BEGIN
        ${_recomputeWhere('sync_uuid = OLD.product_sync_uuid')}
      END;
    ''');
    // الأعمدة التي تدخل في الحساب فقط (تعديل السعر أو ترحيل أعمدة الـ cents لا يعيده)
    await db.execute('''
      CREATE TRIGGER trg_stock_item_upd
      AFTER UPDATE OF product_sync_uuid, invoice_id, quantity_large_unit,
                      units_in_large_unit, quantity_individual ON invoice_items
      BEGIN
        ${_recomputeWhere('sync_uuid IN (OLD.product_sync_uuid, NEW.product_sync_uuid)')}
      END;
    ''');
    // تعليق فاتورة، حفظها، حذفها (حذف منطقي) — كلها تغيّر ما يُحسب مبيعاً
    await db.execute('''
      CREATE TRIGGER trg_stock_invoice_state AFTER UPDATE OF status, is_deleted ON invoices
      WHEN COALESCE(OLD.status, '') IS NOT COALESCE(NEW.status, '')
        OR COALESCE(OLD.is_deleted, 0) IS NOT COALESCE(NEW.is_deleted, 0)
      BEGIN
        ${_recomputeWhere('sync_uuid IN (SELECT product_sync_uuid FROM invoice_items WHERE invoice_id = NEW.id)')}
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER trg_stock_invoice_del AFTER DELETE ON invoices
      BEGIN
        ${_recomputeWhere('sync_uuid IN (SELECT product_sync_uuid FROM invoice_items WHERE invoice_id = OLD.id)')}
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER trg_stock_mv_ins AFTER INSERT ON stock_movements
      BEGIN
        ${_recomputeWhere('sync_uuid = NEW.product_sync_uuid')}
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER trg_stock_mv_del AFTER DELETE ON stock_movements
      BEGIN
        ${_recomputeWhere('sync_uuid = OLD.product_sync_uuid')}
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER trg_stock_mv_upd AFTER UPDATE ON stock_movements
      BEGIN
        ${_recomputeWhere('sync_uuid IN (OLD.product_sync_uuid, NEW.product_sync_uuid)')}
      END;
    ''');
    // منتج وصل بعد حركاته (أو تغيّر معرّفه): كميته من الدفتر لا من مستنده.
    // كان يبقى على كمية مستند المنتج (لحظة رفعه عند منشئه) فيفوته ما بعدها.
    await db.execute('''
      CREATE TRIGGER trg_stock_product_ins AFTER INSERT ON products
      WHEN NEW.sync_uuid IS NOT NULL AND NEW.sync_uuid != ''
      BEGIN
        ${_recomputeWhere('id = NEW.id')}
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER trg_stock_product_uuid AFTER UPDATE OF sync_uuid ON products
      WHEN NEW.sync_uuid IS NOT NULL AND NEW.sync_uuid != ''
      BEGIN
        ${_recomputeWhere('id = NEW.id')}
      END;
    ''');
    // بند أو حركة وصلا بمعرّف منتج دُمج في غيره (rekeyProduct): يتبعان المعرّف
    // الحيّ، مهما كان مسار الوصول (حزمة فاتورة، حركة، نسخة احتياطية...).
    // الرصيد الافتتاحي لا يُحوَّل: لا يُحسب إلا رصيد المعرّف الحي نفسه.
    await db.execute('''
      CREATE TRIGGER trg_stock_item_alias AFTER INSERT ON invoice_items
      WHEN NEW.product_sync_uuid IS NOT NULL AND NEW.product_sync_uuid != ''
        AND EXISTS (SELECT 1 FROM product_uuid_alias WHERE old_uuid = NEW.product_sync_uuid)
      BEGIN
        UPDATE invoice_items SET product_sync_uuid =
            (SELECT new_uuid FROM product_uuid_alias WHERE old_uuid = NEW.product_sync_uuid)
        WHERE id = NEW.id;
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER trg_stock_mv_alias AFTER INSERT ON stock_movements
      WHEN NEW.kind != '$openingKind'
        AND EXISTS (SELECT 1 FROM product_uuid_alias WHERE old_uuid = NEW.product_sync_uuid)
      BEGIN
        UPDATE stock_movements SET product_sync_uuid =
            (SELECT new_uuid FROM product_uuid_alias WHERE old_uuid = NEW.product_sync_uuid)
        WHERE id = NEW.id;
      END;
    ''');
  }

  // ════════════════════════════════════════════════════════════════════
  //  الترقية لمرة واحدة + الرصيد الافتتاحي
  // ════════════════════════════════════════════════════════════════════

  /// تُستدعى عند كل فتح لقاعدة البيانات (بعد ensureSchema). آمنة التكرار.
  static Future<void> migrate(Database db) async {
    // بنود قديمة بلا معرّف منتج: بالرقم ثم بالاسم (كمطابقة الخصم القديم)
    await db.execute('''
      UPDATE invoice_items SET product_sync_uuid = COALESCE(
          (SELECT sync_uuid FROM products p WHERE p.id = invoice_items.product_id
             AND p.sync_uuid IS NOT NULL AND p.sync_uuid != ''),
          (SELECT sync_uuid FROM products p WHERE p.name = invoice_items.product_name
             AND p.sync_uuid IS NOT NULL AND p.sync_uuid != '' LIMIT 1))
      WHERE (product_sync_uuid IS NULL OR product_sync_uuid = '')
    ''');
    await ensureOpenings(db);
  }

  /// لكل منتج بلا رصيد افتتاحي: رصيد افتتاحي = كميته الحالية + ما بيع منه في
  /// الفواتير المعروفة هنا. بعده الحساب = الكمية الحالية نفسها (لا قفزة محلية)،
  /// ثم يتبنّى الجهاز الرصيد الذي ثبّته أول جهاز رفعه للمجموعة.
  ///
  /// [upload] = false لمنتج وصل من جهاز آخر: رصيد «مؤقت» محلي لا يُرفع أبداً
  /// (is_uploaded = 2) حتى يصل رصيد منشئه. لو رُفع، قد يسبق رصيدَ المنشئ
  /// (المنشئ بلا إنترنت، ومستند المنتج وصل قبل حركته) فيثبّت للمجموعة كلها
  /// كميةً قديمة من مستند المنتج. يرفعه فقط: منشئ المنتج، وترقية المنتجات القديمة.
  static const int provisionalFlag = 2;

  static Future<int> ensureOpenings(DatabaseExecutor db,
      {String? onlyUuid, bool upload = true}) async {
    final rows = await db.rawQuery('''
      SELECT p.sync_uuid AS u, p.stock_quantity AS q, ${_soldExpr('p.sync_uuid')} AS sold
      FROM products p
      WHERE p.sync_uuid IS NOT NULL AND p.sync_uuid != ''
        ${onlyUuid != null ? 'AND p.sync_uuid = ?' : ''}
        AND NOT EXISTS (SELECT 1 FROM stock_movements m
                        WHERE m.movement_uuid = 'opening_' || p.sync_uuid)
    ''', onlyUuid != null ? [onlyUuid] : const []);
    var n = 0;
    for (final r in rows) {
      final u = r['u'] as String;
      final q = (r['q'] as num?)?.toDouble() ?? 0.0;
      final sold = (r['sold'] as num?)?.toDouble() ?? 0.0;
      final inserted = await db.insert(
        'stock_movements',
        {
          'movement_uuid': openingUuid(u),
          'product_sync_uuid': u,
          'delta': q + sold,
          'kind': openingKind,
          'note': upload ? 'رصيد افتتاحي' : 'رصيد افتتاحي مؤقت (بانتظار رصيد المنشئ)',
          'created_at': DateTime.now().toIso8601String(),
          'is_uploaded': upload ? 0 : provisionalFlag,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (inserted > 0) n++;
    }
    if (n > 0 && upload) onMovementAdded?.call();
    return n;
  }

  // ════════════════════════════════════════════════════════════════════
  //  الحركات
  // ════════════════════════════════════════════════════════════════════

  /// يسجّل حركة مخزون محلية (تُرفع لاحقاً). [delta] بالوحدة الأساسية:
  /// موجب = دخول (شراء، إضافة يدوية)، سالب = خروج (إلغاء شراء، طرح يدوي).
  /// المشغّل يعيد حساب الكمية في نفس المعاملة.
  static Future<String?> addMovement(
    DatabaseExecutor db, {
    required String productSyncUuid,
    required double delta,
    required String kind,
    String? note,
    String? originDeviceId,
  }) async {
    if (productSyncUuid.isEmpty || delta.abs() < 1e-9) return null;
    // منتج بلا رصيد افتتاحي بعد (وصل من جهاز آخر ولم يصل رصيد منشئه): رصيد
    // مؤقت محلي، وإلا بقيت الكمية «مجمّدة» (الحساب لا يعمل قبله) فتضيع هذه
    // الحركة من العرض. المنتجات المحلية لها رصيدها منذ إنشائها أو الترقية.
    await ensureOpenings(db, onlyUuid: productSyncUuid, upload: false);
    final uuid = UuidHelper.newStockMovementUuid();
    await db.insert('stock_movements', {
      'movement_uuid': uuid,
      'product_sync_uuid': productSyncUuid,
      'delta': delta,
      'kind': kind,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
      'origin_device_id': originDeviceId,
      'is_uploaded': 0,
    });
    onMovementAdded?.call();
    return uuid;
  }

  /// معرّف المزامنة لمنتج بالرقم المحلي (يولّده ويثبّته إن لم يوجد).
  static Future<String?> productSyncUuidForId(DatabaseExecutor db, int productId) async {
    final r = await db.query('products',
        columns: ['sync_uuid'], where: 'id = ?', whereArgs: [productId], limit: 1);
    if (r.isEmpty) return null;
    final u = r.first['sync_uuid'] as String?;
    if (u != null && u.isNotEmpty) return u;
    final fresh = UuidHelper.newProductUuid();
    await db.update('products', {'sync_uuid': fresh, 'last_synced_at': null},
        where: 'id = ?', whereArgs: [productId]);
    return fresh;
  }

  /// إعادة حساب كمية منتج (أو كل المنتجات) من الدفتر.
  static Future<void> recompute(DatabaseExecutor db, {String? productSyncUuid}) async {
    if (productSyncUuid != null) {
      await db.rawUpdate(
          'UPDATE products SET stock_quantity = ${_stockExpr()} WHERE sync_uuid = ?',
          [productSyncUuid]);
    } else {
      await db.rawUpdate('UPDATE products SET stock_quantity = ${_stockExpr()} '
          "WHERE sync_uuid IS NOT NULL AND sync_uuid != ''");
    }
  }

  /// دمج معرّف منتج في معرّف حيّ (نسختان من المنتج نفسه — مطابقة كتالوج
  /// بالاسم): البنود والحركات تتبع [newUuid]، الآن وكل ما يصل لاحقاً بالمعرّف
  /// القديم (مشغّلا alias). الرصيد الافتتاحي القديم يبقى مهملاً (لا يُحسب إلا
  /// opening_<الحي>). آمنة التكرار، وتقبل الدمج في أي اتجاه لاحقاً.
  ///
  /// بدون سجلّ التحويل كانت الحركات وبنود الفواتير التي تصل بعد الدمج بالمعرّف
  /// القديم لا تُحسب لأي منتج، فتختلف الكمية بين الأجهزة.
  static Future<void> rekeyProduct(DatabaseExecutor db, String oldUuid, String newUuid) async {
    if (oldUuid.isEmpty || newUuid.isEmpty || oldUuid == newUuid) return;
    // الحي لا يُحوَّل لغيره، ومن كان يُحوَّل للقديم يُحوَّل للحي مباشرة:
    // خطوة واحدة دائماً، بلا سلاسل ولا حلقات
    await db.delete('product_uuid_alias', where: 'old_uuid = ?', whereArgs: [newUuid]);
    await db.update('product_uuid_alias', {'new_uuid': newUuid},
        where: 'new_uuid = ?', whereArgs: [oldUuid]);
    // تحديث ثم إدراج (لا REPLACE): يحفظ pending_doc إن وُجد
    final n = await db.update('product_uuid_alias', {'new_uuid': newUuid},
        where: 'old_uuid = ?', whereArgs: [oldUuid]);
    if (n == 0) {
      await db.insert('product_uuid_alias', {'old_uuid': oldUuid, 'new_uuid': newUuid});
    }
    await db.delete('product_uuid_alias', where: 'old_uuid = new_uuid');
    const aliased = 'SELECT old_uuid FROM product_uuid_alias WHERE new_uuid = ?';
    await db.rawUpdate(
        'UPDATE invoice_items SET product_sync_uuid = ? WHERE product_sync_uuid IN ($aliased)',
        [newUuid, newUuid]);
    await db.rawUpdate(
        "UPDATE stock_movements SET product_sync_uuid = ? "
        "WHERE product_sync_uuid IN ($aliased) AND kind != '$openingKind'",
        [newUuid, newUuid]);
  }
}
