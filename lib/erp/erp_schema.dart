// lib/erp/erp_schema.dart
//
// 🧱 مخطط ميزات «الإداري» و«سهل» في النسخة المحاسبية.
//
// القواعد التي لا نكسرها أبداً (الأمان الحسابي):
//   1. رصيد العميل يتغيّر فقط عبر مسار المعاملات الأصلي (AppProvider.addTransaction
//      ← TransactionDao) الذي يحسب الرصيد من مجموع المعاملات ويقفل العميل ويزامن.
//      الجداول هنا «تصف» تلك المعاملات (نوعها، صندوقها، عملتها...) ولا تغيّر الرصيد.
//   2. رصيد المورد يتغيّر فقط عبر PurchaseService/SupplierDebtReconciler.
//   3. المخزون يتغيّر فقط عبر StockLedger.addMovement (حركة لها معرّف وتزامن).
//   4. كل قيد يُكتب عبر Ledger.writeEntry الذي يرفض أي قيد غير متوازن.
//   5. كل التعريفات IF NOT EXISTS وكل عمود يُضاف بعد فحص وجوده: التشغيل المتكرر آمن،
//      ولا يُحذف أو يُعدَّل أي جدول قديم.

import 'package:sqflite/sqflite.dart';

class ErpSchema {
  ErpSchema._();

