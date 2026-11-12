// lib/erp/delivery/delivery_screens.dart
//
// 🚚 شاشة شركات التوصيل: الطلبات (إضافة، حالة)، الشركات، وحساب كل شركة وتسويته.
// التسجيل يدوي (لا توجد واجهة ربط عامة لشركات التوصيل العراقية).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../widgets/settings_kit.dart';
import '../debts/receipt_screen.dart';
import '../erp_common.dart';
import '../pickers.dart';
import 'delivery_models.dart';
import 'delivery_store.dart';
import '../../services/save_lock.dart'; // 🔒 قفل الحفظ

final _n = NumberFormat('#,##0', 'en');
String _m(int fils) => _n.format(fromFils(fils).round());
final _d = DateFormat('yyyy/MM/dd', 'en');

Color _statusColor(DeliveryStatus s) => switch (s) {
      DeliveryStatus.pending => kSetBlue,
      DeliveryStatus.out => kSetOrange,
      DeliveryStatus.delivered => kSetGreen,
      DeliveryStatus.returned => kSetRed,
      DeliveryStatus.cancelled => kSetMuted,
    };

class DeliveryHubScreen extends StatefulWidget {
  const DeliveryHubScreen({super.key});
  @override
  State<DeliveryHubScreen> createState() => _DeliveryHubScreenState();
}

class _DeliveryHubScreenState extends State<DeliveryHubScreen> {
  final _store = DeliveryStore();
  List<DeliveryCompany> _companies = const [];
  List<DeliveryOrder> _orders = const [];
  int _tab = 0;
  int? _companyFilter;
  DeliveryStatus? _statusFilter;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final c = await _store.companies();
      final o = await _store.orders(companyId: _companyFilter, status: _statusFilter);
      if (!mounted) return;
      setState(() {
        _companies = c;
        _orders = o;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        setToast(context, '$e', error: true);
      }
    }
  }

  String _companyName(int id) => _companies.firstWhere((c) => c.id == id, orElse: () => DeliveryCompany(name: '#$id')).name;

  Future<void> _editCompany([DeliveryCompany? c]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _CompanyDialog(store: _store, company: c));
    if (saved == true) await _load();
  }

  Future<void> _editOrder([DeliveryOrder? o]) async {
    if (_companies.where((c) => c.active).isEmpty) {
      setToast(context, 'أضف شركة توصيل أولاً', error: true);
      setState(() => _tab = 1);
      return;
    }
    final saved = await showDialog<bool>(
        context: context, builder: (_) => _OrderDialog(store: _store, companies: _companies, order: o));
    if (saved == true) await _load();
  }

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط: القفل يُؤخذ قبل أي انتظار ويغطي الشاشة حتى ينتهي
  Future<void> _changeStatus(DeliveryOrder o) async {
    await SaveLock.run(() => _changeStatusUnlocked(o));
  }

  Future<void> _changeStatusUnlocked(DeliveryOrder o) async {
    if (o.settled) return;
    final to = await showModalBottomSheet<DeliveryStatus>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('${o.customerName} — ${o.status.label}', style: const TextStyle(fontWeight: FontWeight.w800))),
          for (final s in o.status.next)
            ListTile(
              leading: Icon(Icons.circle, color: _statusColor(s), size: 14),
              title: Text('إلى: ${s.label}'),
              onTap: () => Navigator.pop(ctx, s),
            ),
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: const Text('تعديل الطلب'),
            onTap: () {
              Navigator.pop(ctx);
              _editOrder(o);
            },
          ),
        ]),
      ),
    );
    if (to == null) return;
    try {
      await _store.setStatus(o, to);
      await _load();
    } catch (e) {
      if (mounted) setToast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'شركات التوصيل',
      icon: Icons.local_shipping_rounded,
      subtitle: 'الطلبات وحالتها، وحساب كل شركة وتسويته',
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _tab == 0 ? _editOrder() : _editCompany(),
        icon: const Icon(Icons.add_rounded),
        label: Text(_tab == 0 ? 'طلب توصيل' : 'شركة'),
      ),
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('الطلبات'), icon: Icon(Icons.inventory_rounded)),
            ButtonSegment(value: 1, label: Text('الشركات والحساب'), icon: Icon(Icons.business_rounded)),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator() else if (_tab == 0) ..._ordersView() else ..._companiesView(),
        const SizedBox(height: 80),
      ],
    );
  }

  List<Widget> _ordersView() => [
        Wrap(spacing: 8, runSpacing: 8, children: [
          DropdownButton<int?>(
            value: _companyFilter,
            hint: const Text('كل الشركات'),
            items: [
              const DropdownMenuItem(value: null, child: Text('كل الشركات')),
              for (final c in _companies) DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) {
              _companyFilter = v;
              _load();
            },
          ),
          for (final s in [null, ...DeliveryStatus.values])
            ChoiceChip(
              label: Text(s?.label ?? 'كل الحالات'),
              selected: _statusFilter == s,
              onSelected: (_) {
                _statusFilter = s;
                _load();
              },
            ),
        ]),
        const SizedBox(height: 8),
        if (_orders.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا طلبات')))
        else
          for (final o in _orders)
            Card(
              elevation: 0,
              child: ListTile(
                onTap: () => _changeStatus(o),
                leading: CircleAvatar(
                  backgroundColor: _statusColor(o.status).withValues(alpha: 0.15),
                  child: Icon(Icons.local_shipping_rounded, color: _statusColor(o.status), size: 20),
                ),
                title: Text('${o.customerName}${o.area.isEmpty ? '' : ' — ${o.area}'}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text([
                  _companyName(o.companyId),
                  o.status.label,
                  'تحصيل ${_m(o.codFils)}',
                  'أجرة ${_m(o.feeFils)}',
                  if (o.invoiceNumber.isNotEmpty) 'فاتورة ${o.invoiceNumber}',
                  _d.format(o.createdAt),
                  if (o.settled) 'مُسوّى',
                ].join(' • ')),
                trailing: o.settled ? const Icon(Icons.verified_rounded, color: kSetGreen) : const Icon(Icons.chevron_left_rounded),
              ),
            ),
      ];

  List<Widget> _companiesView() => [
        const SetBanner(
          'الطريقة الصحيحة حسابياً: اربط الشركة بحساب في سجل الديون، واحفظ فاتورة الطلب ديناً على ذلك الحساب. '
          'عند التسوية يُسجَّل ما تسلّمته بوصل قبض (والأجرة خصماً) — فلا يدخل الصندوق مال لم يصل.',
        ),
        const SizedBox(height: 10),
        if (_companies.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا شركات — أضف شركة')))
        else
          for (final c in _companies)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CompanyCard(store: _store, company: c, onEdit: () => _editCompany(c), onChanged: _load),
            ),
      ];
}

