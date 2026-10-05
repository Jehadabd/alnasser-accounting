// lib/widgets/global_search.dart
//
// 🔎 البحث الشامل (Ctrl+K): عميل، مادة، أو رقم قائمة من أي شاشة.
// قراءة فقط: يفتح الشاشة المناسبة ولا يغيّر شيئاً.

import 'dart:async';

import 'package:flutter/material.dart';

import '../accounting/screens/acc_ui.dart' show fmtMoney, requirePermission;
import '../inventory/item_card_editor_screen.dart';
import '../models/app_user.dart';
import '../models/customer.dart';
import '../screens/create_invoice_screen.dart';
import '../screens/customer_details_screen.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

enum _Kind { customer, product, invoice }

class _Hit {
  _Hit(this.kind, this.id, this.title, this.subtitle);
  final _Kind kind;
  final int id;
  final String title;
  final String subtitle;
}

Future<void> showGlobalSearch(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _GlobalSearchDialog());
}

class _GlobalSearchDialog extends StatefulWidget {
  const _GlobalSearchDialog();
  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<_Hit> _hits = const [];
  bool _busy = false;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _run(q.trim()));
  }

  Future<void> _run(String q) async {
    final seq = ++_seq;
    if (q.isEmpty) {
      setState(() => _hits = const []);
      return;
    }
    setState(() => _busy = true);
    final hits = <_Hit>[];
    try {
      final db = await DatabaseService().database;
      final like = '%$q%';
      // 👤 كل موظف يرى في البحث ما تسمح به صلاحياته فقط
      final auth = AuthService();
      final canCustomers = auth.hasPermission(AppPermissions.debtRegister);
      final canProducts = auth.hasPermission(AppPermissions.itemCard);
      final canInvoices = auth.hasPermission(AppPermissions.editInvoices);
      final customers = !canCustomers ? const <Map<String, Object?>>[] : await db.rawQuery('''
        SELECT id, name, phone, current_total_debt FROM customers
        WHERE COALESCE(is_deleted, 0) = 0 AND (name LIKE ? OR phone LIKE ?)
        ORDER BY name LIMIT 8
      ''', [like, like]);
      for (final r in customers) {
        final debt = (r['current_total_debt'] as num?)?.toDouble() ?? 0;
        hits.add(_Hit(_Kind.customer, r['id'] as int, '${r['name']}',
            'عميل • ${r['phone'] ?? ''} • الدين ${fmtMoney(debt)}'));
      }
      final products = !canProducts ? const <Map<String, Object?>>[] : await db.rawQuery('''
        SELECT id, name, stock_quantity, unit_price FROM products
        WHERE COALESCE(is_deleted, 0) = 0 AND name LIKE ?
        ORDER BY name LIMIT 8
      ''', [like]);
      for (final r in products) {
        hits.add(_Hit(_Kind.product, r['id'] as int, '${r['name']}',
            'مادة • الكمية ${fmtMoney((r['stock_quantity'] as num?) ?? 0)} • السعر ${fmtMoney((r['unit_price'] as num?) ?? 0)}'));
      }
      final isNumber = RegExp(r'^\d+$').hasMatch(q);
      final invoices = !canInvoices ? const <Map<String, Object?>>[] : await db.rawQuery('''
        SELECT id, invoice_number, customer_name, total_amount, invoice_date FROM invoices
        WHERE COALESCE(is_deleted, 0) = 0 AND (invoice_number = ? ${isNumber ? 'OR id = ?' : ''} OR customer_name LIKE ?)
        ORDER BY id DESC LIMIT 8
      ''', [q, if (isNumber) int.parse(q), like]);
      for (final r in invoices) {
        final no = (r['invoice_number'] as String?)?.isNotEmpty == true ? r['invoice_number'] : r['id'];
        final date = '${r['invoice_date'] ?? ''}';
        hits.add(_Hit(_Kind.invoice, r['id'] as int, 'فاتورة رقم $no — ${r['customer_name'] ?? ''}',
            'فاتورة • ${date.length >= 10 ? date.substring(0, 10) : date} • ${fmtMoney((r['total_amount'] as num?) ?? 0)}'));
      }
    } catch (_) {}
    if (!mounted || seq != _seq) return;
    setState(() {
      _hits = hits;
      _busy = false;
    });
  }

  Future<void> _open(_Hit h) async {
    final nav = Navigator.of(context);
    final db = DatabaseService();
    switch (h.kind) {
      case _Kind.customer:
        if (!requirePermission(context, AppPermissions.debtRegister)) return;
        final Customer? c = await db.getCustomerById(h.id);
        if (c == null) return;
        nav.pop();
        nav.push(MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: c)));
        break;
      case _Kind.product:
        if (!requirePermission(context, AppPermissions.itemCard)) return;
        nav.pop();
        nav.push(MaterialPageRoute(builder: (_) => ItemCardEditorScreen(productId: h.id)));
        break;
      case _Kind.invoice:
        if (!requirePermission(context, AppPermissions.editInvoices)) return;
        final inv = await db.getInvoiceById(h.id);
        if (inv == null) return;
        nav.pop();
        nav.push(MaterialPageRoute(
          builder: (_) => CreateInvoiceScreen(
            existingInvoice: inv,
            isViewOnly: inv.status == 'محفوظة' || !inv.isCreatedByMe,
          ),
        ));
        break;
    }
  }

  static IconData _icon(_Kind k) => switch (k) {
        _Kind.customer => Icons.person_outline,
        _Kind.product => Icons.inventory_2_outlined,
        _Kind.invoice => Icons.receipt_long_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 60, left: 24, right: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                onSubmitted: (_) {
                  if (_hits.isNotEmpty) _open(_hits.first);
                },
                decoration: InputDecoration(
                  hintText: 'ابحث: اسم عميل، هاتف، اسم مادة، رقم فاتورة...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _busy
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (_hits.isEmpty && _controller.text.trim().isNotEmpty && !_busy)
              const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد نتائج')),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _hits.length,
                itemBuilder: (_, i) {
                  final h = _hits[i];
                  return ListTile(
                    leading: Icon(_icon(h.kind)),
                    title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(h.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => _open(h),
                  );
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Text('Enter يفتح أول نتيجة • Esc للإغلاق',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}
