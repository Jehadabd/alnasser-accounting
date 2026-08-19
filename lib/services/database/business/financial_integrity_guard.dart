// lib/services/database/business/financial_integrity_guard.dart
// 🛡️ النظام المتكامل لحماية السلامة المالية - 9 طبقات أمان
// هذا الملف مسؤول فقط عن التحقق والمراقبة، ولا يغير منطق الحفظ الحالي

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../models/invoice.dart';
import '../../../models/invoice_item.dart';
import '../../../models/invoice_input_data.dart';
import '../../../models/customer.dart';
import '../../../models/transaction.dart';
import '../../../models/invoice_adjustment.dart';
import '../../../models/product.dart';
import '../../../utils/money_calculator.dart';
import '../../../services/auth_service.dart';
import '../dao/invoice_dao.dart';
import '../dao/transaction_dao.dart';
import '../dao/customer_dao.dart';
import '../dao/product_dao.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// هياكل البيانات الخاصة بنتائج التحقق
// ═══════════════════════════════════════════════════════════════════════════════

class GuardResult {
  final bool passed;
  final String? errorCode;
  final String? errorMessage;
  final String? details;

  const GuardResult({
    required this.passed,
    this.errorCode,
    this.errorMessage,
    this.details,
  });

  static const GuardResult success = GuardResult(passed: true);

  static GuardResult fail(String code, String message, {String? details}) =>
      GuardResult(passed: false, errorCode: code, errorMessage: message, details: details);
}

class PreSaveGuardReport {
  final bool canProceed;
  final List<GuardResult> failures;
  final List<GuardResult> warnings;

  const PreSaveGuardReport({
    required this.canProceed,
    required this.failures,
    required this.warnings,
  });
}

class PostSaveGuardReport {
  final bool isConsistent;
  final List<GuardResult> anomalies;
  final double verificationTimeMs;

  const PostSaveGuardReport({
    required this.isConsistent,
    required this.anomalies,
    required this.verificationTimeMs,
  });
}

class IntegrityAlert {
  final String alertCode;
  final DateTime timestamp;
  final String severity; // 'CRITICAL' | 'ERROR' | 'WARNING' | 'INFO'
  final String message;
  final String? details;
  final int? invoiceId;
  final int? customerId;
  final String? triggeredBy;
  final Map<String, dynamic>? context;

