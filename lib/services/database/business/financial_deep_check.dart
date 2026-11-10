// lib/services/database/business/financial_deep_check.dart
//
// 🔬 الفحص العميق — عند الطلب فقط، قراءة فقط.
//
// لا يضيف ولا يحذف ولا يعدّل أي صف: كل ما فيه SELECT. لا يُصلح شيئاً؛ يقول
// ما وجد وأين، والقرار لصاحب البرنامج.
//
// الفحوص الموجودة سابقاً تقارن «دين العميل المخزّن» بـ«مجموع معاملاته». هذا
// لا يكشف معاملة خاطئة: فاتورة دين بمئة ألف ومعاملاتها ثمانون ألفاً يبقى فيها
// الدين = المجموع. هنا نعيد الحساب من المصدر نفسه — الفاتورة — بالصيغة نفسها
// التي يحفظ بها البرنامج (InvoiceDebtReconciler):
//     مساهمة فاتورة الدين = الإجمالي − المسدد − التسويات النقدية (ولا تقل عن صفر)
//     مساهمة فاتورة النقد أو المحذوفة أو المعلّقة = صفر

import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'deep_check_repair.dart';
import 'invoice_debt_reconciler.dart';
import 'financial_black_box.dart';

enum DeepSeverity { error, warning, info }

class DeepFinding {
  DeepFinding(this.severity, this.area, this.title, this.explain,
      {this.rows = const [], this.total = 0, this.invoiceRefs = const []});
  final DeepSeverity severity;
  final String area;
  final String title;
  final String explain;
  final List<String> rows;
  final int total;

  /// لملاحظات الفواتير: معرّف الفاتورة لكل سطر (بالترتيب نفسه) — لزر «معالجة».
  final List<int> invoiceRefs;
}

class DeepCheckReport {
  DeepCheckReport(this.findings, this.passed, this.elapsed, this.at);
  final List<DeepFinding> findings;

  /// أسماء الفحوص التي مرّت بلا ملاحظة
  final List<String> passed;
  final Duration elapsed;
  final DateTime at;

  int get errors => findings.where((f) => f.severity == DeepSeverity.error).length;
  int get warnings => findings.where((f) => f.severity == DeepSeverity.warning).length;

  String asText() {
    final b = StringBuffer('🔬 الفحص العميق — ${at.toString().substring(0, 16)}\n');
    b.writeln('أخطاء: $errors — تنبيهات: $warnings — فحوص سليمة: ${passed.length}');
    for (final f in findings) {
      final tag = switch (f.severity) {
        DeepSeverity.error => '❌',
        DeepSeverity.warning => '⚠️',
        DeepSeverity.info => 'ℹ️',
      };
      b.writeln('\n$tag [${f.area}] ${f.title}');
      b.writeln(f.explain);
      for (final r in f.rows) {
        b.writeln('  • $r');
      }
      if (f.total > f.rows.length) b.writeln('  … و${f.total - f.rows.length} غيرها');
    }
    if (passed.isNotEmpty) {
      b.writeln('\n✅ سليم:');
      for (final p in passed) {
        b.writeln('  • $p');
      }
    }
    return b.toString().trimRight();
  }
}

class FinancialDeepCheck {
  FinancialDeepCheck(this.db);
  final DatabaseExecutor db;

  static const double _tol = 0.01;
  static const int _show = 40;

  final _findings = <DeepFinding>[];
  final _passed = <String>[];

  static final _fmt = NumberFormat('#,##0.##', 'en');
  static String m(num? v) => _fmt.format((v ?? 0).toDouble());

