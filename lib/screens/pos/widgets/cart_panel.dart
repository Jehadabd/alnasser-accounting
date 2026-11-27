// lib/screens/pos/widgets/cart_panel.dart
//
// 🧺 سلة الكاشير: العميل، أسطر المواد جدولاً بأعمدة يختارها المستخدم ويغيّر عرضها
//  (cart_table.dart)، والدفع.
//  • سعر السطر يُكتب بحرية ويُعتمد عند الخروج من الحقل أو Enter (لا يقفز المؤشر)
//  • زر الدفع يُقفل أثناء الحفظ (منع الحفظ المكرر) — والاختصار F9
//  • «مسح» السلة يطلب تأكيداً

import '../../../services/save_lock.dart'; // 🔒 قفل الحفظ
import '../../../services/credit_limit_guard.dart'; // 🚫 سقف الدين
import '../../../services/database_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/pos_provider.dart';
import '../../../widgets/formatters.dart';
import '../pos_receipts_screen.dart';
import 'cart_table.dart'; // ▦ أسطر السلة جدولاً
import 'pos_style.dart';

class CartPanel extends StatefulWidget {
  const CartPanel({super.key, this.onCheckedOut, this.onLayoutChanged});

  /// يُستدعى بعد حفظ الفاتورة بنجاح (مثلاً لإغلاق السلة المنبثقة على الشاشات الصغيرة)
  final VoidCallback? onCheckedOut;

  /// تغيّر تخطيط السلة من قائمة أعمدتها (مثل إعادة عرض السلة للافتراضي)
  final VoidCallback? onLayoutChanged;

  @override
  State<CartPanel> createState() => CartPanelState();
}

class CartPanelState extends State<CartPanel> {
  final _customerController = TextEditingController();
  final _discountController = TextEditingController();
  final _paidController = TextEditingController();

