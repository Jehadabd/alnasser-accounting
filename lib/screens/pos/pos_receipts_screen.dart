// lib/screens/pos/pos_receipts_screen.dart
//
// 🧾 إيصالات الكاشير — على طريقة أنظمة البيع العالمية (Square، Loyverse، Odoo POS):
//   • قائمة الإيصالات مع بحث وتصفية بالتاريخ ونوع الدفع، وملخص الفترة.
//   • تفاصيل الإيصال كما طُبع: المواد، الخصم، المدفوع، الباقي، والكاشير.
//   • الإيصال المكتمل لا يُعدَّل من الكاشير: التصحيح يكون بـ«مرتجع» (كلي أو جزئي)
//     ثم بيع جديد، وتبقى إعادة الطباعة متاحة («نسخة»).
//   • «عرض كامل» يفتح الفاتورة للعرض؛ تعديلها (بصلاحية «تعديل الفواتير») يُسجَّل في سجلها.
//
// قراءة فقط: هذه الشاشة لا تغيّر أي رصيد أو مخزون بنفسها.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../accounting/screens/acc_ui.dart' show requirePermission;
import '../../erp/sales/sales_return_screen.dart';
import '../../models/app_user.dart';
import '../../models/invoice.dart';
import '../../models/invoice_item.dart';
import '../../services/database_service.dart';
import '../../services/thermal_receipt_service.dart';
import '../create_invoice_screen.dart';

enum _Range { today, yesterday, week, month, all }

class PosReceiptsScreen extends StatefulWidget {
  const PosReceiptsScreen({super.key});

  @override
  State<PosReceiptsScreen> createState() => _PosReceiptsScreenState();
}

class _Row {
  _Row(this.m);
  final Map<String, Object?> m;
  int get id => m['id'] as int;
  String get number {
    final n = m['invoice_number'] as String?;
    return (n != null && n.isNotEmpty) ? n : '#${id.toString().padLeft(5, '0')}';
  }

  String get customer => (m['customer_name'] as String?)?.trim().isNotEmpty == true ? m['customer_name'] as String : 'عميل نقدي';
  double get total => (m['total_amount'] as num?)?.toDouble() ?? 0;
  double get returned => (m['returned'] as num?)?.toDouble() ?? 0;
  String get payment => (m['payment_type'] as String?) ?? 'نقد';
  String get status => (m['status'] as String?) ?? 'محفوظة';
  String? get cashier => m['created_by_username'] as String?;
  DateTime get date => DateTime.tryParse('${m['invoice_date']}') ?? DateTime.now();
}

class _PosReceiptsScreenState extends State<PosReceiptsScreen> {
  static final _money = NumberFormat('#,##0.##', 'en');
  static final _time = DateFormat('HH:mm');
  static final _day = DateFormat('yyyy/MM/dd');

  final _search = TextEditingController();
  _Range _range = _Range.today;
  String? _payment; // null = الكل
  bool _loading = true;
  List<_Row> _rows = const [];
  _Row? _selected;

