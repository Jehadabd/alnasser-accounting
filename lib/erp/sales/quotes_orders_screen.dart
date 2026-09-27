// lib/erp/sales/quotes_orders_screen.dart
//
// 📝 شاشات عروض الأسعار والطلبات.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../screens/create_purchase_invoice_screen.dart';
import '../../services/purchase_service.dart';
import '../doc_lines.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../report_export.dart';
import '../stock_helpers.dart';
import 'doc_pdf.dart';
import 'invoice_bridge.dart';
import 'quote_order_service.dart';

const Map<String, String> quoteStatusLabels = {
  'open': 'مفتوح',
  'converted': 'حُوِّل لفاتورة',
  'expired': 'منتهي',
  'cancelled': 'ملغى',
};
const Map<String, String> orderStatusLabels = {
  'open': 'مفتوح',
  'partial': 'مسلّم جزئياً',
  'closed': 'مغلق',
  'cancelled': 'ملغى',
};
const Map<int, String> priorityLabels = {1: 'عاجل', 2: 'عادي', 3: 'منخفض'};

List<DraftLine> _draftFrom(List<DocLine> lines) => [
      for (final l in lines)
        if (l.quantity > 0)
          DraftLine(
            productName: l.product.name,
            productUnit: l.product.unit,
            unitPrice: l.product.prices[0],
            baseCost: l.product.cost,
            quantity: l.quantity,
            saleType: l.unit.name,
            factor: l.unit.factor,
            price: roundTo2(l.netPrice),
          ),
    ];

double roundTo2(double v) => (v * 100).roundToDouble() / 100;

Future<void> printLines(
  BuildContext context, {
  required String title,
  required String number,
  required DateTime date,
  required String partyLabel,
  required String partyName,
  String? partyExtra,
  List<MapEntry<String, String>> infos = const [],
  required List<DocLine> lines,
  double discount = 0,
  String? notes,
  String? terms,
}) async {
  final bytes = await DocPdf.build(
    title: title,
    number: number,
    date: date,
    partyLabel: partyLabel,
    partyName: partyName,
    partyExtra: partyExtra,
    infos: infos,
    headers: const ['#', 'المادة', 'الوحدة', 'الكمية', 'السعر', 'حسم %', 'الإجمالي'],
    rows: [
      for (var i = 0; i < lines.length; i++)
        [
          '${i + 1}',
          lines[i].product.name,
          lines[i].unit.name,
          fmtQty(lines[i].quantity),
          fmtMoney(lines[i].price),
          lines[i].discountPercent == 0 ? '' : fmtQty(lines[i].discountPercent),
          fmtMoney(lines[i].total),
        ],
    ],
    total: linesTotal(lines),
    discount: discount,
    notes: notes,
    terms: terms,
  );
  if (context.mounted) await ReportExport.openPdf(context, bytes, '${title}_$number');
}

// ═══════════════════════════ عروض الأسعار ═══════════════════════════

class QuotationsScreen extends StatefulWidget {
  const QuotationsScreen({super.key});
  @override
  State<QuotationsScreen> createState() => _QuotationsScreenState();
}

