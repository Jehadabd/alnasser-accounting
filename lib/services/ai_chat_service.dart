import 'package:sqflite/sqflite.dart';
import 'database_service.dart';
import 'settings_manager.dart';
import 'gemini_service.dart';
import '../utils/money_calculator.dart';
import 'dart:convert';
import 'dart:io';

/// خدمة الدردشة مع الذكاء الاصطناعي - تدقيق شامل للنظام
/// هذه الخدمة تستطيع الوصول لكامل قاعدة البيانات والتحقق من صحة البيانات
class AIChatService {
  final DatabaseService _dbService;
  final GeminiService? _geminiService;
  
  AIChatService(
    this._dbService, {
    GeminiService? geminiService,
  }) : _geminiService = geminiService;

  /// 🔧 حساب التكلفة من unit_hierarchy عندما لا تتوفر بيانات أخرى
  /// نفس منطق _calculateActualCostPrice في create_invoice_screen.dart
  /// يُستخدم عندما يكون uilu = 0 ولا يوجد actualCostPrice
  double _calculateCostFromHierarchy({
    required double productCost,
    required String saleType,
    required String? unitHierarchyJson,
  }) {
    // إذا لم يكن هناك تسلسل هرمي، نرجع التكلفة الأساسية
    if (unitHierarchyJson == null || unitHierarchyJson.trim().isEmpty) {
      return productCost;
    }
    
    try {
      final List<dynamic> hierarchy = jsonDecode(unitHierarchyJson) as List<dynamic>;
      double multiplier = 1.0;
      
      for (final level in hierarchy) {
        final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
        final double qty = (level['quantity'] is num)
            ? (level['quantity'] as num).toDouble()
            : double.tryParse(level['quantity'].toString()) ?? 1.0;
        multiplier *= qty;
        
        // إذا وصلنا لوحدة البيع المطلوبة، نرجع التكلفة المحسوبة
        if (unitName == saleType) {
          return productCost * multiplier;
        }
      }
      
      // إذا لم نجد الوحدة في التسلسل، نرجع التكلفة الأساسية
      return productCost;
    } catch (e) {
      // في حالة خطأ التحليل، نرجع التكلفة الأساسية
      return productCost;
    }
  }

  /// الاقتراحات السريعة الافتراضية
  static const List<String> defaultSuggestions = [
    "تدقيق ذكي للفواتير",
    "تدقيق جميع أرصدة الديون",
    "ابحث عن عميل",
    "تصحيح أخطاء الديون تلقائياً",
    "فحص صحة الفواتير",
    "التحقق من المخزون والوحدات",
    "ملخص مبيعات هذا الشهر",
    "كشف الأخطاء المحاسبية",
    "تحليل دقة الأرباح",
    "كشف الكلاش في الأسعار",
    "أعلى 10 عملاء",
    "البضائع الراكدة",
    "تقرير أرباح السنة",
  ];

  /// معالجة رسالة المستخدم
  Future<ChatResponse> processMessage(String userMessage, {List<String>? conversationHistory}) async {
    try {
      // تحليل نية المستخدم
      final intent = await _analyzeIntent(userMessage);
    
      
      // تنفيذ الإجراء المناسب
      switch (intent.action) {
        case 'audit_debts':
          return await _auditAllDebts();
        case 'audit_invoices':
          return await _auditAllInvoices();
        case 'audit_invoices_ai':
          return await _auditInvoicesWithAI();
        case 'audit_inventory':
          return await _auditInventoryHierarchy();
        case 'sales_summary':
          return await _getSalesSummary(intent.params);
        case 'detect_anomalies':
          return await _detectAccountingAnomalies();
        case 'analyze_profit_accuracy':
          return await analyzeProfitAccuracy();
        case 'top_customers':
          return await _getTopCustomers(intent.params);
        case 'stagnant_stock':
          return await _getStagnantStock(intent.params);
        case 'profit_report':
          return await _generateProfitReport(intent.params);
        case 'fix_debts':
          return await autoFixDebtErrors();
        case 'fix_invoices':
          return await autoFixInvoiceErrors();
        case 'fix_inventory':
          return await recalculateInventory();
        case 'analyze_performance':
          return await analyzeFinancialPerformance();
        case 'recommendations':
          return await getSmartRecommendations();
        case 'search_customer':
          return await searchCustomerComplete(intent.params['customer_name'] ?? '');
        case 'search':
          return await searchEntity(intent.params['query'] ?? '');
        case 'general_query':
          return await _handleGeneralQuery(userMessage, conversationHistory);
        default:
          return ChatResponse(
            text: "عذرًا، لم أفهم طلبك. هل يمكنك إعادة الصياغة؟",
            followups: defaultSuggestions.take(4).toList(),
          );
      }
    } catch (e, stackTrace) {
      return ChatResponse(
        text: "حدث خطأ أثناء معالجة طلبك: ${e.toString()}",
        followups: ["إعادة المحاولة", "العودة للقائمة الرئيسية"],
        status: 'error',
      );
    }
  }

  /// تحليل نية المستخدم من الرسالة
  Future<UserIntent> _analyzeIntent(String message) async {
    final msg = message.toLowerCase();
    
    // تدقيق الديون
    if (msg.contains('تدقيق') && (msg.contains('دين') || msg.contains('رصد') || msg.contains('حساب'))) {
      return UserIntent(action: 'audit_debts');
    }
    
    // تدقيق الفواتير مع تحليل ذكي
    if ((msg.contains('تدقيق') && msg.contains('ذكي')) || 
        (msg.contains('تحليل') && msg.contains('ذكي')) || 
        (msg.contains('ذكي') && msg.contains('فاتور'))) {
      return UserIntent(action: 'audit_invoices_ai');
    }
    
    // تدقيق الفواتير
    if ((msg.contains('فحص') || msg.contains('تدقيق')) && msg.contains('فاتور')) {
      return UserIntent(action: 'audit_invoices');
    }
    
    // تدقيق المخزون
    if (msg.contains('مخزون') || msg.contains('وحدات') || msg.contains('هرمي')) {
      return UserIntent(action: 'audit_inventory');
    }
    
    // ملخص المبيعات
    if (msg.contains('مبيعات') || msg.contains('ملخص')) {
      return UserIntent(action: 'sales_summary', params: _extractDateParams(msg));
    }
    
    // كشف الأخطاء
    if (msg.contains('خطأ') || msg.contains('أخطاء') || msg.contains('كشف')) {
      return UserIntent(action: 'detect_anomalies');
    }
    
    // تحليل دقة الأرباح
    if (msg.contains('دقة') && (msg.contains('ربح') || msg.contains('أرباح'))) {
      return UserIntent(action: 'analyze_profit_accuracy');
    }
    
    // كلاش أو تضارب في الأسعار
    if (msg.contains('كلاش') || msg.contains('تضارب') || msg.contains('clash')) {
      return UserIntent(action: 'analyze_profit_accuracy');
    }
    
    // أعلى العملاء
    if (msg.contains('أعلى') && msg.contains('عملاء')) {
      return UserIntent(action: 'top_customers');
    }
    
    // البضائع الراكدة
    if (msg.contains('راكد') || msg.contains('مكدس')) {
      return UserIntent(action: 'stagnant_stock', params: _extractDaysParam(msg));
    }
    
    // تقرير الأرباح
    if (msg.contains('ربح') || msg.contains('تقرير')) {
      return UserIntent(action: 'profit_report', params: _extractDateParams(msg));
    }
    
    // تصحيح تلقائي
    if (msg.contains('تصحيح') || msg.contains('إصلاح')) {
      if (msg.contains('دين')) {
        return UserIntent(action: 'fix_debts');
      } else if (msg.contains('فاتور')) {
        return UserIntent(action: 'fix_invoices');
      } else if (msg.contains('مخزون')) {
        return UserIntent(action: 'fix_inventory');
      }
    }
    
    // تحليل الأداء
    if (msg.contains('أداء') || msg.contains('تحليل مالي')) {
      return UserIntent(action: 'analyze_performance');
    }
    
    // اقتراحات ذكية
    if (msg.contains('اقتراح') || msg.contains('توصي')) {
      return UserIntent(action: 'recommendations');
    }
    
    // البحث عن عميل محدد
    if ((msg.contains('ابحث') || msg.contains('اعرض') || msg.contains('أين')) && 
        (msg.contains('عميل') || msg.contains('زبون'))) {
      // استخراج اسم العميل من الرسالة
      String customerName = message
          .replaceAll(RegExp(r'ابحث|اعرض|أين|عن|عميل|زبون|ال'), '')
          .trim();
      return UserIntent(action: 'search_customer', params: {'customer_name': customerName});
    }
    
    // البحث العام
    if (msg.contains('ابحث') || msg.contains('أين') || msg.contains('اعرض')) {
      return UserIntent(action: 'search', params: {'query': message});
    }
    
    return UserIntent(action: 'general_query');
  }

  /// تدقيق شامل لجميع أرصدة الديون بذكاء عالي
  /// يستخدم نفس المنطق الذي يستخدمه كشف الحساب لضمان الدقة 100%
  Future<ChatResponse> _auditAllDebts() async {
    try {
      final db = await _dbService.database;
      final errors = <Map<String, dynamic>>[];
      
      // جلب جميع العملاء
      final customers = await db.query('customers');
      for (var customer in customers) {
        final customerId = customer['id'] as int;
        final customerName = customer['name'] as String;
        final displayedBalance = (customer['current_total_debt'] as num?)?.toDouble() ?? 0.0;
        
        // ═══════════════════════════════════════════════════════════
        // استخدام نفس المنطق الذي يستخدمه كشف الحساب
        // ═══════════════════════════════════════════════════════════
        
        // جلب جميع معاملات العميل مرتبة حسب التاريخ (نفس ترتيب كشف الحساب)
        final transactions = await db.query(
          'transactions',
          where: 'customer_id = ?',
          whereArgs: [customerId],
          orderBy: 'transaction_date ASC, created_at ASC', // نفس الترتيب في كشف الحساب
        );
        // حساب الرصيد من البداية (صفر) - نفس طريقة كشف الحساب
        double calculatedBalance = 0.0;
        
        // تحليل تفصيلي للمعاملات
        int debtTransactions = 0;
        int paymentTransactions = 0;
        double totalDebts = 0.0;
        double totalPayments = 0.0;
        final transactionDetails = <String>[];
        
        // حساب الرصيد معاملة بمعاملة (نفس طريقة كشف الحساب)
        for (int i = 0; i < transactions.length; i++) {
          final trans = transactions[i];
          final amount = (trans['amount_changed'] as num?)?.toDouble() ?? 0.0;
          final type = trans['transaction_type'] as String?;
          final date = trans['transaction_date'] as String?;
          
          // إضافة المبلغ للرصيد (نفس طريقة كشف الحساب)
          calculatedBalance += amount;
          
          // تصنيف المعاملة للتقرير
          if (amount > 0) {
            debtTransactions++;
            totalDebts += amount;
            transactionDetails.add(
              'معاملة ${i + 1} (${date ?? "بدون تاريخ"}): إضافة دين ${amount.toStringAsFixed(0)} دينار (${type ?? "يدوي"})'
            );
          } else if (amount < 0) {
            paymentTransactions++;
            totalPayments += amount.abs();
            transactionDetails.add(
              'معاملة ${i + 1} (${date ?? "بدون تاريخ"}): تسديد ${amount.abs().toStringAsFixed(0)} دينار (${type ?? "يدوي"})'
            );
          }
        }
        // مقارنة الرصيد المعروض مع المحسوب
        final diff = (displayedBalance - calculatedBalance).abs();
        
        if (diff > 0.01) { // هامش خطأ صغير للتعامل مع الأرقام العشرية
          errors.add({
            'customer': customerName,
            'displayedBalance': displayedBalance,
            'calculatedBalance': calculatedBalance,
            'difference': diff,
            'debtCount': debtTransactions,
            'paymentCount': paymentTransactions,
            'totalDebts': totalDebts,
            'totalPayments': totalPayments,
            'transactionCount': transactions.length,
            'details': transactionDetails,
          });
        }
      }
      
      if (errors.isEmpty) {
        return ChatResponse(
          text: "✅ تم تدقيق ${customers.length} عميل\n\n"
                "جميع الأرصدة صحيحة ومتطابقة مع المعاملات!",
          followups: ["تدقيق الفواتير", "فحص المخزون", "كشف أخطاء أخرى"],
          status: 'success',
        );
      } else {
        // بناء تقرير تفصيلي للأخطاء
        final report = StringBuffer();
        report.writeln('⚠️ وجدت ${errors.length} خطأ في الأرصدة:\n');
        
        for (int i = 0; i < errors.length; i++) {
          final error = errors[i];
          report.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          report.writeln('❌ خطأ ${i + 1}: العميل "${error['customer']}"\n');
          
          report.writeln('📊 الأرصدة:');
          report.writeln('   • الرصيد المعروض: ${(error['displayedBalance'] as double).toStringAsFixed(0)} دينار');
          report.writeln('   • الرصيد الصحيح: ${(error['calculatedBalance'] as double).toStringAsFixed(0)} دينار');
          report.writeln('   • الفرق: ${(error['difference'] as double).toStringAsFixed(0)} دينار\n');
          
          report.writeln('📝 التحليل (نفس طريقة كشف الحساب):');
          report.writeln('   • عدد معاملات الدين: ${error['debtCount']}');
          report.writeln('   • إجمالي الديون المضافة: ${(error['totalDebts'] as double).toStringAsFixed(0)} دينار');
          report.writeln('   • عدد معاملات التسديد: ${error['paymentCount']}');
          report.writeln('   • إجمالي المدفوعات: ${(error['totalPayments'] as double).toStringAsFixed(0)} دينار');
          report.writeln('   • إجمالي المعاملات: ${error['transactionCount']}\n');
          
          report.writeln('🔍 الحساب الصحيح (من أول معاملة):');
          report.writeln('   0 (البداية)');
          if ((error['totalDebts'] as double) > 0) {
            report.writeln('   + ${(error['totalDebts'] as double).toStringAsFixed(0)} (ديون مضافة)');
          }
          if ((error['totalPayments'] as double) > 0) {
            report.writeln('   - ${(error['totalPayments'] as double).toStringAsFixed(0)} (مدفوعات)');
          }
          report.writeln('   ─────────────────────');
          report.writeln('   = ${(error['calculatedBalance'] as double).toStringAsFixed(0)} دينار (الرصيد الصحيح)\n');
          
          // عرض تفاصيل المعاملات (أول 5 فقط لتجنب الإطالة)
          if ((error['details'] as List).isNotEmpty) {
            report.writeln('📋 تفاصيل المعاملات:');
            final details = error['details'] as List<String>;
            for (int j = 0; j < details.length && j < 5; j++) {
              report.writeln('   ${details[j]}');
            }
            if (details.length > 5) {
              report.writeln('   ... و${details.length - 5} معاملة أخرى');
            }
          }
          
          report.writeln();
        }
        
        report.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        report.writeln('\n💡 التوصية: استخدم أمر "تصحيح أخطاء الديون" لإصلاح هذه الأخطاء تلقائياً');
        
        return ChatResponse(
          text: report.toString(),
          followups: ["تصحيح الأخطاء تلقائيًا", "عرض التفاصيل الكاملة", "تصدير التقرير"],
          status: 'warning',
          data: {'errors': errors},
        );
      }
    } catch (e, stackTrace) {
      rethrow;
    }
  }

