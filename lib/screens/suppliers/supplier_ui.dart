// lib/screens/suppliers/supplier_ui.dart
//
// 🧩 عناصر مشتركة لشاشات الموردين:
//   • تنسيق المبالغ والحالات (فاتورة: مسودة/مؤكدة/ملغاة…، طريقة الدفع).
//   • SupActionCard — زر إجراء على شكل بطاقة (حركة عند المرور).
//   • PurchaseInvoiceTile / SupplierPaymentTile — صف فاتورة/سند بإجراءاته.
//   • نوافذ: الرصيد الافتتاحي، إلغاء سند دفع، إلغاء فاتورة شراء.

import '../../services/save_lock.dart'; // 🔒 قفل الحفظ
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../erp/erp_common.dart' show parseMoney;
import '../../erp/erp_ui.dart';
import '../../models/purchase_invoice.dart';
import '../../models/supplier.dart';
import '../../models/supplier_payment.dart';
import '../../services/purchase_service.dart';
import '../../widgets/formatters.dart';

/// لون هوية الموردين (سماوي داكن).
const supplierAccent = Color(0xFF0E7490);
const supOwe = Color(0xFFB91C1C); // له علينا
const supCredit = Color(0xFF047857); // لنا عنده

String supCur(String c) => c == 'USD' ? '\$' : 'د.ع';
String supMoney(double v, String c) => '${fmtMoney(v)} ${supCur(c)}';

/// مجموع لكل عملة كنص: «1,000 د.ع + 50 $».
String supTotals(Map<String, double> byCurrency) {
  final parts = <String>[
    for (final e in byCurrency.entries)
      if (e.value.abs() > 0.004) supMoney(e.value, e.key),
  ];
  return parts.isEmpty ? '0' : parts.join(' + ');
}

/// أرصدة المورد التي تستحق العرض: الدينار دائماً (إلا إن كان كله دولاراً)، والدولار إن وُجد.
List<(String, double)> supBalances(Supplier s) => [
      if (s.totalDebtIqd.abs() > 0.01 || s.totalDebtUsd.abs() <= 0.01) ('IQD', s.totalDebtIqd),
      if (s.totalDebtUsd.abs() > 0.01) ('USD', s.totalDebtUsd),
    ];

Color supBalanceColor(double v) => v > 0.01 ? supOwe : (v < -0.01 ? supCredit : AccColors.muted);
String supBalanceCaption(double v) => v > 0.01 ? 'له علينا' : (v < -0.01 ? 'لنا عنده' : 'لا دين');

String invoiceStatusLabel(String s) => switch (s) {
      'draft' => 'مسودة',
      'confirmed' => 'مؤكدة',
      'cancelled' => 'ملغاة',
      'paid' => 'مدفوعة',
      'partial' => 'مدفوعة جزئياً',
      _ => s,
    };

Color invoiceStatusColor(String s) => switch (s) {
      'draft' => const Color(0xFF64748B),
      'confirmed' => const Color(0xFF2563EB),
      'cancelled' => const Color(0xFFB91C1C),
      'paid' => const Color(0xFF047857),
      'partial' => const Color(0xFFC2410C),
      _ => const Color(0xFF2563EB),
    };

String paymentMethodLabel(String m) => switch (m) {
      'cash' => 'نقداً',
      'bank' => 'تحويل بنكي',
      'transfer' => 'حوالة',
      'cheque' => 'شيك',
      'discount' => 'خصم مكتسب',
      _ => m,
    };

String supInitial(String name) {
  final t = name.trim();
  return t.isEmpty ? '?' : t.characters.first;
}

// ═══════════════════════════ زر إجراء ═══════════════════════════

class SupActionCard extends StatefulWidget {
  const SupActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  State<SupActionCard> createState() => _SupActionCardState();
}

class _SupActionCardState extends State<SupActionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: _hover ? Color.alphaBlend(c.withValues(alpha: 0.05), Colors.white) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hover ? c.withValues(alpha: 0.5) : ErpColors.border),
          boxShadow: [
            BoxShadow(
              color: _hover ? c.withValues(alpha: 0.18) : const Color(0x080F172A),
              blurRadius: _hover ? 16 : 6,
              offset: Offset(0, _hover ? 7 : 2),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _hover ? c : c.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, size: 22, color: _hover ? Colors.white : c),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: ErpColors.text)),
                      if (widget.subtitle != null)
                        Text(widget.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: ErpColors.muted)),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// شبكة أزرار إجراءات متجاوبة (ارتفاع ثابت).
class SupActionGrid extends StatelessWidget {
  const SupActionGrid({super.key, required this.children, this.maxExtent = 250});
  final List<Widget> children;
  final double maxExtent;
  @override
  Widget build(BuildContext context) => GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxExtent,
          mainAxisExtent: 70,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        children: [for (var i = 0; i < children.length; i++) FadeSlideIn(index: i, child: children[i])],
      );
}