class _QuotationsScreenState extends State<QuotationsScreen> {
  List<Map<String, Object?>> _rows = const [];
  String? _status = 'open';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await QuoteOrderService().quotations(status: _status);
    if (mounted) setState(() => _rows = r);
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'عروض الأسعار',
      subtitle: 'عروض للزبائن بلا أثر على المخزون أو الحسابات',
      icon: Icons.request_quote_outlined,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: ErpColors.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('عرض جديد'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuotationEditorScreen()))
            .then((_) => _load()),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(spacing: 8, children: [
            for (final e in {null: 'الكل', ...quoteStatusLabels}.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _status == e.key,
                onSelected: (_) {
                  _status = e.key;
                  _load();
                },
              ),
          ]),
        ),
        Expanded(
          child: _rows.isEmpty
              ? const EmptyState('لا توجد عروض')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 90),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    final valid = r['valid_until'] == null ? null : parseDate(r['valid_until']);
                    final expired = valid != null && valid.isBefore(DateTime.now()) && r['status'] == 'open';
                    final net = d0(r['total']) - d0(r['discount']);
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12), side: const BorderSide(color: ErpColors.border)),
                      child: ListTile(
                        onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => QuotationEditorScreen(quotationId: r['id'] as int)))
                            .then((_) => _load()),
                        leading: CircleAvatar(
                          backgroundColor: ErpColors.cyan.withOpacity(0.14),
                          child: Text('${r['quote_no']}', style: const TextStyle(color: ErpColors.navy, fontSize: 12)),
                        ),
                        title: Text('${r['customer_name']}'),
                        subtitle: Text([
                          fmtDate(parseDate(r['quote_date'])),
                          '${r['n_items']} مادة',
                          if (valid != null) 'صالح حتى ${fmtDate(valid)}',
                        ].join(' • ')),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            MoneyText(net, bold: true),
                            StatusBadge(expired ? 'انتهت صلاحيته' : (quoteStatusLabels[r['status']] ?? '${r['status']}'),
                                color: expired
                                    ? ErpColors.red
                                    : (r['status'] == 'converted' ? ErpColors.green : ErpColors.blue)),
                          ],
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

class QuotationEditorScreen extends StatefulWidget {
  const QuotationEditorScreen({super.key, this.quotationId});
  final int? quotationId;
  @override
  State<QuotationEditorScreen> createState() => _QuotationEditorScreenState();
}

