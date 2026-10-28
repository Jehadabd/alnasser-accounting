import 'dart:io';
import '../services/save_lock.dart'; // 🔒 قفل الحفظ
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
import '../services/ensemble_ai_service_factory.dart';
import '../accounting/screens/acc_ui.dart' show accAppBar;
import '../erp/erp_kit.dart' show ErpTheme;
import '../owner/ai_invoice/ai_alias_store.dart';
import '../owner/ai_invoice/ai_purchase_prefill.dart';
import '../owner/owner_access.dart';

/// شاشة إنشاء فاتورة شراء (Odoo-Style مع Unit Conversion)
class CreatePurchaseInvoiceScreen extends StatefulWidget {
  final Supplier? preselectedSupplier;
  final PurchaseInvoice? existingInvoice;
  /// 👑🤖 تعبئة مسبقة من شاشة «فاتورة بالذكاء الاصطناعي» (حساب المالك)
  final AiPurchasePrefill? aiPrefill;

  const CreatePurchaseInvoiceScreen({super.key, this.preselectedSupplier, this.existingInvoice, this.aiPrefill});

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
    final ai = widget.aiPrefill;
    if (ai != null && widget.existingInvoice == null) {
      if (ai.invoiceNumber.isNotEmpty) _invoiceNumberController.text = ai.invoiceNumber;
      if (ai.date != null) _invoiceDate = ai.date!;
      _currency = _normCurrency(ai.currency);
      _attachmentPath = ai.attachmentPath;
      _items = List.of(ai.items);
      _paymentType = ai.isCash ? 'نقد' : 'دين';
      if (!ai.isCash && ai.paidAmount > 0) _paidAmountController.text = _moneyFmt.format(ai.paidAmount);
      _syncCashPaid();
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
          // عملة الفاتورة المقروءة بالذكاء الاصطناعي تبقى كما هي
          if (widget.aiPrefill == null) _currency = _normCurrency(_selectedSupplier!.currency);
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
    // نفس رأس وشكل أزرار شاشات المحاسبة والموردين
    return Theme(
      data: ErpTheme.apply(Theme.of(context)),
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: accAppBar(
        widget.existingInvoice != null ? 'تعديل فاتورة مشتريات' : 'فاتورة شراء جديدة',
        icon: Icons.receipt_long_rounded,
        subtitle: _selectedSupplier == null ? 'اختر المورد ثم أضف المواد' : 'المورد: ${_selectedSupplier!.name}',
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Theme(
              // 🎨 حقول موحّدة الشكل (الشكل فقط — الحقول والتحقق كما هي)
              data: Theme.of(context).copyWith(
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: const Color(0xFFFBFCFE),
                  isDense: true,
                  labelStyle: const TextStyle(color: Color(0xFF667085)),
                  prefixIconColor: const Color(0xFF0F3460),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _pLine)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _pLine)),
                  disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEEF1F6))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF0F3460), width: 1.6)),
                ),
              ),
              child: Form(
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
                                    return _buildItemRow(_items[index], index);
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
            ),
    );
  }

  static const _pLine = Color(0xFFE4E9F1);
  static const _pNavy = Color(0xFF0F3460);
  static const _pMuted = Color(0xFF667085);

  Widget _sectionLabel(IconData icon, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(icon, size: 18, color: _pNavy),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1B2433))),
        ]),
      );

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
      
      // 👑 القراءة الآلية للفاتورة المرفقة لحساب المالك فقط؛ لغيره يبقى الملف مرفقاً فقط
      if (OwnerAccess.enabled) _processInvoiceFile(savedFile);
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
      debugPrint('📊 AI Extracted ${extractedItems.length} items:');
      for (int i = 0; i < extractedItems.length; i++) {
        debugPrint('  [$i] name="${extractedItems[i]['name']}" qty=${extractedItems[i]['qty']} price=${extractedItems[i]['price']} total=${extractedItems[i]['line_total']} unit="${extractedItems[i]['unit'] ?? ''}"');
      }
      debugPrint('📊 Detection method: ${result['detection_method'] ?? 'unknown'}');

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
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _pLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel(Icons.storefront_rounded, 'المورد والفاتورة'),
          // Row 1: Supplier + Invoice Number
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<Supplier>(
                  initialValue: _selectedSupplier,
                  decoration: const InputDecoration(
                    labelText: 'المورد *',
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
                  initialValue: _currency,
                  decoration: const InputDecoration(
                    labelText: 'العملة',
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

          const Divider(height: 26, color: _pLine),
          _sectionLabel(Icons.payments_outlined, 'الدفع والاستلام'),
          // 🆕 Row 3: Payment Type + Paid Amount
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _paymentType,
                  decoration: const InputDecoration(
                    labelText: 'نوع الدفع',
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
                    prefixIcon: Icon(Icons.money),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                  onChanged: (_) => setState(() {}), // يحدّث «المسدد/الباقي» في الأسفل (عرض فقط)
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
                    color: const Color(0xFFFBFCFE),
                    border: Border.all(color: _pLine),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_file, color: _pMuted),
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
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, color: _pNavy, size: 20),
          const SizedBox(width: 8),
          const Text(
            'المواد',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1B2433)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: _pNavy.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
            child: Text('${_items.length}', style: const TextStyle(fontWeight: FontWeight.w800, color: _pNavy)),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _showAddProductDialog,
            style: FilledButton.styleFrom(
              backgroundColor: _pNavy,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة منتج', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // Helper class for Sticky Headers
  
  Widget _buildItemRow(PurchaseInvoiceItem item, int index) {
    bool isNew = item.productId == -1;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
        color: isNew ? const Color(0xFFF2F6FF) : (index.isOdd ? const Color(0xFFFAFBFD) : Colors.white),
        border: const Border(
          left: BorderSide(color: _pLine),
          right: BorderSide(color: _pLine),
          bottom: BorderSide(color: _pLine),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          // #
          SizedBox(width: 30, child: Text('${index + 1}', style: const TextStyle(color: _pMuted))),
          
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
                  TextButton.icon(
                    onPressed: () => _defineNewProduct(item, index),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1D4ED8),
                      backgroundColor: const Color(0xFF1D4ED8).withValues(alpha: 0.08),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: const Size(0, 30),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    label: const Text('مادة جديدة — عرّفها', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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
                Text(item.unitName, textAlign: TextAlign.center),
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
              style: const TextStyle(fontWeight: FontWeight.w800, color: _pNavy),
            ),
          ),
          
          // Actions
          SizedBox(
            width: 40,
            child: IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB42318), size: 20),
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
    // عرض فقط: المسدد والباقي من الحقول نفسها
    final paidShown = _paymentType == 'نقد' ? _totalAmount : (parseMoney(_paidAmountController.text) ?? 0.0);
    final rest = _totalAmount - paidShown;
    Widget fig(String label, String value, Color c, {bool big = false}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: _pMuted)),
            Text(value,
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: big ? 24 : 16, fontWeight: FontWeight.w900, color: c)),
          ],
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _pLine)),
      ),
      child: Column(
        children: [
          // Total
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              fig('الإجمالي ($_currency)', _formatNumber(_totalAmount), _pNavy, big: true),
              const SizedBox(width: 28),
              fig('المسدد', _formatNumber(paidShown), const Color(0xFF067647)),
              const SizedBox(width: 28),
              fig('الباقي للمورد', _formatNumber(rest < 0 ? 0 : rest), rest > 0.004 ? const Color(0xFFB42318) : _pMuted),
              const Spacer(),
              Text('${_items.length} مادة', style: const TextStyle(color: _pMuted)),
            ],
          ),
          const SizedBox(height: 14),
          
          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : () => _saveInvoice(confirm: false),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ كمسودة'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _pNavy,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  label: const Text('تأكيد واستلام', style: TextStyle(fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF067647),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              // 🧠 مادة جديدة من فاتورة مورد مقروءة بالذكاء الاصطناعي: نتعلّم اسمها الأصلي
              final aiOriginal = widget.aiPrefill?.originalNames[item.productName ?? ''];
              final newId = product.id;
              if (aiOriginal != null && newId != null && newId > 0) {
                AiAliasStore.learn(
                  supplierId: _selectedSupplier?.id,
                  alias: aiOriginal,
                  productId: newId,
                  productName: product.name,
                ).catchError((_) {});
              }
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
            debugPrint('📦 PURCHASE_DEBUG: Adding item ${product.name}');
            debugPrint('📦 PURCHASE_DEBUG: Unit selected: $unit');
            debugPrint('📦 PURCHASE_DEBUG: Quantity: $quantity');
            debugPrint('📦 PURCHASE_DEBUG: Unit Price: $price');
            debugPrint('📦 PURCHASE_DEBUG: Conversion Factor: $factor');
            debugPrint('📦 PURCHASE_DEBUG: Base Quantity: ${quantity * factor}');
            debugPrint('📦 PURCHASE_DEBUG: Base Unit Cost: ${price / factor}');
            
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

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط (القفل قبل أي انتظار)
  Future<void> _saveInvoice({required bool confirm}) async {
    await SaveLock.run(() => _saveInvoiceUnlocked(confirm: confirm), message: 'جارٍ حفظ فاتورة الشراء…');
  }
  Future<void> _saveInvoiceUnlocked({required bool confirm}) async {
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
      color: const Color(0xFFF3F6FB),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0F3460),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.white),
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
      ),
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
