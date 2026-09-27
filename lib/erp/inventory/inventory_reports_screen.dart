// lib/erp/inventory/inventory_reports_screen.dart
//
// 📊 مركز تقارير المخزون: حركة المواد، الجرد بتاريخ، تقييم المخزون، الراكدة،
// المتجاوزة للحدود (مع طلب شراء تلقائي)، الصلاحية القريبة. قراءة فقط + تصدير.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../report_export.dart';
import '../sales/quote_order_service.dart';
import 'inventory_reports.dart';

class _Report {
  const _Report(this.key, this.title, this.icon, this.color, this.hint);
  final String key;
  final String title;
  final IconData icon;
  final Color color;
  final String hint;
}

const _reports = [
  _Report('movements', 'حركة المواد', Icons.swap_vert_rounded, ErpColors.blue,
      'أول المدة + الوارد − الصادر = آخر المدة لكل مادة'),
  _Report('stock_at', 'الجرد بتاريخ', Icons.history_rounded, ErpColors.purple, 'كميات المخزون كما كانت في تاريخ سابق'),
  _Report('valuation', 'تقييم المخزون', Icons.account_balance_wallet_rounded, ErpColors.green,
      'قيمة البضاعة بالكلفة الحالية أو آخر/متوسط شراء'),
  _Report('stagnant', 'المواد الراكدة', Icons.hourglass_bottom_rounded, ErpColors.orange,
      'مواد لم تُبع (أو لم تُشترَ) خلال فترة'),
  _Report('limits', 'حدود الطلب', Icons.warning_amber_rounded, ErpColors.red,
      'تحت الحد الأدنى / فوق الأعلى / نفدت — مع إنشاء طلبات شراء'),
  _Report('expiring', 'الصلاحية', Icons.event_busy_rounded, ErpColors.gold, 'مواد تنتهي صلاحيتها قريباً'),
];

class InventoryReportsScreen extends StatefulWidget {
  const InventoryReportsScreen({super.key, this.initial = 'movements'});
  final String initial;
  @override
  State<InventoryReportsScreen> createState() => _InventoryReportsScreenState();
}

class _InventoryReportsScreenState extends State<InventoryReportsScreen> {
  final _svc = InventoryReports();
  late String _key = widget.initial;
  bool _loading = false;

  // المعاملات
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  DateTime _at = DateTime.now();
  int? _categoryId;
  int? _warehouseId;
  String _valMethod = 'current';
  String _stagType = 'sales';
  double _stagMaxQty = 0;
  String _limitMode = 'below_min';
  int _days = 30;
  bool _hideZero = true;
  bool _onlyMoved = true;
  List<Map<String, Object?>> _cats = const [];

  // النتيجة
  List<String> _headers = const [];
  List<List<String>> _rows = const [];
  List<String>? _footer;
  Set<int> _numeric = const {};
  List<Widget> _stats = const [];
  List<int> _rowIds = const [];

