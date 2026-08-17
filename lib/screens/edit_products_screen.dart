// lib/screens/edit_products_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import '../models/product.dart';
import '../widgets/camera_barcode_scanner_dialog.dart';
import '../models/category.dart';
import '../services/database_service.dart';
import '../services/password_service.dart'; // Import PasswordService
import '../widgets/formatters.dart';
import '../widgets/product/product_basic_info.dart';
import '../widgets/product/product_attributes.dart';
import '../widgets/product/unit_hierarchy.dart';
import '../widgets/product/category_management_dialog.dart';
import '../widgets/product/unit_management_dialog.dart';

// Consts
const Color kPrimaryColor = Color(0xFF5D5FEF);
const Color kInputFillColor = Color(0xFFF8F9FA);

class EditProductsScreen extends StatefulWidget {
  static const routeName = '/edit-products';

  const EditProductsScreen({super.key});

  @override
  State<EditProductsScreen> createState() => _EditProductsScreenState();
}

class _EditProductsScreenState extends State<EditProductsScreen> {
  final TextEditingController _searchController = TextEditingController();
  
  // 🚀 Cache ثابت للمنتجات (مشترك بين جميع النسخ)
  static List<Product> _productsCache = [];
  static DateTime? _lastCacheUpdate;
  static const Duration _cacheValidDuration = Duration(minutes: 5);
  
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  List<Category> _categories = [];
  int? _selectedCategoryId;
  bool _isLoading = false;

  /// 🚀 التحقق من صلاحية Cache
  bool get _isCacheValid {
    if (_lastCacheUpdate == null) return false;
    return DateTime.now().difference(_lastCacheUpdate!) < _cacheValidDuration;
  }

  /// 🚀 إبطال Cache المنتجات
  void _invalidateProductsCache() {
    _lastCacheUpdate = null;
    _productsCache.clear();
  }

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }



  /// 🚀 تحميل المنتجات مع Cache ذكي
  Future<void> _loadProducts() async {
    // 🚀 تحقق من Cache أولاً
    if (_isCacheValid && _productsCache.isNotEmpty) {
      setState(() {
        _allProducts = List.from(_productsCache);
        _filterProducts(_searchController.text);
        _isLoading = false;
      });
      
      // تحميل الفئات في الخلفية
      final db = DatabaseService();
      final categories = await db.getAllCategories();
      if (mounted) {
        setState(() => _categories = categories);
      }
      return;
    }

    // جلب من قاعدة البيانات
    setState(() => _isLoading = true);
    final db = DatabaseService();
    final products = await db.getAllProducts();
    final categories = await db.getAllCategories();
    
    // 🚀 تحديث Cache
    _productsCache = List.from(products);
    _lastCacheUpdate = DateTime.now();
    
    if (mounted) {
      setState(() {
        _allProducts = products;
        _categories = categories;
        _filterProducts(_searchController.text);
        _isLoading = false;
      });
    }
  }

  void _filterProducts(String query) {
    setState(() {
      _filteredProducts = _allProducts.where((product) {
        final matchesQuery = product.name.toLowerCase().contains(query.toLowerCase()) ||
            (product.barcode != null && product.barcode!.contains(query));
        final matchesCategory = _selectedCategoryId == null || product.categoryId == _selectedCategoryId;
        return matchesQuery && matchesCategory;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    // --- Modern Authenticated UI ---
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      // Modern Header matching ProductEntryScreen
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          alignment: Alignment.bottomCenter,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Title Group
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kPrimaryColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.edit_note, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تعديل المنتجات',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E1E2E),
                        ),
                      ),
                      Text(
                        'نظام  • البحث والتعديل',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),

              const Spacer(),

              // Stats Group
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'المنتجات المعروضة',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  Text(
                    '${_filteredProducts.length}',
                    style: const TextStyle(
                      color: kPrimaryColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // Unit Management Button
              OutlinedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => const UnitManagementDialog(),
                  );
                },
                icon: const Icon(Icons.straighten, size: 18),
                label: const Text('إدارة الوحدات'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1E1E2E),
                  side: BorderSide(color: Colors.grey[300]!),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 16),
              // Back Button
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_forward_ios, color: Color(0xFF1E1E2E)),
                tooltip: 'رجوع',
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Summary & Category Slider
          Container(
            padding: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Modern Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'بحث عن منتج (الاسم أو الباركود)...',
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                        prefixIcon: const Icon(Icons.search, color: kPrimaryColor, size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  _filterProducts('');
                                },
                              )
                            : null,
                      ),
                      onChanged: _filterProducts,
                    ),
                  ),
                ),
                // Category Slider
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _categories.length + 1,
                    itemBuilder: (context, index) {
                      final isAll = index == 0;
                      final cat = isAll ? null : _categories[index - 1];
                      final isSelected = isAll ? _selectedCategoryId == null : _selectedCategoryId == cat?.id;

                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedCategoryId = isAll ? null : cat?.id;
                              _filterProducts(_searchController.text);
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? kPrimaryColor : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? kPrimaryColor : Colors.grey[200]!,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                isAll ? 'الكل' : (cat?.name ?? ''),
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.grey[600],
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 12,
                                ),
                              ),
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
          
          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: kPrimaryColor))
                : _filteredProducts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[200]),
                            const SizedBox(height: 16),
                            Text(
                              'لا توجد منتجات مطابقة',
                              style: TextStyle(color: Colors.grey[400], fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                          final category = _categories.firstWhere(
                            (c) => c.id == product.categoryId,
                            orElse: () => Category(id: -1, name: 'غير محدد'),
                          );

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: InkWell(
                              onTap: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ProductEditScreen(product: product),
                                  ),
                                );
                                if (result == true) {
                                  // 🚀 إبطال Cache وإعادة التحميل
                                  _invalidateProductsCache();
                                  _loadProducts();
                                }
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    // Avatar
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [kPrimaryColor.withOpacity(0.1), kPrimaryColor.withOpacity(0.05)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: const Icon(Icons.shopping_bag_outlined, color: kPrimaryColor, size: 26),
                                    ),
                                    const SizedBox(width: 16),
                                    // Info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            product.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Color(0xFF1E1E2E),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              _buildMiniBadge(category.name, Colors.blue),
                                              const SizedBox(width: 8),
                                              if (product.barcode != null && product.barcode!.isNotEmpty)
                                                _buildMiniBadge(product.barcode!, Colors.grey),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Price
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${product.price1.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: kPrimaryColor,
                                            fontSize: 20,
                                          ),
                                        ),
                                        const Text(
                                          'دينار',
                                          style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 16),
                                    // Action Button
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [kPrimaryColor, Color(0xFF8C9EFF)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: kPrimaryColor.withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(Icons.edit_outlined, size: 20, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }}

