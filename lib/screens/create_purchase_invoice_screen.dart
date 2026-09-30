import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' as intl;
import '../models/supplier.dart';
import '../models/product.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_invoice_item.dart';
import '../models/supplier_delegate.dart';
import '../services/purchase_service.dart';
import '../erp/pickers.dart' show CashBoxDropdown, WarehouseDropdown;
import '../erp/erp_common.dart' show PeriodLock, parseMoney, fmtQty, confirmDialog, currentUserId;
import '../widgets/formatters.dart' show ThousandSeparatorDecimalInputFormatter;
import '../services/database_service.dart';
import '../widgets/quick_product_creation_dialog.dart';
import '../services/ocr_service_factory.dart';
import '../services/ensemble_ai_service_factory.dart';
import '../models/ocr_invoice_item.dart';
import 'product_entry_screen.dart';

/// شاشة إنشاء فاتورة شراء (Odoo-Style مع Unit Conversion)
class CreatePurchaseInvoiceScreen extends StatefulWidget {
  final Supplier? preselectedSupplier;
  final PurchaseInvoice? existingInvoice;

  const CreatePurchaseInvoiceScreen({super.key, this.preselectedSupplier, this.existingInvoice});

  @override
  State<CreatePurchaseInvoiceScreen> createState() => _CreatePurchaseInvoiceScreenState();
}

