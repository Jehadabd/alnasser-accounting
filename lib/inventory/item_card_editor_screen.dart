// lib/inventory/item_card_editor_screen.dart
//
// 🗂️ «بطاقة مادة» — شاملة مثل الإداري، لكن بواجهة حديثة هادئة:
//   • في الواجهة ما تحتاجه أغلب المواد فقط: الاسم والرمز والقسم والباركود،
//     الوحدات بمعاملات التحويل، الكلفة والأسعار الستة، والكمية والتنبيه.
//   • كل ما يندر استعماله في نافذة «المزيد»: التعريف الإضافي، أرقام التسجيل
//     والجمرك والضريبة، الحسم والهدايا، طرق الكلفة، الحدود والمخزن والمورد،
//     الصلاحية والتسلسلي والوزن والميزان، الباركودات الإضافية، الحالة.
//     الإعدادات المفعّلة منها تظهر شارات صغيرة تحت الاسم.
//   • شريط سفلي: حفظ • جديد • السابق/التالي • بحث • البطاقة الموسّعة • ملصق.
//     لوحة المفاتيح: Enter ينقل للحقل التالي، Ctrl+S حفظ، Ctrl+N جديد،
//     Ctrl+F بحث، Ctrl+PageUp/PageDown السابق/التالي.
//
// الأمان (المسارات نفسها المستعملة في «إدخال بضاعة» و«بطاقة المادة الموسّعة»):
//   • مادة جديدة: DatabaseService.insertProduct (الكمية الأولى رصيد افتتاحي في
//     دفتر المخزون) ثم product_details ثم الباركودات الإضافية.
//   • تعديل: تُكتب الحقول التي غيّرها المستخدم فقط فوق نسخة المادة الحالية في
//     القاعدة عبر updateProduct (لا يلمس الكمية ولا معرّف المزامنة)، والأسعار عبر
//     PriceTools.applyPrices (تُسجَّل في سجل تغييرات الأسعار).
//   • الكمية لا تُعدَّل من هنا — مكانها المستندات المخزنية والجرد.

import 'dart:convert';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show NumberFormat, DateFormat;
import 'package:shared_preferences/shared_preferences.dart';

import '../accounting/screens/acc_ui.dart' show showError, showOk, requirePermission;
import '../erp/erp_common.dart' show parseMoney, erpDb, confirmDialog, d0;
import '../erp/inventory/barcode_labels.dart';
import '../erp/inventory/price_tools.dart' show PriceTools, priceFieldNames, roundToStep;
import '../models/app_user.dart';
import '../models/product.dart';
import '../org/org_service.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../widgets/formatters.dart';
import 'item_card_screen.dart' show ItemCardService, ItemCardScreen, ErpStockReserved, itemTypeLabels;

// ─────────────────────────── ألوان الواجهة ───────────────────────────
class _C {
  static const bg = Color(0xFFF3F6FB);
  static const card = Colors.white;
  static const border = Color(0xFFE3E9F1);
  static const field = Color(0xFFF6F8FB);
  static const navy = Color(0xFF0F3460);
  static const navy2 = Color(0xFF1B5E8C);
  static const cyan = Color(0xFF00A6C8);
  static const text = Color(0xFF1E293B);
  static const muted = Color(0xFF64748B);
  static const green = Color(0xFF059669);
  static const red = Color(0xFFDC2626);
  static const orange = Color(0xFFD97706);
  static const units = Color(0xFF059669);
  static const prices = Color(0xFF4F46E5);
  static const stock = Color(0xFF0891B2);
  static const tiers = [
    Color(0xFF4F46E5),
    Color(0xFF6366F1),
    Color(0xFFD97706),
    Color(0xFF059669),
    Color(0xFF0284C7),
    Color(0xFF7C3AED),
  ];
}

final NumberFormat _nf = NumberFormat('#,##0.####', 'en');
final DateFormat _df = DateFormat('yyyy/MM/dd', 'en');
String _fmt(num? v) => (v == null || v == 0) ? '' : _nf.format(v);

class _UnitLine {
  _UnitLine({String name = '', String qty = ''})
      : name = TextEditingController(text: name),
        qty = TextEditingController(text: qty);
  final TextEditingController name;
  final TextEditingController qty;
  void dispose() {
    name.dispose();
    qty.dispose();
  }
}

class _NewBarcode {
  final code = TextEditingController();
  final label = TextEditingController();
  void dispose() {
    code.dispose();
    label.dispose();
  }
}

class _MoreSection {
  const _MoreSection(this.title, this.icon, this.color);
  final String title;
  final IconData icon;
  final Color color;
}

class ItemCardEditorScreen extends StatefulWidget {
  const ItemCardEditorScreen({super.key, this.productId});

  /// null = مادة جديدة
  final int? productId;

  @override
  State<ItemCardEditorScreen> createState() => _ItemCardEditorScreenState();
}

class _ItemCardEditorScreenState extends State<ItemCardEditorScreen> {
  final _svc = ItemCardService();
  final _dbs = DatabaseService();

  int? _id;
  Product? _orig;
  Map<String, Object?> _baseline = const {};
  bool _loading = true;
  bool _saving = false;
  bool _newAfterSave = true;
  int _seq = 0;
  int _savedCount = 0;

  // ── الحقول الأساسية ──
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _barcode = TextEditingController();
  final _baseUnit = TextEditingController(text: 'قطعة');
  final List<_UnitLine> _units = [];
  final _price = List.generate(6, (_) => TextEditingController());
  final _markup = List.generate(6, (_) => TextEditingController());
  final _cost = TextEditingController();
  final _openQty = TextEditingController();
  String? _openUnit;
  final _weight = TextEditingController();
  final _alertQty = TextEditingController();
  String? _alertUnit;
  DateTime? _expiryDate;
  bool _weighable = false, _hasExpiry = false;
  int? _categoryId;

  // ── تفاصيل البطاقة (product_details) ──
  static const _detailText = [
    'second_name', 'brand', 'origin', 'shelf_location', 'notes', 'registration_no',
    'classification_no', 'customs_no', 'group2', 'group3', 'scale_code',
  ];
  static const _detailNum = [
    'min_qty', 'max_qty', 'reorder_qty', 'tax_percent', 'max_discount_percent', 'bonus_buy', 'bonus_free',
    'fixed_cost', 'opening_cost', 'price_rounding',
  ];
  final Map<String, TextEditingController> _dc = {
    for (final k in [..._detailText, ..._detailNum]) k: TextEditingController(),
  };
  bool _trackSerial = false, _scale = false, _active = true, _hideFromStaff = false;
  int? _supplierId, _warehouseId;
  String _costMethod = 'last', _itemType = 'trade', _pricingMode = 'fixed';
  String? _defaultUnit;

  // ── قوائم ومعلومات ──
  List<Map<String, Object?>> _cats = const [];
  List<Map<String, Object?>> _suppliers = const [];
  List<Map<String, Object?>> _barcodesList = const [];
  final List<_NewBarcode> _pendingBarcodes = [];
  List<Warehouse> _warehouses = const [];
  List<String> _allUnits = const [];
  List<MapEntry<Warehouse, double>> _balances = const [];
  double _reserved = 0;
  List<double> _sales30 = const [0, 0];
  Map<String, Object?>? _lastPurchase;

  final _nameFocus = FocusNode();
  final _price1Focus = FocusNode();