// ═══════════════════════════ صف فاتورة ═══════════════════════════

class PurchaseInvoiceTile extends StatefulWidget {
  const PurchaseInvoiceTile({
    super.key,
    required this.invoice,
    this.supplierName,
    this.onOpen,
    this.onEdit,
    this.onCancel,
  });
  final PurchaseInvoice invoice;
  final String? supplierName;
  final VoidCallback? onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;

  @override
  State<PurchaseInvoiceTile> createState() => _PurchaseInvoiceTileState();
}

class _PurchaseInvoiceTileState extends State<PurchaseInvoiceTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final st = inv.status;
    final c = invoiceStatusColor(st);
    final cancelled = st == 'cancelled';
    final remaining = inv.remainingAmount;
    final sub = [
      fmtDate(inv.date),
      if (widget.supplierName != null && widget.supplierName!.trim().isNotEmpty) widget.supplierName!,
      if (inv.paidAmount > 0.004) 'الواصل: ${supMoney(inv.paidAmount, inv.currency)}',
    ].join('  •  ');
    final hasMenu = widget.onOpen != null || widget.onEdit != null || (widget.onCancel != null && !cancelled);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: cancelled ? const Color(0xFFFBFBFC) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hover ? c.withValues(alpha: 0.45) : ErpColors.border),
            boxShadow: [
              BoxShadow(
                color: _hover ? c.withValues(alpha: 0.12) : const Color(0x080F172A),
                blurRadius: _hover ? 12 : 5,
                offset: Offset(0, _hover ? 4 : 2),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: widget.onOpen,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 10),
                child: Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: c.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(12)),
                    child: Icon(cancelled ? Icons.block_rounded : Icons.receipt_long_rounded, color: c, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(
                          child: Text('فاتورة ${inv.invoiceNumber}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: cancelled ? ErpColors.muted : ErpColors.text,
                              )),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(invoiceStatusLabel(st), color: c),
                      ]),
                      const SizedBox(height: 3),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(
                      supMoney(inv.totalAmount, inv.currency),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: cancelled ? ErpColors.muted : ErpColors.text,
                        decoration: cancelled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (st == 'confirmed' && remaining > 0.004)
                      Text('المتبقي ${supMoney(remaining, inv.currency)}',
                          style: const TextStyle(fontSize: 11.5, color: AccColors.orange, fontWeight: FontWeight.w600)),
                  ]),
                  if (hasMenu)
                    PopupMenuButton<String>(
                      tooltip: 'إجراءات',
                      icon: const Icon(Icons.more_vert_rounded, color: ErpColors.muted),
                      onSelected: (v) {
                        if (v == 'open') widget.onOpen?.call();
                        if (v == 'edit') widget.onEdit?.call();
                        if (v == 'cancel') widget.onCancel?.call();
                      },
                      itemBuilder: (_) => [
                        if (widget.onOpen != null)
                          const PopupMenuItem(
                              value: 'open',
                              child: ListTile(
                                  dense: true, leading: Icon(Icons.open_in_new_rounded), title: Text('فتح التفاصيل'))),
                        if (widget.onEdit != null && !cancelled)
                          const PopupMenuItem(
                              value: 'edit',
                              child: ListTile(dense: true, leading: Icon(Icons.edit_rounded), title: Text('تعديل'))),
                        if (widget.onCancel != null && !cancelled)
                          const PopupMenuItem(
                              value: 'cancel',
                              child: ListTile(
                                dense: true,
                                leading: Icon(Icons.block_rounded, color: supOwe),
                                title: Text('إلغاء الفاتورة', style: TextStyle(color: supOwe)),
                              )),
                      ],
                    )
                  else
                    const SizedBox(width: 8),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════ صف سند دفع ═══════════════════════════

class SupplierPaymentTile extends StatefulWidget {
  const SupplierPaymentTile({super.key, required this.payment, this.onVoid});
  final SupplierPayment payment;
  final VoidCallback? onVoid;
  @override
  State<SupplierPaymentTile> createState() => _SupplierPaymentTileState();
}

