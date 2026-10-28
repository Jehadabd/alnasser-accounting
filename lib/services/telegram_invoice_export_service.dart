// خدمة تصدير الفواتير وإرسالها إلى Telegram
// تستخدم InvoicePdfService لضمان توحيد التصميم ودعم الأعمدة الديناميكية
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:io';
import 'dart:convert';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';
import 'database_service.dart';
import 'settings_manager.dart';
import 'telegram_backup_service.dart';
import 'invoice_pdf_service.dart'; // 🔄 استخدام InvoicePdfService الموحد
import 'invoice_upload_tracker.dart'; // 📤 ما رُفع، وأي فاتورة من الكاشير
import 'logo_service.dart'; // 🖼️ Custom logo loading
import 'font_manager.dart'; // 🔡 Font management

class TelegramInvoiceExportService {
  final DatabaseService _db = DatabaseService();
  final TelegramBackupService _telegram = TelegramBackupService();

  /// تصدير الفواتير المُنشأة بعد تاريخ معين وإرسالها إلى Telegram
  Future<TelegramExportResult> exportAndSendNewInvoices({
    required DateTime afterDate,
    Function(int current, int total, String status)? onProgress,
  }) async {
    return _exportInvoicesInternal(afterDate: afterDate, onProgress: onProgress);
  }

  /// تصدير جميع الفواتير وإرسالها إلى Telegram
  Future<TelegramExportResult> exportAndSendAllInvoices({
    Function(int current, int total, String status)? onProgress,
  }) async {
    return _exportInvoicesInternal(onProgress: onProgress); // بدون تاريخ = الكل
  }