  static const List<String> createStatements = [
    // ═══════════════════════════ العملاء ═══════════════════════════
    '''
    CREATE TABLE IF NOT EXISTS customer_groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      notes TEXT,
      created_at TEXT NOT NULL
    )''',
    // حقول بطاقة العميل الإضافية (علاقة 1:1 مع customers)
    '''
    CREATE TABLE IF NOT EXISTS customer_ext (
      customer_id INTEGER PRIMARY KEY,
      code TEXT,
      title TEXT,
      group_id INTEGER,
      region TEXT,
      credit_limit REAL,
      discount_percent REAL,
      price_level TEXT,
      collection_day TEXT,
      responsible TEXT,
      id_number TEXT,
      id_image_path TEXT,
      photo_path TEXT,
      notes2 TEXT,
      is_blocked INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT
    )''',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_ext_code ON customer_ext(code) WHERE code IS NOT NULL AND code != \'\'',
    // وصف معاملة دين (نوعها المحاسبي، صندوقها، عملتها، رقم المستند) — مفتاحها
    // transaction_uuid الذي يولّده مسار المعاملات الأصلي نفسه.
    // kind: cash | discount | cheque | cheque_bounce | sales_return | reconcile | installment
    '''
    CREATE TABLE IF NOT EXISTS customer_tx_ext (
      transaction_uuid TEXT PRIMARY KEY,
      kind TEXT NOT NULL DEFAULT 'cash',
      cash_box_id INTEGER,
      currency TEXT NOT NULL DEFAULT 'IQD',
      fc_amount REAL,
      fx_rate REAL,
      doc_no TEXT,
      receipt_id INTEGER,
      ref_type TEXT,
      ref_id INTEGER,
      note TEXT,
      created_at TEXT NOT NULL
    )''',
    // وصل قبض (مفرد أو مركّب)
    '''
    CREATE TABLE IF NOT EXISTS customer_receipts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      receipt_no INTEGER NOT NULL,
      receipt_date TEXT NOT NULL,
      cash_box_id INTEGER,
      currency TEXT NOT NULL DEFAULT 'IQD',
      fx_rate REAL NOT NULL DEFAULT 1,
      total_amount REAL NOT NULL DEFAULT 0,
      total_discount REAL NOT NULL DEFAULT 0,
      commission REAL NOT NULL DEFAULT 0,
      commission_voucher_id INTEGER,
      doc_no TEXT,
      notes TEXT,
      is_compound INTEGER NOT NULL DEFAULT 0,
      created_by TEXT,
      created_at TEXT NOT NULL
    )''',
    '''
    CREATE TABLE IF NOT EXISTS customer_receipt_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      receipt_id INTEGER NOT NULL,
      customer_id INTEGER NOT NULL,
      amount REAL NOT NULL DEFAULT 0,
      discount REAL NOT NULL DEFAULT 0,
      fc_amount REAL,
      pay_tx_uuid TEXT,
      disc_tx_uuid TEXT,
      balance_before REAL,
      balance_after REAL,
      note TEXT,
      FOREIGN KEY (receipt_id) REFERENCES customer_receipts (id) ON DELETE CASCADE
    )''',
    'CREATE INDEX IF NOT EXISTS idx_crl_receipt ON customer_receipt_lines(receipt_id)',
    // مطابقة رصيد مع العميل
    '''
    CREATE TABLE IF NOT EXISTS customer_reconciliations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL,
      recon_date TEXT NOT NULL,
      our_balance REAL NOT NULL,
      agreed_balance REAL NOT NULL,
      diff REAL NOT NULL DEFAULT 0,
      adjust_tx_uuid TEXT,
      notes TEXT,
      created_by TEXT,
      created_at TEXT NOT NULL
    )''',
    'CREATE INDEX IF NOT EXISTS idx_recon_customer ON customer_reconciliations(customer_id, recon_date)',
    // ربط عميل بمورد (نفس الشخص) لعرض الرصيد الصافي — عرض فقط
    '''
    CREATE TABLE IF NOT EXISTS party_links (
      customer_id INTEGER PRIMARY KEY,
      supplier_id INTEGER NOT NULL,
      created_at TEXT NOT NULL
    )''',
    // دفعات الموردين: الصندوق الذي خرجت منه الدفعة
    '''
    CREATE TABLE IF NOT EXISTS supplier_payment_ext (
      payment_id INTEGER PRIMARY KEY,
      cash_box_id INTEGER,
      fx_rate REAL,
      doc_no TEXT,
      created_at TEXT NOT NULL
    )''',

    // ═══════════════════════════ الاستحقاقات ═══════════════════════════
    // kind: receivable_note | payable_note | cheque_in | cheque_out | installment
    // status: open | partial | closed | bounced | cancelled
    '''
    CREATE TABLE IF NOT EXISTS due_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      due_no INTEGER NOT NULL,
      kind TEXT NOT NULL,
      party_type TEXT NOT NULL,
      party_id INTEGER NOT NULL,
      party_name TEXT,
      amount REAL NOT NULL,
      currency TEXT NOT NULL DEFAULT 'IQD',
      fx_rate REAL NOT NULL DEFAULT 1,
      issue_date TEXT NOT NULL,
      due_date TEXT NOT NULL,
      doc_no TEXT,
      bank_name TEXT,
      guarantor TEXT,
      statement TEXT,
      installment_no INTEGER,
      installments_total INTEGER,
      plan_ref TEXT,
      status TEXT NOT NULL DEFAULT 'open',
      paid_amount REAL NOT NULL DEFAULT 0,
      affects_balance INTEGER NOT NULL DEFAULT 0,
      balance_ref TEXT,
      created_by TEXT,
      created_at TEXT NOT NULL,
      closed_at TEXT
    )''',
    'CREATE INDEX IF NOT EXISTS idx_due_items_due ON due_items(status, due_date)',
    'CREATE INDEX IF NOT EXISTS idx_due_items_party ON due_items(party_type, party_id)',
    '''
    CREATE TABLE IF NOT EXISTS due_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      due_id INTEGER NOT NULL,
      event_type TEXT NOT NULL,
      event_date TEXT NOT NULL,
      amount REAL NOT NULL DEFAULT 0,
      cash_box_id INTEGER,
      voucher_id INTEGER,
      balance_ref TEXT,
      note TEXT,
      created_by TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (due_id) REFERENCES due_items (id) ON DELETE CASCADE
    )''',

    // ═══════════════════════════ المبيعات ═══════════════════════════
    '''
    CREATE TABLE IF NOT EXISTS sellers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      commission_percent REAL NOT NULL DEFAULT 0,
      phone TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )''',
    '''
    CREATE TABLE IF NOT EXISTS invoice_extras (
      invoice_id INTEGER PRIMARY KEY,
      seller_id INTEGER,
      seller_name TEXT,
      commission_percent REAL,
      commission_amount REAL,
      delivery_method TEXT,
      shipping_company TEXT,
      shipping_no TEXT,
      order_ref TEXT,
      quote_ref TEXT,
      notes2 TEXT,
      updated_at TEXT
    )''',
    '''
    CREATE TABLE IF NOT EXISTS quotations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      quote_no INTEGER NOT NULL,
      quote_date TEXT NOT NULL,
      valid_until TEXT,
      customer_id INTEGER,
      customer_name TEXT NOT NULL,
      customer_phone TEXT,
      customer_address TEXT,
      price_level TEXT,
      discount REAL NOT NULL DEFAULT 0,
      total REAL NOT NULL DEFAULT 0,
      notes TEXT,
      terms TEXT,
      status TEXT NOT NULL DEFAULT 'open',
      created_by TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT
    )''',
    '''
    CREATE TABLE IF NOT EXISTS quotation_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      quotation_id INTEGER NOT NULL,
      product_id INTEGER,
      product_name TEXT NOT NULL,
      unit TEXT,
      sale_type TEXT,
      units_in_large REAL,
      quantity REAL NOT NULL,
      price REAL NOT NULL,
      discount_percent REAL NOT NULL DEFAULT 0,
      total REAL NOT NULL,
      FOREIGN KEY (quotation_id) REFERENCES quotations (id) ON DELETE CASCADE
    )''',
    // الطلبات: order_type = sales | purchase
    '''
    CREATE TABLE IF NOT EXISTS orders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_type TEXT NOT NULL,
      order_no INTEGER NOT NULL,
      order_date TEXT NOT NULL,
      delivery_date TEXT,
      party_type TEXT NOT NULL,
      party_id INTEGER,
      party_name TEXT NOT NULL,
      priority INTEGER NOT NULL DEFAULT 2,
      price_level TEXT,
      discount_percent REAL NOT NULL DEFAULT 0,
      currency TEXT NOT NULL DEFAULT 'IQD',
      fx_rate REAL NOT NULL DEFAULT 1,
      shipping_company TEXT,
      delivery_method TEXT,
      payment_method TEXT,
      seller_name TEXT,
      warehouse_id INTEGER,
      reserve INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'open',
      notes TEXT,
      created_by TEXT,
      created_at TEXT NOT NULL,
      closed_at TEXT
    )''',
    '''
    CREATE TABLE IF NOT EXISTS order_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL,
      product_id INTEGER,
      product_name TEXT NOT NULL,
      unit TEXT,
      sale_type TEXT,
      units_in_large REAL NOT NULL DEFAULT 1,
      quantity REAL NOT NULL,
      base_qty REAL NOT NULL,
      delivered_base_qty REAL NOT NULL DEFAULT 0,
      price REAL NOT NULL DEFAULT 0,
      discount_percent REAL NOT NULL DEFAULT 0,
      reserve INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
      FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE
    )''',
    '''
    CREATE TABLE IF NOT EXISTS order_delivery_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL,
      order_item_id INTEGER NOT NULL,
      base_qty REAL NOT NULL,
      ref TEXT,
      created_by TEXT,
      created_at TEXT NOT NULL
    )''',
    // مرتجع مبيعات مستقل برقم
    // refund_mode: cash (نقداً من صندوق) | credit (يُنزَّل من دين العميل)
    '''
    CREATE TABLE IF NOT EXISTS sales_returns (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      return_no INTEGER NOT NULL,
      return_date TEXT NOT NULL,
      customer_id INTEGER,
      customer_name TEXT NOT NULL,
      original_invoice_id INTEGER,
      refund_mode TEXT NOT NULL,
      cash_box_id INTEGER,
      warehouse_id INTEGER,
      total REAL NOT NULL,
      cost_total REAL NOT NULL DEFAULT 0,
      tx_uuid TEXT,
      notes TEXT,
      status TEXT NOT NULL DEFAULT 'posted',
      created_by TEXT,
      created_at TEXT NOT NULL
    )''',
    '''
    CREATE TABLE IF NOT EXISTS sales_return_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      return_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      sale_type TEXT,
      units_in_large REAL NOT NULL DEFAULT 1,
      quantity REAL NOT NULL,
      base_qty REAL NOT NULL,
      price REAL NOT NULL,
      total REAL NOT NULL,
      unit_cost REAL NOT NULL DEFAULT 0,
      movement_uuid TEXT,
      FOREIGN KEY (return_id) REFERENCES sales_returns (id) ON DELETE CASCADE
    )''',

    // ═══════════════════════════ مرتجع المشتريات ═══════════════════════════
    // refund_mode: debt (يُنزل من دين المورد) | cash (يردّ المورد نقداً) | mixed
    '''
    CREATE TABLE IF NOT EXISTS purchase_returns (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      return_no INTEGER NOT NULL,
      return_date TEXT NOT NULL,
      supplier_id INTEGER NOT NULL,
      supplier_name TEXT,
      original_invoice_id INTEGER,
      currency TEXT NOT NULL DEFAULT 'IQD',
      fx_rate REAL NOT NULL DEFAULT 1,
      refund_mode TEXT NOT NULL,
      cash_amount REAL NOT NULL DEFAULT 0,
      cash_box_id INTEGER,
      warehouse_id INTEGER,
      total REAL NOT NULL,
      cost_total REAL NOT NULL DEFAULT 0,
      tx_uuid TEXT,
      notes TEXT,
      status TEXT NOT NULL DEFAULT 'posted',
      created_by TEXT,
      created_at TEXT NOT NULL
    )''',
    '''
    CREATE TABLE IF NOT EXISTS purchase_return_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      return_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      unit_name TEXT,
      factor REAL NOT NULL DEFAULT 1,
      quantity REAL NOT NULL,
      base_qty REAL NOT NULL,
      price REAL NOT NULL,
      total REAL NOT NULL,
      unit_cost REAL NOT NULL DEFAULT 0,
      movement_uuid TEXT,
      FOREIGN KEY (return_id) REFERENCES purchase_returns (id) ON DELETE CASCADE
    )''',

    // ═══════════════════════════ المخزون ═══════════════════════════
    // doc_type: in | out | opening | production | count
    '''
    CREATE TABLE IF NOT EXISTS stock_docs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      doc_type TEXT NOT NULL,
      doc_no INTEGER NOT NULL,
      doc_date TEXT NOT NULL,
      warehouse_id INTEGER,
      counter_account_id INTEGER,
      reason TEXT,
      notes TEXT,
      total_cost REAL NOT NULL DEFAULT 0,
      model_id INTEGER,
      produced_qty REAL,
      overhead_amount REAL NOT NULL DEFAULT 0,
      overhead_account_id INTEGER,
      status TEXT NOT NULL DEFAULT 'posted',
      created_by TEXT,
      created_at TEXT NOT NULL
    )''',
    '''
    CREATE TABLE IF NOT EXISTS stock_doc_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      doc_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      product_name TEXT,
      base_qty REAL NOT NULL,
      unit_cost REAL NOT NULL DEFAULT 0,
      total_cost REAL NOT NULL DEFAULT 0,
      movement_uuid TEXT,
      warehouse_id INTEGER,
      note TEXT,
      FOREIGN KEY (doc_id) REFERENCES stock_docs (id) ON DELETE CASCADE
    )''',
    'CREATE INDEX IF NOT EXISTS idx_sdi_doc ON stock_doc_items(doc_id)',
    '''
    CREATE TABLE IF NOT EXISTS stock_counts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      count_no INTEGER NOT NULL,
      count_date TEXT NOT NULL,
      warehouse_id INTEGER,
      scope TEXT,
      status TEXT NOT NULL DEFAULT 'draft',
      notes TEXT,
      stock_doc_id INTEGER,
      created_by TEXT,
      created_at TEXT NOT NULL,
      approved_at TEXT
    )''',
    '''
    CREATE TABLE IF NOT EXISTS stock_count_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      count_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      product_name TEXT,
      system_qty REAL NOT NULL DEFAULT 0,
      counted_qty REAL,
      unit_cost REAL NOT NULL DEFAULT 0,
      FOREIGN KEY (count_id) REFERENCES stock_counts (id) ON DELETE CASCADE,
      UNIQUE (count_id, product_id)
    )''',
    '''
    CREATE TABLE IF NOT EXISTS item_serials (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      serial TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL DEFAULT 'in_stock',
      ref TEXT,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT
    )''',
    '''
    CREATE TABLE IF NOT EXISTS price_change_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      batch_no INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      field TEXT NOT NULL,
      old_value REAL,
      new_value REAL,
      created_by TEXT,
      created_at TEXT NOT NULL
    )''',
    // نماذج التصنيع
    '''
    CREATE TABLE IF NOT EXISTS bom_models (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      model_no INTEGER NOT NULL,
      name TEXT NOT NULL,
      product_id INTEGER NOT NULL,
      output_qty REAL NOT NULL DEFAULT 1,
      raw_warehouse_id INTEGER,
      finished_warehouse_id INTEGER,
      notes TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )''',
    '''
    CREATE TABLE IF NOT EXISTS bom_components (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      model_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      qty REAL NOT NULL,
      is_essential INTEGER NOT NULL DEFAULT 1,
      FOREIGN KEY (model_id) REFERENCES bom_models (id) ON DELETE CASCADE
    )''',
    '''
    CREATE TABLE IF NOT EXISTS bom_expenses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      model_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      amount REAL NOT NULL,
      FOREIGN KEY (model_id) REFERENCES bom_models (id) ON DELETE CASCADE
    )''',

    // ═══════════════════════════ المحاسبة ═══════════════════════════
    '''
    CREATE TABLE IF NOT EXISTS currencies (
      code TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      symbol TEXT,
      fraction_name TEXT,
      decimals INTEGER NOT NULL DEFAULT 0,
      rate REAL NOT NULL DEFAULT 1,
      is_base INTEGER NOT NULL DEFAULT 0,
      divide INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1
    )''',
    '''
    CREATE TABLE IF NOT EXISTS currency_rates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT NOT NULL,
      rate REAL NOT NULL,
      rate_date TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''',
    'CREATE INDEX IF NOT EXISTS idx_currency_rates ON currency_rates(code, rate_date)',
    '''
    CREATE TABLE IF NOT EXISTS voucher_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      voucher_id INTEGER NOT NULL,
      account_id INTEGER NOT NULL,
      debit REAL NOT NULL DEFAULT 0,
      credit REAL NOT NULL DEFAULT 0,
      currency TEXT NOT NULL DEFAULT 'IQD',
      fc_amount REAL,
      fx_rate REAL,
      memo TEXT
    )''',
    'CREATE INDEX IF NOT EXISTS idx_voucher_lines ON voucher_lines(voucher_id)',
    '''
    CREATE TABLE IF NOT EXISTS voucher_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      abbrev TEXT,
      voucher_type TEXT NOT NULL,
      cash_box_id INTEGER,
      account_id INTEGER,
      notes TEXT,
      created_at TEXT NOT NULL
    )''',
    '''
    CREATE TABLE IF NOT EXISTS account_groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      notes TEXT,
      created_at TEXT NOT NULL
    )''',
    '''
    CREATE TABLE IF NOT EXISTS account_group_members (
      group_id INTEGER NOT NULL,
      account_id INTEGER NOT NULL,
      PRIMARY KEY (group_id, account_id)
    )''',
    '''
    CREATE TABLE IF NOT EXISTS fiscal_closings (
      year INTEGER PRIMARY KEY,
      close_date TEXT NOT NULL,
      net_profit REAL NOT NULL,
      created_by TEXT,
      created_at TEXT NOT NULL
    )''',
    '''
    CREATE TABLE IF NOT EXISTS erp_notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      body TEXT,
      updated_at TEXT NOT NULL
    )''',
  ];

