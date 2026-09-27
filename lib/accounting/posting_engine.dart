// lib/accounting/posting_engine.dart
//
// ⚙️ محرك الترحيل: يحوّل المستندات الموجودة إلى قيود مزدوجة.
//
// لماذا «اشتقاق» لا «تسجيل عند الحفظ»؟
//   البرنامج يحفظ الفواتير والديون من عشرات المسارات (شاشات، مزامنة، تسويات).
//   لو زرعنا قيداً في كل مسار لنسينا واحداً يوماً ما واختلف الدفتر عن الواقع.
//   بدلاً من ذلك: المستند هو الحقيقة، والقيد مشتق منه ومربوط ببصمته. كل تشغيل
//   للمحرك يقارن البصمات: جديد ⇒ قيد جديد، تغيّر ⇒ يُعاد القيد، حُذف ⇒ يُحذف.
//
// المصادر وقيودها:
//   • فاتورة بيع محفوظة:   مدين الصندوق (الجزء النقدي) / دائن المبيعات
//                          مدين كلفة البضاعة / دائن المخزون
//   • حركة دين عميل:        ذمم العملاء ↔ المقابل حسب النوع
//        - مرتبطة بفاتورة ⇒ المبيعات (الجزء الآجل من الفاتورة)
//        - دين يدوي       ⇒ ديون يدوية (مبيعات خارج القوائم)
//        - تسديد          ⇒ الصندوق
//        - رصيد افتتاحي  ⇒ الأرصدة الافتتاحية
//   • فاتورة مشتريات مؤكدة: مدين المخزون / دائن الصندوق (الجزء المدفوع)
//   • حركة مورد:            ذمم الموردين ↔ المخزون / الصندوق / الافتتاحي / التسويات
//
// بهذا يبقى رصيد «ذمم العملاء» = مجموع أرصدة العملاء في سجل الديون، دائماً،
// ورصيد «ذمم الموردين» = مجموع أرصدة الموردين.
//
// يعمل على حاسبة تملك القاعدة فقط (مستقل أو سيرفر). الطرفيات تقرأ النتائج.

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';
import '../services/settings_manager.dart';
import '../utils/money_calculator.dart';
import 'ledger.dart';

class PostingSummary {
  int created = 0;
  int updated = 0;
  int deleted = 0;
  int unchanged = 0;
  final List<String> errors = [];

  @override
  String toString() =>
      'جديد $created، معدّل $updated، محذوف $deleted، بلا تغيير $unchanged'
      '${errors.isEmpty ? '' : '، أخطاء ${errors.length}'}';
}

/// مصدر واحد جاهز للترحيل.
class _Source {
  _Source(this.id, this.hash, this.row);
  final int id;
  final String hash;
  final Map<String, Object?> row;
}

class PostingEngine {
  PostingEngine({Future<Database> Function()? getDatabase})
      : _getDb = getDatabase ?? (() => DatabaseService().database);

  final Future<Database> Function() _getDb;

  static bool _running = false;

  /// آخر وقت ترحيل ناجح (لعرضه في الشاشات).
  static DateTime? lastRun;

