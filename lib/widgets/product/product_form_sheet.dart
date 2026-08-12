import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/product.dart';
import '../../models/category.dart';
import '../../services/database_service.dart';
import '../modern_text_field.dart';
import '../gradient_button.dart';

// Joker Colors
const Color kPrimaryColor = Color(0xFF5D5FEF);
const Color kSecondaryColor = Color(0xFF843BCE);
const Color kBackgroundColor = Color(0xFFF5F7FA);

class ProductFormSheet extends StatefulWidget {
  final Product? product;
  final Function(Product) onSave;

  const ProductFormSheet({super.key, this.product, required this.onSave});

  @override
  State<ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<ProductFormSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final DatabaseService _db = DatabaseService();

  // Controllers
  final _nameController = TextEditingController();
  final _priceController = TextEditingController(text: '0.0');
  final _costController = TextEditingController(text: '0.0');
  final _skuController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _weightController = TextEditingController(); // For weight
  
  // Unit & Hierarchy
  final _baseUnitController = TextEditingController(text: 'قطعة'); // Text controller for autocomplete
  List<String> _availableUnits = [];
  List<Map<String, dynamic>> _hierarchyItems = []; // [{"unit_name": "كرتون", "qty": 12}]

  // Odoo & Joker Fields
  String _productType = 'storable';
  String _invoicePolicy = 'ordered';
  bool _canBeSold = true;
  bool _canBePurchased = true;
  
    // New Fields
  List<Category> _categories = [];
  int? _selectedCategoryId;
  bool _isWeighable = false; // Is it a weighted product?
  String _weightUnit = 'kg'; // kg, g, ton
  bool _hasExpiry = false;   // Does it expire?
  DateTime? _expiryDate; // ✅ Added state variable
  // Future: int? _alertTime; // Alert days before expiry
  
  // Other State
  bool _isLoadingUnits = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData(); // Combined load
    if (widget.product != null) {
      _loadProductData(widget.product!);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _weightController.dispose();
    _baseUnitController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final units = await _db.getAllUnits();
    final categories = await _db.getAllCategories();
    if (mounted) {
      setState(() {
        _availableUnits = units;
        _categories = categories;
        _isLoadingUnits = false;
      });
    }
  }

  void _loadProductData(Product p) {
    _nameController.text = p.name;
    _priceController.text = p.unitPrice.toString();
    _costController.text = p.costPrice?.toString() ?? '0.0';
    _skuController.text = p.sku ?? '';
    _barcodeController.text = p.barcode ?? '';
    _productType = p.productType;
    _invoicePolicy = p.invoicePolicy;
    _baseUnitController.text = p.unit;
    
    // New Fields Load
    _selectedCategoryId = p.categoryId;
    _isWeighable = p.isWeighable;
    _weightController.text = p.baseWeight?.toString() ?? '';
    _weightUnit = p.weightUnit ?? 'kg';
    _hasExpiry = p.hasExpiry;
    _expiryDate = p.expiryDate; // ✅ Loaded

    // Load Hierarchy
    _hierarchyItems = p.getUnitHierarchyList();
  }

  // --- Logic for Units ---
  void _addHierarchyLevel() {
    setState(() {
      _hierarchyItems.add({'unit_name': '', 'quantity': 10});
    });
  }

  void _removeHierarchyLevel(int index) {
    setState(() {
      _hierarchyItems.removeAt(index);
    });
  }

