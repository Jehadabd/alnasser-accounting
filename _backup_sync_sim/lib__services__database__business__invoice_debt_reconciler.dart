// lib/services/database/business/invoice_debt_reconciler.dart
// ═══════════════════════════════════════════════════════════════════════════
// 🛡️ الحارس المحاسبي لمساهمة الفاتورة في دين العميل
// ═══════════════════════════════════════════════════════════════════════════
//
// قاعدة واحدة لا تقبل التأويل:
//
//     مساهمة الفاتورة في دين العميل = الإجمالي − المسدد   (لفواتير الدين)
//                                    = صفر                 (لفواتير النقد)
//
// هذه الدالة تحل محل الحالات الخمس التي كانت في InvoiceController
// (نقد←دين، دين←نقد، تغيير العميل، تعديل فاتورة دين، فاتورة جديدة).
//
// خاصيتان تجعلان الخطأ الحسابي مستحيلاً:
//
//   1) تقرأ حالة الفاتورة من قاعدة البيانات، لا من كائن في ذاكرة الشاشة.
//      فلا يهم إن كانت الشاشة تحمل نسخة قديمة من الفاتورة.
//
//   2) إدمبوتنت (Idempotent): تشغيلها مرة أو عشر مرات يعطي النتيجة نفسها،
//      لأنها تحتفظ بصف تسوية *واحد* لكل (فاتورة، عميل) وتضبط قيمته،
//      بدل أن تُراكم صفوفاً جديدة. فثلاث ضغطات حفظ = دين واحد، لا ثلاثة.
//
// معرّف صف التسوية اشتقاقي (recon_inv<id>_cus<id>) كي تتعرف عليه المزامنة
// على الأجهزة الأخرى فتُحدّثه بدل أن تُضاعفه.

import 'package:sqflite/sqflite.dart';

class InvoiceDebtReconciler {
  /// أنواع المعاملات التي لا تُعدّ جزءاً من مساهمة الفاتورة نفسها.
  /// هذه تسديدات وتصحيحات خارجية قد تكون مربوطة برقم الفاتورة، وإدخالها
  /// في الحساب يجعل الكود يظن أن الدين أقل مما هو، فيُلغي أثر التسديد.
  static const List<String> nonContributionTypes = <String>[
    'manual_payment',
    'return_payment',
    'correction',
    'opening_balance',
  ];

  /// نوع صف التسوية الذي تكتبه هذه الدالة. (يُعدّ مساهمة، فلا يُستثنى أعلاه)
  static const String adjustmentType = 'invoice_debt_sync';

  static String adjustmentUuid(int invoiceId, int customerId) =>
      'recon_inv${invoiceId}_cus$customerId';

  // ═══════════════════════════════════════════════════════════════════════
  // الدالة الرئيسية
  // ═══════════════════════════════════════════════════════════════════════