// ═════════════════════ بطاقة حساب شركة ═════════════════════

class _CompanyCard extends StatefulWidget {
  const _CompanyCard({required this.store, required this.company, required this.onEdit, required this.onChanged});
  final DeliveryStore store;
  final DeliveryCompany company;
  final VoidCallback onEdit;
  final Future<void> Function() onChanged;
  @override
  State<_CompanyCard> createState() => _CompanyCardState();
}

class _CompanyCardState extends State<_CompanyCard> {
  DeliveryBalance? _b;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final o = await widget.store.orders(companyId: widget.company.id, unsettledOnly: true, limit: 100000);
    if (mounted) setState(() => _b = DeliveryBalance.of(o));
  }

  Future<void> _settle() async {
    final b = _b;
    if (b == null || b.orders.isEmpty) return;
    final c = widget.company;
    final ok = await confirmDialog(
      context,
      'تسوية حساب ${c.name}',
      '${b.delivered} مسلّم و${b.returned} راجع\n'
          'التحصيل: ${_m(b.codFils)}\nالأجور: ${_m(b.feeFils)}\nالصافي المستحق لك: ${_m(b.netFils)}\n\n'
          'تُعلَّم الطلبات «مُسوّاة» ولا تُعدَّل بعدها. قبض المال يُسجَّل بوصل قبض بعدها.',
      ok: 'تسوية',
    );
    if (!ok || !mounted) return;
    try {
      // 🔒 التسوية وحدها تحت القفل: وصل القبض بعدها شاشة لها قفلها
      final r = await SaveLock.run(() => widget.store.settle(c.id!));
      if (r == null || !mounted) return;
      setToast(context, 'سُوّيت ${r.balance.orders.length} طلباً — الصافي ${_m(r.balance.netFils)}');
      await widget.onChanged();
      await _load();
      if (c.customerId != null && mounted) {
        final go = await confirmDialog(context, 'وصل القبض',
            'افتح «وصل قبض» لحساب ${c.name} الآن؟ اكتب فيه ما تسلّمته (${_m(r.balance.netFils)})، والأجرة خصماً إن سجّلت التحصيل كاملاً.',
            ok: 'فتح الوصل');
        if (go && mounted) {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => ReceiptScreen(customer: PartyLite(c.customerId!, c.name, c.phone, 0))));
        }
      }
    } catch (e) {
      if (mounted) setToast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.company;
    final b = _b;
    return SetCard(
      title: c.name,
      subtitle: [if (c.phone.isNotEmpty) c.phone, if (!c.active) 'موقوفة', if (c.customerId == null) 'غير مربوطة بحساب'].join(' • '),
      icon: Icons.business_rounded,
      color: c.active ? kSetNavy : kSetMuted,
      trailing: IconButton(onPressed: widget.onEdit, icon: const Icon(Icons.edit_rounded)),
      child: b == null
          ? const LinearProgressIndicator()
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('قيد التوصيل: ${b.open} • مسلّم غير مُسوّى: ${b.delivered} • راجع: ${b.returned}'),
              Text('التحصيل ${_m(b.codFils)} − الأجور ${_m(b.feeFils)} = الصافي لك ${_m(b.netFils)}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  onPressed: b.orders.isEmpty ? null : _settle,
                  icon: const Icon(Icons.handshake_rounded),
                  label: const Text('تسوية الحساب'),
                ),
              ),
            ]),
    );
  }
}

