import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/ai_extraction_service.dart';
import '../services/suppliers_service.dart';
import '../services/product_specs_service.dart';
import '../models/supplier.dart';
import '../services/database_service.dart';
import '../models/product.dart';

class AiImportReviewScreen extends StatefulWidget {
  final Uint8List fileBytes;
  final String mimeType; // image/png, image/jpeg, application/pdf
  final String type; // 'invoice' | 'receipt'
  final String geminiApiKey;
  final String? geminiApiKey2;
  final String? geminiApiKey3;
  final int? supplierId;

  const AiImportReviewScreen({
    Key? key,
    required this.fileBytes,
    required this.mimeType,
    required this.type,
    required this.geminiApiKey,
    this.geminiApiKey2,
    this.geminiApiKey3,
    this.supplierId,
  }) : super(key: key);

  @override
  State<AiImportReviewScreen> createState() => _AiImportReviewScreenState();
}

class _AiImportReviewScreenState extends State<AiImportReviewScreen> {
  Map<String, dynamic>? _extracted;
  bool _loading = true;
  String? _error;
  String? _rawOcrText; // النص الخام المستخرج من OCR
  final SuppliersService _suppliersService = SuppliersService();
  List<Supplier> _suppliers = const [];
  int? _selectedSupplierId;
  Set<String> _knownProductNames = {};
  Set<String> _knownProductNamesNorm = {};
  String _paymentType = 'دين';
  final NumberFormat _nf = NumberFormat('#,##0.##', 'en');