  // ملخص الفترة
  int _count = 0;
  double _cash = 0, _credit = 0, _returns = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  (String?, String?) _bounds() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String d(DateTime x) => DateFormat('yyyy-MM-dd').format(x);
    switch (_range) {
      case _Range.today:
        return (d(today), d(today.add(const Duration(days: 1))));
      case _Range.yesterday:
        return (d(today.subtract(const Duration(days: 1))), d(today));
      case _Range.week:
        return (d(today.subtract(const Duration(days: 6))), d(today.add(const Duration(days: 1))));
      case _Range.month:
        return (d(DateTime(now.year, now.month, 1)), d(today.add(const Duration(days: 1))));
      case _Range.all:
        return (null, null);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final db = await DatabaseService().database;
      final (from, to) = _bounds();
      final where = <String>['COALESCE(i.is_deleted, 0) = 0'];
      final args = <Object?>[];
      if (from != null) {
        where.add('i.invoice_date >= ? AND i.invoice_date < ?');
        args.addAll([from, to]);
      }
      if (_payment != null) {
        where.add('i.payment_type = ?');
        args.add(_payment);
      }
      final q = _search.text.trim();
      if (q.isNotEmpty) {
        final isNum = RegExp(r'^\d+$').hasMatch(q);
        where.add('(i.invoice_number LIKE ? OR i.customer_name LIKE ?${isNum ? ' OR i.id = ?' : ''})');
        args.addAll(['%$q%', '%$q%', if (isNum) int.parse(q)]);
      }
      final rows = await db.rawQuery('''
        SELECT i.id, i.invoice_number, i.customer_name, i.total_amount, i.payment_type, i.status,
               i.invoice_date, i.created_by_username,
               (SELECT COALESCE(SUM(r.total), 0) FROM sales_returns r
                 WHERE r.original_invoice_id = i.id AND r.status = 'posted') AS returned
        FROM invoices i
        WHERE ${where.join(' AND ')}
        ORDER BY i.invoice_date DESC, i.id DESC
        LIMIT 500
      ''', args);

      // ملخص الفترة (بلا تصفية البحث): المبيعات حسب نوع الدفع + المرتجعات
      final sumWhere = <String>["COALESCE(is_deleted, 0) = 0", "COALESCE(status, '') != 'معلقة'"];
      final sumArgs = <Object?>[];
      if (from != null) {
        sumWhere.add('invoice_date >= ? AND invoice_date < ?');
        sumArgs.addAll([from, to]);
      }
      final sums = await db.rawQuery('''
        SELECT COUNT(*) AS c,
               COALESCE(SUM(CASE WHEN payment_type = 'نقد' THEN total_amount ELSE 0 END), 0) AS cash,
               COALESCE(SUM(CASE WHEN payment_type != 'نقد' THEN total_amount ELSE 0 END), 0) AS credit
        FROM invoices WHERE ${sumWhere.join(' AND ')}
      ''', sumArgs);
      double returns = 0;
      try {
        final r = await db.rawQuery('''
          SELECT COALESCE(SUM(total), 0) AS t FROM sales_returns
          WHERE status = 'posted' ${from != null ? 'AND return_date >= ? AND return_date < ?' : ''}
        ''', [if (from != null) ...[from, to]]);
        returns = (r.first['t'] as num?)?.toDouble() ?? 0;
      } catch (_) {}

      if (!mounted) return;
      final list = rows.map((m) => _Row(m)).toList();
      setState(() {
        _rows = list;
        _count = (sums.first['c'] as num?)?.toInt() ?? 0;
        _cash = (sums.first['cash'] as num?)?.toDouble() ?? 0;
        _credit = (sums.first['credit'] as num?)?.toDouble() ?? 0;
        _returns = returns;
        final keep = _selected == null ? const <_Row>[] : list.where((r) => r.id == _selected!.id).toList();
        _selected = keep.isNotEmpty ? keep.first : (list.isEmpty ? null : list.first);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر تحميل الإيصالات: $e')));
    }
  }

  // ─────────────────────────── الواجهة ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('إيصالات الكاشير'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh), onPressed: _load),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _summaryStrip(),
          _filters(),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 900;
              final list = _list(onTap: (r) {
                setState(() => _selected = r);
                if (!wide) _openDetailSheet(r);
              });
              if (!wide) return list;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 420, child: list),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _selected == null
                        ? const Center(child: Text('اختر إيصالاً لعرضه', style: TextStyle(color: Colors.grey)))
                        : _ReceiptDetail(
                            key: ValueKey(_selected!.id),
                            row: _selected!,
                            onChanged: _load,
                          ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  void _openDetailSheet(_Row r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: _ReceiptDetail(row: r, onChanged: _load),
      ),
    );
  }

  Widget _summaryStrip() {
    Widget kpi(String label, double v, Color c, {String? hint}) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border(top: BorderSide(color: c, width: 3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              Text(_money.format(v), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c)),
              if (hint != null) Text(hint, style: const TextStyle(fontSize: 11, color: Colors.black45)),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 4),
      child: Row(children: [
        kpi('المبيعات', _cash + _credit, const Color(0xFF1565C0), hint: '$_count إيصال'),
        kpi('نقداً', _cash, const Color(0xFF2E7D32)),
        kpi('آجل (دين)', _credit, const Color(0xFFE65100)),
        kpi('المرتجعات', _returns, const Color(0xFFC62828)),
        kpi('الصافي', _cash + _credit - _returns, const Color(0xFF0F3460)),
      ]),
    );
  }

  Widget _filters() {
    const labels = {
      _Range.today: 'اليوم',
      _Range.yesterday: 'أمس',
      _Range.week: 'آخر 7 أيام',
      _Range.month: 'هذا الشهر',
      _Range.all: 'الكل',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _load(),
              onChanged: (v) {
                if (v.isEmpty) _load();
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: 'رقم الإيصال أو اسم العميل ثم Enter',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
              ),
            ),
          ),
          for (final e in labels.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: _range == e.key,
              onSelected: (_) {
                setState(() => _range = e.key);
                _load();
              },
            ),
          const SizedBox(width: 8),
          for (final p in const [null, 'نقد', 'دين'])
            FilterChip(
              label: Text(p ?? 'كل الدفعات'),
              selected: _payment == p,
              onSelected: (_) {
                setState(() => _payment = p);
                _load();
              },
            ),
        ],
      ),
    );
  }

  Widget _list({required void Function(_Row) onTap}) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_rows.isEmpty) {
      return const Center(child: Text('لا توجد إيصالات في هذه الفترة', style: TextStyle(color: Colors.grey)));
    }
    // تجميع حسب اليوم
    final items = <Widget>[];
    String? lastDay;
    for (final r in _rows) {
      final day = _day.format(r.date);
      if (day != lastDay) {
        lastDay = day;
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(day, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
        ));
      }
      final sel = _selected?.id == r.id;
      final fullyReturned = r.returned > 0 && r.returned >= r.total - 0.5;
      items.add(Material(
        color: sel ? const Color(0xFFE3F2FD) : Colors.white,
        child: InkWell(
          onTap: () => onTap(r),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: r.payment == 'نقد' ? Colors.green.shade50 : Colors.orange.shade50,
                child: Icon(r.payment == 'نقد' ? Icons.payments_outlined : Icons.receipt_long,
                    size: 18, color: r.payment == 'نقد' ? Colors.green : Colors.orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(r.number, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Text(_time.format(r.date), style: const TextStyle(fontSize: 12, color: Colors.black45)),
                  ]),
                  Text(r.customer, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_money.format(r.total),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: fullyReturned ? TextDecoration.lineThrough : null,
                    )),
                if (r.status == 'معلقة')
                  _badge('معلقة', Colors.grey)
                else if (fullyReturned)
                  _badge('مرتجع كلي', Colors.red)
                else if (r.returned > 0)
                  _badge('مرتجع جزئي', Colors.deepOrange)
                else if (r.payment != 'نقد')
                  _badge('دين', Colors.orange),
              ]),
            ]),
          ),
        ),
      ));
      items.add(const Divider(height: 1, indent: 16, endIndent: 16));
    }
    return ListView(children: items);
  }

  static Widget _badge(String t, Color c) => Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.bold)),
      );
}