// ═════════════════════ نوافذ الإدخال ═════════════════════

class _CompanyDialog extends StatefulWidget {
  const _CompanyDialog({required this.store, this.company});
  final DeliveryStore store;
  final DeliveryCompany? company;
  @override
  State<_CompanyDialog> createState() => _CompanyDialogState();
}

class _CompanyDialogState extends State<_CompanyDialog> {
  late final _name = TextEditingController(text: widget.company?.name ?? '');
  late final _phone = TextEditingController(text: widget.company?.phone ?? '');
  late final _notes = TextEditingController(text: widget.company?.notes ?? '');
  late final _fee = TextEditingController(text: _n.format(fromFils(widget.company?.defaultFeeFils ?? 0).round()));
  late bool _active = widget.company?.active ?? true;
  PartyLite? _customer;
  late int? _customerId = widget.company?.customerId;

  @override
  void dispose() {
    for (final c in [_name, _phone, _notes, _fee]) {
      c.dispose();
    }
    super.dispose();
  }

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط: القفل يُؤخذ قبل أي انتظار ويغطي الشاشة حتى ينتهي
  Future<void> _save() async {
    await SaveLock.run(() => _saveUnlocked());
  }

  Future<void> _saveUnlocked() async {
    try {
      await widget.store.saveCompany(DeliveryCompany(
        id: widget.company?.id,
        name: _name.text,
        phone: _phone.text,
        notes: _notes.text,
        customerId: _customerId,
        defaultFeeFils: toFils(parseMoney(_fee.text) ?? 0),
        active: _active,
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setToast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.company == null ? 'شركة توصيل جديدة' : 'تعديل الشركة'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم')),
              TextField(controller: _phone, decoration: const InputDecoration(labelText: 'الهاتف'), keyboardType: TextInputType.phone),
              TextField(controller: _fee, decoration: const InputDecoration(labelText: 'الأجرة الافتراضية للطلب'), keyboardType: TextInputType.number),
              TextField(controller: _notes, decoration: const InputDecoration(labelText: 'ملاحظات')),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_balance_wallet_rounded),
                title: Text(_customer?.name ?? (_customerId == null ? 'غير مربوطة بحساب في سجل الديون' : 'حساب #$_customerId')),
                subtitle: const Text('للتسوية بوصل قبض'),
                trailing: TextButton(
                  onPressed: () async {
                    final p = await Pickers.customer(context, title: 'حساب الشركة في سجل الديون');
                    if (p != null) {
                      setState(() {
                        _customer = p;
                        _customerId = p.id;
                      });
                    }
                  },
                  child: const Text('اختيار'),
                ),
              ),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('فعّالة'), value: _active, onChanged: (v) => setState(() => _active = v)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
        ],
      );
}