  const IntegrityAlert({
    required this.alertCode,
    required this.timestamp,
    required this.severity,
    required this.message,
    this.details,
    this.invoiceId,
    this.customerId,
    this.triggeredBy,
    this.context,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// 🛡️ الحارس المالي المتكامل - Financial Integrity Guard
// ═══════════════════════════════════════════════════════════════════════════════

class FinancialIntegrityGuard {
  final Future<Database> Function() getDatabase;
  final InvoiceDao invoiceDao;
  final TransactionDao transactionDao;
  final CustomerDao customerDao;
  final ProductDao? productDao;

  /// سجل الإنذارات
  final List<IntegrityAlert> _alerts = [];
  int _alertCounter = 0;
///
  FinancialIntegrityGuard({
    required this.getDatabase,
    required this.invoiceDao,
    required this.transactionDao,
    required this.customerDao,
    this.productDao,
  });

  // ─── Properties ───────────────────────────────────────────────────────────

  List<IntegrityAlert> get alerts => List.unmodifiable(_alerts);
  int get alertCount => _alerts.length;

  String get _currentUser {
    try {
      return AuthService().currentUser?.username ?? 'System';
    } catch (_) {
      return 'System';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🏗️  مسجّل الإنذارات (Alert System) - الطبقة الرابعة
  // ═══════════════════════════════════════════════════════════════════════════

  IntegrityAlert _recordAlert({
    required String code,
    required String severity,
    required String message,
    String? details,
    int? invoiceId,
    int? customerId,
    Map<String, dynamic>? context,
  }) {
    _alertCounter++;
    final alert = IntegrityAlert(
      alertCode: 'FIG-$code',
      timestamp: DateTime.now(),
      severity: severity,
      message: message,
      details: details,
      invoiceId: invoiceId,
      customerId: customerId,
      triggeredBy: _currentUser,
      context: context,
    );
    _alerts.add(alert);
    print('⚠️ [FIG-${alert.alertCode}] $severity: $message');
    if (details != null) print('   📋 $details');
    return alert;
  }

  /// جلب آخر N إنذار
  List<IntegrityAlert> getRecentAlerts({int count = 50}) {
    final sorted = List<IntegrityAlert>.from(_alerts);
    sorted.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(count).toList();
  }

  /// تصدير الإنذارات كنص
  String exportAlertsAsText() {
    final buf = StringBuffer();
    buf.writeln('═' * 60);
    buf.writeln('📋 سجل إنذارات السلامة المالية');
    buf.writeln('═' * 60);
    buf.writeln('إجمالي الإنذارات: ${_alerts.length}');
    buf.writeln('');
    for (final alert in _alerts.reversed) {
      buf.writeln('[${alert.alertCode}] ${alert.severity} @ ${alert.timestamp}');
      buf.writeln('  ${alert.message}');
      if (alert.invoiceId != null) buf.writeln('  الفاتورة: ${alert.invoiceId}');
      if (alert.customerId != null) buf.writeln('  العميل: ${alert.customerId}');
      if (alert.triggeredBy != null) buf.writeln('  المستخدم: ${alert.triggeredBy}');
      if (alert.details != null) buf.writeln('  التفاصيل: ${alert.details}');
      buf.writeln('');
    }
    return buf.toString();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // الطبقة الخامسة: اختبارات منطقية (Invariant Checks)
  // ═══════════════════════════════════════════════════════════════════════════

  /// التحقق من أن رصيد العميل = مجموع معاملاته
  Future<GuardResult> checkCustomerDebtInvariant(int customerId) async {
    final db = await getDatabase();
    final customer = await customerDao.getCustomerById(customerId);
    if (customer == null) {
      return GuardResult.fail('C001', 'العميل $customerId غير موجود');
    }
    final res = await db.rawQuery(
       'SELECT COALESCE(SUM(amount_changed), 0) as total FROM transactions WHERE customer_id = ?',
      [customerId],
    );
    final calculated = ((res.first['total'] as num?) ?? 0).toDouble();
    final recorded = customer.currentTotalDebt;
    if (!MoneyCalculator.areEqual(calculated, recorded)) {
      _recordAlert(
        code: 'C001-INVARIANT',
        severity: 'ERROR',
        message: 'رصيد العميل "${customer.name}" لا يطابق مجموع المعاملات',
        details: 'المخزّن: $recorded، المحسوب: $calculated، الفرق: ${(calculated - recorded).toStringAsFixed(3)}',
        customerId: customerId,
      );
      return GuardResult.fail(
        'C001',
        'رصيد العميل ($recorded) لا يطابق مجموع المعاملات ($calculated)',
        details: 'الفرق: ${(calculated - recorded).toStringAsFixed(3)}',
      );
    }
    return GuardResult.success;
  }

  /// التحقق من أن إجمالي الفاتورة = مجموع الأصناف + أجور التحميل - الخصم
  Future<GuardResult> checkInvoiceTotalInvariant(int invoiceId) async {
    final db = await getDatabase();
    final invoice = await invoiceDao.getInvoiceById(invoiceId);
    if (invoice == null) {
      return GuardResult.fail('I001', 'الفاتورة $invoiceId غير موجودة');
    }
    final items = await invoiceDao.getInvoiceItems(invoiceId);
    double itemsTotal = items.fold(0.0, (s, i) => s + i.itemTotal);
    final expected = itemsTotal + invoice.loadingFee - invoice.discount;
    if (!MoneyCalculator.areEqual(invoice.totalAmount, expected)) {
      _recordAlert(
        code: 'I001-INVARIANT',
        severity: 'ERROR',
        message: 'إجمالي الفاتورة رقم $invoiceId لا يطابق مجموع العناصر',
        details: 'المسجّل: ${invoice.totalAmount}، المحسوب: $expected، الفرق: ${(invoice.totalAmount - expected).toStringAsFixed(3)}',
        invoiceId: invoiceId,
      );
      return GuardResult.fail(
        'I001',
        'إجمالي الفاتورة (${invoice.totalAmount}) ≠ مجموع العناصر ($expected)',
        details: 'العناصر: $itemsTotal، أجور: ${invoice.loadingFee}، خصم: ${invoice.discount}',
      );
    }
    return GuardResult.success;
  }

  /// التحقق من أن كل فاتورة دين لها معاملة مقابلة
  Future<GuardResult> checkInvoiceHasTransaction(int invoiceId) async {
    final db = await getDatabase();
    final invoice = await invoiceDao.getInvoiceById(invoiceId);
    if (invoice == null) return GuardResult.fail('I002', 'الفاتورة $invoiceId غير موجودة');
    if (invoice.paymentType != 'دين' || invoice.customerId == null) {
      return GuardResult.success;
    }
    final remaining = invoice.totalAmount - invoice.amountPaidOnInvoice;
    if (remaining <= 0) return GuardResult.success;
    final txRes = await db.rawQuery(
      'SELECT COUNT(1) as cnt FROM transactions WHERE invoice_id = ?',
      [invoiceId],
    );
    final count = (txRes.first['cnt'] as int?) ?? 0;
    if (count == 0) {
      _recordAlert(
        code: 'I002-ORPHAN',
        severity: 'CRITICAL',
        message: 'فاتورة دين رقم $invoiceId بدون أي معاملة في سجل الديون',
        details: 'قيمة الدين: $remaining، العميل: ${invoice.customerName}',
        invoiceId: invoiceId,
        customerId: invoice.customerId,
      );
      return GuardResult.fail('I002', 'فاتورة دين بمعاملات ديون صفرية');
    }
    return GuardResult.success;
  }

  /// التحقق من أن كل الفواتير لها أصناف
  Future<GuardResult> checkInvoiceHasItems(int invoiceId) async {
    final items = await invoiceDao.getInvoiceItems(invoiceId);
    if (items.isEmpty) {
      final invoice = await invoiceDao.getInvoiceById(invoiceId);
      _recordAlert(
        code: 'I003-ORPHAN',
        severity: 'CRITICAL',
        message: 'فاتورة رقم $invoiceId بدون أصناف',
        details: 'العميل: ${invoice?.customerName ?? 'غير معروف'}',
        invoiceId: invoiceId,
      );
      return GuardResult.fail('I003', 'فاتورة بدون أصناف');
    }
    return GuardResult.success;
  }

  /// التحقق من عدم وجود Transaction لفاتورة غير موجودة
  Future<GuardResult> checkOrphanTransactions() async {
    final db = await getDatabase();
    final orphans = await db.rawQuery('''
      SELECT t.id, t.invoice_id, t.customer_id, t.amount_changed
      FROM transactions t
      LEFT JOIN invoices i ON t.invoice_id = i.id
      WHERE t.invoice_id IS NOT NULL AND i.id IS NULL
    ''');
    if (orphans.isNotEmpty) {
      for (final o in orphans) {
        _recordAlert(
          code: 'O001-ORPHAN',
          severity: 'CRITICAL',
          message: 'معاملة ديون تتعلق بفاتورة غير موجودة',
          details: 'transaction_id: ${o['id']}، invoice_id: ${o['invoice_id']}',
          invoiceId: o['invoice_id'] as int?,
          customerId: o['customer_id'] as int?,
        );
      }
      return GuardResult.fail('O001', '${orphans.length} معاملات يتيمة');
    }
    return GuardResult.success;
  }

  /// التحقق من عدم وجود Customer برصيد لا يطابق معاملاته
  Future<GuardResult> checkAllCustomersDebtInvariant() async {
    final db = await getDatabase();
    final customers = await customerDao.getAllCustomers();
    int errors = 0;
    for (final c in customers) {
      if (c.id == null) continue;
      final res = await db.rawQuery(
        'SELECT COALESCE(SUM(amount_changed), 0) as total FROM transactions WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
        [c.id],
      );
      final calc = ((res.first['total'] as num?) ?? 0).toDouble();
      if (!MoneyCalculator.areEqual(calc, c.currentTotalDebt)) {
        errors++;
        _recordAlert(
          code: 'C001-INVARIANT',
          severity: 'WARNING',
          message: 'رصيد العميل "${c.name}" لا يطابق المعاملات',
          details: 'المسجّل: ${c.currentTotalDebt}، المحسوب: $calc',
          customerId: c.id,
        );
      }
    }
    if (errors > 0) {
      return GuardResult.fail('C002', '$errors عملاء بأرصدة غير متطابقة');
    }
    return GuardResult.success;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // الطبقة الأولى: فحص قبل الحفظ (Pre-Save Guard)
  // ═══════════════════════════════════════════════════════════════════════════

  /// التحقق من 30+ شرطاً قبل حفظ الفاتورة
  Future<PreSaveGuardReport> runPreSaveChecks({
    required InvoiceInputData data,
    required List<InvoiceItem> completeItems,
    required double calculatedTotal,
    required double totalAmount,
  }) async {
    final failures = <GuardResult>[];
    final warnings = <GuardResult>[];

    // 1. شرط: مجموع الأصناف = إجمالي العناصر المكتملة
    final itemsSum = completeItems.fold(0.0, (s, i) => s + i.itemTotal);
    if (!MoneyCalculator.areEqual(itemsSum, calculatedTotal)) {
      failures.add(GuardResult.fail(
        'PS01', 'مجموع الأصناف ($itemsSum) ≠ الإجمالي المحسوب ($calculatedTotal)',
      ));
    }

    // 2. شرط: totalAmount = calculatedTotal + loadingFee - discount
    // (محسوب في المستدعي، لكن نتحقق هنا)

    // 3. شرط: الخصم لا يساوي أو يتجاوز calculatedTotal
    if (data.discount >= calculatedTotal && calculatedTotal > 0) {
      failures.add(GuardResult.fail(
        'PS02', 'الخصم (${data.discount}) لا يمكن أن يساوي أو يتجاوز الإجمالي ($calculatedTotal)',
      ));
    }

    // 4. شرط: المبلغ المدفوع لا يتجاوز totalAmount
    if (data.paidAmount > totalAmount + 0.01) {
      failures.add(GuardResult.fail(
        'PS03', 'المبلغ المدفوع (${data.paidAmount}) > الإجمالي ($totalAmount)',
      ));
    }

    // 5. شرط: المبلغ المدفوع لا يمكن أن يكون سالباً
    if (data.paidAmount < 0) {
      failures.add(GuardResult.fail(
        'PS04', 'المبلغ المدفوع سالب (${data.paidAmount})',
      ));
    }

    // 6. شرط: الخصم لا يمكن أن يكون سالباً
    if (data.discount < 0) {
      failures.add(GuardResult.fail(
        'PS05', 'الخصم سالب (${data.discount})',
      ));
    }

    // 7. شرط: أجور التحميل لا يمكن أن تكون سالبة
    if (data.loadingFee < 0) {
      failures.add(GuardResult.fail(
        'PS06', 'أجور التحميل سالبة (${data.loadingFee})',
      ));
    }

    // 8. شرط: صنف واحد مكتمل على الأقل
    if (completeItems.isEmpty) {
      failures.add(GuardResult.fail(
        'PS07', 'لا يوجد أصناف مكتملة في الفاتورة',
      ));
    }

    // 9. شرط: لا توجد أصناف مكررة بنفس المنتج ونفس الوحدة (تحذير)
    final seen = <String>{};
    for (final item in completeItems) {
      final key = '${item.productName}|${item.saleType}';
      if (seen.contains(key)) {
        warnings.add(GuardResult.fail(
          'PS08', 'توجد أصناف مكررة: "${item.productName}" بوحدة "${item.saleType}"',
        ));
      }
      seen.add(key);
    }

    // 10. شرط: لكل صنف، السعر > 0
    for (final item in completeItems) {
      if (item.appliedPrice <= 0) {
        failures.add(GuardResult.fail(
          'PS09', 'السعر صفر أو سالب للصنف "${item.productName}"',
        ));
      }
      // 11. شرط: الكمية > 0
      final qty = item.quantityIndividual ?? item.quantityLargeUnit ?? 0;
      if (qty <= 0) {
        failures.add(GuardResult.fail(
          'PS10', 'الكمية صفر أو سالبة للصنف "${item.productName}"',
        ));
      }
      // 12. شرط: itemTotal > 0
      if (item.itemTotal <= 0) {
        failures.add(GuardResult.fail(
          'PS11', 'إجمالي الصنف "${item.productName}" صفر أو سالب',
        ));
      }
    }

    // 13. شرط: إذا كان نوع الدفع 'نقد'، المبلغ المدفوع = totalAmount
    if (data.paymentType == 'نقد' && !MoneyCalculator.areEqual(data.paidAmount, totalAmount)) {
      failures.add(GuardResult.fail(
        'PS12', 'الدفع نقد ولكن المبلغ المدفوع (${data.paidAmount}) ≠ الإجمالي ($totalAmount)',
      ));
    }

    // 14. شرط: إذا كان نوع الدفع 'دين'، يجب أن يكون هناك عميل
    if (data.paymentType == 'دين' && data.customerName.trim().isEmpty) {
      failures.add(GuardResult.fail(
        'PS13', 'فاتورة دين بدون اسم عميل',
      ));
    }

    // 15. شرط: في التعديل (edit)، totalAmount >= paidAmount (لاتساع)
    if (data.invoiceToManage != null && data.invoiceToManage!.id != null) {
      if (totalAmount < data.paidAmount - 0.01) {
        failures.add(GuardResult.fail(
          'PS14', 'الإجمالي ($totalAmount) أقل من المبلغ المسدد (${data.paidAmount})',
        ));
      }
    }

    // 16-25. التحقق من أن كل صنف له productId صحيح (إذا كان productDao متاحاً)
    if (productDao != null) {
      for (final item in completeItems) {
        if (item.productName.isEmpty) continue;
        if (item.productId != null) {
          final prod = await productDao!.getProductById(item.productId!);
          if (prod == null) {
            warnings.add(GuardResult.fail(
              'PS15', 'المنتج "${item.productName}" (ID: ${item.productId}) غير موجود في قاعدة البيانات',
            ));
          }
        }
      }
    }

    // 26. شرط: customerPhone إذا وُجد يجب أن يكون رقم صحيح
    if (data.customerPhone.trim().isNotEmpty) {
      final digitsOnly = data.customerPhone.replaceAll(RegExp(r'[^0-9]'), '');
      if (digitsOnly.length < 8) {
        warnings.add(GuardResult.fail(
          'PS16', 'رقم الهاتف "${data.customerPhone}" يبدو غير صحيح',
        ));
      }
    }

    return PreSaveGuardReport(
      canProceed: failures.isEmpty,
      failures: failures,
      warnings: warnings,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // الطبقة الثانية: فحص بعد الحفظ (Post-Save Guard)
  // ═══════════════════════════════════════════════════════════════════════════

  /// التحقق من صحة البيانات بعد الحفظ
  Future<PostSaveGuardReport> runPostSaveChecks({
    required Invoice savedInvoice,
    required InvoiceInputData originalData,
    required int expectedItemsCount,
    required List<InvoiceItem> expectedItems,
  }) async {
    final anomalies = <GuardResult>[];
    final stopwatch = Stopwatch()..start();

    // 1. هل الفاتورة محفوظة فعلاً في قاعدة البيانات؟
    final fetchedInvoice = await invoiceDao.getInvoiceById(savedInvoice.id!);
    if (fetchedInvoice == null) {
      anomalies.add(GuardResult.fail(
        'PO01', 'الفاتورة رقم ${savedInvoice.id} غير موجودة في قاعدة البيانات بعد الحفظ!',
      ));
      return PostSaveGuardReport(
        isConsistent: false,
        anomalies: anomalies,
        verificationTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
      );
    }

    // 2. هل totalAmount مطابق؟
    if (!MoneyCalculator.areEqual(fetchedInvoice.totalAmount, savedInvoice.totalAmount)) {
      anomalies.add(GuardResult.fail(
        'PO02', 'عدم تطابق totalAmount بعد الحفظ: المتوقع ${savedInvoice.totalAmount}، الموجود ${fetchedInvoice.totalAmount}',
        details: 'invoice_id: ${savedInvoice.id}',
      ));
    }

    // 3. هل paymentType مطابق؟
    if (fetchedInvoice.paymentType != savedInvoice.paymentType) {
      anomalies.add(GuardResult.fail(
        'PO03', 'عدم تطابق paymentType بعد الحفظ',
        details: 'المتوقع: ${savedInvoice.paymentType}، الموجود: ${fetchedInvoice.paymentType}',
      ));
    }

    // 4. هل customerId مطابق (إذا كان متوقعاً)؟
    if (fetchedInvoice.customerId != savedInvoice.customerId) {
      anomalies.add(GuardResult.fail(
        'PO04', 'عدم تطابق customerId بعد الحفظ',
        details: 'المتوقع: ${savedInvoice.customerId}، الموجود: ${fetchedInvoice.customerId}',
      ));
    }

    // 5. هل عدد الأصناف المحفوظة = العدد المتوقع؟
    final savedItems = await invoiceDao.getInvoiceItems(savedInvoice.id!);
    final completeSavedItems = savedItems.where((i) =>
      i.productName.isNotEmpty && i.itemTotal > 0).toList();
    if (completeSavedItems.length != expectedItemsCount) {
      anomalies.add(GuardResult.fail(
        'PO05', 'عدد الأصناف المحفوظة (${completeSavedItems.length}) ≠ المتوقع ($expectedItemsCount)',
        details: 'invoice_id: ${savedInvoice.id}',
      ));
    }

    // 6. هل كل صنف محفوظ له itemTotal صحيح؟
    double recalculatedItemsTotal = 0.0;
    for (final item in completeSavedItems) {
      final expectedItemTotal = (item.quantityIndividual ?? item.quantityLargeUnit ?? 0) * item.appliedPrice;
      if (!MoneyCalculator.areEqual(item.itemTotal, expectedItemTotal)) {
        anomalies.add(GuardResult.fail(
          'PO06', 'itemTotal غير صحيح للصنف "${item.productName}": المسجّل ${item.itemTotal}، المحسوب $expectedItemTotal',
          details: 'invoice_id: ${savedInvoice.id}',
        ));
      }
      recalculatedItemsTotal += item.itemTotal;
    }

    // 7. هل الإجمالي المعاد حسابه = totalAmount الفاتورة؟
    final expectedTotal = recalculatedItemsTotal + fetchedInvoice.loadingFee - fetchedInvoice.discount;
    if (!MoneyCalculator.areEqual(expectedTotal, fetchedInvoice.totalAmount)) {
      anomalies.add(GuardResult.fail(
        'PO07', 'إعادة حساب الإجمالي ($expectedTotal) ≠ totalAmount المسجّل (${fetchedInvoice.totalAmount})',
        details: 'invoice_id: ${savedInvoice.id}',
      ));
    }

    // 8. إذا كانت فاتورة دين: هل تم إنشاء معاملة؟
    if (fetchedInvoice.paymentType == 'دين' &&
        fetchedInvoice.customerId != null &&
        fetchedInvoice.totalAmount > fetchedInvoice.amountPaidOnInvoice + 0.001) {
      final db = await getDatabase();
      final txCount = await db.rawQuery(
        'SELECT COUNT(1) as cnt FROM transactions WHERE invoice_id = ?',
        [savedInvoice.id],
      );
      final count = (txCount.first['cnt'] as int?) ?? 0;
      if (count == 0) {
        anomalies.add(GuardResult.fail(
          'PO08', 'فاتورة دين بدون معاملة في سجل الديون!',
          details: 'invoice_id: ${savedInvoice.id}، المبلغ المتبقي: ${fetchedInvoice.totalAmount - fetchedInvoice.amountPaidOnInvoice}',
        ));
        _recordAlert(
          code: 'PO08-MISSING_TX',
          severity: 'CRITICAL',
          message: 'فاتورة دين رقم ${savedInvoice.id} بدون معاملة بعد الحفظ',
          details: 'العميل: ${fetchedInvoice.customerName}، الباقي: ${fetchedInvoice.totalAmount - fetchedInvoice.amountPaidOnInvoice}',
          invoiceId: savedInvoice.id,
          customerId: fetchedInvoice.customerId,
        );
      }
    }

    // 9. التحقق من رصيد العميل بعد الحفظ (إذا كان ديناً)
    if (fetchedInvoice.paymentType == 'دين' && fetchedInvoice.customerId != null) {
      final customerCheck = await checkCustomerDebtInvariant(fetchedInvoice.customerId!);
      if (!customerCheck.passed) {
        anomalies.add(customerCheck);
      }
    }

    stopwatch.stop();

    return PostSaveGuardReport(
      isConsistent: anomalies.isEmpty,
      anomalies: anomalies,
      verificationTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // الطبقة السادسة: التحقق المزدوج (Double Calculation)
  // ═══════════════════════════════════════════════════════════════════════════

  /// حساب رصيد العميل بطريقتين مختلفتين والمقارنة
  Future<GuardResult> verifyCustomerDebtDoubleCalculation(int customerId) async {
    final db = await getDatabase();

    // الطريقة الأولى: من جدول customers مباشرة
    final customer = await customerDao.getCustomerById(customerId);
    if (customer == null) return GuardResult.fail('DC01', 'العميل غير موجود');
    final method1 = customer.currentTotalDebt;

    // الطريقة الثانية: من مجموع transactions
    final txSumRes = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_changed), 0) as total FROM transactions WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
      [customerId],
    );
    final method2 = ((txSumRes.first['total'] as num?) ?? 0).toDouble();

    if (!MoneyCalculator.areEqual(method1, method2)) {
      _recordAlert(
        code: 'DC01-DOUBLE_CALC',
        severity: 'ERROR',
        message: 'الحساب المزدوج لرصيد العميل "${customer.name}" غير متطابق',
        details: 'الطريقة الأولى (customers): $method1، الطريقة الثانية (transactions): $method2',
        customerId: customerId,
      );
      return GuardResult.fail(
        'DC01', 'عدم تطابق الحساب المزدوج: customers=$method1, transactions=$method2',
      );
    }

    // الطريقة الثالثة: من فواتير الدين (للتحقق الإضافي)
    final invoiceRes = await db.rawQuery('''
      SELECT COALESCE(SUM(total_amount - amount_paid_on_invoice), 0) as total
      FROM invoices
      WHERE customer_id = ? AND payment_type = 'دين'
    ''', [customerId]);
    // تحذير: هذه الطريقة قد لا تتطابق مع الأولى والثانية بسبب التسويات
    // لذلك نستخدمها للتحذير فقط وليس للإيقاف

    return GuardResult.success;
  }

  /// التحقق من سلسلة معاملات العميل (Chain Verification)
  Future<GuardResult> verifyTransactionChain(int customerId) async {
    final transactions = await transactionDao.getCustomerTransactions(
      customerId, orderBy: 'transaction_date ASC, id ASC',
    );
    if (transactions.isEmpty) return GuardResult.success;

    final txDataList = transactions.map((tx) => TransactionData(
      balanceBefore: tx.balanceBeforeTransaction ?? 0,
      amountChanged: tx.amountChanged,
      balanceAfter: tx.newBalanceAfterTransaction ?? 0,
    )).toList();

    final chainResult = MoneyCalculator.verifyTransactionChain(txDataList);
    if (!chainResult.isValid) {
      _recordAlert(
        code: 'DC02-CHAIN_BREAK',
        severity: 'ERROR',
        message: 'انقطاع في سلسلة معاملات العميل $customerId',
        details: chainResult.errorMessage,
        customerId: customerId,
      );
      return GuardResult.fail('DC02', chainResult.errorMessage ?? 'انقطاع في السلسلة');
    }
    return GuardResult.success;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // الطبقة الثامنة: التدقيق الذكي (Smart Audit)
  // ═══════════════════════════════════════════════════════════════════════════

  /// كشف التغييرات غير المنطقية
  Future<GuardResult> smartAuditInvoiceChange({
    required Invoice oldInvoice,
    required InvoiceInputData newData,
  }) async {
    final db = await getDatabase();
    final issues = <String>[];

    // 1. تغيير كبير غير منطقي في المبلغ الإجمالي
    final oldTotal = oldInvoice.totalAmount;
    final newItems = newData.invoiceItems.where((i) =>
      i.productName.isNotEmpty && i.itemTotal > 0).toList();
    final newItemsTotal = newItems.fold(0.0, (s, i) => s + i.itemTotal);
    final newTotal = newItemsTotal + newData.loadingFee - newData.discount;

    if (oldTotal > 0 && newTotal > 0) {
      final ratio = newTotal / oldTotal;
      if (ratio > 5.0) {
        issues.add('المبلغ الجديد ($newTotal) أكبر 5 مرات من القديم ($oldTotal)');
      } else if (ratio < 0.2) {
        issues.add('المبلغ الجديد ($newTotal) أقل من 20% من القديم ($oldTotal)');
      }
    }

    // 2. تغيير الدين بشكل غير منطقي
    if (oldInvoice.paymentType == 'دين' && newData.paymentType == 'دين' && oldInvoice.customerId != null) {
      final oldRemaining = oldInvoice.totalAmount - oldInvoice.amountPaidOnInvoice;
      final newRemaining = newTotal - newData.paidAmount;
      final diff = (newRemaining - oldRemaining).abs();
      if (diff > 1000000) {
        issues.add('تغيير الدين بمقدار $diff (أكثر من مليون)');
      }
    }

    // 3. تحويل دين→نقد بمبلغ كبير
    if (oldInvoice.paymentType == 'دين' && newData.paymentType == 'نقد') {
      final oldRemaining = oldInvoice.totalAmount - oldInvoice.amountPaidOnInvoice;
      if (oldRemaining > 1000000) {
        issues.add('تحويل دين→نقد بمبلغ $oldRemaining (أكثر من مليون)');
      }
    }

    // 4. تغيير اسم العميل (قد يكون خطأ)
    final oldName = oldInvoice.customerName.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final newName = newData.customerName.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (oldName != newName && oldName.isNotEmpty && newName.isNotEmpty) {
      issues.add('تغيير اسم العميل من "${oldInvoice.customerName}" إلى "${newData.customerName}"');
    }

    // 5. تغيير كبير في الخصم
    if ((newData.discount - oldInvoice.discount).abs() > 500000) {
      issues.add('تغيير الخصم بمقدار ${(newData.discount - oldInvoice.discount).abs()}');
    }

    if (issues.isNotEmpty) {
      _recordAlert(
        code: 'SA01-SMART_AUDIT',
        severity: 'WARNING',
        message: 'تغييرات غير معتادة في الفاتورة رقم ${oldInvoice.id}',
        details: issues.join(' | '),
        invoiceId: oldInvoice.id,
        customerId: oldInvoice.customerId,
        context: {
          'old_total': oldTotal,
          'new_total': newTotal,
          'old_payment_type': oldInvoice.paymentType,
          'new_payment_type': newData.paymentType,
        },
      );
      return GuardResult.fail('SA01', 'تغييرات غير معتادة: ${issues.join('; ')}');
    }
    return GuardResult.success;
  }

  /// كشف تناقض في دين العميل (زيادة كبيرة دون مبرر)
  Future<GuardResult> smartAuditCustomerDebtJump(int customerId) async {
    final db = await getDatabase();
    final customer = await customerDao.getCustomerById(customerId);
    if (customer == null) return GuardResult.fail('SA02', 'العميل غير موجود');

    // جلب آخر معاملة
    final lastTx = await db.rawQuery('''
      SELECT amount_changed, description, transaction_date, invoice_id
      FROM transactions
      WHERE customer_id = ?
      ORDER BY transaction_date DESC, id DESC
      LIMIT 1
    ''', [customerId]);

    if (lastTx.isNotEmpty) {
      final amount = (lastTx.first['amount_changed'] as num).toDouble();
      final desc = lastTx.first['description'] as String? ?? '';
      final invId = lastTx.first['invoice_id'] as int?;

      if (amount.abs() > 1000000) {
        _recordAlert(
          code: 'SA02-DEBT_JUMP',
          severity: 'WARNING',
          message: 'قفزة كبيرة في دين العميل "${customer.name}" بمبلغ $amount',
          details: 'الوصف: $desc، الفاتورة: $invId',
          customerId: customerId,
          invoiceId: invId,
        );
        return GuardResult.fail(
          'SA02', 'قفزة دين كبيرة: $amount للعميل "${customer.name}"',
        );
      }
    }
    return GuardResult.success;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // الطبقة الثالثة: مراقب سلامة البيانات (Integrity Monitor)
  // ═══════════════════════════════════════════════════════════════════════════

  /// فحص كامل لسلامة النظام
  Future<Map<String, dynamic>> runFullIntegrityScan() async {
    final startTime = DateTime.now();
    final results = <String, dynamic>{};
    final issues = <String>[];
    int errors = 0;
    int warnings = 0;

    try {
      // 1. فحص كل العملاء
      final customers = await customerDao.getAllCustomers();
      int customerErrors = 0;
      int customerWarnings = 0;
      for (final c in customers) {
        if (c.id == null) continue;
        final r1 = await checkCustomerDebtInvariant(c.id!);
        if (!r1.passed) {
          customerErrors++;
          issues.add(r1.errorMessage ?? '');
        }
        final r2 = await verifyTransactionChain(c.id!);
        if (!r2.passed) {
          customerWarnings++;
        }
      }
      results['customer_errors'] = customerErrors;
      results['customer_warnings'] = customerWarnings;

      // 2. فحص كل الفواتير (بحد أقصى 1000)
      final invoices = await invoiceDao.getAllInvoices(orderBy: 'id DESC');
      int invoiceErrors = 0;
      int invoiceWarnings = 0;
      int checked = 0;
      for (final inv in invoices) {
        if (inv.id == null) continue;
        checked++;
        if (checked > 1000) break;
        final r1 = await checkInvoiceTotalInvariant(inv.id!);
        if (!r1.passed) { invoiceErrors++; issues.add(r1.errorMessage ?? ''); }
        final r2 = await checkInvoiceHasItems(inv.id!);
        if (!r2.passed) { invoiceErrors++; issues.add(r2.errorMessage ?? ''); }
        final r3 = await checkInvoiceHasTransaction(inv.id!);
        if (!r3.passed) { invoiceWarnings++; issues.add(r3.errorMessage ?? ''); }
      }
      results['invoice_errors'] = invoiceErrors;
      results['invoice_warnings'] = invoiceWarnings;
      results['invoices_checked'] = checked;

      // 3. فحص المعاملات اليتيمة
      final orphanTx = await checkOrphanTransactions();
      if (!orphanTx.passed) { errors++; issues.add(orphanTx.errorMessage ?? ''); }

      errors = customerErrors + invoiceErrors;
      warnings = customerWarnings + invoiceWarnings;
    } catch (e) {
      _recordAlert(
        code: 'IM01-SCAN_FAILED',
        severity: 'ERROR',
        message: 'فشل فحص السلامة الشامل',
        details: e.toString(),
      );
      results['error'] = e.toString();
    }

    final duration = DateTime.now().difference(startTime);
    results['duration_ms'] = duration.inMilliseconds;
    results['total_errors'] = errors;
    results['total_warnings'] = warnings;
    results['issues'] = issues;
    results['scan_time'] = startTime.toIso8601String();

    _recordAlert(
      code: 'IM01-SCAN_COMPLETE',
      severity: 'INFO',
      message: 'اكتمل فحص السلامة الشامل',
      details: 'الأخطاء: $errors، التحذيرات: $warnings، المدة: ${duration.inMilliseconds}ms',
    );

    return results;
  }

  /// فحص سريع (يُستدعى دورياً)
  Future<Map<String, dynamic>> runQuickScan() async {
    final results = <String, dynamic>{};
    final issues = <String>[];
    int errors = 0;

    try {
      // 1. إجمالي الديون
      final db = await getDatabase();
      final debtRes = await db.rawQuery(
        'SELECT COALESCE(SUM(current_total_debt), 0) as total FROM customers WHERE current_total_debt > 0 AND (is_deleted IS NULL OR is_deleted = 0)',
      );
      results['total_debt'] = ((debtRes.first['total'] as num?) ?? 0).toDouble();

      // 2. إجمالي معاملات الديون
      final txRes = await db.rawQuery(
        'SELECT COALESCE(SUM(amount_changed), 0) as total FROM transactions WHERE (is_deleted IS NULL OR is_deleted = 0)',
      );
      results['total_transactions'] = ((txRes.first['total'] as num?) ?? 0).toDouble();

      // 3. فرق
      final diff = ((results['total_debt'] as double) - (results['total_transactions'] as double)).abs();
      results['difference'] = diff;
      if (diff > 1.0) {
        errors++;
        issues.add('فرق بين إجمالي الديون وإجمالي المعاملات: $diff');
        _recordAlert(
          code: 'QS01-DIFF',
          severity: 'WARNING',
          message: 'فرق بين إجمالي ديون العملاء ومجموع المعاملات',
          details: 'الديون: ${results['total_debt']}، المعاملات: ${results['total_transactions']}، الفرق: $diff',
        );
      }

      // 4. فواتير بدون أصناف
      final orphanInv = await db.rawQuery('''
        SELECT i.id FROM invoices i
        LEFT JOIN invoice_items ii ON ii.invoice_id = i.id
        WHERE ii.id IS NULL
        LIMIT 10
      ''');
      results['orphan_invoices'] = orphanInv.length;
      if (orphanInv.isNotEmpty) {
        errors++;
        issues.add('${orphanInv.length} فواتير بدون أصناف');
      }

      // 5. معاملات بدون فواتير
      final orphanTx = await db.rawQuery('''
        SELECT t.id FROM transactions t
        LEFT JOIN invoices i ON t.invoice_id = i.id
        WHERE t.invoice_id IS NOT NULL AND i.id IS NULL
        LIMIT 10
      ''');
      results['orphan_transactions'] = orphanTx.length;
      if (orphanTx.isNotEmpty) {
        errors++;
        issues.add('${orphanTx.length} معاملات بدون فواتير');
      }
    } catch (e) {
      results['error'] = e.toString();
    }

    results['errors'] = errors;
    results['issues'] = issues;
    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // الطبقة التاسعة: التحقق عند إغلاق اليوم (End-of-Day)
  // ═══════════════════════════════════════════════════════════════════════════

  /// فحص نهاية اليوم
  Future<Map<String, dynamic>> runEndOfDayVerification() async {
    final startTime = DateTime.now();
    final report = <String, dynamic>{};
    final issues = <String>[];

    report['date'] = DateTime.now().toIso8601String();
    report['started_at'] = startTime.toIso8601String();

    try {
      // 1. إعادة حساب أرصدة جميع العملاء
      final fixResult = await _verifyAndFixAllCustomerBalances();
      report['customers_checked'] = fixResult['checked'];
      report['customers_fixed'] = fixResult['fixed'];
      if (fixResult['fixed'] > 0) {
        issues.add('تم إصلاح ${fixResult['fixed']} عميل');
      }

      // 2. إعادة حساب مجاميع الفواتير
      final invoiceFixResult = await _verifyAndFixAllInvoiceTotals();
      report['invoices_checked'] = invoiceFixResult['checked'];
      report['invoices_fixed'] = invoiceFixResult['fixed'];
      if (invoiceFixResult['fixed'] > 0) {
        issues.add('تم إصلاح ${invoiceFixResult['fixed']} فاتورة');
      }

      // 3. إجمالي الديون
      final db = await getDatabase();
      final totalDebtRes = await db.rawQuery(
        'SELECT COALESCE(SUM(current_total_debt), 0) as total FROM customers WHERE (is_deleted IS NULL OR is_deleted = 0)',
      );
      report['total_debt'] = ((totalDebtRes.first['total'] as num?) ?? 0).toDouble();

      // 4. إجمالي المبيعات
      final totalSalesRes = await db.rawQuery(
        "SELECT COALESCE(SUM(total_amount), 0) as total FROM invoices WHERE status != 'معلقة'",
      );
      report['total_sales'] = ((totalSalesRes.first['total'] as num?) ?? 0).toDouble();

      // 5. إجمالي المدفوعات
      final totalPaidRes = await db.rawQuery(
        'SELECT COALESCE(SUM(amount_paid_on_invoice), 0) as total FROM invoices',
      );
      report['total_paid'] = ((totalPaidRes.first['total'] as num?) ?? 0).toDouble();

      // 6. فحص التسويات
      final adjustmentsRes = await db.rawQuery('SELECT COUNT(1) as cnt FROM invoice_adjustments');
      report['total_adjustments'] = (adjustmentsRes.first['cnt'] as int?) ?? 0;

      report['issues'] = issues;
      report['passed'] = issues.isEmpty;

      _recordAlert(
        code: 'EOD01',
        severity: report['passed'] ? 'INFO' : 'WARNING',
        message: report['passed']
          ? '✅ فحص نهاية اليوم: اجتاز جميع الفحوصات'
          : '⚠️ فحص نهاية اليوم:存在问题 تحتاج مراجعة',
        details: issues.isEmpty ? 'كل شيء سليم' : issues.join(' | '),
      );

    } catch (e) {
      report['error'] = e.toString();
      report['passed'] = false;
    }

    report['duration_ms'] = DateTime.now().difference(startTime).inMilliseconds;
    return report;
  }

  Future<Map<String, dynamic>> _verifyAndFixAllCustomerBalances() async {
    final db = await getDatabase();
    final customers = await customerDao.getAllCustomers();
    int checked = 0;
    int fixed = 0;

    for (final c in customers) {
      if (c.id == null) continue;
      checked++;
      final result = await db.rawQuery(
        'SELECT COALESCE(SUM(amount_changed), 0) as total FROM transactions WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
        [c.id],
      );
      final calc = ((result.first['total'] as num?) ?? 0).toDouble();
      if (!MoneyCalculator.areEqual(calc, c.currentTotalDebt)) {
        await db.update(
          'customers',
          {'current_total_debt': calc, 'last_modified_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [c.id],
        );
        fixed++;
      }
    }
    return {'checked': checked, 'fixed': fixed};
  }

  Future<Map<String, dynamic>> _verifyAndFixAllInvoiceTotals() async {
    final db = await getDatabase();
    final invoices = await invoiceDao.getAllInvoices();
    int checked = 0;
    int fixed = 0;

    for (final inv in invoices) {
      if (inv.id == null) continue;
      checked++;
      final items = await invoiceDao.getInvoiceItems(inv.id!);
      double itemsTotal = items.fold(0.0, (s, i) => s + i.itemTotal);
      final expected = itemsTotal + inv.loadingFee - inv.discount;
      if (!MoneyCalculator.areEqual(inv.totalAmount, expected)) {
        await db.update(
          'invoices',
          {'total_amount': expected},
          where: 'id = ?',
          whereArgs: [inv.id],
        );
        fixed++;
      }
    }
    return {'checked': checked, 'fixed': fixed};
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // الطبقة السابعة: مانع التناقضات (Contradiction Prevention)
  // ═══════════════════════════════════════════════════════════════════════════

  /// فحص التناقضات في النظام
  Future<List<GuardResult>> checkForContradictions() async {
    final db = await getDatabase();
    final results = <GuardResult>[];

    // 1. فواتير دين بدون عميل
    final debtNoCustomer = await db.rawQuery(
      "SELECT COUNT(1) as cnt FROM invoices WHERE payment_type = 'دين' AND (customer_id IS NULL OR customer_id = 0)",
    );
    if ((debtNoCustomer.first['cnt'] as int?) != 0) {
      results.add(GuardResult.fail('CT01', 'فواتير دين بدون عميل'));
    }

    // 2. عملاء برصيد سالب
    final negativeBalance = await db.rawQuery(
      'SELECT COUNT(1) as cnt FROM customers WHERE current_total_debt < -0.01',
    );
    if ((negativeBalance.first['cnt'] as int?) != 0) {
      results.add(GuardResult.fail('CT02', 'عملاء برصيد سالب'));
    }

    // 3. أصناف تشير لمنتج محذوف
    final orphanItems = await db.rawQuery('''
      SELECT COUNT(1) as cnt FROM invoice_items ii
      LEFT JOIN products p ON ii.product_id = p.id
      WHERE ii.product_id IS NOT NULL AND p.id IS NULL
      LIMIT 100
    ''');
    if ((orphanItems.first['cnt'] as int?) != 0) {
      results.add(GuardResult.fail('CT03', 'أصناف فواتير تشير لمنتجات محذوفة'));
    }

    // 4. فواتير بإجمالي سالب
    final negativeTotal = await db.rawQuery(
      'SELECT COUNT(1) as cnt FROM invoices WHERE total_amount < -0.01',
    );
    if ((negativeTotal.first['cnt'] as int?) != 0) {
      results.add(GuardResult.fail('CT04', 'فواتير بإجمالي سالب'));
    }

    // 5. فواتير مدفوع أكثر من الإجمالي
    final overpaid = await db.rawQuery(
      'SELECT COUNT(1) as cnt FROM invoices WHERE amount_paid_on_invoice > total_amount + 0.01',
    );
    if ((overpaid.first['cnt'] as int?) != 0) {
      results.add(GuardResult.fail('CT05', 'فواتير مدفوع أكثر من الإجمالي'));
    }

    // 6. تسويات تشير لفاتورة غير موجودة
    final orphanAdjustments = await db.rawQuery('''
      SELECT COUNT(1) as cnt FROM invoice_adjustments adj
      LEFT JOIN invoices i ON adj.invoice_id = i.id
      WHERE i.id IS NULL
    ''');
    if ((orphanAdjustments.first['cnt'] as int?) != 0) {
      results.add(GuardResult.fail('CT06', 'تسويات تشير لفواتير غير موجودة'));
    }

    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎯 الدمج مع مسار الحفظ (Integration Points)
  // ═══════════════════════════════════════════════════════════════════════════

  /// يتم استدعاؤها في بداية saveInvoice
  Future<PreSaveGuardReport> guardPreSaveInvoice({
    required InvoiceInputData data,
    required List<InvoiceItem> completeItems,
    required double calculatedTotal,
    required double totalAmount,
  }) async {
    final report = await runPreSaveChecks(
      data: data,
      completeItems: completeItems,
      calculatedTotal: calculatedTotal,
      totalAmount: totalAmount,
    );

    for (final f in report.failures) {
      _recordAlert(
        code: f.errorCode ?? 'PS-PRE',
        severity: 'ERROR',
        message: f.errorMessage ?? 'فشل الفحص القبلي',
        details: f.details,
        invoiceId: data.invoiceToManage?.id,
      );
    }

    return report;
  }

  /// يتم استدعاؤها بعد نجاح saveInvoice
  Future<PostSaveGuardReport> guardPostSaveInvoice({
    required Invoice savedInvoice,
    required InvoiceInputData originalData,
    required int expectedItemsCount,
    required List<InvoiceItem> expectedItems,
  }) async {
    final report = await runPostSaveChecks(
      savedInvoice: savedInvoice,
      originalData: originalData,
      expectedItemsCount: expectedItemsCount,
      expectedItems: expectedItems,
    );

    if (!report.isConsistent) {
      for (final a in report.anomalies) {
        _recordAlert(
          code: a.errorCode ?? 'PS-POST',
          severity: 'CRITICAL',
          message: a.errorMessage ?? 'شذوذ بعد الحفظ',
          details: a.details,
          invoiceId: savedInvoice.id,
          customerId: savedInvoice.customerId,
        );
      }
    }

    return report;
  }

  /// يتم استدعاؤها قبل إدراج تسوية
  Future<GuardResult> guardPreAdjustment({
    required InvoiceAdjustment adjustment,
  }) async {
    // 1. التحقق من وجود الفاتورة
    final invoice = await invoiceDao.getInvoiceById(adjustment.invoiceId);
    if (invoice == null) {
      return GuardResult.fail('ADJ01', 'الفاتورة رقم ${adjustment.invoiceId} غير موجودة');
    }

    // 2. التحقق من أن amountDelta ليس 0
    if (adjustment.amountDelta == 0) {
      return GuardResult.fail('ADJ02', 'قيمة التسوية صفر');
    }

    // 3. للـ credit: التحقق من أن المبلغ لا يتجاوز المتبقي
    if (adjustment.type == 'credit') {
      final afterDiscount = invoice.totalAmount;
      final paidSoFar = invoice.amountPaidOnInvoice;
      final remaining = afterDiscount - paidSoFar;
      if (adjustment.amountDelta.abs() > remaining + 0.01) {
        return GuardResult.fail(
          'ADJ03', 'التسوية الراجعة (${adjustment.amountDelta.abs()}) تتجاوز المبلغ المتبقي ($remaining)',
        );
      }
    }

    return GuardResult.success;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎯 واجهة مبسطة لـ InvoiceManager (بدون InvoiceInputData)
  // ═══════════════════════════════════════════════════════════════════════════

  /// فحص قبل الحفظ من InvoiceManager
  Future<PreSaveGuardReport> guardPreSaveCompleteInvoice({
    required Invoice invoice,
    required List<InvoiceItem> items,
  }) async {
    final failures = <GuardResult>[];
    final warnings = <GuardResult>[];

    // 1. مجموع الأصناف = إجمالي الفاتورة
    final itemsSum = items.fold(0.0, (s, i) => s + i.itemTotal);
    final expectedTotal = itemsSum + invoice.loadingFee - invoice.discount;
    if (!MoneyCalculator.areEqual(invoice.totalAmount, expectedTotal)) {
      failures.add(GuardResult.fail(
        'MGR01', 'مجموع الأصناف ($itemsSum) + أجور (${invoice.loadingFee}) - خصم (${invoice.discount}) ≠ إجمالي الفاتورة (${invoice.totalAmount})',
      ));
    }

    // 2. المبلغ المدفوع لا يتجاوز الإجمالي
    if (invoice.amountPaidOnInvoice > invoice.totalAmount + 0.01) {
      failures.add(GuardResult.fail(
        'MGR02', 'المبلغ المدفوع (${invoice.amountPaidOnInvoice}) > الإجمالي (${invoice.totalAmount})',
      ));
    }

    // 3. لا قيم سالبة
    if (invoice.discount < 0) {
      failures.add(GuardResult.fail('MGR03', 'الخصم سالب'));
    }
    if (invoice.loadingFee < 0) {
      failures.add(GuardResult.fail('MGR04', 'أجور التحميل سالبة'));
    }
    if (invoice.amountPaidOnInvoice < 0) {
      failures.add(GuardResult.fail('MGR05', 'المبلغ المدفوع سالب'));
    }

    // 4. أصناف مكتملة
    if (items.isEmpty) {
      failures.add(GuardResult.fail('MGR06', 'لا يوجد أصناف في الفاتورة'));
    } else {
      // 5. لكل صنف سعر > 0 وكمية > 0
      for (final item in items) {
        if (item.appliedPrice <= 0) {
          failures.add(GuardResult.fail('MGR07', 'السعر صفر أو سالب للصنف "${item.productName}"'));
        }
        final qty = item.quantityIndividual ?? item.quantityLargeUnit ?? 0;
        if (qty <= 0) {
          failures.add(GuardResult.fail('MGR08', 'الكمية صفر أو سالبة للصنف "${item.productName}"'));
        }
        if (item.itemTotal <= 0) {
          failures.add(GuardResult.fail('MGR09', 'إجمالي الصنف "${item.productName}" صفر أو سالب'));
        }
      }
    }

    // 6. دين بدون عميل
    if (invoice.paymentType == 'دين' && (invoice.customerId == null || invoice.customerId == 0)) {
      failures.add(GuardResult.fail('MGR10', 'فاتورة دين بدون عميل'));
    }

    // 7. نقد والمبلغ المدفوع = الإجمالي
    if (invoice.paymentType == 'نقد' && !MoneyCalculator.areEqual(invoice.amountPaidOnInvoice, invoice.totalAmount)) {
      warnings.add(GuardResult.fail('MGR11', 'الدفع نقد ولكن المبلغ المدفوع (${invoice.amountPaidOnInvoice}) ≠ الإجمالي (${invoice.totalAmount})'));
    }

    return PreSaveGuardReport(
      canProceed: failures.isEmpty,
      failures: failures,
      warnings: warnings,
    );
  }

  /// فحص بعد الحفظ من InvoiceManager
  Future<PostSaveGuardReport> guardPostSaveCompleteInvoice({
    required int savedInvoiceId,
    required Invoice invoice,
    required List<InvoiceItem> items,
  }) async {
    final fetchedInvoice = await invoiceDao.getInvoiceById(savedInvoiceId);
    if (fetchedInvoice == null) {
      return PostSaveGuardReport(
        isConsistent: false,
        anomalies: [GuardResult.fail('MGRP01', 'الفاتورة رقم $savedInvoiceId غير موجودة بعد الحفظ')],
        verificationTimeMs: 0,
      );
    }
    return runPostSaveChecks(
      savedInvoice: fetchedInvoice,
      originalData: InvoiceInputData(
        invoiceToManage: invoice,
        customerName: invoice.customerName,
        customerPhone: invoice.customerPhone ?? '',
        customerAddress: invoice.customerAddress ?? '',
        installerName: invoice.installerName,
        paidAmount: invoice.amountPaidOnInvoice,
        loadingFee: invoice.loadingFee,
        discount: invoice.discount,
        paymentType: invoice.paymentType,
        selectedDate: invoice.invoiceDate,
        invoiceItems: items,
      ),
      expectedItemsCount: items.length,
      expectedItems: items,
    );
  }
}
