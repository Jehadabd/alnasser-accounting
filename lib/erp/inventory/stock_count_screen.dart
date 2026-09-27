// lib/erp/inventory/stock_count_screen.dart
//
// 📋 الجرد الفعلي (مثل «جرد المواد» في الإداري و«الجرد» في سهل):
//   جلسة = لقطة لكميات النظام ← إدخال المعدود (بحث/باركود) ← اعتماد.
//   الاعتماد يُنشئ «تسوية جرد» بالفرق عن الكمية الحالية لحظة الاعتماد.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../report_export.dart';
import 'stock_docs_screen.dart';
import 'stock_docs_service.dart';

class StockCountsScreen extends StatefulWidget {
  const StockCountsScreen({super.key});
  @override
  State<StockCountsScreen> createState() => _StockCountsScreenState();
}

class _StockCountsScreenState extends State<StockCountsScreen> {
  final _svc = StockDocsService();
  List<Map<String, Object?>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _svc.counts();
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _new() async {
    int? wid;
    int? cat;
    final notes = TextEditingController();
    final db = await erpDb();
    List<Map<String, Object?>> cats = const [];
    try {
      cats = await db.query('categories', orderBy: 'name');
    } catch (_) {}
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(children: [
            Icon(Icons.fact_check_rounded, color: ErpColors.orange),
            SizedBox(width: 8),
            Text('جلسة جرد جديدة'),
          ]),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              WarehouseDropdown(
                  value: wid, width: 360, label: 'المخزن (فارغ = الكمية الكلية)', onChanged: (w) => setS(() => wid = w?.id)),
              const SizedBox(height: 12),
              DropBox<int?>(
                label: 'القسم (اختياري)',
                width: 360,
                value: cat,
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('كل المواد')),
                  for (final c in cats) DropdownMenuItem<int?>(value: c['id'] as int, child: Text('${c['name']}')),
                ],
                onChanged: (v) => setS(() => cat = v),
              ),
              const SizedBox(height: 12),
              TextBox(controller: notes, label: 'ملاحظات', width: 360),
              const SizedBox(height: 10),
              const Text('ستُؤخذ لقطة لكميات النظام الآن. يمكنك البيع أثناء الجرد: الفرق يُحسب عند الاعتماد مقابل الكمية الحالية.',
                  style: TextStyle(color: ErpColors.muted, fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بدء الجرد')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final id = await _svc.createCount(warehouseId: wid, categoryId: cat, notes: notes.text.trim());
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => StockCountEditorScreen(countId: id)));
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drafts = _rows.where((r) => r['status'] == 'draft').length;
    return ErpPage(
      title: 'الجرد الفعلي',
      subtitle: 'جلسات جرد بالباركود مع تسوية تلقائية للفروقات',
      icon: Icons.fact_check_rounded,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        backgroundColor: ErpColors.orange,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('جلسة جديدة', style: TextStyle(color: Colors.white)),
      ),
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'جلسات مفتوحة', value: '$drafts', icon: Icons.pending_actions_rounded, color: ErpColors.orange),
        StatCard(
            label: 'جلسات معتمدة',
            value: '${_rows.length - drafts}',
            icon: Icons.verified_rounded,
            color: ErpColors.green),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const EmptyState('لا توجد جلسات جرد بعد — ابدأ جلسة جديدة', icon: Icons.fact_check_outlined)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    final draft = r['status'] == 'draft';
                    final n = (r['n'] as int?) ?? 0;
                    final counted = (r['counted'] as int?) ?? 0;
                    final pct = n == 0 ? 0.0 : counted / n;
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14), side: const BorderSide(color: ErpColors.border)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          await Navigator.push(context,
                              MaterialPageRoute(builder: (_) => StockCountEditorScreen(countId: r['id'] as int)));
                          _load();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            SizedBox(
                              width: 52,
                              height: 52,
                              child: Stack(alignment: Alignment.center, children: [
                                CircularProgressIndicator(
                                  value: pct,
                                  strokeWidth: 5,
                                  backgroundColor: ErpColors.border,
                                  color: draft ? ErpColors.orange : ErpColors.green,
                                ),
                                Text('${(pct * 100).round()}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ]),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Text('جرد #${r['count_no']}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  const SizedBox(width: 8),
                                  StatusBadge(draft ? 'مفتوحة' : 'معتمدة', color: draft ? ErpColors.orange : ErpColors.green),
                                ]),
                                const SizedBox(height: 4),
                                Text(
                                  '${fmtDate(parseDate(r['count_date']))} • ${r['warehouse_name'] ?? 'الكمية الكلية'} • '
                                  'معدود $counted من $n',
                                  style: const TextStyle(color: ErpColors.muted, fontSize: 12),
                                ),
                              ]),
                            ),
                            const Icon(Icons.chevron_left_rounded, color: ErpColors.muted),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ═══════════════════════════ محرر جلسة الجرد ═══════════════════════════

