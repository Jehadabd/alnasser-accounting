// lib/erp/inventory/price_tools_screen.dart
//
// 💲 تعديل الأسعار الجماعي (مثل «تعديل قائمة المواد» في الإداري):
//   اختيار المواد (قسم/بحث) ← سعر منطلق ← أسعار هدف ← طريقة (نسبة/مبلغ/توحيد/مسح)
//   ← تقريب ← معاينة الفروقات ← تنفيذ كدفعة قابلة للتراجع. + سجل الدفعات.
// كل تغيير عبر PriceTools (DatabaseService.updateProduct — يزامن ولا يلمس الكمية).

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../stock_helpers.dart';
import 'barcode_labels.dart';
import 'price_tools.dart';

class PriceToolsScreen extends StatefulWidget {
  const PriceToolsScreen({super.key});
  @override
  State<PriceToolsScreen> createState() => _PriceToolsScreenState();
}

class _PriceToolsScreenState extends State<PriceToolsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _tools = PriceTools();

  // اختيار المواد
  List<Map<String, Object?>> _cats = const [];
  int? _categoryId;
  String _q = '';
  List<ProductLite> _products = const [];
  final Set<int> _selected = {};

  // المعاملات
  int _source = 0;
  final Set<int> _targets = {1};
  String _method = 'percent';
  bool _increase = true;
  final _value = TextEditingController(text: '10');
  double _rounding = 0;
  bool _onlyZero = false;

  List<PriceChange> _preview = const [];
  bool _busy = false;
  List<Map<String, Object?>> _batches = const [];

  bool get _canEdit =>
      AuthService().hasPermission(AppPermissions.editProducts) && AuthService().hasPermission(AppPermissions.priceTools);

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final db = await erpDb();
    try {
      _cats = await db.query('categories', orderBy: 'name');
    } catch (_) {}
    await _loadProducts();
    await _loadBatches();
  }

  Future<void> _loadProducts() async {
    final db = await erpDb();
    final where = <String>[];
    final args = <Object?>[];
    if (_categoryId != null) {
      where.add('p.category_id = ?');
      args.add(_categoryId);
    }
    final t = _q.trim();
    if (t.isNotEmpty) {
      where.add('(p.name LIKE ? OR p.barcode = ? OR d.item_code = ?)');
      args.addAll(['%$t%', t, t]);
    }
    final r = await ErpStock.all(db, where: where.isEmpty ? null : where.join(' AND '), args: args.isEmpty ? null : args);
    if (mounted) {
      setState(() {
        _products = r;
        _preview = const [];
      });
    }
  }

  Future<void> _loadBatches() async {
    final b = await _tools.batches();
    if (mounted) setState(() => _batches = b);
  }

  List<int> get _ids => _selected.isEmpty ? [for (final p in _products) p.id] : _selected.toList();

  Future<void> _doPreview() async {
    final v = parseMoney(_value.text) ?? 0;
    if (_targets.isEmpty) {
      showError(context, 'اختر سعراً هدفاً واحداً على الأقل');
      return;
    }
    if ((_method == 'percent' || _method == 'amount') && v <= 0) {
      showError(context, 'اكتب قيمة أكبر من صفر');
      return;
    }
    if (_method == 'percent' && !_increase && v >= 100) {
      showError(context, 'نسبة التخفيض يجب أن تكون أقل من 100%');
      return;
    }
    if (_targets.contains(_source) && _method != 'set' && _method != 'clear') {
      // مسموح: مثلاً رفع المفرد 10% من نفسه
    }
    setState(() => _busy = true);
    try {
      final p = await _tools.preview(
        productIds: _ids,
        source: _source,
        targets: _targets.toList()..sort(),
        method: _method,
        increase: _increase,
        value: v,
        rounding: _rounding,
        onlyZero: _onlyZero,
      );
      if (mounted) setState(() => _preview = p);
      if (p.isEmpty && mounted) showOk(context, 'لا توجد أسعار ستتغير بهذه المعاملات');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    if (!_canEdit) {
      showError(context, 'لا تملك صلاحية تعديل الأسعار');
      return;
    }
    if (_preview.isEmpty) return;
    final products = _preview.map((c) => c.productId).toSet().length;
    final ok = await confirmDialog(
      context,
      'تنفيذ تعديل الأسعار',
      'سيتغير ${_preview.length} سعراً لـ $products مادة، وتُزامَن المواد مع الفروع.\n'
          'يمكنك التراجع عن الدفعة كاملة من «سجل الدفعات».',
      color: ErpColors.green,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final batch = await _tools.apply(_preview);
      if (!mounted) return;
      showOk(context, 'نُفِّذ التعديل (دفعة #$batch)');
      await _loadProducts();
      await _loadBatches();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo(int batch) async {
    if (!_canEdit) {
      showError(context, 'لا تملك صلاحية تعديل الأسعار');
      return;
    }
    final ok = await confirmDialog(context, 'التراجع عن الدفعة #$batch',
        'تعود كل الأسعار في هذه الدفعة إلى قيمها السابقة (يُسجَّل التراجع كدفعة جديدة). متابعة؟',
        color: ErpColors.orange);
    if (!ok) return;
    try {
      final n = await _tools.undoBatch(batch);
      if (mounted) showOk(context, 'أُعيد $n سعراً');
      await _loadProducts();
      await _loadBatches();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _refreshMarkups() async {
    if (!_canEdit) {
      showError(context, 'لا تملك صلاحية تعديل الأسعار');
      return;
    }
    final ok = await confirmDialog(context, 'تحديث الأسعار المحسوبة بالنسبة',
        'إعادة حساب أسعار كل المواد المسعّرة «كنسبة ربح على الكلفة» من كلفتها الحالية؟');
    if (!ok) return;
    try {
      final n = await _tools.refreshAllMarkups();
      if (mounted) showOk(context, 'تحدّث $n سعراً');
      await _loadProducts();
      await _loadBatches();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'أدوات الأسعار',
      subtitle: 'تعديل جماعي بمعاينة وتراجع • قوائم أسعار • ملصقات',
      icon: Icons.price_change_rounded,
      actions: [
        IconButton(
          tooltip: 'تحديث أسعار النِّسب من الكلفة',
          icon: const Icon(Icons.autorenew_rounded, color: Colors.white),
          onPressed: _refreshMarkups,
        ),
        IconButton(
          tooltip: 'قائمة أسعار PDF',
          icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
          onPressed: () => BarcodeLabels.priceList(context, _ids, _targets.isEmpty ? [1] : (_targets.toList()..sort())),
        ),
        IconButton(
          tooltip: 'ملصقات باركود للمحدد',
          icon: const Icon(Icons.qr_code_2_rounded, color: Colors.white),
          onPressed: () => BarcodeLabels.printForProducts(context, _ids),
        ),
      ],
      headerExtra: TabBar(
        controller: _tabs,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        tabs: const [
          Tab(icon: Icon(Icons.tune_rounded), text: 'تعديل جماعي'),
          Tab(icon: Icon(Icons.history_rounded), text: 'سجل الدفعات'),
        ],
      ),
      body: TabBarView(controller: _tabs, children: [_editor(), _history()]),
    );
  }

  Widget _editor() {
    final wide = MediaQuery.of(context).size.width > 1000;
    final params = _paramsPanel();
    final list = _productsPanel();
    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 440, child: ListView(children: [params])),
        Expanded(child: list),
      ]);
    }
    return ListView(children: [params, SizedBox(height: 520, child: list)]);
  }

  Widget _paramsPanel() {
    final levels = [for (var i = 0; i < 6; i++) i + 1];
    return Column(children: [
      ErpSection(
        title: 'المواد',
        icon: Icons.inventory_2_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropBox<int?>(
            label: 'القسم',
            width: 400,
            value: _categoryId,
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('كل الأقسام')),
              for (final c in _cats) DropdownMenuItem<int?>(value: c['id'] as int, child: Text('${c['name']}')),
            ],
            onChanged: (v) {
              _categoryId = v;
              _selected.clear();
              _loadProducts();
            },
          ),
          const SizedBox(height: 10),
          SearchBox(
            hint: 'تصفية بالاسم/الباركود/الرمز',
            onChanged: (v) {
              _q = v;
              _loadProducts();
            },
          ),
          const SizedBox(height: 8),
          Text(
            _selected.isEmpty
                ? 'سيُطبَّق على كل المواد المعروضة (${_products.length})'
                : 'سيُطبَّق على ${_selected.length} مادة محددة',
            style: const TextStyle(color: ErpColors.muted),
          ),
        ]),
      ),
      ErpSection(
        title: 'طريقة التعديل',
        icon: Icons.functions_rounded,
        color: ErpColors.purple,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('السعر المنطلق', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ChoiceChip(label: const Text('الكلفة'), selected: _source == 0, onSelected: (_) => setState(() => _source = 0)),
            for (final l in levels)
              ChoiceChip(
                  label: Text(priceFieldNames[l - 1]),
                  selected: _source == l,
                  onSelected: (_) => setState(() => _source = l)),
          ]),
          const SizedBox(height: 12),
          const Text('الأسعار الهدف', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final l in levels)
              FilterChip(
                label: Text(priceFieldNames[l - 1]),
                selected: _targets.contains(l),
                onSelected: (v) => setState(() => v ? _targets.add(l) : _targets.remove(l)),
              ),
          ]),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'percent', label: Text('نسبة %'), icon: Icon(Icons.percent)),
              ButtonSegment(value: 'amount', label: Text('مبلغ'), icon: Icon(Icons.attach_money)),
              ButtonSegment(value: 'set', label: Text('توحيد'), icon: Icon(Icons.drag_handle)),
              ButtonSegment(value: 'clear', label: Text('مسح'), icon: Icon(Icons.backspace_outlined)),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: 10),
          if (_method == 'percent' || _method == 'amount')
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('زيادة'), icon: Icon(Icons.arrow_upward)),
                ButtonSegment(value: false, label: Text('نقصان'), icon: Icon(Icons.arrow_downward)),
              ],
              selected: {_increase},
              onSelectionChanged: (s) => setState(() => _increase = s.first),
            ),
          const SizedBox(height: 10),
          if (_method != 'clear')
            MoneyField(
              controller: _value,
              label: _method == 'percent' ? 'النسبة %' : (_method == 'set' ? 'السعر الموحد' : 'المبلغ'),
              width: 200,
            ),
          const SizedBox(height: 10),
          Row(children: [
            const Text('التقريب إلى: '),
            const SizedBox(width: 6),
            DropdownButton<double>(
              value: _rounding,
              items: const [
                DropdownMenuItem(value: 0, child: Text('بدون')),
                DropdownMenuItem(value: 50, child: Text('50')),
                DropdownMenuItem(value: 100, child: Text('100')),
                DropdownMenuItem(value: 250, child: Text('250')),
                DropdownMenuItem(value: 500, child: Text('500')),
                DropdownMenuItem(value: 1000, child: Text('1000')),
              ],
              onChanged: (v) => setState(() => _rounding = v ?? 0),
            ),
          ]),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _onlyZero,
            onChanged: (v) => setState(() => _onlyZero = v ?? false),
            title: const Text('الأسعار الصفرية فقط (تعبئة الفارغ)'),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _doPreview,
                icon: const Icon(Icons.visibility_rounded),
                label: const Text('معاينة'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PrimaryButton(
                label: 'تنفيذ (${_preview.length})',
                icon: Icons.done_all_rounded,
                color: ErpColors.green,
                busy: _busy,
                onPressed: _preview.isEmpty ? null : _apply,
              ),
            ),
          ]),
        ]),
      ),
    ]);
  }

  Widget _productsPanel() {
    if (_preview.isNotEmpty) {
      var up = 0, down = 0;
      for (final c in _preview) {
        if (c.newValue > c.oldValue) {
          up++;
        } else {
          down++;
        }
      }
      return Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            StatusBadge('معاينة: ${_preview.length} تغيير', color: ErpColors.purple),
            const SizedBox(width: 8),
            StatusBadge('↑ $up', color: ErpColors.green),
            const SizedBox(width: 8),
            StatusBadge('↓ $down', color: ErpColors.red),
            const Spacer(),
            TextButton.icon(
                onPressed: () => setState(() => _preview = const []),
                icon: const Icon(Icons.close),
                label: const Text('إلغاء المعاينة')),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _preview.length,
            itemBuilder: (_, i) {
              final c = _preview[i];
              final upd = c.newValue > c.oldValue;
              final pct = c.oldValue <= 0 ? null : (c.newValue - c.oldValue) / c.oldValue * 100;
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), side: const BorderSide(color: ErpColors.border)),
                child: ListTile(
                  dense: true,
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(priceFieldNames[c.level - 1]),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(fmtMoney(c.oldValue),
                        style: const TextStyle(color: ErpColors.muted, decoration: TextDecoration.lineThrough)),
                    const SizedBox(width: 8),
                    Icon(upd ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 16, color: upd ? ErpColors.green : ErpColors.red),
                    const SizedBox(width: 4),
                    Text(fmtMoney(c.newValue),
                        style: TextStyle(fontWeight: FontWeight.bold, color: upd ? ErpColors.green : ErpColors.red)),
                    if (pct != null) ...[
                      const SizedBox(width: 8),
                      Text('${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 11, color: ErpColors.muted)),
                    ],
                  ]),
                ),
              );
            },
          ),
        ),
      ]);
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(children: [
          Text('${_products.length} مادة', style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          TextButton(
              onPressed: () => setState(() => _selected.addAll(_products.map((p) => p.id))), child: const Text('تحديد الكل')),
          TextButton(onPressed: () => setState(_selected.clear), child: const Text('إلغاء التحديد')),
        ]),
      ),
      Expanded(
        child: _products.isEmpty
            ? const EmptyState('لا توجد مواد')
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _products.length,
                itemBuilder: (_, i) {
                  final p = _products[i];
                  final sel = _selected.contains(p.id);
                  return CheckboxListTile(
                    dense: true,
                    value: sel,
                    onChanged: (v) => setState(() => v == true ? _selected.add(p.id) : _selected.remove(p.id)),
                    title: Text(p.name),
                    subtitle: Wrap(spacing: 10, children: [
                      Text('الكلفة ${fmtMoney(p.cost)}', style: const TextStyle(fontSize: 11)),
                      for (var l = 0; l < 6; l++)
                        if (p.prices[l] > 0)
                          Text('${priceFieldNames[l]} ${fmtMoney(p.prices[l])}',
                              style: const TextStyle(fontSize: 11, color: ErpColors.navy)),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _history() {
    if (_batches.isEmpty) return const EmptyState('لا توجد دفعات تعديل بعد', icon: Icons.history);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _batches.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final b = _batches[i];
        final no = b['batch_no'] as int;
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: ErpColors.border)),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: ErpColors.purple.withOpacity(.12),
              child: Text('$no', style: const TextStyle(color: ErpColors.purple, fontWeight: FontWeight.bold)),
            ),
            title: Text('دفعة #$no — ${b['n']} تغيير'),
            subtitle: Text('${fmtDate(parseDate(b['at']))} • ${b['by'] ?? ''}'),
            trailing: TextButton.icon(
              onPressed: () => _undo(no),
              icon: const Icon(Icons.undo_rounded, color: ErpColors.orange),
              label: const Text('تراجع', style: TextStyle(color: ErpColors.orange)),
            ),
            children: [
              FutureBuilder<List<Map<String, Object?>>>(
                future: _batchLines(no),
                builder: (_, s) {
                  final rows = s.data ?? const [];
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: SimpleTable(
                      headers: const ['المادة', 'السعر', 'قبل', 'بعد'],
                      numericColumns: const {2, 3},
                      rows: [
                        for (final r in rows)
                          [
                            '${r['name'] ?? r['product_id']}',
                            _fieldLabel('${r['field']}'),
                            fmtMoney(d0(r['old_value'])),
                            fmtMoney(d0(r['new_value'])),
                          ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _fieldLabel(String f) {
    final i = int.tryParse(f.replaceAll('price', ''));
    if (i == null || i < 1 || i > 6) return f;
    return priceFieldNames[i - 1];
  }

  Future<List<Map<String, Object?>>> _batchLines(int batch) async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT l.*, p.name FROM price_change_log l LEFT JOIN products p ON p.id = l.product_id
      WHERE l.batch_no = ? ORDER BY p.name''', [batch]);
  }
}
