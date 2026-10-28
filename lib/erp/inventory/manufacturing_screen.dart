// lib/erp/inventory/manufacturing_screen.dart
//
// 🏭 التصنيع (مثل «نماذج التصنيع» في الإداري):
//   نموذج (وصفة) = مادة جاهزة + مواد أولية بكمياتها (أساسية/ثانوية) + مصاريف صناعية.
//   الاحتياجات والكمية الممكن تصنيعها، تنفيذ عملية تصنيع، ومراقبة الهدر.
// التنفيذ عبر StockDocsService.produce (مستند «تصنيع» واحد: إخراج الأولية + إدخال
// الجاهزة بكلفتها + قيد المصاريف المحمّلة).
//
// الواجهة: شرح «كيف يعمل» في 3 خطوات، بطاقة لكل وصفة بجاهزيتها، محرر وصفة
// بخطوات مرقّمة وملخص كلفة حيّ، وشاشة تصنيع تُظهر الناقص قبل التنفيذ.

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart';
import '../../accounting/screens/acc_ui.dart';
import '../../widgets/formatters.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../stock_helpers.dart';
import 'stock_docs_screen.dart';
import 'stock_docs_service.dart';

// ═══════════════════════════ عناصر مشتركة ═══════════════════════════

String _unitName(Object? u) {
  final s = '${u ?? ''}';
  return s == 'piece' ? 'قطعة' : (s == 'meter' ? 'متر' : s);
}

BoxDecoration _cardDeco({Color? accent}) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: accent == null ? ErpColors.border : accent.withValues(alpha: 0.4),
        width: accent == null ? 1 : 1.4,
      ),
      boxShadow: [BoxShadow(color: ErpColors.navy.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4))],
    );

/// بطاقة خطوة مرقّمة.
Widget _stepCard(int n, String title, String subtitle, Color color, Widget child, {Widget? trailing}) => Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: StepTitle(n, title, subtitle: subtitle, color: color)),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 4),
        child,
      ]),
    );

Widget _iconBox(IconData icon, Color color, {double size = 46}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, color: color, size: size * 0.5),
    );

Widget _sumLine(String label, String value, {Color color = ErpColors.text, bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: bold ? ErpColors.text : ErpColors.muted))),
        Text(value,
            style: TextStyle(fontSize: bold ? 15 : 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
      ]),
    );

Widget _check(bool ok, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 17, color: ok ? ErpColors.green : ErpColors.muted),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text, style: TextStyle(fontSize: 12.5, color: ok ? ErpColors.text : ErpColors.muted))),
      ]),
    );

Widget _hint(String text, {IconData icon = Icons.lightbulb_outline_rounded, Color color = ErpColors.muted}) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color, height: 1.45))),
      ]),
    );

Widget _bottomBarShell(Widget child) => Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: ErpColors.border)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2))],
      ),
      child: SafeArea(top: false, child: child),
    );

/// شرح «كيف يعمل التصنيع» في ثلاث خطوات.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();
  static const _steps = [
    (Icons.menu_book_rounded, 'الوصفة (النموذج)', 'ماذا تصنع ومن ماذا: المادة الجاهزة + المواد الأولية بكمياتها + مصاريف اختيارية.'),
    (Icons.play_circle_outline_rounded, 'التصنيع', 'اختر الوصفة واكتب الكمية — يُظهر البرنامج الاحتياجات والناقص قبل التنفيذ.'),
    (Icons.auto_awesome_rounded, 'النتيجة تلقائياً', 'تخرج المواد الأولية من المخزن وتدخل المادة الجاهزة بكلفتها الحقيقية، ويُسجَّل القيد.'),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 760;
        Widget step(int i) {
          final s = _steps[i];
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: ErpColors.purple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(s.$1, size: 19, color: ErpColors.purple),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i + 1}. ${s.$2}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(s.$3, style: const TextStyle(fontSize: 12, color: ErpColors.muted, height: 1.45)),
              ]),
            ),
          ]);
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ErpColors.purple.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ErpColors.purple.withValues(alpha: 0.18)),
          ),
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (var i = 0; i < _steps.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(10, 8, 10, 0),
                        child: Icon(Icons.arrow_forward_rounded, size: 18, color: ErpColors.muted),
                      ),
                    Expanded(child: step(i)),
                  ],
                ])
              : Column(children: [
                  for (var i = 0; i < _steps.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    step(i),
                  ],
                ]),
        );
      });
}

