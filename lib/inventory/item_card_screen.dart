// lib/inventory/item_card_screen.dart
//
// 🗂️ بطاقة المادة الموسّعة (مثل الإداري وسهل) — تصميم عصري بتبويبات:
//   التعريف • الأسعار • المخزون • الشراء والطلبات • التتبع • الباركودات • الحركة
//
// الأمان:
//   • الأسعار تُحفظ عبر DatabaseService.updateProduct (المسار الأصلي: يزامن
//     المادة ولا يلمس كميتها) ويُسجَّل كل تغيير في سجل تغييرات الأسعار.
//   • الكمية لا تُعدَّل من هنا أبداً — مكانها المستندات المخزنية/الجرد.
//   • باقي الحقول في product_details (محلية، لا تمس المزامنة).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../accounting/screens/acc_ui.dart';
import '../erp/erp_common.dart';
import '../erp/erp_ui.dart';
import '../erp/inventory/barcode_labels.dart';
import '../erp/inventory/inventory_reports.dart';
import '../erp/inventory/price_tools.dart';
import '../erp/report_export.dart';
import '../erp/sales/quote_order_service.dart';
import '../models/app_user.dart';
import '../org/org_service.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

const Map<String, String> itemTypeLabels = {
  'trade': 'للمتاجرة',
  'service': 'خدمة (لا مخزنية)',
  'raw': 'مادة أولية (للتصنيع)',
  'manufactured': 'مادة مصنّعة',
  'group': 'إجمالية / رئيسية',
};

class ItemCardService {
  Future<Database> get _db => DatabaseService().database;

  Future<List<Map<String, Object?>>> search(String q, {int? categoryId, String? filter}) async {
    final db = await _db;
    final t = q.trim();
    final like = '%$t%';
    final where = <String>['COALESCE(p.is_deleted, 0) = 0'];
    final args = <Object?>[];
    if (t.isNotEmpty) {
      where.add('''(p.name LIKE ? OR d.item_code LIKE ? OR d.second_name LIKE ? OR d.brand LIKE ?
             OR p.barcode = ? OR CAST(p.id AS TEXT) = ? OR p.id IN (SELECT product_id FROM product_barcodes WHERE barcode = ?))''');
      args.addAll([like, like, like, like, t, t, t]);
    }
    if (categoryId != null) {
      where.add('p.category_id = ?');
      args.add(categoryId);
    }
    switch (filter) {
      case 'low':
        where.add('d.min_qty IS NOT NULL AND d.min_qty > 0 AND COALESCE(p.stock_quantity, 0) <= d.min_qty');
        break;
      case 'zero':
        where.add('COALESCE(p.stock_quantity, 0) <= 0');
        break;
      case 'inactive':
        where.add('COALESCE(d.is_active, 1) = 0');
        break;
      case 'service':
        where.add("d.item_type = 'service'");
        break;
      case 'nocode':
        where.add("(d.item_code IS NULL OR d.item_code = '')");
        break;
    }
    if (!AuthService().isAdmin) where.add("COALESCE(d.min_role, '') != 'admin'");
    return db.rawQuery('''
      SELECT p.id, p.name, p.unit, p.stock_quantity, p.unit_price, p.cost_price, p.category_id,
             d.item_code, d.brand, d.item_type, d.min_qty, d.is_active, c.name AS category_name
      FROM products p LEFT JOIN product_details d ON d.product_id = p.id
      LEFT JOIN categories c ON c.id = p.category_id
      WHERE ${where.join(' AND ')}
      ORDER BY p.name LIMIT 400
    ''', args);
  }

