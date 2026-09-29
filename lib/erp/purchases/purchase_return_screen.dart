// lib/erp/purchases/purchase_return_screen.dart
//
// ↩️ مرتجع المشتريات: محرر (من فاتورة شراء أو حر) + سجل المرتجعات مع الطباعة والإلغاء.

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart' show roundMoney;
import '../../accounting/screens/acc_ui.dart';
import '../currency_service.dart';
import '../doc_lines.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../report_export.dart';
import '../sales/doc_pdf.dart';
import '../stock_helpers.dart';
import 'purchase_return_service.dart';

class PurchaseReturnEditorScreen extends StatefulWidget {
  const PurchaseReturnEditorScreen({super.key, this.invoiceId});
  final int? invoiceId;
  @override
  State<PurchaseReturnEditorScreen> createState() => _PurchaseReturnEditorScreenState();
}

class _PurchaseReturnEditorScreenState extends State<PurchaseReturnEditorScreen> {
  final _svc = PurchaseReturnService();
  final _lines = <DocLine>[];
  PartyLite? _supplier;
  int? _invoiceId;
  String? _invoiceLabel;
  Map<int, double> _returnable = const {};
  List<Map<String, Object?>> _invoices = const [];
  String _currency = 'IQD';
  final _rate = TextEditingController(text: '1');
  String _mode = 'debt';
  final _cash = TextEditingController();
  int? _boxId;
  int? _warehouseId;
  DateTime _date = DateTime.now();
  final _notes = TextEditingController();
  bool _allowNegative = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.invoiceId != null) _loadInvoice(widget.invoiceId!);
  }

  Future<void> _pickSupplier() async {
    final s = await Pickers.supplier(context);
    if (s == null) return;
    final inv = await _svc.supplierInvoices(s.id);
    final db = await erpDb();
    final cur = await db.query('suppliers', columns: ['currency'], where: 'id = ?', whereArgs: [s.id], limit: 1);
    if (!mounted) return;
    setState(() {
      _supplier = s;
      _invoices = inv;
      _invoiceId = null;
      _invoiceLabel = null;
      _returnable = const {};
      _currency = cur.isEmpty ? 'IQD' : ((cur.first['currency'] as String?) ?? 'IQD');
    });
    await _loadRate();
  }

  Future<void> _loadRate() async {
    if (_currency == 'IQD') {
      _rate.text = '1';
      return;
    }
    final db = await erpDb();
    final r = await CurrencyService.rateAt(db, _currency, _date);
    if (mounted) setState(() => _rate.text = fmtMoney(r));
  }

  Future<void> _loadInvoice(int id) async {
    final h = await _svc.invoiceHeader(id);
    if (h == null) {
      if (mounted) showError(context, 'فاتورة الشراء غير موجودة');
      return;
    }
    final allowed = await _svc.returnableFromInvoice(id);
    final items = await _svc.invoiceItems(id);
    final db = await erpDb();
    final lines = <DocLine>[];
    final seen = <String>{};
    for (final it in items) {
      final pid = it['product_id'] as int;
      final key = '$pid|${it['unit_name']}';
      if (seen.contains(key)) continue;
      seen.add(key);
      final p = await ErpStock.byId(db, pid);
      if (p == null) continue;
      final f = d0(it['factor']);
      var u = p.unitNamed(it['unit_name'] as String?);
      if ((u.factor - f).abs() > 1e-9) u = UnitOption('${it['unit_name']}', f);
      lines.add(DocLine(product: p, unit: u, quantity: 0, price: d0(it['unit_price'])));
    }
    final inv = h['supplier_id'] == null ? const <Map<String, Object?>>[] : await _svc.supplierInvoices(h['supplier_id'] as int);
    if (!mounted) return;
    setState(() {
      _supplier = PartyLite(h['supplier_id'] as int, '${h['supplier_name'] ?? ''}', null, 0);
      _invoices = inv;
      _invoiceId = id;
      _invoiceLabel = '${h['invoice_number'] ?? '#$id'}';
      _returnable = allowed;
      _currency = (h['currency'] as String?) ?? 'IQD';
      _lines
        ..clear()
        ..addAll(lines);
    });
    await _loadRate();
  }

  void _returnAll() {
    setState(() {
      for (final l in _lines) {
        final left = _returnable[l.product.id] ?? 0;
        l.quantity = l.unit.factor <= 0 ? 0 : left / l.unit.factor;
        l.rev++;
      }
    });
  }

  Future<void> _save() async {
    final s = _supplier;
    if (s == null) {
      showError(context, 'اختر المورد');
      return;
    }
    if (!await PeriodLock.guard(context, _date)) return;
    final total = linesTotal(_lines.where((l) => l.quantity > 0).toList());
    if (!mounted) return;
    final ok = await confirmDialog(
      context,
      'حفظ مرتجع المشتريات',
      'إرجاع ${_lines.where((l) => l.quantity > 0).length} مادة بقيمة ${fmtMoney(total)} $_currency للمورد «${s.name}».\n'
          '${_mode == 'debt' ? 'يُنزل المبلغ من دين المورد.' : _mode == 'cash' ? 'يستلم الصندوق المبلغ نقداً.' : 'جزء نقداً والباقي من دين المورد.'}',
    );
    if (!ok) return;
    setState(() => _saving = true);
    try {
      final id = await _svc.create(
        supplierId: s.id,
        supplierName: s.name,
        originalInvoiceId: _invoiceId,
        currency: _currency,
        fxRate: parseMoney(_rate.text) ?? 1,
        refundMode: _mode,
        cashAmount: _mode == 'mixed' ? (parseMoney(_cash.text) ?? 0) : 0,
        cashBoxId: _boxId,
        warehouseId: _warehouseId,
        date: _date,
        notes: _notes.text.trim(),
        allowNegative: _allowNegative,
        lines: [
          for (final l in _lines)
            if (l.quantity > 0) PurchaseReturnLine(product: l.product, unit: l.unit, quantity: l.quantity, price: l.netPrice),
        ],
      );
      if (!mounted) return;
      showOk(context, 'حُفظ مرتجع المشتريات');
      final pr = await confirmDialog(context, 'طباعة', 'طباعة مستند المرتجع؟', ok: 'طباعة');
      if (pr && mounted) await printPurchaseReturn(context, id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = linesTotal(_lines);
    final cash = _mode == 'cash' ? total : (_mode == 'mixed' ? (parseMoney(_cash.text) ?? 0) : 0.0);
    return ErpPage(
      title: 'مرتجع مشتريات',
      subtitle: 'إرجاع بضاعة للمورد — من دينه أو نقداً',
      icon: Icons.assignment_return_rounded,
      actions: [
        IconButton(
          tooltip: 'سجل مرتجعات المشتريات',
          icon: const Icon(Icons.history_rounded, color: Colors.white),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseReturnsListScreen())),
        ),
      ],
      bottom: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: Wrap(spacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('الإجمالي: ${fmtMoney(total)} $_currency',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ErpColors.orange)),
                if (_mode != 'debt') Text('نقداً: ${fmtMoney(cash)}', style: const TextStyle(color: ErpColors.green)),
                if (_mode != 'cash')
                  Text('من الدين: ${fmtMoney(roundMoney(total - cash))}', style: const TextStyle(color: ErpColors.blue)),
              ]),
            ),
            PrimaryButton(label: 'حفظ المرتجع', icon: Icons.save_rounded, color: ErpColors.orange, busy: _saving, onPressed: _save),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 20), children: [
        ErpSection(
          title: 'المورد والفاتورة',
          icon: Icons.local_shipping_outlined,
          color: ErpColors.orange,
          child: FieldGrid(children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.person_search),
              label: Text(_supplier?.name ?? 'اختر المورد'),
              onPressed: _pickSupplier,
            ),
            if (_supplier != null)
              DropBox<int?>(
                label: 'فاتورة الشراء (اختياري)',
                width: 300,
                value: _invoices.any((i) => i['id'] == _invoiceId) ? _invoiceId : null,
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('بدون فاتورة')),
                  for (final i in _invoices)
                    DropdownMenuItem<int?>(
                      value: i['id'] as int,
                      child: Text('${i['invoice_number'] ?? '#${i['id']}'} • ${fmtDate(parseDate(i['date']))} • ${fmtMoney(d0(i['total_amount']))}'),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) {
                    setState(() {
                      _invoiceId = null;
                      _invoiceLabel = null;
                      _returnable = const {};
                    });
                  } else {
                    _loadInvoice(v);
                  }
                },
              ),
            if (_invoiceId != null)
              TextButton.icon(onPressed: _returnAll, icon: const Icon(Icons.select_all), label: const Text('إرجاع كل المتبقي')),
            DateButton(
                label: 'التاريخ',
                value: _date,
                onChanged: (d) {
                  setState(() => _date = d);
                  _loadRate();
                }),
            if (_currency != 'IQD') MoneyField(controller: _rate, label: 'سعر الصرف ($_currency)', width: 150),
          ]),
        ),
        ErpSection(
          title: 'الاسترداد والمخزن',
          icon: Icons.payments_outlined,
          color: ErpColors.blue,
          child: FieldGrid(children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'debt', label: Text('من دين المورد'), icon: Icon(Icons.account_balance)),
                ButtonSegment(value: 'cash', label: Text('نقداً'), icon: Icon(Icons.payments)),
                ButtonSegment(value: 'mixed', label: Text('مختلط'), icon: Icon(Icons.call_split)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            if (_mode != 'debt') CashBoxDropdown(value: _boxId, label: 'يُستلم في', onChanged: (b) => setState(() => _boxId = b?.id)),
            if (_mode == 'mixed')
              MoneyField(controller: _cash, label: 'المستلم نقداً', width: 170, onChanged: (_) => setState(() {})),
            WarehouseDropdown(value: _warehouseId, label: 'يخرج من مخزن', onChanged: (w) => setState(() => _warehouseId = w?.id)),
            FilterChip(
              label: const Text('السماح بتجاوز المتوفر'),
              selected: _allowNegative,
              selectedColor: ErpColors.red.withOpacity(.15),
              onSelected: (v) => setState(() => _allowNegative = v),
            ),
            TextBox(controller: _notes, label: 'سبب الإرجاع / ملاحظات', width: 300),
          ]),
        ),
        ErpSection(
          title: _invoiceLabel == null ? 'المواد المُرجعة' : 'المواد المُرجعة من فاتورة $_invoiceLabel',
          icon: Icons.inventory_2_outlined,
          color: ErpColors.orange,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_invoiceId != null && _returnable.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final l in _lines)
                    StatusBadge('${l.product.name}: متاح ${fmtQty(_returnable[l.product.id] ?? 0)} ${l.product.baseUnitName}',
                        color: ErpColors.muted),
                ]),
              ),
            DocLinesEditor(lines: _lines, priceSource: PriceSource.cost, priceLabel: 'سعر الشراء', onChanged: () => setState(() {})),
          ]),
        ),
      ]),
    );
  }
}

