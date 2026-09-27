// lib/erp/inventory/stock_docs_screen.dart
//
// 📦 سندات الإدخال والإخراج وبضاعة أول المدة — سجل + محرر.
// الحفظ عبر StockDocsService.create (حركات StockLedger + قيد مشتق تلقائياً).

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart';
import '../../accounting/screens/acc_ui.dart';
import '../doc_lines.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../report_export.dart';
import 'stock_docs_service.dart';

const Map<String, IconData> _docIcons = {
  'in': Icons.move_to_inbox_rounded,
  'out': Icons.outbox_rounded,
  'opening': Icons.inventory_rounded,
  'count': Icons.fact_check_rounded,
  'production': Icons.precision_manufacturing_rounded,
};

const Map<String, Color> _docColors = {
  'in': ErpColors.green,
  'out': ErpColors.red,
  'opening': ErpColors.blue,
  'count': ErpColors.orange,
  'production': ErpColors.purple,
};

class StockDocsListScreen extends StatefulWidget {
  const StockDocsListScreen({super.key, this.docType});
  final String? docType;
  @override
  State<StockDocsListScreen> createState() => _StockDocsListScreenState();
}

class _StockDocsListScreenState extends State<StockDocsListScreen> {
  final _svc = StockDocsService();
  String? _type;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  List<Map<String, Object?>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _type = widget.docType;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _svc.list(docType: _type, from: _from, to: _to);
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _new(String type) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => StockDocEditorScreen(docType: type)));
    if (ok == true) _load();
  }

  Future<void> _open(Map<String, Object?> r) async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => StockDocViewScreen(docId: r['id'] as int)));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final posted = _rows.where((r) => r['status'] == 'posted');
    final inVal = posted.where((r) => d0(r['total_cost']) > 0).fold<double>(0, (s, r) => s + d0(r['total_cost']));
    final outVal = posted.where((r) => d0(r['total_cost']) < 0).fold<double>(0, (s, r) => s - d0(r['total_cost']));
    return ErpPage(
      title: 'المستندات المخزنية',
      subtitle: 'إدخال • إخراج • بضاعة أول المدة • تسويات الجرد • التصنيع',
      icon: Icons.inventory_2_rounded,
      actions: [
        ...exportActions(
          context,
          title: 'المستندات المخزنية',
          headers: () => ['النوع', 'الرقم', 'التاريخ', 'المخزن', 'الحساب المقابل', 'عدد المواد', 'القيمة', 'الحالة'],
          rows: () => [
            for (final r in _rows)
              [
                stockDocLabels[r['doc_type']] ?? '${r['doc_type']}',
                '${r['doc_no']}',
                fmtDate(parseDate(r['doc_date'])),
                '${r['warehouse_name'] ?? 'الرئيسي'}',
                '${r['account_name'] ?? 'تلقائي'}',
                '${r['n_items']}',
                fmtMoney(d0(r['total_cost'])),
                r['status'] == 'posted' ? 'مرحّل' : 'ملغى',
              ],
          ],
        ),
      ],
      floatingActionButton: PopupMenuButton<String>(
        tooltip: 'مستند جديد',
        onSelected: _new,
        itemBuilder: (_) => [
          for (final t in ['in', 'out', 'opening'])
            PopupMenuItem(
              value: t,
              child: Row(children: [
                Icon(_docIcons[t], color: _docColors[t]),
                const SizedBox(width: 8),
                Text(stockDocLabels[t]!),
              ]),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [ErpColors.navy, ErpColors.blue]),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: ErpColors.navy.withOpacity(.3), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, color: Colors.white),
            SizedBox(width: 6),
            Text('مستند جديد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'قيمة الإدخالات', value: fmtMoney(inVal), icon: Icons.south_west_rounded, color: ErpColors.green),
        StatCard(label: 'قيمة الإخراجات', value: fmtMoney(outVal), icon: Icons.north_east_rounded, color: ErpColors.red),
        StatCard(label: 'عدد المستندات', value: '${_rows.length}', icon: Icons.description_outlined, color: ErpColors.blue),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ChoiceChip(label: const Text('الكل'), selected: _type == null, onSelected: (_) {
              _type = null;
              _load();
            }),
            for (final t in stockDocLabels.keys)
              ChoiceChip(
                avatar: Icon(_docIcons[t], size: 18, color: _docColors[t]),
                label: Text(stockDocLabels[t]!),
                selected: _type == t,
                onSelected: (_) {
                  _type = t;
                  _load();
                },
              ),
            const SizedBox(width: 12),
            DateButton(label: 'من', value: _from, onChanged: (d) {
              _from = d;
              _load();
            }),
            DateButton(label: 'إلى', value: _to, onChanged: (d) {
              _to = d;
              _load();
            }),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? const EmptyState('لا توجد مستندات في هذه الفترة', icon: Icons.inventory_2_outlined)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _docCard(_rows[i]),
                    ),
        ),
      ]),
    );
  }

  Widget _docCard(Map<String, Object?> r) {
    final t = '${r['doc_type']}';
    final color = _docColors[t] ?? ErpColors.navy;
    final voided = r['status'] != 'posted';
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(r),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(.25)),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color.withOpacity(.12),
              child: Icon(_docIcons[t] ?? Icons.description, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('${stockDocLabels[t] ?? t} #${r['doc_no']}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          decoration: voided ? TextDecoration.lineThrough : null)),
                  const SizedBox(width: 8),
                  if (voided) const StatusBadge('ملغى', color: ErpColors.red),
                ]),
                const SizedBox(height: 3),
                Text(
                  '${fmtDate(parseDate(r['doc_date']))} • ${r['warehouse_name'] ?? 'المخزن الرئيسي'} • ${r['n_items']} مادة'
                  '${(r['reason'] as String?)?.isNotEmpty == true ? ' • ${r['reason']}' : ''}',
                  style: const TextStyle(color: ErpColors.muted, fontSize: 12),
                ),
              ]),
            ),
            Text(fmtMoney(d0(r['total_cost']).abs()),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: voided ? ErpColors.muted : color)),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════ محرر مستند ═══════════════════════════