  /// تدقيق شامل لجميع الفواتير
  Future<ChatResponse> _auditAllInvoices() async {
    try {
      final db = await _dbService.database;
      final errors = <String>[];
      
      // جلب جميع الفواتير
      final invoices = await db.query('invoices');
      for (var invoice in invoices) {
        final invoiceId = invoice['id'] as int;
        final displayedTotal = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
        
        // جلب عناصر الفاتورة
        final items = await db.query(
          'invoice_items',
          where: 'invoice_id = ?',
          whereArgs: [invoiceId],
        );
        // حساب المجموع الفعلي من item_total
        double calculatedTotal = 0.0;
        for (var item in items) {
          // استخدام item_total مباشرة لأنه محسوب مسبقًا
          final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0.0;
          calculatedTotal += itemTotal;
        }
        
        // الحصول على الخصم وأجور التحميل من الفاتورة
        final discount = (invoice['discount'] as num?)?.toDouble() ?? 0.0;
        final loadingFee = (invoice['loading_fee'] as num?)?.toDouble() ?? 0.0;
        
        // المجموع الصحيح = مجموع البنود - الخصم + أجور التحميل
        final correctTotal = calculatedTotal - discount + loadingFee;
        
        // مقارنة المجموع (مع هامش خطأ صغير للأرقام العشرية)
        if ((displayedTotal - correctTotal).abs() > 0.01) {
          final difference = displayedTotal - correctTotal;
          
          // تحديد السبب المحتمل
          String possibleReason = "";
          if (difference > 0 && items.isEmpty) {
            possibleReason = "💡 السبب المحتمل: تم حذف جميع بنود الفاتورة دون تحديث المجموع";
          } else if (difference > 0) {
            possibleReason = "💡 السبب المحتمل: تم حذف بعض البنود من الفاتورة دون تحديث المجموع";
          } else if (difference < 0) {
            possibleReason = "💡 السبب المحتمل: تم إضافة بنود للفاتورة دون تحديث المجموع";
          }
          
          String errorMsg = "❌ خطأ في الفاتورة رقم: $invoiceId\n"
              "   المجموع المعروض: ${displayedTotal.toStringAsFixed(0)} دينار\n"
              "   ━━━━━━━━━━━━━━━━━━━━━━━━\n"
              "   📋 تفاصيل الحساب:\n"
              "   • مجموع البنود: ${calculatedTotal.toStringAsFixed(0)} دينار\n"
              "   • الخصم: ${discount.toStringAsFixed(0)} دينار\n"
              "   • أجور التحميل: ${loadingFee.toStringAsFixed(0)} دينار\n"
              "   • عدد العناصر: ${items.length}\n"
              "   ━━━━━━━━━━━━━━━━━━━━━━━━\n"
              "   المجموع الصحيح: ${correctTotal.toStringAsFixed(0)} دينار\n"
              "   الفرق: ${difference.abs().toStringAsFixed(0)} دينار ${difference > 0 ? '(زيادة)' : '(نقصان)'} ⚠️\n\n"
              "   $possibleReason";
          
          errors.add(errorMsg);
        }
      }
      
      if (errors.isEmpty) {
        return ChatResponse(
          text: "✅ تم تدقيق ${invoices.length} فاتورة\n\n"
                "جميع مجاميع الفواتير صحيحة!",
          followups: ["تدقيق الديون", "فحص المخزون"],
          status: 'success',
        );
      } else {
        return ChatResponse(
          text: "⚠️ وجدت ${errors.length} خطأ في الفواتير:\n\n${errors.join('\n\n')}",
          followups: ["تصحيح الأخطاء", "عرض الفواتير المتأثرة"],
          status: 'warning',
          data: {'errors': errors},
        );
      }
    } catch (e, stackTrace) {
      rethrow;
    }
  }

  /// تدقيق النظام الهرمي للوحدات (قطعة - باكية - سيات - كرتون)
  Future<ChatResponse> _auditInventoryHierarchy() async {
    // ملاحظة: جدول inventory غير موجود في قاعدة البيانات الحالية
    // سيتم تفعيل هذه الميزة عند إضافة الجدول
    return ChatResponse(
      text: "⚠️ ميزة تدقيق المخزون غير متاحة حاليًا\n\n"
            "جدول المخزون (inventory) غير موجود في قاعدة البيانات.\n"
            "يمكنك استخدام الميزات الأخرى للتدقيق.",
      followups: ["تدقيق الديون", "فحص الفواتير", "كشف أخطاء أخرى"],
      status: 'warning',
    );
    
    /* الكود الأصلي - سيتم تفعيله عند إضافة جدول inventory
    try {
      final db = await _dbService.database;
      final errors = <String>[];
      
      // جلب جميع المنتجات
      final products = await db.query('products');
      for (var product in products) {
        final productId = product['id'] as int;
        final productName = product['name'] ?? 'غير معروف';
        // التحقق من الوحدات الهرمية
        final piecePerPacket = (product['piece_per_packet'] as int?) ?? 1;
        final packetPerCarton = (product['packet_per_carton'] as int?) ?? 1;
        final cartonPerSiat = (product['carton_per_siat'] as int?) ?? 1;
        
        // التحقق من القيم المنطقية
        if (piecePerPacket <= 0 || packetPerCarton <= 0 || cartonPerSiat <= 0) {
          errors.add(
            "❌ خطأ في وحدات المنتج: $productName\n"
            "   قطعة/باكية: $piecePerPacket\n"
            "   باكية/كرتون: $packetPerCarton\n"
            "   كرتون/سيات: $cartonPerSiat"
          );
        }
        
        // التحقق من الكميات في المخزون
        final stock = await db.query(
          'inventory',
          where: 'product_id = ?',
          whereArgs: [productId],
        );
        
        if (stock.isNotEmpty) {
          final stockRecord = stock.first;
          final totalPieces = (stockRecord['total_pieces'] as int?) ?? 0;
          
          // حساب القطع من الوحدات الأخرى
          final siats = (stockRecord['siats'] as int?) ?? 0;
          final cartons = (stockRecord['cartons'] as int?) ?? 0;
          final packets = (stockRecord['packets'] as int?) ?? 0;
          final pieces = (stockRecord['pieces'] as int?) ?? 0;
          
          final calculatedPieces = 
            (siats * cartonPerSiat * packetPerCarton * piecePerPacket) +
            (cartons * packetPerCarton * piecePerPacket) +
            (packets * piecePerPacket) +
            pieces;
          
          if (totalPieces != calculatedPieces) {
            errors.add(
              "❌ خطأ في حساب المخزون: $productName\n"
              "   القطع المعروضة: $totalPieces\n"
              "   القطع المحسوبة: $calculatedPieces\n"
              "   (سيات: $siats، كرتون: $cartons، باكية: $packets، قطعة: $pieces)"
            );
          }
        }
      }
      
      if (errors.isEmpty) {
        return ChatResponse(
          text: "✅ تم تدقيق ${products.length} منتج\n\n"
                "جميع الوحدات الهرمية والمخزون صحيحة!",
          followups: ["تدقيق الديون", "فحص الفواتير"],
          status: 'success',
        );
      } else {
        return ChatResponse(
          text: "⚠️ وجدت ${errors.length} خطأ في المخزون:\n\n${errors.join('\n\n')}",
          followups: ["تصحيح الأخطاء", "إعادة حساب المخزون"],
          status: 'warning',
          data: {'errors': errors},
        );
      }
    } catch (e, stackTrace) {
      rethrow;
    }
    */
  }

  /// ملخص المبيعات المفصل
  Future<ChatResponse> _getSalesSummary(Map<String, dynamic> params) async {
    try {
      final db = await _dbService.database;
      
      // جلب إعدادات التطبيق لنسبة الربح
      final settings = await SettingsManager.getAppSettings();
      final adHocProfit = settings.defaultAdHocProfitPercentage / 100.0;
      
      // تحديد الفترة الزمنية
      final now = DateTime.now();
      final startDate = params['start_date'] ?? DateTime(now.year, now.month, 1);
      final endDate = params['end_date'] ?? now;
      // جلب الفواتير في الفترة
      final invoices = await db.query(
        'invoices',
        where: 'invoice_date BETWEEN ? AND ?',
        whereArgs: [startDate.toIso8601String(), endDate.toIso8601String()],
      );
      double totalSales = 0.0;
      double totalCost = 0.0;
      double totalProfit = 0.0;
      
      for (var invoice in invoices) {
        final invoiceId = invoice['id'] as int;
        final totalAmount = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
        
        totalSales += totalAmount;
        
        // جلب بنود الفاتورة لحساب التكلفة
        final items = await db.query(
          'invoice_items',
          where: 'invoice_id = ?',
          whereArgs: [invoiceId],
        );
        
        double invoiceCost = 0.0;
        for (var item in items) {
          final qty = (item['quantity_individual'] as num?)?.toDouble() ?? 0.0;
          final qtyLarge = (item['quantity_large_unit'] as num?)?.toDouble() ?? 0.0;
          final unitsInLarge = (item['units_in_large_unit'] as num?)?.toDouble() ?? 1.0;
          final appliedPrice = (item['applied_price'] as num?)?.toDouble() ?? 0.0;
          double costPrice = (item['cost_price'] as num?)?.toDouble() ?? 0.0;
          final actualCostPrice = (item['actual_cost_price'] as num?)?.toDouble();
          
          // استخدام التكلفة الفعلية إذا كانت متوفرة
          if (actualCostPrice != null && actualCostPrice > 0) {
            costPrice = actualCostPrice;
          }
          
          // 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط
          if (costPrice <= 0 && appliedPrice > 0) {
            costPrice = MoneyCalculator.getEffectiveCost(0, appliedPrice);
          }
          
          // حساب التكلفة الفعلية مع مراعاة الوحدات الكبيرة
          if (qtyLarge > 0) {
            invoiceCost += (qtyLarge * costPrice);
          } else {
            invoiceCost += (qty * costPrice);
          }
        }
        
        totalCost += invoiceCost;
      }
      
      // الربح = المبيعات - التكلفة
      totalProfit = totalSales - totalCost;
      
      // نسبة الربح
      final profitMargin = totalSales > 0 ? (totalProfit / totalSales) * 100 : 0.0;
      return ChatResponse(
        text: "📊 ملخص المبيعات\n\n"
              "الفترة: ${_formatDate(startDate)} - ${_formatDate(endDate)}\n"
              "عدد الفواتير: ${invoices.length}\n"
              "إجمالي المبيعات: ${totalSales.toStringAsFixed(0)} دينار\n"
              "إجمالي التكلفة: ${totalCost.toStringAsFixed(0)} دينار\n"
              "إجمالي الأرباح: ${totalProfit.toStringAsFixed(0)} دينار\n"
              "نسبة الربح: ${profitMargin.toStringAsFixed(2)}%",
        followups: ["تفاصيل حسب المنتج", "أعلى 10 عملاء", "تقرير الأرباح"],
        status: 'success',
        data: {
          'total_sales': totalSales,
          'total_cost': totalCost,
          'total_profit': totalProfit,
          'profit_margin': profitMargin,
          'count': invoices.length
        },
      );
      
    } catch (e, stackTrace) {
      return ChatResponse(
        text: '❌ حدث خطأ أثناء إنشاء ملخص المبيعات:\n\n$e',
        followups: ["المحاولة مرة أخرى", "تقرير الأرباح"],
        status: 'error',
      );
    }
  }