  /// دالة داخلية مشتركة للتصدير
  Future<TelegramExportResult> _exportInvoicesInternal({
    DateTime? afterDate,
    Function(int current, int total, String status)? onProgress,
  }) async {
    final result = TelegramExportResult();
    
    try {
      // التحقق من الإعدادات
      if (!await _telegram.isUserConfigured && !_telegram.channelIdExists) {
        result.success = false;
        result.message = 'إعدادات Telegram غير مكتملة';
        return result;
      }

      onProgress?.call(0, 0, 'جاري تحضير الموارد...');
      debugPrint('📂 بدء عملية التصدير، المجلد المؤقت سيتم إنشاؤه...');
      
      final tempDir = await getTemporaryDirectory();
      final exportDir = Directory('${tempDir.path}/telegram_export_temp_${DateTime.now().millisecondsSinceEpoch}');
      if (await exportDir.exists()) {
        await exportDir.delete(recursive: true);
      }
      await exportDir.create();
      debugPrint('✅ تم إنشاء المجلد المؤقت: ${exportDir.path}');

      // تحميل الخطوط والإعدادات مرة واحدة
      debugPrint('📂 جاري تهيئة خطوط النظام...');
      await FontManager.loadArabicFonts();
      
      debugPrint('📂 جاري تحميل الخطوط للمعالجة...');
      // نضمن الحصول على خطوط غير فارغة باستخدام الاحتياطي
      final amiriData = await rootBundle.load("assets/fonts/Amiri-Regular.ttf");
      final fallbackFont = pw.Font.ttf(amiriData);
      
      final font = FontManager.getPdfFont('Amiri') ?? fallbackFont;
      final ptbData = await rootBundle.load("assets/fonts/PTBLDHAD.TTF");
      final alnaserFont = pw.Font.ttf(ptbData);
      debugPrint('✅ تم تهيئة الخطوط بنجاح (Amiri & PTBLDHAD)');
      
      final appSettings = await SettingsManager.getAppSettings();
      final logoImage = await LogoService.getLogoImage(appSettings: appSettings);
      final branchName = appSettings.branchName;

      // جلب الفواتير
      final db = await _db.database;
      await InvoiceUploadTracker.ensure(db);
      final resend = appSettings.telegramResendEdited;
      List<Map<String, Object?>> invoicesData;

      if (afterDate != null) {
        // ما لم يُرفع بعد ضمن الفترة، + (إن فُعّل) ما رُفع ثم عُدّل بعد رفعه
        final dateStr = afterDate.toIso8601String();
        debugPrint('🔍 جلب الفواتير غير المرفوعة بعد تاريخ: $dateStr');
        invoicesData = await db.rawQuery("""
          SELECT i.*, s.sent_at AS _sent_at,
                 ${InvoiceUploadTracker.isPosSql('i')} AS _is_pos
          FROM invoices i LEFT JOIN telegram_sent s ON s.invoice_id = i.id
          WHERE i.status = 'محفوظة' AND COALESCE(i.is_deleted, 0) = 0 AND (
            (s.invoice_id IS NULL AND i.created_at > ?)
            ${resend ? "OR (s.invoice_id IS NOT NULL AND COALESCE(i.last_modified_at, '') > s.sent_at)" : ''}
          )
          ORDER BY i.id ASC
        """, [dateStr]);
      } else {
        // «إرسال الكل» من إعدادات تيليغرام: كل الفواتير المحفوظة صراحةً
        debugPrint('🔍 جلب جميع الفواتير المحفوظة...');
        invoicesData = await db.rawQuery("""
          SELECT i.*, NULL AS _sent_at, ${InvoiceUploadTracker.isPosSql('i')} AS _is_pos
          FROM invoices i
          WHERE i.status = 'محفوظة' AND COALESCE(i.is_deleted, 0) = 0
          ORDER BY i.id ASC
        """);
      }
      debugPrint('📊 عدد الفواتير الموجودة: ${invoicesData.length}');

      if (invoicesData.isEmpty) {
        result.success = true;
        result.message = 'لا توجد فواتير جديدة لرفعها';
        return result;
      }

      // جلب المنتجات لحساب الربح (مرة واحدة للأداء)
      final allProducts = await _db.getAllProducts();
      final productMap = {for (var p in allProducts) p.name: p};

      final totalInvoices = invoicesData.length;
      result.totalCount = totalInvoices;

      // 🧾 فصل إيصالات الكاشير عن الفواتير العادية، ولكل نوع طريقة رفع
      final groups = <(String, String, List<Map<String, Object?>>)>[
        ('🧾 فواتير كاشير', appSettings.telegramPosInvoicesMode,
            invoicesData.where((m) => (m['_is_pos'] as num?) == 1).toList()),
        ('📄 فواتير عادية وجملة', appSettings.telegramRegularInvoicesMode,
            invoicesData.where((m) => (m['_is_pos'] as num?) != 1).toList()),
      ];

      // إرسال رسالة بداية
      final startMsg = '📋 بدء إرسال $totalInvoices فاتورة\n'
          '🏪 $branchName\n'
          '📅 التاريخ: ${_formatDate(DateTime.now())}';
      await _telegram.sendMessage(startMsg);

      var done = 0;
      for (final (label, mode, list) in groups) {
        if (list.isEmpty) continue;
        if (mode == 'off') {
          result.skippedCount += list.length; // الرفع معطّل لهذا النوع من الإعدادات
          done += list.length;
          continue;
        }
        // ملف واحد لكل 100 فاتورة كحد أقصى (حد حجم ملفات تيليغرام 50 ميغا)
        final chunks = mode == 'combined'
            ? [for (var k = 0; k < list.length; k += 100) list.sublist(k, k + 100 > list.length ? list.length : k + 100)]
            : [for (final m in list) [m]];

        for (final chunk in chunks) {
          final combined = mode == 'combined';
          final doc = combined ? pw.Document() : null;
          final numbers = <String>[];
          final ids = <int>[];
          var sumAmount = 0.0, sumProfit = 0.0;
          String? singleCaption;

          for (final invMap in chunk) {
            final invoice = Invoice.fromMap(invMap);
            final edited = invMap['_sent_at'] != null;
            done++;
            onProgress?.call(done, totalInvoices, 'تجهيز فاتورة #${invoice.formattedInvoiceNumber}...');
            try {
              final itemsData = await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoice.id]);
              final items = itemsData.map((e) => InvoiceItem.fromMap(e)).toList();
              if (items.isEmpty) {
                result.skippedCount++;
                continue;
              }
              final itemsTotal = items.fold(0.0, (sum, item) => sum + item.itemTotal);
              final afterDiscount = (itemsTotal + invoice.loadingFee) - invoice.discount;
              final remaining = afterDiscount - invoice.amountPaidOnInvoice;
              final invoiceProfit = _calculateInvoiceProfit(items, productMap, invoice.discount);

              double previousDebt = 0.0, currentDebt = 0.0;
              String? customerPhone;
              String invoiceCustomerAddress = '';
              if (invoice.customerId != null) {
                final customer = await _db.getCustomerById(invoice.customerId!);
                if (customer != null) {
                  currentDebt = customer.currentTotalDebt;
                  previousDebt = currentDebt - remaining; // تقديري
                  customerPhone = customer.phone;
                  invoiceCustomerAddress = customer.address ?? '';
                }
              }

              final pdf = await InvoicePdfService.generateInvoicePdf(
                into: doc,
                invoiceItems: items,
                allProducts: allProducts,
                customerName: invoice.customerName,
                customerAddress: invoiceCustomerAddress,
                customerPhone: customerPhone,
                invoiceId: invoice.id!,
                createdAt: invoice.invoiceDate,
                selectedDate: invoice.invoiceDate,
                discount: invoice.discount,
                paid: invoice.amountPaidOnInvoice,
                loadingFee: invoice.loadingFee,
                paymentType: invoice.paymentType,
                invoiceToManage: invoice,
                afterDiscount: afterDiscount,
                remaining: remaining,
                font: font,
                alnaserFont: alnaserFont,
                logoImage: logoImage,
                appSettings: appSettings,
                previousDebt: previousDebt,
                currentDebt: currentDebt,
              );

              numbers.add('${invoice.formattedInvoiceNumber}${edited ? ' (معدّلة)' : ''}');
              ids.add(invoice.id!);
              sumAmount += afterDiscount;
              sumProfit += invoiceProfit;

              if (!combined) {
                // فاتورة فاتورة: كما كان (رقم، فرع، عميل، مبلغ، ربح)
                final fileName = 'فاتورة_${invoice.formattedInvoiceNumber}.pdf';
                final pdfFile = File('${exportDir.path}/$fileName');
                await pdfFile.writeAsBytes(await pdf.save());
                singleCaption = '${edited ? '✏️ نسخة معدّلة — ' : ''}🧾 فاتورة #${invoice.formattedInvoiceNumber}\n'
                    '🏪 $branchName\n'
                    '👤 ${invoice.customerName}\n'
                    '💰 المبلغ: ${_formatNumber(afterDiscount)} د.ع\n'
                    '📈 الربح: ${_formatNumber(invoiceProfit)} د.ع\n'
                    '📅 ${_formatDate(invoice.invoiceDate)}';
                debugPrint('📤 جاري إرسال PDF للفاتورة #${invoice.formattedInvoiceNumber} إلى Telegram...');
                final sent = await _telegram.sendDocument(file: pdfFile, caption: singleCaption);
                if (sent) {
                  result.sentCount++;
                  await InvoiceUploadTracker.markSent(db, [invoice.id!]);
                } else {
                  result.failedCount++;
                }
                await Future.delayed(const Duration(milliseconds: 3500)); // تجنّب الحظر
              }
            } catch (e, stack) {
              result.failedCount++;
              debugPrint('❌ خطأ في معالجة الفاتورة #${invoice.id}: $e');
              debugPrint('Stack trace: $stack');
            }
          }

          if (combined && ids.isNotEmpty) {
            // ملف واحد + رسالة فوقه بأرقام الفواتير
            onProgress?.call(done, totalInvoices, 'إرسال ملف $label (${ids.length} فاتورة)...');
            final today = _formatDate(DateTime.now()).replaceAll('/', '-');
            final kind = label.contains('كاشير') ? 'فواتير_كاشير' : 'فواتير_عادية';
            final pdfFile = File('${exportDir.path}/${kind}_${today}_${ids.length}.pdf');
            await pdfFile.writeAsBytes(await doc!.save());
            final header = '$label — ${ids.length} فاتورة\n'
                '🏪 $branchName\n'
                '💰 المجموع: ${_formatNumber(sumAmount)} د.ع\n'
                '📈 الربح: ${_formatNumber(sumProfit)} د.ع\n'
                '📅 ${_formatDate(DateTime.now())}\n'
                '🔢 الأرقام: ${numbers.join('، ')}';
            bool sent;
            if (header.length <= 1000) {
              sent = await _telegram.sendDocument(file: pdfFile, caption: header);
            } else {
              // تعليق الملف في تيليغرام محدود بـ 1024 حرفاً: الأرقام في رسالة فوقه
              await _telegram.sendMessage(header);
              sent = await _telegram.sendDocument(file: pdfFile, caption: '$label — ${ids.length} فاتورة (الأرقام في الرسالة أعلاه)');
            }
            if (sent) {
              result.sentCount += ids.length;
              await InvoiceUploadTracker.markSent(db, ids);
            } else {
              result.failedCount += ids.length;
            }
            await Future.delayed(const Duration(milliseconds: 3500));
          }
        }
      }

