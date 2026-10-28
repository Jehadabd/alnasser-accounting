import 'package:flutter/material.dart';
import '../services/save_lock.dart'; // 🔒 قفل الحفظ
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import '../models/category.dart';
import '../models/customer.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../erp/pos/scale_barcode.dart';
import '../services/settings_manager.dart';
import '../services/thermal_receipt_service.dart';
import '../services/firebase_sync/invoice_sync_service.dart';

class CartItem {
  final String id;
  final Product product;
  int quantity;
  double price;
  String selectedUnit; // Unit type (قطعة, كرتون, باكيت, etc.)
  int unitsInLargeUnit; // How many base units in selected unit

  CartItem({
    required this.id,
    required this.product,
    this.quantity = 1,
    required this.price,
    required this.selectedUnit,
    this.unitsInLargeUnit = 1,
  });

  double get total => price * quantity;
}

enum PaymentType { cash, credit }

class POSProvider extends ChangeNotifier {
  List<Category> _categories = [];
  List<Product> _allProducts = [];
  List<Product> _displayedProducts = [];
  List<Customer> _allCustomers = [];
  List<Customer> _filteredCustomers = [];
  
  final List<CartItem> _cartItems = [];
  
  int? _selectedCategoryId;
  String _searchQuery = '';
  bool _isLoading = false;
  bool _allowNegativeStock = false;

  PaymentType _paymentType = PaymentType.cash;
  String _customerName = '';
  int? _lastInvoiceId;
  // 🔢 الرقم التجاري للفاتورة المحفوظة آخراً (للعرض في الـ SnackBar وغيره)
  String? _lastInvoiceDisplayNumber;
  
  double _discount = 0.0;
  double _paidAmount = 0.0;

  // 💰 مستوى السعر في الكاشير — نفس مستويات «نوع الفاتورة» في شاشة إنشاء الفاتورة.
  //    أسعار المواد محفوظة في price1..price6 (unit_price قديم ويكون صفراً غالباً).
  static const List<String> priceLevels = ['مفرد', 'مفرد 2', 'منزل', 'جملة', 'جملة 2', 'أخرى'];
  static const String _kPriceLevel = 'pos_price_level';
  String _priceLevel = 'مفرد';
  String get priceLevel => _priceLevel;

  double? _levelPrice(Product p, String level) {
    switch (level) {
      case 'مفرد 2':
        return p.price2;
      case 'منزل':
        return p.price3;
      case 'جملة':
        return p.price4;
      case 'جملة 2':
        return p.price5;
      case 'أخرى':
        return p.price6;
      default:
        return p.price1;
    }
  }

  /// سعر الوحدة الأساسية: سعر المستوى المختار، فإن كان فارغاً فسعر المفرد، ثم unit_price القديم
  double basePriceOf(Product p) {
    for (final v in [_levelPrice(p, _priceLevel), p.price1, p.unitPrice]) {
      if (v != null && v > 0) return v;
    }
    return 0.0;
  }

  double _unitPriceFor(Product p, String unitName) {
    for (final u in getProductUnits(p)) {
      if (u['name'] == unitName) return (u['price'] as num).toDouble();
    }
    return basePriceOf(p);
  }

