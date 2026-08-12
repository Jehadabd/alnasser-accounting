import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/supplier.dart';
import '../models/product.dart';
import '../services/gemini_service.dart';
import '../services/suppliers_service.dart';
import '../services/ensemble_ai_service.dart';
import '../models/supplier_invoice_item.dart';
import '../models/attachment.dart';
import '../services/database_service.dart';

class NewSupplierInvoiceScreen extends StatefulWidget {
  final Supplier supplier;
  const NewSupplierInvoiceScreen({Key? key, required this.supplier}) : super(key: key);

  @override
  State<NewSupplierInvoiceScreen> createState() => _NewSupplierInvoiceScreenState();
}

class _NewSupplierInvoiceScreenState extends State<NewSupplierInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dateCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final _paidCtrl = TextEditingController(text: '0');
  final _discountCtrl = TextEditingController(text: '0');
  String _paymentType = 'دين'; // نقد أو دين
  bool _saving = false;
  Uint8List? _pickedBytes;
  String? _pickedMime;
  String? _pickedName;
  final NumberFormat _nf = NumberFormat('#,##0.##', 'en');
  bool _formatting = false;

  final SuppliersService _service = SuppliersService();
  final DatabaseService _db = DatabaseService();
  
  // قائمة بنود الفاتورة
  List<SupplierInvoiceItem> _items = [];
  List<Product> _allProducts = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _dateCtrl.text = DateTime.now().toIso8601String().split('T')[0];
  }

  Future<void> _loadProducts() async {
    final products = await _db.getAllProducts();
    setState(() {
      _allProducts = products;
    });
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _numberCtrl.dispose();
    _totalCtrl.dispose();
    _paidCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  void _recalculateTotal() {
    final itemsTotal = _items.fold(0.0, (sum, item) => sum + item.totalPrice);
    setState(() {
      _totalCtrl.text = _nf.format(itemsTotal);
    });
  }

  void _addItem() {
    showDialog(
      context: context,
      builder: (context) => _AddItemDialog(
        allProducts: _allProducts,
        onAdd: (item) {
          setState(() {
            _items.add(item);
            _recalculateTotal();
          });
        },
      ),
    );
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _recalculateTotal();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('فاتورة مورد جديدة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'ملء تلقائي من صورة',
            onPressed: _onAutofillFromImage,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text('المورد: ${widget.supplier.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
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
              TextFormField(
                controller: _dateCtrl,
                decoration: const InputDecoration(labelText: 'تاريخ الفاتورة (ISO yyyy-MM-dd)'),
                validator: (v) => (v == null || v.isEmpty) ? 'أدخل التاريخ' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _numberCtrl,
                decoration: const InputDecoration(labelText: 'رقم الفاتورة (اختياري)'),
              ),
              const SizedBox(height: 16),
              // قسم المنتجات
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('المنتجات:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ElevatedButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة منتج'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_items.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text('لم يتم إضافة منتجات بعد'),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Card(
                      child: ListTile(
                        title: Text(item.productName),
                        subtitle: Text(
                          '${item.quantity} ${item.unit ?? ''} × ${item.unitPrice.toStringAsFixed(2)} = ${item.totalPrice.toStringAsFixed(2)}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removeItem(index),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _totalCtrl,
                decoration: const InputDecoration(labelText: 'الإجمالي'),
                keyboardType: TextInputType.number,
                readOnly: _items.isNotEmpty, // للقراءة فقط إذا كانت هناك بنود
                onChanged: (v) => _onFormatNumber(_totalCtrl),
                validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '')) == null) ? 'أدخل رقم صحيح' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _discountCtrl,
                decoration: const InputDecoration(labelText: 'الخصم (اختياري)'),
                keyboardType: TextInputType.number,
                onChanged: (v) =>

 _onFormatNumber(_discountCtrl),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _paidCtrl,
                decoration: const InputDecoration(labelText: 'المدفوع عند الفاتورة (اختياري)'),
                keyboardType: TextInputType.number,
                onChanged: (v) => _onFormatNumber(_paidCtrl),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file),
                title: Text(_pickedName == null ? 'إرفاق ملف (اختياري)' : _pickedName!),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: _onPickAttachment,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('اختيار'),
                    ),
                    if (_pickedBytes != null)
                      IconButton(
                        tooltip: 'إزالة',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() { _pickedBytes = null; _pickedMime = null; _pickedName = null; }),
                      )
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                  label: const Text('حفظ'),
                  onPressed: _saving ? null : _onSave,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onAutofillFromImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.bytes == null) return;
    final ext = (file.extension ?? '').toLowerCase();
    final mime = ext == 'pdf'
        ? 'application/pdf'
        : (ext == 'png' ? 'image/png' : 'image/jpeg');

    setState(() {
      _pickedBytes = file.bytes!;
      _pickedMime = mime;
      _pickedName = file.name;
    });

    setState(() {
      _saving = true; // Show loading indicator
    });

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جاري تحليل الفاتورة بواسطة الذكاء الاصطناعي الخاص...')));
      }

      // Use the new Local AI Service (Ensemble → Table Extractor → Fallback)
      final aiService = EnsembleAIService();
      
      // Write bytes to temp file for the service
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${file.name}');
      await tempFile.writeAsBytes(file.bytes!);
      
      final data = await aiService.extractInvoiceData(tempFile);
      
      if (mounted) {
        setState(() {
          _saving = false; // Stop loading
        });
      }
      
      if (data.containsKey('error')) {
         throw Exception(data['error']);
      }

      final date = (data['date'] ?? '').toString();
      final invoiceNum = (data['invoice_number'] ?? '').toString();
      final total = (data['total'] ?? 0.0).toString();
      final detectionMethod = (data['detection_method'] ?? 'unknown').toString();
      
      // ═══ Auto-populate header fields ═══
      if (mounted) {
        setState(() {
          if (date.isNotEmpty) {
               _dateCtrl.text = date;
          }
          if (invoiceNum.isNotEmpty) _numberCtrl.text = invoiceNum;
          if (total != "0.0" && total != "0") { 
              _totalCtrl.text = _nf.format(double.tryParse(total) ?? 0); 
          }
          _onFormatNumber(_totalCtrl);
        });
      }
      
      // ═══ Auto-populate ITEMS from AI extraction ═══
      final List<dynamic> extractedItems = data['items'] ?? [];
      if (extractedItems.isNotEmpty && mounted) {
        final List<SupplierInvoiceItem> newItems = [];
        
        for (var aiItem in extractedItems) {
          final String name = (aiItem['name'] ?? '').toString().trim();
          final double qty = _toDouble(aiItem['qty']);
          final double price = _toDouble(aiItem['price']);
          final double lineTotal = _toDouble(aiItem['line_total']);
          final String unit = (aiItem['unit'] ?? '').toString();
          
          // Skip items without useful data
          if (name.isEmpty && price == 0 && lineTotal == 0) continue;
          
          // Try to match with database products
          int? matchedProductId;
          String finalName = name;
          if (name.isNotEmpty && _allProducts.isNotEmpty) {
            for (var product in _allProducts) {
              if (product.name.contains(name) || name.contains(product.name)) {
                matchedProductId = product.id;
                finalName = product.name; // Use the official product name
                break;
              }
            }
          }
          
          newItems.add(SupplierInvoiceItem(
            invoiceId: 0, // Will be set on save
            productId: matchedProductId,
            productName: finalName.isEmpty ? 'منتج غير معرّف' : finalName,
            quantity: qty > 0 ? qty : 1.0,
            unitPrice: price,
            totalPrice: lineTotal > 0 ? lineTotal : (qty > 0 ? qty * price : price),
            unit: unit.isNotEmpty ? unit : null,
            createdAt: DateTime.now(),
          ));
        }
        
        if (newItems.isNotEmpty) {
          setState(() {
            _items.addAll(newItems);
            _recalculateTotal();
          });
        }
      }
      
      if (mounted) {
        final itemCount = extractedItems.length;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text('✅ تم استخراج $itemCount منتج بنجاح! (طريقة: $detectionMethod)'),
          duration: const Duration(seconds: 4),
        ));
      }

    } catch (e) {
      if (mounted) {
        setState(() { _saving = false; });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text('فشل التحليل: $e')));
    }
  }



  Future<void> _onPickAttachment() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.bytes == null) return;
    final ext = (file.extension ?? '').toLowerCase();
    final mime = ext == 'pdf' ? 'application/pdf' : (ext == 'png' ? 'image/png' : 'image/jpeg');
    setState(() {
      _pickedBytes = file.bytes!;
      _pickedMime = mime;
      _pickedName = file.name;
    });
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    
    // منع الضغط المتكرر
    if (_saving) return;
    
    setState(() => _saving = true);
    
    try {
      print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🚀 بدء عملية الحفظ...');
      
      final total = double.tryParse(_totalCtrl.text.replaceAll(',', '').trim()) ?? 0;
      final discount = double.tryParse(_discountCtrl.text.replaceAll(',', '').trim()) ?? 0;
      final paid = double.tryParse(_paidCtrl.text.replaceAll(',', '').trim()) ?? 0;
      
      final inv = SupplierInvoice(
        supplierId: widget.supplier.id!,
        invoiceNumber: _numberCtrl.text.trim().isEmpty ? '' : _numberCtrl.text.trim(),
        date: DateTime.tryParse(_dateCtrl.text.trim()) ?? DateTime.now(),
        totalAmount: total,
        paidAmount: paid,
      );
      
      // الخطوة 1: حفظ الفاتورة
      print('📝 [1/5] حفظ الفاتورة...');
      final invoiceId = await _service.insertSupplierInvoice(inv);
      print('✅ تم حفظ الفاتورة برقم: $invoiceId');
      
      // الخطوة 2: حفظ البنود
      print('📝 [2/5] حفظ ${_items.length} بنود...');
      int savedItems = 0;
      List<String> failedItems = [];
      
      for (var item in _items) {
        try {
          item.invoiceId = invoiceId;
          // Ensure productId is valid (not -1) or null
          if (item.productId != null && item.productId! <= 0) {
             print('⚠️ Item ${item.productName} has invalid productId: ${item.productId}. Setting to null.');
             // We can't set productId because it's final (in some versions) or we fixed it in toMap.
             // But let's log it.
          }
          await _service.insertInvoiceItem(item);
          savedItems++;
          print('  ✓ حفظ بند $savedItems/${_items.length}: ${item.productName} (ID: ${item.productId})');
        } catch (e) {
          print('❌ فشل حفظ البند ${item.productName}: $e');
          failedItems.add('${item.productName}: $e');
        }
      }
      
      // التحقق من أن جميع البنود حُفظت بنجاح
      if (savedItems != _items.length) {
        final errorMsg = 'فشل حفظ ${_items.length - savedItems} من ${_items.length} بند!\nالبنود الفاشلة: ${failedItems.join(", ")}';
        print('❌ $errorMsg');
        throw Exception(errorMsg);
      }
      
      print('✅ تم حفظ جميع البنود بنجاح ($savedItems/${_items.length})');
      
      // التحقق النهائي: قراءة البنود من قاعدة البيانات للتأكد
      print('🔍 [2.5/5] التحقق من البنود في قاعدة البيانات...');
      final savedItemsInDb = await _service.getInvoiceItems(invoiceId);
      if (savedItemsInDb.length != _items.length) {
        final errorMsg = 'خطأ في التحقق: تم حفظ ${savedItemsInDb.length} بند في قاعدة البيانات بدلاً من ${_items.length}!';
        print('❌ $errorMsg');
        throw Exception(errorMsg);
      }
      print('✅ تم التحقق: جميع البنود موجودة في قاعدة البيانات (${savedItemsInDb.length}/${_items.length})');
      
      // الخطوة 3: تحديث أسعار المنتجات
      print('🔄 [3/5] تحديث أسعار المنتجات...');
      final updatedProducts = await _service.updateProductStatsFromInvoice(invoiceId);
      print('✅ تم تحديث ${updatedProducts.length} منتج');
      
      // الخطوة 4: حفظ المرفق
      if (_pickedBytes != null && _pickedMime != null) {
        print('📎 [4/5] حفظ المرفق...');
        final ext = _pickedMime == 'application/pdf' ? 'pdf' : (_pickedMime == 'image/png' ? 'png' : 'jpg');
        final path = await _service.saveAttachmentFile(bytes: _pickedBytes!, extension: ext);
        await _service.insertAttachment(Attachment(
          ownerType: 'SupplierInvoice',
          ownerId: invoiceId,
          filePath: path,
          fileType: ext == 'pdf' ? 'pdf' : 'image',
          extractedText: null,
          extractionConfidence: null,
          uploadedAt: DateTime.now(),
        ));
        print('✅ تم حفظ المرفق');
      } else {
        print('⏭️ [4/5] لا يوجد مرفق');
      }
      
      // الخطوة 5: عرض رسالة التحديث (إذا لزم الأمر)
      if (updatedProducts.isNotEmpty && mounted) {
        print('📢 [5/5] عرض رسالة التحديث...');
        await showDialog<bool>(
          context: context,
          barrierDismissible: false, // منع الإغلاق بالنقر خارج الحوار
          builder: (context) => WillPopScope(
            onWillPop: () async => false, // منع الإغلاق بزر الرجوع
            child: AlertDialog(
              title: const Text('✅ تم الحفظ بنجاح'),
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
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('موافق'),
                ),
              ],
            ),
          ),
        );
      } else {
        print('⏭️ [5/5] لا توجد منتجات محدثة');
      }
      
      print('✅ اكتملت جميع العمليات بنجاح');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      // العودة إلى الشاشة السابقة
      if (!mounted) return;
      Navigator.of(context).pop(true);
      
    } catch (e, stackTrace) {
      print('❌ خطأ في الحفظ: $e');
      print('Stack trace: $stackTrace');
      
      if (!mounted) return;
      
      // عرض رسالة خطأ واضحة
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('❌ فشل الحفظ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('حدث خطأ أثناء حفظ الفاتورة:'),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
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
      
      // إعادة تفعيل الزر في حالة الخطأ فقط
      if (mounted) setState(() => _saving = false);
    }
    // ملاحظة: لا يوجد finally هنا - الزر يبقى معطلاً حتى تكتمل العملية أو يحدث خطأ
  }

  void _onFormatNumber(TextEditingController ctrl) {
    if (_formatting) return;
    _formatting = true;
    final raw = ctrl.text.replaceAll(',', '').trim();
    if (raw.isEmpty) { _formatting = false; return; }
    final val = double.tryParse(raw);
    if (val != null) {
      ctrl.text = _nf.format(val);
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    }
    _formatting = false;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '')) ?? 0.0;
  }
}

