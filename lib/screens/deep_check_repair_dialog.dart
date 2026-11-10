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
import '../widgets/settings_kit.dart';
import 'create_invoice_screen.dart';
import 'deep_check/repair_parts.dart';

const _navy = Color(0xFF0F3460);
const _red = Color(0xFFB91C1C);

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

  Widget _section(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Row(children: [
          Icon(icon, size: 18, color: kSetNavy),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kSetText)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final block = i.ledgerTruthBlock;
    final invBlock = i.invoiceTruthBlock;
    final size = MediaQuery.sizeOf(context);
    // الأقرب: سجل الديون حين يمكن (لا يتغير أي دين)، وإلا الفاتورة
    final preferLedger = block == null && !i.consistent;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 680, maxHeight: size.height * 0.88),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          RepairHeader(i, onClose: _busy ? null : () => Navigator.pop(context, false)),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _busy ? const LinearProgressIndicator(minHeight: 3) : const SizedBox.shrink(),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                RepairCompare(i),
                _section('معاملاتها في سجل الديون', Icons.timeline_rounded),
                RepairTimeline(i.txs),
                if (!i.consistent) ...[
                  _section('أيهما الصحيح؟', Icons.help_outline_rounded),
                  const Text(
                    'أنت تعرف: هل دفع الزبون هذه الفاتورة عند البيع، أم بقيت ديناً عليه وسدّدها لاحقاً؟',
                    style: TextStyle(fontSize: 13, height: 1.6, color: Color(0xFF334155)),
                  ),
                  const SizedBox(height: 10),
                  RepairChoice(
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'اعتمد سجل الديون',
                    tag: 'لا يتغير أي دين',
                    color: kSetGreen,
                    recommended: preferLedger,
                    text: 'تُصحَّح الفاتورة فقط: ${i.paymentType} ← ${i.newPaymentType}، '
                        'المسدد ${repairNum.format(i.paid)} ← ${repairNum.format(i.newPaid)}. رصيد العميل يبقى كما هو.',
                    blockedWhy: block == null ? null : 'غير ممكن: $block',
                    onTap: _busy ? null : _ledgerTruth,
                  ),
                  RepairChoice(
                    icon: Icons.receipt_long_rounded,
                    title: 'اعتمد الفاتورة',
                    tag: 'يتغير الدين',
                    color: kSetRed,
                    recommended: !preferLedger,
                    text: 'يُضبط سجل الديون على ما تقوله الفاتورة (المتبقي ${repairNum.format(i.expected)}). '
                        'ترى رصيد كل عميل قبل وبعد قبل التأكيد.',
                    blockedWhy: invBlock == null ? null : 'غير ممكن: $invBlock',
                    onTap: _busy ? null : _invoiceTruth,
                  ),
                ],
                RepairChoice(
                  icon: Icons.open_in_new_rounded,
                  title: 'فتح الفاتورة',
                  tag: 'تصحيح يدوي',
                  color: kSetNavy,
                  text: 'تفتح الفاتورة لتصحيحها بنفسك (مثلاً اختيار العميل). الحفظ يضبط سجل الديون تلقائياً.',
                  onTap: _busy ? null : _open,
                ),
                RepairChoice(
                  icon: Icons.task_alt_rounded,
                  title: 'مُراجَعة — أبقها كما هي',
                  tag: 'بلا تغيير',
                  color: kSetMuted,
                  text: 'لا يتغير شيء، ولا تظهر في الفحص ما دامت أرقامها كما هي. أي تغيير فيها يعيد إظهارها.',
                  onTap: _busy ? null : _ack,
                ),
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SetBanner('هنا وقع خطأ: $_err', kind: SetBannerKind.error),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
