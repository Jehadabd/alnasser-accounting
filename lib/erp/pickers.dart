// lib/erp/pickers.dart
//
// 🔎 نوافذ اختيار موحّدة: مادة، عميل، مورد، حساب، صندوق، مخزن.

import 'package:flutter/material.dart';

import '../accounting/ledger.dart';
import '../accounting/screens/acc_ui.dart';
import '../accounting/vouchers_service.dart';
import '../org/org_service.dart';
import 'erp_common.dart';
import 'erp_ui.dart';
import 'stock_helpers.dart';

class PartyLite {
  PartyLite(this.id, this.name, this.phone, this.balance, {this.balanceUsd = 0});
  final int id;
  final String name;
  final String? phone;
  final double balance;
  final double balanceUsd;
  @override
  String toString() => name;
}

class Pickers {
  Pickers._();

  static Future<List<PartyLite>> searchCustomers(String q, {int limit = 80}) async {
    final db = await erpDb();
    final t = q.trim();
    final rows = await db.rawQuery('''
      SELECT id, name, phone, current_total_debt FROM customers
      WHERE COALESCE(is_deleted, 0) = 0 ${t.isEmpty ? '' : 'AND (name LIKE ? OR phone LIKE ?)'}
      ORDER BY name LIMIT $limit
    ''', t.isEmpty ? null : ['%$t%', '%$t%']);
    return rows
        .map((r) => PartyLite(r['id'] as int, (r['name'] as String?) ?? '', r['phone'] as String?,
            d0(r['current_total_debt'])))
        .toList();
  }