  /// كشف الأخطاء المحاسبية بتفاصيل كاملة
  Future<ChatResponse> _detectAccountingAnomalies() async {
    final report = StringBuffer();
    report.writeln('🔍 فحص شامل للنظام\n');
    report.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    bool hasErrors = false;
    final List<String> followups = [];
    
    // 1. تدقيق الديون
    final debtResult = await _auditAllDebts();
    if (debtResult.status == 'warning') {
      hasErrors = true;
      report.writeln('🔴 أخطاء في أرصدة الديون:\n');
      report.writeln(debtResult.text);
      report.writeln('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      followups.add('تصحيح أخطاء الديون تلقائياً');
    } else {
      report.writeln('✅ أرصدة الديون: صحيحة\n');
    }
    
    // 2. تدقيق الفواتير
    final invoiceResult = await _auditAllInvoices();
    if (invoiceResult.status == 'warning') {
      hasErrors = true;
      report.writeln('🔴 أخطاء في مجاميع الفواتير:\n');
      report.writeln(invoiceResult.text);
      report.writeln('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      followups.add('تصحيح أخطاء الفواتير تلقائياً');
    } else {
      report.writeln('✅ مجاميع الفواتير: صحيحة\n');
    }
    
    // 3. تدقيق المخزون
    final inventoryResult = await _auditInventoryHierarchy();
    if (inventoryResult.status == 'warning') {
      hasErrors = true;
      report.writeln('🔴 أخطاء في حسابات المخزون:\n');
      report.writeln(inventoryResult.text);
      report.writeln('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      followups.add('إعادة حساب المخزون');
    } else {
      report.writeln('✅ حسابات المخزون: صحيحة\n');
    }
    
    report.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    if (!hasErrors) {
      return ChatResponse(
        text: "✅ فحص شامل للنظام\n\n"
              "لم يتم العثور على أي أخطاء محاسبية!\n"
              "النظام يعمل بدقة عالية.",
        followups: ["ملخص المبيعات", "تقرير الأرباح", "تدقيق الديون"],
        status: 'success',
      );
    } else {
      return ChatResponse(
        text: report.toString(),
        followups: followups.isNotEmpty ? followups : ["تصحيح جميع الأخطاء"],
        status: 'warning',
      );
    }
  }

  /// أعلى العملاء
  Future<ChatResponse> _getTopCustomers(Map<String, dynamic> params) async {
    final db = await _dbService.database;
    final limit = params['limit'] ?? 10;
    
    final result = await db.rawQuery('''
      SELECT customer_name, SUM(total_amount) as total_purchases, COUNT(*) as invoice_count
      FROM invoices
      WHERE customer_name IS NOT NULL
      GROUP BY customer_name
      ORDER BY total_purchases DESC
      LIMIT ?
    ''', [limit]);
    
    final customersList = result.map((row) {
      final name = row['customer_name'] ?? 'غير معروف';
      final total = (row['total_purchases'] as num?)?.toDouble() ?? 0.0;
      final count = row['invoice_count'] ?? 0;
      return "• $name: ${total.toStringAsFixed(0)} دينار ($count فاتورة)";
    }).join('\n');
    
    return ChatResponse(
      text: "👥 أعلى $limit عملاء:\n\n$customersList",
      followups: ["تفاصيل عميل محدد", "تقرير PDF"],
      status: 'success',
      data: {'customers': result},
    );
  }

  /// البضائع الراكدة
  Future<ChatResponse> _getStagnantStock(Map<String, dynamic> params) async {
    final db = await _dbService.database;
    final days = params['days'] ?? 90;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    
    final result = await db.rawQuery('''
      SELECT p.name, i.total_pieces, i.last_updated
      FROM products p
      JOIN inventory i ON p.id = i.product_id
      WHERE i.last_updated < ? AND i.total_pieces > 0
      ORDER BY i.last_updated ASC
    ''', [cutoffDate.toIso8601String()]);
    
    if (result.isEmpty) {
      return ChatResponse(
        text: "✅ لا توجد بضائع راكدة منذ $days يوم",
        followups: ["فحص فترة أطول", "ملخص المخزون"],
        status: 'success',
      );
    }
    
    final stockList = result.map((row) {
      final name = row['name'] ?? 'غير معروف';
      final pieces = row['total_pieces'] ?? 0;
      return "• $name: $pieces قطعة";
    }).join('\n');
    
    return ChatResponse(
      text: "📦 بضائع راكدة منذ $days يوم:\n\n$stockList",
      followups: ["اقتراح عروض", "تقرير مفصل"],
      status: 'warning',
      data: {'stagnant_items': result},
    );
  }

  /// تقرير الأرباح المفصل
  Future<ChatResponse> _generateProfitReport(Map<String, dynamic> params) async {
    try {
      final db = await _dbService.database;
      
      // جلب جميع الفواتير
      final invoices = await db.query('invoices');
      double totalSales = 0.0;
      double totalProfit = 0.0;
      int invoiceCount = 0;
      
      for (var invoice in invoices) {
        final invoiceId = invoice['id'] as int;
        final totalAmount = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
        
        // جلب بنود الفاتورة
        final items = await db.query(
          'invoice_items',
          where: 'invoice_id = ?',
          whereArgs: [invoiceId],
        );
        
        double invoiceCost = 0.0;
        for (var item in items) {
          final qty = (item['quantity_individual'] as num?)?.toDouble() ?? 0.0;
          final qtyLarge = (item['quantity_large_unit'] as num?)?.toDouble() ?? 0.0;
          final appliedPrice = (item['applied_price'] as num?)?.toDouble() ?? 0.0;
          double costPrice = (item['cost_price'] as num?)?.toDouble() ?? 0.0;
          final actualCostPrice = (item['actual_cost_price'] as num?)?.toDouble();
          
          // استخدام التكلفة الفعلية إذا كانت متوفرة
          if (actualCostPrice != null && actualCostPrice > 0) {
            costPrice = actualCostPrice;
          }
          
          // 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط
          if (costPrice <= 0 && appliedPrice > 0) {
            costPrice = MoneyCalculator.getEffectiveCost(0, appliedPrice);
          }
          
          // حساب التكلفة الفعلية مع مراعاة الوحدات الكبيرة
          if (qtyLarge > 0) {
            invoiceCost += (qtyLarge * costPrice);
          } else {
            invoiceCost += (qty * costPrice);
          }
        }
        
        // حساب الربح = المبيعات - التكلفة
        final invoiceProfit = totalAmount - invoiceCost;
        
        totalSales += totalAmount;
        totalProfit += invoiceProfit;
        invoiceCount++;
      }
      
      // حساب نسبة الربح
      final profitMargin = totalSales > 0 ? (totalProfit / totalSales) * 100 : 0.0;
      final report = StringBuffer();
      report.writeln('📊 تقرير الأرباح\n');
      report.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      report.writeln('📈 إجمالي المبيعات: ${totalSales.toStringAsFixed(0)} دينار');
      report.writeln('💰 إجمالي الأرباح: ${totalProfit.toStringAsFixed(0)} دينار');
      report.writeln('📊 نسبة الربح: ${profitMargin.toStringAsFixed(2)}%');
      report.writeln('📄 عدد الفواتير: $invoiceCount\n');
      
      if (invoiceCount > 0) {
        final avgSale = totalSales / invoiceCount;
        final avgProfit = totalProfit / invoiceCount;
        report.writeln('📊 متوسط المبيعات للفاتورة: ${avgSale.toStringAsFixed(0)} دينار');
        report.writeln('💰 متوسط الربح للفاتورة: ${avgProfit.toStringAsFixed(0)} دينار');
      }
      
      report.writeln('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      return ChatResponse(
        text: report.toString(),
        followups: ["ملخص المبيعات", "أعلى 10 عملاء", "تدقيق الديون"],
        status: 'success',
        data: {
          'totalSales': totalSales,
          'totalProfit': totalProfit,
          'profitMargin': profitMargin,
          'invoiceCount': invoiceCount,
        },
      );
      
    } catch (e, stackTrace) {
      return ChatResponse(
        text: '❌ حدث خطأ أثناء إنشاء تقرير الأرباح:\n\n$e',
        followups: ["المحاولة مرة أخرى", "ملخص المبيعات"],
        status: 'error',
      );
    }
  }


  // Helper methods
  Map<String, dynamic> _extractDateParams(String message) {
    // استخراج التواريخ من الرسالة
    return {};
  }

  Map<String, dynamic> _extractDaysParam(String message) {
    // استخراج عدد الأيام
    final match = RegExp(r'(\d+)\s*يوم').firstMatch(message);
    if (match != null) {
      return {'days': int.parse(match.group(1)!)};
    }
    return {};
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  /// تصحيح تلقائي لأخطاء الديون بذكاء عالي
  Future<ChatResponse> autoFixDebtErrors() async {
    try {
      final db = await _dbService.database;
      int fixedCount = 0;
      int errorCount = 0;
      final fixedCustomers = <String>[];
      final failedCustomers = <String>[];
      
      // جلب جميع العملاء
      final customers = await db.query('customers');
      for (var customer in customers) {
        final customerId = customer['id'] as int;
        final customerName = customer['name'] as String;
        final displayedBalance = (customer['current_total_debt'] as num?)?.toDouble() ?? 0.0;
        
        try {
          // حساب الرصيد الصحيح من جميع المعاملات
          final transactions = await db.query(
            'transactions',
            where: 'customer_id = ?',
            whereArgs: [customerId],
            orderBy: 'transaction_date ASC, id ASC',
          );
          
          double correctBalance = 0.0;
          for (var trans in transactions) {
            final amount = (trans['amount_changed'] as num?)?.toDouble() ?? 0.0;
            correctBalance += amount;
          }
          
          // التحقق من وجود خطأ
          final diff = (displayedBalance - correctBalance).abs();
          
          if (diff > 0.01) {
            // تحديث الرصيد باستخدام دالة database_service
            await _dbService.recalculateAndApplyCustomerDebt(customerId);
            
            fixedCount++;
            fixedCustomers.add(
              '$customerName: ${displayedBalance.toStringAsFixed(0)} ← ${correctBalance.toStringAsFixed(0)} دينار'
            );
          }
        } catch (e) {
          errorCount++;
          failedCustomers.add('$customerName: $e');
        }
      }
      // بناء التقرير
      final report = StringBuffer();
      
      if (fixedCount > 0) {
        report.writeln('✅ تم تصحيح $fixedCount عميل تلقائياً:\n');
        for (final fix in fixedCustomers) {
          report.writeln('   • $fix');
        }
        report.writeln();
      }
      
      if (errorCount > 0) {
        report.writeln('⚠️ فشل تصحيح $errorCount عميل:\n');
        for (final fail in failedCustomers) {
          report.writeln('   • $fail');
        }
        report.writeln();
      }
      
      if (fixedCount == 0 && errorCount == 0) {
        report.writeln('✅ جميع الأرصدة صحيحة بالفعل!\n');
        report.writeln('لا توجد أخطاء تحتاج للتصحيح.');
      } else {
        report.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        report.writeln('\n💡 تم إعادة حساب جميع الأرصدة من المعاملات المسجلة');
      }
      
      return ChatResponse(
        text: report.toString(),
        followups: ["تدقيق مرة أخرى", "فحص الفواتير", "كشف أخطاء أخرى"],
        status: fixedCount > 0 ? 'success' : 'info',
      );
      
    } catch (e, stackTrace) {
      return ChatResponse(
        text: '❌ حدث خطأ أثناء التصحيح التلقائي:\n\n$e',
        followups: ["المحاولة مرة أخرى", "تدقيق الديون"],
        status: 'error',
      );
    }
  }

  /// تصحيح مجاميع الفواتير (إعادة حساب من البنود + أجور التحميل - الخصم)
  Future<ChatResponse> _fixInvoiceTotals() async {
    try {
      final result = await _dbService.recalculateAllInvoiceTotals();
      
      if (result['success']) {
        final fixed = result['fixed'] as int;
        final total = result['total_invoices'] as int;
        final details = result['details'] as List<String>;
        
        String message = '✅ تم إعادة حساب $total فاتورة\n\n';
        
        if (fixed > 0) {
          message += '🔧 تم تصحيح $fixed فاتورة:\n\n';
          for (var detail in details.take(10)) {
            message += '• $detail\n';
          }
          if (details.length > 10) {
            message += '\n... و ${details.length - 10} فاتورة أخرى';
          }
        } else {
          message += '✅ جميع الفواتير صحيحة!';
        }
        
        return ChatResponse(
          text: message,
          followups: ['تدقيق الفواتير', 'كشف الأخطاء'],
          status: fixed > 0 ? 'success' : 'info',
        );
      } else {
        return ChatResponse(
          text: '❌ حدث خطأ: ${result['error']}',
          followups: ['إعادة المحاولة'],
          status: 'error',
        );
      }
    } catch (e) {
      return ChatResponse(
        text: '❌ حدث خطأ أثناء التصحيح: $e',
        followups: ['إعادة المحاولة'],
        status: 'error',
      );
    }
  }

  /// تصحيح تلقائي لأخطاء الفواتير
  Future<ChatResponse> autoFixInvoiceErrors() async {
    final db = await _dbService.database;
    int fixedCount = 0;
    
    final invoices = await db.query('invoices');
    
    for (var invoice in invoices) {
      final invoiceId = invoice['id'] as int;
      
      // حساب المجموع الصحيح
      final items = await db.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );
      
      double correctTotal = 0.0;
      for (var item in items) {
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        correctTotal += quantity * price;
      }
      
      // تحديث المجموع
      await db.update(
        'invoices',
        {'total': correctTotal},
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
      fixedCount++;
    }
    
    return ChatResponse(
      text: "✅ تم تصحيح $fixedCount فاتورة تلقائيًا\n\n"
            "جميع المجاميع الآن صحيحة.",
      followups: ["تدقيق مرة أخرى", "فحص المخزون"],
      status: 'success',
    );
  }

  /// إعادة حساب المخزون بالكامل
  Future<ChatResponse> recalculateInventory() async {
    final db = await _dbService.database;
    int fixedCount = 0;
    
    final products = await db.query('products');
    
    for (var product in products) {
      final productId = product['id'] as int;
      
      final piecePerPacket = (product['piece_per_packet'] as int?) ?? 1;
      final packetPerCarton = (product['packet_per_carton'] as int?) ?? 1;
      final cartonPerSiat = (product['carton_per_siat'] as int?) ?? 1;
      
      final stock = await db.query(
        'inventory',
        where: 'product_id = ?',
        whereArgs: [productId],
      );
      
      if (stock.isNotEmpty) {
        final stockRecord = stock.first;
        final siats = (stockRecord['siats'] as int?) ?? 0;
        final cartons = (stockRecord['cartons'] as int?) ?? 0;
        final packets = (stockRecord['packets'] as int?) ?? 0;
        final pieces = (stockRecord['pieces'] as int?) ?? 0;
        
        final correctTotalPieces = 
          (siats * cartonPerSiat * packetPerCarton * piecePerPacket) +
          (cartons * packetPerCarton * piecePerPacket) +
          (packets * piecePerPacket) +
          pieces;
        
        await db.update(
          'inventory',
          {'total_pieces': correctTotalPieces},
          where: 'product_id = ?',
          whereArgs: [productId],
        );
        fixedCount++;
      }
    }
    
    return ChatResponse(
      text: "✅ تم إعادة حساب $fixedCount منتج في المخزون\n\n"
            "جميع الكميات الآن صحيحة.",
      followups: ["تدقيق المخزون", "عرض التقرير"],
      status: 'success',
    );
  }

  /// تحليل الأداء المالي
  Future<ChatResponse> analyzeFinancialPerformance() async {
    final db = await _dbService.database;
    
    // المبيعات الشهرية
    final thisMonth = DateTime.now();
    final lastMonth = DateTime(thisMonth.year, thisMonth.month - 1);
    
    final thisMonthSales = await db.rawQuery('''
      SELECT SUM(total_amount) as total, SUM(total_amount - discount) as profit
      FROM invoices
      WHERE strftime('%Y-%m', invoice_date) = ?
    ''', ['${thisMonth.year}-${thisMonth.month.toString().padLeft(2, '0')}']);
    
    final lastMonthSales = await db.rawQuery('''
      SELECT SUM(total_amount) as total, SUM(total_amount - discount) as profit
      FROM invoices
      WHERE strftime('%Y-%m', invoice_date) = ?
    ''', ['${lastMonth.year}-${lastMonth.month.toString().padLeft(2, '0')}']);
    
    final thisTotal = (thisMonthSales.first['total'] as num?)?.toDouble() ?? 0.0;
    final lastTotal = (lastMonthSales.first['total'] as num?)?.toDouble() ?? 0.0;
    final thisProfit = (thisMonthSales.first['profit'] as num?)?.toDouble() ?? 0.0;
    
    final growth = lastTotal > 0 ? ((thisTotal - lastTotal) / lastTotal * 100) : 0.0;
    
    // إجمالي الديون
    final debts = await db.rawQuery('SELECT SUM(current_total_debt) as total FROM customers');
    final totalDebts = (debts.first['total'] as num?)?.toDouble() ?? 0.0;
    
    // قيمة المخزون
    final inventory = await db.rawQuery('''
      SELECT SUM(i.total_pieces * p.cost_price) as total
      FROM inventory i
      JOIN products p ON i.product_id = p.id
    ''');
    final inventoryValue = (inventory.first['total'] as num?)?.toDouble() ?? 0.0;
    
    return ChatResponse(
      text: "📊 تحليل الأداء المالي\n\n"
            "🔹 مبيعات هذا الشهر: ${thisTotal.toStringAsFixed(0)} دينار\n"
            "🔹 الأرباح: ${thisProfit.toStringAsFixed(0)} دينار\n"
            "🔹 النمو: ${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)}%\n\n"
            "💰 إجمالي الديون: ${totalDebts.toStringAsFixed(0)} دينار\n"
            "📦 قيمة المخزون: ${inventoryValue.toStringAsFixed(0)} دينار\n\n"
            "${_getPerformanceInsight(growth, thisProfit, totalDebts)}",
      followups: ["تفاصيل أكثر", "اقتراحات للتحسين", "تقرير PDF"],
      status: 'success',
      data: {
        'sales': thisTotal,
        'profit': thisProfit,
        'growth': growth,
        'debts': totalDebts,
        'inventory': inventoryValue,
      },
    );
  }

  String _getPerformanceInsight(double growth, double profit, double debts) {
    if (growth > 10) {
      return "✨ أداء ممتاز! المبيعات في نمو مستمر.";
    } else if (growth > 0) {
      return "👍 أداء جيد، استمر في التحسين.";
    } else if (growth > -10) {
      return "⚠️ انخفاض طفيف، راجع استراتيجية المبيعات.";
    } else {
      return "🔴 تحذير: انخفاض كبير في المبيعات!";
    }
  }

  /// اقتراحات ذكية للتحسين
  Future<ChatResponse> getSmartRecommendations() async {
    final db = await _dbService.database;
    final recommendations = <String>[];
    
    // فحص البضائع الراكدة
    final stagnant = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM inventory i
      WHERE i.last_updated < date('now', '-90 days')
      AND i.total_pieces > 0
    ''');
    
    if ((stagnant.first['count'] as int) > 0) {
      recommendations.add("📦 لديك بضائع راكدة منذ أكثر من 90 يوم - اقترح عروض خاصة");
    }
    
    // فحص الديون المتأخرة
    final overdueDebts = await db.rawQuery('''
      SELECT COUNT(DISTINCT c.id) as count
      FROM customers c
      JOIN transactions t ON c.id = t.customer_id
      WHERE c.current_total_debt > 0
      AND t.date < date('now', '-30 days')
    ''');
    
    if ((overdueDebts.first['count'] as int) > 0) {
      recommendations.add("💰 لديك ديون متأخرة - تواصل مع العملاء للتحصيل");
    }
    
    // فحص المنتجات الأكثر مبيعًا
    final topProducts = await db.rawQuery('''
      SELECT p.name, SUM(ii.quantity) as total_sold
      FROM invoice_items ii
      JOIN products p ON ii.product_id = p.id
      WHERE ii.invoice_id IN (
        SELECT id FROM invoices WHERE invoice_date > date('now', '-30 days')
      )
      GROUP BY p.id
      ORDER BY total_sold DESC
      LIMIT 3
    ''');
    
    if (topProducts.isNotEmpty) {
      final topProduct = topProducts.first['name'];
      recommendations.add("⭐ المنتج الأكثر مبيعًا: $topProduct - تأكد من توفره دائمًا");
    }
    
    // فحص المخزون المنخفض
    final lowStock = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM inventory
      WHERE total_pieces < 100
    ''');
    
    if ((lowStock.first['count'] as int) > 0) {
      recommendations.add("⚠️ بعض المنتجات مخزونها منخفض - راجع قائمة الطلبات");
    }
    
    if (recommendations.isEmpty) {
      return ChatResponse(
        text: "✅ كل شيء يسير بشكل جيد!\n\n"
              "لا توجد توصيات عاجلة في الوقت الحالي.",
        followups: ["تحليل الأداء", "تقرير شامل"],
        status: 'success',
      );
    }
    
    return ChatResponse(
      text: "💡 اقتراحات ذكية للتحسين:\n\n${recommendations.map((r) => '• $r').join('\n\n')}",
      followups: ["تفاصيل البضائع الراكدة", "قائمة الديون المتأخرة", "المنتجات الأكثر مبيعًا"],
      status: 'success',
    );
  }

  /// البحث عن عميل أو منتج محدد
  Future<ChatResponse> searchEntity(String query) async {
    final db = await _dbService.database;
    
    // البحث في العملاء
    final customers = await db.query(
      'customers',
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
      limit: 5,
    );
    
    // البحث في المنتجات
    final products = await db.query(
      'products',
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
      limit: 5,
    );
    
    if (customers.isEmpty && products.isEmpty) {
      return ChatResponse(
        text: "لم أجد نتائج لـ \"$query\"",
        followups: ["بحث آخر", "العودة للقائمة"],
      );
    }
    
    String result = "🔍 نتائج البحث عن \"$query\":\n\n";
    
    if (customers.isNotEmpty) {
      result += "👥 العملاء:\n";
      for (var customer in customers) {
        final name = customer['name'];
        final balance = (customer['current_total_debt'] as num?)?.toDouble() ?? 0.0;
        result += "• $name (رصيد: ${balance.toStringAsFixed(0)} دينار)\n";
      }
      result += "\n";
    }
    
    if (products.isNotEmpty) {
      result += "📦 المنتجات:\n";
      for (var product in products) {
        final name = product['name'];
        result += "• $name\n";
      }
    }
    
    return ChatResponse(
      text: result,
      followups: ["تفاصيل العميل", "تفاصيل المنتج", "بحث جديد"],
      status: 'success',
    );
  }

  /// تحليل دقة حساب الأرباح مع الذكاء الاصطناعي
  /// يستخدم التحليل المحلي فقط (تم إزالة خدمات AI الخارجية)
  Future<ChatResponse> analyzeProfitAccuracyWithAI() async {
    // استخدام التحليل المحلي فقط
    return await analyzeProfitAccuracy();
  }

  /// تحليل دقة حساب الأرباح واكتشاف الأخطاء (Clash Detection)
  /// يستخدم نفس المنطق الدقيق من getMonthlySalesSummary و getProductSalesData
  Future<ChatResponse> analyzeProfitAccuracy() async {
    try {
      final db = await _dbService.database;
      final report = StringBuffer();
      final List<String> warnings = [];
      final List<String> errors = [];
      
      report.writeln('📊 تحليل دقة حساب الأرباح (بمنطق الجرد الشهري)\n');
      report.writeln('=' * 50);
      report.writeln();
      
      // جلب الفواتير المحفوظة
      final invoices = await db.query('invoices', where: 'status = ?', whereArgs: ['محفوظة']);
      report.writeln('✅ عدد الفواتير: ${invoices.length}\n');
      
      double totalSalesFromInvoices = 0.0;
      double totalCostCalculated = 0.0;
      int invoicesWithLowProfit = 0;
      int invoicesWithNegativeProfit = 0;
      int invoicesWithWrongTotal = 0;
      
      for (var invoiceMap in invoices) {
        final invoiceId = invoiceMap['id'] as int;
        final displayedTotal = (invoiceMap['total_amount'] as num).toDouble();
        final discount = (invoiceMap['discount'] as num?)?.toDouble() ?? 0.0;
        final returnAmount = (invoiceMap['return_amount'] as num?)?.toDouble() ?? 0.0;
        
        // جلب بنود الفاتورة مع بيانات المنتج الكاملة (نفس منطق الجرد الشهري)
        final List<Map<String, dynamic>> itemRows = await db.rawQuery('''
          SELECT 
            ii.quantity_individual AS qi,
            ii.quantity_large_unit AS ql,
            ii.units_in_large_unit AS uilu,
            ii.item_total AS item_total,
            ii.cost_price AS item_cost_total,
            ii.actual_cost_price AS actual_cost_per_unit,
            ii.applied_price AS selling_price,
            ii.sale_type AS sale_type,
            p.unit AS product_unit,
            p.cost_price AS product_cost_price,
            p.length_per_unit AS length_per_unit,
            p.unit_costs AS unit_costs,
            p.name AS product_name
          FROM invoice_items ii
          LEFT JOIN products p ON p.name = ii.product_name
          WHERE ii.invoice_id = ?
        ''', [invoiceId]);
        
        // 1. التحقق من صحة المجموع (إعادة الجمع)
        double calculatedItemsTotal = 0.0;
        for (final row in itemRows) {
          final itemTotal = (row['item_total'] as num?)?.toDouble() ?? 0.0;
          calculatedItemsTotal += itemTotal;
        }
        
        // الحصول على أجور التحميل
        final loadingFee = (invoiceMap['loading_fee'] as num?)?.toDouble() ?? 0.0;
        
        // المجموع الصحيح = مجموع البنود - الخصم + أجور التحميل
        final correctTotal = calculatedItemsTotal - discount + loadingFee;
        
        if ((displayedTotal - correctTotal).abs() > 0.01) {
          invoicesWithWrongTotal++;
          errors.add('❌ الفاتورة #$invoiceId: خطأ في المجموع\n'
              '   المعروض: ${displayedTotal.toStringAsFixed(0)} د.ع\n'
              '   مجموع البنود: ${calculatedItemsTotal.toStringAsFixed(0)} د.ع\n'
              '   الخصم: ${discount.toStringAsFixed(0)} د.ع\n'
              '   الصحيح: ${correctTotal.toStringAsFixed(0)} د.ع');
        }
        
        totalSalesFromInvoices += displayedTotal;
        
        // 2. حساب التكلفة الدقيقة (نفس منطق الجرد الشهري)
        double invoiceCost = 0.0;
        for (final row in itemRows) {
          final double qi = (row['qi'] as num?)?.toDouble() ?? 0.0;
          final double ql = (row['ql'] as num?)?.toDouble() ?? 0.0;
          final double uilu = (row['uilu'] as num?)?.toDouble() ?? 0.0;
          final String saleType = (row['sale_type'] as String?) ?? '';
          final String productUnit = (row['product_unit'] as String?) ?? '';
          final double productCost = (row['product_cost_price'] as num?)?.toDouble() ?? 0.0;
          final double? lengthPerUnit = (row['length_per_unit'] as num?)?.toDouble();
          final double? actualCostPerUnit = (row['actual_cost_per_unit'] as num?)?.toDouble();
          final double sellingPrice = (row['selling_price'] as num?)?.toDouble() ?? 0.0;
          final String? unitCostsJson = row['unit_costs'] as String?;
          final String productName = (row['product_name'] as String?) ?? '';
          
          Map<String, dynamic> unitCosts = const {};
          if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
            try { unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>; } catch (_) {}
          }
          
          final bool soldAsLargeUnit = ql > 0;
          final double soldUnitsCount = soldAsLargeUnit ? ql : qi;
          
          // استخدام التكلفة الفعلية إن وجدت
          if (actualCostPerUnit != null) {
            invoiceCost += actualCostPerUnit * soldUnitsCount;
            continue;
          }
          
          // حساب التكلفة من النظام الهرمي
          double costPerSoldUnit;
          if (soldAsLargeUnit) {
            // بيع بوحدة كبيرة (باكية، كرتون، لفة، إلخ)
            final dynamic stored = unitCosts[saleType];
            if (stored is num) {
              costPerSoldUnit = stored.toDouble();
            } else {
              // حساب من النظام الهرمي
              final bool isMeterRoll = productUnit == 'meter' && lengthPerUnit != null && (saleType == 'لفة');
              costPerSoldUnit = isMeterRoll
                  ? productCost * (lengthPerUnit ?? 1.0)
                  : productCost * uilu;
            }
          } else {
            // بيع بالوحدة الأساسية (قطعة أو متر)
            costPerSoldUnit = productCost;
          }
          
          invoiceCost += costPerSoldUnit * soldUnitsCount;
        }
        
        totalCostCalculated += invoiceCost;
        
        // 3. حساب الربح وكشف الأخطاء (Clash Detection)
        final netSaleAmount = displayedTotal - returnAmount;
        final profit = netSaleAmount - invoiceCost;
        final profitMargin = netSaleAmount > 0 ? (profit / netSaleAmount) * 100 : 0.0;
        
        if (profit < 0) {
          invoicesWithNegativeProfit++;
          warnings.add('🔴 الفاتورة #$invoiceId: ربح سالب (${profit.toStringAsFixed(0)} د.ع) - خسارة!\n'
              '   المبيعات: ${netSaleAmount.toStringAsFixed(0)} د.ع\n'
              '   التكلفة: ${invoiceCost.toStringAsFixed(0)} د.ع');
        } else if (profitMargin < 5) {
          invoicesWithLowProfit++;
          warnings.add('⚠️ الفاتورة #$invoiceId: نسبة ربح منخفضة جداً (${profitMargin.toStringAsFixed(1)}%)\n'
              '   المبيعات: ${netSaleAmount.toStringAsFixed(0)} د.ع\n'
              '   الربح: ${profit.toStringAsFixed(0)} د.ع');
        }
      }
      
      final totalProfit = totalSalesFromInvoices - totalCostCalculated;
      final overallProfitMargin = totalSalesFromInvoices > 0 ? (totalProfit / totalSalesFromInvoices) * 100 : 0.0;
      
      report.writeln('💰 إجمالي المبيعات: ${totalSalesFromInvoices.toStringAsFixed(0)} د.ع');
      report.writeln('📉 إجمالي التكلفة: ${totalCostCalculated.toStringAsFixed(0)} د.ع');
      report.writeln('📈 إجمالي الأرباح: ${totalProfit.toStringAsFixed(0)} د.ع');
      report.writeln('📊 نسبة الربح: ${overallProfitMargin.toStringAsFixed(2)}%\n');
      
      // عرض الأخطاء
      if (invoicesWithWrongTotal > 0) {
        report.writeln('❌ أخطاء: $invoicesWithWrongTotal فاتورة بمجموع خاطئ');
      }
      
      if (invoicesWithNegativeProfit > 0) {
        report.writeln('🔴 تحذير: $invoicesWithNegativeProfit فاتورة بربح سالب (خسارة)');
      }
      
      if (invoicesWithLowProfit > 0) {
        report.writeln('⚠️ تنبيه: $invoicesWithLowProfit فاتورة بنسبة ربح منخفضة جداً');
      }
      
      // عرض التفاصيل
      if (errors.isNotEmpty) {
        report.writeln('\n🔴 أخطاء في المجاميع:');
        for (var error in errors.take(5)) {
          report.writeln(error);
        }
        if (errors.length > 5) {
          report.writeln('... و ${errors.length - 5} خطأ آخر');
        }
      }
      
      if (warnings.isNotEmpty) {
        report.writeln('\n⚠️ تحذيرات الأرباح:');
        for (var warning in warnings.take(5)) {
          report.writeln(warning);
        }
        if (warnings.length > 5) {
          report.writeln('... و ${warnings.length - 5} تحذير آخر');
        }
      }
      
      report.writeln('\n💡 التوصيات:');
      if (invoicesWithWrongTotal > 0) {
        report.writeln('• راجع الفواتير ذات المجاميع الخاطئة وصححها');
      }
      if (invoicesWithNegativeProfit > 0) {
        report.writeln('• راجع أسعار التكلفة وأسعار البيع للفواتير ذات الربح السالب');
      }
      if (overallProfitMargin < 10) {
        report.writeln('• نسبة الربح الإجمالية منخفضة، راجع استراتيجية التسعير');
      }
      if (errors.isEmpty && warnings.isEmpty) {
        report.writeln('• ✅ جميع الفواتير صحيحة والأرباح منطقية!');
      }
      
      return ChatResponse(
        text: report.toString(),
        followups: ['تدقيق الفواتير', 'تقرير الأرباح', 'كشف الأخطاء'],
        status: errors.isNotEmpty ? 'error' : (warnings.isNotEmpty ? 'warning' : 'success'),
      );
    } catch (e, stackTrace) {
      return ChatResponse(
        text: 'حدث خطأ أثناء تحليل دقة الأرباح: $e',
        followups: ['إعادة المحاولة'],
        status: 'error',
      );
    }
  }

  /// تقرير اليوم - حساب دقيق للأرباح والمبيعات
  /// تقرير اليوم - حساب دقيق للأرباح والمبيعات
  /// 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط (مصاريف كهرباء/تشغيل)
  /// 🔧 إصلاح 2: عند عدم توفر actualCostPrice و uilu = 0، نحسب من unit_hierarchy
  Future<Map<String, dynamic>> getDailyReport() async {
    try {
      final db = await _dbService.database;
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      
      // جلب إعدادات التطبيق لنسب الربح
      final settings = await SettingsManager.getAppSettings();
      final adHocProfit = settings.defaultAdHocProfitPercentage / 100.0;
      final manualDebtProfitPercent = settings.manualDebtProfitPercentage / 100.0;
      
      final startStr = startOfDay.toIso8601String();
      final endStr = endOfDay.toIso8601String();
      
      // جلب الفواتير المحفوظة لهذا اليوم
      final invoices = await db.query(
        'invoices',
        where: 'invoice_date >= ? AND invoice_date < ? AND status = ?',
        whereArgs: [startStr, endStr, 'محفوظة'],
      );
      
      double totalSales = 0.0;
      double totalCost = 0.0;
      double cashSales = 0.0;
      double creditSales = 0.0;
      double totalReturns = 0.0;
      
      // 🆕 جلب الراجع من التعديلات (Snapshots/Box Match)
      final snapshotReturns = await _getSnapshotReturns(startOfDay, endOfDay, exclusionStartDate: startOfDay);
      totalReturns += snapshotReturns;
      
      // حساب المبيعات والتكلفة بدقة عالية (نفس منطق الجرد الشهري)
      for (var invoice in invoices) {
        final invoiceId = invoice['id'] as int;
        final totalAmount = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
        final paymentType = invoice['payment_type'] as String?;
        final returnAmount = (invoice['return_amount'] as num?)?.toDouble() ?? 0.0;
        
        totalSales += totalAmount;
        totalReturns += returnAmount;
        
        if (paymentType == 'نقد') {
          cashSales += totalAmount;
        } else if (paymentType == 'دين') {
          creditSales += totalAmount;
        }
        
        // حساب التكلفة بنفس منطق getMonthlySalesSummary (مع إصلاح unit_hierarchy)
        final List<Map<String, dynamic>> itemRows = await db.rawQuery('''
          SELECT 
            ii.quantity_individual AS qi,
            ii.quantity_large_unit AS ql,
            ii.units_in_large_unit AS uilu,
            ii.cost_price AS item_cost_total,
            ii.actual_cost_price AS actual_cost_per_unit,
            ii.applied_price AS selling_price,
            ii.sale_type AS sale_type,
            p.unit AS product_unit,
            p.cost_price AS product_cost_price,
            p.length_per_unit AS length_per_unit,
            p.unit_costs AS unit_costs,
            p.unit_hierarchy AS unit_hierarchy
          FROM invoice_items ii
          LEFT JOIN products p ON p.name = ii.product_name
          WHERE ii.invoice_id = ?
        ''', [invoiceId]);
        
        for (final row in itemRows) {
          final double qi = (row['qi'] as num?)?.toDouble() ?? 0.0;
          final double ql = (row['ql'] as num?)?.toDouble() ?? 0.0;
          final double uilu = (row['uilu'] as num?)?.toDouble() ?? 0.0;
          final String saleType = (row['sale_type'] as String?) ?? '';
          final String productUnit = (row['product_unit'] as String?) ?? '';
          final double productCost = (row['product_cost_price'] as num?)?.toDouble() ?? 0.0;
          final double? lengthPerUnit = (row['length_per_unit'] as num?)?.toDouble();
          final double? actualCostPerUnit = (row['actual_cost_per_unit'] as num?)?.toDouble();
          final double sellingPrice = (row['selling_price'] as num?)?.toDouble() ?? 0.0;
          final String? unitCostsJson = row['unit_costs'] as String?;
          final String? unitHierarchyJson = row['unit_hierarchy'] as String?;
          Map<String, dynamic> unitCosts = const {};
          if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
            try { unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>; } catch (_) {}
          }
          
          final bool soldAsLargeUnit = ql > 0;
          final double soldUnitsCount = soldAsLargeUnit ? ql : qi;
          
          // حساب التكلفة لكل وحدة مباعة
          double costPerSoldUnit;
          if (actualCostPerUnit != null && actualCostPerUnit > 0) {
            costPerSoldUnit = actualCostPerUnit;
          } else if (soldAsLargeUnit) {
            final dynamic stored = unitCosts[saleType];
            if (stored is num && stored > 0) {
              costPerSoldUnit = stored.toDouble();
            } else {
              final bool isMeterRoll = productUnit == 'meter' && lengthPerUnit != null && (saleType == 'لفة');
              if (isMeterRoll) {
                costPerSoldUnit = productCost * (lengthPerUnit ?? 1.0);
              } else if (uilu > 0) {
                costPerSoldUnit = productCost * uilu;
              } else {
                // 🔧 إصلاح: إذا كان uilu = 0، نحاول حساب المضاعف من unit_hierarchy
                costPerSoldUnit = _calculateCostFromHierarchy(
                  productCost: productCost,
                  saleType: saleType,
                  unitHierarchyJson: unitHierarchyJson,
                );
              }
            }
          } else {
            costPerSoldUnit = productCost;
          }
          
          // إذا كانت التكلفة صفر، افترض أن الربح 10% فقط
          if (costPerSoldUnit <= 0 && sellingPrice > 0) {
            costPerSoldUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice, profitMargin: adHocProfit);
          }
          
          totalCost += costPerSoldUnit * soldUnitsCount;
        }
      }
      
      // حساب المعاملات المالية اليدوية (تسديد دين وإضافة دين)
      // 🔧 إصلاح: فقط المعاملات اليدوية من هذا الجهاز وغير المرتبطة بفاتورة
      final manualDebtTransactions = await db.query(
        'transactions',
        where: 'transaction_date >= ? AND transaction_date < ? AND transaction_type = ? AND invoice_id IS NULL AND is_created_by_me = 1',
        whereArgs: [startStr, endStr, 'manual_debt'],
      );
      
      final manualPaymentTransactions = await db.query(
        'transactions',
        where: 'transaction_date >= ? AND transaction_date < ? AND transaction_type = ? AND invoice_id IS NULL AND is_created_by_me = 1',
        whereArgs: [startStr, endStr, 'manual_payment'],
      );
      
      double totalManualDebt = 0.0;
      double totalManualPayment = 0.0;
      
      for (var trans in manualDebtTransactions) {
        totalManualDebt += (trans['amount_changed'] as num?)?.toDouble() ?? 0.0;
      }
      
      for (var trans in manualPaymentTransactions) {
        totalManualPayment += ((trans['amount_changed'] as num?)?.toDouble() ?? 0.0).abs();
      }
      
      // إضافة الدين المبدئي لليوم
      // 🔧 إصلاح: فقط المعاملات من هذا الجهاز وغير المرتبطة بفاتورة
      final openingBalanceTransactions = await db.query(
        'transactions',
        where: 'transaction_date >= ? AND transaction_date < ? AND transaction_type = ? AND invoice_id IS NULL AND is_created_by_me = 1',
        whereArgs: [startStr, endStr, 'opening_balance'],
      );
      
      for (var trans in openingBalanceTransactions) {
        totalManualDebt += (trans['amount_changed'] as num?)?.toDouble() ?? 0.0;
      }
      
      // حساب ربح المعاملات اليدوية (15% من إضافة الدين اليدوية فقط - بدون الدين المبدئي)
      // 🔧 إصلاح: فقط المعاملات اليدوية من هذا الجهاز وغير المرتبطة بفاتورة
      double manualDebtProfit = 0.0;
      final manualDebtOnlyTransactions = await db.query(
        'transactions',
        where: 'transaction_date >= ? AND transaction_date < ? AND transaction_type = ? AND invoice_id IS NULL AND is_created_by_me = 1',
        whereArgs: [startStr, endStr, 'manual_debt'],
      );
      for (var trans in manualDebtOnlyTransactions) {
        final amount = (trans['amount_changed'] as num?)?.toDouble() ?? 0.0;
        manualDebtProfit += amount * manualDebtProfitPercent; // 15% ربح
      }
      
      // صافي الربح = (المبيعات - الراجع) - التكلفة
      final netSaleAmount = totalSales - totalReturns;
      final netProfit = netSaleAmount - totalCost;
      return {
        'totalSales': totalSales,
        'totalCost': totalCost,
        'netProfit': netProfit,
        'cashSales': cashSales,
        'creditSales': creditSales,
        'totalReturns': totalReturns,
        'totalManualDebt': totalManualDebt,
        'totalManualPayment': totalManualPayment,
        'manualDebtProfit': manualDebtProfit,
        'invoiceCount': invoices.length,
        'manualDebtCount': manualDebtTransactions.length + openingBalanceTransactions.length,
        'manualPaymentCount': manualPaymentTransactions.length,
      };
    } catch (e, stackTrace) {
      rethrow;
    }
  }

