import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../models/category.dart';
import '../services/database_service.dart';
import '../widgets/formatters.dart';
import '../widgets/camera_barcode_scanner_dialog.dart';

// --- VISUAL CONSTANTS (From ProductEntryScreen) ---
const Color kPrimaryColor = Color(0xFF5D5FEF);
const Color kBackgroundColor = Color(0xFFF5F7FA);
const Color kCardColor = Colors.white;
const Color kTextColor = Color(0xFF1E1E2E);
const Color kInputFillColor = Color(0xFFF8F9FA);

// --- MODERN WIDGETS RE-DEFINITION (For Dialog Context) ---
class ModernSectionCard extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;
  final Widget child;

  const ModernSectionCard({
    super.key,
    required this.number,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: const Color(0xff121212).withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: kPrimaryColor, borderRadius: BorderRadius.circular(8)),
                  child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kTextColor)),
                    Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

class ModernTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool isRequired;
  final List<TextInputFormatter>? inputFormatters;
  final Function(String)? onChanged;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final bool autofocus;

  const ModernTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.isRequired = false,
    this.inputFormatters,
    this.onChanged,
    this.suffixIcon,
    this.keyboardType,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
            if (isRequired) const Text(' *', style: TextStyle(color: Colors.red)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: kInputFillColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.transparent),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            autofocus: autofocus,
            onChanged: onChanged,
            validator: isRequired ? (v) => (v == null || v.isEmpty) ? 'مطلوب' : null : null,
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
              suffixIcon: suffixIcon,
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }
}

class ModernDropdownField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final Function(T?) onChanged;
  final String? hint;

  const ModernDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: kInputFillColor, borderRadius: BorderRadius.circular(12)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              items: items,
              onChanged: onChanged,
              hint: hint != null ? Text(hint!, style: TextStyle(color: Colors.grey[400], fontSize: 13)) : null,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}

class QuickProductCreationDialog extends StatefulWidget {
  final List<Product> existingProducts;
  final Function(Product product, double quantity, double price, String unit) onProductSelected;
  
  // --- Smart Import Params ---
  final String? initialName;
  final double? initialCost;
  final String? initialUnit;
  final double? initialQty;

  const QuickProductCreationDialog({
    super.key,
    required this.existingProducts,
    required this.onProductSelected,
    this.initialName,
    this.initialCost,
    this.initialUnit,
    this.initialQty,
  });

  @override
  State<QuickProductCreationDialog> createState() => _QuickProductCreationDialogState();
}

class _QuickProductCreationDialogState extends State<QuickProductCreationDialog> {
  String _mode = 'search'; // 'search' or 'create'

  // --- Search Mode State ---
  Product? _selectedExistingProduct;
  final _invoiceQtyController = TextEditingController(text: '1');
  final _invoicePriceController = TextEditingController();
  final _invoiceUnitController = TextEditingController(); 

  // --- Create Mode State (Exact from ProductEntryScreen) ---
  final _formKey = GlobalKey<FormState>();
  
  // Basic
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  
  // Base Unit & Stock
  final _baseUnitNameController = TextEditingController(text: 'قطعة');
  final _stockController = TextEditingController();
  final _baseWeightController = TextEditingController();
  final _alertQtyController = TextEditingController(); // 🔔 Added
  
  // Pricing (Cost + 6 Sell Prices)
  final _baseCostController = TextEditingController();
  final _basePriceController = TextEditingController(); // Price 1
  final _price2Controller = TextEditingController();
  final _price3Controller = TextEditingController();
  final _price4Controller = TextEditingController();
  final _price5Controller = TextEditingController();
  final _price6Controller = TextEditingController();
  
  // Config
  int? _selectedCategoryId;
  List<Category> _categories = [];
  bool _isWeighable = false;
  bool _hasExpiry = false;
  DateTime? _expiryDate;
  
  // Lists
  List<String> _availableUnits = ['قطعة', 'كرتون', 'باكيت', 'طرد', 'كغم', 'متر', 'رول'];
  List<Map<String, dynamic>> _hierarchyItems = [];
  List<Map<String, dynamic>> _barcodeItems = [];
  
  // UI Expandables
  bool _showAdditionalPrices = false;
  bool _showAdditionalBarcodes = false;
  bool _showUnitHierarchy = false;

  // Invoice Entry (Context) 
  String _currentBuyUnit = 'قطعة'; 
  final _currentBuyQtyController = TextEditingController(text: '1');
  final _currentBuyCostController = TextEditingController(); // For invoice logic

  // Smart Unit Tracking (from AI Invoice)
  String? _invoiceOriginalUnit; // The unit from the invoice (e.g. لفة)
  double _invoiceOriginalCost = 0; // The cost per invoice unit (e.g. 156,000)

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadUnits();
    
