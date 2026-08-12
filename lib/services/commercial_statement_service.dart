// services/commercial_statement_service.dart
// خدمة كشف الحساب التجاري - تجميع المعاملات المرتبطة بالفواتير
// 🔧 تم إصلاح جميع الأخطاء المكتشفة
import 'database_service.dart';

class CommercialStatementService {
  final DatabaseService _db = DatabaseService();

  /// جلب السنوات المتاحة للعميل (من أقدم فاتورة أو معاملة)
  Future<List<int>> getAvailableYears(int customerId) async {
    final db = await _db.database;

    // جلب السنوات من المعاملات
    final txYears = await db.rawQuery('''
      SELECT DISTINCT strftime('%Y', transaction_date) as year
      FROM transactions
      WHERE customer_id = ?
    ''', [customerId]);

    // جلب السنوات من الفواتير (بما فيها النقدية)
    final invYears = await db.rawQuery('''
      SELECT DISTINCT strftime('%Y', invoice_date) as year
      FROM invoices
      WHERE customer_id = ? AND status = 'محفوظة'
    ''', [customerId]);

    final allYears = <int>{};
    for (final r in txYears) {
      final y = int.tryParse(r['year']?.toString() ?? '');
      if (y != null && y > 0) allYears.add(y);
    }
    for (final r in invYears) {
      final y = int.tryParse(r['year']?.toString() ?? '');
      if (y != null && y > 0) allYears.add(y);
    }

    final sorted = allYears.toList()..sort();
    return sorted;
  }