class ProductEditScreen extends StatefulWidget {
  final Product product;
  const ProductEditScreen({super.key, required this.product});

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseService();

  // Controllers
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _baseCostController = TextEditingController(); // تكلفة الوحدة الأساسية
  final _baseWeightController = TextEditingController(); // وزن القطعة (للموزونات)
  
  // Prices
  final _price1Controller = TextEditingController();
  final _price2Controller = TextEditingController();
  final _price3Controller = TextEditingController();
  final _price4Controller = TextEditingController();
  final _price5Controller = TextEditingController();
  final _price6Controller = TextEditingController(); // 🆕 Price 6

  // State
  final _alertQtyController = TextEditingController();
  final _alertUnitController = TextEditingController();
  final _unitController = TextEditingController(); // 🆕 Controller for Base Unit Name

  // State
  List<Category> _categories = [];
  List<String> _availableUnits = []; 
  int? _selectedCategoryId;
  bool _isWeighable = false;
  bool _hasExpiry = false;
  DateTime? _expiryDate;
  String _baseUnitName = 'piece'; 
  
  // Hierarchy Data
  List<Map<String, dynamic>> _hierarchyItems = [];
  
  // 🆕 Multi-Barcode Data
  List<Map<String, dynamic>> _barcodeItems = [];
  bool _showAdditionalBarcodes = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadUnits(); // 🆕 Load Units
    _initializeData();
    _loadBarcodes(); // 🆕 Load Barcodes
    _loadCategories();
    _loadUnits(); // 🆕 Load Units
    _initializeData();
    _loadBarcodes(); // 🆕 Load Barcodes

  }

  Future<void> _initializeData() async {
    // 🔄 Reload product from database to get latest data
    final dbService = DatabaseService();
    print('🔍 EDIT_DEBUG: Loading product ID: ${widget.product.id}');
    print('🔍 EDIT_DEBUG: Widget product cost_price: ${widget.product.costPrice}');
    
    final freshProduct = await dbService.getProductById(widget.product.id!);
    
    print('🔍 EDIT_DEBUG: Fresh product from DB: ${freshProduct != null ? "FOUND" : "NULL"}');
    if (freshProduct != null) {
      print('🔍 EDIT_DEBUG: Fresh product cost_price: ${freshProduct.costPrice}');
    }
    
    final p = freshProduct ?? widget.product;
    
    _nameController.text = p.name;
    _barcodeController.text = p.barcode ?? '';
    _selectedCategoryId = p.categoryId;
    
    _isWeighable = p.isWeighable;
    _hasExpiry = p.hasExpiry;
    _expiryDate = p.expiryDate;
    
    // 🔧 Fix Unit Display on Load
    // If it's the old internal key 'piece', show 'قطعة'.
    // If it's 'meter', show 'متر'.
    // Otherwise, show EXACTLY what is stored (e.g. 'لفة', 'ق', etc.)
    if (p.unit == 'piece') {
      _baseUnitName = 'قطعة';
    } else if (p.unit == 'meter') {
      _baseUnitName = 'متر';
    } else {
      _baseUnitName = p.unit;
    }
    _unitController.text = _baseUnitName; // 🆕 Sync controller with state 
    
    _alertQtyController.text = p.alertQuantity != null ? _formatNumber(p.alertQuantity) : '';
    _alertUnitController.text = p.alertUnit ?? '';
    
    if (_isWeighable) {
       _baseWeightController.text = p.baseWeight?.toString() ?? '';
    }

    // ✅ cost_price from DB is the authoritative source
    // Updated by purchase invoices, no need to check unitCosts
    double baseCost = p.costPrice ?? 0.0;
    print('🔍 EDIT_DEBUG: Using cost_price from DB: $baseCost');
    
    _baseCostController.text = _formatNumber(baseCost);

    _price1Controller.text = _formatNumber(p.price1);
    _price2Controller.text = _formatNumber(p.price2);
    _price3Controller.text = _formatNumber(p.price3);
    _price4Controller.text = _formatNumber(p.price4);
    _price5Controller.text = _formatNumber(p.price5);
    _price6Controller.text = _formatNumber(p.price6); // 🆕 Price 6

    // Initialize Hierarchy
    if (p.unitHierarchy != null) {
      try {
        List<dynamic> list = json.decode(p.unitHierarchy!);
        _hierarchyItems = list.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
         // ignore
      }
    }
    
    if (mounted) setState(() {});
  }

  String _formatNumber(double? val) {
    if (val == null) return '';
    if (val == val.roundToDouble()) return val.toInt().toString();
    return val.toString();
  }

  Future<void> _loadCategories() async {
    final cats = await _db.getAllCategories();
    setState(() {
      _categories = cats;
    });
  }

  // 🆕 Load Available Units
  Future<void> _loadUnits() async {
    final units = await _db.getAllUnits();
    if (mounted) {
      setState(() => _availableUnits = units);
    }
  }

  // 🆕 Load Existing Barcodes
  Future<void> _loadBarcodes() async {
    final barcodes = await _db.getProductBarcodes(widget.product.id!);
    if (mounted) {
      setState(() {
         _barcodeItems = barcodes.map((b) => {
           'barcode': b['barcode'],
           'variant_label': b['variant_label'],
           'sell_price': b['sell_price'],
           'cost_price': b['cost_price'],
           'id': b['id'], // Store ID to delete/update later if needed
         }).toList();
      });
    }
  }

  /// الحصول على الوحدات المتاحة للهرمية (بدون المستخدمة)
  List<String> _getAvailableUnitsForHierarchy(int currentIndex) {
    Set<String> usedUnits = {_baseUnitName.trim()};
    for (int i = 0; i < currentIndex; i++) {
      final name = _hierarchyItems[i]['unit_name']?.toString() ?? '';
      if (name.isNotEmpty) usedUnits.add(name);
    }
    return _availableUnits.where((u) => !usedUnits.contains(u)).toList();
  }

  void _addNewCategory() {
    showDialog(
      context: context,
      builder: (context) => const CategoryManagementDialog(),
    ).then((result) {
       if (result == true) {
         // Reload cats if added
         _loadCategories();
       }
    });
  }

  // 🆕 Build Barcode Row (Matching ProductEntryScreen)
  Widget _buildBarcodeRow(int index) {
    final item = _barcodeItems[index];
    final barcodeController = TextEditingController(text: item['barcode'] ?? '');
    final labelController = TextEditingController(text: item['variant_label'] ?? '');
    final priceController = TextEditingController(
      text: item['sell_price'] != null ? item['sell_price'].toString() : '',
    );
    
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // الباركود
          Expanded(
            flex: 2,
            child: TextField(
              controller: barcodeController,
              decoration: InputDecoration(
                labelText: 'الباركود ${index + 1}',
                hintText: 'scan...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (v) => _barcodeItems[index]['barcode'] = v,
            ),
          ),
          const SizedBox(width: 12),
          // الوصف
          Expanded(
            flex: 2,
            child: TextField(
              controller: labelController,
              decoration: InputDecoration(
                labelText: 'الوصف',
                hintText: 'لون/نكهة...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (v) => _barcodeItems[index]['variant_label'] = v,
            ),
          ),
          const SizedBox(width: 12),
          // السعر
          Expanded(
            flex: 1,
            child: TextField(
              controller: priceController,
              decoration: InputDecoration(
                labelText: 'سعر',
                hintText: 'اختياري',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
              onChanged: (v) => _barcodeItems[index]['sell_price'] = _parse(v),
            ),
          ),
          // حذف
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => setState(() => _barcodeItems.removeAt(index)),
          ),
        ],
      ),
    );
  }

  // --- Hierarchy Handlers ---
  void _addHierarchyItem(Map<String, dynamic> item) {
    setState(() {
      _hierarchyItems.add(item);
    });
  }

  void _removeHierarchyItem(int index) {
    setState(() {
      _hierarchyItems.removeAt(index);
    });
  }

  void _updateHierarchyItem(int index, String unitName, String quantity) {
    setState(() {
      _hierarchyItems[index]['unit_name'] = unitName;
      _hierarchyItems[index]['quantity'] = double.tryParse(quantity) ?? 0;
    });
  }
   // --------------------------

  // Check duplicate logic (simplified for edit)
  void _checkDuplicatePrices(String changedField) {
     // Optional: Warning logic if prices are weird
  }

  double _parse(String val) {
    if (val.isEmpty) return 0.0;
    return double.tryParse(val.replaceAll(',', '')) ?? 0.0;
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Logic for Hierarchy & Costs Calculation
    double baseCost = _parse(_baseCostController.text);
    List<Map<String, dynamic>> finalHierarchy = [];
    Map<String, double> unitCosts = {};
    
    // Base Unit Cost
    String baseKey = _isWeighable ? 'قطعة' : (_baseUnitName == 'piece' ? 'قطعة' : _baseUnitName);
    unitCosts[baseKey] = baseCost;

    if (_baseUnitName == 'piece' && _hierarchyItems.isNotEmpty) {
       for (var item in _hierarchyItems) {
          String uName = item['unit_name'];
          double qty = (item['quantity'] as num).toDouble();
          if (qty <= 0) continue;
          
          finalHierarchy.add({'unit_name': uName, 'quantity': qty});
          
          // Cost Calc
          String prevUnitName = _hierarchyItems.indexOf(item) == 0 ? baseKey : _hierarchyItems[_hierarchyItems.indexOf(item) - 1]['unit_name'];
          double prevCost = unitCosts[prevUnitName] ?? baseCost;
          unitCosts[uName] = prevCost * qty;
       }
    }

    String? unitHierarchyJson = finalHierarchy.isNotEmpty ? json.encode(finalHierarchy) : null;
    String? unitCostsJson = unitCosts.isNotEmpty ? json.encode(unitCosts) : null;

    // 🔧 Prepare Unit Name for Save
    // Only map back standard Arabic names to internal English keys.
    // Preserve any custom name exactly as entered.
    String finalUnit = _baseUnitName.trim();
    if (finalUnit == 'قطعة') finalUnit = 'piece';
    else if (finalUnit == 'متر') finalUnit = 'meter';
    
    final updatedProduct = widget.product.copyWith(
      name: _nameController.text.trim(),
      // 🔧 CRITICAL FIX: Do NOT force 'piece' if weighable.
      // Save the actual unit name entered by the user.
      unit: finalUnit, 
      
      categoryId: _selectedCategoryId,
      isWeighable: _isWeighable,
      baseWeight: _isWeighable ? _parse(_baseWeightController.text) : null,
      weightUnit: _isWeighable ? 'kg' : null,
      hasExpiry: _hasExpiry,
      
      costPrice: baseCost,
      unitPrice: _parse(_price1Controller.text),
      
      price1: _parse(_price1Controller.text),
      price2: _parse(_price2Controller.text),
      price3: _parse(_price3Controller.text),
      price4: _parse(_price4Controller.text),
      price5: _parse(_price5Controller.text),
      price6: _parse(_price6Controller.text), // 🆕 Price 6
      
      expiryDate: _expiryDate,
      alertQuantity: _parse(_alertQtyController.text) == 0 ? null : _parse(_alertQtyController.text),
      alertUnit: _alertUnitController.text.isEmpty ? baseKey : _alertUnitController.text,

      unitHierarchy: unitHierarchyJson,
      unitCosts: unitCostsJson,
      
      lastModifiedAt: DateTime.now(),
    );

    // No need for a second copyWith to fix 'piec' anymore as we handle it correctly above.
    final productToSave = updatedProduct;


    try {
      // 1. Update Product
      await _db.updateProduct(productToSave);

      // 2. Handle Multi-Barcodes (Delete Old & Insert New)
      // Since we don't have a simple bulk update/diff logic here, 
      // easiest reliable way is to fetch existing IDs and delete them, then re-insert.
      // Or just delete all for this product? DatabaseService has `deleteProductBarcode`.
      
      // Get current stored barcodes to delete them
      final currentBarcodes = await _db.getProductBarcodes(widget.product.id!);
      for (var b in currentBarcodes) {
        await _db.deleteProductBarcode(b['id']);
      }

      // Insert new ones
      for (var item in _barcodeItems) {
        final code = item['barcode']?.toString().trim() ?? '';
        if (code.isNotEmpty) {
           await _db.addProductBarcode(
             productId: widget.product.id!,
             barcode: code,
             variantLabel: item['variant_label'],
             sellPrice: item['sell_price'] as double?,
             costPrice: item['cost_price'] as double?,
           );
        }
      }
      
      // 3. Add Custom Units if needed
      if (baseKey.isNotEmpty && !_availableUnits.contains(baseKey)) {
        await _db.addCustomUnit(baseKey);
      }
      for (var h in finalHierarchy) {
        final unitName = h['unit_name']?.toString() ?? '';
        if (unitName.isNotEmpty && !_availableUnits.contains(unitName)) {
           await _db.addCustomUnit(unitName);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التعديلات بنجاح!'), backgroundColor: Colors.green),
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
    _nameController.dispose();
    _barcodeController.dispose();
    _baseCostController.dispose();
    _baseWeightController.dispose();
    _price1Controller.dispose();
    _price2Controller.dispose();
    _price3Controller.dispose();
    _price4Controller.dispose();
    _price5Controller.dispose();
    _price6Controller.dispose();
    _alertQtyController.dispose();
    _alertUnitController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _deleteProduct() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد أنك تريد حذف هذا المنتج؟ لا يمكن التراجع عن هذه العملية.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
       await _db.deleteProduct(widget.product.id!);
       if (mounted) {
         Navigator.pop(context, true);
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('تم حذف المنتج بنجاح'), backgroundColor: Colors.red),
         );
       }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          alignment: Alignment.bottomCenter,
          child: Row(
            children: [
               Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: kPrimaryColor, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.edit_note, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('تعديل المنتج', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E1E2E))),
                  Text(widget.product.name, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                ],
              ),
              const Spacer(),
              IconButton( // Back Button
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_forward_ios, color: Color(0xFF1E1E2E)),
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
            // Section 1: Basic Info
            ModernSectionCard(
              number: '01',
              title: 'البيانات الأساسية',
              subtitle: 'اسم المنتج، الفئة، والباركود',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: ModernTextField(
                          controller: _nameController,
                          label: 'اسم المنتج',
                          hint: 'مثال: دجاج، أرز...',
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ModernTextField(
                          controller: _barcodeController,
                          label: 'الباركود',
                          hint: 'scan...',
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
                      ),
                      const SizedBox(width: 16),
                      // Add Category Button
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('إجراءات', style: TextStyle(color: Colors.transparent, fontSize: 12)), // Spacer
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _addNewCategory,
                            icon: const Icon(Icons.add),
                            label: const Text('قسم جديد'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Section 2: Attributes
            ModernSectionCard(
              number: '02',
              title: 'الخصائص والوحدة الأساسية',
              subtitle: 'الوزن، الصلاحية، والتسعير الأساسي',
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildToggle('منتج يوزن؟', _isWeighable, (v) => setState(() => _isWeighable = v)),
                      const SizedBox(width: 24),
                      _buildToggle('انتهاء صلاحية؟', _hasExpiry, (v) => setState(() => _hasExpiry = v)),
                    ],
                  ),
                  if (_hasExpiry) ...[
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _expiryDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
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
                              _expiryDate == null ? 'اختر تاريخ الصلاحية' : intl.DateFormat('yyyy-MM-dd').format(_expiryDate!),
                              style: TextStyle(color: _expiryDate == null ? Colors.grey : Colors.black),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const Divider(height: 32),
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
                                        List<String> units = [_baseUnitName];
                                        for (var h in _hierarchyItems) {
                                          if (h['unit_name'] != null) units.add(h['unit_name']);
                                        }
                                        if (textEditingValue.text.isEmpty) return units;
                                        return units.where((u) => u.contains(textEditingValue.text));
                                      },
                                      onSelected: (selection) => setState(() => _alertUnitController.text = selection),
                                      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                                        // Sync controller text with state
                                        if (controller.text != _alertUnitController.text) {
                                          controller.text = _alertUnitController.text;
                                        }
                                        return TextField(
                                          controller: controller,
                                          focusNode: focusNode,
                                          decoration: const InputDecoration(
                                            border: InputBorder.none,
                                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                            hintText: 'قطعة...',
                                            suffixIcon: Icon(Icons.arrow_drop_down, color: Colors.grey),
                                          ),
                                          onChanged: (v) => _alertUnitController.text = v,
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
                  const Divider(height: 32),
                  Row(
                    children: [
                      Expanded(
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                              const Text('اسم الوحدة الأساسية', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(color: kInputFillColor, borderRadius: BorderRadius.circular(12)),
                                child: TextFormField(
                                  controller: _unitController, // 🆕 Use controller instead of initialValue
                                  onChanged: (v) => _baseUnitName = v, // Updates generic variable
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    hintText: 'قطعة',
                                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                                    isDense: true,
                                  ),
                                ),
                              ),
                           ],
                         ),
                      ),
                      if (_isWeighable) ...[
                        const SizedBox(width: 16),
                        Expanded(
                          child: ModernTextField(
                            controller: _baseWeightController,
                            label: 'وزن الوحدة (كغم)',
                            hint: '0.000',
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                     children: [
                       Expanded(
                         child: ModernTextField(
                           controller: _baseCostController,
                           label: 'سعر التكلفة',
                           hint: '0.00',
                           inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                         ),
                       ),
                     ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 🆕 Section 2b: Multi-Barcodes
            ModernSectionCard(
               number: '2b',
               title: 'باركودات متعددة',
               subtitle: 'إضافة باركودات فرعية لنكهات أو ألوان',
               child: Column(
                 children: [
                   for (int i = 0; i < _barcodeItems.length; i++)
                     _buildBarcodeRow(i),
                   
                   SizedBox(
                     width: double.infinity,
                     child: OutlinedButton.icon(
                       onPressed: () {
                         setState(() {
                           _barcodeItems.add({
                             'barcode': '',
                             'variant_label': '',
                             'sell_price': null,
                           });
                         });
                       },
                       icon: const Icon(Icons.add),
                       label: const Text('إضافة باركود جديد'),
                     ),
                   ),
                 ],
               ),
            ),

            const SizedBox(height: 24),

            // Section 3: Hierarchy
            ModernSectionCard(
              number: '03',
              title: 'شجرة الوحدات الكبرى',
              subtitle: 'كرتون، صندوق، إلخ...',
              child: Column(
                children: [
                  _buildHierarchyNode(
                    title: _baseUnitName.isEmpty ? 'قطعة' : _baseUnitName,
                    subtitle: 'الوحدة الأساسية',
                    isRoot: true,
                  ),
                  for (int i = 0; i < _hierarchyItems.length; i++)
                    _buildHierarchyNode(index: i, isRoot: false),
                  
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _hierarchyItems.add({'unit_name': '', 'quantity': 10.0});
                        });
                      },
                      icon: const Icon(Icons.add_link),
                      label: const Text('إضافة مستوى جديد'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kPrimaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: kPrimaryColor.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Section 4: Prices
            ModernSectionCard(
              number: '04',
              title: 'قائمة الأسعار',
              subtitle: 'تحديد أسعار البيع المختلفة',
              child: Column(
                children: [
                  ModernTextField(controller: _price1Controller, label: 'سعر البيع (المفرد)', hint: '0', isRequired: true, inputFormatters: [ThousandSeparatorDecimalInputFormatter()]),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: const Text('أسعار إضافية (جملة/خاص)', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
                    children: [
                      const SizedBox(height: 8),
                      ModernTextField(controller: _price2Controller, label: 'سعر 2 (جملة)', hint: '0', inputFormatters: [ThousandSeparatorDecimalInputFormatter()]),
                      const SizedBox(height: 12),
                      ModernTextField(controller: _price3Controller, label: 'سعر 3 (جملة)', hint: '0', inputFormatters: [ThousandSeparatorDecimalInputFormatter()]),
                      const SizedBox(height: 12),
                      ModernTextField(controller: _price4Controller, label: 'سعر 4 (خاص)', hint: '0', inputFormatters: [ThousandSeparatorDecimalInputFormatter()]),
                      const SizedBox(height: 12),
                      ModernTextField(controller: _price5Controller, label: 'سعر 5 (تصفية)', hint: '0', inputFormatters: [ThousandSeparatorDecimalInputFormatter()]),
                      const SizedBox(height: 12),
                      ModernTextField(controller: _price6Controller, label: 'سعر 6 (أخرى)', hint: '0', inputFormatters: [ThousandSeparatorDecimalInputFormatter()]), // 🆕 Price 6
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: InkWell(
                    onTap: _deleteProduct,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 55,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.withOpacity(0.2)),
                      ),
                      alignment: Alignment.center,
                      child: const Text('حذف المنتج', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: _saveChanges,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 55,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [kPrimaryColor, Color(0xFF4F46E5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: kPrimaryColor.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, color: Colors.white),
                          SizedBox(width: 8),
                          Text('حفظ التعديلات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
             const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
  Widget _buildHierarchyNode({
    int? index,
    String? title,
    String? subtitle,
    required bool isRoot,
  }) {
    if (isRoot) {
      return Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: kPrimaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kPrimaryColor.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.circle, color: kPrimaryColor, size: 12),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title ?? 'قطعة', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(subtitle ?? 'الوحدة الأساسية', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ],
        ),
      );
    }

    // For hierarchy items
    final item = _hierarchyItems[index!];
    final qtyController = TextEditingController(text: (item['quantity'] ?? 0).toString());
    final availableUnits = _getAvailableUnitsForHierarchy(index);
    final currentUnitName = item['unit_name']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('اسم الوحدة', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: kInputFillColor, borderRadius: BorderRadius.circular(12)),
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
                       // Ensure the controller text matches the state if rebuilt
                       if (controller.text != currentUnitName) {
                         controller.text = currentUnitName;
                       }
                       return TextField(
                         controller: controller,
                         focusNode: focusNode,
                         decoration: InputDecoration(
                           border: InputBorder.none,
                           contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                           hintText: 'كرتون، باكيت...',
                           hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
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
          const SizedBox(width: 16),
          Expanded(
            child: Builder(
              builder: (context) {
                // الحصول على اسم الوحدة الحالية والسابقة
                final currentUnitName = item['unit_name']?.toString() ?? '';
                final String prevUnitName;
                if (index == 0) {
                  prevUnitName = _baseUnitName.isEmpty ? 'قطعة' : _baseUnitName;
                } else {
                  prevUnitName = _hierarchyItems[index - 1]['unit_name']?.toString() ?? 'وحدة';
                }
                
                // بناء النص الديناميكي
                final String dynamicLabel = currentUnitName.isNotEmpty 
                    ? '$currentUnitName يحتوي على كم $prevUnitName؟'
                    : 'يحتوي على كم $prevUnitName؟';
                
                return ModernTextField(
                  controller: qtyController,
                  label: dynamicLabel,
                  hint: 'عدد الوحدات',
                  onChanged: (v) => _hierarchyItems[index]['quantity'] = double.tryParse(v.replaceAll(',', '')) ?? 0,
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => setState(() => _hierarchyItems.removeAt(index)),
          ),
        ],
      ),
    );
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
} // End _ProductEditScreenState

// --- Modern UI Helpers ---

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
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
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E1E2E))),
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

  const ModernTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.isRequired = false,
    this.inputFormatters,
    this.onChanged,
    this.suffixIcon,
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