// ═══════════════════════════ قائمة الوصفات ═══════════════════════════

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
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
    if (ok == true && mounted) _load();
  }

  Future<void> _produce(int id) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ProduceScreen(modelId: id)));
    if (ok == true && mounted) _load();
  }

  void _history() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const StockDocsListScreen(docType: 'production')));

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'التصنيع',
      subtitle: 'حوّل المواد الأولية إلى منتج جاهز بكلفته الحقيقية',
      icon: Icons.precision_manufacturing_rounded,
      actions: [
        IconButton(tooltip: 'سجل عمليات التصنيع', icon: const Icon(Icons.history_rounded), onPressed: _history),
        IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh_rounded), onPressed: _load),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _models.isEmpty
              ? _empty()
              : _list(),
    );
  }

  Widget _empty() => ListView(padding: const EdgeInsets.all(16), children: [
        const _HowItWorks(),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: _cardDeco(),
          child: Column(children: [
            _iconBox(Icons.precision_manufacturing_rounded, ErpColors.purple, size: 72),
            const SizedBox(height: 14),
            const Text('لا توجد وصفات تصنيع بعد',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ErpColors.text)),
            const SizedBox(height: 6),
            const Text(
              'أمثلة: خلطة بهارات من مكوّناتها، طقم هدايا من عدة مواد، كيك من الطحين والسكر والبيض، منتج مجمّع من قطع.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: ErpColors.muted, height: 1.5),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: ErpColors.purple),
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('أنشئ أول وصفة'),
            ),
          ]),
        ),
      ]);

  Widget _list() => LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth - 32;
        final cols = (w / 340).floor().clamp(1, 4).toInt();
        final cw = (w - (cols - 1) * 14) / cols;
        final ready = _models.where((m) => (_possible[m['id'] as int] ?? 0) > 0).length;
        final blocked = _models.length - ready;
        final shown = _q.isEmpty
            ? _models
            : _models
                .where((m) => '${m['name']}'.contains(_q) || '${m['product_name'] ?? ''}'.contains(_q))
                .toList();
        return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
          const _HowItWorks(),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatCard(
                  label: 'الوصفات',
                  value: fmtQty(_models.length),
                  icon: Icons.menu_book_rounded,
                  color: ErpColors.purple,
                  width: 180),
              StatCard(
                  label: 'جاهزة للتصنيع',
                  value: fmtQty(ready),
                  icon: Icons.check_circle_rounded,
                  color: ErpColors.green,
                  width: 180),
              StatCard(
                  label: 'تنقصها مواد',
                  value: fmtQty(blocked),
                  icon: Icons.error_outline_rounded,
                  color: blocked > 0 ? ErpColors.red : ErpColors.muted,
                  width: 180),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: SearchBox(hint: 'بحث في الوصفات', onChanged: (v) => setState(() => _q = v.trim()))),
            const SizedBox(width: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: ErpColors.purple),
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('وصفة جديدة'),
            ),
          ]),
          const SizedBox(height: 14),
          if (shown.isEmpty)
            EmptyState('لا توجد وصفات تطابق «$_q»', icon: Icons.search_off_rounded)
          else
            Wrap(spacing: 14, runSpacing: 14, children: [for (final m in shown) _modelCard(m, cw)]),
        ]);
      });

  Widget _modelCard(Map<String, Object?> m, double width) {
    final id = m['id'] as int;
    final can = _possible[id] ?? 0;
    final ready = can > 0;
    final out = d0(m['output_qty']);
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _iconBox(Icons.precision_manufacturing_rounded, ErpColors.purple),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${m['name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ErpColors.text)),
                const SizedBox(height: 2),
                Text('وصفة رقم ${m['model_no']}', style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
              ]),
            ),
            PopupMenuButton<String>(
              tooltip: 'المزيد',
              icon: const Icon(Icons.more_vert_rounded, color: ErpColors.muted),
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _edit(id);
                  case 'waste':
                    _waste(m);
                  case 'history':
                    _history();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [Icon(Icons.edit_outlined, size: 19), SizedBox(width: 10), Text('تعديل الوصفة')])),
                PopupMenuItem(
                    value: 'waste',
                    child: Row(children: [
                      Icon(Icons.analytics_outlined, size: 19),
                      SizedBox(width: 10),
                      Text('مراقبة الهدر')
                    ])),
                PopupMenuItem(
                    value: 'history',
                    child: Row(children: [
                      Icon(Icons.history_rounded, size: 19),
                      SizedBox(width: 10),
                      Text('سجل عمليات التصنيع')
                    ])),
              ],
            ),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: ErpColors.bg, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.category_outlined, size: 18, color: ErpColors.blue),
              const SizedBox(width: 6),
              Text('${m['n_components']} مادة أولية',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded, size: 16, color: ErpColors.muted),
              ),
              const Icon(Icons.inventory_2_outlined, size: 18, color: ErpColors.purple),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${fmtQty(out)} × ${m['product_name'] ?? '؟'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Icon(ready ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 18, color: ready ? ErpColors.green : ErpColors.red),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                ready ? 'المواد المتوفرة تكفي لتصنيع ${fmtQty(can)}' : 'تنقص مواد أساسية — لا يمكن التصنيع الآن',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: ready ? ErpColors.green : ErpColors.red),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: ErpColors.purple),
                onPressed: () => _produce(id),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('تصنيع'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _edit(id),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('تعديل'),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _waste(Map<String, Object?> m) async {
    List<Map<String, Object?>> rows;
    try {
      rows = await _svc.wasteReport(m['id'] as int);
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => ErpDialog(
        title: 'مراقبة الهدر',
        subtitle: '${m['name']}',
        icon: Icons.analytics_rounded,
        color: ErpColors.orange,
        width: 640,
        content: rows.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('لا توجد عمليات تصنيع بعد لهذه الوصفة.',
                    textAlign: TextAlign.center, style: TextStyle(color: ErpColors.muted)),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                const Text(
                  'المقدّر = حسب الوصفة لكل ما صُنِّع، والفعلي = ما صُرف فعلاً. الفرق الموجب يعني هدراً.',
                  style: TextStyle(fontSize: 12.5, color: ErpColors.muted, height: 1.5),
                ),
                const SizedBox(height: 10),
                SimpleTable(
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
              ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
      ),
    );
  }
}

// ═══════════════════════════ محرر الوصفة ═══════════════════════════

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

  Future<void> _pickProduct() async {
    final p = await Pickers.product(context, title: 'المادة الجاهزة (الناتج)');
    if (p == null || !mounted) return;
    if (_comps.any((c) => c.product.id == p.id)) {
      showError(context, '«${p.name}» موجودة ضمن المواد الأولية — المادة الجاهزة لا تكون من موادها');
      return;
    }
    setState(() {
      _product = p;
      if (_name.text.trim().isEmpty) _name.text = p.name;
    });
  }

  Future<void> _addComp() async {
    final p = await Pickers.product(context, title: 'مادة أولية');
    if (p == null || !mounted) return;
    if (_product?.id == p.id) {
      showError(context, 'هذه هي المادة الجاهزة نفسها — اختر مادة أولية أخرى');
      return;
    }
    if (_comps.any((c) => c.product.id == p.id)) {
      showError(context, '«${p.name}» مضافة مسبقاً');
      return;
    }
    setState(() => _comps.add(_Comp(p, 1, true)));
  }

  Future<void> _save() async {
    if (_product == null) {
      showError(context, 'اختر المادة الجاهزة في الخطوة 1');
      return;
    }
    if (_comps.isEmpty) {
      showError(context, 'أضف مادة أولية واحدة على الأقل في الخطوة 2');
      return;
    }
    if (_comps.any((c) => c.qty <= 0)) {
      showError(context, 'كل كميات المواد الأولية يجب أن تكون أكبر من صفر');
      return;
    }
    setState(() => _saving = true);
    try {
      await _svc.saveModel(
        id: widget.modelId,
        name: _name.text.trim(),
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
      showOk(context, 'حُفظت الوصفة');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      'إيقاف الوصفة',
      'ستختفي هذه الوصفة من القائمة. عمليات التصنيع السابقة تبقى كما هي في السجل.',
      ok: 'إيقاف',
      color: ErpColors.red,
    );
    if (!ok) return;
    try {
      await _svc.deleteModel(widget.modelId!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final out = parseMoney(_outQty.text) ?? 0;
    final unitCost = out <= 0 ? 0.0 : (_rawCost + _expTotal) / out;
    return ErpPage(
      title: widget.modelId == null ? 'وصفة تصنيع جديدة' : 'تعديل وصفة التصنيع',
      subtitle: 'ماذا تصنع، ومن ماذا، وكم تكلّف الوحدة',
      icon: Icons.precision_manufacturing_rounded,
      actions: [
        if (widget.modelId != null)
          IconButton(icon: const Icon(Icons.delete_outline_rounded), tooltip: 'إيقاف الوصفة', onPressed: _delete),
      ],
      bottom: _bottomBarShell(Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('كلفة الوحدة: ${fmtMoney(unitCost)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ErpColors.purple)),
            Text('${fmtQty(_comps.length)} مادة أولية • ${fmtQty(_exps.length)} مصروف',
                style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
          ]),
        ),
        PrimaryButton(
            label: 'حفظ الوصفة', icon: Icons.save_rounded, color: ErpColors.purple, busy: _saving, onPressed: _save),
      ])),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 1050;
        final form = ListView(padding: EdgeInsets.fromLTRB(16, 16, wide ? 8 : 16, 24), children: [
          _step1(),
          const SizedBox(height: 14),
          _step2(out),
          const SizedBox(height: 14),
          _step3(),
          const SizedBox(height: 14),
          _step4(),
          if (!wide) ...[const SizedBox(height: 14), _summary(out, unitCost)],
        ]);
        if (!wide) return form;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: form),
          SizedBox(
            width: 330,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 24),
              child: _summary(out, unitCost),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _step1() {
    final p = _product;
    return _stepCard(
      1,
      'ماذا تصنع؟',
      'المادة الجاهزة التي تدخل المخزن بعد التصنيع، وكم تنتج هذه الوصفة منها',
      ErpColors.purple,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(
          color: p == null ? ErpColors.purple.withValues(alpha: 0.04) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: ErpColors.purple.withValues(alpha: p == null ? 0.35 : 0.5), width: 1.4),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _pickProduct,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                _iconBox(p == null ? Icons.add_box_outlined : Icons.inventory_2_rounded, ErpColors.purple, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p?.name ?? 'اختر المادة الجاهزة',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: p == null ? ErpColors.purple : ErpColors.text)),
                    Text(
                      p == null
                          ? 'اضغط للبحث في المواد'
                          : 'الكلفة الحالية ${fmtMoney(p.cost)} • المتوفر ${fmtQty(p.stock)} ${p.baseUnitName}',
                      style: const TextStyle(fontSize: 12, color: ErpColors.muted),
                    ),
                  ]),
                ),
                Text(p == null ? 'اختيار' : 'تغيير',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: ErpColors.purple)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 12, runSpacing: 12, children: [
          TextBox(controller: _name, label: 'اسم الوصفة', width: 280),
          MoneyField(
            controller: _outQty,
            label: 'الكمية التي تنتجها الوصفة${p == null ? '' : ' (${p.baseUnitName})'}',
            width: 230,
            onChanged: (_) => setState(() {}),
          ),
        ]),
        _hint('مثال: وصفة تنتج 10 قطع — اكتب كميات المواد الأولية في الخطوة 2 لإنتاج هذه الكمية كاملة.'),
      ]),
    );
  }

  Widget _step2(double out) => _stepCard(
        2,
        'من ماذا؟',
        'المواد الأولية وكمياتها لإنتاج ${fmtQty(out)} — النجمة ★ تعني مادة أساسية لا تصنيع بدونها',
        ErpColors.blue,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final c in _comps) _compRow(c),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 46),
              foregroundColor: ErpColors.blue,
              side: BorderSide(color: ErpColors.blue.withValues(alpha: 0.45)),
            ),
            onPressed: _addComp,
            icon: const Icon(Icons.add_rounded),
            label: Text(_comps.isEmpty ? 'أضف أول مادة أولية' : 'إضافة مادة أولية'),
          ),
        ]),
      );

  Widget _compRow(_Comp c) => Container(
        key: ValueKey('c-${c.product.id}-$_rev'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.qty <= 0 ? ErpColors.red.withValues(alpha: 0.5) : ErpColors.border),
        ),
        child: Row(children: [
          IconButton(
            tooltip: c.essential ? 'أساسية — اضغط لجعلها ثانوية' : 'ثانوية — اضغط لجعلها أساسية',
            icon: Icon(c.essential ? Icons.star_rounded : Icons.star_border_rounded,
                color: c.essential ? ErpColors.gold : ErpColors.muted),
            onPressed: () => setState(() => c.essential = !c.essential),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              Text(
                '${c.essential ? 'أساسية' : 'ثانوية'} • كلفة ${fmtMoney(c.product.cost)} / ${c.product.baseUnitName}'
                ' • متوفر ${fmtQty(c.product.stock)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: ErpColors.muted),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: TextFormField(
              initialValue: fmtQty(c.qty),
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
              decoration: InputDecoration(isDense: true, labelText: 'الكمية', suffixText: c.product.baseUnitName),
              onChanged: (v) => setState(() => c.qty = parseMoney(v) ?? 0),
            ),
          ),
          SizedBox(
            width: 104,
            child: Text(fmtMoney(c.qty * c.product.cost),
                textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          IconButton(
            tooltip: 'إزالة',
            icon: const Icon(Icons.close_rounded, color: ErpColors.red, size: 20),
            onPressed: () => setState(() {
              _comps.remove(c);
              _rev++;
            }),
          ),
        ]),
      );

  Widget _step3() => _stepCard(
        3,
        'المصاريف الصناعية (اختياري)',
        'أجور، كهرباء، تغليف… تُضاف على كلفة المادة الجاهزة وتُقيَّد على «مصاريف صناعية محمّلة»',
        ErpColors.orange,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < _exps.length; i++)
            Padding(
              key: ValueKey('e-$i-$_rev'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _exps[i].name,
                    decoration: const InputDecoration(
                        isDense: true, labelText: 'البند', prefixIcon: Icon(Icons.bolt_rounded, size: 19)),
                    onChanged: (v) => _exps[i].name = v,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 160,
                  child: TextFormField(
                    initialValue: _exps[i].amount == 0 ? '' : fmtMoney(_exps[i].amount),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true, labelText: 'المبلغ'),
                    onChanged: (v) => setState(() => _exps[i].amount = parseMoney(v) ?? 0),
                  ),
                ),
                IconButton(
                  tooltip: 'إزالة',
                  icon: const Icon(Icons.close_rounded, color: ErpColors.red, size: 20),
                  onPressed: () => setState(() {
                    _exps.removeAt(i);
                    _rev++;
                  }),
                ),
              ]),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: ErpColors.orange),
              onPressed: () => setState(() {
                _exps.add(_Exp('', 0));
                _rev++;
              }),
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة مصروف'),
            ),
          ),
        ]),
      );

  Widget _step4() => _stepCard(
        4,
        'المخازن والملاحظات (اختياري)',
        'حدّدها إن كان لديك أكثر من مخزن',
        ErpColors.navy,
        Wrap(spacing: 12, runSpacing: 12, children: [
          WarehouseDropdown(
              value: _rawWh,
              width: 260,
              label: 'تُسحب المواد الأولية من',
              onChanged: (w) => setState(() => _rawWh = w?.id)),
          WarehouseDropdown(
              value: _finWh,
              width: 260,
              label: 'تدخل المادة الجاهزة إلى',
              onChanged: (w) => setState(() => _finWh = w?.id)),
          TextBox(controller: _notes, label: 'ملاحظات', width: 300),
        ]),
      );

  Widget _summary(double out, double unitCost) {
    final p = _product;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(accent: ErpColors.purple),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.calculate_rounded, color: ErpColors.purple),
          SizedBox(width: 8),
          Text('ملخص الكلفة', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 12),
        _sumLine('كلفة المواد الأولية', fmtMoney(_rawCost), color: ErpColors.blue),
        _sumLine('المصاريف الصناعية', fmtMoney(_expTotal), color: ErpColors.orange),
        const Divider(height: 20),
        _sumLine('إجمالي كلفة الوصفة', fmtMoney(_rawCost + _expTotal), bold: true),
        _sumLine('÷ الكمية المنتجة', fmtQty(out)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ErpColors.purple.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            const Text('كلفة الوحدة المصنّعة', style: TextStyle(fontSize: 12.5, color: ErpColors.muted)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(fmtMoney(unitCost),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: ErpColors.purple)),
            ),
            if (p != null && p.cost > 0)
              Text('الكلفة الحالية للمادة ${fmtMoney(p.cost)}',
                  style: const TextStyle(fontSize: 11.5, color: ErpColors.muted)),
          ]),
        ),
        const SizedBox(height: 14),
        _check(p != null, 'اختيرت المادة الجاهزة'),
        _check(out > 0, 'كمية الإنتاج أكبر من صفر'),
        _check(_comps.isNotEmpty, 'أُضيفت مواد أولية'),
        _check(_comps.isNotEmpty && _comps.every((c) => c.qty > 0), 'كل كميات المواد أكبر من صفر'),
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
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final db = await erpDb();
      final m = await db.rawQuery(
          'SELECT m.*, p.name AS product_name, p.unit AS product_unit FROM bom_models m '
          'LEFT JOIN products p ON p.id = m.product_id WHERE m.id = ?',
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
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _calc() async {
    final my = ++_seq;
    final q = parseMoney(_qty.text) ?? 0;
    if (q <= 0) {
      setState(() => _req = const []);
      return;
    }
    try {
      final r = await _svc.requirements(widget.modelId, q);
      if (mounted && my == _seq) setState(() => _req = r);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _setQty(double v) {
    _qty.text = v <= 0 ? '' : fmtQty(v);
    setState(() {});
    _calc();
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
          'ستخرج المواد الأولية من المخزن وتدخل المادة الجاهزة بكلفتها، ويُسجَّل القيد تلقائياً.'
          '${short.isNotEmpty ? '\n⚠️ تنقص ${short.length} مادة وستصبح أرصدتها سالبة.' : ''}',
      ok: 'تنفيذ',
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
    if (m == null) {
      return const ErpPage(
        title: 'تصنيع',
        icon: Icons.play_circle_fill_rounded,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final q = parseMoney(_qty.text) ?? 0;
    final raw = _req.fold<double>(0, (s, r) => s + d0(r['need']) * d0(r['cost_price']));
    final exp = _expPerOut * q;
    final unit = q <= 0 ? 0.0 : (raw + exp) / q;
    final short = _req.where((r) => d0(r['shortage']) > 1e-9).toList();
    final blocked = q <= 0 || (short.isNotEmpty && !_allowShortage);
    final productUnit = _unitName(m['product_unit']);

    return ErpPage(
      title: 'تصنيع: ${m['name']}',
      subtitle: 'الناتج: ${m['product_name']}',
      icon: Icons.play_circle_fill_rounded,
      bottom: _bottomBarShell(Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('الإجمالي: ${fmtMoney(raw + exp)}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ErpColors.purple)),
            Text(
              q <= 0
                  ? 'اكتب الكمية المراد تصنيعها'
                  : blocked
                      ? 'تنقص ${fmtQty(short.length)} مادة — فعّل «السماح بالنقص» أو قلّل الكمية'
                      : 'تصنيع ${fmtQty(q)} $productUnit × ${m['product_name']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: blocked && q > 0 ? ErpColors.red : ErpColors.muted),
            ),
          ]),
        ),
        PrimaryButton(
          label: 'تنفيذ التصنيع',
          icon: Icons.play_arrow_rounded,
          color: ErpColors.purple,
          busy: _busy,
          onPressed: blocked ? null : _produce,
        ),
      ])),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 1050;
        final form = ListView(padding: EdgeInsets.fromLTRB(16, 16, wide ? 8 : 16, 24), children: [
          _qtyStep(q, productUnit),
          const SizedBox(height: 14),
          _reqStep(q, short),
          const SizedBox(height: 14),
          _detailsStep(),
          if (!wide) ...[const SizedBox(height: 14), _summary(q, raw, exp, unit, short.length)],
        ]);
        if (!wide) return form;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: form),
          SizedBox(
            width: 330,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 24),
              child: _summary(q, raw, exp, unit, short.length),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _qtyStep(double q, String productUnit) => _stepCard(
        1,
        'كم تريد أن تصنع؟',
        'بوحدة المادة الجاهزة${productUnit.isEmpty ? '' : ' ($productUnit)'}',
        ErpColors.purple,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            IconButton.outlined(
              tooltip: 'إنقاص',
              onPressed: q <= 1 ? null : () => _setQty(q - 1),
              icon: const Icon(Icons.remove_rounded),
            ),
            MoneyField(
              controller: _qty,
              label: 'الكمية',
              width: 170,
              onChanged: (_) {
                setState(() {});
                _calc();
              },
            ),
            IconButton.outlined(
              tooltip: 'زيادة',
              onPressed: () => _setQty(q + 1),
              icon: const Icon(Icons.add_rounded),
            ),
            const SizedBox(width: 6),
            if (_max > 0)
              ActionChip(
                avatar: const Icon(Icons.vertical_align_top_rounded, size: 18, color: ErpColors.purple),
                label: Text('أقصى ممكن: ${fmtQty(_max)}'),
                onPressed: () => _setQty(_max),
              ),
          ]),
          _hint(
            _max > 0
                ? 'المواد الأساسية المتوفرة تكفي لتصنيع ${fmtQty(_max)} كحد أقصى.'
                : 'المواد الأساسية المتوفرة لا تكفي لتصنيع أي كمية الآن.',
            icon: _max > 0 ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
            color: _max > 0 ? ErpColors.green : ErpColors.red,
          ),
        ]),
      );

  Widget _reqStep(double q, List<Map<String, Object?>> short) => _stepCard(
        2,
        'الاحتياجات',
        'ما سيُسحب من المخزن لهذه الكمية — الشريط يوضّح كفاية المتوفر',
        ErpColors.blue,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (q <= 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('اكتب الكمية لرؤية الاحتياجات.', style: TextStyle(color: ErpColors.muted)),
            )
          else ...[
            if (short.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: ErpColors.red.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ErpColors.red.withValues(alpha: 0.25)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: ErpColors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تنقص ${fmtQty(short.length)} مادة. للتصنيع رغم ذلك فعّل «السماح بالنقص» — ستصبح أرصدتها سالبة حتى تُدخلها.',
                      style: const TextStyle(fontSize: 12.5, height: 1.45),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('السماح بالنقص', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  Switch(
                    value: _allowShortage,
                    onChanged: (v) => setState(() => _allowShortage = v),
                  ),
                ]),
              ),
            for (final r in _req) _reqRow(r),
          ],
        ]),
      );

  Widget _reqRow(Map<String, Object?> r) {
    final need = d0(r['need']);
    final avail = d0(r['available']);
    final shortage = d0(r['shortage']);
    final essential = (r['is_essential'] as int? ?? 1) == 1;
    final ok = shortage <= 1e-9;
    final unit = _unitName(r['unit']);
    final ratio = need <= 0 ? 1.0 : (avail / need).clamp(0.0, 1.0).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok ? Colors.white : ErpColors.red.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ok ? ErpColors.border : ErpColors.red.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Tooltip(
            message: essential ? 'مادة أساسية' : 'مادة ثانوية',
            child: Icon(essential ? Icons.star_rounded : Icons.star_border_rounded,
                size: 18, color: essential ? ErpColors.gold : ErpColors.muted),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${r['product_name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          Text('${fmtQty(need)} $unit', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 7,
            color: ok ? ErpColors.green : ErpColors.red,
            backgroundColor: (ok ? ErpColors.green : ErpColors.red).withValues(alpha: 0.12),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text('المتوفر ${fmtQty(avail)}', style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
          const Spacer(),
          Text(
            ok ? 'يبقى ${fmtQty(d0(r['surplus']))}' : 'ناقص ${fmtQty(shortage)}',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ok ? ErpColors.green : ErpColors.red),
          ),
          Text(' • ${fmtMoney(need * d0(r['cost_price']))}',
              style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
        ]),
      ]),
    );
  }

  Widget _detailsStep() => _stepCard(
        3,
        'تفاصيل العملية',
        'التاريخ وحساب المصاريف وملاحظات',
        ErpColors.navy,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DateButton(label: 'التاريخ', value: _date, onChanged: (d) => setState(() => _date = d)),
            OutlinedButton.icon(
              icon: const Icon(Icons.account_tree_outlined, size: 19),
              label: Text(_overheadAcc == null
                  ? 'حساب المصاريف: تلقائي'
                  : '${_overheadAcc!.code} ${_overheadAcc!.name}'),
              onPressed: () async {
                final a = await Pickers.account(context, title: 'حساب المصاريف الصناعية المحمّلة');
                if (mounted) setState(() => _overheadAcc = a);
              },
            ),
            TextBox(controller: _notes, label: 'ملاحظات', width: 280),
          ]),
          _hint('حساب المصاريف: يُقيَّد عليه مبلغ المصاريف الصناعية المحمّلة — اتركه «تلقائي» إن لم تكن متأكداً.'),
        ]),
      );

  Widget _summary(double q, double raw, double exp, double unit, int shortCount) {
    final total = _req.length;
    final okCount = total - shortCount;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(accent: ErpColors.purple),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.calculate_rounded, color: ErpColors.purple),
          SizedBox(width: 8),
          Text('ملخص العملية', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 12),
        if (total > 0)
          Center(
            child: RingGauge(
              value: total == 0 ? 0 : okCount / total,
              label: 'جاهزية المواد',
              center: '${fmtQty(okCount)}/${fmtQty(total)}',
              caption: shortCount == 0 ? 'كل المواد متوفرة' : 'تنقص ${fmtQty(shortCount)}',
              color: shortCount == 0 ? ErpColors.green : ErpColors.red,
              size: 110,
            ),
          ),
        const SizedBox(height: 12),
        _sumLine('كلفة المواد', fmtMoney(raw), color: ErpColors.blue),
        _sumLine('المصاريف المحمّلة', fmtMoney(exp), color: ErpColors.orange),
        const Divider(height: 20),
        _sumLine('الإجمالي', fmtMoney(raw + exp), bold: true),
        _sumLine('÷ الكمية', fmtQty(q)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ErpColors.purple.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            const Text('كلفة الوحدة المصنّعة', style: TextStyle(fontSize: 12.5, color: ErpColors.muted)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(fmtMoney(unit),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: ErpColors.purple)),
            ),
          ]),
        ),
      ]),
    );
  }
}
