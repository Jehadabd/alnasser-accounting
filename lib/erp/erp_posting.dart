// lib/erp/erp_posting.dart
//
// ⚙️ ترحيل مستندات الإداري/سهل إلى الدفتر — بنفس مبدأ محرك الترحيل:
// القيد مشتق من المستند ومربوط ببصمته؛ تغيّر المستند ⇒ يُعاد قيده، أُلغي ⇒ يُحذف.
//
//   • مرتجع مبيعات (sales_return):
//       نقداً:  مدين مردودات المبيعات / دائن الصندوق
//       الكلفة: مدين المخزون / دائن كلفة البضاعة المباعة
//       (المرتجع على الحساب يُرحّل من حركة العميل نفسها: مدين المردودات / دائن الذمم)
//   • مستند مخزني (stock_doc): إدخال، إخراج، بضاعة أول المدة، جرد، تصنيع
//       فرق قيمة المخزون ↔ الحساب المقابل للمستند
//   • عمولة بائع على فاتورة (invoice_commission):
//       مدين عمولات البيع / دائن عمولات مستحقة للبائعين

import 'package:sqflite/sqflite.dart';

import '../accounting/ledger.dart';
import 'erp_common.dart';
import 'sales/sales_return_service.dart' show returnCashPart;

class ErpPostingSummary {
  int created = 0;
  int updated = 0;
  int deleted = 0;
  int unchanged = 0;
  final List<String> errors = [];
}

class _Src {
  _Src(this.id, this.hash, this.row);
  final int id;
  final String hash;
  final Map<String, Object?> row;
}

class ErpPosting {
  ErpPosting(this.db);
  final Database db;

  /// هل هُيّئت حسابات النظام الجديدة؟
  static Future<bool> hasAccounts(DatabaseExecutor db) async {
    final r = await db.query('accounts',
        columns: ['id'], where: 'system_key = ?', whereArgs: ['discount_allowed'], limit: 1);
    return r.isNotEmpty;
  }

  /// الحساب المقابل لذمم العملاء حسب وصف المعاملة.
  static Future<int> customerCounter(DatabaseExecutor db, String kind) async {
    switch (kind) {
      case 'discount':
        return Ledger.systemAccountId(db, 'discount_allowed');
      case 'cheque':
      case 'cheque_bounce':
        return Ledger.systemAccountId(db, 'cheques_receivable');
      case 'sales_return':
        return Ledger.systemAccountId(db, 'sales_returns');
      case 'reconcile':
        return Ledger.systemAccountId(db, 'customer_settlement');
      default:
        throw LedgerException('نوع معاملة غير معروف: $kind');
    }
  }

