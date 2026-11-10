// lib/services/database/business/deep_check_repair.dart
//
// 🩺 معالجة ملاحظات «الفحص العميق» للفواتير — بقرار صريح من المدير، فاتورة فاتورة:
//
//   الفاتورة وسجل الديون يختلفان ⇒ أحدهما خطأ، والبرنامج لا يعرف أيهما؛ صاحب المحل يعرف.
//   • «اعتمد سجل الديون»: لا يتغير أي دين ولا معاملة. تُصحَّح خانتا الفاتورة فقط (نقد/دين
//     والمسدد) لتطابق ما في سجل الديون. يُستعمل حين يكون رصيد العميل صحيحاً (مثلاً سدّد
//     بتسديدات يدوية) والفاتورة هي التي بقيت على حال قديمة.
//   • «اعتمد الفاتورة»: يُضبط سجل الديون على ما تقوله الفاتورة عبر الحارس المحاسبي نفسه
//     (InvoiceDebtReconciler — صف تسوية واحد لكل فاتورة وعميل). يغيّر رصيد العميل: يُعرض
//     الرصيد قبل وبعد ويُطلب التأكيد.
//   • «مُراجَعة»: تُخفى الملاحظة ما دامت أرقامها كما هي؛ أي تغيير فيها يعيد إظهارها.
//
// كل عملية في معاملة قاعدة بيانات واحدة: إن لم تنتهِ النتيجة متطابقة تُلغى كلها.
// لا حذف لأي معاملة. كل معالجة تُسجَّل في سجل التدقيق.

import 'package:sqflite/sqflite.dart';

import '../../financial_audit_service.dart';
import 'invoice_debt_reconciler.dart';

class InvoiceTx {
  InvoiceTx(this.id, this.date, this.amount, this.type, this.customerId, this.customerName, this.description);
  final int id;
  final String date;
  final double amount;
  final String type, customerName, description;
  final int? customerId;
}

class InvoiceRepairInfo {
  InvoiceRepairInfo({
    required this.invoiceId,
    required this.number,
    required this.customerId,
    required this.customerName,
    required this.paymentType,
    required this.status,
    required this.deleted,
    required this.total,
    required this.paid,
    required this.cashSettlements,
    required this.expected,
    required this.recorded,
    required this.names,
    required this.balances,
    required this.txs,
    required this.customerExists,
  });

  /// عميل الفاتورة موجود وغير محذوف؟
  final bool customerExists;

  /// null = «اعتمد الفاتورة» ممكن. وإلا السبب.
  String? get invoiceTruthBlock {
    if (consistent) return 'متطابقة';
    if (expected > 0.01 && !customerExists) {
      return 'عميل الفاتورة غير موجود أو محذوف — لا يُسجَّل دين على عميل غير موجود؛ افتح الفاتورة واختر العميل';
    }
    return null;
  }

  final int invoiceId;
  final String number, customerName, paymentType, status;
  final int? customerId;
  final bool deleted;
  final double total, paid, cashSettlements;

  /// مساهمة الفاتورة المتوقعة في دين عميلها (قاعدة الحارس المحاسبي).
  final double expected;

  /// المسجّل فعلاً في سجل الديون لكل عميل (معاملات الفاتورة بلا التسديدات والتصحيحات).
  final Map<int, double> recorded;
  final Map<int, String> names;

  /// رصيد كل عميل معني الآن.
  final Map<int, double> balances;
  final List<InvoiceTx> txs;

  bool get suspended => status == 'معلقة';
  double get recordedCurrent => customerId == null ? 0 : (recorded[customerId] ?? 0);
  double get recordedOthers =>
      recorded.entries.where((e) => e.key != customerId).fold(0.0, (s, e) => s + e.value);

  bool get consistent =>
      (expected - recordedCurrent).abs() <= 0.01 && recordedOthers.abs() <= 0.01;

