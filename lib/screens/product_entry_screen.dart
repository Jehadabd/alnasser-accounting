// screens/product_entry_screen.dart
//
// 📦 «إدخال بضاعة» — تعريف مادة جديدة.
//
// الأقسام: البيانات الأساسية • الوحدات • الأسعار • المخزون
// (عمودان على الشاشات العريضة، عمود واحد على الضيقة).
// لوحة المفاتيح: Enter ينقل للحقل التالي • Ctrl+S يحفظ.
//
// ⚠️ مسار الحفظ لم يتغير: addCustomUnit للوحدات الجديدة ثم
// DatabaseService.insertProduct ثم addProductBarcode للباركودات الإضافية،
// وبالحقول نفسها. التحسينات هنا في الواجهة والتحقق فقط.

import '../services/save_lock.dart'; // 🔒 قفل الحفظ
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/category.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import '../services/internal_barcode.dart';
import '../erp/inventory/barcode_labels.dart' show BarcodeLabels;
import '../widgets/camera_barcode_scanner_dialog.dart';
import '../widgets/formatters.dart';
import '../widgets/product/category_management_dialog.dart';
import 'product_entry/pe_widgets.dart';
import '../erp/control/landed_cost_dialog.dart'; // 🚢 مصاريف الشحن والجمارك
import '../erp/control/landed_cost_service.dart';

// --- Theme Colors from Design ---
const Color kPrimaryColor = Color(0xFF5D5FEF); // Purple/Indigo
const Color kBackgroundColor = Color(0xFFF5F7FA); // Light Gray
const Color kCardColor = Colors.white;
const Color kTextColor = Color(0xFF1E1E2E);
const Color kInputFillColor = Color(0xFFF8F9FA); // Very light gray for inputs

const Color _kUnitsColor = Color(0xFF059669);
const Color _kPricesColor = Color(0xFF4F46E5);
const Color _kStockColor = Color(0xFF0891B2);
const Color _kBarcodeColor = Color(0xFFEA580C);

/// شريحة سعر (مفرد، مفرد 2، منزل، جملة، جملة 2، أخرى).
class _PriceTier {
  _PriceTier({
    required this.label,
    required this.hint,
    required this.icon,
    required this.color,
    required this.controller,
    required this.focus,
    this.isRequired = false,
  });

  final String label;
  final String hint;
  final IconData icon;
  final Color color;
  final TextEditingController controller;
  final FocusNode focus;
  final bool isRequired;
}

/// سطر «وحدة أكبر»: اسمها وكم من الوحدة السابقة بداخلها.
/// المتحكمات ثابتة لكل سطر (لا تُنشأ من جديد في كل بناء).
class _UnitRow {
  _UnitRow(this.id, {String name = '', String qty = ''})
      : nameController = TextEditingController(text: name),
        qtyController = TextEditingController(text: qty);

  final int id;
  final TextEditingController nameController;
  final TextEditingController qtyController;
  final FocusNode nameFocus = FocusNode();
  final FocusNode qtyFocus = FocusNode();

  String get name => nameController.text.trim();
  double get qty => peParseNumber(qtyController.text);

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    nameFocus.dispose();
    qtyFocus.dispose();
  }
}

/// سطر باركود إضافي (متغير: لون / نكهة / حجم) مع سعر خاص اختياري.
class _BarcodeRow {
  _BarcodeRow(this.id);

  final int id;
  final TextEditingController barcodeController = TextEditingController();
  final TextEditingController labelController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final FocusNode barcodeFocus = FocusNode();
  final FocusNode labelFocus = FocusNode();
  final FocusNode priceFocus = FocusNode();

