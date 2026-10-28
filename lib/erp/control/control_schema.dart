// lib/erp/control/control_schema.dart
//
// 🛡️ جداول «الرقابة والأدوات المالية» — تُنشأ مع بقية جداول الإداري (ErpSchema.ensure)
// وعند أول استعمال لأي خدمة منها. كلها IF NOT EXISTS: التشغيل المتكرر آمن.
//
// ما يمسّ الدفتر من هذه الجداول (عبر ErpPosting فقط، وبحالة صريحة يضعها المستخدم):
//   • cash_counts      بحالة 'posted'  ⇒ قيد فرق الصندوق (عجز/زيادة).
//   • fixed_assets     بتمويل box/opening ⇒ قيد شراء الأصل؛ وبحالة 'disposed' ⇒ قيد الاستبعاد.
//   • depreciation_runs بحالة 'posted' ⇒ قيد إهلاك الشهر.
//   • landed_costs     بطريقة box/reclass ⇒ قيد مصاريف الشحن على المخزون.
// وما سواها سجلات متابعة فقط: invoice_prints، approval_log، bank_recs، bank_rec_marks.

import 'package:sqflite/sqflite.dart';

class ControlSchema {
  ControlSchema._();

  static const List<String> statements = [
    // 💵 عدّ الدرج: لقطة لما كان متوقعاً وما عُدّ فعلاً لحظة الحفظ (لا يتغير بعدها)
    '''
    CREATE TABLE IF NOT EXISTS cash_counts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      count_no INTEGER NOT NULL,
      count_day TEXT NOT NULL,
      counted_at TEXT NOT NULL,
      source TEXT,
      box_id INTEGER,
      opening REAL NOT NULL DEFAULT 0,
      expected REAL NOT NULL DEFAULT 0,
      counted REAL NOT NULL DEFAULT 0,
      diff REAL NOT NULL DEFAULT 0,
      counted_by TEXT,
      note TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      review_note TEXT,
      reviewed_by TEXT,
      reviewed_at TEXT,
      created_at TEXT NOT NULL
    )''',
    'CREATE INDEX IF NOT EXISTS idx_cash_counts_day ON cash_counts(count_day)',

    // 🖨️ كل طباعة لفاتورة محفوظة: متى ومن
    '''
    CREATE TABLE IF NOT EXISTS invoice_prints (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL,
      printed_at TEXT NOT NULL,
      printed_by TEXT,
      kind TEXT
    )''',
    'CREATE INDEX IF NOT EXISTS idx_invoice_prints_inv ON invoice_prints(invoice_id)',

    // ✅ سجل الموافقات: كل عملية احتاجت موافقة المدير، ومن وافق أو رفض
    '''
    CREATE TABLE IF NOT EXISTS approval_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      rule TEXT NOT NULL,
      ref_type TEXT,
      ref_id INTEGER,
      ref_label TEXT,
      details TEXT,
      requested_by TEXT,
      decided_by TEXT,
      decision TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''',
    'CREATE INDEX IF NOT EXISTS idx_approval_log_date ON approval_log(created_at)',

    // 🏢 الأصول الثابتة
    '''
    CREATE TABLE IF NOT EXISTS fixed_assets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      asset_no INTEGER NOT NULL,
      name TEXT NOT NULL,
      category TEXT,
      acquired_on TEXT NOT NULL,
      cost REAL NOT NULL,
      salvage REAL NOT NULL DEFAULT 0,
      life_months INTEGER NOT NULL,
      dep_start TEXT NOT NULL,
      asset_account_id INTEGER,
      funding TEXT NOT NULL DEFAULT 'already',
      funding_box_id INTEGER,
      status TEXT NOT NULL DEFAULT 'active',
      disposed_on TEXT,
      disposal_amount REAL,
      disposal_box_id INTEGER,
      notes TEXT,
      created_by TEXT,
      created_at TEXT NOT NULL
    )''',
    // 📉 تشغيل إهلاك شهر واحد (قيد واحد للشهر كله)
    '''
    CREATE TABLE IF NOT EXISTS depreciation_runs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      period TEXT NOT NULL,
      run_date TEXT NOT NULL,
      total REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'posted',
      created_by TEXT,
      created_at TEXT NOT NULL
    )''',
    '''
    CREATE TABLE IF NOT EXISTS depreciation_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      run_id INTEGER NOT NULL,
      asset_id INTEGER NOT NULL,
      amount REAL NOT NULL
    )''',
    'CREATE INDEX IF NOT EXISTS idx_dep_lines_run ON depreciation_lines(run_id)',
    'CREATE INDEX IF NOT EXISTS idx_dep_lines_asset ON depreciation_lines(asset_id)',

    // 🏦 مطابقة كشف البنك (لا تغيّر قيداً — تعلّم فقط)
    '''
    CREATE TABLE IF NOT EXISTS bank_recs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      box_id INTEGER NOT NULL,
      statement_date TEXT NOT NULL,
      statement_balance REAL NOT NULL,
      cleared_balance REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'draft',
      note TEXT,
      created_by TEXT,
      created_at TEXT NOT NULL,
      finalized_at TEXT
    )''',
    '''
    CREATE TABLE IF NOT EXISTS bank_rec_marks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      rec_id INTEGER NOT NULL,
      line_key TEXT NOT NULL,
      amount REAL NOT NULL,
      entry_date TEXT,
      UNIQUE(rec_id, line_key)
    )''',
    'CREATE INDEX IF NOT EXISTS idx_bank_rec_marks_key ON bank_rec_marks(line_key)',

    // 🚢 مصاريف الشحن والجمارك المحمّلة على كلفة مادة
    '''
    CREATE TABLE IF NOT EXISTS landed_costs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      product_name TEXT,
      cost_date TEXT NOT NULL,
      base_qty REAL NOT NULL,
      purchase_unit_cost REAL NOT NULL,
      extras TEXT NOT NULL,
      total_extra REAL NOT NULL,
      per_unit REAL NOT NULL,
      mode TEXT NOT NULL,
      box_id INTEGER,
      expense_account_id INTEGER,
      status TEXT NOT NULL DEFAULT 'posted',
      created_by TEXT,
      created_at TEXT NOT NULL
    )''',
  ];

  /// حسابات النظام التي تحتاجها هذه الميزات: [المفتاح، الاسم، رمز مفضّل، رمز الأب، النوع، مراقبة؟]
  /// (تُضاف عبر ErpSchema.systemAccounts بالآلية نفسها — لا تلمس حساباً موجوداً)
  static const List<List<Object?>> systemAccounts = [
    ['cash_over_short', 'فروقات الصندوق (عجز/زيادة)', '5304', '53', 'expense', 0],
    ['accum_depreciation', 'مجمع إهلاك الأصول الثابتة', '1499', '14', 'asset', 0],
    ['depreciation_expense', 'مصروف الإهلاك', '5207', '52', 'expense', 0],
    ['asset_disposal', 'أرباح وخسائر استبعاد الأصول', '5305', '53', 'expense', 0],
  ];

  static int _readyGen = -1;

  /// ينشئ الجداول إن لم توجد. [gen]: رقم فتح القاعدة (يُعاد الفحص عند فتح قاعدة أخرى).
  static Future<void> ensure(DatabaseExecutor db, {int? gen}) async {
    if (gen != null && gen == _readyGen) return;
    for (final sql in statements) {
      await db.execute(sql);
    }
    if (gen != null) _readyGen = gen;
  }
}
