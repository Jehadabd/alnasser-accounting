// lib/accounting/accounting_schema.dart
//
// 📒 مخطط النسخة المحاسبية: الفروع، المخازن، شجرة الحسابات، القيود،
// الصناديق، السندات، وإعدادات المحاسبة.
//
// المبدأ: القيود تُشتق من المستندات (الفواتير، حركات العملاء والموردين،
// السندات) بمحرك الترحيل — لا نعدّل أي مسار حفظ قديم. كل قيد مربوط بمصدره
// (source_type, source_id) وببصمة (source_hash)؛ إذا تغيّر المصدر يُعاد
// توليد قيده، وإذا حُذف يُحذف قيده. لذلك لا يمكن أن يختلف الدفتر عن المستندات.
//
// كل التعريفات CREATE ... IF NOT EXISTS، فالاستدعاء المتكرر آمن.

import 'package:sqflite/sqflite.dart';

class AccountingSchema {
  AccountingSchema._();

  /// أوامر إنشاء الجداول — تُقرأ أيضاً من اختبار Python على نسخة القاعدة الحقيقية.
  static const List<String> createStatements = [
    // ── الفروع ──
    '''
    CREATE TABLE IF NOT EXISTS branches (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      address TEXT,
      phone TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      is_current INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )''',
    // ── المخازن ──
    '''
    CREATE TABLE IF NOT EXISTS warehouses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      branch_id INTEGER NOT NULL DEFAULT 1,
      code TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      keeper_user_id INTEGER,
      is_default INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      notes TEXT,
      created_at TEXT NOT NULL
    )''',
    // ── شجرة الحسابات ──
    // type: asset | liability | equity | revenue | expense
    // is_group: حساب رئيسي (لا تُرحّل عليه قيود مباشرة)
    // is_control: حساب مراقبة (ذمم العملاء/الموردين) — لا يُستعمل في القيود اليدوية
    //             لأن رصيده يجب أن يساوي مجموع أرصدة العملاء/الموردين دائماً.
    // system_key: مفتاح ثابت يعرفه محرك الترحيل (sales, cash_main, ...)
    '''
    CREATE TABLE IF NOT EXISTS accounts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      parent_id INTEGER,
      type TEXT NOT NULL,
      is_group INTEGER NOT NULL DEFAULT 0,
      is_control INTEGER NOT NULL DEFAULT 0,
      system_key TEXT UNIQUE,
      currency TEXT NOT NULL DEFAULT 'IQD',
      is_active INTEGER NOT NULL DEFAULT 1,
      notes TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (parent_id) REFERENCES accounts (id)
    )''',
    // ── القيود ──
    // source_type: invoice | customer_tx | purchase_invoice | supplier_tx |
    //              voucher | manual | inventory_valuation
    '''
    CREATE TABLE IF NOT EXISTS journal_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_number INTEGER NOT NULL,
      entry_date TEXT NOT NULL,
      description TEXT,
      source_type TEXT NOT NULL,
      source_id INTEGER,
      source_hash TEXT,
      branch_id INTEGER NOT NULL DEFAULT 1,
      created_by_user_id INTEGER,
      created_at TEXT NOT NULL,
      UNIQUE (source_type, source_id)
    )''',
    '''
    CREATE TABLE IF NOT EXISTS journal_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_id INTEGER NOT NULL,
      account_id INTEGER NOT NULL,
      debit REAL NOT NULL DEFAULT 0,
      credit REAL NOT NULL DEFAULT 0,
      party_type TEXT,
      party_id INTEGER,
      currency TEXT NOT NULL DEFAULT 'IQD',
      fc_amount REAL,
      exchange_rate REAL,
      memo TEXT,
      FOREIGN KEY (entry_id) REFERENCES journal_entries (id) ON DELETE CASCADE,
      FOREIGN KEY (account_id) REFERENCES accounts (id)
    )''',
    'CREATE INDEX IF NOT EXISTS idx_jl_entry ON journal_lines(entry_id)',
    'CREATE INDEX IF NOT EXISTS idx_jl_account ON journal_lines(account_id)',
    'CREATE INDEX IF NOT EXISTS idx_jl_party ON journal_lines(party_type, party_id)',
    'CREATE INDEX IF NOT EXISTS idx_je_date ON journal_entries(entry_date)',
    // ── الصناديق والبنوك ──
    '''
    CREATE TABLE IF NOT EXISTS cash_boxes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      account_id INTEGER NOT NULL UNIQUE,
      branch_id INTEGER NOT NULL DEFAULT 1,
      kind TEXT NOT NULL DEFAULT 'cash',
      is_default INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      FOREIGN KEY (account_id) REFERENCES accounts (id)
    )''',
    // ── السندات: مصروف، قبض آخر، صرف آخر، تحويل بين صناديق، رصيد افتتاحي ──
    '''
    CREATE TABLE IF NOT EXISTS vouchers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      voucher_number INTEGER NOT NULL,
      voucher_type TEXT NOT NULL,
      voucher_date TEXT NOT NULL,
      amount REAL NOT NULL,
      cash_box_id INTEGER,
      to_cash_box_id INTEGER,
      account_id INTEGER,
      description TEXT,
      reference TEXT,
      branch_id INTEGER NOT NULL DEFAULT 1,
      created_by_user_id INTEGER,
      created_at TEXT NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      deleted_at TEXT,
      deleted_by_user_id INTEGER
    )''',
    'CREATE INDEX IF NOT EXISTS idx_vouchers_date ON vouchers(voucher_date)',
    // ── إعدادات المحاسبة (مفتاح/قيمة) ──
    '''
    CREATE TABLE IF NOT EXISTS accounting_settings (
      key TEXT PRIMARY KEY,
      value TEXT
    )''',
    // ── تفاصيل بطاقة المادة (علاقة 1:1 مع products) ──
    '''
    CREATE TABLE IF NOT EXISTS product_details (
      product_id INTEGER PRIMARY KEY,
      item_code TEXT,
      second_name TEXT,
      brand TEXT,
      origin TEXT,
      default_supplier_id INTEGER,
      default_warehouse_id INTEGER,
      min_qty REAL,
      max_qty REAL,
      reorder_qty REAL,
      cost_method TEXT DEFAULT 'last',
      track_expiry INTEGER NOT NULL DEFAULT 0,
      track_serial INTEGER NOT NULL DEFAULT 0,
      is_scale_item INTEGER NOT NULL DEFAULT 0,
      scale_code TEXT,
      tax_percent REAL,
      max_discount_percent REAL,
      shelf_location TEXT,
      image_path TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      notes TEXT,
      updated_at TEXT,
      FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
    )''',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_product_details_code ON product_details(item_code) WHERE item_code IS NOT NULL AND item_code != \'\'',
    // ── تحويلات مخزنية بين المخازن ──
    '''
    CREATE TABLE IF NOT EXISTS stock_transfers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      transfer_number INTEGER NOT NULL,
      transfer_date TEXT NOT NULL,
      from_warehouse_id INTEGER NOT NULL,
      to_warehouse_id INTEGER NOT NULL,
      notes TEXT,
      created_by_user_id INTEGER,
      created_at TEXT NOT NULL
    )''',
    '''
    CREATE TABLE IF NOT EXISTS stock_transfer_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      transfer_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      quantity REAL NOT NULL,
      FOREIGN KEY (transfer_id) REFERENCES stock_transfers (id) ON DELETE CASCADE
    )''',
  ];