  void dispose() {
    barcodeController.dispose();
    labelController.dispose();
    priceController.dispose();
    barcodeFocus.dispose();
    labelFocus.dispose();
    priceFocus.dispose();
  }
}

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
  final _nameFieldKey = GlobalKey<FormFieldState<String>>();
  final _scrollController = ScrollController();

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

  // --- Stock / Alert Controllers ---
  final _stockController = TextEditingController();
  final _alertQtyController = TextEditingController();
  final _alertUnitController = TextEditingController();

  // --- Focus (Enter ينقل للحقل التالي) ---
  final _nameFocus = FocusNode();
  final _unitFocus = FocusNode();
  final _barcodeFocus = FocusNode();
  final _weightFocus = FocusNode();
  final _costFocus = FocusNode();
  final _stockFocus = FocusNode();
  final _alertQtyFocus = FocusNode();
  final _saveButtonFocus = FocusNode();

  late final List<_PriceTier> _tiers = [
    _PriceTier(
      label: 'مفرد',
      hint: 'سعر البيع للزبون العادي',
      icon: Icons.person_outline_rounded,
      color: kPrimaryColor,
      controller: _basePriceController,
      focus: FocusNode(),
      isRequired: true,
    ),
    _PriceTier(
      label: 'مفرد 2',
      hint: 'سعر مفرد بديل',
      icon: Icons.storefront_outlined,
      color: const Color(0xFF4F46E5),
      controller: _price2Controller,
      focus: FocusNode(),
    ),
    _PriceTier(
      label: 'منزل',
      hint: 'سعر زبائن المنازل',
      icon: Icons.home_outlined,
      color: const Color(0xFFD97706),
      controller: _price3Controller,
      focus: FocusNode(),
    ),
    _PriceTier(
      label: 'جملة',
      hint: 'للمحلات والمتاجر',
      icon: Icons.inventory_2_outlined,
      color: const Color(0xFF059669),
      controller: _price4Controller,
      focus: FocusNode(),
    ),
    _PriceTier(
      label: 'جملة 2',
      hint: 'كبار العملاء',
      icon: Icons.workspace_premium_outlined,
      color: const Color(0xFF0284C7),
      controller: _price5Controller,
      focus: FocusNode(),
    ),
    _PriceTier(
      label: 'أخرى',
      hint: 'عروض أو تسعيرة خاصة',
      icon: Icons.stars_outlined,
      color: const Color(0xFF7C3AED),
      controller: _price6Controller,
      focus: FocusNode(),
    ),
  ];

  static const List<String> _baseUnitSuggestions = ['قطعة', 'متر', 'لفة', 'علبة', 'طقم', 'كيلو'];
  static const List<String> _largerUnitSuggestions = [
    'كرتون',
    'باكيت',
    'درزن',
    'صندوق',
    'شدة',
    'لفة',
    'كيس',
    'كونية',
  ];

  // --- State Variables ---
  List<Category> _categories = [];
  bool _categoriesFailed = false;
  int? _selectedCategoryId;

  /// الوحدات كما رجعت من قاعدة البيانات (تحدد متى تُسجَّل وحدة جديدة عند الحفظ — كما كان).
  List<String> _dbUnits = [];

  /// الوحدات المعروضة للاختيار (من القاعدة + الافتراضية، بلا مفاتيح داخلية).
  List<String> _availableUnits = _mergeUnits(const []);

  bool _isWeighable = false;
  bool _hasExpiry = false;
  DateTime? _expiryDate;
  int _totalProductsCount = 0;

  final List<_UnitRow> _unitRows = [];
  final List<_BarcodeRow> _barcodeRows = [];
  int _rowSeq = 0;
  bool _invoiceUnitSuggested = false;

  bool _saving = false;

  /// 🚢 مصاريف شحن مطبّقة على الكلفة (تُسجَّل بعد نجاح الحفظ)
  LandedPlan? _landed;
  bool _submitted = false;
  int _savedCount = 0;

  // فحص تكرار الاسم
  Timer? _nameCheckTimer;
  bool _checkingName = false;
  String _lastCheckedName = '';
  String? _duplicateNameOf;

  // فحص الباركود المستعمل
  Timer? _barcodeCheckTimer;
  String? _barcodeUsedBy;

  double? _lastMarkupPercent;

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
      _baseCostController.text = peFormatNumber(widget.initialCost!);
    }
    // افتراضياً نضع وحدة الفاتورة كوحدة أساسية، والمستخدم يغيرها
    if (widget.initialUnit != null && widget.initialUnit!.trim().isNotEmpty) {
      _baseUnitNameController.text = widget.initialUnit!.trim();
    }
    if (widget.initialQty != null) {
      _stockController.text = peFormatNumber(widget.initialQty!);
    }

    _baseUnitNameController.addListener(_onBaseUnitChanged);
    // إن غيّر المستخدم وحدة الفاتورة: تُقترح كوحدة أكبر عند مغادرة الحقل (لا مع أول حرف)
    _unitFocus.addListener(_onUnitFocusChanged);

    if (_nameController.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkDuplicateName(_nameController.text);
      });
    }
  }

  @override
  void dispose() {
    _nameCheckTimer?.cancel();
    _barcodeCheckTimer?.cancel();
    _baseUnitNameController.removeListener(_onBaseUnitChanged);
    _unitFocus.removeListener(_onUnitFocusChanged);

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

    for (final t in _tiers) {
      t.focus.dispose();
    }
    _nameFocus.dispose();
    _unitFocus.dispose();
    _barcodeFocus.dispose();
    _weightFocus.dispose();
    _costFocus.dispose();
    _stockFocus.dispose();
    _alertQtyFocus.dispose();
    _saveButtonFocus.dispose();

    for (final r in _unitRows) {
      r.dispose();
    }
    for (final r in _barcodeRows) {
      r.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // التحميل (مع تحمّل الأخطاء: الشاشة تعمل حتى لو فشل تحميل الوحدات/الأقسام)
  // ═══════════════════════════════════════════════════════════════════════

  static List<String> _mergeUnits(List<String> dbUnits) {
    final out = <String>[];
    for (final u in [...dbUnits, ...DatabaseService.defaultArabicUnits]) {
      final t = u.trim();
      // piece/meter مفاتيح داخلية تُحفظ بها قطعة/متر — لا تُعرض للمستخدم
      if (t.isEmpty || t == 'piece' || t == 'meter' || out.contains(t)) continue;
      out.add(t);
    }
    return out;
  }

  Future<void> _loadUnits() async {
    List<String> units = const [];
    try {
      units = await DatabaseService().getAllUnits();
    } catch (e) {
      debugPrint('⚠️ [إدخال بضاعة] تعذّر تحميل الوحدات — تُستعمل القائمة الافتراضية: $e');
    }
    if (!mounted) return;
    setState(() {
      _dbUnits = units;
      _availableUnits = _mergeUnits(units);
    });
  }

  Future<void> _loadCategories({bool selectNew = false}) async {
    try {
      final before = _categories.map((c) => c.id).toSet();
      final cats = await DatabaseService().getAllCategories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _categoriesFailed = false;
        if (selectNew) {
          final added = cats.where((c) => c.id != null && !before.contains(c.id)).toList();
          if (added.length == 1) _selectedCategoryId = added.first.id;
        }
        if (_selectedCategoryId != null && !cats.any((c) => c.id == _selectedCategoryId)) {
          _selectedCategoryId = null;
        }
      });
    } catch (e) {
      debugPrint('⚠️ [إدخال بضاعة] تعذّر تحميل الأقسام: $e');
      if (mounted) setState(() => _categoriesFailed = true);
    }
  }

  Future<void> _loadProductCount() async {
    try {
      final products = await DatabaseService().getAllProducts();
      if (mounted) setState(() => _totalProductsCount = products.length);
    } catch (e) {
      debugPrint('⚠️ [إدخال بضاعة] تعذّر حساب عدد المواد: $e');
    }
  }

  void _addNewCategory() {
    showDialog(
      context: context,
      builder: (context) => const CategoryManagementDialog(),
    ).then((result) {
      if (mounted) _loadCategories(selectNew: result == true);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // مساعدات
  // ═══════════════════════════════════════════════════════════════════════

  double _parse(String val) {
    if (val.isEmpty) return 0.0;
    return double.tryParse(val.replaceAll(',', '')) ?? 0.0;
  }

  void _setText(TextEditingController c, String text) {
    c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  String get _baseUnitDisplay {
    final t = _baseUnitNameController.text.trim();
    return t.isEmpty ? 'قطعة' : t;
  }

  void _showSnack(String message, {Color? color, int seconds = 4}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: seconds),
      ));
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'إلغاء',
    Color color = kPrimaryColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  bool _hasUnsavedInput() {
    final controllers = <TextEditingController>[
      _nameController,
      _barcodeController,
      _baseCostController,
      _baseWeightController,
      _stockController,
      _alertQtyController,
      ..._tiers.map((t) => t.controller),
    ];
    if (controllers.any((c) => c.text.trim().isNotEmpty)) return true;
    return _unitRows.isNotEmpty || _barcodeRows.isNotEmpty;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // الوحدة الأساسية والوحدات الأكبر
  // ═══════════════════════════════════════════════════════════════════════

  void _onBaseUnitChanged() {
    if (mounted) setState(() {});
  }

  void _onUnitFocusChanged() {
    if (!_unitFocus.hasFocus) _checkUnitHierarchySuggestion();
  }

  /// إن غيّر المستخدم الوحدة الأساسية عن وحدة الفاتورة، تُضاف وحدة الفاتورة
  /// كوحدة أكبر (مرة واحدة) ليحدد كم تحتوي.
  void _checkUnitHierarchySuggestion() {
    if (!mounted || _invoiceUnitSuggested) return;
    final currentBase = _baseUnitNameController.text.trim();
    final invoiceUnit = widget.initialUnit?.trim();

    if (invoiceUnit == null || invoiceUnit.isEmpty || currentBase.isEmpty || currentBase == invoiceUnit) return;
    if (_unitRows.any((r) => r.name == invoiceUnit)) return;

    _invoiceUnitSuggested = true;
    final row = _UnitRow(++_rowSeq, name: invoiceUnit);
    setState(() => _unitRows.add(row));
    _showSnack(
      'أُضيفت وحدة الفاتورة «$invoiceUnit» إلى الوحدات الأكبر لأنك غيّرت الوحدة الأساسية — حدّد كم $currentBase بداخلها.',
      color: Colors.blue.shade700,
      seconds: 6,
    );
  }

  void _addUnitRow([String name = '']) {
    final row = _UnitRow(++_rowSeq, name: name);
    setState(() => _unitRows.add(row));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (name.isEmpty ? row.nameFocus : row.qtyFocus).requestFocus();
    });
  }

  void _removeUnitRow(_UnitRow row) {
    setState(() {
      _unitRows.remove(row);
      if (_alertUnitController.text.trim().isNotEmpty && _alertUnitController.text.trim() == row.name) {
        _alertUnitController.clear();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  /// [(اسم الوحدة، كم وحدة أساسية بداخلها)] للأسطر المكتملة بالترتيب.
  List<MapEntry<String, double>> _levelFactors() {
    final out = <MapEntry<String, double>>[];
    double factor = 1;
    for (final r in _unitRows) {
      if (r.name.isEmpty || r.qty <= 0) break;
      factor *= r.qty;
      out.add(MapEntry(r.name, factor));
    }
    return out;
  }

  /// توزيع الرصيد على الوحدات: «= 2 كرتون + 4 قطعة».
  String? _stockBreakdown(double qty) {
    final levels = _levelFactors();
    if (qty <= 0 || levels.isEmpty) return null;
    double remaining = qty;
    final parts = <String>[];
    for (final level in levels.reversed) {
      if (level.value <= 1) continue;
      final n = (remaining / level.value + 1e-9).floor();
      if (n > 0) {
        parts.add('${peFormatNumber(n.toDouble())} ${level.key}');
        remaining -= n * level.value;
      }
    }
    if (parts.isEmpty) return null;
    if (remaining > 1e-9) {
      parts.add('${peFormatNumber((remaining * 1000).round() / 1000)} $_baseUnitDisplay');
    }
    return '= ${parts.join(' + ')}';
  }

  Iterable<String> _unitOptionsFor(String query, Set<String> exclude) {
    final q = query.trim();
    final pool = _availableUnits.where((u) => !exclude.contains(u));
    if (q.isEmpty) return pool;
    final exact = <String>[];
    final starts = <String>[];
    final contains = <String>[];
    for (final u in pool) {
      if (u == q) {
        exact.add(u);
      } else if (u.startsWith(q)) {
        starts.add(u);
      } else if (u.contains(q)) {
        contains.add(u);
      }
    }
    return [...exact, ...starts, ...contains];
  }

  Set<String> _rowNames({_UnitRow? except}) {
    return _unitRows.where((r) => r != except && r.name.isNotEmpty).map((r) => r.name).toSet();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // التحقق
  // ═══════════════════════════════════════════════════════════════════════

  String? _validateName(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'اسم المادة مطلوب';
    if (_duplicateNameOf != null && _duplicateNameOf == t) {
      return 'توجد مادة بالاسم نفسه مسبقاً — اختر اسماً مختلفاً';
    }
    return null;
  }

  String? _validateBaseUnit(String? v) {
    if ((v ?? '').trim().isEmpty) return 'الوحدة الأساسية مطلوبة';
    return null;
  }

  String? _validateUnitRowName(_UnitRow row) {
    final n = row.name;
    if (n.isEmpty) return 'اكتب اسم الوحدة أو احذف السطر';
    if (n == _baseUnitDisplay) return 'هذه هي الوحدة الأساسية نفسها';
    final i = _unitRows.indexOf(row);
    for (int j = 0; j < i; j++) {
      if (_unitRows[j].name == n) return 'الوحدة «$n» مكررة';
    }
    return null;
  }

  String? _validateUnitRowQty(_UnitRow row) {
    if (row.qtyController.text.trim().isEmpty) return 'أدخل العدد';
    if (row.qty <= 0) return 'العدد يجب أن يكون أكبر من صفر';
    return null;
  }

  String? _validateTier(_PriceTier t, String? v) {
    if (!t.isRequired) return null;
    if (_parse(v ?? '') <= 0) return 'سعر ${t.label} مطلوب';
    return null;
  }

  String? _validateExtraBarcode(_BarcodeRow row) {
    final code = row.barcodeController.text.trim();
    if (code.isEmpty) {
      final hasOther = row.labelController.text.trim().isNotEmpty || row.priceController.text.trim().isNotEmpty;
      return hasOther ? 'أدخل الباركود أو احذف السطر' : null;
    }
    if (code == _barcodeController.text.trim()) return 'مطابق للباركود الأساسي';
    final i = _barcodeRows.indexOf(row);
    for (int j = 0; j < i; j++) {
      if (_barcodeRows[j].barcodeController.text.trim() == code) return 'باركود مكرر';
    }
    return null;
  }

  void _focusFirstInvalid() {
    FocusNode? target;
    if (_validateName(_nameController.text) != null) {
      target = _nameFocus;
    } else if (_validateBaseUnit(_baseUnitNameController.text) != null) {
      target = _unitFocus;
    }
    if (target == null) {
      for (final r in _barcodeRows) {
        if (_validateExtraBarcode(r) != null) {
          target = r.barcodeFocus;
          break;
        }
      }
    }
    if (target == null) {
      for (final r in _unitRows) {
        if (_validateUnitRowName(r) != null) {
          target = r.nameFocus;
          break;
        }
        if (_validateUnitRowQty(r) != null) {
          target = r.qtyFocus;
          break;
        }
      }
    }
    if (target == null) {
      for (final t in _tiers) {
        if (_validateTier(t, t.controller.text) != null) {
          target = t.focus;
          break;
        }
      }
    }
    target?.requestFocus();
  }

  // --- تكرار الاسم (getProductByName) ---

  void _onNameChanged(String v) {
    _nameCheckTimer?.cancel();
    final t = v.trim();
    setState(() {
      if (_duplicateNameOf != null && _duplicateNameOf != t) _duplicateNameOf = null;
      _checkingName = false;
    });
    if (t.isEmpty) return;
    _nameCheckTimer = Timer(const Duration(milliseconds: 450), () => _checkDuplicateName(t));
  }

  Future<bool> _checkDuplicateName(String raw) async {
    final name = raw.trim();
    if (name.isEmpty) return false;
    if (mounted) setState(() => _checkingName = true);
    bool duplicate = false;
    try {
      duplicate = (await DatabaseService().getProductByName(name)) != null;
    } catch (e) {
      debugPrint('⚠️ [إدخال بضاعة] فحص تكرار الاسم: $e');
    }
    if (!mounted) return duplicate;
    final stillSame = _nameController.text.trim() == name;
    setState(() {
      _checkingName = false;
      if (stillSame) {
        _lastCheckedName = name;
        _duplicateNameOf = duplicate ? name : null;
      }
    });
    if (stillSame && duplicate) _nameFieldKey.currentState?.validate();
    return duplicate;
  }

  Widget? _nameStatusIcon() {
    if (_checkingName) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final t = _nameController.text.trim();
    if (t.isEmpty || _lastCheckedName != t) return null;
    if (_duplicateNameOf == t) {
      return const Tooltip(
        message: 'توجد مادة بهذا الاسم',
        child: Icon(Icons.error_outline_rounded, color: PeColors.danger),
      );
    }
    return const Tooltip(
      message: 'الاسم غير مستعمل',
      child: Icon(Icons.check_circle_outline_rounded, color: PeColors.success),
    );
  }

  // --- الباركود المستعمل لمادة أخرى (findProductByBarcode) ---

  /// 🏷️ باركود داخلي جديد (9900000001…) للمادة التي لا باركود لها.
  Future<void> _generateBarcode() async {
    if (_barcodeController.text.trim().isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('للمادة باركود'),
          content: const Text('استبدال الباركود المكتوب بباركود جديد يولّده البرنامج؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استبدال')),
          ],
        ),
      );
      if (replace != true) return;
    }
    try {
      final code = await InternalBarcode.next();
      if (!mounted) return;
      _setText(_barcodeController, code);
      _onBarcodeChanged(code);
    } catch (e) {
      if (mounted) _showSnack('تعذّر توليد الباركود: $e', color: PeColors.danger);
    }
  }

  void _onBarcodeChanged(String v) {
    _barcodeCheckTimer?.cancel();
    final code = v.trim();
    if (_barcodeUsedBy != null) setState(() => _barcodeUsedBy = null);
    if (code.isEmpty) return;
    _barcodeCheckTimer = Timer(const Duration(milliseconds: 500), () async {
      String? usedBy;
      try {
        usedBy = (await DatabaseService().findProductByBarcode(code))?.name;
      } catch (e) {
        debugPrint('⚠️ [إدخال بضاعة] فحص الباركود: $e');
      }
      if (!mounted || _barcodeController.text.trim() != code) return;
      setState(() => _barcodeUsedBy = usedBy);
    });
  }

  Future<void> _scanInto(TextEditingController controller, {bool isMain = false}) async {
    final code = await CameraBarcodeScannerDialog.scan(context);
    if (code == null || code.trim().isEmpty || !mounted) return;
    setState(() => _setText(controller, code.trim()));
    if (isMain) _onBarcodeChanged(code.trim());
  }

  void _addBarcodeRow() {
    final row = _BarcodeRow(++_rowSeq);
    setState(() => _barcodeRows.add(row));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) row.barcodeFocus.requestFocus();
    });
  }

  void _removeBarcodeRow(_BarcodeRow row) {
    setState(() => _barcodeRows.remove(row));
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  // --- سعر بنسبة ربح ---

  Future<void> _applyMarkup(_PriceTier tier) async {
    final cost = _parse(_baseCostController.text);
    if (cost <= 0) {
      _showSnack('أدخل سعر الكلفة أولاً لحساب السعر بنسبة ربح', color: Colors.orange.shade800);
      _costFocus.requestFocus();
      return;
    }
    final result = await showPeMarkupDialog(
      context,
      cost: cost,
      tierLabel: tier.label,
      initialPercent: _lastMarkupPercent,
    );
    if (result == null || !mounted) return;
    setState(() {
      _lastMarkupPercent = result.percent;
      _setText(tier.controller, peFormatNumber(result.price));
    });
    tier.focus.requestFocus();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? today.add(const Duration(days: 365)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 10)),
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
    if (picked != null && mounted) {
      setState(() => _expiryDate = picked);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // الحفظ
  // ═══════════════════════════════════════════════════════════════════════

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط (القفل قبل أي انتظار)
  Future<void> _saveProduct() async {
    await SaveLock.run(() => _saveProductUnlocked(), message: 'جارٍ حفظ المادة…');
  }
  Future<void> _saveProductUnlocked() async {
    if (_saving) return;
    setState(() => _submitted = true);

    // فحص تكرار الاسم إن لم يُفحص الاسم الحالي بعد
    _nameCheckTimer?.cancel();
    final name = _nameController.text.trim();
    if (name.isNotEmpty && _lastCheckedName != name) {
      await _checkDuplicateName(name);
      if (!mounted) return;
    }

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      _showSnack('لم تُحفظ المادة — راجع الحقول المعلّمة بالأحمر', color: PeColors.danger);
      _focusFirstInvalid();
      return;
    }

    // سعر أقل من الكلفة؟ تأكيد قبل الحفظ
    final cost = _parse(_baseCostController.text);
    if (cost > 0) {
      final below = _tiers.where((t) {
        final p = _parse(t.controller.text);
        return p > 0 && p < cost;
      }).toList();
      if (below.isNotEmpty) {
        final ok = await _confirmBelowCost(below, cost);
        if (!mounted) return;
        if (!ok) {
          below.first.focus.requestFocus();
          return;
        }
      }
    }

    // باركود مستعمل لمادة أخرى؟ تأكيد
    final code = _barcodeController.text.trim();
    if (code.isNotEmpty) {
      String? usedBy;
      try {
        usedBy = (await DatabaseService().findProductByBarcode(code))?.name;
      } catch (e) {
        debugPrint('⚠️ [إدخال بضاعة] فحص الباركود: $e');
      }
      if (!mounted) return;
      if (usedBy != null) {
        final ok = await _confirm(
          title: 'باركود مستعمل',
          message: 'الباركود $code مستعمل للمادة «$usedBy». هل تريد حفظه لهذه المادة أيضاً؟',
          confirmLabel: 'حفظ رغم ذلك',
          cancelLabel: 'مراجعة',
          color: PeColors.warning,
        );
        if (!mounted) return;
        if (!ok) {
          _barcodeFocus.requestFocus();
          return;
        }
      }
    }

    // 🚢 مصاريف الشحن: الكلفة والكمية يجب أن تبقيا كما حُسبتا
    final landed = _landed;
    if (landed != null) {
      final costNow = _parse(_baseCostController.text);
      final qtyNow = _parse(_stockController.text);
      if ((costNow - landed.finalUnitCost).abs() > 0.01 || (qtyNow - landed.baseQty).abs() > 0.0001) {
        final ok = await _confirm(
          title: 'تغيّرت الكلفة أو الكمية',
          message: 'أُضيفت مصاريف الشحن على كلفة ${peFormatNumber(landed.purchaseUnitCost)} وكمية '
              '${peFormatNumber(landed.baseQty)}، ثم تغيّر أحدهما. أعد فتح «المزيد ← مصاريف الشحن» ليُعاد الحساب، '
              'أو احفظ بلا مصاريف شحن (تبقى الكلفة كما هي في الحقل).',
          confirmLabel: 'احفظ بلا مصاريف شحن',
          cancelLabel: 'مراجعة',
          color: PeColors.warning,
        );
        if (!mounted || !ok) return;
        setState(() => _landed = null);
      }
    }

    await _performSave();
  }

  /// 🚢 «المزيد ← مصاريف الشحن والجمارك»
  Future<void> _openLanded() async {
    final qty = _parse(_stockController.text);
    final purchase = _landed?.purchaseUnitCost ?? _parse(_baseCostController.text);
    if (qty <= 0) {
      _showSnack('اكتب الرصيد الافتتاحي أولاً — المصاريف توزَّع على الكمية', color: PeColors.warning);
      _stockFocus.requestFocus();
      return;
    }
    if (purchase <= 0) {
      _showSnack('اكتب كلفة الوحدة (سعر الشراء) أولاً', color: PeColors.warning);
      return;
    }
    final plan = await showLandedCostDialog(
      context,
      purchaseUnitCost: purchase,
      baseQty: qty,
      unitLabel: _baseUnitDisplay,
      initial: _landed != null && (_landed!.baseQty - qty).abs() < 0.0001 ? _landed : null,
    );
    if (plan == null || !mounted) return;
    setState(() {
      _landed = plan;
      _baseCostController.text = peFormatNumber(plan.finalUnitCost);
    });
  }

  void _removeLanded() {
    final l = _landed;
    if (l == null) return;
    setState(() {
      _baseCostController.text = peFormatNumber(l.purchaseUnitCost);
      _landed = null;
    });
  }

  Future<bool> _confirmBelowCost(List<_PriceTier> below, double cost) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: PeColors.warning, size: 40),
        title: const Text('سعر أقل من الكلفة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الكلفة ${peFormatNumber(cost)} د.ع، والأسعار التالية أقل منها (بيع بخسارة):'),
            const SizedBox(height: 8),
            for (final t in below)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${t.label}: ${peFormatNumber(_parse(t.controller.text))} د.ع',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: PeColors.danger),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('مراجعة الأسعار'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PeColors.warning),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حفظ رغم ذلك'),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// الحفظ الفعلي — نفس البيانات ونفس المسار كما كان.
  Future<void> _performSave() async {
    setState(() => _saving = true);
    final db = DatabaseService();

    // Build hierarchy JSON: [{unit_name, quantity}] — كل مستوى بالنسبة للمستوى السابق
    List<Map<String, dynamic>> finalHierarchy = [];
    Map<String, double> unitCosts = {};
    double baseCost = _parse(_baseCostController.text);
    // 🔧 Fix: Map standard Arabic names to internal keys for DB compatibility
    String rawUnit = _baseUnitNameController.text.trim();
    String baseKey = rawUnit.isEmpty ? 'piece' : (rawUnit == 'قطعة' ? 'piece' : (rawUnit == 'متر' ? 'meter' : rawUnit));
    unitCosts[baseKey] = baseCost;

    // السلسلة تمشي على المستويات المحفوظة فعلاً (التحقق يمنع الأسطر الناقصة)
    String prevUnitName = baseKey;
    for (final row in _unitRows) {
      final String uName = row.name;
      final double qty = row.qty;
      if (uName.isEmpty || qty <= 0) continue;

      finalHierarchy.add({'unit_name': uName, 'quantity': qty});

      // Calculate cost for this unit
      final double prevCost = unitCosts[prevUnitName] ?? baseCost;
      unitCosts[uName] = prevCost * qty;
      prevUnitName = uName;
    }

    String? unitHierarchyJson = finalHierarchy.isNotEmpty ? json.encode(finalHierarchy) : null;
    String? unitCostsJson = unitCosts.isNotEmpty ? json.encode(unitCosts) : null;

    // 🔍 تشخيص تحويل الوحدات — ماذا يُحفظ فعلاً للمنتج الموزون؟
    debugPrint('🔍 [تشخيص-حفظ-منتج] "${_nameController.text.trim()}"');
    debugPrint('    unit="$baseKey" | isWeighable=$_isWeighable | baseWeight=${_isWeighable ? _parse(_baseWeightController.text) : null}');
    debugPrint('    unitHierarchy=$unitHierarchyJson');
    debugPrint('    unitCosts=$unitCostsJson');
    if (finalHierarchy.isEmpty) {
      debugPrint('    ⚠️ الهرمية فارغة! لن تظهر وحدات كبرى في الفاتورة — تحقق من "تعبئة وحدات كبرى"');
    }

    // وحدة التنبيه: إن حُذفت/تغيّرت وحدتها الأكبر تعود للوحدة الأساسية
    final alertUnits = <String>{
      _baseUnitDisplay,
      ...finalHierarchy.map((h) => h['unit_name'].toString()),
    };
    if (_alertUnitController.text.trim().isNotEmpty && !alertUnits.contains(_alertUnitController.text.trim())) {
      _alertUnitController.clear();
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
      // حفظ الوحدات الجديدة إذا لم تكن موجودة — فشلها لا يمنع حفظ المادة
      try {
        if (baseKey.isNotEmpty && !_dbUnits.contains(baseKey)) {
          await db.addCustomUnit(baseKey);
        }
        for (var h in finalHierarchy) {
          final unitName = h['unit_name']?.toString() ?? '';
          if (unitName.isNotEmpty && !_dbUnits.contains(unitName)) {
            await db.addCustomUnit(unitName);
          }
        }
      } catch (e) {
        debugPrint('⚠️ [إدخال بضاعة] تسجيل الوحدات الجديدة: $e');
      }

      final productId = await db.insertProduct(product);

      // 🚢 سجل مصاريف الشحن (والقيد حسب طريقة الدفع) — بعد نجاح حفظ المادة فقط
      final landedPlan = _landed;
      if (landedPlan != null) {
        try {
          await LandedCostService.record(productId: productId, productName: product.name, plan: landedPlan);
        } catch (e) {
          debugPrint('⚠️ [إدخال بضاعة] مصاريف الشحن: $e');
          _showSnack('حُفظت المادة بكلفتها الجديدة، لكن تعذّر تسجيل مصاريف الشحن: $e',
              color: Colors.orange.shade800, seconds: 8);
        }
      }

      // 🏷️ حفظ الباركودات الإضافية (فشل أحدها لا يُلغي حفظ المادة)
      final failedBarcodes = <String>[];
      for (final row in _barcodeRows) {
        final barcode = row.barcodeController.text.trim();
        if (barcode.isEmpty) continue;
        final sellPrice = _parse(row.priceController.text);
        try {
          await db.addProductBarcode(
            productId: productId,
            barcode: barcode,
            variantLabel: row.labelController.text.trim(),
            sellPrice: sellPrice > 0 ? sellPrice : null,
            costPrice: null,
          );
        } catch (e) {
          failedBarcodes.add(barcode);
          debugPrint('⚠️ [إدخال بضاعة] حفظ الباركود $barcode: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _saving = false;
        _savedCount++;
        _totalProductsCount++;
      });
      if (failedBarcodes.isNotEmpty) {
        _showSnack(
          'حُفظت المادة، لكن تعذّر حفظ الباركودات: ${failedBarcodes.join('، ')}',
          color: Colors.orange.shade800,
          seconds: 6,
        );
      }
      await _showSaveSuccess(product, finalHierarchy, productId);
    } on DuplicateProductNameException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _duplicateNameOf = product.name;
        _lastCheckedName = product.name;
      });
      _nameFieldKey.currentState?.validate();
      _nameFocus.requestFocus();
      _showSnack(e.toString(), color: PeColors.danger, seconds: 6);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack('خطأ في الحفظ: $e', color: PeColors.danger, seconds: 6);
    }
  }

  Future<void> _showSaveSuccess(Product product, List<Map<String, dynamic>> hierarchy, int productId) async {
    final unitsText = [
      _baseUnitDisplay,
      for (final h in hierarchy)
        '${h['unit_name']} (${peFormatNumber((h['quantity'] as num).toDouble())})',
    ].join('، ');

    final addAnother = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded, color: PeColors.success, size: 52),
        title: const Text('تم حفظ المادة بنجاح', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '«${product.name}»',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextColor),
            ),
            const SizedBox(height: 10),
            Text(
              'سعر المفرد: ${peFormatNumber(product.price1)} د.ع   •   الرصيد: ${peFormatNumber(product.stockQuantity)} $_baseUnitDisplay',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700]),
            ),
            if (hierarchy.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('الوحدات: $unitsText', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, false),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('رجوع'),
          ),
          OutlinedButton.icon(
            onPressed: () => BarcodeLabels.printForProducts(ctx, [productId]),
            icon: const Icon(Icons.print_rounded),
            label: const Text('طباعة ملصق باركود'),
          ),
          FilledButton.icon(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة مادة أخرى'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (addAnother == false) {
      Navigator.of(context).pop(true);
    } else {
      _resetForm();
    }
  }

  /// تفريغ النموذج لإدخال مادة جديدة — يبقى القسم والوحدة الأساسية ونوع البيع بالوزن.
  void _resetForm() {
    final keepUnit = _baseUnitNameController.text;
    _nameCheckTimer?.cancel();
    _barcodeCheckTimer?.cancel();
    _formKey.currentState?.reset();

    final oldUnitRows = List<_UnitRow>.from(_unitRows);
    final oldBarcodeRows = List<_BarcodeRow>.from(_barcodeRows);
    setState(() {
      for (final c in <TextEditingController>[
        _nameController,
        _barcodeController,
        _baseCostController,
        _baseWeightController,
        _stockController,
        _alertQtyController,
        _alertUnitController,
        ..._tiers.map((t) => t.controller),
      ]) {
        c.clear();
      }
      _setText(_baseUnitNameController, keepUnit.trim().isEmpty ? 'قطعة' : keepUnit);
      _unitRows.clear();
      _barcodeRows.clear();
      _hasExpiry = false;
      _expiryDate = null;
      _landed = null;
      _submitted = false;
      _checkingName = false;
      _lastCheckedName = '';
      _duplicateNameOf = null;
      _barcodeUsedBy = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in oldUnitRows) {
        r.dispose();
      }
      for (final r in oldBarcodeRows) {
        r.dispose();
      }
      if (!mounted) return;
      _nameFocus.requestFocus();
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _confirmClear() async {
    if (_hasUnsavedInput()) {
      final ok = await _confirm(
        title: 'تفريغ الحقول؟',
        message: 'ستُمسح كل البيانات المدخلة (يبقى القسم والوحدة الأساسية).',
        confirmLabel: 'تفريغ',
        color: PeColors.danger,
      );
      if (!ok || !mounted) return;
    }
    _resetForm();
  }

  Future<void> _handleBack() async {
    if (_saving) return;
    if (_hasUnsavedInput()) {
      final leave = await _confirm(
        title: 'الخروج بدون حفظ؟',
        message: 'في النموذج بيانات لم تُحفظ بعد. هل تريد الخروج وتجاهلها؟',
        confirmLabel: 'خروج بدون حفظ',
        cancelLabel: 'البقاء',
        color: PeColors.danger,
      );
      if (!leave || !mounted) return;
    }
    Navigator.of(context).pop(_savedCount > 0 ? true : null);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // البناء
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final wideChrome = MediaQuery.of(context).size.width >= 900;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveProduct,
        },
        child: Scaffold(
          backgroundColor: kBackgroundColor,
          appBar: _buildHeader(wideChrome),
          bottomNavigationBar: _buildBottomBar(wideChrome),
          body: Form(
            key: _formKey,
            autovalidateMode: _submitted ? AutovalidateMode.always : AutovalidateMode.disabled,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                final basic = _buildBasicSection();
                final units = _buildUnitsSection();
                final prices = _buildPricesSection();
                final stock = _buildStockSection();
                return Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: wide,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.all(wide ? 20 : 12),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1400),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [basic, units],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [prices, stock],
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [basic, units, prices, stock],
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildHeader(bool wide) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(72),
      child: Material(
        color: Colors.white,
        elevation: 1,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: kPrimaryColor, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.add_box_outlined, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إدخال بضاعة — مادة جديدة',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: kTextColor),
                      ),
                      Text(
                        'عرّف المادة ووحداتها وأسعارها ورصيدها الافتتاحي',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (wide) ...[
                  _headerStat('إجمالي المواد', '$_totalProductsCount'),
                  if (_savedCount > 0) ...[
                    const SizedBox(width: 20),
                    _headerStat('أُضيفت الآن', '$_savedCount', color: PeColors.success),
                  ],
                  const SizedBox(width: 20),
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
                ] else
                  IconButton(
                    onPressed: _addNewCategory,
                    icon: const Icon(Icons.category_outlined, color: kTextColor),
                    tooltip: 'إدارة الأقسام',
                  ),
                const SizedBox(width: 8),
                // Back Button
                IconButton(
                  onPressed: _handleBack,
                  icon: const Icon(Icons.arrow_forward_ios, color: kTextColor), // Forward for RTL back
                  tooltip: 'رجوع',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerStat(String label, String value, {Color color = kPrimaryColor}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11.5)),
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildBottomBar(bool wide) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 12, vertical: 10),
          child: Row(
            children: [
              if (wide)
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.keyboard_outlined, size: 18, color: Colors.grey[500]),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Enter: الحقل التالي    •    Ctrl+S: حفظ    •    * حقل مطلوب',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Spacer(),
              TextButton.icon(
                onPressed: _saving ? null : _confirmClear,
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: const Text('تفريغ الحقول'),
                style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Ctrl+S',
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    focusNode: _saveButtonFocus,
                    onPressed: _saving ? null : _saveProduct,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      _saving ? 'جارٍ الحفظ...' : 'حفظ المادة',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: kPrimaryColor.withValues(alpha: 0.6),
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // حقل وحدة بإكمال تلقائي (للوحدة الأساسية ولأسطر الوحدات الأكبر)
  // ─────────────────────────────────────────────────────────────────────

  Widget _unitAutocomplete({
    required TextEditingController controller,
    required FocusNode focusNode,
    required Set<String> Function() exclude,
    required String hint,
    required String? Function(String?) validator,
    required VoidCallback onNext,
    ValueChanged<String>? onSelected,
    ValueChanged<String>? onChanged,
  }) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (value) => _unitOptionsFor(value.text, exclude()),
      onSelected: (selection) {
        setState(() {});
        onSelected?.call(selection);
      },
      fieldViewBuilder: (context, textController, fieldFocus, onFieldSubmitted) {
        return TextFormField(
          controller: textController,
          focusNode: fieldFocus,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          textInputAction: TextInputAction.next,
          decoration: peInputDecoration(
            hint: hint,
            suffixIcon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.grey),
          ),
          validator: validator,
          onChanged: onChanged,
          onEditingComplete: () {},
          onFieldSubmitted: (text) {
            // كتابة جزئية لوحدة موجودة (مثل «كرت») + Enter = اختيار أقرب وحدة
            final t = text.trim();
            if (t.isNotEmpty) {
              final options = _unitOptionsFor(t, exclude()).toList();
              if (options.isNotEmpty && !options.contains(t)) onFieldSubmitted();
            }
            onNext();
          },
        );
      },
      optionsViewBuilder: (context, onSelectedOption, options) {
        final list = options.toList();
        final highlighted = AutocompleteHighlightedOption.of(context);
        return Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 260),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final option = list[i];
                  return InkWell(
                    onTap: () => onSelectedOption(option),
                    child: Container(
                      color: i == highlighted ? kPrimaryColor.withValues(alpha: 0.08) : null,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(option, style: const TextStyle(fontSize: 13.5)),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // القسم 1: البيانات الأساسية
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildBasicSection() {
    return PeSectionCard(
      icon: Icons.badge_outlined,
      color: kPrimaryColor,
      title: 'البيانات الأساسية',
      subtitle: 'اسم المادة، الوحدة الأساسية، القسم، والباركود',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PeFieldLabel('اسم المادة', isRequired: true),
          TextFormField(
            key: _nameFieldKey,
            controller: _nameController,
            focusNode: _nameFocus,
            autofocus: true,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            textInputAction: TextInputAction.next,
            decoration: peInputDecoration(
              hint: 'مثال: سلك كهرباء 2.5 ملم، حنفية مغسلة...',
              suffixIcon: _nameStatusIcon(),
            ),
            validator: _validateName,
            onChanged: _onNameChanged,
            onEditingComplete: () {},
            onFieldSubmitted: (_) => _unitFocus.requestFocus(),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final unit = _buildBaseUnitField();
              final category = _buildCategoryField();
              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [unit, const SizedBox(height: 14), category],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: unit),
                  const SizedBox(width: 12),
                  Expanded(child: category),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('وحدة سريعة:', style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
              for (final u in _baseUnitSuggestions)
                ChoiceChip(
                  label: Text(u, style: const TextStyle(fontSize: 12)),
                  selected: _baseUnitDisplay == u,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) {
                    _setText(_baseUnitNameController, u);
                    _checkUnitHierarchySuggestion();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          const PeFieldLabel('الباركود', icon: Icons.qr_code_2_rounded),
          TextFormField(
            controller: _barcodeController,
            focusNode: _barcodeFocus,
            textInputAction: TextInputAction.next,
            decoration: peInputDecoration(
              hint: 'امسح بالقارئ أو اكتب الباركود (اختياري)',
              suffixIcon: ExcludeFocus(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.auto_awesome_rounded, color: _kPricesColor, size: 20),
                    tooltip: 'توليد باركود للمادة (لمادة بلا باركود من المصنع)',
                    onPressed: _generateBarcode,
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt_rounded, color: _kPricesColor, size: 20),
                    tooltip: 'مسح الباركود بالكاميرا',
                    onPressed: () => _scanInto(_barcodeController, isMain: true),
                  ),
                ]),
              ),
              helperText: _barcodeUsedBy != null ? 'تنبيه: هذا الباركود مستعمل للمادة «$_barcodeUsedBy»' : null,
              helperColor: PeColors.warning,
            ),
            onChanged: _onBarcodeChanged,
            onEditingComplete: () {},
            onFieldSubmitted: (_) => _costFocus.requestFocus(),
          ),
          _buildExtraBarcodes(),
        ],
      ),
    );
  }

  Widget _buildBaseUnitField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PeFieldLabel('الوحدة الأساسية (الأصغر)', isRequired: true),
        _unitAutocomplete(
          controller: _baseUnitNameController,
          focusNode: _unitFocus,
          exclude: () => _rowNames(),
          hint: 'قطعة، متر، لفة...',
          validator: _validateBaseUnit,
          onNext: () => _barcodeFocus.requestFocus(),
          onSelected: (_) => _checkUnitHierarchySuggestion(),
        ),
      ],
    );
  }

  Widget _buildCategoryField() {
    final seen = <int>{};
    final cats = <Category>[];
    for (final c in _categories) {
      final id = c.id;
      if (id != null && seen.add(id)) cats.add(c);
    }
    final value = seen.contains(_selectedCategoryId) ? _selectedCategoryId : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PeFieldLabel(
          'القسم',
          trailing: InkWell(
            onTap: _addNewCategory,
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Text(
                '+ إدارة الأقسام',
                style: TextStyle(fontSize: 11.5, color: kPrimaryColor, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        InputDecorator(
          decoration: peInputDecoration().copyWith(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: value,
              isExpanded: true,
              isDense: true,
              hint: Text(
                _categoriesFailed ? 'تعذّر تحميل الأقسام' : 'بدون قسم',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('بدون قسم')),
                for (final c in cats)
                  DropdownMenuItem<int?>(
                    value: c.id,
                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _selectedCategoryId = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExtraBarcodes() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBarcodeColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_scanner_rounded, size: 18, color: _kBarcodeColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _barcodeRows.isEmpty
                      ? 'باركودات إضافية (اختياري)'
                      : 'باركودات إضافية (${_barcodeRows.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF9A3412)),
                ),
              ),
              TextButton.icon(
                onPressed: _addBarcodeRow,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('إضافة باركود'),
                style: TextButton.styleFrom(foregroundColor: _kBarcodeColor),
              ),
            ],
          ),
          if (_barcodeRows.isEmpty)
            Text(
              'لكل لون أو نكهة أو حجم من المادة نفسها باركود خاص، ويمكن تحديد سعر خاص له.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 460;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < _barcodeRows.length; i++) _buildBarcodeRow(i, compact),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBarcodeRow(int index, bool compact) {
    final row = _barcodeRows[index];
    final barcodeField = TextFormField(
      controller: row.barcodeController,
      focusNode: row.barcodeFocus,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      textInputAction: TextInputAction.next,
      decoration: peInputDecoration(
        hint: 'الباركود',
        suffixIcon: ExcludeFocus(
          child: IconButton(
            icon: const Icon(Icons.camera_alt_rounded, color: _kBarcodeColor, size: 18),
            tooltip: 'مسح بالكاميرا',
            onPressed: () => _scanInto(row.barcodeController),
          ),
        ),
      ),
      validator: (_) => _validateExtraBarcode(row),
      onEditingComplete: () {},
      onFieldSubmitted: (_) => row.labelFocus.requestFocus(),
    );
    final labelField = TextFormField(
      controller: row.labelController,
      focusNode: row.labelFocus,
      textInputAction: TextInputAction.next,
      decoration: peInputDecoration(hint: 'الوصف: لون / نكهة / حجم'),
      onEditingComplete: () {},
      onFieldSubmitted: (_) => row.priceFocus.requestFocus(),
    );
    final priceField = TextFormField(
      controller: row.priceController,
      focusNode: row.priceFocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
      textInputAction: TextInputAction.next,
      decoration: peInputDecoration(hint: 'سعر خاص (اختياري)', suffixText: 'د.ع'),
      onEditingComplete: () {},
      onFieldSubmitted: (_) {
        final i = _barcodeRows.indexOf(row);
        if (i >= 0 && i + 1 < _barcodeRows.length) {
          _barcodeRows[i + 1].barcodeFocus.requestFocus();
        } else {
          _costFocus.requestFocus();
        }
      },
    );
    final deleteButton = IconButton(
      tooltip: 'حذف هذا الباركود',
      icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
      onPressed: () => _removeBarcodeRow(row),
    );

    return Padding(
      key: ValueKey('barcode_row_${row.id}'),
      padding: const EdgeInsets.only(top: 8),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: barcodeField), deleteButton],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: labelField),
                    const SizedBox(width: 8),
                    Expanded(child: priceField),
                  ],
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: barcodeField),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: labelField),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: priceField),
                deleteButton,
              ],
            ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // القسم 2: الوحدات
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildUnitsSection() {
    final taken = _rowNames();
    final suggestions = _largerUnitSuggestions.where((u) => u != _baseUnitDisplay && !taken.contains(u)).toList();
    return PeSectionCard(
      icon: Icons.account_tree_outlined,
      color: _kUnitsColor,
      title: 'الوحدات',
      subtitle: 'الوحدات الأكبر التي تُباع بها المادة (كرتون، باكيت...) وكم تحتوي',
      trailing: _unitRows.isEmpty ? null : _countPill('${_unitRows.length}', _kUnitsColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _kUnitsColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.straighten_rounded, size: 18, color: _kUnitsColor),
                const SizedBox(width: 8),
                const Text('الوحدة الأساسية: ', style: TextStyle(fontSize: 12.5, color: Color(0xFF065F46))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: _kUnitsColor, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    _baseUnitDisplay,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'الرصيد والكلفة والأسعار كلها بهذه الوحدة',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_unitRows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'المادة تُباع بوحدة واحدة ($_baseUnitDisplay). إذا كانت تُباع أيضاً بالكرتون أو الباكيت، أضف وحدة أكبر وحدّد كم تحتوي.',
                style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5),
              ),
            )
          else
            ...[
              for (int i = 0; i < _unitRows.length; i++) _buildUnitRow(i),
            ],
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _addUnitRow(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('إضافة وحدة أكبر'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kUnitsColor,
                  side: BorderSide(color: _kUnitsColor.withValues(alpha: 0.5)),
                ),
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text('أو بسرعة:', style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                for (final u in suggestions)
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 14),
                    label: Text(u, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onPressed: () => _addUnitRow(u),
                  ),
              ],
            ],
          ),
          const Divider(height: 28),
          Row(
            children: [
              Icon(Icons.scale_outlined, size: 18, color: Colors.grey[600]),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('يُباع بالوزن (ميزان)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ),
              Switch(
                value: _isWeighable,
                activeThumbColor: kPrimaryColor,
                onChanged: (v) => setState(() => _isWeighable = v),
              ),
            ],
          ),
          if (_isWeighable) ...[
            const SizedBox(height: 6),
            const PeFieldLabel('وزن الوحدة الواحدة (كغم)'),
            TextFormField(
              controller: _baseWeightController,
              focusNode: _weightFocus,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
              textInputAction: TextInputAction.next,
              decoration: peInputDecoration(hint: '0.120', suffixText: 'كغم'),
              onEditingComplete: () {},
              onFieldSubmitted: (_) => _costFocus.requestFocus(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUnitRow(int index) {
    final row = _unitRows[index];
    final prevName = index == 0
        ? _baseUnitDisplay
        : (_unitRows[index - 1].name.isEmpty ? 'الوحدة السابقة' : _unitRows[index - 1].name);

    // كم وحدة أساسية في هذه الوحدة (إن اكتملت السلسلة حتى هذا السطر)
    double factor = 1;
    bool complete = true;
    for (int j = 0; j <= index; j++) {
      final q = _unitRows[j].qty;
      if (q <= 0) {
        complete = false;
        break;
      }
      factor *= q;
    }
    final hasName = row.name.isNotEmpty;
    final summary = (complete && hasName)
        ? '1 ${row.name} = ${peFormatNumber(row.qty)} $prevName'
            '${index > 0 ? ' = ${peFormatNumber(factor)} $_baseUnitDisplay' : ''}'
        : 'حدّد اسم الوحدة وكم $prevName بداخلها';

    return Container(
      key: ValueKey('unit_row_${row.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FBF8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kUnitsColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _kUnitsColor, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  'مستوى ${index + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: (complete && hasName) ? const Color(0xFF065F46) : Colors.grey[600],
                  ),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                tooltip: 'حذف هذه الوحدة',
                onPressed: () => _removeUnitRow(row),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PeFieldLabel('اسم الوحدة', isRequired: true),
                    _unitAutocomplete(
                      controller: row.nameController,
                      focusNode: row.nameFocus,
                      exclude: () => {_baseUnitDisplay, ..._rowNames(except: row)},
                      hint: 'مثال: كرتون',
                      validator: (_) => _validateUnitRowName(row),
                      onNext: () => row.qtyFocus.requestFocus(),
                      onSelected: (_) => row.qtyFocus.requestFocus(),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PeFieldLabel('كم $prevName بداخلها؟', isRequired: true),
                    TextFormField(
                      controller: row.qtyController,
                      focusNode: row.qtyFocus,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                      textInputAction: TextInputAction.next,
                      decoration: peInputDecoration(hint: 'مثال: 24', suffixText: prevName),
                      validator: (_) => _validateUnitRowQty(row),
                      onChanged: (_) => setState(() {}),
                      onEditingComplete: () {},
                      onFieldSubmitted: (_) {
                        final i = _unitRows.indexOf(row);
                        if (i >= 0 && i + 1 < _unitRows.length) {
                          _unitRows[i + 1].nameFocus.requestFocus();
                        } else {
                          _costFocus.requestFocus();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (complete && hasName)
            AnimatedBuilder(
              animation: Listenable.merge([_baseCostController, _basePriceController]),
              builder: (context, _) {
                final cost = _parse(_baseCostController.text);
                final retail = _parse(_basePriceController.text);
                final parts = <String>[
                  if (cost > 0) 'الكلفة: ${peFormatNumber(cost * factor)} د.ع',
                  if (retail > 0) 'بسعر المفرد: ${peFormatNumber(retail * factor)} د.ع',
                ];
                if (parts.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${row.name} الواحد — ${parts.join('   •   ')}',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[700]),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // القسم 3: الأسعار
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildPricesSection() {
    return PeSectionCard(
      icon: Icons.sell_outlined,
      color: _kPricesColor,
      title: 'الأسعار',
      subtitle: 'الكلفة وأسعار البيع الستة — نسبة الربح تظهر بجانب كل سعر',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PeFieldLabel('سعر الكلفة (لكل $_baseUnitDisplay)', icon: Icons.payments_outlined),
          TextFormField(
            controller: _baseCostController,
            focusNode: _costFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
            textInputAction: TextInputAction.next,
            decoration: peInputDecoration(
              hint: '0',
              suffixText: 'د.ع',
              helperText: 'منها تُحسب نسبة الربح وكلفة الوحدات الأكبر',
            ),
            onEditingComplete: () {},
            onFieldSubmitted: (_) => _tiers.first.focus.requestFocus(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'أسعار البيع',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[800]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'زر ٪ داخل الحقل = سعر بنسبة ربح فوق الكلفة',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 480;
              final width = twoColumns ? ((constraints.maxWidth - 12) / 2).floorToDouble() : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (int i = 0; i < _tiers.length; i++) SizedBox(width: width, child: _buildTierField(i)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTierField(int index) {
    final tier = _tiers[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PeFieldLabel(
          tier.label,
          isRequired: tier.isRequired,
          icon: tier.icon,
          iconColor: tier.color,
          trailing: AnimatedBuilder(
            animation: Listenable.merge([_baseCostController, tier.controller]),
            builder: (context, _) => PeProfitBadge(
              cost: _parse(_baseCostController.text),
              price: _parse(tier.controller.text),
            ),
          ),
        ),
        TextFormField(
          controller: tier.controller,
          focusNode: tier.focus,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
          textInputAction: TextInputAction.next,
          decoration: peInputDecoration(
            hint: tier.hint,
            suffixText: 'د.ع',
            suffixIcon: ExcludeFocus(
              child: IconButton(
                tooltip: 'سعر بنسبة ربح',
                icon: Icon(Icons.percent_rounded, size: 18, color: tier.color),
                onPressed: () => _applyMarkup(tier),
              ),
            ),
          ),
          validator: (v) => _validateTier(tier, v),
          onEditingComplete: () {},
          onFieldSubmitted: (_) {
            if (index + 1 < _tiers.length) {
              _tiers[index + 1].focus.requestFocus();
            } else {
              _stockFocus.requestFocus();
            }
          },
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // القسم 4: المخزون
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildStockSection() {
    final alertOptions = <String>[_baseUnitDisplay];
    for (final level in _levelFactors()) {
      if (!alertOptions.contains(level.key)) alertOptions.add(level.key);
    }
    String alertValue = _alertUnitController.text.trim();
    if (alertValue.isEmpty || !alertOptions.contains(alertValue)) alertValue = _baseUnitDisplay;

    return PeSectionCard(
      icon: Icons.warehouse_outlined,
      color: _kStockColor,
      title: 'المخزون',
      subtitle: 'الرصيد الافتتاحي، حد التنبيه، وتاريخ الصلاحية',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PeFieldLabel('الرصيد الافتتاحي (الكمية الموجودة الآن)', icon: Icons.inventory_outlined),
          TextFormField(
            controller: _stockController,
            focusNode: _stockFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
            textInputAction: TextInputAction.next,
            decoration: peInputDecoration(hint: '0', suffixText: _baseUnitDisplay),
            onEditingComplete: () {},
            onFieldSubmitted: (_) => _alertQtyFocus.requestFocus(),
          ),
          AnimatedBuilder(
            animation: Listenable.merge([_stockController, _baseCostController]),
            builder: (context, _) {
              final qty = _parse(_stockController.text);
              final cost = _parse(_baseCostController.text);
              final breakdown = _stockBreakdown(qty);
              final parts = <String>[
                if (breakdown != null) breakdown,
                if (qty > 0 && cost > 0) 'قيمة الرصيد بالكلفة: ${peFormatNumber(qty * cost)} د.ع',
              ];
              if (parts.isEmpty) return const SizedBox(height: 4);
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  parts.join('   •   '),
                  style: const TextStyle(fontSize: 11.5, color: _kStockColor, fontWeight: FontWeight.w600),
                ),
              );
            },
          ),
          // 🚢 المزيد: مصاريف شحن وجمارك تُضاف إلى كلفة الوحدة
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _landed == null
                ? Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _openLanded,
                      icon: const Icon(Icons.local_shipping_outlined, size: 18),
                      label: const Text('المزيد: مصاريف شحن وجمارك'),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _kStockColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kStockColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.local_shipping_rounded, size: 18, color: _kStockColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'شحن وجمارك ${peFormatNumber(_landed!.totalExtra)} د.ع: +${peFormatNumber(_landed!.perUnit)} للوحدة '
                          '(${peFormatNumber(_landed!.purchaseUnitCost)} ← ${peFormatNumber(_landed!.finalUnitCost)}) — '
                          '${LandedMode.label(_landed!.mode)}',
                          style: const TextStyle(fontSize: 12, color: _kStockColor, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: 'تعديل',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        onPressed: _openLanded,
                      ),
                      IconButton(
                        tooltip: 'إزالة (تعود الكلفة لسعر الشراء)',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: _removeLanded,
                      ),
                    ]),
                  ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PeFieldLabel(
                      'نبّهني عندما تصل الكمية إلى',
                      icon: Icons.notifications_active_outlined,
                      iconColor: Colors.red,
                    ),
                    TextFormField(
                      controller: _alertQtyController,
                      focusNode: _alertQtyFocus,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                      textInputAction: TextInputAction.next,
                      decoration: peInputDecoration(hint: 'مثال: 10 (اختياري)'),
                      onEditingComplete: () {},
                      onFieldSubmitted: (_) => _saveButtonFocus.requestFocus(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PeFieldLabel('بوحدة'),
                    InputDecorator(
                      decoration: peInputDecoration().copyWith(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: alertValue,
                          isExpanded: true,
                          isDense: true,
                          items: [
                            for (final u in alertOptions)
                              DropdownMenuItem<String>(value: u, child: Text(u, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => setState(() {
                            _alertUnitController.text = (v == null || v == _baseUnitDisplay) ? '' : v;
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildExpiryBox(),
        ],
      ),
    );
  }

  Widget _buildExpiryBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: kInputFillColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PeColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.event_outlined, size: 18, color: Colors.orange),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('للمادة تاريخ صلاحية', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ),
              Switch(
                value: _hasExpiry,
                activeThumbColor: kPrimaryColor,
                onChanged: (v) => setState(() {
                  _hasExpiry = v;
                  if (!v) _expiryDate = null;
                }),
              ),
            ],
          ),
          if (_hasExpiry)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: _pickExpiry,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month, color: Colors.orange, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _expiryDate != null
                              ? 'تاريخ الانتهاء: ${DateFormat('dd/MM/yyyy', 'ar').format(_expiryDate!)}'
                              : 'اضغط لاختيار تاريخ الانتهاء',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _expiryDate != null ? kTextColor : Colors.grey[500],
                          ),
                        ),
                      ),
                      if (_expiryDate != null)
                        IconButton(
                          tooltip: 'إزالة التاريخ',
                          icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                          onPressed: () => setState(() => _expiryDate = null),
                        )
                      else
                        const Icon(Icons.chevron_left_rounded, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- Reusable Modern Widgets (كانت هنا سابقاً — تبقى متاحة لمن يستوردها) ---

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
           BoxShadow(color: const Color(0xff121212).withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 4)),
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