  bool get _canSeeCost => AuthService().hasPermission(AppPermissions.viewCostProfit);
  bool get _isNew => _id == null;
  bool get _showCost => _isNew || _canSeeCost;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final v = p.getBool('item_card_new_after_save');
      if (v != null && mounted) setState(() => _newAfterSave = v);
    }).catchError((_) {});
    _open(widget.productId);
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _barcode, _baseUnit, _cost, _openQty, _weight, _alertQty, ..._price, ..._markup]) {
      c.dispose();
    }
    for (final c in _dc.values) {
      c.dispose();
    }
    for (final u in _units) {
      u.dispose();
    }
    for (final b in _pendingBarcodes) {
      b.dispose();
    }
    _nameFocus.dispose();
    _price1Focus.dispose();
    super.dispose();
  }

  /// المتحكمات المحذوفة تُتلف بعد الإطار التالي (بعد أن تُزال حقولها من الشاشة).
  void _disposeLater(Iterable<ChangeNotifier> notifiers) {
    final list = notifiers.toList();
    if (list.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final n in list) {
        n.dispose();
      }
    });
  }

  // ═══════════════════════════ التحميل ═══════════════════════════

  String _unitDisplay(String? u) => (u == null || u.isEmpty || u == 'piece') ? 'قطعة' : (u == 'meter' ? 'متر' : u);

  String get _baseKey {
    final t = _baseUnit.text.trim();
    return (t.isEmpty || t == 'قطعة') ? 'piece' : (t == 'متر' ? 'meter' : t);
  }

  String get _baseName => _unitDisplay(_baseKey);

  List<Map<String, dynamic>> _parseHierarchy(String? h) {
    if (h == null || h.trim().isEmpty) return [];
    try {
      final list = jsonDecode(h.replaceAll("'", '"')) as List;
      return [
        for (final e in list)
          if (e is Map)
            {
              'unit_name': '${e['unit_name'] ?? e['name'] ?? ''}'.trim(),
              'quantity': (e['quantity'] is num)
                  ? (e['quantity'] as num).toDouble()
                  : (double.tryParse('${e['quantity']}') ?? 0.0),
            },
      ];
    } catch (_) {
      return [];
    }
  }

  void _resetForm() {
    for (final c in [_name, _code, _barcode, _cost, _openQty, _weight, _alertQty, ..._price, ..._markup]) {
      c.clear();
    }
    for (final c in _dc.values) {
      c.clear();
    }
    _baseUnit.text = 'قطعة';
    _disposeLater([for (final u in _units) ...[u.name, u.qty]]);
    _units
      ..clear()
      ..addAll([_UnitLine(), _UnitLine()]);
    _disposeLater([for (final b in _pendingBarcodes) ...[b.code, b.label]]);
    _pendingBarcodes.clear();
    _openUnit = null;
    _alertUnit = null;
    _expiryDate = null;
    _weighable = false;
    _hasExpiry = false;
    _categoryId = null;
    _trackSerial = false;
    _scale = false;
    _active = true;
    _hideFromStaff = false;
    _supplierId = null;
    _warehouseId = null;
    _costMethod = 'last';
    _itemType = 'trade';
    _pricingMode = 'fixed';
    _defaultUnit = null;
    _barcodesList = const [];
    _balances = const [];
    _reserved = 0;
    _sales30 = const [0, 0];
    _lastPurchase = null;
  }

  void _fill(Product p, Map<String, Object?> d) {
    _name.text = p.name;
    _barcode.text = p.barcode ?? '';
    _baseUnit.text = _unitDisplay(p.unit);
    final levels = _parseHierarchy(p.unitHierarchy);
    _disposeLater([for (final u in _units) ...[u.name, u.qty]]);
    _units
      ..clear()
      ..addAll([
        for (final l in levels) _UnitLine(name: l['unit_name'] as String, qty: _fmt(l['quantity'] as double)),
      ]);
    while (_units.length < 2) {
      _units.add(_UnitLine());
    }
    final prices = [p.price1, p.price2, p.price3, p.price4, p.price5, p.price6];
    for (var i = 0; i < 6; i++) {
      _price[i].text = _fmt(prices[i]);
    }
    if (_canSeeCost) _cost.text = _fmt(p.costPrice);
    _weighable = p.isWeighable;
    _weight.text = _fmt(p.baseWeight);
    _hasExpiry = p.hasExpiry || (d['track_expiry'] as int? ?? 0) == 1;
    _expiryDate = p.expiryDate;
    _alertQty.text = _fmt(p.alertQuantity);
    final names = levels.map((l) => l['unit_name'] as String).toList();
    _alertUnit = (p.alertUnit != null && names.contains(p.alertUnit)) ? p.alertUnit : null;
    _categoryId = p.categoryId;
    // التفاصيل
    _code.text = (d['item_code'] as String?) ?? '';
    for (final k in _detailText) {
      _dc[k]!.text = (d[k] as String?) ?? '';
    }
    for (final k in _detailNum) {
      _dc[k]!.text = _fmt(d[k] as num?);
    }
    for (var i = 0; i < 6; i++) {
      _markup[i].text = _fmt(d['markup${i + 1}'] as num?);
    }
    _trackSerial = (d['track_serial'] as int? ?? 0) == 1;
    _scale = (d['is_scale_item'] as int? ?? 0) == 1;
    _active = (d['is_active'] as int? ?? 1) == 1;
    _hideFromStaff = d['min_role'] == 'admin';
    _supplierId = d['default_supplier_id'] as int?;
    _warehouseId = d['default_warehouse_id'] as int?;
    _costMethod = (d['cost_method'] as String?) ?? 'last';
    _itemType = (d['item_type'] as String?) ?? (p.productType == 'service' ? 'service' : 'trade');
    _pricingMode = (d['pricing_mode'] as String?) ?? 'fixed';
    final du = d['default_unit'] as String?;
    _defaultUnit = (du != null && names.contains(du)) ? du : null;
  }

  Future<void> _open(int? id) async {
    final my = ++_seq;
    setState(() => _loading = true);
    try {
      final cats = await _svc.categories();
      final sups = await _svc.suppliers();
      List<Warehouse> whs = const [];
      try {
        whs = await OrgService().warehouses(activeOnly: true);
      } catch (_) {}
      List<String> units = _allUnits;
      try {
        units = await _dbs.getAllUnits();
      } catch (_) {}
      Product? p;
      Map<String, Object?> d = const {};
      if (id != null) {
        p = await _dbs.getProductById(id);
        if (p == null) {
          if (mounted) showError(context, 'المادة رقم $id غير موجودة');
          id = null;
        } else {
          d = await _svc.details(id);
        }
      }
      if (!mounted || my != _seq) return;
      _cats = cats;
      _suppliers = sups;
      _warehouses = whs;
      _allUnits = units;
      _resetForm();
      if (id != null && p != null) {
        _fill(p, d);
        try {
          _barcodesList = await _svc.barcodes(id);
        } catch (_) {}
        try {
          _balances = await _svc.balancesByWarehouse(id);
        } catch (_) {}
        try {
          _reserved = await ErpStockReserved.forProduct(await erpDb(), id);
        } catch (_) {}
        try {
          _sales30 = await _svc.recentSales(p.syncUuid);
        } catch (_) {}
        try {
          final lp = await _svc.lastPurchases(id);
          _lastPurchase = lp.isEmpty ? null : lp.first;
        } catch (_) {}
      } else {
        try {
          _code.text = await _svc.suggestCode();
        } catch (_) {}
      }
      _id = id;
      _orig = p;
      _baseline = _snapshot();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (!mounted || my != _seq) return;
    setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  // ═══════════════════════════ القيم ═══════════════════════════

  double? _p(TextEditingController c) => parseMoney(c.text);
  String? _nz(String s) => s.trim().isEmpty ? null : s.trim();

  /// مستويات الوحدات المكتملة (اسم + معامل > 0)
  List<Map<String, dynamic>> _levels() => [
        for (final u in _units)
          if (u.name.text.trim().isNotEmpty && (_p(u.qty) ?? 0) > 0)
            {'unit_name': u.name.text.trim(), 'quantity': _p(u.qty)!},
      ];

  List<String> get _unitNames => [_baseName, ..._levels().map((l) => l['unit_name'] as String)];

  double _factorOf(String? unitName) {
    if (unitName == null) return 1;
    var f = 1.0;
    for (final l in _levels()) {
      f *= (l['quantity'] as double);
      if (l['unit_name'] == unitName) return f;
    }
    return 1;
  }

  String? get _alertUnitKey => _alertUnit ?? _baseKey;

  double? get _alertQ {
    final q = _p(_alertQty);
    return (q == null || q == 0) ? null : q;
  }

  Map<String, Object?> _detailsValues() => {
        'item_code': _nz(_code.text),
        for (final k in _detailText) k: _nz(_dc[k]!.text),
        for (final k in _detailNum) k: _p(_dc[k]!),
        for (var i = 0; i < 6; i++) 'markup${i + 1}': _p(_markup[i]),
        'track_expiry': _hasExpiry ? 1 : 0,
        'track_serial': _trackSerial ? 1 : 0,
        'is_scale_item': _scale ? 1 : 0,
        'is_active': _active ? 1 : 0,
        'default_supplier_id': _supplierId,
        'default_warehouse_id': _warehouseId,
        'cost_method': _costMethod,
        'item_type': _itemType,
        'pricing_mode': _pricingMode,
        'default_unit': _defaultUnit,
        'min_role': _hideFromStaff ? 'admin' : null,
      };

  /// صورة كاملة لقيم النموذج — تُقارن بصورة لحظة الفتح لمعرفة ما تغيّر فعلاً.
  Map<String, Object?> _snapshot() {
    final levels = _levels();
    return {
      'name': _name.text.trim(),
      'unit': _baseKey,
      'barcode': _nz(_barcode.text),
      'category_id': _categoryId,
      'is_weighable': _weighable ? 1 : 0,
      'base_weight': _weighable ? _p(_weight) : null,
      'has_expiry': _hasExpiry ? 1 : 0,
      'expiry_date': _hasExpiry ? _expiryDate?.toIso8601String() : null,
      'alert_quantity': _alertQ,
      'alert_unit': _alertUnitKey,
      'unit_hierarchy': levels.isEmpty ? null : jsonEncode(levels),
      'cost_price': _p(_cost) ?? 0.0,
      for (var i = 0; i < 6; i++) 'price${i + 1}': _p(_price[i]) ?? 0.0,
      for (final e in _detailsValues().entries) 'd.${e.key}': e.value,
    };
  }

  bool get _hasChanges =>
      !_loading && (!mapEquals(_snapshot(), _baseline) || _pendingBarcodes.any((b) => b.code.text.trim().isNotEmpty));

  String _unitCostsJson(String baseKey, double cost, List<Map<String, dynamic>> levels) {
    final m = <String, double>{baseKey: cost};
    var c = cost;
    for (final l in levels) {
      c = c * (l['quantity'] as double);
      m[l['unit_name'] as String] = c;
    }
    return jsonEncode(m);
  }

  void _touch() => setState(() {});

  void _recalcMarkup(int i) {
    final cost = _p(_cost) ?? 0;
    final m = _p(_markup[i]);
    if (cost > 0 && m != null) {
      _price[i].text = _nf.format(roundToStep(cost * (1 + m / 100), _p(_dc['price_rounding']!) ?? 0));
    }
  }

  void _onCostChanged() {
    if (_pricingMode == 'markup') {
      for (var i = 0; i < 6; i++) {
        _recalcMarkup(i);
      }
    }
    _touch();
  }

  // ═══════════════════════════ الحفظ ═══════════════════════════

  void _warn(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: _C.orange,
      ));

  /// التحقق من الوحدات: كل سطر إما فارغ تماماً أو مكتمل، بلا تكرار.
  List<Map<String, dynamic>>? _validLevels() {
    final seen = <String>{_baseName};
    final out = <Map<String, dynamic>>[];
    for (final u in _units) {
      final n = u.name.text.trim();
      final q = _p(u.qty) ?? 0;
      if (n.isEmpty && q == 0) continue;
      if (n.isEmpty || q <= 0) {
        _warn(n.isEmpty ? 'اكتب اسم الوحدة التي معاملها ${_nf.format(q)}' : 'اكتب كم ${_unitNameBefore(u)} في «$n»');
        return null;
      }
      if (seen.contains(n)) {
        _warn('الوحدة «$n» مكررة');
        return null;
      }
      seen.add(n);
      out.add({'unit_name': n, 'quantity': q});
    }
    return out;
  }

  String _unitNameBefore(_UnitLine line) {
    var prev = _baseName;
    for (final u in _units) {
      if (identical(u, line)) return prev;
      if (u.name.text.trim().isNotEmpty) prev = u.name.text.trim();
    }
    return prev;
  }

  Future<bool> _codeTaken(String? code) async {
    if (code == null) return false;
    final db = await erpDb();
    final r = await db.query('product_details',
        columns: ['product_id'], where: 'item_code = ? AND product_id != ?', whereArgs: [code, _id ?? -1], limit: 1);
    return r.isNotEmpty;
  }

  Future<void> _registerUnits(List<Map<String, dynamic>> levels) async {
    try {
      for (final u in [_baseName, ...levels.map((l) => l['unit_name'] as String)]) {
        if (u.isNotEmpty && !_allUnits.contains(u)) await _dbs.addCustomUnit(u);
      }
    } catch (e) {
      debugPrint('⚠️ [بطاقة مادة] تسجيل الوحدات: $e');
    }
  }

  Future<List<String>> _flushBarcodes(int id) async {
    final notes = <String>[];
    for (final b in _pendingBarcodes) {
      final code = b.code.text.trim();
      if (code.isEmpty) continue;
      try {
        await _svc.addBarcode(id, code, b.label.text);
      } catch (e) {
        notes.add('لم يُحفظ الباركود $code: $e');
      }
    }
    return notes;
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    final isNew = _isNew;
    if (isNew && !requirePermission(context, AppPermissions.productEntry)) return;
    if (_name.text.trim().isEmpty) {
      _warn('اكتب اسم المادة');
      _nameFocus.requestFocus();
      return;
    }
    final levels = _validLevels();
    if (levels == null) return;
    if ((_p(_price[0]) ?? 0) <= 0) {
      _warn('سعر المفرد مطلوب');
      _price1Focus.requestFocus();
      return;
    }
    final v = _snapshot();
    final changed = isNew ? v.keys.toSet() : {for (final k in v.keys) if (v[k] != _baseline[k]) k};
    final hasNewBarcodes = _pendingBarcodes.any((b) => b.code.text.trim().isNotEmpty);
    if (!isNew && changed.isEmpty && !hasNewBarcodes) {
      showOk(context, 'لا توجد تعديلات');
      return;
    }
    // رمز المادة مكرر؟
    if ((isNew || changed.contains('d.item_code')) && await _codeTaken(v['d.item_code'] as String?)) {
      if (!mounted) return;
      _warn('رمز المادة ${v['d.item_code']} مستخدم لمادة أخرى');
      return;
    }
    // سعر أقل من الكلفة؟
    final cost = (v['cost_price'] as double?) ?? 0;
    if (cost > 0 && (isNew || changed.any((k) => k.startsWith('price') || k == 'cost_price'))) {
      final below = [
        for (var i = 0; i < 6; i++)
          if ((v['price${i + 1}'] as double) > 0 && (v['price${i + 1}'] as double) < cost) priceFieldNames[i],
      ];
      if (below.isNotEmpty) {
        if (!mounted) return;
        final ok = await confirmDialog(context, 'سعر أقل من الكلفة',
            'الكلفة ${_nf.format(cost)} د.ع، وهذه الأسعار أقل منها (بيع بخسارة): ${below.join('، ')}.',
            ok: 'حفظ رغم ذلك', color: _C.orange);
        if (!ok) return;
      }
    }
    // باركود مستعمل لمادة أخرى؟
    final bc = v['barcode'] as String?;
    if (bc != null && (isNew || changed.contains('barcode'))) {
      try {
        final other = await _dbs.findProductByBarcode(bc);
        if (other != null && other.id != _id) {
          if (!mounted) return;
          final ok = await confirmDialog(context, 'باركود مستعمل',
              'الباركود $bc مستعمل للمادة «${other.name}». حفظه لهذه المادة أيضاً؟',
              ok: 'حفظ رغم ذلك', color: _C.orange);
          if (!ok) return;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      if (isNew) {
        await _insertNew(v, levels);
      } else {
        await _updateExisting(v, changed, levels);
      }
    } on DuplicateProductNameException catch (e) {
      if (mounted) showError(context, e);
      _nameFocus.requestFocus();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _insertNew(Map<String, Object?> v, List<Map<String, dynamic>> levels) async {
    final baseKey = v['unit'] as String;
    final cost = (v['cost_price'] as double?) ?? 0;
    final service = _itemType == 'service';
    await _registerUnits(levels);
    final now = DateTime.now();
    final product = Product(
      name: v['name'] as String,
      unit: baseKey,
      barcode: v['barcode'] as String?,
      categoryId: _categoryId,
      isWeighable: _weighable,
      baseWeight: _weighable ? v['base_weight'] as double? : null,
      weightUnit: _weighable ? 'kg' : null,
      hasExpiry: _hasExpiry,
      expiryDate: _hasExpiry ? _expiryDate : null,
      costPrice: cost,
      unitPrice: v['price1'] as double,
      price1: v['price1'] as double,
      price2: v['price2'] as double,
      price3: v['price3'] as double,
      price4: v['price4'] as double,
      price5: v['price5'] as double,
      price6: v['price6'] as double,
      stockQuantity: service ? 0 : (_p(_openQty) ?? 0) * _factorOf(_openUnit),
      unitHierarchy: v['unit_hierarchy'] as String?,
      unitCosts: _unitCostsJson(baseKey, cost, levels),
      alertQuantity: v['alert_quantity'] as double?,
      alertUnit: v['alert_unit'] as String?,
      productType: service ? 'service' : 'storable',
      createdAt: now,
      lastModifiedAt: now,
    );
    final id = await _dbs.insertProduct(product);
    final notes = <String>[];
    try {
      await _svc.saveDetails(id, _detailsValues());
    } catch (e) {
      notes.add('$e');
    }
    notes.addAll(await _flushBarcodes(id));
    _savedCount++;
    if (!mounted) return;
    final msg = 'حُفظت «${product.name}» برقم $id${notes.isEmpty ? '' : ' — ${notes.join('، ')}'}';
    await _open(_newAfterSave ? null : id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: notes.isEmpty ? _C.green : _C.orange,
      duration: const Duration(seconds: 5),
      action: _newAfterSave
          ? SnackBarAction(label: 'فتحها', textColor: Colors.white, onPressed: () => _open(id))
          : null,
    ));
  }

  Future<void> _updateExisting(Map<String, Object?> v, Set<String> changed, List<Map<String, dynamic>> levels) async {
    final id = _id!;
    final auth = AuthService();
    final productKeys = changed.where((k) => !k.startsWith('d.')).toSet();
    final priceKeys = productKeys.where((k) => RegExp(r'^price[1-6]$').hasMatch(k)).toSet();
    final colKeys = productKeys.difference(priceKeys);
    final detailKeys = changed.where((k) => k.startsWith('d.')).map((k) => k.substring(2)).toSet();
    if (productKeys.isNotEmpty && !auth.hasPermission(AppPermissions.editProducts)) {
      throw Exception('ليس لديك صلاحية «تعديل البضاعة» (الاسم والوحدات والأسعار والكلفة)');
    }
    if (detailKeys.isNotEmpty &&
        !(auth.hasPermission(AppPermissions.itemCard) || auth.hasPermission(AppPermissions.editProducts))) {
      throw Exception('ليس لديك صلاحية تعديل بطاقة المادة');
    }
    final cur = await _dbs.getProductById(id);
    if (cur == null) throw Exception('المادة غير موجودة (ربما حُذفت من جهاز آخر)');
    final typeChanged = detailKeys.contains('item_type') && ((_itemType == 'service') != (cur.productType == 'service'));
    var touched = false;
    if (colKeys.isNotEmpty || typeChanged) {
      final m = <String, Object?>{for (final k in colKeys) k: v[k]};
      if (colKeys.contains('is_weighable') || colKeys.contains('base_weight')) {
        m['is_weighable'] = v['is_weighable'];
        m['base_weight'] = v['base_weight'];
        m['weight_unit'] = _weighable ? 'kg' : null;
      }
      if (colKeys.contains('has_expiry') || colKeys.contains('expiry_date')) {
        m['has_expiry'] = v['has_expiry'];
        m['expiry_date'] = v['expiry_date'];
      }
      if (colKeys.contains('unit') || colKeys.contains('unit_hierarchy') || colKeys.contains('cost_price')) {
        final cost = colKeys.contains('cost_price') ? (v['cost_price'] as double) : (cur.costPrice ?? 0);
        m['unit'] = v['unit'];
        m['unit_hierarchy'] = v['unit_hierarchy'];
        m['unit_costs'] = _unitCostsJson(v['unit'] as String, cost, levels);
        await _registerUnits(levels);
      }
      if (typeChanged) {
        m['product_type'] = _itemType == 'service' ? 'service' : 'storable';
      }
      m['last_modified_at'] = DateTime.now().toIso8601String();
      await _dbs.updateProduct(Product.fromMap({...cur.toMap(), ...m}));
      touched = true;
    }
    if (priceKeys.isNotEmpty) {
      final changes = {for (final k in priceKeys) int.parse(k.substring(5)): v[k] as double};
      if (await PriceTools().applyPrices(id, changes) > 0) touched = true;
    }
    if (detailKeys.isNotEmpty) {
      await _svc.saveDetails(id, {for (final k in detailKeys) k: v['d.$k'], 'item_code': v['d.item_code']});
      // 🔄 تغيّرت التفاصيل فقط: نلمس وقت تعديل المادة لتُرفع بطاقتها للفروع
      if (!touched) {
        final fresh = await _dbs.getProductById(id);
        if (fresh != null) await _dbs.updateProduct(fresh.copyWith(lastModifiedAt: DateTime.now()));
      }
    }
    final notes = await _flushBarcodes(id);
    _savedCount++;
    if (!mounted) return;
    await _open(id);
    if (mounted) showOk(context, notes.isEmpty ? 'حُفظت التعديلات' : 'حُفظت التعديلات — ${notes.join('، ')}');
  }

  // ═══════════════════════════ التنقل ═══════════════════════════

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    return confirmDialog(context, 'تعديلات غير محفوظة', 'على هذه البطاقة تعديلات لم تُحفظ. تجاهلها؟',
        ok: 'تجاهل التعديلات', color: _C.red);
  }

  Future<void> _newCard() async {
    if (!await _confirmDiscard()) return;
    await _open(null);
  }

  Future<void> _step(bool next) async {
    if (!await _confirmDiscard()) return;
    try {
      final db = await erpDb();
      final hide = AuthService().isAdmin
          ? ''
          : " AND COALESCE((SELECT d.min_role FROM product_details d WHERE d.product_id = p.id), '') != 'admin'";
      final from = _id ?? (next ? 0 : 9007199254740991);
      final r = await db.rawQuery(
          'SELECT p.id FROM products p WHERE COALESCE(p.is_deleted, 0) = 0 AND p.id ${next ? '>' : '<'} ?$hide '
          'ORDER BY p.id ${next ? 'ASC' : 'DESC'} LIMIT 1',
          [from]);
      if (r.isEmpty) {
        if (mounted) showOk(context, next ? 'هذه آخر مادة' : 'هذه أول مادة');
        return;
      }
      await _open(r.first['id'] as int);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _search() async {
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    final id = await showDialog<int>(context: context, builder: (_) => _ItemSearchDialog(svc: _svc));
    if (id != null) await _open(id);
  }

  Future<void> _openExtended() async {
    final id = _id;
    if (id == null) return;
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ItemCardScreen(productId: id)));
    if (mounted) await _open(id);
  }

  Future<void> _setNewAfterSave(bool v) async {
    setState(() => _newAfterSave = v);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('item_card_new_after_save', v);
    } catch (_) {}
  }

  // ═══════════════════════════ عناصر الواجهة ═══════════════════════════

  InputDecoration _dec({String? hint, Widget? suffix, String? suffixText, bool enabled = true}) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
        suffixIcon: suffix,
        suffixText: suffixText,
        suffixStyle: const TextStyle(color: _C.muted, fontSize: 12),
        filled: true,
        fillColor: enabled ? _C.field : const Color(0xFFEFF2F6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _C.border)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _C.border)),
        disabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _C.border)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _C.cyan, width: 1.6)),
      );

  Widget _label(String t, {bool required = false}) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 2, bottom: 4),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: t),
            if (required) const TextSpan(text: ' *', style: TextStyle(color: _C.red)),
          ]),
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _C.muted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );

  Widget _input(
    TextEditingController c, {
    bool number = false,
    String? hint,
    FocusNode? focus,
    ValueChanged<String>? onChanged,
    Widget? suffix,
    String? suffixText,
    bool enabled = true,
    int maxLines = 1,
    TextStyle? style,
  }) =>
      TextField(
        controller: c,
        focusNode: focus,
        enabled: enabled,
        maxLines: maxLines,
        style: style ?? const TextStyle(fontSize: 13.5, color: _C.text),
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
        inputFormatters: number ? [ThousandSeparatorDecimalInputFormatter()] : null,
        textDirection: number ? TextDirection.ltr : null,
        textAlign: number ? TextAlign.end : TextAlign.start,
        textInputAction: maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
        decoration: _dec(hint: hint, suffix: suffix, suffixText: suffixText, enabled: enabled),
        onChanged: (s) {
          onChanged?.call(s);
          _touch();
        },
      );

  Widget _field(String label, TextEditingController c,
          {bool number = false,
          String? hint,
          bool required = false,
          FocusNode? focus,
          ValueChanged<String>? onChanged,
          Widget? suffix,
          String? suffixText,
          bool enabled = true,
          int maxLines = 1}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        _label(label, required: required),
        _input(c,
            number: number,
            hint: hint,
            focus: focus,
            onChanged: onChanged,
            suffix: suffix,
            suffixText: suffixText,
            enabled: enabled,
            maxLines: maxLines),
      ]);

  Widget _drop<T>(String label, T? value, List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged,
          {bool enabled = true}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        _label(label),
        DropdownButtonFormField<T>(
          value: items.any((i) => i.value == value) ? value : null,
          items: items,
          isExpanded: true,
          isDense: true,
          style: const TextStyle(fontSize: 13.5, color: _C.text, fontFamily: 'Cairo'),
          icon: const Icon(Icons.expand_more, size: 18, color: _C.muted),
          borderRadius: BorderRadius.circular(10),
          decoration: _dec(enabled: enabled),
          onChanged: enabled ? onChanged : null,
        ),
      ]);

  /// شبكة حقول متجاوبة: [cols] أعمدة متساوية.
  Widget _grid(List<Widget> children, {int cols = 2, double gap = 12}) => LayoutBuilder(builder: (context, box) {
        final c = box.maxWidth < 360 ? 1 : cols;
        final w = (box.maxWidth - gap * (c - 1)) / c;
        return Wrap(spacing: gap, runSpacing: 10, children: [
          for (final ch in children) SizedBox(width: w, child: ch),
        ]);
      });

  Widget _card({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
    Widget? trailing,
    String? subtitle,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: _C.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: _C.text)),
                  if (subtitle != null)
                    Text(subtitle,
                        style: const TextStyle(fontSize: 11.5, color: _C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (trailing != null) trailing,
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 14), child: child),
        ]),
      );

  Widget _pill(String text, Color color, {IconData? icon, VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
            Text(text, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  // ═══════════════════════════ البناء ═══════════════════════════

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop(_savedCount > 0);
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newCard,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): _search,
          const SingleActivator(LogicalKeyboardKey.pageDown, control: true): () => _step(true),
          const SingleActivator(LogicalKeyboardKey.pageUp, control: true): () => _step(false),
        },
        child: Scaffold(
          backgroundColor: _C.bg,
          body: Column(children: [
            _header(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : KeyedSubtree(key: ValueKey('card_$_seq'), child: _body()),
            ),
            _bottomBar(),
          ]),
        ),
      ),
    );
  }

  Widget _header() {
    final title = _isNew ? 'مادة جديدة' : (_orig?.name ?? '');
    final sub = _isNew
        ? 'تعريف مادة جديدة — الحقول المعلّمة * مطلوبة'
        : [
            'رقم ${_id ?? ''}',
            if (_code.text.trim().isNotEmpty) 'رمز ${_code.text.trim()}',
            if (_orig != null) 'آخر تعديل ${_df.format(_orig!.lastModifiedAt)}',
          ].join('  •  ');
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white, size: 21),
          style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.10)),
        );
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_C.navy, _C.navy2], begin: Alignment.centerRight, end: Alignment.centerLeft),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            IconButton(
              tooltip: 'رجوع',
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.maybePop(context),
            ),
            const SizedBox(width: 4),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
              child: Icon(_isNew ? Icons.add_box_outlined : Icons.inventory_2_outlined, color: Colors.white, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Text('بطاقة مادة', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.bold)),
                  ),
                ]),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5)),
              ]),
            ),
            btn(Icons.search, 'بحث عن مادة (Ctrl+F)', _search),
            const SizedBox(width: 6),
            btn(Icons.chevron_left, 'المادة السابقة (Ctrl+PageUp)', () => _step(false)),
            const SizedBox(width: 4),
            btn(Icons.chevron_right, 'المادة التالية (Ctrl+PageDown)', () => _step(true)),
            const SizedBox(width: 6),
            btn(Icons.add, 'مادة جديدة (Ctrl+N)', _newCard),
          ]),
        ),
      ),
    );
  }

  Widget _body() {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1100;
      final cards = [
        FocusTraversalGroup(child: _unitsCard()),
        FocusTraversalGroup(child: _pricesCard()),
        FocusTraversalGroup(child: _stockCard()),
      ];
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FocusTraversalGroup(child: _heroCard(wide)),
          const SizedBox(height: 14),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 10, child: cards[0]),
              const SizedBox(width: 14),
              Expanded(flex: 11, child: cards[1]),
              const SizedBox(width: 14),
              Expanded(flex: 10, child: cards[2]),
            ])
          else
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              cards[0],
              const SizedBox(height: 14),
              cards[1],
              const SizedBox(height: 14),
              cards[2],
            ]),
        ]),
      );
    });
  }

  // ─────────────── البطاقة العلوية: الاسم والتعريف ───────────────

  Widget _heroCard(bool wide) {
    final chips = _activeChips();
    final nameField = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _label('اسم المادة', required: true),
      TextField(
        controller: _name,
        focusNode: _nameFocus,
        textInputAction: TextInputAction.next,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _C.text),
        decoration: _dec(hint: 'مثال: قاطع 32 أمبير ثنائي').copyWith(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        ),
        onChanged: (_) => _touch(),
      ),
    ]);
    final idFields = [
      _field('رقم المادة (الرمز)', _code,
          hint: 'تلقائي',
          suffix: IconButton(
            tooltip: 'رمز تلقائي جديد',
            icon: const Icon(Icons.auto_awesome, size: 17, color: _C.cyan),
            onPressed: () async {
              try {
                _code.text = await _svc.suggestCode();
                _touch();
              } catch (_) {}
            },
          )),
      _drop<int?>(
        'القسم',
        _categoryId,
        [
          const DropdownMenuItem<int?>(value: null, child: Text('— بلا قسم —')),
          for (final c in _cats) DropdownMenuItem<int?>(value: c['id'] as int, child: Text('${c['name']}')),
        ],
        (v) => setState(() => _categoryId = v),
      ),
      _field('الباركود', _barcode, hint: 'امسح أو اكتب', suffix: const Icon(Icons.qr_code_scanner, size: 18, color: _C.muted)),
    ];
    final stats = _isNew ? <Widget>[] : _heroStats();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 5,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                nameField,
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: idFields[0]),
                  const SizedBox(width: 12),
                  Expanded(child: idFields[1]),
                  const SizedBox(width: 12),
                  Expanded(child: idFields[2]),
                ]),
              ]),
            ),
            if (stats.isNotEmpty) ...[
              const SizedBox(width: 16),
              SizedBox(
                width: 300,
                child: Wrap(spacing: 8, runSpacing: 8, children: stats),
              ),
            ],
          ])
        else ...[
          nameField,
          const SizedBox(height: 12),
          _grid(idFields, cols: 3),
          if (stats.isNotEmpty) ...[const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: stats)],
        ],
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: chips.isEmpty
                ? const Text('الحقول الإضافية (الماركة، الصلاحية، الحدود، المورد، الضريبة…) في «المزيد» — أغلب المواد لا تحتاجها.',
                    style: TextStyle(fontSize: 12, color: _C.muted))
                : Wrap(spacing: 6, runSpacing: 6, children: chips),
          ),
          const SizedBox(width: 10),
          _moreButton(),
        ]),
      ]),
    );
  }

  Widget _moreButton() {
    final n = _advancedCount;
    return Stack(clipBehavior: Clip.none, children: [
      OutlinedButton.icon(
        onPressed: () => _openMore(),
        icon: const Icon(Icons.tune, size: 18),
        label: const Text('المزيد'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _C.navy,
          side: const BorderSide(color: _C.border, width: 1.2),
          backgroundColor: _C.field,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      if (n > 0)
        PositionedDirectional(
          top: -6,
          start: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: _C.cyan, borderRadius: BorderRadius.circular(10)),
            child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ),
    ]);
  }

  List<Widget> _heroStats() {
    final p = _orig!;
    final stock = p.stockQuantity;
    Widget stat(String label, String value, Color color, {String? sub}) => Container(
          width: 146,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: _C.muted)),
            Text(value,
                textDirection: TextDirection.ltr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            if (sub != null)
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: _C.muted)),
          ]),
        );
    return [
      if (_itemType != 'service')
        stat('الرصيد', _nf.format(stock), stock <= 0 ? _C.red : _C.stock, sub: _baseName),
      stat('سعر المفرد', _nf.format(p.price1), _C.prices),
      if (_canSeeCost && _itemType != 'service')
        stat('قيمة المخزون', _nf.format(stock * (p.costPrice ?? 0)), _C.navy, sub: 'بالكلفة'),
      stat('مبيعات 30 يوماً', _nf.format(_sales30[0]), _C.green, sub: '${_nf.format(_sales30[1])} د.ع'),
    ];
  }

  /// شارات الإعدادات الإضافية المفعّلة (تفتح «المزيد» على قسمها).
  List<Widget> _activeChips() {
    final out = <Widget>[];
    void add(String t, IconData i, Color c, int section) =>
        out.add(_pill(t, c, icon: i, onTap: () => _openMore(section)));
    if (_itemType != 'trade') add(itemTypeLabels[_itemType] ?? _itemType, Icons.category_outlined, _C.prices, 0);
    if (_dc['brand']!.text.trim().isNotEmpty) add(_dc['brand']!.text.trim(), Icons.verified_outlined, _C.navy, 0);
    if (!_active) add('موقوفة', Icons.block, _C.red, 7);
    if (_hideFromStaff) add('مخفية عن الموظفين', Icons.visibility_off_outlined, _C.red, 7);
    if (_hasExpiry) {
      add(_expiryDate == null ? 'لها صلاحية' : 'صلاحية ${_df.format(_expiryDate!)}', Icons.event_outlined, _C.orange, 5);
    }
    if (_weighable) add('تباع بالوزن', Icons.scale_outlined, _C.units, 5);
    if (_trackSerial) add('رقم تسلسلي', Icons.pin_outlined, _C.stock, 5);
    if (_scale) add('مادة ميزان', Icons.monitor_weight_outlined, _C.units, 5);
    if ((_p(_dc['tax_percent']!) ?? 0) > 0) add('ضريبة ${_dc['tax_percent']!.text}%', Icons.percent, _C.navy, 1);
    if ((_p(_dc['bonus_buy']!) ?? 0) > 0 && (_p(_dc['bonus_free']!) ?? 0) > 0) {
      add('هدية ${_dc['bonus_free']!.text} لكل ${_dc['bonus_buy']!.text}', Icons.card_giftcard, _C.green, 2);
    }
    if ((_p(_dc['min_qty']!) ?? 0) > 0) add('حد أدنى ${_dc['min_qty']!.text}', Icons.trending_down, _C.orange, 4);
    if (_dc['shelf_location']!.text.trim().isNotEmpty) add('رف ${_dc['shelf_location']!.text.trim()}', Icons.shelves, _C.stock, 4);
    if (_supplierId != null) {
      final s = _suppliers.where((x) => x['id'] == _supplierId);
      if (s.isNotEmpty) add('${s.first['name']}', Icons.local_shipping_outlined, _C.orange, 4);
    }
    final bcs = _barcodesList.length + _pendingBarcodes.where((b) => b.code.text.trim().isNotEmpty).length;
    if (bcs > 0) add('$bcs باركود إضافي', Icons.qr_code_2, _C.navy, 6);
    return out;
  }

  int get _advancedCount {
    var n = 0;
    for (final k in _detailText) {
      if (_dc[k]!.text.trim().isNotEmpty) n++;
    }
    for (final k in _detailNum) {
      if ((_p(_dc[k]!) ?? 0) != 0) n++;
    }
    if (_itemType != 'trade') n++;
    if (_trackSerial) n++;
    if (_scale) n++;
    if (_hasExpiry) n++;
    if (_weighable) n++;
    if (!_active) n++;
    if (_hideFromStaff) n++;
    if (_supplierId != null) n++;
    if (_warehouseId != null) n++;
    if (_costMethod != 'last') n++;
    if (_defaultUnit != null) n++;
    n += _barcodesList.length + _pendingBarcodes.where((b) => b.code.text.trim().isNotEmpty).length;
    return n;
  }

  // ─────────────── الوحدات ───────────────

  Widget _unitsCard() {
    final levels = _levels();
    final chain = <String>[];
    var f = 1.0;
    for (final l in levels) {
      f *= l['quantity'] as double;
      chain.add('1 ${l['unit_name']} = ${_nf.format(f)} $_baseName');
    }
    return _card(
      title: 'الوحدات',
      subtitle: 'الوحدة الأساسية ثم الوحدات الأكبر ومعامل كل منها',
      icon: Icons.layers_outlined,
      color: _C.units,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _field('الوحدة الأساسية (الأصغر)', _baseUnit,
            required: true,
            suffix: PopupMenuButton<String>(
              tooltip: 'اختيار وحدة',
              icon: const Icon(Icons.arrow_drop_down, color: _C.muted),
              itemBuilder: (_) => [
                for (final u in {'قطعة', 'متر', 'كيلو', 'لفة', 'علبة', 'طقم', ..._allUnits}) PopupMenuItem(value: u, child: Text(u)),
              ],
              onSelected: (u) => setState(() => _baseUnit.text = u),
            )),
        const SizedBox(height: 10),
        for (var i = 0; i < _units.length; i++) _unitLineRow(i),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _units.length >= 5 ? null : () => setState(() => _units.add(_UnitLine())),
            icon: const Icon(Icons.add, size: 17),
            label: const Text('وحدة أكبر'),
            style: TextButton.styleFrom(foregroundColor: _C.units),
          ),
        ),
        if (chain.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _C.units.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in chain) _pill(c, _C.units, icon: Icons.swap_horiz),
            ]),
          ),
      ]),
    );
  }

  Widget _unitLineRow(int i) {
    final u = _units[i];
    final prev = _unitNameBefore(u);
    return Padding(
      key: ObjectKey(u),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          flex: 5,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _label('الوحدة ${i + 2}'),
            LayoutBuilder(builder: (context, box) => Autocomplete<String>(
              initialValue: TextEditingValue(text: u.name.text),
              optionsBuilder: (t) {
                final all = {'كرتون', 'باكيت', 'درزن', 'صندوق', 'شدة', 'لفة', 'كيس', 'كونية', ..._allUnits};
                final q = t.text.trim();
                return q.isEmpty ? all : all.where((x) => x.contains(q));
              },
              onSelected: (s) {
                u.name.text = s;
                _touch();
              },
              // قائمة الاقتراحات بعرض الحقل نفسه وتحته مباشرة (لا تغطي حقل المعامل)
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: AlignmentDirectional.topStart,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth, maxHeight: 220),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        for (final o in options)
                          InkWell(
                            onTap: () => onSelected(o),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              child: Text(o, style: const TextStyle(fontSize: 13.5)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              fieldViewBuilder: (context, ctrl, focus, onSubmit) {
                return TextField(
                  controller: ctrl,
                  focusNode: focus,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(fontSize: 13.5, color: _C.text),
                  decoration: _dec(hint: i == 0 ? 'مثال: كرتون' : 'مثال: صندوق'),
                  onChanged: (s) {
                    u.name.text = s;
                    _touch();
                  },
                );
              },
            )),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text('=', style: TextStyle(fontSize: 16, color: _C.muted, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          flex: 5,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _label('كم $prev فيها'),
            _input(u.qty, number: true, hint: '0', suffixText: prev),
          ]),
        ),
        SizedBox(
          width: 34,
          child: IconButton(
            tooltip: 'حذف الوحدة',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 17, color: _C.muted),
            onPressed: () => setState(() {
              if (_units.length > 1) {
                final gone = _units.removeAt(i);
                _disposeLater([gone.name, gone.qty]);
              } else {
                u.name.clear();
                u.qty.clear();
              }
            }),
          ),
        ),
      ]),
    );
  }

  // ─────────────── الكلفة والأسعار ───────────────

  Widget _pricesCard() {
    final cost = _p(_cost) ?? 0;
    return _card(
      title: 'الكلفة والأسعار',
      subtitle: _pricingMode == 'markup' ? 'الأسعار بنسبة ربح على الكلفة' : 'سعر كل مستوى لوحدة $_baseName',
      icon: Icons.sell_outlined,
      color: _C.prices,
      trailing: SegmentedButton<String>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 12, fontFamily: 'Cairo'),
          selectedBackgroundColor: _C.prices.withValues(alpha: 0.12),
          selectedForegroundColor: _C.prices,
        ),
        segments: const [
          ButtonSegment(value: 'fixed', label: Text('ثابتة')),
          ButtonSegment(value: 'markup', label: Text('نسبة %')),
        ],
        selected: {_pricingMode},
        onSelectionChanged: (s) => setState(() => _pricingMode = s.first),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_showCost)
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: _field(_isNew ? 'كلفة الوحدة الأساسية' : 'الكلفة الحالية', _cost,
                  number: true, hint: '0', suffixText: 'د.ع', onChanged: (_) => _onCostChanged()),
            ),
            if (_pricingMode == 'markup') ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 130,
                child: _field('التقريب لأقرب', _dc['price_rounding']!, number: true, hint: '250', onChanged: (_) {
                  for (var i = 0; i < 6; i++) {
                    _recalcMarkup(i);
                  }
                }),
              ),
            ],
          ]),
        if (_showCost) const SizedBox(height: 12),
        _grid([for (var i = 0; i < 6; i++) _priceTile(i, cost)], cols: 2, gap: 10),
      ]),
    );
  }

  Widget _priceTile(int i, double cost) {
    final color = _C.tiers[i];
    final price = _p(_price[i]) ?? 0;
    final showProfit = _showCost && cost > 0 && price > 0;
    final pct = showProfit ? (price / cost - 1) * 100 : 0.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: priceFieldNames[i]),
                if (i == 0) const TextSpan(text: ' *', style: TextStyle(color: _C.red)),
              ]),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          if (showProfit)
            Text('${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(pct.abs() < 10 ? 1 : 0)}%',
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: pct < 0 ? _C.red : _C.green)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _price[i],
              focusNode: i == 0 ? _price1Focus : null,
              textInputAction: TextInputAction.next,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _C.text),
              decoration: _dec(hint: '0').copyWith(fillColor: Colors.white),
              onChanged: (_) {
                if (_pricingMode == 'markup' && cost > 0) {
                  final pr = _p(_price[i]) ?? 0;
                  _markup[i].text = pr > 0 ? (((pr / cost) - 1) * 100).toStringAsFixed(1) : '';
                }
                _touch();
              },
            ),
          ),
          if (_pricingMode == 'markup') ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 74,
              child: _input(_markup[i], number: true, hint: '%', suffixText: '%', onChanged: (_) => _recalcMarkup(i)),
            ),
          ],
        ]),
      ]),
    );
  }

  // ─────────────── المخزون ───────────────

  Widget _stockCard() {
    final unitItems = [
      DropdownMenuItem<String?>(value: null, child: Text(_baseName)),
      for (final n in _unitNames.skip(1)) DropdownMenuItem<String?>(value: n, child: Text(n)),
    ];
    final alertRow = Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: _field('تنبيه عند نقص الرصيد عن', _alertQty, number: true, hint: 'بلا تنبيه')),
      const SizedBox(width: 8),
      SizedBox(width: 120, child: _drop<String?>('الوحدة', _alertUnit, unitItems, (v) => setState(() => _alertUnit = v))),
    ]);
    if (_itemType == 'service') {
      return _card(
        title: 'المخزون',
        icon: Icons.warehouse_outlined,
        color: _C.stock,
        child: const Text('هذه المادة خدمة — لا رصيد لها في المخزن.', style: TextStyle(color: _C.muted)),
      );
    }
    if (_isNew) {
      final open = (_p(_openQty) ?? 0) * _factorOf(_openUnit);
      return _card(
        title: 'المخزون',
        subtitle: 'الكمية الموجودة الآن تُسجَّل رصيداً افتتاحياً',
        icon: Icons.warehouse_outlined,
        color: _C.stock,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: _field('الكمية الافتتاحية', _openQty, number: true, hint: '0')),
            const SizedBox(width: 8),
            SizedBox(width: 120, child: _drop<String?>('الوحدة', _openUnit, unitItems, (v) => setState(() => _openUnit = v))),
          ]),
          if (_openUnit != null && open > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('= ${_nf.format(open)} $_baseName', style: const TextStyle(fontSize: 12, color: _C.stock)),
            ),
          const SizedBox(height: 12),
          alertRow,
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _C.stock.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 16, color: _C.stock),
              SizedBox(width: 8),
              Expanded(
                child: Text('بعد الحفظ تتغيّر الكمية بالفواتير والمستندات المخزنية والجرد فقط.',
                    style: TextStyle(fontSize: 11.5, color: _C.muted)),
              ),
            ]),
          ),
        ]),
      );
    }
    final p = _orig!;
    final stock = p.stockQuantity;
    final lp = _lastPurchase;
    return _card(
      title: 'المخزون',
      subtitle: 'الرصيد يتغيّر بالمستندات والجرد فقط',
      icon: Icons.warehouse_outlined,
      color: _C.stock,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_C.stock.withValues(alpha: 0.10), _C.stock.withValues(alpha: 0.03)]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('الرصيد الحالي', style: TextStyle(fontSize: 11.5, color: _C.muted)),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(_nf.format(stock),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: stock <= 0 ? _C.red : _C.stock)),
                const SizedBox(width: 6),
                Text(_baseName, style: const TextStyle(fontSize: 12.5, color: _C.muted)),
              ]),
            ]),
            const Spacer(),
            if (_reserved > 0)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _pill('محجوز ${_nf.format(_reserved)}', _C.prices),
                const SizedBox(height: 4),
                _pill('متاح ${_nf.format(stock - _reserved)}', _C.green),
              ]),
          ]),
        ),
        if (_balances.length > 1) ...[
          const SizedBox(height: 10),
          for (final b in _balances.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                const Icon(Icons.store_mall_directory_outlined, size: 15, color: _C.muted),
                const SizedBox(width: 6),
                Expanded(child: Text(b.key.name, style: const TextStyle(fontSize: 12.5))),
                Text(_nf.format(b.value),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: b.value <= 0 ? _C.red : _C.text)),
              ]),
            ),
        ],
        const SizedBox(height: 12),
        alertRow,
        if (lp != null && _canSeeCost) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.history, size: 15, color: _C.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'آخر شراء: ${_nf.format(d0(lp['unit_price']))} لـ${lp['unit_name'] ?? _baseName}'
                '${lp['supplier'] != null ? ' من ${lp['supplier']}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _C.muted),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  // ─────────────── الشريط السفلي ───────────────

  Widget _bottomBar() {
    final dirty = _hasChanges;
    final save = FilledButton.icon(
      onPressed: (_saving || _loading) ? null : _save,
      icon: _saving
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.check_circle_outline, size: 19),
      label: Text(_isNew ? 'حفظ المادة' : 'حفظ التعديلات'),
      style: FilledButton.styleFrom(
        backgroundColor: _C.green,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Cairo'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    Widget tb(IconData icon, String label, VoidCallback? onTap) => TextButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: TextButton.styleFrom(foregroundColor: _C.navy),
        );
    final left = <Widget>[
      save,
      const SizedBox(width: 8),
      tb(Icons.add, 'جديد', _newCard),
      if (!_isNew) ...[
        tb(Icons.open_in_new, 'البطاقة الموسّعة', _openExtended),
        tb(Icons.qr_code_2, 'ملصق باركود', () => BarcodeLabels.printForProducts(context, [_id!])),
      ],
    ];
    final right = <Widget>[
      if (dirty && !_loading)
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 12),
          child: _pill('تعديلات غير محفوظة', _C.orange, icon: Icons.edit_note),
        ),
      if (_isNew)
        InkWell(
          onTap: () => _setNewAfterSave(!_newAfterSave),
          borderRadius: BorderRadius.circular(8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(
              value: _newAfterSave,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => _setNewAfterSave(v ?? true),
            ),
            const Text('بعد الحفظ ابدأ مادة جديدة', style: TextStyle(fontSize: 12.5, color: _C.muted)),
            const SizedBox(width: 6),
          ]),
        ),
      tb(Icons.history_toggle_off, 'الواجهة القديمة', () => Navigator.pushReplacementNamed(context, '/product_entry_classic')),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _C.border)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, -3))],
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 900) {
            return Wrap(spacing: 4, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [...left, ...right]);
          }
          return Row(children: [...left, const Spacer(), ...right]);
        }),
      ),
    );
  }

  // ═══════════════════════════ نافذة «المزيد» ═══════════════════════════

  static const _sections = [
    _MoreSection('التعريف الإضافي', Icons.badge_outlined, _C.prices),
    _MoreSection('الأرقام والضريبة', Icons.numbers, _C.navy),
    _MoreSection('الحسم والهدايا', Icons.card_giftcard, _C.green),
    _MoreSection('الكلفة', Icons.calculate_outlined, _C.orange),
    _MoreSection('المخزن والطلب', Icons.inventory_outlined, _C.stock),
    _MoreSection('الصلاحية والتتبع', Icons.track_changes, _C.units),
    _MoreSection('باركودات إضافية', Icons.qr_code_2, _C.navy),
    _MoreSection('الحالة', Icons.toggle_on_outlined, _C.red),
  ];

  int _sectionCount(int s) {
    int nz(List<String> keys) => keys.where((k) {
          final c = _dc[k]!;
          return _detailNum.contains(k) ? (_p(c) ?? 0) != 0 : c.text.trim().isNotEmpty;
        }).length;
    switch (s) {
      case 0:
        return nz(['second_name', 'brand', 'origin', 'group2', 'group3', 'notes']) + (_itemType != 'trade' ? 1 : 0);
      case 1:
        return nz(['registration_no', 'classification_no', 'customs_no', 'tax_percent']);
      case 2:
        return nz(['max_discount_percent', 'bonus_buy', 'bonus_free']) + (_defaultUnit != null ? 1 : 0);
      case 3:
        return nz(['fixed_cost', 'opening_cost']) + (_costMethod != 'last' ? 1 : 0);
      case 4:
        return nz(['min_qty', 'reorder_qty', 'max_qty', 'shelf_location']) +
            (_supplierId != null ? 1 : 0) +
            (_warehouseId != null ? 1 : 0);
      case 5:
        return (_hasExpiry ? 1 : 0) + (_trackSerial ? 1 : 0) + (_weighable ? 1 : 0) + (_scale ? 1 : 0);
      case 6:
        return _barcodesList.length + _pendingBarcodes.where((b) => b.code.text.trim().isNotEmpty).length;
      default:
        return (!_active ? 1 : 0) + (_hideFromStaff ? 1 : 0);
    }
  }

  Future<void> _openMore([int initial = 0]) async {
    var sel = initial;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        void upd(VoidCallback f) {
          setState(f);
          setD(() {});
        }

        final size = MediaQuery.of(ctx).size;
        final narrow = size.width < 760;
        final rail = AnimatedBuilder(
          animation: Listenable.merge([..._dc.values]),
          builder: (_, __) => Container(
          width: narrow ? double.infinity : 210,
          color: const Color(0xFFF7F9FC),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: narrow
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (var i = 0; i < _sections.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                          label: Text(_sections[i].title),
                          selected: sel == i,
                          onSelected: (_) => setD(() => sel = i),
                        ),
                      ),
                  ]),
                )
              : Column(children: [
                  for (var i = 0; i < _sections.length; i++) _railItem(i, sel == i, () => setD(() => sel = i)),
                ]),
          ),
        );
        final content = Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: FocusTraversalGroup(child: _moreSection(sel, upd)),
          ),
        );
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 860,
            height: size.height < 700 ? size.height - 48 : 600,
            child: Column(children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _C.border))),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: _C.navy.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.tune, color: _C.navy, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      const Text('إعدادات إضافية للمادة',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _C.text)),
                      Text(
                          _name.text.trim().isEmpty
                              ? 'تُحفظ مع البطاقة عند الضغط على «حفظ»'
                              : '«${_name.text.trim()}» — تُحفظ مع البطاقة عند الضغط على «حفظ»',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: _C.muted)),
                    ]),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ]),
              ),
              Expanded(
                child: narrow
                    ? Column(children: [rail, content])
                    : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        rail,
                        const VerticalDivider(width: 1, color: _C.border),
                        content,
                      ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: _C.border))),
                child: Row(children: [
                  TextButton.icon(
                    onPressed: sel > 0 ? () => setD(() => sel--) : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('السابق'),
                  ),
                  TextButton.icon(
                    onPressed: sel < _sections.length - 1 ? () => setD(() => sel++) : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('التالي'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(
                      backgroundColor: _C.navy,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('تم'),
                  ),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
    if (mounted) setState(() {});
  }

  Widget _railItem(int i, bool selected, VoidCallback onTap) {
    final s = _sections[i];
    final n = _sectionCount(i);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        elevation: selected ? 0.5 : 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(children: [
              Icon(s.icon, size: 18, color: selected ? s.color : _C.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                        color: selected ? _C.text : _C.muted)),
              ),
              if (n > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: s.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text('$n', style: TextStyle(fontSize: 11, color: s.color, fontWeight: FontWeight.bold)),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: _C.text)),
          const SizedBox(height: 2),
          Text(hint, style: const TextStyle(fontSize: 12, color: _C.muted)),
        ]),
      );

  Widget _switchTile(String title, String? subtitle, bool value, ValueChanged<bool> onChanged, {Widget? extra}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: value ? _C.cyan.withValues(alpha: 0.05) : _C.field,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: value ? _C.cyan.withValues(alpha: 0.35) : _C.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: _C.text)),
                if (subtitle != null) Text(subtitle, style: const TextStyle(fontSize: 11.5, color: _C.muted)),
              ]),
            ),
            Switch(value: value, onChanged: onChanged),
          ]),
          if (value && extra != null) Padding(padding: const EdgeInsets.fromLTRB(0, 6, 6, 4), child: extra),
        ]),
      );

  Widget _moreSection(int s, void Function(VoidCallback) upd) {
    switch (s) {
      case 0:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionTitle('التعريف الإضافي', 'النوع والأسماء البديلة والتصنيف — تفيد في البحث والتقارير.'),
          _grid([
            _drop<String>(
              'نوع المادة',
              _itemType,
              [for (final e in itemTypeLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              (v) => upd(() => _itemType = v ?? 'trade'),
            ),
            _field('الاسم الثاني (إنكليزي / تجاري)', _dc['second_name']!),
            _field('الماركة', _dc['brand']!),
            _field('بلد المنشأ', _dc['origin']!),
            _field('المجموعة 2', _dc['group2']!),
            _field('المجموعة 3', _dc['group3']!),
          ]),
          const SizedBox(height: 10),
          _field('ملاحظات (تظهر في تقارير الجرد)', _dc['notes']!, maxLines: 3),
        ]);
      case 1:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionTitle('الأرقام والضريبة', 'أرقام الكتالوج والتصنيف والجمرك، ونسبة الضريبة إن وُجدت.'),
          _grid([
            _field('رقم التسجيل (الكتالوج / الأوردر)', _dc['registration_no']!),
            _field('رقم التصنيف', _dc['classification_no']!),
            _field('الرقم الجمركي', _dc['customs_no']!),
            _field('نسبة الضريبة', _dc['tax_percent']!, number: true, hint: '0', suffixText: '%'),
          ]),
        ]);
      case 2:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionTitle('الحسم والهدايا', 'حدود الحسم، والهدية التلقائية، والوحدة التي تظهر أولاً في الفاتورة.'),
          _grid([
            _field('أعلى حسم مسموح', _dc['max_discount_percent']!, number: true, hint: 'بلا حد', suffixText: '%'),
            _drop<String?>(
              'الوحدة الافتراضية في البيع',
              _defaultUnit,
              [
                DropdownMenuItem<String?>(value: null, child: Text('$_baseName (الأساسية)')),
                for (final n in _unitNames.skip(1)) DropdownMenuItem<String?>(value: n, child: Text(n)),
              ],
              (v) => upd(() => _defaultUnit = v),
            ),
            _field('هدية: لكل (كمية)', _dc['bonus_buy']!, number: true, hint: '0', suffixText: _baseName),
            _field('يُعطى مجاناً', _dc['bonus_free']!, number: true, hint: '0', suffixText: _baseName),
          ]),
        ]);
      case 3:
        if (!_showCost) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _sectionTitle('الكلفة', 'تحتاج صلاحية «رؤية الكلفة والأرباح».'),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionTitle('الكلفة', 'كيف تُحسب كلفة المادة في الأرباح وتقييم المخزون.'),
          _grid([
            _drop<String>(
              'طريقة الكلفة',
              _costMethod,
              const [
                DropdownMenuItem(value: 'last', child: Text('آخر سعر شراء')),
                DropdownMenuItem(value: 'average', child: Text('المتوسط المرجّح')),
                DropdownMenuItem(value: 'fixed', child: Text('كلفة ثابتة')),
              ],
              (v) => upd(() => _costMethod = v ?? 'last'),
            ),
            _field('سعر كلفة ثابت (للأرباح)', _dc['fixed_cost']!, number: true, hint: '0', suffixText: 'د.ع'),
            _field('الكلفة الافتتاحية', _dc['opening_cost']!, number: true, hint: '0', suffixText: 'د.ع'),
          ]),
        ]);
      case 4:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionTitle('المخزن والطلب', 'حدود الكمية ونقطة إعادة الطلب ومكان المادة ومورّدها.'),
          _grid([
            _field('الحد الأدنى', _dc['min_qty']!, number: true, hint: '0', suffixText: _baseName),
            _field('كمية إعادة الطلب', _dc['reorder_qty']!, number: true, hint: '0', suffixText: _baseName),
            _field('الحد الأعلى', _dc['max_qty']!, number: true, hint: '0', suffixText: _baseName),
            _field('مكان التواجد (الرف)', _dc['shelf_location']!, hint: 'مثال: A-3'),
            _drop<int?>(
              'المخزن الافتراضي',
              _warehouseId,
              [
                const DropdownMenuItem<int?>(value: null, child: Text('—')),
                for (final w in _warehouses) DropdownMenuItem<int?>(value: w.id, child: Text(w.name)),
              ],
              (v) => upd(() => _warehouseId = v),
            ),
            _drop<int?>(
              'المورد الافتراضي',
              _supplierId,
              [
                const DropdownMenuItem<int?>(value: null, child: Text('—')),
                for (final sp in _suppliers) DropdownMenuItem<int?>(value: sp['id'] as int, child: Text('${sp['name']}')),
              ],
              (v) => upd(() => _supplierId = v),
            ),
          ]),
        ]);
      case 5:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionTitle('الصلاحية والتتبع', 'للأدوية والأغذية والأجهزة والمواد الموزونة.'),
          _switchTile('لها تاريخ صلاحية', 'يظهر تنبيه قبل انتهائها', _hasExpiry, (v) => upd(() => _hasExpiry = v),
              extra: Row(children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 17),
                  label: Text(_expiryDate == null ? 'اختيار تاريخ الانتهاء' : _df.format(_expiryDate!)),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _expiryDate ?? now.add(const Duration(days: 365)),
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 15),
                    );
                    if (d != null) upd(() => _expiryDate = d);
                  },
                ),
                if (_expiryDate != null)
                  TextButton(onPressed: () => upd(() => _expiryDate = null), child: const Text('مسح')),
              ])),
          _switchTile('تتبع الرقم التسلسلي', 'موبايلات وأجهزة — يُسجَّل لكل قطعة رقمها', _trackSerial,
              (v) => upd(() => _trackSerial = v)),
          _switchTile('تباع بالوزن', 'تُدخل الكمية بالكيلو في الفاتورة', _weighable, (v) => upd(() => _weighable = v),
              extra: SizedBox(
                width: 260,
                child: _field('وزن الوحدة الأساسية', _weight, number: true, hint: '0', suffixText: 'كغم'),
              )),
          _switchTile('مادة ميزان (الوزن داخل الباركود)',
              'باركود الميزان: 2 + رمز المادة (5 أرقام) + الوزن بالغرام', _scale, (v) => upd(() => _scale = v),
              extra: SizedBox(width: 260, child: _field('رمز المادة في الميزان', _dc['scale_code']!, hint: '5 أرقام'))),
        ]);
      case 6:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionTitle('باركودات إضافية', 'لنفس المادة بأكثر من باركود (لون، حجم، مورد آخر).'),
          if (_barcode.text.trim().isNotEmpty)
            _barcodeRow(_barcode.text.trim(), 'الباركود الأساسي', null),
          for (final b in _barcodesList)
            _barcodeRow('${b['barcode']}', '${b['variant_label'] ?? ''}', () async {
              if (!requirePermission(context, AppPermissions.itemCard)) return;
              final ok = await confirmDialog(context, 'حذف باركود', 'حذف الباركود ${b['barcode']} من هذه المادة؟',
                  ok: 'حذف', color: _C.red);
              if (!ok) return;
              try {
                await _svc.deleteBarcode(b['id'] as int);
                final list = await _svc.barcodes(_id!);
                upd(() => _barcodesList = list);
              } catch (e) {
                if (mounted) showError(context, e);
              }
            }),
          for (final nb in _pendingBarcodes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(flex: 5, child: _field('باركود جديد', nb.code, onChanged: (_) => upd(() {}))),
                const SizedBox(width: 10),
                Expanded(flex: 4, child: _field('الوصف (اختياري)', nb.label, hint: 'مثال: أحمر')),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: _C.muted),
                  onPressed: () => upd(() {
                    _pendingBarcodes.remove(nb);
                    _disposeLater([nb.code, nb.label]);
                  }),
                ),
              ]),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => upd(() => _pendingBarcodes.add(_NewBarcode())),
              icon: const Icon(Icons.add),
              label: const Text('إضافة باركود'),
            ),
          ),
        ]);
      default:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionTitle('الحالة', 'إيقاف المادة يخفيها من البيع والشراء دون حذف تاريخها.'),
          _switchTile('المادة فعّالة', 'تظهر في البيع والشراء', _active, (v) => upd(() => _active = v)),
          _switchTile('إخفاؤها عن الموظفين', 'تظهر للمدير فقط في شاشات المخزون', _hideFromStaff,
              (v) => upd(() => _hideFromStaff = v)),
        ]);
    }
  }

  Widget _barcodeRow(String code, String label, VoidCallback? onDelete) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: _C.field, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
        child: Row(children: [
          const Icon(Icons.qr_code_2, size: 20, color: _C.navy),
          const SizedBox(width: 10),
          Text(code, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: _C.muted))),
          if (onDelete != null)
            IconButton(
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_outline, size: 19, color: _C.red),
              onPressed: onDelete,
            ),
        ]),
      );
}

