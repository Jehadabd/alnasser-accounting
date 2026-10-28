// lib/erp/control/purchase_suggestions_screen.dart
//
// 🛒 اقتراح طلبية شراء: لكل مادة سرعة بيعها (آخر N يوماً) ورصيدها الآن، وما يلزم
// لتغطية مدة التوريد + مدة التغطية — مجمّعة حسب آخر مورد اشتُريت منه.
// للقراءة فقط: لا يُنشئ أمراً ولا فاتورة. يُطبع أو يُصدَّر PDF ليُرسل للمورد.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart' show fmtMoney, showError;
import '../erp_common.dart';
import '../erp_ui.dart';
import '../report_export.dart';
import '../sales/doc_pdf.dart';
import 'business_math.dart';
import 'control_common.dart';

class _Suggestion {
  _Suggestion({
    required this.productId,
    required this.name,
    required this.unit,
    required this.input,
    required this.supplierId,
    required this.supplierName,
    required this.unitCost,
    required this.largeUnit,
    required this.unitsPerLarge,
  });
  final int productId;
  final String name;
  final String unit;
  final ReorderInput input;
  final int? supplierId;
  final String supplierName;
  final double unitCost;
  final String? largeUnit;
  final double unitsPerLarge;

  double get qty => input.suggested;
  double get value => qty * unitCost;
}

class PurchaseSuggestionsScreen extends StatefulWidget {
  const PurchaseSuggestionsScreen({super.key});
  @override
  State<PurchaseSuggestionsScreen> createState() => _PurchaseSuggestionsScreenState();
}

class _PurchaseSuggestionsScreenState extends State<PurchaseSuggestionsScreen> {
  static const _kLookback = 'ps_lookback_days';
  static const _kLead = 'ps_lead_days';
  static const _kCover = 'ps_cover_days';

