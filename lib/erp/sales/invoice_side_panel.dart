// lib/erp/sales/invoice_side_panel.dart
//
// 🧭 لوحة صغيرة داخل شاشة إنشاء القائمة (قراءة فقط — لا تغيّر الفاتورة):
//   • رصيد العميل الحالي، وسقف دينه وما يتبقى منه (تحذير عند التجاوز)
//   • نسبة حسمه الدائمة ومستوى سعره المعتاد
//   • إيقاف البيع الآجل
//   • لفاتورة محفوظة: «مرتجع من هذه الفاتورة»

import 'dart:async';

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../debts/customer_ext_service.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import 'sales_return_screen.dart';
import '../../services/invoice_edit_log.dart';

class ErpInvoiceSidePanel extends StatefulWidget {
  const ErpInvoiceSidePanel({
    super.key,
    required this.customerName,
    required this.invoiceTotal,
    required this.isDebt,
    this.invoiceId,
  });
  final String customerName;
  final double invoiceTotal;
  final bool isDebt;
  final int? invoiceId;

  @override
  State<ErpInvoiceSidePanel> createState() => _ErpInvoiceSidePanelState();
}

class _ErpInvoiceSidePanelState extends State<ErpInvoiceSidePanel> {
  Timer? _debounce;
  String _loadedFor = '';
  double? _balance;
  CustomerExt? _ext;
  List<InvoiceEditChange> _edits = const [];
  bool _showEdits = false;

  @override
  void initState() {
    super.initState();
    _schedule();
    _loadEdits();
  }

  Future<void> _loadEdits() async {
    final id = widget.invoiceId;
    if (id == null) return;
    try {
      final r = await InvoiceEditLog.forInvoice(await erpDb(), id);
      if (mounted) setState(() => _edits = r);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant ErpInvoiceSidePanel old) {
    super.didUpdateWidget(old);
    if (old.customerName != widget.customerName) _schedule();
    if (old.invoiceId != widget.invoiceId) _loadEdits();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _load);
  }

  Future<void> _load() async {
    final name = widget.customerName.trim();
    if (name == _loadedFor) return;
    _loadedFor = name;
    try {
      final svc = CustomerExtService();
      final id = await svc.customerIdByName(name);
      if (id == null) {
        if (mounted) {
          setState(() {
            _balance = null;
            _ext = null;
          });
        }
        return;
      }
      final e = await svc.get(id);
      final db = await erpDb();
      final r = await db.query('customers', columns: ['current_total_debt'], where: 'id = ?', whereArgs: [id], limit: 1);
      if (!mounted) return;
      setState(() {
        _ext = e;
        _balance = r.isEmpty ? null : d0(r.first['current_total_debt']);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final e = _ext;
    final bal = _balance;
    final children = <Widget>[];
    if (bal != null) {
      children.add(_row('رصيد العميل الحالي', fmtMoney(bal), bal > 0 ? ErpColors.orange : ErpColors.green));
    }
    if (e != null && (e.creditLimit ?? 0) > 0 && bal != null) {
      final remaining = e.creditLimit! - bal;
      final after = widget.isDebt ? remaining - widget.invoiceTotal : remaining;
      children.add(_row('المتبقي من سقف الدين', fmtMoney(remaining), remaining < 0 ? ErpColors.red : ErpColors.navy));
      if (widget.isDebt && after < 0) {
        children.add(_warn('هذه الفاتورة الآجلة تتجاوز سقف دين العميل بـ ${fmtMoney(-after)}'));
      }
    }
    if (e != null && e.isBlocked && widget.isDebt) {
      children.add(_warn('البيع الآجل موقوف لهذا العميل'));
    }
    if (e != null && (e.discountPercent ?? 0) > 0) {
      final amt = widget.invoiceTotal * e.discountPercent! / 100;
      children.add(_row('خصم العميل الدائم', '${fmtQty(e.discountPercent!)}% ≈ ${fmtMoney(amt)}', ErpColors.purple));
    }
    if (e != null && (e.priceLevel ?? '').isNotEmpty) {
      children.add(_row('مستوى سعره المعتاد', e.priceLevel!, ErpColors.blue));
    }
    if (widget.invoiceId != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.assignment_return, size: 18),
            label: const Text('مرتجع من هذه الفاتورة'),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => SalesReturnScreen(invoiceId: widget.invoiceId))),
          ),
        ]),
      ));
    }
    if (_edits.isNotEmpty) children.add(_editsBlock());
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ErpColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  /// ✏️ ما تغيّر في مواد الفاتورة بعد حفظها: إضافة / مرتجع / تعديل سعر
  Widget _editsBlock() {
    double add = 0, ret = 0;
    for (final e in _edits) {
      if (e.kind == InvoiceEditLog.kindAdd) add += e.amountDelta;
      if (e.kind == InvoiceEditLog.kindReturn) ret += -e.amountDelta;
    }
    Color colorOf(String k) => k == InvoiceEditLog.kindAdd
        ? ErpColors.blue
        : (k == InvoiceEditLog.kindReturn ? ErpColors.orange : ErpColors.purple);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ErpColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _showEdits = !_showEdits),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              const Icon(Icons.edit_note_rounded, size: 20, color: ErpColors.navy),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'عُدّلت بعد الحفظ: '
                  '${add > 0 ? 'إضافات ${fmtMoney(add)}' : ''}'
                  '${add > 0 && ret > 0 ? '، ' : ''}'
                  '${ret > 0 ? 'مرتجعات ${fmtMoney(ret)}' : ''}'
                  '${add <= 0 && ret <= 0 ? 'تعديل أسعار' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              Icon(_showEdits ? Icons.expand_less : Icons.expand_more, color: ErpColors.muted),
            ]),
          ),
        ),
        if (_showEdits)
          for (final e in _edits)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorOf(e.kind).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(e.kind, style: TextStyle(color: colorOf(e.kind), fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${e.productName}  ${fmtQty(e.qtyBefore)} ← ${fmtQty(e.qtyAfter)} ${e.unit}',
                    style: const TextStyle(fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${e.amountDelta >= 0 ? '+' : '−'}${fmtMoney(e.amountDelta.abs())}',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: colorOf(e.kind)),
                ),
              ]),
            ),
      ]),
    );
  }

  Widget _row(String k, String v, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(color: ErpColors.muted, fontSize: 13))),
          Text(v, textDirection: TextDirection.ltr, style: TextStyle(color: c, fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _warn(String t) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFFFFF1F1), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: ErpColors.red, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text(t, style: const TextStyle(color: ErpColors.red, fontSize: 13))),
        ]),
      );
}