class _QuotationEditorScreenState extends State<QuotationEditorScreen> {
  final _svc = QuoteOrderService();
  final _lines = <DocLine>[];
  int? _id;
  int? _number;
  String _status = 'open';
  PartyLite? _customer;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _discount = TextEditingController();
  final _notes = TextEditingController();
  final _terms = TextEditingController(text: 'الأسعار تشمل التوصيل داخل المدينة. العرض صالح حتى التاريخ المذكور.');
  DateTime _date = DateTime.now();
  DateTime? _valid = DateTime.now().add(const Duration(days: 7));
  String _level = 'مفرد';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _id = widget.quotationId;
    if (_id != null) _load();
  }

  Future<void> _load() async {
    final q = await _svc.quotation(_id!);
    final lines = await _svc.quotationLines(_id!);
    if (q == null || !mounted) return;
    setState(() {
      _number = q['quote_no'] as int?;
      _status = (q['status'] as String?) ?? 'open';
      _name.text = '${q['customer_name'] ?? ''}';
      _phone.text = '${q['customer_phone'] ?? ''}';
      _address.text = '${q['customer_address'] ?? ''}';
      _discount.text = d0(q['discount']) == 0 ? '' : fmtMoney(d0(q['discount']));
      _notes.text = '${q['notes'] ?? ''}';
      _terms.text = '${q['terms'] ?? ''}';
      _date = parseDate(q['quote_date']);
      _valid = q['valid_until'] == null ? null : parseDate(q['valid_until']);
      _level = (q['price_level'] as String?) ?? 'مفرد';
      if (q['customer_id'] != null) {
        _customer = PartyLite(q['customer_id'] as int, _name.text, _phone.text, 0);
      }
      _lines
        ..clear()
        ..addAll(lines);
    });
  }

  Future<bool> _save() async {
    setState(() => _saving = true);
    try {
      _id = await _svc.saveQuotation(
        id: _id,
        date: _date,
        validUntil: _valid,
        customerId: _customer?.id,
        customerName: _name.text,
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        priceLevel: _level,
        discount: parseMoney(_discount.text) ?? 0,
        notes: _notes.text.trim(),
        terms: _terms.text.trim(),
        lines: _lines,
      );
      final q = await _svc.quotation(_id!);
      _number = q?['quote_no'] as int?;
      if (mounted) showOk(context, 'حُفظ العرض رقم $_number');
      return true;
    } catch (e) {
      if (mounted) showError(context, e);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _print() async {
    if (!await _save() || !mounted) return;
    await printLines(context,
        title: 'عرض سعر',
        number: '$_number',
        date: _date,
        partyLabel: 'السادة',
        partyName: _name.text,
        partyExtra: [_phone.text, _address.text].where((s) => s.trim().isNotEmpty).join(' — '),
        infos: [if (_valid != null) MapEntry('صالح حتى', fmtDate(_valid!))],
        lines: _lines,
        discount: parseMoney(_discount.text) ?? 0,
        notes: _notes.text,
        terms: _terms.text);
  }

  Future<void> _convert() async {
    if (_valid != null && _valid!.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))) {
      final ok = await confirmDialog(context, 'انتهت صلاحية العرض', 'انتهت صلاحية هذا العرض. تحويله إلى فاتورة رغم ذلك؟');
      if (!ok) return;
    }
    if (!await _save() || !mounted) return;
    try {
      final invId = await InvoiceBridge.openAsInvoice(
        context,
        customerName: _name.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        lines: _draftFrom(_lines),
        discount: parseMoney(_discount.text) ?? 0,
      );
      if (invId != null) {
        await _svc.setQuotationStatus(_id!, 'converted');
        if (mounted) {
          showOk(context, 'حُوّل العرض إلى الفاتورة #$invId');
          setState(() => _status = 'converted');
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = linesTotal(_lines);
    final disc = parseMoney(_discount.text) ?? 0;
    return ErpPage(
      title: _number == null ? 'عرض سعر جديد' : 'عرض سعر رقم $_number',
      subtitle: quoteStatusLabels[_status],
      icon: Icons.request_quote_outlined,
      actions: [
        IconButton(tooltip: 'طباعة', icon: const Icon(Icons.print), onPressed: _print),
        if (_id != null && _status == 'open')
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) async {
              if (v == 'cancel') {
                await _svc.setQuotationStatus(_id!, 'cancelled');
                if (mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'cancel', child: Text('إلغاء العرض'))],
          ),
      ],
      bottom: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: Text('الصافي: ${fmtMoney(total - disc)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ErpColors.navy)),
            ),
            OutlinedButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: const Text('حفظ')),
            const SizedBox(width: 8),
            if (_status == 'open')
              PrimaryButton(
                  label: 'تحويل إلى فاتورة', icon: Icons.transform, color: ErpColors.green, busy: _saving, onPressed: _convert),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 20), children: [
        ErpSection(
          title: 'الزبون',
          icon: Icons.person_outline,
          color: ErpColors.blue,
          child: FieldGrid(children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.person_search),
              label: const Text('من العملاء'),
              onPressed: () async {
                final c = await Pickers.customer(context);
                if (c == null) return;
                setState(() {
                  _customer = c;
                  _name.text = c.name;
                  _phone.text = c.phone ?? '';
                });
              },
            ),
            TextBox(controller: _name, label: 'اسم الزبون', width: 240),
            TextBox(controller: _phone, label: 'الهاتف', width: 160),
            TextBox(controller: _address, label: 'العنوان', width: 240),
          ]),
        ),
        ErpSection(
          title: 'بيانات العرض',
          icon: Icons.tune,
          child: FieldGrid(children: [
            DateButton(label: 'التاريخ', value: _date, onChanged: (d) => setState(() => _date = d)),
            DateButton(label: 'صالح حتى', value: _valid, onChanged: (d) => setState(() => _valid = d)),
            DropBox<String>(
              label: 'مستوى السعر',
              width: 160,
              value: _level,
              items: [for (final p in priceLevelNames) DropdownMenuItem(value: p, child: Text(p))],
              onChanged: (v) => setState(() => _level = v ?? 'مفرد'),
            ),
            MoneyField(controller: _discount, label: 'حسم على العرض', width: 160, onChanged: (_) => setState(() {})),
          ]),
        ),
        ErpSection(
          title: 'المواد',
          icon: Icons.inventory_2_outlined,
          color: ErpColors.orange,
          child: DocLinesEditor(
            lines: _lines,
            onChanged: () => setState(() {}),
            priceLevel: priceLevelIndex(_level),
            showDiscount: true,
          ),
        ),
        ErpSection(
          title: 'ملاحظات وشروط',
          icon: Icons.notes,
          child: Column(children: [
            TextBox(controller: _notes, label: 'ملاحظات', maxLines: 2),
            const SizedBox(height: 10),
            TextBox(controller: _terms, label: 'شروط العرض', maxLines: 3),
          ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════ الطلبات ═══════════════════════════

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.orderType = 'sales'});
  final String orderType;
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Map<String, Object?>> _rows = const [];
  bool _closed = false;
  late String _type = widget.orderType;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await QuoteOrderService().orders(orderType: _type, includeClosed: _closed);
    if (mounted) setState(() => _rows = r);
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: _type == 'sales' ? 'طلبات المبيعات' : 'طلبات المشتريات',
      subtitle: 'تاريخ تسليم، أولوية، حجز كميات، تسليم جزئي',
      icon: Icons.assignment_outlined,
      actions: [
        if (_type == 'purchase')
          IconButton(
            tooltip: 'طلب تلقائي للمواد تحت الحد الأدنى',
            icon: const Icon(Icons.auto_mode),
            onPressed: () async {
              try {
                final n = await QuoteOrderService().autoReorder();
                if (mounted) showOk(context, n == 0 ? 'لا توجد مواد تحتاج طلباً' : 'أُنشئ $n طلب شراء');
                _load();
              } catch (e) {
                if (mounted) showError(context, e);
              }
            },
          ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: ErpColors.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('طلب جديد'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderEditorScreen(orderType: _type)))
            .then((_) => _load()),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'sales', label: Text('مبيعات'), icon: Icon(Icons.north_east)),
                ButtonSegment(value: 'purchase', label: Text('مشتريات'), icon: Icon(Icons.south_west)),
              ],
              selected: {_type},
              onSelectionChanged: (s) {
                _type = s.first;
                _load();
              },
            ),
            FilterChip(
                label: const Text('إظهار المغلقة'),
                selected: _closed,
                onSelected: (v) {
                  _closed = v;
                  _load();
                }),
          ]),
        ),
        Expanded(
          child: _rows.isEmpty
              ? const EmptyState('لا توجد طلبات')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 90),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    final qty = d0(r['qty']);
                    final del = d0(r['delivered']);
                    final pr = (r['priority'] as int?) ?? 2;
                    final dd = r['delivery_date'] == null ? null : parseDate(r['delivery_date']);
                    final late = dd != null && dd.isBefore(DateTime.now()) && r['status'] != 'closed';
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: late ? ErpColors.red.withOpacity(0.4) : ErpColors.border)),
                      child: ListTile(
                        onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => OrderEditorScreen(orderType: _type, orderId: r['id'] as int)))
                            .then((_) => _load()),
                        leading: CircleAvatar(
                          backgroundColor: (pr == 1 ? ErpColors.red : ErpColors.navy).withOpacity(0.12),
                          child: Text('${r['order_no']}',
                              style: TextStyle(color: pr == 1 ? ErpColors.red : ErpColors.navy, fontSize: 12)),
                        ),
                        title: Row(children: [
                          Flexible(child: Text('${r['party_name']}', overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 6),
                          if (pr == 1) const StatusBadge('عاجل', color: ErpColors.red),
                          if ((r['reserve'] as int? ?? 0) == 1) ...[
                            const SizedBox(width: 4),
                            const StatusBadge('محجوز', color: ErpColors.purple),
                          ],
                        ]),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text([
                            fmtDate(parseDate(r['order_date'])),
                            if (dd != null) 'التسليم ${fmtDate(dd)}${late ? ' (متأخر)' : ''}',
                            '${r['n_items']} مادة',
                          ].join(' • ')),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: qty <= 0 ? 0 : (del / qty).clamp(0.0, 1.0).toDouble(),
                            minHeight: 5,
                            color: ErpColors.green,
                            backgroundColor: ErpColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ]),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            MoneyText(d0(r['total']), bold: true),
                            StatusBadge(orderStatusLabels[r['status']] ?? '${r['status']}',
                                color: r['status'] == 'closed' ? ErpColors.green : ErpColors.blue),
                          ],
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

