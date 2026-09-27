// lib/erp/inventory/manufacturing_screen.dart
//
// 🏭 التصنيع (مثل «نماذج التصنيع» في الإداري):
//   نموذج = مادة جاهزة + مواد أولية بكمياتها (أساسية/ثانوية) + مصاريف صناعية.
//   الاحتياجات والكمية الممكن تصنيعها، تنفيذ عملية تصنيع، ومراقبة الهدر.
// التنفيذ عبر StockDocsService.produce (مستند «تصنيع» واحد: إخراج الأولية + إدخال
// الجاهزة بكلفتها + قيد المصاريف المحمّلة).

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart';
import '../../accounting/screens/acc_ui.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../stock_helpers.dart';
import 'stock_docs_screen.dart';
import 'stock_docs_service.dart';

class ManufacturingScreen extends StatefulWidget {
  const ManufacturingScreen({super.key});
  @override
  State<ManufacturingScreen> createState() => _ManufacturingScreenState();
}

class _ManufacturingScreenState extends State<ManufacturingScreen> {
  final _svc = StockDocsService();
  List<Map<String, Object?>> _models = const [];
  final Map<int, double> _possible = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final m = await _svc.models();
      final poss = <int, double>{};
      for (final x in m) {
        poss[x['id'] as int] = await _svc.maxProducible(x['id'] as int, essentialOnly: true);
      }
      if (!mounted) return;
      setState(() {
        _models = m;
        _possible
          ..clear()
          ..addAll(poss);
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([int? id]) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => BomModelEditorScreen(modelId: id)));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'التصنيع',
      subtitle: 'نماذج التصنيع • الاحتياجات • عمليات الإنتاج • مراقبة الهدر',
      icon: Icons.precision_manufacturing_rounded,
      actions: [
        IconButton(
          tooltip: 'سجل عمليات التصنيع',
          icon: const Icon(Icons.history_rounded, color: Colors.white),
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const StockDocsListScreen(docType: 'production'))),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: ErpColors.purple,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('نموذج جديد', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _models.isEmpty
              ? const EmptyState('لا توجد نماذج تصنيع — أنشئ نموذجاً (مثلاً: خلطة، طقم، منتج مجمّع)',
                  icon: Icons.precision_manufacturing_outlined)
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    mainAxisExtent: 190,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _models.length,
                  itemBuilder: (_, i) {
                    final m = _models[i];
                    final id = m['id'] as int;
                    final can = _possible[id] ?? 0;
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: ErpColors.border),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.03), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          CircleAvatar(
                            backgroundColor: ErpColors.purple.withOpacity(.12),
                            child: const Icon(Icons.precision_manufacturing_rounded, color: ErpColors.purple),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${m['name']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              Text('نموذج #${m['model_no']} • ينتج ${m['product_name'] ?? '?'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: ErpColors.muted, fontSize: 12)),
                            ]),
                          ),
                          IconButton(tooltip: 'تعديل', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(id)),
                        ]),
                        const Spacer(),
                        Wrap(spacing: 8, runSpacing: 6, children: [
                          StatusBadge('${m['n_components']} مادة أولية', color: ErpColors.blue),
                          StatusBadge('وحدة الإنتاج ${fmtQty(d0(m['output_qty']))}', color: ErpColors.navy),
                          StatusBadge('يمكن تصنيع ${fmtQty(can)}', color: can > 0 ? ErpColors.green : ErpColors.red),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: ErpColors.purple),
                              onPressed: () async {
                                final ok = await Navigator.push<bool>(
                                    context, MaterialPageRoute(builder: (_) => ProduceScreen(modelId: id)));
                                if (ok == true) _load();
                              },
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('تصنيع'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => _waste(m),
                            icon: const Icon(Icons.analytics_outlined),
                            label: const Text('الهدر'),
                          ),
                        ]),
                      ]),
                    );
                  },
                ),
    );
  }

  Future<void> _waste(Map<String, Object?> m) async {
    final rows = await _svc.wasteReport(m['id'] as int);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('مراقبة الهدر — ${m['name']}'),
        content: SizedBox(
          width: 560,
          child: rows.isEmpty
              ? const Text('لا توجد عمليات تصنيع بعد')
              : SimpleTable(
                  headers: const ['المادة الأولية', 'المقدّر', 'الفعلي', 'الفرق', 'النسبة'],
                  numericColumns: const {1, 2, 3, 4},
                  rows: [
                    for (final r in rows)
                      [
                        '${r['product_name']}',
                        fmtQty(d0(r['planned'])),
                        fmtQty(d0(r['actual'])),
                        fmtQty(d0(r['actual']) - d0(r['planned'])),
                        d0(r['planned']) <= 0
                            ? '-'
                            : '${((d0(r['actual']) - d0(r['planned'])) / d0(r['planned']) * 100).toStringAsFixed(1)}%',
                      ],
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
      ),
    );
  }
}

