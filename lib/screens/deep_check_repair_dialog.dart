// lib/screens/deep_check_repair_dialog.dart
//
// 🩺 «معالجة» ملاحظة فاتورة من الفحص العميق (deep_check_repair.dart): تعرض الفاتورة وكل
// معاملاتها في سجل الديون ورصيد كل عميل، ثم يختار المدير — لا شيء يتغير بلا تأكيد صريح:
//   1) اعتمد سجل الديون: تُصحَّح الفاتورة (نقد/دين، المسدد) — لا يتغير أي دين.
//   2) اعتمد الفاتورة: يُضبط سجل الديون عليها — يتغير رصيد العميل (قبل/بعد ظاهران).
//   3) فتح الفاتورة: لتصحيحها يدوياً.
//   4) مُراجَعة: تبقى كما هي ولا تظهر ثانية ما دامت أرقامها لم تتغير.
// يعيد true إن تغيّر شيء (فتُعاد الفحص).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/auth_service.dart';
import '../services/database/business/deep_check_repair.dart';
import '../services/database_service.dart';
import 'create_invoice_screen.dart';

const _navy = Color(0xFF0F3460);
const _red = Color(0xFFB91C1C);
const _green = Color(0xFF047857);
const _muted = Color(0xFF64748B);

final _n = NumberFormat('#,##0.##', 'en');

Future<bool> showDeepCheckRepair(BuildContext context, int invoiceId) async {
  if (!AuthService().isAdmin) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المعالجة لمدير البرنامج فقط')));
    return false;
  }
  final db = await DatabaseService().database;
  final info = await DeepCheckRepair.load(db, invoiceId);
  if (!context.mounted) return false;
  if (info == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الفاتورة غير موجودة')));
    return false;
  }
  return await showDialog<bool>(context: context, builder: (_) => _RepairDialog(info)) ?? false;
}

class _RepairDialog extends StatefulWidget {
  const _RepairDialog(this.info);
  final InvoiceRepairInfo info;
  @override
  State<_RepairDialog> createState() => _RepairDialogState();
}

class _RepairDialogState extends State<_RepairDialog> {
  bool _busy = false;
  String? _err;

  InvoiceRepairInfo get i => widget.info;
  String get _user => AuthService().currentUser?.username ?? '';

