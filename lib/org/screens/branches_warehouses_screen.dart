// lib/org/screens/branches_warehouses_screen.dart
//
// 🏢 الفروع والمخازن والتحويلات المخزنية — بالتصميم الموحّد (ErpPage).
//   • الفروع: بطاقة لكل فرع + «هذا فرعي».
//   • المخازن: بطاقة لكل مخزن ← «الأرصدة وتعديلها».
//   • أرصدة مخزن: بحث وفلاتر + «تعديل الرصيد» الذي يُنشئ مستند «تسوية جرد»
//     بالفرق — لا تُكتب الكمية مباشرة (كل حركة تمر عبر StockLedger وتُقيَّد).
//   • التحويل بين المخازن: من ← إلى، بكميات لا تتجاوز المتوفر.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../erp/erp_common.dart';
import '../../erp/erp_ui.dart';
import '../../erp/inventory/stock_count_screen.dart';
import '../../erp/inventory/stock_docs_screen.dart';
import '../../erp/inventory/stock_docs_service.dart';
import '../../erp/stock_helpers.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../widgets/formatters.dart';
import '../org_service.dart';

// ═══════════════════════════ عناصر مشتركة ═══════════════════════════

/// عرض البطاقة حسب عرض الشاشة (1 إلى 4 أعمدة).
double _cardWidth(double w, {double min = 340}) {
  final cols = (w / min).floor().clamp(1, 4).toInt();
  return (w - (cols - 1) * 14) / cols;
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.accent});
  final Widget child;
  final Color? accent;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accent == null ? ErpColors.border : accent!.withValues(alpha: 0.45),
            width: accent == null ? 1 : 1.4,
          ),
          boxShadow: [
            BoxShadow(color: ErpColors.navy.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4)),
          ],
        ),
        child: child,
      );
}

class _IconBox extends StatelessWidget {
  const _IconBox(this.icon, this.color, {this.size = 46});
  final IconData icon;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Icon(icon, color: color, size: size * 0.5),
      );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color, [this.icon]);
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.icon, this.text, {this.muted = false});
  final IconData icon;
  final String text;
  final bool muted;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 16, color: ErpColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: muted ? ErpColors.muted : ErpColors.text)),
          ),
        ]),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.icon = Icons.info_outline_rounded, this.color = ErpColors.blue});
  final String text;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.55, color: ErpColors.text))),
        ]),
      );
}

class _TabHeader extends StatelessWidget {
  const _TabHeader({required this.title, required this.subtitle, this.action});
  final String title;
  final String subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ErpColors.text)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 12.5, color: ErpColors.muted, height: 1.4)),
            ]),
          ),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ]),
      );
}

/// صندوق «من / إلى» لعرض مخزن في تحويل.
Widget _endpointBox(String label, String name, Color color, IconData icon) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w700)),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: ErpColors.text)),
          ]),
        ),
      ]),
    );

/// صندوق كمية كبير (الرصيد الحالي / بعد التعديل).
Widget _qtyBox(String label, double v, String unit, Color color) => AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(children: [
        Text(label, style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(fmtQty(v), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
        ),
        Text(unit.isEmpty ? ' ' : unit, style: const TextStyle(fontSize: 11.5, color: ErpColors.muted)),
      ]),
    );

/// حقل نصي بأيقونة داخل الحوارات.
Widget _field(TextEditingController c, String label, IconData icon,
        {bool autofocus = false, int maxLines = 1, TextInputType? keyboard}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        autofocus: autofocus,
        minLines: 1,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20)),
      ),
    );