class StockDocEditorScreen extends StatefulWidget {
  const StockDocEditorScreen({super.key, required this.docType});
  final String docType;
  @override
  State<StockDocEditorScreen> createState() => _StockDocEditorScreenState();
}

class _StockDocEditorScreenState extends State<StockDocEditorScreen> {
  final _svc = StockDocsService();
  final _lines = <DocLine>[];
  DateTime _date = DateTime.now();
  int? _warehouseId;
  Account? _counter;
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  bool _adoptCost = true;
  bool _saving = false;

  bool get _isIn => widget.docType != 'out';

  Future<void> _save() async {
    if (!await PeriodLock.guard(context, _date)) return;
    final valid = _lines.where((l) => l.quantity > 0).toList();
    if (valid.isEmpty) {
      showError(context, 'أضف مادة واحدة على الأقل بكمية أكبر من صفر');
      return;
    }
    if (valid.any((l) => l.product.isService)) {
      showError(context, 'مواد الخدمة لا تُخزَّن — احذفها من المستند');
      return;
    }
    final total = linesTotal(valid);
    final ok = await confirmDialog(
      context,
      'حفظ ${stockDocLabels[widget.docType]}',
      '${valid.length} مادة بقيمة ${fmtMoney(total)}.\n'
          'سيُحدَّث المخزون ويُنشأ القيد المحاسبي تلقائياً. هل تريد المتابعة؟',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      final id = await _svc.create(
        docType: widget.docType,
        date: _date,
        warehouseId: _warehouseId,
        counterAccountId: _counter?.id,
        reason: _reason.text.trim(),
        notes: _notes.text.trim(),
        lines: [
          for (final l in valid)
            StockDocLine(
              productId: l.product.id,
              name: l.product.name,
              baseQty: _isIn ? l.baseQty : -l.baseQty,
              unitCost: l.unit.factor <= 0 ? 0 : l.netPrice / l.unit.factor,
              note: l.note,
            ),
        ],
      );
      if (_isIn && _adoptCost) {
        for (final l in valid) {
          await _svc.adoptCostIfMissing(l.product.id, l.unit.factor <= 0 ? 0 : l.netPrice / l.unit.factor);
        }
      }
      if (!mounted) return;
      showOk(context, 'حُفظ المستند (#$id)');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _docColors[widget.docType] ?? ErpColors.navy;
    final total = linesTotal(_lines);
    final hint = {
      'in': 'الحساب المقابل الافتراضي: فروقات المخزون (مثل هدية مورد أو فائض).',
      'out': 'الحساب المقابل الافتراضي: تالف ومفقودات المخزون (أو اختر مصروف ضيافة/هدايا...).',
      'opening': 'الحساب المقابل الافتراضي: الأرصدة الافتتاحية (رأس المال).',
    }[widget.docType];
    return ErpPage(
      title: stockDocLabels[widget.docType] ?? 'مستند مخزني',
      subtitle: _isIn ? 'إدخال مواد إلى المخزن بكلفتها' : 'إخراج مواد من المخزن بكلفتها',
      icon: _docIcons[widget.docType],
      bottom: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(Icons.calculate_outlined, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text('القيمة بالكلفة: ${fmtMoney(total)}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            ),
            PrimaryButton(label: 'حفظ المستند', icon: Icons.save_rounded, busy: _saving, color: color, onPressed: _save),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 20), children: [
        ErpSection(
          title: 'بيانات المستند',
          icon: Icons.description_outlined,
          color: color,
          child: FieldGrid(children: [
            DateButton(label: 'التاريخ', value: _date, onChanged: (d) => setState(() => _date = d)),
            WarehouseDropdown(value: _warehouseId, onChanged: (w) => setState(() => _warehouseId = w?.id)),
            OutlinedButton.icon(
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(_counter == null ? 'الحساب المقابل: تلقائي' : 'المقابل: ${_counter!.code} ${_counter!.name}'),
              onPressed: () async {
                final a = await Pickers.account(context, title: 'الحساب المقابل للمستند');
                setState(() => _counter = a);
              },
            ),
            if (_counter != null)
              IconButton(
                tooltip: 'العودة للتلقائي',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _counter = null),
              ),
            TextBox(controller: _reason, label: 'البيان / السبب', width: 280),
            TextBox(controller: _notes, label: 'ملاحظات', width: 280),
            if (_isIn)
              FilterChip(
                label: const Text('اعتماد الكلفة للمواد بلا كلفة'),
                selected: _adoptCost,
                onSelected: (v) => setState(() => _adoptCost = v),
              ),
          ]),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 16, color: ErpColors.muted),
              const SizedBox(width: 6),
              Expanded(child: Text(hint, style: const TextStyle(color: ErpColors.muted, fontSize: 12))),
            ]),
          ),
        ErpSection(
          title: 'المواد',
          icon: Icons.list_alt_rounded,
          color: color,
          child: DocLinesEditor(
            lines: _lines,
            priceSource: PriceSource.cost,
            priceLabel: 'الكلفة',
            onChanged: () => setState(() {}),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════ عرض مستند ═══════════════════════════

class StockDocViewScreen extends StatefulWidget {
  const StockDocViewScreen({super.key, required this.docId});
  final int docId;
  @override
  State<StockDocViewScreen> createState() => _StockDocViewScreenState();
}

class _StockDocViewScreenState extends State<StockDocViewScreen> {
  final _svc = StockDocsService();
  Map<String, Object?>? _h;
  List<Map<String, Object?>> _items = const [];
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await erpDb();
    final h = await db.rawQuery('''
      SELECT d.*, w.name AS warehouse_name, a.name AS account_name FROM stock_docs d
      LEFT JOIN warehouses w ON w.id = d.warehouse_id LEFT JOIN accounts a ON a.id = d.counter_account_id
      WHERE d.id = ?''', [widget.docId]);
    final it = await _svc.items(widget.docId);
    if (mounted) {
      setState(() {
        _h = h.isEmpty ? null : h.first;
        _items = it;
      });
    }
  }

  Future<void> _void() async {
    final h = _h;
    if (h == null) return;
    if (!await PeriodLock.guard(context, parseDate(h['doc_date']))) return;
    if (!mounted) return;
    final reason = await askText(context, 'سبب الإلغاء', label: 'اكتب سبب إلغاء المستند');
    if (reason == null || !mounted) return;
    final ok = await confirmDialog(context, 'إلغاء المستند',
        'ستُعكس كل حركات المخزون ويُحذف القيد. لا يمكن التراجع. متابعة؟',
        color: ErpColors.red);
    if (!ok) return;
    try {
      await _svc.voidDoc(widget.docId, reason: reason);
      _changed = true;
      await _load();
      if (mounted) showOk(context, 'أُلغي المستند');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = _h;
    if (h == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final t = '${h['doc_type']}';
    final color = _docColors[t] ?? ErpColors.navy;
    final posted = h['status'] == 'posted';
    final headers = ['المادة', 'المخزن', 'الكمية', 'كلفة الوحدة', 'الإجمالي'];
    List<List<String>> rows() => [
          for (final i in _items)
            [
              '${i['product_name']}',
              '${i['warehouse_name'] ?? 'الرئيسي'}',
              fmtQty(d0(i['base_qty'])),
              fmtMoney(d0(i['unit_cost'])),
              fmtMoney(d0(i['total_cost'])),
            ],
        ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (!did) Navigator.pop(context, _changed);
      },
      child: ErpPage(
        title: '${stockDocLabels[t] ?? t} #${h['doc_no']}',
        subtitle: fmtDate(parseDate(h['doc_date'])),
        icon: _docIcons[t],
        actions: [
          ...exportActions(context,
              title: '${stockDocLabels[t]} ${h['doc_no']}',
              headers: () => headers,
              rows: rows,
              footer: () => ['الإجمالي', '', '', '', fmtMoney(d0(h['total_cost']).abs())]),
          if (posted && t != 'count' && t != 'production')
            IconButton(
              tooltip: 'إلغاء المستند',
              icon: const Icon(Icons.block, color: Colors.white),
              onPressed: _void,
            ),
        ],
        body: ListView(padding: const EdgeInsets.only(bottom: 20), children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              StatCard(label: 'القيمة', value: fmtMoney(d0(h['total_cost']).abs()), icon: Icons.payments_outlined, color: color),
              StatCard(label: 'عدد المواد', value: '${_items.length}', icon: Icons.format_list_numbered, color: ErpColors.blue),
              StatCard(
                  label: 'الحالة',
                  value: posted ? 'مرحّل' : 'ملغى',
                  icon: posted ? Icons.verified_outlined : Icons.block,
                  color: posted ? ErpColors.green : ErpColors.red),
            ]),
          ),
          ErpSection(
            title: 'التفاصيل',
            icon: Icons.info_outline,
            color: color,
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              InfoTile('المخزن', '${h['warehouse_name'] ?? 'الرئيسي'}'),
              InfoTile('الحساب المقابل', '${h['account_name'] ?? 'تلقائي'}'),
              InfoTile('البيان', '${h['reason'] ?? '-'}', width: 260),
              InfoTile('ملاحظات', '${h['notes'] ?? '-'}', width: 260),
              InfoTile('بواسطة', '${h['created_by'] ?? ''}'),
            ]),
          ),
          ErpSection(
            title: 'المواد',
            icon: Icons.list_alt_rounded,
            color: color,
            child: SimpleTable(
              headers: headers,
              rows: rows(),
              numericColumns: const {2, 3, 4},
              footer: ['الإجمالي', '', '', '', fmtMoney(d0(h['total_cost']).abs())],
            ),
          ),
          if (posted && (t == 'count' || t == 'production'))
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('مستندات الجرد والتصنيع تُلغى من شاشاتها (أو من هنا عند الحاجة عبر مدير النظام).',
                  style: TextStyle(color: ErpColors.muted)),
            ),
        ]),
      ),
    );
  }
}