class _OrderDialog extends StatefulWidget {
  const _OrderDialog({required this.store, required this.companies, this.order});
  final DeliveryStore store;
  final List<DeliveryCompany> companies;
  final DeliveryOrder? order;
  @override
  State<_OrderDialog> createState() => _OrderDialogState();
}

class _OrderDialogState extends State<_OrderDialog> {
  late int _companyId = widget.order?.companyId ?? widget.companies.firstWhere((c) => c.active).id!;
  late final _customer = TextEditingController(text: widget.order?.customerName ?? '');
  late final _phone = TextEditingController(text: widget.order?.phone ?? '');
  late final _area = TextEditingController(text: widget.order?.area ?? '');
  late final _address = TextEditingController(text: widget.order?.address ?? '');
  late final _invoice = TextEditingController(text: widget.order?.invoiceNumber ?? '');
  late final _cod = TextEditingController(text: widget.order == null ? '' : _n.format(fromFils(widget.order!.codFils).round()));
  late final _fee = TextEditingController(
      text: _n.format(fromFils(widget.order?.feeFils ??
              widget.companies.firstWhere((c) => c.id == _companyId, orElse: () => widget.companies.first).defaultFeeFils)
          .round()));
  late final _note = TextEditingController(text: widget.order?.note ?? '');

  @override
  void dispose() {
    for (final c in [_customer, _phone, _area, _address, _invoice, _cod, _fee, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط: القفل يُؤخذ قبل أي انتظار ويغطي الشاشة حتى ينتهي
  Future<void> _save() async {
    await SaveLock.run(() => _saveUnlocked());
  }

  Future<void> _saveUnlocked() async {
    final o = widget.order;
    try {
      await widget.store.saveOrder(DeliveryOrder(
        id: o?.id,
        companyId: _companyId,
        invoiceId: o?.invoiceId,
        invoiceNumber: _invoice.text,
        customerName: _customer.text,
        phone: _phone.text,
        area: _area.text,
        address: _address.text,
        codFils: toFils(parseMoney(_cod.text) ?? 0),
        feeFils: toFils(parseMoney(_fee.text) ?? 0),
        status: o?.status ?? DeliveryStatus.pending,
        note: _note.text,
        createdAt: o?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setToast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.order == null ? 'طلب توصيل جديد' : 'تعديل الطلب'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                initialValue: _companyId,
                decoration: const InputDecoration(labelText: 'الشركة'),
                items: [
                  for (final c in widget.companies)
                    if (c.active || c.id == _companyId) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _companyId = v ?? _companyId),
              ),
              TextField(controller: _customer, decoration: const InputDecoration(labelText: 'اسم الزبون')),
              TextField(controller: _phone, decoration: const InputDecoration(labelText: 'هاتف الزبون'), keyboardType: TextInputType.phone),
              TextField(controller: _area, decoration: const InputDecoration(labelText: 'المحافظة / المنطقة')),
              TextField(controller: _address, decoration: const InputDecoration(labelText: 'العنوان')),
              TextField(controller: _invoice, decoration: const InputDecoration(labelText: 'رقم الفاتورة (اختياري)')),
              TextField(controller: _cod, decoration: const InputDecoration(labelText: 'مبلغ التحصيل من الزبون'), keyboardType: TextInputType.number),
              TextField(controller: _fee, decoration: const InputDecoration(labelText: 'أجرة التوصيل للشركة'), keyboardType: TextInputType.number),
              TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
        ],
      );
}
