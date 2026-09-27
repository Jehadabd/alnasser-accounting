// lib/erp/debts/receipt_screen.dart
//
// 🧾 شاشة وصل القبض — مفرد أو مركّب، بعملة، مع حسم وعمولة تحصيل وطباعة.

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart';
import '../../accounting/screens/acc_ui.dart';
import '../../accounting/vouchers_service.dart';
import '../arabic_words.dart';
import '../currency_service.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../report_export.dart';
import 'receipt_pdf.dart';
import 'receipts_service.dart';

class _Line {
  _Line(this.customer);
  final PartyLite customer;
  final amount = TextEditingController();
  final discount = TextEditingController();
  final note = TextEditingController();
}

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, this.customer});
  final PartyLite? customer;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final _lines = <_Line>[];
  DateTime _date = DateTime.now();
  int? _boxId;
  String _boxName = '';
  List<Currency> _currencies = const [];
  String _currency = 'IQD';
  final _rate = TextEditingController(text: '1');
  final _docNo = TextEditingController();
  final _notes = TextEditingController();
  final _commission = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.customer != null) _lines.add(_Line(widget.customer!));
    CurrencyService().all().then((c) {
      if (mounted) setState(() => _currencies = c);
    });
  }

  bool get _isBase => _currency == 'IQD';
  double get _fx => parseMoney(_rate.text) ?? 1;

  double _lineBase(_Line l) {
    final a = parseMoney(l.amount.text) ?? 0;
    return _isBase ? a : roundMoney(a * _fx);
  }

  double get _total => _lines.fold(0.0, (s, l) => s + _lineBase(l));
  double get _totalFc => _lines.fold(0.0, (s, l) => s + (parseMoney(l.amount.text) ?? 0));
  double get _totalDisc => _lines.fold(0.0, (s, l) => s + (parseMoney(l.discount.text) ?? 0));

  Future<void> _pickCurrency(String code) async {
    final db = await erpDb();
    final r = await CurrencyService.rateAt(db, code, _date);
    setState(() {
      _currency = code;
      _rate.text = code == 'IQD' ? '1' : fmtMoney(r);
    });
  }

  Future<void> _addCustomer() async {
    final c = await Pickers.customer(context);
    if (c == null) return;
    if (_lines.any((l) => l.customer.id == c.id)) {
      showError(context, 'العميل موجود في الوصل');
      return;
    }
    setState(() => _lines.add(_Line(c)));
  }

  Future<void> _save() async {
    if (_boxId == null) {
      showError(context, 'اختر الصندوق');
      return;
    }
    if (_lines.isEmpty) {
      showError(context, 'أضف عميلاً');
      return;
    }
    // تنبيه: تسديد يجعل الرصيد دائناً (دفعة مقدمة)
    for (final l in _lines) {
      final after = l.customer.balance - _lineBase(l) - (parseMoney(l.discount.text) ?? 0);
      if (after < -0.01) {
        final ok = await confirmDialog(context, 'رصيد دائن',
            'بعد الوصل يصبح رصيد «${l.customer.name}» دائناً (${fmtMoney(after)}) — أي دفعة مقدمة لصالحه. متابعة؟');
        if (!ok) return;
      }
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final res = await ReceiptsService().createCustomerReceipt(
        context,
        date: _date,
        cashBoxId: _boxId!,
        currency: _currency,
        fxRate: _isBase ? 1 : _fx,
        lines: [
          for (final l in _lines)
            ReceiptLineInput(
              customerId: l.customer.id,
              customerName: l.customer.name,
              amountFc: parseMoney(l.amount.text) ?? 0,
              discount: parseMoney(l.discount.text) ?? 0,
              note: l.note.text.trim(),
            ),
        ],
        commission: parseMoney(_commission.text) ?? 0,
        docNo: _docNo.text.trim(),
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      if (res.errors.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('بعض الأسطر لم تُحفظ'),
            content: Text(res.errors.join('\n')),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
          ),
        );
      }
      if (!mounted) return;
      final print = await confirmDialog(context, 'تم حفظ الوصل رقم ${res.receiptNo}', 'هل تريد طباعة الوصل؟',
          ok: 'طباعة');
      if (print) {
        final lines = await ReceiptsService().receiptLines(res.receiptId);
        final bytes = await ReceiptPdf.build(
          title: 'وصل قبض',
          number: res.receiptNo,
          date: _date,
          boxName: _boxName,
          currency: _currency,
          fxRate: _isBase ? 1 : _fx,
          lines: lines,
          docNo: _docNo.text.trim(),
          notes: _notes.text.trim(),
          commission: parseMoney(_commission.text) ?? 0,
        );
        if (mounted) await ReportExport.openPdf(context, bytes, 'وصل_قبض_${res.receiptNo}');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'وصل قبض',
      subtitle: _lines.length > 1 ? 'وصل مركّب — ${_lines.length} عملاء' : 'قبض من عميل مع حسم وعمولة تحصيل',
      icon: Icons.receipt_long,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          ErpSection(
            title: 'بيانات الوصل',
            icon: Icons.info_outline,
            child: FieldGrid(children: [
              DateButton(label: 'التاريخ', value: _date, onChanged: (d) => setState(() => _date = d)),
              CashBoxDropdown(
                value: _boxId,
                onChanged: (b) => setState(() {
                  _boxId = b?.id;
                  _boxName = b?.name ?? '';
                }),
              ),
              DropBox<String>(
                label: 'العملة',
                width: 170,
                value: _currencies.any((c) => c.code == _currency) ? _currency : null,
                items: [for (final c in _currencies) DropdownMenuItem(value: c.code, child: Text(c.name))],
                onChanged: (v) {
                  if (v != null) _pickCurrency(v);
                },
              ),
              if (!_isBase)
                MoneyField(controller: _rate, label: 'سعر التعادل', width: 140, onChanged: (_) => setState(() {})),
              TextBox(controller: _docNo, label: 'رقم المستند الورقي', width: 170),
              TextBox(controller: _notes, label: 'البيان', width: 320),
            ]),
          ),
          ErpSection(
            title: 'العملاء',
            icon: Icons.people_alt_outlined,
            color: ErpColors.blue,
            trailing: TextButton.icon(
              onPressed: _addCustomer,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('إضافة عميل'),
            ),
            child: _lines.isEmpty
                ? const EmptyState('أضف عميلاً واحداً (وصل مفرد) أو أكثر (وصل مركّب)', icon: Icons.group_add)
                : Column(children: [for (var i = 0; i < _lines.length; i++) _lineCard(i)]),
          ),
          ErpSection(
            title: 'الإجمالي',
            icon: Icons.calculate_outlined,
            color: ErpColors.green,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 10, runSpacing: 10, children: [
                StatCard(label: 'المقبوض (دينار)', value: fmtMoney(_total), icon: Icons.payments, color: ErpColors.green),
                if (!_isBase)
                  StatCard(label: 'المقبوض ($_currency)', value: fmtMoney(_totalFc), icon: Icons.currency_exchange, color: ErpColors.blue),
                StatCard(label: 'الحسم', value: fmtMoney(_totalDisc), icon: Icons.discount, color: ErpColors.orange),
                SizedBox(
                  width: 210,
                  child: MoneyField(controller: _commission, label: 'عمولة التحصيل (من الصندوق)'),
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ErpColors.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _isBase ? ArabicWords.money(_total) : ArabicWords.money(_totalFc, currency: _currency),
                  style: const TextStyle(fontWeight: FontWeight.w600, color: ErpColors.navy),
                ),
              ),
            ]),
          ),
        ],
      ),
      bottom: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: PrimaryButton(label: 'حفظ الوصل', icon: Icons.save, busy: _saving, onPressed: _save),
        ),
      ),
    );
  }

  Widget _lineCard(int i) {
    final l = _lines[i];
    final base = _lineBase(l);
    final disc = parseMoney(l.discount.text) ?? 0;
    final after = l.customer.balance - base - disc;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ErpColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(
            backgroundColor: ErpColors.blue.withOpacity(0.12),
            child: Text('${i + 1}', style: const TextStyle(color: ErpColors.blue, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(l.customer.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          IconButton(
            tooltip: 'حذف السطر',
            icon: const Icon(Icons.delete_outline, color: ErpColors.red),
            onPressed: () => setState(() => _lines.removeAt(i)),
          ),
        ]),
        const SizedBox(height: 8),
        FieldGrid(children: [
          InfoTile('الرصيد الحالي', fmtMoney(l.customer.balance), width: 140),
          MoneyField(
              controller: l.amount,
              label: _isBase ? 'المبلغ المقبوض' : 'المبلغ ($_currency)',
              width: 170,
              onChanged: (_) => setState(() {})),
          if (!_isBase) InfoTile('بالدينار', fmtMoney(base), width: 120),
          MoneyField(controller: l.discount, label: 'حسم (دينار)', width: 140, onChanged: (_) => setState(() {})),
          InfoTile('الرصيد بعد الوصل', fmtMoney(after),
              width: 150, color: after < -0.01 ? ErpColors.orange : ErpColors.green),
          TextBox(controller: l.note, label: 'ملاحظة', width: 220),
        ]),
      ]),
    );
  }
}