/// طباعة مستند مرتجع مشتريات.
Future<void> printPurchaseReturn(BuildContext context, int id) async {
  try {
    final db = await erpDb();
    final h = (await db.query('purchase_returns', where: 'id = ?', whereArgs: [id], limit: 1)).first;
    final items = await PurchaseReturnService().items(id);
    final mode = {'debt': 'من دين المورد', 'cash': 'نقداً', 'mixed': 'مختلط (نقداً ${fmtMoney(purchaseReturnCashPart(h))})'}[h['refund_mode']];
    final bytes = await DocPdf.build(
      title: h['status'] == 'posted' ? 'مرتجع مشتريات' : 'مرتجع مشتريات (ملغى)',
      number: '${h['return_no']}',
      date: parseDate(h['return_date']),
      partyLabel: 'المورد',
      partyName: '${h['supplier_name'] ?? ''}',
      infos: [
        MapEntry('الاسترداد', mode ?? ''),
        if (h['original_invoice_id'] != null) MapEntry('فاتورة الشراء', '#${h['original_invoice_id']}'),
      ],
      headers: const ['#', 'المادة', 'الوحدة', 'الكمية', 'السعر', 'الإجمالي'],
      rows: [
        for (var i = 0; i < items.length; i++)
          [
            '${i + 1}',
            '${items[i]['product_name']}',
            '${items[i]['unit_name'] ?? ''}',
            fmtQty(d0(items[i]['quantity'])),
            fmtMoney(d0(items[i]['price'])),
            fmtMoney(d0(items[i]['total'])),
          ],
      ],
      total: d0(h['total']),
      notes: h['notes'] as String?,
      currency: '${h['currency'] ?? 'IQD'}',
    );
    if (context.mounted) await ReportExport.openPdf(context, bytes, 'مرتجع مشتريات ${h['return_no']}');
  } catch (e) {
    if (context.mounted) showError(context, 'تعذّرت الطباعة: $e');
  }
}