  _Report get _r => _reports.firstWhere((x) => x.key == _key);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final db = await erpDb();
      _cats = await db.query('categories', orderBy: 'name');
    } catch (_) {}
    await _run();
  }

  Future<void> _run() async {
    setState(() => _loading = true);
    try {
      switch (_key) {
        case 'movements':
          await _runMovements();
          break;
        case 'stock_at':
          await _runStockAt();
          break;
        case 'valuation':
          await _runValuation();
          break;
        case 'stagnant':
          await _runStagnant();
          break;
        case 'limits':
          await _runLimits();
          break;
        case 'expiring':
          await _runExpiring();
          break;
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runMovements() async {
    final all = await _svc.movements(from: _from, to: _to, categoryId: _categoryId);
    final rows = _onlyMoved ? all.where((r) => r.moved).toList() : all;
    var tin = 0.0, tout = 0.0;
    for (final r in rows) {
      tin += r.totalIn * r.cost;
      tout += r.totalOut * r.cost;
    }
    _headers = ['المادة', 'الوحدة', 'أول المدة', 'مشتريات', 'مرتجع بيع', 'إدخالات أخرى', 'مبيعات', 'إخراجات أخرى', 'آخر المدة'];
    _numeric = {2, 3, 4, 5, 6, 7, 8};
    _rows = [
      for (final r in rows)
        [
          r.name,
          r.unit,
          fmtQty(r.opening),
          fmtQty(r.purchases),
          fmtQty(r.returnsIn),
          fmtQty(r.otherIn),
          fmtQty(r.sales),
          fmtQty(r.otherOut),
          fmtQty(r.closing),
        ],
    ];
    _rowIds = [for (final r in rows) r.productId];
    _footer = null;
    _stats = [
      StatCard(label: 'مواد متحركة', value: '${rows.where((r) => r.moved).length}', icon: Icons.swap_vert, color: ErpColors.blue),
      StatCard(label: 'قيمة الوارد (بالكلفة)', value: fmtMoney(tin), icon: Icons.south_west, color: ErpColors.green),
      StatCard(label: 'قيمة الصادر (بالكلفة)', value: fmtMoney(tout), icon: Icons.north_east, color: ErpColors.red),
    ];
  }

  Future<void> _runStockAt() async {
    final rows = await _svc.stockAt(_at, hideZero: _hideZero);
    final total = rows.fold<double>(0, (s, r) => s + d0(r['value']));
    _headers = ['المادة', 'الوحدة', 'الكمية', 'الكلفة', 'القيمة'];
    _numeric = {2, 3, 4};
    _rows = [
      for (final r in rows) ['${r['name']}', '${r['unit']}', fmtQty(d0(r['qty'])), fmtMoney(d0(r['cost'])), fmtMoney(d0(r['value']))],
    ];
    _rowIds = [for (final r in rows) r['id'] as int];
    _footer = ['الإجمالي', '', '', '', fmtMoney(total)];
    _stats = [
      StatCard(label: 'عدد المواد', value: '${rows.length}', icon: Icons.category_outlined, color: ErpColors.purple),
      StatCard(label: 'القيمة بالكلفة الحالية', value: fmtMoney(total), icon: Icons.payments_outlined, color: ErpColors.green),
    ];
  }

  Future<void> _runValuation() async {
    final rows = await _svc.valuation(_valMethod, warehouseId: _warehouseId);
    final total = rows.fold<double>(0, (s, r) => s + d0(r['value']));
    final sale = rows.fold<double>(0, (s, r) => s + d0(r['sale_value']));
    _headers = ['المادة', 'الوحدة', 'الكمية', 'الكلفة', 'القيمة بالكلفة', 'القيمة بسعر المفرد'];
    _numeric = {2, 3, 4, 5};
    _rows = [
      for (final r in rows)
        [
          '${r['name']}',
          '${r['unit']}',
          fmtQty(d0(r['qty'])),
          fmtMoney(d0(r['cost'])),
          fmtMoney(d0(r['value'])),
          fmtMoney(d0(r['sale_value'])),
        ],
    ];
    _rowIds = [for (final r in rows) r['id'] as int];
    _footer = ['الإجمالي', '', '', '', fmtMoney(total), fmtMoney(sale)];
    _stats = [
      StatCard(label: 'القيمة بالكلفة', value: fmtMoney(total), icon: Icons.account_balance_wallet_outlined, color: ErpColors.green),
      StatCard(label: 'القيمة البيعية', value: fmtMoney(sale), icon: Icons.sell_outlined, color: ErpColors.blue),
      StatCard(
          label: 'الربح المتوقع',
          value: fmtMoney(sale - total),
          icon: Icons.trending_up_rounded,
          color: sale >= total ? ErpColors.green : ErpColors.red),
    ];
  }

  Future<void> _runStagnant() async {
    final rows = await _svc.stagnant(from: _from, to: _to, type: _stagType, maxQty: _stagMaxQty);
    final total = rows.fold<double>(0, (s, r) => s + d0(r['stock_value']));
    _headers = ['المادة', 'الوحدة', 'الرصيد', 'المباع', 'قيمة المباع', 'المشترى', 'قيمة الرصيد'];
    _numeric = {2, 3, 4, 5, 6};
    _rows = [
      for (final r in rows)
        [
          '${r['name']}',
          '${r['unit']}',
          fmtQty(d0(r['stock'])),
          fmtQty(d0(r['sold_qty'])),
          fmtMoney(d0(r['sold_value'])),
          fmtQty(d0(r['purchased_qty'])),
          fmtMoney(d0(r['stock_value'])),
        ],
    ];
    _rowIds = [for (final r in rows) r['id'] as int];
    _footer = ['الإجمالي', '', '', '', '', '', fmtMoney(total)];
    _stats = [
      StatCard(label: 'مواد راكدة', value: '${rows.length}', icon: Icons.hourglass_bottom, color: ErpColors.orange),
      StatCard(label: 'رأس مال مجمّد', value: fmtMoney(total), icon: Icons.ac_unit_rounded, color: ErpColors.red),
    ];
  }

  Future<void> _runLimits() async {
    final rows = await _svc.limits(_limitMode);
    _headers = ['المادة', 'الرصيد', 'محجوز', 'متاح', 'الحد الأدنى', 'الحد الأعلى', 'المقترح طلبه', 'المورد'];
    _numeric = {1, 2, 3, 4, 5, 6};
    _rows = [
      for (final r in rows)
        [
          '${r['name']}',
          fmtQty(d0(r['stock_quantity'])),
          fmtQty(d0(r['reserved'])),
          fmtQty(d0(r['available'])),
          r['min_qty'] == null ? '' : fmtQty(d0(r['min_qty'])),
          r['max_qty'] == null ? '' : fmtQty(d0(r['max_qty'])),
          fmtQty(d0(r['suggest'])),
          '${r['supplier_name'] ?? ''}',
        ],
    ];
    _rowIds = [for (final r in rows) r['id'] as int];
    _footer = null;
    _stats = [
      StatCard(label: 'مواد', value: '${rows.length}', icon: Icons.warning_amber_rounded, color: ErpColors.red),
    ];
  }

  Future<void> _runExpiring() async {
    final rows = await _svc.expiring(_days);
    final now = DateTime.now();
    _headers = ['المادة', 'الرصيد', 'تاريخ الانتهاء', 'المتبقي (يوم)'];
    _numeric = {1, 3};
    _rows = [
      for (final r in rows)
        [
          '${r['name']}',
          fmtQty(d0(r['stock_quantity'])),
          fmtDate(parseDate(r['expiry_date'])),
          '${parseDate(r['expiry_date']).difference(DateTime(now.year, now.month, now.day)).inDays}',
        ],
    ];
    _rowIds = [for (final r in rows) r['id'] as int];
    _footer = null;
    final expired = rows.where((r) => parseDate(r['expiry_date']).isBefore(now)).length;
    _stats = [
      StatCard(label: 'منتهية', value: '$expired', icon: Icons.dangerous_outlined, color: ErpColors.red),
      StatCard(label: 'قريبة الانتهاء', value: '${rows.length - expired}', icon: Icons.schedule, color: ErpColors.gold),
    ];
  }

  Future<void> _autoReorder() async {
    final ok = await confirmDialog(context, 'طلبات شراء تلقائية',
        'إنشاء طلبات شراء (مسودات) لكل مورد بالمواد التي وصلت حدها الأدنى؟ لا يتغير المخزون ولا الحسابات.');
    if (!ok) return;
    try {
      final n = await QuoteOrderService().autoReorder();
      if (mounted) showOk(context, n == 0 ? 'لا توجد مواد تحتاج طلباً (أو لها طلبات مفتوحة)' : 'أُنشئ $n طلب شراء');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _params() {
    final children = <Widget>[];
    Widget cat() => DropBox<int?>(
          label: 'القسم',
          value: _categoryId,
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('كل الأقسام')),
            for (final c in _cats) DropdownMenuItem<int?>(value: c['id'] as int, child: Text('${c['name']}')),
          ],
          onChanged: (v) {
            _categoryId = v;
            _run();
          },
        );
    Widget period() => Wrap(spacing: 8, children: [
          DateButton(label: 'من', value: _from, onChanged: (d) {
            _from = d;
            _run();
          }),
          DateButton(label: 'إلى', value: _to, onChanged: (d) {
            _to = d;
            _run();
          }),
        ]);
    switch (_key) {
      case 'movements':
        children.addAll([
          period(),
          cat(),
          FilterChip(
              label: const Text('المتحركة فقط'),
              selected: _onlyMoved,
              onSelected: (v) {
                _onlyMoved = v;
                _run();
              }),
        ]);
        break;
      case 'stock_at':
        children.addAll([
          DateButton(label: 'بتاريخ', value: _at, onChanged: (d) {
            _at = d;
            _run();
          }),
          FilterChip(
              label: const Text('إخفاء الصفري'),
              selected: _hideZero,
              onSelected: (v) {
                _hideZero = v;
                _run();
              }),
        ]);
        break;
      case 'valuation':
        children.addAll([
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'current', label: Text('الكلفة الحالية')),
              ButtonSegment(value: 'last_purchase', label: Text('آخر شراء')),
              ButtonSegment(value: 'avg_purchase', label: Text('متوسط الشراء')),
            ],
            selected: {_valMethod},
            onSelectionChanged: (s) {
              _valMethod = s.first;
              _run();
            },
          ),
          WarehouseDropdown(
              value: _warehouseId,
              label: 'المخزن (فارغ = الكل)',
              onChanged: (w) {
                _warehouseId = w?.id;
                _run();
              }),
        ]);
        break;
      case 'stagnant':
        children.addAll([
          period(),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'sales', label: Text('بيعاً')),
              ButtonSegment(value: 'purchase', label: Text('شراءً')),
              ButtonSegment(value: 'any', label: Text('مطلقاً')),
            ],
            selected: {_stagType},
            onSelectionChanged: (s) {
              _stagType = s.first;
              _run();
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.tune),
            label: Text('حد الكمية: ${fmtQty(_stagMaxQty)}'),
            onPressed: () async {
              final v = await askNumber(context, 'اعتبرها راكدة إن تحرك منها أقل من أو يساوي', initial: _stagMaxQty);
              if (v != null && v >= 0) {
                _stagMaxQty = v;
                _run();
              }
            },
          ),
        ]);
        break;
      case 'limits':
        children.addAll([
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'below_min', label: Text('تحت الأدنى')),
              ButtonSegment(value: 'above_max', label: Text('فوق الأعلى')),
              ButtonSegment(value: 'zero', label: Text('نفدت')),
            ],
            selected: {_limitMode},
            onSelectionChanged: (s) {
              _limitMode = s.first;
              _run();
            },
          ),
          if (_limitMode == 'below_min')
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: ErpColors.red),
              onPressed: _autoReorder,
              icon: const Icon(Icons.shopping_cart_checkout_rounded),
              label: const Text('إنشاء طلبات شراء تلقائياً'),
            ),
        ]);
        break;
      case 'expiring':
        children.addAll([
          for (final d in [7, 30, 60, 90])
            ChoiceChip(
              label: Text('خلال $d يوم'),
              selected: _days == d,
              onSelected: (_) {
                _days = d;
                _run();
              },
            ),
        ]);
        break;
    }
    return Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: children);
  }

  String get _subtitle {
    switch (_key) {
      case 'movements':
      case 'stagnant':
        return 'من ${fmtDate(_from)} إلى ${fmtDate(_to)}';
      case 'stock_at':
        return 'بتاريخ ${fmtDate(_at)}';
      default:
        return fmtDate(DateTime.now());
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return ErpPage(
      title: 'تقارير المخزون',
      subtitle: r.hint,
      icon: Icons.analytics_rounded,
      actions: [
        ...exportActions(context,
            title: r.title,
            headers: () => _headers,
            rows: () => _rows,
            footer: () => _footer,
            subtitle: () => _subtitle),
      ],
      headerExtra: SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final x in _reports)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                avatar: Icon(x.icon, size: 18, color: _key == x.key ? Colors.white : x.color),
                label: Text(x.title),
                selected: _key == x.key,
                selectedColor: x.color,
                labelStyle: TextStyle(color: _key == x.key ? Colors.white : ErpColors.text, fontWeight: FontWeight.w600),
                onSelected: (_) {
                  setState(() {
                    _key = x.key;
                    _rows = const [];
                    _headers = const [];
                    _stats = const [];
                  });
                  _run();
                },
              ),
            ),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        ErpSection(title: r.title, icon: r.icon, color: r.color, child: _params()),
        if (_stats.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 10, runSpacing: 10, children: _stats),
          ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
        else if (_rows.isEmpty)
          const EmptyState('لا توجد نتائج', icon: Icons.analytics_outlined)
        else
          ErpSection(
            title: '${_rows.length} سطر',
            icon: Icons.table_rows_rounded,
            color: r.color,
            child: SimpleTable(
              headers: _headers,
              rows: _rows,
              numericColumns: _numeric,
              footer: _footer,
              onRowTap: (i) {
                if (i < 0 || i >= _rowIds.length) return;
                _openProductCard(_rowIds[i]);
              },
            ),
          ),
      ]),
    );
  }

  Future<void> _openProductCard(int productId) async {
    final rows = await _svc.productCard(productId);
    final db = await erpDb();
    final p = await db.query('products', columns: ['name'], where: 'id = ?', whereArgs: [productId], limit: 1);
    if (!mounted) return;
    final name = p.isEmpty ? '' : '${p.first['name']}';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ErpPage(
          title: 'بطاقة حركة: $name',
          icon: Icons.timeline_rounded,
          actions: [
            ...exportActions(context,
                title: 'حركة $name',
                headers: () => ['التاريخ', 'النوع', 'البيان', 'الكمية', 'الرصيد'],
                rows: () => [
                      for (final r in rows)
                        [
                          fmtDate(parseDate(r['d'])),
                          movementKindLabels[r['kind']] ?? '${r['kind']}',
                          '${r['note'] ?? ''}',
                          fmtQty(d0(r['q'])),
                          fmtQty(d0(r['balance'])),
                        ],
                    ]),
          ],
          body: rows.isEmpty
              ? const EmptyState('لا توجد حركات')
              : ListView(padding: const EdgeInsets.all(16), children: [
                  SimpleTable(
                    headers: const ['التاريخ', 'النوع', 'البيان', 'الكمية', 'الرصيد'],
                    numericColumns: const {3, 4},
                    rows: [
                      for (final r in rows)
                        [
                          fmtDate(parseDate(r['d'])),
                          movementKindLabels[r['kind']] ?? '${r['kind']}',
                          '${r['note'] ?? ''}',
                          fmtQty(d0(r['q'])),
                          fmtQty(d0(r['balance'])),
                        ],
                    ],
                  ),
                ]),
        ),
      ),
    );
  }
}

/// اختصار للاستخدام من أماكن أخرى.
Future<void> openReportExport(BuildContext context, String title, List<String> h, List<List<String>> r) =>
    ReportExport.exportPdf(context, title: title, headers: h, rows: r);
