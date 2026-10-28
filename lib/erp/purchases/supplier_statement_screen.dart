// lib/erp/purchases/supplier_statement_screen.dart
//
// 📒 كشف حساب المورد: حركات دفتر المورد (supplier_transactions) لفترة، بعملة
// واحدة في كل مرة، مع «رصيد سابق» قبل بداية الفترة والرصيد بعد كل حركة.
// قراءة فقط — لا يغيّر أي رصيد. الرصيد = مجموع الحركات (قاعدة SupplierDebtReconciler).
// طباعة PDF وتصدير Excel للفترة المعروضة.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../report_export.dart';

class SupplierStatementScreen extends StatefulWidget {
  const SupplierStatementScreen({super.key, required this.supplierId, required this.supplierName});
  final int supplierId;
  final String supplierName;

  @override
  State<SupplierStatementScreen> createState() => _SupplierStatementScreenState();
}

class _SupplierStatementScreenState extends State<SupplierStatementScreen> {
  List<Map<String, Object?>> _rows = const [];
  bool _loading = true;
  String? _error;
  DateTime? _from;
  DateTime _to = DateTime.now();
  String _currency = 'IQD';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await erpDb();
      final rows = await db.rawQuery('''
        SELECT transaction_date, amount_changed, COALESCE(currency, 'IQD') AS currency,
               transaction_type, description, invoice_id, payment_id
        FROM supplier_transactions
        WHERE supplier_id = ? AND COALESCE(is_deleted, 0) = 0
        ORDER BY transaction_date ASC, id ASC
      ''', [widget.supplierId]);
      if (!mounted) return;
      // العملة الافتراضية: التي لها حركات (الدينار أولاً)
      final curs = rows.map((r) => '${r['currency']}').toSet();
      setState(() {
        _rows = rows;
        if (!curs.contains(_currency) && curs.isNotEmpty) _currency = curs.contains('IQD') ? 'IQD' : curs.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  static String _typeLabel(String? t, Object? invoiceId, Object? paymentId) {
    switch (t) {
      case 'supplier_payment':
        return 'دفعة للمورد';
      case 'opening_balance':
        return 'رصيد افتتاحي';
      case 'purchase_return':
        return 'مرتجع مشتريات';
      case 'correction':
        return 'تصحيح';
      case 'purchase_invoice_sync':
      case 'invoice_debt':
        return 'فاتورة شراء';
    }
    if (paymentId != null) return 'دفعة للمورد';
    if (invoiceId != null) return 'فاتورة شراء';
    return t ?? '—';
  }

  String get _curName => _currency == 'IQD' ? 'دينار' : (_currency == 'USD' ? 'دولار' : _currency);

  String get _periodText => _from == null ? 'حتى ${fmtDate(_to)}' : 'من ${fmtDate(_from!)} إلى ${fmtDate(_to)}';

  @override
  Widget build(BuildContext context) {
    final currencies = _rows.map((r) => '${r['currency']}').toSet().toList()..sort();
    final fromDay = _from == null ? null : DateTime(_from!.year, _from!.month, _from!.day);
    final toEnd = DateTime(_to.year, _to.month, _to.day).add(const Duration(days: 1));

    double opening = 0, debit = 0, credit = 0;
    final table = <List<String>>[];
    var bal = 0.0;
    for (final r in _rows) {
      if ('${r['currency']}' != _currency) continue;
      final amt = d0(r['amount_changed']);
      final date = DateTime.tryParse('${r['transaction_date']}');
      if (date != null && !date.isBefore(toEnd)) continue; // بعد نهاية الفترة
      if (fromDay != null && date != null && date.isBefore(fromDay)) {
        opening += amt; // قبل بداية الفترة ⇒ رصيد سابق
        continue;
      }
      if (table.isEmpty) bal = opening;
      bal += amt;
      if (amt >= 0) {
        debit += amt;
      } else {
        credit += -amt;
      }
      table.add([
        date == null ? '${r['transaction_date']}' : fmtDate(date),
        _typeLabel(r['transaction_type'] as String?, r['invoice_id'], r['payment_id']),
        '${r['description'] ?? ''}',
        amt >= 0 ? fmtMoney(amt) : '',
        amt < 0 ? fmtMoney(-amt) : '',
        fmtMoney(bal),
      ]);
    }
    final closing = opening + debit - credit;
    final rows = <List<String>>[
      if (fromDay != null) ['', 'رصيد سابق', 'قبل ${fmtDate(fromDay)}', '', '', fmtMoney(opening)],
      ...table,
    ];
    const headers = ['التاريخ', 'النوع', 'البيان', 'له (دين علينا)', 'دفعنا له', 'الرصيد'];
    final footer = ['', 'المجموع', '', fmtMoney(debit), fmtMoney(credit), fmtMoney(closing)];
    String caption(double v) => v > 0.01 ? 'له علينا' : (v < -0.01 ? 'لنا عنده' : 'لا رصيد');

    return ErpPage(
      title: 'كشف حساب المورد',
      subtitle: '${widget.supplierName} — $_periodText — بال$_curName',
      icon: Icons.list_alt_rounded,
      actions: [
        IconButton(
          tooltip: 'تصدير Excel',
          icon: const Icon(Icons.table_view_rounded),
          onPressed: rows.isEmpty
              ? null
              : () => ReportExport.exportCsv(context,
                  title: 'كشف حساب ${widget.supplierName}', headers: headers, rows: [...rows, footer]),
        ),
        IconButton(
          tooltip: 'PDF / طباعة',
          icon: const Icon(Icons.picture_as_pdf_rounded),
          onPressed: rows.isEmpty
              ? null
              : () => ReportExport.exportPdf(
                    context,
                    title: 'كشف حساب مورد',
                    subtitle: '${widget.supplierName} — $_periodText — بال$_curName',
                    headers: headers,
                    rows: rows,
                    footer: footer,
                    summaryLines: ['الرصيد الختامي: ${fmtMoney(closing.abs())} $_curName (${caption(closing)})'],
                  ),
        ),
        IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      headerExtra: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Wrap(spacing: 10, runSpacing: 8, children: [
          if (_from != null)
            HeaderStat(label: 'رصيد سابق', value: fmtMoney(opening), icon: Icons.history_rounded),
          HeaderStat(
              label: 'له (فواتير ورصيد)', value: fmtMoney(debit), icon: Icons.north_east_rounded, accent: const Color(0xFFFCA5A5)),
          HeaderStat(
              label: 'دفعنا ومرتجعات', value: fmtMoney(credit), icon: Icons.south_west_rounded, accent: const Color(0xFF86EFAC)),
          HeaderStat(
            label: 'الرصيد الختامي — ${caption(closing)}',
            value: '${fmtMoney(closing.abs())} $_curName',
            icon: Icons.account_balance_wallet_rounded,
            accent: const Color(0xFFFDE68A),
          ),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('تعذّر تحميل الكشف: $_error'))
              : Column(children: [
                  PeriodBar(
                    from: _from,
                    to: _to,
                    onChanged: (f, t) => setState(() {
                      _from = f;
                      _to = t;
                    }),
                    trailing: currencies.length > 1
                        ? SegmentedButton<String>(
                            segments: [
                              for (final c in currencies)
                                ButtonSegment(value: c, label: Text(c == 'IQD' ? 'دينار' : (c == 'USD' ? 'دولار' : c))),
                            ],
                            selected: {_currency},
                            onSelectionChanged: (v) => setState(() => _currency = v.first),
                          )
                        : null,
                  ),
                  Expanded(
                    child: rows.isEmpty
                        ? const EmptyState('لا توجد حركات لهذا المورد في الفترة', icon: Icons.list_alt_outlined)
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: ErpColors.border),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: SimpleTable(
                                headers: headers,
                                numericColumns: const {3, 4, 5},
                                rows: rows,
                                footer: footer,
                              ),
                            ),
                          ),
                  ),
                ]),
    );
  }
}
