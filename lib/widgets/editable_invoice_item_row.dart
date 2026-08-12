import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/invoice_item.dart';
import 'formatters.dart';
import '../models/product.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'safe_autocomplete.dart';
import '../services/database_service.dart';

class EditableInvoiceItemRow extends StatefulWidget {
  final InvoiceItem item;
  final int index;
  final Function(InvoiceItem) onItemUpdated;
  final Function(String) onItemRemovedByUid;
  final List<Product> allProducts;
  final bool isViewOnly;
  final bool isPlaceholder;
  final FocusNode? detailsFocusNode;
  final FocusNode? quantityFocusNode;
  final FocusNode? priceFocusNode;
  final VoidCallback? onPriceSubmitted;
  final DatabaseService? databaseService;
  final String? currentCustomerName;
  final String? currentCustomerPhone;

  const EditableInvoiceItemRow({
    Key? key,
    required this.item,
    required this.index,
    required this.onItemUpdated,
    required this.onItemRemovedByUid,
    required this.allProducts,
    required this.isViewOnly,
    required this.isPlaceholder,
    this.detailsFocusNode,
    this.quantityFocusNode,
    this.priceFocusNode,
    this.onPriceSubmitted,
    this.databaseService,
    this.currentCustomerName,
    this.currentCustomerPhone,
  }) : super(key: key);

  @override
  State<EditableInvoiceItemRow> createState() => _EditableInvoiceItemRowState();
}

class _EditableInvoiceItemRowState extends State<EditableInvoiceItemRow> {
  late InvoiceItem _currentItem;
  late TextEditingController _quantityController;
  late TextEditingController _priceController;
  late FocusNode _quantityFocusNode;
  late FocusNode _priceFocusNode;
  late FocusNode _detailsFocusNode;
  late FocusNode _saleTypeFocusNode;
  bool _openSaleTypeDropdown = false;
  bool _openPriceDropdown = false;
  bool _isSaleTypeDropdownOpen = false;
  int _selectedSaleTypeIndex = 0;
  final GlobalKey _saleTypeDropdownKey = GlobalKey();
  OverlayEntry? _saleTypeOverlayEntry;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // 🔧 إصلاح: تحديد الكمية الصحيحة بناءً على نوع البيع
    // ═══════════════════════════════════════════════════════════════════════════
    final quantity = _getCorrectQuantity(widget.item);
    final price = widget.item.appliedPrice;
    
    _quantityController = TextEditingController(
      text: quantity > 0 ? NumberFormat('#,##0.##', 'en_US').format(quantity) : ''
    );
    _priceController = TextEditingController(
      text: price > 0 ? NumberFormat('#,##0.##', 'en_US').format(price) : ''
    );
    
    _detailsFocusNode = widget.detailsFocusNode ?? FocusNode();
    _quantityFocusNode = widget.quantityFocusNode ?? FocusNode();
    _priceFocusNode = widget.priceFocusNode ?? FocusNode();
    _saleTypeFocusNode = FocusNode();
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // 🔧 دالة مساعدة: الحصول على الكمية الصحيحة بناءً على نوع البيع
  // ═══════════════════════════════════════════════════════════════════════════
  double _getCorrectQuantity(InvoiceItem item) {
    // إذا كان نوع البيع قطعة أو متر، استخدم quantityIndividual
    // وإلا استخدم quantityLargeUnit (للفة، كرتون، إلخ)
    if (item.saleType == 'قطعة' || item.saleType == 'متر') {
      return item.quantityIndividual ?? item.quantityLargeUnit ?? 0;
    } else {
      // للوحدات الكبيرة (لفة، كرتون، إلخ) استخدم quantityLargeUnit أولاً
      return item.quantityLargeUnit ?? item.quantityIndividual ?? 0;
    }
  }

