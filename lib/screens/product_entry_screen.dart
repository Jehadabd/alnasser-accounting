// screens/product_entry_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

import '../models/product.dart';
import '../widgets/camera_barcode_scanner_dialog.dart';
import '../models/category.dart';
import '../services/database_service.dart';
import '../widgets/formatters.dart';
import '../widgets/product/category_management_dialog.dart';

// --- Theme Colors from Design ---
const Color kPrimaryColor = Color(0xFF5D5FEF); // Purple/Indigo
const Color kBackgroundColor = Color(0xFFF5F7FA); // Light Gray
const Color kCardColor = Colors.white;
const Color kTextColor = Color(0xFF1E1E2E);
const Color kInputFillColor = Color(0xFFF8F9FA); // Very light gray for inputs

class ProductEntryScreen extends StatefulWidget {
  static const routeName = '/product-entry';
  
  // --- Smart Import Parameters ---
  final String? initialName;
  final String? initialUnit; // الوحدة من الفاتورة
  final double? initialCost;
  final double? initialQty; // الكمية من الفاتورة

  const ProductEntryScreen({
    super.key,
    this.initialName,
    this.initialUnit,
    this.initialCost,
    this.initialQty,
  });

  @override
  State<ProductEntryScreen> createState() => _ProductEntryScreenState();
}