  /// أعمدة تُضاف لجداول موجودة (جدول، عمود، تعريف).
  static const List<List<String>> addedColumns = [
    ['users', 'full_name', 'TEXT'],
    ['users', 'branch_id', 'INTEGER'],
    ['users', 'is_active', 'INTEGER DEFAULT 1'],
    ['users', 'role_template', 'TEXT'],
    ['stock_movements', 'warehouse_id', 'INTEGER'],
    ['invoices', 'warehouse_id', 'INTEGER'],
    ['invoices', 'branch_id', 'INTEGER'],
    ['invoices', 'cash_box_id', 'INTEGER'],
  ];

  /// الشجرة الافتراضية: [الرمز، الاسم، رمز الأب، النوع، مجموعة؟، مراقبة؟، المفتاح]
  static const List<List<Object?>> defaultChart = [
    ['1', 'الأصول', null, 'asset', 1, 0, null],
    ['11', 'النقدية', '1', 'asset', 1, 0, 'cash_group'],
    ['1101', 'الصندوق الرئيسي', '11', 'asset', 0, 0, 'cash_main'],
    ['1102', 'البنك', '11', 'asset', 0, 0, 'bank_main'],
    ['12', 'الذمم المدينة', '1', 'asset', 1, 0, null],
    ['1201', 'ذمم العملاء', '12', 'asset', 0, 1, 'ar_customers'],
    ['1202', 'سلف الموظفين', '12', 'asset', 0, 0, 'employee_advances'],
    ['13', 'المخزون', '1', 'asset', 1, 0, null],
    ['1301', 'مخزون البضاعة', '13', 'asset', 0, 0, 'inventory'],
    ['14', 'الأصول الثابتة', '1', 'asset', 1, 0, null],
    ['1401', 'الأثاث والمعدات', '14', 'asset', 0, 0, null],
    ['2', 'الخصوم', null, 'liability', 1, 0, null],
    ['21', 'الذمم الدائنة', '2', 'liability', 1, 0, null],
    ['2101', 'ذمم الموردين - دينار', '21', 'liability', 0, 1, 'ap_iqd'],
    ['2102', 'ذمم الموردين - دولار', '21', 'liability', 0, 1, 'ap_usd'],
    ['22', 'مستحقات', '2', 'liability', 1, 0, null],
    ['2201', 'رواتب مستحقة', '22', 'liability', 0, 0, null],
    ['2202', 'نقاط الفنيين المستحقة', '22', 'liability', 0, 0, 'installer_points'],
    ['3', 'حقوق الملكية', null, 'equity', 1, 0, null],
    ['31', 'رأس المال', '3', 'equity', 0, 0, 'capital'],
    ['32', 'الأرصدة الافتتاحية', '3', 'equity', 0, 0, 'opening_equity'],
    ['33', 'الأرباح المحتجزة', '3', 'equity', 0, 0, 'retained_earnings'],
    ['34', 'مسحوبات المالك', '3', 'equity', 0, 0, 'owner_drawings'],
    ['4', 'الإيرادات', null, 'revenue', 1, 0, null],
    ['41', 'المبيعات', '4', 'revenue', 0, 0, 'sales'],
    ['42', 'ديون يدوية (مبيعات خارج القوائم)', '4', 'revenue', 0, 0, 'sales_manual'],
    ['43', 'إيرادات أخرى', '4', 'revenue', 0, 0, 'other_income'],
    ['5', 'التكاليف والمصاريف', null, 'expense', 1, 0, null],
    ['51', 'كلفة البضاعة المباعة', '5', 'expense', 0, 0, 'cogs'],
    ['52', 'المصاريف التشغيلية', '5', 'expense', 1, 0, 'expenses_group'],
    ['5201', 'الإيجار', '52', 'expense', 0, 0, null],
    ['5202', 'الرواتب والأجور', '52', 'expense', 0, 0, null],
    ['5203', 'الكهرباء والمولدة', '52', 'expense', 0, 0, null],
    ['5204', 'النقل والتحميل', '52', 'expense', 0, 0, null],
    ['5205', 'الصيانة', '52', 'expense', 0, 0, null],
    ['5206', 'الاتصالات والإنترنت', '52', 'expense', 0, 0, null],
    ['5299', 'مصاريف عامة', '52', 'expense', 0, 0, 'general_expense'],
    ['53', 'فروقات وتسويات', '5', 'expense', 1, 0, null],
    ['5301', 'فروقات تسوية الموردين', '53', 'expense', 0, 0, 'supplier_corrections'],
    ['5302', 'فروقات جرد المخزون', '53', 'expense', 0, 0, 'inventory_adjust'],
    ['5303', 'فروقات أسعار الصرف', '53', 'expense', 0, 0, 'fx_diff'],
  ];