  String _fmt(num v) => _nf.format(v);
  double? _supplierCurrentBalance; // الرصيد قبل العملية

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Load suppliers if supplierId not passed
      if (widget.supplierId == null) {
        await _suppliersService.ensureTables();
        final list = await _suppliersService.getAllSuppliers();
        if (!mounted) return;
        _suppliers = list;
      } else {
        _selectedSupplierId = widget.supplierId;
        await _loadSupplierBalance(_selectedSupplierId!);
      }
      // Load known product names for lookup
      try {
        final db = await DatabaseService().database;
        final rows = await db.query('products', columns: ['name']);
        if (!mounted) return;
        final names = rows
            .map((e) => (e['name']?.toString().trim() ?? ''))
            .where((s) => s.isNotEmpty)
            .toSet();
        _knownProductNames = names;
        _knownProductNamesNorm = names.map(_normalizeName).toSet();
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      _error = e.toString();
    }
    await _runExtraction();
  }

  Future<void> _loadSupplierBalance(int supplierId) async {
    try {
      final db = await DatabaseService().database;
      final rows = await db.query('suppliers', columns: ['current_balance'], where: 'id = ?', whereArgs: [supplierId], limit: 1);
      if (!mounted) return;
      _supplierCurrentBalance = rows.isNotEmpty ? ((rows.first['current_balance'] as num?)?.toDouble() ?? 0.0) : 0.0;
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      _supplierCurrentBalance = null;
      setState(() {});
    }
  }

  Future<void> _runExtraction() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = AIExtractionService(
        geminiApiKey: widget.geminiApiKey,
        geminiApiKey2: widget.geminiApiKey2,
        geminiApiKey3: widget.geminiApiKey3,
      );
      final extractionResult = await service.extractInvoiceOrReceiptStructured(
        fileBytes: widget.fileBytes,
        fileMimeType: widget.mimeType,
        extractType: widget.type,
      );
      
      if (!extractionResult.success) {
        throw Exception(extractionResult.error ?? 'فشل الاستخراج');
      }
      
      if (!mounted) return;
      var normalized = _normalizeResult(extractionResult.data);
      
      // حفظ النص الخام المستخرج من OCR
      _rawOcrText = extractionResult.data['raw_text']?.toString();
      
      // طباعة العناصر المستخرجة ومطابقتها مع المنتجات في القاعدة للتشخيص في الـ terminal
      if (widget.type == 'invoice') {
        var items = (normalized['line_items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        print('DEBUG AI ITEMS: extracted ${items.length} items');
        
        // 🧠 تطبيق المواصفات المحفوظة من قاعدة البيانات
        final specsService = ProductSpecsService();
        items = await specsService.enrichWithSpecs(items);
        normalized['line_items'] = items;
        
        // حفظ المواصفات الجديدة من AI للتعلم
        await specsService.saveSpecsFromAIResult(items);
        print('📚 تم حفظ/تحديث مواصفات المنتجات للتعلم');
        
        for (final it in items) {
          final name = (it['name'] ?? '').toString();
          final norm = _normalizeName(name);
          final exact = _knownProductNames.contains(name.trim());
          final normHit = _knownProductNamesNorm.contains(norm);
          bool partial = false;
          if (!exact && !normHit) {
            for (final k in _knownProductNamesNorm) {
              if (k.contains(norm) || norm.contains(k)) { partial = true; break; }
            }
          }
          final hasLocalSpec = it['analysis']?['from_local_db'] == true;
          print('DEBUG AI ITEM: name="$name" => exact:$exact norm:$normHit partial:$partial localSpec:$hasLocalSpec');
        }
        
        // تحميل بيانات المنتجات الموجودة (التكلفة القديمة)
        await _loadProductCosts(items);
      }
      setState(() {
        _extracted = normalized;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// تحميل أسعار التكلفة القديمة للمنتجات الموجودة
  Future<void> _loadProductCosts(List<Map<String, dynamic>> items) async {
    try {
      final db = DatabaseService();
      for (final item in items) {
        final productName = (item['name'] ?? '').toString().trim();
        if (productName.isEmpty) continue;
        
        // البحث عن المنتج
        final products = await db.searchProductsSmart(productName);
        
        // التحقق من التطابق الدقيق
        for (final product in products) {
          final normalizedProductName = _normalizeName(product.name);
          final normalizedSearchName = _normalizeName(productName);
          
          if (normalizedProductName == normalizedSearchName) {
            // حفظ سعر التكلفة القديم
            item['oldCostPrice'] = product.costPrice;
            item['productId'] = product.id;
            print('  💾 تحميل تكلفة قديمة: $productName = ${product.costPrice}');
            break;
          }
        }
      }
    } catch (e) {
      print('  ⚠️ خطأ في تحميل أسعار التكلفة: $e');
    }
  }

  Map<String, dynamic> _normalizeResult(Map<String, dynamic> raw) {
    // يدعم تنويعات شائعة في مفاتيح JSON
    if (widget.type == 'invoice') {
      final invoiceDate = raw['invoice_date'] ?? raw['date'] ?? raw['invoiceDate'];
      final invoiceNumber = raw['invoice_number'] ?? raw['number'] ?? raw['invoiceNumber'];
      final totals = raw['totals'] ?? {};
      final grand = totals is Map
          ? (totals['grand_total'] ?? totals['total'] ?? totals['final'])
          : (raw['grand_total'] ?? raw['total'] ?? raw['final_total']);
      // استنتاج المدفوع والمتبقي
      double amountPaid = _toDouble(raw['amount_paid'] ?? raw['paid'] ?? raw['paid_amount'] ?? raw['amountReceived']);
      double remaining = _toDouble(raw['remaining'] ?? raw['balance_due'] ?? raw['due'] ?? raw['rest'] ?? raw['متبقي'] ?? raw['الدين_المتبقي']);
      final grandNum = _toDouble(grand);
      if (amountPaid == 0 && remaining > 0 && grandNum > 0) {
        amountPaid = (grandNum - remaining);
      }
      if (remaining == 0 && amountPaid > 0 && grandNum > 0) {
        remaining = (grandNum - amountPaid);
      }
      // تطبيع عناصر الفاتورة
      final dynamicLines = raw['line_items'] ?? raw['items'] ?? raw['details'] ?? raw['products'];
      final List<Map<String, dynamic>> lineItems = [];
      if (dynamicLines is List) {
        for (final e in dynamicLines) {
          if (e is Map) {
            final name = e['name'] ?? e['item'] ?? e['product'] ?? e['details'] ?? e['description'] ?? '';
            final originalName = e['original_name'] ?? name;
            final qty = _toDouble(e['qty'] ?? e['quantity'] ?? e['count'] ?? 1);
            final price = _toDouble(e['price'] ?? e['unit_price'] ?? e['rate'] ?? 0);
            final amount = _toDouble(e['amount'] ?? e['line_total'] ?? (qty * price));
            // بيانات المطابقة من Gemini
            final matchedProductId = e['matched_product_id'];
            final oldCostPrice = e['old_cost_price'];
            final isNewProduct = e['is_new_product'] == true;
            
            // حقول المطابقة الذكية
            final confidence = _toDouble(e['confidence'] ?? 0);
            final reason = e['reason']?.toString() ?? '';
            
            lineItems.add({
              'name': name.toString(),
              'original_name': originalName.toString(),
              'qty': qty,
              'price': price,
              'amount': amount,
              'matched_product_id': matchedProductId,
              'oldCostPrice': oldCostPrice,
              'isNewProduct': isNewProduct,
              'confidence': confidence,
              'reason': reason,
            });
          }
        }
      }
      return {
        'invoice_date': invoiceDate,
        'invoice_number': invoiceNumber,
        'totals': {'grand_total': grandNum},
        'amount_paid': amountPaid,
        'remaining': remaining,
        if (lineItems.isNotEmpty) 'line_items': lineItems,
      };
    } else {
      final receiptDate = raw['receipt_date'] ?? raw['date'] ?? raw['receiptDate'];
      final receiptNumber = raw['receipt_number'] ?? raw['number'] ?? raw['receiptNumber'];
      final amount = raw['amount'] ?? raw['total'] ?? raw['value'];
      return {
        'receipt_date': receiptDate,
        'receipt_number': receiptNumber,
        'amount': amount,
      };
    }
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll(',', '').trim();
    return double.tryParse(s) ?? 0;
  }

  /// بناء خلية عرض درجة الثقة في المطابقة
  Widget _buildConfidenceCell(Map<String, dynamic> item) {
    final confidence = _toDouble(item['confidence'] ?? 0);
    final reason = item['reason']?.toString() ?? '';
    final originalName = item['original_name']?.toString() ?? '';
    final isNewProduct = item['isNewProduct'] == true;
    
    // تحديد اللون حسب درجة الثقة
    Color confidenceColor;
    IconData confidenceIcon;
    String confidenceLabel;
    
    if (isNewProduct || confidence < 0.50) {
      confidenceColor = Colors.orange;
      confidenceIcon = Icons.fiber_new;
      confidenceLabel = 'جديد';
    } else if (confidence >= 0.90) {
      confidenceColor = Colors.green;
      confidenceIcon = Icons.check_circle;
      confidenceLabel = '${(confidence * 100).toInt()}%';
    } else if (confidence >= 0.70) {
      confidenceColor = Colors.blue;
      confidenceIcon = Icons.thumb_up;
      confidenceLabel = '${(confidence * 100).toInt()}%';
    } else {
      confidenceColor = Colors.amber;
      confidenceIcon = Icons.help_outline;
      confidenceLabel = '${(confidence * 100).toInt()}%';
    }
    
    // بناء نص التلميح
    String tooltipText = '';
    if (originalName.isNotEmpty && originalName != item['name']) {
      tooltipText = 'الأصلي: $originalName\n';
    }
    if (reason.isNotEmpty) {
      tooltipText += reason;
    }
    
    return Tooltip(
      message: tooltipText.isNotEmpty ? tooltipText : 'لا توجد تفاصيل',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(confidenceIcon, size: 16, color: confidenceColor),
          const SizedBox(width: 4),
          Text(
            confidenceLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: confidenceColor,
            ),
          ),
        ],
      ),
    );
  }

  bool _isKnownProduct(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return true; // لا نعرض تحذيراً للحقل الفارغ
    if (_knownProductNames.contains(trimmed)) return true;
    final norm = _normalizeName(trimmed);
    if (_knownProductNamesNorm.contains(norm)) return true;
    // تطابق جزئي بعد التطبيع
    for (final k in _knownProductNamesNorm) {
      if (k.contains(norm) || norm.contains(k)) return true;
    }
    // تطابق ضبابي (Levenshtein) بعد التطبيع
    for (final k in _knownProductNamesNorm) {
      final dist = _levenshtein(norm, k);
      final maxLen = norm.length > k.length ? norm.length : k.length;
      final threshold = (maxLen * 0.15).ceil(); // 15%
      if (dist <= threshold || dist <= 2) return true;
    }
    return false;
  }

  String _normalizeName(String input) {
    String s = input.toLowerCase();
    // إزالة التشكيل العربي
    final diacritics = RegExp('[\u0610-\u061A\u064B-\u065F\u06D6-\u06ED]');
    s = s.replaceAll(diacritics, '');
    // إزالة التطويل
    s = s.replaceAll('\u0640', '');
    // توحيد الألفات والهمزات
    s = s.replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا');
    // توحيد الياء والألف المقصورة
    s = s.replaceAll('ى', 'ي');
    // توحيد الفارسية إلى العربية (ک -> ك، ی -> ي)
    s = s.replaceAll('ک', 'ك').replaceAll('ی', 'ي');
    // توحيد الكاف العربية/الفارسية في الاتجاه الآخر أيضاً (ك -> ك ثابت)
    // توحيد الأرقام العربية والهندية والفارسية إلى ASCII
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const persianIndic = '۰۱۲۳۴۵۶۷۸۹';
    for (int i = 0; i < 10; i++) {
      s = s.replaceAll(arabicIndic[i], i.toString());
      s = s.replaceAll(persianIndic[i], i.toString());
    }
    // توحيد التاء المربوطة والهاء (اختياري)
    s = s.replaceAll('ة', 'ه');
    // إزالة الرموز غير المهمة
    s = s.replaceAll(RegExp('[^\u0600-\u06FF0-9 ]'), ' ');
    // تصغير المسافات
    s = s.replaceAll(RegExp(' +'), ' ').trim();
    return s;
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final m = a.length;
    final n = b.length;
    List<int> prev = List<int>.generate(n + 1, (j) => j);
    List<int> curr = List<int>.filled(n + 1, 0);
    for (int i = 1; i <= m; i++) {
      curr[0] = i;
      for (int j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          curr[j - 1] + 1, // insertion
          prev[j] + 1, // deletion
          prev[j - 1] + cost, // substitution
        ].reduce((v, e) => v < e ? v : e);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[n];
  }

  Future<String?> _showAddProductDialog(String initialName) async {
    final nameCtrl = TextEditingController(text: initialName);
    final costCtrl = TextEditingController();
    final unitPriceCtrl = TextEditingController();
    String saleUnit = 'piece';
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة منتج جديد'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'اسم المنتج'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: saleUnit,
                  decoration: const InputDecoration(labelText: 'نوع البيع'),
                  items: const [
                    DropdownMenuItem(value: 'piece', child: Text('قطعة')),
                    DropdownMenuItem(value: 'meter', child: Text('متر')),
                  ],
                  onChanged: (v) { if (v != null) saleUnit = v; },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: costCtrl,
                  decoration: const InputDecoration(labelText: 'سعر التكلفة'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: unitPriceCtrl,
                  decoration: const InputDecoration(labelText: 'سعر المفرد (سعر 1)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final db = DatabaseService();
              final now = DateTime.now();
              final product = Product(
                name: nameCtrl.text.trim(),
                unit: saleUnit, // فقط قطعة أو متر وفق طلبك
                unitPrice: double.tryParse(unitPriceCtrl.text.trim()) ?? 0.0,
                price1: double.tryParse(unitPriceCtrl.text.trim()) ?? 0.0,
                costPrice: double.tryParse(costCtrl.text.trim()),
                piecesPerUnit: null,
                lengthPerUnit: null,
                price2: null,
                price3: null,
                price4: null,
                price5: null,
                unitHierarchy: null,
                unitCosts: null,
                createdAt: now,
                lastModifiedAt: now,
              );
              try {
                await db.insertProduct(product);
                if (!mounted) return;
                Navigator.of(context).pop(true);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل إنشاء المنتج: $e')));
              }
            },
            child: const Text('حفظ'),
          )
        ],
      ),
    );

    if (result == true) {
      // أعد تحميل قائمة المنتجات المعروفة لتحديث التحذيرات
      try {
        final db = await DatabaseService().database;
        final rows = await db.query('products', columns: ['name']);
        final names = rows
            .map((e) => (e['name']?.toString().trim() ?? ''))
            .where((s) => s.isNotEmpty)
            .toSet();
        setState(() {
          _knownProductNames = names;
          _knownProductNamesNorm = names.map(_normalizeName).toSet();
        });
      } catch (_) {}
      return nameCtrl.text.trim();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مراجعة الاستخراج')), 
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildForm(),
    );
  }

  Widget _buildError() {
    final message = _error ?? '';
    // رسائل لطيفة لحالات مختلفة
    String friendly = message;
    String suggestion = '';
    IconData errorIcon = Icons.error_outline;
    
    if (message.contains(' 429 ') || message.contains('code": 429') || message.contains('RESOURCE_EXHAUSTED')) {
      friendly = 'خدمات الذكاء الاصطناعي مشغولة الآن';
      suggestion = 'جرب مرة أخرى بعد دقيقة أو أدخل البيانات يدوياً';
      errorIcon = Icons.hourglass_empty;
    } else if (message.contains(' 503 ') || message.contains('UNAVAILABLE') || message.contains('code": 503')) {
      friendly = 'الخدمة غير متاحة مؤقتاً';
      suggestion = 'سنحاول مجدداً أو يمكنك الإدخال يدوياً';
      errorIcon = Icons.cloud_off;
    } else if (message.contains('فشل') || message.contains('جميع')) {
      friendly = 'تعذر تحليل الصورة تلقائياً';
      suggestion = 'يمكنك إدخال بيانات الفاتورة يدوياً';
      errorIcon = Icons.image_not_supported;
    }
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(errorIcon, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              friendly,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            if (suggestion.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                suggestion,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _runExtraction,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    // إنشاء بيانات فارغة للإدخال اليدوي
                    setState(() {
                      _error = null;
                      _extracted = widget.type == 'invoice'
                          ? {
                              'invoice_date': DateTime.now().toString().substring(0, 10),
                              'invoice_number': '',
                              'currency': 'IQD',
                              'line_items': <Map<String, dynamic>>[],
                              'totals': {'subtotal': 0, 'discount': 0, 'grand_total': 0},
                              'amount_paid': 0,
                              'remaining': 0,
                              'status': 'دين',
                            }
                          : {
                              'receipt_date': DateTime.now().toString().substring(0, 10),
                              'receipt_number': '',
                              'amount': 0,
                              'payment_method': 'نقد',
                              'currency': 'IQD',
                              'notes': '',
                            };
                    });
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('إدخال يدوي'),
                ),
              ],
            ),
            if (widget.type == 'invoice') ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'أو الصق نص الفاتورة:',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _showTextInputDialog,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('تحليل نص'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green[700],
                    ),
                  ),
                  if (_rawOcrText != null && _rawOcrText!.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _showRawOcrText,
                      icon: const Icon(Icons.text_snippet),
                      label: const Text('عرض النص المستخرج'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue[700],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  /// عرض النص الخام المستخرج من OCR
  Future<void> _showRawOcrText() async {
    if (_rawOcrText == null || _rawOcrText!.isEmpty) return;
    
    final textController = TextEditingController(text: _rawOcrText);
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.text_snippet, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('النص المستخرج من OCR'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'نسخ النص',
              onPressed: () {
                // نسخ النص للحافظة
                final data = ClipboardData(text: _rawOcrText!);
                Clipboard.setData(data);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ النص')),
                );
              },
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'يمكنك تعديل النص ثم الضغط على "تحليل" لإعادة التحليل:',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Directionality(
                  textDirection: ui.TextDirection.rtl,
                  child: TextField(
                    controller: textController,
                    maxLines: null,
                    expands: true,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontFamily: 'Courier New', fontSize: 12),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: const Text('تحليل'),
          ),
        ],
      ),
    );
    
    if (result != null && result.trim().isNotEmpty) {
      await _parseTextInput(result);
    }
  }
  
  /// عرض نافذة إدخال نص الفاتورة للتحليل
  Future<void> _showTextInputDialog() async {
    final textController = TextEditingController();
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الصق نص الفاتورة'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الصق نص الفاتورة من Excel أو أي مصدر آخر:',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Directionality(
                  textDirection: ui.TextDirection.rtl,
                  child: TextField(
                    controller: textController,
                    maxLines: null,
                    expands: true,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      hintText:
                          'مثال:\n1  سيمس Berly 80M 1.5*2  100  38.75  3,875\n2  كيبل 2.5*3  50  45  2,250',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: const Text('تحليل'),
          ),
        ],
      ),
    );
    
    if (result != null && result.trim().isNotEmpty) {
      await _parseTextInput(result);
    }
  }
  
  /// تحليل النص المدخل (ميزة معطلة مؤقتاً)
  Future<void> _parseTextInput(String text) async {
    setState(() {
      _error = 'ميزة تحليل النص غير متاحة حالياً. استخدم تحليل الصور بدلاً منها.';
      _loading = false;
    });
  }

  Widget _buildForm() {
    final data = _extracted ?? {};
    final isInvoice = widget.type == 'invoice';
    final TextEditingController dateCtrl = TextEditingController(
      text: data[isInvoice ? 'invoice_date' : 'receipt_date']?.toString() ?? '',
    );
    final TextEditingController numCtrl = TextEditingController(
      text: data[isInvoice ? 'invoice_number' : 'receipt_number']?.toString() ?? '',
    );
    final TextEditingController amountCtrl = TextEditingController(
      text: isInvoice
          ? (() { final t = data['totals']?['grand_total']; return t == null ? '' : _fmt(_toDouble(t)); })()
          : (() { final a = data['amount']; return a == null ? '' : _fmt(_toDouble(a)); })(),
    );
    final TextEditingController paidCtrl = TextEditingController(
      text: isInvoice ? _fmt(_toDouble(data['amount_paid'] ?? 0)) : '0',
    );
    double remaining = 0.0;
    try {
      final total = double.tryParse(amountCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
      final paid = double.tryParse(paidCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
      remaining = (total - paid);
    } catch (_) {}

    final List<Map<String, dynamic>> lineItems = isInvoice
        ? ((data['line_items'] as List?)?.cast<Map<String, dynamic>>() ?? const [])
        : const [];
    double lineItemsTotal = 0;
    for (final it in lineItems) {
      final qty = _toDouble(it['qty'] ?? 0);
      var price = _toDouble(it['price'] ?? 0);
      var amt = _toDouble(it['amount'] ?? (qty * price));
      
      // تصحيح السعر إذا كان خطأ
      if (price > 0 && amt > 0 && qty > 0) {
        final calculatedPrice = amt / qty;
        if (calculatedPrice > price * 10) {
          price = calculatedPrice;
        }
      }
      
      it['qty'] = qty;
      it['price'] = price; // السعر المصحح
      it['amount'] = amt;
      lineItemsTotal += amt;
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          if (isInvoice) ...[
            DropdownButtonFormField<String>(
              value: _paymentType,
              decoration: const InputDecoration(labelText: 'طريقة الدفع'),
              items: const [
                DropdownMenuItem(value: 'نقد', child: Text('نقد')),
                DropdownMenuItem(value: 'دين', child: Text('دين')),
              ],
              onChanged: (v) { if (v != null) setState(() { _paymentType = v; }); },
            ),
            const SizedBox(height: 12),
          ],
          if (isInvoice && lineItems.isNotEmpty) ...[
            const Text('عناصر الفاتورة', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'التكلفة القديمة بالبرتقالي تعني تغير السعر. التكلفة الجديدة بالأخضر قابلة للتعديل.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 6,
                headingRowHeight: 38,
                dataRowHeight: 60,
                columns: const [
                  DataColumn(label: SizedBox(width: 24)),
                  DataColumn(label: SizedBox(width: 180, child: Text('المنتج'))),
                  DataColumn(label: SizedBox(width: 70, child: Text('العدد')), numeric: true),
                  DataColumn(label: SizedBox(width: 90, child: Text('السعر')), numeric: true),
                  DataColumn(label: SizedBox(width: 100, child: Text('المبلغ')), numeric: true),
                  DataColumn(label: SizedBox(width: 60, child: Text('الثقة'))),
                  DataColumn(label: SizedBox(width: 80, child: Text('الوحدة'))),
                  DataColumn(label: SizedBox(width: 90, child: Text('التكلفة القديمة'))),
                  DataColumn(label: SizedBox(width: 90, child: Text('التكلفة الجديدة'))),
                  DataColumn(label: SizedBox(width: 90, child: Text('السعر 1'))),
                ],
                rows: [
                  ...List.generate(lineItems.length, (index) {
                    final item = lineItems[index];
                    // المنتج يعتبر "جديد" إذا كان isNewProduct = true أو لم يكن له productId/oldCostPrice
                    final isNewProduct = item['isNewProduct'] == true || 
                        (!item.containsKey('productId') && 
                         !item.containsKey('oldCostPrice') && 
                         !item.containsKey('matched_product_id'));
                    
                    // طباعة تشخيصية
                    if (index == 0) {
                      print('🔍 عرض البند: ${item['name']}');
                      final originalName = item['original_name'];
                      if (originalName != null && originalName != item['name']) {
                        print('   📝 الاسم الأصلي: $originalName');
                      }
                      print('   isNewProduct: $isNewProduct');
                      print('   hasProductId: ${item.containsKey('matched_product_id')}');
                      print('   hasOldCostPrice: ${item.containsKey('oldCostPrice')}');
                      print('   oldCostPrice: ${item['oldCostPrice']}');
                      print('   confidence: ${item['confidence']}');
                      print('   reason: ${item['reason']}');
                    }
                    
                    // حقول المنتج الجديد
                    if (!item.containsKey('newProductUnit')) item['newProductUnit'] = 'piece';
                    if (!item.containsKey('newProductCost')) item['newProductCost'] = item['price'] ?? 0;
                    if (!item.containsKey('newProductPrice1')) item['newProductPrice1'] = item['price'] ?? 0;
                    
                    return DataRow(cells: [
                      DataCell(SizedBox(
                        width: 24,
                        child: Center(child: Text('${index + 1}')),
                      )),
                      DataCell(Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: (item['name'] ?? '').toString(),
                              decoration: const InputDecoration(border: InputBorder.none),
                              onChanged: (v) {
                                item['name'] = v;
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          if (isNewProduct) ...[ 
                            const Tooltip(
                              message: 'منتج جديد - سيتم إنشاؤه',
                              child: Icon(Icons.fiber_new, color: Colors.green, size: 20),
                            ),
                          ] else ...[
                            const Icon(Icons.check_circle, color: Colors.blue, size: 18),
                          ],
                        ],
                      )),
                      DataCell(TextFormField(
                        initialValue: (item['qty'] ?? 0).toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(border: InputBorder.none),
                        onChanged: (v) {
                          final val = double.tryParse(v) ?? 0;
                          item['qty'] = val;
                          item['amount'] = val * (_toDouble(item['price']));
                          setState(() {});
                        },
                      )),
                      DataCell(TextFormField(
                        initialValue: (item['price'] ?? 0).toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(border: InputBorder.none),
                        onChanged: (v) {
                          final val = double.tryParse(v) ?? 0;
                          item['price'] = val;
                          item['amount'] = (_toDouble(item['qty'])) * val;
                          // تحديث تلقائي للتكلفة والسعر 1 للمنتجات الجديدة
                          if (isNewProduct) {
                            item['newProductCost'] = val;
                            item['newProductPrice1'] = val;
                          }
                          setState(() {});
                        },
                      )),
                      DataCell(Align(
                        alignment: Alignment.centerRight,
                        child: Text(_fmt(_toDouble(item['amount'] ?? 0))),
                      )),
                      // درجة الثقة في المطابقة
                      DataCell(_buildConfidenceCell(item)),
                      // الوحدة (للمنتجات الجديدة فقط)
                      DataCell(
                        isNewProduct
                            ? DropdownButton<String>(
                                value: item['newProductUnit'] as String? ?? 'piece',
                                isDense: true,
                                underline: Container(),
                                items: const [
                                  DropdownMenuItem(value: 'piece', child: Text('قطعة')),
                                  DropdownMenuItem(value: 'meter', child: Text('متر')),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    item['newProductUnit'] = v;
                                    setState(() {});
                                  }
                                },
                              )
                            : const Text('-'),
                      ),
                      // التكلفة القديمة (للمنتجات الموجودة فقط)
                      DataCell(
                        !isNewProduct && item.containsKey('oldCostPrice')
                            ? Text(
                                _fmt(_toDouble(item['oldCostPrice'] ?? 0)),
                                style: TextStyle(
                                  color: (_toDouble(item['oldCostPrice'] ?? 0) != _toDouble(item['price'] ?? 0))
                                      ? Colors.orange
                                      : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : const Text('-'),
                      ),
                      // التكلفة الجديدة (قابلة للتعديل دائماً)
                      DataCell(
                        TextFormField(
                          initialValue: isNewProduct
                              ? (item['newProductCost'] ?? item['price'] ?? 0).toString()
                              : (item['price'] ?? 0).toString(),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            hintText: 'التكلفة',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                          ),
                          style: TextStyle(
                            color: !isNewProduct && item.containsKey('oldCostPrice') &&
                                    (_toDouble(item['oldCostPrice'] ?? 0) != _toDouble(item['price'] ?? 0))
                                ? Colors.green
                                : Colors.black,
                            fontWeight: !isNewProduct && item.containsKey('oldCostPrice') &&
                                    (_toDouble(item['oldCostPrice'] ?? 0) != _toDouble(item['price'] ?? 0))
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          onChanged: (v) {
                            final newCost = double.tryParse(v) ?? 0;
                            if (isNewProduct) {
                              item['newProductCost'] = newCost;
                            } else {
                              item['price'] = newCost;
                            }
                          },
                        ),
                      ),
                      // السعر 1 (للمنتجات الجديدة فقط)
                      DataCell(
                        isNewProduct
                            ? TextFormField(
                                initialValue: (item['newProductPrice1'] ?? 0).toString(),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                                onChanged: (v) {
                                  item['newProductPrice1'] = double.tryParse(v) ?? 0;
                                },
                              )
                            : const Text('-'),
                      ),
                    ]);
                  })
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('مجموع العناصر: ', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(_fmt(lineItems.fold<double>(0, (s, e) => s + _toDouble(e['amount']))),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (widget.supplierId == null) ...[
            DropdownButtonFormField<int>(
              value: _selectedSupplierId,
              decoration: const InputDecoration(
                labelText: 'اختر المورد',
                border: OutlineInputBorder(),
              ),
              items: _suppliers
                  .map((s) => DropdownMenuItem<int>(
                        value: s.id,
                        child: Text(s.companyName),
                      ))
                  .toList(),
              onChanged: (v) async {
                setState(() => _selectedSupplierId = v);
                if (v != null) await _loadSupplierBalance(v);
              },
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: dateCtrl,
            decoration: InputDecoration(
              labelText: isInvoice ? 'تاريخ الفاتورة' : 'تاريخ السند',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: numCtrl,
            decoration: InputDecoration(
              labelText: isInvoice ? 'رقم الفاتورة' : 'رقم السند',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountCtrl,
            decoration: InputDecoration(
              labelText: isInvoice ? 'الإجمالي' : 'المبلغ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          if (isInvoice) ...[
            const SizedBox(height: 12),
            TextField(
              controller: paidCtrl,
              decoration: const InputDecoration(labelText: 'المدفوع'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) {
                // حدث قيمة نوع الدفع تلقائياً حسب المتبقي
                final total = double.tryParse(amountCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
                final paid = double.tryParse(v.replaceAll(',', '').trim()) ?? 0.0;
                final rem = total - paid;
                setState(() {
                  _paymentType = rem <= 0 ? 'نقد' : 'دين';
                });
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('المتبقي (يُضاف للدين إن كان دين):',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(remaining.toStringAsFixed(2),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if ((_selectedSupplierId ?? widget.supplierId) != null) _buildBalancePreview(
            isInvoice: isInvoice,
            totalText: amountCtrl.text,
            paidText: paidCtrl.text,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              if ((_selectedSupplierId ?? widget.supplierId) == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('الرجاء اختيار المورد أولاً')),
                );
                return;
              }
              await _saveRecord(
                isInvoice: isInvoice,
                dateText: dateCtrl.text,
                numberText: numCtrl.text,
                amountText: amountCtrl.text,
                paidText: paidCtrl.text,
              );
            },
            icon: const Icon(Icons.save),
            label: const Text('حفظ'),
          )
        ],
      ),
    );
  }

  Widget _buildBalancePreview({
    required bool isInvoice,
    required String totalText,
    required String paidText,
  }) {
    final current = (_supplierCurrentBalance ?? 0.0);
    final total = double.tryParse(totalText.replaceAll(',', '').trim()) ?? 0.0;
    final paid = double.tryParse(paidText.replaceAll(',', '').trim()) ?? 0.0;
    double delta;
    if (isInvoice) {
      final remaining = (total - paid);
      delta = _paymentType == 'نقد' ? 0.0 : (remaining < 0 ? 0.0 : remaining);
    } else {
      delta = -total;
    }
    final after = current + delta;
    return Card(
      margin: const EdgeInsets.only(top: 4),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('قبل: ${_fmt(current)}'),
            Text('التغير: ${_fmt(delta)}'),
            Text('بعد: ${_fmt(after)}'),
          ],
        ),
      ),
    );
  }

  Future<void> _saveRecord({
    required bool isInvoice,
    required String dateText,
    required String numberText,
    required String amountText,
    String? paidText,
  }) async {
    try {
      // التحقق من اختيار المورد
      final supplierId = widget.supplierId ?? _selectedSupplierId;
      if (supplierId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ الرجاء اختيار المورد أولاً'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      
      // احفظ الملف أولاً كمرفق
      final ext = widget.mimeType == 'application/pdf'
          ? 'pdf'
          : (widget.mimeType == 'image/png' ? 'png' : 'jpg');
      final path = await _suppliersService.saveAttachmentFile(
        bytes: widget.fileBytes,
        extension: ext,
      );

      int? ownerId;
      if (isInvoice) {
        final lineItems = (_extracted?['line_items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final total = _toDouble(amountText);
        final paid = _toDouble((paidText ?? '0'));
        String status;
        if (paid >= total && total > 0) {
          status = 'مسدد';
        } else if (paid > 0 && paid < total) {
          status = 'جزئي';
        } else {
          status = 'آجل';
        }
        final inv = SupplierInvoice(
          supplierId: supplierId,
          invoiceNumber: numberText.isEmpty ? null : numberText,
          invoiceDate: DateTime.tryParse(dateText) ?? DateTime.now(),
          totalAmount: total,
          amountPaid: paid,
          status: status,
          paymentType: _paymentType,
        );
        
        print('📝 حفظ فاتورة من الذكاء الاصطناعي...');
        ownerId = await _suppliersService.insertSupplierInvoice(inv);
        print('✅ تم حفظ الفاتورة برقم: $ownerId');
        
        // حفظ البنود
        if (lineItems.isNotEmpty) {
          print('📝 حفظ ${lineItems.length} بنود من الذكاء الاصطناعي...');
          final db = DatabaseService();
          
          for (var item in lineItems) {
            var productName = (item['name'] ?? '').toString().trim();
            final quantity = _toDouble(item['qty'] ?? 0);
            
            // استخدام التكلفة الجديدة المعدلة من الجدول
            // للمنتجات الجديدة: استخدم newProductCost
            // للمنتجات الموجودة: استخدم price (الذي تم تعديله في الجدول)
            var unitPrice = _toDouble(item['newProductCost'] ?? item['price'] ?? 0);
            var totalPrice = _toDouble(item['amount'] ?? (quantity * unitPrice));
            
            if (productName.isEmpty || quantity <= 0) continue;
            
            // تطبيع الاسم (تحويل الأحرف الفارسية للعربية)
            productName = productName
                .replaceAll('ک', 'ك')
                .replaceAll('ی', 'ي')
                .replaceAll('ى', 'ي');
            
            // إصلاح السعر: إذا كان unitPrice صغير جداً والإجمالي كبير، احسب من الإجمالي
            if (unitPrice > 0 && totalPrice > 0 && quantity > 0) {
              final calculatedPrice = totalPrice / quantity;
              // إذا كان السعر المحسوب أكبر بكثير من المستخرج، استخدم المحسوب
              if (calculatedPrice > unitPrice * 10) {
                print('  🔧 تصحيح السعر: $unitPrice → $calculatedPrice');
                unitPrice = calculatedPrice;
              }
            }
            
            // البحث عن المنتج في القاعدة
            int? productId;
            double? oldCostPrice; // سعر التكلفة القديم من القاعدة
            
            try {
              final products = await db.searchProductsSmart(productName);
              
              // التحقق من التطابق الدقيق للاسم
              Product? exactMatch;
              for (final product in products) {
                // تطبيع الأسماء للمقارنة
                final normalizedProductName = _normalizeName(product.name);
                final normalizedSearchName = _normalizeName(productName);
                
                if (normalizedProductName == normalizedSearchName) {
                  exactMatch = product;
                  break;
                }
              }
              
              if (exactMatch != null) {
                productId = exactMatch.id;
                oldCostPrice = exactMatch.costPrice; // حفظ سعر التكلفة القديم
                
                // التحقق من تغير السعر
                final newCost = unitPrice;
                final costChanged = oldCostPrice != null && (oldCostPrice - newCost).abs() > 0.01;
                
                print('  ✅ تم العثور على منتج: $productName (ID: $productId)');
                if (costChanged) {
                  print('     💰 التكلفة القديمة: $oldCostPrice → الجديدة: $newCost (تغير: ${(newCost - oldCostPrice!).toStringAsFixed(2)})');
                } else {
                  print('     💰 التكلفة: $oldCostPrice (بدون تغيير)');
                }
                
                // حفظ سعر التكلفة القديم في البند
                item['oldCostPrice'] = oldCostPrice;
              } else {
                if (products.isNotEmpty) {
                  print('  ⚠️ لم يتم العثور على تطابق دقيق. نتائج البحث:');
                  for (final p in products.take(3)) {
                    print('    - ${p.name} (ID: ${p.id})');
                  }
                }
                print('  ⚠️ منتج غير موجود: $productName');
                
                // استخدام القيم من الجدول للمنتجات الجديدة
                final unit = item['newProductUnit'] as String? ?? 'piece';
                final cost = _toDouble(item['newProductCost'] ?? unitPrice);
                final price1 = _toDouble(item['newProductPrice1'] ?? unitPrice);
                
                // إنشاء المنتج تلقائياً
                try {
                  final newProduct = Product(
                    name: productName,
                    unit: unit,
                    unitPrice: price1,
                    price1: price1,
                    costPrice: cost,
                    piecesPerUnit: null,
                    lengthPerUnit: null,
                    price2: null,
                    price3: null,
                    price4: null,
                    price5: null,
                    unitHierarchy: null,
                    unitCosts: null,
                    createdAt: DateTime.now(),
                    lastModifiedAt: DateTime.now(),
                  );
                  final newId = await db.insertProduct(newProduct);
                  productId = newId;
                  
                  // تحديث قائمة المنتجات المعروفة
                  if (mounted) {
                    setState(() {
                      _knownProductNames.add(productName);
                      _knownProductNamesNorm.add(_normalizeName(productName));
                    });
                  }
                  
                  print('  ✅ تم إنشاء منتج جديد: $productName (ID: $newId, unit: $unit, cost: $cost, price1: $price1)');
                } catch (e) {
                  print('  ❌ خطأ في إنشاء المنتج: $e');
                }
              }
            } catch (e) {
              print('  ❌ خطأ في البحث عن منتج: $e');
            }
            
            final invoiceItem = SupplierInvoiceItem(
              invoiceId: ownerId,
              productId: productId,
              productName: productName,
              quantity: quantity,
              unitPrice: unitPrice,
              totalPrice: totalPrice,
              unit: 'قطعة', // افتراضي
            );
            
            try {
              await _suppliersService.insertInvoiceItem(invoiceItem);
              print('  - حفظ بند: $productName, productId: $productId, unitPrice: $unitPrice');
            } catch (e) {
              print('  ❌ فشل حفظ بند: $productName - خطأ: $e');
              throw Exception('فشل حفظ البند: $productName');
            }
          }
          
          // التحقق النهائي: قراءة البنود من قاعدة البيانات للتأكد
          print('🔍 التحقق من البنود في قاعدة البيانات...');
          final savedItemsInDb = await _suppliersService.getInvoiceItems(ownerId);
          if (savedItemsInDb.length != lineItems.length) {
            final errorMsg = 'خطأ في التحقق: تم حفظ ${savedItemsInDb.length} بند في قاعدة البيانات بدلاً من ${lineItems.length}!';
            print('❌ $errorMsg');
            throw Exception(errorMsg);
          }
          print('✅ تم التحقق: جميع البنود موجودة في قاعدة البيانات (${savedItemsInDb.length}/${lineItems.length})');
          print('✅ تم حفظ جميع البنود بنجاح');
          
          // تحديث أسعار المنتجات
          print('🔄 بدء تحديث الأسعار...');
          final updatedProducts = await _suppliersService.updateProductCostsFromInvoice(ownerId);
          print('✅ انتهى التحديث. عدد المنتجات المحدثة: ${updatedProducts.length}');
          
          // عرض رسالة تأكيد
          if (updatedProducts.isNotEmpty && mounted) {
            print('📢 عرض رسالة التأكيد...');
            await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('تحديث أسعار المنتجات'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تم تحديث أسعار المنتجات التالية:'),
                      const SizedBox(height: 8),
                      ...updatedProducts.map((p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('• $p', style: const TextStyle(fontSize: 14)),
                      )),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('موافق'),
                  ),
                ],
              ),
            );
          }
        }
        
        await _suppliersService.insertAttachment(Attachment(
          ownerType: 'SupplierInvoice',
          ownerId: ownerId,
          filePath: path,
          fileType: ext == 'pdf' ? 'pdf' : 'image',
          extractedText: _extracted == null ? null : {
            'line_items': lineItems,
          }.toString(),
          extractionConfidence: null,
        ));
      } else {
        // حفظ سند قبض
        print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('💰 حفظ سند قبض من الذكاء الاصطناعي...');
        print('📋 supplierId: $supplierId');
        print('📋 receiptNumber: $numberText');
        print('📋 receiptDate: $dateText');
        print('📋 amount: $amountText');
        
        // إزالة الفواصل من المبلغ قبل التحليل
        final cleanAmount = amountText.replaceAll(',', '').trim();
        final amount = double.tryParse(cleanAmount) ?? 0;
        
        print('📋 cleanAmount: $cleanAmount');
        print('📋 parsed amount: $amount');
        
        if (amount <= 0) {
          print('❌ خطأ: المبلغ يجب أن يكون أكبر من صفر!');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ المبلغ يجب أن يكون أكبر من صفر'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        
        final rec = SupplierReceipt(
          supplierId: supplierId,
          receiptNumber: numberText.isEmpty ? null : numberText,
          receiptDate: DateTime.tryParse(dateText) ?? DateTime.now(),
          amount: amount,
        );
        
        ownerId = await _suppliersService.insertSupplierReceipt(rec);
        print('✅ تم حفظ سند القبض برقم: $ownerId');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
        
        await _suppliersService.insertAttachment(Attachment(
          ownerType: 'SupplierReceipt',
          ownerId: ownerId,
          filePath: path,
          fileType: ext == 'pdf' ? 'pdf' : 'image',
          extractedText: _extracted == null ? null : _extracted.toString(),
          extractionConfidence: null,
        ));
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الحفظ: $e')),
      );
    }
  }
}