  /// أعمدة تُضاف لجداول موجودة: [جدول، عمود، تعريف].
  static const List<List<String>> addedColumns = [
    ['cash_boxes', 'currency', "TEXT NOT NULL DEFAULT 'IQD'"],
    ['sales_returns', 'cash_amount', 'REAL'],
    ['stock_docs', 'gain_account_id', 'INTEGER'],
    ['stock_docs', 'loss_account_id', 'INTEGER'],
    ['vouchers', 'currency', "TEXT NOT NULL DEFAULT 'IQD'"],
    ['vouchers', 'fc_amount', 'REAL'],
    ['vouchers', 'fx_rate', 'REAL'],
    ['vouchers', 'template_id', 'INTEGER'],
    ['vouchers', 'doc_no', 'TEXT'],
    ['product_details', 'item_type', "TEXT NOT NULL DEFAULT 'trade'"],
    ['product_details', 'registration_no', 'TEXT'],
    ['product_details', 'classification_no', 'TEXT'],
    ['product_details', 'customs_no', 'TEXT'],
    ['product_details', 'group2', 'TEXT'],
    ['product_details', 'group3', 'TEXT'],
    ['product_details', 'bonus_buy', 'REAL'],
    ['product_details', 'bonus_free', 'REAL'],
    ['product_details', 'pricing_mode', "TEXT NOT NULL DEFAULT 'fixed'"],
    ['product_details', 'markup1', 'REAL'],
    ['product_details', 'markup2', 'REAL'],
    ['product_details', 'markup3', 'REAL'],
    ['product_details', 'markup4', 'REAL'],
    ['product_details', 'markup5', 'REAL'],
    ['product_details', 'markup6', 'REAL'],
    ['product_details', 'price_rounding', 'REAL'],
    ['product_details', 'fixed_cost', 'REAL'],
    ['product_details', 'opening_cost', 'REAL'],
    ['product_details', 'default_unit', 'TEXT'],
    ['product_details', 'min_role', 'TEXT'],
  ];