  @override
  void didUpdateWidget(covariant EditableInvoiceItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // 🔧 إصلاح مشكلة عدم تزامن البيانات عند التعديلات المتكررة
    // ═══════════════════════════════════════════════════════════════════════════
    // إذا تغير الـ item من الخارج (مثلاً بعد إعادة جلب البيانات من قاعدة البيانات)
    // يجب تحديث الـ _currentItem والمتحكمات
    if (widget.item.uniqueId != oldWidget.item.uniqueId ||
        widget.item.quantityIndividual != oldWidget.item.quantityIndividual ||
        widget.item.quantityLargeUnit != oldWidget.item.quantityLargeUnit ||
        widget.item.appliedPrice != oldWidget.item.appliedPrice ||
        widget.item.saleType != oldWidget.item.saleType ||
        widget.item.productName != oldWidget.item.productName) {
      
      _currentItem = widget.item;
      
      // 🔧 إصلاح: استخدام الدالة المساعدة للحصول على الكمية الصحيحة
      final newQuantity = _getCorrectQuantity(widget.item);
      final newPrice = widget.item.appliedPrice;
      
      // تحديث الكمية
      if (!_quantityFocusNode.hasFocus) {
        final newQuantityText = newQuantity > 0 ? NumberFormat('#,##0.##', 'en_US').format(newQuantity) : '';
        if (_quantityController.text != newQuantityText) {
          _quantityController.text = newQuantityText;
        }
      }
      
      // تحديث السعر
      if (!_priceFocusNode.hasFocus) {
        final newPriceText = newPrice > 0 ? NumberFormat('#,##0.##', 'en_US').format(newPrice) : '';
        if (_priceController.text != newPriceText) {
          _priceController.text = newPriceText;
        }
      }
    }
  }

  @override
  void dispose() {
    _closeSaleTypeDropdown();
    _quantityController.dispose();
    _priceController.dispose();
    if (widget.detailsFocusNode == null) {
      _detailsFocusNode.dispose();
    }
    if (widget.quantityFocusNode == null) {
      _quantityFocusNode.dispose();
    }
    if (widget.priceFocusNode == null) {
      _priceFocusNode.dispose();
    }
    _saleTypeFocusNode.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔧 قائمة منسدلة مخصصة لنوع البيع مع دعم لوحة المفاتيح
  // ═══════════════════════════════════════════════════════════════════════════
  void _openSaleTypeDropdownMenu() {
    if (_isSaleTypeDropdownOpen) return;
    
    final options = _getUnitValues();
    if (options.isEmpty) return;
    
    // تحديد الفهرس الحالي (أصغر وحدة = الأول)
    _selectedSaleTypeIndex = options.indexOf(_currentItem.saleType ?? options.first);
    if (_selectedSaleTypeIndex < 0) _selectedSaleTypeIndex = 0;
    
    final RenderBox? renderBox = _saleTypeDropdownKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    
    _saleTypeOverlayEntry = OverlayEntry(
      builder: (context) => _SaleTypeDropdownOverlay(
        options: options,
        selectedIndex: _selectedSaleTypeIndex,
        position: position,
        size: size,
        onSelect: (value) {
          _closeSaleTypeDropdown();
          _updateSaleType(value);
          // الانتقال للسعر بعد الاختيار
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _priceFocusNode.requestFocus();
          });
        },
        onClose: () {
          _closeSaleTypeDropdown();
        },
        onIndexChanged: (index) {
          _selectedSaleTypeIndex = index;
        },
      ),
    );
    
