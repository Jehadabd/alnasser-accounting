// lib/org/screens/branches_warehouses_screen.dart
//
// 🏢 الفروع والمخازن والتحويلات المخزنية.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../org_service.dart';

class BranchesWarehousesScreen extends StatefulWidget {
  const BranchesWarehousesScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<BranchesWarehousesScreen> createState() => _BranchesWarehousesScreenState();
}

class _BranchesWarehousesScreenState extends State<BranchesWarehousesScreen> {
  final _svc = OrgService();
  List<Branch> _branches = const [];
  List<Warehouse> _warehouses = const [];
  List<Map<String, Object?>> _transfers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await _svc.branches();
      final w = await _svc.warehouses();
      final t = await _svc.transfers();
      if (mounted) {
        setState(() {
          _branches = b;
          _warehouses = w;
          _transfers = t;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _editBranch([Branch? b]) async {
    if (!requirePermission(context, AppPermissions.manageBranches)) return;
    final name = TextEditingController(text: b?.name ?? '');
    final address = TextEditingController(text: b?.address ?? '');
    final phone = TextEditingController(text: b?.phone ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(b == null ? 'فرع جديد' : 'تعديل ${b.name}'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'اسم الفرع')),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'العنوان')),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'الهاتف')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.saveBranch(id: b?.id, name: name.text, address: address.text, phone: phone.text);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _editWarehouse([Warehouse? w]) async {
    if (!requirePermission(context, AppPermissions.manageBranches)) return;
    final name = TextEditingController(text: w?.name ?? '');
    final notes = TextEditingController(text: w?.notes ?? '');
    int branchId = w?.branchId ?? (_branches.isEmpty ? 1 : _branches.first.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(w == null ? 'مخزن جديد' : 'تعديل ${w.name}'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'اسم المخزن')),
              DropdownButtonFormField<int>(
                value: branchId,
                decoration: const InputDecoration(labelText: 'الفرع'),
                items: [for (final b in _branches) DropdownMenuItem(value: b.id, child: Text(b.name))],
                onChanged: (v) => setD(() => branchId = v ?? branchId),
              ),
              TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _svc.saveWarehouse(id: w?.id, name: name.text, branchId: branchId, notes: notes.text);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
        backgroundColor: AccColors.bg,
        appBar: AppBar(
          title: const Text('الفروع والمخازن', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: AccColors.navy,
          foregroundColor: Colors.white,
          centerTitle: true,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: AccColors.cyan,
            tabs: [
              Tab(icon: Icon(Icons.store), text: 'الفروع'),
              Tab(icon: Icon(Icons.warehouse), text: 'المخازن'),
              Tab(icon: Icon(Icons.swap_horiz), text: 'التحويلات'),
            ],
          ),
        ),
        body: TabBarView(children: [
          _branchesTab(),
          _warehousesTab(),
          _transfersTab(),
        ]),
      ),
    );
  }

  Widget _branchesTab() => Scaffold(
        backgroundColor: AccColors.bg,
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'b',
          backgroundColor: AccColors.navy,
          foregroundColor: Colors.white,
          onPressed: () => _editBranch(),
          icon: const Icon(Icons.add),
          label: const Text('فرع جديد'),
        ),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          const Card(
            color: Color(0xFFE0F2FE),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'كل فرع له حاسبة سيرفر خاصة على شبكته المحلية. الفروع تتزامن مع بعضها عبر الإنترنت (Firebase). '
                'علّم هنا الفرع الذي تعمل عليه هذه الحاسبة.',
              ),
            ),
          ),
          for (final b in _branches)
            Card(
              elevation: 0,
              child: ListTile(
                leading: Icon(Icons.store, color: b.isCurrent ? AccColors.green : AccColors.navy),
                title: Text('${b.name}  (${b.code})', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text([
                  if (b.isCurrent) 'هذا الفرع',
                  if (b.address?.isNotEmpty == true) b.address!,
                  if (b.phone?.isNotEmpty == true) b.phone!,
                ].join(' • ')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!b.isCurrent)
                    TextButton(
                      onPressed: () async {
                        if (!requirePermission(context, AppPermissions.manageBranches)) return;
                        await _svc.setCurrentBranch(b.id);
                        _load();
                      },
                      child: const Text('هذا فرعي'),
                    ),
                  IconButton(onPressed: () => _editBranch(b), icon: const Icon(Icons.edit)),
                ]),
              ),
            ),
        ]),
      );

  Widget _warehousesTab() => Scaffold(
        backgroundColor: AccColors.bg,
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'w',
          backgroundColor: AccColors.navy,
          foregroundColor: Colors.white,
          onPressed: () => _editWarehouse(),
          icon: const Icon(Icons.add),
          label: const Text('مخزن جديد'),
        ),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          for (final w in _warehouses)
            Card(
              elevation: 0,
              child: ListTile(
                leading: Icon(Icons.warehouse, color: w.isActive ? AccColors.green : Colors.grey),
                title: Text(w.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text([
                  _branches.firstWhere((b) => b.id == w.branchId, orElse: () => Branch(0, '', '—', null, null, true, false)).name,
                  if (w.isDefault) 'المخزن الرئيسي — تُخصم منه المبيعات',
                  if (!w.isActive) 'موقوف',
                ].join(' • ')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => WarehouseStockScreen(warehouse: w))),
                    child: const Text('الأرصدة'),
                  ),
                  IconButton(onPressed: () => _editWarehouse(w), icon: const Icon(Icons.edit)),
                  if (!w.isDefault)
                    IconButton(
                      tooltip: w.isActive ? 'إيقاف' : 'تفعيل',
                      icon: Icon(w.isActive ? Icons.pause_circle : Icons.play_circle),
                      onPressed: () async {
                        try {
                          await _svc.setWarehouseActive(w.id, !w.isActive);
                          _load();
                        } catch (e) {
                          if (mounted) showError(context, e);
                        }
                      },
                    ),
                ]),
              ),
            ),
        ]),
      );

  Widget _transfersTab() => Scaffold(
        backgroundColor: AccColors.bg,
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 't',
          backgroundColor: AccColors.navy,
          foregroundColor: Colors.white,
          onPressed: () async {
            if (!requirePermission(context, AppPermissions.stockTransfer)) return;
            if (_warehouses.where((w) => w.isActive).length < 2) {
              showError(context, 'أضف مخزناً ثانياً أولاً');
              return;
            }
            final ok = await Navigator.push<bool>(
                context, MaterialPageRoute(builder: (_) => StockTransferScreen(warehouses: _warehouses)));
            if (ok == true) _load();
          },
          icon: const Icon(Icons.swap_horiz),
          label: const Text('تحويل جديد'),
        ),
        body: _transfers.isEmpty
            ? const Center(child: Text('لا توجد تحويلات بعد'))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _transfers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (_, i) {
                  final t = _transfers[i];
                  return Card(
                    elevation: 0,
                    child: ListTile(
                      leading: const Icon(Icons.swap_horiz, color: AccColors.blue),
                      title: Text('تحويل ${t['transfer_number']}: ${t['from_name']} ← ${t['to_name']}'),
                      subtitle: Text('${fmtDate(DateTime.parse(t['transfer_date'] as String))} • '
                          '${t['items']} مادة${(t['notes'] as String?)?.isNotEmpty == true ? ' • ${t['notes']}' : ''}'),
                      onTap: () async {
                        final items = await _svc.transferItems(t['id'] as int);
                        if (!mounted) return;
                        showDialog<void>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text('تحويل ${t['transfer_number']}'),
                            content: SizedBox(
                              width: 400,
                              child: ListView(shrinkWrap: true, children: [
                                for (final it in items)
                                  ListTile(
                                    dense: true,
                                    title: Text('${it['name']}'),
                                    trailing: Text('${it['quantity']} ${it['unit'] ?? ''}'),
                                  ),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      );
}

// ═══════════════════════════════ أرصدة مخزن ═══════════════════════════════

class WarehouseStockScreen extends StatefulWidget {
  const WarehouseStockScreen({super.key, required this.warehouse});
  final Warehouse warehouse;

  @override
  State<WarehouseStockScreen> createState() => _WarehouseStockScreenState();
}

class _WarehouseStockScreenState extends State<WarehouseStockScreen> {
  List<Map<String, Object?>> _rows = const [];
  String _q = '';
  bool _nonZero = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await OrgService().warehouseStock(widget.warehouse.id, search: _q);
    if (mounted) setState(() => _rows = r);
  }

  @override
  Widget build(BuildContext context) {
    final showCost = AuthService().hasPermission(AppPermissions.viewCostProfit);
    final rows = _nonZero ? _rows.where((r) => ((r['qty'] as num?) ?? 0).abs() > 1e-6).toList() : _rows;
    final value = rows.fold(0.0, (s, r) => s + ((r['qty'] as num?) ?? 0) * ((r['cost_price'] as num?) ?? 0));
    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('أرصدة ${widget.warehouse.name}'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث عن مادة'),
                onChanged: (v) {
                  _q = v;
                  _load();
                },
              ),
            ),
            FilterChip(
              label: const Text('غير الصفرية فقط'),
              selected: _nonZero,
              onSelected: (v) => setState(() => _nonZero = v),
            ),
          ]),
        ),
        if (showCost)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Text('${rows.length} مادة — قيمة البضاعة بالكلفة: '),
              MoneyText(value, bold: true),
            ]),
          ),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = rows[i];
              final q = ((r['qty'] as num?) ?? 0).toDouble();
              return ListTile(
                tileColor: Colors.white,
                dense: true,
                title: Text('${r['name']}'),
                trailing: Text('${q % 1 == 0 ? q.toStringAsFixed(0) : q.toStringAsFixed(2)} ${r['unit'] ?? ''}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: q < 0 ? AccColors.red : AccColors.text)),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════ تحويل مخزني ═══════════════════════════════

class StockTransferScreen extends StatefulWidget {
  const StockTransferScreen({super.key, required this.warehouses});
  final List<Warehouse> warehouses;

  @override
  State<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _StockTransferScreenState extends State<StockTransferScreen> {
  final _svc = OrgService();
  late List<Warehouse> _active = widget.warehouses.where((w) => w.isActive).toList();
  late Warehouse _from = _active.first;
  late Warehouse _to = _active[1];
  List<Map<String, Object?>> _stock = const [];
  final Map<int, double> _qty = {};
  final _notes = TextEditingController();
  String _q = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadStock();
  }

  Future<void> _loadStock() async {
    final s = await _svc.warehouseStock(_from.id);
    if (mounted) {
      setState(() {
        _stock = s.where((r) => ((r['qty'] as num?) ?? 0) > 1e-6).toList();
        _qty.clear();
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _svc.createTransfer(
        fromWarehouseId: _from.id,
        toWarehouseId: _to.id,
        lines: [for (final e in _qty.entries) TransferLine(e.key, e.value)],
        notes: _notes.text.trim(),
        userId: AuthService().currentUser?.id,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _q.isEmpty ? _stock : _stock.where((r) => '${r['name']}'.contains(_q)).toList();
    final count = _qty.values.where((v) => v > 0).length;
    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('تحويل مخزني'),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AccColors.navy, padding: const EdgeInsets.all(16)),
          onPressed: _saving || count == 0 ? null : _save,
          icon: const Icon(Icons.check),
          label: Text('تنفيذ التحويل ($count مادة)'),
        ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: DropdownButtonFormField<Warehouse>(
                value: _from,
                decoration: const InputDecoration(labelText: 'من مخزن'),
                items: [for (final w in _active) DropdownMenuItem(value: w, child: Text(w.name))],
                onChanged: (w) {
                  if (w == null) return;
                  setState(() {
                    _from = w;
                    if (_to.id == w.id) _to = _active.firstWhere((x) => x.id != w.id);
                  });
                  _loadStock();
                },
              ),
            ),
            const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.arrow_back)),
            Expanded(
              child: DropdownButtonFormField<Warehouse>(
                value: _to,
                decoration: const InputDecoration(labelText: 'إلى مخزن'),
                items: [
                  for (final w in _active.where((w) => w.id != _from.id))
                    DropdownMenuItem(value: w, child: Text(w.name))
                ],
                onChanged: (w) => setState(() => _to = w ?? _to),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث'),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _notes, decoration: const InputDecoration(hintText: 'ملاحظات'))),
          ]),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = rows[i];
              final id = r['id'] as int;
              final avail = ((r['qty'] as num?) ?? 0).toDouble();
              return ListTile(
                tileColor: (_qty[id] ?? 0) > 0 ? AccColors.cyan.withOpacity(0.08) : Colors.white,
                title: Text('${r['name']}'),
                subtitle: Text('المتوفر: ${avail.toStringAsFixed(avail % 1 == 0 ? 0 : 2)} ${r['unit'] ?? ''}'),
                trailing: SizedBox(
                  width: 110,
                  child: TextField(
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(hintText: 'الكمية', isDense: true),
                    onChanged: (v) {
                      final q = double.tryParse(v) ?? 0;
                      setState(() {
                        if (q <= 0) {
                          _qty.remove(id);
                        } else {
                          _qty[id] = q > avail ? avail : q;
                        }
                      });
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