  /// حسابات يحتاجها النظام الجديد: [المفتاح، الاسم، رمز مفضّل، رمز الأب، النوع، مراقبة؟]
  static const List<List<Object?>> systemAccounts = [
    ['cheques_receivable', 'أوراق وشيكات القبض', '1203', '12', 'asset', 0],
    ['cheques_payable', 'أوراق وشيكات الدفع', '2103', '21', 'liability', 0],
    ['commissions_payable', 'عمولات مستحقة للبائعين', '2203', '22', 'liability', 0],
    ['discount_received', 'خصم مكتسب من الموردين', '44', '4', 'revenue', 0],
    ['sales_returns', 'مردودات المبيعات', '45', '4', 'revenue', 0],
    ['discount_allowed', 'خصم مسموح به للعملاء', '54', '5', 'expense', 0],
    ['sales_commission', 'عمولات البيع', '55', '5', 'expense', 0],
    ['collection_commission', 'عمولات التحصيل', '56', '5', 'expense', 0],
    ['inventory_writeoff', 'تالف وهدايا ومسحوبات بضاعة', '57', '5', 'expense', 0],
    ['customer_settlement', 'فروقات مطابقة أرصدة العملاء', '58', '5', 'expense', 0],
    ['manufacturing_absorbed', 'مصاريف صناعية محمّلة على الإنتاج', '59', '5', 'expense', 0],
  ];

