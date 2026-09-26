// lib/services/database/business/supplier_debt_reconciler.dart
// ═══════════════════════════════════════════════════════════════════════════
// 🛡️ الحارس المحاسبي لديون الموردين
// ═══════════════════════════════════════════════════════════════════════════
//
// نفس المبدأ الذي أثبت نجاحه في سجل ديون العملاء:
//
//     دين المورد = مجموع حركاته   (لكل عملة على حدة)
//
// قبل هذا كان `total_debt_iqd` رقماً مخزّناً يُزاد ويُنقص بعمليات تراكمية،
// بلا أي دفتر يمكن التحقق منه. فلو انحرف لم يكن لأحد سبيل لاكتشافه.
//
// الآن لكل تغيير مالي على المورد سطر في `supplier_transactions`، والرصيد
// يُشتق من مجموعها. أي انحراف يُكتشف بجمع بسيط.
//
// ومساهمة فاتورة المشتريات في الدين تُدار بصف تسوية *واحد* لكل (فاتورة، مورد)
// بمعرّف اشتقاقي، فالدالة إدمبوتنت: عشر ضغطات حفظ = دين واحد لا عشرة.

import 'package:sqflite/sqflite.dart';

class SupplierDebtReconciler {
  /// أنواع الحركات التي لا تُعدّ جزءاً من مساهمة الفاتورة نفسها
  /// (دفعات وتسويات خارجية قد تكون مربوطة برقم الفاتورة).
  static const List<String> nonContributionTypes = <String>[
    'supplier_payment',
    'opening_balance',
    'correction',
  ];

  static const String adjustmentType = 'purchase_invoice_sync';
  static const String paymentType = 'supplier_payment';

  static String invoiceAdjustmentUuid(int invoiceId, int supplierId) =>
      'srecon_inv${invoiceId}_sup$supplierId';

  static String paymentUuid(int paymentId) => 'spay_$paymentId';

  // ═══════════════════════════════════════════════════════════════════════
  // 1) توفيق مساهمة فاتورة مشتريات
  // ═══════════════════════════════════════════════════════════════════════