class OrderEditorScreen extends StatefulWidget {
  const OrderEditorScreen({super.key, required this.orderType, this.orderId});
  final String orderType;
  final int? orderId;
  @override
  State<OrderEditorScreen> createState() => _OrderEditorScreenState();
}

class _OrderEditorScreenState extends State<OrderEditorScreen> {
  final _svc = QuoteOrderService();
  final _lines = <DocLine>[];
  int? _id;
  int? _number;
  String _status = 'open';
  PartyLite? _party;
  DateTime _date = DateTime.now();
  DateTime? _delivery;
  int _priority = 2;
  String _level = 'مفرد';
  bool _reserve = false;
  int? _warehouseId;
  final _shipping = TextEditingController();
  final _deliveryMethod = TextEditingController();
  final _payment = TextEditingController();
  final _seller = TextEditingController();
  final _notes = TextEditingController();
  List<Map<String, Object?>> _items = const [];
  bool _saving = false;

  bool get _sales => widget.orderType == 'sales';
  bool get _hasDeliveries => _items.any((i) => d0(i['delivered_base_qty']) > 0);

  @override
  void initState() {
    super.initState();
    _id = widget.orderId;
    if (_id != null) _load();
  }

  Future<void> _load() async {
    final o = await _svc.order(_id!);
    final lines = await _svc.orderLines(_id!);
    final items = await _svc.orderItems(_id!);
    if (o == null || !mounted) return;
    setState(() {
      _number = o['order_no'] as int?;
      _status = (o['status'] as String?) ?? 'open';
      _party = PartyLite((o['party_id'] as int?) ?? 0, '${o['party_name']}', null, 0);
      _date = parseDate(o['order_date']);
      _delivery = o['delivery_date'] == null ? null : parseDate(o['delivery_date']);
      _priority = (o['priority'] as int?) ?? 2;
      _level = (o['price_level'] as String?) ?? 'مفرد';
      _reserve = (o['reserve'] as int? ?? 0) == 1;
      _warehouseId = o['warehouse_id'] as int?;
      _shipping.text = '${o['shipping_company'] ?? ''}';
      _deliveryMethod.text = '${o['delivery_method'] ?? ''}';
      _payment.text = '${o['payment_method'] ?? ''}';
      _seller.text = '${o['seller_name'] ?? ''}';
      _notes.text = '${o['notes'] ?? ''}';
      _items = items;
      _lines
        ..clear()
        ..addAll(lines);
    });
  }