class PurchaseReturnsListScreen extends StatefulWidget {
  const PurchaseReturnsListScreen({super.key});
  @override
  State<PurchaseReturnsListScreen> createState() => _PurchaseReturnsListScreenState();
}

class _PurchaseReturnsListScreenState extends State<PurchaseReturnsListScreen> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  List<Map<String, Object?>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await PurchaseReturnService().list(from: _from, to: _to);
    if (mounted) setState(() => _rows = r);
  }

  String _mode(Map<String, Object?> r) {
    switch (r['refund_mode']) {
      case 'cash':
        return 'نقداً';
      case 'mixed':
        return 'مختلط';
      default:
        return 'من الدين';
    }
  }

  Future<void> _details(Map<String, Object?> r) async {
    final items = await PurchaseReturnService().items(r['id'] as int);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('مرتجع مشتريات رقم ${r['return_no']} — ${r['supplier_name']}'),
        content: SizedBox(
          width: 560,
          child: SimpleTable(
            headers: const ['المادة', 'الوحدة', 'الكمية', 'السعر', 'الإجمالي'],
            numericColumns: const {2, 3, 4},
            rows: [
              for (final i in items)
                ['${i['product_name']}', '${i['unit_name'] ?? ''}', fmtQty(d0(i['quantity'])), fmtMoney(d0(i['price'])), fmtMoney(d0(i['total']))],
            ],
          ),
        ),
        actions: [
          TextButton.icon(
              onPressed: () => printPurchaseReturn(ctx, r['id'] as int), icon: const Icon(Icons.print), label: const Text('طباعة')),
          if (r['status'] == 'posted')
            TextButton(
              onPressed: () async {
                final reason = await askText(ctx, 'سبب الإلغاء');
                if (reason == null || !ctx.mounted) return;
                try {
                  await PurchaseReturnService().voidReturn(r['id'] as int, reason: reason);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  if (ctx.mounted) showError(ctx, e);
                }
              },
              child: const Text('إلغاء المرتجع', style: TextStyle(color: ErpColors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _rows.where((r) => r['status'] == 'posted').fold(0.0, (s, r) => s + d0(r['total']));
    return ErpPage(
      title: 'مرتجعات المشتريات',
      subtitle: '${_rows.length} مرتجع — ${fmtMoney(total)}',
      icon: Icons.assignment_return_outlined,
      actions: [
        ...exportActions(context,
            title: 'مرتجعات المشتريات',
            headers: () => ['الرقم', 'التاريخ', 'المورد', 'الفاتورة', 'الاسترداد', 'المخزن', 'المبلغ', 'العملة', 'الحالة'],
            rows: () => [
                  for (final r in _rows)
                    [
                      '${r['return_no']}',
                      fmtDate(parseDate(r['return_date'])),
                      '${r['supplier_name'] ?? ''}',
                      '${r['invoice_number'] ?? ''}',
                      _mode(r),
                      '${r['warehouse_name'] ?? 'الرئيسي'}',
                      fmtMoney(d0(r['total'])),
                      '${r['currency']}',
                      r['status'] == 'posted' ? 'مرحّل' : 'ملغى',
                    ],
                ]),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: Colors.white),
          tooltip: 'مرتجع جديد',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseReturnEditorScreen()))
              .then((_) => _load()),
        ),
      ],
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(spacing: 8, children: [
            DateButton(label: 'من', value: _from, onChanged: (d) {
              _from = d;
              _load();
            }),
            DateButton(label: 'إلى', value: _to, onChanged: (d) {
              _to = d;
              _load();
            }),
          ]),
        ),
        Expanded(
          child: _rows.isEmpty
              ? const EmptyState('لا توجد مرتجعات مشتريات في الفترة', icon: Icons.assignment_return_outlined)
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    final voided = r['status'] != 'posted';
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12), side: const BorderSide(color: ErpColors.border)),
                      child: ListTile(
                        onTap: () => _details(r),
                        leading: CircleAvatar(
                          backgroundColor: (voided ? ErpColors.muted : ErpColors.orange).withOpacity(.12),
                          child: Text('${r['return_no']}',
                              style: TextStyle(color: voided ? ErpColors.muted : ErpColors.orange, fontSize: 12)),
                        ),
                        title: Text('${r['supplier_name'] ?? ''}',
                            style: TextStyle(decoration: voided ? TextDecoration.lineThrough : null)),
                        subtitle: Text([
                          fmtDate(parseDate(r['return_date'])),
                          _mode(r),
                          if (r['invoice_number'] != null) 'فاتورة ${r['invoice_number']}',
                          '${r['n_items']} مادة',
                        ].join(' • ')),
                        trailing: voided
                            ? const StatusBadge('ملغى', color: ErpColors.muted)
                            : Text('${fmtMoney(d0(r['total']))} ${r['currency'] == 'IQD' ? '' : r['currency']}',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