/// سجل وصولات القبض.
class ReceiptsListScreen extends StatefulWidget {
  const ReceiptsListScreen({super.key});
  @override
  State<ReceiptsListScreen> createState() => _ReceiptsListScreenState();
}

class _ReceiptsListScreenState extends State<ReceiptsListScreen> {
  DateTime? _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  List<Map<String, Object?>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ReceiptsService().receipts(from: _from, to: _to);
    if (mounted) setState(() => _rows = r);
  }

  List<String> get _headers => ['الرقم', 'التاريخ', 'العملاء', 'الصندوق', 'المبلغ', 'الحسم', 'العملة', 'المستند'];
  List<List<String>> get _data => [
        for (final r in _rows)
          [
            '${r['receipt_no']}',
            fmtDate(parseDate(r['receipt_date'])),
            '${r['customers'] ?? ''}',
            '${r['box_name'] ?? ''}',
            fmtMoney(d0(r['total_amount'])),
            fmtMoney(d0(r['total_discount'])),
            '${r['currency']}',
            '${r['doc_no'] ?? ''}',
          ],
      ];

  Future<void> _print(Map<String, Object?> r) async {
    final lines = await ReceiptsService().receiptLines(r['id'] as int);
    final bytes = await ReceiptPdf.build(
      title: 'وصل قبض',
      number: r['receipt_no'] as int,
      date: parseDate(r['receipt_date']),
      boxName: '${r['box_name'] ?? ''}',
      currency: (r['currency'] as String?) ?? 'IQD',
      fxRate: d0(r['fx_rate']),
      lines: lines,
      docNo: r['doc_no'] as String?,
      notes: r['notes'] as String?,
      commission: d0(r['commission']),
    );
    if (mounted) await ReportExport.openPdf(context, bytes, 'وصل_قبض_${r['receipt_no']}');
  }

  @override
  Widget build(BuildContext context) {
    final total = _rows.fold<double>(0, (s, r) => s + d0(r['total_amount']));
    return ErpPage(
      title: 'سجل وصولات القبض',
      subtitle: '${_rows.length} وصل — المجموع ${fmtMoney(total)}',
      icon: Icons.history_edu,
      actions: [
        ...exportActions(context,
            title: 'وصولات القبض', headers: () => _headers, rows: () => _data),
        IconButton(
          tooltip: 'وصل جديد',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceiptScreen()))
              .then((_) => _load()),
        ),
      ],
      body: Column(children: [
        PeriodBar(
          from: _from,
          to: _to,
          onChanged: (f, t) {
            _from = f;
            _to = t;
            _load();
          },
        ),
        Expanded(
          child: _rows.isEmpty
              ? const EmptyState('لا توجد وصولات في الفترة')
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14), side: const BorderSide(color: ErpColors.border)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: ErpColors.green.withOpacity(0.12),
                          child: Text('${r['receipt_no']}',
                              style: const TextStyle(color: ErpColors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        title: Text('${r['customers'] ?? '—'}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${fmtDate(parseDate(r['receipt_date']))} • ${r['box_name'] ?? ''}${(r['doc_no'] as String?)?.isNotEmpty == true ? ' • مستند ${r['doc_no']}' : ''}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              MoneyText(d0(r['total_amount']), bold: true),
                              if (d0(r['total_discount']) > 0)
                                Text('حسم ${fmtMoney(d0(r['total_discount']))}',
                                    style: const TextStyle(fontSize: 11, color: ErpColors.orange)),
                            ],
                          ),
                          IconButton(icon: const Icon(Icons.print_outlined), onPressed: () => _print(r)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

/// دفعة لمورد: نقداً/بنك/شيك/خصم مكتسب، بعملة ومن صندوق محدد.
class SupplierPaymentScreen extends StatefulWidget {
  const SupplierPaymentScreen({super.key});
  @override
  State<SupplierPaymentScreen> createState() => _SupplierPaymentScreenState();
}

class _SupplierPaymentScreenState extends State<SupplierPaymentScreen> {
  PartyLite? _supplier;
  DateTime _date = DateTime.now();
  String _method = 'cash';
  String _currency = 'IQD';
  int? _boxId;
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _docNo = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;

  static const _methods = {
    'cash': 'نقداً من صندوق',
    'bank': 'تحويل بنكي',
    'cheque': 'شيك / ورقة دفع',
    'discount': 'خصم مكتسب من المورد',
  };

  Future<void> _loadRate() async {
    if (_currency == 'IQD') return;
    final db = await erpDb();
    final r = await CurrencyService.rateAt(db, _currency, _date);
    if (mounted) setState(() => _rate.text = fmtMoney(r));
  }

  Future<void> _save() async {
    final amt = parseMoney(_amount.text) ?? 0;
    if (_supplier == null) {
      showError(context, 'اختر المورد');
      return;
    }
    if (amt <= 0) {
      showError(context, 'أدخل المبلغ');
      return;
    }
    if ((_method == 'cash') && _boxId == null) {
      showError(context, 'اختر الصندوق');
      return;
    }
    setState(() => _saving = true);
    try {
      await ReceiptsService().supplierPayment(
        supplierId: _supplier!.id,
        amount: amt,
        currency: _currency,
        method: _method,
        date: _date,
        cashBoxId: _method == 'cash' || _method == 'bank' ? _boxId : null,
        fxRate: _currency == 'IQD' ? null : parseMoney(_rate.text),
        docNo: _docNo.text.trim(),
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      showOk(context, 'تم تسجيل الدفعة');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'دفعة لمورد',
      subtitle: 'نقداً، بنك، شيك، أو خصم مكتسب',
      icon: Icons.outbox,
      body: ListView(children: [
        ErpSection(
          title: 'المورد',
          icon: Icons.local_shipping_outlined,
          color: ErpColors.orange,
          child: Row(children: [
            Expanded(
              child: _supplier == null
                  ? const Text('لم يُختر مورد', style: TextStyle(color: ErpColors.muted))
                  : Wrap(spacing: 20, children: [
                      InfoTile('المورد', _supplier!.name, width: 220),
                      InfoTile('الرصيد (دينار)', fmtMoney(_supplier!.balance)),
                      InfoTile('الرصيد (دولار)', fmtMoney(_supplier!.balanceUsd)),
                    ]),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('اختيار'),
              onPressed: () async {
                final s = await Pickers.supplier(context);
                if (s != null) setState(() => _supplier = s);
              },
            ),
          ]),
        ),
        ErpSection(
          title: 'الدفعة',
          icon: Icons.payments_outlined,
          child: FieldGrid(children: [
            DateButton(label: 'التاريخ', value: _date, onChanged: (d) {
              setState(() => _date = d);
              _loadRate();
            }),
            DropBox<String>(
              label: 'طريقة الدفع',
              value: _method,
              items: [for (final e in _methods.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _method = v ?? 'cash'),
            ),
            DropBox<String>(
              label: 'العملة',
              width: 150,
              value: _currency,
              items: const [
                DropdownMenuItem(value: 'IQD', child: Text('دينار')),
                DropdownMenuItem(value: 'USD', child: Text('دولار')),
              ],
              onChanged: (v) {
                setState(() => _currency = v ?? 'IQD');
                _loadRate();
              },
            ),
            MoneyField(controller: _amount, label: 'المبلغ', width: 180),
            if (_currency != 'IQD') MoneyField(controller: _rate, label: 'سعر التعادل', width: 140),
            if (_method == 'cash' || _method == 'bank')
              CashBoxDropdown(value: _boxId, onChanged: (b) => setState(() => _boxId = b?.id)),
            TextBox(controller: _docNo, label: 'رقم المستند/الشيك', width: 180),
            TextBox(controller: _notes, label: 'البيان', width: 300),
          ]),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: PrimaryButton(label: 'حفظ الدفعة', icon: Icons.save, busy: _saving, onPressed: _save),
        ),
      ]),
    );
  }
}

/// أداة مساعدة: اسم الصندوق من رقمه.
Future<String> cashBoxName(int? id) async {
  if (id == null) return '';
  final boxes = await VouchersService().cashBoxes(activeOnly: false);
  for (final b in boxes) {
    if (b.id == id) return b.name;
  }
  return '';
}

double receiptRound(double v) => roundMoney(v);