  /// جلب كشف الحساب التجاري الكامل
  Future<Map<String, dynamic>> getCommercialStatement({
    required int customerId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await _db.database;

    // ═══════════════════════════════════════════════════════════════════════════
    // 1. جلب جميع الفواتير (دين ونقد) للعميل في الفترة
    // ═══════════════════════════════════════════════════════════════════════════
    String invoiceWhere = 'customer_id = ? AND status = ?';
    List<dynamic> invoiceArgs = [customerId, 'محفوظة'];

    if (startDate != null) {
      invoiceWhere += ' AND DATE(invoice_date) >= DATE(?)';
      invoiceArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      invoiceWhere += ' AND DATE(invoice_date) <= DATE(?)';
      invoiceArgs.add(endDate.toIso8601String());
    }

    final invoices = await db.query(
      'invoices',
      where: invoiceWhere,
      whereArgs: invoiceArgs,
      orderBy: 'invoice_date ASC, id ASC',
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // 2. جلب المعاملات اليدوية (غير مرتبطة بفاتورة)
    // ═══════════════════════════════════════════════════════════════════════════
    String txWhere = 'customer_id = ? AND invoice_id IS NULL';
    List<dynamic> txArgs = [customerId];

    if (startDate != null) {
      txWhere += ' AND DATE(transaction_date) >= DATE(?)';
      txArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      txWhere += ' AND DATE(transaction_date) <= DATE(?)';
      txArgs.add(endDate.toIso8601String());
    }

    final manualTx = await db.query(
      'transactions',
      where: txWhere,
      whereArgs: txArgs,
      orderBy: 'transaction_date ASC, id ASC',
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // 3. جلب المعاملات المرتبطة بفواتير (لتحسين الأداء - استعلام واحد)
    // ═══════════════════════════════════════════════════════════════════════════
    String invoiceTxWhere = 'customer_id = ? AND invoice_id IS NOT NULL';
    List<dynamic> invoiceTxArgs = [customerId];

    if (startDate != null) {
      invoiceTxWhere += ' AND DATE(transaction_date) >= DATE(?)';
      invoiceTxArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      invoiceTxWhere += ' AND DATE(transaction_date) <= DATE(?)';
      invoiceTxArgs.add(endDate.toIso8601String());
    }

    final allInvoiceTx = await db.query(
      'transactions',
      where: invoiceTxWhere,
      whereArgs: invoiceTxArgs,
      orderBy: 'transaction_date ASC, id ASC',
    );

    // تجميع المعاملات حسب invoice_id (لتحسين الأداء)
    final Map<int, List<Map<String, dynamic>>> txByInvoiceId = {};
    for (final tx in allInvoiceTx) {
      final invId = tx['invoice_id'] as int;
      txByInvoiceId.putIfAbsent(invId, () => []).add(tx);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // 4. جلب snapshots لجميع الفواتير (استعلام واحد لتحسين الأداء)
    // ═══════════════════════════════════════════════════════════════════════════
    final invoiceIds = invoices.map((inv) => inv['id'] as int).toList();
    final Map<int, List<Map<String, dynamic>>> snapshotsByInvoiceId = {};

    if (invoiceIds.isNotEmpty) {
      final placeholders = invoiceIds.map((_) => '?').join(',');
      final allSnapshots = await db.rawQuery(
        'SELECT * FROM invoice_snapshots WHERE invoice_id IN ($placeholders) ORDER BY created_at ASC',
        invoiceIds,
      );
      for (final snap in allSnapshots) {
        final invId = snap['invoice_id'] as int;
        snapshotsByInvoiceId.putIfAbsent(invId, () => []).add(snap);
      }
    }

    // جمع invoice_ids من الفواتير التي تم جلبها
    final fetchedInvoiceIds = invoiceIds.toSet();

    // ═══════════════════════════════════════════════════════════════════════════
    // 5. بناء قائمة السطور
    // ═══════════════════════════════════════════════════════════════════════════
    final List<Map<String, dynamic>> entries = [];

    // إضافة الفواتير
    for (final inv in invoices) {
      final invoiceId = inv['id'] as int;
      final invoiceDate = DateTime.parse(inv['invoice_date'] as String);
      final totalAmount = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
      final paymentType = inv['payment_type'] as String? ?? '';
      // 🔧 إصلاح خطأ 1: استخدام الحقل الصحيح amount_paid_on_invoice
      final amountPaidOnInvoice =
          (inv['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0.0;
      final createdAt = inv['created_at'] as String?;

      // جلب المعاملات المرتبطة بهذه الفاتورة من الـ cache
      final invoiceTx = txByInvoiceId[invoiceId] ?? [];

      // حساب صافي المبلغ من المعاملات الفعلية
      double netDebtAmount = 0.0;
      for (final tx in invoiceTx) {
        netDebtAmount += (tx['amount_changed'] as num?)?.toDouble() ?? 0.0;
      }

      // 🔧 إصلاح: إذا كانت فاتورة دين ولا توجد معاملات مرتبطة بها،
      // فهذا يعني أنها فاتورة قديمة لم يتم إنشاء معاملة لها
      if (paymentType == 'دين' && invoiceTx.isEmpty) {
        netDebtAmount = totalAmount - amountPaidOnInvoice;
      }

      // تحديد نوع الفاتورة ووصفها
      String description;
      String entryType;
      bool wasConverted = false;
      String? originalPaymentType;

      // جلب snapshots من الـ cache
      final snapshots = snapshotsByInvoiceId[invoiceId] ?? [];

      // 🔧 إصلاح خطأ 6: تحسين منطق اكتشاف التحويل
      String? originalPaymentTypeFromSnapshot;
      if (snapshots.isNotEmpty) {
        final firstSnapshot = snapshots.first;
        originalPaymentTypeFromSnapshot =
            firstSnapshot['payment_type'] as String?;
      }

      // إذا كانت الفاتورة نقد ولا توجد معاملات مرتبطة بها، فهي فاتورة نقدية حقيقية
      final bool isTrueCashInvoice =
          paymentType == 'نقد' && invoiceTx.isEmpty && netDebtAmount == 0;

      // فحص إذا تحولت من نقد إلى دين (مع التحقق من وجود snapshot)
      final bool convertedFromCashToDebt = paymentType == 'دين' &&
          originalPaymentTypeFromSnapshot == 'نقد' &&
          snapshots.isNotEmpty;

      // فحص إذا تحولت من دين إلى نقد
      final bool convertedFromDebtToCash =
          paymentType == 'نقد' && invoiceTx.isNotEmpty;

      if (isTrueCashInvoice) {
        description = 'فاتورة رقم #$invoiceId نقد';
        entryType = 'cash_invoice';
        netDebtAmount = 0;
      } else if (convertedFromDebtToCash) {
        description = 'فاتورة رقم #$invoiceId (تحولت لنقد)';
        entryType = 'converted_to_cash';
        wasConverted = true;
        originalPaymentType = 'دين';
      } else if (convertedFromCashToDebt) {
        description = 'فاتورة رقم #$invoiceId (تحولت لدين)';
        entryType = 'converted_to_debt';
        wasConverted = true;
        originalPaymentType = 'نقد';
      } else if (paymentType == 'دين') {
        description = 'فاتورة رقم #$invoiceId';
        entryType = 'debt_invoice';
      } else {
        // فاتورة نقد لكن لها معاملات (حالة غير متوقعة)
        description = 'فاتورة رقم #$invoiceId نقد';
        entryType = 'cash_invoice';
        netDebtAmount = 0;
      }

      entries.add({
        'date': invoiceDate,
        'description': description,
        'invoiceAmount': totalAmount,
        'netAmount': netDebtAmount,
        'debtBefore': 0.0,
        'debtAfter': 0.0,
        'type': entryType,
        'invoiceId': invoiceId,
        'paymentType': paymentType,
        'paidAmount': amountPaidOnInvoice,
        'wasConverted': wasConverted,
        'originalPaymentType': originalPaymentType,
        'createdAt': createdAt,
        'sortOrder': 0, // للترتيب الثانوي
      });
    }

    // إضافة المعاملات اليدوية
    for (final tx in manualTx) {
      final txDate = DateTime.parse(tx['transaction_date'] as String);
      final amount = (tx['amount_changed'] as num?)?.toDouble() ?? 0.0;
      final txType = tx['transaction_type'] as String? ?? '';
      final note = tx['transaction_note'] as String?;
      final txId = tx['id'] as int?;
      final createdAt = tx['created_at'] as String?;

      String description;
      if (txType == 'manual_payment') {
        description = 'دفعة نقدية (تسديد)';
      } else if (txType == 'manual_debt') {
        description = 'دين يدوي';
      } else if (txType == 'opening_balance') {
        description = 'رصيد سابق';
      } else {
        description = note ?? 'معاملة يدوية';
      }

      entries.add({
        'date': txDate,
        'description': description,
        'invoiceAmount': amount.abs(),
        'netAmount': amount,
        'debtBefore': 0.0,
        'debtAfter': 0.0,
        'type': 'manual_transaction',
        'invoiceId': null,
        'paymentType': null,
        'paidAmount': null,
        'transactionId': txId,
        'createdAt': createdAt,
        'sortOrder': 1, // المعاملات اليدوية بعد الفواتير في نفس اليوم
      });
    }

    // إضافة المعاملات المرتبطة بفواتير لم تظهر في قائمة الفواتير
    for (final tx in allInvoiceTx) {
      final invoiceId = tx['invoice_id'] as int?;
      // تخطي إذا كانت الفاتورة موجودة في القائمة
      if (invoiceId != null && fetchedInvoiceIds.contains(invoiceId)) {
        continue;
      }

      final txDate = DateTime.parse(tx['transaction_date'] as String);
      final amount = (tx['amount_changed'] as num?)?.toDouble() ?? 0.0;
      final note = tx['transaction_note'] as String?;
      final txId = tx['id'] as int?;
      final createdAt = tx['created_at'] as String?;

      String description = 'فاتورة #$invoiceId';
      if (note != null && note.isNotEmpty) {
        description += ' - $note';
      }

      entries.add({
        'date': txDate,
        'description': description,
        'invoiceAmount': amount.abs(),
        'netAmount': amount,
        'debtBefore': 0.0,
        'debtAfter': 0.0,
        // 🔧 إصلاح خطأ 4: تصنيف معاملات الفواتير اليتيمة بشكل صحيح
        'type': 'orphan_invoice_transaction',
        'invoiceId': invoiceId,
        'paymentType': null,
        'paidAmount': null,
        'transactionId': txId,
        'createdAt': createdAt,
        'sortOrder': 2,
      });
    }

    // 🔧 إصلاح خطأ 3: ترتيب حسب التاريخ ثم الترتيب الثانوي ثم وقت الإنشاء
    entries.sort((a, b) {
      final dateCompare =
          (a['date'] as DateTime).compareTo(b['date'] as DateTime);
      if (dateCompare != 0) return dateCompare;

      final sortOrderCompare =
          (a['sortOrder'] as int).compareTo(b['sortOrder'] as int);
      if (sortOrderCompare != 0) return sortOrderCompare;

      // ترتيب حسب وقت الإنشاء إذا كان متاحاً
      final aCreated = a['createdAt'] as String?;
      final bCreated = b['createdAt'] as String?;
      if (aCreated != null && bCreated != null) {
        return aCreated.compareTo(bCreated);
      }
      return 0;
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // 6. حساب الدين قبل والدين بعد لكل سطر
    // 🔧 إصلاح خطأ 2: حساب الرصيد الافتتاحي يشمل الفواتير القديمة
    // ═══════════════════════════════════════════════════════════════════════════
    double debtBeforePeriod = 0.0;
    if (startDate != null) {
      // حساب من المعاملات
      final txResult = await db.rawQuery('''
        SELECT COALESCE(SUM(amount_changed), 0) as total
        FROM transactions
        WHERE customer_id = ? AND DATE(transaction_date) < DATE(?)
      ''', [customerId, startDate.toIso8601String()]);
      debtBeforePeriod =
          (txResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // 🔧 إضافة: حساب ديون الفواتير القديمة التي ليس لها معاملات
      final oldInvoicesResult = await db.rawQuery('''
        SELECT 
          i.id,
          i.total_amount,
          i.amount_paid_on_invoice,
          i.payment_type,
          (SELECT COUNT(*) FROM transactions t WHERE t.invoice_id = i.id) as tx_count
        FROM invoices i
        WHERE i.customer_id = ? 
          AND i.status = 'محفوظة'
          AND i.payment_type = 'دين'
          AND DATE(i.invoice_date) < DATE(?)
      ''', [customerId, startDate.toIso8601String()]);

      for (final inv in oldInvoicesResult) {
        final txCount = (inv['tx_count'] as int?) ?? 0;
        if (txCount == 0) {
          // فاتورة قديمة بدون معاملات
          final total = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
          final paid =
              (inv['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0.0;
          debtBeforePeriod += (total - paid);
        }
      }
    }

    double runningDebt = debtBeforePeriod;
    for (final entry in entries) {
      entry['debtBefore'] = runningDebt;
      runningDebt += (entry['netAmount'] as num?)?.toDouble() ?? 0.0;
      entry['debtAfter'] = runningDebt;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // 7. حساب الملخص المفصل
    // ═══════════════════════════════════════════════════════════════════════════
    int totalDebtInvoices = 0;
    int totalCashInvoices = 0;
    int convertedToCash = 0;
    int convertedToDebt = 0;

    double invoiceDebts = 0.0;
    double manualDebts = 0.0;
    double invoicePayments = 0.0;
    double manualPayments = 0.0;

    for (final entry in entries) {
      final type = entry['type'] as String;
      final netAmount = (entry['netAmount'] as num?)?.toDouble() ?? 0.0;

      // حساب عدد الفواتير
      if (type == 'debt_invoice') {
        totalDebtInvoices++;
      } else if (type == 'cash_invoice') {
        totalCashInvoices++;
      } else if (type == 'converted_to_cash') {
        convertedToCash++;
      } else if (type == 'converted_to_debt') {
        convertedToDebt++;
      }

      // حساب الديون والمدفوعات
      if (type == 'debt_invoice' || type == 'converted_to_debt') {
        if (netAmount > 0) {
          invoiceDebts += netAmount;
        } else if (netAmount < 0) {
          invoicePayments += netAmount.abs();
        }
      } else if (type == 'converted_to_cash') {
        // فاتورة تحولت لنقد - المعاملات السالبة هي تسديد
        if (netAmount < 0) {
          invoicePayments += netAmount.abs();
        }
      } else if (type == 'orphan_invoice_transaction') {
        // 🔧 إصلاح خطأ 4: معاملات الفواتير اليتيمة تُحسب كديون فواتير
        if (netAmount > 0) {
          invoiceDebts += netAmount;
        } else if (netAmount < 0) {
          invoicePayments += netAmount.abs();
        }
      } else if (type == 'manual_transaction') {
        if (netAmount > 0) {
          manualDebts += netAmount;
        } else if (netAmount < 0) {
          manualPayments += netAmount.abs();
        }
      }
      // فواتير النقد (cash_invoice) لا تؤثر على الدين
    }

    // 🔧 إصلاح خطأ 8: إجمالي الفواتير يشمل جميع الأنواع
    final summary = {
      'totalDebtInvoices': totalDebtInvoices,
      'totalCashInvoices': totalCashInvoices,
      'convertedToCash': convertedToCash,
      'convertedToDebt': convertedToDebt,
      'totalInvoices': totalDebtInvoices +
          totalCashInvoices +
          convertedToCash +
          convertedToDebt,
      'invoiceDebts': invoiceDebts,
      'manualDebts': manualDebts,
      'totalDebts': invoiceDebts + manualDebts,
      'invoicePayments': invoicePayments,
      'manualPayments': manualPayments,
      'totalPayments': invoicePayments + manualPayments,
      'remainingBalance': runningDebt,
    };

    return {
      'entries': entries,
      'summary': summary,
      'finalBalance': runningDebt,
      'openingBalance': debtBeforePeriod,
    };
  }
}