class _CreatePurchaseInvoiceScreenState extends State<CreatePurchaseInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _invoiceNumberController = TextEditingController();
  final _notesController = TextEditingController();
  
  Supplier? _selectedSupplier;
  DateTime _invoiceDate = DateTime.now();
  DateTime? _dueDate;
  String _currency = 'IQD';
  String? _attachmentPath; // 📎 مسار المرفق
  
  List<Supplier> _suppliers = [];
  List<Product> _products = [];
  List<PurchaseInvoiceItem> _items = [];
  bool _isLoading = true;
  bool _isSaving = false;

  // 🆕 New Fields
  String _paymentType = 'دين'; // دين or نقد
  final _paidAmountController = TextEditingController(text: '0');
  // 🏬 المخزن المستلم والصندوق/البنك المدفوع منه (فارغ = الرئيسي/الافتراضي)
  int? _warehouseId;
  int? _cashBoxId;
  final _delegateNameController = TextEditingController();
  List<SupplierDelegate> _delegates = []; // For auto-complete or check
  // متحكم حقل الإكمال التلقائي — نربط به مستمعاً واحداً فقط (كان يُضاف مستمع
  // جديد في كل إعادة بناء)
  TextEditingController? _delegateFieldController;
  // 🛡️ في التعديل لا يُغيَّر المورد: تغييره كان يُبقي مساهمة الفاتورة على دين
  //    المورد القديم ويضيفها للجديد (دين مزدوج).
  bool _supplierLocked = false;

  static String _normCurrency(String? c) => c == 'USD' ? 'USD' : 'IQD';

  static final intl.NumberFormat _moneyFmt = intl.NumberFormat('#,##0.##', 'en_US');

  /// «نقد» = مدفوعة بالكامل: المسدد يتبع الإجمالي كلما تغيّرت المواد
  /// (كان يُضبط مرة واحدة عند اختيار «نقد» فيبقى 0 أو قيمة قديمة ⇒ دين وهمي).
  void _syncCashPaid() {
    if (_paymentType == 'نقد') {
      _paidAmountController.text = _moneyFmt.format(_totalAmount);
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedSupplier = widget.preselectedSupplier;
    
    if (widget.existingInvoice != null) {
      final inv = widget.existingInvoice!;
      _invoiceNumberController.text = inv.invoiceNumber;
      _notesController.text = inv.notes ?? '';
      _invoiceDate = inv.date;
      _dueDate = inv.dueDate;
      _currency = _normCurrency(inv.currency);
      _attachmentPath = inv.attachmentPath;
      _paidAmountController.text = _moneyFmt.format(inv.paidAmount);
      _paymentType = inv.isPaid ? 'نقد' : (inv.paidAmount > 0 ? 'دين' : (inv.totalAmount == 0 ? 'نقد' : 'دين'));
    } else if (_selectedSupplier != null) {
      _currency = _normCurrency(_selectedSupplier!.currency);
    }
    _loadData();
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _notesController.dispose();
    _paidAmountController.dispose();
    _delegateNameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final purchaseService = context.read<PurchaseService>();
    final dbService = DatabaseService();

    try {
      final suppliers = await purchaseService.getSuppliers();
      final products = await dbService.getAllProducts();
      if (!mounted) return;

      int? delegatesFor;
      setState(() {
        _suppliers = suppliers;
        _products = products;
        // Find matching supplier from loaded list (to match dropdown items by reference)
        final existing = widget.existingInvoice;
        if (existing != null) {
          final idx = _suppliers.indexWhere((s) => s.id == existing.supplierId);
          if (idx != -1) {
            _selectedSupplier = _suppliers[idx];
            _supplierLocked = true;
            delegatesFor = _selectedSupplier!.id;
          }
          // 🛡️ عملة الفاتورة تبقى عملتها: كانت تُستبدل بعملة المورد المفضلة
          //    فتتحول فاتورة دولار إلى دينار بالمبلغ نفسه عند أي تعديل.
          _currency = _normCurrency(existing.currency);
        } else if (_selectedSupplier != null) {
          final pre = _selectedSupplier!;
          final idx = _suppliers.indexWhere((s) => s.id == pre.id);
          if (idx != -1) {
            _selectedSupplier = _suppliers[idx];
          } else {
            // 🛡️ قيمة ليست ضمن عناصر القائمة المنسدلة تُسقط الشاشة
            _suppliers = [..._suppliers, pre];
          }
          _currency = _normCurrency(_selectedSupplier!.currency);
          delegatesFor = _selectedSupplier!.id;
        }
        _isLoading = false;
      });

      if (delegatesFor != null) _loadDelegatesForSupplier(delegatesFor!);
      final existingId = widget.existingInvoice?.id;
      if (existingId != null) {
        _loadExistingItems(existingId);
        _loadExt(existingId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر تحميل البيانات: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _loadExistingItems(int invoiceId) async {
    final purchaseService = context.read<PurchaseService>();
    try {
      final items = await purchaseService.getInvoiceItems(invoiceId);

      // Refresh product names for display
      final dbService = DatabaseService();
      final allProducts = await dbService.getAllProducts();

      final updatedItems = items.map((item) {
        final p = allProducts.firstWhere((p) => p.id == item.productId, orElse: () => Product(name: 'محذوف', unit: 'piece', unitPrice: 0, price1: 0, createdAt: DateTime.now(), lastModifiedAt: DateTime.now(), categoryId: 0, isWeighable: false));
        return item.copyWith(productName: p.name);
      }).toList();

      if (!mounted) return;
      setState(() {
        _items = updatedItems;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر تحميل مواد الفاتورة: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _loadDelegatesForSupplier(int supplierId) async {
    final purchaseService = context.read<PurchaseService>();
    try {
      final delegates = await purchaseService.getDelegatesForSupplier(supplierId);
      if (!mounted || _selectedSupplier?.id != supplierId) return;
      String? prefill;
      // 🛡️ في التعديل: اسم مندوب الفاتورة يظهر في الحقل، وإلا كان الحفظ يفكّ
      //    ربطه بصمت (delegateId = null).
      final delegateId = widget.existingInvoice?.delegateId;
      if (delegateId != null && _delegateNameController.text.isEmpty) {
        final i = delegates.indexWhere((d) => d.id == delegateId);
        if (i != -1) prefill = delegates[i].name;
      }
      setState(() => _delegates = delegates);
      if (prefill != null) {
        _delegateNameController.text = prefill;
        _delegateFieldController?.text = prefill;
      }
    } catch (_) {
      // المندوب اختياري: فشل تحميل القائمة لا يمنع إدخال الفاتورة
    }
  }

  double get _totalAmount => _items.fold(0, (sum, item) => sum + item.totalPrice);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(widget.existingInvoice != null ? 'تعديل فاتورة مشتريات' : 'فاتورة شراء جديدة'),
        backgroundColor: const Color(0xFF455A64),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Column(
                children: [
                  // Expanded Scrollable Area (Header + Items)
                  Expanded(
                    child: CustomScrollView(
                      slivers: [
                        // 1. Invoice Header Form (Supplier, Date, etc.)
                        SliverToBoxAdapter(
                          child: _buildHeaderSection(),
                        ),

                        // 2. Items Title & Add Button
                        SliverToBoxAdapter(
                          child: _buildItemsHeaderActions(),
                        ),

                        // 3. Items Table Header (Pinned or Scrolling - let's make it sticky)
                         SliverPersistentHeader(
                           pinned: true,
                           delegate: _TableHeadersDelegate(),
                         ),

                        // 4. Items List
                        _items.isEmpty
                            ? SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey[300]),
                                      const SizedBox(height: 16),
                                      Text(
                                        'لم تتم إضافة منتجات بعد',
                                        style: TextStyle(color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    return Column(
                                      children: [
                                        _buildItemRow(_items[index], index),
                                        const Divider(height: 1),
                                      ],
                                    );
                                  },
                                  childCount: _items.length,
                                ),
                              ),
                      ],
                    ),
                  ),
                  
                  // Footer Section (Fixed at bottom)
                  _buildFooterSection(),
                ],
              ),
            ),
    );
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final originalFile = File(result.files.single.path!);
      final appDir = await getApplicationDocumentsDirectory();
      final attachmentsDir = Directory('${appDir.path}/attachments');
      if (!await attachmentsDir.exists()) {
        await attachmentsDir.create(recursive: true);
      }
      final ext = p.extension(originalFile.path);
      final baseName = p.basenameWithoutExtension(originalFile.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Use timestamp to guarantee uniqueness and avoid PathExistsException
      final uniqueName = '${baseName}_$timestamp$ext'; 
      final savedFile = await originalFile.copy('${attachmentsDir.path}/$uniqueName');
      if (!mounted) return;

      setState(() {
        _attachmentPath = savedFile.path;
      });
      
      // 🚀 Trigger OCR automatically
      _processInvoiceFile(savedFile);
    }
  }

  Future<void> _processInvoiceFile(File file) async {
    setState(() => _isLoading = true);
    
    try {
      // 🚀 Use Ensemble AI Service (InvoiceNet Logic) — من المزوّد إن وُجد
      EnsembleAIService aiService;
      try {
        aiService = context.read<EnsembleAIService>();
      } catch (_) {
        aiService = EnsembleAIService();
      }

      final result = await aiService.extractInvoiceData(file);

      if (result.containsKey('error')) {
        throw result['error'];
      }

      // 1. Process Metadata
      if (result['invoice_number'] != null && result['invoice_number'].toString().isNotEmpty) {
        _invoiceNumberController.text = result['invoice_number'].toString();
      }
      
      // Auto-Select Supplier if matched (Future Feature)
      // if (result['vendor'] != null) { ... }

      List<dynamic> extractedItems = result['items'] ?? [];
      
      if (extractedItems.isEmpty) {
         throw "لم يتم العثور على أصناف في الفاتورة. تأكد من وضوح الجدول.";
      }

      // 📊 Debug: Log all extracted items
      print('📊 AI Extracted ${extractedItems.length} items:');
      for (int i = 0; i < extractedItems.length; i++) {
        print('  [$i] name="${extractedItems[i]['name']}" qty=${extractedItems[i]['qty']} price=${extractedItems[i]['price']} total=${extractedItems[i]['line_total']} unit="${extractedItems[i]['unit'] ?? ''}"');
      }
      print('📊 Detection method: ${result['detection_method'] ?? 'unknown'}');

      int addedCount = 0;
      for (var item in extractedItems) {
         String name = item['name']?.toString() ?? 'منتج';
         double qty = (item['qty'] as num?)?.toDouble() ?? 1.0;
         double price = (item['price'] as num?)?.toDouble() ?? 0.0;
         double total = (item['line_total'] as num?)?.toDouble() ?? (qty * price);
         String extractedUnit = item['unit']?.toString() ?? '';
         
         // Basic filtering for noise
         if (price == 0 && total == 0) continue;

         // Try match existing product (exact match first, then partial)
         Product? matchedProduct;
         try {
           matchedProduct = _products.firstWhere((p) => p.name.trim() == name.trim());
         } catch (_) {
           // Try partial match (product name contains extracted name or vice versa)
           try {
             matchedProduct = _products.firstWhere((p) => 
               p.name.trim().contains(name.trim()) || name.trim().contains(p.name.trim())
             );
           } catch (_) {}
         }
         
         // Determine ID (-1 for new)
         int pId = matchedProduct?.id ?? -1;
         String pName = matchedProduct?.name ?? name;
         String pUnit = extractedUnit.isNotEmpty ? extractedUnit : (matchedProduct?.unit ?? 'قطعة');

         // 🛡️ كمية صفرية أو سالبة من القراءة الآلية: قسمة على صفر ⇒ سعر لا نهائي
         if (qty <= 0) qty = 1.0;

         _items.add(PurchaseInvoiceItem(
            productId: pId,
            productName: pName,
            quantity: qty,
            unitPrice: price > 0 ? price : (total / qty),
            totalPrice: total,
            unitName: pUnit,
            conversionFactor: 1.0, 
         ));
         addedCount++;
      }
      _syncCashPaid();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تم استخراج $addedCount صنفاً بنجاح!'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ تنبيه: $e'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadExt(int invoiceId) async {
    try {
      final db = await DatabaseService().database;
      final e = await PurchaseExt.read(db, invoiceId);
      if (mounted) {
        setState(() {
          _warehouseId = e.warehouseId;
          _cashBoxId = e.cashBoxId;
        });
      }
    } catch (_) {}
  }

  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Row 1: Supplier + Invoice Number
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<Supplier>(
                  value: _selectedSupplier,
                  decoration: const InputDecoration(
                    labelText: 'المورد *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: _suppliers.map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s.name, overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: _supplierLocked
                      ? null
                      : (val) {
                          setState(() {
                            _selectedSupplier = val;
                            _currency = _normCurrency(val?.currency);
                            // 🛡️ مندوبو المورد السابق لا يُربطون بفاتورة المورد الجديد
                            _delegates = [];
                          });
                          final id = val?.id;
                          if (id != null) _loadDelegatesForSupplier(id);
                        },
                  validator: (val) => val == null ? 'اختر المورد' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _invoiceNumberController,
                  decoration: const InputDecoration(
                    labelText: 'رقم الفاتورة',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Row 2: Date + Currency
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _invoiceDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setState(() => _invoiceDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'التاريخ',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: Text(intl.DateFormat('yyyy-MM-dd').format(_invoiceDate)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _currency,
                  decoration: const InputDecoration(
                    labelText: 'العملة',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'IQD', child: Text('IQD')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                  ],
                  onChanged: (val) => setState(() => _currency = val!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 🆕 Row 3: Payment Type + Paid Amount
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _paymentType,
                  decoration: const InputDecoration(
                    labelText: 'نوع الدفع',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payment),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'دين', child: Text('دين')),
                    DropdownMenuItem(value: 'نقد', child: Text('نقد')),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _paymentType = val ?? 'دين';
                      _syncCashPaid();
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _paidAmountController,
                  enabled: _paymentType == 'دين',
                  decoration: const InputDecoration(
                    labelText: 'المبلغ المسدد',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.money),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                  validator: (v) {
                    final paid = parseMoney(v) ?? 0.0;
                    if (paid < 0) return 'مبلغ غير صالح';
                    if (paid > _totalAmount + 0.01) return 'أكبر من إجمالي الفاتورة';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 🏬 المخزن المستلم + الصندوق/البنك (مثل سهل)
          Wrap(spacing: 12, runSpacing: 12, children: [
            WarehouseDropdown(
              value: _warehouseId,
              label: 'المخزن المستلم',
              onChanged: (w) => setState(() => _warehouseId = w?.id),
            ),
            CashBoxDropdown(
              value: _cashBoxId,
              label: 'يُدفع من (صندوق/بنك)',
              onChanged: (b) => setState(() => _cashBoxId = b?.id),
            ),
          ]),
          const SizedBox(height: 12),

          // 🆕 Row 4: Delegate Name
          Autocomplete<String>(
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
              return _delegates
                  .where((d) => d.name.contains(textEditingValue.text))
                  .map((d) => d.name);
            },
            onSelected: (selection) {
              _delegateNameController.text = selection;
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              // Sync with our controller — مستمع واحد لكل متحكم (لا يتراكم مع كل بناء)
              if (!identical(_delegateFieldController, controller)) {
                _delegateFieldController = controller;
                if (_delegateNameController.text.isNotEmpty && controller.text.isEmpty) {
                  controller.text = _delegateNameController.text;
                }
                controller.addListener(() {
                  _delegateNameController.text = controller.text;
                });
              }

              return TextField(
                controller: controller,
                focusNode: focusNode,
                onSubmitted: (val) => onFieldSubmitted(),
                decoration: const InputDecoration(
                  labelText: 'اسم المندوب',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          
          // Attachment Row
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_file, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _attachmentPath != null 
                              ? p.basename(_attachmentPath!) 
                              : 'إرفاق صورة أو PDF (اختياري)',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _attachmentPath != null ? Colors.black : Colors.grey,
                          ),
                        ),
                      ),
                      if (_attachmentPath != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => setState(() => _attachmentPath = null),
                        )
                      else
                        TextButton(
                          onPressed: _pickAttachment,
                          child: const Text('اختيار ملف'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 🆕 Extracted: Items Header Actions
  Widget _buildItemsHeaderActions() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Text(
            'المنتجات',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _showAddProductDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF455A64),
            ),
            icon: const Icon(Icons.add),
            label: const Text('إضافة منتج'),
          ),
        ],
      ),
    );
  }

  // Helper class for Sticky Headers
  
  Widget _buildItemRow(PurchaseInvoiceItem item, int index) {
    bool isNew = item.productId == -1;

    return Container(
      color: isNew ? Colors.blue.withOpacity(0.05) : Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        children: [
          // #
          SizedBox(width: 30, child: Text('${index + 1}')),
          
          // Product Name
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.productName ?? 'منتج غير معروف',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isNew) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('جديد', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => _defineNewProduct(item, index),
                    child: const Icon(Icons.add_circle, color: Colors.blue, size: 20),
                  ),
                ],
              ],
            ),
          ),
          
          // Price
          Expanded(
            flex: 1,
            child: Text(
              _formatNumber(item.unitPrice),
              textAlign: TextAlign.center,
            ),
          ),
          
          // Qty
          Expanded(
            flex: 1,
            child: Text(
              fmtQty(item.quantity),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          
          // Unit
          Expanded(
            flex: 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(item.unitName ?? '', textAlign: TextAlign.center),
                if (item.conversionFactor > 1)
                  Text(
                    '(x${item.conversionFactor.toInt()})',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
          ),
          
          // Total
          Expanded(
            flex: 1,
            child: Text(
              _formatNumber(item.totalPrice),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF455A64)),
            ),
          ),
          
          // Actions
          SizedBox(
            width: 40,
            child: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
              tooltip: 'حذف المادة',
              onPressed: () {
                setState(() {
                  _items.removeAt(index);
                  _syncCashPaid();
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('الإجمالي:', style: TextStyle(fontSize: 18)),
              Text(
                '${_formatNumber(_totalAmount)} $_currency',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF455A64),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : () => _saveInvoice(confirm: false),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ كمسودة'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : () => _saveInvoice(confirm: true),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle),
                  label: const Text('تأكيد واستلام'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _defineNewProduct(PurchaseInvoiceItem item, int index) async {
    // Open the Quick Dialog
    showDialog(
      context: context,
      builder: (context) => QuickProductCreationDialog(
        existingProducts: _products,
        // Pre-fill parameters
        initialName: item.productName,
        initialCost: item.unitPrice, 
        initialUnit: item.unitName,
        initialQty: item.quantity,
        onProductSelected: (product, quantity, price, unit) {
           // This callback is called when user clicks "Add" in the dialog
           setState(() {
              // 1. Add to products list if new (handled by dialog internally mostly, but we need to refresh _products)
              
              bool exists = _products.any((p) => p.id == product.id);
              if (!exists) {
                // If ID is created by dialog, adding it here allows Dropdowns to work
                _products.add(product);
              }
              
              // 2. Update the invoice item
              //    🛡️ معامل التحويل من هرم وحدات المادة (كان ثابتاً 1.0 ⇒ شراء
              //    «كرتون» يُدخل للمخزون قطعة واحدة بكلفة الكرتون كاملة)
              if (index < _items.length) {
                _items[index] = PurchaseInvoiceItem(
                  productId: product.id ?? -1,
                  productName: product.name,
                  quantity: quantity,
                  unitPrice: price,
                  totalPrice: quantity * price,
                  unitName: unit,
                  conversionFactor: _conversionFactorFor(product, unit),
                );
              }
              _syncCashPaid();
           });
           ScaffoldMessenger.of(this.context).showSnackBar(
             const SnackBar(content: Text('تم تعريف المنتج بنجاح')),
           );
        },
      ),
    );
  }

  void _showAddProductDialog() {
    showDialog(
      context: context,
      builder: (context) => QuickProductCreationDialog(
        existingProducts: _products,
        onProductSelected: (product, quantity, price, unit) async {
          // Calculate Conversion Factor from Unit Hierarchy
          final double factor = _conversionFactorFor(product, unit);

          // Handle New Product Creation
          if (product.id == null || product.id == -1) {
             final dbService = DatabaseService();
             try {
               final newId = await dbService.insertProduct(product);
               product = product.copyWith(id: newId);
               if (!mounted) return;
               setState(() {
                 _products.add(product);
               });
             } catch (e) {
               if (!mounted) return;
               ScaffoldMessenger.of(this.context).showSnackBar(
                 SnackBar(content: Text('فشل إنشاء المنتج الجديد: $e')),
               );
               return;
             }
          }
          if (!mounted) return;
          
          setState(() {
            // DEBUG: Print conversion factor and base values
            print('📦 PURCHASE_DEBUG: Adding item ${product.name}');
            print('📦 PURCHASE_DEBUG: Unit selected: $unit');
            print('📦 PURCHASE_DEBUG: Quantity: $quantity');
            print('📦 PURCHASE_DEBUG: Unit Price: $price');
            print('📦 PURCHASE_DEBUG: Conversion Factor: $factor');
            print('📦 PURCHASE_DEBUG: Base Quantity: ${quantity * factor}');
            print('📦 PURCHASE_DEBUG: Base Unit Cost: ${price / factor}');
            
            _items.add(PurchaseInvoiceItem(
              productId: product.id!,
              productName: product.name,
              quantity: quantity,
              unitPrice: price,
              totalPrice: quantity * price,
              unitName: unit,
              // baseUnitCost: price / factor, // (implicit via getter)
              conversionFactor: factor,
            ));
            _syncCashPaid();
          });
        },
      ),
    );
  }

  /// كم وحدة أساسية في الوحدة المشتراة (كرتون = 24 قطعة مثلاً) من هرم وحدات المادة.
  double _conversionFactorFor(Product product, String unit) {
    double factor = 1.0;
    final baseUnit = product.unit == 'piece' ? 'قطعة' :
                    (product.unit == 'meter' ? 'متر' : product.unit);
    if (unit == baseUnit || unit == product.unit) return 1.0;

    // Check unit hierarchy for conversion factor
    final hierarchy = product.getUnitHierarchyList();
    double cumulativeFactor = 1.0;
    for (var level in hierarchy) {
      final unitName = level['unit_name']?.toString() ?? '';
      final qty = (level['quantity'] as num?)?.toDouble() ?? 1.0;
      if (unitName.isNotEmpty) {
        cumulativeFactor *= qty;
        // If this is the unit we're buying, use this cumulative factor
        if (unitName == unit) {
          factor = cumulativeFactor;
          break;
        }
      }
    }

    // Fallback to piecesPerUnit if hierarchy doesn't match
    if (factor == 1.0 && product.piecesPerUnit != null && product.piecesPerUnit! > 1) {
      factor = product.piecesPerUnit!.toDouble();
    }
    return factor > 0 ? factor : 1.0;
  }

  Future<void> _saveInvoice({required bool confirm}) async {
    // 🛡️ منع الحفظ المزدوج: الضغط مرتين قبل إعادة البناء كان يُنشئ فاتورتين
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إضافة منتجات أولاً')),
      );
      return;
    }
    if (_items.any((item) => item.quantity <= 0 || item.unitPrice < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يوجد مادة بكمية صفر أو سعر سالب — صحّحها أو احذفها'), backgroundColor: Colors.orange),
      );
      return;
    }

    // 🔍 Validation: Check for undefined items (New Products)
    if (_items.any((item) => item.productId == -1)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ يوجد منتجات غير معرفة (باللون الأزرق). يرجى تعريفها أو حذفها قبل الحفظ.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
 
    try {
      final purchaseService = context.read<PurchaseService>();
      final existing = widget.existingInvoice;
      final supplier = _selectedSupplier!;
      final supplierId = supplier.id;
      if (supplierId == null) throw 'المورد المختار غير محفوظ';

      // 🔒 تثبيت الإدخالات: لا إضافة ولا تعديل بتاريخ داخل فترة مثبّتة
      if (!await PeriodLock.guard(context, _invoiceDate)) return;
      if (!mounted) return;
      if (existing != null && !await PeriodLock.guard(context, existing.date)) return;
      if (!mounted) return;

      // 💰 المبلغ المسدد: «نقد» = الإجمالي كاملاً دائماً
      final double total = _totalAmount;
      final double paidAmount = _paymentType == 'نقد' ? total : (parseMoney(_paidAmountController.text) ?? 0.0);
      if (paidAmount < 0 || paidAmount > total + 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('المبلغ المسدد يجب أن يكون بين صفر وإجمالي الفاتورة'), backgroundColor: Colors.orange),
        );
        return;
      }

      // ⚠️ فاتورة مؤكدة تُحفظ كمسودة = إلغاء أثرها على المخزون ورصيد المورد
      if (existing != null && existing.status == 'confirmed' && !confirm) {
        final ok = await confirmDialog(
          context,
          'تحويل الفاتورة إلى مسودة',
          'هذه الفاتورة مؤكدة. حفظها كمسودة يُلغي أثرها: تُخرج كمياتها من المخزون ويُلغى دينها على المورد.\n'
              'للإبقاء عليها مؤكدة اضغط «تأكيد واستلام» بدلاً من ذلك.',
          ok: 'حفظ كمسودة',
          color: Colors.orange,
        );
        if (!ok || !mounted) return;
      }

      // 🔁 رقم فاتورة مكرر لنفس المورد (إدخال الفاتورة الورقية مرتين)
      final number = _invoiceNumberController.text.trim();
      if (number.isNotEmpty) {
        final sameSupplier = await purchaseService.getInvoicesForSupplier(supplierId);
        final dup = sameSupplier.any((i) => i.id != existing?.id && i.invoiceNumber.trim() == number);
        if (dup) {
          if (!mounted) return;
          final ok = await confirmDialog(
            context,
            'رقم فاتورة مكرر',
            'يوجد لدى المورد «${supplier.name}» فاتورة بالرقم $number مسبقاً.\nهل تريد الحفظ على أي حال؟',
            ok: 'حفظ على أي حال',
            color: Colors.orange,
          );
          if (!ok || !mounted) return;
        }
      }

      // 1️⃣ Handle Delegate (Find or Create)
      int? finalDelegateId;
      if (_delegateNameController.text.trim().isNotEmpty) {
        final delegateName = _delegateNameController.text.trim();
        final existingIndex = _delegates.indexWhere(
          (d) => d.name.toLowerCase() == delegateName.toLowerCase(),
        );

        if (existingIndex != -1) {
          finalDelegateId = _delegates[existingIndex].id;
        } else {
          // Create new delegate automatically
          finalDelegateId = await purchaseService.addDelegate(SupplierDelegate(
            supplierId: supplierId,
            name: delegateName,
          ));
        }
      }

      final invoice = PurchaseInvoice(
        invoiceNumber: number.isNotEmpty
            ? number
            : 'INV-${DateTime.now().millisecondsSinceEpoch}',
        supplierId: supplierId,
        delegateId: finalDelegateId, // 👤 Link delegate
        totalAmount: total,
        paidAmount: paidAmount, // 💰 Set paid amount
        currency: _currency,
        status: confirm ? 'confirmed' : 'draft',
        date: _invoiceDate,
        dueDate: _dueDate,
        createdByUserId: existing?.createdByUserId ?? currentUserId(),
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        lastModifiedAt: DateTime.now(),
        attachmentPath: _attachmentPath,
      );

      if (existing != null && existing.id != null) {
        final oldItems = await purchaseService.getInvoiceItems(existing.id!);
        await purchaseService.updatePurchaseInvoiceWithReversal(
          existing,
          invoice,
          oldItems,
          _items,
          warehouseId: _warehouseId,
          cashBoxId: _cashBoxId,
        );
      } else {
        await purchaseService.savePurchaseInvoice(invoice, _items,
            confirm: confirm, warehouseId: _warehouseId, cashBoxId: _cashBoxId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(confirm ? 'تم تأكيد الفاتورة وتحديث المخزون ✓' : 'تم حفظ المسودة ✓'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      // يُعاد تفعيل الأزرار في كل خروج مبكر أو خطأ (النجاح يغلق الشاشة)
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // #,##0.## — الدولار يحتفظ بكسوره (كان يُقرَّب لأقرب رقم صحيح في العرض)
  String _formatNumber(double number) => _moneyFmt.format(number);
}

class _TableHeadersDelegate extends SliverPersistentHeaderDelegate {
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: 56, // Force height to match extent
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        boxShadow: overlapsContent
            ? [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]
            : [],
      ),
      child: const Row(
        children: [
          SizedBox(width: 30, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 3, child: Text('المنتج', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 1, child: Text('سعر الوحدة', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 1, child: Text('الكمية', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 1, child: Text('الوحدة', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 1, child: Text('الإجمالي', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(width: 40), // Actions
        ],
      ),
    );
  }

  @override
  double get maxExtent => 56.0;

  @override
  double get minExtent => 56.0;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => false;
}
