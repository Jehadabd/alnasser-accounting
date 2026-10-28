import 'package:flutter/foundation.dart' show debugPrint;
import '../erp/erp_common.dart' show PeriodLock;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;

import '../models/customer.dart';
import '../models/invoice.dart';
import '../models/invoice_input_data.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import '../services/database/business/invoice_debt_reconciler.dart';
import '../services/smart_search/smart_search.dart';
import '../services/smart_pricing_service.dart';
import '../services/auth_service.dart';
import '../services/invoice_settings_service.dart';
import '../services/database/business/invoice_numbering.dart';
import '../services/seat_service.dart';
import '../services/invoice_edit_log.dart'; // ✏️ إضافة/مرتجع عند التعديل
import '../services/invoice_edit_events.dart'; // ✏️ التعديل عملية بتاريخ يومه
import '../services/settings_manager.dart';
import '../accounting/posting_engine.dart' show PostingEngine;


class InvoiceValidationResult {
  final bool isValid;
  final String? errorMessage;
  final bool isWarning; // If true, can proceed after confirmation (not used for now, logic seems to be hard blocking)

  InvoiceValidationResult({required this.isValid, this.errorMessage, this.isWarning = false});
}

class InvoiceSaveResult {
  final bool success;
  final Invoice? invoice;
  final String? errorMessage;

  /// ✏️ حدث التعديل (إضافة/مرتجع بتاريخ اليوم) إن كان للحفظ أثر مالي — لطباعة سنده.
  final int? editEventId;

  InvoiceSaveResult({required this.success, this.invoice, this.errorMessage, this.editEventId});
}

class InvoiceController {
  final DatabaseService _db;
  final FlutterSecureStorage _storage;

  InvoiceController({DatabaseService? db, FlutterSecureStorage? storage})
      : _db = db ?? DatabaseService(),
        _storage = storage ?? const FlutterSecureStorage();

  // ═══════════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════════
  
  String formatNumber(num value, {bool forceDecimal = false}) {
    final formatter = NumberFormat('#,##0.##', 'en_US');
    return formatter.format(value);
  }