  Future<bool> _confirm(String title, String body, {required String ok, Color color = _navy}) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body, style: const TextStyle(height: 1.7)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: color),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ok)),
          ],
        ),
      ) ??
      false;

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await job();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _err = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ledgerTruth() async {
    final ok = await _confirm(
      'اعتماد سجل الديون',
      'تتغير الفاتورة ${i.number} فقط:\n'
          '• نوعها: ${i.paymentType} ← ${i.newPaymentType}\n'
          '• المسدد عليها: ${_n.format(i.paid)} ← ${_n.format(i.newPaid)}\n\n'
          'لا يتغير أي دين ولا أي معاملة، ورصيد العميل يبقى ${_n.format(i.balances[i.customerId] ?? 0)}.\n'
          'القيد المحاسبي للفاتورة يتبعها عند «الترحيل» القادم.',
      ok: 'صحّح الفاتورة',
    );
    if (ok) await _run(() async => DeepCheckRepair.applyLedgerTruth(await DatabaseService().database, i.invoiceId, user: _user));
  }

  Future<void> _invoiceTruth() async {
    final lines = <String>[];
    for (final c in {...i.recorded.keys, if (i.customerId != null && i.customerId! > 0) i.customerId!}) {
      final cur = i.recorded[c] ?? 0;
      final target = c == i.customerId ? i.expected : 0.0;
      final bal = i.balances[c] ?? 0;
      final after = bal + (target - cur);
      if ((target - cur).abs() <= 0.01) continue;
      lines.add('• ${i.names[c] ?? '#$c'}: رصيده ${_n.format(bal)} ← ${_n.format(after)}'
          '${after < -0.01 ? '  ⚠️ يصبح له رصيد دائن' : ''}');
    }
    final ok = await _confirm(
      'اعتماد الفاتورة — يتغير الدين',
      'يُضبط سجل الديون على ما تقوله الفاتورة (${i.paymentType}، المتبقي ${_n.format(i.expected)}):\n'
          '${lines.join('\n')}\n\n'
          'لا تُحذف أي معاملة: يُضاف أو يُعدَّل صف تسوية واحد للفاتورة. '
          'إن كنت سجّلت سابقاً تسديداً يدوياً لتعويض هذا الخطأ فسيبقى — راجعه بعدها.',
      ok: 'غيّر سجل الديون',
      color: _red,
    );
    if (ok) await _run(() async => DeepCheckRepair.applyInvoiceTruth(await DatabaseService().database, i.invoiceId, user: _user));
  }

  Future<void> _ack() async {
    final ok = await _confirm(
      'مُراجَعة بلا تغيير',
      'تبقى الفاتورة وسجل الديون كما هما، ولا تظهر هذه الملاحظة في الفحص ما دامت أرقامها كما هي الآن. '
          'أي تغيير في الفاتورة أو معاملاتها يعيد إظهارها.',
      ok: 'مُراجَعة',
    );
    if (ok) await _run(() async => DeepCheckRepair.acknowledge(await DatabaseService().database, i, user: _user));
  }

  Future<void> _open() async {
    final inv = await DatabaseService().getInvoiceById(i.invoiceId);
    if (inv == null || !mounted) return;
    final nav = Navigator.of(context);
    nav.pop(false);
    await nav.push(MaterialPageRoute(
        builder: (_) => CreateInvoiceScreen(
              existingInvoice: inv,
              isViewOnly: inv.status == 'محفوظة' || !inv.isCreatedByMe,
            )));
  }

  Widget _kv(String k, String v, {Color? c}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(width: 170, child: Text(k, style: const TextStyle(color: _muted))),
          Expanded(child: Text(v, style: TextStyle(fontWeight: FontWeight.w700, color: c))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final block = i.ledgerTruthBlock;
    final invBlock = i.invoiceTruthBlock;
    final cid = i.customerId;
    return AlertDialog(
      title: Text('فاتورة ${i.number} — ${i.customerName}'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            _kv('النوع والحالة', '${i.paymentType} — ${i.deleted ? 'محذوفة' : i.status}'),
            _kv('الإجمالي / المسدد', '${_n.format(i.total)} / ${_n.format(i.paid)}'
                '${i.cashSettlements.abs() > 0.01 ? ' (تسويات نقدية ${_n.format(i.cashSettlements)})' : ''}'),
            _kv('حسب الفاتورة على العميل', _n.format(i.expected)),
            _kv('في سجل الديون لعميلها', _n.format(i.recordedCurrent),
                c: (i.expected - i.recordedCurrent).abs() > 0.01 ? _red : _green),
            if (i.recordedOthers.abs() > 0.01) _kv('على عملاء آخرين', _n.format(i.recordedOthers), c: _red),
            if (cid != null && i.balances.containsKey(cid)) _kv('رصيد العميل الآن', _n.format(i.balances[cid])),
            const Divider(height: 22),
            const Text('معاملاتها في سجل الديون', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            if (i.txs.isEmpty) const Text('لا شيء', style: TextStyle(color: _muted)),
            for (final t in i.txs)
              Text(
                '${t.date.length >= 16 ? t.date.substring(0, 16).replaceFirst('T', ' ') : t.date} — '
                '${_n.format(t.amount)} — ${t.type} — ${t.customerName}${t.description.isEmpty ? '' : ' — ${t.description}'}',
                style: const TextStyle(fontSize: 12, height: 1.6),
              ),
            const Divider(height: 22),
            const Text('أيهما الصحيح؟ أنت تعرف: هل دفع الزبون هذه الفاتورة عند البيع، أم بقيت ديناً عليه؟',
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.6)),
            if (block != null && !i.consistent)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('«اعتمد سجل الديون» غير ممكن: $block', style: const TextStyle(fontSize: 12, color: _muted)),
              ),
            if (invBlock != null && !i.consistent)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('«اعتمد الفاتورة» غير ممكن: $invBlock', style: const TextStyle(fontSize: 12, color: _muted)),
              ),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('هنا وقع خطأ: $_err', style: const TextStyle(color: _red)),
              ),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          ]),
        ),
      ),
      actionsOverflowButtonSpacing: 6,
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('إغلاق')),
        TextButton.icon(onPressed: _busy ? null : _ack, icon: const Icon(Icons.task_alt_rounded), label: const Text('مُراجَعة')),
        OutlinedButton.icon(onPressed: _busy ? null : _open, icon: const Icon(Icons.open_in_new_rounded), label: const Text('فتح الفاتورة')),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: _red),
          onPressed: _busy || invBlock != null ? null : _invoiceTruth,
          icon: const Icon(Icons.receipt_long_rounded),
          label: const Text('اعتمد الفاتورة'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _green),
          onPressed: _busy || block != null || i.consistent ? null : _ledgerTruth,
          icon: const Icon(Icons.account_balance_wallet_rounded),
          label: const Text('اعتمد سجل الديون'),
        ),
      ],
    );
  }
}
