// lib/erp/purchases/purchase_register_screen.dart
//
// 🧾 سجل فواتير الشراء لكل الموردين: فترة بأزرار سريعة، بحث برقم الفاتورة أو
// المورد، فلترة بالحالة (مع العدد)، ملخّص المؤكد/المدفوع/المتبقي في الرأس،
// تصدير Excel وPDF، وإجراءات كل فاتورة (فتح، تعديل، إلغاء).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../models/purchase_invoice.dart';
import '../../screens/create_purchase_invoice_screen.dart';
import '../../screens/invoice_details_split_screen.dart';
import '../../screens/suppliers/supplier_ui.dart';
import '../../services/purchase_service.dart';
import '../erp_ui.dart';
import '../report_export.dart';

class PurchaseRegisterScreen extends StatefulWidget {
  const PurchaseRegisterScreen({super.key});

  @override
  State<PurchaseRegisterScreen> createState() => _PurchaseRegisterScreenState();
}

class _PurchaseRegisterScreenState extends State<PurchaseRegisterScreen> {
  DateTime? _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _status = 'all';
  String _q = '';
  List<(PurchaseInvoice, String)> _rows = const [];
  bool _loading = true;

  static const _statuses = [
    ('all', 'الكل'),
    ('confirmed', 'مؤكدة'),
    ('draft', 'مسودات'),
    ('cancelled', 'ملغاة'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await context.read<PurchaseService>().getAllPurchaseInvoices(from: _from, to: _to);
      final list = <(PurchaseInvoice, String)>[];
      for (final m in r) {
        try {
          list.add((PurchaseInvoice.fromMap(m), (m['supplier_name'] as String?) ?? 'مورد #${m['supplier_id']}'));
        } catch (_) {
          // صف تالف لا يُسقط السجل كله
        }
      }
      if (mounted) setState(() => _rows = list);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<(PurchaseInvoice, String)> _filtered({bool ignoreStatus = false}) {
    final q = _q.trim().toLowerCase();
    return _rows.where((r) {
      if (!ignoreStatus && _status != 'all' && r.$1.status != _status) return false;
      if (q.isEmpty) return true;
      return r.$1.invoiceNumber.toLowerCase().contains(q) ||
          r.$2.toLowerCase().contains(q) ||
          (r.$1.notes ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, accRoute<void>(screen));
    if (mounted) _load();
  }

  List<String> get _headers => const ['التاريخ', 'رقم الفاتورة', 'المورد', 'الحالة', 'الإجمالي', 'المدفوع', 'المتبقي', 'العملة'];

  List<List<String>> _table(List<(PurchaseInvoice, String)> list) => [
        for (final (inv, name) in list)
          [
            fmtDate(inv.date),
            inv.invoiceNumber,
            name,
            invoiceStatusLabel(inv.status),
            fmtMoney(inv.totalAmount),
            fmtMoney(inv.paidAmount),
            inv.status == 'confirmed' ? fmtMoney(inv.remainingAmount) : '—',
            inv.currency,
          ],
      ];

  String get _periodText => _from == null ? 'كل الفترات حتى ${fmtDate(_to)}' : 'من ${fmtDate(_from!)} إلى ${fmtDate(_to)}';

  @override
  Widget build(BuildContext context) {
    final shown = _filtered();
    final inPeriod = _filtered(ignoreStatus: true);
    int count(String s) => s == 'all' ? inPeriod.length : inPeriod.where((r) => r.$1.status == s).length;

    final total = <String, double>{}, paid = <String, double>{}, remaining = <String, double>{};
    for (final (inv, _) in shown) {
      if (inv.status != 'confirmed') continue;
      total[inv.currency] = (total[inv.currency] ?? 0) + inv.totalAmount;
      paid[inv.currency] = (paid[inv.currency] ?? 0) + inv.paidAmount;
      remaining[inv.currency] = (remaining[inv.currency] ?? 0) + inv.remainingAmount;
    }

    return ErpPage(
      title: 'سجل فواتير الشراء',
      subtitle: 'كل الموردين — $_periodText',
      icon: Icons.receipt_long_rounded,
      actions: [
        IconButton(
          tooltip: 'تصدير Excel',
          icon: const Icon(Icons.table_view_rounded),
          onPressed: shown.isEmpty
              ? null
              : () => ReportExport.exportCsv(context, title: 'فواتير الشراء', headers: _headers, rows: _table(shown)),
        ),
        IconButton(
          tooltip: 'PDF / طباعة',
          icon: const Icon(Icons.picture_as_pdf_rounded),
          onPressed: shown.isEmpty
              ? null
              : () => ReportExport.exportPdf(
                    context,
                    title: 'سجل فواتير الشراء',
                    subtitle: _periodText,
                    headers: _headers,
                    rows: _table(shown),
                    summaryLines: [
                      'المؤكدة: ${supTotals(total)}',
                      'المدفوع عند الشراء: ${supTotals(paid)}',
                      'المتبقي (آجل): ${supTotals(remaining)}',
                    ],
                  ),
        ),
        IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _load),
      ],
      headerExtra: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Wrap(spacing: 10, runSpacing: 8, children: [
          HeaderStat(
              label: 'المؤكدة', value: supTotals(total), icon: Icons.shopping_bag_rounded, accent: const Color(0xFF93C5FD)),
          HeaderStat(
              label: 'المدفوع عند الشراء', value: supTotals(paid), icon: Icons.payments_rounded, accent: const Color(0xFF86EFAC)),
          HeaderStat(
              label: 'المتبقي (آجل)',
              value: supTotals(remaining),
              icon: Icons.schedule_rounded,
              accent: const Color(0xFFFDBA74)),
          HeaderStat(label: 'عدد الفواتير', value: '${shown.length}', icon: Icons.tag_rounded),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _push(const CreatePurchaseInvoiceScreen()),
        icon: const Icon(Icons.note_add_rounded),
        label: const Text('فاتورة شراء'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(children: [
            PeriodBar(
              from: _from,
              to: _to,
              onChanged: (f, t) {
                setState(() {
                  _from = f;
                  _to = t;
                });
                _load();
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 340,
                  child: SearchBox(hint: 'بحث برقم الفاتورة أو المورد…', onChanged: (v) => setState(() => _q = v)),
                ),
                for (final (s, label) in _statuses)
                  ChoiceChip(
                    label: Text('$label (${count(s)})'),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
              ]),
            ),
            SizedBox(height: 2, child: _loading ? const LinearProgressIndicator(minHeight: 2) : null),
            Expanded(
              child: shown.isEmpty && !_loading
                  ? const EmptyState('لا توجد فواتير شراء مطابقة', icon: Icons.receipt_long_outlined)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final (inv, name) = shown[i];
                        final id = inv.id;
                        final tile = PurchaseInvoiceTile(
                          invoice: inv,
                          supplierName: name,
                          onOpen: id == null ? null : () => _push(InvoiceDetailsSplitScreen(invoiceId: id)),
                          onEdit: id == null ? null : () => _push(CreatePurchaseInvoiceScreen(existingInvoice: inv)),
                          onCancel: id == null
                              ? null
                              : () async {
                                  if (await cancelPurchaseInvoiceFlow(context, inv) && mounted) _load();
                                },
                        );
                        return i < 14 ? FadeSlideIn(key: ValueKey(id), index: i, child: tile) : tile;
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