  Future<Map<String, Object?>?> product(int id) async {
    final db = await _db;
    final r = await db.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<Map<String, Object?>> details(int productId) async {
    final db = await _db;
    final r = await db.query('product_details', where: 'product_id = ?', whereArgs: [productId], limit: 1);
    return r.isEmpty ? {'product_id': productId} : Map<String, Object?>.from(r.first);
  }

  Future<void> saveDetails(int productId, Map<String, Object?> values) async {
    final db = await _db;
    final code = (values['item_code'] as String?)?.trim();
    if (code != null && code.isNotEmpty) {
      final dup = await db.query('product_details',
          where: 'item_code = ? AND product_id != ?', whereArgs: [code, productId], limit: 1);
      if (dup.isNotEmpty) throw Exception('رمز المادة $code مستخدم لمادة أخرى');
    }
    final current = await details(productId);
    final row = {
      ...current,
      ...values,
      'product_id': productId,
      'item_code': (code == null || code.isEmpty) ? null : code,
      'updated_at': DateTime.now().toIso8601String(),
    };
    await db.insert('product_details', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String> suggestCode() async {
    final db = await _db;
    final r = await db.rawQuery(
        "SELECT item_code FROM product_details WHERE item_code GLOB 'M[0-9]*' ORDER BY LENGTH(item_code) DESC, item_code DESC LIMIT 1");
    var n = 0;
    if (r.isNotEmpty) n = int.tryParse(((r.first['item_code'] as String?) ?? 'M0').substring(1)) ?? 0;
    return 'M${(n + 1).toString().padLeft(5, '0')}';
  }

  Future<List<Map<String, Object?>>> barcodes(int productId) async {
    final db = await _db;
    return db.query('product_barcodes', where: 'product_id = ?', whereArgs: [productId], orderBy: 'id');
  }

  Future<void> addBarcode(int productId, String barcode, String? label) async {
    final db = await _db;
    final b = barcode.trim();
    if (b.isEmpty) return;
    final dup = await db.rawQuery('''
      SELECT p.name FROM product_barcodes pb JOIN products p ON p.id = pb.product_id WHERE pb.barcode = ?
      UNION SELECT name FROM products WHERE barcode = ? AND id != ?
    ''', [b, b, productId]);
    if (dup.isNotEmpty) throw Exception('الباركود مستخدم للمادة «${dup.first['name']}»');
    await db.insert('product_barcodes', {
      'product_id': productId,
      'barcode': b,
      'variant_label': (label == null || label.trim().isEmpty) ? null : label.trim(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteBarcode(int id) async {
    final db = await _db;
    await db.delete('product_barcodes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> suppliers() async {
    final db = await _db;
    try {
      return await db.query('suppliers', columns: ['id', 'name'], orderBy: 'name');
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, Object?>>> categories() async {
    final db = await _db;
    try {
      return await db.query('categories', orderBy: 'name');
    } catch (_) {
      return const [];
    }
  }

  /// آخر مشتريات المادة (من فواتير المشتريات المؤكدة).
  Future<List<Map<String, Object?>>> lastPurchases(int productId) async {
    final db = await _db;
    try {
      return await db.rawQuery('''
        SELECT p.date, p.invoice_number, s.name AS supplier, i.quantity, i.unit_name, i.unit_price, p.currency
        FROM purchase_invoice_items i
        JOIN purchase_invoices p ON p.id = i.invoice_id
        LEFT JOIN suppliers s ON s.id = p.supplier_id
        WHERE i.product_id = ? AND p.status = 'confirmed'
        ORDER BY p.date DESC LIMIT 10
      ''', [productId]);
    } catch (_) {
      return const [];
    }
  }

  /// مبيعات المادة خلال آخر [days] يوماً (كمية أساسية ومبلغ).
  Future<List<double>> recentSales(String? syncUuid, {int days = 30}) async {
    if (syncUuid == null) return const [0, 0];
    final db = await _db;
    final r = await db.rawQuery('''
      SELECT COALESCE(SUM($kItemBaseQty), 0) AS q, COALESCE(SUM(ii.item_total), 0) AS v
      FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
      WHERE ii.product_sync_uuid = ? AND COALESCE(i.is_deleted, 0) = 0 AND i.status = 'محفوظة' AND i.invoice_date >= ?
    ''', [syncUuid, isoDay(DateTime.now().subtract(Duration(days: days)))]);
    return [d0(r.first['q']), d0(r.first['v'])];
  }

  /// أرصدة المادة في كل مخزن.
  Future<List<MapEntry<Warehouse, double>>> balancesByWarehouse(int productId) async {
    final org = OrgService();
    final out = <MapEntry<Warehouse, double>>[];
    for (final w in await org.warehouses(activeOnly: true)) {
      final rows = await org.warehouseStock(w.id);
      final r = rows.where((x) => x['id'] == productId);
      out.add(MapEntry(w, r.isEmpty ? 0 : ((r.first['qty'] as num?) ?? 0).toDouble()));
    }
    return out;
  }

  Future<List<Map<String, Object?>>> serials(int productId) async {
    final db = await _db;
    return db.query('item_serials', where: 'product_id = ?', whereArgs: [productId], orderBy: 'id DESC');
  }

  Future<void> addSerial(int productId, String serial, {String? notes}) async {
    final s = serial.trim();
    if (s.isEmpty) return;
    final db = await _db;
    final dup = await db.query('item_serials', where: 'serial = ?', whereArgs: [s], limit: 1);
    if (dup.isNotEmpty) throw Exception('الرقم التسلسلي $s مسجّل مسبقاً');
    await db.insert('item_serials', {
      'product_id': productId,
      'serial': s,
      'status': 'in_stock',
      'notes': notes,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> setSerialStatus(int id, String status, {String? ref}) async {
    final db = await _db;
    await db.update('item_serials', {'status': status, 'ref': ref, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }
}

// ═══════════════════════════════ قائمة البطاقات ═══════════════════════════════

class ItemCardsListScreen extends StatefulWidget {
  const ItemCardsListScreen({super.key});

  @override
  State<ItemCardsListScreen> createState() => _ItemCardsListScreenState();
}

class _ItemCardsListScreenState extends State<ItemCardsListScreen> {
  final _svc = ItemCardService();
  List<Map<String, Object?>> _rows = const [];
  List<Map<String, Object?>> _cats = const [];
  String _q = '';
  int? _cat;
  String? _filter;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _svc.categories().then((c) {
      if (mounted) setState(() => _cats = c);
    });
    _load();
  }

  Future<void> _load() async {
    final my = ++_seq;
    final r = await _svc.search(_q, categoryId: _cat, filter: _filter);
    if (mounted && my == _seq) setState(() => _rows = r);
  }

  @override
  Widget build(BuildContext context) {
    final showCost = AuthService().hasPermission(AppPermissions.viewCostProfit);
    return ErpPage(
      title: 'بطاقات المواد',
      subtitle: '${_rows.length} مادة',
      icon: Icons.inventory,
      actions: exportActions(context,
          title: 'بطاقات المواد',
          headers: () => ['الرقم', 'الرمز', 'المادة', 'القسم', 'النوع', 'المخزون', 'سعر البيع', if (showCost) 'الكلفة'],
          rows: () => [
                for (final r in _rows)
                  [
                    '${r['id']}',
                    '${r['item_code'] ?? ''}',
                    '${r['name']}',
                    '${r['category_name'] ?? ''}',
                    itemTypeLabels[r['item_type']] ?? itemTypeLabels['trade']!,
                    fmtQty(d0(r['stock_quantity'])),
                    fmtMoney(d0(r['unit_price'])),
                    if (showCost) fmtMoney(d0(r['cost_price'])),
                  ],
              ]),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            SearchBox(
              hint: 'بحث بالاسم، الرقم، الرمز، الماركة أو الباركود',
              autofocus: true,
              onChanged: (v) {
                _q = v;
                _load();
              },
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              DropBox<int>(
                label: 'القسم',
                width: 200,
                value: _cats.any((c) => c['id'] == _cat) ? _cat : null,
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('كل الأقسام')),
                  for (final c in _cats) DropdownMenuItem(value: c['id'] as int, child: Text('${c['name']}')),
                ],
                onChanged: (v) {
                  _cat = v;
                  _load();
                },
              ),
              for (final e in const {
                null: 'الكل',
                'low': 'تحت الحد الأدنى',
                'zero': 'نفدت',
                'inactive': 'موقوفة',
                'service': 'خدمات',
                'nocode': 'بلا رمز',
              }.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _filter == e.key,
                  onSelected: (_) {
                    _filter = e.key;
                    _load();
                  },
                ),
            ]),
          ]),
        ),
        Expanded(
          child: _rows.isEmpty
              ? const EmptyState('لا توجد مواد')
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    final q = d0(r['stock_quantity']);
                    final min = (r['min_qty'] as num?)?.toDouble();
                    final low = min != null && min > 0 && q <= min;
                    final inactive = (r['is_active'] as int? ?? 1) == 0;
                    final type = (r['item_type'] as String?) ?? 'trade';
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: low ? ErpColors.orange.withOpacity(0.5) : ErpColors.border),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              inactive ? ErpColors.muted : ErpColors.navy,
                              inactive ? ErpColors.muted.withOpacity(0.6) : ErpColors.cyan,
                            ]),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(type == 'service' ? Icons.miscellaneous_services : Icons.inventory_2,
                              color: Colors.white),
                        ),
                        title: Row(children: [
                          Flexible(
                            child: Text('${r['name']}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(decoration: inactive ? TextDecoration.lineThrough : null)),
                          ),
                          if (r['item_code'] != null) ...[
                            const SizedBox(width: 6),
                            StatusBadge('${r['item_code']}', color: ErpColors.cyan),
                          ],
                        ]),
                        subtitle: Text([
                          'رقم ${r['id']}',
                          if (r['category_name'] != null) '${r['category_name']}',
                          if (r['brand'] != null) '${r['brand']}',
                          if (type != 'trade') itemTypeLabels[type] ?? type,
                        ].join(' • ')),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(type == 'service' ? '—' : fmtQty(q),
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: low ? ErpColors.orange : (q <= 0 ? ErpColors.red : ErpColors.navy))),
                            Text(fmtMoney(d0(r['unit_price'])), style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
                          ],
                        ),
                        onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => ItemCardScreen(productId: r['id'] as int)))
                            .then((_) => _load()),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════ البطاقة ═══════════════════════════════

class ItemCardScreen extends StatefulWidget {
  const ItemCardScreen({super.key, required this.productId});
  final int productId;

  @override
  State<ItemCardScreen> createState() => _ItemCardScreenState();
}

class _ItemCardScreenState extends State<ItemCardScreen> with SingleTickerProviderStateMixin {
  final _svc = ItemCardService();
  late final TabController _tabs = TabController(length: 7, vsync: this);
  Map<String, Object?>? _p;
  Map<String, Object?> _d = const {};
  List<Map<String, Object?>> _barcodes = const [];
  List<Map<String, Object?>> _suppliers = const [];
  List<Map<String, Object?>> _cats = const [];
  List<Map<String, Object?>> _purchases = const [];
  List<Map<String, Object?>> _orders = const [];
  List<Map<String, Object?>> _moves = const [];
  List<Map<String, Object?>> _serials = const [];
  List<MapEntry<Warehouse, double>> _balances = const [];
  List<Warehouse> _warehouses = const [];
  List<double> _sales30 = const [0, 0];
  double _reserved = 0;
  bool _saving = false;
  bool _dirty = false;

  static const _textKeys = [
    'item_code', 'second_name', 'brand', 'origin', 'shelf_location', 'notes', 'registration_no',
    'classification_no', 'customs_no', 'group2', 'group3', 'scale_code',
  ];
  static const _numKeys = [
    'min_qty', 'max_qty', 'reorder_qty', 'tax_percent', 'max_discount_percent', 'bonus_buy', 'bonus_free',
    'fixed_cost', 'opening_cost', 'price_rounding', 'markup1', 'markup2', 'markup3', 'markup4', 'markup5', 'markup6',
  ];
  final _c = <String, TextEditingController>{
    for (final k in [..._textKeys, ..._numKeys]) k: TextEditingController(),
  };
  final _price = List.generate(6, (_) => TextEditingController());
  bool _trackExpiry = false, _trackSerial = false, _scale = false, _active = true, _hideFromStaff = false;
  int? _supplierId, _warehouseId, _categoryId;
  String _costMethod = 'last';
  String _itemType = 'trade';
  String _pricingMode = 'fixed';
  String? _defaultUnit;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await _svc.product(widget.productId);
    if (p == null) return;
    final d = await _svc.details(widget.productId);
    final b = await _svc.barcodes(widget.productId);
    final s = await _svc.suppliers();
    final cats = await _svc.categories();
    final pu = await _svc.lastPurchases(widget.productId);
    final bal = await _svc.balancesByWarehouse(widget.productId);
    final w = await OrgService().warehouses(activeOnly: true);
    final orders = await QuoteOrderService().productOrders(widget.productId);
    final moves = await InventoryReports().productCard(widget.productId);
    final serials = await _svc.serials(widget.productId);
    final sales = await _svc.recentSales(p['sync_uuid'] as String?);
    final db = await erpDb();
    final res = await ErpStockReserved.forProduct(db, widget.productId);
    if (!mounted) return;
    setState(() {
      _p = p;
      _d = d;
      _barcodes = b;
      _suppliers = s;
      _cats = cats;
      _purchases = pu;
      _balances = bal;
      _warehouses = w;
      _orders = orders;
      _moves = moves;
      _serials = serials;
      _sales30 = sales;
      _reserved = res;
      for (final k in _textKeys) {
        _c[k]!.text = (d[k] as String?) ?? '';
      }
      for (final k in _numKeys) {
        final v = d[k] as num?;
        _c[k]!.text = v == null ? '' : fmtQty(v);
      }
      for (var i = 0; i < 6; i++) {
        final v = (p['price${i + 1}'] as num?)?.toDouble() ?? 0;
        _price[i].text = v == 0 ? '' : fmtMoney(v);
      }
      _trackExpiry = (d['track_expiry'] as int? ?? 0) == 1;
      _trackSerial = (d['track_serial'] as int? ?? 0) == 1;
      _scale = (d['is_scale_item'] as int? ?? 0) == 1;
      _active = (d['is_active'] as int? ?? 1) == 1;
      _hideFromStaff = d['min_role'] == 'admin';
      _supplierId = d['default_supplier_id'] as int?;
      _warehouseId = d['default_warehouse_id'] as int?;
      _categoryId = p['category_id'] as int?;
      _costMethod = (d['cost_method'] as String?) ?? 'last';
      _itemType = (d['item_type'] as String?) ?? 'trade';
      _pricingMode = (d['pricing_mode'] as String?) ?? 'fixed';
      _defaultUnit = d['default_unit'] as String?;
      _dirty = false;
    });
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  double? _num(String k) => parseMoney(_c[k]!.text);
  String? _txt(String k) {
    final t = _c[k]!.text.trim();
    return t.isEmpty ? null : t;
  }

  double get _cost => ((_p?['cost_price'] as num?) ?? 0).toDouble();

  List<String> get _unitNames {
    final p = _p;
    if (p == null) return const [];
    final base = p['unit'] == 'piece' ? 'قطعة' : (p['unit'] == 'meter' ? 'متر' : '${p['unit']}');
    final names = <String>[base];
    final h = p['unit_hierarchy'] as String?;
    if (h != null && h.isNotEmpty) {
      for (final m in RegExp(r'''["']unit_name["']\s*:\s*["']([^"']+)["']''').allMatches(h)) {
        if (!names.contains(m.group(1))) names.add(m.group(1)!);
      }
    }
    return names;
  }

  void _applyMarkups() {
    final m = [for (var i = 1; i <= 6; i++) _num('markup$i')];
    final prices = PriceTools.fromMarkups(_cost, m, _num('price_rounding') ?? 0);
    setState(() {
      for (var i = 0; i < 6; i++) {
        if (prices[i] != null) _price[i].text = fmtMoney(prices[i]!);
      }
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (!requirePermission(context, AppPermissions.itemCard)) return;
    setState(() => _saving = true);
    try {
      await _svc.saveDetails(widget.productId, {
        for (final k in _textKeys) k: _txt(k),
        for (final k in _numKeys) k: _num(k),
        'track_expiry': _trackExpiry ? 1 : 0,
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
      });
      var uploaded = false;
      // الأسعار: فقط ما تغيّر، عبر المسار الأصلي
      final p = _p!;
      final changed = <int, double>{};
      for (var i = 0; i < 6; i++) {
        final nv = parseMoney(_price[i].text) ?? 0;
        final old = ((p['price${i + 1}'] as num?) ?? 0).toDouble();
        if ((nv - old).abs() >= 0.005) changed[i + 1] = nv;
      }
      if (changed.isNotEmpty) {
        if (!AuthService().hasPermission(AppPermissions.editProducts)) {
          throw Exception('ليس لديك صلاحية تعديل الأسعار (تعديل البضاعة)');
        }
        if ((changed[1] ?? 1) <= 0) throw Exception('سعر المفرد لا يكون صفراً');
        if (await PriceTools().applyPrices(widget.productId, changed) > 0) uploaded = true;
      }
      // القسم يُحفظ في جدول المواد (يُزامن)
      final dbs = DatabaseService();
      if (_categoryId != p['category_id']) {
        final prod = await dbs.getProductById(widget.productId);
        if (prod != null) {
          await dbs.updateProduct(productWithCategory(prod, _categoryId));
          uploaded = true;
        }
      }
      // 🔄 تغيّرت التفاصيل فقط: نلمس وقت تعديل المادة لتُرفع بطاقتها للفروع
      // (updateProduct لا يغيّر الكمية ولا المعرّف)
      if (!uploaded) {
        final prod = await dbs.getProductById(widget.productId);
        if (prod != null) await dbs.updateProduct(prod.copyWith(lastModifiedAt: DateTime.now()));
      }
      if (mounted) showOk(context, 'حُفظت بطاقة المادة');
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─────────────── عناصر مساعدة ───────────────

  Widget _tf(String k, String label, {double width = 220, bool number = false, int maxLines = 1}) => SizedBox(
        width: width,
        child: TextField(
          controller: _c[k],
          maxLines: maxLines,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
          textDirection: number ? TextDirection.ltr : null,
          decoration: InputDecoration(
              labelText: label, isDense: true, filled: true, fillColor: Colors.white, border: const OutlineInputBorder()),
          onChanged: (_) => _touch(),
        ),
      );

  Widget _switch(String title, bool v, ValueChanged<bool> f, {String? subtitle}) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: v,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        onChanged: (x) {
          f(x);
          _touch();
        },
      );

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final showCost = AuthService().hasPermission(AppPermissions.viewCostProfit);
    final stock = ((p['stock_quantity'] as num?) ?? 0).toDouble();
    final minQ = _num('min_qty');
    final low = minQ != null && minQ > 0 && stock <= minQ;
    final img = p['image_path'] as String?;
    final hasImg = img != null && img.isNotEmpty && File(img).existsSync();
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save},
      child: Focus(
        autofocus: true,
        child: ErpPage(
          title: '${p['name']}',
          subtitle: [
            'رقم ${p['id']}',
            if (_txt('item_code') != null) 'رمز ${_txt('item_code')}',
            itemTypeLabels[_itemType] ?? '',
          ].join(' • '),
          icon: Icons.inventory_2,
          actions: [
            IconButton(
              tooltip: 'طباعة ملصق باركود',
              icon: const Icon(Icons.qr_code_2),
              onPressed: () => BarcodeLabels.printForProducts(context, [widget.productId]),
            ),
            IconButton(tooltip: 'حفظ (Ctrl+S)', icon: const Icon(Icons.save), onPressed: _saving ? null : _save),
          ],
          headerExtra: Row(children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                image: hasImg ? DecorationImage(image: FileImage(File(img!)), fit: BoxFit.cover) : null,
              ),
              child: hasImg ? null : const Icon(Icons.inventory_2, color: Colors.white, size: 34),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(spacing: 10, runSpacing: 8, children: [
                _heroStat('المخزون', _itemType == 'service' ? '—' : fmtQty(stock),
                    low ? const Color(0xFFFFD6A5) : Colors.white, sub: low ? 'تحت الحد الأدنى' : null),
                if (_reserved > 0) _heroStat('محجوز', fmtQty(_reserved), const Color(0xFFE9D5FF), sub: 'متاح ${fmtQty(stock - _reserved)}'),
                _heroStat('سعر المفرد', fmtMoney(((p['price1'] as num?) ?? 0).toDouble()), Colors.white),
                if (showCost) _heroStat('الكلفة', fmtMoney(_cost), const Color(0xFFB7F7C8)),
                if (showCost && _itemType != 'service') _heroStat('قيمة المخزون', fmtMoney(stock * _cost), Colors.white),
                _heroStat('مبيعات 30 يوم', fmtQty(_sales30[0]), Colors.white, sub: fmtMoney(_sales30[1])),
              ]),
            ),
          ]),
          bottom: _dirty
              ? SafeArea(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(10),
                    child: PrimaryButton(label: 'حفظ التعديلات', icon: Icons.save, busy: _saving, onPressed: _save),
                  ),
                )
              : null,
          body: Column(children: [
            Material(
              color: Colors.white,
              child: TabBar(
                controller: _tabs,
                isScrollable: true,
                labelColor: ErpColors.navy,
                indicatorColor: ErpColors.cyan,
                tabs: const [
                  Tab(icon: Icon(Icons.badge_outlined), text: 'التعريف'),
                  Tab(icon: Icon(Icons.sell_outlined), text: 'الأسعار'),
                  Tab(icon: Icon(Icons.warehouse_outlined), text: 'المخزون'),
                  Tab(icon: Icon(Icons.local_shipping_outlined), text: 'الشراء والطلبات'),
                  Tab(icon: Icon(Icons.track_changes), text: 'التتبع والضريبة'),
                  Tab(icon: Icon(Icons.qr_code), text: 'الباركودات'),
                  Tab(icon: Icon(Icons.swap_vert), text: 'الحركة'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(controller: _tabs, children: [
                _identityTab(),
                _pricesTab(showCost),
                _stockTab(),
                _purchaseTab(showCost),
                _trackingTab(),
                _barcodesTab(p),
                _movesTab(),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _heroStat(String label, String value, Color color, {String? sub}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11.5)),
          Text(value, textDirection: TextDirection.ltr, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.bold)),
          if (sub != null) Text(sub, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
        ]),
      );

  Widget _identityTab() => ListView(padding: const EdgeInsets.only(bottom: 30, top: 6), children: [
        ErpSection(
          title: 'الأسماء والرموز',
          icon: Icons.badge_outlined,
          child: FieldGrid(children: [
            SizedBox(
              width: 220,
              child: Row(children: [
                Expanded(child: _tf('item_code', 'رمز المادة')),
                IconButton(
                  tooltip: 'رمز تلقائي',
                  icon: const Icon(Icons.auto_fix_high, color: ErpColors.cyan),
                  onPressed: () async {
                    _c['item_code']!.text = await _svc.suggestCode();
                    _touch();
                  },
                ),
              ]),
            ),
            _tf('second_name', 'الاسم الثاني (إنكليزي/تجاري)', width: 300),
            _tf('registration_no', 'رقم التسجيل (الكتالوج/الأوردر)'),
            _tf('classification_no', 'رقم التصنيف'),
            _tf('customs_no', 'الرقم الجمركي'),
          ]),
        ),
        ErpSection(
          title: 'التصنيف',
          icon: Icons.category_outlined,
          color: ErpColors.purple,
          child: FieldGrid(children: [
            DropBox<String>(
              label: 'نوع المادة',
              width: 220,
              value: _itemType,
              items: [for (final e in itemTypeLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() {
                _itemType = v ?? 'trade';
                _dirty = true;
              }),
            ),
            DropBox<int>(
              label: 'القسم (المجموعة 1)',
              width: 220,
              value: _cats.any((c) => c['id'] == _categoryId) ? _categoryId : null,
              items: [
                const DropdownMenuItem<int>(value: null, child: Text('— بلا —')),
                for (final c in _cats) DropdownMenuItem(value: c['id'] as int, child: Text('${c['name']}')),
              ],
              onChanged: (v) => setState(() {
                _categoryId = v;
                _dirty = true;
              }),
            ),
            _tf('group2', 'المجموعة 2', width: 180),
            _tf('group3', 'المجموعة 3', width: 180),
            _tf('brand', 'الماركة', width: 180),
            _tf('origin', 'بلد المنشأ', width: 180),
          ]),
        ),
        ErpSection(
          title: 'الحالة والملاحظات',
          icon: Icons.toggle_on_outlined,
          color: ErpColors.green,
          child: Column(children: [
            _switch('المادة فعّالة (تظهر في البيع والشراء)', _active, (v) => setState(() => _active = v)),
            _switch('إخفاؤها عن الموظفين (تظهر للمدير فقط في شاشات المخزون)', _hideFromStaff,
                (v) => setState(() => _hideFromStaff = v)),
            const SizedBox(height: 6),
            _tf('notes', 'ملاحظات (تظهر في تقارير الجرد)', width: 900, maxLines: 2),
          ]),
        ),
      ]);

  Widget _pricesTab(bool showCost) {
    final rounding = _num('price_rounding') ?? 0;
    return ListView(padding: const EdgeInsets.only(bottom: 30, top: 6), children: [
      ErpSection(
        title: 'طريقة التسعير',
        icon: Icons.tune,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'fixed', label: Text('أسعار ثابتة'), icon: Icon(Icons.push_pin_outlined)),
              ButtonSegment(value: 'markup', label: Text('نسبة ربح على الكلفة'), icon: Icon(Icons.percent)),
            ],
            selected: {_pricingMode},
            onSelectionChanged: (s) => setState(() {
              _pricingMode = s.first;
              _dirty = true;
            }),
          ),
          const SizedBox(height: 8),
          Text(
            _pricingMode == 'markup'
                ? 'كل سعر = الكلفة × (1 + النسبة)، مقرّباً لأقرب مضاعف. يُعاد حسابه عند تغيّر الكلفة من «تحديث الأسعار من الكلفة».'
                : 'تُكتب الأسعار يدوياً.',
            style: const TextStyle(color: ErpColors.muted),
          ),
        ]),
      ),
      ErpSection(
        title: 'مستويات الأسعار',
        icon: Icons.sell_outlined,
        color: ErpColors.green,
        trailing: _pricingMode == 'markup'
            ? TextButton.icon(onPressed: _applyMarkups, icon: const Icon(Icons.calculate), label: const Text('احسب من النسب'))
            : null,
        child: Column(children: [
          if (showCost)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                InfoTile('الكلفة الحالية', fmtMoney(_cost), color: ErpColors.navy),
                if (_pricingMode == 'markup') _tf('price_rounding', 'التقريب لأقرب (مثلاً 250)', width: 200, number: true),
              ]),
            ),
          for (var i = 0; i < 6; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 110,
                  child: Text('${priceFieldNames[i]}${i == 0 ? ' *' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _price[i],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                        labelText: 'السعر', isDense: true, filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
                    onChanged: (_) => _touch(),
                  ),
                ),
                if (_pricingMode == 'markup') _tf('markup${i + 1}', 'نسبة الربح %', width: 130, number: true),
                if (showCost && _cost > 0 && (parseMoney(_price[i].text) ?? 0) > 0)
                  StatusBadge(
                    'ربح ${(((parseMoney(_price[i].text) ?? 0) / _cost - 1) * 100).toStringAsFixed(1)}%',
                    color: (parseMoney(_price[i].text) ?? 0) < _cost ? ErpColors.red : ErpColors.green,
                  ),
                if (_pricingMode == 'markup' && _num('markup${i + 1}') != null && _cost > 0)
                  Text('← ${fmtMoney(roundToStep(_cost * (1 + (_num('markup${i + 1}') ?? 0) / 100), rounding))}',
                      style: const TextStyle(color: ErpColors.muted)),
              ]),
            ),
        ]),
      ),
      ErpSection(
        title: 'الحسم والهدايا والكلفة',
        icon: Icons.card_giftcard,
        color: ErpColors.orange,
        child: FieldGrid(children: [
          _tf('max_discount_percent', 'أعلى حسم مسموح %', width: 170, number: true),
          _tf('bonus_buy', 'هدية: كل (كمية)', width: 150, number: true),
          _tf('bonus_free', 'عليها مجاناً', width: 130, number: true),
          if (showCost) _tf('fixed_cost', 'سعر كلفة ثابت (للأرباح)', width: 200, number: true),
          if (showCost) _tf('opening_cost', 'الكلفة الافتتاحية', width: 170, number: true),
        ]),
      ),
    ]);
  }

  Widget _stockTab() => ListView(padding: const EdgeInsets.only(bottom: 30, top: 6), children: [
        ErpSection(
          title: 'الحدود ونقطة الطلب',
          icon: Icons.stacked_line_chart,
          color: ErpColors.green,
          child: FieldGrid(children: [
            _tf('min_qty', 'الحد الأدنى', width: 150, number: true),
            _tf('reorder_qty', 'كمية إعادة الطلب', width: 170, number: true),
            _tf('max_qty', 'الحد الأعلى', width: 150, number: true),
            _tf('shelf_location', 'مكان التواجد (الرف)', width: 200),
          ]),
        ),
        ErpSection(
          title: 'الإعدادات',
          icon: Icons.settings_outlined,
          child: FieldGrid(children: [
            DropBox<int>(
              label: 'المخزن الافتراضي',
              value: _warehouses.any((w) => w.id == _warehouseId) ? _warehouseId : null,
              items: [
                const DropdownMenuItem<int>(value: null, child: Text('—')),
                for (final w in _warehouses) DropdownMenuItem(value: w.id, child: Text(w.name)),
              ],
              onChanged: (v) => setState(() {
                _warehouseId = v;
                _dirty = true;
              }),
            ),
            DropBox<String>(
              label: 'طريقة الكلفة',
              value: _costMethod,
              items: const [
                DropdownMenuItem(value: 'last', child: Text('آخر سعر شراء')),
                DropdownMenuItem(value: 'average', child: Text('المتوسط المرجّح')),
                DropdownMenuItem(value: 'fixed', child: Text('كلفة ثابتة')),
              ],
              onChanged: (v) => setState(() {
                _costMethod = v ?? 'last';
                _dirty = true;
              }),
            ),
            DropBox<String>(
              label: 'الوحدة الافتراضية',
              value: _unitNames.contains(_defaultUnit) ? _defaultUnit : null,
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('— الأساسية —')),
                for (final u in _unitNames) DropdownMenuItem(value: u, child: Text(u)),
              ],
              onChanged: (v) => setState(() {
                _defaultUnit = v;
                _dirty = true;
              }),
            ),
          ]),
        ),
        ErpSection(
          title: 'الرصيد في كل مخزن',
          icon: Icons.warehouse_outlined,
          color: ErpColors.blue,
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            for (final b in _balances)
              StatCard(label: b.key.name, value: fmtQty(b.value), icon: Icons.warehouse, color: ErpColors.blue, width: 190),
          ]),
        ),
      ]);

  Widget _purchaseTab(bool showCost) => ListView(padding: const EdgeInsets.only(bottom: 30, top: 6), children: [
        ErpSection(
          title: 'المورد',
          icon: Icons.local_shipping_outlined,
          color: ErpColors.orange,
          child: DropBox<int>(
            label: 'المورد الافتراضي',
            width: 320,
            value: _suppliers.any((s) => s['id'] == _supplierId) ? _supplierId : null,
            items: [
              const DropdownMenuItem<int>(value: null, child: Text('—')),
              for (final s in _suppliers) DropdownMenuItem(value: s['id'] as int, child: Text('${s['name']}')),
            ],
            onChanged: (v) => setState(() {
              _supplierId = v;
              _dirty = true;
            }),
          ),
        ),
        if (showCost)
          ErpSection(
            title: 'آخر المشتريات',
            icon: Icons.history,
            child: _purchases.isEmpty
                ? const EmptyState('لا توجد مشتريات مسجّلة')
                : SimpleTable(
                    headers: const ['التاريخ', 'المورد', 'الفاتورة', 'الكمية', 'السعر', 'العملة'],
                    numericColumns: const {3, 4},
                    rows: [
                      for (final pu in _purchases)
                        [
                          fmtDate(parseDate(pu['date'])),
                          '${pu['supplier'] ?? ''}',
                          '${pu['invoice_number'] ?? ''}',
                          '${fmtQty(d0(pu['quantity']))} ${pu['unit_name'] ?? ''}',
                          fmtMoney(d0(pu['unit_price'])),
                          '${pu['currency'] ?? ''}',
                        ],
                    ],
                  ),
          ),
        ErpSection(
          title: 'الطلبات على المادة',
          icon: Icons.assignment_outlined,
          color: ErpColors.purple,
          child: _orders.isEmpty
              ? const EmptyState('لا توجد طلبات')
              : SimpleTable(
                  headers: const ['النوع', 'الرقم', 'التاريخ', 'الطرف', 'الكمية', 'المسلّم', 'الحالة'],
                  numericColumns: const {4, 5},
                  rows: [
                    for (final o in _orders)
                      [
                        o['order_type'] == 'sales' ? 'مبيعات' : 'مشتريات',
                        '${o['order_no']}',
                        fmtDate(parseDate(o['order_date'])),
                        '${o['party_name']}',
                        '${fmtQty(d0(o['quantity']))} ${o['sale_type'] ?? ''}',
                        fmtQty(d0(o['delivered_base_qty'])),
                        '${o['status']}',
                      ],
                  ],
                ),
        ),
      ]);

  Widget _trackingTab() => ListView(padding: const EdgeInsets.only(bottom: 30, top: 6), children: [
        ErpSection(
          title: 'التتبع',
          icon: Icons.track_changes,
          color: ErpColors.purple,
          child: Column(children: [
            _switch('تتبع تاريخ الصلاحية', _trackExpiry, (v) => setState(() => _trackExpiry = v)),
            _switch('تتبع الرقم التسلسلي (موبايلات، أجهزة)', _trackSerial, (v) => setState(() => _trackSerial = v)),
            _switch('مادة ميزان (الوزن داخل الباركود)', _scale, (v) => setState(() => _scale = v),
                subtitle: 'باركود الميزان: 2 + رمز المادة (5 أرقام) + الوزن بالغرام (5 أرقام) + رقم تحقق'),
            if (_scale) Align(alignment: AlignmentDirectional.centerStart, child: _tf('scale_code', 'رمز المادة في الميزان (5 أرقام)')),
          ]),
        ),
        ErpSection(
          title: 'الضريبة',
          icon: Icons.account_balance_outlined,
          child: _tf('tax_percent', 'نسبة الضريبة %', width: 180, number: true),
        ),
        if (_trackSerial)
          ErpSection(
            title: 'الأرقام التسلسلية (${_serials.where((s) => s['status'] == 'in_stock').length} في المخزن)',
            icon: Icons.pin_outlined,
            color: ErpColors.blue,
            trailing: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('إضافة'),
              onPressed: () async {
                final s = await askText(context, 'رقم تسلسلي جديد', label: 'الرقم (IMEI / Serial)');
                if (s == null || s.isEmpty) return;
                try {
                  await _svc.addSerial(widget.productId, s);
                  _serials = await _svc.serials(widget.productId);
                  if (mounted) setState(() {});
                } catch (e) {
                  if (mounted) showError(context, e);
                }
              },
            ),
            child: Column(children: [
              for (final s in _serials)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.pin, color: s['status'] == 'in_stock' ? ErpColors.green : ErpColors.muted),
                  title: Text('${s['serial']}', textDirection: TextDirection.ltr),
                  subtitle: Text(s['status'] == 'in_stock' ? 'في المخزن' : 'مباع ${s['ref'] ?? ''}'),
                  trailing: s['status'] == 'in_stock'
                      ? TextButton(
                          onPressed: () async {
                            final ref = await askText(context, 'مرجع البيع', label: 'رقم الفاتورة / الزبون');
                            if (ref == null) return;
                            await _svc.setSerialStatus(s['id'] as int, 'sold', ref: ref);
                            _serials = await _svc.serials(widget.productId);
                            if (mounted) setState(() {});
                          },
                          child: const Text('تسجيل بيع'),
                        )
                      : TextButton(
                          onPressed: () async {
                            await _svc.setSerialStatus(s['id'] as int, 'in_stock');
                            _serials = await _svc.serials(widget.productId);
                            if (mounted) setState(() {});
                          },
                          child: const Text('إرجاع للمخزن'),
                        ),
                ),
            ]),
          ),
      ]);

  Widget _barcodesTab(Map<String, Object?> p) => ListView(padding: const EdgeInsets.only(bottom: 30, top: 6), children: [
        ErpSection(
          title: 'الباركودات',
          icon: Icons.qr_code,
          color: ErpColors.blue,
          trailing: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('باركود إضافي'),
            onPressed: () async {
              if (!requirePermission(context, AppPermissions.itemCard)) return;
              final code = TextEditingController();
              final label = TextEditingController();
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('باركود إضافي'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(controller: code, autofocus: true, decoration: const InputDecoration(labelText: 'الباركود')),
                    TextField(controller: label, decoration: const InputDecoration(labelText: 'الوصف (مثلاً: أحمر)')),
                  ]),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة')),
                  ],
                ),
              );
              if (ok != true) return;
              try {
                await _svc.addBarcode(widget.productId, code.text, label.text);
                _load();
              } catch (e) {
                if (mounted) showError(context, e);
              }
            },
          ),
          child: Column(children: [
            if (p['barcode'] != null && '${p['barcode']}'.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.qr_code, color: ErpColors.navy),
                title: Text('${p['barcode']}', textDirection: TextDirection.ltr),
                subtitle: const Text('الباركود الأساسي'),
              ),
            for (final b in _barcodes)
              ListTile(
                leading: const Icon(Icons.qr_code_2),
                title: Text('${b['barcode']}', textDirection: TextDirection.ltr),
                subtitle: Text('${b['variant_label'] ?? ''}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: ErpColors.red),
                  onPressed: () async {
                    if (!requirePermission(context, AppPermissions.itemCard)) return;
                    await _svc.deleteBarcode(b['id'] as int);
                    _load();
                  },
                ),
              ),
            if ((p['barcode'] == null || '${p['barcode']}'.isEmpty) && _barcodes.isEmpty)
              const EmptyState('لا يوجد باركود — يمكن طباعة ملصق برقم المادة', icon: Icons.qr_code_scanner),
          ]),
        ),
      ]);

  Widget _movesTab() => _moves.isEmpty
      ? const EmptyState('لا توجد حركات', icon: Icons.swap_vert)
      : ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: _moves.length,
          itemBuilder: (_, i) {
            final m = _moves[i];
            final q = d0(m['q']);
            return Card(
              elevation: 0,
              margin: const EdgeInsets.symmetric(vertical: 2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10), side: const BorderSide(color: ErpColors.border)),
              child: ListTile(
                dense: true,
                leading: Icon(q >= 0 ? Icons.south_west : Icons.north_east,
                    color: q >= 0 ? ErpColors.green : ErpColors.orange),
                title: Text(movementKindLabels[m['kind']] ?? '${m['kind']}'),
                subtitle: Text('${fmtDate(parseDate(m['d']))}  ${m['note'] ?? ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${q >= 0 ? '+' : ''}${fmtQty(q)}',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(fontWeight: FontWeight.bold, color: q >= 0 ? ErpColors.green : ErpColors.orange)),
                    Text('الرصيد ${fmtQty(d0(m['balance']))}', style: const TextStyle(fontSize: 11, color: ErpColors.muted)),
                  ],
                ),
              ),
            );
          },
        );
}

/// الكمية المحجوزة لمادة في طلبات المبيعات المفتوحة.
class ErpStockReserved {
  static Future<double> forProduct(DatabaseExecutor db, int productId) async {
    try {
      final r = await db.rawQuery('''
        SELECT COALESCE(SUM(MAX(oi.base_qty - oi.delivered_base_qty, 0)), 0) AS q
        FROM order_items oi JOIN orders o ON o.id = oi.order_id
        WHERE oi.product_id = ? AND o.order_type = 'sales' AND o.status IN ('open', 'partial')
          AND (o.reserve = 1 OR oi.reserve = 1)
      ''', [productId]);
      return d0(r.first['q']);
    } catch (_) {
      return 0;
    }
  }
}
