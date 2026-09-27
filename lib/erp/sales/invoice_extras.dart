// lib/erp/sales/invoice_extras.dart
//
// 🏷️ «حقول إضافية» للفاتورة (مثل الإداري): البائع وعمولته، طريقة التسليم،
// شركة الشحن ورقم الإشعار، رقم الطلب/العرض المرتبط، ملاحظات 2.
// + إدارة البائعين وتقرير عمولاتهم ومبيعاتهم.
//
// العمولة تُرحَّل تلقائياً: مدين عمولات البيع / دائن عمولات مستحقة للبائعين.
// دفع العمولة للبائع = سند صرف على حساب «عمولات مستحقة للبائعين».

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart';
import '../../accounting/screens/acc_ui.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../report_export.dart';

class Seller {
  Seller(this.id, this.name, this.commissionPercent, this.phone, this.isActive);
  final int id;
  final String name;
  final double commissionPercent;
  final String? phone;
  final bool isActive;
  factory Seller.fromMap(Map<String, Object?> m) => Seller(m['id'] as int, m['name'] as String,
      d0(m['commission_percent']), m['phone'] as String?, (m['is_active'] as int? ?? 1) == 1);
}

class InvoiceExtrasService {
  Future<List<Seller>> sellers({bool activeOnly = true}) async {
    final db = await erpDb();
    final r = await db.query('sellers', where: activeOnly ? 'is_active = 1' : null, orderBy: 'name');
    return r.map(Seller.fromMap).toList();
  }