// حوار إضافة منتج
class _AddItemDialog extends StatefulWidget {
  final List<Product> allProducts;
  final Function(SupplierInvoiceItem) onAdd;

  const _AddItemDialog({required this.allProducts, required this.onAdd});

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _productNameCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _totalPriceCtrl = TextEditingController(); // السعر الإجمالي للوحدة المختارة
  Product? _selectedProduct;
  List<Product> _filteredProducts = [];
  String? _selectedUnit; // الوحدة المختارة (قطعة، كرتون، إلخ)
  List<String> _availableUnits = ['قطعة']; // الوحدات المتاحة
  Map<String, int> _unitQuantities = {}; // عدد القطع في كل وحدة
  final _calculatedCostCtrl = TextEditingController(); // التكلفة المحسوبة للقطعة

  @override
  void dispose() {
    _productNameCtrl.dispose();
    _quantityCtrl.dispose();
    _totalPriceCtrl.dispose();
    _calculatedCostCtrl.dispose();
    super.dispose();
  }

  void _searchProducts(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredProducts = [];
      });
      return;
    }
    
    setState(() {
      _filteredProducts = widget.allProducts
          .where((p) => p.name.contains(query))
          .take(10)
          .toList();
    });
  }

  void _selectProduct(Product product) {
    setState(() {
      _selectedProduct = product;
      _productNameCtrl.text = product.name;
      _filteredProducts = [];
      
      // بناء قائمة الوحدات المتاحة
      _availableUnits = ['قطعة'];
      _unitQuantities = {};
      
      if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
        try {
          final List<dynamic> hierarchy = json.decode(product.unitHierarchy!);
          int cumulativeQty = 1;
          for (var level in hierarchy) {
            final unitName = level['unit_name'] as String?;
            final qty = level['quantity'] as int?;
            if (unitName != null && qty != null && qty > 0) {
              cumulativeQty *= qty;
              _availableUnits.add(unitName);
              _unitQuantities[unitName] = cumulativeQty;
            }
          }
        } catch (e) {
          print('خطأ في قراءة الهرمية: $e');
        }
      }
      
      _selectedUnit = 'قطعة';
      _totalPriceCtrl.text = (product.costPrice ?? 0).toString();
      _recalculateCost();
    });
  }

  void _recalculateCost() {
    if (_totalPriceCtrl.text.isEmpty  || _selectedUnit == null) return;
    
    final totalPrice = double.tryParse(_totalPriceCtrl.text.trim()) ?? 0;
    if (_selectedUnit == 'قطعة') {
      _calculatedCostCtrl.text = totalPrice.toStringAsFixed(2);
    } else {
      final unitQty = _unitQuantities[_selectedUnit] ?? 1;
      final costPerPiece = totalPrice / unitQty;
      _calculatedCostCtrl.text = costPerPiece.toStringAsFixed(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة منتج'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // حقل اسم المنتج مع البحث
              TextFormField(
                controller: _productNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم المنتج',
                  hintText: 'ابحث عن منتج...',
                ),
                onChanged: _searchProducts,
                validator: (v) => (v == null || v.isEmpty) ? 'أدخل اسم المنتج' : null,
              ),
              // نتائج البحث
              if (_filteredProducts.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = _filteredProducts[index];
                      return ListTile(
                        title: Text(product.name),
                        subtitle: Text('التكلفة: ${product.costPrice?.toStringAsFixed(2) ?? '-'}'),
                        onTap: () => _selectProduct(product),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              // اختيار الوحدة
              if (_selectedProduct != null)
                DropdownButtonFormField<String>(
                  value: _selectedUnit,
                  decoration: const InputDecoration(labelText: 'الوحدة في الفاتورة'),
                  items: _availableUnits.map((unit) {
                    String label = unit;
                    if (unit != 'قطعة' && _unitQuantities.containsKey(unit)) {
                      label = '$unit (${_unitQuantities[unit]} قطعة)';
                    }
                    return DropdownMenuItem(value: unit, child: Text(label));
                  }).toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedUnit = v;
                      _recalculateCost();
                    });
                  },
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantityCtrl,
                decoration: InputDecoration(
                  labelText: 'الكمية ($_selectedUnit)',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => (double.tryParse(v ?? '') == null) ? 'أدخل كمية صحيحة' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _totalPriceCtrl,
                decoration: InputDecoration(
                  labelText: 'سعر التكلفة (لـ $_selectedUnit)',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _recalculateCost(),
                validator: (v) => (double.tryParse(v ?? '') == null) ? 'أدخل سعر صحيح' : null,
              ),
              const SizedBox(height: 12),
              // التكلفة المحسوبة للقطعة
              if (_calculatedCostCtrl.text.isNotEmpty && _selectedUnit != 'قطعة')
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تكلفة القطعة: ${_calculatedCostCtrl.text} دينار',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            
            final quantity = double.parse(_quantityCtrl.text.trim());
            final totalPriceForUnit = double.parse(_totalPriceCtrl.text.trim());
            
            // حساب سعر القطعة
            double unitPricePerPiece;
            if (_selectedUnit == 'قطعة') {
              unitPricePerPiece = totalPriceForUnit;
            } else {
              final unitQty = _unitQuantities[_selectedUnit] ?? 1;
              unitPricePerPiece = totalPriceForUnit / unitQty;
            }
            
            final item = SupplierInvoiceItem(
              invoiceId: 0, // سيتم تحديثه لاحقاً
              productId: _selectedProduct?.id,
              productName: _productNameCtrl.text.trim(),
              quantity: quantity,
              unitPrice: unitPricePerPiece, // سعر القطعة الواحدة
              totalPrice: quantity * totalPriceForUnit, // الإجمالي في الفاتورة
              unit: _selectedUnit,
              notes: _selectedUnit != 'قطعة' 
                ? 'من $_selectedUnit (${_unitQuantities[_selectedUnit]} قطعة) بسعر $totalPriceForUnit'
                : null,
              createdAt: DateTime.now(),
            );
            
            widget.onAdd(item);
            Navigator.pop(context);
          },
          child: const Text('إضافة'),
        ),
      ],
    );
  }
}