class StockCountEditorScreen extends StatefulWidget {
  const StockCountEditorScreen({super.key, required this.countId});
  final int countId;
  @override
  State<StockCountEditorScreen> createState() => _StockCountEditorScreenState();
}

class _StockCountEditorScreenState extends State<StockCountEditorScreen> {
  final _svc = StockDocsService();
  Map<String, Object?>? _h;
  List<Map<String, Object?>> _items = const [];
  String _q = '';
  String _view = 'all'; // all | pending | diff
  final _scan = TextEditingController();
  final _scanFocus = FocusNode();
  bool _busy = false;

  bool get _draft => _h?['status'] == 'draft';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scan.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = await erpDb();
    final h = await db.rawQuery(
        'SELECT c.*, w.name AS warehouse_name FROM stock_counts c LEFT JOIN warehouses w ON w.id = c.warehouse_id WHERE c.id = ?',
        [widget.countId]);
    final it = await _svc.countItems(widget.countId);
    if (mounted) {
      setState(() {
        _h = h.isEmpty ? null : h.first;
        _items = it;
      });
    }
  }

  List<Map<String, Object?>> get _visible {
    final t = _q.trim();
    return _items.where((r) {
      if (t.isNotEmpty && !('${r['product_name']}'.contains(t) || '${r['barcode'] ?? ''}' == t)) return false;
      if (_view == 'pending') return r['counted_qty'] == null;
      if (_view == 'diff') {
        return r['counted_qty'] != null && (d0(r['counted_qty']) - d0(r['system_qty'])).abs() > 1e-9;
      }
      return true;
    }).toList();
  }

  Future<void> _edit(Map<String, Object?> r, {double add = 0}) async {
    if (!_draft) return;
    double? v;
    if (add != 0) {
      v = (r['counted_qty'] == null ? 0 : d0(r['counted_qty'])) + add;
    } else {
      v = await askNumber(context, 'الكمية المعدودة — ${r['product_name']}',
          initial: r['counted_qty'] == null ? null : d0(r['counted_qty']));
      if (v == null) return;
    }
    if (v < 0) {
      if (mounted) showError(context, 'الكمية لا تكون سالبة');
      return;
    }
    await _svc.setCounted(r['id'] as int, v);
    await _load();
  }

  Future<void> _onScan(String code) async {
    final c = code.trim();
    _scan.clear();
    _scanFocus.requestFocus();
    if (c.isEmpty) return;
    Map<String, Object?>? hit;
    for (final r in _items) {
      if ('${r['barcode'] ?? ''}' == c) {
        hit = r;
        break;
      }
    }
    if (hit == null) {
      final db = await erpDb();
      final extra = await db.query('product_barcodes', columns: ['product_id'], where: 'barcode = ?', whereArgs: [c], limit: 1);
      if (extra.isNotEmpty) {
        for (final r in _items) {
          if (r['product_id'] == extra.first['product_id']) {
            hit = r;
            break;
          }
        }
      }
    }
    if (hit == null) {
      if (mounted) showError(context, 'الباركود $c غير موجود في هذه الجلسة');
      return;
    }
    await _edit(hit, add: 1);
    if (mounted) showOk(context, '${hit['product_name']} +1');
  }

  Future<void> _approve() async {
    final n = _items.where((r) => r['counted_qty'] != null).length;
    if (n == 0) {
      showError(context, 'لم تُدخل أي كمية معدودة');
      return;
    }
    if (!await PeriodLock.guard(context, DateTime.now())) return;
    if (!mounted) return;
    final ok = await confirmDialog(
      context,
      'اعتماد الجرد',
      'سيُسجَّل مستند «تسوية جرد» بفروقات $n مادة معدودة (مقابل الكمية الحالية لحظة الاعتماد).\n'
          'المواد غير المعدودة لا تتغير. متابعة؟',
      color: ErpColors.green,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final docId = await _svc.approveCount(widget.countId);
      await _load();
      if (!mounted) return;
      if (docId == null) {
        showOk(context, 'اعتُمد الجرد — لا توجد فروقات');
      } else {
        showOk(context, 'اعتُمد الجرد وسُجِّلت التسوية');
        Navigator.push(context, MaterialPageRoute(builder: (_) => StockDocViewScreen(docId: docId)));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, 'حذف الجلسة', 'حذف جلسة الجرد المفتوحة وكل ما عُدَّ فيها؟',
        color: ErpColors.red);
    if (!ok) return;
    try {
      await _svc.deleteCount(widget.countId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _fillSystem() async {
    final ok = await confirmDialog(context, 'تعبئة غير المعدود',
        'تعبئة المواد غير المعدودة بكمية النظام (أي بلا فرق)؟ مفيد عند جرد جزء من المواد فقط.');
    if (!ok) return;
    for (final r in _items.where((r) => r['counted_qty'] == null)) {
      await _svc.setCounted(r['id'] as int, d0(r['system_qty']));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final h = _h;
    if (h == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final counted = _items.where((r) => r['counted_qty'] != null).toList();
    var plus = 0.0, minus = 0.0;
    for (final r in counted) {
      final d = (d0(r['counted_qty']) - d0(r['system_qty'])) * d0(r['unit_cost']);
      if (d > 0) plus += d;
      if (d < 0) minus -= d;
    }
    final vis = _visible;
    return ErpPage(
      title: 'جرد #${h['count_no']}',
      subtitle: '${h['warehouse_name'] ?? 'الكمية الكلية'} • ${fmtDate(parseDate(h['count_date']))}',
      icon: Icons.fact_check_rounded,
      actions: [
        ...exportActions(context,
            title: 'جرد رقم ${h['count_no']}',
            headers: () => ['المادة', 'الباركود', 'النظام', 'المعدود', 'الفرق', 'قيمة الفرق'],
            rows: () => [
                  for (final r in _items)
                    [
                      '${r['product_name']}',
                      '${r['barcode'] ?? ''}',
                      fmtQty(d0(r['system_qty'])),
                      r['counted_qty'] == null ? '' : fmtQty(d0(r['counted_qty'])),
                      r['counted_qty'] == null ? '' : fmtQty(d0(r['counted_qty']) - d0(r['system_qty'])),
                      r['counted_qty'] == null
                          ? ''
                          : fmtMoney((d0(r['counted_qty']) - d0(r['system_qty'])) * d0(r['unit_cost'])),
                    ],
                ]),
        if (_draft)
          IconButton(
              tooltip: 'حذف الجلسة',
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: _delete),
      ],
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(
            label: 'المعدود', value: '${counted.length} / ${_items.length}', icon: Icons.checklist_rounded, color: ErpColors.blue),
        StatCard(label: 'فائض (تقديري)', value: fmtMoney(plus), icon: Icons.trending_up_rounded, color: ErpColors.green),
        StatCard(label: 'عجز (تقديري)', value: fmtMoney(minus), icon: Icons.trending_down_rounded, color: ErpColors.red),
      ]),
      bottom: _draft
          ? SafeArea(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  OutlinedButton.icon(
                      onPressed: _fillSystem,
                      icon: const Icon(Icons.auto_fix_high_rounded),
                      label: const Text('تعبئة غير المعدود بكمية النظام')),
                  const Spacer(),
                  PrimaryButton(
                      label: 'اعتماد الجرد',
                      icon: Icons.verified_rounded,
                      color: ErpColors.green,
                      busy: _busy,
                      onPressed: _approve),
                ]),
              ),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (_draft)
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _scan,
                  focusNode: _scanFocus,
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
                    labelText: 'امسح الباركود (+1)',
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onSubmitted: _onScan,
                ),
              ),
            SizedBox(width: 260, child: SearchBox(hint: 'بحث بالاسم', onChanged: (v) => setState(() => _q = v))),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('الكل')),
                ButtonSegment(value: 'pending', label: Text('غير معدود')),
                ButtonSegment(value: 'diff', label: Text('فيه فرق')),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ]),
        ),
        Expanded(
          child: vis.isEmpty
              ? const EmptyState('لا توجد مواد في هذا العرض')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: vis.length,
                  itemBuilder: (_, i) {
                    final r = vis[i];
                    final c = r['counted_qty'];
                    final diff = c == null ? null : d0(c) - d0(r['system_qty']);
                    final color = diff == null
                        ? ErpColors.muted
                        : diff.abs() < 1e-9
                            ? ErpColors.green
                            : (diff > 0 ? ErpColors.blue : ErpColors.red);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border(right: BorderSide(color: color, width: 4)),
                      ),
                      child: ListTile(
                        onTap: _draft ? () => _edit(r) : null,
                        title: Text('${r['product_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('النظام: ${fmtQty(d0(r['system_qty']))}'
                            '${(r['barcode'] as String?)?.isNotEmpty == true ? ' • ${r['barcode']}' : ''}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (diff != null && diff.abs() > 1e-9)
                            StatusBadge('${diff > 0 ? '+' : ''}${fmtQty(diff)}', color: color),
                          const SizedBox(width: 10),
                          Container(
                            width: 84,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: color.withOpacity(.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(c == null ? '—' : fmtQty(d0(c)),
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
                          ),
                          if (_draft) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: '+1',
                              icon: const Icon(Icons.add_circle_outline_rounded),
                              onPressed: () => _edit(r, add: 1),
                            ),
                          ],
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
