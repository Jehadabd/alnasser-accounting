// screens/product_reports_screen.dart
//
// 📦 تقارير البضاعة — لأي فترة ولأي قسم:
//   • الفترة (اليوم/الشهر/السنة/الكل أو من–إلى) + مصدر البيانات.
//   • القسم (مع أقسامه الفرعية) + بحث + ترتيب (المبيعات/الربح/الكمية/الهامش/الاسم).
//   • مؤشرات: مواد مباعة، المبيعات، الكلفة، الربح وهامشه، المرتجع.
//   • توزيع الأقسام، ثم جدول المواد، ثم «مواد لم تُبع في الفترة».
// الأرقام من المحرك الموحّد: الكمية بالوحدة الأساسية (الكرتون = عدد قطعه)،
// والخسارة تظهر بالأحمر وبإشارتها (كانت تُعرض ربحاً).

import 'dart:async';

import 'package:flutter/material.dart';

import '../accounting/screens/acc_ui.dart' show PeriodBar, accRoute;
import '../erp/erp_kit.dart' show pickFromList;
import '../services/database_service.dart';
import '../services/reports_service.dart';
import '../widgets/report_kit.dart';
import 'product_report_details_screen.dart';

enum _Sort { sales, profit, qty, margin, name }

class ProductReportsScreen extends StatefulWidget {
  const ProductReportsScreen({super.key, this.initialCategoryId});
  final int? initialCategoryId;

  @override
  State<ProductReportsScreen> createState() => _ProductReportsScreenState();
}

class _ProductReportsScreenState extends State<ProductReportsScreen> {
  final _rs = ReportsService();
  final _search = TextEditingController();
  Timer? _debounce;

  DateTime? _from = DateTime(DateTime.now().year, 1, 1);
  DateTime _to = DateTime.now();
  String _source = ReportSource.all;
  int? _categoryId;
  bool _includeSub = true;
  _Sort _sort = _Sort.sales;
  bool _showUnsold = false;