  /// يرحّل كل المصادر. آمن للتكرار ومتزامن ذاتياً (لا يعمل مرتين معاً).
  Future<PostingSummary> syncAll({void Function(String)? progress}) async {
    final summary = PostingSummary();
    if (_running) return summary;
    _running = true;
    try {
      final db = await _getDb();
      progress?.call('فواتير البيع...');
      await _syncSalesInvoices(db, summary);
      progress?.call('ديون العملاء...');
      await _syncCustomerTransactions(db, summary);
      if (await _tableExists(db, 'purchase_invoices')) {
        progress?.call('فواتير المشتريات...');
        await _syncPurchaseInvoices(db, summary);
      }
      if (await _tableExists(db, 'supplier_transactions')) {
        progress?.call('ديون الموردين...');
        await _syncSupplierTransactions(db, summary);
      }
      lastRun = DateTime.now();
    } finally {
      _running = false;
    }
    return summary;
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String t) async {
    final r = await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [t]);
    return r.isNotEmpty;
  }

  static Future<bool> _columnExists(DatabaseExecutor db, String t, String c) async {
    final cols = await db.rawQuery('PRAGMA table_info($t)');
    return cols.any((r) => r['name'] == c);
  }

  static double _d(Object? v) => (v as num?)?.toDouble() ?? 0.0;

  static DateTime _date(Object? v) {
    final s = v as String?;
    if (s == null || s.isEmpty) return DateTime.now();
    return DateTime.tryParse(s) ?? DateTime.now();
  }

  /// المقارنة العامة: مصادر حالية مقابل قيود موجودة ⇒ ما يُنشأ ويُحدَّث ويُحذف.
  Future<void> _reconcile(
    Database db,
    String sourceType,
    List<_Source> sources,
    PostingSummary summary,
    Future<void> Function(DatabaseExecutor txn, _Source s) post,
  ) async {
    final existing = <int, String?>{};
    final rows = await db.query('journal_entries',
        columns: ['source_id', 'source_hash'],
        where: 'source_type = ?',
        whereArgs: [sourceType]);
    for (final r in rows) {
      existing[r['source_id'] as int] = r['source_hash'] as String?;
    }

    final todo = <_Source>[];
    for (final s in sources) {
      final had = existing.containsKey(s.id);
      final old = existing.remove(s.id);
      if (had && old == s.hash) {
        summary.unchanged++;
        continue;
      }
      todo.add(s);
      if (had) {
        summary.updated++;
      } else {
        summary.created++;
      }
    }
    final toDelete = existing.keys.toList();

    // الكتابة على دفعات قصيرة حتى لا تُحجز القاعدة طويلاً عن الكاشير.
    const batch = 150;
    for (var i = 0; i < todo.length; i += batch) {
      final chunk = todo.sublist(i, i + batch > todo.length ? todo.length : i + batch);
      await db.transaction((txn) async {
        for (final s in chunk) {
          try {
            await post(txn, s);
          } catch (e) {
            summary.errors.add('$sourceType #${s.id}: $e');
          }
        }
      });
    }
    for (var i = 0; i < toDelete.length; i += batch) {
      final chunk = toDelete.sublist(
          i, i + batch > toDelete.length ? toDelete.length : i + batch);
      await db.transaction((txn) async {
        for (final id in chunk) {
          await Ledger.deleteBySource(txn, sourceType, id);
        }
      });
      summary.deleted += chunk.length;
    }
  }

  // ═══════════════════════════════ فواتير البيع ═══════════════════════════════

  Future<void> _syncSalesInvoices(Database db, PostingSummary summary) async {
    final hasDeleted = await _columnExists(db, 'invoices', 'is_deleted');
    final hasAdj = await _tableExists(db, 'invoice_adjustments');
    final hasCashBoxCol = await _columnExists(db, 'invoices', 'cash_box_id');
    final hasBranchCol = await _columnExists(db, 'invoices', 'branch_id');

    final rows = await db.rawQuery('''
      SELECT i.id, i.invoice_date, i.payment_type, i.total_amount,
             i.amount_paid_on_invoice, i.customer_id, i.customer_name,
             ${hasCashBoxCol ? 'i.cash_box_id' : 'NULL'} AS cash_box_id,
             ${hasBranchCol ? 'i.branch_id' : 'NULL'} AS branch_id,
             ${hasAdj ? "COALESCE((SELECT SUM(a.amount_delta) FROM invoice_adjustments a WHERE a.invoice_id = i.id AND a.settlement_payment_type = 'نقد'), 0)" : '0'} AS adj_cash,
             (SELECT COUNT(*) || ':' || ROUND(COALESCE(SUM(ii.item_total), 0), 2) || ':' ||
                     ROUND(COALESCE(SUM(COALESCE(ii.quantity_individual, 0) + COALESCE(ii.quantity_large_unit, 0)), 0), 3) || ':' ||
                     ROUND(COALESCE(SUM(COALESCE(ii.actual_cost_price, 0)), 0), 2)
              FROM invoice_items ii WHERE ii.invoice_id = i.id) AS items_sig
      FROM invoices i
      WHERE i.status = 'محفوظة'
        ${hasDeleted ? 'AND COALESCE(i.is_deleted, 0) = 0' : ''}
    ''');

    final sources = <_Source>[];
    for (final r in rows) {
      final hash = [
        r['invoice_date'],
        r['payment_type'],
        _d(r['total_amount']).toStringAsFixed(2),
        _d(r['amount_paid_on_invoice']).toStringAsFixed(2),
        _d(r['adj_cash']).toStringAsFixed(2),
        r['items_sig'],
        r['cash_box_id'],
        r['branch_id'],
      ].join('|');
      sources.add(_Source(r['id'] as int, hash, r));
    }

    final cashMain = await _defaultCashAccount(db);
    final sales = await Ledger.systemAccountId(db, 'sales');
    final cogs = await Ledger.systemAccountId(db, 'cogs');
    final inventory = await Ledger.systemAccountId(db, 'inventory');
    final settings = await SettingsManager.getAppSettings();
    final adHocMargin = settings.defaultAdHocProfitPercentage / 100.0;

    await _reconcile(db, 'invoice', sources, summary, (txn, s) async {
      final r = s.row;
      final total = _d(r['total_amount']);
      final isCash = r['payment_type'] == 'نقد';
      var cashPart = isCash ? total : _d(r['amount_paid_on_invoice']);
      if (cashPart > total) cashPart = total;
      if (cashPart < 0) cashPart = 0;
      cashPart += _d(r['adj_cash']);

      final cost = await _invoiceCost(txn, s.id, adHocMargin);
      final cashAcc = await _cashAccountFor(txn, r['cash_box_id'] as int?, cashMain);

      final lines = <JournalLineInput>[
        if (cashPart > 0) ...[
          JournalLineInput(accountId: cashAcc, debit: cashPart, memo: 'المقبوض نقداً'),
          JournalLineInput(accountId: sales, credit: cashPart),
        ],
        if (cashPart < 0) ...[
          JournalLineInput(accountId: sales, debit: -cashPart),
          JournalLineInput(accountId: cashAcc, credit: -cashPart),
        ],
        if (cost > 0) ...[
          JournalLineInput(accountId: cogs, debit: cost),
          JournalLineInput(accountId: inventory, credit: cost),
        ],
      ];
      final desc = 'فاتورة بيع #${s.id} — ${r['customer_name'] ?? ''}'.trim();
      if (lines.isEmpty) {
        // فاتورة آجلة بلا كلفة معروفة: نثبت بصمتها بقيد صفري لا يُكتب.
        await Ledger.deleteBySource(txn, 'invoice', s.id);
        await txn.insert('journal_entries', {
          'entry_number': 0,
          'entry_date': _date(r['invoice_date']).toIso8601String(),
          'description': '$desc (الجزء الآجل يُرحّل من دين العميل)',
          'source_type': 'invoice',
          'source_id': s.id,
          'source_hash': s.hash,
          'branch_id': (r['branch_id'] as int?) ?? 1,
          'created_at': DateTime.now().toIso8601String(),
        });
        return;
      }
      await Ledger.writeEntry(txn,
          sourceType: 'invoice',
          sourceId: s.id,
          sourceHash: s.hash,
          date: _date(r['invoice_date']),
          description: desc,
          lines: lines,
          branchId: (r['branch_id'] as int?) ?? 1);
    });
  }

  /// كلفة الفاتورة — نفس منطق ProfitCalculator حرفياً حتى تطابق أرباح
  /// الدفتر أرباحَ التقارير القديمة.
  static Future<double> _invoiceCost(
      DatabaseExecutor db, int invoiceId, double adHocMargin) async {
    final items = await db.rawQuery('''
      SELECT ii.quantity_individual AS qi, ii.quantity_large_unit AS ql,
             ii.units_in_large_unit AS uilu, ii.actual_cost_price AS actual_cost,
             ii.applied_price AS selling_price, ii.sale_type AS sale_type,
             p.cost_price AS product_cost, p.unit AS product_unit,
             p.length_per_unit AS length_per_unit, p.unit_costs AS unit_costs
      FROM invoice_items ii
      LEFT JOIN products p ON p.name = ii.product_name
      WHERE ii.invoice_id = ?
    ''', [invoiceId]);
    var total = 0.0;
    for (final it in items) {
      final qi = _d(it['qi']);
      final ql = _d(it['ql']);
      final uilu = (it['uilu'] as num?)?.toDouble() ?? 1;
      final actual = (it['actual_cost'] as num?)?.toDouble();
      final productCost = _d(it['product_cost']);
      final selling = _d(it['selling_price']);
      final saleType = (it['sale_type'] as String?) ?? '';
      final unit = (it['product_unit'] as String?) ?? '';
      final lengthPerUnit = (it['length_per_unit'] as num?)?.toDouble();
      Map<String, dynamic> unitCosts = const {};
      final uc = it['unit_costs'] as String?;
      if (uc != null && uc.trim().isNotEmpty) {
        try {
          unitCosts = jsonDecode(uc) as Map<String, dynamic>;
        } catch (_) {}
      }
      final large = ql > 0;
      final count = large ? ql : qi;
      double c;
      if (actual != null && actual > 0) {
        c = actual;
      } else if (large) {
        final stored = unitCosts[saleType];
        if (stored is num && stored > 0) {
          c = stored.toDouble();
        } else {
          final meterRoll = unit == 'meter' && lengthPerUnit != null && saleType == 'لفة';
          c = meterRoll ? productCost * lengthPerUnit : productCost * uilu;
        }
      } else {
        c = productCost;
      }
      if (c <= 0 && selling > 0) {
        c = MoneyCalculator.getEffectiveCost(0, selling, profitMargin: adHocMargin);
      }
      total += c * count;
    }
    return roundMoney(total);
  }

  // ═══════════════════════════════ ديون العملاء ═══════════════════════════════

  Future<void> _syncCustomerTransactions(Database db, PostingSummary summary) async {
    final hasDeleted = await _columnExists(db, 'transactions', 'is_deleted');
    final rows = await db.rawQuery('''
      SELECT t.id, t.customer_id, t.transaction_date, t.amount_changed,
             t.transaction_type, t.invoice_id, t.description, c.name AS customer_name
      FROM transactions t LEFT JOIN customers c ON c.id = t.customer_id
      ${hasDeleted ? 'WHERE COALESCE(t.is_deleted, 0) = 0' : ''}
    ''');
    final sources = <_Source>[];
    for (final r in rows) {
      final amt = _d(r['amount_changed']);
      if (amt.abs() < kMoneyEpsilon) continue;
      final hash = [
        r['customer_id'],
        r['transaction_date'],
        amt.toStringAsFixed(2),
        r['transaction_type'],
        r['invoice_id'],
      ].join('|');
      sources.add(_Source(r['id'] as int, hash, r));
    }

    final ar = await Ledger.systemAccountId(db, 'ar_customers');
    final sales = await Ledger.systemAccountId(db, 'sales');
    final salesManual = await Ledger.systemAccountId(db, 'sales_manual');
    final opening = await Ledger.systemAccountId(db, 'opening_equity');
    final cash = await _defaultCashAccount(db);

    await _reconcile(db, 'customer_tx', sources, summary, (txn, s) async {
      final r = s.row;
      final amt = _d(r['amount_changed']);
      final type = (r['transaction_type'] as String?) ?? '';
      final int counter;
      String label;
      if (r['invoice_id'] != null) {
        counter = sales;
        label = 'الجزء الآجل من فاتورة #${r['invoice_id']}';
      } else if (type == 'opening_balance') {
        counter = opening;
        label = 'رصيد افتتاحي';
      } else if (type == 'manual_payment' || (type.isEmpty && amt < 0)) {
        counter = cash;
        label = 'تسديد';
      } else {
        counter = salesManual;
        label = 'دين يدوي';
      }
      final customerId = r['customer_id'] as int?;
      final lines = amt > 0
          ? [
              JournalLineInput(
                  accountId: ar, debit: amt, partyType: 'customer', partyId: customerId),
              JournalLineInput(accountId: counter, credit: amt),
            ]
          : [
              JournalLineInput(accountId: counter, debit: -amt),
              JournalLineInput(
                  accountId: ar, credit: -amt, partyType: 'customer', partyId: customerId),
            ];
      await Ledger.writeEntry(txn,
          sourceType: 'customer_tx',
          sourceId: s.id,
          sourceHash: s.hash,
          date: _date(r['transaction_date']),
          description: '$label — ${r['customer_name'] ?? 'عميل #$customerId'}',
          lines: lines);
    });
  }

  // ═══════════════════════════════ المشتريات ═══════════════════════════════

  Future<void> _syncPurchaseInvoices(Database db, PostingSummary summary) async {
    final rows = await db.rawQuery('''
      SELECT p.id, p.invoice_number, p.date, p.paid_amount, p.total_amount,
             p.currency, s.name AS supplier_name
      FROM purchase_invoices p LEFT JOIN suppliers s ON s.id = p.supplier_id
      WHERE p.status = 'confirmed'
    ''');
    final rate = await Ledger.usdRate(db);
    final sources = <_Source>[];
    for (final r in rows) {
      final paid = _d(r['paid_amount']);
      if (paid.abs() < kMoneyEpsilon) continue; // الجزء الآجل يأتي من حركة المورد
      final hash = [
        r['date'],
        paid.toStringAsFixed(2),
        r['currency'],
        r['currency'] == 'USD' ? rate.toStringAsFixed(2) : '',
      ].join('|');
      sources.add(_Source(r['id'] as int, hash, r));
    }
    final inventory = await Ledger.systemAccountId(db, 'inventory');
    final cash = await _defaultCashAccount(db);

    await _reconcile(db, 'purchase_invoice', sources, summary, (txn, s) async {
      final r = s.row;
      final paid = _d(r['paid_amount']);
      final usd = r['currency'] == 'USD';
      final iqd = usd ? paid * rate : paid;
      await Ledger.writeEntry(txn,
          sourceType: 'purchase_invoice',
          sourceId: s.id,
          sourceHash: s.hash,
          date: _date(r['date']),
          description:
              'فاتورة مشتريات ${r['invoice_number'] ?? '#${s.id}'} — ${r['supplier_name'] ?? ''} (المدفوع عند الشراء)',
          lines: [
            JournalLineInput(
                accountId: inventory,
                debit: iqd,
                currency: usd ? 'USD' : 'IQD',
                fcAmount: usd ? paid : null,
                exchangeRate: usd ? rate : null),
            JournalLineInput(accountId: cash, credit: iqd),
          ]);
    });
  }

  Future<void> _syncSupplierTransactions(Database db, PostingSummary summary) async {
    final rows = await db.rawQuery('''
      SELECT t.id, t.supplier_id, t.transaction_date, t.amount_changed, t.currency,
             t.transaction_type, t.description, s.name AS supplier_name
      FROM supplier_transactions t LEFT JOIN suppliers s ON s.id = t.supplier_id
      WHERE COALESCE(t.is_deleted, 0) = 0
    ''');
    final rate = await Ledger.usdRate(db);
    final sources = <_Source>[];
    for (final r in rows) {
      final amt = _d(r['amount_changed']);
      if (amt.abs() < kMoneyEpsilon) continue;
      final usd = r['currency'] == 'USD';
      final hash = [
        r['supplier_id'],
        r['transaction_date'],
        amt.toStringAsFixed(2),
        r['currency'],
        r['transaction_type'],
        usd ? rate.toStringAsFixed(2) : '',
      ].join('|');
      sources.add(_Source(r['id'] as int, hash, r));
    }
    final apIqd = await Ledger.systemAccountId(db, 'ap_iqd');
    final apUsd = await Ledger.systemAccountId(db, 'ap_usd');
    final inventory = await Ledger.systemAccountId(db, 'inventory');
    final opening = await Ledger.systemAccountId(db, 'opening_equity');
    final corrections = await Ledger.systemAccountId(db, 'supplier_corrections');
    final cash = await _defaultCashAccount(db);

    await _reconcile(db, 'supplier_tx', sources, summary, (txn, s) async {
      final r = s.row;
      final amt = _d(r['amount_changed']);
      final usd = r['currency'] == 'USD';
      final iqd = usd ? amt * rate : amt;
      final type = (r['transaction_type'] as String?) ?? '';
      final int counter;
      String label;
      switch (type) {
        case 'supplier_payment':
          counter = cash;
          label = 'دفعة لمورد';
          break;
        case 'opening_balance':
          counter = opening;
          label = 'رصيد افتتاحي لمورد';
          break;
        case 'correction':
          counter = corrections;
          label = 'تسوية حساب مورد';
          break;
        case 'purchase_return':
          counter = inventory;
          label = 'مرتجع مشتريات';
          break;
        default:
          counter = amt > 0 ? inventory : cash;
          label = amt > 0 ? 'مشتريات آجلة' : 'دفعة لمورد';
      }
      final ap = usd ? apUsd : apIqd;
      final supplierId = r['supplier_id'] as int?;
      JournalLineInput apLine(double dr, double cr) => JournalLineInput(
            accountId: ap,
            debit: dr,
            credit: cr,
            partyType: 'supplier',
            partyId: supplierId,
            currency: usd ? 'USD' : 'IQD',
            fcAmount: usd ? amt.abs() : null,
            exchangeRate: usd ? rate : null,
          );
      final lines = iqd > 0
          ? [JournalLineInput(accountId: counter, debit: iqd), apLine(0, iqd)]
          : [apLine(-iqd, 0), JournalLineInput(accountId: counter, credit: -iqd)];
      await Ledger.writeEntry(txn,
          sourceType: 'supplier_tx',
          sourceId: s.id,
          sourceHash: s.hash,
          date: _date(r['transaction_date']),
          description: '$label — ${r['supplier_name'] ?? 'مورد #$supplierId'}',
          lines: lines);
    });
  }

  // ═══════════════════════════════ الصناديق ═══════════════════════════════

  static Future<int> _defaultCashAccount(DatabaseExecutor db) async {
    final r = await db.rawQuery(
        'SELECT account_id FROM cash_boxes WHERE is_default = 1 AND is_active = 1 ORDER BY id LIMIT 1');
    if (r.isNotEmpty) return r.first['account_id'] as int;
    return Ledger.systemAccountId(db, 'cash_main');
  }

  static Future<int> _cashAccountFor(
      DatabaseExecutor db, int? cashBoxId, int fallback) async {
    if (cashBoxId == null) return fallback;
    final r = await db.query('cash_boxes',
        columns: ['account_id'], where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
    return r.isEmpty ? fallback : r.first['account_id'] as int;
  }

  // ═══════════════════════════ تقييم المخزون الافتتاحي ═══════════════════════════

  /// يضبط رصيد حساب المخزون ليساوي قيمة البضاعة الموجودة فعلاً
  /// (الكمية × سعر الكلفة)، والفرق يذهب إلى الأرصدة الافتتاحية.
  ///
  /// لماذا؟ أغلب المشتريات القديمة لم تُسجَّل في البرنامج، فحساب المخزون
  /// (المشتريات − كلفة المبيعات) يكون سالباً. هذا القيد الواحد يصحّحه، ويُعاد
  /// حسابه كلما ضُغط الزر (مصدره ثابت: source_id = 1).
  Future<double> alignInventoryToStockValue() async {
    final db = await _getDb();
    final inventory = await Ledger.systemAccountId(db, 'inventory');
    final opening = await Ledger.systemAccountId(db, 'opening_equity');
    final hasStock = await _columnExists(db, 'products', 'stock_quantity');
    if (!hasStock) {
      throw LedgerException('لا يوجد عمود كمية المخزون في جدول المواد');
    }
    final v = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN stock_quantity > 0 THEN stock_quantity * COALESCE(cost_price, 0) ELSE 0 END), 0) AS v
      FROM products
    ''');
    final stockValue = roundMoney(_d(v.first['v']));

    return db.transaction((txn) async {
      await Ledger.deleteBySource(txn, 'inventory_valuation', 1);
      final bal = await txn.rawQuery(
          'SELECT COALESCE(SUM(debit - credit), 0) AS b FROM journal_lines WHERE account_id = ?',
          [inventory]);
      final current = _d(bal.first['b']);
      final diff = roundMoney(stockValue - current);
      if (diff.abs() < kMoneyEpsilon) return 0.0;
      await Ledger.writeEntry(txn,
          sourceType: 'inventory_valuation',
          sourceId: 1,
          sourceHash: stockValue.toStringAsFixed(2),
          date: DateTime.now(),
          description:
              'مطابقة المخزون مع قيمة البضاعة الموجودة (${stockValue.toStringAsFixed(0)})',
          lines: diff > 0
              ? [
                  JournalLineInput(accountId: inventory, debit: diff),
                  JournalLineInput(accountId: opening, credit: diff),
                ]
              : [
                  JournalLineInput(accountId: opening, debit: -diff),
                  JournalLineInput(accountId: inventory, credit: -diff),
                ]);
      return diff;
    });
  }
}