  static String customerKindLabel(String kind) {
    switch (kind) {
      case 'discount':
        return 'خصم مسموح به';
      case 'cheque':
        return 'تسديد بشيك/ورقة قبض';
      case 'cheque_bounce':
        return 'شيك مرتجع';
      case 'sales_return':
        return 'مرتجع مبيعات على الحساب';
      case 'reconcile':
        return 'فرق مطابقة رصيد';
      default:
        return kind;
    }
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String t) async {
    final r = await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [t]);
    return r.isNotEmpty;
  }

  Future<ErpPostingSummary> syncAll() async {
    final s = ErpPostingSummary();
    if (!await _tableExists(db, 'sales_returns') || !await hasAccounts(db)) return s;
    await _salesReturns(s);
    await _stockDocs(s);
    await _commissions(s);
    return s;
  }

  Future<void> _reconcile(
    String sourceType,
    List<_Src> sources,
    ErpPostingSummary summary,
    Future<void> Function(DatabaseExecutor txn, _Src s) post,
  ) async {
    final existing = <int, String?>{};
    final rows = await db.query('journal_entries',
        columns: ['source_id', 'source_hash'], where: 'source_type = ?', whereArgs: [sourceType]);
    for (final r in rows) {
      existing[r['source_id'] as int] = r['source_hash'] as String?;
    }
    final todo = <_Src>[];
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
    if (toDelete.isNotEmpty) {
      await db.transaction((txn) async {
        for (final id in toDelete) {
          await Ledger.deleteBySource(txn, sourceType, id);
        }
      });
      summary.deleted += toDelete.length;
    }
  }

  static Future<int> _boxAccount(DatabaseExecutor db, int? boxId) async {
    if (boxId != null) {
      final r = await db.query('cash_boxes', columns: ['account_id'], where: 'id = ?', whereArgs: [boxId], limit: 1);
      if (r.isNotEmpty) return r.first['account_id'] as int;
    }
    final d = await db.rawQuery(
        'SELECT account_id FROM cash_boxes WHERE is_default = 1 AND is_active = 1 ORDER BY id LIMIT 1');
    if (d.isNotEmpty) return d.first['account_id'] as int;
    return Ledger.systemAccountId(db, 'cash_main');
  }

  // ═══════════════════════════ مرتجع المبيعات ═══════════════════════════

  Future<void> _salesReturns(ErpPostingSummary summary) async {
    final rows = await db.rawQuery(
        "SELECT * FROM sales_returns WHERE status = 'posted'");
    final sources = <_Src>[];
    for (final r in rows) {
      final total = d0(r['total']);
      final cost = d0(r['cost_total']);
      final cashPart = returnCashPart(r);
      if (cashPart.abs() < kMoneyEpsilon && cost.abs() < kMoneyEpsilon) continue;
      final hash = [
        r['return_date'],
        total.toStringAsFixed(2),
        cost.toStringAsFixed(2),
        r['refund_mode'],
        r['cash_box_id'],
        cashPart.toStringAsFixed(2),
      ].join('|');
      sources.add(_Src(r['id'] as int, hash, r));
    }
    final salesReturns = await Ledger.systemAccountId(db, 'sales_returns');
    final inventory = await Ledger.systemAccountId(db, 'inventory');
    final cogs = await Ledger.systemAccountId(db, 'cogs');
    await _reconcile('sales_return', sources, summary, (txn, s) async {
      final r = s.row;
      final total = d0(r['total']);
      final cost = d0(r['cost_total']);
      final cashPart = returnCashPart(r);
      final lines = <JournalLineInput>[
        // الجزء النقدي فقط؛ جزء الحساب يُرحَّل من حركة العميل نفسها
        if (cashPart > 0 && total > 0) ...[
          JournalLineInput(accountId: salesReturns, debit: cashPart, memo: 'مرتجع نقدي'),
          JournalLineInput(accountId: await _boxAccount(txn, r['cash_box_id'] as int?), credit: cashPart),
        ],
        if (cost > 0) ...[
          JournalLineInput(accountId: inventory, debit: cost, memo: 'عودة البضاعة للمخزن'),
          JournalLineInput(accountId: cogs, credit: cost),
        ],
      ];
      await Ledger.writeEntry(txn,
          sourceType: 'sales_return',
          sourceId: s.id,
          sourceHash: s.hash,
          date: parseDate(r['return_date']),
          description: 'مرتجع مبيعات رقم ${r['return_no']} — ${r['customer_name'] ?? ''}',
          lines: lines);
    });
  }

  // ═══════════════════════════ المستندات المخزنية ═══════════════════════════

  static const Map<String, String> docTypeLabels = {
    'in': 'سند إدخال مخزني',
    'out': 'سند إخراج مخزني',
    'opening': 'بضاعة أول المدة',
    'count': 'تسوية جرد',
    'production': 'عملية تصنيع',
  };

  /// جرد بحسابَي زيادة/عجز مثبّتين على المستند.
  static bool _splitCount(Map<String, Object?> r) =>
      r['doc_type'] == 'count' &&
      r['counter_account_id'] == null &&
      (r['gain_account_id'] != null || r['loss_account_id'] != null);

  Future<void> _stockDocs(ErpPostingSummary summary) async {
    final rows = await db.rawQuery('''
      SELECT d.*, COALESCE((SELECT SUM(CASE WHEN i.base_qty < 0 THEN -i.total_cost ELSE i.total_cost END)
                             FROM stock_doc_items i WHERE i.doc_id = d.id), 0) AS inv_delta,
             COALESCE((SELECT SUM(i.total_cost) FROM stock_doc_items i WHERE i.doc_id = d.id AND i.base_qty > 0), 0) AS gain_total,
             COALESCE((SELECT SUM(i.total_cost) FROM stock_doc_items i WHERE i.doc_id = d.id AND i.base_qty < 0), 0) AS loss_total,
             (SELECT COUNT(*) FROM stock_doc_items i WHERE i.doc_id = d.id) AS n_items
      FROM stock_docs d WHERE d.status = 'posted'
    ''');
    final sources = <_Src>[];
    for (final r in rows) {
      final delta = roundMoney(d0(r['inv_delta']));
      final split = _splitCount(r);
      if (!split && delta.abs() < kMoneyEpsilon) continue;
      if (split && d0(r['gain_total']) < kMoneyEpsilon && d0(r['loss_total']) < kMoneyEpsilon) continue;
      final hash = [
        r['doc_date'],
        delta.toStringAsFixed(2),
        r['counter_account_id'],
        r['overhead_account_id'],
        r['n_items'],
        r['doc_type'],
        if (split) '${r['gain_account_id']}/${r['loss_account_id']}/${d0(r['gain_total']).toStringAsFixed(2)}',
      ].join('|');
      sources.add(_Src(r['id'] as int, hash, r));
    }
    final inventory = await Ledger.systemAccountId(db, 'inventory');
    await _reconcile('stock_doc', sources, summary, (txn, s) async {
      final r = s.row;
      final delta = roundMoney(d0(r['inv_delta']));
      final type = r['doc_type'] as String;
      if (_splitCount(r)) {
        // 🧮 جرد بحسابَي زيادة/عجز منفصلين
        final gain = roundMoney(d0(r['gain_total']));
        final loss = roundMoney(d0(r['loss_total']));
        final fallback = await Ledger.systemAccountId(txn, 'inventory_adjust');
        final gainAcc = (r['gain_account_id'] as int?) ?? fallback;
        final lossAcc = (r['loss_account_id'] as int?) ?? fallback;
        await Ledger.writeEntry(txn,
            sourceType: 'stock_doc',
            sourceId: s.id,
            sourceHash: s.hash,
            date: parseDate(r['doc_date']),
            description: '${docTypeLabels[type] ?? type} رقم ${r['doc_no']}${(r['reason'] as String?)?.isNotEmpty == true ? ' — ${r['reason']}' : ''}',
            lines: [
              if (gain > 0) ...[
                JournalLineInput(accountId: inventory, debit: gain, memo: 'زيادة جرد'),
                JournalLineInput(accountId: gainAcc, credit: gain),
              ],
              if (loss > 0) ...[
                JournalLineInput(accountId: lossAcc, debit: loss, memo: 'عجز جرد'),
                JournalLineInput(accountId: inventory, credit: loss),
              ],
            ]);
        return;
      }
      int counter;
      final explicit = (type == 'production' ? r['overhead_account_id'] : r['counter_account_id']) as int?;
      if (explicit != null) {
        counter = explicit;
      } else {
        switch (type) {
          case 'opening':
            counter = await Ledger.systemAccountId(txn, 'opening_equity');
            break;
          case 'count':
            counter = await Ledger.systemAccountId(txn, 'inventory_adjust');
            break;
          case 'production':
            counter = await Ledger.systemAccountId(txn, 'manufacturing_absorbed');
            break;
          case 'in':
            counter = await Ledger.systemAccountId(txn, 'inventory_adjust');
            break;
          default:
            counter = await Ledger.systemAccountId(txn, 'inventory_writeoff');
        }
      }
      final lines = delta > 0
          ? [
              JournalLineInput(accountId: inventory, debit: delta),
              JournalLineInput(accountId: counter, credit: delta),
            ]
          : [
              JournalLineInput(accountId: counter, debit: -delta),
              JournalLineInput(accountId: inventory, credit: -delta),
            ];
      await Ledger.writeEntry(txn,
          sourceType: 'stock_doc',
          sourceId: s.id,
          sourceHash: s.hash,
          date: parseDate(r['doc_date']),
          description:
              '${docTypeLabels[type] ?? type} رقم ${r['doc_no']}${(r['reason'] as String?)?.isNotEmpty == true ? ' — ${r['reason']}' : ''}',
          lines: lines);
    });
  }

  // ═══════════════════════════ عمولات البائعين ═══════════════════════════

  Future<void> _commissions(ErpPostingSummary summary) async {
    final rows = await db.rawQuery('''
      SELECT x.invoice_id, x.commission_amount, x.seller_name, i.invoice_date, i.customer_name
      FROM invoice_extras x JOIN invoices i ON i.id = x.invoice_id
      WHERE COALESCE(x.commission_amount, 0) > 0
        AND i.status = 'محفوظة' AND COALESCE(i.is_deleted, 0) = 0
    ''');
    final sources = <_Src>[
      for (final r in rows)
        _Src(r['invoice_id'] as int,
            [r['invoice_date'], d0(r['commission_amount']).toStringAsFixed(2), r['seller_name']].join('|'), r),
    ];
    final expense = await Ledger.systemAccountId(db, 'sales_commission');
    final payable = await Ledger.systemAccountId(db, 'commissions_payable');
    await _reconcile('invoice_commission', sources, summary, (txn, s) async {
      final r = s.row;
      final amt = d0(r['commission_amount']);
      await Ledger.writeEntry(txn,
          sourceType: 'invoice_commission',
          sourceId: s.id,
          sourceHash: s.hash,
          date: parseDate(r['invoice_date']),
          description: 'عمولة البائع ${r['seller_name'] ?? ''} على فاتورة #${s.id} — ${r['customer_name'] ?? ''}',
          lines: [
            JournalLineInput(accountId: expense, debit: amt),
            JournalLineInput(accountId: payable, credit: amt),
          ]);
    });
  }
}