  /// بصمة الحالة: «مُراجَعة» تبقى ما دامت هذه كما هي.
  String get fingerprint => [
        paymentType,
        status,
        deleted ? 1 : 0,
        customerId ?? 0,
        (total * 100).round(),
        (paid * 100).round(),
        (recordedCurrent * 100).round(),
        (recordedOthers * 100).round(),
      ].join('|');

  // ── «اعتمد سجل الديون»: ماذا يتغير في الفاتورة؟ ──

  /// null = ممكن. وإلا سبب عدم الإمكان.
  String? get ledgerTruthBlock {
    if (deleted) return 'الفاتورة محذوفة — لا تُعدَّل';
    if (suspended) return 'الفاتورة معلّقة — المعلّقة لا تحمل ديناً أصلاً؛ استعمل «اعتمد الفاتورة»';
    if (customerId == null || customerId! <= 0) return 'الفاتورة بلا عميل مرتبط — افتحها واختر العميل';
    if (recordedOthers.abs() > 0.01) return 'جزء من دينها على عميل آخر — استعمل «اعتمد الفاتورة» لنقله';
    final room = total - cashSettlements;
    if (recordedCurrent < -0.01) return 'المسجّل في سجل الديون سالب — لا يقابله مسدد منطقي';
    if (recordedCurrent > room + 0.01) {
      return 'المسجّل في سجل الديون (${_m(recordedCurrent)}) أكبر من إجمالي الفاتورة — لا يُفسَّر بالمسدد';
    }
    return null;
  }

  String get newPaymentType => recordedCurrent > 0.01 ? 'دين' : paymentType;
  double get newPaid {
    final p = total - cashSettlements - recordedCurrent;
    return p < 0 ? 0 : (p * 100).round() / 100;
  }

  static String _m(double v) {
    final s = v.abs().round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return v < 0 ? '-$s' : s;
  }
}

class DeepCheckRepair {
  DeepCheckRepair._();

  static const ackTable = 'deep_check_ack';

