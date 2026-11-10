// lib/wa_messages/wa_customer_picker.dart
//
// 👥 نافذة اختيار العملاء لرسائل واتساب: بحث، فلاتر التأخر، بطاقة لكل عميل (دينه ومنذ متى
// بلا تسديد)، وشريط سفلي بعدد المختارين ومجموع ديونهم. ألوان settings_kit نفسها.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../owner/wa_auto/wa_auto_reminder.dart';
import '../widgets/settings_kit.dart';

final _n = NumberFormat('#,##0', 'en');
const _amber = Color(0xFFB45309);

class WaCustomerPickerDialog extends StatefulWidget {
  const WaCustomerPickerDialog({super.key, required this.all, required this.initial, required this.title});
  final List<WaTarget> all;
  final Set<int> initial;
  final String title;

  @override
  State<WaCustomerPickerDialog> createState() => _WaCustomerPickerDialogState();
}

class _WaCustomerPickerDialogState extends State<WaCustomerPickerDialog> {
  late final Set<int> _sel = {...widget.initial};
  String _q = '';
  int _late = 0; // 0 = الكل، وإلا: بلا تسديد N شهراً فأكثر

  static String _lateLabel(int m) =>
      m == 0 ? 'الكل' : 'بلا تسديد $m ${m == 1 ? 'شهر' : (m == 2 ? 'شهرين' : 'أشهر')}+';

  List<WaTarget> get _shown {
    final q = _q.trim();
    return [
      for (final t in widget.all)
        if ((q.isEmpty || t.name.contains(q) || t.phone.contains(q)) && (_late == 0 || (t.lateMonths ?? -1) >= _late))
          t,
    ];
  }

  void _toggle(int id) => setState(() => _sel.contains(id) ? _sel.remove(id) : _sel.add(id));

  @override
  Widget build(BuildContext context) {
    final list = _shown;
    final size = MediaQuery.sizeOf(context);
    final chosenDebt = widget.all.where((t) => _sel.contains(t.id)).fold<double>(0, (s, t) => s + t.debt);
    final allShownSelected = list.isNotEmpty && list.every((t) => _sel.contains(t.id));
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      backgroundColor: kSetBg,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 620, maxHeight: size.height * 0.9),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _search(),
              const SizedBox(height: 10),
              _filters(),
              const SizedBox(height: 8),
              Row(children: [
                Text('${list.length} ظاهر', style: const TextStyle(fontSize: 12.5, color: kSetMuted)),
                const Spacer(),
                TextButton.icon(
                  onPressed: list.isEmpty
                      ? null
                      : () => setState(() => allShownSelected
                          ? _sel.removeAll(list.map((t) => t.id))
                          : _sel.addAll(list.map((t) => t.id))),
                  icon: Icon(allShownSelected ? Icons.remove_done_rounded : Icons.done_all_rounded, size: 18),
                  label: Text(allShownSelected ? 'إلغاء تحديد الظاهرين' : 'تحديد الظاهرين'),
                ),
                if (_sel.isNotEmpty)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: kSetRed),
                    onPressed: () => setState(_sel.clear),
                    child: const Text('إلغاء الكل'),
                  ),
              ]),
            ]),
          ),
          Flexible(child: _list(list)),
          _bottomBar(chosenDebt),
        ]),
      ),
    );
  }

  Widget _header() => Container(
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
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.groups_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(widget.title,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Container(
              key: ValueKey(_sel.length),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Text('${_sel.length} مختار',
                  style: const TextStyle(color: kSetNavy, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
          ),
          IconButton(
            tooltip: 'إغلاق',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ]),
      );

  Widget _search() => TextField(
        autofocus: true,
        onChanged: (v) => setState(() => _q = v),
        decoration: InputDecoration(
          hintText: 'بحث بالاسم أو الرقم',
          prefixIcon: const Icon(Icons.search_rounded, color: kSetMuted),
          suffixIcon: _q.isEmpty ? null : const Icon(Icons.manage_search_rounded, color: kSetNavy),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: kSetBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: kSetNavy, width: 1.6),
          ),
        ),
      );

  Widget _filters() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final m in const [0, 1, 2, 3, 6])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: _FilterPill(
                label: _lateLabel(m),
                selected: _late == m,
                color: m == 0 ? kSetNavy : (m >= 3 ? kSetRed : _amber),
                onTap: () => setState(() => _late = m),
              ),
            ),
        ]),
      );

  Widget _list(List<WaTarget> list) {
    if (widget.all.isEmpty) {
      return const _Empty(icon: Icons.phone_disabled_rounded, text: 'لا يوجد عميل له رقم هاتف صالح');
    }
    if (list.isEmpty) return const _Empty(icon: Icons.search_off_rounded, text: 'لا أحد يطابق البحث أو الفلتر');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final t = list[i];
        return _CustomerTile(t: t, selected: _sel.contains(t.id), onTap: () => _toggle(t.id));
      },
    );
  }

  Widget _bottomBar(double chosenDebt) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: kSetBorder)),
          boxShadow: [BoxShadow(color: Color(0x0F0F172A), blurRadius: 12, offset: Offset(0, -3))],
        ),
        child: Row(children: [
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_sel.length} عميل', style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
              Text('مجموع ديونهم ${_n.format(chosenDebt.round())} دينار',
                  style: const TextStyle(fontSize: 12, color: kSetMuted)),
            ]),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
          const SizedBox(width: 6),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: kSetGreen,
              minimumSize: const Size(0, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.pop(context, _sel),
            icon: const Icon(Icons.check_rounded),
            label: const Text('حفظ الاختيار'),
          ),
        ]),
      );
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.selected, required this.color, required this.onTap});
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? color : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? color : kSetBorder),
                boxShadow: selected
                    ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))]
                    : null,
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : kSetText)),
            ),
          ),
        ),
      );
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.t, required this.selected, required this.onTap});
  final WaTarget t;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final late = t.lateMonths ?? 0;
    final lateColor = late >= 3 ? kSetRed : (late >= 1 ? _amber : kSetGreen);
    final name = t.name.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: selected,
        label: name,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected ? Color.alphaBlend(kSetGreen.withValues(alpha: 0.06), Colors.white) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: selected ? kSetGreen : kSetBorder, width: selected ? 1.6 : 1),
                boxShadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: 21,
                  backgroundColor: lateColor.withValues(alpha: 0.12),
                  child: Text(name.isEmpty ? '؟' : name.characters.first,
                      style: TextStyle(color: lateColor, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kSetText)),
                    const SizedBox(height: 2),
                    Text(t.phone,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 12, color: kSetMuted)),
                    if (late > 0) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: lateColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                        child: Text('بلا تسديد منذ $late ${late == 1 ? 'شهر' : (late == 2 ? 'شهرين' : 'أشهر')}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: lateColor)),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(t.debt > 0 ? _n.format(t.debt.round()) : 'لا دين',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 14.5, color: t.debt > 0 ? kSetRed : kSetGreen)),
                  if (t.debt > 0) const Text('دينار', style: TextStyle(fontSize: 11, color: kSetMuted)),
                ]),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? kSetGreen : Colors.white,
                    border: Border.all(color: selected ? kSetGreen : const Color(0xFFCBD5E1), width: 2),
                  ),
                  child: AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
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

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: const Color(0xFFCBD5E1)),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: kSetMuted)),
        ]),
      );
}
