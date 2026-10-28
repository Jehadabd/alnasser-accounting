// screens/product_report_details_screen.dart
//
// 📦 تقرير مادة واحدة: كل الفترات ← سنة ← أشهرها ← فواتير الشهر وعملاؤه.
// قراءة واحدة لبنود المادة من المحرك الموحّد، ثم كل التجميعات هنا.

import 'package:flutter/material.dart';

import '../accounting/screens/acc_ui.dart' show accRoute;
import '../services/database_service.dart';
import '../services/reports_service.dart';
import '../widgets/report_kit.dart';
import 'invoice_details_screen.dart';

class ProductReportDetailsScreen extends StatefulWidget {
  const ProductReportDetailsScreen({super.key, required this.productId, required this.productName, this.categoryName});
  final int? productId;
  final String productName;
  final String? categoryName;

  @override
  State<ProductReportDetailsScreen> createState() => _ProductReportDetailsScreenState();
}

class _Bucket {
  double qty = 0, sales = 0, cost = 0, returnedQty = 0, returned = 0;
  final Set<int> invoices = {};
  double get profit => sales - cost;
}

class _ProductReportDetailsScreenState extends State<ProductReportDetailsScreen> {
  bool _loading = true;
  SalesFacts? _facts;
  Map<String, Object?>? _product;
  int? _year;
  int? _month;
  bool _chartQty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final facts = await ReportsService().loadFacts(productId: widget.productId, productName: widget.productName);
      Map<String, Object?>? product;
      if (widget.productId != null) {
        final db = await DatabaseService().database;
        final r = await db.query('products', where: 'id = ?', whereArgs: [widget.productId], limit: 1);
        product = r.isEmpty ? null : r.first;
      }
      if (!mounted) return;
      final years = _years(facts);
      setState(() {
        _facts = facts;
        _product = product;
        _year ??= years.isEmpty ? DateTime.now().year : years.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      setToast(context, 'تعذّر تحميل تقرير المادة: $e', error: true);
    }
  }

  List<int> _years(SalesFacts f) {
    final s = <int>{for (final i in f.saleItems) i.date.year, for (final i in f.returnItems) i.date.year};
    return s.toList()..sort((a, b) => b.compareTo(a));
  }

  _Bucket _bucket(bool Function(DateTime d) inRange) {
    final b = _Bucket();
    for (final it in _facts!.saleItems) {
      if (!inRange(it.date)) continue;
      b.qty += it.baseQty;
      b.sales += it.revenue;
      b.cost += it.cost;
      b.invoices.add(it.invoiceId);
    }
    for (final it in _facts!.returnItems) {
      if (!inRange(it.date)) continue;
      b.returnedQty += it.baseQty;
      b.returned += it.revenue;
      b.qty -= it.baseQty;
      b.sales -= it.revenue;
      b.cost -= it.cost;
    }
    return b;
  }

  String get _unit => _facts?.saleItems.isNotEmpty == true ? _facts!.saleItems.first.baseUnit : 'قطعة';

  @override
  Widget build(BuildContext context) {
    final profit = repCanSeeProfit();
    return ReportScaffold(
      title: widget.productName,
      subtitle: [if (widget.categoryName != null) widget.categoryName!, 'تقرير المادة'].join(' • '),
      icon: Icons.inventory_2_rounded,
      actions: [IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      loading: _loading,
      children: _loading
          ? null
          : _facts == null
              ? const [EmptyReport(title: 'تعذّر تحميل تقرير المادة', text: 'اضغط «تحديث» للمحاولة مجدداً.', icon: Icons.error_outline_rounded)]
              : [
              _allTime(profit),
              _yearChips(),
              if (_year != null) _yearCard(_year!, profit),
              if (_year != null && _month != null) _monthCard(_year!, _month!, profit),
            ],
    );
  }

  Widget _allTime(bool profit) {
    final b = _bucket((_) => true);
    final p = _product;
    final stock = (p?['stock_quantity'] as num?)?.toDouble();
    final customers = <String>{
      for (final i in _facts!.invoices)
        if (i.items.isNotEmpty) i.customerId != null && i.customerId! > 0 ? 'id:${i.customerId}' : 'n:${i.customerName}'
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrid(minTileWidth: 180, children: [
        KpiTile(label: 'الكمية المباعة (كل الفترات)', value: b.qty, money: false, icon: Icons.shopping_basket_rounded, hint: _unit),
        KpiTile(label: 'صافي المبيعات', value: b.sales, icon: Icons.point_of_sale_rounded, color: kSetBlue, emphasis: true),
        if (profit)
          KpiTile(
            label: 'الربح',
            value: b.profit,
            icon: Icons.trending_up_rounded,
            color: kSetGreen,
            hint: b.sales.abs() > 0 ? 'هامش ${repPercent(b.profit / b.sales * 100)}' : null,
          ),
        KpiTile(
          label: 'الفواتير',
          value: b.invoices.length.toDouble(),
          money: false,
          icon: Icons.receipt_long_rounded,
          color: kRepPurple,
          hint: '${customers.length} عميل',
        ),
        if (stock != null) KpiTile(label: 'المخزون الحالي', value: stock, money: false, icon: Icons.warehouse_rounded, color: kRepTeal, hint: _unit),
        if (b.returnedQty > 0)
          KpiTile(label: 'المرتجع', value: b.returnedQty, money: false, icon: Icons.assignment_return_rounded, color: kSetRed, hint: '${repMoney(b.returned)} د.ع'),
      ]),
      const SizedBox(height: 14),
    ]);
  }