  /// يجعل مساهمة الفاتورة [invoiceId] في دين المورد تساوي
  /// (الإجمالي − المدفوع) للفواتير المؤكدة، وصفراً لغيرها.
  ///
  /// إدمبوتنت: يحتفظ بصف تسوية واحد ويضبط قيمته بدل أن يُراكم صفوفاً.
  static Future<bool> reconcileInvoice(
    DatabaseExecutor db,
    int invoiceId, {
    String? reason,
  }) async {
    final rows = await db.query(
      'purchase_invoices',
      columns: [
        'id',
        'supplier_id',
        'total_amount',
        'paid_amount',
        'currency',
        'status',
        'invoice_number',
      ],
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final inv = rows.first;

    final int? supplierId = inv['supplier_id'] as int?;
    if (supplierId == null || supplierId == 0) return false;

    final double total = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
    final double paid = (inv['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final String currency = (inv['currency'] as String?) ?? 'IQD';
    final String status = (inv['status'] as String?) ?? 'draft';
    final String invNumber = (inv['invoice_number'] as String?) ?? '#$invoiceId';

    // فاتورة غير مؤكدة (مسوّدة أو ملغاة) لا تُنتج ديناً
    // ملاحظة: لا نقصّ الفرق عند صفر — الدفع الزائد على الفاتورة يعني أننا
    // دفعنا مقدماً، وهو رصيد حقيقي لنا عند المورد ولا يجوز أن يضيع.
    final double expected = (status == 'confirmed') ? (total - paid) : 0.0;

    final String uuid = invoiceAdjustmentUuid(invoiceId, supplierId);

    // ما هو مسجّل فعلاً لهذه الفاتورة على هذا المورد (بلا الدفعات)
    final String ph = List.filled(nonContributionTypes.length, '?').join(',');
    final recRows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount_changed), 0) AS total
      FROM supplier_transactions
      WHERE invoice_id = ?
        AND supplier_id = ?
        AND (is_deleted IS NULL OR is_deleted = 0)
        AND (transaction_type IS NULL OR transaction_type NOT IN ($ph))
      ''',
      <Object?>[invoiceId, supplierId, ...nonContributionTypes],
    );
    final double recorded = (recRows.first['total'] as num?)?.toDouble() ?? 0.0;

    final adjRows = await db.query(
      'supplier_transactions',
      columns: ['id', 'amount_changed'],
      where:
          'transaction_uuid = ? AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [uuid],
      limit: 1,
    );
    final double adjAmount = adjRows.isEmpty
        ? 0.0
        : ((adjRows.first['amount_changed'] as num?)?.toDouble() ?? 0.0);

    final double others = recorded - adjAmount;
    final double needed = expected - others;

    final String desc = reason == null || reason.isEmpty
        ? 'فاتورة مشتريات $invNumber'
        : 'فاتورة مشتريات $invNumber — $reason';

    bool changed = false;
    if (adjRows.isEmpty) {
      if (needed.abs() > 0.01) {
        await _insert(
          db,
          supplierId: supplierId,
          amount: needed,
          currency: currency,
          type: adjustmentType,
          description: desc,
          invoiceId: invoiceId,
          uuid: uuid,
        );
        changed = true;
      }
    } else {
      if ((adjAmount - needed).abs() > 0.01) {
        if (needed.abs() <= 0.01) {
          // لم تعد هناك مساهمة: صفّر الصف بدل حذفه (يحفظ الأثر للتدقيق)
          await db.update(
            'supplier_transactions',
            {'amount_changed': 0.0, 'description': '$desc (أُلغيت المساهمة)'},
            where: 'id = ?',
            whereArgs: [adjRows.first['id']],
          );
        } else {
          await db.update(
            'supplier_transactions',
            {
              'amount_changed': needed,
              'currency': currency,
              'description': desc,
            },
            where: 'id = ?',
            whereArgs: [adjRows.first['id']],
          );
        }
        changed = true;
      }
    }

    if (changed) {
      await rebuildSupplierBalances(db, supplierId);
    }
    return changed;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 2) تسجيل دفعة لمورد
  // ═══════════════════════════════════════════════════════════════════════

  /// يسجّل دفعة كحركة سالبة في دفتر المورد. إدمبوتنت بمعرّف الدفعة:
  /// استدعاؤها مرتين لنفس الدفعة لا يخصم المبلغ مرتين.
  ///
  /// لا يوجد `clamp` هنا عمداً: الدفع الزائد يجعل الرصيد سالباً — أي أن
  /// المورد صار مديناً لنا، وهذه حقيقة محاسبية لا يجوز محوها.
  static Future<void> recordPayment(
    DatabaseExecutor db, {
    required int paymentId,
    required int supplierId,
    required double amount,
    required String currency,
    int? invoiceId,
    String? description,
    String? date,
  }) async {
    final String uuid = paymentUuid(paymentId);
    final existing = await db.query(
      'supplier_transactions',
      columns: ['id'],
      where: 'transaction_uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );

    if (existing.isEmpty) {
      await _insert(
        db,
        supplierId: supplierId,
        amount: -amount.abs(),
        currency: currency,
        type: paymentType,
        description: description ?? 'سند دفع للمورد',
        invoiceId: invoiceId,
        paymentId: paymentId,
        uuid: uuid,
        date: date,
      );
    } else {
      await db.update(
        'supplier_transactions',
        {
          'amount_changed': -amount.abs(),
          'currency': currency,
          'description': description ?? 'سند دفع للمورد',
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }

    await rebuildSupplierBalances(db, supplierId);
  }

  /// يلغي أثر دفعة محذوفة (حذف منطقي يحفظ الأثر).
  static Future<void> voidPayment(
    DatabaseExecutor db, {
    required int paymentId,
    required int supplierId,
  }) async {
    await db.update(
      'supplier_transactions',
      {'is_deleted': 1},
      where: 'transaction_uuid = ?',
      whereArgs: [paymentUuid(paymentId)],
    );
    await rebuildSupplierBalances(db, supplierId);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 3) إعادة بناء أرصدة المورد من دفتره
  // ═══════════════════════════════════════════════════════════════════════

  /// يُعيد بناء سلسلة الأرصدة لكل عملة، ثم يضبط أعمدة المورد:
  /// `total_debt_iqd` و`total_debt_usd` = مجموع الحركات لكل عملة،
  /// و`total_invoices` و`total_payments` = عدّادات مشتقّة لا تراكمية.
  static Future<void> rebuildSupplierBalances(
    DatabaseExecutor db,
    int supplierId,
  ) async {
    final Map<String, double> running = <String, double>{};

    final txs = await db.query(
      'supplier_transactions',
      columns: ['id', 'amount_changed', 'currency'],
      where: 'supplier_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [supplierId],
      orderBy: 'transaction_date ASC, id ASC',
    );

    for (final t in txs) {
      final String cur = (t['currency'] as String?) ?? 'IQD';
      final double before = running[cur] ?? 0.0;
      final double after =
          before + ((t['amount_changed'] as num?)?.toDouble() ?? 0.0);
      running[cur] = after;
      await db.update(
        'supplier_transactions',
        {'balance_before': before, 'balance_after': after},
        where: 'id = ?',
        whereArgs: [t['id']],
      );
    }

    final double iqd = running['IQD'] ?? 0.0;
    final double usd = running['USD'] ?? 0.0;

    // عدّادات مشتقّة: العدّاد التراكمي القديم كان يزيد ولا ينقص أبداً
    int invoiceCount = 0;
    int paymentCount = 0;
    try {
      final r1 = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM purchase_invoices WHERE supplier_id = ? AND status = 'confirmed'",
        [supplierId],
      );
      invoiceCount = (r1.first['c'] as num?)?.toInt() ?? 0;
    } catch (_) {}
    try {
      final r2 = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM supplier_payments WHERE supplier_id = ?',
        [supplierId],
      );
      paymentCount = (r2.first['c'] as num?)?.toInt() ?? 0;
    } catch (_) {}

    await db.update(
      'suppliers',
      {
        'total_debt_iqd': iqd,
        'total_debt_usd': usd,
        // نُبقي current_balance متزامناً مع دين الدينار للتوافق مع
        // الشاشات القديمة التي تقرأه (hasDebt وغيرها)
        'current_balance': iqd,
        'total_invoices': invoiceCount,
        'total_payments': paymentCount,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [supplierId],
    );
  }

  /// يوفّق كل فواتير المورد — شبكة أمان تُستدعى قبل عرض كشف حسابه.
  static Future<int> reconcileSupplierLedger(
    DatabaseExecutor db,
    int supplierId, {
    String? reason,
  }) async {
    int fixed = 0;
    try {
      final invoices = await db.query(
        'purchase_invoices',
        columns: ['id'],
        where: 'supplier_id = ?',
        whereArgs: [supplierId],
      );
      for (final inv in invoices) {
        final ok = await reconcileInvoice(db, inv['id'] as int, reason: reason);
        if (ok) fixed++;
      }
      if (fixed == 0) {
        // حتى بلا تغيير، اضبط الأعمدة المشتقّة (قد تكون قديمة)
        await rebuildSupplierBalances(db, supplierId);
      }
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ تعذّرت تسوية دفتر المورد $supplierId: $e');
    }
    return fixed;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // مساعدات
  // ═══════════════════════════════════════════════════════════════════════

  static Future<void> _insert(
    DatabaseExecutor db, {
    required int supplierId,
    required double amount,
    required String currency,
    required String type,
    required String description,
    required String uuid,
    int? invoiceId,
    int? paymentId,
    String? date,
  }) async {
    final String now = DateTime.now().toIso8601String();
    await db.insert('supplier_transactions', {
      'supplier_id': supplierId,
      'transaction_date': date ?? now,
      'amount_changed': amount,
      'currency': currency,
      // تُضبط فوراً في rebuildSupplierBalances
      'balance_before': 0.0,
      'balance_after': 0.0,
      'transaction_type': type,
      'description': description,
      'invoice_id': invoiceId,
      'payment_id': paymentId,
      'transaction_uuid': uuid,
      'is_deleted': 0,
      'created_at': now,
    });
  }
}
