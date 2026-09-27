// lib/erp/sales/invoice_side_panel.dart
//
// 🧭 لوحة صغيرة داخل شاشة إنشاء القائمة (قراءة فقط — لا تغيّر الفاتورة):
//   • رصيد العميل الحالي، وسقف دينه وما يتبقى منه (تحذير عند التجاوز)
//   • نسبة حسمه الدائمة ومستوى سعره المعتاد
//   • إيقاف البيع الآجل
//   • لفاتورة محفوظة: «حقول إضافية» (البائع، الشحن...) و«مرتجع»

import 'dart:async';

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../debts/customer_ext_service.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import 'invoice_extras.dart';
import 'sales_return_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ErpInvoiceSidePanel old) {
    super.didUpdateWidget(old);
    if (old.customerName != widget.customerName) _schedule();
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
      children.add(_row('حسم العميل الدائم', '${fmtQty(e.discountPercent!)}% ≈ ${fmtMoney(amt)}', ErpColors.purple));
    }
    if (e != null && (e.priceLevel ?? '').isNotEmpty) {
      children.add(_row('مستوى سعره المعتاد', e.priceLevel!, ErpColors.blue));
    }
    if (widget.invoiceId != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.post_add, size: 18),
            label: const Text('حقول إضافية'),
            onPressed: () => showInvoiceExtrasDialog(context, widget.invoiceId!),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.assignment_return, size: 18),
            label: const Text('مرتجع'),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => SalesReturnScreen(invoiceId: widget.invoiceId))),
          ),
        ]),
      ));
    }
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