// ═══════════════════════════ محرر النموذج ═══════════════════════════

class _Comp {
  _Comp(this.product, this.qty, this.essential);
  final ProductLite product;
  double qty;
  bool essential;
}

class _Exp {
  _Exp(this.name, this.amount);
  String name;
  double amount;
}

class BomModelEditorScreen extends StatefulWidget {
  const BomModelEditorScreen({super.key, this.modelId});
  final int? modelId;
  @override
  State<BomModelEditorScreen> createState() => _BomModelEditorScreenState();
}

class _BomModelEditorScreenState extends State<BomModelEditorScreen> {
  final _svc = StockDocsService();
  final _name = TextEditingController();
  final _notes = TextEditingController();
  final _outQty = TextEditingController(text: '1');
  ProductLite? _product;
  int? _rawWh, _finWh;
  final _comps = <_Comp>[];
  final _exps = <_Exp>[];
  bool _saving = false;
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    if (widget.modelId != null) _loadModel();
  }

  Future<void> _loadModel() async {
    final db = await erpDb();
    final m = await db.query('bom_models', where: 'id = ?', whereArgs: [widget.modelId], limit: 1);
    if (m.isEmpty) return;
    final comps = await _svc.modelComponents(widget.modelId!);
    final exps = await _svc.modelExpenses(widget.modelId!);
    final prod = await ErpStock.byId(db, m.first['product_id'] as int);
    final cl = <_Comp>[];
    for (final c in comps) {
      final p = await ErpStock.byId(db, c['product_id'] as int);
      if (p != null) cl.add(_Comp(p, d0(c['qty']), (c['is_essential'] as int? ?? 1) == 1));
    }
    if (!mounted) return;
    setState(() {
      _name.text = '${m.first['name']}';
      _notes.text = '${m.first['notes'] ?? ''}';
      _outQty.text = fmtQty(d0(m.first['output_qty']));
      _rawWh = m.first['raw_warehouse_id'] as int?;
      _finWh = m.first['finished_warehouse_id'] as int?;
      _product = prod;
      _comps
        ..clear()
        ..addAll(cl);
      _exps
        ..clear()
        ..addAll([for (final e in exps) _Exp('${e['name']}', d0(e['amount']))]);
      _rev++;
    });
  }

  double get _rawCost => _comps.fold<double>(0, (s, c) => s + c.qty * c.product.cost);
  double get _expTotal => _exps.fold<double>(0, (s, e) => s + e.amount);

  Future<void> _save() async {
    if (_product == null) {
      showError(context, 'اختر المادة المصنّعة');
      return;
    }
    setState(() => _saving = true);
    try {
      await _svc.saveModel(
        id: widget.modelId,
        name: _name.text,
        productId: _product!.id,
        outputQty: parseMoney(_outQty.text) ?? 1,
        rawWarehouseId: _rawWh,
        finishedWarehouseId: _finWh,
        notes: _notes.text.trim(),
        components: [
          for (final c in _comps) {'product_id': c.product.id, 'qty': c.qty, 'is_essential': c.essential ? 1 : 0},
        ],
        expenses: [
          for (final e in _exps)
            if (e.name.trim().isNotEmpty) {'name': e.name.trim(), 'amount': e.amount},
        ],
      );
      if (!mounted) return;
      showOk(context, 'حُفظ النموذج');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, 'حذف النموذج', 'إيقاف هذا النموذج؟ (عملياته السابقة تبقى كما هي)',
        color: ErpColors.red);
    if (!ok) return;
    await _svc.deleteModel(widget.modelId!);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final out = parseMoney(_outQty.text) ?? 1;
    final unitCost = out <= 0 ? 0.0 : (_rawCost + _expTotal) / out;
    return ErpPage(
      title: widget.modelId == null ? 'نموذج تصنيع جديد' : 'تعديل نموذج التصنيع',
      icon: Icons.precision_manufacturing_rounded,
      actions: [
        if (widget.modelId != null)
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white), tooltip: 'حذف', onPressed: _delete),
      ],
      bottom: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: Wrap(spacing: 16, children: [
                Text('كلفة المواد: ${fmtMoney(_rawCost)}'),
                Text('المصاريف: ${fmtMoney(_expTotal)}'),
                Text('كلفة الوحدة المصنّعة: ${fmtMoney(unitCost)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: ErpColors.purple)),
              ]),
            ),
            PrimaryButton(label: 'حفظ النموذج', icon: Icons.save_rounded, color: ErpColors.purple, busy: _saving, onPressed: _save),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 20), children: [
        ErpSection(
          title: 'المادة المصنّعة',
          icon: Icons.inventory_rounded,
          color: ErpColors.purple,
          child: FieldGrid(children: [
            TextBox(controller: _name, label: 'اسم النموذج', width: 260),
            OutlinedButton.icon(
              icon: const Icon(Icons.search),
              label: Text(_product?.name ?? 'اختر المادة الجاهزة'),
              onPressed: () async {
                final p = await Pickers.product(context, title: 'المادة الجاهزة');
                if (p != null) setState(() => _product = p);
              },
            ),
            MoneyField(controller: _outQty, label: 'كمية الإنتاج للنموذج', width: 160, onChanged: (_) => setState(() {})),
            WarehouseDropdown(value: _rawWh, label: 'مخزن المواد الأولية', onChanged: (w) => setState(() => _rawWh = w?.id)),
            WarehouseDropdown(value: _finWh, label: 'مخزن المادة الجاهزة', onChanged: (w) => setState(() => _finWh = w?.id)),
            TextBox(controller: _notes, label: 'ملاحظات', width: 260),
          ]),
        ),
        ErpSection(
          title: 'المواد الأولية (لكمية الإنتاج أعلاه)',
          icon: Icons.category_rounded,
          color: ErpColors.blue,
          trailing: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('إضافة مادة'),
            onPressed: () async {
              final p = await Pickers.product(context, title: 'مادة أولية');
              if (p == null) return;
              if (_comps.any((c) => c.product.id == p.id)) {
                if (mounted) showError(context, 'المادة مضافة مسبقاً');
                return;
              }
              setState(() => _comps.add(_Comp(p, 1, true)));
            },
          ),
          child: _comps.isEmpty
              ? const Padding(padding: EdgeInsets.all(12), child: Text('أضف المواد الأولية', style: TextStyle(color: ErpColors.muted)))
              : Column(children: [
                  for (final c in _comps)
                    ListTile(
                      key: ValueKey('c-${c.product.id}-$_rev'),
                      dense: true,
                      leading: Tooltip(
                        message: c.essential ? 'أساسية (لا تصنيع بدونها)' : 'ثانوية',
                        child: IconButton(
                          icon: Icon(c.essential ? Icons.star_rounded : Icons.star_border_rounded,
                              color: c.essential ? ErpColors.gold : ErpColors.muted),
                          onPressed: () => setState(() => c.essential = !c.essential),
                        ),
                      ),
                      title: Text(c.product.name),
                      subtitle: Text('كلفة ${fmtMoney(c.product.cost)} / ${c.product.baseUnitName} • متوفر ${fmtQty(c.product.stock)}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(
                          width: 110,
                          child: TextFormField(
                            initialValue: fmtQty(c.qty),
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                                isDense: true, labelText: 'الكمية (${c.product.baseUnitName})', border: const OutlineInputBorder()),
                            onChanged: (v) => setState(() => c.qty = parseMoney(v) ?? 0),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(fmtMoney(c.qty * c.product.cost), style: const TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.close, color: ErpColors.red),
                          onPressed: () => setState(() {
                            _comps.remove(c);
                            _rev++;
                          }),
                        ),
                      ]),
                    ),
                ]),
        ),
        ErpSection(
          title: 'المصاريف الصناعية',
          icon: Icons.bolt_rounded,
          color: ErpColors.orange,
          trailing: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('إضافة مصروف'),
            onPressed: () => setState(() {
              _exps.add(_Exp('', 0));
              _rev++;
            }),
          ),
          child: Column(children: [
            for (var i = 0; i < _exps.length; i++)
              Padding(
                key: ValueKey('e-$i-$_rev'),
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _exps[i].name,
                      decoration: const InputDecoration(isDense: true, labelText: 'البند (أجور، كهرباء...)', border: OutlineInputBorder()),
                      onChanged: (v) => _exps[i].name = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 150,
                    child: TextFormField(
                      initialValue: _exps[i].amount == 0 ? '' : fmtMoney(_exps[i].amount),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(isDense: true, labelText: 'المبلغ', border: OutlineInputBorder()),
                      onChanged: (v) => setState(() => _exps[i].amount = parseMoney(v) ?? 0),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: ErpColors.red),
                    onPressed: () => setState(() {
                      _exps.removeAt(i);
                      _rev++;
                    }),
                  ),
                ]),
              ),
            if (_exps.isEmpty)
              const Text('اختياري: تُحمَّل على كلفة المادة المصنّعة وتُقيَّد على حساب «مصاريف صناعية محمّلة».',
                  style: TextStyle(color: ErpColors.muted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════ تنفيذ تصنيع ═══════════════════════════

class ProduceScreen extends StatefulWidget {
  const ProduceScreen({super.key, required this.modelId});
  final int modelId;
  @override
  State<ProduceScreen> createState() => _ProduceScreenState();
}

class _ProduceScreenState extends State<ProduceScreen> {
  final _svc = StockDocsService();
  final _qty = TextEditingController(text: '1');
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  Map<String, Object?>? _model;
  List<Map<String, Object?>> _req = const [];
  double _expPerOut = 0;
  double _max = 0;
  bool _allowShortage = false;
  Account? _overheadAcc;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final db = await erpDb();
    final m = await db.rawQuery(
        'SELECT m.*, p.name AS product_name FROM bom_models m LEFT JOIN products p ON p.id = m.product_id WHERE m.id = ?',
        [widget.modelId]);
    final exps = await _svc.modelExpenses(widget.modelId);
    final max = await _svc.maxProducible(widget.modelId, essentialOnly: true);
    if (!mounted || m.isEmpty) return;
    setState(() {
      _model = m.first;
      final out = d0(m.first['output_qty']) <= 0 ? 1.0 : d0(m.first['output_qty']);
      _expPerOut = exps.fold<double>(0, (s, e) => s + d0(e['amount'])) / out;
      _max = max;
    });
    await _calc();
  }

  Future<void> _calc() async {
    final q = parseMoney(_qty.text) ?? 0;
    if (q <= 0) {
      setState(() => _req = const []);
      return;
    }
    final r = await _svc.requirements(widget.modelId, q);
    if (mounted) setState(() => _req = r);
  }

  Future<void> _produce() async {
    final q = parseMoney(_qty.text) ?? 0;
    if (q <= 0) {
      showError(context, 'اكتب الكمية');
      return;
    }
    if (!await PeriodLock.guard(context, _date)) return;
    final short = _req.where((r) => d0(r['shortage']) > 1e-9).toList();
    if (!mounted) return;
    final ok = await confirmDialog(
      context,
      'تنفيذ التصنيع',
      'تصنيع ${fmtQty(q)} × ${_model?['product_name']}.\n'
          'ستُخرج المواد الأولية وتُدخل المادة الجاهزة بكلفتها، ويُسجَّل القيد تلقائياً.'
          '${short.isNotEmpty ? '\n⚠️ توجد ${short.length} مادة ناقصة.' : ''}',
      color: ErpColors.purple,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final id = await _svc.produce(
        modelId: widget.modelId,
        qty: q,
        date: _date,
        overheadAccountId: _overheadAcc?.id,
        allowShortage: _allowShortage,
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      showOk(context, 'تم التصنيع (مستند #$id)');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _model;
    if (m == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final q = parseMoney(_qty.text) ?? 0;
    final raw = _req.fold<double>(0, (s, r) => s + d0(r['need']) * d0(r['cost_price']));
    final exp = _expPerOut * q;
    final unit = q <= 0 ? 0.0 : (raw + exp) / q;
    return ErpPage(
      title: 'تصنيع: ${m['name']}',
      subtitle: 'المادة الجاهزة: ${m['product_name']} • الحد الممكن ${fmtQty(_max)}',
      icon: Icons.play_circle_fill_rounded,
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'كلفة المواد', value: fmtMoney(raw), icon: Icons.category_outlined, color: ErpColors.blue),
        StatCard(label: 'المصاريف المحمّلة', value: fmtMoney(exp), icon: Icons.bolt_rounded, color: ErpColors.orange),
        StatCard(label: 'كلفة الوحدة', value: fmtMoney(unit), icon: Icons.calculate_rounded, color: ErpColors.purple),
      ]),
      bottom: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
                child: Text('الإجمالي: ${fmtMoney(raw + exp)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ErpColors.purple))),
            PrimaryButton(
                label: 'تنفيذ التصنيع', icon: Icons.play_arrow_rounded, color: ErpColors.purple, busy: _busy, onPressed: _produce),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 20), children: [
        ErpSection(
          title: 'العملية',
          icon: Icons.tune_rounded,
          color: ErpColors.purple,
          child: FieldGrid(children: [
            MoneyField(
                controller: _qty,
                label: 'الكمية المراد تصنيعها',
                width: 180,
                onChanged: (_) {
                  setState(() {});
                  _calc();
                }),
            TextButton(
                onPressed: () {
                  _qty.text = fmtQty(_max);
                  _calc();
                },
                child: Text('أقصى ممكن (${fmtQty(_max)})')),
            DateButton(label: 'التاريخ', value: _date, onChanged: (d) => setState(() => _date = d)),
            OutlinedButton.icon(
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(_overheadAcc == null ? 'حساب المصاريف: تلقائي' : '${_overheadAcc!.code} ${_overheadAcc!.name}'),
              onPressed: () async {
                final a = await Pickers.account(context, title: 'حساب المصاريف الصناعية المحمّلة');
                setState(() => _overheadAcc = a);
              },
            ),
            FilterChip(
              label: const Text('السماح بنقص المواد'),
              selected: _allowShortage,
              selectedColor: ErpColors.red.withOpacity(.15),
              onSelected: (v) => setState(() => _allowShortage = v),
            ),
            TextBox(controller: _notes, label: 'ملاحظات', width: 260),
          ]),
        ),
        ErpSection(
          title: 'الاحتياجات',
          icon: Icons.checklist_rounded,
          color: ErpColors.blue,
          child: SimpleTable(
            headers: const ['المادة', 'نوعها', 'المطلوب', 'المتوفر', 'الناقص', 'الفائض', 'الكلفة'],
            numericColumns: const {2, 3, 4, 5, 6},
            rows: [
              for (final r in _req)
                [
                  '${r['product_name']}',
                  (r['is_essential'] as int? ?? 1) == 1 ? 'أساسية' : 'ثانوية',
                  fmtQty(d0(r['need'])),
                  fmtQty(d0(r['available'])),
                  d0(r['shortage']) > 1e-9 ? '⚠ ${fmtQty(d0(r['shortage']))}' : '-',
                  fmtQty(d0(r['surplus'])),
                  fmtMoney(d0(r['need']) * d0(r['cost_price'])),
                ],
            ],
          ),
        ),
      ]),
    );
  }
}