  bool _loading = true;
  List<ProductAgg> _all = const [];
  List<ReportCategory> _cats = const [];
  List<Map<String, Object?>> _unsold = const [];
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initialCategoryId;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() => _loading = true);
    try {
      _rs.reportSourceFilter = _source;
      final facts = await _rs.loadFacts(from: _from, to: _to);
      final cats = await _rs.getCategories();
      final all = facts.byProduct();
      if (!mounted || token != _loadToken) return;
      setState(() {
        _all = all;
        _cats = cats;
        _loading = false;
      });
      if (_showUnsold) _loadUnsold();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      setToast(context, 'تعذّر تحميل التقرير: $e', error: true);
    }
  }

  Future<void> _loadUnsold() async {
    try {
      final db = await DatabaseService().database;
      final rows = await db.rawQuery('''
        SELECT id, name, unit, category_id, COALESCE(stock_quantity, 0) AS stock
        FROM products WHERE COALESCE(is_deleted, 0) = 0 ORDER BY name''');
      if (!mounted) return;
      setState(() => _unsold = rows);
    } catch (_) {}
  }

  // ─────────────────────────── تصفية ───────────────────────────

  Set<int>? get _catSet {
    final id = _categoryId;
    if (id == null) return null;
    if (!_includeSub) return {id};
    final children = <int, List<int>>{};
    for (final c in _cats) {
      if (c.parentId != null) children.putIfAbsent(c.parentId!, () => []).add(c.id);
    }
    final out = <int>{id};
    final stack = [id];
    while (stack.isNotEmpty) {
      for (final ch in children[stack.removeLast()] ?? const <int>[]) {
        if (out.add(ch)) stack.add(ch);
      }
    }
    return out;
  }

  bool _matches(String name, int? categoryId) {
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty && !name.toLowerCase().contains(q)) return false;
    final set = _catSet;
    if (set != null && (categoryId == null || !set.contains(categoryId))) return false;
    return true;
  }

  List<ProductAgg> get _shown {
    final list = _all.where((p) => _matches(p.name, p.categoryId)).toList();
    int cmp(ProductAgg a, ProductAgg b) => switch (_sort) {
          _Sort.sales => b.netRevenue.compareTo(a.netRevenue),
          _Sort.profit => b.profit.compareTo(a.profit),
          _Sort.qty => b.netQty.compareTo(a.netQty),
          _Sort.margin => b.margin.compareTo(a.margin),
          _Sort.name => a.name.compareTo(b.name),
        };
    list.sort(cmp);
    return list;
  }

  String _catName(int? id) {
    if (id == null) return 'بلا قسم';
    for (final c in _cats) {
      if (c.id == id) return c.name;
    }
    return 'قسم #$id';
  }

  Future<void> _pickCategory() async {
    // شجرة الأقسام بترتيب العرض (الأب ثم أبناؤه)
    final children = <int?, List<ReportCategory>>{};
    for (final c in _cats) {
      children.putIfAbsent(c.parentId, () => []).add(c);
    }
    final ordered = <(ReportCategory?, int)>[(null, 0)];
    void walk(int? parent, int depth) {
      for (final c in children[parent] ?? const <ReportCategory>[]) {
        ordered.add((c, depth));
        walk(c.id, depth + 1);
      }
    }

    walk(null, 0);
    final picked = await pickFromList<(ReportCategory?, int)>(
      context,
      title: 'اختر القسم',
      subtitle: 'تُحسب الأقسام الفرعية ضمن القسم المختار',
      icon: Icons.category_rounded,
      items: ordered,
      labelOf: (x) => x.$1?.name ?? 'كل الأقسام',
      depthOf: (x) => x.$2,
      detailOf: (x) => x.$1 == null ? '' : '${x.$1!.productCount} مادة',
    );
    if (picked == null || !mounted) return;
    setState(() => _categoryId = picked.$1?.id);
  }

  // ─────────────────────────── الواجهة ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final profit = repCanSeeProfit();
    final shown = _loading ? const <ProductAgg>[] : _shown;
    final sales = shown.fold<double>(0, (s, p) => s + p.netRevenue);
    final cost = shown.fold<double>(0, (s, p) => s + p.netCost);
    final prof = shown.fold<double>(0, (s, p) => s + p.profit);
    final returned = shown.fold<double>(0, (s, p) => s + p.returnedRevenue);
    final maxSales = shown.fold<double>(0, (m, p) => p.netRevenue > m ? p.netRevenue : m);

    final soldKeys = {for (final p in _all) p.productId};
    final unsold = !_showUnsold
        ? const <Map<String, Object?>>[]
        : _unsold
            .where((r) => !soldKeys.contains((r['id'] as num).toInt()))
            .where((r) => _matches((r['name'] as String?) ?? '', (r['category_id'] as num?)?.toInt()))
            .toList();

    return ReportScaffold(
      title: 'تقارير البضاعة',
      subtitle: _categoryId == null ? 'كل الأقسام' : 'قسم: ${_catName(_categoryId)}',
      icon: Icons.inventory_2_rounded,
      actions: [
        SourceMenu(
          value: _source,
          onChanged: (v) {
            setState(() => _source = v);
            _load();
          },
        ),
        IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      header: _filters(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        KpiGrid(minTileWidth: 190, children: [
                          KpiTile(
                            label: 'مواد مباعة',
                            value: shown.length.toDouble(),
                            money: false,
                            icon: Icons.category_rounded,
                            color: kSetNavy,
                            hint: _all.length == shown.length ? null : 'من ${_all.length}',
                          ),
                          KpiTile(label: 'صافي المبيعات', value: sales, icon: Icons.point_of_sale_rounded, color: kSetBlue, emphasis: true),
                          if (profit) KpiTile(label: 'الكلفة', value: cost, icon: Icons.price_change_rounded, color: kRepAmber),
                          if (profit)
                            KpiTile(
                              label: 'الربح',
                              value: prof,
                              icon: Icons.trending_up_rounded,
                              color: kSetGreen,
                              hint: sales.abs() > 0 ? 'هامش ${repPercent(prof / sales * 100)}' : null,
                            ),
                          if (returned > 0)
                            KpiTile(label: 'مرتجع', value: returned, icon: Icons.assignment_return_rounded, color: kSetRed),
                        ]),
                        const SizedBox(height: 14),
                        if (_categoryId == null && shown.isNotEmpty) _categoriesCard(shown, profit),
                        _listHeader(shown.length, profit),
                      ]),
                    ),
                  ),
                ),
              ),
              if (shown.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyReport(
                    title: 'لا توجد مبيعات مطابقة',
                    text: 'غيّر الفترة أو القسم أو كلمة البحث.',
                    icon: Icons.inventory_2_outlined,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) => Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: _ProductRow(
                          rank: i + 1,
                          p: shown[i],
                          category: _catName(shown[i].categoryId),
                          showProfit: profit,
                          fraction: maxSales <= 0 ? 0 : shown[i].netRevenue / maxSales,
                          onTap: () => Navigator.push(
                            context,
                            accRoute(ProductReportDetailsScreen(
                              productId: shown[i].productId,
                              productName: shown[i].name,
                              categoryName: _catName(shown[i].categoryId),
                            )),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
                      child: _unsoldCard(unsold),
                    ),
                  ),
                ),
              ),
            ]),
    );
  }

  Widget _filters() {
    final sorts = <(_Sort, String)>[
      (_Sort.sales, 'المبيعات'),
      if (repCanSeeProfit()) (_Sort.profit, 'الربح'),
      (_Sort.qty, 'الكمية'),
      if (repCanSeeProfit()) (_Sort.margin, 'الهامش'),
      (_Sort.name, 'الاسم'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PeriodBar(
        from: _from,
        to: _to,
        onChanged: (f, t) {
          setState(() {
            _from = f;
            _to = t;
          });
          _load();
        },
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'بحث باسم المادة…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _search.clear()),
                      ),
              ),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 250), () {
                  if (mounted) setState(() {});
                });
              },
            ),
          ),
          OutlinedButton.icon(
            onPressed: _pickCategory,
            icon: const Icon(Icons.category_rounded, size: 19),
            label: Text(_categoryId == null ? 'كل الأقسام' : _catName(_categoryId)),
          ),
          if (_categoryId != null) ...[
            FilterChip(
              label: const Text('مع الفرعية'),
              selected: _includeSub,
              onSelected: (v) => setState(() => _includeSub = v),
            ),
            IconButton(
              tooltip: 'إلغاء القسم',
              onPressed: () => setState(() => _categoryId = null),
              icon: const Icon(Icons.filter_alt_off_rounded),
            ),
          ],
          const SizedBox(width: 6),
          const Text('ترتيب:', style: TextStyle(color: kSetMuted, fontWeight: FontWeight.w600)),
          for (final s in sorts)
            ChoiceChip(
              label: Text(s.$2),
              selected: _sort == s.$1,
              showCheckmark: false,
              onSelected: (_) => setState(() => _sort = s.$1),
            ),
        ]),
      ),
    ]);
  }

  Widget _categoriesCard(List<ProductAgg> shown, bool profit) {
    // توزيع على الأقسام الجذرية (الفرعي يُجمع تحت أبيه)
    final parent = {for (final c in _cats) c.id: c.parentId};
    int? root(int? id) {
      if (id == null) return null;
      var cur = id;
      final seen = <int>{};
      while (parent[cur] != null && seen.add(cur)) {
        cur = parent[cur]!;
      }
      return cur;
    }

    final sums = <int?, (double, double, int)>{};
    for (final p in shown) {
      final r = root(p.categoryId);
      final cur = sums[r] ?? (0.0, 0.0, 0);
      sums[r] = (cur.$1 + p.netRevenue, cur.$2 + p.profit, cur.$3 + 1);
    }
    final list = sums.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    if (list.length < 2) return const SizedBox.shrink();
    final max = list.first.value.$1;
    return SetCard(
      title: 'حسب القسم',
      subtitle: 'اضغط قسماً لعرض مواده فقط',
      icon: Icons.donut_small_rounded,
      color: kRepTeal,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 760 ? 2 : 1;
          final w = (c.maxWidth - (cols - 1) * 16) / cols;
          return Wrap(spacing: 16, children: [
            for (var i = 0; i < list.length && i < 12; i++)
              SizedBox(
                width: w,
                child: RankRow(
                  rank: i + 1,
                  title: _catName(list[i].key),
                  subtitle: '${list[i].value.$3} مادة${profit ? ' • ربح ${repMoney(list[i].value.$2)}' : ''}',
                  value: list[i].value.$1,
                  fraction: max <= 0 ? 0 : list[i].value.$1 / max,
                  color: kRepTeal,
                  onTap: list[i].key == null ? null : () => setState(() => _categoryId = list[i].key),
                ),
              ),
          ]);
        }),
      ),
    );
  }

  Widget _listHeader(int n, bool profit) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Row(children: [
          Text('المواد ($n)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kSetText)),
          const Spacer(),
          const Text('الكمية بالوحدة الأساسية (قطعة/متر)', style: TextStyle(fontSize: 12, color: kSetMuted)),
        ]),
      );

  Widget _unsoldCard(List<Map<String, Object?>> unsold) {
    return SetCard(
      title: 'مواد لم تُبع في الفترة',
      subtitle: _showUnsold ? '${unsold.length} مادة — مرتّبة بالاسم' : 'المواد الراكدة ضمن القسم والبحث الحاليين',
      icon: Icons.hourglass_empty_rounded,
      color: kSetOrange,
      trailing: Switch(
        value: _showUnsold,
        onChanged: (v) {
          setState(() => _showUnsold = v);
          if (v && _unsold.isEmpty) _loadUnsold();
        },
      ),
      child: !_showUnsold
          ? const SizedBox(height: 4)
          : unsold.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('كل المواد المطابقة بيعت في هذه الفترة.', style: TextStyle(color: kSetMuted)),
                )
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final r in unsold.take(300))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: kSetOrange.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          '${r['name']} • مخزون ${repQty((r['stock'] as num?) ?? 0)}',
                          style: const TextStyle(fontSize: 12.5, color: kSetText),
                        ),
                      ),
                    if (unsold.length > 300)
                      Text('… و${unsold.length - 300} مادة أخرى', style: const TextStyle(color: kSetMuted)),
                  ]),
                ),
    );
  }
}