  String _normalizePhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.startsWith('+')) {
      cleaned = cleaned.substring(1);
    }
    if (cleaned.startsWith('0')) {
      cleaned = '964${cleaned.substring(1)}';
    }
    if (!cleaned.startsWith('964')) {
      cleaned = '964$cleaned';
    }
    return cleaned;
  }

  bool _isInvoiceItemComplete(InvoiceItem item) {
    final hasValidQuantity = (item.quantityIndividual != null && item.quantityIndividual! > 0) ||
                             (item.quantityLargeUnit != null && item.quantityLargeUnit! > 0);
    return (item.productName.isNotEmpty &&
        hasValidQuantity &&
        (item.appliedPrice > 0 || item.isGift) && // 🎁 الهدية سعرها صفر
        (item.itemTotal > 0 || item.isGift) &&
        (item.saleType != null && item.saleType!.isNotEmpty));
  }


  double calculateActualCostPrice(
      Product product, String saleUnit, double quantity) {
    final double baseCost = product.costPrice ?? 0.0;
    if ((product.unit == 'piece' && saleUnit == 'قطعة') ||
        (product.unit == 'meter' && saleUnit == 'متر')) {
      return baseCost;
    }
    Map<String, double> unitCosts = const {};
    try {
      unitCosts = product.getUnitCostsMap();
    } catch (_) {}
    final double? stored = unitCosts[saleUnit];
    if (stored != null && stored > 0) {
      return stored;
    }
    if (product.unit == 'meter' && saleUnit == 'لفة') {
      final double lengthPerUnit = product.lengthPerUnit ?? 1.0;
      return baseCost * lengthPerUnit;
    }
    if (product.unit == 'piece' &&
        product.unitHierarchy != null &&
        product.unitHierarchy!.isNotEmpty) {
      try {
        final List<dynamic> hierarchy =
            jsonDecode(product.unitHierarchy!) as List<dynamic>;
        double multiplier = 1.0;
        for (final level in hierarchy) {
          final String unitName =
              (level['unit_name'] ?? level['name'] ?? '').toString();
          final double qty = (level['quantity'] is num)
              ? (level['quantity'] as num).toDouble()
              : double.tryParse(level['quantity'].toString()) ?? 1.0;
          multiplier *= qty;
          if (unitName == saleUnit) {
            return baseCost * multiplier;
          }
        }
      } catch (e) {
        debugPrint('خطأ في حساب التكلفة الهيراركية: $e');
      }
    }
    return baseCost;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. Validation Logic
  // ═══════════════════════════════════════════════════════════════════════════

  InvoiceValidationResult validateInvoiceData(InvoiceInputData data) {
    // 0. Check for Customer Name (Mandatory)
    if (data.customerName.trim().isEmpty) {
      return InvoiceValidationResult(isValid: false, errorMessage: 'اسم العميل مطلوب');
    }

    // 1. Check for complete items
    final completeItems = data.invoiceItems.where(_isInvoiceItemComplete).toList();
    final incompleteItems = data.invoiceItems.where((item) => 
      item.productName.isNotEmpty && !_isInvoiceItemComplete(item)
    ).toList();
    
    if (completeItems.isEmpty) {
      if (incompleteItems.isNotEmpty) {
        final problems = <String>[];
        for (final item in incompleteItems) {
          final itemProblems = <String>[];
          final hasQty = (item.quantityIndividual != null && item.quantityIndividual! > 0) ||
                         (item.quantityLargeUnit != null && item.quantityLargeUnit! > 0);
          if (!hasQty) itemProblems.add('الكمية');
          if (item.appliedPrice <= 0 && !item.isGift) itemProblems.add('السعر');
          if (item.saleType == null || item.saleType!.isEmpty) itemProblems.add('نوع البيع');
          if (itemProblems.isNotEmpty) {
            problems.add('${item.productName}: ينقص ${itemProblems.join('، ')}');
          }
        }
        if (problems.isNotEmpty) {
          return InvoiceValidationResult(
            isValid: false, 
            errorMessage: 'أصناف غير مكتملة:\n${problems.take(3).join('\n')}${problems.length > 3 ? '\n... و${problems.length - 3} أصناف أخرى' : ''}'
          );
        }
      }
      return InvoiceValidationResult(isValid: false, errorMessage: 'لا يمكن حفظ فاتورة بدون أصناف. أضف صنفاً واحداً على الأقل مع الكمية والسعر ونوع البيع.');
    }
    
    // 2. Calculate Total
    double calculatedTotal = 0.0;
    for (final item in completeItems) {
      // Assuming itemTotal is already calculated correctly in the UI/Model
      // But we can re-verify if needed, logic in mixin re-verified it.
      calculatedTotal += item.itemTotal;
    }
    
    // 3. Discount Check
    if (data.discount < 0) {
      return InvoiceValidationResult(isValid: false, errorMessage: 'الخصم لا يمكن أن يكون سالباً');
    }
    if (data.discount >= calculatedTotal) {
      return InvoiceValidationResult(isValid: false, errorMessage: 'الخصم لا يمكن أن يساوي أو يتجاوز الإجمالي');
    }
    
    // 4. Loading Fee Check
    if (data.loadingFee < 0) {
      return InvoiceValidationResult(isValid: false, errorMessage: 'أجور التحميل لا يمكن أن تكون سالبة');
    }
    
    // 5. Paid Amount Check
    final finalTotal = (calculatedTotal + data.loadingFee) - data.discount;
    
    if (data.paidAmount < 0) {
      return InvoiceValidationResult(isValid: false, errorMessage: 'المبلغ المدفوع لا يمكن أن يكون سالباً');
    }
    if (data.paidAmount > finalTotal + 0.01) {
      return InvoiceValidationResult(isValid: false, errorMessage: 'المبلغ المدفوع لا يمكن أن يتجاوز الإجمالي');
    }
    
    // 🔒 New Condition: Prevent reducing invoice total below paid amount (for edits)
    if (data.invoiceToManage != null && data.invoiceToManage!.id != null) {
      if (finalTotal < data.paidAmount - 0.01) {
        return InvoiceValidationResult(
          isValid: false, 
          errorMessage: 'لا يمكن أن يكون إجمالي الفاتورة (${formatNumber(finalTotal)}) أقل من المبلغ المسدد (${formatNumber(data.paidAmount)}). يرجى تقليل المبلغ المسدد أولاً.',
        );
      }
    }
    
    // 6. Payment Type Check
    if (data.paymentType == 'نقد' && (data.paidAmount - finalTotal).abs() > 0.01) {
      return InvoiceValidationResult(isValid: false, errorMessage: 'في حالة الدفع النقدي، يجب أن يساوي المبلغ المدفوع الإجمالي');
    }
    
    return InvoiceValidationResult(isValid: true);
  }

  Future<InvoiceValidationResult> validateDebtChangeWontCauseNegativeBalance(InvoiceInputData data) async {
    // Only for existing invoices (edits)
    if (data.invoiceToManage == null || data.invoiceToManage!.id == null) {
      return InvoiceValidationResult(isValid: true);
    }
    
    final oldInvoiceFromDb = await _db.getInvoiceById(data.invoiceToManage!.id!);
    if (oldInvoiceFromDb == null) return InvoiceValidationResult(isValid: true); // Should not happen
    
    final oldInvoice = oldInvoiceFromDb;

    if (oldInvoice.paymentType != 'دين') {
      return InvoiceValidationResult(isValid: true);
    }
    
    final oldCustomerId = oldInvoice.customerId;
    if (oldCustomerId == null) {
      return InvoiceValidationResult(isValid: true);
    }
    
    final oldCustomer = await _db.getCustomerById(oldCustomerId);
    if (oldCustomer == null) {
      return InvoiceValidationResult(isValid: true);
    }
    
    final currentCustomerDebt = oldCustomer.currentTotalDebt;
    
    // 🛡️ الدين القديم = ما هو مسجّل فعلاً في المعاملات، لا ما تفترضه الفاتورة.
    // (كانت الحسبة السابقة تفترض تطابقهما — وهو بالضبط ما قد يكون منحرفاً)
    final oldRemaining = await InvoiceDebtReconciler.recordedContribution(
      await _db.database,
      oldInvoice.id!,
      oldCustomerId,
    );
    
    // Calculate New Total
    final completeItems = data.invoiceItems.where(_isInvoiceItemComplete).toList();
    double calculatedTotal = completeItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    final newTotal = (calculatedTotal + data.loadingFee) - data.discount;
    final newPaid = data.paidAmount;
    
    // Check Customer Change
    final newCustomerName = data.customerName.trim();
    final oldCustomerName = oldInvoice.customerName.trim();
    final isCustomerChanged = newCustomerName.replaceAll(' ', '').toLowerCase() != 
                              oldCustomerName.replaceAll(' ', '').toLowerCase();
    
    double debtChange = 0.0;
    
    // Case 1: Change to Cash
    if (data.paymentType == 'نقد') {
      debtChange = -oldRemaining;
    }
    // Case 2: Customer Changed (Debt Invoice)
    else if (data.paymentType == 'دين' && isCustomerChanged) {
      debtChange = -oldRemaining; // All old debt removed from *old* customer
    }
    // Case 3: Edit Debt Invoice (Same Customer)
    else if (data.paymentType == 'دين') {
      final newRemaining = newTotal - newPaid;
      debtChange = newRemaining - oldRemaining;
    }
    
    final expectedNewBalance = currentCustomerDebt + debtChange;
    
    // 🛡️ يُمنع التعديل فقط إذا كان هو نفسه يُنقص رصيد العميل إلى ما دون الصفر.
    // عميل رصيده سالب أصلاً (له رصيد دائن، مثلاً بعد تحويل معاملة إلى تسديد) كان
    // يُمنع من أي تعديل على فواتيره — حتى تغيير التاريخ أو زيادة الكمية.
    // (وُجد في اختبار التحمّل: تعديل التاريخ وحده رُفض 5 مرات لهذا السبب)
    if (debtChange < -0.01 && expectedNewBalance < -0.01) {
      final debtToDeduct = formatNumber(-debtChange);
      String reason = '';
      String solution = '';
      
      if (isCustomerChanged) {
        reason = 'تم تغيير اسم العميل، وسيُخصم الدين من العميل القديم "${oldCustomer.name}".';
        solution = 'تأكد من أن العميل القديم لديه رصيد كافٍ، أو عدّل المعاملات أولاً.';
      } else if (data.paymentType == 'نقد') {
        reason = 'تم تحويل الفاتورة من دين إلى نقد.';
        solution = 'راجع معاملات العميل أو أبقِ الفاتورة بالدين.';
      } else {
        reason = 'تم تسديد جزء من هذه الفاتورة من سجل الديون.';
        solution = 'راجع معاملات العميل أو عدّل المبلغ المسدد.';
      }
      
      return InvoiceValidationResult(
        isValid: false,
        errorMessage: 'لا يمكن إتمام هذا التعديل!\n\n'
            'رصيد العميل "${oldCustomer.name}" الحالي: ${formatNumber(currentCustomerDebt)}\n'
            'المبلغ الذي سيُخصم: $debtToDeduct\n'
            'الرصيد المتوقع: ${formatNumber(expectedNewBalance)} (سالب!)\n\n'
            'السبب: $reason\n'
            'الحل: $solution',
      );
    }
    
    return InvoiceValidationResult(isValid: true);
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // 2. Main Save Function
  // ═══════════════════════════════════════════════════════════════════════════

  Future<InvoiceSaveResult> saveInvoice(InvoiceInputData data) async {
    // 🛡️ حماية الفواتير المستوردة من التعديل
    if (!data.isNewInvoice && data.invoiceToManage != null && !data.invoiceToManage!.isCreatedByMe) {
      return InvoiceSaveResult(
        success: false, 
        errorMessage: 'عذراً، لا يمكن تعديل الفواتير المستوردة لأنها أنشئت بواسطة جهاز آخر.'
      );
    }

    // 🛡️ فاتورة من نسخة احتياطية مستعادة والجهاز لم يلحق بالبقية بعد: قد تكون
    // نسختها المعروضة قديمة (DatabaseService.isRestoredRecordLocked)
    if (!data.isNewInvoice &&
        data.invoiceToManage?.id != null &&
        await _db.isRestoredRecordLocked('invoices', data.invoiceToManage!.id!)) {
      return InvoiceSaveResult(
          success: false, errorMessage: RestoredRecordLockedException.message);
    }

    // 🔒 تثبيت الإدخالات: لا فاتورة جديدة ولا تعديل بتاريخ داخل فترة مثبّتة
    //    (يُفحص التاريخ الجديد والتاريخ الأصلي للفاتورة المعدّلة)
    try {
      await PeriodLock.assertOpen(data.selectedDate);
      final orig = data.invoiceToManage?.invoiceDate;
      if (!data.isNewInvoice && orig != null) await PeriodLock.assertOpen(orig);
    } catch (e) {
      return InvoiceSaveResult(success: false, errorMessage: e.toString());
    }

    // Re-run standard validation to be safe
    final validation = validateInvoiceData(data);
    if (!validation.isValid) {
      return InvoiceSaveResult(success: false, errorMessage: validation.errorMessage);
    }
    
    // Re-run debt validation
    final debtValidation = await validateDebtChangeWontCauseNegativeBalance(data);
    if (!debtValidation.isValid) {
      return InvoiceSaveResult(success: false, errorMessage: debtValidation.errorMessage);
    }

    // 🛡️ Pre-save guard
    final completeItems = data.invoiceItems.where(_isInvoiceItemComplete).toList();
    final double preCalculatedTotal = completeItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    final double preTotalAmount = (preCalculatedTotal + data.loadingFee) - data.discount;

    final preSaveReport = await _db.financialIntegrityGuard.guardPreSaveInvoice(
      data: data,
      completeItems: completeItems,
      calculatedTotal: preCalculatedTotal,
      totalAmount: preTotalAmount,
    );
    if (!preSaveReport.canProceed) {
      final errorMsg = preSaveReport.failures.map((f) => f.errorMessage).join('; ');
      return InvoiceSaveResult(success: false, errorMessage: 'فشل فحص السلامة المالية: $errorMsg');
    }

    // 🛡️ Smart audit for edits
    if (!data.isNewInvoice && data.invoiceToManage != null) {
      try {
        await _db.financialIntegrityGuard.smartAuditInvoiceChange(
          oldInvoice: data.invoiceToManage!,
          newData: data,
        );
      } catch (_) {}
    }

    try {
      if (!data.isNewInvoice && data.invoiceToManage?.id == null) {
        throw Exception('خطأ فادح: محاولة تعديل فاتورة بدون معرّف (ID).');
      }

      Invoice? savedInvoice;

      // 📸 Save Snapshot (Before Edit)
      final currentUser = AuthService().currentUser;
      final currentUserName = currentUser?.username ?? 'System';

      if (!data.isNewInvoice && data.invoiceToManage?.id != null) {
        try {
          final hasSnapshots = await _db.hasInvoiceBeenModified(data.invoiceToManage!.id!);
          if (!hasSnapshots) {
            await _db.saveInvoiceSnapshot(
              invoiceId: data.invoiceToManage!.id!,
              snapshotType: 'original',
              notes: 'النسخة الأصلية قبل أي تعديل',
              createdBy: currentUserName,
            );
          }
          await _db.saveInvoiceSnapshot(
            invoiceId: data.invoiceToManage!.id!,
            snapshotType: 'before_edit',
            notes: 'قبل التعديل',
            createdBy: currentUserName,
          );
        } catch (e) {
          debugPrint('تحذير: فشل حفظ نسخة الفاتورة: $e');
        }
      }

      // ✏️ أحداث التعديل: كلفة محرك الترحيل تحتاج نسبة ربح المواد بلا كلفة
      double editAdHoc = 0.10;
      int? editEventId;
      if (!data.isNewInvoice) {
        try {
          editAdHoc = (await SettingsManager.getAppSettings()).defaultAdHocProfitPercentage / 100.0;
        } catch (_) {}
      }

      // 🏁 Start Transaction
      await (await _db.database).transaction((txn) async {
        Customer? customer;
        // اسم/هاتف الفاتورة المحفوظة قد يختلفان عمّا كُتب (عميل تغيّر اسمه أو هاتفه)
        String? resolvedName;
        String? resolvedPhone;
        var phoneFromCustomer = false;
        if (data.customerName.trim().isNotEmpty) {
          String? normalizedPhone;
          if (data.customerPhone.trim().isNotEmpty) {
            normalizedPhone = _normalizePhoneNumber(data.customerPhone.trim());
          }

          final normalizedName = data.customerName.trim().replaceAll(' ', '');
          String nameKey(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

          // 🛡️ قاعدة سجل الديون: الاسم (بتجاهل المسافات) يحدد الحساب — لا يُنشأ
          // حسابان بالاسم نفسه أبداً. الهاتف لا يفرّق بين الحسابات:
          //   • للعميل هاتف وكُتب غيره ⇒ الفاتورة لحسابه ويبقى هاتفه كما هو
          //     (الفاتورة تحفظ الرقم المكتوب عليها).
          //   • ليس للعميل هاتف وكُتب رقم ⇒ يُضاف الرقم إلى بطاقته.
          //   • لم يُكتب رقم ⇒ الفاتورة لحسابه وهاتفه يبقى.
          // كان البحث بالاسم + الهاتف معاً، فاسم موجود مع رقم مختلف (أو بلا رقم)
          // يُنشئ حساباً ثانياً بالاسم نفسه ويقسم دينه على حسابين.

          // تعديل فاتورة محفوظة بالاسم نفسه ⇒ هي لعميلها نفسه (بالمعرّف)، حتى
          // لو تغيّر اسمه في بطاقته بعد إنشاء الفاتورة.
          final old = data.invoiceToManage;
          if (!data.isNewInvoice &&
              old != null &&
              old.customerId != null &&
              nameKey(old.customerName) == nameKey(data.customerName)) {
            final byId = await txn.query('customers',
                where: 'id = ? AND COALESCE(is_deleted, 0) = 0', whereArgs: [old.customerId], limit: 1);
            if (byId.isNotEmpty) {
              customer = Customer.fromMap(byId.first);
            }
          }

          if (customer == null) {
            final candidates = await txn.rawQuery(
              "SELECT * FROM customers WHERE REPLACE(name, ' ', '') = ? AND COALESCE(is_deleted, 0) = 0 ORDER BY id",
              [normalizedName],
            );
            if (candidates.isNotEmpty) {
              // أكثر من حساب بالاسم نفسه = تكرار قديم لم يُدمج بعد (شاشة «دمج
              // الحسابات المكررة»): نختار صاحب الهاتف نفسه إن وُجد، وإلا الأقدم.
              Map<String, Object?> picked = candidates.first;
              if (normalizedPhone != null && normalizedPhone.isNotEmpty) {
                for (final m in candidates) {
                  final p = (m['phone'] as String?)?.trim() ?? '';
                  if (p.isNotEmpty && _normalizePhoneNumber(p) == normalizedPhone) {
                    picked = m;
                    break;
                  }
                }
              }
              customer = Customer.fromMap(picked);
            }
          }

          final found = customer;
          if (found != null) {
            resolvedName = found.name;
            final cardPhone = (found.phone ?? '').trim();
            if (cardPhone.isEmpty && normalizedPhone != null && normalizedPhone.isNotEmpty) {
              // ليس للعميل هاتف: يُضاف الرقم المكتوب إلى بطاقته
              try {
                await txn.update(
                  'customers',
                  {'phone': normalizedPhone, 'last_modified_at': DateTime.now().toIso8601String()},
                  where: 'id = ?',
                  whereArgs: [found.id],
                );
                customer = found.copyWith(phone: normalizedPhone);
              } on DatabaseException catch (e) {
                // قيد UNIQUE(name, phone) القديم مع حساب مكرر لم يُدمج بعد: يبقى بلا هاتف
                if (!e.isUniqueConstraintError()) rethrow;
              }
            }
            if (normalizedPhone == null && !data.isNewInvoice) {
              // تعديل فاتورة بلا هاتف مكتوب: يُعرض هاتف العميل عليها
              resolvedPhone = found.phone;
              phoneFromCustomer = true;
            }
          } else {
            customer = Customer(
              id: null,
              name: data.customerName.trim(),
              phone: normalizedPhone,
              address: data.customerAddress.trim(),
              createdAt: DateTime.now(),
              lastModifiedAt: DateTime.now(),
              currentTotalDebt: 0.0,
              syncUuid: const Uuid().v4(),
            );
            final insertedId = await txn.insert('customers', customer.toMap());
            customer = customer.copyWith(id: insertedId);
          }
        }

        // 🛡️ استخدام القيم المحسوبة مسبقاً من pre-save guard
        final double currentTotalAmount = preCalculatedTotal;
        final double totalAmount = preTotalAmount;

        double paid = data.paidAmount;
        if (data.invoiceToManage != null && data.paymentType == 'نقد') {
          paid = totalAmount;
        }

        if (data.discount >= currentTotalAmount) {
          throw Exception(
              'نسبة الخصم خاطئة! (الخصم: ${formatNumber(data.discount)} الإجمالي: ${formatNumber(currentTotalAmount)})');
        }

        String newStatus = 'محفوظة';
        String? normalizedPhoneForInvoice;
        if (data.customerPhone.trim().isNotEmpty) {
          normalizedPhoneForInvoice = _normalizePhoneNumber(data.customerPhone.trim());
        }

        final currentUser = AuthService().currentUser;
        
        int? nextSeq = data.invoiceToManage?.monthlySequenceNumber;
        String? invoiceNumberStr = data.invoiceToManage?.invoiceNumber;
        int? invoiceYear = data.invoiceToManage?.invoiceYear;
        int? invoiceMonth = data.invoiceToManage?.invoiceMonth;
        String? creatorDeviceIdStr = data.invoiceToManage?.creatorDeviceId;

        if (data.isNewInvoice) {
          final deviceIdNum = await InvoiceSettingsService.getInvoiceDeviceId();
          creatorDeviceIdStr = deviceIdNum.toString();
          invoiceYear = data.selectedDate.year;
          invoiceMonth = data.selectedDate.month;
          
          // 🔢 أول رقم غير مستعمل في القاعدة كلها — لا في فواتير هذا الجهاز وحدها
          // (فواتير جهاز آخر على «رقم الجهاز» نفسه كانت تصطدم: UNIQUE invoice_number)
          final n = await InvoiceNumbering.next(txn,
              deviceNum: deviceIdNum, year: invoiceYear, month: invoiceMonth);
          nextSeq = n.seq;
          invoiceNumberStr = n.number;
        }

        Invoice invoice = Invoice(
          id: data.invoiceToManage?.id,
          customerName: resolvedName ?? data.customerName,
          customerPhone: phoneFromCustomer
              ? ((resolvedPhone ?? '').trim().isEmpty ? null : _normalizePhoneNumber(resolvedPhone!.trim()))
              : normalizedPhoneForInvoice,
          customerAddress: data.customerAddress,
          installerName: (data.installerName == null || data.installerName!.isEmpty)
              ? null
              : data.installerName,
          invoiceDate: data.selectedDate,
          paymentType: data.paymentType,
          totalAmount: totalAmount,
          discount: data.discount,
          amountPaidOnInvoice: paid,
          loadingFee: data.loadingFee,
          createdAt: data.invoiceToManage?.createdAt ?? DateTime.now(),
          lastModifiedAt: DateTime.now(),
          customerId: customer?.id,
          status: newStatus,
          isLocked: false,
          // 👷 معدل نقاط المؤسس يُحفظ مع الفاتورة (يُزامَن معها)؛ بلا مؤسس = صفر
          pointsRate: (data.installerName == null || data.installerName!.trim().isEmpty) ? 0.0 : data.pointsRate,
          createdByUserId: data.invoiceToManage?.createdByUserId ?? currentUser?.id,
          createdByUsername: data.invoiceToManage?.createdByUsername ?? currentUser?.username,
          invoiceUuid: data.invoiceToManage?.invoiceUuid,
          creatorDeviceId: creatorDeviceIdStr,
          version: data.invoiceToManage?.version ?? 1,
          monthlySequenceNumber: nextSeq,
          invoiceNumber: invoiceNumberStr,
          invoiceYear: invoiceYear,
          invoiceMonth: invoiceMonth,
          isCreatedByMe: data.invoiceToManage?.isCreatedByMe ?? true,
        );

        int invoiceId;
        final invoiceMap = invoice.toMap();
        // 🛡️ النسخة تُبنى على الأكبر بين نسخة الشاشة ونسخة الصف: التسوية أو
        // تعديل سابق قد يكونان رفعاها، والبناء على نسخة الشاشة وحدها يعيد
        // رقماً سبق رفعه فتتجاهل الأجهزة الأخرى هذا التعديل.
        int? baseVersion = data.invoiceToManage?.version;
        final existingId = data.invoiceToManage?.id;
        if (!data.isNewInvoice && existingId != null) {
          final vr = await txn.query('invoices',
              columns: ['version'], where: 'id = ?', whereArgs: [existingId], limit: 1);
          final dbVersion =
              vr.isEmpty ? null : (vr.first['version'] as num?)?.toInt();
          if (dbVersion != null &&
              (baseVersion == null || dbVersion > baseVersion)) {
            baseVersion = dbVersion;
          }
        }
        await DatabaseService.stampInvoiceForSync(
          invoiceMap,
          isNew: data.isNewInvoice,
          currentVersion: baseVersion,
        );
        // ملاحظة: ربط المعاملة بـ invoice_uuid صار من مسؤولية
        // InvoiceDebtReconciler الذي يقرأه من صف الفاتورة مباشرة.

        // ✏️ حال الفاتورة قبل هذا التعديل (قبل تحديث رأسها وبنودها)
        InvoiceMoneyState? editBefore;
        if (!data.isNewInvoice && existingId != null) {
          try {
            editBefore = await InvoiceEditEvents.capture(txn, existingId,
                costOf: (d, id) => PostingEngine.invoiceCostOf(d, id, editAdHoc));
          } catch (e) {
            debugPrint('⚠️ حدث التعديل (قبل): $e');
          }
        }

        if (data.isNewInvoice) {
          // سبقنا جهاز آخر بالرقم نفسه في اللحظة نفسها؟ يُعاد الترقيم تلقائياً
          invoiceId = await InvoiceNumbering.insertNew(txn, invoiceMap);
          invoice = Invoice.fromMap(invoiceMap).copyWith(id: invoiceId);
        } else {
          invoiceId = data.invoiceToManage!.id!;
          await txn.update('invoices', invoiceMap,
              where: 'id = ?', whereArgs: [invoiceId]);
          invoice = Invoice.fromMap(invoiceMap).copyWith(id: invoiceId);
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // Protect Items
        // ═══════════════════════════════════════════════════════════════════════════
        final products = await txn.rawQuery('SELECT * FROM products');
        final productMap = <String, Map<String, dynamic>>{};
        for (var productData in products) {
          final productName = productData['name'] as String?;
          if (productName != null) {
            productMap[productName] = productData;
          }
        }

        final List<Map<String, dynamic>> itemsToInsert = [];
        for (var item in data.invoiceItems) {
          if (_isInvoiceItemComplete(item)) {
            final productData = productMap[item.productName];
            Product matchedProduct;

            if (productData != null) {
              matchedProduct = Product.fromMap(productData);
            } else {
              matchedProduct = Product(
                name: '',
                unit: '',
                unitPrice: 0.0,
                price1: 0.0,
                createdAt: DateTime.now(),
                lastModifiedAt: DateTime.now(),
              );
            }

            final actualCostPrice = calculateActualCostPrice(
                matchedProduct,
                item.saleType ?? 'قطعة',
                item.quantityIndividual ?? item.quantityLargeUnit ?? 0);

            final invoiceItem = item.copyWith(
              invoiceId: invoiceId,
              actualCostPrice: actualCostPrice,
              productSyncUuid: matchedProduct.syncUuid, // 🔥 الربط الذري
            );

            var itemMap = invoiceItem.toMap();
            itemMap.remove('id');
            itemsToInsert.add(itemMap);
          }
        }

        if (!data.isNewInvoice && itemsToInsert.isEmpty) {
          throw Exception('لا يمكن حفظ الفاتورة بدون أصناف مكتملة. تأكد من إدخال اسم المنتج والكمية والسعر ونوع البيع.');
        }

        // 📦 المخزون: حذف البنود القديمة وإدراج الجديدة يعيد حساب الكمية
        //    تلقائياً (دفتر المخزون — مشغّلات SQLite). كان هنا «إرجاع القديم ثم
        //    خصم الجديد» بكود التطبيق فوق مشغّلين يفعلان الشيء نفسه: ضعف الفرق
        //    لبنود القطعة/المتر.
        // ✏️ تعديل فاتورة محفوظة: ما زاد «إضافة» وما نقص «مرتجع» (سجل توضيحي
        //    فقط — الأثر المالي والمخزني يحسبه الحارس والمشغّلات أدناه مرة واحدة)
        String? editSummary;
        if (!data.isNewInvoice) {
          try {
            final oldItems = await txn.query('invoice_items',
                columns: ['product_name', 'sale_type', 'quantity_individual', 'quantity_large_unit', 'item_total'],
                where: 'invoice_id = ?', whereArgs: [invoiceId]);
            editSummary = await InvoiceEditLog.record(
              txn,
              invoiceId: invoiceId,
              oldItems: oldItems,
              newItems: itemsToInsert,
              editedBy: AuthService().currentUser?.username,
            );
          } catch (e) {
            debugPrint('⚠️ سجل تعديل الفاتورة تعذّر (لا يؤثر على الحفظ): $e');
          }
        }

        await txn.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
        
        // 2. Insert new items (stock follows automatically)
        final batch = txn.batch();
        int savedItemsCount = 0;
        for (var itemMap in itemsToInsert) {
          batch.insert('invoice_items', itemMap);
          savedItemsCount++;
        }
        await batch.commit(noResult: true);


        if (savedItemsCount == 0 && !data.isNewInvoice) {
          throw Exception('فشل حفظ أصناف الفاتورة. يرجى المحاولة مرة أخرى.');
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // 🛡️ الحارس المحاسبي — قاعدة واحدة تحل محل الحالات الخمس السابقة
        // ═══════════════════════════════════════════════════════════════════════════
        //
        // مساهمة الفاتورة في الدين = الإجمالي − المسدد (لفواتير الدين)، وصفر للنقد.
        //
        // كان هنا خمس حالات منفصلة (نقد←دين، دين←نقد، تغيير العميل، تعديل فاتورة
        // دين، فاتورة جديدة) يختار بينها الكود بالنظر إلى
        // data.invoiceToManage.paymentType — وهو كائن من ذاكرة الشاشة قد يكون
        // قديماً. وكانت الحالة 2 تراكمية: تضيف الدين كاملاً في كل مرة تدخلها،
        // فضغطتا حفظ متتاليتان كانتا تضاعفان دين العميل.
        //
        // البديل دالة واحدة تقرأ الفاتورة من قاعدة البيانات (لا من الذاكرة)
        // وهي إدمبوتنت: تشغيلها مرة أو عشر مرات يعطي النتيجة نفسها.
        await InvoiceDebtReconciler.reconcileInvoice(
          txn,
          invoiceId,
          createMissing: true,
          reason: data.isNewInvoice
              ? 'دين فاتورة جديدة'
              : (editSummary == null ? 'تعديل فاتورة' : 'تعديل فاتورة: $editSummary'),
        );

        // ✏️ حدث التعديل بتاريخ اليوم — في المعاملة نفسها: يُحفظ مع التعديل أو لا شيء.
        //    فشله لا يُفشل الحفظ: تبقى الفاتورة على السلوك القديم (كلها بتاريخها).
        if (editBefore != null) {
          try {
            final editAfter = await InvoiceEditEvents.capture(txn, invoiceId,
                costOf: (d, id) => PostingEngine.invoiceCostOf(d, id, editAdHoc));
            if (editAfter != null) {
              editEventId = await InvoiceEditEvents.record(
                txn,
                invoiceId: invoiceId,
                before: editBefore,
                after: editAfter,
                user: AuthService().currentUser?.username,
                summary: editSummary,
              );
            }
          } catch (e) {
            debugPrint('⚠️ حدث التعديل: $e');
          }
        }

        final maps = await txn
            .query('invoices', where: 'id = ?', whereArgs: [invoiceId]);
        savedInvoice = Invoice.fromMap(maps.first);
      });

      // 🛡️ Post-save guard
      if (savedInvoice != null) {
        try {
          await _db.financialIntegrityGuard.guardPostSaveInvoice(
            savedInvoice: savedInvoice!,
            originalData: data,
            expectedItemsCount: completeItems.length,
            expectedItems: completeItems,
          );
        } catch (guardError) {
          debugPrint('⚠️ Post-save guard error (non-blocking): $guardError');
        }
      }

      // ═══════════════════════════════════════════════════════════════════════════
      // Helper: Audit Log
      // ═══════════════════════════════════════════════════════════════════════════
      try {
        if (savedInvoice != null) {
           final double totalAmount = savedInvoice!.totalAmount;
          final double discountVal = savedInvoice!.discount;
          final double paidVal = savedInvoice!.amountPaidOnInvoice;
          final int? customerId = savedInvoice!.customerId;
          
          // Invoice Log
          await _db.insertAuditLog(
            operationType: data.isNewInvoice ? 'invoice_create' : 'invoice_update',
            entityType: 'invoice',
            entityId: savedInvoice!.id!,
            oldValues: data.isNewInvoice ? null : jsonEncode({
              'total_amount': data.invoiceToManage?.totalAmount,
              'discount': data.invoiceToManage?.discount,
              'payment_type': data.invoiceToManage?.paymentType,
              'paid_amount': data.invoiceToManage?.amountPaidOnInvoice,
              'customer_id': data.invoiceToManage?.customerId,
            }),
            newValues: jsonEncode({
              'total_amount': totalAmount,
              'discount': discountVal,
              'payment_type': data.paymentType,
              'paid_amount': paidVal,
              'customer_id': customerId,
              'customer_name': data.customerName,
              'items_count': data.invoiceItems.where((i) => _isInvoiceItemComplete(i)).length,
            }),
            notes: data.isNewInvoice 
              ? 'إنشاء فاتورة جديدة' 
              : 'تعديل فاتورة - الإجمالي: $totalAmount، الخصم: $discountVal، المدفوع: $paidVal',
          );
          
          if (customerId != null) {
            await _db.insertAuditLog(
              operationType: data.isNewInvoice ? 'invoice_create' : 'invoice_update',
              entityType: 'customer',
              entityId: customerId,
              oldValues: data.isNewInvoice ? null : jsonEncode({
                'invoice_id': savedInvoice!.id,
                'total_amount': data.invoiceToManage?.totalAmount,
                'payment_type': data.invoiceToManage?.paymentType,
              }),
              newValues: jsonEncode({
                'invoice_id': savedInvoice!.id,
                'total_amount': totalAmount,
                'discount': discountVal,
                'payment_type': data.paymentType,
                'paid_amount': paidVal,
              }),
              notes: data.isNewInvoice 
                ? 'فاتورة جديدة رقم ${savedInvoice!.id} بقيمة $totalAmount' 
                : 'تعديل فاتورة رقم ${savedInvoice!.id}',
            );
          }
          
          if (data.isNewInvoice) {
            try {
              await _db.saveInvoiceSnapshot(
                invoiceId: savedInvoice!.id!,
                snapshotType: 'original',
                notes: 'النسخة الأصلية عند الإنشاء',
                createdBy: currentUserName,
              );
            } catch (_) {
              // فشل حفظ اللقطة لا يُفشل حفظ الفاتورة (اللقطة للسجل فقط)
            }
          } else {
            try {
              await _db.saveInvoiceSnapshot(
                invoiceId: savedInvoice!.id!,
                snapshotType: 'after_edit',
                notes: 'بعد التعديل - الإجمالي: $totalAmount',
                createdBy: currentUserName,
              );
            } catch (_) {
              // فشل حفظ اللقطة لا يُفشل حفظ الفاتورة (اللقطة للسجل فقط)
            }
          }
        }
      } catch (auditError) {
        // Ignore
      }

      await _storage.delete(key: SeatService.key('temp_invoice_data'));

      // Smart Search Training
      if (savedInvoice != null && savedInvoice!.id != null) {
        try {
          await SmartSearchService.instance.trainOnNewInvoice(savedInvoice!.id!);
        } catch (e) {
          debugPrint('⚠️ Smart Search training error (non-blocking): $e');
        }
        // 🧠 علاقات مستويات الأسعار — في الخلفية، لا ينتظرها الحفظ
        final sid = savedInvoice!.id!;
        SmartPricingService().recordInvoicePriceLevels(sid).catchError((e) {
          debugPrint('⚠️ Price-level learning error (non-blocking): $e');
        });
      }
      
      SmartSearchService.instance.forceNewSession();

      return InvoiceSaveResult(success: true, invoice: savedInvoice, editEventId: editEventId);

    } catch (e, stack) {
      debugPrint("Save Error: $e \n $stack");
       return InvoiceSaveResult(success: false, errorMessage: e.toString());
    }
  }
}