  /// تغيير مستوى السعر: تُعاد تسعيرة الأسطر التي لم يُعدَّل سعرها يدوياً، ويُحفظ الاختيار
  Future<void> setPriceLevel(String level) async {
    if (!priceLevels.contains(level) || level == _priceLevel) return;
    final before = {for (final it in _cartItems) it.id: _unitPriceFor(it.product, it.selectedUnit)};
    _priceLevel = level;
    for (final it in _cartItems) {
      final was = before[it.id];
      if (was != null && (it.price - was).abs() < 0.0001) {
        it.price = _unitPriceFor(it.product, it.selectedUnit);
      }
    }
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(_kPriceLevel, level);
    } catch (_) {}
  }

  // Getters
  List<Category> get categories => _categories;
  List<Product> get displayedProducts => _displayedProducts;
  List<CartItem> get cartItems => _cartItems;
  int? get selectedCategoryId => _selectedCategoryId;
  bool get isLoading => _isLoading;
  bool get allowNegativeStock => _allowNegativeStock;
  PaymentType get paymentType => _paymentType;
  String get customerName => _customerName;
  int? get lastInvoiceId => _lastInvoiceId;
  /// 🔢 الرقم التجاري المرئي لآخر فاتورة محفوظة (مثل 120260815)
  String? get lastInvoiceDisplayNumber => _lastInvoiceDisplayNumber;
  List<Customer> get filteredCustomers => _filteredCustomers;
  double get discount => _discount;
  double get paidAmount => _paidAmount;
  
  double get subtotal => _cartItems.fold(0, (sum, item) => sum + item.total);
  double get total => (subtotal - _discount).clamp(0, double.infinity);
  double get remainingAmount => (total - _paidAmount).clamp(0, double.infinity);

  Future<void> loadInitialData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final db = await DatabaseService().database;
      
      final catsData = await db.query('categories');
      _categories = catsData.map((e) => Category.fromMap(e)).toList();
      
      final prodsData = await db.query('products');
      _allProducts = prodsData.map((e) => Product.fromMap(e)).toList();
      
      final customersData = await db.query('customers', where: 'is_deleted = 0 OR is_deleted IS NULL');
      _allCustomers = customersData.map((e) => Customer.fromMap(e)).toList();
      
      final settings = await SettingsManager.getAppSettings();
      _allowNegativeStock = settings.allowNegativeStock;

      try {
        final lv = (await SharedPreferences.getInstance()).getString(_kPriceLevel);
        if (lv != null && priceLevels.contains(lv)) _priceLevel = lv;
      } catch (_) {}
      
      _applyFilter();
    } catch (e) {
      debugPrint("Error loading POS data: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectCategory(int? categoryId) {
    _selectedCategoryId = categoryId;
    _applyFilter();
    notifyListeners();
  }
  
  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilter();
    notifyListeners();
  }

  void setPaymentType(PaymentType type) {
    _paymentType = type;
    if (type == PaymentType.cash) {
      _paidAmount = 0.0;
    }
    notifyListeners();
  }

  // Normalize name by removing extra spaces
  String _normalizeName(String name) {
    return name.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  void setCustomerName(String name) {
    _customerName = name;
    if (name.isEmpty) {
      _filteredCustomers = [];
    } else {
      // Normalize input name for comparison
      final normalizedInput = _normalizeName(name).toLowerCase();
      _filteredCustomers = _allCustomers
          .where((c) => _normalizeName(c.name).toLowerCase().contains(normalizedInput))
          .take(5)
          .toList();
    }
    notifyListeners();
  }

  void selectCustomer(Customer customer) {
    _customerName = customer.name;
    _filteredCustomers = [];
    notifyListeners();
  }

  void setDiscount(double value) {
    // Cannot exceed subtotal
    _discount = value.clamp(0, subtotal);
    // Recalculate paid if it now exceeds total
    if (_paidAmount > total) {
      _paidAmount = total;
    }
    notifyListeners();
  }

  void setPaidAmount(double value) {
    // Cannot exceed total
    _paidAmount = value.clamp(0, total);
    notifyListeners();
  }

  void _applyFilter() {
    _displayedProducts = _allProducts.where((p) {
      bool matchesCategory = _selectedCategoryId == null || p.categoryId == _selectedCategoryId;
      bool matchesSearch = _searchQuery.isEmpty || 
          p.name.toLowerCase().contains(_searchQuery.toLowerCase()) || 
          (p.barcode != null && p.barcode!.contains(_searchQuery));
          
      return matchesCategory && matchesSearch;
    }).toList();
  }

  // Get available units for a product
  // السعر من مستوى السعر المختار (price1..price6). الوحدات الأكبر بمضاعف تراكمي
  // (صندوق = 12 كيس × 25 قطعة) كما في شاشة إنشاء الفاتورة.
  List<Map<String, dynamic>> getProductUnits(Product product) {
    final units = <Map<String, dynamic>>[];
    final base = basePriceOf(product);

    // Base unit
    String baseUnitName = product.unit == 'piece' ? 'قطعة' : (product.unit == 'meter' ? 'متر' : product.unit);
    units.add({'name': baseUnitName, 'quantity': 1, 'price': base});

    // Hierarchy units
    double multiplier = 1.0;
    for (final item in product.getUnitHierarchyList()) {
      final unitName = (item['unit_name'] ?? item['name'] ?? '').toString();
      final q = item['quantity'];
      final qty = q is num ? q.toDouble() : (double.tryParse('$q') ?? 1.0);
      multiplier *= qty > 0 ? qty : 1.0;
      if (unitName.isEmpty || units.any((u) => u['name'] == unitName)) continue;
      final own = (item['price'] as num?)?.toDouble();
      units.add({
        'name': unitName,
        'quantity': multiplier.round(),
        'price': (own != null && own > 0) ? own : base * multiplier,
      });
    }

    return units;
  }

  void addToCart(Product product, {String? unitName, double? price, int? unitsInLargeUnit}) {
    final units = getProductUnits(product);
    final selectedUnitName = unitName ?? units.first['name'] as String;
    final selectedPrice = price ?? units.first['price'] as double;
    final selectedUnitsQty = unitsInLargeUnit ?? units.first['quantity'] as int;
    
    // Check if same product with same unit exists
    final existingIndex = _cartItems.indexWhere(
      (item) => item.product.id == product.id && item.selectedUnit == selectedUnitName
    );
    
    if (existingIndex >= 0) {
      _cartItems[existingIndex].quantity++;
    } else {
      _cartItems.add(CartItem(
        id: '${product.id}_$selectedUnitName',
        product: product,
        price: selectedPrice,
        quantity: 1,
        selectedUnit: selectedUnitName,
        unitsInLargeUnit: selectedUnitsQty,
      ));
    }
    notifyListeners();
  }

  /// إضافة منتج بالباركود مباشرة
  /// يبحث عن المنتج بالباركود في الذاكرة وقاعدة البيانات ويضيفه للسلة
  /// يعيد المنتج إذا وُجد وأُضيف، null إذا لم يُعثر عليه
  Future<Product?> addProductByBarcode(String barcode) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return null;
    _lastErrorMessage = null;
    
    // 1. البحث أولاً في قائمة المنتجات المحملة بالذاكرة
    Product? product = _allProducts.cast<Product?>().firstWhere(
      (p) => p?.barcode != null && p!.barcode!.trim() == cleanBarcode,
      orElse: () => null,
    );
    
    // 2. إذا لم يتم العثور عليه في الذاكرة، نبحث في قاعدة البيانات (يشمل جدول product_barcodes والباركود الأساسي)
    if (product == null) {
      try {
        product = await DatabaseService().findProductByBarcode(cleanBarcode);
        if (product != null) {
          final exists = _allProducts.any((p) => p.id == product!.id);
          if (!exists) {
            _allProducts.add(product);
            _applyFilter();
          }
        }
      } catch (e) {
        debugPrint('Error searching product by barcode: $e');
      }
    }
    
    if (product != null) {
      // فحص إذا كان هناك سعر بيع مخصص لهذا الباركود
      double? customPrice;
      try {
        final barcodePriceInfo = await DatabaseService().getBarcodePrice(cleanBarcode);
        final num? sp = barcodePriceInfo['sell_price'];
        if (sp != null && sp > 0) customPrice = sp.toDouble();
      } catch (_) {}

      addToCart(product, price: customPrice);
      return product;
    }

    // 3. ⚖️ باركود ميزان (بادئة + رمز المادة + الوزن/العدد)
    try {
      final hit = await ScaleBarcode.parse(cleanBarcode);
      if (hit != null) {
        final scaled = await DatabaseService().getProductById(hit.productId);
        if (scaled != null) {
          final qty = ScaleBarcode.integralBaseQty(hit);
          if (qty == null) {
            _lastErrorMessage =
                'مادة موزونة (${scaled.name}) بكمية كسرية — الكاشير يقبل كميات صحيحة؛ استخدم «إنشاء فاتورة» لهذه المادة';
            notifyListeners();
            return null;
          }
          if (!_allProducts.any((p) => p.id == scaled.id)) {
            _allProducts.add(scaled);
            _applyFilter();
          }
          addToCart(scaled);
          final idx = _cartItems.indexWhere((i) => i.product.id == scaled.id && i.unitsInLargeUnit == 1);
          if (idx >= 0) {
            // addToCart أضاف 1 (أو زاد 1) ⇒ نضيف الباقي
            _cartItems[idx].quantity += qty - 1;
            notifyListeners();
          }
          return scaled;
        }
      }
    } catch (e) {
      debugPrint('scale barcode: $e');
    }
    return null;
  }

  void updateCartItemUnit(String cartItemId, String newUnit, double newPrice, int unitsQty) {
    final index = _cartItems.indexWhere((item) => item.id == cartItemId);
    if (index >= 0) {
      final item = _cartItems[index];
      // Create new item with updated unit
      _cartItems[index] = CartItem(
        id: '${item.product.id}_$newUnit',
        product: item.product,
        quantity: item.quantity,
        price: newPrice,
        selectedUnit: newUnit,
        unitsInLargeUnit: unitsQty,
      );
      notifyListeners();
    }
  }

  void removeFromCart(String cartItemId) {
    _cartItems.removeWhere((item) => item.id == cartItemId);
    notifyListeners();
  }

  void updateQuantity(String cartItemId, int delta) {
    final index = _cartItems.indexWhere((item) => item.id == cartItemId);
    if (index >= 0) {
      _cartItems[index].quantity += delta;
      if (_cartItems[index].quantity <= 0) {
        _cartItems.removeAt(index);
      }
      notifyListeners();
    }
  }

  void clearCart() {
    _cartItems.clear();
    _customerName = '';
    _paymentType = PaymentType.cash;
    _discount = 0.0;
    _paidAmount = 0.0;
    _filteredCustomers = [];
    notifyListeners();
  }

  String? _lastErrorMessage;
  String? get lastErrorMessage => _lastErrorMessage;

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط (القفل قبل أي انتظار)
  Future<bool> processCheckout() async =>
      (await SaveLock.run(() => _processCheckoutUnlocked(), message: 'جارٍ حفظ البيع…')) ?? false;
  Future<bool> _processCheckoutUnlocked() async {
    _lastErrorMessage = null;
    if (_cartItems.isEmpty) return false;

    _isLoading = true;
    notifyListeners();

    try {
        final items = _cartItems.map((item) => {
            'product_id': item.product.id,
            'product_name': item.product.name,
            'quantity': item.quantity * item.unitsInLargeUnit, // Convert to base units
            'price': item.price,
            'unit': item.selectedUnit,
            'cost_price': item.product.costPrice,
            'sale_type': item.selectedUnit,
            'units_in_large_unit': item.unitsInLargeUnit,
        }).toList();

        final invoiceId = await DatabaseService().createPosInvoice(
            items: items,
            totalAmount: total,
            paymentType: _paymentType == PaymentType.cash ? 'نقد' : 'دين',
            customerName: _customerName.isNotEmpty ? _customerName : null,
            discount: _discount,
            paidAmount: _paymentType == PaymentType.credit ? _paidAmount : total,
            createdByUserId: AuthService().currentUser?.id,
            createdByUsername: AuthService().currentUser?.username,
        );
        
        _lastInvoiceId = invoiceId;

        // جلب الفاتورة المحفوظة للحصول على رقمها التجاري المركّب
        final savedInvoice = await DatabaseService().getInvoiceById(invoiceId);
        final invoiceDisplayNumber = savedInvoice?.formattedInvoiceNumber ?? invoiceId.toString();
        _lastInvoiceDisplayNumber = invoiceDisplayNumber;

        // ⚡ رفع فوري للحزمة المدمجة (فاتورة + معاملاتها + items) عبر Firebase.
        //    fire-and-forget: لا نُعلّق تجربة المستخدم على نتيجة الشبكة؛
        //    عند الفشل يلتقطها المؤقت الدوري لاحقاً (ضمان عدم الفقدان).
        final invoiceUuid = savedInvoice?.invoiceUuid;
        if (invoiceUuid != null && invoiceUuid.isNotEmpty) {
          InvoiceSyncService().syncInvoiceBundleNow(invoiceUuid).then((ok) {
            if (!ok) {
              debugPrint('⚠️ الرفع الفوري تأجّل (سيلتقطه المؤقت الدوري لاحقاً)');
            }
          }).catchError((e) {
            debugPrint('⚠️ الرفع الفوري تأجّل (سيلتقطه المؤقت): $e');
          });
        }
        
        // 🖨️ طباعة إيصال حراري تلقائياً
        try {
          final receiptItems = _cartItems.map((item) => ReceiptItem(
            name: item.product.name,
            quantity: item.quantity,
            price: item.price,
            unit: item.selectedUnit,
          )).toList();
          
          final receipt = ReceiptData(
            invoiceId: invoiceDisplayNumber, // الرقم المركّب كـ String للعرض
            dateTime: DateTime.now(),
            items: receiptItems,
            subtotal: subtotal,
            discount: _discount,
            total: total,
            paidAmount: _paymentType == PaymentType.credit ? _paidAmount : total,
            customerName: _customerName.isNotEmpty ? _customerName : null,
            paymentType: _paymentType == PaymentType.cash ? 'نقد' : 'دين',
          );
          
          await ThermalReceiptService().printReceipt(receipt);
        } catch (e) {
          debugPrint('⚠️ فشل طباعة الإيصال: $e');
        }
        
        await loadInitialData();
        
        clearCart();
        return true;
    } catch(e) {
        _lastErrorMessage = e.toString().replaceAll('Exception: ', '');
        debugPrint("Checkout error: $e");
        return false;
    } finally {
        _isLoading = false;
        notifyListeners();
    }
  }
}