  static Future<bool> _hasTable(DatabaseExecutor db, String t) async =>
      (await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [t])).isNotEmpty;

  static Future<bool> _hasCol(DatabaseExecutor db, String t, String c) async =>
      (await db.rawQuery('PRAGMA table_info($t)')).any((r) => r['name'] == c);

  // ───────────── القراءة ─────────────

  static Future<InvoiceRepairInfo?> load(DatabaseExecutor db, int invoiceId) async {
    final inv = await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (inv.isEmpty) return null;
    final i = inv.first;
    double cash = 0;
    if (await _hasTable(db, 'invoice_adjustments')) {
      final r = await db.rawQuery(
          "SELECT COALESCE(SUM(amount_delta), 0) AS s FROM invoice_adjustments WHERE invoice_id = ? AND settlement_payment_type = 'نقد'",
          [invoiceId]);
      cash = (r.first['s'] as num?)?.toDouble() ?? 0;
    }
    final total = (i['total_amount'] as num?)?.toDouble() ?? 0;
    final paid = (i['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0;
    final pt = (i['payment_type'] as String?) ?? 'نقد';
    final st = (i['status'] as String?) ?? '';
    final del = ((i['is_deleted'] as int?) ?? 0) == 1;
    final cid = i['customer_id'] as int?;
    double expected = 0;
    if (pt == 'دين' && !del && st != 'معلقة') {
      final r = total - paid - cash;
      expected = r > 0 ? r : 0;
    }

    final non = InvoiceDebtReconciler.nonContributionTypes;
    final rows = await db.rawQuery('''
      SELECT t.id, t.transaction_date AS d, t.amount_changed AS a, t.transaction_type AS ty, t.customer_id AS cid,
             c.name AS cname, COALESCE(t.description, t.transaction_note, '') AS descr
      FROM transactions t LEFT JOIN customers c ON c.id = t.customer_id
      WHERE t.invoice_id = ? AND COALESCE(t.is_deleted, 0) = 0
      ORDER BY t.transaction_date, t.id''', [invoiceId]);
    final txs = <InvoiceTx>[];
    final recorded = <int, double>{};
    final names = <int, String>{};
    for (final r in rows) {
      final c = r['cid'] as int?;
      final ty = '${r['ty'] ?? ''}';
      final a = (r['a'] as num?)?.toDouble() ?? 0;
      txs.add(InvoiceTx(r['id'] as int, '${r['d'] ?? ''}', a, ty, c, '${r['cname'] ?? '-'}', '${r['descr']}'));
      if (c == null || c == 0) continue;
      names[c] = '${r['cname'] ?? '#$c'}'.trim();
      if (non.contains(ty)) continue;
      recorded[c] = (recorded[c] ?? 0) + a;
    }
    if (cid != null && cid > 0 && !names.containsKey(cid)) {
      final c = await db.query('customers', columns: ['name'], where: 'id = ?', whereArgs: [cid], limit: 1);
      names[cid] = c.isEmpty ? '#$cid (غير موجود)' : '${c.first['name']}'.trim();
    }
    var exists = false;
    if (cid != null && cid > 0) {
      final e = await db.rawQuery('SELECT 1 FROM customers WHERE id = ? AND COALESCE(is_deleted, 0) = 0', [cid]);
      exists = e.isNotEmpty;
    }
    final balances = <int, double>{};
    for (final c in {...recorded.keys, if (cid != null && cid > 0) cid}) {
      balances[c] = await _balance(db, c);
    }
    return InvoiceRepairInfo(
      invoiceId: invoiceId,
      number: '${i['invoice_number'] ?? '#$invoiceId'}',
      customerId: cid,
      customerName: '${i['customer_name'] ?? ''}'.trim(),
      paymentType: pt,
      status: st,
      deleted: del,
      total: total,
      paid: paid,
      cashSettlements: cash,
      expected: expected,
      recorded: recorded,
      names: names,
      balances: balances,
      txs: txs,
      customerExists: exists,
    );
  }

  static Future<double> _balance(DatabaseExecutor db, int customerId) async {
    final r = await db.rawQuery(
        'SELECT COALESCE(SUM(amount_changed), 0) AS s FROM transactions WHERE customer_id = ? AND COALESCE(is_deleted, 0) = 0',
        [customerId]);
    return (r.first['s'] as num?)?.toDouble() ?? 0;
  }

  // ───────────── «اعتمد الفاتورة»: سجل الديون ← الفاتورة ─────────────

  /// يضبط سجل الديون على الفاتورة. يعيد رصيد كل عميل معني قبل وبعد.
  static Future<Map<int, (double, double)>> applyInvoiceTruth(Database db, int invoiceId, {required String user}) async {
    final result = <int, (double, double)>{};
    await db.transaction((txn) async {
      final before = await load(txn, invoiceId);
      if (before == null) throw StateError('الفاتورة غير موجودة');
      if (before.consistent) return;
      final block = before.invoiceTruthBlock;
      if (block != null) throw StateError(block);
      await InvoiceDebtReconciler.reconcileInvoice(txn, invoiceId,
          createMissing: true, allowNegativeBalance: true, reason: 'تصحيح من الفحص العميق — اعتماد الفاتورة');
      final after = await load(txn, invoiceId);
      if (after == null || !after.consistent) {
        // صف تسوية سابق لهذه الفاتورة محذوف (الحارس لا يعيد إحياءه) أو فاتورة مستلمة من جهاز آخر
        throw StateError('تعذّر ضبط سجل الديون على هذه الفاتورة تلقائياً (صف تسويتها أُبطل سابقاً، أو أنشأها جهاز آخر). '
            'لم يتغير شيء.');
      }
      for (final c in {...before.balances.keys, ...after.balances.keys}) {
        result[c] = (before.balances[c] ?? 0, after.balances[c] ?? await _balance(txn, c));
      }
    });
    await _audit('اعتماد الفاتورة', invoiceId, user, result.entries.map((e) => 'عميل ${e.key}: ${e.value.$1} ← ${e.value.$2}').join('، '));
    return result;
  }

  // ───────────── «اعتمد سجل الديون»: الفاتورة ← سجل الديون ─────────────

  /// يصحح خانتي «نقد/دين» و«المسدد» في الفاتورة لتطابق سجل الديون. لا يمس أي معاملة.
  static Future<({String type, double paid})> applyLedgerTruth(Database db, int invoiceId, {required String user}) async {
    late ({String type, double paid}) applied;
    late InvoiceRepairInfo was;
    await db.transaction((txn) async {
      final info = await load(txn, invoiceId);
      if (info == null) throw StateError('الفاتورة غير موجودة');
      final block = info.ledgerTruthBlock;
      if (block != null) throw StateError(block);
      was = info;
      applied = (type: info.newPaymentType, paid: info.newPaid);
      final values = <String, Object?>{
        'payment_type': applied.type,
        'amount_paid_on_invoice': applied.paid,
        'last_modified_at': DateTime.now().toIso8601String(),
      };
      if (await _hasCol(txn, 'invoices', 'amount_paid_cents')) values['amount_paid_cents'] = (applied.paid * 100).round();
      await txn.update('invoices', values, where: 'id = ?', whereArgs: [invoiceId]);
      if (await _hasCol(txn, 'invoices', 'version')) {
        await txn.rawUpdate(
            'UPDATE invoices SET version = COALESCE(version, 1) + 1, is_synced = 0 WHERE id = ?', [invoiceId]);
      }
      // الحارس المحاسبي يجب ألا يجد شيئاً يغيّره الآن — وإلا فالحساب لم يتطابق: يُلغى كل شيء
      final changed = await InvoiceDebtReconciler.reconcileInvoice(txn, invoiceId,
          createMissing: true, allowNegativeBalance: true, reason: 'تحقق بعد تصحيح الفاتورة');
      final after = await load(txn, invoiceId);
      if (changed || after == null || !after.consistent) {
        throw StateError('بعد تصحيح الفاتورة لم يتطابق الحساب — أُلغي التصحيح ولم يتغير شيء');
      }
    });
    await _audit('اعتماد سجل الديون', invoiceId, user,
        '${was.paymentType}/${was.paid} ← ${applied.type}/${applied.paid}');
    return applied;
  }

  // ───────────── «مُراجَعة» ─────────────

  static Future<void> _ensureAck(DatabaseExecutor db) => db.execute('''
      CREATE TABLE IF NOT EXISTS $ackTable (
        ref TEXT PRIMARY KEY,
        fingerprint TEXT NOT NULL,
        note TEXT,
        by_user TEXT,
        at TEXT NOT NULL
      )''');

  static Future<void> acknowledge(DatabaseExecutor db, InvoiceRepairInfo info, {required String user, String? note}) async {
    await _ensureAck(db);
    await db.insert(
      ackTable,
      {
        'ref': 'inv:${info.invoiceId}',
        'fingerprint': info.fingerprint,
        'note': note,
        'by_user': user,
        'at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _audit('مراجعة بلا تغيير', info.invoiceId, user, note ?? '');
  }

  /// الملاحظات المُراجَعة: ref ← البصمة وقت المراجعة. (قراءة فقط — لا ينشئ الجدول)
  static Future<Map<String, String>> acknowledged(DatabaseExecutor db) async {
    if (!await _hasTable(db, ackTable)) return const {};
    return {for (final r in await db.query(ackTable)) '${r['ref']}': '${r['fingerprint']}'};
  }

  static Future<void> _audit(String what, int invoiceId, String user, String details) async {
    try {
      await FinancialAuditService().logDataRepair('الفحص العميق — $what', 'فاتورة #$invoiceId بواسطة $user: $details');
    } catch (_) {}
  }
}