  /// تقرير الأسبوع - حساب دقيق للأرباح والمبيعات
  Future<Map<String, dynamic>> getWeeklyReport() async {
    try {
      final db = await _dbService.database;
      
      // جلب إعدادات التطبيق لنسبة الربح
      final settings = await SettingsManager.getAppSettings();
      final adHocProfit = settings.defaultAdHocProfitPercentage / 100.0;
      final manualDebtProfitPercent = settings.manualDebtProfitPercentage / 100.0;
      final today = DateTime.now();
      final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
      final startOfWeekDay = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      final endOfWeek = startOfWeekDay.add(const Duration(days: 7));
      
      final startStr = startOfWeekDay.toIso8601String();
      final endStr = endOfWeek.toIso8601String();
      
      // جلب الفواتير المحفوظة لهذا الأسبوع
      final invoices = await db.query(
        'invoices',
        where: 'invoice_date >= ? AND invoice_date < ? AND status = ?',
        whereArgs: [startStr, endStr, 'محفوظة'],
      );
      
      double totalSales = 0.0;
      double totalCost = 0.0;
      double cashSales = 0.0;
      double creditSales = 0.0;
      double totalReturns = 0.0;
      
      // 🆕 جلب الراجع من التعديلات (Snapshots/Box Match)
      final snapshotReturns = await _getSnapshotReturns(startOfWeekDay, endOfWeek, exclusionStartDate: startOfWeekDay);
      totalReturns += snapshotReturns;
      
      // حساب المبيعات والتكلفة بدقة عالية (نفس منطق الجرد الشهري)
      for (var invoice in invoices) {
        final invoiceId = invoice['id'] as int;
        final totalAmount = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
        final paymentType = invoice['payment_type'] as String?;
        final returnAmount = (invoice['return_amount'] as num?)?.toDouble() ?? 0.0;
        
        totalSales += totalAmount;
        totalReturns += returnAmount;
        
        if (paymentType == 'نقد') {
          cashSales += totalAmount;
        } else if (paymentType == 'دين') {
          creditSales += totalAmount;
        }
        
        // حساب التكلفة بنفس منطق getMonthlySalesSummary (مع إصلاح unit_hierarchy)
        final List<Map<String, dynamic>> itemRows = await db.rawQuery('''
          SELECT 
            ii.quantity_individual AS qi,
            ii.quantity_large_unit AS ql,
            ii.units_in_large_unit AS uilu,
            ii.cost_price AS item_cost_total,
            ii.actual_cost_price AS actual_cost_per_unit,
            ii.applied_price AS selling_price,
            ii.sale_type AS sale_type,
            p.unit AS product_unit,
            p.cost_price AS product_cost_price,
            p.length_per_unit AS length_per_unit,
            p.unit_costs AS unit_costs,
            p.unit_hierarchy AS unit_hierarchy
          FROM invoice_items ii
          LEFT JOIN products p ON p.name = ii.product_name
          WHERE ii.invoice_id = ?
        ''', [invoiceId]);
        
        for (final row in itemRows) {
          final double qi = (row['qi'] as num?)?.toDouble() ?? 0.0;
          final double ql = (row['ql'] as num?)?.toDouble() ?? 0.0;
          final double uilu = (row['uilu'] as num?)?.toDouble() ?? 0.0;
          final String saleType = (row['sale_type'] as String?) ?? '';
          final String productUnit = (row['product_unit'] as String?) ?? '';
          final double productCost = (row['product_cost_price'] as num?)?.toDouble() ?? 0.0;
          final double? lengthPerUnit = (row['length_per_unit'] as num?)?.toDouble();
          final double? actualCostPerUnit = (row['actual_cost_per_unit'] as num?)?.toDouble();
          final double sellingPrice = (row['selling_price'] as num?)?.toDouble() ?? 0.0;
          final String? unitCostsJson = row['unit_costs'] as String?;
          final String? unitHierarchyJson = row['unit_hierarchy'] as String?;
          Map<String, dynamic> unitCosts = const {};
          if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
            try { unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>; } catch (_) {}
          }
          
          final bool soldAsLargeUnit = ql > 0;
          final double soldUnitsCount = soldAsLargeUnit ? ql : qi;
          
          // حساب التكلفة لكل وحدة مباعة
          double costPerSoldUnit;
          if (actualCostPerUnit != null && actualCostPerUnit > 0) {
            costPerSoldUnit = actualCostPerUnit;
          } else if (soldAsLargeUnit) {
            final dynamic stored = unitCosts[saleType];
            if (stored is num && stored > 0) {
              costPerSoldUnit = stored.toDouble();
            } else {
              final bool isMeterRoll = productUnit == 'meter' && lengthPerUnit != null && (saleType == 'لفة');
              if (isMeterRoll) {
                costPerSoldUnit = productCost * (lengthPerUnit ?? 1.0);
              } else if (uilu > 0) {
                costPerSoldUnit = productCost * uilu;
              } else {
                // 🔧 إصلاح: إذا كان uilu = 0، نحاول حساب المضاعف من unit_hierarchy
                costPerSoldUnit = _calculateCostFromHierarchy(
                  productCost: productCost,
                  saleType: saleType,
                  unitHierarchyJson: unitHierarchyJson,
                );
              }
            }
          } else {
            costPerSoldUnit = productCost;
          }
          
          // إذا كانت التكلفة صفر، افترض أن الربح 10% فقط
          if (costPerSoldUnit <= 0 && sellingPrice > 0) {
            costPerSoldUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice, profitMargin: adHocProfit);
          }
          
          totalCost += costPerSoldUnit * soldUnitsCount;
        }
      }
      
