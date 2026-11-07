// lib/erp/inventory/margin_review.dart
//
// 📉 مراجعة «مواد نزل ربحها»: بطاقة لكل مادة (الكلفة قبل/بعد، كل مستوى سعر: الآن ←
// المقترح، ونسبة الربح)، اختيار ما يُطبَّق، وزر تطبيق واحد (دفعة قابلة للتراجع من
// «أدوات الأسعار ← سجل الدفعات»). لا يتغير شيء بلا ضغطة.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_dialog_shell.dart';
import 'margin_alert.dart';
import 'price_tools.dart';

const _red = Color(0xFFB91C1C);
const _orange = Color(0xFFC2410C);
const _green = Color(0xFF047857);
const _text = Color(0xFF1E293B);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE6EBF2);
final _n = NumberFormat('#,##0', 'en');

/// نافذة بعد حفظ فاتورة الشراء.
Future<void> showMarginDropDialog(BuildContext context, List<MarginRow> rows) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppDialogShell(
        icon: Icons.trending_down_rounded,
        color: _orange,
        title: 'مواد نزل ربحها',
        subtitle: 'ارتفعت كلفتها في هذه الفاتورة وسعر بيعها كما هو — المقترح يعيد ربح كل سعر إلى نسبته السابقة',
        onClose: () => Navigator.pop(ctx),
        maxWidth: 720,
        body: MarginReview(rows: rows, onApplied: (_) => Navigator.pop(ctx), laterLabel: 'لاحقاً', onLater: () => Navigator.pop(ctx)),
      ),
    );

class MarginReview extends StatefulWidget {
  const MarginReview({super.key, required this.rows, this.onApplied, this.onLater, this.laterLabel});
  final List<MarginRow> rows;

  /// بعد التطبيق (رقم الدفعة).
  final void Function(int batch)? onApplied;
  final VoidCallback? onLater;
  final String? laterLabel;

  @override
  State<MarginReview> createState() => _MarginReviewState();
}

class _MarginReviewState extends State<MarginReview> {
  late final Set<int> _sel = {for (final r in widget.rows) r.product.id!};
  bool _busy = false;

  bool get _canEdit =>
      AuthService().hasPermission(AppPermissions.editProducts) && AuthService().hasPermission(AppPermissions.priceTools);

  @override
  void didUpdateWidget(covariant MarginReview old) {
    super.didUpdateWidget(old);
    if (old.rows != widget.rows) {
      _sel
        ..clear()
        ..addAll(widget.rows.map((r) => r.product.id!));
    }
  }

  Future<void> _apply() async {
    final chosen = widget.rows.where((r) => _sel.contains(r.product.id)).toList();
    final changes = MarginAlert.changesFor(chosen);
    if (changes.isEmpty) return;
    setState(() => _busy = true);
    try {
      final batch = await PriceTools().apply(changes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('طُبّقت ${changes.length} أسعار لـ ${chosen.length} مادة — دفعة #$batch (يمكن التراجع من سجل الدفعات)'),
        backgroundColor: _green,
      ));
      widget.onApplied?.call(batch);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر التطبيق: $e'), backgroundColor: _red));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final all = rows.isNotEmpty && _sel.length == rows.length;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(children: [
          Checkbox(
            value: all ? true : (_sel.isEmpty ? false : null),
            tristate: true,
            onChanged: (_) => setState(() {
              if (all) {
                _sel.clear();
              } else {
                _sel.addAll(rows.map((r) => r.product.id!));
              }
            }),
          ),
          Text('اختر الكل (${rows.length})', style: const TextStyle(fontWeight: FontWeight.w700, color: _text)),
          const Spacer(),
          Text('${_sel.length} مختارة', style: const TextStyle(color: _muted, fontSize: 12.5)),
        ]),
      ),
      Flexible(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _card(rows[i]),
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
        child: Row(children: [
          if (!_canEdit)
            const Expanded(
              child: Text('لا صلاحية لتعديل الأسعار — اطلبها من المدير.',
                  style: TextStyle(color: _red, fontSize: 12.5)),
            )
          else
            const Expanded(
              child: Text('لا يتغير أي سعر إلا بالضغط على «تطبيق».', style: TextStyle(color: _muted, fontSize: 12)),
            ),
          if (widget.onLater != null) ...[
            TextButton(onPressed: _busy ? null : widget.onLater, child: Text(widget.laterLabel ?? 'لاحقاً')),
            const SizedBox(width: 8),
          ],
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _orange, minimumSize: const Size(150, 44)),
            onPressed: !_canEdit || _busy || _sel.isEmpty ? null : _apply,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded),
            label: Text('تطبيق على ${_sel.length}'),
          ),
        ]),
      ),
    ]);
  }

  Widget _card(MarginRow r) {
    final id = r.product.id!;
    final on = _sel.contains(id);
    final rose = r.newCost > r.oldCost;
    final m1 = r.marginNow(1);
    final mColor = m1 < 0 ? _red : (m1 < 10 ? _orange : _text);
    return Material(
      color: on ? const Color(0xFFFFF7ED) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: on ? _orange.withValues(alpha: 0.45) : _line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => on ? _sel.remove(id) : _sel.add(id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 12, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(value: on, onChanged: (_) => setState(() => on ? _sel.remove(id) : _sel.add(id))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(r.product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _text)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: mColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text(m1 < 0 ? 'خسارة ${(-m1).toStringAsFixed(1)}%' : 'ربح ${m1.toStringAsFixed(1)}%',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: mColor)),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(
                  rose
                      ? 'الكلفة: ${_n.format(r.oldCost)} ← ${_n.format(r.newCost)} (+${((r.newCost / r.oldCost - 1) * 100).toStringAsFixed(1)}%)'
                      : 'الكلفة: ${_n.format(r.newCost)}',
                  style: const TextStyle(fontSize: 12.5, color: _muted),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final e in r.current.entries)
                    _pricePill(priceFieldNames[e.key - 1], e.value, r.suggested[e.key]),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _pricePill(String label, double now, double? sug) {
    final changes = sug != null && (sug - now).abs() > 0.004;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: changes ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: changes ? _orange.withValues(alpha: 0.35) : _line),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label: ', style: const TextStyle(color: _muted)),
          TextSpan(text: _n.format(now), style: const TextStyle(fontWeight: FontWeight.w700, color: _text)),
          if (changes) ...[
            const TextSpan(text: '  ←  ', style: TextStyle(color: _muted)),
            TextSpan(text: _n.format(sug), style: const TextStyle(fontWeight: FontWeight.w900, color: _orange)),
          ],
        ]),
        style: const TextStyle(fontSize: 12.5),
        textDirection: TextDirection.rtl,
      ),
    );
  }
}