// ═══════════════════════════ نافذة البحث ═══════════════════════════

class _ItemSearchDialog extends StatefulWidget {
  const _ItemSearchDialog({required this.svc});
  final ItemCardService svc;

  @override
  State<_ItemSearchDialog> createState() => _ItemSearchDialogState();
}

class _ItemSearchDialogState extends State<_ItemSearchDialog> {
  List<Map<String, Object?>> _rows = const [];
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String q) async {
    final my = ++_seq;
    try {
      final r = await widget.svc.search(q);
      if (mounted && my == _seq) setState(() => _rows = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 620,
        height: 560,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو الرقم أو الرمز أو الباركود',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: _C.field,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: _load,
              onSubmitted: (_) {
                if (_rows.isNotEmpty) Navigator.pop(context, _rows.first['id'] as int);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text('${_rows.length} مادة', style: const TextStyle(fontSize: 12, color: _C.muted)),
              const Spacer(),
              const Text('Enter لفتح أول نتيجة', style: TextStyle(fontSize: 11.5, color: _C.muted)),
            ]),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: _C.border),
              itemBuilder: (_, i) {
                final r = _rows[i];
                final q = d0(r['stock_quantity']);
                return ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: CircleAvatar(
                    radius: 17,
                    backgroundColor: _C.navy.withValues(alpha: 0.08),
                    child: Text('${r['id']}', style: const TextStyle(fontSize: 11, color: _C.navy)),
                  ),
                  title: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    [
                      if (r['item_code'] != null) '${r['item_code']}',
                      if (r['category_name'] != null) '${r['category_name']}',
                      if (r['brand'] != null) '${r['brand']}',
                    ].join(' • '),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_nf.format(q),
                          style: TextStyle(fontWeight: FontWeight.bold, color: q <= 0 ? _C.red : _C.stock)),
                      Text(_nf.format(d0(r['unit_price'])), style: const TextStyle(fontSize: 11, color: _C.muted)),
                    ],
                  ),
                  onTap: () => Navigator.pop(context, r['id'] as int),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
