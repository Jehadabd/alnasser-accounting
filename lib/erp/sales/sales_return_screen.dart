// lib/erp/sales/sales_return_screen.dart
//
// ↩️ شاشة مرتجع المبيعات + سجل المرتجعات.

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart' show roundMoney;
import '../../accounting/screens/acc_ui.dart';
import '../doc_lines.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../report_export.dart';
import '../stock_helpers.dart';
import 'doc_pdf.dart';
import 'sales_return_service.dart';

class SalesReturnScreen extends StatefulWidget {
  const SalesReturnScreen({super.key, this.invoiceId});
  final int? invoiceId;
  @override
  State<SalesReturnScreen> createState() => _SalesReturnScreenState();
}

class _SalesReturnScreenState extends State<SalesReturnScreen> {
  final _svc = SalesReturnService();
  final _lines = <DocLine>[];
  PartyLite? _customer;
  String _walkInName = '';
  int? _invoiceId;
  Map<int, double> _returnable = const {};
  String _mode = 'credit';
  int? _boxId;
  int? _warehouseId;
  DateTime _date = DateTime.now();
  final _notes = TextEditingController();
  final _invoiceCtrl = TextEditingController();
  final _cashCtrl = TextEditingController();

  /// المتبقي (الآجل) من الفاتورة الأصلية — لاقتراح التقسيم في المرتجع المختلط.
  double? _invRemaining;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.invoiceId != null) {
      _invoiceCtrl.text = '${widget.invoiceId}';
      _loadInvoice();
    }
  }

  Future<void> _loadInvoice() async {
    final id = widget.invoiceId != null && _invoiceCtrl.text.trim() == '${widget.invoiceId}'
        ? widget.invoiceId
        : await _svc.findInvoice(_invoiceCtrl.text);
    if (id == null) {
      if (mounted && _invoiceCtrl.text.trim().isNotEmpty) showError(context, 'لا توجد فاتورة بهذا الرقم');
      return;
    }
    final h = await _svc.invoiceHeader(id);
    if (h == null) {
      if (mounted) showError(context, 'الفاتورة #$id غير موجودة');
      return;
    }
    final allowed = await _svc.returnableFromInvoice(id);
    final db = await erpDb();
    final items = await db.rawQuery('''
      SELECT ii.product_name, ii.sale_type, ii.applied_price, ii.units_in_large_unit, p.id AS pid
      FROM invoice_items ii
      JOIN products p ON (p.sync_uuid = ii.product_sync_uuid OR (ii.product_sync_uuid IS NULL AND p.name = ii.product_name))
      WHERE ii.invoice_id = ? ORDER BY ii.id
    ''', [id]);
    final lines = <DocLine>[];
    final seen = <String>{};
    for (final it in items) {
      final pid = it['pid'] as int;
      final key = '$pid|${it['sale_type']}';
      if (seen.contains(key)) continue;
      seen.add(key);
      final p = await ErpStock.byId(db, pid);
      if (p == null) continue;
      final u = p.unitNamed(it['sale_type'] as String?);
      lines.add(DocLine(product: p, unit: u, quantity: 0, price: d0(it['applied_price'])));
    }
    if (!mounted) return;
    final rem = d0(h['total_amount']) - d0(h['amount_paid_on_invoice']);
    setState(() {
      _invRemaining = rem > 0 ? rem : 0;
      _invoiceId = id;
      _returnable = allowed;
      _lines
        ..clear()
        ..addAll(lines);
      if (h['customer_id'] != null) {
        _customer = PartyLite(h['customer_id'] as int, (h['customer_name'] as String?) ?? '', null, 0);
      } else {
        _walkInName = (h['customer_name'] as String?) ?? '';
        _mode = 'cash';
      }
    });
  }

  /// مثل سهل: يُنزل من دين الفاتورة بقدر آجلها، والباقي يُرد نقداً.
  void _suggestSplit() {
    final total = linesTotal(_lines);
    if (_invRemaining != null && _invRemaining! >= total - 0.004) {
      // آجل الفاتورة يغطي المرتجع كله ⇒ من الحساب بالكامل
      _mode = 'credit';
      _cashCtrl.clear();
      return;
    }
    final credit = _invRemaining ?? roundMoney(total / 2);
    final cash = total - credit;
    _cashCtrl.text = cash <= 0 ? '' : fmtMoney(cash);
  }

  Future<void> _save() async {
    final name = _customer?.name ?? _walkInName.trim();
    if (name.isEmpty) {
      showError(context, 'اختر العميل أو اكتب اسم الزبون');
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await _svc.create(
        context,
        customerId: _customer?.id,
        customerName: name,
        originalInvoiceId: _invoiceId,
        refundMode: _mode,
        cashBoxId: _boxId,
        cashAmount: _mode == 'mixed' ? (parseMoney(_cashCtrl.text) ?? 0) : 0,
        warehouseId: _warehouseId,
        date: _date,
        lines: [
          for (final l in _lines)
            if (l.quantity > 0) ReturnLine(product: l.product, unit: l.unit, quantity: l.quantity, price: l.netPrice),
        ],
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      showOk(context, 'حُفظ المرتجع (#$id)');
      final pr = await confirmDialog(context, 'طباعة', 'طباعة مستند المرتجع؟', ok: 'طباعة');
      if (pr && mounted) await printSalesReturn(context, id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = linesTotal(_lines);
    return ErpPage(
      title: 'مرتجع مبيعات',
      subtitle: 'إعادة بضاعة من زبون — نقداً أو من حسابه',
      icon: Icons.assignment_return,
      bottom: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: Text('إجمالي المرتجع: ${fmtMoney(total)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ErpColors.navy)),
            ),
            PrimaryButton(label: 'حفظ المرتجع', icon: Icons.save, busy: _saving, onPressed: _save),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 20), children: [
        ErpSection(
          title: 'الفاتورة الأصلية (اختياري)',
          icon: Icons.receipt,
          child: FieldGrid(children: [
            SizedBox(
              width: 200,
              child: TextField(
                controller: _invoiceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'رقم الفاتورة', border: OutlineInputBorder(), isDense: true, filled: true,
                    fillColor: Colors.white),
                onSubmitted: (_) => _loadInvoice(),
              ),
            ),
            OutlinedButton.icon(onPressed: _loadInvoice, icon: const Icon(Icons.download), label: const Text('تحميل موادها')),
            if (_invoiceId != null)
              TextButton.icon(
                onPressed: () => setState(() {
                  for (final l in _lines) {
                    final left = _returnable[l.product.id] ?? 0;
                    l.quantity = l.unit.factor <= 0 ? 0 : left / l.unit.factor;
                    l.rev++;
                  }
                }),
                icon: const Icon(Icons.select_all),
                label: const Text('إرجاع كل المتبقي'),
              ),
            if (_invoiceId != null)
              const Text('لا يمكن إرجاع أكثر مما بيع في الفاتورة', style: TextStyle(color: ErpColors.muted)),
          ]),
        ),
        ErpSection(
          title: 'الزبون وطريقة الرد',
          icon: Icons.person_outline,
          color: ErpColors.blue,
          child: FieldGrid(children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.person_search),
              label: Text(_customer?.name ?? 'اختيار عميل مسجّل'),
              onPressed: () async {
                final c = await Pickers.customer(context);
                if (c != null) setState(() => _customer = c);
              },
            ),
            if (_customer == null)
              SizedBox(
                width: 220,
                child: TextField(
                  decoration: const InputDecoration(
                      labelText: 'أو اسم زبون نقدي', border: OutlineInputBorder(), isDense: true, filled: true,
                      fillColor: Colors.white),
                  onChanged: (v) => _walkInName = v,
                ),
              ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'credit', label: Text('من حسابه (ينقص دينه)'), icon: Icon(Icons.account_balance)),
                ButtonSegment(value: 'cash', label: Text('نقداً من الصندوق'), icon: Icon(Icons.payments)),
                ButtonSegment(value: 'mixed', label: Text('مختلط'), icon: Icon(Icons.call_split)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() {
                _mode = s.first;
                if (_mode == 'mixed') _suggestSplit();
              }),
            ),
            if (_mode != 'credit') CashBoxDropdown(value: _boxId, onChanged: (b) => setState(() => _boxId = b?.id)),
            if (_mode == 'mixed') ...[
              MoneyField(controller: _cashCtrl, label: 'المُرجع نقداً', width: 170, onChanged: (_) => setState(() {})),
              Text(
                'يُنزل من الدين: ${fmtMoney(linesTotal(_lines) - (parseMoney(_cashCtrl.text) ?? 0))}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: ErpColors.blue),
              ),
              TextButton.icon(
                onPressed: () => setState(_suggestSplit),
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: Text(_invRemaining == null ? 'اقتراح' : 'اقتراح (آجل الفاتورة ${fmtMoney(_invRemaining!)})'),
              ),
            ],
            WarehouseDropdown(
                value: _warehouseId, label: 'يعود إلى مخزن', onChanged: (w) => setState(() => _warehouseId = w?.id)),
            DateButton(label: 'التاريخ', value: _date, onChanged: (d) => setState(() => _date = d)),
            TextBox(controller: _notes, label: 'سبب الإرجاع / ملاحظات', width: 300),
          ]),
        ),
        ErpSection(
          title: 'المواد المُرجعة',
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
            DocLinesEditor(lines: _lines, onChanged: () => setState(() {}), showDiscount: true),
          ]),
        ),
      ]),
    );
  }
}