  Future<bool> _hasTable(String t) async =>
      (await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [t])).isNotEmpty;

  Future<bool> _hasCol(String t, String c) async =>
      (await db.rawQuery('PRAGMA table_info($t)')).any((r) => r['name'] == c);

  void _add(DeepSeverity s, String area, String title, String explain, List<String> rows, {List<int> refs = const []}) {
    _findings.add(DeepFinding(s, area, title, explain,
        rows: rows.take(_show).toList(), total: rows.length, invoiceRefs: refs.take(_show).toList()));
  }

  /// يشغّل كل الفحوص. [onStep] لعرض التقدّم.
  Future<DeepCheckReport> run({void Function(String step)? onStep}) async {
    final sw = Stopwatch()..start();
    final steps = <(String, Future<void> Function())>[
      ('أرصدة العملاء', _customerBalances),
      ('فواتير الدين مقابل سجل الديون', _invoiceContributions),
      ('صفوف تسوية مكررة', _duplicateAdjustments),
      ('معاملات بلا صاحب أو بلا فاتورة', _orphans),
      ('مبالغ الفواتير', _invoiceSanity),
      ('أرصدة الموردين', _supplierBalances),
      ('المخزون مقابل دفتر الحركات', _stock),
      ('الدفتر المحاسبي', _ledger),
      ('الصندوق الأسود', _blackBox),
    ];
    for (final (name, fn) in steps) {
      onStep?.call(name);
      try {
        await fn();
      } catch (e) {
        _add(DeepSeverity.warning, name, 'تعذّر إكمال هذا الفحص', 'الخطأ: $e — بقية الفحوص أُكملت.', const []);
      }
    }
    sw.stop();
    return DeepCheckReport(List.unmodifiable(_findings), List.unmodifiable(_passed), sw.elapsed, DateTime.now());
  }

  // ─── 1) دين العميل المخزّن = مجموع معاملاته الحيّة ───────────────────────
  final _mismatchedCustomers = <int, String>{};

  Future<void> _customerBalances() async {
    final rows = await db.rawQuery('''
      SELECT c.id, c.name, COALESCE(c.current_total_debt, 0) AS rec,
             COALESCE((SELECT SUM(t.amount_changed) FROM transactions t
                       WHERE t.customer_id = c.id AND COALESCE(t.is_deleted, 0) = 0), 0) AS calc
      FROM customers c WHERE COALESCE(c.is_deleted, 0) = 0''');
    final bad = <String>[];
    for (final r in rows) {
      final rec = (r['rec'] as num).toDouble(), calc = (r['calc'] as num).toDouble();
      if ((rec - calc).abs() > _tol) {
        _mismatchedCustomers[r['id'] as int] = '${r['name']}';
        bad.add('${r['name']}: المخزّن ${m(rec)} — مجموع المعاملات ${m(calc)} — الفرق ${m(rec - calc)}');
      }
    }
    if (bad.isEmpty) {
      _passed.add('دين كل عميل = مجموع معاملاته (${rows.length} عميل)');
    } else {
      _add(DeepSeverity.error, 'أرصدة العملاء', '${bad.length} عميل رصيده لا يساوي مجموع معاملاته',
          'الرقم الظاهر في سجل الديون غير مجموع الحركات. «الصندوق الأسود» أسفل التقرير يبيّن متى تغيّر.', bad);
    }
  }

  // ─── 2) كل فاتورة من هذا الجهاز: المتوقع من الفاتورة = المسجّل في سجل الديون ─
  Future<void> _invoiceContributions() async {
    final ph = List.filled(InvoiceDebtReconciler.nonContributionTypes.length, '?').join(',');
    final adj = await _hasTable('invoice_adjustments');
    final cash = adj
        ? "COALESCE((SELECT SUM(a.amount_delta) FROM invoice_adjustments a WHERE a.invoice_id = i.id AND a.settlement_payment_type = 'نقد'), 0)"
        : '0';
    final rows = await db.rawQuery('''
      SELECT i.id, i.invoice_number AS no, i.customer_id AS cid, i.customer_name AS cname,
             i.payment_type AS pt, COALESCE(i.is_deleted, 0) AS del, COALESCE(i.status, '') AS st,
             CASE WHEN i.payment_type = 'دين' AND COALESCE(i.is_deleted, 0) = 0 AND COALESCE(i.status, '') != 'معلقة'
                  THEN MAX(COALESCE(i.total_amount, 0) - COALESCE(i.amount_paid_on_invoice, 0) - $cash, 0)
                  ELSE 0 END AS expected,
             COALESCE((SELECT SUM(t.amount_changed) FROM transactions t
                       WHERE t.invoice_id = i.id AND t.customer_id = i.customer_id
                         AND COALESCE(t.is_deleted, 0) = 0
                         AND (t.transaction_type IS NULL OR t.transaction_type NOT IN ($ph))), 0) AS rec_cur,
             COALESCE((SELECT SUM(t.amount_changed) FROM transactions t
                       WHERE t.invoice_id = i.id AND (i.customer_id IS NULL OR t.customer_id != i.customer_id)
                         AND COALESCE(t.is_deleted, 0) = 0
                         AND (t.transaction_type IS NULL OR t.transaction_type NOT IN ($ph))), 0) AS rec_other
      FROM invoices i
      WHERE COALESCE(i.is_created_by_me, 1) = 1''',
        [...InvoiceDebtReconciler.nonContributionTypes, ...InvoiceDebtReconciler.nonContributionTypes]);

    final missing = <String>[], wrong = <String>[], ghost = <String>[], other = <String>[], noCustomer = <String>[];
    final rMissing = <int>[], rWrong = <int>[], rGhost = <int>[], rOther = <int>[], rNoCustomer = <int>[];
    // ملاحظات راجعها المدير وأبقاها كما هي: تُخفى ما دامت أرقامها لم تتغير
    final acks = await DeepCheckRepair.acknowledged(db);
    var hidden = 0;
    var checked = 0;
    for (final r in rows) {
      checked++;
      final id = r['id'] as int;
      final ack = acks['inv:$id'];
      if (ack != null) {
        final info = await DeepCheckRepair.load(db, id);
        if (info != null && info.fingerprint == ack) {
          hidden++;
          continue;
        }
      }
      final exp = (r['expected'] as num).toDouble();
      final cur = (r['rec_cur'] as num).toDouble();
      final oth = (r['rec_other'] as num).toDouble();
      final label = 'فاتورة ${r['no'] ?? '#${r['id']}'} — ${r['cname'] ?? 'بلا اسم'}';
      if (r['pt'] == 'دين' && r['del'] == 0 && r['st'] != 'معلقة' && exp > _tol &&
          (r['cid'] == null || (r['cid'] as int) <= 0)) {
        noCustomer.add('$label: دين ${m(exp)} بلا عميل مرتبط');
        rNoCustomer.add(id);
        continue;
      }
      if (exp > _tol && cur.abs() <= _tol) {
        missing.add('$label: المتوقع ${m(exp)} — في سجل الديون صفر');
        rMissing.add(id);
      } else if ((exp - cur).abs() > _tol) {
        if (exp.abs() <= _tol) {
          final why = r['del'] == 1
              ? 'محذوفة'
              : (r['st'] == 'معلقة' ? 'معلّقة' : (r['pt'] == 'دين' ? 'دين مسددة بالكامل على الفاتورة' : 'نقد'));
          ghost.add('$label ($why): ما زال لها في سجل الديون ${m(cur)}');
          rGhost.add(id);
        } else {
          wrong.add('$label: المتوقع ${m(exp)} — المسجّل ${m(cur)} — الفرق ${m(cur - exp)}');
          rWrong.add(id);
        }
      }
      if (oth.abs() > _tol) {
        other.add('$label: ${m(oth)} مسجّلة على عميل غير عميل الفاتورة');
        rOther.add(id);
      }
    }
    var any = false;
    if (missing.isNotEmpty) {
      any = true;
      _add(DeepSeverity.error, 'فواتير الدين', '${missing.length} فاتورة دين لم تصل إلى سجل الديون',
          'الفاتورة تقول إن على العميل مبلغاً، وسجل الديون لا يحمل منه شيئاً.', missing,
          refs: rMissing);
    }
    if (wrong.isNotEmpty) {
      any = true;
      _add(DeepSeverity.error, 'فواتير الدين', '${wrong.length} فاتورة مبلغها في سجل الديون غير المتبقي عليها',
          'المتبقي = الإجمالي − المسدد (− التسويات النقدية). الفرق الموجب = سجل الديون أكثر من الفاتورة.', wrong,
          refs: rWrong);
    }
    if (ghost.isNotEmpty) {
      any = true;
      _add(DeepSeverity.error, 'فواتير الدين', '${ghost.length} فاتورة لا يجب أن تحمل ديناً وما زال لها أثر',
          'فاتورة نقد أو محذوفة أو معلّقة أو دين مسددة بالكامل: مساهمتها صفر، وسجل الديون ما زال يحمل لها مبلغاً.',
          ghost,
          refs: rGhost);
    }
    if (other.isNotEmpty) {
      any = true;
      _add(DeepSeverity.error, 'فواتير الدين', '${other.length} فاتورة لها دين على عميل آخر',
          'غالباً بعد تغيير عميل الفاتورة: بقي أثرها على العميل السابق.', other,
          refs: rOther);
    }
    if (noCustomer.isNotEmpty) {
      any = true;
      _add(DeepSeverity.warning, 'فواتير الدين', '${noCustomer.length} فاتورة دين بلا عميل',
          'لا تظهر في حساب أي عميل.', noCustomer,
          refs: rNoCustomer);
    }
    if (!any) _passed.add('كل فواتير هذا الجهاز تطابق سجل الديون ($checked فاتورة)');
    if (hidden > 0) _passed.add('$hidden ملاحظة فاتورة راجعتها سابقاً وأبقيتها كما هي (مخفية ما دامت أرقامها لم تتغير)');
  }

  // ─── 3) صف تسوية واحد فقط لكل (فاتورة، عميل) ───────────────────────────
  Future<void> _duplicateAdjustments() async {
    final rows = await db.rawQuery('''
      SELECT t.invoice_id AS inv, t.customer_id AS cid, c.name AS name, COUNT(*) AS n, SUM(t.amount_changed) AS s
      FROM transactions t LEFT JOIN customers c ON c.id = t.customer_id
      WHERE t.transaction_type = ? AND COALESCE(t.is_deleted, 0) = 0 AND t.invoice_id IS NOT NULL
      GROUP BY t.invoice_id, t.customer_id
      HAVING SUM(CASE WHEN ABS(COALESCE(t.amount_changed, 0)) > 0.0001 THEN 1 ELSE 0 END) > 1''',
        [InvoiceDebtReconciler.adjustmentType]);
    if (rows.isEmpty) {
      _passed.add('لا صفوف تسوية مكررة لفاتورة واحدة');
      return;
    }
    _add(DeepSeverity.error, 'تكرار', '${rows.length} فاتورة لها أكثر من صف دين واحد للعميل نفسه',
        'أكثر من صف بمبلغ غير صفري لفاتورة واحدة وعميل واحد = دين قد يكون محسوباً مرتين '
            '(الصفوف الصفرية لا تُحسب: يتركها نقل الفاتورة بين العملاء على الأجهزة المستقبِلة).', [
      for (final r in rows) 'فاتورة #${r['inv']} — ${r['name'] ?? r['cid']}: ${r['n']} صفوف مجموعها ${m(r['s'] as num?)}'
    ]);
  }

  // ─── 4) معاملات بلا عميل حيّ أو بلا فاتورة موجودة ──────────────────────
  Future<void> _orphans() async {
    final noCust = await db.rawQuery('''
      SELECT t.customer_id AS cid, COUNT(*) AS n, SUM(t.amount_changed) AS s
      FROM transactions t LEFT JOIN customers c ON c.id = t.customer_id
      WHERE COALESCE(t.is_deleted, 0) = 0 AND (c.id IS NULL OR COALESCE(c.is_deleted, 0) = 1)
      GROUP BY t.customer_id''');
    final noInv = await db.rawQuery('''
      SELECT c.name AS name, t.invoice_id AS inv, t.amount_changed AS a, t.transaction_date AS d
      FROM transactions t LEFT JOIN invoices i ON i.id = t.invoice_id LEFT JOIN customers c ON c.id = t.customer_id
      WHERE COALESCE(t.is_deleted, 0) = 0 AND t.invoice_id IS NOT NULL AND i.id IS NULL''');
    if (noCust.isEmpty && noInv.isEmpty) {
      _passed.add('كل معاملة لها عميل حيّ، وكل معاملة فاتورة لها فاتورة موجودة');
      return;
    }
    if (noCust.isNotEmpty) {
      _add(DeepSeverity.warning, 'معاملات يتيمة', 'معاملات حيّة لعملاء محذوفين أو غير موجودين',
          'لا تدخل في أي رصيد ظاهر، ويحسبها الدفتر المحاسبي.', [
        for (final r in noCust) 'العميل #${r['cid']}: ${r['n']} معاملة مجموعها ${m(r['s'] as num?)}'
      ]);
    }
    if (noInv.isNotEmpty) {
      _add(DeepSeverity.warning, 'معاملات يتيمة', '${noInv.length} معاملة تشير إلى فاتورة غير موجودة',
          'المبلغ باقٍ في رصيد العميل، والفاتورة التي تفسّره غير موجودة.', [
        for (final r in noInv) '${r['name'] ?? '-'}: ${m(r['a'] as num?)} — فاتورة #${r['inv']} — ${'${r['d'] ?? ''}'.split('T').first}'
      ]);
    }
  }

  // ─── 5) مبالغ الفواتير المنطقية ─────────────────────────────────────────
  Future<void> _invoiceSanity() async {
    final rows = await db.rawQuery('''
      SELECT id, invoice_number AS no, customer_name AS cname, total_amount AS t, amount_paid_on_invoice AS p
      FROM invoices
      WHERE COALESCE(is_deleted, 0) = 0 AND payment_type = 'دين'
        AND (COALESCE(amount_paid_on_invoice, 0) < -0.01
             OR COALESCE(amount_paid_on_invoice, 0) > COALESCE(total_amount, 0) + 0.01)''');
    if (rows.isEmpty) {
      _passed.add('لا فاتورة دين مسددها سالب أو أكبر من إجمالها');
      return;
    }
    _add(DeepSeverity.warning, 'مبالغ الفواتير', '${rows.length} فاتورة دين مسددها خارج المنطق',
        'المسدد أكبر من الإجمالي أو سالب — مساهمتها في الدين تُحسب صفراً، فالزيادة لا تظهر في أي مكان.', [
      for (final r in rows) 'فاتورة ${r['no'] ?? '#${r['id']}'} — ${r['cname'] ?? ''}: الإجمالي ${m(r['t'] as num?)} — المسدد ${m(r['p'] as num?)}'
    ]);
  }

  // ─── 6) دين المورد = مجموع حركاته (لكل عملة) ───────────────────────────
  Future<void> _supplierBalances() async {
    if (!await _hasTable('suppliers') || !await _hasTable('supplier_transactions')) return;
    final usd = await _hasCol('suppliers', 'total_debt_usd');
    final rows = await db.rawQuery('''
      SELECT s.id, s.name, COALESCE(s.total_debt_iqd, 0) AS iqd, ${usd ? 'COALESCE(s.total_debt_usd, 0)' : '0'} AS usd,
        COALESCE((SELECT SUM(t.amount_changed) FROM supplier_transactions t WHERE t.supplier_id = s.id
                  AND COALESCE(t.is_deleted, 0) = 0 AND COALESCE(t.currency, 'IQD') = 'IQD'), 0) AS ciqd,
        COALESCE((SELECT SUM(t.amount_changed) FROM supplier_transactions t WHERE t.supplier_id = s.id
                  AND COALESCE(t.is_deleted, 0) = 0 AND t.currency = 'USD'), 0) AS cusd
      FROM suppliers s''');
    final bad = <String>[];
    for (final r in rows) {
      final a = (r['iqd'] as num).toDouble(), b = (r['ciqd'] as num).toDouble();
      final c = (r['usd'] as num).toDouble(), d = (r['cusd'] as num).toDouble();
      if ((a - b).abs() > _tol) bad.add('${r['name']}: دينار — المخزّن ${m(a)}، مجموع الحركات ${m(b)}');
      if (usd && (c - d).abs() > _tol) bad.add('${r['name']}: دولار — المخزّن ${m(c)}، مجموع الحركات ${m(d)}');
    }
    if (bad.isEmpty) {
      _passed.add('دين كل مورد = مجموع حركاته (${rows.length} مورد)');
    } else {
      _add(DeepSeverity.error, 'الموردون', '${bad.length} رصيد مورد لا يساوي مجموع حركاته', '', bad);
    }
  }

  // ─── 7) كمية المادة = دفتر حركات المخزون − المبيع ──────────────────────
  Future<void> _stock() async {
    if (!await _hasTable('stock_movements') || !await _hasCol('invoice_items', 'product_sync_uuid')) return;
    final rows = await db.rawQuery('''
      SELECT p.name, p.stock_quantity AS q,
        COALESCE((SELECT SUM(m.delta) FROM stock_movements m WHERE m.product_sync_uuid = p.sync_uuid
                    AND (m.kind != 'opening' OR m.movement_uuid = 'opening_' || p.sync_uuid)), 0)
        - COALESCE((SELECT SUM(CASE WHEN COALESCE(ii.quantity_large_unit, 0) > 0
                      THEN ii.quantity_large_unit * COALESCE(NULLIF(ii.units_in_large_unit, 0), 1)
                      ELSE COALESCE(ii.quantity_individual, 0) END)
                    FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
                    WHERE ii.product_sync_uuid = p.sync_uuid AND COALESCE(i.is_deleted, 0) = 0
                      AND COALESCE(i.status, '') != 'معلقة'), 0) AS calc
      FROM products p WHERE COALESCE(p.is_deleted, 0) = 0 AND p.sync_uuid IS NOT NULL
        AND EXISTS (SELECT 1 FROM stock_movements m0 WHERE m0.movement_uuid = 'opening_' || p.sync_uuid)''');
    final bad = <String>[];
    for (final r in rows) {
      final q = (r['q'] as num?)?.toDouble() ?? 0, c = (r['calc'] as num?)?.toDouble() ?? 0;
      if ((q - c).abs() > 0.001) bad.add('${r['name']}: الكمية ${m(q)} — حسب الحركات ${m(c)}');
    }
    if (bad.isEmpty) {
      _passed.add('كمية كل مادة لها دفتر حركات = حركاتها (${rows.length} مادة)');
    } else {
      _add(DeepSeverity.warning, 'المخزون', '${bad.length} مادة كميتها غير ما تقوله حركاتها',
          'الأثر على الأرباح والجرد، لا على الديون.', bad);
    }
  }

  // ─── 8) الدفتر المحاسبي: القيود متوازنة، والذمم = سجل الديون ───────────
  Future<void> _ledger() async {
    if (!await _hasTable('journal_lines') || !await _hasTable('journal_entries')) return;
    final unb = await db.rawQuery('''
      SELECT e.id, e.source_type AS st, SUM(l.debit) AS d, SUM(l.credit) AS c
      FROM journal_entries e JOIN journal_lines l ON l.entry_id = e.id
      GROUP BY e.id HAVING ABS(SUM(l.debit) - SUM(l.credit)) > 0.004''');
    final neg = await db.rawQuery('SELECT COUNT(*) AS n FROM journal_lines WHERE debit < 0 OR credit < 0');
    final problems = <String>[
      for (final r in unb) 'قيد #${r['id']} (${r['st']}): مدين ${m(r['d'] as num?)} ≠ دائن ${m(r['c'] as num?)}',
      if (((neg.first['n'] as num?) ?? 0) > 0) '${neg.first['n']} سطر قيد بمبلغ سالب',
    ];
    if (problems.isEmpty) {
      _passed.add('كل قيود الدفتر متوازنة');
    } else {
      _add(DeepSeverity.error, 'الدفتر المحاسبي', 'قيود غير متوازنة', '', problems);
    }
    if (!await _hasTable('accounts') || !await _hasCol('accounts', 'system_key')) return;
    final ar = await db.query('accounts', columns: ['id'], where: "system_key = 'ar_customers'", limit: 1);
    if (ar.isEmpty) return;
    final led = await db.rawQuery(
        'SELECT COALESCE(SUM(debit - credit), 0) AS b FROM journal_lines WHERE account_id = ?', [ar.first['id']]);
    final reg = await db.rawQuery('''
      SELECT COALESCE(SUM(t.amount_changed), 0) AS b FROM transactions t
      WHERE COALESCE(t.is_deleted, 0) = 0''');
    final diff = (led.first['b'] as num).toDouble() - (reg.first['b'] as num).toDouble();
    if (diff.abs() > 1) {
      _add(DeepSeverity.warning, 'الدفتر المحاسبي', 'ذمم العملاء في الدفتر تختلف عن سجل الديون بـ ${m(diff)}',
          'إن كان آخر ترحيل قديماً فهذا متوقع: اضغط «ترحيل الآن» في شاشة المحاسبة ثم أعد الفحص. '
              'إن بقي الفرق بعد الترحيل فهو فرق حقيقي.', const []);
    } else {
      _passed.add('ذمم العملاء في الدفتر = سجل الديون');
    }
  }

  // ─── 9) الصندوق الأسود: متى تغيّر دين العملاء غير المتطابقين ───────────
  Future<void> _blackBox() async {
    if (!await _hasTable(FinancialBlackBox.table)) {
      _add(DeepSeverity.info, 'الصندوق الأسود', 'غير مفعّل بعد', 'يبدأ التسجيل من أول تشغيل بعد هذا التحديث.', const []);
      return;
    }
    final first = await db.rawQuery('SELECT MIN(at) AS a, COUNT(*) AS n FROM ${FinancialBlackBox.table}');
    final since = '${first.first['a'] ?? '-'}'.replaceFirst('T', ' ');
    final rows = <String>[];
    for (final e in _mismatchedCustomers.entries.take(15)) {
      final log = await FinancialBlackBox.forCustomer(db, e.key, limit: 6);
      for (final l in log) {
        final at = '${l['at']}'.replaceFirst('T', ' ');
        switch (l['kind']) {
          case 'debt':
            final drift = ((l['new_value'] as num?) ?? 0) - ((l['tx_sum'] as num?) ?? 0);
            rows.add('${e.value} — $at: الدين ${m(l['old_value'] as num?)} ← ${m(l['new_value'] as num?)}'
                '${drift.abs() > _tol ? ' (مجموع المعاملات لحظتها ${m(l['tx_sum'] as num?)})' : ''}');
          case 'tx_change':
            rows.add('${e.value} — $at: معاملة ${m(l['old_value'] as num?)} ← ${m(l['new_value'] as num?)} (${l['note']})');
          case 'tx_delete':
            rows.add('${e.value} — $at: حُذفت نهائياً معاملة ${m(l['old_value'] as num?)} (${l['tx_type'] ?? '-'})');
        }
      }
    }
    final del = await db.rawQuery('''
      SELECT b.at, c.name, b.old_value AS a, b.tx_type AS ty, b.invoice_id AS inv
      FROM ${FinancialBlackBox.table} b LEFT JOIN customers c ON c.id = b.customer_id
      WHERE b.kind = 'tx_delete' ORDER BY b.id DESC LIMIT 200''');
    if (del.isNotEmpty) {
      _add(DeepSeverity.info, 'الصندوق الأسود', '${del.length} معاملة من هذا الجهاز حُذفت حذفاً نهائياً',
          'لم تُفقد: مبلغها وعميلها محفوظان في الصندوق الأسود. الحذف العادي في البرنامج لا يحذف نهائياً؛ '
              'هذا يحدث عند الاستعادة أو حذف عميل أو أداة إصلاح.', [
        for (final r in del)
          '${'${r['at']}'.replaceFirst('T', ' ')} — ${r['name'] ?? '-'}: ${m(r['a'] as num?)} (${r['ty'] ?? '-'})'
              '${r['inv'] == null ? '' : ' فاتورة #${r['inv']}'}'
      ]);
    }
    if (rows.isNotEmpty) {
      _add(DeepSeverity.info, 'الصندوق الأسود', 'آخر ما تغيّر في العملاء غير المتطابقين',
          'السجل يبدأ من $since. ما حدث قبله لا يظهر هنا.', rows);
    } else {
      _passed.add('الصندوق الأسود يعمل منذ $since (${first.first['n']} سطر)');
    }
  }
}