      // حساب المعاملات المالية اليدوية (تسديد دين وإضافة دين)
      // 🔧 إصلاح: فقط المعاملات اليدوية من هذا الجهاز وغير المرتبطة بفاتورة
      final manualDebtTransactions = await db.query(
        'transactions',
        where: 'transaction_date >= ? AND transaction_date < ? AND transaction_type = ? AND invoice_id IS NULL AND is_created_by_me = 1',
        whereArgs: [startStr, endStr, 'manual_debt'],
      );
      
      final manualPaymentTransactions = await db.query(
        'transactions',
        where: 'transaction_date >= ? AND transaction_date < ? AND transaction_type = ? AND invoice_id IS NULL AND is_created_by_me = 1',
        whereArgs: [startStr, endStr, 'manual_payment'],
      );
      
      double totalManualDebt = 0.0;
      double totalManualPayment = 0.0;
      
      for (var trans in manualDebtTransactions) {
        totalManualDebt += (trans['amount_changed'] as num?)?.toDouble() ?? 0.0;
      }
      
      for (var trans in manualPaymentTransactions) {
        totalManualPayment += ((trans['amount_changed'] as num?)?.toDouble() ?? 0.0).abs();
      }
      
      // إضافة الدين المبدئي للأسبوع
      // 🔧 إصلاح: فقط المعاملات من هذا الجهاز وغير المرتبطة بفاتورة
      final openingBalanceTransactions = await db.query(
        'transactions',
        where: 'transaction_date >= ? AND transaction_date < ? AND transaction_type = ? AND invoice_id IS NULL AND is_created_by_me = 1',
        whereArgs: [startStr, endStr, 'opening_balance'],
      );
      