// ─────────────────────────── تفاصيل الإيصال ───────────────────────────

class _ReceiptDetail extends StatefulWidget {
  const _ReceiptDetail({super.key, required this.row, required this.onChanged});
  final _Row row;
  final VoidCallback onChanged;

  @override
  State<_ReceiptDetail> createState() => _ReceiptDetailState();
}

class _ReceiptDetailState extends State<_ReceiptDetail> {
  static final _money = NumberFormat('#,##0.##', 'en');
  static final _qty = NumberFormat('#,##0.###', 'en');

  Invoice? _inv;
  List<InvoiceItem> _items = const [];
  List<Map<String, Object?>> _returns = const [];
  bool _loading = true;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dbs = DatabaseService();
    try {
      final inv = await dbs.getInvoiceById(widget.row.id);
      final items = await dbs.getInvoiceItems(widget.row.id);
      List<Map<String, Object?>> returns = const [];
      try {
        final db = await dbs.database;
        returns = await db.rawQuery(
          "SELECT id, return_no, return_date, total, refund_mode FROM sales_returns "
          "WHERE original_invoice_id = ? AND status = 'posted' ORDER BY id",
          [widget.row.id],
        );
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _inv = inv;
        _items = items;
        _returns = returns;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _soldQty(InvoiceItem it) =>
      (it.quantityLargeUnit ?? 0) > 0 ? it.quantityLargeUnit! : (it.quantityIndividual ?? 0);

  Future<void> _reprint() async {
    final inv = _inv;
    if (inv == null) return;
    setState(() => _printing = true);
    final subtotal = _items.fold<double>(0, (s, it) => s + it.itemTotal);
    final ok = await ThermalReceiptService().printReceipt(ReceiptData(
      invoiceId: inv.formattedInvoiceNumber,
      dateTime: inv.invoiceDate,
      items: [
        for (final it in _items)
          ReceiptItem(name: it.productName, quantity: _soldQty(it), price: it.appliedPrice, unit: it.saleType),
      ],
      subtotal: subtotal,
      discount: inv.discount,
      total: inv.totalAmount,
      paidAmount: inv.amountPaidOnInvoice,
      customerName: inv.customerName,
      paymentType: inv.paymentType,
      isCopy: true,
    ));
    if (!mounted) return;
    setState(() => _printing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'أُرسلت نسخة الإيصال إلى الطابعة'
          : 'لم تُطبع: لم تُحدَّد طابعة حرارية (الإعدادات ← الطابعات). يمكنك «عرض كامل» ثم الطباعة A4'),
      backgroundColor: ok ? Colors.green : Colors.orange,
    ));
  }

