// lib/inventory/item_card_screen.dart
//
// 🗂️ بطاقة المادة الموسّعة (مثل الإداري): كل معلومات المادة في مكان واحد.
//
// البيانات الأساسية (الاسم، الوحدات، أسعار البيع، الكلفة) تبقى في شاشة
// «تعديل البضاعة» الحالية لأنها مرتبطة بالمزامنة والفواتير. هذه البطاقة تضيف
// فوقها: رمز المادة، اسم ثانٍ، الماركة، المنشأ، موقع الرف، حدود المخزون،
// المخزن والمورد الافتراضيين، تتبع الصلاحية والرقم التسلسلي، مادة ميزان،
// الضريبة وحد الخصم، الباركودات المتعددة، وأرصدة المادة في كل مخزن.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../accounting/screens/acc_ui.dart';
import '../models/app_user.dart';
import '../org/org_service.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

class ItemCardService {
  Future<Database> get _db => DatabaseService().database;

  Future<List<Map<String, Object?>>> search(String q) async {
    final db = await _db;
    final like = '%${q.trim()}%';
    return db.rawQuery('''
      SELECT p.id, p.name, p.unit, p.stock_quantity, p.unit_price, d.item_code, d.brand
      FROM products p LEFT JOIN product_details d ON d.product_id = p.id
      WHERE COALESCE(p.is_deleted, 0) = 0
        AND (p.name LIKE ? OR d.item_code LIKE ? OR d.second_name LIKE ? OR d.brand LIKE ?
             OR p.barcode = ? OR p.id IN (SELECT product_id FROM product_barcodes WHERE barcode = ?))
      ORDER BY p.name LIMIT 300
    ''', [like, like, like, like, q.trim(), q.trim()]);
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
    final row = {
      ...values,
      'product_id': productId,
      'item_code': (code == null || code.isEmpty) ? null : code,
      'updated_at': DateTime.now().toIso8601String(),
    };
    await db.insert('product_details', row, conflictAlgorithm: ConflictAlgorithm.replace);
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
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _svc.search(_q);
    if (mounted) setState(() => _rows = r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('بطاقات المواد'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'بحث بالاسم، الرمز، الماركة أو الباركود',
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (v) {
              _q = v;
              _load();
            },
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = _rows[i];
              final q = ((r['stock_quantity'] as num?) ?? 0).toDouble();
              return ListTile(
                tileColor: Colors.white,
                leading: const Icon(Icons.inventory_2, color: AccColors.navy),
                title: Text('${r['name']}'),
                subtitle: Text([
                  if (r['item_code'] != null) 'رمز ${r['item_code']}',
                  if (r['brand'] != null) '${r['brand']}',
                  'المخزون: ${q.toStringAsFixed(q % 1 == 0 ? 0 : 2)} ${r['unit'] ?? ''}',
                ].join(' • ')),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ItemCardScreen(productId: r['id'] as int))).then((_) => _load()),
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

class _ItemCardScreenState extends State<ItemCardScreen> {
  final _svc = ItemCardService();
  Map<String, Object?>? _p;
  Map<String, Object?> _d = const {};
  List<Map<String, Object?>> _barcodes = const [];
  List<Map<String, Object?>> _suppliers = const [];
  List<Map<String, Object?>> _purchases = const [];
  List<MapEntry<Warehouse, double>> _balances = const [];
  List<Warehouse> _warehouses = const [];
  bool _saving = false;

  final _c = <String, TextEditingController>{
    for (final k in const [
      'item_code', 'second_name', 'brand', 'origin', 'shelf_location', 'notes',
      'min_qty', 'max_qty', 'reorder_qty', 'tax_percent', 'max_discount_percent', 'scale_code',
    ])
      k: TextEditingController(),
  };
  bool _trackExpiry = false, _trackSerial = false, _scale = false, _active = true;
  int? _supplierId, _warehouseId;
  String _costMethod = 'last';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await _svc.product(widget.productId);
    final d = await _svc.details(widget.productId);
    final b = await _svc.barcodes(widget.productId);
    final s = await _svc.suppliers();
    final pu = await _svc.lastPurchases(widget.productId);
    final bal = await _svc.balancesByWarehouse(widget.productId);
    final w = await OrgService().warehouses(activeOnly: true);
    if (!mounted) return;
    setState(() {
      _p = p;
      _d = d;
      _barcodes = b;
      _suppliers = s;
      _purchases = pu;
      _balances = bal;
      _warehouses = w;
      for (final e in _c.entries) {
        final v = d[e.key];
        e.value.text = v == null ? '' : (v is double && v % 1 == 0 ? v.toStringAsFixed(0) : '$v');
      }
      _trackExpiry = (d['track_expiry'] as int? ?? 0) == 1;
      _trackSerial = (d['track_serial'] as int? ?? 0) == 1;
      _scale = (d['is_scale_item'] as int? ?? 0) == 1;
      _active = (d['is_active'] as int? ?? 1) == 1;
      _supplierId = d['default_supplier_id'] as int?;
      _warehouseId = d['default_warehouse_id'] as int?;
      _costMethod = (d['cost_method'] as String?) ?? 'last';
    });
  }

  double? _num(String k) {
    final t = _c[k]!.text.trim().replaceAll(',', '');
    return t.isEmpty ? null : double.tryParse(t);
  }

  String? _txt(String k) {
    final t = _c[k]!.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    if (!requirePermission(context, AppPermissions.itemCard)) return;
    setState(() => _saving = true);
    try {
      await _svc.saveDetails(widget.productId, {
        'item_code': _txt('item_code'),
        'second_name': _txt('second_name'),
        'brand': _txt('brand'),
        'origin': _txt('origin'),
        'shelf_location': _txt('shelf_location'),
        'notes': _txt('notes'),
        'min_qty': _num('min_qty'),
        'max_qty': _num('max_qty'),
        'reorder_qty': _num('reorder_qty'),
        'tax_percent': _num('tax_percent'),
        'max_discount_percent': _num('max_discount_percent'),
        'scale_code': _txt('scale_code'),
        'track_expiry': _trackExpiry ? 1 : 0,
        'track_serial': _trackSerial ? 1 : 0,
        'is_scale_item': _scale ? 1 : 0,
        'is_active': _active ? 1 : 0,
        'default_supplier_id': _supplierId,
        'default_warehouse_id': _warehouseId,
        'cost_method': _costMethod,
        'image_path': _d['image_path'],
      });
      if (mounted) showOk(context, 'حُفظت بطاقة المادة');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String k, String label, {bool number = false, int flex = 1}) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: TextField(
            controller: _c[k],
            keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
            decoration: InputDecoration(labelText: label, isDense: true),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) {
      return Scaffold(appBar: accAppBar('بطاقة مادة'), body: const Center(child: CircularProgressIndicator()));
    }
    final showCost = AuthService().hasPermission(AppPermissions.viewCostProfit);
    final stock = ((p['stock_quantity'] as num?) ?? 0).toDouble();
    final minQ = _num('min_qty');
    final low = minQ != null && stock <= minQ;
    final prices = [
      for (var i = 1; i <= 6; i++)
        if (((p['price$i'] as num?) ?? 0) > 0) MapEntry('سعر $i', (p['price$i'] as num).toDouble()),
    ];

    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('بطاقة مادة', actions: [
        IconButton(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), tooltip: 'حفظ (Ctrl+S)'),
      ]),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        },
        child: Focus(
          autofocus: true,
          child: ListView(padding: const EdgeInsets.all(8), children: [
            // ── رأس البطاقة ──
            Card(
              color: AccColors.navy,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Icon(Icons.inventory_2, color: Colors.white, size: 40),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${p['name']}',
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('الوحدة: ${p['unit']}   •   سعر البيع: ${fmtMoney((p['unit_price'] as num?) ?? 0)}'
                          '${showCost ? '   •   الكلفة: ${fmtMoney((p['cost_price'] as num?) ?? 0)}' : ''}',
                          style: const TextStyle(color: Colors.white70)),
                    ]),
                  ),
                  Column(children: [
                    const Text('الرصيد الكلي', style: TextStyle(color: Colors.white70)),
                    Text(stock.toStringAsFixed(stock % 1 == 0 ? 0 : 2),
                        style: TextStyle(
                            color: low ? const Color(0xFFFCA5A5) : Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold)),
                    if (low) const Text('تحت الحد الأدنى', style: TextStyle(color: Color(0xFFFCA5A5))),
                  ]),
                ]),
              ),
            ),
            if (prices.isNotEmpty)
              SectionCard(
                title: 'مستويات الأسعار',
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final e in prices) Chip(label: Text('${e.key}: ${fmtMoney(e.value)}')),
                    const Text('  (تُعدَّل من شاشة تعديل البضاعة)', style: TextStyle(color: AccColors.muted)),
                  ]),
                ),
              ),
            SectionCard(
              title: 'التعريف',
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  Row(children: [
                    _field('item_code', 'رمز المادة'),
                    _field('second_name', 'الاسم الثاني (إنكليزي/تجاري)', flex: 2),
                  ]),
                  Row(children: [
                    _field('brand', 'الماركة'),
                    _field('origin', 'بلد المنشأ'),
                    _field('shelf_location', 'موقع الرف'),
                  ]),
                  Row(children: [_field('notes', 'ملاحظات')]),
                  SwitchListTile(
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                    title: const Text('المادة فعّالة (تظهر في البيع والشراء)'),
                  ),
                ]),
              ),
            ),
            SectionCard(
              title: 'المخزون',
              color: AccColors.green,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  Row(children: [
                    _field('min_qty', 'الحد الأدنى', number: true),
                    _field('reorder_qty', 'كمية إعادة الطلب', number: true),
                    _field('max_qty', 'الحد الأعلى', number: true),
                  ]),
                  Row(children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: DropdownButtonFormField<int?>(
                          value: _warehouses.any((w) => w.id == _warehouseId) ? _warehouseId : null,
                          decoration: const InputDecoration(labelText: 'المخزن الافتراضي', isDense: true),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('—')),
                            for (final w in _warehouses) DropdownMenuItem<int?>(value: w.id, child: Text(w.name)),
                          ],
                          onChanged: (v) => setState(() => _warehouseId = v),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: DropdownButtonFormField<String>(
                          value: _costMethod,
                          decoration: const InputDecoration(labelText: 'طريقة الكلفة', isDense: true),
                          items: const [
                            DropdownMenuItem(value: 'last', child: Text('آخر سعر شراء')),
                            DropdownMenuItem(value: 'average', child: Text('المتوسط المرجّح')),
                          ],
                          onChanged: (v) => setState(() => _costMethod = v ?? 'last'),
                        ),
                      ),
                    ),
                  ]),
                  const Divider(),
                  for (final b in _balances)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.warehouse, size: 20),
                      title: Text(b.key.name),
                      trailing: Text(b.value.toStringAsFixed(b.value % 1 == 0 ? 0 : 2),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                ]),
              ),
            ),
            SectionCard(
              title: 'الشراء',
              color: AccColors.orange,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  DropdownButtonFormField<int?>(
                    value: _suppliers.any((s) => s['id'] == _supplierId) ? _supplierId : null,
                    decoration: const InputDecoration(labelText: 'المورد الافتراضي', isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('—')),
                      for (final s in _suppliers)
                        DropdownMenuItem<int?>(value: s['id'] as int, child: Text('${s['name']}')),
                    ],
                    onChanged: (v) => setState(() => _supplierId = v),
                  ),
                  if (showCost)
                    for (final pu in _purchases)
                      ListTile(
                        dense: true,
                        title: Text('${pu['supplier'] ?? ''} — فاتورة ${pu['invoice_number'] ?? ''}'),
                        subtitle: Text('${pu['date'] ?? ''}'.split('T').first),
                        trailing: Text('${pu['quantity']} ${pu['unit_name'] ?? ''} × '
                            '${fmtMoney((pu['unit_price'] as num?) ?? 0)} ${pu['currency'] ?? ''}'),
                      ),
                ]),
              ),
            ),
            SectionCard(
              title: 'التتبع والضريبة',
              color: AccColors.purple,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  SwitchListTile(
                    value: _trackExpiry,
                    onChanged: (v) => setState(() => _trackExpiry = v),
                    title: const Text('تتبع تاريخ الصلاحية'),
                  ),
                  SwitchListTile(
                    value: _trackSerial,
                    onChanged: (v) => setState(() => _trackSerial = v),
                    title: const Text('تتبع الرقم التسلسلي (موبايلات، أجهزة)'),
                  ),
                  SwitchListTile(
                    value: _scale,
                    onChanged: (v) => setState(() => _scale = v),
                    title: const Text('مادة ميزان (الوزن داخل الباركود)'),
                  ),
                  if (_scale) Row(children: [_field('scale_code', 'رمز المادة في الميزان')]),
                  Row(children: [
                    _field('tax_percent', 'نسبة الضريبة %', number: true),
                    _field('max_discount_percent', 'أعلى خصم مسموح %', number: true),
                  ]),
                ]),
              ),
            ),
            SectionCard(
              title: 'الباركودات',
              color: AccColors.blue,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  if (p['barcode'] != null && '${p['barcode']}'.isNotEmpty)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.qr_code),
                      title: Text('${p['barcode']}'),
                      subtitle: const Text('الباركود الأساسي'),
                    ),
                  for (final b in _barcodes)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.qr_code_2),
                      title: Text('${b['barcode']}'),
                      subtitle: Text('${b['variant_label'] ?? ''}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (!requirePermission(context, AppPermissions.itemCard)) return;
                          await _svc.deleteBarcode(b['id'] as int);
                          _load();
                        },
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة باركود (لون/حجم/رائحة مختلفة)'),
                      onPressed: () async {
                        if (!requirePermission(context, AppPermissions.itemCard)) return;
                        final code = TextEditingController();
                        final label = TextEditingController();
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('باركود إضافي'),
                            content: Column(mainAxisSize: MainAxisSize.min, children: [
                              TextField(
                                  controller: code,
                                  autofocus: true,
                                  decoration: const InputDecoration(labelText: 'الباركود')),
                              TextField(
                                  controller: label,
                                  decoration: const InputDecoration(labelText: 'الوصف (مثلاً: أحمر)')),
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
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AccColors.navy, padding: const EdgeInsets.all(16)),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('حفظ البطاقة'),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}
