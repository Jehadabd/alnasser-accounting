// lib/accounting/screens/orphan_debts_dialog.dart
//
// 👻 «ديون عملاء ليسوا في سجل الديون» — عرض فقط:
// صفوف عملاء حُذفت وبقيت معاملاتهم، فيحسبها الدفتر المحاسبي (ذمم العملاء) ولا يعرضها
// سجل الديون، فيظهر فرق في «سلامة الدفتر». هنا تُعرض بالاسم والمبلغ والتاريخ ليقرّر
// صاحب المحل ما يفعل بها. لا شيء يتغيّر من هذه النافذة.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../widgets/app_dialog_shell.dart';
import '../accounting_reports.dart';

const _orange = Color(0xFFC2410C);
const _text = Color(0xFF1E293B);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE6EBF2);

/// يعرض النافذة (تجلب البيانات بنفسها).
Future<void> showOrphanDebtsDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _OrphanDebtsDialog());

/// هل هذا نص مشكلة «عملاء حُذفوا من سجل الديون»؟
bool isOrphanDebtsProblem(String p) => p.contains('حُذفوا من سجل الديون');

class _OrphanDebtsDialog extends StatefulWidget {
  const _OrphanDebtsDialog();

  @override
  State<_OrphanDebtsDialog> createState() => _OrphanDebtsDialogState();
}

class _OrphanDebtsDialogState extends State<_OrphanDebtsDialog> {
  late final Future<List<OrphanCustomerDebt>> _f = AccountingReports().orphanCustomerDebts();
  static final _n = NumberFormat('#,##0', 'en');
  static final _d = DateFormat('yyyy/MM/dd', 'en');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OrphanCustomerDebt>>(
      future: _f,
      builder: (_, s) {
        final list = s.data;
        final total = list?.fold<double>(0, (a, b) => a + b.total) ?? 0;
        return AppDialogShell(
          icon: Icons.person_off_rounded,
          color: _orange,
          title: 'ديون عملاء ليسوا في سجل الديون',
          subtitle: list == null
              ? 'جارٍ الجمع...'
              : '${list.length} عميلاً • ${_n.format(total)} دينار — عرض فقط، لا يتغيّر شيء من هنا',
          onClose: () => Navigator.pop(context),
          maxWidth: 680,
          body: s.hasError
              ? Padding(padding: const EdgeInsets.all(20), child: Text('تعذّر الجمع: ${s.error}'))
              : list == null
                  ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                  : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(12)),
                        child: const Text(
                          'هؤلاء عملاء حُذفت بطاقاتهم من سجل الديون لكن معاملاتهم (فواتير آجلة، تسديدات) بقيت. '
                          'الدفتر المحاسبي يحسبها ضمن «ذمم العملاء» والسجل لا يعرضها، فيظهر الفرق. '
                          'البرنامج لا يغيّر أي دين تلقائياً — القرار لك.',
                          style: TextStyle(fontSize: 12.8, height: 1.6, color: Color(0xFF9A3412)),
                        ),
                      ),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (_, i) => _row(list[i]),
                        ),
                      ),
                    ]),
          actions: [
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _orange, minimumSize: const Size(110, 44)),
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        );
      },
    );
  }

  Widget _row(OrphanCustomerDebt o) {
    final name = (o.name == null || o.name!.isEmpty) ? 'بلا اسم معروف' : o.name!;
    final dates = [
      if (o.first != null) _d.format(o.first!),
      if (o.last != null && o.last != o.first) _d.format(o.last!),
    ].join(' ← ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w800, color: _text)),
            Text('رقم العميل ${o.customerId ?? '—'} • ${o.count} معاملة${dates.isEmpty ? '' : ' • $dates'}',
                style: const TextStyle(fontSize: 12, color: _muted)),
          ]),
        ),
        Text(_n.format(o.total),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14.5,
              color: o.total > 0 ? _orange : (o.total < 0 ? const Color(0xFF047857) : _muted),
            )),
      ]),
    );
  }
}