  void _refund() {
    if (!requirePermission(context, AppPermissions.salesDocs)) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SalesReturnScreen(invoiceId: widget.row.id)))
        .then((_) {
      _load();
      widget.onChanged();
    });
  }

  void _openFull() {
    final inv = _inv;
    if (inv == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => CreateInvoiceScreen(existingInvoice: inv, isViewOnly: true)))
        .then((_) {
      _load();
      widget.onChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final inv = _inv;
    if (inv == null) return const Center(child: Text('تعذّر فتح الإيصال'));
    final subtotal = _items.fold<double>(0, (s, it) => s + it.itemTotal);
    final returned = _returns.fold<double>(0, (s, r) => s + ((r['total'] as num?)?.toDouble() ?? 0));
    final remaining = (inv.totalAmount - inv.amountPaidOnInvoice).clamp(0, double.infinity);
    final held = inv.status == 'معلقة';
    final dt = DateFormat('yyyy/MM/dd  HH:mm').format(inv.invoiceDate);

    Widget line(String a, String b, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Text(a, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color)),
            const Spacer(),
            Text(b, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color, fontSize: bold ? 16 : null)),
          ]),
        );

    return Column(children: [
      // شريط الإجراءات
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Wrap(spacing: 10, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _printing ? null : _reprint,
            icon: const Icon(Icons.print),
            label: const Text('إعادة طباعة'),
          ),
          if (!held)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
              onPressed: _refund,
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('مرتجع (كلي أو جزئي)'),
            ),
          OutlinedButton.icon(
            onPressed: _openFull,
            icon: const Icon(Icons.open_in_new),
            label: Text(held ? 'فتح الفاتورة المعلقة' : 'عرض كامل'),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('إيصال ${inv.formattedInvoiceNumber}',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(dt, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 8),
                line('العميل', inv.customerName),
                line('الدفع', inv.paymentType == 'نقد' ? 'نقداً' : 'آجل (دين)'),
                if ((inv.createdByUsername ?? '').isNotEmpty) line('الكاشير', inv.createdByUsername!),
                if (held) line('الحالة', 'معلقة (لم تُحفظ بعد)', color: Colors.grey),
                const Divider(height: 20),
                // المواد
                Row(children: const [
                  Expanded(flex: 5, child: Text('المادة', style: TextStyle(fontSize: 12, color: Colors.black54))),
                  Expanded(flex: 3, child: Text('الكمية', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54))),
                  Expanded(flex: 3, child: Text('السعر', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54))),
                  Expanded(flex: 3, child: Text('المجموع', textAlign: TextAlign.left, style: TextStyle(fontSize: 12, color: Colors.black54))),
                ]),
                const SizedBox(height: 4),
                for (final it in _items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 5, child: Text(it.productName)),
                      Expanded(
                        flex: 3,
                        child: Text('${_qty.format(_soldQty(it))} ${it.saleType ?? ''}'.trim(), textAlign: TextAlign.center),
                      ),
                      Expanded(flex: 3, child: Text(_money.format(it.appliedPrice), textAlign: TextAlign.center)),
                      Expanded(flex: 3, child: Text(_money.format(it.itemTotal), textAlign: TextAlign.left)),
                    ]),
                  ),
                const Divider(height: 20),
                line('المجموع', _money.format(subtotal)),
                if (inv.discount > 0) line('الخصم', '- ${_money.format(inv.discount)}', color: Colors.red),
                line('الإجمالي', _money.format(inv.totalAmount), bold: true),
                line('المدفوع', _money.format(inv.amountPaidOnInvoice)),
                if (remaining > 0) line('المتبقي (دين)', _money.format(remaining), color: Colors.orange.shade800),
                if (_returns.isNotEmpty) ...[
                  const Divider(height: 20),
                  const Text('المرتجعات من هذا الإيصال', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  for (final r in _returns)
                    line(
                      'مرتجع رقم ${r['return_no']} — ${'${r['return_date']}'.split('T').first}',
                      '- ${_money.format((r['total'] as num?) ?? 0)}',
                      color: Colors.red,
                    ),
                  line('الصافي بعد المرتجع', _money.format(inv.totalAmount - returned), bold: true),
                ],
                const SizedBox(height: 12),
                const Text(
                  'الإيصال المكتمل لا يُعدَّل من الكاشير. للتصحيح: «مرتجع» ثم بيع جديد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