// ═══════════════════════════ الشاشة الرئيسية ═══════════════════════════

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
  bool _loading = true;

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
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e);
      }
    }
  }

  String _branchName(int id) {
    for (final b in _branches) {
      if (b.id == id) return b.name;
    }
    return '—';
  }

  int _defaultBranchId() {
    for (final b in _branches) {
      if (b.isCurrent) return b.id;
    }
    return _branches.isEmpty ? 1 : _branches.first.id;
  }

  // ───────────────────────── الفروع ─────────────────────────

  Future<void> _editBranch([Branch? b]) async {
    if (!requirePermission(context, AppPermissions.manageBranches)) return;
    final name = TextEditingController(text: b?.name ?? '');
    final address = TextEditingController(text: b?.address ?? '');
    final phone = TextEditingController(text: b?.phone ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ErpDialog(
        title: b == null ? 'فرع جديد' : 'تعديل الفرع',
        subtitle: b == null ? 'موقع عمل له حاسبته وشبكته — تتزامن الفروع عبر الإنترنت' : b.name,
        icon: Icons.storefront_rounded,
        width: 460,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(name, 'اسم الفرع *', Icons.badge_outlined, autofocus: true),
            _field(address, 'العنوان', Icons.place_outlined),
            _field(phone, 'الهاتف', Icons.phone_outlined, keyboard: TextInputType.phone),
            if (b != null)
              _Note('رمز الفرع ${b.code} ثابت لأنه يُستعمل في التزامن بين الفروع.',
                  icon: Icons.tag_rounded, color: ErpColors.muted),
          ],
        ),
        actions: erpDialogActions(ctx,
            ok: b == null ? 'إضافة الفرع' : 'حفظ التعديل', icon: b == null ? Icons.add_rounded : Icons.check_rounded),
      ),
    );
    if (ok != true) return;
    try {
      await _svc.saveBranch(id: b?.id, name: name.text.trim(), address: address.text.trim(), phone: phone.text.trim());
      if (!mounted) return;
      showOk(context, b == null ? 'أُضيف الفرع «${name.text.trim()}»' : 'حُفظ الفرع');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _setCurrent(Branch b) async {
    if (!requirePermission(context, AppPermissions.manageBranches)) return;
    final ok = await confirmDialog(
      context,
      'هذا فرعي',
      'سيُعلَّم «${b.name}» على أنه الفرع الذي تعمل عليه هذه الحاسبة.',
      ok: 'تأكيد',
    );
    if (!ok) return;
    try {
      await _svc.setCurrentBranch(b.id);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  // ───────────────────────── المخازن ─────────────────────────

  Future<void> _editWarehouse([Warehouse? w]) async {
    if (!requirePermission(context, AppPermissions.manageBranches)) return;
    final name = TextEditingController(text: w?.name ?? '');
    final notes = TextEditingController(text: w?.notes ?? '');
    int branchId = w?.branchId ?? _defaultBranchId();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => ErpDialog(
          title: w == null ? 'مخزن جديد' : 'تعديل المخزن',
          subtitle: w == null ? 'مكان تُحفظ فيه البضاعة ولكلٍّ أرصدته الخاصة' : w.name,
          icon: Icons.warehouse_rounded,
          color: ErpColors.blue,
          width: 500,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(name, 'اسم المخزن *', Icons.warehouse_outlined, autofocus: true),
              if (_branches.length > 1) ...[
                const Text('يتبع الفرع',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ErpColors.text)),
                const SizedBox(height: 8),
                if (_branches.length <= 6)
                  LayoutBuilder(builder: (context, c) {
                    final tw = (c.maxWidth - 10) / 2;
                    return Wrap(spacing: 10, runSpacing: 10, children: [
                      for (final b in _branches)
                        ChoiceTile(
                          title: b.name,
                          subtitle: b.isCurrent ? 'هذا الفرع' : null,
                          icon: Icons.storefront_rounded,
                          color: ErpColors.blue,
                          dense: true,
                          width: tw,
                          selected: branchId == b.id,
                          onTap: () => setD(() => branchId = b.id),
                        ),
                    ]);
                  })
                else
                  DropdownButtonFormField<int>(
                    initialValue: branchId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الفرع', prefixIcon: Icon(Icons.storefront_outlined)),
                    items: [for (final b in _branches) DropdownMenuItem(value: b.id, child: Text(b.name))],
                    onChanged: (v) => setD(() => branchId = v ?? branchId),
                  ),
                const SizedBox(height: 14),
              ] else if (_branches.length == 1) ...[
                _InfoLine(Icons.storefront_outlined, 'يتبع الفرع: ${_branches.first.name}'),
                const SizedBox(height: 8),
              ],
              _field(notes, 'ملاحظات (اختياري) — مثال: المستودع الخلفي', Icons.notes_rounded, maxLines: 3),
              if (w == null)
                const _Note(
                  'يبدأ المخزن الجديد فارغاً. أدخل بضاعته بـ«تحويل» من مخزن آخر، أو «سند إدخال»، أو «بضاعة أول المدة».',
                  icon: Icons.lightbulb_outline_rounded,
                  color: ErpColors.green,
                )
              else if (w.isDefault)
                const _Note('هذا هو المخزن الرئيسي: تُخصم منه المبيعات افتراضياً ولا يمكن إيقافه.',
                    icon: Icons.star_rounded, color: ErpColors.gold),
            ],
          ),
          actions: erpDialogActions(ctx,
              ok: w == null ? 'إضافة المخزن' : 'حفظ التعديل',
              color: ErpColors.blue,
              icon: w == null ? Icons.add_rounded : Icons.check_rounded),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _svc.saveWarehouse(id: w?.id, name: name.text.trim(), branchId: branchId, notes: notes.text.trim());
      if (!mounted) return;
      showOk(context, w == null ? 'أُضيف المخزن «${name.text.trim()}»' : 'حُفظ المخزن');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleWarehouse(Warehouse w) async {
    if (!requirePermission(context, AppPermissions.manageBranches)) return;
    if (w.isActive) {
      final ok = await confirmDialog(
        context,
        'إيقاف «${w.name}»؟',
        'لن يظهر المخزن في الاختيارات بعد الإيقاف. يجب أن يكون فارغاً — حوّل بضاعته أولاً إن وُجدت.',
        ok: 'إيقاف',
        color: ErpColors.orange,
      );
      if (!ok) return;
    }
    try {
      await _svc.setWarehouseActive(w.id, !w.isActive);
      if (!mounted) return;
      showOk(context, w.isActive ? 'أُوقف المخزن «${w.name}»' : 'فُعِّل المخزن «${w.name}»');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _openStock(Warehouse w) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => WarehouseStockScreen(warehouse: w, warehouses: _warehouses)));
    if (mounted) _load();
  }

  // ───────────────────────── التحويلات ─────────────────────────

  Future<void> _newTransfer() async {
    if (!requirePermission(context, AppPermissions.stockTransfer)) return;
    if (_warehouses.where((w) => w.isActive).length < 2) {
      showError(context, 'التحويل يحتاج مخزنين فعّالين — أضف مخزناً ثانياً من تبويب «المخازن»');
      return;
    }
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => StockTransferScreen(warehouses: _warehouses)));
    if (ok == true && mounted) {
      showOk(context, 'تم تنفيذ التحويل');
      _load();
    }
  }

  Future<void> _showTransfer(Map<String, Object?> t) async {
    List<Map<String, Object?>> items;
    try {
      items = await _svc.transferItems(t['id'] as int);
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    final date = DateTime.tryParse('${t['transfer_date']}');
    final notes = ((t['notes'] as String?) ?? '').trim();
    final sub = [if (date != null) fmtDate(date), if (notes.isNotEmpty) notes].join(' • ');
    await showDialog<void>(
      context: context,
      builder: (ctx) => ErpDialog(
        title: 'تحويل رقم ${t['transfer_number']}',
        subtitle: sub.isEmpty ? null : sub,
        icon: Icons.swap_horiz_rounded,
        color: ErpColors.blue,
        width: 520,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: _endpointBox('من', '${t['from_name']}', ErpColors.red, Icons.logout_rounded)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded, color: ErpColors.muted),
              ),
              Expanded(child: _endpointBox('إلى', '${t['to_name']}', ErpColors.green, Icons.login_rounded)),
            ]),
            const SizedBox(height: 16),
            Text('المواد المحوّلة (${fmtQty(items.length)})',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ErpColors.border),
              ),
              child: Column(children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      Expanded(child: Text('${items[i]['name']}', style: const TextStyle(fontSize: 13.5))),
                      Text('${fmtQty(d0(items[i]['quantity']))} ${items[i]['unit'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: ErpColors.navy)),
                    ]),
                  ),
                ],
              ]),
            ),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
      ),
    );
  }

  // ───────────────────────── البناء ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final font = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    Tab tab(IconData icon, String text, int n) => Tab(
          height: 38,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(text),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: ErpColors.cyan.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(fmtQty(n), style: const TextStyle(fontSize: 11.5)),
            ),
          ]),
        );
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: ErpPage(
        title: 'الفروع والمخازن',
        subtitle: 'أماكن العمل، المخازن وأرصدتها، والتحويل بينها',
        icon: Icons.domain_rounded,
        actions: [IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
        headerExtra: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: TabBar(
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            splashBorderRadius: BorderRadius.circular(10),
            labelColor: ErpColors.navy,
            unselectedLabelColor: Colors.white,
            labelStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.w800, fontSize: 14),
            unselectedLabelStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.w600, fontSize: 14),
            tabs: [
              tab(Icons.storefront_rounded, 'الفروع', _branches.length),
              tab(Icons.warehouse_rounded, 'المخازن', _warehouses.length),
              tab(Icons.swap_horiz_rounded, 'التحويلات', _transfers.length),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [_branchesTab(), _warehousesTab(), _transfersTab()]),
      ),
    );
  }

  Widget _branchesTab() => LayoutBuilder(builder: (context, c) {
        final cw = _cardWidth(c.maxWidth - 32);
        return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          _TabHeader(
            title: 'الفروع',
            subtitle: 'كل فرع موقع عمل له حاسبة سيرفر على شبكته — تتزامن الفروع عبر الإنترنت',
            action: FilledButton.icon(
              onPressed: () => _editBranch(),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('فرع جديد'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _Note('اضغط «هذا فرعي» على الفرع الذي تعمل عليه هذه الحاسبة.', icon: Icons.push_pin_outlined),
          ),
          const SizedBox(height: 14),
          if (_branches.isEmpty)
            const EmptyState('لا توجد فروع بعد', icon: Icons.storefront_outlined)
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 14, runSpacing: 14, children: [for (final b in _branches) _branchCard(b, cw)]),
            ),
        ]);
      });

  Widget _branchCard(Branch b, double width) {
    final whCount = _warehouses.where((w) => w.branchId == b.id).length;
    final color = b.isCurrent ? ErpColors.green : ErpColors.navy;
    return SizedBox(
      width: width,
      child: _Card(
        accent: b.isCurrent ? ErpColors.green : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _IconBox(Icons.storefront_rounded, color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ErpColors.text)),
                const SizedBox(height: 2),
                Text('رمز ${b.code}', style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
              ]),
            ),
            if (b.isCurrent) const _Badge('هذا الفرع', ErpColors.green, Icons.check_circle_rounded),
          ]),
          const SizedBox(height: 12),
          _InfoLine(Icons.place_outlined, (b.address ?? '').trim().isEmpty ? 'بلا عنوان' : b.address!.trim(),
              muted: (b.address ?? '').trim().isEmpty),
          _InfoLine(Icons.phone_outlined, (b.phone ?? '').trim().isEmpty ? 'بلا هاتف' : b.phone!.trim(),
              muted: (b.phone ?? '').trim().isEmpty),
          _InfoLine(Icons.warehouse_outlined, whCount == 0 ? 'لا مخازن بعد' : '${fmtQty(whCount)} مخزن'),
          const Divider(height: 22),
          Row(children: [
            if (!b.isCurrent)
              TextButton.icon(
                onPressed: () => _setCurrent(b),
                icon: const Icon(Icons.push_pin_outlined, size: 18),
                label: const Text('هذا فرعي'),
              ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => _editBranch(b),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('تعديل'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _warehousesTab() => LayoutBuilder(builder: (context, c) {
        final cw = _cardWidth(c.maxWidth - 32);
        final active = _warehouses.where((w) => w.isActive).length;
        return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          _TabHeader(
            title: 'المخازن',
            subtitle: '${fmtQty(active)} فعّال من ${fmtQty(_warehouses.length)} — افتح «الأرصدة» لرؤية الكميات وتعديلها',
            action: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: ErpColors.blue),
              onPressed: () => _editWarehouse(),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('مخزن جديد'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _Note(
              'الأرصدة لا تُكتب يدوياً حفاظاً على صحة الحسابات: تتغيّر بالفواتير وسندات الإدخال والإخراج والجرد والتحويل. '
              'ولتصحيح كمية مادة افتح «الأرصدة» ← «تعديل الرصيد»، فيُسجَّل الفرق تلقائياً كمستند «تسوية جرد».',
              icon: Icons.verified_user_outlined,
              color: ErpColors.green,
            ),
          ),
          const SizedBox(height: 14),
          if (_warehouses.isEmpty)
            const EmptyState('لا توجد مخازن بعد', icon: Icons.warehouse_outlined)
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 14, runSpacing: 14, children: [for (final w in _warehouses) _warehouseCard(w, cw)]),
            ),
        ]);
      });

  Widget _warehouseCard(Warehouse w, double width) {
    final color = !w.isActive ? ErpColors.muted : (w.isDefault ? ErpColors.gold : ErpColors.blue);
    final notes = (w.notes ?? '').trim();
    return SizedBox(
      width: width,
      child: _Card(
        accent: w.isDefault ? ErpColors.gold : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _IconBox(w.isDefault ? Icons.home_work_rounded : Icons.warehouse_rounded, color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: w.isActive ? ErpColors.text : ErpColors.muted)),
                const SizedBox(height: 2),
                Text('رمز ${w.code}', style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
              ]),
            ),
            if (w.isDefault)
              const _Badge('الرئيسي', ErpColors.gold, Icons.star_rounded)
            else if (!w.isActive)
              const _Badge('موقوف', ErpColors.muted, Icons.pause_circle_rounded)
            else
              const _Badge('فعّال', ErpColors.green, Icons.check_circle_rounded),
          ]),
          const SizedBox(height: 12),
          _InfoLine(Icons.storefront_outlined, 'الفرع: ${_branchName(w.branchId)}'),
          if (w.isDefault) const _InfoLine(Icons.point_of_sale_rounded, 'تُخصم منه المبيعات افتراضياً'),
          if (notes.isNotEmpty) _InfoLine(Icons.notes_rounded, notes, muted: true),
          const Divider(height: 22),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: ErpColors.blue.withValues(alpha: 0.10),
                  foregroundColor: ErpColors.blue,
                  elevation: 0,
                ),
                onPressed: () => _openStock(w),
                icon: const Icon(Icons.inventory_2_outlined, size: 19),
                label: const Text('الأرصدة وتعديلها'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'تعديل البيانات',
              onPressed: () => _editWarehouse(w),
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
            if (!w.isDefault) ...[
              const SizedBox(width: 4),
              IconButton.outlined(
                tooltip: w.isActive ? 'إيقاف المخزن' : 'تفعيل المخزن',
                onPressed: () => _toggleWarehouse(w),
                icon: Icon(w.isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 20, color: w.isActive ? ErpColors.orange : ErpColors.green),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  Widget _transfersTab() => ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        _TabHeader(
          title: 'التحويلات',
          subtitle: 'نقل البضاعة بين المخازن — لا يغيّر المخزون الكلي ولا قيمته',
          action: FilledButton.icon(
            onPressed: _newTransfer,
            icon: const Icon(Icons.swap_horiz_rounded, size: 20),
            label: const Text('تحويل جديد'),
          ),
        ),
        if (_transfers.isEmpty)
          const EmptyState('لا توجد تحويلات بعد\nاضغط «تحويل جديد» لنقل بضاعة من مخزن إلى آخر',
              icon: Icons.swap_horiz_rounded)
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: Colors.white,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: ErpColors.border),
              ),
              child: Column(children: [
                for (var i = 0; i < _transfers.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _transferRow(_transfers[i]),
                ],
              ]),
            ),
          ),
      ]);

  Widget _transferRow(Map<String, Object?> t) {
    final date = DateTime.tryParse('${t['transfer_date']}');
    final notes = ((t['notes'] as String?) ?? '').trim();
    return InkWell(
      onTap: () => _showTransfer(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          const _IconBox(Icons.swap_horiz_rounded, ErpColors.blue, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('تحويل رقم ${t['transfer_number']}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                const SizedBox(width: 8),
                if (date != null)
                  Text(fmtDate(date), style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _Badge('${t['from_name']}', ErpColors.red, Icons.logout_rounded),
                const Icon(Icons.arrow_forward_rounded, size: 16, color: ErpColors.muted),
                _Badge('${t['to_name']}', ErpColors.green, Icons.login_rounded),
                if (notes.isNotEmpty)
                  Text(notes,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmtQty(d0(t['items'])),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: ErpColors.navy)),
            const Text('مادة', style: TextStyle(fontSize: 11.5, color: ErpColors.muted)),
          ]),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════ أرصدة مخزن ═══════════════════════════════

class WarehouseStockScreen extends StatefulWidget {
  const WarehouseStockScreen({super.key, required this.warehouse, this.warehouses = const []});
  final Warehouse warehouse;

  /// كل المخازن (لاختصار «تحويل منه»).
  final List<Warehouse> warehouses;

  @override
  State<WarehouseStockScreen> createState() => _WarehouseStockScreenState();
}

class _WarehouseStockScreenState extends State<WarehouseStockScreen> {
  List<Map<String, Object?>> _rows = const [];
  String _q = '';
  String _filter = 'nonzero'; // all | nonzero | negative | zero
  bool _loading = true;
  int _seq = 0;

  static const _filters = [
    ('nonzero', 'لها رصيد'),
    ('negative', 'سالبة'),
    ('zero', 'صفرية'),
    ('all', 'الكل'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final my = ++_seq;
    try {
      final r = await OrgService().warehouseStock(widget.warehouse.id, search: _q);
      if (mounted && my == _seq) {
        setState(() {
          _rows = r;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e);
      }
    }
  }

  Future<void> _openDoc(String type) async {
    if (!requirePermission(context, AppPermissions.inventoryDocs)) return;
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => StockDocEditorScreen(docType: type, warehouseId: widget.warehouse.id)));
    if (mounted) _load();
  }

  Future<void> _openCount() async {
    if (!requirePermission(context, AppPermissions.inventoryDocs)) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const StockCountsScreen()));
    if (mounted) _load();
  }

  Future<void> _openTransfer() async {
    if (!requirePermission(context, AppPermissions.stockTransfer)) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => StockTransferScreen(warehouses: widget.warehouses, fromWarehouseId: widget.warehouse.id)),
    );
    if (ok == true && mounted) {
      showOk(context, 'تم تنفيذ التحويل');
      _load();
    }
  }

  /// تعديل رصيد مادة: يُنشئ مستند «تسوية جرد» بالفرق (لا تعديل مباشر للكمية).
  Future<void> _adjust(Map<String, Object?> r) async {
    if (!requirePermission(context, AppPermissions.inventoryDocs)) return;
    final showCost = AuthService().hasPermission(AppPermissions.viewCostProfit);
    final id = r['id'] as int;
    final name = '${r['name']}';
    final unit = '${r['unit'] ?? ''}';
    final cur = d0(r['qty']);
    final cost = d0(r['cost_price']);
    final qty = TextEditingController();
    final reason = TextEditingController();
    var mode = 'set'; // set = الكمية الفعلية | add = زيادة | sub = نقصان
    double targetOf() {
      final v = parseMoney(qty.text);
      if (v == null) return cur;
      return switch (mode) { 'add' => cur + v, 'sub' => cur - v, _ => v };
    }

    const modes = [
      ('set', 'الكمية الفعلية', Icons.edit_note_rounded, ErpColors.blue),
      ('add', 'زيادة', Icons.add_rounded, ErpColors.green),
      ('sub', 'نقصان', Icons.remove_rounded, ErpColors.red),
    ];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final target = targetOf();
        final diff = target - cur;
        final changed = diff.abs() > 1e-9;
        final invalid = target < -1e-9;
        final dColor = !changed ? ErpColors.navy : (diff > 0 ? ErpColors.green : ErpColors.red);
        return ErpDialog(
          title: 'تعديل رصيد مادة',
          subtitle: '$name • ${widget.warehouse.name}',
          icon: Icons.tune_rounded,
          color: ErpColors.blue,
          width: 520,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: _qtyBox('الرصيد الحالي', cur, unit, ErpColors.navy)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded, color: ErpColors.muted),
                ),
                Expanded(child: _qtyBox('بعد التعديل', target, unit, invalid ? ErpColors.red : dColor)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                for (final m in modes) ...[
                  if (m.$1 != 'set') const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceTile(
                      title: m.$2,
                      icon: m.$3,
                      color: m.$4,
                      dense: true,
                      selected: mode == m.$1,
                      onTap: () => setD(() {
                        mode = m.$1;
                        qty.clear();
                      }),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 12),
              MoneyField(
                controller: qty,
                label: switch (mode) {
                  'add' => 'الكمية المراد إضافتها',
                  'sub' => 'الكمية المراد إنقاصها',
                  _ => 'الكمية الموجودة فعلاً على الرف',
                },
                autofocus: true,
                onChanged: (_) => setD(() {}),
              ),
              const SizedBox(height: 12),
              TextBox(controller: reason, label: 'السبب (اختياري) — تالف، خطأ إدخال، عدّ سريع…'),
              const SizedBox(height: 14),
              _Note(
                invalid
                    ? 'الرصيد بعد التعديل لا يكون سالباً.'
                    : !changed
                        ? 'اكتب الكمية لترى أثر التعديل قبل اعتماده.'
                        : 'سيُسجَّل مستند «تسوية جرد» بفرق ${diff > 0 ? '+' : '−'}${fmtQty(diff.abs())} $unit'
                            '${showCost ? ' (قيمته ${fmtMoney(diff.abs() * cost)})' : ''}، '
                            'ويظهر في «سجل المستندات» مع قيده المحاسبي.',
                icon: invalid ? Icons.error_outline_rounded : Icons.receipt_long_rounded,
                color: invalid ? ErpColors.red : (changed ? dColor : ErpColors.muted),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: ErpColors.blue),
              onPressed: changed && !invalid ? () => Navigator.pop(ctx, true) : null,
              icon: const Icon(Icons.check_rounded, size: 19),
              label: const Text('اعتماد التعديل'),
            ),
          ],
        );
      }),
    );
    if (ok != true || !mounted) return;
    final target = targetOf();
    if (target < -1e-9) return;
    try {
      final db = await erpDb();
      // «الكمية الفعلية» تُقارَن بالرصيد لحظة الحفظ (قد تكون بيعت كمية أثناء فتح النافذة).
      final now = mode == 'set' ? await ErpStock.available(db, id, warehouseId: widget.warehouse.id) : cur;
      final diff = target - now;
      if (diff.abs() <= 1e-9) {
        if (mounted) showOk(context, 'الرصيد مطابق — لا يوجد فرق لتسجيله');
        return;
      }
      final p = await ErpStock.byId(db, id);
      await StockDocsService().create(
        docType: 'count',
        date: DateTime.now(),
        warehouseId: widget.warehouse.id,
        reason: reason.text.trim().isEmpty ? 'تعديل رصيد' : reason.text.trim(),
        notes: 'تعديل رصيد «$name» في ${widget.warehouse.name}: ${fmtQty(now)} ← ${fmtQty(now + diff)}',
        lines: [
          StockDocLine(
            productId: id,
            name: name,
            baseQty: diff,
            unitCost: p?.cost ?? cost,
            warehouseId: widget.warehouse.id,
          ),
        ],
        allowNegative: true,
      );
      if (!mounted) return;
      showOk(context, 'أصبح رصيد «$name» ${fmtQty(now + diff)} $unit');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showCost = AuthService().hasPermission(AppPermissions.viewCostProfit);
    final nonZero = _rows.where((r) => d0(r['qty']).abs() > 1e-6).toList();
    final negatives = _rows.where((r) => d0(r['qty']) < -1e-6).length;
    final value = nonZero.fold<double>(0, (s, r) => s + d0(r['qty']) * d0(r['cost_price']));
    final rows = switch (_filter) {
      'all' => _rows,
      'negative' => _rows.where((r) => d0(r['qty']) < -1e-6).toList(),
      'zero' => _rows.where((r) => d0(r['qty']).abs() <= 1e-6).toList(),
      _ => nonZero,
    };
    final canTransfer = widget.warehouses.where((w) => w.isActive).length > 1;

    return ErpPage(
      title: 'أرصدة ${widget.warehouse.name}',
      subtitle: widget.warehouse.isDefault
          ? 'المخزن الرئيسي — الكميات الحالية وتعديلها'
          : 'الكميات الحالية في هذا المخزن وتعديلها',
      icon: Icons.inventory_2_rounded,
      actions: [IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      StatCard(
                        label: 'مواد لها رصيد',
                        value: fmtQty(nonZero.length),
                        icon: Icons.category_rounded,
                        color: ErpColors.blue,
                        onTap: () => setState(() => _filter = 'nonzero'),
                      ),
                      if (showCost)
                        StatCard(
                          label: 'قيمة البضاعة بالكلفة',
                          value: fmtMoney(value),
                          icon: Icons.payments_rounded,
                          color: ErpColors.green,
                        ),
                      StatCard(
                        label: 'أرصدة سالبة',
                        value: fmtQty(negatives),
                        icon: Icons.warning_amber_rounded,
                        color: negatives > 0 ? ErpColors.red : ErpColors.muted,
                        hint: negatives > 0 ? 'اضغط لعرضها وتصحيحها' : 'لا يوجد',
                        onTap: () => setState(() => _filter = 'negative'),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      _QuickAction('سند إدخال', 'إضافة بضاعة لهذا المخزن', Icons.move_to_inbox_rounded,
                          ErpColors.green, () => _openDoc('in')),
                      _QuickAction('سند إخراج', 'تالف، هدايا، استهلاك داخلي', Icons.outbox_rounded, ErpColors.red,
                          () => _openDoc('out')),
                      _QuickAction('جرد فعلي', 'عدّ الرفوف وتسوية كل الفروقات', Icons.fact_check_rounded,
                          ErpColors.orange, _openCount),
                      if (canTransfer)
                        _QuickAction('تحويل منه', 'نقل بضاعة إلى مخزن آخر', Icons.swap_horiz_rounded,
                            ErpColors.purple, _openTransfer),
                    ]),
                    const SizedBox(height: 14),
                    const _Note(
                      'لتصحيح كمية مادة واحدة اضغط «تعديل الرصيد» بجانبها: يُسجَّل الفرق تلقائياً كمستند «تسوية جرد» '
                      'مع قيده المحاسبي، ولا تُكتب الكمية مباشرة. ولتصحيح مواد كثيرة استعمل «الجرد الفعلي».',
                      icon: Icons.tune_rounded,
                    ),
                    const SizedBox(height: 14),
                    SearchBox(
                      hint: 'بحث عن مادة بالاسم',
                      onChanged: (v) {
                        _q = v;
                        _load();
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final f in _filters)
                        ChoiceChip(
                          label: Text(f.$2),
                          selected: _filter == f.$1,
                          onSelected: (_) => setState(() => _filter = f.$1),
                        ),
                    ]),
                  ]),
                ),
              ),
              if (rows.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    _q.trim().isNotEmpty
                        ? 'لا توجد مواد تطابق «${_q.trim()}»'
                        : _filter == 'negative'
                            ? 'لا توجد أرصدة سالبة 👍'
                            : 'لا توجد مواد في هذا العرض',
                    icon: Icons.inventory_2_outlined,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => _row(rows[i], showCost),
                  ),
                ),
            ]),
    );
  }

  Widget _row(Map<String, Object?> r, bool showCost) {
    final q = d0(r['qty']);
    final unit = '${r['unit'] ?? ''}';
    final cost = d0(r['cost_price']);
    final negative = q < -1e-6;
    final zero = q.abs() <= 1e-6;
    final color = negative ? ErpColors.red : (zero ? ErpColors.muted : ErpColors.text);
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: negative ? ErpColors.red.withValues(alpha: 0.35) : ErpColors.border),
      ),
      child: InkWell(
        onTap: () => _adjust(r),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r['name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: ErpColors.text)),
                if (showCost)
                  Text('الكلفة ${fmtMoney(cost)} • القيمة ${fmtMoney(q * cost)}',
                      style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
              ]),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(fmtQty(q), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
              if (unit.isNotEmpty) Text(unit, style: const TextStyle(fontSize: 11.5, color: ErpColors.muted)),
            ]),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: negative ? ErpColors.red : ErpColors.blue,
              ),
              onPressed: () => _adjust(r),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('تعديل الرصيد'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// زر اختصار بأيقونة وشرح سطر.
class _QuickAction extends StatelessWidget {
  const _QuickAction(this.title, this.subtitle, this.icon, this.color, this.onTap);
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 232,
        child: Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: ErpColors.border),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                _IconBox(icon, color, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: ErpColors.muted)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
}

