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
import '../services/database_service.dart';
import '../widgets/quick_product_creation_dialog.dart';
import '../services/ocr_service.dart';
import '../services/ensemble_ai_service.dart'; // ✅ Fixed Import
import '../models/ocr_invoice_item.dart';
import 'product_entry_screen.dart';

/// شاشة إنشاء فاتورة شراء (Odoo-Style مع Unit Conversion)
class CreatePurchaseInvoiceScreen extends StatefulWidget {
  final Supplier? preselectedSupplier;

  const CreatePurchaseInvoiceScreen({super.key, this.preselectedSupplier});

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
  final _delegateNameController = TextEditingController();
  List<SupplierDelegate> _delegates = []; // For auto-complete or check

  @override
  void initState() {
    super.initState();
    _selectedSupplier = widget.preselectedSupplier;
    if (_selectedSupplier != null) {
      _currency = _selectedSupplier!.currency;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    final purchaseService = context.read<PurchaseService>();
    final dbService = DatabaseService();
    
    final suppliers = await purchaseService.getSuppliers();
    final products = await dbService.getAllProducts();
    
    setState(() {
      _suppliers = suppliers;
      _products = products;
      // Find matching supplier from loaded list (to match dropdown items by reference)
      if (_selectedSupplier != null) {
        _selectedSupplier = _suppliers.firstWhere(
          (s) => s.id == _selectedSupplier!.id,
          orElse: () => _selectedSupplier!,
        );
        _currency = _selectedSupplier!.currency;
        _loadDelegatesForSupplier(_selectedSupplier!.id!);
      }
      _isLoading = false;
    });
  }

  Future<void> _loadDelegatesForSupplier(int supplierId) async {
    final purchaseService = context.read<PurchaseService>();
    final delegates = await purchaseService.getDelegatesForSupplier(supplierId);
    setState(() {
      _delegates = delegates;
    });
  }

  double get _totalAmount => _items.fold(0, (sum, item) => sum + item.totalPrice);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('فاتورة شراء جديدة'),
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
      // 🚀 Use Ensemble AI Service (InvoiceNet Logic)
      final ensemble = context.read<EnsembleAIService>(); // Ensure it's in provider or instance
      // Fallback if not provided (temp fix for hot reload safety):
      final aiService = EnsembleAIService(); 
      
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تم استخراج $addedCount صنفاً بنجاح!'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ تنبيه: $e'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
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
                  onChanged: (val) {
                    setState(() {
                      _selectedSupplier = val;
                      _currency = val?.currency ?? 'IQD';
                    });
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
                      _paymentType = val!;
                      if (_paymentType == 'نقد') {
                        _paidAmountController.text = _totalAmount.toString();
                      }
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
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
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
              // Sync with our controller
              if (_delegateNameController.text.isNotEmpty && controller.text.isEmpty) {
                controller.text = _delegateNameController.text;
              }
              controller.addListener(() {
                _delegateNameController.text = controller.text;
              });

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
              '${item.quantity}',
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
              onPressed: () {
                setState(() => _items.removeAt(index));
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
              _items[index] = PurchaseInvoiceItem(
                productId: product.id!,
                productName: product.name,
                quantity: quantity,
                unitPrice: price,
                totalPrice: quantity * price,
                unitName: unit,
                conversionFactor: 1.0, // Factor calculation handled in save or could be improved here
              );
              
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم تعريف المنتج بنجاح')),
              );
           });
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
          // If we bought 'Carton' (unit) and Product base unit is 'Piece' (product.unit)
          // We need to find the cumulative factor from hierarchy
          double factor = 1.0;
          
          final baseUnit = product.unit == 'piece' ? 'قطعة' : 
                          (product.unit == 'meter' ? 'متر' : product.unit);
          
          if (unit != baseUnit && unit != product.unit) {
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
          }

          // Handle New Product Creation
          if (product.id == -1) {
             final dbService = DatabaseService();
             try {
               final newId = await dbService.insertProduct(product);
               product = product.copyWith(id: newId);
               
               setState(() {
                 _products.add(product);
               });
             } catch (e) {
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text('فشل إنشاء المنتج الجديد: $e')),
               );
               return;
             }
          }
          
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
          });
        },
      ),
    );
  }

  void _saveInvoice({required bool confirm}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إضافة منتجات أولاً')),
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
            supplierId: _selectedSupplier!.id!,
            name: delegateName,
          ));
        }
      }

      // 2️⃣ Handle Paid Amount
      final paidAmount = double.tryParse(_paidAmountController.text) ?? 0.0;

      final invoice = PurchaseInvoice(
        invoiceNumber: _invoiceNumberController.text.isNotEmpty
            ? _invoiceNumberController.text
            : 'INV-${DateTime.now().millisecondsSinceEpoch}',
        supplierId: _selectedSupplier!.id!,
        delegateId: finalDelegateId, // 👤 Link delegate
        totalAmount: _totalAmount,
        paidAmount: paidAmount, // 💰 Set paid amount
        currency: _currency,
        status: confirm ? 'confirmed' : 'draft',
        date: _invoiceDate,
        dueDate: _dueDate,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        attachmentPath: _attachmentPath,
      );

      await context.read<PurchaseService>().savePurchaseInvoice(invoice, _items, confirm: confirm);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(confirm ? 'تم تأكيد الفاتورة وتحديث المخزون ✓' : 'تم حفظ المسودة ✓'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  String _formatNumber(double number) {
    return intl.NumberFormat('#,##0').format(number);
  }
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
