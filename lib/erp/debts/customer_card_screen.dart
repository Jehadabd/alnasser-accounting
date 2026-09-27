// lib/erp/debts/customer_card_screen.dart
//
// 👤 بطاقة العميل الموسّعة — تصميم عصري: رأس بالصورة والرصيد، مؤشرات مالية،
// أقسام البيانات، وأزرار سريعة (وصل قبض، كشف حساب، مطابقة، استحقاق...).
// + دليل العملاء بالتصنيف والتصفية.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../models/app_user.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../report_export.dart';
import '../stock_helpers.dart';
import 'customer_ext_service.dart';
import 'customer_statement_screen.dart';
import 'debt_reports_screen.dart';
import 'due_items_screen.dart';
import 'receipt_screen.dart';
import 'statement_service.dart';

const List<String> weekDays = ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة'];

Future<String?> pickAndStoreImage(String prefix) async {
  final res = await FilePicker.platform.pickFiles(type: FileType.image);
  if (res == null || res.files.isEmpty || res.files.first.path == null) return null;
  final src = File(res.files.first.path!);
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}${Platform.pathSeparator}alnaser_customer_docs');
  if (!await dir.exists()) await dir.create(recursive: true);
  final ext = src.path.contains('.') ? src.path.substring(src.path.lastIndexOf('.')) : '.jpg';
  final dest = '${dir.path}${Platform.pathSeparator}${prefix}_${DateTime.now().millisecondsSinceEpoch}$ext';
  await src.copy(dest);
  return dest;
}

class CustomerCardScreen extends StatefulWidget {
  const CustomerCardScreen({super.key, required this.customerId});
  final int customerId;
  @override
  State<CustomerCardScreen> createState() => _CustomerCardScreenState();
}

class _CustomerCardScreenState extends State<CustomerCardScreen> {
  final _svc = CustomerExtService();
  Map<String, Object?>? _customer;
  CustomerExt? _ext;
  CustomerSummary? _sum;
  List<CustomerGroup> _groups = const [];
  Map<String, Object?>? _linkedSupplier;
  bool _saving = false;
  bool _dirty = false;

