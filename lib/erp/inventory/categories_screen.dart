// lib/erp/inventory/categories_screen.dart
//
// 🗂️ شجرة الأقسام + التعديل الجماعي لبطاقات المواد (مثل الإداري):
//   • أقسام رئيسية وفرعية: إضافة، إعادة تسمية، نقل، حذف (بشروط الأمان).
//   • نقل مواد إلى قسم، تفعيل/إيقاف، إخفاء عن الموظفين، ترميز تلقائي للمواد بلا رمز.
// نقل القسم يمر عبر DatabaseService.updateProduct (يزامن المادة ولا يلمس كميتها).

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../inventory/item_card_screen.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../stock_helpers.dart';
import 'price_tools.dart' show productWithCategory;

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _Cat {
  _Cat(this.id, this.name, this.parentId, this.count);
  final int id;
  final String name;
  final int? parentId;
  final int count;
  final List<_Cat> children = [];
  int get total => count + children.fold<int>(0, (s, c) => s + c.total);
}

class _CategoriesScreenState extends State<CategoriesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<_Cat> _roots = const [];
  int _uncategorized = 0;
  int? _selectedCat;
  bool _selectedNone = false;

  // المواد
  List<ProductLite> _products = const [];
  final Set<int> _sel = {};
  String _q = '';
  bool _busy = false;

  bool get _canEdit => AuthService().hasPermission(AppPermissions.editProducts);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = await erpDb();
    final rows = await db.rawQuery('''
      SELECT c.id, c.name, c.parent_id,
        (SELECT COUNT(*) FROM products p WHERE p.category_id = c.id AND COALESCE(p.is_deleted, 0) = 0) AS n
      FROM categories c ORDER BY c.name''');
    final un = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM products WHERE (category_id IS NULL OR category_id = 0) AND COALESCE(is_deleted, 0) = 0');
    final all = {for (final r in rows) r['id'] as int: _Cat(r['id'] as int, '${r['name']}', r['parent_id'] as int?, (r['n'] as int?) ?? 0)};
    final roots = <_Cat>[];
    for (final c in all.values) {
      final p = c.parentId == null ? null : all[c.parentId];
      if (p != null && p.id != c.id) {
        p.children.add(c);
      } else {
        roots.add(c);
      }
    }
    if (!mounted) return;
    setState(() {
      _roots = roots;
      _uncategorized = (un.first['n'] as int?) ?? 0;
    });
    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    final db = await erpDb();
    final where = <String>[];
    final args = <Object?>[];
    if (_selectedNone) {
      where.add('(p.category_id IS NULL OR p.category_id = 0)');
    } else if (_selectedCat != null) {
      where.add('p.category_id = ?');
      args.add(_selectedCat);
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
        _sel.removeWhere((id) => !r.any((p) => p.id == id));
      });
    }
  }

  // ─────────── عمليات الأقسام ───────────

  Future<void> _addCat({int? parentId}) async {
    if (!_canEdit) {
      showError(context, 'لا تملك صلاحية تعديل البضاعة');
      return;
    }
    final name = await askText(context, parentId == null ? 'قسم رئيسي جديد' : 'قسم فرعي جديد', label: 'اسم القسم');
    if (name == null || name.trim().isEmpty) return;
    final db = await erpDb();
    final dup = await db.query('categories', where: 'LOWER(TRIM(name)) = LOWER(?)', whereArgs: [name.trim()], limit: 1);
    if (dup.isNotEmpty) {
      if (mounted) showError(context, 'يوجد قسم بهذا الاسم');
      return;
    }
    await db.insert('categories', {'name': name.trim(), 'parent_id': parentId});
    await _load();
  }

  Future<void> _renameCat(_Cat c) async {
    if (!_canEdit) {
      showError(context, 'لا تملك صلاحية تعديل البضاعة');
      return;
    }
    final name = await askText(context, 'إعادة تسمية القسم', label: 'الاسم الجديد', initial: c.name);
    if (name == null || name.trim().isEmpty || name.trim() == c.name) return;
    final db = await erpDb();
    final dup = await db.query('categories',
        where: 'LOWER(TRIM(name)) = LOWER(?) AND id != ?', whereArgs: [name.trim(), c.id], limit: 1);
    if (dup.isNotEmpty) {
      if (mounted) showError(context, 'يوجد قسم بهذا الاسم');
      return;
    }
    await db.update('categories', {'name': name.trim()}, where: 'id = ?', whereArgs: [c.id]);
    await _load();
  }

  bool _isDescendant(_Cat c, int id) => c.children.any((x) => x.id == id || _isDescendant(x, id));

  Future<void> _moveCat(_Cat c) async {
    if (!_canEdit) {
      showError(context, 'لا تملك صلاحية تعديل البضاعة');
      return;
    }
    final options = <_Cat>[];
    void walk(List<_Cat> l) {
      for (final x in l) {
        if (x.id != c.id && !_isDescendant(c, x.id)) options.add(x);
        walk(x.children);
      }
    }

    walk(_roots);
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('نقل «${c.name}» تحت'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, -1), child: const Text('— قسم رئيسي —')),
          for (final o in options) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, o.id), child: Text(o.name)),
        ],
      ),
    );
    if (picked == null) return;
    final db = await erpDb();
    await db.update('categories', {'parent_id': picked == -1 ? null : picked}, where: 'id = ?', whereArgs: [c.id]);
    await _load();
  }

  Future<void> _deleteCat(_Cat c) async {
    if (!_canEdit) {
      showError(context, 'لا تملك صلاحية تعديل البضاعة');
      return;
    }
    if (c.children.isNotEmpty) {
      showError(context, 'انقل أو احذف الأقسام الفرعية أولاً');
      return;
    }
    if (c.count > 0) {
      showError(context, 'القسم فيه ${c.count} مادة — انقلها إلى قسم آخر أولاً');
      return;
    }
    final ok = await confirmDialog(context, 'حذف القسم', 'حذف القسم «${c.name}»؟', color: ErpColors.red);
    if (!ok) return;
    final db = await erpDb();
    await db.delete('categories', where: 'id = ?', whereArgs: [c.id]);
    if (_selectedCat == c.id) _selectedCat = null;
    await _load();
  }

  // ─────────── العمليات الجماعية ───────────

  List<int> get _targetIds => _sel.isEmpty ? const [] : _sel.toList();

  Future<void> _bulk(Future<void> Function(int id) f, String done) async {
    final ids = _targetIds;
    if (ids.isEmpty) {
      showError(context, 'حدّد مواداً أولاً');
      return;
    }
    if (!_canEdit) {
      showError(context, 'لا تملك صلاحية تعديل البضاعة');
      return;
    }
    setState(() => _busy = true);
    var n = 0;
    try {
      for (final id in ids) {
        await f(id);
        n++;
      }
      if (mounted) showOk(context, '$done ($n)');
    } catch (e) {
      if (mounted) showError(context, 'توقف بعد $n مادة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _assignCategory() async {
    final cats = <_Cat>[];
    void walk(List<_Cat> l, int depth) {
      for (final x in l) {
        cats.add(x);
        walk(x.children, depth + 1);
      }
    }

    walk(_roots, 0);
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('نقل ${_sel.length} مادة إلى قسم'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, -1), child: const Text('— بلا قسم —')),
          for (final c in cats) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, c.id), child: Text(c.name)),
        ],
      ),
    );
    if (picked == null) return;
    final dbs = DatabaseService();
    await _bulk((id) async {
      final p = await dbs.getProductById(id);
      if (p == null) return;
      final cid = picked == -1 ? null : picked;
      if (p.categoryId == cid) return;
      await dbs.updateProduct(productWithCategory(p, cid));
    }, 'نُقلت المواد');
  }

  Future<void> _setActive(bool active) async {
    final svc = ItemCardService();
    await _bulk((id) => svc.saveDetails(id, {'is_active': active ? 1 : 0}), active ? 'فُعِّلت المواد' : 'أُوقفت المواد');
  }

  Future<void> _setHidden(bool hidden) async {
    final svc = ItemCardService();
    await _bulk((id) => svc.saveDetails(id, {'min_role': hidden ? 'admin' : null}),
        hidden ? 'أُخفيت عن الموظفين' : 'أُظهرت للجميع');
  }

  Future<void> _autoCodes() async {
    final svc = ItemCardService();
    await _bulk((id) async {
      final d = await svc.details(id);
      final c = (d['item_code'] as String?)?.trim() ?? '';
      if (c.isNotEmpty) return;
      await svc.saveDetails(id, {'item_code': await svc.suggestCode()});
    }, 'رُمِّزت المواد');
  }

  // ─────────── الواجهة ───────────

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 900;
    final tree = _treePanel();
    final prods = _productsPanel();
    return ErpPage(
      title: 'الأقسام والتعديل الجماعي',
      subtitle: 'شجرة الأقسام • نقل المواد • تفعيل/إيقاف • ترميز تلقائي',
      icon: Icons.account_tree_rounded,
      actions: [
        IconButton(
          tooltip: 'قسم رئيسي جديد',
          icon: const Icon(Icons.create_new_folder_rounded, color: Colors.white),
          onPressed: () => _addCat(),
        ),
      ],
      body: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 340, child: tree),
              const VerticalDivider(width: 1),
              Expanded(child: prods),
            ])
          : Column(children: [
              TabBar(controller: _tabs, labelColor: ErpColors.navy, tabs: const [
                Tab(text: 'الأقسام'),
                Tab(text: 'المواد'),
              ]),
              Expanded(child: TabBarView(controller: _tabs, children: [tree, prods])),
            ]),
    );
  }

  Widget _treePanel() {
    Widget node(_Cat c, int depth) {
      final sel = _selectedCat == c.id && !_selectedNone;
      final tile = Container(
        margin: EdgeInsetsDirectional.only(start: depth * 16.0, bottom: 4),
        decoration: BoxDecoration(
          color: sel ? ErpColors.navy.withOpacity(.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sel ? ErpColors.navy : ErpColors.border),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(c.children.isEmpty ? Icons.folder_outlined : Icons.folder_copy_rounded,
              color: depth == 0 ? ErpColors.navy : ErpColors.blue),
          title: Text(c.name, style: TextStyle(fontWeight: depth == 0 ? FontWeight.bold : FontWeight.w500)),
          subtitle: Text(c.children.isEmpty ? '${c.count} مادة' : '${c.count} مادة • ${c.total} مع الفروع',
              style: const TextStyle(fontSize: 11)),
          onTap: () {
            setState(() {
              _selectedCat = c.id;
              _selectedNone = false;
              _sel.clear();
            });
            _loadProducts();
            if (MediaQuery.of(context).size.width <= 900) _tabs.animateTo(1);
          },
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (v) {
              switch (v) {
                case 'add':
                  _addCat(parentId: c.id);
                  break;
                case 'rename':
                  _renameCat(c);
                  break;
                case 'move':
                  _moveCat(c);
                  break;
                case 'delete':
                  _deleteCat(c);
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'add', child: Text('قسم فرعي جديد')),
              PopupMenuItem(value: 'rename', child: Text('إعادة تسمية')),
              PopupMenuItem(value: 'move', child: Text('نقل تحت قسم آخر')),
              PopupMenuItem(value: 'delete', child: Text('حذف', style: TextStyle(color: ErpColors.red))),
            ],
          ),
        ),
      );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        tile,
        for (final ch in c.children) node(ch, depth + 1),
      ]);
    }

    return ListView(padding: const EdgeInsets.all(12), children: [
      _chipTile('كل المواد', Icons.all_inbox_rounded, _selectedCat == null && !_selectedNone, () {
        setState(() {
          _selectedCat = null;
          _selectedNone = false;
          _sel.clear();
        });
        _loadProducts();
      }),
      _chipTile('بلا قسم ($_uncategorized)', Icons.help_outline_rounded, _selectedNone, () {
        setState(() {
          _selectedNone = true;
          _selectedCat = null;
          _sel.clear();
        });
        _loadProducts();
      }),
      const SizedBox(height: 8),
      if (_roots.isEmpty) const EmptyState('لا توجد أقسام — أضف قسماً من الأعلى', icon: Icons.folder_off_outlined),
      for (final r in _roots) node(r, 0),
    ]);
  }

  Widget _chipTile(String label, IconData icon, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ListTile(
          dense: true,
          tileColor: selected ? ErpColors.navy.withOpacity(.08) : Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: selected ? ErpColors.navy : ErpColors.border)),
          leading: Icon(icon, color: ErpColors.navy),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          onTap: onTap,
        ),
      );

  Widget _productsPanel() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(children: [
          Expanded(
              child: SearchBox(
                  hint: 'بحث في المواد',
                  onChanged: (v) {
                    _q = v;
                    _loadProducts();
                  })),
          const SizedBox(width: 8),
          Text('${_sel.length} / ${_products.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            tooltip: 'تحديد الكل',
            icon: const Icon(Icons.select_all_rounded),
            onPressed: () => setState(() => _sel.addAll(_products.map((p) => p.id))),
          ),
          IconButton(
            tooltip: 'إلغاء التحديد',
            icon: const Icon(Icons.deselect_rounded),
            onPressed: () => setState(_sel.clear),
          ),
        ]),
      ),
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: _sel.isEmpty ? 0 : 56,
        child: _sel.isEmpty
            ? const SizedBox()
            : ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
                _action('نقل إلى قسم', Icons.drive_file_move_rounded, ErpColors.navy, _assignCategory),
                _action('تفعيل', Icons.check_circle_outline, ErpColors.green, () => _setActive(true)),
                _action('إيقاف', Icons.pause_circle_outline, ErpColors.orange, () => _setActive(false)),
                _action('إخفاء عن الموظفين', Icons.visibility_off_outlined, ErpColors.purple, () => _setHidden(true)),
                _action('إظهار للجميع', Icons.visibility_outlined, ErpColors.blue, () => _setHidden(false)),
                _action('ترميز تلقائي', Icons.tag_rounded, ErpColors.gold, _autoCodes),
              ]),
      ),
      if (_busy) const LinearProgressIndicator(),
      Expanded(
        child: _products.isEmpty
            ? const EmptyState('لا توجد مواد')
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _products.length,
                itemBuilder: (_, i) {
                  final p = _products[i];
                  return CheckboxListTile(
                    dense: true,
                    value: _sel.contains(p.id),
                    onChanged: (v) => setState(() => v == true ? _sel.add(p.id) : _sel.remove(p.id)),
                    title: Text(p.name),
                    subtitle: Text(
                        '${p.itemCode?.isNotEmpty == true ? '${p.itemCode} • ' : ''}الرصيد ${fmtQty(p.stock)} • ${fmtMoney(p.prices[0])}',
                        style: const TextStyle(fontSize: 11)),
                    secondary: IconButton(
                      tooltip: 'بطاقة المادة',
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      onPressed: () async {
                        await Navigator.push(
                            context, MaterialPageRoute(builder: (_) => ItemCardScreen(productId: p.id)));
                        _load();
                      },
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _action(String label, IconData icon, Color color, VoidCallback onTap) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: ActionChip(
          avatar: Icon(icon, size: 18, color: color),
          label: Text(label),
          onPressed: _busy ? null : onTap,
        ),
      );
}