  static Future<List<PartyLite>> searchSuppliers(String q, {int limit = 80}) async {
    final db = await erpDb();
    final t = q.trim();
    try {
      final rows = await db.rawQuery('''
        SELECT id, name, phone, total_debt_iqd, total_debt_usd FROM suppliers
        ${t.isEmpty ? '' : 'WHERE name LIKE ? OR phone LIKE ?'}
        ORDER BY name LIMIT $limit
      ''', t.isEmpty ? null : ['%$t%', '%$t%']);
      return rows
          .map((r) => PartyLite(r['id'] as int, (r['name'] as String?) ?? '', r['phone'] as String?,
              d0(r['total_debt_iqd']),
              balanceUsd: d0(r['total_debt_usd'])))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<T?> _searchDialog<T>(
    BuildContext context, {
    required String title,
    required Future<List<T>> Function(String q) search,
    required Widget Function(T item) tile,
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => _SearchDialog<T>(title: title, search: search, tile: tile),
    );
  }

  static Future<ProductLite?> product(BuildContext context, {String title = 'اختر مادة'}) =>
      _searchDialog<ProductLite>(
        context,
        title: title,
        search: (q) => ErpStock.search(q),
        tile: (p) => ListTile(
          leading: const CircleAvatar(
              backgroundColor: Color(0x140F3460), child: Icon(Icons.inventory_2, color: ErpColors.navy)),
          title: Text(p.name),
          subtitle: Text(
              'رقم ${p.id}${p.itemCode == null ? '' : ' • رمز ${p.itemCode}'} • المخزون ${fmtQty(p.stock)} ${p.baseUnitName}'),
          trailing: Text(fmtMoney(p.prices[0]), textDirection: TextDirection.ltr),
        ),
      );

  static Future<PartyLite?> customer(BuildContext context, {String title = 'اختر عميلاً'}) =>
      _searchDialog<PartyLite>(
        context,
        title: title,
        search: (q) => searchCustomers(q),
        tile: (c) => ListTile(
          leading: const CircleAvatar(
              backgroundColor: Color(0x142563EB), child: Icon(Icons.person, color: ErpColors.blue)),
          title: Text(c.name),
          subtitle: Text(c.phone ?? ''),
          trailing: MoneyText(c.balance, bold: true),
        ),
      );

  static Future<PartyLite?> supplier(BuildContext context, {String title = 'اختر مورداً'}) =>
      _searchDialog<PartyLite>(
        context,
        title: title,
        search: (q) => searchSuppliers(q),
        tile: (c) => ListTile(
          leading: const CircleAvatar(
              backgroundColor: Color(0x14C2410C), child: Icon(Icons.local_shipping, color: ErpColors.orange)),
          title: Text(c.name),
          subtitle: Text(c.phone ?? ''),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(c.balance, bold: true),
              if (c.balanceUsd.abs() > 0.004) Text('\$ ${fmtMoney(c.balanceUsd)}', style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      );

  /// حساب قابل للترحيل (ليس رئيسياً). [excludeControl] يمنع ذمم العملاء/الموردين.
  static Future<Account?> account(BuildContext context,
      {String title = 'اختر حساباً', bool excludeControl = true, String? type}) async {
    final all = await Ledger().postableAccounts(excludeControl: excludeControl);
    final list = type == null ? all : all.where((a) => a.type == type).toList();
    if (!context.mounted) return null;
    return _searchDialog<Account>(
      context,
      title: title,
      search: (q) async {
        final t = q.trim();
        if (t.isEmpty) return list;
        return list.where((a) => a.name.contains(t) || a.code.startsWith(t)).toList();
      },
      tile: (a) => ListTile(
        leading: Text(a.code, style: const TextStyle(fontWeight: FontWeight.bold, color: ErpColors.navy)),
        title: Text(a.name),
        subtitle: Text(a.typeLabel),
      ),
    );
  }
}

class _SearchDialog<T> extends StatefulWidget {
  const _SearchDialog({required this.title, required this.search, required this.tile});
  final String title;
  final Future<List<T>> Function(String q) search;
  final Widget Function(T item) tile;

  @override
  State<_SearchDialog<T>> createState() => _SearchDialogState<T>();
}

class _SearchDialogState<T> extends State<_SearchDialog<T>> {
  List<T> _items = [];
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  Future<void> _run(String q) async {
    final my = ++_seq;
    final r = await widget.search(q);
    if (!mounted || my != _seq) return;
    setState(() => _items = r);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Column(children: [
          SearchBox(hint: 'بحث...', onChanged: _run, autofocus: true),
          const SizedBox(height: 8),
          Expanded(
            child: _items.isEmpty
                ? const EmptyState('لا توجد نتائج', icon: Icons.search_off)
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => InkWell(
                      onTap: () => Navigator.pop(context, _items[i]),
                      child: widget.tile(_items[i]),
                    ),
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
    );
  }
}

/// قائمة منسدلة بالصناديق.
class CashBoxDropdown extends StatefulWidget {
  const CashBoxDropdown({super.key, required this.value, required this.onChanged, this.width = 220, this.label = 'الصندوق'});
  final int? value;
  final ValueChanged<CashBox?> onChanged;
  final double width;
  final String label;
  @override
  State<CashBoxDropdown> createState() => _CashBoxDropdownState();
}

class _CashBoxDropdownState extends State<CashBoxDropdown> {
  List<CashBox> _boxes = const [];
  @override
  void initState() {
    super.initState();
    VouchersService().cashBoxes().then((b) {
      if (!mounted) return;
      setState(() => _boxes = b);
      if (widget.value == null && b.isNotEmpty) widget.onChanged(b.first);
    });
  }

  @override
  Widget build(BuildContext context) {
    final valid = _boxes.any((b) => b.id == widget.value) ? widget.value : null;
    return DropBox<int>(
      label: widget.label,
      width: widget.width,
      value: valid,
      items: [for (final b in _boxes) DropdownMenuItem(value: b.id, child: Text(b.name))],
      onChanged: (id) {
        final m = _boxes.where((b) => b.id == id);
        widget.onChanged(m.isEmpty ? null : m.first);
      },
    );
  }
}

/// قائمة منسدلة بالمخازن.
class WarehouseDropdown extends StatefulWidget {
  const WarehouseDropdown({super.key, required this.value, required this.onChanged, this.width = 220, this.label = 'المخزن'});
  final int? value;
  final ValueChanged<Warehouse?> onChanged;
  final double width;
  final String label;
  @override
  State<WarehouseDropdown> createState() => _WarehouseDropdownState();
}

class _WarehouseDropdownState extends State<WarehouseDropdown> {
  List<Warehouse> _list = const [];
  @override
  void initState() {
    super.initState();
    OrgService().warehouses(activeOnly: true).then((w) {
      if (!mounted) return;
      setState(() => _list = w);
      if (widget.value == null && w.isNotEmpty) widget.onChanged(w.first);
    });
  }

  @override
  Widget build(BuildContext context) {
    final valid = _list.any((w) => w.id == widget.value) ? widget.value : null;
    return DropBox<int>(
      label: widget.label,
      width: widget.width,
      value: valid,
      items: [for (final w in _list) DropdownMenuItem(value: w.id, child: Text(w.name))],
      onChanged: (id) {
        final m = _list.where((w) => w.id == id);
        widget.onChanged(m.isEmpty ? null : m.first);
      },
    );
  }
}