  Future<bool> _save() async {
    if (_party == null) {
      showError(context, _sales ? 'اختر العميل' : 'اختر المورد');
      return false;
    }
    setState(() => _saving = true);
    try {
      _id = await _svc.saveOrder(
        id: _id,
        orderType: widget.orderType,
        date: _date,
        deliveryDate: _delivery,
        partyId: _party!.id == 0 ? null : _party!.id,
        partyName: _party!.name,
        priority: _priority,
        priceLevel: _level,
        shippingCompany: _shipping.text.trim(),
        deliveryMethod: _deliveryMethod.text.trim(),
        paymentMethod: _payment.text.trim(),
        sellerName: _seller.text.trim(),
        warehouseId: _warehouseId,
        reserve: _reserve,
        notes: _notes.text.trim(),
        lines: _lines,
      );
      if (mounted) showOk(context, 'حُفظ الطلب');
      await _load();
      return true;
    } catch (e) {
      if (mounted) showError(context, e);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// تحويل المتبقي من طلب مبيعات إلى فاتورة، وتسجيل ما سُلّم فعلاً منها.
  Future<void> _deliverSales() async {
    if (_id == null && !await _save()) return;
    final lines = await _svc.orderLines(_id!, remainingOnly: true);
    if (lines.isEmpty) {
      if (mounted) showError(context, 'لا توجد كميات متبقية للتسليم');
      return;
    }
    if (!mounted) return;
    try {
      final invId = await InvoiceBridge.openAsInvoice(
        context,
        customerName: _party!.name,
        lines: _draftFrom(lines),
        paymentType: 'دين',
      );
      if (invId != null) {
        await _svc.deliverFromInvoice(_id!, invId);
        if (mounted) showOk(context, 'سُجّل التسليم من الفاتورة #$invId');
        await _load();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// تسجيل استلام طلب مشتريات يدوياً (بعد إدخال فاتورة الشراء).
  Future<void> _receivePurchase() async {
    if (_id == null) return;
    final ctrls = <int, TextEditingController>{};
    for (final it in _items) {
      final rem = d0(it['base_qty']) - d0(it['delivered_base_qty']);
      if (rem > 1e-9) ctrls[it['id'] as int] = TextEditingController(text: fmtQty(rem));
    }
    if (ctrls.isEmpty) {
      showError(context, 'استُلم الطلب كاملاً');
      return;
    }
    final ref = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل استلام (بالوحدة الأساسية)'),
        content: SizedBox(
          width: 460,
          child: ListView(shrinkWrap: true, children: [
            for (final it in _items)
              if (ctrls.containsKey(it['id']))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MoneyField(controller: ctrls[it['id']]!, label: '${it['product_name']}'),
                ),
            TextBox(controller: ref, label: 'رقم فاتورة الشراء'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسجيل')),
        ],
      ),
    );
    if (ok != true) return;
    await _svc.recordDelivery(_id!, {for (final e in ctrls.entries) e.key: parseMoney(e.value.text) ?? 0},
        ref: ref.text.trim().isEmpty ? null : 'فاتورة شراء ${ref.text.trim()}');
    await _load();
  }

  Future<void> _openPurchaseInvoice() async {
    final sid = _party?.id;
    final supplier = (sid == null || sid == 0) ? null : await PurchaseService().getSupplierById(sid);
    if (!mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => CreatePurchaseInvoiceScreen(preselectedSupplier: supplier)));
    if (mounted) await _receivePurchase();
  }

  @override
  Widget build(BuildContext context) {
    final editable = !_hasDeliveries && (_status == 'open');
    return ErpPage(
      title: _number == null
          ? (_sales ? 'طلب مبيعات جديد' : 'طلب مشتريات جديد')
          : '${_sales ? 'طلب مبيعات' : 'طلب مشتريات'} رقم $_number',
      subtitle: orderStatusLabels[_status],
      icon: Icons.assignment_outlined,
      actions: [
        IconButton(
          tooltip: 'طباعة',
          icon: const Icon(Icons.print),
          onPressed: () => printLines(context,
              title: _sales ? 'طلب مبيعات' : 'طلب شراء',
              number: '${_number ?? '-'}',
              date: _date,
              partyLabel: _sales ? 'العميل' : 'المورد',
              partyName: _party?.name ?? '',
              infos: [
                if (_delivery != null) MapEntry('التسليم', fmtDate(_delivery!)),
                MapEntry('الأولوية', priorityLabels[_priority] ?? ''),
              ],
              lines: _lines,
              notes: _notes.text),
        ),
        if (_id != null && (_status == 'open' || _status == 'partial'))
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) async {
              try {
                if (v == 'close') await _svc.closeOrder(_id!);
                if (v == 'cancel') await _svc.cancelOrder(_id!);
                if (mounted) Navigator.pop(context);
              } catch (e) {
                if (mounted) showError(context, e);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'close', child: Text('إغلاق الطلب')),
              PopupMenuItem(value: 'cancel', child: Text('إلغاء الطلب')),
            ],
          ),
      ],
      bottom: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: Text('الإجمالي: ${fmtMoney(linesTotal(_lines))}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ErpColors.navy)),
            ),
            if (editable)
              OutlinedButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: const Text('حفظ')),
            const SizedBox(width: 8),
            if (_id != null && _status != 'closed' && _status != 'cancelled')
              PrimaryButton(
                label: _sales ? 'تسليم ← فاتورة' : 'فاتورة شراء واستلام',
                icon: Icons.local_shipping,
                color: ErpColors.green,
                busy: _saving,
                onPressed: _sales ? _deliverSales : _openPurchaseInvoice,
              ),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 20), children: [
        ErpSection(
          title: _sales ? 'العميل' : 'المورد',
          icon: _sales ? Icons.person_outline : Icons.local_shipping_outlined,
          color: _sales ? ErpColors.blue : ErpColors.orange,
          child: Row(children: [
            Expanded(
              child: Text(_party?.name ?? 'لم يُختر',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            if (editable)
              OutlinedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('اختيار'),
                onPressed: () async {
                  final p = _sales ? await Pickers.customer(context) : await Pickers.supplier(context);
                  if (p != null) setState(() => _party = p);
                },
              ),
          ]),
        ),
        ErpSection(
          title: 'بيانات الطلب',
          icon: Icons.tune,
          child: FieldGrid(children: [
            DateButton(label: 'التاريخ', value: _date, onChanged: (d) => setState(() => _date = d)),
            DateButton(label: 'تاريخ التسليم', value: _delivery, onChanged: (d) => setState(() => _delivery = d)),
            DropBox<int>(
              label: 'الأولوية',
              width: 140,
              value: _priority,
              items: [for (final e in priorityLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _priority = v ?? 2),
            ),
            if (_sales)
              DropBox<String>(
                label: 'مستوى السعر',
                width: 150,
                value: _level,
                items: [for (final p in priceLevelNames) DropdownMenuItem(value: p, child: Text(p))],
                onChanged: (v) => setState(() => _level = v ?? 'مفرد'),
              ),
            WarehouseDropdown(value: _warehouseId, onChanged: (w) => setState(() => _warehouseId = w?.id)),
            TextBox(controller: _deliveryMethod, label: 'طريقة التسليم', width: 170),
            TextBox(controller: _shipping, label: 'شركة الشحن', width: 170),
            TextBox(controller: _payment, label: 'طريقة التسديد', width: 170),
            if (_sales) TextBox(controller: _seller, label: 'البائع', width: 170),
            if (_sales)
              SizedBox(
                width: 260,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _reserve,
                  onChanged: editable ? (v) => setState(() => _reserve = v) : null,
                  title: const Text('حجز الكميات'),
                  subtitle: const Text('تظهر كمحجوزة في الجرد'),
                ),
              ),
          ]),
        ),
        ErpSection(
          title: 'المواد',
          icon: Icons.inventory_2_outlined,
          color: ErpColors.orange,
          child: _hasDeliveries
              ? SimpleTable(
                  headers: const ['المادة', 'الوحدة', 'المطلوب', 'المسلّم (أساسي)', 'المتبقي (أساسي)', 'السعر'],
                  numericColumns: const {2, 3, 4, 5},
                  rows: [
                    for (final it in _items)
                      [
                        '${it['product_name']}',
                        '${it['sale_type'] ?? ''}',
                        fmtQty(d0(it['quantity'])),
                        fmtQty(d0(it['delivered_base_qty'])),
                        fmtQty(d0(it['base_qty']) - d0(it['delivered_base_qty'])),
                        fmtMoney(d0(it['price'])),
                      ],
                  ],
                )
              : DocLinesEditor(
                  lines: _lines,
                  onChanged: () => setState(() {}),
                  priceSource: _sales ? PriceSource.sale : PriceSource.cost,
                  priceLevel: priceLevelIndex(_level),
                  showDiscount: _sales,
                  readOnly: !editable,
                  priceLabel: _sales ? 'السعر' : 'سعر الشراء',
                ),
        ),
        ErpSection(
          title: 'ملاحظات',
          icon: Icons.notes,
          child: TextBox(controller: _notes, label: 'ملاحظات', maxLines: 2),
        ),
      ]),
    );
  }
}