/// سطر مادة: ترتيب، اسم وقسم، كمية، مبيعات، كلفة، ربح وهامش.
class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.rank,
    required this.p,
    required this.category,
    required this.showProfit,
    required this.fraction,
    required this.onTap,
  });
  final int rank;
  final ProductAgg p;
  final String category;
  final bool showProfit;
  final double fraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, Widget value, {double width = 120}) => SizedBox(
          width: width,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: kSetMuted)),
            const SizedBox(height: 2),
            value,
          ]),
        );
    final marginColor = p.profit < 0 ? kSetRed : (p.margin < 10 ? kSetOrange : kSetGreen);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.profit < 0 && showProfit ? kSetRed.withValues(alpha: 0.35) : kSetBorder),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: Row(children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: rank <= 3 ? kSetNavy : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text('$rank',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w900, color: rank <= 3 ? Colors.white : kSetText)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
                          Text('$category • ${p.invoiceCount} فاتورة',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: kSetMuted)),
                        ]),
                      ),
                    ]),
                  ),
                  cell(
                    'الكمية',
                    Text('${repQty(p.netQty)} ${p.baseUnit}',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
                    width: 110,
                  ),
                  cell('المبيعات', MoneyLabel(p.netRevenue)),
                  if (showProfit) cell('الكلفة', MoneyLabel(p.netCost, bold: false)),
                  if (showProfit)
                    cell(
                      'الربح',
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        MoneyLabel(p.profit, color: kSetGreen),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                              color: marginColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                          child: Text(repPercent(p.margin),
                              textDirection: TextDirection.ltr,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: marginColor)),
                        ),
                      ]),
                      width: 170,
                    ),
                  if (p.returnedQty > 0)
                    cell(
                      'مرتجع',
                      Text('${repQty(p.returnedQty)} ${p.baseUnit}',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: kSetRed)),
                      width: 90,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fraction.clamp(0.0, 1.0),
                  minHeight: 4,
                  color: kSetBlue,
                  backgroundColor: const Color(0xFFF1F5F9),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