  /// توفّق مساهمة الفاتورة [invoiceId] مع معاملات الدين.
  ///
  /// [db] يقبل `Database` أو `Transaction` — فتعمل داخل معاملة قائمة أو خارجها.
  ///
  /// [createMissing] إن كانت `false` فلن تُنشئ ديناً لفاتورة ليس لها أي أثر
  /// محاسبي إطلاقاً (تُستخدم في شبكة الأمان عند العرض، حتى لا يظهر دين قديم
  /// فجأة على عميل ربما سدّد نقداً خارج البرنامج). وتبقى تُصلح المبالغ الخاطئة.
  /// [allowNegativeBalance] إن كانت `false` فلن تُطبَّق أي تسوية تجعل رصيد
  /// العميل سالباً. هذا ضروري في الوضع التلقائي: قد يكون دين فاتورة قديمة
  /// خاطئ لكن العميل سدّده بمعاملة يدوية، فحذف الدين وحده يترك التسديد معلّقاً
  /// ويجعل الرصيد سالباً. تلك الحالات تحتاج قرار المستخدم لا إصلاحاً صامتاً.
  static Future<bool> reconcileInvoice(
    DatabaseExecutor db,
    int invoiceId, {
    bool createMissing = true,
    bool allowNegativeBalance = true,
    String? reason,
  }) async {
    final invRows = await db.query(
      'invoices',
      columns: [
        'id',
        'customer_id',
        'total_amount',
        'amount_paid_on_invoice',
        'payment_type',
        'invoice_uuid',
      ],
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (invRows.isEmpty) return false;
    final inv = invRows.first;

    final int? currentCustomerId = inv['customer_id'] as int?;
    final double total = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
    final double paid =
        (inv['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0.0;
    final String paymentType = (inv['payment_type'] as String?) ?? 'نقد';
    final String? invoiceUuid = inv['invoice_uuid'] as String?;

    // 1) المساهمة المتوقعة لعميل الفاتورة الحالي
    //
    //    ملاحظة عن التسويات: insertInvoiceAdjustment يضيف amount_delta إلى
    //    total_amount مباشرة، والشاشة تعرض المتبقي على أنه
    //        الإجمالي (بعد التسويات) − (المسدد + التسويات النقدية)
    //    فنستخدم الصيغة نفسها هنا كي يتطابق سجل الديون مع ما يراه المستخدم.
    double expectedForCurrent = 0.0;
    if (paymentType == 'دين') {
      double cashSettlements = 0.0;
      try {
        final cashRows = await db.rawQuery(
          '''
          SELECT COALESCE(SUM(amount_delta), 0) AS total
          FROM invoice_adjustments
          WHERE invoice_id = ? AND settlement_payment_type = 'نقد'
          ''',
          [invoiceId],
        );
        cashSettlements = (cashRows.first['total'] as num?)?.toDouble() ?? 0.0;
      } catch (_) {
        // جدول التسويات غير موجود في نسخ قديمة — تجاهل
      }
      final double remaining = total - paid - cashSettlements;
      expectedForCurrent = remaining > 0 ? remaining : 0.0;
    }

    // 2) المساهمة المسجّلة فعلاً، لكل عميل على حدة.
    //    (التفصيل حسب العميل ضروري: عند تغيير عميل الفاتورة تبقى للعميل
    //     القديم معاملات يجب أن يعود مجموعها إلى صفر)
    final String ph = List.filled(nonContributionTypes.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT customer_id, COALESCE(SUM(amount_changed), 0) AS total
      FROM transactions
      WHERE invoice_id = ?
        AND (is_deleted IS NULL OR is_deleted = 0)
        AND (transaction_type IS NULL OR transaction_type NOT IN ($ph))
      GROUP BY customer_id
      ''',
      <Object?>[invoiceId, ...nonContributionTypes],
    );

    final Map<int, double> recorded = <int, double>{};
    for (final r in rows) {
      final cid = r['customer_id'] as int?;
      if (cid == null || cid == 0) continue;
      recorded[cid] = (r['total'] as num?)?.toDouble() ?? 0.0;
    }

    final Set<int> affected = <int>{...recorded.keys};
    if (currentCustomerId != null && currentCustomerId != 0) {
      affected.add(currentCustomerId);
    }

    bool changed = false;

    // 3) لكل عميل معنيّ: اضبط صف التسوية الواحد الخاص به
    for (final int customerId in affected) {
      final double expected =
          (customerId == currentCustomerId) ? expectedForCurrent : 0.0;

      final String adjUuid = adjustmentUuid(invoiceId, customerId);
      final adjRows = await db.query(
        'transactions',
        columns: ['id', 'amount_changed'],
        where:
            '(transaction_uuid = ? OR sync_uuid = ?) AND (is_deleted IS NULL OR is_deleted = 0)',
        whereArgs: [adjUuid, adjUuid],
        limit: 1,
      );

      final double adjAmount = adjRows.isEmpty
          ? 0.0
          : ((adjRows.first['amount_changed'] as num?)?.toDouble() ?? 0.0);

      // مساهمة المعاملات الأصلية وحدها (بعد استبعاد صف التسوية)
      final double others = (recorded[customerId] ?? 0.0) - adjAmount;
      final double needed = expected - others;

      if (adjRows.isEmpty) {
        // فاتورة بلا أي أثر محاسبي: لا نخترع ديناً إلا بطلب صريح
        if (!createMissing && others.abs() <= 0.01) continue;
        if (needed.abs() <= 0.01) continue;

        if (!allowNegativeBalance &&
            await _wouldGoNegative(db, customerId, needed - adjAmount)) {
          continue;
        }

        await _insertAdjustment(
          db,
          customerId: customerId,
          invoiceId: invoiceId,
          invoiceUuid: invoiceUuid,
          uuid: adjUuid,
          amount: needed,
          reason: reason,
        );
        changed = true;
      } else {
        if ((adjAmount - needed).abs() <= 0.01) continue;

        if (!allowNegativeBalance &&
            await _wouldGoNegative(db, customerId, needed - adjAmount)) {
          continue;
        }

        await db.update(
          'transactions',
          {
            'amount_changed': needed,
            'description': _describe(invoiceId, reason),
            'transaction_date': DateTime.now().toIso8601String(),
            'is_uploaded': 0,
          },
          where: 'id = ?',
          whereArgs: [adjRows.first['id']],
        );
        changed = true;
      }

      // 4) أعد بناء سلسلة الأرصدة ورصيد العميل من مجموع معاملاته
      await rebuildCustomerBalances(db, customerId);
    }

    return changed;
  }

  /// يوفّق كل فواتير العميل [customerId] (وكل فاتورة له عليها معاملات).
  /// يُستخدم كشبكة أمان قبل عرض سجل الديون.
  static Future<int> reconcileCustomerLedger(
    DatabaseExecutor db,
    int customerId, {
    bool createMissing = false,
    bool allowNegativeBalance = false,
    String? reason,
  }) async {
    final String ph = List.filled(nonContributionTypes.length, '?').join(',');

    // مرشّحون: فواتير العميل + أي فاتورة له عليها معاملة
    final candidates = await db.rawQuery(
      '''
      SELECT i.id AS id,
             CASE WHEN i.payment_type = 'دين'
                  THEN MAX(COALESCE(i.total_amount, 0)
                           - COALESCE(i.amount_paid_on_invoice, 0)
                           - COALESCE((SELECT SUM(a.amount_delta)
                                       FROM invoice_adjustments a
                                       WHERE a.invoice_id = i.id
                                         AND a.settlement_payment_type = 'نقد'), 0), 0)
                  ELSE 0 END AS expected,
             COALESCE((
               SELECT SUM(t.amount_changed) FROM transactions t
               WHERE t.invoice_id = i.id
                 AND t.customer_id = ?
                 AND (t.is_deleted IS NULL OR t.is_deleted = 0)
                 AND (t.transaction_type IS NULL OR t.transaction_type NOT IN ($ph))
             ), 0) AS recorded
      FROM invoices i
      WHERE i.customer_id = ?
         OR i.id IN (SELECT DISTINCT t2.invoice_id FROM transactions t2
                     WHERE t2.customer_id = ? AND t2.invoice_id IS NOT NULL)
      ''',
      <Object?>[customerId, ...nonContributionTypes, customerId, customerId],
    );

    int fixed = 0;
    for (final row in candidates) {
      final double expected = (row['expected'] as num?)?.toDouble() ?? 0.0;
      final double recorded = (row['recorded'] as num?)?.toDouble() ?? 0.0;
      if ((expected - recorded).abs() <= 0.01) continue;
      // لا نخترع ديناً لفاتورة بلا أثر محاسبي إطلاقاً
      if (!createMissing && recorded.abs() <= 0.01) continue;

      final ok = await reconcileInvoice(
        db,
        row['id'] as int,
        createMissing: createMissing,
        allowNegativeBalance: allowNegativeBalance,
        reason: reason,
      );
      if (ok) fixed++;
    }
    return fixed;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // مساعدات
  // ═══════════════════════════════════════════════════════════════════════

  /// المساهمة المسجّلة فعلاً لفاتورة على عميل بعينه (بعد استبعاد التسديدات
  /// والمحذوفات). تُستخدم في التحقق قبل الحفظ كي تطابق التحذيرات الواقع.
  static Future<double> recordedContribution(
    DatabaseExecutor db,
    int invoiceId,
    int customerId,
  ) async {
    final String ph = List.filled(nonContributionTypes.length, '?').join(',');
    final res = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount_changed), 0) AS total
      FROM transactions
      WHERE invoice_id = ?
        AND customer_id = ?
        AND (is_deleted IS NULL OR is_deleted = 0)
        AND (transaction_type IS NULL OR transaction_type NOT IN ($ph))
      ''',
      <Object?>[invoiceId, customerId, ...nonContributionTypes],
    );
    return (res.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// هل تجعل هذه التسوية رصيد العميل سالباً؟
  static Future<bool> _wouldGoNegative(
    DatabaseExecutor db,
    int customerId,
    double delta,
  ) async {
    final res = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_changed), 0) AS total FROM transactions '
      'WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
      [customerId],
    );
    final double current = (res.first['total'] as num?)?.toDouble() ?? 0.0;
    return (current + delta) < -0.01;
  }

  static String _describe(int invoiceId, String? reason) {
    final String suffix = (reason == null || reason.isEmpty) ? '' : ' — $reason';
    return 'تسوية مساهمة الفاتورة رقم $invoiceId$suffix';
  }

  static Future<void> _insertAdjustment(
    DatabaseExecutor db, {
    required int customerId,
    required int invoiceId,
    required String? invoiceUuid,
    required String uuid,
    required double amount,
    String? reason,
  }) async {
    final String now = DateTime.now().toIso8601String();
    await db.insert('transactions', {
      'customer_id': customerId,
      'transaction_date': now,
      'amount_changed': amount,
      // تُضبط فوراً في rebuildCustomerBalances
      'balance_before_transaction': 0.0,
      'new_balance_after_transaction': 0.0,
      'transaction_type': adjustmentType,
      'description': _describe(invoiceId, reason),
      'invoice_id': invoiceId,
      'invoice_sync_uuid': invoiceUuid,
      'transaction_uuid': uuid,
      'sync_uuid': uuid,
      'is_created_by_me': 1,
      'is_uploaded': 0,
      'is_deleted': 0,
      'created_at': now,
    });
  }

  /// يُعيد بناء عمودَي الرصيد التراكمي لكل معاملات العميل، ثم يضبط
  /// `current_total_debt` على مجموعها. بهذا تبقى المعادلة
  /// «رصيد العميل = مجموع معاملاته» صحيحة دائماً بعد أي تسوية.
  static Future<double> rebuildCustomerBalances(
    DatabaseExecutor db,
    int customerId,
  ) async {
    final txs = await db.query(
      'transactions',
      columns: ['id', 'amount_changed'],
      where: 'customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [customerId],
      orderBy: 'transaction_date ASC, id ASC',
    );

    double running = 0.0;
    for (final t in txs) {
      final double before = running;
      running += (t['amount_changed'] as num?)?.toDouble() ?? 0.0;
      await db.update(
        'transactions',
        {
          'balance_before_transaction': before,
          'new_balance_after_transaction': running,
        },
        where: 'id = ?',
        whereArgs: [t['id']],
      );
    }

    // ملاحظة: نكتب current_total_debt فقط (كما تفعل TransactionDao).
    // عمود current_total_debt_cents غير موجود في كل نسخ المخطط، وCustomer.fromMap
    // يعتمد على current_total_debt عند أي تعارض بينهما.
    await db.update(
      'customers',
      {
        'current_total_debt': running,
        'last_modified_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );

    return running;
  }
}