  final _code = TextEditingController();
  final _title = TextEditingController();
  final _region = TextEditingController();
  final _limit = TextEditingController();
  final _discount = TextEditingController();
  final _responsible = TextEditingController();
  final _idNumber = TextEditingController();
  final _notes2 = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await erpDb();
    final c = await db.query('customers', where: 'id = ?', whereArgs: [widget.customerId], limit: 1);
    final e = await _svc.get(widget.customerId);
    final s = await _svc.summary(widget.customerId);
    final g = await _svc.groups();
    final ls = await StatementService().linkedSupplier(widget.customerId);
    if (!mounted) return;
    setState(() {
      _customer = c.isEmpty ? null : c.first;
      _ext = e;
      _sum = s;
      _groups = g;
      _linkedSupplier = ls;
      _code.text = e.code ?? '';
      _title.text = e.title ?? '';
      _region.text = e.region ?? '';
      _limit.text = e.creditLimit == null ? '' : fmtMoney(e.creditLimit!);
      _discount.text = e.discountPercent == null ? '' : fmtQty(e.discountPercent!);
      _responsible.text = e.responsible ?? '';
      _idNumber.text = e.idNumber ?? '';
      _notes2.text = e.notes2 ?? '';
      _dirty = false;
    });
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    final e = _ext!;
    e.code = _code.text.trim();
    e.title = _title.text.trim();
    e.region = _region.text.trim();
    e.creditLimit = parseMoney(_limit.text);
    e.discountPercent = parseMoney(_discount.text);
    e.responsible = _responsible.text.trim();
    e.idNumber = _idNumber.text.trim();
    e.notes2 = _notes2.text.trim();
    setState(() => _saving = true);
    try {
      await _svc.save(e);
      if (mounted) showOk(context, 'حُفظت بطاقة العميل');
      await _load();
    } catch (err) {
      if (mounted) showError(context, err);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  PartyLite get _party => PartyLite(
      widget.customerId, (_customer?['name'] as String?) ?? '', _customer?['phone'] as String?, _sum?.balance ?? 0);

  void _open(Widget w, {String? permission}) {
    if (permission != null && !requirePermission(context, permission)) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => w)).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    if (_customer == null || _ext == null || _sum == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final s = _sum!;
    final e = _ext!;
    final limit = e.creditLimit ?? 0;
    final usage = limit > 0 ? (s.balance / limit) : 0.0;
    final name = '${e.title == null || e.title!.isEmpty ? '' : '${e.title} '}${_customer!['name']}';
    return ErpPage(
      title: 'بطاقة العميل',
      subtitle: name,
      icon: Icons.badge_outlined,
      actions: [
        if (_dirty)
          IconButton(tooltip: 'حفظ', icon: const Icon(Icons.save), onPressed: _saving ? null : _save),
      ],
      headerExtra: _hero(name, s, e, limit, usage),
      bottom: _dirty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: PrimaryButton(label: 'حفظ التعديلات', icon: Icons.save, busy: _saving, onPressed: _save),
              ),
            )
          : null,
      body: ListView(padding: const EdgeInsets.only(bottom: 30, top: 6), children: [
        _actions(),
        ErpSection(
          title: 'الملخص المالي',
          icon: Icons.insights,
          color: ErpColors.green,
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            StatCard(label: 'مجموع الديون', value: fmtMoney(s.totalDebts), icon: Icons.north_east, color: ErpColors.orange),
            StatCard(label: 'مجموع التسديدات', value: fmtMoney(s.totalPayments), icon: Icons.south_west, color: ErpColors.green),
            StatCard(
                label: 'نسبة التحصيل',
                value: '${s.collectionRatio.toStringAsFixed(1)}%',
                icon: Icons.speed,
                color: ErpColors.blue),
            StatCard(label: 'عدد الفواتير', value: '${s.invoicesCount}', icon: Icons.receipt, color: ErpColors.purple),
            StatCard(
                label: 'آخر تسديد',
                value: s.lastPaymentAmount == null ? '—' : fmtMoney(s.lastPaymentAmount!),
                hint: s.lastPaymentDate == null
                    ? null
                    : '${fmtDate(s.lastPaymentDate!)} (قبل ${DateTime.now().difference(s.lastPaymentDate!).inDays} يوم)',
                icon: Icons.event_available,
                color: ErpColors.navy),
            StatCard(
                label: 'استحقاقات مفتوحة',
                value: fmtMoney(s.openDueAmount),
                icon: Icons.event_note,
                color: ErpColors.gold,
                onTap: () => _open(DueItemsScreen(
                    partyType: 'customer', partyId: widget.customerId, partyName: '${_customer!['name']}'))),
            if (_linkedSupplier != null)
              StatCard(
                label: 'صافي مع حسابه كمورد',
                value: fmtMoney(s.balance - d0(_linkedSupplier!['total_debt_iqd'])),
                hint: 'له عندنا كمورد: ${fmtMoney(d0(_linkedSupplier!['total_debt_iqd']))}',
                icon: Icons.compare_arrows,
                color: ErpColors.cyan,
              ),
          ]),
        ),
        ErpSection(
          title: 'التعريف',
          icon: Icons.perm_identity,
          child: FieldGrid(children: [
            SizedBox(
              width: 200,
              child: Row(children: [
                Expanded(child: TextBox(controller: _code, label: 'رمز العميل', onChanged: (_) => _touch())),
                IconButton(
                  tooltip: 'رمز تلقائي',
                  icon: const Icon(Icons.auto_fix_high, color: ErpColors.cyan),
                  onPressed: () async {
                    _code.text = await _svc.suggestCode();
                    _touch();
                  },
                ),
              ]),
            ),
            TextBox(controller: _title, label: 'اللقب (السيد، الحاج...)', width: 180, onChanged: (_) => _touch()),
            InfoTile('الاسم', '${_customer!['name']}', width: 220),
            InfoTile('الهاتف', '${_customer!['phone'] ?? '—'}'),
            InfoTile('العنوان', '${_customer!['address'] ?? '—'}', width: 260),
          ]),
        ),
        ErpSection(
          title: 'التصنيف والمتابعة',
          icon: Icons.category_outlined,
          color: ErpColors.purple,
          child: FieldGrid(children: [
            SizedBox(
              width: 260,
              child: Row(children: [
                Expanded(
                  child: DropBox<int>(
                    label: 'المجموعة',
                    width: 210,
                    value: _groups.any((g) => g.id == e.groupId) ? e.groupId : null,
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text('— بلا —')),
                      for (final g in _groups) DropdownMenuItem(value: g.id, child: Text(g.name)),
                    ],
                    onChanged: (v) => setState(() {
                      e.groupId = v;
                      _dirty = true;
                    }),
                  ),
                ),
                IconButton(
                  tooltip: 'مجموعة جديدة',
                  icon: const Icon(Icons.add_circle_outline, color: ErpColors.purple),
                  onPressed: () async {
                    final n = await askText(context, 'مجموعة جديدة', label: 'اسم المجموعة');
                    if (n == null || n.isEmpty) return;
                    try {
                      final id = await _svc.addGroup(n);
                      final g = await _svc.groups();
                      setState(() {
                        _groups = g;
                        e.groupId = id;
                        _dirty = true;
                      });
                    } catch (err) {
                      if (mounted) showError(context, err);
                    }
                  },
                ),
              ]),
            ),
            TextBox(controller: _region, label: 'المنطقة', width: 180, onChanged: (_) => _touch()),
            TextBox(controller: _responsible, label: 'المسؤول / المندوب', width: 200, onChanged: (_) => _touch()),
            DropBox<String>(
              label: 'يوم التحصيل',
              width: 170,
              value: weekDays.contains(e.collectionDay) ? e.collectionDay : null,
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('— بلا —')),
                for (final d in weekDays) DropdownMenuItem(value: d, child: Text(d)),
              ],
              onChanged: (v) => setState(() {
                e.collectionDay = v;
                _dirty = true;
              }),
            ),
            DropBox<String>(
              label: 'مستوى السعر المعتاد',
              width: 190,
              value: priceLevelNames.contains(e.priceLevel) ? e.priceLevel : null,
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('— افتراضي —')),
                for (final p in priceLevelNames) DropdownMenuItem(value: p, child: Text(p)),
              ],
              onChanged: (v) => setState(() {
                e.priceLevel = v;
                _dirty = true;
              }),
            ),
          ]),
        ),
        ErpSection(
          title: 'شروط التعامل',
          icon: Icons.gavel,
          color: ErpColors.orange,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FieldGrid(children: [
              MoneyField(controller: _limit, label: 'سقف الدين (0 = بلا سقف)', width: 220, onChanged: (_) => _touch()),
              MoneyField(controller: _discount, label: 'نسبة الحسم الدائمة %', width: 190, onChanged: (_) => _touch()),
              SizedBox(
                width: 280,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: e.isBlocked,
                  activeColor: ErpColors.red,
                  title: const Text('إيقاف البيع الآجل لهذا العميل'),
                  onChanged: (v) => setState(() {
                    e.isBlocked = v;
                    _dirty = true;
                  }),
                ),
              ),
            ]),
            if (limit > 0) ...[
              const SizedBox(height: 10),
              Text('استهلاك السقف: ${(usage * 100).toStringAsFixed(0)}% — المتبقي ${fmtMoney(limit - s.balance)}',
                  style: TextStyle(color: usage > 1 ? ErpColors.red : ErpColors.muted)),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: usage.clamp(0.0, 1.0).toDouble(),
                minHeight: 8,
                color: usage > 1 ? ErpColors.red : (usage > 0.8 ? ErpColors.orange : ErpColors.green),
                backgroundColor: ErpColors.border,
                borderRadius: BorderRadius.circular(6),
              ),
            ],
          ]),
        ),
        ErpSection(
          title: 'الأرشيف (الهوية والصورة)',
          icon: Icons.photo_library_outlined,
          color: ErpColors.blue,
          child: FieldGrid(children: [
            TextBox(controller: _idNumber, label: 'رقم الهوية', width: 200, onChanged: (_) => _touch()),
            _imageBox('صورة الهوية', e.idImagePath, (p) => setState(() {
                  e.idImagePath = p;
                  _dirty = true;
                })),
            _imageBox('صورة العميل', e.photoPath, (p) => setState(() {
                  e.photoPath = p;
                  _dirty = true;
                })),
          ]),
        ),
        ErpSection(
          title: 'ملاحظات وربط',
          icon: Icons.sticky_note_2_outlined,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextBox(controller: _notes2, label: 'ملاحظات إضافية', maxLines: 3, onChanged: (_) => _touch()),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.link, color: ErpColors.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_linkedSupplier == null
                    ? 'غير مربوط بحساب مورد (للعميل الذي نشتري منه أيضاً)'
                    : 'مربوط بالمورد: ${_linkedSupplier!['name']}'),
              ),
              TextButton(
                onPressed: () async {
                  final sp = await Pickers.supplier(context, title: 'ربط العميل بمورد');
                  if (sp == null) return;
                  await StatementService().linkSupplier(widget.customerId, sp.id);
                  _load();
                },
                child: const Text('ربط'),
              ),
              if (_linkedSupplier != null)
                TextButton(
                  onPressed: () async {
                    await StatementService().linkSupplier(widget.customerId, null);
                    _load();
                  },
                  child: const Text('فك الربط', style: TextStyle(color: ErpColors.red)),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _hero(String name, CustomerSummary s, CustomerExt e, double limit, double usage) {
    final photo = e.photoPath;
    final hasPhoto = photo != null && photo.isNotEmpty && File(photo).existsSync();
    return Row(children: [
      CircleAvatar(
        radius: 34,
        backgroundColor: Colors.white.withOpacity(0.18),
        backgroundImage: hasPhoto ? FileImage(File(photo)) : null,
        child: hasPhoto
            ? null
            : Text(name.trim().isEmpty ? '?' : name.trim().characters.first,
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if ((e.code ?? '').isNotEmpty) _chip('رمز ${e.code}'),
            if (e.groupId != null)
              _chip(_groups.where((g) => g.id == e.groupId).map((g) => g.name).firstWhere((_) => true, orElse: () => '')),
            if ((e.region ?? '').isNotEmpty) _chip(e.region!),
            if (e.isBlocked) _chip('موقوف الآجل', color: const Color(0xFFFFCDD2)),
            if (s.lastReconDate != null) _chip('آخر مطابقة ${fmtDate(s.lastReconDate!)}'),
          ]),
        ]),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('الرصيد', style: TextStyle(color: Colors.white.withOpacity(0.75))),
        Text(fmtMoney(s.balance),
            textDirection: TextDirection.ltr,
            style: TextStyle(
                color: s.balance > 0 ? const Color(0xFFFFD6A5) : const Color(0xFFB7F7C8),
                fontSize: 26,
                fontWeight: FontWeight.bold)),
        if (limit > 0)
          Text('من سقف ${fmtMoney(limit)}', style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
      ]),
    ]);
  }

  Widget _chip(String t, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
        decoration: BoxDecoration(
          color: (color ?? Colors.white).withOpacity(0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 12)),
      );

  Widget _actions() {
    Widget a(String t, IconData i, Color c, VoidCallback f) => Padding(
          padding: const EdgeInsets.all(4),
          child: ActionChip(
            avatar: Icon(i, color: c, size: 18),
            label: Text(t),
            backgroundColor: Colors.white,
            side: const BorderSide(color: ErpColors.border),
            onPressed: f,
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(children: [
        a('وصل قبض', Icons.receipt_long, ErpColors.green,
            () => _open(ReceiptScreen(customer: _party), permission: AppPermissions.collection)),
        a('كشف حساب', Icons.list_alt, ErpColors.navy,
            () => _open(CustomerStatementScreen(customerId: widget.customerId, customerName: '${_customer!['name']}'))),
        a('استحقاق / تقسيط', Icons.event_note, ErpColors.gold,
            () => _open(
                DueItemFormScreen(partyType: 'customer', partyId: widget.customerId, partyName: '${_customer!['name']}'),
                permission: AppPermissions.collection)),
        a('الفواتير غير المسددة', Icons.receipt_outlined, ErpColors.orange,
            () => _open(OpenInvoicesScreen(customerId: widget.customerId))),
      ]),
    );
  }

  Widget _imageBox(String label, String? path, ValueChanged<String?> onChanged) {
    final has = path != null && path.isNotEmpty && File(path).existsSync();
    return Container(
      width: 200,
      height: 130,
      decoration: BoxDecoration(
        color: ErpColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ErpColors.border),
      ),
      child: Stack(children: [
        Positioned.fill(
          child: has
              ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(path), fit: BoxFit.cover))
              : Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.add_a_photo_outlined, color: ErpColors.muted),
                    Text(label, style: const TextStyle(color: ErpColors.muted)),
                  ]),
                ),
        ),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                try {
                  final p = await pickAndStoreImage('c${widget.customerId}');
                  if (p != null) onChanged(p);
                } catch (err) {
                  if (mounted) showError(context, err);
                }
              },
            ),
          ),
        ),
        if (has)
          Positioned(
            top: 4,
            left: 4,
            child: IconButton.filledTonal(
              iconSize: 16,
              icon: const Icon(Icons.close),
              onPressed: () => onChanged(null),
            ),
          ),
      ]),
    );
  }
}