class _SupplierPaymentTileState extends State<SupplierPaymentTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.payment;
    final v = p.isVoid;
    final c = v ? ErpColors.muted : supCredit;
    final notes = (p.notes ?? '').trim();
    final sub = [fmtDate(p.date), paymentMethodLabel(p.paymentMethod), if (notes.isNotEmpty) notes].join('  •  ');
    final badge = v
        ? Tooltip(
            message: (p.voidReason ?? '').isEmpty ? 'سند ملغى' : 'السبب: ${p.voidReason}',
            child: const StatusBadge('ملغى', color: supOwe),
          )
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: v ? const Color(0xFFFBFBFC) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hover && !v ? c.withValues(alpha: 0.45) : ErpColors.border),
            boxShadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 5, offset: Offset(0, 2))],
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 10),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: c.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(12)),
                child: Icon(v ? Icons.money_off_rounded : Icons.payments_rounded, color: c, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        p.receiptNumber != null ? 'سند دفع رقم ${p.receiptNumber}' : 'دفعة للمورد',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14, color: v ? ErpColors.muted : ErpColors.text),
                      ),
                    ),
                    if (badge != null) ...[const SizedBox(width: 8), badge],
                  ]),
                  const SizedBox(height: 3),
                  Text(sub,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
                ]),
              ),
              const SizedBox(width: 8),
              Text(
                supMoney(p.amount, p.currency),
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: c,
                  decoration: v ? TextDecoration.lineThrough : null,
                ),
              ),
              if (widget.onVoid != null && !v)
                PopupMenuButton<String>(
                  tooltip: 'إجراءات',
                  icon: const Icon(Icons.more_vert_rounded, color: ErpColors.muted),
                  onSelected: (_) => widget.onVoid!(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'void',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.block_rounded, color: supOwe),
                        title: Text('إلغاء السند', style: TextStyle(color: supOwe)),
                      ),
                    ),
                  ],
                )
              else
                const SizedBox(width: 12),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════ نوافذ ═══════════════════════════

/// سؤال تأكيد مع سبب اختياري. يعيد السبب ('' مسموح) أو null عند الإلغاء.
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String message,
  required String ok,
  Color color = supOwe,
  IconData icon = Icons.block_rounded,
}) {
  final reason = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => ErpDialog(
      title: title,
      icon: icon,
      color: color,
      width: 500,
      content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(message, style: const TextStyle(height: 1.7)),
        const SizedBox(height: 14),
        TextField(
          controller: reason,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'السبب (اختياري)', prefixIcon: Icon(Icons.edit_note_rounded)),
          onSubmitted: (_) => Navigator.pop(ctx, reason.text.trim()),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تراجع')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: color),
          onPressed: () => Navigator.pop(ctx, reason.text.trim()),
          icon: Icon(icon, size: 19),
          label: Text(ok),
        ),
      ],
    ),
  );
}