  final _lookback = TextEditingController();
  final _lead = TextEditingController();
  final _cover = TextEditingController();
  List<_Suggestion> _rows = const [];
  bool _loading = true;
  bool _onlyUrgent = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _lookback.dispose();
    _lead.dispose();
    _cover.dispose();
    super.dispose();
  }

  int _int(TextEditingController c, int fb) {
    final v = parseMoney(c.text)?.round();
    return (v == null || v < 0) ? fb : v;
  }

  Future<void> _init() async {
    _lookback.text = '${(await ControlSettings.getNum(_kLookback, 60)).round()}';
    _lead.text = '${(await ControlSettings.getNum(_kLead, 7)).round()}';
    _cover.text = '${(await ControlSettings.getNum(_kCover, 30)).round()}';
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final lookback = _int(_lookback, 60).clamp(7, 365).toInt();
      final lead = _int(_lead, 7).clamp(0, 180).toInt();
      final cover = _int(_cover, 30).clamp(1, 365).toInt();
      await ControlSettings.setNum(_kLookback, lookback.toDouble());
      await ControlSettings.setNum(_kLead, lead.toDouble());
      await ControlSettings.setNum(_kCover, cover.toDouble());
      final db = await controlDb();
      final now = DateTime.now();
      final since = DateTime(now.year, now.month, now.day).subtract(Duration(days: lookback - 1));
      final sold = await db.rawQuery('''
        SELECT ii.product_id AS pid,
               SUM(COALESCE(ii.quantity_individual, 0) + COALESCE(ii.quantity_large_unit, 0)
                   * CASE WHEN COALESCE(ii.units_in_large_unit, 0) > 0 THEN ii.units_in_large_unit ELSE 1 END) AS q
        FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
        WHERE i.status = 'محفوظة' AND COALESCE(i.is_deleted, 0) = 0
          AND i.invoice_date >= ? AND ii.product_id IS NOT NULL
        GROUP BY ii.product_id''', [isoDay(since)]);
      final soldBy = {for (final r in sold) r['pid'] as int: d0(r['q'])};
      final hasPurchases = (await db.rawQuery(
              "SELECT 1 FROM sqlite_master WHERE type='table' AND name='purchase_invoice_items'"))
          .isNotEmpty;
      final lastSupplier = <int, (int?, String)>{};
      if (hasPurchases) {
        final ls = await db.rawQuery('''
          SELECT it.product_id AS pid, p.supplier_id AS sid, s.name AS sname, MAX(p.date) AS d
          FROM purchase_invoice_items it
          JOIN purchase_invoices p ON p.id = it.invoice_id
          LEFT JOIN suppliers s ON s.id = p.supplier_id
          WHERE p.status = 'confirmed'
          GROUP BY it.product_id''');
        for (final r in ls) {
          lastSupplier[r['pid'] as int] = (r['sid'] as int?, (r['sname'] as String?) ?? 'بلا مورد');
        }
      }
      final products = await db.rawQuery('''
        SELECT id, name, unit, stock_quantity, alert_quantity, cost_price, unit_hierarchy
        FROM products WHERE COALESCE(is_deleted, 0) = 0''');
      final out = <_Suggestion>[];
      for (final p in products) {
        final id = p['id'] as int;
        final soldQ = soldBy[id] ?? 0;
        final minStock = d0(p['alert_quantity']);
        if (soldQ <= 0 && minStock <= 0) continue;
        final input = ReorderInput(
          soldBaseQty: soldQ,
          lookbackDays: lookback,
          stockBaseQty: d0(p['stock_quantity']),
          leadDays: lead,
          coverDays: cover,
          minStock: minStock,
        );
        if (input.suggested <= 0) continue;
        final sup = lastSupplier[id];
        final (largeName, perLarge) = _firstLarge(p['unit_hierarchy'] as String?);
        out.add(_Suggestion(
          productId: id,
          name: '${p['name']}',
          unit: _unitLabel('${p['unit'] ?? ''}'),
          input: input,
          supplierId: sup?.$1,
          supplierName: sup?.$2 ?? 'بلا مورد سابق',
          unitCost: d0(p['cost_price']),
          largeUnit: largeName,
          unitsPerLarge: perLarge,
        ));
      }
      out.sort((a, b) {
        final s = a.supplierName.compareTo(b.supplierName);
        if (s != 0) return s;
        return (a.input.daysLeft ?? 1e9).compareTo(b.input.daysLeft ?? 1e9);
      });
      if (!mounted) return;
      setState(() {
        _rows = out;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  static String _unitLabel(String u) => switch (u) {
        'piece' => 'قطعة',
        'meter' => 'متر',
        _ => u,
      };

  /// أول وحدة كبرى وعدد الوحدات الأساسية فيها.
  static (String?, double) _firstLarge(String? json) {
    try {
      if (json == null || json.isEmpty) return (null, 1);
      final m = RegExp(r'"unit_name"\s*:\s*"([^"]+)"\s*,\s*"quantity"\s*:\s*([0-9.]+)').firstMatch(json);
      if (m == null) return (null, 1);
      final q = double.tryParse(m.group(2)!) ?? 1;
      return q > 1 ? (m.group(1), q) : (null, 1);
    } catch (_) {
      return (null, 1);
    }
  }

  String _qtyText(_Suggestion s) {
    final base = '${fmtQty(s.qty)} ${s.unit}';
    if (s.largeUnit == null) return base;
    return '$base (≈ ${fmtQty(toLargeUnits(s.qty, s.unitsPerLarge))} ${s.largeUnit})';
  }

  Future<void> _pdf(String supplier, List<_Suggestion> list) async {
    try {
      final bytes = await DocPdf.build(
        title: 'طلبية شراء مقترحة',
        number: supplier,
        date: DateTime.now(),
        partyLabel: 'المورد',
        partyName: supplier,
        infos: [
          MapEntry('مدة التغطية', '${_int(_cover, 30)} يوماً'),
          MapEntry('مدة التوريد', '${_int(_lead, 7)} أيام'),
        ],
        headers: const ['#', 'المادة', 'الرصيد الآن', 'المقترح'],
        rows: [
          for (var i = 0; i < list.length; i++)
            ['${i + 1}', list[i].name, '${fmtQty(list[i].input.stockBaseQty)} ${list[i].unit}', _qtyText(list[i])],
        ],
        total: list.fold<double>(0, (s, x) => s + x.value),
        showWords: false,
        showTotals: false,
      );
      if (mounted) await ReportExport.openPdf(context, bytes, 'طلبية مقترحة - $supplier');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _onlyUrgent ? _rows.where((r) => r.input.urgent).toList() : _rows;
    final groups = <String, List<_Suggestion>>{};
    for (final s in shown) {
      groups.putIfAbsent(s.supplierName, () => []).add(s);
    }
    return ErpPage(
      title: 'اقتراح طلبية شراء',
      subtitle: 'ماذا تطلب ومن أي مورد وبأي كمية — اقتراح فقط، لا يُنشئ مستنداً',
      icon: Icons.add_shopping_cart_rounded,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 150, child: MoneyField(controller: _lookback, label: 'سرعة البيع: آخر (يوم)')),
            SizedBox(width: 150, child: MoneyField(controller: _lead, label: 'مدة التوريد (يوم)')),
            SizedBox(width: 150, child: MoneyField(controller: _cover, label: 'تغطية (يوم)')),
            FilledButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.calculate_rounded), label: const Text('احسب')),
            FilterChip(
              label: const Text('العاجل فقط'),
              selected: _onlyUrgent,
              onSelected: (v) => setState(() => _onlyUrgent = v),
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : groups.isEmpty
                  ? const EmptyState('لا شيء يحتاج طلباً بهذه الإعدادات', icon: Icons.inventory_rounded)
                  : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                      for (final g in groups.entries)
                        ErpSection(
                          title: '${g.key} (${g.value.length})',
                          icon: Icons.local_shipping_rounded,
                          trailing: IconButton(
                            tooltip: 'PDF للمورد',
                            icon: const Icon(Icons.picture_as_pdf_rounded),
                            onPressed: () => _pdf(g.key, g.value),
                          ),
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                          child: Column(children: [
                            for (final s in g.value)
                              ListTile(
                                dense: true,
                                leading: Icon(s.input.urgent ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
                                    color: s.input.urgent ? ErpColors.red : ErpColors.blue),
                                title: Text('${s.name} — اطلب ${_qtyText(s)}',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text([
                                  'الرصيد ${fmtQty(s.input.stockBaseQty)}',
                                  'يُباع ${fmtQty(double.parse(s.input.dailyVelocity.toStringAsFixed(2)))} يومياً',
                                  if (s.input.daysLeft != null) 'يكفي ${s.input.daysLeft!.toStringAsFixed(0)} يوماً',
                                  if (s.input.minStock > 0) 'الحد الأدنى ${fmtQty(s.input.minStock)}',
                                  if (s.unitCost > 0) 'بكلفة تقريبية ${fmtMoney(s.value.roundToDouble())}',
                                ].join(' • ')),
                              ),
                          ]),
                        ),
                    ]),
        ),
      ]),
    );
  }
}