  Future<void> saveSeller({int? id, required String name, double commission = 0, String? phone, bool active = true}) async {
    if (name.trim().isEmpty) throw ErpException('اكتب اسم البائع');
    if (commission < 0 || commission > 100) throw ErpException('نسبة العمولة بين 0 و 100');
    final db = await erpDb();
    final row = {'name': name.trim(), 'commission_percent': commission, 'phone': phone, 'is_active': active ? 1 : 0};
    if (id == null) {
      await db.insert('sellers', {...row, 'created_at': DateTime.now().toIso8601String()});
    } else {
      await db.update('sellers', row, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<Map<String, Object?>?> get(int invoiceId) async {
    final db = await erpDb();
    final r = await db.query('invoice_extras', where: 'invoice_id = ?', whereArgs: [invoiceId], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  /// يحفظ الحقول الإضافية. العمولة = النسبة × (إجمالي الفاتورة − الحسم) إن لم تُكتب يدوياً.
  Future<void> save(
    int invoiceId, {
    Seller? seller,
    double? commissionPercent,
    double? commissionAmount,
    String? deliveryMethod,
    String? shippingCompany,
    String? shippingNo,
    String? orderRef,
    String? quoteRef,
    String? notes2,
  }) async {
    final db = await erpDb();
    final inv = await db.query('invoices', columns: ['total_amount', 'discount', 'invoice_date'],
        where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (inv.isEmpty) throw ErpException('الفاتورة غير موجودة');
    await PeriodLock.assertOpen(parseDate(inv.first['invoice_date']));
    // total_amount محفوظ بعد الحسم وأجور التحميل
    final net = d0(inv.first['total_amount']);
    final pct = commissionPercent ?? seller?.commissionPercent ?? 0;
    final amount = commissionAmount ?? roundMoney(net * pct / 100);
    if (amount < 0) throw ErpException('العمولة لا تكون سالبة');
    await db.rawInsert('''
      INSERT OR REPLACE INTO invoice_extras(invoice_id, seller_id, seller_name, commission_percent, commission_amount,
        delivery_method, shipping_company, shipping_no, order_ref, quote_ref, notes2, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      invoiceId,
      seller?.id,
      seller?.name,
      pct,
      seller == null ? 0 : amount,
      deliveryMethod,
      shippingCompany,
      shippingNo,
      orderRef,
      quoteRef,
      notes2,
      DateTime.now().toIso8601String(),
    ]);
  }

  /// مبيعات وعمولات البائعين لفترة.
  Future<List<Map<String, Object?>>> sellerReport(DateTime? from, DateTime to) async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT x.seller_name, COUNT(*) AS n,
             COALESCE(SUM(i.total_amount), 0) AS sales,
             COALESCE(SUM(x.commission_amount), 0) AS commission
      FROM invoice_extras x JOIN invoices i ON i.id = x.invoice_id
      WHERE x.seller_name IS NOT NULL AND i.status = 'محفوظة' AND COALESCE(i.is_deleted, 0) = 0
        AND i.invoice_date < ? ${from == null ? '' : 'AND i.invoice_date >= ?'}
      GROUP BY x.seller_name ORDER BY sales DESC
    ''', [isoDayAfter(to), if (from != null) isoDay(from)]);
  }

  /// رصيد العمولات المستحقة (غير المدفوعة) من الدفتر.
  Future<double> commissionsPayable() async {
    final db = await erpDb();
    try {
      final acc = await Ledger.systemAccountId(db, 'commissions_payable');
      final r = await db.rawQuery(
          'SELECT COALESCE(SUM(credit - debit), 0) AS b FROM journal_lines WHERE account_id = ?', [acc]);
      return d0(r.first['b']);
    } catch (_) {
      return 0;
    }
  }
}

/// نافذة «حقول إضافية» لفاتورة محفوظة.
Future<void> showInvoiceExtrasDialog(BuildContext context, int invoiceId) async {
  final svc = InvoiceExtrasService();
  final sellers = await svc.sellers();
  final cur = await svc.get(invoiceId);
  if (!context.mounted) return;
  int? sellerId = cur?['seller_id'] as int?;
  final pct = TextEditingController(text: cur?['commission_percent'] == null ? '' : fmtQty(d0(cur!['commission_percent'])));
  final delivery = TextEditingController(text: '${cur?['delivery_method'] ?? ''}');
  final shipping = TextEditingController(text: '${cur?['shipping_company'] ?? ''}');
  final shippingNo = TextEditingController(text: '${cur?['shipping_no'] ?? ''}');
  final orderRef = TextEditingController(text: '${cur?['order_ref'] ?? ''}');
  final quoteRef = TextEditingController(text: '${cur?['quote_ref'] ?? ''}');
  final notes2 = TextEditingController(text: '${cur?['notes2'] ?? ''}');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text('حقول إضافية — فاتورة #$invoiceId'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: FieldGrid(children: [
              DropBox<int>(
                label: 'البائع',
                width: 250,
                value: sellers.any((s) => s.id == sellerId) ? sellerId : null,
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('— بلا —')),
                  for (final s in sellers)
                    DropdownMenuItem(value: s.id, child: Text('${s.name} (${fmtQty(s.commissionPercent)}%)')),
                ],
                onChanged: (v) => set(() {
                  sellerId = v;
                  final s = sellers.where((x) => x.id == v);
                  pct.text = s.isEmpty ? '' : fmtQty(s.first.commissionPercent);
                }),
              ),
              MoneyField(controller: pct, label: 'نسبة العمولة %', width: 150),
              TextBox(controller: delivery, label: 'طريقة التسليم', width: 240),
              TextBox(controller: shipping, label: 'شركة الشحن', width: 240),
              TextBox(controller: shippingNo, label: 'رقم إشعار الشحن', width: 240),
              TextBox(controller: orderRef, label: 'رقم الطلب', width: 240),
              TextBox(controller: quoteRef, label: 'رقم العرض', width: 240),
              TextBox(controller: notes2, label: 'ملاحظات 2', width: 490, maxLines: 2),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    final s = sellers.where((x) => x.id == sellerId);
    await svc.save(
      invoiceId,
      seller: s.isEmpty ? null : s.first,
      commissionPercent: parseMoney(pct.text),
      deliveryMethod: delivery.text.trim(),
      shippingCompany: shipping.text.trim(),
      shippingNo: shippingNo.text.trim(),
      orderRef: orderRef.text.trim(),
      quoteRef: quoteRef.text.trim(),
      notes2: notes2.text.trim(),
    );
    if (context.mounted) showOk(context, 'حُفظت الحقول الإضافية');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// البائعون وتقرير عمولاتهم.
class SellersScreen extends StatefulWidget {
  const SellersScreen({super.key});
  @override
  State<SellersScreen> createState() => _SellersScreenState();
}

class _SellersScreenState extends State<SellersScreen> {
  final _svc = InvoiceExtrasService();
  List<Seller> _sellers = const [];
  List<Map<String, Object?>> _report = const [];
  double _payable = 0;
  DateTime? _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await _svc.sellers(activeOnly: false);
    final r = await _svc.sellerReport(_from, _to);
    final p = await _svc.commissionsPayable();
    if (mounted) {
      setState(() {
        _sellers = s;
        _report = r;
        _payable = p;
      });
    }
  }

  Future<void> _edit([Seller? s]) async {
    final name = TextEditingController(text: s?.name ?? '');
    final pct = TextEditingController(text: s == null ? '' : fmtQty(s.commissionPercent));
    final phone = TextEditingController(text: s?.phone ?? '');
    bool active = s?.isActive ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(s == null ? 'بائع جديد' : 'تعديل البائع'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextBox(controller: name, label: 'الاسم'),
              const SizedBox(height: 10),
              MoneyField(controller: pct, label: 'نسبة العمولة %'),
              const SizedBox(height: 10),
              TextBox(controller: phone, label: 'الهاتف'),
              SwitchListTile(value: active, onChanged: (v) => set(() => active = v), title: const Text('فعّال')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _svc.saveSeller(
          id: s?.id, name: name.text, commission: parseMoney(pct.text) ?? 0, phone: phone.text.trim(), active: active);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'البائعون والعمولات',
      subtitle: 'مبيعات كل بائع وعمولته (تُرحَّل تلقائياً)',
      icon: Icons.badge,
      actions: exportActions(context,
          title: 'عمولات البائعين',
          headers: () => ['البائع', 'عدد الفواتير', 'المبيعات', 'العمولة'],
          rows: () => [
                for (final r in _report)
                  ['${r['seller_name']}', '${r['n']}', fmtMoney(d0(r['sales'])), fmtMoney(d0(r['commission']))],
              ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: ErpColors.navy,
        foregroundColor: Colors.white,
        onPressed: () => _edit(),
        child: const Icon(Icons.person_add),
      ),
      headerExtra: Wrap(spacing: 10, children: [
        StatCard(label: 'عمولات مستحقة غير مدفوعة', value: fmtMoney(_payable), icon: Icons.account_balance_wallet, color: ErpColors.orange,
            hint: 'تُدفع بسند صرف على حساب «عمولات مستحقة للبائعين»'),
      ]),
      body: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
        PeriodBar(from: _from, to: _to, onChanged: (f, t) {
          _from = f;
          _to = t;
          _load();
        }),
        ErpSection(
          title: 'مبيعات الفترة',
          icon: Icons.leaderboard,
          color: ErpColors.green,
          child: _report.isEmpty
              ? const EmptyState('لا توجد فواتير مرتبطة ببائع في الفترة')
              : SimpleTable(
                  headers: const ['البائع', 'عدد الفواتير', 'المبيعات', 'العمولة'],
                  numericColumns: const {1, 2, 3},
                  rows: [
                    for (final r in _report)
                      ['${r['seller_name']}', '${r['n']}', fmtMoney(d0(r['sales'])), fmtMoney(d0(r['commission']))],
                  ],
                ),
        ),
        ErpSection(
          title: 'البائعون',
          icon: Icons.people_outline,
          child: Column(children: [
            for (final s in _sellers)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: (s.isActive ? ErpColors.navy : ErpColors.muted).withOpacity(0.1),
                  child: Icon(Icons.person, color: s.isActive ? ErpColors.navy : ErpColors.muted),
                ),
                title: Text(s.name),
                subtitle: Text('العمولة ${fmtQty(s.commissionPercent)}%${s.phone == null || s.phone!.isEmpty ? '' : ' • ${s.phone}'}'),
                trailing: s.isActive ? null : const StatusBadge('موقوف', color: ErpColors.muted),
                onTap: () => _edit(s),
              ),
            if (_sellers.isEmpty) const EmptyState('أضف بائعاً بزر +'),
          ]),
        ),
      ]),
    );
  }
}