  Widget _yearChips() {
    final years = _years(_facts!);
    if (years.isEmpty) {
      return const SetCard(
        title: 'لا مبيعات لهذه المادة',
        icon: Icons.info_outline_rounded,
        child: EmptyReport(title: 'لم تُبع هذه المادة بعد', icon: Icons.inventory_2_outlined),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final y in years)
          ChoiceChip(
            label: Text('$y'),
            selected: _year == y,
            showCheckmark: false,
            onSelected: (_) => setState(() {
              _year = y;
              _month = null;
            }),
          ),
      ]),
    );
  }

  Widget _yearCard(int year, bool profit) {
    final months = [for (var m = 1; m <= 12; m++) _bucket((d) => d.year == year && d.month == m)];
    final total = _bucket((d) => d.year == year);
    final values = [for (final b in months) _chartQty ? b.qty : b.sales];
    return SetCard(
      title: 'سنة $year',
      subtitle: '${repQty(total.qty)} $_unit • ${repMoney(total.sales)} د.ع${profit ? ' • ربح ${repMoney(total.profit)}' : ''}',
      icon: Icons.calendar_month_rounded,
      trailing: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('المبلغ')),
          ButtonSegment(value: true, label: Text('الكمية')),
        ],
        selected: {_chartQty},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => _chartQty = s.first),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 12),
        MiniBars(
          values: values,
          labels: [for (var m = 1; m <= 12; m++) '$m'],
          tooltips: [
            for (var m = 1; m <= 12; m++)
              'شهر $m\n${_chartQty ? '${repQty(months[m - 1].qty)} $_unit' : '${repMoney(months[m - 1].sales)} د.ع'}'
          ],
          highlight: _month == null ? null : _month! - 1,
          color: kSetBlue,
          onTap: (i) => setState(() => _month = i + 1),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 600 ? 3 : 2);
          final w = (c.maxWidth - (cols - 1) * 10) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (var m = 1; m <= 12; m++)
              SizedBox(
                width: w,
                child: _MonthTile(
                  month: m,
                  b: months[m - 1],
                  unit: _unit,
                  showProfit: profit,
                  selected: _month == m,
                  onTap: months[m - 1].invoices.isEmpty && months[m - 1].returnedQty == 0
                      ? null
                      : () => setState(() => _month = m),
                ),
              ),
          ]);
        }),
      ]),
    );
  }

  Widget _monthCard(int year, int month, bool profit) {
    final invoices = [
      for (final i in _facts!.invoices.reversed)
        if (i.date.year == year && i.date.month == month && i.items.isNotEmpty) i
    ];
    // العملاء في الشهر
    final byCustomer = <String, (String, double, double, double)>{};
    for (final i in invoices) {
      final k = i.customerId != null && i.customerId! > 0 ? 'id:${i.customerId}' : 'n:${i.customerName}';
      final q = i.items.fold<double>(0, (s, it) => s + it.baseQty);
      final r = i.items.fold<double>(0, (s, it) => s + it.revenue);
      final p = i.items.fold<double>(0, (s, it) => s + it.profit);
      final cur = byCustomer[k] ?? (i.customerName, 0.0, 0.0, 0.0);
      byCustomer[k] = (cur.$1, cur.$2 + q, cur.$3 + r, cur.$4 + p);
    }
    final customers = byCustomer.values.toList()..sort((a, b) => b.$3.compareTo(a.$3));
    final maxC = customers.isEmpty ? 0.0 : customers.first.$3;

    return SetCard(
      title: 'شهر $month / $year',
      subtitle: '${invoices.length} فاتورة • ${customers.length} عميل',
      icon: Icons.receipt_long_rounded,
      color: kRepPurple,
      trailing: IconButton(
        tooltip: 'إغلاق',
        onPressed: () => setState(() => _month = null),
        icon: const Icon(Icons.close_rounded),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 10),
        if (customers.isNotEmpty) ...[
          const Text('العملاء', style: TextStyle(fontWeight: FontWeight.w900, color: kSetText)),
          const SizedBox(height: 4),
          for (var i = 0; i < customers.length && i < 10; i++)
            RankRow(
              rank: i + 1,
              title: customers[i].$1,
              subtitle: '${repQty(customers[i].$2)} $_unit${profit ? ' • ربح ${repMoney(customers[i].$4)}' : ''}',
              value: customers[i].$3,
              fraction: maxC <= 0 ? 0 : customers[i].$3 / maxC,
              color: kRepPurple,
            ),
          const Divider(height: 24),
        ],
        const Text('الفواتير', style: TextStyle(fontWeight: FontWeight.w900, color: kSetText)),
        const SizedBox(height: 6),
        for (final i in invoices)
          _InvoiceLine(
            inv: i,
            unit: _unit,
            showProfit: profit,
            onTap: () => Navigator.push(context, accRoute(InvoiceDetailsScreen(invoiceId: i.id))),
          ),
      ]),
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({
    required this.month,
    required this.b,
    required this.unit,
    required this.showProfit,
    required this.selected,
    required this.onTap,
  });
  final int month;
  final _Bucket b;
  final String unit;
  final bool showProfit;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final empty = onTap == null;
    return Material(
      color: selected ? kSetNavy : (empty ? const Color(0xFFF8FAFC) : Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? kSetNavy : kSetBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('شهر $month',
                style: TextStyle(
                    fontWeight: FontWeight.w900, color: selected ? Colors.white : (empty ? const Color(0xFFB8C2CF) : kSetText))),
            const SizedBox(height: 4),
            if (empty)
              const Text('لا مبيعات', style: TextStyle(fontSize: 12, color: Color(0xFFB8C2CF)))
            else ...[
              Text('${repMoney(b.sales)} د.ع',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : kSetText)),
              Text('${repQty(b.qty)} $unit • ${b.invoices.length} فاتورة',
                  style: TextStyle(fontSize: 11.5, color: selected ? Colors.white70 : kSetMuted)),
              if (showProfit)
                Text('ربح ${repMoney(b.profit)}',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : (b.profit < 0 ? kSetRed : kSetGreen))),
            ],
          ]),
        ),
      ),
    );
  }
}

class _InvoiceLine extends StatelessWidget {
  const _InvoiceLine({required this.inv, required this.unit, required this.showProfit, required this.onTap});
  final SalesInvoiceFact inv;
  final String unit;
  final bool showProfit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final qty = inv.items.fold<double>(0, (s, it) => s + it.baseQty);
    final rev = inv.items.fold<double>(0, (s, it) => s + it.revenue);
    final prof = inv.items.fold<double>(0, (s, it) => s + it.profit);
    final price = inv.items.first.unitPrice;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: kSetBorder)),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: CircleAvatar(
          backgroundColor: inv.isCash ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
          child: Icon(inv.isCash ? Icons.payments_rounded : Icons.schedule_rounded,
              size: 19, color: inv.isCash ? kSetGreen : kSetOrange),
        ),
        title: Text('${inv.displayNumber} • ${inv.customerName}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
        subtitle: Text('${repDate(inv.date)} • ${repQty(qty)} $unit بسعر ${repMoney(price)}',
            style: const TextStyle(fontSize: 12, color: kSetMuted)),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          MoneyLabel(rev),
          if (showProfit) MoneyLabel(prof, size: 12, bold: false, color: kSetGreen),
        ]),
      ),
    );
  }
}