// ═══════════════════════════════ تحويل مخزني ═══════════════════════════════

class StockTransferScreen extends StatefulWidget {
  const StockTransferScreen({super.key, required this.warehouses, this.fromWarehouseId});
  final List<Warehouse> warehouses;

  /// المخزن المصدر المختار مسبقاً (اختياري).
  final int? fromWarehouseId;

  @override
  State<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _StockTransferScreenState extends State<StockTransferScreen> {
  final _svc = OrgService();
  late final List<Warehouse> _active = widget.warehouses.where((w) => w.isActive).toList();
  late Warehouse _from = _active.firstWhere((w) => w.id == widget.fromWarehouseId, orElse: () => _active.first);
  late Warehouse _to = _active.firstWhere((w) => w.id != _from.id);
  List<Map<String, Object?>> _stock = const [];
  final Map<int, double> _avail = {};
  final Map<int, double> _qty = {};
  final Map<int, TextEditingController> _ctrls = {};
  final _notes = TextEditingController();
  String _q = '';
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStock();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  TextEditingController _ctrl(int id) => _ctrls.putIfAbsent(id, () => TextEditingController());

  Future<void> _loadStock() async {
    try {
      final s = await _svc.warehouseStock(_from.id);
      if (!mounted) return;
      setState(() {
        _stock = s.where((r) => d0(r['qty']) > 1e-6).toList();
        _avail
          ..clear()
          ..addAll({for (final r in _stock) r['id'] as int: d0(r['qty'])});
        _qty.clear();
        for (final c in _ctrls.values) {
          c.clear();
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e);
      }
    }
  }

  void _setFrom(Warehouse w) {
    if (w.id == _from.id) return;
    setState(() {
      _from = w;
      if (_to.id == w.id) _to = _active.firstWhere((x) => x.id != w.id);
      _loading = true;
    });
    _loadStock();
  }

  void _swap() {
    setState(() {
      final t = _from;
      _from = _to;
      _to = t;
      _loading = true;
    });
    _loadStock();
  }

  void _setQty(int id, double v, {bool setText = false}) {
    setState(() {
      if (v <= 0) {
        _qty.remove(id);
      } else {
        _qty[id] = v;
      }
      if (setText) _ctrl(id).text = v <= 0 ? '' : fmtQty(v);
    });
  }

  Future<void> _save() async {
    final lines = [
      for (final e in _qty.entries)
        if (e.value > 0) TransferLine(e.key, e.value),
    ];
    if (lines.isEmpty) return;
    final ok = await confirmDialog(
      context,
      'تنفيذ التحويل؟',
      'نقل ${fmtQty(lines.length)} مادة من «${_from.name}» إلى «${_to.name}».\n'
          'المخزون الكلي وقيمته لا يتغيّران — تتغيّر أرصدة المخزنين فقط.',
      ok: 'تنفيذ',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await _svc.createTransfer(
        fromWarehouseId: _from.id,
        toWarehouseId: _to.id,
        lines: lines,
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
    final picked = _qty.entries.where((e) => e.value > 0).toList();
    final over = picked.any((e) => e.value > (_avail[e.key] ?? 0) + 1e-6);
    return ErpPage(
      title: 'تحويل بين المخازن',
      subtitle: 'نقل بضاعة من مخزن إلى آخر — المخزون الكلي وقيمته لا يتغيّران',
      icon: Icons.swap_horiz_rounded,
      bottom: _bottomBar(picked.length, over),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _route(),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: SearchBox(
                    hint: 'بحث عن مادة في «${_from.name}»',
                    onChanged: (v) => setState(() => _q = v.trim()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _notes,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات التحويل (اختياري)',
                      prefixIcon: Icon(Icons.notes_rounded, size: 20),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Text(
                _loading
                    ? 'جارٍ تحميل أرصدة «${_from.name}»…'
                    : '${fmtQty(_stock.length)} مادة متوفرة في «${_from.name}» — اكتب الكمية المراد نقلها أو اضغط «الكل».',
                style: const TextStyle(fontSize: 12.5, color: ErpColors.muted),
              ),
            ]),
          ),
        ),
        if (_loading)
          const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
        else if (rows.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              _stock.isEmpty ? 'لا توجد بضاعة في «${_from.name}» لتحويلها' : 'لا توجد مواد تطابق البحث',
              icon: Icons.inventory_2_outlined,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverList.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _line(rows[i]),
            ),
          ),
      ]),
    );
  }

  Widget _route() => LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 560;
        final from = _picker('من مخزن', _from, _active, ErpColors.red, Icons.logout_rounded, _setFrom);
        final to = _picker('إلى مخزن', _to, _active.where((w) => w.id != _from.id).toList(), ErpColors.green,
            Icons.login_rounded, (w) => setState(() => _to = w));
        final swap = IconButton(
          tooltip: 'عكس الاتجاه',
          style: IconButton.styleFrom(backgroundColor: ErpColors.navy, foregroundColor: Colors.white),
          onPressed: _loading || _saving ? null : _swap,
          icon: Icon(narrow ? Icons.swap_vert_rounded : Icons.swap_horiz_rounded),
        );
        if (narrow) {
          return Column(children: [from, Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: swap), to]);
        }
        return Row(children: [
          Expanded(child: from),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: swap),
          Expanded(child: to),
        ]);
      });

  Widget _picker(String label, Warehouse value, List<Warehouse> options, Color color, IconData icon,
          ValueChanged<Warehouse> onChanged) =>
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.4),
        ),
        child: Row(children: [
          _IconBox(icon, color, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: value.id,
                  isExpanded: true,
                  isDense: true,
                  borderRadius: BorderRadius.circular(12),
                  style: TextStyle(
                    fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: ErpColors.text,
                  ),
                  items: [
                    for (final w in options)
                      DropdownMenuItem(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: _saving
                      ? null
                      : (id) {
                          if (id == null) return;
                          onChanged(options.firstWhere((w) => w.id == id));
                        },
                ),
              ),
            ]),
          ),
        ]),
      );

  Widget _line(Map<String, Object?> r) {
    final id = r['id'] as int;
    final avail = d0(r['qty']);
    final unit = '${r['unit'] ?? ''}';
    final q = _qty[id] ?? 0;
    final over = q > avail + 1e-6;
    final sel = q > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: over
            ? ErpColors.red.withValues(alpha: 0.05)
            : sel
                ? ErpColors.blue.withValues(alpha: 0.05)
                : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: over
              ? ErpColors.red.withValues(alpha: 0.5)
              : sel
                  ? ErpColors.blue.withValues(alpha: 0.45)
                  : ErpColors.border,
          width: sel || over ? 1.4 : 1,
        ),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            Text(
              over ? 'أكثر من المتوفر (${fmtQty(avail)} $unit)' : 'المتوفر: ${fmtQty(avail)} $unit',
              style: TextStyle(
                fontSize: 12,
                color: over ? ErpColors.red : ErpColors.muted,
                fontWeight: over ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ]),
        ),
        TextButton(
          onPressed: _saving ? null : () => _setQty(id, avail, setText: true),
          child: const Text('الكل'),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 130,
          child: TextField(
            controller: _ctrl(id),
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'الكمية',
              isDense: true,
              suffixText: unit.isEmpty ? null : unit,
              suffixStyle: const TextStyle(fontSize: 11, color: ErpColors.muted),
            ),
            onChanged: (v) => _setQty(id, parseMoney(v) ?? 0),
          ),
        ),
        SizedBox(
          width: 40,
          child: sel
              ? IconButton(
                  tooltip: 'إلغاء هذه المادة',
                  onPressed: _saving ? null : () => _setQty(id, 0, setText: true),
                  icon: const Icon(Icons.close_rounded, size: 18, color: ErpColors.muted),
                )
              : null,
        ),
      ]),
    );
  }

  Widget _bottomBar(int count, bool over) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: ErpColors.border)),
          boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2))],
        ),
        child: SafeArea(
          top: false,
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(
                  over
                      ? 'بعض الكميات أكثر من المتوفر'
                      : count == 0
                          ? 'لم تُختر مواد بعد'
                          : '${fmtQty(count)} مادة للتحويل',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: over ? ErpColors.red : ErpColors.text),
                ),
                Text('من «${_from.name}» إلى «${_to.name}»',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: ErpColors.muted)),
              ]),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 22),
              ),
              onPressed: _saving || count == 0 || over ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded),
              label: const Text('تنفيذ التحويل'),
            ),
          ]),
        ),
      );
}
