// lib/erp/warranty/warranty_schema.dart
//
// 🛠️ جداول الضمان والصيانة — تُنشأ مع بقية جداول الإداري (ErpSchema.ensure)
// وكذلك عند أول فتح للشاشة. كلها IF NOT EXISTS: التشغيل المتكرر آمن.
// هذه الجداول «سجل متابعة» فقط: لا مال ولا مخزون ولا قيود.

class WarrantySchema {
  WarrantySchema._();

  static const List<String> statements = [
    // مدة ضمان كل مادة (بالأشهر) — تُقترح تلقائياً عند استلام قطعة منها
    '''
    CREATE TABLE IF NOT EXISTS product_warranty (
      product_id INTEGER PRIMARY KEY,
      months INTEGER NOT NULL DEFAULT 0,
      note TEXT,
      updated_at TEXT
    )''',
    // طلب ضمان/صيانة: قطعة استلمها المحل من عميل
    '''
    CREATE TABLE IF NOT EXISTS warranty_claims (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      claim_no INTEGER NOT NULL,
      customer_id INTEGER,
      customer_name TEXT NOT NULL,
      phone TEXT,
      product_id INTEGER,
      product_name TEXT NOT NULL,
      qty REAL NOT NULL DEFAULT 1,
      serial_no TEXT,
      invoice_id INTEGER,
      sale_date TEXT,
      warranty_months INTEGER,
      within_warranty INTEGER,
      claim_date TEXT NOT NULL,
      problem TEXT,
      accessories TEXT,
      status TEXT NOT NULL DEFAULT 'received',
      resolution TEXT,
      supplier_id INTEGER,
      supplier_name TEXT,
      sent_date TEXT,
      back_date TEXT,
      delivered_date TEXT,
      notes TEXT,
      created_by TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    'CREATE INDEX IF NOT EXISTS idx_wc_status ON warranty_claims(status, claim_date)',
    'CREATE INDEX IF NOT EXISTS idx_wc_customer ON warranty_claims(customer_id)',
    'CREATE INDEX IF NOT EXISTS idx_wc_product ON warranty_claims(product_id)',
    // الخط الزمني لكل طلب (من استلم، متى أُرسل للمورد، متى سُلّم...)
    '''
    CREATE TABLE IF NOT EXISTS warranty_claim_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      claim_id INTEGER NOT NULL,
      status TEXT NOT NULL,
      note TEXT,
      user_name TEXT,
      at TEXT NOT NULL
    )''',
    'CREATE INDEX IF NOT EXISTS idx_wce_claim ON warranty_claim_events(claim_id)',
  ];
}