    // --- Smart Import Auto-Switch ---
    if (widget.initialName != null) {
      _mode = 'create';
      _nameController.text = widget.initialName!;
      
      if (widget.initialCost != null) {
        // Assume cost is the base cost and unit price. User can edit.
        _baseCostController.text = widget.initialCost!.toString();
        // Default margin 20%? or just same? Let's same for now.
        _basePriceController.text = widget.initialCost!.toString();
        
        // Also pre-fill the "Current Invoice" buy fields
        _currentBuyCostController.text = widget.initialCost!.toString();
      }
      
      if (widget.initialUnit != null) {
        _baseUnitNameController.text = widget.initialUnit!;
        _currentBuyUnit = widget.initialUnit!;
        _invoiceOriginalUnit = widget.initialUnit!; // Track original invoice unit
      }
      
      if (widget.initialCost != null) {
        _invoiceOriginalCost = widget.initialCost!; // Track original invoice cost
      }
      
      if (widget.initialQty != null) {
        _currentBuyQtyController.text = widget.initialQty!.toString();
        _stockController.text = '0'; 
      }
    }
  }
  
  Future<void> _loadCategories() async {
    final db = DatabaseService();
    final cats = await db.getAllCategories();
    if (mounted) setState(() => _categories = cats);
  }

  Future<void> _loadUnits() async {
    final db = DatabaseService();
    final units = await db.getAllUnits();
    if (mounted && units.isNotEmpty) {
      setState(() => _availableUnits = units);
    }
  }

  // Helpers
  Widget _buildToggle(String label, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        Switch(value: value, onChanged: onChanged, activeColor: kPrimaryColor),
      ],
    );
  }
  
  double _parse(String val) => double.tryParse(val.replaceAll(',', '')) ?? 0.0;

  /// 🔍 البحث عن المنتج بالباركود أو الاسم واختياره تلقائياً
  Future<void> _searchAndSelectByBarcode(String barcode, {TextEditingController? searchController}) async {
    final clean = barcode.trim();
    if (clean.isEmpty) return;

    // 1. فحص المنتجات الممررة في الذاكرة بالباركود الأساسي
    Product? matched;
    try {
      matched = widget.existingProducts.firstWhere(
        (p) => p.barcode != null && p.barcode!.trim().toLowerCase() == clean.toLowerCase(),
      );
    } catch (_) {
      matched = null;
    }

    // 2. إذا لم يُعثر عليه في الذاكرة، نبحث في قاعدة البيانات (يشمل الباركود الأساسي والباركودات الإضافية)
    if (matched == null) {
      try {
        final db = DatabaseService();
        matched = await db.findProductByBarcode(clean);
      } catch (e) {
        debugPrint('Error finding product by barcode: $e');
      }
    }

    // 3. إذا لم يُعثر عليه بالباركود، نبحث بالاسم المطابق
    if (matched == null) {
      try {
        matched = widget.existingProducts.firstWhere(
          (p) => p.name.toLowerCase() == clean.toLowerCase() || p.name.toLowerCase().contains(clean.toLowerCase()),
        );
      } catch (_) {
        matched = null;
      }
    }

    if (matched != null) {
      // ✅ تم العثور على المنتج: اختياره وملء بياناته
      setState(() {
        _selectedExistingProduct = matched;
        _invoiceUnitController.text = matched!.unit;
        _invoicePriceController.text = (matched.costPrice ?? 0).toString();
        if (searchController != null) {
          searchController.text = matched.name;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم العثور على المنتج: ${matched.name}'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      // ❌ غير موجود: الانتقال إلى وضع إنشاء منتج جديد مع ملء الباركود تلقائياً
      setState(() {
        _mode = 'create';
        _barcodeController.text = clean;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('لم يتم العثور على منتج بهذا الباركود ($clean). يمكنك تعريفه الآن.'),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Called when the base unit changes. If different from invoice unit, auto-creates hierarchy.
  void _onBaseUnitChanged(String newUnit) {
    setState(() {
      _baseUnitNameController.text = newUnit;
      
      // Smart hierarchy: if invoice had a unit and new base is different
      if (_invoiceOriginalUnit != null && 
          _invoiceOriginalUnit!.isNotEmpty && 
          newUnit.isNotEmpty &&
          newUnit != _invoiceOriginalUnit) {
        
        // 1. Auto-open hierarchy section
        _showUnitHierarchy = true;
        
        // 2. Auto-add the invoice unit as a larger unit (if not already there)
        final alreadyExists = _hierarchyItems.any((h) => h['unit_name'] == _invoiceOriginalUnit);
        if (!alreadyExists) {
          // Default to 1 (user must edit), but ready for input
          _hierarchyItems.insert(0, {'unit_name': _invoiceOriginalUnit!, 'contains_qty': 100.0}); 
        }
        
        // 3. Set current buy unit to the invoice unit (we're buying in rolls, not meters)
        _currentBuyUnit = _invoiceOriginalUnit!;
        
        // 4. Set buy cost to original invoice cost
        if (_invoiceOriginalCost > 0) {
           _currentBuyCostController.text = _invoiceOriginalCost.toStringAsFixed(0);
        }

        // 5. Trigger calculation immediately
        _recalcPricesFromHierarchy();
      }
    });
  }

  /// Recalculate cost and sell prices from invoice cost and hierarchy conversion factor.
  void _recalcPricesFromHierarchy() {
    if (_invoiceOriginalUnit == null || _invoiceOriginalCost <= 0) return;
    if (_hierarchyItems.isEmpty) return;
    
    // Find the hierarchy item for the invoice unit (e.g. Roll)
    final invoiceHierarchy = _hierarchyItems.firstWhere(
      (h) => h['unit_name'] == _invoiceOriginalUnit,
      orElse: () => _hierarchyItems.first,
    );
    
    // Factor = How many small units in the large unit (e.g. 100 Meters in 1 Roll)
    final factor = (invoiceHierarchy['contains_qty'] as num?)?.toDouble() ?? 0;
    if (factor <= 0) return;
    
    // Cost per small unit = Invoice Cost / Factor
    // e.g. 100,000 / 100 = 1,000
    final costPerBase = _invoiceOriginalCost / factor;
    
    // Sell Price = Cost + 10%
    // e.g. 1,000 + 10% = 1,100
    final sellPerBase = costPerBase * 1.10; 
    
    setState(() {
      _baseCostController.text = costPerBase.toStringAsFixed(0);
      _basePriceController.text = sellPerBase.toStringAsFixed(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24), // Wide dialog
      child: Container(
        width: 900, // Fixed max width to simulate "shrunk" but wide enough for grid
        decoration: BoxDecoration(
          color: kBackgroundColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
             BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: Row(
                children: [
                   Container(
                     padding: const EdgeInsets.all(10),
                     decoration: BoxDecoration(color: kPrimaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                     child: Icon(_mode == 'search' ? Icons.search : Icons.inventory_2, color: kPrimaryColor),
                   ),
                   const SizedBox(width: 16),
                   Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Text(
                         _mode == 'search' ? 'بحث عن منتج' : 'إضافة منتج جديد (كامل)',
                         style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kTextColor),
                       ),
                       Text(
                         _mode == 'search' ? 'اختر منتجاً لإضافته' : 'نفس شاشة المنتجات بتصميم مصغر',
                         style: TextStyle(color: Colors.grey[500], fontSize: 12),
                       ),
                     ],
                   ),
                   const Spacer(),
                   IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            
            // Body
            Expanded(
              child: _mode == 'search' ? _buildSearchMode() : _buildCreateMode(),
            ),
          ],
        ),
      ),
    );
  }

  // ================= SEARCH MODE =================
  Widget _buildSearchMode() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Autocomplete<Product>(
            optionsBuilder: (textEditingValue) {
               final query = textEditingValue.text.trim().toLowerCase();
               if (query.isEmpty) return const Iterable<Product>.empty();
               return widget.existingProducts.where((p) {
                 final matchName = p.name.toLowerCase().contains(query);
                 final matchBarcode = p.barcode != null && p.barcode!.toLowerCase().contains(query);
                 return matchName || matchBarcode;
               });
            },
            displayStringForOption: (p) => p.name,
            onSelected: (product) {
              setState(() {
                _selectedExistingProduct = product;
                _invoiceUnitController.text = product.unit;
                _invoicePriceController.text = (product.costPrice ?? 0).toString();
              });
            },
            optionsViewBuilder: (context, onSelected, options) {
              if (options.isEmpty) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4.0,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 400,
                        color: Colors.white,
                        child: ListTile(
                          leading: const Icon(Icons.add_circle, color: Colors.green),
                          title: const Text('إضافة منتج جديد غير موجود'),
                          subtitle: const Text('اضغط هنا لتعريف المنتج فوراً'),
                          onTap: () {
                            setState(() {
                              _mode = 'create';
                            });
                          },
                        ),
                      ),
                    ),
                  );
              }
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4.0,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 400,
                    color: Colors.white,
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: options.length,
                      itemBuilder: (BuildContext context, int index) {
                        final Product option = options.elementAt(index);
                        return ListTile(
                          leading: const Icon(Icons.inventory_2_outlined, color: kPrimaryColor),
                          title: Text(option.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            '${option.unit} - التكلفة: ${option.costPrice ?? option.price1}${option.barcode != null && option.barcode!.isNotEmpty ? " | باركود: ${option.barcode}" : ""}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                return TextField(
                 controller: controller,
                 focusNode: focusNode,
                 autofocus: true,
                 onSubmitted: (val) async {
                   onFieldSubmitted();
                   if (val.trim().isNotEmpty) {
                     await _searchAndSelectByBarcode(val, searchController: controller);
                   }
                 },
                 onChanged: (val) {
                    _nameController.text = val; 
                 },
                 decoration: InputDecoration(
                   labelText: 'ابحث عن اسم المنتج أو امسح الباركود...',
                   prefixIcon: const Icon(Icons.search, color: kPrimaryColor),
                   border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                   filled: true,
                   fillColor: Colors.white,
                   suffixIcon: Row(
                     mainAxisSize: MainAxisSize.min,
                     children: [
                       // 📷 زر مسح الباركود بالكاميرا (للهواتف والأجهزة اللوحية)
                       Container(
                         margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                         decoration: BoxDecoration(
                           color: kPrimaryColor.withOpacity(0.1),
                           borderRadius: BorderRadius.circular(12),
                         ),
                         child: IconButton(
                           icon: const Icon(Icons.qr_code_scanner, color: kPrimaryColor),
                           tooltip: 'مسح الباركود بالكاميرا',
                           onPressed: () async {
                             final scanned = await CameraBarcodeScannerDialog.scan(context);
                             if (scanned != null && scanned.trim().isNotEmpty) {
                               await _searchAndSelectByBarcode(scanned, searchController: controller);
                             }
                           },
                         ),
                       ),
                       // ➕ زر إنشاء منتج جديد
                       Container(
                         margin: const EdgeInsets.only(left: 6, right: 2, top: 4, bottom: 4),
                         decoration: BoxDecoration(
                           color: Colors.green.withOpacity(0.1),
                           borderRadius: BorderRadius.circular(12),
                         ),
                         child: IconButton(
                            icon: const Icon(Icons.add, color: Colors.green),
                            tooltip: 'منتج جديد',
                            onPressed: () => setState(() {
                              _mode = 'create';
                              _nameController.text = controller.text;
                            }),
                         ),
                       ),
                     ],
                   ),
                 ),
               );
            },
          ),
          const Spacer(),
          if (_selectedExistingProduct != null) ...[
             // بناء قائمة الوحدات المتاحة
             Builder(builder: (context) {
               final product = _selectedExistingProduct!;
               final baseUnit = product.unit == 'piece' ? 'قطعة' : 
                               (product.unit == 'meter' ? 'متر' : product.unit);
               
               // بناء قائمة الوحدات مع معاملات التحويل
               List<Map<String, dynamic>> unitOptions = [
                 {'name': baseUnit, 'factor': 1.0}
               ];
               
               final hierarchy = product.getUnitHierarchyList();
               double cumulativeFactor = 1.0;
               for (var level in hierarchy) {
                 final unitName = level['unit_name']?.toString() ?? '';
                 final qty = (level['quantity'] as num?)?.toDouble() ?? 1.0;
                 if (unitName.isNotEmpty) {
                   cumulativeFactor *= qty;
                   unitOptions.add({'name': unitName, 'factor': cumulativeFactor});
                 }
               }
               
               // إذا لم تكن الوحدة المختارة في القائمة، اختر الأولى
               if (!unitOptions.any((o) => o['name'] == _invoiceUnitController.text)) {
                 _invoiceUnitController.text = baseUnit;
               }
               
               // حساب معامل التحويل الحالي وسعر الوحدة الأساسية
               final currentUnitData = unitOptions.firstWhere(
                 (o) => o['name'] == _invoiceUnitController.text,
                 orElse: () => unitOptions.first,
               );
               final double currentFactor = currentUnitData['factor'];
               final double invoicePrice = _parse(_invoicePriceController.text);
               final double baseCostFromInvoice = currentFactor > 0 ? invoicePrice / currentFactor : 0;
               
               return ModernSectionCard(
                 number: '✓', 
                 title: 'إضافة للفاتورة', 
                 subtitle: 'حدد الوحدة والكمية والسعر',
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     Row(
                       children: [
                         // الكمية
                         Expanded(
                           child: ModernTextField(
                             controller: _invoiceQtyController, 
                             label: 'الكمية', 
                             keyboardType: TextInputType.number,
                           ),
                         ),
                         const SizedBox(width: 12),
                         // اختيار الوحدة (Dropdown)
                         Expanded(
                           flex: 2,
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               const Text('الوحدة', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                               const SizedBox(height: 8),
                               Container(
                                 padding: const EdgeInsets.symmetric(horizontal: 12),
                                 decoration: BoxDecoration(
                                   color: kInputFillColor,
                                   borderRadius: BorderRadius.circular(12),
                                 ),
                                 child: DropdownButtonHideUnderline(
                                   child: DropdownButton<String>(
                                     value: _invoiceUnitController.text,
                                     isExpanded: true,
                                     items: unitOptions.map((u) {
                                       final factor = u['factor'] as double;
                                       return DropdownMenuItem<String>(
                                         value: u['name'],
                                         child: Row(
                                           children: [
                                             Text(u['name']),
                                             if (factor > 1) ...[
                                               const SizedBox(width: 8),
                                               Container(
                                                 padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                 decoration: BoxDecoration(
                                                   color: Colors.blue.withOpacity(0.1),
                                                   borderRadius: BorderRadius.circular(4),
                                                 ),
                                                 child: Text(
                                                   '= ${factor.toInt()} $baseUnit',
                                                   style: const TextStyle(fontSize: 10, color: Colors.blue),
                                                 ),
                                               ),
                                             ],
                                           ],
                                         ),
                                       );
                                     }).toList(),
                                     onChanged: (val) {
                                       setState(() {
                                         _invoiceUnitController.text = val ?? baseUnit;
                                       });
                                     },
                                   ),
                                 ),
                               ),
                             ],
                           ),
                         ),
                         const SizedBox(width: 12),
                         // سعر الشراء
                         Expanded(
                           child: ModernTextField(
                             controller: _invoicePriceController, 
                             label: 'سعر الشراء', 
                             keyboardType: TextInputType.number,
                             onChanged: (_) => setState(() {}), // لتحديث حساب التكلفة
                           ),
                         ),
                       ],
                     ),
                     // عرض سعر الوحدة الأساسية المحسوب
                     if (currentFactor > 1 && invoicePrice > 0) ...[
                       const SizedBox(height: 12),
                       Container(
                         padding: const EdgeInsets.all(12),
                         decoration: BoxDecoration(
                           color: Colors.green.withOpacity(0.1),
                           borderRadius: BorderRadius.circular(8),
                           border: Border.all(color: Colors.green.withOpacity(0.3)),
                         ),
                         child: Row(
                           children: [
                             const Icon(Icons.calculate, color: Colors.green, size: 20),
                             const SizedBox(width: 8),
                             Text(
                               'سعر الـ$baseUnit = ${NumberFormat('#,##0.##').format(baseCostFromInvoice)}',
                               style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                             ),
                             const Spacer(),
                             Text(
                               '(${_invoicePriceController.text} ÷ ${currentFactor.toInt()})',
                               style: TextStyle(color: Colors.grey[600], fontSize: 12),
                             ),
                           ],
                         ),
                       ),
                     ],
                   ],
                 ),
               );
             }),
             const SizedBox(height: 16),
             SizedBox(
               width: double.infinity,
               height: 50,
               child: ElevatedButton(
                 style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                 onPressed: () {
                    double q = _parse(_invoiceQtyController.text);
                    double p = _parse(_invoicePriceController.text);
                    widget.onProductSelected(_selectedExistingProduct!, q, p, _invoiceUnitController.text);
                    Navigator.pop(context);
                 },
                 child: const Text('إضافة', style: TextStyle(color: Colors.white, fontSize: 16)),
               ),
             ),
          ] else ...[
             const Text('اختر منتجاً أو اضغط "جديد"', style: TextStyle(color: Colors.grey)),
             const Spacer(),
          ],
        ],
      ),
    );
  }

  // ================= CREATE MODE (Exact Clone from ProductEntryScreen) =================
  Widget _buildCreateMode() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
             Row(children: [TextButton.icon(onPressed: () => setState(() => _mode = 'search'), icon: const Icon(Icons.arrow_back), label: const Text('رجوع'))]),
             const SizedBox(height: 12),

             // Section 01: Info
             ModernSectionCard(
               number: '01',
               title: 'تعريف المنتج الأساسي',
               subtitle: 'الاسم، النوع، وطبيعة المنتج',
               child: Column(
                 children: [
                   Row(
                     children: [
                       Expanded(
                         flex: 2,
                         child: ModernTextField(controller: _nameController, label: 'اسم المنتج', hint: 'مثال: دجاج تركي...', isRequired: true),
                       ),
                       const SizedBox(width: 16),
                       Expanded(
                         flex: 1,
                         child: ModernDropdownField<int>(
                           label: 'القسم',
                           value: _selectedCategoryId,
                           items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                           onChanged: (val) => setState(() => _selectedCategoryId = val),
                           hint: 'اختر...',
                         ),
                       ),
                     ],
                   ),
                   const SizedBox(height: 20),
                   Container(
                     padding: const EdgeInsets.all(16),
                     decoration: BoxDecoration(color: kInputFillColor, borderRadius: BorderRadius.circular(12)),
                     child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                           _buildToggle('يباع بالوزن؟', _isWeighable, (v) => setState(() => _isWeighable = v)),
                           Container(width: 1, height: 40, color: Colors.grey[300]),
                           _buildToggle('له تاريخ صلاحية؟', _hasExpiry, (v) => setState(() => _hasExpiry = v)),
                        ],
                     ),
                   ),
                   if (_hasExpiry) ...[
                     const SizedBox(height: 12),
                     InkWell(
                       onTap: () async {
                         final picked = await showDatePicker(
                           context: context,
                           initialDate: _expiryDate ?? DateTime.now(),
                           firstDate: DateTime.now(),
                           lastDate: DateTime(2050),
                         );
                         if (picked != null) setState(() => _expiryDate = picked);
                       },
                       child: Container(
                         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                         decoration: BoxDecoration(
                           color: kInputFillColor,
                           borderRadius: BorderRadius.circular(12),
                           border: Border.all(color: _expiryDate == null ? Colors.red.withOpacity(0.3) : Colors.transparent),
                         ),
                         child: Row(
                           children: [
                             const Icon(Icons.event_note, color: kPrimaryColor),
                             const SizedBox(width: 12),
                             Text(
                               _expiryDate == null ? 'اختر تاريخ الصلاحية' : DateFormat('yyyy-MM-dd').format(_expiryDate!),
                               style: TextStyle(color: _expiryDate == null ? Colors.grey : kTextColor),
                             ),
                           ],
                         ),
                       ),
                     ),
                   ],
                 ],
               ),
             ),

             // Section 02: Stock & Prices
             ModernSectionCard(
                number: '02',
                title: 'الأسعار والمخزون',
                subtitle: 'الوحدة والأسعار الأساسية',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               const Text('الوحدة الأساسية *', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                               const SizedBox(height: 8),
                               Container(
                                 decoration: BoxDecoration(color: kInputFillColor, borderRadius: BorderRadius.circular(12)),
                                 child: Autocomplete<String>(
                                    initialValue: TextEditingValue(text: _baseUnitNameController.text),
                                    optionsBuilder: (v) => _availableUnits.where((u) => u.contains(v.text)),
                                    onSelected: (s) => _onBaseUnitChanged(s),
                                    fieldViewBuilder: (ctx, ctrl, focus, submit) {
                                       // Remove listener, use onChanged with setState directly
                                       return TextField(
                                         controller: ctrl, 
                                         focusNode: focus, 
                                         onChanged: (v) => _onBaseUnitChanged(v),
                                         decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(12), hintText: 'قطعة')
                                       );
                                    },
                                 ),
                               ),
                             ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: ModernTextField(controller: _stockController, label: 'الرصيد الافتتاحي', hint: '0', inputFormatters: [ThousandSeparatorDecimalInputFormatter()])),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: ModernTextField(controller: _baseCostController, label: 'سعر التكلفة', hint: '0.0', inputFormatters: [ThousandSeparatorDecimalInputFormatter()])),
                        const SizedBox(width: 12),
                        Expanded(child: ModernTextField(controller: _basePriceController, label: 'سعر البيع (مفرد) *', hint: '0.0', isRequired: true, inputFormatters: [ThousandSeparatorDecimalInputFormatter()])),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 🔔 حقول التنبيه (Low Stock)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: ModernTextField(
                              controller: _alertQtyController,
                              label: 'تنبيه النفاد عند',
                              hint: 'أدخل الكمية',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ModernTextField(
                      controller: _barcodeController,
                      label: 'الباركود الأساسي',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code_scanner, color: kPrimaryColor),
                        tooltip: 'مسح الباركود بالكاميرا',
                        onPressed: () async {
                          final scanned = await CameraBarcodeScannerDialog.scan(context);
                          if (scanned != null && scanned.trim().isNotEmpty) {
                            setState(() {
                              _barcodeController.text = scanned.trim();
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
             ),

             // Expandable 1: Additional Prices
             _buildExpandableSection(
               title: 'أسعار إضافية',
               subtitle: 'جملة، نصف جملة...',
               isExpanded: _showAdditionalPrices,
               onToggle: () => setState(() => _showAdditionalPrices = !_showAdditionalPrices),
               icon: Icons.price_change_outlined,
               child: Column(
                 children: [
                   Row(
                     children: [
                       Expanded(child: ModernTextField(controller: _price2Controller, label: 'سعر مفرد 2', inputFormatters: [ThousandSeparatorDecimalInputFormatter()])),
                       const SizedBox(width: 12),
                       Expanded(child: ModernTextField(controller: _price3Controller, label: 'سعر منزل', inputFormatters: [ThousandSeparatorDecimalInputFormatter()])),
                     ],
                   ),
                   const SizedBox(height: 12),
                   Row(
                     children: [
                       Expanded(child: ModernTextField(controller: _price4Controller, label: 'سعر جملة', inputFormatters: [ThousandSeparatorDecimalInputFormatter()])),
                       const SizedBox(width: 12),
                       Expanded(child: ModernTextField(controller: _price5Controller, label: 'سعر جملة 2', inputFormatters: [ThousandSeparatorDecimalInputFormatter()])),
                     ],
                   ),
                   const SizedBox(height: 12),
                   ModernTextField(controller: _price6Controller, label: 'سعر أخرى', inputFormatters: [ThousandSeparatorDecimalInputFormatter()]),
                 ],
               ),
             ),
             
             // Expandable 2: Multiple Barcodes
             _buildExpandableSection(
               title: 'باركودات إضافية',
               subtitle: 'للنكهات والألوان المختلفة',
               isExpanded: _showAdditionalBarcodes,
               onToggle: () => setState(() => _showAdditionalBarcodes = !_showAdditionalBarcodes),
               icon: Icons.qr_code_2_outlined,
               child: Column(
                 children: [
                   for (int i = 0; i < _barcodeItems.length; i++)
                     Container(
                       margin: const EdgeInsets.only(bottom: 12),
                       padding: const EdgeInsets.all(12),
                       decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
                       child: Row(
                         children: [
                           Expanded(flex: 2, child: TextField(
                             decoration: InputDecoration(labelText: 'باركود', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.all(12)),
                             onChanged: (v) => _barcodeItems[i]['barcode'] = v,
                           )),
                           const SizedBox(width: 8),
                           Expanded(flex: 2, child: TextField(
                             decoration: InputDecoration(labelText: 'وصف', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.all(12)),
                             onChanged: (v) => _barcodeItems[i]['variant_label'] = v,
                           )),
                           IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => _barcodeItems.removeAt(i))),
                         ],
                       ),
                     ),
                   TextButton.icon(
                     onPressed: () => setState(() => _barcodeItems.add({'barcode': '', 'variant_label': '', 'cost_price': null, 'sell_price': null})),
                     icon: const Icon(Icons.add),
                     label: const Text('إضافة باركود جديد'),
                   ),
                 ],
               ),
             ),

             // Expandable 3: Hierarchy
             _buildExpandableSection(
               title: 'وحدات كبرى (تعبئة)',
               subtitle: 'كرتون، صندوق، درزن...',
               isExpanded: _showUnitHierarchy,
               onToggle: () => setState(() => _showUnitHierarchy = !_showUnitHierarchy),
               icon: Icons.account_tree_outlined,
               child: Column(
                 children: [
                   for (int i=0; i<_hierarchyItems.length; i++)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                           children: [
                             Expanded(flex: 2, child: Autocomplete<String>(
                               initialValue: TextEditingValue(text: _hierarchyItems[i]['unit_name'] ?? ''),
                               optionsBuilder: (v) => _availableUnits.where((u) => u.contains(v.text)),
                               onSelected: (s) => setState(() => _hierarchyItems[i]['unit_name'] = s),
                               fieldViewBuilder: (ctx, ctrl, f, s) => TextField(
                                 controller: ctrl, 
                                 focusNode: f, 
                                 onChanged: (v) => setState(() => _hierarchyItems[i]['unit_name'] = v), 
                                 decoration: const InputDecoration(labelText: 'الوحدة', border: OutlineInputBorder(), contentPadding: EdgeInsets.all(12))
                               ),
                             )),
                             const SizedBox(width: 8),
                             Expanded(child: TextField(
                               keyboardType: TextInputType.number,
                               decoration: const InputDecoration(labelText: 'تحتوي', border: OutlineInputBorder(), contentPadding: EdgeInsets.all(12)),
                               onChanged: (v) { setState(() { _hierarchyItems[i]['contains_qty'] = double.tryParse(v) ?? 1; _recalcPricesFromHierarchy(); }); },
                             )),
                             IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => _hierarchyItems.removeAt(i))),
                           ],
                        ),
                      ),
                   TextButton.icon(
                     onPressed: () => setState(() => _hierarchyItems.add({'unit_name': '', 'contains_qty': 12.0})),
                     icon: const Icon(Icons.add_link),
                     label: const Text('إضافة مستوى جديد'),
                   ),
                    // Visual feedback for auto-calculation

                    if (_invoiceOriginalUnit != null && _invoiceOriginalCost > 0 && _hierarchyItems.isNotEmpty) ...[

                      const SizedBox(height: 12),

                      Builder(builder: (_) {

                        final factor = (_hierarchyItems.first['contains_qty'] as num?)?.toDouble() ?? 0;

                        if (factor <= 0) return const SizedBox.shrink();

                        final costPerBase = _invoiceOriginalCost / factor;

                        final sellPerBase = costPerBase * 1.10;

                        return Container(

                          padding: const EdgeInsets.all(12),

                          decoration: BoxDecoration(

                            color: Colors.blue.withOpacity(0.08),

                            borderRadius: BorderRadius.circular(10),

                            border: Border.all(color: Colors.blue.withOpacity(0.3)),

                          ),

                          child: Column(

                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [

                              Row(

                                children: [

                                  const Icon(Icons.calculate, color: Colors.blue, size: 20),

                                  const SizedBox(width: 8),

                                  Expanded(

                                    child: Text(

                                      'سعر الـ${_baseUnitNameController.text} = سعر الـ${_hierarchyItems.first['unit_name']} (${NumberFormat('#,##0').format(_invoiceOriginalCost)}) ÷ $factor',
                                      style: const TextStyle(fontSize: 12, color: Colors.blue),
                                    ),

                                  ),

                                ],

                              ),

                              const SizedBox(height: 6),

                              Row(

                                children: [

                                  const SizedBox(width: 28),

                                  Expanded(

                                    child: Text(

                                      '= سعر التكلفة: ${NumberFormat('#,##0').format(_invoiceOriginalCost / factor)}  |  سعر البيع: ${NumberFormat('#,##0').format((_invoiceOriginalCost / factor) * 1.10)} (+10%)',

                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green),

                                    ),

                                  ),

                                ],

                              ),

                            ],

                          ),

                        );

                      }),

                    ],

                 ],
               ),
             ),
             
             const SizedBox(height: 24),
             
             // --- INVOICE INTEGRATION SECTION ---
             Container(
               padding: const EdgeInsets.all(16),
               decoration: BoxDecoration(color: Colors.green.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green.withOpacity(0.3))),
               child: Column(
                 children: [
                    const Text('شراء هذا المنتج الآن (إضافة للفاتورة)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: DropdownButtonFormField<String>(
                           value: ([_baseUnitNameController.text, ..._hierarchyItems.map((e) => e['unit_name'].toString())].contains(_currentBuyUnit)) ? _currentBuyUnit : _baseUnitNameController.text,
                           items: [_baseUnitNameController.text, ..._hierarchyItems.map((e) => e['unit_name'].toString())].toSet()
                               .map((u) => DropdownMenuItem(value: u, child: Text(u.isEmpty ? '?' : u))).toList(),
                           onChanged: (v) => setState(() => _currentBuyUnit = v!),
                           decoration: const InputDecoration(labelText: 'الوحدة المشتراة', border: OutlineInputBorder()),
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: ModernTextField(controller: _currentBuyQtyController, label: 'الكمية', keyboardType: TextInputType.number)),
                        const SizedBox(width: 12),
                        Expanded(child: ModernTextField(controller: _currentBuyCostController, label: 'سعر الشراء', hint: 'سعر الوحدة المختارة')),
                      ],
                    ),
                 ],
               ),
             ),

             const SizedBox(height: 24),
             SizedBox(
               width: double.infinity,
               height: 55,
               child: ElevatedButton(
                 style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                 onPressed: _submitProductAndAddToInvoice,
                 child: const Text('حفظ المنتج وإضافته', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
               ),
             ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandableSection({required String title, String? subtitle, required bool isExpanded, required VoidCallback onToggle, IconData? icon, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: isExpanded ? kPrimaryColor : Colors.transparent), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(children: [
        ListTile(
          leading: Icon(icon ?? Icons.list, color: isExpanded ? kPrimaryColor : Colors.grey),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isExpanded ? kPrimaryColor : Colors.black)),
          subtitle: subtitle!=null ? Text(subtitle) : null,
          trailing: Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
          onTap: onToggle,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        if (isExpanded) Padding(padding: const EdgeInsets.all(16), child: child),
      ]),
    );
  }

  void _submitProductAndAddToInvoice() async {
    if (!_formKey.currentState!.validate()) return;
    
    final db = DatabaseService();
    
    // 1. Calculate Costs logic (Same as original screen)
    double baseCost = _parse(_baseCostController.text);
    double buyUnitCost = _parse(_currentBuyCostController.text);
    
    // If user entered Buy Unit Cost but not Base Cost, reverse calculate
    // Need hierarchy factor...
    // Simplified for dialog: Just trust inputs or basic calculation.
    // If Base Cost is empty but Buy Cost is set, try to calc.
    if (baseCost == 0 && buyUnitCost > 0) {
       // Find conversion factor for current buy unit
       double output = 1.0;
       String current = _currentBuyUnit;
       if (current != _baseUnitNameController.text) {
          // Check hierarchy
          for(var h in _hierarchyItems) {
             if (h['unit_name'] == current) {
                output = (h['contains_qty'] as num).toDouble();
                break;
             }
          }
       }
       baseCost = buyUnitCost / output;
    }

    try {
       // 2. Prepare Hierarchy JSON
       List<Map<String, dynamic>> finalHierarchy = [];
       // Simple chain assumption for dialog (or user defined)
       String prev = _baseUnitNameController.text;
       for (var item in _hierarchyItems) {
         finalHierarchy.add({
           'unit_name': item['unit_name'], // Note: DB expects 'unit', 'factor', 'parent' mostly, OR specific JSON structure.
           // Checking ProductEntryScreen: It saves: {'unit_name': uName, 'quantity': qty}
           // Let's stick to ProductEntryScreen implementation
           'unit_name': item['unit_name'],
           'quantity': (item['contains_qty'] as num).toDouble()
         });
       }

       // 3. Create Product Object
       final product = Product(
         name: _nameController.text,
         unit: (_baseUnitNameController.text.trim() == 'قطعة' ? 'piece' : (_baseUnitNameController.text.trim() == 'متر' ? 'meter' : _baseUnitNameController.text.trim())),
         barcode: _barcodeController.text.isEmpty ? null : _barcodeController.text,
         categoryId: _selectedCategoryId,
         isWeighable: _isWeighable,
         hasExpiry: _hasExpiry,
         expiryDate: _expiryDate,
         costPrice: baseCost,
         unitPrice: _parse(_basePriceController.text),
         price1: _parse(_basePriceController.text),
         price2: _parse(_price2Controller.text),
         price3: _parse(_price3Controller.text),
         price4: _parse(_price4Controller.text),
         price5: _parse(_price5Controller.text),
         price6: _parse(_price6Controller.text),
         unitHierarchy: jsonEncode(finalHierarchy),
         alertQuantity: _parse(_invoiceQtyController.text) == 0 ? null : _parse(_invoiceQtyController.text), // Corrected to use available controller
         alertUnit: _baseUnitNameController.text,
         stockQuantity: _parse(_stockController.text),
         createdAt: DateTime.now(),
         lastModifiedAt: DateTime.now(),
       );

       // 4. Insert to DB
       final id = await db.insertProduct(product);
       
       // 5. Insert Extra Barcodes
       for(var b in _barcodeItems) {
          if (b['barcode']?.isNotEmpty == true) {
             await db.addProductBarcode(productId: id, barcode: b['barcode'], variantLabel: b['variant_label'], sellPrice: null, costPrice: null); // Assuming null prices for variants in simplified dialog
          }
       }
       
       // 6. Return to screen
       final savedProduct = product.copyWith(id: id);
       widget.onProductSelected(savedProduct, _parse(_currentBuyQtyController.text), buyUnitCost > 0 ? buyUnitCost : baseCost, _currentBuyUnit);
       Navigator.pop(context);
       
    } catch (e) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }
}