      // تنظيف
      try {
        await exportDir.delete(recursive: true);
      } catch (_) {}

      // رسالة الختام
      final endMsg = '✅ اكتمل النقل\n'
          '📊 الإحصائيات:\n'
          '✅ تم إرسال: ${result.sentCount}\n'
          '❌ فشل: ${result.failedCount}\n'
          '⏭️ تم تخطي: ${result.skippedCount}\n'
          '📦 الإجمالي: $totalInvoices';
      await _telegram.sendMessage(endMsg);

      result.success = true;
      result.message = 'تم إرسال ${result.sentCount} فاتورة';
      
    } catch (e, stack) {
      result.success = false;
      result.message = 'خطأ عام: $e';
      debugPrint('🔥 خطأ فادح في عملية التصدير: $e');
      debugPrint('Stack trace: $stack');
    }

    return result;
  }

  String _formatNumber(num value) {
    final formatter = NumberFormat('#,##0.##', 'en_US');
    return formatter.format(value);
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month}/${dt.day}';
  }


  /// حساب إجمالي ربح الفاتورة
  double _calculateInvoiceProfit(List<InvoiceItem> items, Map<String, Product> productMap, double discount) {
    double totalProfit = 0.0;
    
    for (var item in items) {
      final double sellingPrice = item.appliedPrice;
      final double? acp = item.actualCostPrice;
      final double itemBaseCost = item.costPrice ?? 0.0;
      
      final String saleType = item.saleType ?? '';
      final double qi = item.quantityIndividual ?? 0.0;
      final double ql = item.quantityLargeUnit ?? 0.0;
      final double uilu = item.unitsInLargeUnit ?? 0.0;
      
      // جلب بيانات المنتج
      final Product? product = productMap[item.productName];
      final String productUnit = product?.unit ?? '';
      final double lengthPerUnit = product?.lengthPerUnit ?? 1.0;
      final double productBaseCost = product?.costPrice ?? 0.0;
      final Map<String, double> unitCosts = product?.getUnitCostsMap() ?? {};
      
      final bool soldAsLargeUnit = ql > 0;
      final double saleUnitsCount = soldAsLargeUnit ? ql : qi;
      
      double costPerSaleUnit;
      
      if (acp != null && acp > 0) {
        costPerSaleUnit = acp;
      } else if (soldAsLargeUnit) {
        if (unitCosts.containsKey(saleType)) {
          costPerSaleUnit = unitCosts[saleType]!;
        } else if (productUnit == 'meter' && saleType == 'لفة') {
          costPerSaleUnit = productBaseCost * lengthPerUnit;
        } else if (uilu > 0) {
          costPerSaleUnit = productBaseCost * uilu;
        } else {
          costPerSaleUnit = _calculateCostFromHierarchy(
            productCost: productBaseCost,
            saleType: saleType,
            unitHierarchyJson: product?.unitHierarchy,
          );
        }
      } else {
        costPerSaleUnit = itemBaseCost > 0 ? itemBaseCost : productBaseCost;
      }
      
      if (costPerSaleUnit <= 0 && sellingPrice > 0) {
        costPerSaleUnit = sellingPrice * 0.9; // 10% ربح افتراضي
      }
      
      final double lineAmount = sellingPrice * saleUnitsCount;
      final double lineCostTotal = costPerSaleUnit * saleUnitsCount;
      
      totalProfit += (lineAmount - lineCostTotal);
    }
    
    return totalProfit - discount;
  }

  double _calculateCostFromHierarchy({
    required double productCost,
    required String saleType,
    required String? unitHierarchyJson,
  }) {
    if (unitHierarchyJson == null || unitHierarchyJson.trim().isEmpty) {
      return productCost;
    }
    
    try {
      final List<dynamic> hierarchy = json.decode(unitHierarchyJson.replaceAll("'", '"'));
      double multiplier = 1.0;
      
      for (final level in hierarchy) {
        final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
        final double qty = (level['quantity'] is num)
            ? (level['quantity'] as num).toDouble()
            : double.tryParse(level['quantity'].toString()) ?? 1.0;
        multiplier *= qty;
        
        if (unitName == saleType) {
          return productCost * multiplier;
        }
      }
      
      return productCost;
    } catch (e) {
      return productCost;
    }
  }
}

class TelegramExportResult {
  bool success = false;
  String message = '';
  int totalCount = 0;
  int sentCount = 0;
  int failedCount = 0;
  int skippedCount = 0;
}