  /// 💵 المستلم من الزبون (نقداً) لحساب «الباقي للزبون» — عرض فقط، لا يُحفظ
  final _tenderedController = TextEditingController();
  double _tendered = 0;
  bool _showSuggestions = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // عند فتح السلة من جديد (الورقة المنبثقة) تبقى القيم الحالية ظاهرة
    final pos = context.read<POSProvider>();
    _customerController.text = pos.customerName;
    if (pos.discount > 0) _discountController.text = posMoney(pos.discount);
    if (pos.paidAmount > 0) _paidController.text = posMoney(pos.paidAmount);
  }

  @override
  void dispose() {
    _customerController.dispose();
    _discountController.dispose();
    _paidController.dispose();
    _tenderedController.dispose();
    super.dispose();
  }

  void _resetFields() {
    _customerController.clear();
    _discountController.clear();
    _paidController.clear();
    _tenderedController.clear();
    _tendered = 0;
    _showSuggestions = false;
  }

  /// 💳 حفظ الفاتورة (زر الدفع أو F9)
  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط (القفل قبل أي انتظار)
  Future<void> checkout() async {
    await SaveLock.run(() => _checkoutUnlocked(), message: 'جارٍ حفظ البيع…');
  }
  Future<void> _checkoutUnlocked() async {
    final pos = context.read<POSProvider>();
    if (_busy || pos.cartItems.isEmpty) return;
    FocusScope.of(context).unfocus(); // يُعتمد أي سعر ما زال قيد الكتابة
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    // 🚫 سقف الدين: الباقي على العميل في البيع الآجل
    if (pos.paymentType == PaymentType.credit) {
      final dbx = await DatabaseService().database;
      final cid = await CreditLimitGuard.customerIdByName(dbx, pos.customerName);
      if (!mounted) return;
      final go = await CreditLimitGuard.enforce(
        context,
        customerId: cid,
        increase: pos.remainingAmount,
        what: 'بيع آجل (كاشير) — ${pos.customerName.trim()}',
      );
      if (!go || !mounted) return;
    }
    setState(() => _busy = true);
    final ok = await pos.processCheckout();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = false;
      if (ok) _resetFields();
    });
    if (ok) {
      messenger.showSnackBar(SnackBar(
        content: Text('تم حفظ الفاتورة #${pos.lastInvoiceDisplayNumber ?? pos.lastInvoiceId}'),
        backgroundColor: PosColors.cash,
        behavior: SnackBarBehavior.floating,
      ));
      widget.onCheckedOut?.call();
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(pos.lastErrorMessage ?? 'حدث خطأ أثناء حفظ الفاتورة'),
        backgroundColor: PosColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _confirmClear(POSProvider pos) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح السلة؟'),
        content: Text('ستُحذف ${pos.cartItems.length} مادة من السلة الحالية.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PosColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('مسح'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    pos.clearCart();
    setState(_resetFields);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<POSProvider>(
      builder: (context, pos, _) {
        final items = pos.cartItems;
        return Container(
          decoration: const BoxDecoration(
            color: PosColors.surface,
            border: BorderDirectional(start: BorderSide(color: PosColors.border)),
          ),
          child: LayoutBuilder(
            builder: (context, box) => Column(
              children: [
                _header(pos),
                _customerField(pos),
                Expanded(
                  child: items.isEmpty
                      ? const _EmptyCart()
                      : Container(
                          margin: const EdgeInsets.fromLTRB(10, 2, 10, 8),
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: PosColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: PosColors.border),
                          ),
                          child: CartTable(pos: pos, onLayoutChanged: widget.onLayoutChanged),
                        ),
                ),
                ConstrainedBox(
                  // على الشاشات القصيرة يُمرَّر الملخص بدل أن يفيض
                  constraints: BoxConstraints(maxHeight: box.maxHeight * 0.62),
                  child: SingleChildScrollView(child: _summary(pos)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(POSProvider pos) {
    final n = pos.cartItems.length;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 8, 6),
      child: Row(
        children: [
          const Icon(Icons.shopping_basket_outlined, color: PosColors.primary, size: 22),
          const SizedBox(width: 8),
          const Text('السلة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: PosColors.text)),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: n > 0 ? PosColors.accent : PosColors.surfaceAlt,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$n',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: n > 0 ? Colors.white : PosColors.muted,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'إيصالات الكاشير',
            icon: const Icon(Icons.history_rounded, color: PosColors.muted, size: 21),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PosReceiptsScreen())),
          ),
          if (n > 0)
            TextButton.icon(
              onPressed: () => _confirmClear(pos),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: PosColors.danger),
              label: const Text('مسح', style: TextStyle(color: PosColors.danger, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  Widget _customerField(POSProvider pos) {
    final suggestions = pos.filteredCustomers;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: [
          TextField(
            controller: _customerController,
            onChanged: (v) {
              pos.setCustomerName(v);
              setState(() => _showSuggestions = v.trim().isNotEmpty);
            },
            style: const TextStyle(fontSize: 13.5),
            decoration: _inputDecoration(
              hint: pos.paymentType == PaymentType.credit ? 'اسم العميل (مطلوب للدين)' : 'اسم العميل (اختياري)',
              icon: Icons.person_outline_rounded,
            ),
          ),
          if (_showSuggestions && suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: PosColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PosColors.border),
                boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 12, offset: Offset(0, 4))],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (final c in suggestions)
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: const CircleAvatar(
                          radius: 13,
                          backgroundColor: PosColors.accentSoft,
                          child: Icon(Icons.person_rounded, size: 15, color: PosColors.accent),
                        ),
                        title: Text(c.name, style: const TextStyle(fontSize: 13)),
                        subtitle: c.currentTotalDebt > 0
                            ? Text('عليه ${posMoney(c.currentTotalDebt)}',
                                style: const TextStyle(fontSize: 11, color: PosColors.credit))
                            : null,
                        onTap: () {
                          _customerController.text = c.name;
                          pos.selectCustomer(c);
                          setState(() => _showSuggestions = false);
                        },
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summary(POSProvider pos) {
    final cash = pos.paymentType == PaymentType.cash;
    final payColor = cash ? PosColors.cash : PosColors.credit;
    final total = pos.total;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: const BoxDecoration(
        color: PosColors.surfaceAlt,
        border: Border(top: BorderSide(color: PosColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PaySwitch(
            cash: cash,
            onChanged: (isCash) {
              pos.setPaymentType(isCash ? PaymentType.cash : PaymentType.credit);
              setState(() {
                _paidController.clear();
                _tenderedController.clear();
                _tendered = 0;
              });
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _moneyField(
                  label: 'الخصم',
                  controller: _discountController,
                  onChanged: (v) => pos.setDiscount(v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: cash
                    ? _moneyField(
                        label: 'المستلم من الزبون',
                        controller: _tenderedController,
                        onChanged: (v) => setState(() => _tendered = v),
                      )
                    : _moneyField(
                        label: 'المبلغ المسدد',
                        controller: _paidController,
                        onChanged: (v) => pos.setPaidAmount(v),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SumLine(label: 'المجموع', value: posMoney(pos.subtotal)),
          if (pos.discount > 0) _SumLine(label: 'الخصم', value: '− ${posMoney(pos.discount)}', color: PosColors.danger),
          if (cash && _tendered > 0)
            _SumLine(
              label: _tendered >= total ? 'الباقي للزبون' : 'ناقص',
              value: posMoney((_tendered - total).abs()),
              color: _tendered >= total ? PosColors.cash : PosColors.danger,
              bold: true,
            ),
          if (!cash)
            _SumLine(
              label: 'المتبقي ديناً',
              value: posMoney(pos.remainingAmount),
              color: PosColors.credit,
              bold: true,
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: PosColors.border),
          ),
          Row(
            children: [
              const Text('الإجمالي', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: PosColors.text)),
              const SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: payColor, fontFamily: DefaultTextStyle.of(context).style.fontFamily),
                    child: Text(posMoney(total)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: pos.cartItems.isEmpty || _busy ? null : checkout,
              style: FilledButton.styleFrom(
                backgroundColor: payColor,
                disabledBackgroundColor: PosColors.border,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  else
                    Icon(cash ? Icons.payments_rounded : Icons.receipt_long_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _busy ? 'جارٍ الحفظ…' : (cash ? 'دفع نقدي' : 'حفظ كدين'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('F9', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<double> onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      onChanged: (v) => onChanged(double.tryParse(v.replaceAll(',', '')) ?? 0),
      decoration: _inputDecoration(label: label, hint: '0'),
    );
  }
}

InputDecoration _inputDecoration({String? label, String? hint, IconData? icon}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(fontSize: 12.5, color: PosColors.muted),
    hintStyle: const TextStyle(fontSize: 13, color: PosColors.faint),
    prefixIcon: icon == null ? null : Icon(icon, size: 19, color: PosColors.muted),
    isDense: true,
    filled: true,
    fillColor: PosColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: border(PosColors.border),
    enabledBorder: border(PosColors.border),
    focusedBorder: border(PosColors.accent, 1.5),
  );
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_basket_outlined, size: 52, color: Color(0xFFCBD5E1)),
          SizedBox(height: 10),
          Text('السلة فارغة', style: TextStyle(color: PosColors.muted, fontSize: 14, fontWeight: FontWeight.w600)),
          SizedBox(height: 4),
          Text('اضغط على مادة أو امسح باركودها', style: TextStyle(color: PosColors.faint, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PaySwitch extends StatelessWidget {
  const _PaySwitch({required this.cash, required this.onChanged});

  final bool cash;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(bool isCash, String label, IconData icon) {
      final sel = cash == isCash;
      final c = isCash ? PosColors.cash : PosColors.credit;
      return Expanded(
        child: GestureDetector(
          onTap: sel ? null : () => onChanged(isCash),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: 40,
            decoration: BoxDecoration(
              color: sel ? c : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: sel ? [BoxShadow(color: c.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))] : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: sel ? Colors.white : PosColors.muted),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : PosColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: PosColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PosColors.border),
      ),
      child: Row(
        children: [
          seg(true, 'نقد', Icons.payments_outlined),
          const SizedBox(width: 3),
          seg(false, 'دين', Icons.account_balance_wallet_outlined),
        ],
      ),
    );
  }
}

class _SumLine extends StatelessWidget {
  const _SumLine({required this.label, required this.value, this.color, this.bold = false});

  final String label;
  final String value;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: color ?? PosColors.muted, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: color ?? PosColors.text, fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