// ═══════════════════════════ دليل العملاء ═══════════════════════════

class CustomersDirectoryScreen extends StatefulWidget {
  const CustomersDirectoryScreen({super.key});
  @override
  State<CustomersDirectoryScreen> createState() => _CustomersDirectoryScreenState();
}

class _CustomersDirectoryScreenState extends State<CustomersDirectoryScreen> {
  List<Map<String, Object?>> _rows = const [];
  List<CustomerGroup> _groups = const [];
  int? _group;
  String? _region;
  String _filter = 'all'; // all | debt | over | blocked | nodata
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await erpDb();
    final r = await db.rawQuery('''
      SELECT c.id, c.name, c.phone, c.current_total_debt AS balance,
             x.code, x.region, x.group_id, x.credit_limit, x.is_blocked, x.collection_day, g.name AS group_name
      FROM customers c
      LEFT JOIN customer_ext x ON x.customer_id = c.id
      LEFT JOIN customer_groups g ON g.id = x.group_id
      WHERE COALESCE(c.is_deleted, 0) = 0
      ORDER BY c.name
    ''');
    final g = await CustomerExtService().groups();
    if (mounted) {
      setState(() {
        _rows = r;
        _groups = g;
      });
    }
  }

  List<Map<String, Object?>> get _visible => _rows.where((r) {
        if (_q.isNotEmpty &&
            !('${r['name']}'.contains(_q) || '${r['phone'] ?? ''}'.contains(_q) || '${r['code'] ?? ''}' == _q)) {
          return false;
        }
        if (_group != null && r['group_id'] != _group) return false;
        if (_region != null && r['region'] != _region) return false;
        switch (_filter) {
          case 'debt':
            return d0(r['balance']) > 0;
          case 'over':
            return d0(r['credit_limit']) > 0 && d0(r['balance']) > d0(r['credit_limit']);
          case 'blocked':
            return (r['is_blocked'] as int? ?? 0) == 1;
          case 'nodata':
            return r['code'] == null && r['group_id'] == null;
        }
        return true;
      }).toList();

  @override
  Widget build(BuildContext context) {
    final regions = {
      for (final r in _rows)
        if ((r['region'] as String?)?.isNotEmpty == true) r['region'] as String
    }.toList()
      ..sort();
    final v = _visible;
    final total = v.fold(0.0, (s, r) => s + d0(r['balance']));
    return ErpPage(
      title: 'دليل العملاء',
      subtitle: '${v.length} عميل — مجموع الأرصدة ${fmtMoney(total)}',
      icon: Icons.contacts_outlined,
      actions: [
        IconButton(
          tooltip: 'إدارة المجموعات',
          icon: const Icon(Icons.workspaces_outline),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerGroupsScreen()))
              .then((_) => _load()),
        ),
        ...exportActions(context,
            title: 'دليل العملاء',
            headers: () => ['الرمز', 'الاسم', 'الهاتف', 'المجموعة', 'المنطقة', 'السقف', 'الرصيد'],
            rows: () => [
                  for (final r in v)
                    [
                      '${r['code'] ?? ''}',
                      '${r['name']}',
                      '${r['phone'] ?? ''}',
                      '${r['group_name'] ?? ''}',
                      '${r['region'] ?? ''}',
                      d0(r['credit_limit']) > 0 ? fmtMoney(d0(r['credit_limit'])) : '',
                      fmtMoney(d0(r['balance'])),
                    ],
                ]),
      ],
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            SearchBox(hint: 'بحث بالاسم أو الهاتف أو الرمز', onChanged: (x) => setState(() => _q = x.trim())),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              DropBox<int>(
                label: 'المجموعة',
                width: 180,
                value: _group,
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('الكل')),
                  for (final g in _groups) DropdownMenuItem(value: g.id, child: Text(g.name)),
                ],
                onChanged: (x) => setState(() => _group = x),
              ),
              DropBox<String>(
                label: 'المنطقة',
                width: 170,
                value: regions.contains(_region) ? _region : null,
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('الكل')),
                  for (final r in regions) DropdownMenuItem(value: r, child: Text(r)),
                ],
                onChanged: (x) => setState(() => _region = x),
              ),
              for (final e in const {
                'all': 'الكل',
                'debt': 'عليهم دين',
                'over': 'تجاوزوا السقف',
                'blocked': 'موقوفون',
                'nodata': 'بطاقة غير مكتملة',
              }.entries)
                ChoiceChip(
                    label: Text(e.value), selected: _filter == e.key, onSelected: (_) => setState(() => _filter = e.key)),
            ]),
          ]),
        ),
        Expanded(
          child: v.isEmpty
              ? const EmptyState('لا يوجد عملاء بهذه التصفية')
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: v.length,
                  itemBuilder: (_, i) {
                    final r = v[i];
                    final bal = d0(r['balance']);
                    final lim = d0(r['credit_limit']);
                    final over = lim > 0 && bal > lim;
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: over ? ErpColors.red.withOpacity(0.4) : ErpColors.border)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: ErpColors.navy.withOpacity(0.08),
                          child: Text('${r['name']}'.isEmpty ? '?' : '${r['name']}'.characters.first,
                              style: const TextStyle(color: ErpColors.navy, fontWeight: FontWeight.bold)),
                        ),
                        title: Row(children: [
                          Flexible(child: Text('${r['name']}', overflow: TextOverflow.ellipsis)),
                          if (r['code'] != null) ...[
                            const SizedBox(width: 6),
                            StatusBadge('${r['code']}', color: ErpColors.cyan),
                          ],
                          if ((r['is_blocked'] as int? ?? 0) == 1) ...[
                            const SizedBox(width: 6),
                            const StatusBadge('موقوف', color: ErpColors.red),
                          ],
                        ]),
                        subtitle: Text([
                          if (r['phone'] != null) '${r['phone']}',
                          if (r['group_name'] != null) '${r['group_name']}',
                          if (r['region'] != null) '${r['region']}',
                          if (r['collection_day'] != null) 'يحصّل ${r['collection_day']}',
                        ].join(' • ')),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            MoneyText(bal, bold: true),
                            if (lim > 0)
                              Text('السقف ${fmtMoney(lim)}',
                                  style: TextStyle(fontSize: 11, color: over ? ErpColors.red : ErpColors.muted)),
                          ],
                        ),
                        onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => CustomerCardScreen(customerId: r['id'] as int)))
                            .then((_) => _load()),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class CustomerGroupsScreen extends StatefulWidget {
  const CustomerGroupsScreen({super.key});
  @override
  State<CustomerGroupsScreen> createState() => _CustomerGroupsScreenState();
}

