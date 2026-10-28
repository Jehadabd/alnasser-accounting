// lib/erp/sales/sales_return_screen.dart
//
// ↩️ شاشة مرتجع المبيعات + سجل المرتجعات.

import '../../services/save_lock.dart'; // 🔒 قفل الحفظ
import 'package:flutter/material.dart';

import '../../accounting/ledger.dart' show roundMoney;
import '../debts/customer_money.dart' show CustomerMoney;
import '../../accounting/screens/acc_ui.dart';
import '../doc_lines.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../report_export.dart';
import '../stock_helpers.dart';
import 'doc_pdf.dart';
import 'sales_return_service.dart';
import '../../services/settings_manager.dart';
import '../../services/invoice_edit_log.dart';

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

  /// الفاتورة المفتوحة من «تعديل الفواتير» (بمعرّفها الداخلي) — تُحمَّل مرة واحدة.
  int? _presetId;

  /// رأس الفاتورة المحمّلة (رقمها المطبوع، التاريخ، المجموع).
  Map<String, Object?>? _invHeader;

  @override
  void initState() {
    super.initState();
    if (widget.invoiceId != null) {
      _presetId = widget.invoiceId;
      _loadInvoice();
    }
  }

  /// يفك ربط الفاتورة: مرتجع حر بلا فاتورة (أي مادة).
  void _unlinkInvoice() => setState(() {
        _invoiceId = null;
        _invHeader = null;
        _returnable = const {};
        _invRemaining = null;
        _lines.clear();
        _invoiceCtrl.clear();
      });

  Future<void> _loadInvoice() async {
    final preset = _presetId;
    _presetId = null;
    final id = preset ?? await _svc.findInvoice(_invoiceCtrl.text);
    if (id == null) {
      if (mounted && _invoiceCtrl.text.trim().isNotEmpty) showError(context, 'لا توجد فاتورة بهذا الرقم');
      return;
    }
    final h = await _svc.invoiceHeader(id);
    if (h == null) {
      if (mounted) showError(context, 'الفاتورة غير موجودة');
      return;
    }
    // 🔒 فاتورة من جهاز آخر: لا تُحمَّل إلا لجهازها أو لمحاسبها
    final blocked = await _svc.returnBlockReason(id);
    if (blocked != null) {
      if (mounted) showError(context, blocked);
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
    final number = (h['invoice_number'] as String?)?.trim();
    setState(() {
      _invHeader = h;
      // الرقم المطبوع على الفاتورة، لا المعرّف الداخلي
      _invoiceCtrl.text = (number != null && number.isNotEmpty) ? number : '#$id';
      _invRemaining = rem > 0 ? rem : 0;
      _invoiceId = id;
      _returnable = allowed;
      _lines
        ..clear()
        ..addAll(lines);
      if (h['customer_id'] != null) {
        _customer = PartyLite(h['customer_id'] as int, (h['customer_name'] as String?) ?? '', null, 0);
        // فاتورة مدفوعة بالكامل لا دين فيها يُنزل منه: الردّ الطبيعي نقداً.
        // (كان الافتراضي «من حسابه» دائماً، فيصير العميل دائناً دون قصد.)
        _mode = rem > 0 ? 'credit' : 'cash';
      } else {
        _walkInName = (h['customer_name'] as String?) ?? '';
        _mode = 'cash';
      }
    });
  }

  /// المواد التي تجاوزت كميتها المتبقي في الفاتورة (بالوحدة الأساسية).
  Set<int> _overReturned() {
    if (_invoiceId == null) return const {};
    final want = <int, double>{};
    for (final l in _lines) {
      want[l.product.id] = (want[l.product.id] ?? 0) + l.baseQty;
    }
    return {
      for (final e in want.entries)
        if (e.value > (_returnable[e.key] ?? 0) + 1e-6) e.key
    };
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

  /// الردّ «من حسابه» يُنزل دين العميل؛ إن تجاوز دينه الحالي يصير العميل
  /// دائناً (له عندكم مال). لا يحدث ذلك إلا بتأكيد صريح.
  Future<bool> _confirmCreditBalance() async {
    final customer = _customer;
    if (customer == null || _mode == 'cash') return true;
    final total = linesTotal(_lines);
    final credit = _mode == 'mixed' ? total - (parseMoney(_cashCtrl.text) ?? 0) : total;
    if (credit <= 0) return true;
    final balance = await CustomerMoney.balance(await erpDb(), customer.id);
    final after = roundMoney(balance - credit);
    if (after >= 0) return true;
    if (!mounted) return false;
    return confirmDialog(
      context,
      'سيصبح للعميل رصيد دائن',
      'دين «${customer.name}» الآن ${fmtMoney(balance)}، والمرتجع من حسابه ${fmtMoney(credit)}.\n'
          'بعد الحفظ يصبح له عندكم ${fmtMoney(-after)}.\n\n'
          'إن أعدتم له المبلغ نقداً فاختر «نقداً من الصندوق» بدلاً من ذلك.',
      ok: 'حفظ ويصبح دائناً',
      color: AccColors.red,
    );
  }

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط (القفل قبل أي انتظار)
  Future<void> _save() async {
    await SaveLock.run(() => _saveUnlocked(), message: 'جارٍ حفظ المرتجع…');
  }
  Future<void> _saveUnlocked() async {
    final name = _customer?.name ?? _walkInName.trim();
    if (name.isEmpty) {
      showError(context, 'اختر العميل أو اكتب اسم الزبون');
      return;
    }
    if (!await _confirmCreditBalance()) return;
    if (!mounted) return;
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
      // رسالة الطباعة حسب الإعداد: اسأل / اطبع دائماً / لا تطبع
      final mode = (await SettingsManager.getAppSettings()).adjustmentVoucherMode;
      if (!mounted) return;
      final pr = mode == 'always'
          ? true
          : mode == 'never'
              ? false
              : await confirmDialog(context, 'طباعة', 'طباعة مستند المرتجع؟', ok: 'طباعة');
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
    final over = _overReturned();
    return ErpPage(
      title: 'مرتجع مبيعات',
      subtitle: _invoiceId == null
          ? 'إعادة بضاعة من زبون — نقداً أو من حسابه'
          : 'من فاتورة ${_invoiceCtrl.text} — موادها فقط وبكمياتها المتبقية',
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
            PrimaryButton(label: 'حفظ المرتجع', icon: Icons.save, busy: _saving, onPressed: over.isEmpty ? _save : null),
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
                readOnly: _invoiceId != null,
                decoration: const InputDecoration(
                    labelText: 'رقم الفاتورة (المطبوع)', border: OutlineInputBorder(), isDense: true, filled: true,
                    fillColor: Colors.white),
                onSubmitted: (_) => _loadInvoice(),
              ),
            ),
            if (_invoiceId == null)
              OutlinedButton.icon(onPressed: _loadInvoice, icon: const Icon(Icons.download), label: const Text('تحميل موادها'))
            else
              OutlinedButton.icon(
                onPressed: _unlinkInvoice,
                icon: const Icon(Icons.link_off),
                label: const Text('مرتجع بلا فاتورة'),
              ),
            if (_invHeader != null)
              StatusBadge(
                  '${_invHeader!['customer_name'] ?? ''} • ${fmtDate(parseDate(_invHeader!['invoice_date']))} • ${fmtMoney(d0(_invHeader!['total_amount']))}',
                  color: ErpColors.navy),
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
                  for (final pid in {for (final l in _lines) l.product.id})
                    StatusBadge(
                        '${_lines.firstWhere((l) => l.product.id == pid).product.name}: '
                        'متاح ${fmtQty(_returnable[pid] ?? 0)} ${_lines.firstWhere((l) => l.product.id == pid).product.baseUnitName}'
                        '${over.contains(pid) ? ' — تجاوزت المتاح' : ''}',
                        color: over.contains(pid) ? ErpColors.red : ErpColors.muted),
                ]),
              ),
            if (_invoiceId != null)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('المواد من الفاتورة فقط — اكتب كمية المُرجع لكل مادة، أو احذف ما لن يُرجع.',
                    style: TextStyle(color: ErpColors.muted)),
              ),
            DocLinesEditor(
              lines: _lines,
              onChanged: () => setState(() {}),
              showDiscount: true,
              // من فاتورة: لا بحث ولا إضافة مواد ليست فيها
              allowAdd: _invoiceId == null,
            ),
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

  /// ما نقص من الفواتير بتعديلها (حذف مادة أو إنقاص كميتها) — للعرض.
  List<Map<String, Object?>> _editRows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await SalesReturnService().list(from: _from, to: _to);
    final e = await InvoiceEditLog.returnsInPeriod(await erpDb(), from: _from ?? DateTime(2000), to: _to);
    if (mounted) {
      setState(() {
        _rows = r;
        _editRows = e;
      });
    }
  }

  Widget _editCard(Map<String, Object?> r) {
    final n = (r['invoice_number'] as String?)?.trim();
    final inv = (n != null && n.isNotEmpty) ? n : '#${r['invoice_id']}';
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: ErpColors.border)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: ErpColors.purple.withValues(alpha: 0.12),
          child: const Icon(Icons.edit_note_rounded, color: ErpColors.purple, size: 20),
        ),
        title: Text('${r['product_name']}  ${fmtQty(d0(r['qty_before']))} ← ${fmtQty(d0(r['qty_after']))} ${r['unit'] ?? ''}'),
        subtitle: Text([
          fmtDate(parseDate(r['edited_at'])),
          '${r['customer_name'] ?? ''}',
          'فاتورة $inv',
          if ((r['edited_by'] as String?)?.isNotEmpty ?? false) '👤 ${r['edited_by']}',
        ].join(' • ')),
        trailing: MoneyText(InvoiceEditLog.returnedAmount(r), bold: true),
      ),
    );
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
    final editTotal = _editRows.fold(0.0, (s, r) => s + InvoiceEditLog.returnedAmount(r));
    return ErpPage(
      title: 'مرتجعات المبيعات',
      subtitle: '${fmtQty(_rows.length)} مرتجع — ${fmtMoney(total)}'
          '${_editRows.isEmpty ? '' : ' • بتعديل الفواتير ${fmtQty(_editRows.length)} — ${fmtMoney(editTotal)}'}',
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
                      _invLabel(r),
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
          child: _rows.isEmpty && _editRows.isEmpty
              ? const EmptyState('لا توجد مرتجعات في الفترة')
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _rows.length + (_editRows.isEmpty ? 0 : _editRows.length + 1),
                  itemBuilder: (_, i) {
                    if (i >= _rows.length) {
                      final k = i - _rows.length;
                      if (k == 0) {
                        return const Padding(
                          padding: EdgeInsets.fromLTRB(8, 14, 8, 6),
                          child: Text('بتعديل الفواتير (حذف مادة أو إنقاص كميتها بعد الحفظ)',
                              style: TextStyle(fontWeight: FontWeight.bold, color: ErpColors.purple)),
                        );
                      }
                      return _editCard(_editRows[k - 1]);
                    }
                    final r = _rows[i];
                    final voided = r['status'] != 'posted';
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12), side: const BorderSide(color: ErpColors.border)),
                      child: ListTile(
                        onTap: () => _details(r),
                        leading: CircleAvatar(
                          backgroundColor: (voided ? ErpColors.muted : ErpColors.orange).withValues(alpha: 0.12),
                          child: Text('${r['return_no']}',
                              style: TextStyle(color: voided ? ErpColors.muted : ErpColors.orange, fontSize: 12)),
                        ),
                        title: Text('${r['customer_name']}',
                            style: TextStyle(decoration: voided ? TextDecoration.lineThrough : null)),
                        subtitle: Text([
                          fmtDate(parseDate(r['return_date'])),
                          _modeLabel(r),
                          if (r['original_invoice_id'] != null) 'فاتورة ${_invLabel(r)}',
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

/// رقم الفاتورة الأصلية المطبوع (أو #المعرّف للقديمة).
String _invLabel(Map<String, Object?> r) {
  if (r['original_invoice_id'] == null) return '';
  final n = (r['invoice_number'] as String?)?.trim();
  return (n != null && n.isNotEmpty) ? n : '#${r['original_invoice_id']}';
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
    final h = (await db.rawQuery(
            'SELECT r.*, (SELECT inv.invoice_number FROM invoices inv WHERE inv.id = r.original_invoice_id) AS invoice_number '
            'FROM sales_returns r WHERE r.id = ? LIMIT 1',
            [id]))
        .first;
    final items = await SalesReturnService().items(id);
    final bytes = await DocPdf.build(
      title: h['status'] == 'posted' ? 'مرتجع مبيعات' : 'مرتجع مبيعات (ملغى)',
      number: '${h['return_no']}',
      date: parseDate(h['return_date']),
      partyLabel: 'الزبون',
      partyName: '${h['customer_name'] ?? ''}',
      infos: [
        MapEntry('طريقة الرد', _modeLabel(h)),
        if (h['original_invoice_id'] != null) MapEntry('الفاتورة الأصلية', _invLabel(h)),
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