class SalesReturnsListScreen extends StatefulWidget {
  const SalesReturnsListScreen({super.key});
  @override
  State<SalesReturnsListScreen> createState() => _SalesReturnsListScreenState();
}

class _SalesReturnsListScreenState extends State<SalesReturnsListScreen> {
  DateTime? _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  List<Map<String, Object?>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await SalesReturnService().list(from: _from, to: _to);
    if (mounted) setState(() => _rows = r);
  }

  Future<void> _details(Map<String, Object?> r) async {
    final items = await SalesReturnService().items(r['id'] as int);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('مرتجع رقم ${r['return_no']} — ${r['customer_name']}'),
        content: SizedBox(
          width: 560,
          child: SimpleTable(
            headers: const ['المادة', 'الوحدة', 'الكمية', 'السعر', 'الإجمالي'],
            numericColumns: const {2, 3, 4},
            rows: [
              for (final i in items)
                ['${i['product_name']}', '${i['sale_type'] ?? ''}', fmtQty(d0(i['quantity'])), fmtMoney(d0(i['price'])),
                  fmtMoney(d0(i['total']))],
            ],
          ),
        ),
        actions: [
          TextButton.icon(
              onPressed: () => printSalesReturn(ctx, r['id'] as int), icon: const Icon(Icons.print), label: const Text('طباعة')),
          if (r['status'] == 'posted')
            TextButton(
              onPressed: () async {
                final reason = await askText(ctx, 'سبب الإلغاء');
                if (reason == null || !ctx.mounted) return;
                try {
                  await SalesReturnService().voidReturn(ctx, r['id'] as int, reason: reason);
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
      title: 'مرتجعات المبيعات',
      subtitle: '${_rows.length} مرتجع — ${fmtMoney(total)}',
      icon: Icons.assignment_return,
      actions: [
        ...exportActions(context,
            title: 'مرتجعات المبيعات',
            headers: () => ['الرقم', 'التاريخ', 'الزبون', 'الفاتورة', 'الرد', 'المبلغ', 'الكلفة', 'الحالة'],
            rows: () => [
                  for (final r in _rows)
                    [
                      '${r['return_no']}',
                      fmtDate(parseDate(r['return_date'])),
                      '${r['customer_name']}',
                      r['original_invoice_id'] == null ? '' : '#${r['original_invoice_id']}',
                      _modeLabel(r),
                      fmtMoney(d0(r['total'])),
                      fmtMoney(d0(r['cost_total'])),
                      r['status'] == 'posted' ? 'مرحّل' : 'ملغى',
                    ],
                ]),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'مرتجع جديد',
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesReturnScreen())).then((_) => _load()),
        ),
      ],
      body: Column(children: [
        PeriodBar(from: _from, to: _to, onChanged: (f, t) {
          _from = f;
          _to = t;
          _load();
        }),
        Expanded(
          child: _rows.isEmpty
              ? const EmptyState('لا توجد مرتجعات في الفترة')
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
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
                          backgroundColor: (voided ? ErpColors.muted : ErpColors.orange).withOpacity(0.12),
                          child: Text('${r['return_no']}',
                              style: TextStyle(color: voided ? ErpColors.muted : ErpColors.orange, fontSize: 12)),
                        ),
                        title: Text('${r['customer_name']}',
                            style: TextStyle(decoration: voided ? TextDecoration.lineThrough : null)),
                        subtitle: Text([
                          fmtDate(parseDate(r['return_date'])),
                          _modeLabel(r),
                          if (r['original_invoice_id'] != null) 'فاتورة #${r['original_invoice_id']}',
                          '${r['n_items']} مادة',
                        ].join(' • ')),
                        trailing: voided
                            ? const StatusBadge('ملغى', color: ErpColors.muted)
                            : MoneyText(d0(r['total']), bold: true),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

String _modeLabel(Map<String, Object?> r) {
  switch (r['refund_mode']) {
    case 'cash':
      return 'نقداً';
    case 'mixed':
      return 'مختلط (نقداً ${fmtMoney(returnCashPart(r))})';
    default:
      return 'من الحساب';
  }
}

/// طباعة مستند مرتجع مبيعات (بالمبلغ كتابةً).
Future<void> printSalesReturn(BuildContext context, int id) async {
  try {
    final db = await erpDb();
    final h = (await db.query('sales_returns', where: 'id = ?', whereArgs: [id], limit: 1)).first;
    final items = await SalesReturnService().items(id);
    final bytes = await DocPdf.build(
      title: h['status'] == 'posted' ? 'مرتجع مبيعات' : 'مرتجع مبيعات (ملغى)',
      number: '${h['return_no']}',
      date: parseDate(h['return_date']),
      partyLabel: 'الزبون',
      partyName: '${h['customer_name'] ?? ''}',
      infos: [
        MapEntry('طريقة الرد', _modeLabel(h)),
        if (h['original_invoice_id'] != null) MapEntry('الفاتورة الأصلية', '#${h['original_invoice_id']}'),
      ],
      headers: const ['#', 'المادة', 'الوحدة', 'الكمية', 'السعر', 'الإجمالي'],
      rows: [
        for (var i = 0; i < items.length; i++)
          [
            '${i + 1}',
            '${items[i]['product_name']}',
            '${items[i]['sale_type'] ?? ''}',
            fmtQty(d0(items[i]['quantity'])),
            fmtMoney(d0(items[i]['price'])),
            fmtMoney(d0(items[i]['total'])),
          ],
      ],
      total: d0(h['total']),
      notes: h['notes'] as String?,
    );
    if (context.mounted) await ReportExport.openPdf(context, bytes, 'مرتجع مبيعات ${h['return_no']}');
  } catch (e) {
    if (context.mounted) showError(context, 'تعذّرت الطباعة: $e');
  }
}