  static Future<void> ensure(DatabaseExecutor db) async {
    for (final sql in createStatements) {
      await db.execute(sql);
    }
    for (final c in addedColumns) {
      await _addColumnIfMissing(db, c[0], c[1], c[2]);
    }
    await _seedAccounts(db);
    await _seedCurrencies(db);
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

  /// يضيف الحسابات النظامية الناقصة فقط. إن كان الرمز المفضّل مستعملاً لحساب
  /// آخر، يُختار أول رمز فارغ تحت الأب نفسه.
  static Future<void> _seedAccounts(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'accounts')) return;
    final now = DateTime.now().toIso8601String();
    for (final a in systemAccounts) {
      final key = a[0] as String;
      final has = await db.query('accounts',
          columns: ['id'], where: 'system_key = ?', whereArgs: [key], limit: 1);
      if (has.isNotEmpty) continue;
      final parentCode = a[3] as String;
      final parent = await db.query('accounts',
          columns: ['id', 'code', 'type'], where: 'code = ?', whereArgs: [parentCode], limit: 1);
      if (parent.isEmpty) continue;
      final parentId = parent.first['id'] as int;
      var code = a[2] as String;
      final taken = await db.query('accounts',
          columns: ['id'], where: 'code = ?', whereArgs: [code], limit: 1);
      if (taken.isNotEmpty) {
        final kids = await db.query('accounts',
            columns: ['code'], where: 'parent_id = ?', whereArgs: [parentId]);
        var max = 0;
        for (final k in kids) {
          final c = k['code'] as String;
          if (!c.startsWith(parentCode)) continue;
          final tail = int.tryParse(c.substring(parentCode.length));
          if (tail != null && tail > max) max = tail;
        }
        // نجرّب رموزاً متتالية حتى نجد رمزاً غير مستعمل
        var n = max + 1;
        while (true) {
          final candidate = '$parentCode${n.toString().padLeft(2, '0')}';
          final t = await db.query('accounts',
              columns: ['id'], where: 'code = ?', whereArgs: [candidate], limit: 1);
          if (t.isEmpty) {
            code = candidate;
            break;
          }
          n++;
        }
      }
      await db.insert('accounts', {
        'code': code,
        'name': a[1],
        'parent_id': parentId,
        'type': a[4],
        'is_group': 0,
        'is_control': a[5],
        'system_key': key,
        'currency': 'IQD',
        'created_at': now,
      });
    }
  }

  static Future<void> _seedCurrencies(DatabaseExecutor db) async {
    final n = await db.rawQuery('SELECT COUNT(*) AS n FROM currencies');
    if (((n.first['n'] as num?) ?? 0) > 0) return;
    // سعر الدولار الابتدائي = سعر إعدادات المحاسبة الحالي (إن وُجد)
    double usd = 1310;
    try {
      final r = await db.query('accounting_settings',
          columns: ['value'], where: 'key = ?', whereArgs: ['usd_rate'], limit: 1);
      if (r.isNotEmpty) {
        final v = double.tryParse((r.first['value'] as String?) ?? '');
        if (v != null && v > 0) usd = v;
      }
    } catch (_) {}
    await db.insert('currencies', {
      'code': 'IQD',
      'name': 'دينار عراقي',
      'symbol': 'د.ع',
      'fraction_name': 'فلس',
      'decimals': 0,
      'rate': 1,
      'is_base': 1,
      'divide': 0,
      'is_active': 1,
    });
    await db.insert('currencies', {
      'code': 'USD',
      'name': 'دولار أمريكي',
      'symbol': r'$',
      'fraction_name': 'سنت',
      'decimals': 2,
      'rate': usd,
      'is_base': 0,
      'divide': 0,
      'is_active': 1,
    });
    await db.insert('currency_rates', {
      'code': 'USD',
      'rate': usd,
      'rate_date': DateTime(2000, 1, 1).toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