/// إلغاء سند دفع لمورد (تأكيد + سبب). يعيد true إن أُلغي.
Future<bool> voidSupplierPaymentFlow(BuildContext context, SupplierPayment p) async {
  final id = p.id;
  if (id == null) return false;
  final svc = context.read<PurchaseService>();
  final reason = await askReason(
    context,
    title: 'إلغاء سند الدفع',
    message: 'سيُلغى ${p.receiptNumber != null ? 'السند رقم ${p.receiptNumber}' : 'السند'} '
        'بمبلغ ${supMoney(p.amount, p.currency)}، ويعود دين المورد كما كان قبله، ويُحذف قيده من الدفتر.\n'
        'يبقى السند في السجل بعلامة «ملغى».',
    ok: 'إلغاء السند',
  );
  if (reason == null || !context.mounted) return false;
  try {
    await svc.voidPayment(id, reason: reason);
    if (context.mounted) showOk(context, 'أُلغي سند الدفع وعاد الرصيد كما كان');
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

/// إلغاء فاتورة شراء (تأكيد + سبب). يعيد true إن أُلغيت.
Future<bool> cancelPurchaseInvoiceFlow(BuildContext context, PurchaseInvoice inv) async {
  final id = inv.id;
  if (id == null) return false;
  final svc = context.read<PurchaseService>();
  final confirmed = inv.status == 'confirmed';
  final reason = await askReason(
    context,
    title: 'إلغاء فاتورة الشراء ${inv.invoiceNumber}',
    message: [
      if (confirmed) 'ستخرج كمياتها من المخزون، ويسقط دينها (${supMoney(inv.remainingAmount, inv.currency)}) عن المورد.',
      if (confirmed && inv.paidAmount > 0.004)
        'المبلغ المدفوع عند الشراء (${supMoney(inv.paidAmount, inv.currency)}) يُحذف قيده أيضاً، أي يُعتبر عائداً إلى الصندوق — '
            'إن لم يُسترد فعلاً سجّله دفعةً للمورد بعد الإلغاء.',
      'تبقى الفاتورة في السجل بعلامة «ملغاة» ولا يمكن التراجع عن الإلغاء.',
    ].join('\n'),
    ok: 'إلغاء الفاتورة',
  );
  if (reason == null || !context.mounted) return false;
  try {
    await svc.cancelPurchaseInvoice(id, reason: reason);
    if (context.mounted) showOk(context, 'أُلغيت فاتورة الشراء ${inv.invoiceNumber}');
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

/// نافذة الرصيد الافتتاحي للمورد. تعيد true إن حُفظ.
Future<bool> showOpeningBalanceDialog(BuildContext context, Supplier s) async {
  if (s.id == null) return false;
  final r = await showDialog<bool>(context: context, builder: (_) => _OpeningBalanceDialog(supplier: s));
  return r == true;
}

class _OpeningBalanceDialog extends StatefulWidget {
  const _OpeningBalanceDialog({required this.supplier});
  final Supplier supplier;
  @override
  State<_OpeningBalanceDialog> createState() => _OpeningBalanceDialogState();
}

class _OpeningBalanceDialogState extends State<_OpeningBalanceDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _cur = 'IQD';
  bool _weOwe = true;
  DateTime _date = DateTime.now();
  Map<String, double> _current = const {'IQD': 0, 'USD': 0};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cur = widget.supplier.currency == 'USD' ? 'USD' : 'IQD';
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final svc = context.read<PurchaseService>();
    try {
      final cur = await svc.getOpeningBalances(widget.supplier.id!);
      final first = await svc.getFirstActivityDate(widget.supplier.id!);
      if (!mounted) return;
      setState(() {
        _current = cur;
        if (first != null) _date = first;
        _loading = false;
      });
      _fill();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذّر قراءة الرصيد الحالي: $e';
        });
      }
    }
  }

  void _fill() {
    final v = _current[_cur] ?? 0;
    _amount.text = v.abs() < 0.004 ? '' : fmtMoney(v.abs());
    setState(() => _weOwe = v >= 0);
  }

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط (القفل قبل أي انتظار)
  Future<void> _save() async {
    await SaveLock.run(() => _saveUnlocked(), message: 'جارٍ الحفظ…');
  }
  Future<void> _saveUnlocked() async {
    if (_saving) return;
    final a = parseMoney(_amount.text) ?? 0;
    if (a < 0) {
      setState(() => _error = 'أدخل المبلغ موجباً واختر الاتجاه');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<PurchaseService>().setOpeningBalance(
            widget.supplier.id!,
            amount: _weOwe ? a : -a,
            currency: _cur,
            date: _date,
            note: _note.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final curText = [
      for (final c in const ['IQD', 'USD'])
        if ((_current[c] ?? 0).abs() > 0.004) '${supMoney((_current[c] ?? 0).abs(), c)} (${supBalanceCaption(_current[c] ?? 0)})',
    ];
    return ErpDialog(
      title: 'رصيد افتتاحي — ${widget.supplier.name}',
      subtitle: 'ما كان على المورد أو له قبل بدء العمل بالبرنامج',
      icon: Icons.flag_rounded,
      color: const Color(0xFF7C3AED),
      width: 540,
      content: _loading
          ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'IQD', label: Text('دينار'), icon: Icon(Icons.payments_outlined)),
                  ButtonSegment(value: 'USD', label: Text('دولار'), icon: Icon(Icons.attach_money_rounded)),
                ],
                selected: {_cur},
                onSelectionChanged: (v) {
                  setState(() => _cur = v.first);
                  _fill();
                },
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: ChoiceTile(
                    title: 'له علينا',
                    subtitle: 'دين للمورد',
                    icon: Icons.north_east_rounded,
                    color: supOwe,
                    dense: true,
                    selected: _weOwe,
                    onTap: () => setState(() => _weOwe = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChoiceTile(
                    title: 'لنا عنده',
                    subtitle: 'دفعنا مقدماً',
                    icon: Icons.south_west_rounded,
                    color: supCredit,
                    dense: true,
                    selected: !_weOwe,
                    onTap: () => setState(() => _weOwe = false),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  labelText: 'المبلغ',
                  hintText: '0',
                  suffixText: supCur(_cur),
                  helperText: 'اتركه صفراً لحذف الرصيد الافتتاحي بهذه العملة',
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _note,
                    decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)', prefixIcon: Icon(Icons.short_text_rounded)),
                  ),
                ),
                const SizedBox(width: 10),
                DatePill(label: 'بتاريخ', value: _date, help: 'تاريخ الرصيد الافتتاحي', onPicked: (d) => setState(() => _date = d)),
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AccColors.soft, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  curText.isEmpty ? 'لا يوجد رصيد افتتاحي مسجّل لهذا المورد.' : 'المسجّل حالياً: ${curText.join(' • ')}',
                  style: const TextStyle(fontSize: 12.5, color: AccColors.text, height: 1.5),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: supOwe, fontWeight: FontWeight.w700)),
              ],
            ]),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
          onPressed: _saving || _loading ? null : _save,
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_rounded, size: 19),
          label: const Text('حفظ'),
        ),
      ],
    );
  }
}
