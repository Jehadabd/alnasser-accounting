// lib/services/database/core/database_migrations.dart
// إنشاء الجداول وترقيتها

import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../dao/product_dao.dart';
import 'package:alnaser/services/database/core/database_helpers.dart'; // ✅ Explicit import

/// فئة مسؤولة عن إدارة مخطط قاعدة البيانات والترقيات
class DatabaseMigrations {
  
  /// إنشاء الجداول الأساسية
  static Future<void> createTables(Database db) async {
    // 👥 جدول العملاء
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        current_total_debt REAL NOT NULL,
        last_modified_at TEXT,
        sync_uuid TEXT,
        is_deleted INTEGER DEFAULT 0,
        sync_last_update_at TEXT,
        audio_note_path TEXT,
        UNIQUE(name, phone)
      )
    ''');

    // 💰 جدول المعاملات
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        amount_changed REAL NOT NULL,
        transaction_date TEXT NOT NULL,
        transaction_note TEXT,
        balance_before_transaction REAL,
        new_balance_after_transaction REAL,
        invoice_id INTEGER,
        is_created_by_me INTEGER DEFAULT 1,
        is_uploaded INTEGER DEFAULT 0,
        transaction_uuid TEXT,
        checksum TEXT,
        transaction_type TEXT,
        description TEXT,
        audio_note_path TEXT,
        is_read_by_others INTEGER DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE SET NULL
      )
    ''');
    
    // فهرس لجدول المعاملات لتحسين الأداء
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_customer_id ON transactions(customer_id);');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS ux_transactions_uuid ON transactions(transaction_uuid) WHERE transaction_uuid IS NOT NULL;');

    // 📦 جدول المنتجات
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        unit_price REAL NOT NULL DEFAULT 0,
        cost_price REAL NOT NULL,
        pieces_per_unit INTEGER DEFAULT 1,
        length_per_unit REAL DEFAULT 1,
        price1 REAL NOT NULL DEFAULT 0,
        price2 REAL,
        price3 REAL,
        price4 REAL,
        price5 REAL,
        price6 REAL,
        image_path TEXT,
        category_id INTEGER,
        is_weighable INTEGER DEFAULT 0,
        base_weight REAL,
        weight_unit TEXT,
        has_expiry INTEGER DEFAULT 0,
        barcode TEXT,
        stock_quantity REAL DEFAULT 0.0,
        unit_costs TEXT,
        unit_hierarchy TEXT,
        alert_quantity REAL,
        alert_unit TEXT,
        sku TEXT,
        product_type TEXT,
        invoice_policy TEXT,
        name_norm TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_modified_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // 🧾 جدول الفواتير
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_date TEXT NOT NULL,
        total_amount REAL NOT NULL,
        customer_name TEXT,
        customer_phone TEXT,
        customer_address TEXT,
        notes TEXT,
        items_json TEXT, 
        created_at TEXT NOT NULL,
        installer_id INTEGER,
        installer_name TEXT,
        final_total REAL DEFAULT 0,
        loading_fee REAL DEFAULT 0,
        return_amount REAL DEFAULT 0,
        is_locked INTEGER DEFAULT 0,
        discount REAL DEFAULT 0,
        status TEXT DEFAULT 'محفوظة',
        customer_id INTEGER,
        amount_paid_on_invoice REAL DEFAULT 0,
        points_rate REAL DEFAULT 1.0,
        is_created_by_me INTEGER DEFAULT 1,
        FOREIGN KEY (installer_id) REFERENCES installers (id) ON DELETE SET NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE SET NULL
      )
    ''');

    // 📦 جدول بنود الفاتورة
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        unit TEXT NOT NULL,
        unit_price REAL NOT NULL,
        cost_price REAL NOT NULL,
        quantity_individual REAL NOT NULL,
        quantity_large_unit REAL NOT NULL,
        applied_price REAL NOT NULL,
        item_total REAL NOT NULL,
        product_id INTEGER,
        actual_cost_price REAL,
        sale_type TEXT,
        units_in_large_unit REAL,
        unique_id TEXT,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
      )
    ''');

    // 👷 جدول الفنيين
    await db.execute('''
      CREATE TABLE IF NOT EXISTS installers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        phone TEXT,
        points REAL DEFAULT 0,
        billed_amount REAL DEFAULT 0,
        total_points REAL DEFAULT 0.0
      )
    ''');

    // 🔧 جدول التسويات وتعديلات الفواتير
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_adjustments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        adjustment_type TEXT NOT NULL,
        amount_delta REAL NOT NULL,
        reason TEXT,
        created_at TEXT NOT NULL,
        product_id INTEGER,
        product_name TEXT,
        quantity REAL,
        price REAL,
        unit TEXT,
        sale_type TEXT,
        units_in_large_unit REAL,
        settlement_payment_type TEXT,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
      )
    ''');

    // 📝 جدول سجلات الفواتير (Invoice Logs)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        details TEXT,
        created_at TEXT NOT NULL,
        created_by TEXT,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
      )
    ''');

    // 🔍 جدول التدقيق المالي
    await db.execute('''
      CREATE TABLE IF NOT EXISTS financial_audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_type TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        old_values TEXT,
        new_values TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // 📸 جدول لقطات الفواتير
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        version_number INTEGER NOT NULL DEFAULT 1,
        snapshot_type TEXT NOT NULL,
        customer_name TEXT,
        customer_phone TEXT,
        customer_address TEXT,
        invoice_date TEXT,
        payment_type TEXT,
        total_amount REAL,
        discount REAL,
        amount_paid REAL,
        loading_fee REAL,
        items_json TEXT,
        created_at TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
      )
    ''');

    // 📑 جدول التصنيفات
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        parent_id INTEGER,
        description TEXT,
        FOREIGN KEY (parent_id) REFERENCES categories (id) ON DELETE SET NULL
      )
    ''');

    // 📏 جدول الوحدات
    await db.execute('''
      CREATE TABLE IF NOT EXISTS units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        is_default INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    
    // 🏷️ جدول باركودات المنتجات (متعددة لكل منتج)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_barcodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        barcode TEXT NOT NULL,
        variant_label TEXT,
        cost_price REAL,
        sell_price REAL,
        is_default INTEGER DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE,
        UNIQUE(barcode)
      )
    ''');
    
    // فهرس للبحث السريع بالباركود
    await db.execute('CREATE INDEX IF NOT EXISTS idx_product_barcodes_barcode ON product_barcodes(barcode);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_product_barcodes_product_id ON product_barcodes(product_id);');
    
    // ⭐ جدول نقاط الفنيين
    await db.execute('''
      CREATE TABLE IF NOT EXISTS installer_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        installer_id INTEGER NOT NULL,
        invoice_id INTEGER,
        points REAL NOT NULL,
        reason TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (installer_id) REFERENCES installers (id) ON DELETE CASCADE,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE SET NULL
      )
    ''');
    
    // 📄 جدول أرشيف سندات القبض
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_receipt_vouchers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_number INTEGER NOT NULL,
        customer_id INTEGER NOT NULL,
        customer_name TEXT NOT NULL,
        before_payment REAL NOT NULL,
        paid_amount REAL NOT NULL,
        after_payment REAL NOT NULL,
        transaction_id INTEGER,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE,
        FOREIGN KEY (transaction_id) REFERENCES transactions (id) ON DELETE SET NULL
      )
    ''');
    
    // 👤 جدول المستخدمين
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'accountant',
        created_at TEXT NOT NULL
      )
    ''');
    
    // 🔑 جدول صلاحيات المستخدمين
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_permissions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        permission_key TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
        UNIQUE(user_id, permission_key)
      )
    ''');
    
    // 🏭 جدول الموردين
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        currency TEXT NOT NULL DEFAULT 'IQD',
        payment_terms TEXT DEFAULT 'cash',
        credit_days INTEGER DEFAULT 0,
        total_debt_iqd REAL NOT NULL DEFAULT 0.0,
        total_debt_usd REAL NOT NULL DEFAULT 0.0,
        total_invoices INTEGER DEFAULT 0,
        total_payments INTEGER DEFAULT 0,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    
    // 📥 جدول فواتير المشتريات
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL,
        supplier_id INTEGER NOT NULL,
        total_amount REAL NOT NULL DEFAULT 0.0,
        paid_amount REAL NOT NULL DEFAULT 0.0,
        currency TEXT NOT NULL DEFAULT 'IQD',
        status TEXT NOT NULL DEFAULT 'draft',
        date TEXT NOT NULL,
        due_date TEXT,
        created_by_user_id INTEGER,
        notes TEXT,
        last_modified_at TEXT,
        delegate_id INTEGER,
        attachment_path TEXT,
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE CASCADE,
        FOREIGN KEY (delegate_id) REFERENCES supplier_delegates (id) ON DELETE SET NULL
      )
    ''');

    // 👤 جدول المندوبين (Delegates) - New for ERP
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_delegates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        notes TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE CASCADE
      )
    ''');
    
    // 📦 جدول بنود فواتير المشتريات
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        unit_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        conversion_factor REAL NOT NULL DEFAULT 1.0,
        total_price REAL NOT NULL,
        received_quantity REAL DEFAULT 0.0,
        FOREIGN KEY (invoice_id) REFERENCES purchase_invoices (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT
      )
    ''');
    
    // 💳 جدول مدفوعات الموردين
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_number TEXT NOT NULL,
        supplier_id INTEGER NOT NULL,
        invoice_id INTEGER,
        amount REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'IQD',
        payment_method TEXT NOT NULL,
        reference_number TEXT,
        date TEXT NOT NULL,
        notes TEXT,
        created_by_user_id INTEGER,
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE CASCADE,
        FOREIGN KEY (invoice_id) REFERENCES purchase_invoices (id) ON DELETE SET NULL
      )
    ''');
    
    // 🔄 جدول عمليات المزامنة
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_operations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          local_sequence INTEGER,
          operation_id TEXT UNIQUE,
          operation_type TEXT,
          entity_table TEXT,
          entity_id INTEGER,
          data_payload TEXT,
          timestamp TEXT,
          device_id TEXT,
          status TEXT DEFAULT 'pending',
          uploaded_at TEXT
      )
    ''');
    
    // 🔄 جدول العمليات المطبقة
    await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_applied_operations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            operation_id TEXT UNIQUE,
            device_id TEXT,
            applied_at TEXT
        )
    ''');
    
    // 🔄 جدول حالة المزامنة
    await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            device_id TEXT,
            device_name TEXT,
            local_sequence INTEGER DEFAULT 0,
            synced_up_to_global INTEGER DEFAULT 0,
            last_sync_at TEXT,
            secret_key_hash TEXT
        )
    ''');
    
    // 🔄 جدول سجل المزامنة
    await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_audit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sync_start_time TEXT NOT NULL,
            sync_end_time TEXT,
            sync_type TEXT, -- Auto/Manual/Full/Delta
            operations_uploaded INTEGER DEFAULT 0,
            operations_downloaded INTEGER DEFAULT 0,
            operations_applied INTEGER DEFAULT 0,
            operations_failed INTEGER DEFAULT 0,
            success INTEGER DEFAULT 0, -- 1 success, 0 failure
            error_message TEXT,
            affected_customers TEXT, -- JSON Array of IDs
            warnings TEXT,
            device_id TEXT,
            backup_path TEXT
        )
    ''');

    // 🔒 جدول الأقفال (للمنع من التعديل المتزامن)
    await db.execute('''
        CREATE TABLE IF NOT EXISTS resource_locks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            resource_type TEXT NOT NULL, -- 'customer', 'invoice'
            resource_id INTEGER NOT NULL,
            locked_by_device_id TEXT NOT NULL,
            locked_by_user_name TEXT,
            locked_at TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            UNIQUE(resource_type, resource_id)
        )
    ''');

    await _createFtsTable(db);
    await _createProductSpecsTable(db);
    
    // 📊 View: product_price_stats
    await db.execute('''
      CREATE VIEW IF NOT EXISTS product_price_stats AS
      SELECT 
        product_id,
        AVG(applied_price) as median_price,
        COUNT(*) as sales_count
      FROM invoice_items
      GROUP BY product_id
    ''');

    // 📊 View: recent_sales_buffer
    await db.execute('''
      CREATE VIEW IF NOT EXISTS recent_sales_buffer AS
      SELECT 
        ii.product_id,
        ii.applied_price as price,
        i.invoice_date
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
    ''');
  }

  // إنشاء جدول FTS5 للبحث السريع
  static Future<void> _createFtsTable(Database db) async {
    try {
      // إجبار إعادة بناء الجدول والترايغرز في حال كان الهيكل القديم تالفاً
      await db.execute('DROP TRIGGER IF EXISTS products_ai;');
      await db.execute('DROP TRIGGER IF EXISTS products_ad;');
      await db.execute('DROP TRIGGER IF EXISTS products_au;');
      await db.execute('DROP TABLE IF EXISTS products_fts;');
      
      await db.execute('''
        CREATE VIRTUAL TABLE products_fts USING fts5(
          name, 
          unit, 
          content='products', 
          content_rowid='id'
        );
      ''');
      
      // الترايغرز
      await db.execute('''
        CREATE TRIGGER products_ai AFTER INSERT ON products BEGIN
          INSERT INTO products_fts(rowid, name, unit) VALUES (new.id, new.name, new.unit);
        END;
      ''');
      await db.execute('''
        CREATE TRIGGER products_ad AFTER DELETE ON products BEGIN
          INSERT INTO products_fts(products_fts, rowid, name, unit) VALUES('delete', old.id, old.name, old.unit);
        END;
      ''');
      await db.execute('''
        CREATE TRIGGER products_au AFTER UPDATE ON products BEGIN
          INSERT INTO products_fts(products_fts, rowid, name, unit) VALUES('delete', old.id, old.name, old.unit);
          INSERT INTO products_fts(rowid, name, unit) VALUES (new.id, new.name, new.unit);
        END;
      ''');
      
      // rebuild index
      await ProductDao(getDatabase: () async => db).rebuildFTSIndex();
    } catch (e) {
      print('FTS5 Error: $e');
    }
  }

  static Future<void> _createProductSpecsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_specs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER,
        spec_key TEXT,
        spec_value TEXT,
        is_searchable INTEGER DEFAULT 1,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');
  }

  /// ضمان وجود جميع الأعمدة المطلوبة في الجداول
  static Future<void> ensureSchema(Database db) async {
    // 1. إصلاح مشكلة price6 (إضافة العمود إذا لم يكن موجوداً)
    await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'price6', 'REAL');
    
    // 2. إضافة عمود تاريخ الانتهاء (للميزة الجديدة)
    await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'expiry_date', 'TEXT');
    
    // 3. إضافة عمود تنبيه الصلاحية (اختياري، إذا كنا سنستخدمه)
    // await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'expiry_alert_threshold', 'INTEGER');

    // 4. التأكد من وجود جدول المندوبين (للميزة الجديدة)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_delegates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        notes TEXT,
        is_active INTEGER DEFAULT 1,
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE CASCADE
      )
    ''');

    // 5. إضافة عمود delegate_id لجدول فواتير الشراء (إذا لم يكن موجوداً)
    // نستخدم rawQuery للتأكد لأن addColumnIfNotExists قد لا تدعم FK حالياً
    try {
      final cols = await db.rawQuery('PRAGMA table_info(purchase_invoices);');
      final hasDelegateId = cols.any((c) => (c['name'] == 'delegate_id'));
      if (!hasDelegateId) {
        await db.execute('ALTER TABLE purchase_invoices ADD COLUMN delegate_id INTEGER REFERENCES supplier_delegates(id) ON DELETE SET NULL;');
      }
      
      // 6. إضافة عمود last_modified_at لجدول فواتير الشراء
      final hasLastMod = cols.any((c) => (c['name'] == 'last_modified_at'));
      if (!hasLastMod) {
         await db.execute('ALTER TABLE purchase_invoices ADD COLUMN last_modified_at TEXT;');
      }

      // 7. إضافة عمود attachment_path لجدول فواتير الشراء
      final hasAttachment = cols.any((c) => (c['name'] == 'attachment_path'));
      if (!hasAttachment) {
         await db.execute('ALTER TABLE purchase_invoices ADD COLUMN attachment_path TEXT;');
      }

      // 8. إضافة أعمدة Odoo (sku, product_type, invoice_policy)
      await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'sku', 'TEXT');
      await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'product_type', 'TEXT');
      await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'invoice_policy', 'TEXT');

    } catch (_) {
      // قد تفشل إذا كان الجدول غير موجود أصلاً (سيتم إنشاؤه بالكامل لاحقاً)
    }
    
    // 9. إضافة أعمدة المنتج الجديدة (has_expiry, expiry_alert_days)
    await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'has_expiry', 'INTEGER DEFAULT 0');
    await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'expiry_alert_days', 'INTEGER');
    
    // 10. إضافة أعمدة الفاتورة الجديدة (created_by_user_id, created_by_username, payment_type)
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'created_by_user_id', 'INTEGER');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'created_by_username', 'TEXT');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'payment_type', 'TEXT DEFAULT \'دين\'');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'last_modified_at', 'TEXT');

    // 🔥 أعمدة مزامنة Firebase للفواتير (مفاتيح الهوية وحل التعارضات)
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'invoice_uuid', 'TEXT');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'creator_device_id', 'TEXT');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'version', 'INTEGER DEFAULT 1');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'is_synced', 'INTEGER DEFAULT 0');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'monthly_sequence_number', 'INTEGER');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'notes', 'TEXT');
    // فهرس فريد على invoice_uuid (يسمح بـ NULL لأداء آمن للفواتير القديمة)
    try {
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS ux_invoices_invoice_uuid ON invoices(invoice_uuid) WHERE invoice_uuid IS NOT NULL;');
    } catch (_) {}

    // 11. إضافة أعمدة العملاء المفقودة
    await DatabaseHelpers.addColumnIfNotExists(db, 'customers', 'general_note', 'TEXT');
    await DatabaseHelpers.addColumnIfNotExists(db, 'customers', 'created_at', 'TEXT');
    
    // 12. إضافة عمود name_norm للبحث العربي المطبع
    await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'name_norm', 'TEXT');

    // 13. إضافة أعمدة بنود الفاتورة المفقودة (حرجة لنظام المخزون)
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoice_items', 'product_id', 'INTEGER');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoice_items', 'unique_id', 'TEXT');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoice_items', 'actual_cost_price', 'REAL');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoice_items', 'sale_type', 'TEXT');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoice_items', 'units_in_large_unit', 'REAL');

    // 14. إضافة أعمدة التعديلات (لضمان عمل الاسترجاع)
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoice_adjustments', 'product_id', 'INTEGER');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoice_adjustments', 'sale_type', 'TEXT');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoice_adjustments', 'units_in_large_unit', 'REAL');
    
    // 15. إضافة أعمدة الموردين المفقودة
    await DatabaseHelpers.addColumnIfNotExists(db, 'suppliers', 'current_balance', 'REAL DEFAULT 0.0');
    await DatabaseHelpers.addColumnIfNotExists(db, 'suppliers', 'total_purchases', 'REAL DEFAULT 0.0');
    await DatabaseHelpers.addColumnIfNotExists(db, 'suppliers', 'last_modified_at', 'TEXT');

    // 16. إضافة عمود created_by لجدول لقطات الفواتير
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoice_snapshots', 'created_by', 'TEXT');
    
    // 17. إضافة عمود invoice_notes لفصل ملاحظات الفاتورة عن ملاحظات النظام/السجل
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoice_snapshots', 'invoice_notes', 'TEXT');

    // 18. إضافة عمود sync_uuid لجدول المعاملات (مفقود ويسبب خطأ)
    await DatabaseHelpers.addColumnIfNotExists(db, 'transactions', 'sync_uuid', 'TEXT');
    
    // 19. إضافة أعمدة التنبيهات للمنتجات (alert_quantity, alert_unit)
    await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'alert_quantity', 'REAL');
    await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'alert_unit', 'TEXT');
    
    // 20. إضافة عمود المخزون إذا لم يكن موجوداً
    await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'stock_quantity', 'REAL DEFAULT 0.0');

    // 21. إضافة عمود الملاحظات للفواتير (مفقود ويسبب خطأ)
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'notes', 'TEXT');

    // 22. إصلاحات المزامنة: إضافة أعمدة مفقودة تسبب أخطاء SQL
    await DatabaseHelpers.addColumnIfNotExists(db, 'transactions', 'is_deleted', 'INTEGER DEFAULT 0');
    await DatabaseHelpers.addColumnIfNotExists(db, 'customers', 'synced_at', 'TEXT');
    await DatabaseHelpers.addColumnIfNotExists(db, 'customers', 'is_created_by_me', 'INTEGER DEFAULT 1');
    await DatabaseHelpers.addColumnIfNotExists(db, 'customers', 'last_debt_added', 'TEXT');
    await DatabaseHelpers.addColumnIfNotExists(db, 'customers', 'last_modified_at', 'TEXT');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'is_created_by_me', 'INTEGER DEFAULT 1');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'is_deleted', 'INTEGER DEFAULT 0');

    // 22.أ. 🔒 الربط الذري بين المعاملة والفاتورة عبر UUID (مزامنة ذرية)
    // ضروري لنقل "حزمة الفاتورة" (فاتورة + معاملاتها) كوحدة واحدة غير قابلة للتجزئة،
    // بحيث يصل أثرها المالي للعميل على كل الأجهزة مع الفاتورة نفسها.
    await DatabaseHelpers.addColumnIfNotExists(db, 'transactions', 'invoice_sync_uuid', 'TEXT');
    // فهرس لتسرييع البحث عن معاملات الفاتورة أثناء الاستقبال
    try {
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_transactions_invoice_sync_uuid
        ON transactions(invoice_sync_uuid) WHERE invoice_sync_uuid IS NOT NULL
      ''');
    } catch (_) {}

    // 23. إضافة رقم الفاتورة التجاري المركّب (Surrogate Key + Natural Key pattern)
    //     يبقى id تسلسلياً تقنياً، invoice_number هو الرقم المرئي للمستخدم
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'invoice_number', 'TEXT');
    // فهرس للبحث السريع برقم الفاتورة
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_number ON invoices(invoice_number)');
    } catch (_) {}

    // 24. أعمدة مساعدة (السنة/الشهر) لقيد التفرّد المركّب وسرعة الاستعلام
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'invoice_year', 'INTEGER');
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'invoice_month', 'INTEGER');

    // تعبئة invoice_year/invoice_month للفواتير القديمة منها بدون قيم
    try {
      await db.execute('''
        UPDATE invoices
        SET invoice_year = CAST(strftime('%Y', invoice_date) AS INTEGER),
            invoice_month = CAST(strftime('%m', invoice_date) AS INTEGER)
        WHERE invoice_year IS NULL OR invoice_month IS NULL
      ''');
    } catch (_) {}

    // 25. قيد فريد مركّب: لا تكرار لنفس (الجهاز + السنة + الشهر + التسلسل الشهري)
    //     رقم الجهاز مختلف بين الأجهزة → لا تعارض ممكن بين الأجهزة المتزامنة.
    try {
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_unique_composite
        ON invoices(creator_device_id, invoice_year, invoice_month, monthly_sequence_number)
      ''');
    } catch (_) {}

    // تشغيل هجرة أرقام الفواتير دائماً للتأكد من عدم وجود فواتير بدون أرقام
    await _migrateInvoiceNumbers(db);

    // ════════════════════════════════════════════════════════════════════════
    // 24. نظام مزامنة المنتجات + سجل تعديلات المنتجات (كتالوج موحد مركزياً)
    // ════════════════════════════════════════════════════════════════════════

    // 24.أ. أعمدة المزامنة لجدول products
    await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'sync_uuid', 'TEXT');
    await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'created_by_device_id', 'TEXT');
    await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'last_modified_by_device_id', 'TEXT');
    await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'last_synced_at', 'TEXT');
    await DatabaseHelpers.addColumnIfNotExists(db, 'products', 'is_deleted', 'INTEGER DEFAULT 0');

    // فهرس فريد على sync_uuid (جزئي - فقط للقيم غير الفارغة)
    try {
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS ux_products_sync_uuid
        ON products(sync_uuid) WHERE sync_uuid IS NOT NULL
      ''');
    } catch (_) {}
    // فهرس لتسريع البحث عن المنتجات غير المُزامَنة
    try {
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_products_not_synced
        ON products(last_synced_at) WHERE last_synced_at IS NULL
      ''');
    } catch (_) {}

    // 24.ب. ربط ذري لأصناف الفاتورة بالمنتجات عبر sync_uuid (بدل product_id المحلي)
    await DatabaseHelpers.addColumnIfNotExists(db, 'invoice_items', 'product_sync_uuid', 'TEXT');
    try {
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_invoice_items_product_sync_uuid
        ON invoice_items(product_sync_uuid) WHERE product_sync_uuid IS NOT NULL
      ''');
    } catch (_) {}

    // 24.ج. جدول سجل تعديلات المنتجات (تتبع كامل: من، متى، ماذا تغير)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_edit_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        product_sync_uuid TEXT,
        field_changed TEXT NOT NULL,
        old_value TEXT,
        new_value TEXT,
        edit_type TEXT NOT NULL,
        device_id TEXT,
        user_id INTEGER,
        username TEXT,
        invoice_uuid TEXT,
        note TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');
    try {
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_product_edit_history_product
        ON product_edit_history(product_id)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_product_edit_history_device
        ON product_edit_history(device_id)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_product_edit_history_type
        ON product_edit_history(edit_type)
      ''');
    } catch (_) {}

    // 24.د. هجرة المنتجات الموجودة: توليد sync_uuid لكل منتج محلي بلا UUID
    await _migrateProductSyncUuids(db);

    // 25. التأكد من إعادة بناء جدول FTS والترايغرز بشكل سليم دائماً عند فتح قاعدة البيانات
    await _createFtsTable(db);
  }

  /// ترقية قاعدة البيانات
  static Future<void> upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    await createTables(db);
    // استدعاء ensureSchema للتأكد من إضافة الأعمدة الجديدة عند الترقية أيضاً
    await ensureSchema(db);
  }
  
  /// يقوم بتوليد أرقام فواتير (Natural Keys) للفواتير القديمة التي لا تملك رقماً.
  ///
  /// الاستراتيجية:
  /// 1. نُسقط القيد الفريد المركّب مؤقتاً (إن وُجد) لتفادي فشل التحديث أثناء الهجرة.
  /// 2. نُجمّع الفواتير التي تنقصها بيانات (invoice_number أو monthly_sequence_number أو invoice_year/month).
  /// 3. نُرقّم التسلسل الشهري من الصفر داخل كل مجموعة (creator_device_id + سنة + شهر)
  ///    مرتبة حسب تاريخ الفاتورة تصاعدياً (الأقدم أولاً).
  /// 4. نبني invoice_number = [جهاز][سنة][شهر][تسلسل].
  /// 5. نُعيد إنشاء القيد الفريد المركّب.
  static Future<void> _migrateInvoiceNumbers(Database db) async {
    // 1) إسقاط القيد الفريد مؤقتاً أثناء الهجرة (إن وُجد)
    try {
      await db.execute('DROP INDEX IF EXISTS idx_invoices_unique_composite');
    } catch (_) {}

    // 2) جلب الفواتير التي تنقصها أي من الحقول المركّبة، مرتبة زمنياً تصاعدياً
    final List<Map<String, dynamic>> invoices = await db.rawQuery('''
      SELECT id, invoice_date, creator_device_id,
             monthly_sequence_number, invoice_year, invoice_month
      FROM invoices
      WHERE invoice_number IS NULL OR invoice_number = ''
         OR monthly_sequence_number IS NULL
         OR invoice_year IS NULL OR invoice_month IS NULL
      ORDER BY creator_device_id ASC,
               CAST(strftime('%Y', invoice_date) AS INTEGER) ASC,
               CAST(strftime('%m', invoice_date) AS INTEGER) ASC,
               invoice_date ASC,
               id ASC
    ''');

    if (invoices.isEmpty) {
      // إعادة إنشاء القيد الفريد حتى لو لم تكن هناك هجرة
      try {
        await db.execute('''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_unique_composite
          ON invoices(creator_device_id, invoice_year, invoice_month, monthly_sequence_number)
        ''');
      } catch (_) {}
      return;
    }

    // 3) جلب رقم هذا الجهاز من SharedPreferences (افتراضياً 1)
    int deviceIdNum = 1;
    try {
      final prefs = await SharedPreferences.getInstance();
      deviceIdNum = prefs.getInt('invoice_device_id') ?? 1;
    } catch (_) {}

    // 4) تجميع الفواتير حسب (creator_device_id + سنة + شهر) وإعادة ترقيم التسلسل
    // المفتاح: "creatorDeviceId|year|month"
    final Map<String, int> seqCounters = {};
    final batch = db.batch();
    int migratedCount = 0;

    for (final row in invoices) {
      final int id = row['id'] as int;
      final String dateStr = row['invoice_date'] as String;
      final DateTime date = DateTime.tryParse(dateStr) ?? DateTime.now();

      // رقم الجهاز: نحترم creator_device_id الموجود، وإن لم يكن نستخدم رقم الجهاز الحالي
      String creatorDeviceIdStr = (row['creator_device_id'] as String?) ?? '';
      int effectiveDeviceId;
      if (creatorDeviceIdStr.isNotEmpty) {
        effectiveDeviceId = int.tryParse(creatorDeviceIdStr) ?? deviceIdNum;
      } else {
        effectiveDeviceId = deviceIdNum;
        creatorDeviceIdStr = deviceIdNum.toString();
      }

      final int year = date.year;
      final int month = date.month;
      final String groupKey = '$creatorDeviceIdStr|$year|$month';

      // زيادة التسلسل داخل المجموعة (يبدأ من 1)
      seqCounters[groupKey] = (seqCounters[groupKey] ?? 0) + 1;
      final int seq = seqCounters[groupKey]!;

      // بناء الرقم التجاري: [جهاز][سنة][شهر][تسلسل]
      final invoiceNumberStr = '$effectiveDeviceId$year$month$seq';

      batch.update(
        'invoices',
        {
          'invoice_number': invoiceNumberStr,
          'monthly_sequence_number': seq,
          'invoice_year': year,
          'invoice_month': month,
          'creator_device_id': creatorDeviceIdStr,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      migratedCount++;
    }

    await batch.commit(noResult: true);
    print('✅ تمت هجرة $migratedCount فاتورة وتم توليد أرقام تجارية متسلسلة لها.');

    // 5) إعادة إنشاء القيد الفريد المركّب
    try {
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_unique_composite
        ON invoices(creator_device_id, invoice_year, invoice_month, monthly_sequence_number)
      ''');
    } catch (e) {
      print('⚠️ تعذّر إنشاء القيد الفريد المركّب (يوجد تكرار في البيانات): $e');
    }
  }

  /// يولّد sync_uuid لكل منتج محلي بلا UUID، ويعيّن created_by_device_id.
  /// هذا ضروري لتمكين مزامنة المنتجات (كتالوج موحد) بين الأجهزة.
  static Future<void> _migrateProductSyncUuids(Database db) async {
    // جلب رقم هذا الجهاز للمزامنة (نستخدمه كـ created_by_device_id للمنتجات المحلية)
    String deviceId = 'local';
    try {
      final prefs = await SharedPreferences.getInstance();
      final firebaseDeviceId = prefs.getString('firebase_sync_device_id');
      if (firebaseDeviceId != null && firebaseDeviceId.isNotEmpty) {
        deviceId = firebaseDeviceId;
      } else {
        // نسقط لرقم الفاتورة المحلي كاحتياط
        final invoiceDeviceId = prefs.getInt('invoice_device_id') ?? 1;
        deviceId = invoiceDeviceId.toString();
      }
    } catch (_) {}

    // جلب المنتجات بلا sync_uuid
    final List<Map<String, dynamic>> products = await db.rawQuery(
        "SELECT id FROM products WHERE sync_uuid IS NULL OR sync_uuid = '' ORDER BY id ASC");

    if (products.isEmpty) return;

    final batch = db.batch();
    final now = DateTime.now().toUtc().toIso8601String();
    int migrated = 0;

    for (final row in products) {
      final int id = row['id'] as int;
      // توليد UUID حتمي (مبني على id المحلي) لضمان ثباته عبر إعادة التشغيل
      // الصيغة: prod_local_<id> — هذا يضمن عدم تكرار التوليد في كل مرة
      final String syncUuid = 'prod_local_$id';
      batch.update(
        'products',
        {
          'sync_uuid': syncUuid,
          'created_by_device_id': deviceId,
          'last_modified_by_device_id': deviceId,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      migrated++;
    }

    await batch.commit(noResult: true);
    print('✅ تمت هجرة $migrated منتج وتم توليد sync_uuid لها (device=$deviceId).');
  }
}