  static Future<void> ensure(DatabaseExecutor db) async {
    for (final sql in createStatements) {
      await db.execute(sql);
    }
    for (final c in addedColumns) {
      await _addColumnIfMissing(db, c[0], c[1], c[2]);
    }
    await _seed(db);
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final r = await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [table]);
    return r.isNotEmpty;
  }

  static Future<void> _addColumnIfMissing(
      DatabaseExecutor db, String table, String column, String def) async {
    if (!await _tableExists(db, table)) return;
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (cols.any((c) => c['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $def');
  }

  static Future<void> _seed(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();

    final b = await db.rawQuery('SELECT COUNT(*) AS n FROM branches');
    if (((b.first['n'] as num?) ?? 0) == 0) {
      await db.insert('branches', {
        'id': 1,
        'code': 'B1',
        'name': 'الفرع الرئيسي',
        'is_active': 1,
        'is_current': 1,
        'created_at': now,
      });
    }

    final w = await db.rawQuery('SELECT COUNT(*) AS n FROM warehouses');
    if (((w.first['n'] as num?) ?? 0) == 0) {
      await db.insert('warehouses', {
        'id': 1,
        'branch_id': 1,
        'code': 'W1',
        'name': 'المخزن الرئيسي',
        'is_default': 1,
        'is_active': 1,
        'created_at': now,
      });
    }

    // الشجرة: نُدرج ما ينقص فقط (بالرمز) — لا نلمس ما عدّله المستخدم.
    final existing = await db.query('accounts', columns: ['id', 'code']);
    final idByCode = <String, int>{
      for (final r in existing) r['code'] as String: r['id'] as int,
    };
    for (final a in defaultChart) {
      final code = a[0] as String;
      if (idByCode.containsKey(code)) continue;
      final parentCode = a[2] as String?;
      final key = a[6] as String?;
      if (key != null) {
        // مفتاح نظام موجود برمز آخر (المستخدم غيّر الرمز) — لا نكرره.
        final k = await db.query('accounts',
            columns: ['id'], where: 'system_key = ?', whereArgs: [key], limit: 1);
        if (k.isNotEmpty) continue;
      }
      final id = await db.insert('accounts', {
        'code': code,
        'name': a[1],
        'parent_id': parentCode == null ? null : idByCode[parentCode],
        'type': a[3],
        'is_group': a[4],
        'is_control': a[5],
        'system_key': key,
        'currency': key == 'ap_usd' ? 'USD' : 'IQD',
        'created_at': now,
      });
      idByCode[code] = id;
    }

    // الصندوق الرئيسي مربوط بحسابه
    final cb = await db.rawQuery('SELECT COUNT(*) AS n FROM cash_boxes');
    if (((cb.first['n'] as num?) ?? 0) == 0) {
      final acc = await db.query('accounts',
          columns: ['id'], where: "system_key = 'cash_main'", limit: 1);
      if (acc.isNotEmpty) {
        await db.insert('cash_boxes', {
          'name': 'الصندوق الرئيسي',
          'account_id': acc.first['id'],
          'branch_id': 1,
          'kind': 'cash',
          'is_default': 1,
          'created_at': now,
        });
      }
      final bank = await db.query('accounts',
          columns: ['id'], where: "system_key = 'bank_main'", limit: 1);
      if (bank.isNotEmpty) {
        await db.insert('cash_boxes', {
          'name': 'البنك',
          'account_id': bank.first['id'],
          'branch_id': 1,
          'kind': 'bank',
          'is_default': 0,
          'created_at': now,
        });
      }
    }

    await db.execute(
        "INSERT OR IGNORE INTO accounting_settings(key, value) VALUES ('usd_rate', '1310')");
    await db.execute(
        "INSERT OR IGNORE INTO accounting_settings(key, value) VALUES ('auto_post', '1')");
  }
}