    Overlay.of(context).insert(_saleTypeOverlayEntry!);
    setState(() {
      _isSaleTypeDropdownOpen = true;
    });
  }
  
  void _closeSaleTypeDropdown() {
    _saleTypeOverlayEntry?.remove();
    _saleTypeOverlayEntry = null;
    if (mounted) {
      setState(() {
        _isSaleTypeDropdownOpen = false;
      });
    }
  }

  List<String> _getUnitValues() {
    Product? product = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    List<String> options = ['قطعة'];
    if (product.unit == 'piece' &&
        product.unitHierarchy != null &&
        product.unitHierarchy!.isNotEmpty) {
      try {
        List<dynamic> hierarchy =
            json.decode(product.unitHierarchy!.replaceAll("'", '"'));
        options.addAll(hierarchy
            .map((e) => (e['unit_name'] ?? e['name'] ?? '').toString()));
      } catch (e) {}
    } else if (product.unit == 'meter' && product.lengthPerUnit != null) {
      options = ['متر'];
      options.add('لفة');
    } else if (product.unit != 'piece' && product.unit != 'meter') {
      options = [product.unit];
    }
    options = options.where((e) => e != null && e.isNotEmpty).toSet().toList();
    if (_currentItem.saleType != null &&
        _currentItem.saleType!.isNotEmpty &&
        !options.contains(_currentItem.saleType)) {
      options.add(_currentItem.saleType!);
    }
    return options;
  }

  List<DropdownMenuItem<String>> _getUnitOptions() {
    return _getUnitValues()
        .map((unit) => DropdownMenuItem(
              value: unit,
              child: Text(unit, textAlign: TextAlign.center),
            ))
        .toList();
  }

  void _updateQuantity(String value) {
    double? newQuantity = double.tryParse(value.replaceAll(',', ''));
    if (newQuantity == null || newQuantity <= 0) return;
    
    setState(() {
      if (_currentItem.saleType == 'قطعة' || _currentItem.saleType == 'متر') {
        _currentItem = _currentItem.copyWith(
          quantityIndividual: newQuantity,
          quantityLargeUnit: null,
          itemTotal: newQuantity * _currentItem.appliedPrice,
        );
      } else {
        _currentItem = _currentItem.copyWith(
          quantityLargeUnit: newQuantity,
          quantityIndividual: null,
          itemTotal: newQuantity * _currentItem.appliedPrice,
        );
      }
      _quantityController.text = NumberFormat('#,##0.##', 'en_US').format(newQuantity);
      _priceController.text = NumberFormat('#,##0.##', 'en_US').format(_currentItem.appliedPrice);
      widget.onItemUpdated(_currentItem);
    });
  }

  void _updateSaleType(String newType) {
    Product? product = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    double conversionFactor = 1.0;
    if (product != null) {
      if (product.unit == 'piece' && newType != 'قطعة') {
        if (product.unitHierarchy != null &&
            product.unitHierarchy!.isNotEmpty) {
          try {
            List<dynamic> hierarchy =
                json.decode(product.unitHierarchy!.replaceAll("'", '"'));
            for (var unit in hierarchy) {
              if ((unit['unit_name'] ?? unit['name']) == newType) {
                conversionFactor = (unit['quantity'] as num).toDouble();
                break;
              }
            }
          } catch (e) {}
        }
      } else if (product.unit == 'meter' && newType == 'لفة') {
        conversionFactor = product.lengthPerUnit ?? 1.0;
      }
    }
    setState(() {
      double newAppliedPrice;
      if ((product?.unit == 'piece' && newType != 'قطعة') ||
          (product?.unit == 'meter' && newType == 'لفة')) {
        newAppliedPrice = _currentItem.appliedPrice * conversionFactor;
      } else if ((product?.unit == 'piece' &&
              _currentItem.saleType != 'قطعة' &&
              newType == 'قطعة') ||
          (product?.unit == 'meter' &&
              _currentItem.saleType == 'لفة' &&
              newType == 'متر')) {
        newAppliedPrice = _currentItem.appliedPrice / conversionFactor;
      } else {
        newAppliedPrice = _currentItem.appliedPrice;
      }
      double quantity = _currentItem.quantityIndividual ??
          _currentItem.quantityLargeUnit ??
          1;
      _currentItem = _currentItem.copyWith(
        saleType: newType,
        appliedPrice: newAppliedPrice,
        unitsInLargeUnit: conversionFactor != 1.0 ? conversionFactor : null,
        itemTotal: quantity * newAppliedPrice,
        quantityIndividual:
            (newType == 'قطعة' || newType == 'متر') ? quantity : null,
        quantityLargeUnit:
            (newType != 'قطعة' && newType != 'متر') ? quantity : null,
      );
      _quantityController.text = NumberFormat('#,##0.##', 'en_US').format(quantity);
      _priceController.text =
          (newAppliedPrice > 0) ? NumberFormat('#,##0.##', 'en_US').format(newAppliedPrice) : '';
      widget.onItemUpdated(_currentItem);
      // FocusScope.of(context).requestFocus(_priceFocusNode); // <-- Removed auto focus to price here to allow user to confirm with Enter
      setState(() {
        _openPriceDropdown = true;
      });
    });
  }

  void _updatePrice(String value) {
    double? newPrice = double.tryParse(value.replaceAll(',', ''));
    if (newPrice == null || newPrice <= 0) return;
    setState(() {
      double quantity = _currentItem.quantityIndividual ??
          _currentItem.quantityLargeUnit ??
          1;
      _currentItem = _currentItem.copyWith(
        appliedPrice: newPrice,
        itemTotal: quantity * newPrice,
      );
      _priceController.text = NumberFormat('#,##0.##', 'en_US').format(newPrice);
      widget.onItemUpdated(_currentItem);
    });
  }

  String formatCurrency(num value) {
    return NumberFormat('#,##0.##', 'en_US').format(value);
  }

  // الحصول على ID المنتج من قائمة المنتجات
  int? _getProductId() {
    if (_currentItem.productName.isEmpty) return null;
    final product = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    return product.id;
  }

  // بناء حقل إدخال بحدود مربعة
  Widget _buildSquareInputField({
    required Widget child,
    bool showBorder = true,
  }) {
    return Container(
      decoration: showBorder
          ? BoxDecoration(
              border: Border.all(color: Colors.grey.shade400, width: 1),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ═══════════════════════════════════════════════════════════════════════════
    // 🔧 إصلاح: استخدام _currentItem دائماً لضمان عرض البيانات المحدثة
    // ═══════════════════════════════════════════════════════════════════════════
    final displayItem = _currentItem;
    final productId = _getProductId();

    // 🔴 التحقق من المخزون
    bool isOutOfStock = false;
    double currentStock = 0.0;
    
    if (productId != null) {
      final product = widget.allProducts.firstWhere(
        (p) => p.id == productId, 
        orElse: () => Product(name: '', unit: '', unitPrice: 0, price1: 0, createdAt: DateTime.now(), lastModifiedAt: DateTime.now())
      );
      
      currentStock = product.stockQuantity;
      
      // حساب الكمية المباعة بالوحدة الأساسية
      double quantitySoldInBaseUnit;
      double enteredQuantity = _getCorrectQuantity(displayItem);
      
      if (displayItem.saleType == 'قطعة' || displayItem.saleType == 'متر' || displayItem.saleType == product.unit) {
         quantitySoldInBaseUnit = enteredQuantity;
      } else {
         // تحويل الوحدات الكبيرة إلى الوحدة الأساسية
         // سنفترض هنا عملية تقريبية إذا لم تتوفر التسلسل الهرمي الدقيق في هذه اللحظة،
         // لكن الأفضل استخدام unitsInLargeUnit إذا كان محسوباً
         double factor = displayItem.unitsInLargeUnit ?? 1.0;
         quantitySoldInBaseUnit = enteredQuantity * factor;
      }
      
      // إذا كان المخزون 0 أو أقل، نعتبره نافذاً (حسب طلب المستخدم: إذا المخزون 0، يظهر تحذير أحمر)
      // المستخدم قال: "الذي اصبح المخزون له صفر... تظهر عليه لون احمر"
      // هذا يعني إذا *بعد* البيع سيصبح < 0؟ أو إذا هو *أصلاً* 0؟
      // التوضيح: "المنتج الذي اصبح المخزون له صفر تظهر عليه... احمر... لكن يستطيع المستخدم بيعه"
      // التوضيح 2: "ما دام المخزون صفر لا ينقص"
      // سنفعل التحذير إذا كان المخزون الحالي <= 0
      
      if (currentStock <= 0) {
        isOutOfStock = true;
      }
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 0.0),
      decoration: BoxDecoration(
        color: isOutOfStock ? Colors.red.shade50 : null, // 🔴 خلفية حمراء خفيفة
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
          left: isOutOfStock ? const BorderSide(color: Colors.red, width: 4) : BorderSide.none, // 🔴 شريط أحمر جانبي
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        child: Row(
          children: [
            // عمود التسلسل (ت)
            Expanded(
                flex: 1,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                     Text((widget.index + 1).toString(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium),
                     if (isOutOfStock)
                       const Padding(
                         padding: EdgeInsets.only(right: 4.0),
                         child: Tooltip(
                           message: 'المخزون نافذ (0)',
                           child: Icon(Icons.error_outline, color: Colors.red, size: 16),
                         ),
                       )
                  ],
                )),
            // عمود المبلغ
            Expanded(
                flex: 2,
                child: widget.isViewOnly
                    ? Text(
                        NumberFormat('#,##0.##', 'en_US').format(displayItem.itemTotal),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary),
                      )
                    : Text(formatCurrency(_currentItem.itemTotal),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary))),
            // عمود ID
            Expanded(
              flex: 2,
              child: _buildSquareInputField(
                child: Text(
                  productId?.toString() ?? '',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            // عمود التفاصيل (اسم المنتج)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: _buildSquareInputField(
                  child: widget.isViewOnly
                      ? Text(displayItem.productName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium)
                      : Builder(
                          builder: (context) {
                            TextEditingController? detailsController;
                            return SafeAutocomplete<String>(
                              initialValue:
                                  TextEditingValue(text: widget.item.productName),
                              optionsBuilder:
                                  (TextEditingValue textEditingValue) {
                                if (textEditingValue.text == '') {
                                  return const Iterable<String>.empty();
                                }
                                return widget.allProducts
                                    .map((p) => p.name)
                                    .where((option) =>
                                        option.contains(textEditingValue.text));
                              },
                              fieldViewBuilder: (context, controller, focusNode,
                                  onFieldSubmitted) {
                                detailsController = controller;
                                return TextField(
                                  controller: controller,
                                  focusNode: _detailsFocusNode,
                                  enabled: !widget.isViewOnly,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 8),
                                    isDense: true,
                                  ),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  onChanged: (val) {
                                    _currentItem =
                                        _currentItem.copyWith(productName: val);
                                  },
                                  onSubmitted: (val) {
                                    onFieldSubmitted();
                                  },
                                );
                              },
                              onSelected: (String selection) {
                                // الحصول على المنتج المحدد لتعيين نوع البيع الافتراضي
                                final selectedProduct = widget.allProducts.firstWhere(
                                  (p) => p.name == selection,
                                  orElse: () => Product(
                                    id: null,
                                    name: '',
                                    unit: 'piece',
                                    unitPrice: 0,
                                    price1: 0,
                                    createdAt: DateTime.now(),
                                    lastModifiedAt: DateTime.now(),
                                  ),
                                );
                                
                                // تحديد نوع البيع الافتراضي (أصغر وحدة)
                                String defaultSaleType = 'قطعة';
                                if (selectedProduct.unit == 'meter') {
                                  defaultSaleType = 'متر';
                                }
                                
                                setState(() {
                                  _currentItem = _currentItem.copyWith(
                                    productName: selection,
                                    saleType: defaultSaleType,
                                    appliedPrice: selectedProduct.price1 ?? selectedProduct.unitPrice,
                                    costPrice: selectedProduct.costPrice,
                                  );
                                  widget.onItemUpdated(_currentItem);
                                });
                                detailsController?.text = selection;
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  _quantityFocusNode.requestFocus();
                                });
                              },
                            );
                          },
                        ),
                ),
              ),
            ),
            // عمود العدد
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: _buildSquareInputField(
                  child: widget.isViewOnly
                      ? Text(
                          // 🔧 إصلاح: استخدام الدالة المساعدة للحصول على الكمية الصحيحة
                          NumberFormat('#,##0.##', 'en_US').format(_getCorrectQuantity(displayItem)),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      : TextFormField(
                          controller: _quantityController,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            ThousandSeparatorDecimalInputFormatter(),
                          ],
                          enabled: !widget.isViewOnly,
                          onChanged: _updateQuantity,
                          focusNode: _quantityFocusNode,
                          onFieldSubmitted: (val) {
                            // عند الضغط على Enter في حقل العدد
                            // انتقل إلى حقل الوحدة وافتح القائمة المنسدلة
                            _saleTypeFocusNode.requestFocus();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _openSaleTypeDropdownMenu();
                            });
                          },
                          style: Theme.of(context).textTheme.bodyMedium,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            isDense: true,
                          ),
                        ),
                ),
              ),
            ),
            // عمود نوع البيع
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: _buildSquareInputField(
                  child: widget.isViewOnly
                      ? Text(
                          displayItem.saleType ?? '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      : Focus(
                          focusNode: _saleTypeFocusNode,
                          onFocusChange: (hasFocus) {
                            if (!hasFocus && _isSaleTypeDropdownOpen) {
                              _closeSaleTypeDropdown();
                            }
                          },
                          onKeyEvent: (node, event) {
                            if (event is! KeyDownEvent) return KeyEventResult.ignored;

                            if (event.logicalKey.keyLabel == 'Enter') {
                                // إذا القائمة مفتوحة، أغلقها وانتقل للسعر
                                if (_isSaleTypeDropdownOpen) {
                                  _closeSaleTypeDropdown();
                                }
                                _priceFocusNode.requestFocus();
                                return KeyEventResult.handled;
                            } else if (event.logicalKey.keyLabel == 'Arrow Down') {
                                // الوحدة التالية
                                final options = _getUnitValues();
                                if (options.isNotEmpty) {
                                    int currentIndex = options.indexOf(_currentItem.saleType ?? '');
                                    int nextIndex = (currentIndex + 1) % options.length;
                                    _updateSaleType(options[nextIndex]);
                                }
                                return KeyEventResult.handled;
                            } else if (event.logicalKey.keyLabel == 'Arrow Up') {
                                // الوحدة السابقة
                                final options = _getUnitValues();
                                if (options.isNotEmpty) {
                                    int currentIndex = options.indexOf(_currentItem.saleType ?? '');
                                    int prevIndex = (currentIndex - 1 + options.length) % options.length;
                                    _updateSaleType(options[prevIndex]);
                                }
                                return KeyEventResult.handled;
                            } else if (event.logicalKey.keyLabel == ' ') {
                                // فتح القائمة بالمسافة
                                _openSaleTypeDropdownMenu();
                                return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: GestureDetector(
                            key: _saleTypeDropdownKey,
                            onTap: () {
                              _saleTypeFocusNode.requestFocus();
                              _openSaleTypeDropdownMenu();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                              decoration: BoxDecoration(
                                border: _saleTypeFocusNode.hasFocus
                                    ? Border.all(color: Colors.red, width: 2)
                                    : null,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _currentItem.saleType ?? '',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: _saleTypeFocusNode.hasFocus ? Colors.red : null,
                                        fontWeight: _saleTypeFocusNode.hasFocus ? FontWeight.bold : null,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down,
                                    size: 20,
                                    color: _saleTypeFocusNode.hasFocus ? Colors.red : Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            // عمود السعر
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: _buildSquareInputField(
                  child: widget.isViewOnly
                      ? Text(
                          NumberFormat('#,##0.##', 'en_US').format(displayItem.appliedPrice),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      : TextFormField(
                          controller: _priceController,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            ThousandSeparatorDecimalInputFormatter(),
                          ],
                          enabled: !widget.isViewOnly,
                          onChanged: _updatePrice,
                          focusNode: _priceFocusNode,
                          onFieldSubmitted: (val) {
                            // عند الضغط على Enter في حقل السعر، انتقل للصف التالي
                            widget.onPriceSubmitted?.call();
                            // العودة للتركيز على حقل العدد للصف الجديد أو الحالي إذا تطلب الأمر
                            // (يتم التعامل مع إنشاء صف جديد في create_invoice_screen)
                          },
                          style: Theme.of(context).textTheme.bodyMedium,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            isDense: true,
                          ),
                        ),
                ),
              ),
            ),
            // عمود عدد الوحدات
            Expanded(
              flex: 2,
              child: widget.isViewOnly
                  ? ((displayItem.saleType == 'قطعة' ||
                          displayItem.saleType == 'متر')
                      ? const SizedBox.shrink()
                      : Text(
                          displayItem.unitsInLargeUnit?.toStringAsFixed(0) ??
                              '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium))
                  : (_currentItem.saleType == 'قطعة' ||
                          _currentItem.saleType == 'متر')
                      ? const SizedBox.shrink()
                      : Text(
                          _currentItem.unitsInLargeUnit?.toStringAsFixed(0) ??
                              '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium),
            ),
            // زر الحذف
            if (!widget.isViewOnly && !widget.isPlaceholder)
              SizedBox(
                width: 40,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 24),
                  onPressed: () => widget.onItemRemovedByUid(widget.item.uniqueId),
                  tooltip: 'حذف الصنف',
                ),
              )
            else
              const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }

  // دالة لاختيار نوع البيع الافتراضي (أصغر وحدة) والانتقال للسعر (لم تعد مستخدمة في onFieldSubmitted للكمية)
  void _selectDefaultSaleTypeAndMoveToPrice() {
     // ... logic kept or removed as needed, currently not called by Quantity Enter anymore ...
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🔧 Widget مخصص للقائمة المنسدلة مع دعم لوحة المفاتيح
// ═══════════════════════════════════════════════════════════════════════════
class _SaleTypeDropdownOverlay extends StatefulWidget {
  final List<String> options;
  final int selectedIndex;
  final Offset position;
  final Size size;
  final Function(String) onSelect;
  final VoidCallback onClose;
  final Function(int) onIndexChanged;

  const _SaleTypeDropdownOverlay({
    required this.options,
    required this.selectedIndex,
    required this.position,
    required this.size,
    required this.onSelect,
    required this.onClose,
    required this.onIndexChanged,
  });

  @override
  State<_SaleTypeDropdownOverlay> createState() => _SaleTypeDropdownOverlayState();
}

class _SaleTypeDropdownOverlayState extends State<_SaleTypeDropdownOverlay> {
  late int _currentIndex;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.selectedIndex;
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // خلفية شفافة للإغلاق عند النقر خارج القائمة
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(color: Colors.transparent),
          ),
        ),
        // القائمة المنسدلة
        Positioned(
          left: widget.position.dx,
          top: widget.position.dy + widget.size.height,
          width: widget.size.width,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(4),
            child: Focus(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;

                if (event.logicalKey.keyLabel == 'Arrow Down') {
                  setState(() {
                    _currentIndex = (_currentIndex + 1) % widget.options.length;
                    widget.onIndexChanged(_currentIndex);
                  });
                  return KeyEventResult.handled;
                } else if (event.logicalKey.keyLabel == 'Arrow Up') {
                  setState(() {
                    _currentIndex = (_currentIndex - 1 + widget.options.length) % widget.options.length;
                    widget.onIndexChanged(_currentIndex);
                  });
                  return KeyEventResult.handled;
                } else if (event.logicalKey.keyLabel == 'Enter') {
                  widget.onSelect(widget.options[_currentIndex]);
                  return KeyEventResult.handled;
                } else if (event.logicalKey.keyLabel == 'Escape') {
                  widget.onClose();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: widget.options.length,
                  itemBuilder: (context, index) {
                    final isSelected = index == _currentIndex;
                    return InkWell(
                      onTap: () => widget.onSelect(widget.options[index]),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.red.shade50 : Colors.white,
                          border: isSelected
                              ? Border.all(color: Colors.red, width: 2)
                              : null,
                        ),
                        child: Text(
                          widget.options[index],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isSelected ? Colors.red : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
