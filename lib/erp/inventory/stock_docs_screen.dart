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
  String _preset = 'month'; // month | last | 3m | year | custom
  String _q = '';
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  List<Map<String, Object?>> _all = const [];
  bool _loading = true;

  static const _presets = [
    ('month', 'هذا الشهر'),
    ('last', 'الشهر الماضي'),
    ('3m', 'آخر 3 أشهر'),
    ('year', 'هذه السنة'),
  ];

  @override
  void initState() {
    super.initState();
    _type = widget.docType;
    _load();
  }

  Future<void> _load() async {
    if (!_loading && mounted) setState(() => _loading = true);
    try {
      // نحمّل كل الأنواع للفترة ونفلتر محلياً — لتظهر أعداد كل نوع على شرائح الفلترة.
      final r = await _svc.list(docType: null, from: _from, to: _to);
      if (mounted) setState(() => _all = r);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyPreset(String p) {
    final now = DateTime.now();
    setState(() {
      _preset = p;
      switch (p) {
        case 'month':
          _from = DateTime(now.year, now.month, 1);
          _to = now;
        case 'last':
          _from = DateTime(now.year, now.month - 1, 1);
          _to = DateTime(now.year, now.month, 0);
        case '3m':
          _from = DateTime(now.year, now.month - 2, 1);
          _to = now;
        case 'year':
          _from = DateTime(now.year, 1, 1);
          _to = now;
      }
    });
    _load();
  }

  List<Map<String, Object?>> get _rows {
    final q = _q.trim();
    return _all.where((r) {
      if (_type != null && r['doc_type'] != _type) return false;
      if (q.isEmpty) return true;
      return '${r['doc_no']}'.contains(q) ||
          '${r['reason'] ?? ''}'.contains(q) ||
          '${r['notes'] ?? ''}'.contains(q) ||
          '${r['warehouse_name'] ?? ''}'.contains(q) ||
          '${r['account_name'] ?? ''}'.contains(q);
    }).toList();
  }

  Future<void> _new(String type) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => StockDocEditorScreen(docType: type)));
    if (ok == true && mounted) _load();
  }

  Future<void> _open(Map<String, Object?> r) async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => StockDocViewScreen(docId: r['id'] as int)));
    if (ok == true && mounted) _load();
  }

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    return fmtDate(d);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final posted = rows.where((r) => r['status'] == 'posted');
    final inVal = posted.where((r) => d0(r['total_cost']) > 0).fold<double>(0, (s, r) => s + d0(r['total_cost']));
    final outVal = posted.where((r) => d0(r['total_cost']) < 0).fold<double>(0, (s, r) => s - d0(r['total_cost']));
    final counts = <String, int>{};
    for (final r in _all) {
      counts['${r['doc_type']}'] = (counts['${r['doc_type']}'] ?? 0) + 1;
    }

    // تجميع حسب اليوم
    final items = <Object>[];
    String? lastDay;
    for (final r in rows) {
      final d = parseDate(r['doc_date']);
      final key = isoDay(d);
      if (key != lastDay) {
        items.add(d);
        lastDay = key;
      }
      items.add(r);
    }

    return ErpPage(
      title: 'سجل المستندات المخزنية',
      subtitle: 'كل حركة كمية لها مستند: إدخال • إخراج • أول المدة • تسوية جرد • تصنيع',
      icon: Icons.receipt_long_rounded,
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
                const SizedBox(width: 10),
                Text(stockDocLabels[t]!),
              ]),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: ErpColors.navy,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: ErpColors.navy.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, color: Colors.white),
            SizedBox(width: 6),
            Text('مستند جديد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'قيمة الإدخالات', value: fmtMoney(inVal), icon: Icons.south_west_rounded, color: ErpColors.green),
        StatCard(label: 'قيمة الإخراجات', value: fmtMoney(outVal), icon: Icons.north_east_rounded, color: ErpColors.red),
        StatCard(label: 'عدد المستندات', value: fmtQty(rows.length), icon: Icons.description_outlined, color: ErpColors.blue),
      ]),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: _filters(counts)),
        if (_loading)
          const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
        else if (rows.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              _q.trim().isNotEmpty ? 'لا توجد مستندات تطابق «${_q.trim()}»' : 'لا توجد مستندات في هذه الفترة',
              icon: Icons.receipt_long_outlined,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            sliver: SliverList.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final it = items[i];
                if (it is DateTime) {
                  return Padding(
                    padding: EdgeInsets.fromLTRB(4, i == 0 ? 4 : 14, 4, 8),
                    child: Row(children: [
                      Text(_dayLabel(it),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ErpColors.navy)),
                      const SizedBox(width: 10),
                      const Expanded(child: Divider()),
                    ]),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _docCard(it as Map<String, Object?>),
                );
              },
            ),
          ),
      ]),
    );
  }

  Widget _filters(Map<String, int> counts) => Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ErpColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              label: Text('الكل (${fmtQty(_all.length)})'),
              selected: _type == null,
              onSelected: (_) => setState(() => _type = null),
            ),
            for (final t in stockDocLabels.keys)
              ChoiceChip(
                avatar: Icon(_docIcons[t], size: 18, color: _type == t ? Colors.white : _docColors[t]),
                label: Text('${stockDocLabels[t]} (${fmtQty(counts[t] ?? 0)})'),
                selected: _type == t,
                selectedColor: _docColors[t],
                labelStyle: _type == t ? const TextStyle(color: Colors.white, fontWeight: FontWeight.w700) : null,
                showCheckmark: false,
                onSelected: (_) => setState(() => _type = _type == t ? null : t),
              ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Icon(Icons.date_range_rounded, size: 19, color: ErpColors.muted),
            for (final p in _presets)
              ChoiceChip(
                label: Text(p.$2),
                selected: _preset == p.$1,
                onSelected: (_) => _applyPreset(p.$1),
              ),
            const SizedBox(width: 4),
            DateButton(
                label: 'من',
                value: _from,
                onChanged: (d) {
                  setState(() {
                    _from = d;
                    _preset = 'custom';
                  });
                  _load();
                }),
            DateButton(
                label: 'إلى',
                value: _to,
                onChanged: (d) {
                  setState(() {
                    _to = d;
                    _preset = 'custom';
                  });
                  _load();
                }),
          ]),
          const SizedBox(height: 10),
          SearchBox(
            hint: 'بحث برقم المستند أو السبب أو المخزن أو الحساب',
            onChanged: (v) => setState(() => _q = v),
          ),
        ]),
      );

  Widget _meta(IconData icon, String text) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: ErpColors.muted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
          ),
        ]),
      );

  Widget _docCard(Map<String, Object?> r) {
    final t = '${r['doc_type']}';
    final color = _docColors[t] ?? ErpColors.navy;
    final voided = r['status'] != 'posted';
    final v = d0(r['total_cost']);
    final reason = ((r['reason'] as String?) ?? '').trim();
    final account = ((r['account_name'] as String?) ?? '').trim();
    final amountColor = voided ? ErpColors.muted : (v > 0 ? ErpColors.green : (v < 0 ? ErpColors.red : ErpColors.muted));
    return Material(
      color: voided ? const Color(0xFFFAFBFC) : Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: ErpColors.border),
      ),
      child: InkWell(
        onTap: () => _open(r),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: voided ? 0.06 : 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(_docIcons[t] ?? Icons.description_outlined, color: voided ? ErpColors.muted : color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text('${stockDocLabels[t] ?? t} رقم ${r['doc_no']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: voided ? ErpColors.muted : ErpColors.text,
                            decoration: voided ? TextDecoration.lineThrough : null)),
                  ),
                  if (voided) ...[const SizedBox(width: 8), const StatusBadge('ملغى', color: ErpColors.red)],
                ]),
                const SizedBox(height: 5),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  _meta(Icons.warehouse_outlined, '${r['warehouse_name'] ?? 'المخزن الرئيسي'}'),
                  _meta(Icons.category_outlined, '${r['n_items']} مادة'),
                  if (reason.isNotEmpty) _meta(Icons.notes_rounded, reason),
                  if (account.isNotEmpty) _meta(Icons.account_tree_outlined, account),
                ]),
              ]),
            ),
            const SizedBox(width: 12),
            Text(
              '${v > 0 ? '+' : (v < 0 ? '−' : '')}${fmtMoney(v.abs())}',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: amountColor),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════ محرر مستند ═══════════════════════════