  void _updateHierarchyItem(int index, String key, dynamic value) {
    setState(() {
      _hierarchyItems[index][key] = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1000,
      constraints: const BoxConstraints(minHeight: 650),
      margin: const EdgeInsets.only(bottom: 30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24), // Joker Rounds
        boxShadow: [
          BoxShadow(color: kPrimaryColor.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header (Joker Style)
            _buildHeader(),
            
            // 2. Tabs
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: kPrimaryColor,
                unselectedLabelColor: Colors.grey,
                indicatorColor: kPrimaryColor,
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                tabs: const [
                  Tab(text: 'أساسي'),
                  Tab(text: 'المبيعات'),
                  Tab(text: 'الشراء'),
                  Tab(text: 'المخزون والوحدات'),
                ],
              ),
            ),

            // 3. Content
            SizedBox(
              height: 500, // Fixed height or use AspectRatio
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGeneralInfoTab(),
                  _buildSalesTab(), // Placeholder
                  _buildPurchaseTab(), // Placeholder
                  _buildInventoryTab(), // The Important One
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image / Icon
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [kPrimaryColor.withOpacity(0.1), kSecondaryColor.withOpacity(0.1)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.inventory_2_outlined, size: 40, color: kPrimaryColor),
          ),
          const SizedBox(width: 20),
          
          // Title & Flags
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ModernTextField(
                  label: '',
                  hint: 'اسم المنتج (مثال: شيبس ليز كبير)',
                  controller: _nameController,
                  isRequired: true,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(
                      selected: _canBeSold,
                      label: const Text('قابل للبيع'),
                      onSelected: (v) => setState(() => _canBeSold = v),
                      selectedColor: kPrimaryColor.withOpacity(0.2),
                      checkmarkColor: kPrimaryColor,
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _canBePurchased,
                      label: const Text('قابل للشراء'),
                      onSelected: (v) => setState(() => _canBePurchased = v),
                      selectedColor: kSecondaryColor.withOpacity(0.2),
                      checkmarkColor: kSecondaryColor,
                    ),
                  ],
                )
              ],
            ),
          ),

          // Actions
          Column(
            children: [
               GradientButton(
                 text: 'حفظ المنتج',
                 icon: Icons.save_outlined,
                 onPressed: _submitForm,
               ),
            ],
          )
        ],
      ),
    );
  }

  // --- TABS ---

  Widget _buildGeneralInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column
          Expanded(
            child: Column(
              children: [
                _buildJokerCard(
                  title: 'بيانات النوعية والتصنيف',
                  icon: Icons.category,
                  children: [
                     _buildDropdown(
                       label: 'نوع المنتج',
                       value: _productType,
                       items: [
                         {'val': 'storable', 'label': 'منتج مخزني (يتم جرد الكميات)'},
                         {'val': 'consumable', 'label': 'منتج استهلاكي (دائماً متوفر)'},
                         {'val': 'service', 'label': 'خدمة (توصيل/تركيب)'},
                       ],
                       onChanged: (v) => setState(() => _productType = v!),
                       helperText: 'يحدد هل سيقوم النظام بتتبع كميات هذا المنتج في المخزن أم لا.',
                     ),
                     const SizedBox(height: 16),
                     
                     // Category Dropdown
                     Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         const Text('فئة المنتج', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                         const SizedBox(height: 8),
                         Container(
                           padding: const EdgeInsets.symmetric(horizontal: 16),
                           decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(12)),
                           child: DropdownButtonFormField<int>(
                             value: _selectedCategoryId,
                             items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                             onChanged: (v) => setState(() => _selectedCategoryId = v),
                             hint: const Text('اختر الفئة...', style: TextStyle(fontSize: 14)),
                             decoration: const InputDecoration(border: InputBorder.none),
                             isExpanded: true,
                           ),
                         ),
                       ],
                     ),

                     const SizedBox(height: 16),
                     _buildDropdown(
                       label: 'سياسة الفوترة',
                       value: _invoicePolicy,
                       items: [
                         {'val': 'ordered', 'label': 'الكميات المطلوبة (فوراً)'},
                         {'val': 'delivered', 'label': 'الكميات المستلمة (بعد التسليم)'},
                       ],
                       onChanged: (v) => setState(() => _invoicePolicy = v!),
                       helperText: 'متى يحق لك إصدار الفاتورة للعميل؟',
                     ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Right Column
          Expanded(
            child: Column(
              children: [
                 _buildJokerCard(
                  title: 'التسعير',
                  icon: Icons.attach_money,
                  children: [
                     ModernTextField(
                       label: 'سعر البيع',
                       controller: _priceController,
                       keyboardType: TextInputType.number,
                       hint: '0.00',
                       icon: Icons.sell,
                     ),
                     const SizedBox(height: 16),
                     ModernTextField(
                       label: 'سعر التكلفة',
                       controller: _costController,
                       keyboardType: TextInputType.number,
                       hint: '0.00',
                       icon: Icons.money_off,
                     ),
                  ]
                 ),
                 const SizedBox(height: 24),
                 _buildJokerCard(
                  title: 'الرموز',
                  icon: Icons.qr_code,
                  children: [
                    ModernTextField(
                       label: 'المرجع الداخلي (SKU)',
                       controller: _skuController,
                       hint: 'CODE-123',
                       icon: Icons.tag,
                     ),
                     const SizedBox(height: 16),
                     ModernTextField(
                       label: 'الباركود',
                       controller: _barcodeController,
                       icon: Icons.qr_code_scanner,
                     ),
                  ]
                 ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryTab() {
     return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Logistics Section
          _buildJokerCard(
            title: 'اللوجستيات والتتبع',
            icon: Icons.local_shipping,
            children: [
               Row(
                 children: [
                   Expanded(
                     child: CheckboxListTile(
                       value: _isWeighable,
                       onChanged: (v) => setState(() => _isWeighable = v!),
                       title: const Text('منتج وزني (يباع بالوزن)'),
                       secondary: const Icon(Icons.scale, color: kSecondaryColor),
                       contentPadding: EdgeInsets.zero,
                       activeColor: kPrimaryColor,
                     ),
                   ),
                   if (_isWeighable) ...[
                     const SizedBox(width: 16),
                     Expanded(
                       child: ModernTextField(
                         label: 'وزن القطعة',
                         controller: _weightController,
                         hint: 'مثال: 0.5',
                         keyboardType: TextInputType.number,
                         icon: Icons.monitor_weight_outlined,
                       ),
                     ),
                     const SizedBox(width: 8),
                     SizedBox(
                       width: 120, // Increased to prevent Overflow
                       child: _buildDropdown(label: 'الوحدة', value: _weightUnit, items: [
                         {'val': 'kg', 'label': 'كغم'},
                         {'val': 'g', 'label': 'غرام'},
                         {'val': 'ton', 'label': 'طن'},
                       ], onChanged: (v) => setState(() => _weightUnit = v!)),
                     )
                   ]
                 ],
               ),
               const Divider(),
               CheckboxListTile(
                 value: _hasExpiry,
                 onChanged: (v) => setState(() => _hasExpiry = v!),
                 title: const Text('تتبع تاريخ انتهاء الصلاحية'),
                 subtitle: const Text('سيطلب النظام إدخال تاريخ الانتهاء عند الاستلام'),
                 secondary: const Icon(Icons.event_busy, color: Colors.orange),
                 contentPadding: EdgeInsets.zero,
                 activeColor: Colors.orange,
               ),
               if (_hasExpiry) ...[
                 const SizedBox(height: 16),
                 Container(
                   decoration: BoxDecoration(
                     color: Colors.orange.withOpacity(0.05),
                     borderRadius: BorderRadius.circular(12),
                     border: Border.all(color: Colors.orange.withOpacity(0.2)),
                   ),
                   child: ListTile(
                     title: Text(
                       _expiryDate == null 
                           ? 'اضغط لتحديد تاريخ الانتهاء' 
                           : 'ينتهي في: ${_expiryDate!.year}-${_expiryDate!.month}-${_expiryDate!.day}',
                       style: TextStyle(
                         color: _expiryDate == null ? Colors.grey : Colors.orange[800],
                         fontWeight: FontWeight.bold,
                       ),
                     ),
                     leading: const Icon(Icons.calendar_today, color: Colors.orange),
                     trailing: IconButton(
                       icon: const Icon(Icons.edit),
                       onPressed: () async {
                         final picked = await showDatePicker(
                           context: context,
                           initialDate: _expiryDate ?? DateTime.now().add(const Duration(days: 90)),
                           firstDate: DateTime.now(),
                           lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                         );
                         if (picked != null) {
                           setState(() => _expiryDate = picked);
                         }
                       },
                     ),
                     onTap: () async {
                       final picked = await showDatePicker(
                         context: context,
                         initialDate: _expiryDate ?? DateTime.now().add(const Duration(days: 90)),
                         firstDate: DateTime.now(),
                         lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                       );
                       if (picked != null) {
                         setState(() => _expiryDate = picked);
                       }
                     },
                   ),
                 ),
               ],
            ],
          ),
          
          const SizedBox(height: 24),

          // Units Section
          _buildJokerCard(
            title: 'وحدات القياس والهرمية',
            icon: Icons.schema,
            children: [
              const Text('حدد الوحدات التي تبيع بها هذا المنتج (مثال: قطعة، ثم كرتون يحتوي 12 قطعة).', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              
              // Base Unit Autocomplete
              LayoutBuilder(
                builder: (ctx, constraints) {
                  return Autocomplete<String>(
                    optionsBuilder: (text) => _availableUnits.where((u) => u.contains(text.text)),
                    onSelected: (val) => setState(() => _baseUnitController.text = val),
                     // ignore: avoid_types_on_closure_parameters
                    fieldViewBuilder: (BuildContext context, TextEditingController controller, FocusNode focusNode, VoidCallback onEditingComplete) {
                       // Sync controllers if needed
                       if (controller.text != _baseUnitController.text && _baseUnitController.text.isNotEmpty && controller.text.isEmpty) {
                         controller.text = _baseUnitController.text;
                       }
                       return ModernTextField(
                          label: 'الوحدة الأساسية (أصغر وحدة)',
                          controller: controller, // Use the autocomplete controller
                          hint: 'مثال: قطعة، كيلو',
                          icon: Icons.circle,
                          onChanged: (val) => _baseUnitController.text = val, // Capture manual input
                       );
                    },
                  );
                }
              ),
              
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              
              Text('الوحدات الأكبر (Hierarchy)', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              
              // Dynamic List
              ..._hierarchyItems.asMap().entries.map((entry) {
                 final i = entry.key;
                 final item = entry.value;
                 return Container(
                   margin: const EdgeInsets.only(bottom: 12),
                   padding: const EdgeInsets.all(12),
                   decoration: BoxDecoration(
                     color: kInputFillColor,
                     borderRadius: BorderRadius.circular(12),
                     border: Border.all(color: Colors.grey[300]!),
                   ),
                   child: Row(
                     children: [
                       Expanded(
                         flex: 3,
                         child: Autocomplete<String>(
                            optionsBuilder: (text) => _availableUnits.where((u) => u.contains(text.text) && u != _baseUnitController.text),
                            onSelected: (val) => _updateHierarchyItem(i, 'unit_name', val),
                             // ignore: avoid_types_on_closure_parameters
                            fieldViewBuilder: (BuildContext ctx, TextEditingController ctrl, FocusNode focus, VoidCallback submit) {
                               if (ctrl.text.isEmpty && item['unit_name'] != null) ctrl.text = item['unit_name'];
                               return TextField(
                                 controller: ctrl,
                                 focusNode: focus,
                                 decoration: const InputDecoration(labelText: 'اسم الوحدة الكبرى', border: InputBorder.none),
                                 onChanged: (val) => _updateHierarchyItem(i, 'unit_name', val),
                               );
                            },
                         ),
                       ),
                       const Text(' = '),
                       Expanded(
                         flex: 2,
                         child: TextField(
                           keyboardType: TextInputType.number,
                           controller: TextEditingController(text: item['quantity'].toString()),
                           decoration: const InputDecoration(labelText: 'الكمية', border: InputBorder.none),
                           onChanged: (val) => _updateHierarchyItem(i, 'quantity', double.tryParse(val) ?? 0),
                         ),
                       ),
                       Text(' ${_baseUnitController.text} ', style: const TextStyle(fontWeight: FontWeight.bold)),
                       IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _removeHierarchyLevel(i))
                     ],
                   ),
                 );
              }),
              
              TextButton.icon(
                onPressed: _addHierarchyLevel,
                icon: const Icon(Icons.add),
                label: const Text('إضافة وحدة أكبر (مثل كرتون)'),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSalesTab() => const Center(child: Text('إعدادات المبيعات - سيتم إضافتها لاحقاً'));
  Widget _buildPurchaseTab() => const Center(child: Text('إعدادات الشراء - سيتم إضافتها لاحقاً'));


  // --- Helper Builders ---

  Widget _buildJokerCard({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: kSecondaryColor),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
            ],
          ),
          const Divider(height: 30),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDropdown({required String label, required String value, required List<Map<String, String>> items, required Function(String?) onChanged, String? helperText}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Text(label, style: const TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
         const SizedBox(height: 8),
         Container(
           padding: const EdgeInsets.symmetric(horizontal: 16),
           decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(12)),
           child: DropdownButtonFormField<String>(
             value: value,
             items: items.map((e) => DropdownMenuItem(value: e['val'], child: Text(e['label']!))).toList(),
             onChanged: onChanged,
             decoration: const InputDecoration(border: InputBorder.none),
             isExpanded: true,
           ),
         ),
         if (helperText != null) 
           Padding(
             padding: const EdgeInsets.only(top: 4, right: 8),
             child: Text(helperText, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
           )
      ],
    );
  }

  void _submitForm() {
    if (!_formKey.currentState!.validate()) return;
    if (_baseUnitController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء تحديد الوحدة الأساسية')));
      return;
    }

    final double price = double.tryParse(_priceController.text) ?? 0.0;
    
    // Construct Hierarchy Cost Logic
    Map<String, double> costs = {};
    double baseCost = double.tryParse(_costController.text) ?? 0.0;
    costs[_baseUnitController.text] = baseCost;
    
    // Simple iterative cost calculation assuming hierarchy is flat relative to base for now, 
    // or cascading if we respect order. 
    // Let's assume order matches input: Base -> Level 1 -> Level 2
    
    String previousUnit = _baseUnitController.text;
    double previousCost = baseCost;
    
    // We'll trust the user added them in order (Smallest to Largest)
    for (var item in _hierarchyItems) {
      String name = item['unit_name'] ?? '';
      double qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      if (name.isNotEmpty) {
          double cost = previousCost * qty;
          costs[name] = cost;
          // Set as previous for next level
          previousUnit = name;
          previousCost = cost;
      }
    }

    // Construct the product
    final newProduct = Product(
      id: widget.product?.id,
      name: _nameController.text,
      unit: _baseUnitController.text,
      unitPrice: price,
      costPrice: baseCost,
      price1: price, // Default wholesale same as retail for now
      
      // Hierarchy
      unitHierarchy: _hierarchyItems.isNotEmpty ? jsonEncode(_hierarchyItems) : null,
      unitCosts: costs.isNotEmpty ? jsonEncode(costs) : null,

      // Defaults
      createdAt: widget.product?.createdAt ?? DateTime.now(),
      lastModifiedAt: DateTime.now(),
      
      // Odoo Fields
      productType: _productType,
      invoicePolicy: _invoicePolicy,
      sku: _skuController.text.isEmpty ? null : _skuController.text,
      barcode: _barcodeController.text.isEmpty ? null : _barcodeController.text,
      
      // Flags & New Fields
      isWeighable: _isWeighable,
      baseWeight: double.tryParse(_weightController.text),
      weightUnit: _weightUnit,
      hasExpiry: _hasExpiry,
      expiryDate: _hasExpiry ? _expiryDate : null,
      categoryId: _selectedCategoryId,
    );

    widget.onSave(newProduct);
  }
}