class _ProductEntryScreenState extends State<ProductEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // --- Basic Controllers ---
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  
  // --- Base Unit Controllers ---
  final _baseUnitNameController = TextEditingController(text: 'قطعة');
  final _baseCostController = TextEditingController();
  final _basePriceController = TextEditingController(); // price1 - مفرد
  final _baseWeightController = TextEditingController();
  
  // --- Price Controllers (6 أسعار) ---
  final _price2Controller = TextEditingController(); // مفرد 2
  final _price3Controller = TextEditingController(); // منزل
  final _price4Controller = TextEditingController(); // جملة
  final _price5Controller = TextEditingController(); // جملة 2
  final _price6Controller = TextEditingController(); // أخرى
  
  // --- Alert Controllers ---
  final _alertQtyController = TextEditingController();
  final _alertUnitController = TextEditingController();

  // --- State Variables ---
  List<Category> _categories = [];
  List<String> _availableUnits = [];
  int? _selectedCategoryId;
  bool _isWeighable = false;
  bool _hasExpiry = false;
  DateTime? _expiryDate;
  int _totalProductsCount = 0;

  // --- Stock Controller ---
  final _stockController = TextEditingController();

  // --- Hierarchy Data ---
  List<Map<String, dynamic>> _hierarchyItems = [];
  
  // --- Multi-Barcode Data ---
  List<Map<String, dynamic>> _barcodeItems = [];
  
  // --- Advanced Segmented Tab State (0: Prices, 1: Barcodes, 2: Units Hierarchy) ---
  int _selectedAdvancedTab = 0;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadProductCount();
    _loadUnits();
    
    // --- Pre-fill Data from Smart Import ---
    if (widget.initialName != null) {
      _nameController.text = widget.initialName!;
    }
    if (widget.initialCost != null) {
      _baseCostController.text = widget.initialCost!.toString();
    }
    // افتراضياً نضع وحدة الفاتورة كوحدة أساسية، والمستخدم يغيرها
    if (widget.initialUnit != null) {
      _baseUnitNameController.text = widget.initialUnit!;
      
      // Add logic to detect change: 
      // If user changes base unit from "initialUnit", we should add "initialUnit" to hierarchy
      _baseUnitNameController.addListener(_checkUnitHierarchySuggestion);
    }
    if (widget.initialQty != null) {
      _stockController.text = widget.initialQty!.toString();
    }
  }
  
  void _checkUnitHierarchySuggestion() {
    final currentBase = _baseUnitNameController.text.trim();
    final invoiceUnit = widget.initialUnit?.trim();
    
    if (invoiceUnit != null && 
        invoiceUnit.isNotEmpty && 
        currentBase.isNotEmpty && 
        currentBase != invoiceUnit) {
          
      // Check if already in hierarchy
      bool exists = _hierarchyItems.any((item) => item['unit_name'] == invoiceUnit);
      if (!exists) {
        setState(() {
          _selectedAdvancedTab = 2;
          _hierarchyItems.add({
            'unit_name': invoiceUnit,
            'contains_qty': 0.0, // User must fill this
          });
          
          // Show snackbar instruction
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم إضافة وحدة "$invoiceUnit" للقائمة لأنك غيرت الوحدة الأساسية. يرجى تحديد الكمية بداخلها.'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 5),
            ),
          );
        });
      }
    }
  }

  Future<void> _loadUnits() async {
    final db = DatabaseService();
    final units = await db.getAllUnits();
    if (mounted) {
      setState(() => _availableUnits = units);
    }
  }

  /// الحصول على الوحدات المتاحة للهرمية (بدون المستخدمة)
  List<String> _getAvailableUnitsForHierarchy(int currentIndex) {
    Set<String> usedUnits = {_baseUnitNameController.text.trim()};
    for (int i = 0; i < currentIndex; i++) {
      final name = _hierarchyItems[i]['unit_name']?.toString() ?? '';
      if (name.isNotEmpty) usedUnits.add(name);
    }
    return _availableUnits.where((u) => !usedUnits.contains(u)).toList();
  }

  Future<void> _loadCategories() async {
    final db = DatabaseService();
    final cats = await db.getAllCategories();
    if (mounted) {
      setState(() => _categories = cats);
    }
  }

  Future<void> _loadProductCount() async {
    final db = DatabaseService();
    final products = await db.getAllProducts();
    if (mounted) {
      setState(() => _totalProductsCount = products.length);
    }
  }

  void _addNewCategory() {
    showDialog(
      context: context,
      builder: (context) => const CategoryManagementDialog(),
    ).then((result) {
      if (result == true) {
        _loadCategories();
      }
    });
  }

  Widget _buildToggle(String label, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: kPrimaryColor,
        ),
      ],
    );
  }

  /// بناء زر كبسولي تفاعلي لشريط التبويبات المدمج
  Widget _buildAdvancedTabButton({
    required int index,
    required String title,
    required IconData icon,
    required Color activeColor,
    int badgeCount = 0,
  }) {
    final isSelected = _selectedAdvancedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedAdvancedTab = index;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? activeColor : Colors.grey[600],
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? activeColor : Colors.grey[700],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badgeCount > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? activeColor : Colors.grey[400],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// بناء بطاقة سعر إضافي بتصميم عصري
  Widget _buildPriceFieldCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required TextEditingController controller,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: kInputFillColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.withOpacity(0.15)),
            ),
            child: TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                hintText: '0.0',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                isDense: true,
                suffixText: 'د.ع',
                suffixStyle: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// بناء عقدة هرمية للوحدات الكبرى بتصميم حديث وسهل
  Widget _buildHierarchyNode({
    required int index,
  }) {
    final item = _hierarchyItems[index];
    final qtyController = TextEditingController(
      text: (item['contains_qty'] != null && item['contains_qty'] > 0)
          ? (item['contains_qty'] % 1 == 0 ? item['contains_qty'].toInt().toString() : item['contains_qty'].toString())
          : '',
    );
    final availableUnits = _getAvailableUnitsForHierarchy(index);
    final currentUnitName = item['unit_name']?.toString().trim() ?? '';
    final baseName = _baseUnitNameController.text.trim().isEmpty ? 'قطعة' : _baseUnitNameController.text.trim();
    final prevUnitName = index == 0
        ? baseName
        : (_hierarchyItems[index - 1]['unit_name']?.toString().trim().isNotEmpty == true
            ? _hierarchyItems[index - 1]['unit_name'].toString().trim()
            : 'الوحدة السابقة');
    final qty = (item['contains_qty'] as num?)?.toDouble() ?? 0;

    final List<String> quickUnitSuggestions = [
      'كرتون',
      'باكيت',
      'درزن',
      'صندوق',
      'طرد',
      'كيس',
      'شدة',
      'سيت',
      'بندل',
      'كونية',
    ];

    return Column(
      children: [
        if (index > 0) ...[
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF059669).withOpacity(0.2)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_downward_rounded, size: 14, color: Color(0xFF059669)),
                      SizedBox(width: 4),
                      Text(
                        'المستوى التالي',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF059669)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF059669).withOpacity(0.25)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF059669).withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Level chip + Title + Delete Button
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'المستوى #${index + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    currentUnitName.isNotEmpty ? 'عبوة: $currentUnitName' : 'تحديد وحدة كبرى جديدة',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kTextColor),
                  ),
                  const Spacer(),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                    tooltip: 'حذف هذا المستوى',
                    onPressed: () => setState(() => _hierarchyItems.removeAt(index)),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Visual Equation Formula
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF059669).withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calculate_outlined, color: Color(0xFF059669), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 12, color: Color(0xFF065F46)),
                          children: [
                            const TextSpan(text: 'المعادلة: 1 '),
                            TextSpan(
                              text: currentUnitName.isNotEmpty ? '[$currentUnitName]' : '[الوحدة الكبرى]',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                            ),
                            const TextSpan(text: ' = '),
                            TextSpan(
                              text: qty > 0 ? (qty % 1 == 0 ? qty.toInt().toString() : qty.toString()) : '؟',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                            ),
                            TextSpan(
                              text: ' [$prevUnitName]',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Quick suggestion chips
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('اختيار سريع للوحدة:', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: quickUnitSuggestions.map((unit) {
                        final isSelected = currentUnitName == unit;
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _hierarchyItems[index]['unit_name'] = unit;
                              });
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF059669) : const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF059669) : Colors.grey.withOpacity(0.2),
                                ),
                              ),
                              child: Text(
                                unit,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? Colors.white : Colors.grey[800],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Form fields: Unit name + Multiplier Qty
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Unit Name
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('اسم الوحدة الكبرى', style: TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 11)),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: kInputFillColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.withOpacity(0.15)),
                          ),
                          child: Autocomplete<String>(
                            initialValue: TextEditingValue(text: currentUnitName),
                            optionsBuilder: (textEditingValue) {
                              if (textEditingValue.text.isEmpty) return availableUnits;
                              return availableUnits.where((u) => u.contains(textEditingValue.text));
                            },
                            onSelected: (selection) {
                              setState(() => _hierarchyItems[index]['unit_name'] = selection);
                            },
                            fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                              if (controller.text != currentUnitName && currentUnitName.isNotEmpty) {
                                controller.text = currentUnitName;
                              }
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  hintText: 'مثال: كرتون...',
                                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                                  isDense: true,
                                ),
                                onChanged: (v) => _hierarchyItems[index]['unit_name'] = v,
                              );
                            },
                            optionsViewBuilder: (context, onSelected, options) {
                              return Align(
                                alignment: Alignment.topRight,
                                child: Material(
                                  elevation: 4,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    constraints: const BoxConstraints(maxHeight: 200, maxWidth: 200),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (context, i) {
                                        final opt = options.elementAt(i);
                                        return ListTile(
                                          dense: true,
                                          title: Text(opt),
                                          onTap: () => onSelected(opt),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Multiplier Qty
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'كم $prevUnitName بداخلها؟',
                          style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: kInputFillColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.withOpacity(0.15)),
                          ),
                          child: TextField(
                            controller: qtyController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              hintText: 'مثال: 12',
                              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                              isDense: true,
                            ),
                            onChanged: (v) {
                              setState(() {
                                _hierarchyItems[index]['contains_qty'] = double.tryParse(v.replaceAll(',', '')) ?? 0;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  double _parse(String val) {
    if (val.isEmpty) return 0.0;
    return double.tryParse(val.replaceAll(',', '')) ?? 0.0;
  }

  /// بناء صف باركود إضافي بتصميم عصري مريح
  Widget _buildBarcodeRow(int index) {
    final item = _barcodeItems[index];
    final barcodeController = TextEditingController(text: item['barcode'] ?? '');
    final labelController = TextEditingController(text: item['variant_label'] ?? '');
    final priceController = TextEditingController(
      text: item['sell_price'] != null ? (item['sell_price'] % 1 == 0 ? (item['sell_price'] as double).toInt().toString() : item['sell_price'].toString()) : '',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEA580C).withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEA580C).withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Badge + Label preview + Delete
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEA580C).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'باركود #${index + 1}',
                  style: const TextStyle(
                    color: Color(0xFFEA580C),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if ((item['variant_label']?.toString().isNotEmpty ?? false))
                Expanded(
                  child: Text(
                    item['variant_label'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: kTextColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                tooltip: 'حذف هذا الباركود',
                onPressed: () => setState(() => _barcodeItems.removeAt(index)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Inputs Row 1: Barcode (with Camera) + Description (Flavor/Color)
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الباركود', style: TextStyle(color: Color(0xFFEA580C), fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: kInputFillColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.withOpacity(0.15)),
                      ),
                      child: TextField(
                        controller: barcodeController,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          hintText: 'امسح أو اكتب الباركود...',
                          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                          isDense: true,
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.camera_alt_rounded, color: Color(0xFFEA580C), size: 18),
                            tooltip: 'مسح بالكاميرا',
                            onPressed: () async {
                              final code = await CameraBarcodeScannerDialog.scan(context);
                              if (code != null && code.isNotEmpty) {
                                setState(() {
                                  _barcodeItems[index]['barcode'] = code;
                                });
                              }
                            },
                          ),
                        ),
                        onChanged: (v) => _barcodeItems[index]['barcode'] = v,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الوصف / النكهة / اللون', style: TextStyle(color: Color(0xFFEA580C), fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: kInputFillColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.withOpacity(0.15)),
                      ),
                      child: TextField(
                        controller: labelController,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          hintText: 'مثال: فراولة، أسود...',
                          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                          isDense: true,
                        ),
                        onChanged: (v) => _barcodeItems[index]['variant_label'] = v,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Price override (optional)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('سعر خاص لهذا المتغير', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 11)),
                  const SizedBox(width: 4),
                  Text('(اختياري - سيُعتمد سعر البيع الأساسي إذا تُرك فارغاً)', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: kInputFillColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.withOpacity(0.15)),
                ),
                child: TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    hintText: 'مثال: 15,000',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                    isDense: true,
                    suffixText: 'د.ع',
                    suffixStyle: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.bold),
                  ),
                  onChanged: (v) => _barcodeItems[index]['sell_price'] = _parse(v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// بناء محتوى التبويب المختار بنعومة وانسيابية
  Widget _buildSelectedTabContent(int extraPricesCount) {
    if (_selectedAdvancedTab == 0) {
      // Tab 0: الأسعار الإضافية
      return KeyedSubtree(
        key: const ValueKey('tab_prices'),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF4F46E5).withOpacity(0.15)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lightbulb_outline_rounded, color: Color(0xFF4F46E5), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'حدد أسعاراً خاصة لكل فئة من زبائنك لسرعة وسهولة اختيار السعر المناسب في الفاتورة.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF3730A3), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _buildPriceFieldCard(
                    title: 'سعر مفرد 2',
                    subtitle: 'سعر بديل للتجزئة',
                    icon: Icons.storefront_outlined,
                    color: const Color(0xFF4F46E5),
                    controller: _price2Controller,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildPriceFieldCard(
                    title: 'سعر منزل',
                    subtitle: 'سعر التوصيل للمنازل',
                    icon: Icons.home_outlined,
                    color: const Color(0xFFD97706),
                    controller: _price3Controller,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildPriceFieldCard(
                    title: 'سعر جملة',
                    subtitle: 'سعر المحلات والمتاجر',
                    icon: Icons.inventory_2_outlined,
                    color: const Color(0xFF059669),
                    controller: _price4Controller,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildPriceFieldCard(
                    title: 'سعر جملة 2',
                    subtitle: 'كبار العملاء / VIP',
                    icon: Icons.workspace_premium_outlined,
                    color: const Color(0xFF0284C7),
                    controller: _price5Controller,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildPriceFieldCard(
              title: 'سعر أخرى / خاص',
              subtitle: 'عروض أو تسعيرة خاصة',
              icon: Icons.stars_outlined,
              color: const Color(0xFF7C3AED),
              controller: _price6Controller,
            ),
          ],
        ),
      );
    } else if (_selectedAdvancedTab == 1) {
      // Tab 1: باركودات متعددة
      return KeyedSubtree(
        key: const ValueKey('tab_barcodes'),
        child: Column(
          children: [
            if (_barcodeItems.isEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFDBA74).withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.qr_code_scanner_rounded, size: 32, color: const Color(0xFFEA580C).withOpacity(0.8)),
                    const SizedBox(height: 8),
                    const Text(
                      'لا توجد باركودات إضافية حالياً',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF9A3412)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'أضف باركوداً لكل نكهة أو لون أو حجم إضافي لنفس المنتج لتسهيل قراءتها عند البيع.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ] else ...[
              for (int i = 0; i < _barcodeItems.length; i++)
                _buildBarcodeRow(i),
              const SizedBox(height: 6),
            ],

            InkWell(
              onTap: () {
                setState(() {
                  _barcodeItems.add({
                    'barcode': '',
                    'variant_label': '',
                    'cost_price': null,
                    'sell_price': null,
                  });
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEA580C).withOpacity(0.35), width: 1.5),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline_rounded, color: Color(0xFFEA580C), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'إضافة باركود لمتغير جديد (نكهة / لون / حجم)',
                      style: TextStyle(color: Color(0xFFEA580C), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Tab 2: تعبئة ووحدات كبرى
      return KeyedSubtree(
        key: const ValueKey('tab_hierarchy'),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF059669).withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.all_inbox_rounded, color: Color(0xFF059669), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('الوحدة الأساسية (الصغرى): ', style: TextStyle(fontSize: 12, color: Color(0xFF065F46))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _baseUnitNameController.text.trim().isEmpty ? 'قطعة' : _baseUnitNameController.text.trim(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'كل المستويات في الأسفل هي عبوات أكبر تحتوي على مضاعفات من هذه الوحدة.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_hierarchyItems.isEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF86EFAC).withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.account_tree_outlined, size: 32, color: const Color(0xFF059669).withOpacity(0.8)),
                    const SizedBox(height: 8),
                    const Text(
                      'لا توجد وحدات كبرى مضافة حالياً',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF065F46)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'إذا كان هذا المنتج يُباع بكراتين، طرود، أو بكجات، أضف مستوى تعبئة لضبط الحسابات والبيع السريع.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ] else ...[
              for (int i = 0; i < _hierarchyItems.length; i++)
                _buildHierarchyNode(
                  index: i,
                ),
              const SizedBox(height: 6),
            ],

            InkWell(
              onTap: () {
                setState(() {
                  _hierarchyItems.add({
                    'unit_name': '',
                    'contains_qty': 10.0,
                    'price': 0.0,
                    'barcode': ''
                  });
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF059669).withOpacity(0.35), width: 1.5),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline_rounded, color: Color(0xFF059669), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'إضافة مستوى تعبئة جديد (مثال: كرتون / باكيت)',
                      style: TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال اسم المنتج'), backgroundColor: Colors.red),
      );
      return;
    }

    final db = DatabaseService();

    // Build hierarchy JSON
    List<Map<String, dynamic>> finalHierarchy = [];
    Map<String, double> unitCosts = {};
    double baseCost = _parse(_baseCostController.text);
    // 🔧 Fix: Map standard Arabic names to internal keys for DB compatibility
    String rawUnit = _baseUnitNameController.text.trim();
    String baseKey = rawUnit.isEmpty ? 'piece' : (rawUnit == 'قطعة' ? 'piece' : (rawUnit == 'متر' ? 'meter' : rawUnit));
    unitCosts[baseKey] = baseCost;

    for (var item in _hierarchyItems) {
      String uName = item['unit_name'] ?? '';
      double qty = (item['contains_qty'] as num?)?.toDouble() ?? 0;
      if (uName.isEmpty || qty <= 0) continue;

      finalHierarchy.add({'unit_name': uName, 'quantity': qty});

      // Calculate cost for this unit
      int idx = _hierarchyItems.indexOf(item);
      String prevUnitName = idx == 0 ? baseKey : (_hierarchyItems[idx - 1]['unit_name'] ?? baseKey);
      double prevCost = unitCosts[prevUnitName] ?? baseCost;
      unitCosts[uName] = prevCost * qty;
    }

    String? unitHierarchyJson = finalHierarchy.isNotEmpty ? json.encode(finalHierarchy) : null;
    String? unitCostsJson = unitCosts.isNotEmpty ? json.encode(unitCosts) : null;

    // 🔍 تشخيص تحويل الوحدات — ماذا يُحفظ فعلاً للمنتج الموزون؟
    print('🔍 [تشخيص-حفظ-منتج] "${_nameController.text.trim()}"');
    print('    unit="$baseKey" | isWeighable=$_isWeighable | baseWeight=${_isWeighable ? _parse(_baseWeightController.text) : null}');
    print('    unitHierarchy=$unitHierarchyJson');
    print('    unitCosts=$unitCostsJson');
    if (finalHierarchy.isEmpty) {
      print('    ⚠️ الهرمية فارغة! لن تظهر وحدات كبرى في الفاتورة — تحقق من "تعبئة وحدات كبرى"');
    }

    final product = Product(
      name: _nameController.text.trim(),
      unit: baseKey,
      barcode: _barcodeController.text.trim().isEmpty ? null : _barcodeController.text.trim(),
      categoryId: _selectedCategoryId,
      isWeighable: _isWeighable,
      baseWeight: _isWeighable ? _parse(_baseWeightController.text) : null,
      weightUnit: _isWeighable ? 'kg' : null,
      hasExpiry: _hasExpiry,
      costPrice: baseCost,
      unitPrice: _parse(_basePriceController.text),
      price1: _parse(_basePriceController.text),
      price2: _parse(_price2Controller.text),
      price3: _parse(_price3Controller.text),
      price4: _parse(_price4Controller.text),
      price5: _parse(_price5Controller.text),
      price6: _parse(_price6Controller.text),
      stockQuantity: _parse(_stockController.text),
      unitHierarchy: unitHierarchyJson,
      unitCosts: unitCostsJson,
      expiryDate: _expiryDate,
      alertQuantity: _parse(_alertQtyController.text) == 0 ? null : _parse(_alertQtyController.text),
      alertUnit: _alertUnitController.text.isEmpty ? baseKey : _alertUnitController.text,
      createdAt: DateTime.now(),
      lastModifiedAt: DateTime.now(),
    );

    try {
      // حفظ الوحدات الجديدة إذا لم تكن موجودة
      if (baseKey.isNotEmpty && !_availableUnits.contains(baseKey)) {
        await db.addCustomUnit(baseKey);
      }
      for (var h in finalHierarchy) {
        final unitName = h['unit_name']?.toString() ?? '';
        if (unitName.isNotEmpty && !_availableUnits.contains(unitName)) {
          await db.addCustomUnit(unitName);
        }
      }
      
      final productId = await db.insertProduct(product);
      
      // 🏷️ حفظ الباركودات الإضافية
      for (var barcodeItem in _barcodeItems) {
        final barcode = barcodeItem['barcode']?.toString().trim() ?? '';
        if (barcode.isNotEmpty) {
          await db.addProductBarcode(
            productId: productId,
            barcode: barcode,
            variantLabel: barcodeItem['variant_label']?.toString(),
            sellPrice: barcodeItem['sell_price'] as double?,
            costPrice: barcodeItem['cost_price'] as double?,
          );
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ المنتج بنجاح!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الحفظ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _stockController.dispose();
    _nameController.dispose();
    _barcodeController.dispose();
    _baseUnitNameController.dispose();
    _baseCostController.dispose();
    _basePriceController.dispose();
    _price2Controller.dispose();
    _price3Controller.dispose();
    _price4Controller.dispose();
    _price5Controller.dispose();
    _price6Controller.dispose();
    _baseWeightController.dispose();
    _alertQtyController.dispose();
    _alertUnitController.dispose();
    super.dispose();
  }

  // ... (Helpers)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      // Custom Header
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          alignment: Alignment.bottomCenter,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left: Back Button & Title (Swapped) -> Actually user said "Manage Products on the other side"
              // Originally: Left=Stats, Right=Title
              // User wants: Right=Stats, Left=Title ?? Or simply swapped.
              // Let's put Title on Right (standard Arabic) and Stats on Left?
              // Wait, the user said "flipped". Arabic usually has Title on Right. 
              // Original code: Left=[Stats], Right=[Title].
              // User: "Button upside down... Manage Products wrong side... Total Products wrong side".
              // Interpretation: "Total Products" should be Left (or Right depending on his view).
              // Let's assume standard RTL: Title on Right, Actions/Stats on Left.
              // My previous code: Left=Stats, Right=Title. This is actually RTL-compliant (Start=Stats, End=Title if LTR).
              // Wait, in RTL (Ar), 'Start' is Right.
              // So `Row(children: [A, B])` displays A then B. In RTL, A is Right, B is Left.
              // So my code displayed: Stats(Right) ... Title(Left).
              // User said: "Manage Products" (Title) should be on the OTHER side. So he wants Title on Right? Or Left?
              // "Total products on the other side".
              // Okay, I will SWAP them in the Row list.
              
              // New Order: Title Group, Spacer, Stats Group
              
              // 1. Title Group (with Back Button)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: kPrimaryColor, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.inventory_2_outlined, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start, // Align to start (Right in RTL)
                    children: [
                      const Text('إدارة المنتجات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kTextColor)),
                      Text('نظام الجوكر • الإصدار الاحترافي', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                    ],
                  ),
                ],
              ),
              
              const Spacer(),
              
              // 2. Stats Group & Manage Categories
               Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('إجمالي المنتجات', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  Text(
                    '$_totalProductsCount',
                    style: const TextStyle(color: kPrimaryColor, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: _addNewCategory,
                icon: const Icon(Icons.category_outlined, size: 18),
                label: const Text('إدارة الأقسام'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kTextColor,
                  side: BorderSide(color: Colors.grey[300]!),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
               const SizedBox(width: 16),
               // Back Button
               IconButton(
                 onPressed: () => Navigator.pop(context),
                 icon: const Icon(Icons.arrow_forward_ios, color: kTextColor), // Forward for RTL back
                 tooltip: 'رجوع',
               ),
            ],
          ),
        ),
      ),
      
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Section 01
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
                        child: ModernTextField(
                          controller: _nameController,
                          label: 'اسم المنتج',
                          hint: 'مثال: دجاج تركي، سلك كهرباء...',
                          isRequired: true,
                        ),
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
                    child: Column(
                       children: [
                         Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildToggle('يباع بالوزن؟', _isWeighable, (v) => setState(() => _isWeighable = v)),
                              Container(width: 1, height: 40, color: Colors.grey[300]),
                              _buildToggle('له تاريخ صلاحية؟', _hasExpiry, (v) => setState(() => _hasExpiry = v)),
                            ],
                          ),
                          if (_hasExpiry) ...[
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 16),
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _expiryDate ?? DateTime.now().add(const Duration(days: 365)),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                                  locale: const Locale('ar'),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: const ColorScheme.light(
                                          primary: kPrimaryColor,
                                          onPrimary: Colors.white,
                                          surface: Colors.white,
                                          onSurface: Color(0xFF1E1E2E),
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked != null) {
                                  setState(() => _expiryDate = picked);
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.calendar_month, color: Colors.orange, size: 24),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'تاريخ انتهاء الصلاحية',
                                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _expiryDate != null
                                                ? DateFormat('dd/MM/yyyy', 'ar').format(_expiryDate!)
                                                : 'اضغط لاختيار التاريخ',
                                            style: TextStyle(
                                              color: _expiryDate != null ? const Color(0xFF1E1E2E) : Colors.grey[400],
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_expiryDate != null)
                                      IconButton(
                                        icon: const Icon(Icons.clear, color: Colors.grey),
                                        onPressed: () => setState(() => _expiryDate = null),
                                      )
                                    else
                                      const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                                  ],
                                ),
                              ),
                            ),
                          ]
                       ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Section 02: الوحدة والسعر (أساسي)
            ModernSectionCard(
               number: '02',
               title: 'الأسعار والمخزون',
               subtitle: 'حدد سياستك السعرية والكمية المتوفرة',
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   // صف الوحدة الأساسية والرصيد
                   Row(
                     children: [
                       Expanded(
                         flex: 3, // مساحة أكبر لاسم الوحدة
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Row(
                               mainAxisSize: MainAxisSize.min,
                               children: [
                                 const Text('الوحدة الأساسية', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
                                 const Text(' *', style: TextStyle(color: Colors.red)),
                               ],
                             ),
                             const SizedBox(height: 8),
                             Container(
                               decoration: BoxDecoration(color: kInputFillColor, borderRadius: BorderRadius.circular(12)),
                               child: Autocomplete<String>(
                                 initialValue: TextEditingValue(text: _baseUnitNameController.text),
                                 optionsBuilder: (textEditingValue) {
                                   if (textEditingValue.text.isEmpty) return _availableUnits;
                                   return _availableUnits.where((u) => u.contains(textEditingValue.text));
                                 },
                                 onSelected: (selection) {
                                   setState(() => _baseUnitNameController.text = selection);
                                 },
                                 fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                                   controller.addListener(() => _baseUnitNameController.text = controller.text);
                                   return TextField(
                                     controller: controller,
                                     focusNode: focusNode,
                                     decoration: InputDecoration(
                                       border: InputBorder.none,
                                       contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                       hintText: 'قطعة، كرتون...',
                                       suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                                     ),
                                   );
                                 },
                                 optionsViewBuilder: (context, onSelected, options) {
                                   return Align(
                                     alignment: Alignment.topRight,
                                     child: Material(
                                       elevation: 4,
                                       borderRadius: BorderRadius.circular(8),
                                       child: Container(
                                         constraints: const BoxConstraints(maxHeight: 250, maxWidth: 250),
                                         child: ListView.builder(
                                           padding: EdgeInsets.zero,
                                           shrinkWrap: true,
                                           itemCount: options.length,
                                           itemBuilder: (context, i) {
                                             final opt = options.elementAt(i);
                                             return ListTile(
                                               dense: true,
                                               title: Text(opt),
                                               onTap: () => onSelected(opt),
                                             );
                                           },
                                         ),
                                       ),
                                     ),
                                   );
                                 },
                               ),
                             ),
                           ],
                         ),
                       ),
                       const SizedBox(width: 12),
                       Expanded(
                         flex: 2,
                         child: ModernTextField(
                           controller: _stockController, 
                           label: 'الرصيد الحالي', 
                           hint: '0', 
                           inputFormatters: [ThousandSeparatorDecimalInputFormatter()]
                         )
                       ),
                     ],
                   ),
                   
                   if (_isWeighable) ...[
                     const SizedBox(height: 16),
                      ModernTextField(
                        controller: _baseWeightController, 
                        label: 'وزن الوحدة (كغم)', 
                        hint: '0.120', 
                        inputFormatters: [ThousandSeparatorDecimalInputFormatter()]
                      ),
                   ],

                   const SizedBox(height: 16),
                   
                   // صف الأسعار (تكلفة + بيع مفرد)
                   Row(
                     children: [
                       Expanded(child: ModernTextField(
                         controller: _baseCostController, 
                         label: 'سعر التكلفة', 
                         hint: '0.0', 
                         inputFormatters: [ThousandSeparatorDecimalInputFormatter()]
                       )),
                       const SizedBox(width: 12),
                       Expanded(child: ModernTextField(
                         controller: _basePriceController, 
                         label: 'سعر البيع (مفرد) *', 
                         hint: '0.0', 
                         inputFormatters: [ThousandSeparatorDecimalInputFormatter()]
                       )),
                     ],
                   ),
                   
                    const SizedBox(height: 16),
                    // 🔔 حقول التنبيه (Low Stock Alert)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.notification_important_outlined, color: Colors.red, size: 18),
                              SizedBox(width: 8),
                              Text('تنبيه نفاد الكمية', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: ModernTextField(
                                  controller: _alertQtyController,
                                  label: 'نبهني عندما تصل الكمية إلى',
                                  hint: 'مثال: 10',
                                  inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('الوحدة', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                                    const SizedBox(height: 8),
                                    Container(
                                      decoration: BoxDecoration(color: kInputFillColor, borderRadius: BorderRadius.circular(12)),
                                      child: Autocomplete<String>(
                                        initialValue: TextEditingValue(text: _alertUnitController.text),
                                        optionsBuilder: (textEditingValue) {
                                          List<String> units = [_baseUnitNameController.text];
                                          for (var h in _hierarchyItems) {
                                            if (h['unit_name'] != null) units.add(h['unit_name']);
                                          }
                                          if (textEditingValue.text.isEmpty) return units;
                                          return units.where((u) => u.contains(textEditingValue.text));
                                        },
                                        onSelected: (selection) => setState(() => _alertUnitController.text = selection),
                                        fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                                          controller.addListener(() => _alertUnitController.text = controller.text);
                                          return TextField(
                                            controller: controller,
                                            focusNode: focusNode,
                                            decoration: const InputDecoration(
                                              border: InputBorder.none,
                                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                              hintText: 'قطعة...',
                                              suffixIcon: Icon(Icons.arrow_drop_down, color: Colors.grey),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // باركود أساسي
                    ModernTextField(
                      controller: _barcodeController, 
                      label: 'الباركود الأساسي', 
                      hint: 'امسح الباركود ميديا أو بالكاميرا...',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.camera_alt_rounded, color: Color(0xFF4F46E5)),
                        tooltip: 'مسح الباركود بالكاميرا',
                        onPressed: () async {
                          final code = await CameraBarcodeScannerDialog.scan(context);
                          if (code != null && code.isNotEmpty) {
                            setState(() {
                              _barcodeController.text = code;
                            });
                          }
                        },
                      ),
                    ),
                 ],
               ),
            ),

            const SizedBox(height: 24),
            
            // Section 03: خيارات متقدمة (Segmented Capsule Switcher)
            ModernSectionCard(
              number: '03',
              title: 'خيارات متقدمة للمنتج',
              subtitle: 'الأسعار الخاصة، الباركودات والنكهات، وتعبئة الوحدات الكبرى',
              child: Builder(
                builder: (context) {
                  int extraPricesCount = [_price2Controller, _price3Controller, _price4Controller, _price5Controller, _price6Controller]
                      .where((c) => c.text.trim().isNotEmpty && c.text.trim() != '0')
                      .length;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Segmented Tab Switcher Bar
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.withOpacity(0.15)),
                        ),
                        child: Row(
                          children: [
                            _buildAdvancedTabButton(
                              index: 0,
                              title: 'الأسعار الإضافية',
                              icon: Icons.price_change_outlined,
                              activeColor: const Color(0xFF4F46E5),
                              badgeCount: extraPricesCount,
                            ),
                            _buildAdvancedTabButton(
                              index: 1,
                              title: 'باركودات ونكهات',
                              icon: Icons.qr_code_2_outlined,
                              activeColor: const Color(0xFFEA580C),
                              badgeCount: _barcodeItems.length,
                            ),
                            _buildAdvancedTabButton(
                              index: 2,
                              title: 'تعبئة كبرى',
                              icon: Icons.account_tree_outlined,
                              activeColor: const Color(0xFF059669),
                              badgeCount: _hierarchyItems.length,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Tab Content with AnimatedSwitcher
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _buildSelectedTabContent(extraPricesCount),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),
      
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            onPressed: _saveProduct,
            style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 4),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                 Icon(Icons.check_circle, color: Colors.white),
                 SizedBox(width: 12),
                 Text('حفظ وإضافة للمخزن', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Reusable Modern Widgets ---

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
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
           BoxShadow(color: const Color(0xff121212).withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: kPrimaryColor, borderRadius: BorderRadius.circular(12)),
                  child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kTextColor)),
                    Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(20), child: child),
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
          decoration: BoxDecoration(color: kInputFillColor, borderRadius: BorderRadius.circular(12)),
          child: TextFormField(
            controller: controller,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
              suffixIcon: suffixIcon,
              isDense: true,
            ),
            validator: isRequired ? (val) => val == null || val.isEmpty ? 'مطلوب' : null : null,
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
