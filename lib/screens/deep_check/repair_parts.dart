// lib/screens/deep_check/repair_parts.dart
//
// 🎨 قطع نافذة «معالجة» فاتورة في الفحص العميق: رأس الفاتورة، مقارنة «الفاتورة» و«سجل الديون»،
// خط زمني لمعاملاتها، وبطاقات الاختيار (كل واحدة تقول بوضوح هل يتغير الدين أم لا).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/database/business/deep_check_repair.dart';
import '../../widgets/settings_kit.dart';

final repairNum = NumberFormat('#,##0.##', 'en');

/// أسماء أنواع المعاملات كما يفهمها صاحب المحل.
String repairTxType(String t) => switch (t) {
      'invoice_debt' => 'دين فاتورة',
      'invoice_edit' => 'تعديل فاتورة',
      'invoice_payment_type_change' => 'تغيير نقد/دين',
      'invoice_debt_sync' => 'تسوية الحارس المحاسبي',
      'SETTLEMENT' => 'تسوية قديمة',
      'manual_payment' => 'تسديد يدوي',
      'return_payment' => 'تسديد مرتجع',
      'correction' => 'تصحيح',
      'opening_balance' => 'رصيد افتتاحي',
      '' => 'بلا نوع',
      _ => t,
    };

/// الرأس: رقم الفاتورة والعميل وحالتها.
class RepairHeader extends StatelessWidget {
  const RepairHeader(this.i, {super.key, required this.onClose});
  final InvoiceRepairInfo i;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(18, 16, 8, 16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kSetNavy, Color(0xFF1E4E8C)],
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
          ),
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.healing_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('فاتورة ${i.number}',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(i.customerName.isEmpty ? 'بلا اسم' : i.customerName,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                _pill(i.paymentType),
                _pill(i.deleted ? 'محذوفة' : i.status),
              ]),
            ]),
          ),
          IconButton(
            tooltip: 'إغلاق',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ]),
      );

  static Widget _pill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}

/// «حسب الفاتورة» مقابل «في سجل الديون» — والفرق بينهما.
class RepairCompare extends StatelessWidget {
  const RepairCompare(this.i, {super.key});
  final InvoiceRepairInfo i;

  @override
  Widget build(BuildContext context) {
    final diff = i.recordedCurrent - i.expected;
    final bad = diff.abs() > 0.01;
    final left = _side(
      'حسب الفاتورة',
      i.expected,
      Icons.receipt_long_rounded,
      kSetNavy,
      'الإجمالي ${repairNum.format(i.total)} • المسدد ${repairNum.format(i.paid)}'
          '${i.cashSettlements.abs() > 0.01 ? ' • تسويات نقدية ${repairNum.format(i.cashSettlements)}' : ''}',
    );
    final right = _side(
      'في سجل الديون',
      i.recordedCurrent,
      Icons.account_balance_wallet_rounded,
      bad ? kSetRed : kSetGreen,
      i.customerId != null && i.balances.containsKey(i.customerId)
          ? 'رصيد العميل الآن ${repairNum.format(i.balances[i.customerId])}'
          : 'لا عميل مرتبط',
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, c) {
        final mid = Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: (bad ? kSetRed : kSetGreen).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(bad ? 'الفرق ${repairNum.format(diff)}' : 'متطابق',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: bad ? kSetRed : kSetGreen)),
        );
        if (c.maxWidth < 480) return Column(children: [left, mid, right]);
        return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: left),
          mid,
          Expanded(child: right),
        ]);
      }),
      if (i.recordedOthers.abs() > 0.01)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SetBanner(
            'على عملاء آخرين من هذه الفاتورة: ${repairNum.format(i.recordedOthers)} — '
            '${i.recorded.entries.where((e) => e.key != i.customerId).map((e) => '${i.names[e.key] ?? '#${e.key}'} (${repairNum.format(e.value)})').join('، ')}',
            kind: SetBannerKind.error,
          ),
        ),
    ]);
  }

  Widget _side(String title, double v, IconData icon, Color c, String sub) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withValues(alpha: 0.22)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: c)),
          ]),
          const SizedBox(height: 8),
          Text(repairNum.format(v),
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c, height: 1.1)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(fontSize: 11.5, color: kSetMuted, height: 1.4)),
        ]),
      );
}

/// معاملات الفاتورة في سجل الديون بترتيبها الزمني.
class RepairTimeline extends StatelessWidget {
  const RepairTimeline(this.txs, {super.key});
  final List<InvoiceTx> txs;

  @override
  Widget build(BuildContext context) {
    if (txs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('لا معاملات لهذه الفاتورة في سجل الديون', style: TextStyle(color: kSetMuted)),
      );
    }
    return Column(children: [
      for (var k = 0; k < txs.length; k++) _item(txs[k], last: k == txs.length - 1),
    ]);
  }

  Widget _item(InvoiceTx t, {required bool last}) {
    final c = t.amount >= 0 ? kSetRed : kSetGreen;
    final date = t.date.length >= 16 ? t.date.substring(0, 16).replaceFirst('T', '  ') : t.date;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 22,
          child: Column(children: [
            const SizedBox(height: 6),
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            if (!last) Expanded(child: Container(width: 2, color: const Color(0xFFE2E8F0))),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(repairTxType(t.type),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kSetText)),
                ),
                Text('${t.amount >= 0 ? '+' : ''}${repairNum.format(t.amount)}',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontWeight: FontWeight.w800, color: c)),
              ]),
              Text(
                [date, t.customerName, if (t.description.isNotEmpty) t.description].join(' • '),
                style: const TextStyle(fontSize: 11.5, color: kSetMuted, height: 1.4),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// بطاقة اختيار: ماذا يفعل، وهل يتغير الدين — وتُعطَّل بسببها إن لم تكن ممكنة.
class RepairChoice extends StatelessWidget {
  const RepairChoice({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.tag,
    required this.color,
    required this.onTap,
    this.blockedWhy,
    this.recommended = false,
  });
  final IconData icon;
  final String title, text, tag;
  final Color color;
  final VoidCallback? onTap;
  final String? blockedWhy;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && blockedWhy == null;
    final c = enabled ? color : kSetMuted;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.6,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: recommended && enabled ? c : kSetBorder, width: recommended && enabled ? 1.6 : 1),
          boxShadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 10, offset: Offset(0, 3))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? onTap : null,
            hoverColor: c.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: c, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: enabled ? kSetText : kSetMuted)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                        child: Text(tag, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
                      ),
                      if (recommended && enabled)
                        const Text('⭐ الأقرب', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: kSetGreen)),
                    ]),
                    const SizedBox(height: 4),
                    Text(blockedWhy ?? text, style: const TextStyle(fontSize: 12.3, height: 1.5, color: kSetMuted)),
                  ]),
                ),
                if (enabled) const Icon(Icons.chevron_left_rounded, color: Color(0xFFB8C2CF)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