class _CustomerGroupsScreenState extends State<CustomerGroupsScreen> {
  final _svc = CustomerExtService();
  List<CustomerGroup> _groups = const [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = await _svc.groups();
    if (mounted) setState(() => _groups = g);
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'مجموعات العملاء',
      subtitle: 'تصنيف العملاء (مثل الأرصدة الخاصة في الإداري)',
      icon: Icons.workspaces_outline,
      floatingActionButton: FloatingActionButton(
        backgroundColor: ErpColors.navy,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
        onPressed: () async {
          final n = await askText(context, 'مجموعة جديدة', label: 'الاسم');
          if (n == null || n.isEmpty) return;
          try {
            await _svc.addGroup(n);
            _load();
          } catch (e) {
            if (mounted) showError(context, e);
          }
        },
      ),
      body: _groups.isEmpty
          ? const EmptyState('لا توجد مجموعات بعد')
          : ListView(
              padding: const EdgeInsets.all(8),
              children: [
                for (final g in _groups)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12), side: const BorderSide(color: ErpColors.border)),
                    child: ListTile(
                      leading: const Icon(Icons.folder_shared_outlined, color: ErpColors.purple),
                      title: Text(g.name),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () async {
                            final n = await askText(context, 'إعادة تسمية', initial: g.name);
                            if (n == null || n.isEmpty) return;
                            await _svc.renameGroup(g.id, n);
                            _load();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: ErpColors.red),
                          onPressed: () async {
                            final ok = await confirmDialog(context, 'حذف المجموعة',
                                'سيُزال التصنيف عن عملائها (لا يُحذف أي عميل).',
                                color: ErpColors.red);
                            if (!ok) return;
                            await _svc.deleteGroup(g.id);
                            _load();
                          },
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
    );
  }
}
