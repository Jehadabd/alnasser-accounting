// lib/widgets/edit_transaction_dialog.dart
//
// ✏️ تعديل معاملة يدوية في سجل الديون — بنفس لغة تصميم البرنامج:
//   • نوعها بزرين كبيرين: «إضافة دين» (أحمر) أو «تسديد» (أخضر).
//   • المبلغ كبير بفواصل الآلاف، والرصيد قبل/بعد يتحدث فوراً مع الفرق.
//   • الملاحظة والتاريخ (يبقى وقت المعاملة الأصلي كما هو).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../models/transaction.dart';
import 'formatters.dart';

const _navy = Color(0xFF0F3460);
const _ink = Color(0xFF1E293B);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE6EBF2);
const _bg = Color(0xFFF6F8FB);
const _debt = Color(0xFFB42318);
const _pay = Color(0xFF067647);

String _money(num v) => NumberFormat('#,##0.##', 'en_US').format(v);

class EditTxResult {
  const EditTxResult({required this.amount, required this.note, required this.date});

  /// موجب = دين، سالب = تسديد
  final double amount;
  final String? note;
  final DateTime date;
}

Future<EditTxResult?> showEditTransactionDialog(BuildContext context, DebtTransaction tx) =>
    showDialog<EditTxResult>(context: context, builder: (_) => _EditTxDialog(tx: tx));

class _EditTxDialog extends StatefulWidget {
  const _EditTxDialog({required this.tx});
  final DebtTransaction tx;

  @override
  State<_EditTxDialog> createState() => _EditTxDialogState();
}

class _EditTxDialogState extends State<_EditTxDialog> {
  late bool _isDebt;
  late DateTime _date;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  String? _err;

  DebtTransaction get tx => widget.tx;

  @override
  void initState() {
    super.initState();
    _isDebt = tx.amountChanged >= 0;
    _date = tx.transactionDate;
    _amount = TextEditingController(text: NumberFormat('#,##0.##', 'en_US').format(tx.amountChanged.abs()));
    _note = TextEditingController(text: tx.transactionNote ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _entered => double.tryParse(_amount.text.trim().replaceAll(',', ''));
  double get _signed => (_isDebt ? 1.0 : -1.0) * (_entered ?? tx.amountChanged.abs());
  double get _delta => _signed - tx.amountChanged;
  double get _after => (tx.newBalanceAfterTransaction ?? 0.0) + _delta;
  double get _before => tx.balanceBeforeTransaction ?? ((tx.newBalanceAfterTransaction ?? 0.0) - tx.amountChanged);

  bool get _changed =>
      _delta.abs() > 0.0001 ||
      (_note.text.trim()) != (tx.transactionNote ?? '').trim() ||
      !DateUtils.isSameDay(_date, tx.transactionDate);

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    // نحتفظ بوقت المعاملة الأصلي (الساعة والدقيقة) حتى لا يتغير ترتيبها في اليوم
    setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute, _date.second));
  }

  void _save() {
    final v = _entered;
    if (v == null || v <= 0) {
      setState(() => _err = 'اكتب مبلغاً أكبر من صفر');
      return;
    }
    final n = _note.text.trim();
    Navigator.pop(context, EditTxResult(amount: _isDebt ? v : -v, note: n.isEmpty ? null : n, date: _date));
  }

  @override
  Widget build(BuildContext context) {
    final accent = _isDebt ? _debt : _pay;
    return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(accent),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _label('نوع المعاملة'),
                  Row(children: [
                    Expanded(
                      child: _TypeCard(
                        title: 'إضافة دين',
                        subtitle: 'يزيد ما على العميل',
                        icon: Icons.add_circle_outline_rounded,
                        color: _debt,
                        selected: _isDebt,
                        onTap: () => setState(() => _isDebt = true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TypeCard(
                        title: 'تسديد',
                        subtitle: 'ينقص ما على العميل',
                        icon: Icons.price_check_rounded,
                        color: _pay,
                        selected: !_isDebt,
                        onTap: () => setState(() => _isDebt = false),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _label('المبلغ'),
                  TextField(
                    controller: _amount,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: accent, height: 1.1),
                    decoration: _dec(accent).copyWith(
                      suffixText: 'دينار',
                      errorText: _err,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                    ),
                    onChanged: (_) => setState(() => _err = null),
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 14),
                  _balancePreview(accent),
                  const SizedBox(height: 16),
                  _label('ملاحظة'),
                  TextField(
                    controller: _note,
                    minLines: 1,
                    maxLines: 3,
                    decoration: _dec(_navy).copyWith(
                      hintText: 'مثال: تسديد نقدي بيد المحاسب',
                      prefixIcon: const Icon(Icons.notes_rounded, size: 20),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  _label('التاريخ'),
                  Material(
                    color: _bg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _line)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _pickDate,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        child: Row(children: [
                          const Icon(Icons.event_rounded, size: 20, color: _navy),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(DateFormat('yyyy/MM/dd  •  HH:mm').format(_date),
                                style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
                          ),
                          const Text('تغيير', style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Row(children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _changed ? _save : null,
                  icon: const Icon(Icons.save_rounded, size: 20),
                  label: const Text('حفظ التعديل', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
          ]),
        ),
    );
  }

  Widget _header(Color accent) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 8, 16),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.06),
          border: const Border(bottom: BorderSide(color: _line)),
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.edit_note_rounded, color: accent, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('تعديل المعاملة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 2),
              Text(
                'الأصل: ${tx.amountChanged >= 0 ? 'دين' : 'تسديد'} ${_money(tx.amountChanged.abs())} • '
                '${DateFormat('yyyy/MM/dd').format(tx.transactionDate)}',
                style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.4),
              ),
            ]),
          ),
          IconButton(
            tooltip: 'إغلاق',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: _muted),
          ),
        ]),
      );

  Widget _balancePreview(Color accent) {
    final delta = _delta;
    final up = delta > 0;
    Widget col(String label, double v, {bool strong = false}) => Expanded(
          child: Column(children: [
            Text(label, style: const TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(_money(v),
                  style: TextStyle(
                      fontSize: strong ? 19 : 16,
                      fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                      color: strong ? _ink : _muted)),
            ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
      child: Column(children: [
        Row(children: [
          col('الرصيد قبلها', _before),
          const Icon(Icons.arrow_back_rounded, color: _muted, size: 20),
          col('الرصيد بعد الحفظ', _after, strong: true),
        ]),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: delta.abs() < 0.0001
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (up ? _debt : _pay).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                          size: 16, color: up ? _debt : _pay),
                      const SizedBox(width: 6),
                      Text(
                        '${up ? 'يزيد' : 'ينقص'} رصيد العميل ${_money(delta.abs())} عمّا هو الآن',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: up ? _debt : _pay),
                      ),
                    ]),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, right: 2, left: 2),
        child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _ink)),
      );

  InputDecoration _dec(Color focus) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: _bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: focus, width: 1.6)),
      );
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: title,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? color : _line, width: selected ? 1.6 : 1),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Icon(icon, color: selected ? color : _muted, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title,
                          style: TextStyle(fontWeight: FontWeight.w800, color: selected ? color : _ink, fontSize: 14.5)),
                      Text(subtitle, style: const TextStyle(fontSize: 11.5, color: _muted)),
                    ]),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: selected ? 1 : 0,
                    child: Icon(Icons.check_circle_rounded, color: color, size: 20),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