class StockDocEditorScreen extends StatefulWidget {
  const StockDocEditorScreen({super.key, required this.docType, this.warehouseId});
  final String docType;

  /// المخزن المختار مسبقاً (مثلاً عند الفتح من شاشة أرصدة مخزن).
  final int? warehouseId;
  @override
  State<StockDocEditorScreen> createState() => _StockDocEditorScreenState();
}

class _StockDocEditorScreenState extends State<StockDocEditorScreen> {
  final _svc = StockDocsService();
  final _lines = <DocLine>[];
  DateTime _date = DateTime.now();
  late int? _warehouseId = widget.warehouseId;
  Account? _counter;
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  bool _adoptCost = true;
  bool _saving = false;

  bool get _isIn => widget.docType != 'out';

  Future<void> _save() async {
    if (!await PeriodLock.guard(context, _date)) return;
    if (!mounted) return;
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
      '${fmtQty(valid.length)} مادة بقيمة ${fmtMoney(total)}.\n'
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
    final explain = {
      'in': 'لزيادة كمية مواد دون فاتورة شراء: هدية من مورد، فائض، إرجاع داخلي.',
      'out': 'لإنقاص كمية مواد دون فاتورة بيع: تالف، ضيافة، استهلاك داخلي، مفقود.',
      'opening': 'لتسجيل الكميات الموجودة فعلاً عند بدء العمل بالبرنامج، بكلفتها.',
    }[widget.docType];
    final count = _lines.where((l) => l.quantity > 0).length;
    return ErpPage(
      title: stockDocLabels[widget.docType] ?? 'مستند مخزني',
      subtitle: _isIn ? 'إدخال مواد إلى المخزن بكلفتها' : 'إخراج مواد من المخزن بكلفتها',
      icon: _docIcons[widget.docType],
      bottom: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: ErpColors.border)),
          ),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.calculate_outlined, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${fmtQty(count)} مادة • القيمة بالكلفة',
                    style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(fmtMoney(total), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
                ),
              ]),
            ),
            PrimaryButton(label: 'حفظ المستند', icon: Icons.save_rounded, busy: _saving, color: color, onPressed: _save),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 20), children: [
        if (explain != null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                child: Icon(_docIcons[widget.docType] ?? Icons.description_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(explain, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.5)),
                  if (hint != null)
                    Text(hint, style: const TextStyle(fontSize: 12, color: ErpColors.muted, height: 1.5)),
                ]),
              ),
            ]),
          ),
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
                avatar: Icon(_adoptCost ? Icons.check_circle_rounded : Icons.circle_outlined, size: 18, color: color),
                showCheckmark: false,
                label: const Text('اعتماد الكلفة للمواد بلا كلفة'),
                selected: _adoptCost,
                onSelected: (v) => setState(() => _adoptCost = v),
              ),
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
              StatCard(label: 'عدد المواد', value: fmtQty(_items.length), icon: Icons.format_list_numbered, color: ErpColors.blue),
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