      for (var trans in openingBalanceTransactions) {
        totalManualDebt += (trans['amount_changed'] as num?)?.toDouble() ?? 0.0;
      }
      
      // حساب ربح المعاملات اليدوية (15% من إضافة الدين اليدوية فقط - بدون الدين المبدئي)
      // 🔧 إصلاح: فقط المعاملات اليدوية من هذا الجهاز وغير المرتبطة بفاتورة
      double manualDebtProfit = 0.0;
      final manualDebtOnlyTransactions = await db.query(
        'transactions',
        where: 'transaction_date >= ? AND transaction_date < ? AND transaction_type = ? AND invoice_id IS NULL AND is_created_by_me = 1',
        whereArgs: [startStr, endStr, 'manual_debt'],
      );
      for (var trans in manualDebtOnlyTransactions) {
        final amount = (trans['amount_changed'] as num?)?.toDouble() ?? 0.0;
        manualDebtProfit += amount * manualDebtProfitPercent; // 15% ربح
      }
      
      // صافي الربح = (المبيعات - الراجع) - التكلفة
      final netSaleAmount = totalSales - totalReturns;
      final netProfit = netSaleAmount - totalCost;
      return {
        'totalSales': totalSales,
        'totalCost': totalCost,
        'netProfit': netProfit,
        'cashSales': cashSales,
        'creditSales': creditSales,
        'totalReturns': totalReturns,
        'totalManualDebt': totalManualDebt,
        'totalManualPayment': totalManualPayment,
        'manualDebtProfit': manualDebtProfit,
        'invoiceCount': invoices.length,
        'manualDebtCount': manualDebtTransactions.length + openingBalanceTransactions.length,
        'manualPaymentCount': manualPaymentTransactions.length,
      };
    } catch (e, stackTrace) {
      rethrow;
    }
  }

  // ============================================
  // 🆕 ميزات التدقيق الذكي الشامل
  // ============================================

  /// تدقيق الفواتير مع تحليل ذكي من الذكاء الاصطناعي
  /// يقوم بـ:
  /// 1. التحقق من كل عنصر: الكمية × السعر = المبلغ
  /// 2. التحقق من مجموع الفاتورة
  /// 3. إرسال الأخطاء للذكاء الاصطناعي للتحليل العميق
  Future<ChatResponse> _auditInvoicesWithAI() async {
    try {
      final db = await _dbService.database;
      final List<Map<String, dynamic>> invoiceErrors = [];
      final List<Map<String, dynamic>> itemErrors = [];
      
      // جلب جميع الفواتير
      final invoices = await db.query('invoices');
      for (var invoice in invoices) {
        final invoiceId = invoice['id'] as int;
        final displayedTotal = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
        final discount = (invoice['discount'] as num?)?.toDouble() ?? 0.0;
        final loadingFee = (invoice['loading_fee'] as num?)?.toDouble() ?? 0.0;
        
        // جلب عناصر الفاتورة
        final items = await db.query(
          'invoice_items',
          where: 'invoice_id = ?',
          whereArgs: [invoiceId],
        );
        
        double calculatedItemsTotal = 0.0;
        
        // 1️⃣ فحص كل عنصر: الكمية × السعر = المبلغ
        for (var item in items) {
          final itemId = item['id'] as int;
          final productName = item['product_name'] as String;
          
          // حساب الكمية الإجمالية (فردي + وحدات كبيرة)
          final quantityIndividual = (item['quantity_individual'] as num?)?.toDouble() ?? 0.0;
          final quantityLargeUnit = (item['quantity_large_unit'] as num?)?.toDouble() ?? 0.0;
          final unitsInLargeUnit = (item['units_in_large_unit'] as num?)?.toDouble() ?? 1.0;
          
          // الكمية الإجمالية = الفردي + (الوحدات الكبيرة × عدد القطع في الوحدة)
          final totalQuantity = quantityIndividual + (quantityLargeUnit * unitsInLargeUnit);
          
          final price = (item['applied_price'] as num?)?.toDouble() ?? 0.0;
          final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0.0;
          
          // الحساب الصحيح
          final correctItemTotal = totalQuantity * price;
          
          // التحقق من دقة حساب العنصر
          if ((itemTotal - correctItemTotal).abs() > 0.01) {
            itemErrors.add({
              'invoice_id': invoiceId,
              'item_id': itemId,
              'product_name': productName,
              'quantity_individual': quantityIndividual,
              'quantity_large_unit': quantityLargeUnit,
              'units_in_large_unit': unitsInLargeUnit,
              'total_quantity': totalQuantity,
              'price': price,
              'displayed_total': itemTotal,
              'correct_total': correctItemTotal,
              'difference': (itemTotal - correctItemTotal).abs(),
            });
          }
          
          calculatedItemsTotal += correctItemTotal;
        }
        
        // 2️⃣ فحص مجموع الفاتورة
        final correctInvoiceTotal = calculatedItemsTotal - discount + loadingFee;
        
        if ((displayedTotal - correctInvoiceTotal).abs() > 0.01) {
          invoiceErrors.add({
            'invoice_id': invoiceId,
            'customer_name': invoice['customer_name'],
            'invoice_date': invoice['invoice_date'],
            'displayed_total': displayedTotal,
            'items_total': calculatedItemsTotal,
            'discount': discount,
            'loading_fee': loadingFee,
            'correct_total': correctInvoiceTotal,
            'difference': (displayedTotal - correctInvoiceTotal).abs(),
            'items_count': items.length,
          });
        }
      }
      
      // 3️⃣ إذا لم توجد أخطاء
      if (itemErrors.isEmpty && invoiceErrors.isEmpty) {
        return ChatResponse(
          text: "✅ تدقيق ذكي شامل\n\n"
                "تم فحص ${invoices.length} فاتورة بدقة عالية:\n"
                "• جميع حسابات العناصر صحيحة ✓\n"
                "• جميع مجاميع الفواتير صحيحة ✓\n\n"
                "النظام المحاسبي يعمل بدقة 100%!",
          followups: ["تدقيق الديون", "تحليل الأرباح", "كشف أخطاء أخرى"],
          status: 'success',
        );
      }
      
      // 4️⃣ إرسال الأخطاء للذكاء الاصطناعي للتحليل
      final analysisData = {
        'total_invoices': invoices.length,
        'item_errors': itemErrors,
        'invoice_errors': invoiceErrors,
      };
      
      final aiAnalysis = await _analyzeErrorsWithAI(analysisData);
      
      return ChatResponse(
        text: aiAnalysis,
        followups: ["تصحيح الأخطاء تلقائياً", "عرض تفاصيل الأخطاء", "تصدير التقرير"],
        status: 'warning',
        data: analysisData,
      );
      
    } catch (e, stackTrace) {
      return ChatResponse(
        text: '❌ حدث خطأ أثناء التدقيق الذكي:\n\n$e',
        followups: ["إعادة المحاولة", "التدقيق العادي"],
        status: 'error',
      );
    }
  }

  /// إرسال الأخطاء للذكاء الاصطناعي للتحليل العميق
  Future<String> _analyzeErrorsWithAI(Map<String, dynamic> errorsData) async {
    try {
      // استخدام Gemini للتحليل
      if (_geminiService != null) {
        try {
          final dataJson = jsonEncode(errorsData);
          final prompt = '''أنت محاسب خبير ومدقق مالي محترف.
مهمتك تحليل الأخطاء المحاسبية المكتشفة في الفواتير وتقديم:
1. تفسير واضح لكل خطأ
2. السبب المحتمل للخطأ
3. التأثير المالي
4. الحل المقترح
5. الأولوية (عالية/متوسطة/منخفضة)

البيانات:
$dataJson

قم بتحليل هذه الأخطاء المحاسبية وقدم تقرير مفصل مع توصيات للإصلاح.
يجب أن تكون إجابتك بالعربية، واضحة، ومنظمة.''';
          
          final analysis = await _geminiService!.sendMessage(prompt);
          return '🤖 تحليل ذكي من Gemini\n\n$analysis';
        } catch (e) {
          // تابع للتحليل المحلي
        }
      }
      
      // إذا لم يتوفر أي خدمة ذكاء اصطناعي
      return _generateLocalErrorReport(errorsData);
      
    } catch (e) {
      return _generateLocalErrorReport(errorsData);
    }
  }

  /// توليد تقرير محلي للأخطاء (بدون ذكاء اصطناعي)
  String _generateLocalErrorReport(Map<String, dynamic> errorsData) {
    final report = StringBuffer();
    report.writeln('📊 تقرير الأخطاء المحاسبية\n');
    report.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    final itemErrors = errorsData['item_errors'] as List;
    final invoiceErrors = errorsData['invoice_errors'] as List;
    
    if (itemErrors.isNotEmpty) {
      report.writeln('❌ أخطاء في حساب العناصر (${itemErrors.length}):\n');
      for (int i = 0; i < itemErrors.length && i < 10; i++) {
        final error = itemErrors[i];
        report.writeln('${i + 1}. فاتورة #${error['invoice_id']} - ${error['product_name']}');
        report.writeln('   الكمية: ${error['quantity']} × السعر: ${error['price']}');
        report.writeln('   المعروض: ${error['displayed_total']} ← الصحيح: ${error['correct_total']}');
        report.writeln('   الفرق: ${error['difference']} دينار\n');
      }
      if (itemErrors.length > 10) {
        report.writeln('   ... و${itemErrors.length - 10} خطأ آخر\n');
      }
    }
    
    if (invoiceErrors.isNotEmpty) {
      report.writeln('❌ أخطاء في مجاميع الفواتير (${invoiceErrors.length}):\n');
      for (int i = 0; i < invoiceErrors.length && i < 10; i++) {
        final error = invoiceErrors[i];
        report.writeln('${i + 1}. فاتورة #${error['invoice_id']} - ${error['customer_name']}');
        report.writeln('   مجموع البنود: ${error['items_total']}');
        if (error['discount'] > 0) report.writeln('   الخصم: ${error['discount']}');
        if (error['loading_fee'] > 0) report.writeln('   أجور التحميل: ${error['loading_fee']}');
        report.writeln('   المعروض: ${error['displayed_total']} ← الصحيح: ${error['correct_total']}');
        report.writeln('   الفرق: ${error['difference']} دينار\n');
      }
      if (invoiceErrors.length > 10) {
        report.writeln('   ... و${invoiceErrors.length - 10} خطأ آخر\n');
      }
    }
    
    report.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    report.writeln('\n💡 التوصية: استخدم "تصحيح الأخطاء تلقائياً" لإصلاح هذه المشاكل');
    
    return report.toString();
  }

  /// البحث عن عميل محدد وعرض كل بياناته مع تحليل ذكي بالذكاء الاصطناعي
  Future<ChatResponse> searchCustomerComplete(String customerName) async {
    try {
      final db = await _dbService.database;
      
      // البحث عن العميل
      final customers = await db.query(
        'customers',
        where: 'name LIKE ?',
        whereArgs: ['%$customerName%'],
      );
      
      if (customers.isEmpty) {
        return ChatResponse(
          text: '❌ لم يتم العثور على عميل باسم "$customerName"',
          followups: ["البحث عن عميل آخر", "عرض جميع العملاء"],
          status: 'warning',
        );
      }
      
      final customer = customers.first;
      final customerId = customer['id'] as int;
      final currentDebt = (customer['current_total_debt'] as num?)?.toDouble() ?? 0.0;
      
      // جلب جميع المعاملات مرتبة حسب التاريخ
      final transactions = await db.query(
        'transactions',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'transaction_date ASC, id ASC',
      );
      
      // جلب جميع الفواتير
      final invoices = await db.query(
        'invoices',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'invoice_date DESC',
      );
      
      // حساب الدين المبدئي
      double transactionsSum = 0.0;
      for (var trans in transactions) {
        final amount = (trans['amount_changed'] as num?)?.toDouble() ?? 0.0;
        transactionsSum += amount;
      }
      
      double initialBalance = currentDebt - transactionsSum;
      if (initialBalance < 0.01) {
        initialBalance = 0.0;
      }
      
      // بناء قاعدة بيانات كاملة للعميل لإرسالها للذكاء الاصطناعي
      final customerData = StringBuffer();
      customerData.writeln('=== بيانات العميل الكاملة ===');
      customerData.writeln('الاسم: ${customer['name']}');
      customerData.writeln('الهاتف: ${customer['phone'] ?? "غير محدد"}');
      customerData.writeln('العنوان: ${customer['address'] ?? "غير محدد"}');
      customerData.writeln('الرصيد الحالي المعروض: $currentDebt دينار');
      customerData.writeln('الدين المبدئي: $initialBalance دينار');
      customerData.writeln('\n=== سجل المعاملات (${transactions.length} معاملة) ===');
      
      double runningBalance = initialBalance;
      for (int i = 0; i < transactions.length; i++) {
        final trans = transactions[i];
        final amount = (trans['amount_changed'] as num?)?.toDouble() ?? 0.0;
        final date = trans['transaction_date'] as String?;
        final type = trans['transaction_type'] as String?;
        final note = trans['transaction_note'] as String?;
        final balanceAfter = (trans['new_balance_after_transaction'] as num?)?.toDouble() ?? 0.0;
        
        runningBalance += amount;
        
        customerData.writeln('\nمعاملة ${i + 1}:');
        customerData.writeln('  التاريخ: $date');
        customerData.writeln('  النوع: ${amount > 0 ? "إضافة دين" : "تسديد"}');
        customerData.writeln('  المبلغ: ${amount.toStringAsFixed(2)} دينار');
        customerData.writeln('  الرصيد قبل المعاملة: ${(runningBalance - amount).toStringAsFixed(2)} دينار');
        customerData.writeln('  الرصيد بعد المعاملة (محسوب): ${runningBalance.toStringAsFixed(2)} دينار');
        customerData.writeln('  الرصيد بعد المعاملة (مسجل): ${balanceAfter.toStringAsFixed(2)} دينار');
        if ((runningBalance - balanceAfter).abs() > 0.01) {
          customerData.writeln('  ⚠️ تحذير: الرصيد المحسوب لا يطابق المسجل!');
        }
        if (type != null) customerData.writeln('  نوع المعاملة: $type');
        if (note != null && note.isNotEmpty) customerData.writeln('  ملاحظة: $note');
      }
      
      // إضافة بيانات الفواتير
      customerData.writeln('\n=== الفواتير (${invoices.length} فاتورة) ===');
      for (int i = 0; i < invoices.length; i++) {
        final invoice = invoices[i];
        final invoiceId = invoice['id'] as int;
        final invoiceDate = invoice['invoice_date'] as String?;
        final totalAmount = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
        final discount = (invoice['discount'] as num?)?.toDouble() ?? 0.0;
        final loadingFee = (invoice['loading_fee'] as num?)?.toDouble() ?? 0.0;
        final amountPaid = (invoice['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0.0;
        
        customerData.writeln('\nفاتورة ${i + 1} (رقم $invoiceId):');
        customerData.writeln('  التاريخ: $invoiceDate');
        customerData.writeln('  المجموع المعروض: ${totalAmount.toStringAsFixed(2)} دينار');
        customerData.writeln('  الخصم: ${discount.toStringAsFixed(2)} دينار');
        customerData.writeln('  أجور التحميل: ${loadingFee.toStringAsFixed(2)} دينار');
        customerData.writeln('  المبلغ المدفوع: ${amountPaid.toStringAsFixed(2)} دينار');
        
        // جلب بنود الفاتورة
        final items = await db.query(
          'invoice_items',
          where: 'invoice_id = ?',
          whereArgs: [invoiceId],
        );
        
        customerData.writeln('  البنود (${items.length} بند):');
        double itemsTotal = 0.0;
        for (int j = 0; j < items.length; j++) {
          final item = items[j];
          final productName = item['product_name'] as String?;
          final quantity = (item['quantity_individual'] as num?)?.toDouble() ?? 0.0;
          final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
          final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0.0;
          final unit = item['unit'] as String?;
          
          itemsTotal += itemTotal;
          customerData.writeln('    بند ${j + 1}: $productName - $quantity $unit × $unitPrice = $itemTotal دينار');
        }
        
        final calculatedTotal = itemsTotal - discount + loadingFee;
        customerData.writeln('  مجموع البنود: ${itemsTotal.toStringAsFixed(0)} دينار');
        customerData.writeln('  الخصم: ${discount.toStringAsFixed(0)} دينار');
        customerData.writeln('  رسوم التحميل: ${loadingFee.toStringAsFixed(0)} دينار');
        customerData.writeln('  المجموع النهائي: ${calculatedTotal.toStringAsFixed(0)} دينار');
      }
      
      // إرجاع البيانات الكاملة
      return ChatResponse(
        text: customerData.toString(),
        followups: ["تحليل البيانات", "البحث عن عميل آخر"],
        status: 'success',
      );
      
    } catch (e, stackTrace) {
      return ChatResponse(
        text: '❌ حدث خطأ أثناء البحث:\n\n$e',
        followups: ["إعادة المحاولة"],
        status: 'error',
      );
    }
  }
  /// معالجة الاستفسارات العامة مع سياق كامل لقاعدة البيانات
  Future<ChatResponse> _handleGeneralQuery(String message, List<String>? history) async {
    try {
      // بناء سياق قاعدة البيانات
      final dbContext = await _buildDatabaseContext();
      
      // دمج السياق مع رسالة المستخدم
      final fullPrompt = '''أنت مساعد ذكي لمحاسب في متجر. لديك وصول كامل لقاعدة البيانات أدناه.
مهمتك هي الإجابة على أسئلة المستخدم بدقة بناءً على هذه البيانات فقط.

قواعد مهمة:
1. إذا سأل عن "ديون" أو "رصيد"، تحقق من قسم [تحليل الديون].
2. إذا كان هناك عميل لديه "دين مبدئي" (رصيد حالي > 0 ولكن مجموع المعاملات 0)، اشرح ذلك بوضوح واقترح إضافة "رصيد افتتاحي".
3. إذا سأل عن "أرباح" أو "مبيعات"، استخدم بيانات [ملخص المبيعات] و [تحليل المنتجات].
4. انتبه جيداً للوحدات (قطعة، باكية، كرتون) عند الحديث عن المخزون أو الأسعار.
5. كن دقيقاً في الأرقام ولا تخترع بيانات غير موجودة.

$dbContext

سؤال المستخدم: $message''';
      
      // إرسال للذكاء الاصطناعي (Gemini فقط)
      String responseText = "عذرًا، لا يمكنني الإجابة حاليًا.";
      
      if (_geminiService != null) {
        responseText = await _geminiService!.sendMessage(fullPrompt, conversationHistory: history);
      } else {
        return ChatResponse(
          text: "عذرًا، خدمة Gemini غير متصلة. تأكد من إعداد GEMINI_API_KEY.",
          status: 'error',
        );
      }
      
      return ChatResponse(
        text: responseText,
        followups: ["تحليل الديون", "تقرير الأرباح", "فحص المخزون"],
        status: 'success',
      );
      
    } catch (e) {
      return ChatResponse(
        text: "حدث خطأ أثناء معالجة طلبك: $e",
        status: 'error',
      );
    }
  }

  /// بناء سياق كامل لقاعدة البيانات (ملخص شامل)
  Future<String> _buildDatabaseContext() async {
    final db = await _dbService.database;
    final buffer = StringBuffer();
    
    buffer.writeln('=== تقرير قاعدة البيانات الشامل ===\n');
    
    // 1. ملخص مالي عام
    final customers = await db.query('customers');
    double totalDebt = 0.0;
    for (var c in customers) {
      totalDebt += (c['current_total_debt'] as num?)?.toDouble() ?? 0.0;
    }
    
    buffer.writeln('[ملخص مالي]');
    buffer.writeln('إجمالي الديون المستحقة: ${totalDebt.toStringAsFixed(0)} دينار');
    buffer.writeln('عدد العملاء: ${customers.length}');
    buffer.writeln('');
    
    // 2. تحليل الديون (الكشف عن المشاكل)
    buffer.writeln('[تحليل الديون والعملاء]');
    for (var c in customers) {
      final id = c['id'];
      final name = c['name'];
      final debt = (c['current_total_debt'] as num?)?.toDouble() ?? 0.0;
      
      if (debt > 0) {
        // التحقق من المعاملات
        final transactions = await db.query('transactions', where: 'customer_id = ?', whereArgs: [id]);
        double transSum = 0.0;
        for (var t in transactions) {
          transSum += (t['amount_changed'] as num?)?.toDouble() ?? 0.0;
        }
        
        buffer.write('- العميل "$name": الرصيد $debt');
        
        if (transactions.isEmpty) {
          buffer.write(' (⚠️ تنبيه: لا توجد معاملات! هذا دين مبدئي قديم يحتاج لتصحيح)');
        } else if ((debt - transSum).abs() > 0.01) {
          buffer.write(' (⚠️ تنبيه: مجموع المعاملات $transSum لا يطابق الرصيد! يوجد خلل)');
        }
        buffer.writeln('');
      }
    }
    buffer.writeln('');
    
    // 3. تحليل المنتجات والوحدات
    buffer.writeln('[تحليل المنتجات والوحدات]');
    final products = await db.query('products');
    for (var p in products) {
      final name = p['name'];
      final unit = p['unit'] == 'piece' ? 'قطعة' : 'متر';
      final cost = p['cost_price'];
      final hierarchy = (p['unit_hierarchy'] as String?) ?? ''; // e.g., "1:12:10" (Carton:Packet:Piece)
      final unitCosts = (p['unit_costs'] as String?) ?? '';
      
      buffer.writeln('- المنتج "$name":');
      buffer.writeln('  الوحدة الأساسية: $unit (تكلفتها $cost)');
      if (hierarchy.isNotEmpty) {
        buffer.writeln('  النظام الهرمي: $hierarchy (مثلاً: كرتون -> باكية -> قطعة)');
        // محاولة شرح الهرمية
        final parts = hierarchy.toString().split(':'); // افتراض التنسيق، قد يحتاج تعديل حسب الداتا الحقيقية
        if (parts.length >= 3) {
           buffer.writeln('  تفسير الوحدات: الكرتون يحتوي على ${parts[1]} باكية، والباكية تحتوي على ${parts[2]} قطعة.');
        }
      }
      if (unitCosts.isNotEmpty) {
        buffer.writeln('  تكاليف الوحدات: $unitCosts');
      }
    }
    buffer.writeln('');
    
    // 4. ملخص المبيعات (اليوم والشهر)
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1).toIso8601String();
    
    final monthlyInvoices = await db.query('invoices', 
      where: 'invoice_date >= ?', 
      whereArgs: [startOfMonth]
    );
    
    double monthSales = 0.0;
    double monthProfit = 0.0; // تقديري
    
    for (var inv in monthlyInvoices) {
      monthSales += (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
      // يمكن حساب الربح بدقة أكبر إذا جلبنا العناصر، هنا تقريب
    }
    
    buffer.writeln('[ملخص مبيعات الشهر الحالي]');
    buffer.writeln('عدد الفواتير: ${monthlyInvoices.length}');
    buffer.writeln('إجمالي المبيعات: ${monthSales.toStringAsFixed(0)} دينار');
    
    // 5. ملخص مبيعات اليوم
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final dailyInvoices = await db.query('invoices', 
      where: 'invoice_date >= ?', 
      whereArgs: [startOfDay]
    );
    
    double daySales = 0.0;
    for (var inv in dailyInvoices) {
      daySales += (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
    }
    
    buffer.writeln('');
    buffer.writeln('[ملخص مبيعات اليوم (${now.year}-${now.month}-${now.day})]');
    buffer.writeln('عدد الفواتير: ${dailyInvoices.length}');
    buffer.writeln('مبيعات اليوم: ${daySales.toStringAsFixed(0)} دينار');
    
    return buffer.toString();
  }



  /// جلب إجمالي المبالغ الراجعة من التعديلات (نفس منطق ReportsService)
  Future<double> _getSnapshotReturns(DateTime start, DateTime end, {DateTime? exclusionStartDate}) async {
    try {
      final db = await _dbService.database;
      final startStr = start.toIso8601String().split('T')[0];
      final endStr = end.toIso8601String().split('T')[0];
      
      // جلب السناب شوتس للفواتير النقدية التي حدث عليها تعديل في هذه الفترة
      // نقوم بجلب created_at للفاتورة الأصلية أيضاً للتحقق من شرط الاستثناء
      // 🗜️ نجلب سلسلة لقطات الفاتورة كاملة لا اللقطات الواقعة في الفترة فقط:
      // بعد منع اللقطات المكررة قد تكون «الحالة قبل التعديل» لقطة أقدم من الفترة،
      // وبدونها يضيع المرتجع. نحتسب لاحقاً الانتقالات التي وقعت داخل الفترة فقط.
      final snapshots = await db.rawQuery('''
        SELECT s.*, i.customer_name, i.created_at as invoice_created_at
        FROM invoice_snapshots s
        JOIN invoices i ON s.invoice_id = i.id
        WHERE i.payment_type = 'نقد'
        AND s.invoice_id IN (
          SELECT invoice_id FROM invoice_snapshots
          WHERE DATE(created_at) >= ? AND DATE(created_at) <= ?
        )
        ORDER BY s.invoice_id, s.created_at ASC
      ''', [startStr, endStr]);
      
      if (snapshots.isEmpty) return 0.0;
      
      double total = 0.0;
      final Map<int, List<Map<String, dynamic>>> snapshotsByInvoice = {};
      for (var s in snapshots) {
        final invId = s['invoice_id'] as int;
        snapshotsByInvoice.putIfAbsent(invId, () => []).add(s);
      }
      
      snapshotsByInvoice.forEach((invoiceId, invoiceSnapshots) {
        // التحقق من شرط الاستثناء: إذا كانت الفاتورة أنشئت *بعد* exclusionStartDate، نتجاهلها
        if (exclusionStartDate != null && invoiceSnapshots.isNotEmpty) {
           final invCreatedAtStr = invoiceSnapshots.first['invoice_created_at'] as String?;
           if (invCreatedAtStr != null) {
              final invCreatedAt = DateTime.tryParse(invCreatedAtStr);
              if (invCreatedAt != null && invCreatedAt.isAfter(exclusionStartDate)) {
                return; // ⏩ تخطي هذه الفاتورة لأنها أنشئت في نفس الفترة
              }
              // أيضا إذا كانت تساوي نفس الوقت تماما (نادرة لكن ممكنة)
              if (invCreatedAt != null && invCreatedAt.isAtSameMomentAs(exclusionStartDate)) {
                return;
              }
           }
        }

        for (int i = 0; i < invoiceSnapshots.length - 1; i++) {
          final current = invoiceSnapshots[i];
          final next = invoiceSnapshots[i+1];
          
          // 🗜️ لا نعتمد على أنواع اللقطات (before_edit / after_edit): اللقطة
          // المطابقة لسابقتها لم تعد تُكتب، فقد تأتي after_edit بلا before_edit.
          // كل انتقال بين لقطتين متتاليتين هو تعديل، ويُحتسب إن وقع داخل الفترة.
          final nextCreated = (next['created_at'] as String?) ?? '';
          final nextDay =
              nextCreated.length >= 10 ? nextCreated.substring(0, 10) : nextCreated;
          if (nextDay.compareTo(startStr) >= 0 && nextDay.compareTo(endStr) <= 0) {
            final oldTotal = (current['total_amount'] as num?)?.toDouble() ?? 0.0;
            final newTotal = (next['total_amount'] as num?)?.toDouble() ?? 0.0;
            
            if (newTotal < oldTotal) {
              total += (oldTotal - newTotal);
            }
          }
        }
      });
      
      return total;
    } catch (e) {
      return 0.0;
    }
  }

  // 🆕 تقرير الشهر
  Future<Map<String, dynamic>> getMonthlyReport() async {
    try {
      final db = await _dbService.database;
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final lastDay = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

      final monthlyInvoices = await db.query('invoices',
          where: 'created_at BETWEEN ? AND ?',
          whereArgs: [startOfMonth.toIso8601String(), lastDay.toIso8601String()]);

      double totalSales = 0.0;
      double totalCost = 0.0;
      double cashSales = 0.0;
      double creditSales = 0.0;
      double totalReturns = 0.0;

      for (var inv in monthlyInvoices) {
        final total = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
        final type = inv['payment_type'] as String? ?? 'نقد';
        double invReturn = (inv['return_amount'] as num?)?.toDouble() ?? 0.0;

        totalSales += total;
        if (type == 'نقد') cashSales += total; else creditSales += total;
        
        if (inv['items_json'] != null) {
           final items = jsonDecode(inv['items_json'] as String) as List;
           for (var item in items) {
             double cost = (item['cost_price'] as num?)?.toDouble() ?? 0.0;
             double qty = (item['quantity_individual'] as num?)?.toDouble() ?? 
                          (item['quantity_large_unit'] as num?)?.toDouble() ?? 0.0;
             totalCost += (cost * qty);
           }
        }
        totalReturns += invReturn;
      }

      final snapshotReturns = await _getSnapshotReturns(startOfMonth, lastDay, exclusionStartDate: startOfMonth);
      totalReturns += snapshotReturns;
      final netProfit = (totalSales - totalReturns) - totalCost;

      return {
        'totalSales': totalSales,
        'totalCost': totalCost,
        'netProfit': netProfit,
        'cashSales': cashSales,
        'creditSales': creditSales,
        'totalReturns': totalReturns,
        'invoiceCount': monthlyInvoices.length,
        'startDate': startOfMonth,
        'endDate': lastDay
      };
    } catch (e) {
      rethrow;
    }
  }

  // 🆕 تقرير السنة
  Future<Map<String, dynamic>> getYearlyReport() async {
    try {
      final db = await _dbService.database;
      final now = DateTime.now();
      final startOfYear = DateTime(now.year, 1, 1);
      final endOfYear = DateTime(now.year, 12, 31, 23, 59, 59);

      final yearlyInvoices = await db.query('invoices',
          where: 'created_at BETWEEN ? AND ?',
          whereArgs: [startOfYear.toIso8601String(), endOfYear.toIso8601String()]);

      double totalSales = 0.0;
      double totalCost = 0.0;
      double cashSales = 0.0;
      double creditSales = 0.0;
      double totalReturns = 0.0;

      for (var inv in yearlyInvoices) {
        final total = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
        final type = inv['payment_type'] as String? ?? 'نقد';
        double invReturn = (inv['return_amount'] as num?)?.toDouble() ?? 0.0;

        totalSales += total;
        if (type == 'نقد') cashSales += total; else creditSales += total;
        
        if (inv['items_json'] != null) {
           final items = jsonDecode(inv['items_json'] as String) as List;
           for (var item in items) {
             double cost = (item['cost_price'] as num?)?.toDouble() ?? 0.0;
             double qty = (item['quantity_individual'] as num?)?.toDouble() ?? 
                          (item['quantity_large_unit'] as num?)?.toDouble() ?? 0.0;
             totalCost += (cost * qty);
           }
        }
        totalReturns += invReturn;
      }

      final snapshotReturns = await _getSnapshotReturns(startOfYear, endOfYear, exclusionStartDate: startOfYear);
      totalReturns += snapshotReturns;
      final netProfit = (totalSales - totalReturns) - totalCost;

      return {
        'totalSales': totalSales,
        'totalCost': totalCost,
        'netProfit': netProfit,
        'cashSales': cashSales,
        'creditSales': creditSales,
        'totalReturns': totalReturns,
        'invoiceCount': yearlyInvoices.length,
        'startDate': startOfYear,
        'endDate': endOfYear
      };
    } catch (e) {
      rethrow;
    }
  }
}

/// نموذج رسالة الدردشة
class ChatMessage {
  final String text;
  final bool isUser;
  final List<String> suggestions;
  final String status;
  final Map<String, dynamic>? data;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.suggestions = const [],
    this.status = 'normal',
    this.data,
  });
}

/// نموذج نية المستخدم
class UserIntent {
  final String action;
  final Map<String, dynamic> params;

  UserIntent({required this.action, this.params = const {}});
}

/// نموذج استجابة الدردشة
class ChatResponse {
  final String text;
  final List<String> followups;
  final String status;
  final Map<String, dynamic>? data;

  ChatResponse({
    required this.text,
    this.followups = const [],
    this.status = 'success',
    this.data,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'followups': followups,
    'status': status,
    'data': data,
  };
}
