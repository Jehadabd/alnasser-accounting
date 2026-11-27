// lib/screens/pos/pos_cart_layout_screen.dart
//
// 🧩 تصميم جدول سلة الكاشير (مثل «تخطيط شاشة إنشاء الفاتورة»): الأعمدة الظاهرة، عرض
// كل عمود، ارتفاع السطر، وعرض مساحة السلة — مع معاينة حيّة.
// (الإعدادات ← الفاتورة والطباعة ← أعمدة سلة الكاشير، أو من زر الأعمدة في رأس السلة)
// إعداد عرض فقط لهذا الجهاز — لا يغيّر أي بيانات.

import 'package:flutter/material.dart';

import '../../erp/erp_kit.dart' show ChoiceTile;
import '../../widgets/settings_kit.dart';
import 'pos_cart_layout.dart';

class PosCartLayoutScreen extends StatefulWidget {
  const PosCartLayoutScreen({super.key});

  @override
  State<PosCartLayoutScreen> createState() => _PosCartLayoutScreenState();
}

class _PosCartLayoutScreenState extends State<PosCartLayoutScreen> {
  late Map<String, double> _widths;
  late Set<String> _hidden;
  double _rowHeight = 44;
  double? _cartWidth; // null = الافتراضي حسب الشاشة
  bool _loading = true;

  static const _rowIcons = [Icons.density_small_rounded, Icons.density_medium_rounded, Icons.density_large_rounded];
  static const double _defaultCartPreview = 420;
  static const double _maxCartSetting = 1000;

  @override
  void initState() {
    super.initState();
    PosCartLayout.load().then((l) {
      if (!mounted) return;
      setState(() {
        _widths = {for (final k in PosCartLayout.keys) k: l.w(k)};
        _hidden = {...l.hidden};
        _rowHeight = l.rowHeight;
        _cartWidth = l.cartWidth;
        _loading = false;
      });
    });
  }

  PosCartLayout get _draft => PosCartLayout(widths: _widths, hidden: _hidden, rowHeight: _rowHeight, cartWidth: _cartWidth);

  Future<void> _save() async {
    await _draft.save();
    if (!mounted) return;
    setToast(context, 'حُفظت أعمدة السلة — تظهر في الكاشير فوراً');
    Navigator.pop(context, true);
  }

  void _reset() => setState(() {
        _widths = {...PosCartLayout.defaultWidths};
        _hidden = {...PosCartLayout.defaultHidden};
        _rowHeight = 44;
        _cartWidth = null;
      });

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'أعمدة سلة الكاشير',
      subtitle: 'الأعمدة الظاهرة وعرضها، ارتفاع السطر، وعرض مساحة السلة',
      icon: Icons.point_of_sale_rounded,
      maxWidth: 1000,
      loading: _loading,
      actions: [
        IconButton(
          tooltip: 'إظهار كل الأعمدة',
          onPressed: _loading ? null : () => setState(() => _hidden = {}),
          icon: const Icon(Icons.view_column_rounded),
        ),
        IconButton(
          tooltip: 'إرجاع التخطيط الافتراضي',
          onPressed: _loading ? null : _reset,
          icon: const Icon(Icons.restart_alt_rounded),
        ),
        const SizedBox(width: 6),
      ],
      bottom: _loading ? null : _bottomBar(),
      children: _loading
          ? null
          : [
              const SetBanner(
                'اختر الأعمدة الظاهرة في سلة الكاشير وعرض كل عمود. «المادة» تتّسع لتملأ الباقي، وإن زادت الأعمدة '
                'عن عرض السلة يظهر تمرير أفقي. المادة والسعر والكمية والإجمالي ضرورية ولا تُخفى. '
                'تستطيع أيضاً تغيير العرض مباشرة في الكاشير: اسحب حافة العمود في رأس السلة، أو الفاصل بين المواد والسلة.',
              ),
              const SizedBox(height: 14),
              _generalCard(),
              SetCard(
                title: 'معاينة حيّة',
                subtitle: 'هكذا ستظهر السلة',
                icon: Icons.preview_rounded,
                child: Padding(padding: const EdgeInsets.only(top: 12), child: _preview()),
              ),
              SetCard(
                title: 'الأعمدة',
                subtitle: 'فعّل العمود وحرّك المؤشر لتحديد عرضه',
                icon: Icons.view_column_rounded,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(children: [for (final k in PosCartLayout.keys) _columnTile(k)]),
              ),
            ],
    );
  }

  Widget _bottomBar() => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kSetBorder))),
        child: SafeArea(
          top: false,
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: kSetMuted),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('التغييرات تُطبَّق على السلة بعد الحفظ.', style: TextStyle(fontSize: 12.5, color: kSetMuted)),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 200,
                  child: SetPrimaryButton(label: 'حفظ', icon: Icons.save_rounded, onPressed: _save),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _generalCard() {
    final heights = PosCartLayout.rowHeights.entries.toList();
    final custom = _cartWidth != null;
    return SetCard(
      title: 'إعدادات عامة',
      icon: Icons.tune_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 12),
        const Text('ارتفاع السطر', style: TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth >= 540 ? (c.maxWidth - 20) / 3 : c.maxWidth;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (var i = 0; i < heights.length; i++)
              ChoiceTile(
                width: w,
                dense: true,
                icon: _rowIcons[i.clamp(0, _rowIcons.length - 1)],
                title: heights[i].value,
                subtitle: '${heights[i].key.round()} بكسل',
                selected: _rowHeight == heights[i].key,
                onTap: () => setState(() => _rowHeight = heights[i].key),
              ),
          ]);
        }),
        const Divider(height: 26),
        Row(children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('عرض مساحة السلة', style: TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
              Text('أكبر = أعمدة أكثر في السلة ومواد أقل في كل صف. يُحدّ تلقائياً حسب عرض الشاشة.',
                  style: TextStyle(fontSize: 12, color: kSetMuted)),
            ]),
          ),
          Switch(
            value: custom,
            onChanged: (v) => setState(() => _cartWidth = v ? (_cartWidth ?? _defaultCartPreview) : null),
          ),
        ]),
        if (custom)
          Row(children: [
            Expanded(
              child: Slider(
                value: _cartWidth!.clamp(PosCartLayout.minCartWidth, _maxCartSetting).toDouble(),
                min: PosCartLayout.minCartWidth,
                max: _maxCartSetting,
                divisions: ((_maxCartSetting - PosCartLayout.minCartWidth) / 10).round(),
                label: '${_cartWidth!.round()}',
                onChanged: (v) => setState(() => _cartWidth = v.roundToDouble()),
              ),
            ),
            _pxBadge(_cartWidth!, true),
          ])
        else
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('الافتراضي: نحو ثلث الشاشة', style: TextStyle(fontSize: 12, color: kSetMuted)),
          ),
      ]),
    );
  }

  Widget _pxBadge(double v, bool on) => Container(
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? const Color(0xFFEFF4FF) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('${v.round()} px',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: on ? kSetNavy : const Color(0xFF94A3B8))),
      );

  Widget _preview() {
    final d = _draft;
    final shown = d.visibleKeys;
    const sample = [
      {'index': '1', 'name': 'كوب ماء 250 مل', 'unit': 'كرتون', 'price': '6,000', 'qty': '−  2  +', 'total': '12,000', 'stock': '18', 'barcode': '6281001234567'},
      {'index': '2', 'name': 'مصباح ليد 12 واط', 'unit': 'قطعة', 'price': '1,500', 'qty': '−  10  +', 'total': '15,000', 'stock': '4', 'barcode': '6923456789012'},
      {'index': '3', 'name': 'بلك ابيض 16 امبير', 'unit': 'قطعة', 'price': '750', 'qty': '−  5  +', 'total': '3,750', 'stock': '120', 'barcode': '—'},
    ];
    return LayoutBuilder(builder: (context, box) {
      final cartW = (_cartWidth ?? _defaultCartPreview).clamp(PosCartLayout.minCartWidth, box.maxWidth).toDouble();
      const trail = 34.0;
      final widths = d.resolve(cartW - trail - 2);
      final tableW = widths.values.fold<double>(0, (a, b) => a + b) + trail + 2;
      Widget row(Map<String, String>? cells, {bool zebra = false}) {
        final header = cells == null;
        return Container(
          height: header ? 34 : _rowHeight,
          color: header ? const Color(0xFFF1F5F9) : (zebra ? const Color(0xFFF8FAFC) : Colors.white),
          child: Row(children: [
            for (final k in shown)
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: widths[k],
                alignment: k == 'name' ? AlignmentDirectional.centerStart : Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: const BoxDecoration(
                  border: BorderDirectional(end: BorderSide(color: Color(0xFFE6EAF0)), bottom: BorderSide(color: Color(0xFFEDF0F4))),
                ),
                child: Text(
                  header ? PosCartLayout.headers[k]! : (cells?[k] ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: header || k == 'total' ? FontWeight.w800 : FontWeight.w500,
                    color: header ? const Color(0xFF475569) : (k == 'total' ? kSetNavy : kSetText),
                  ),
                ),
              ),
            SizedBox(
              width: trail,
              child: Icon(header ? Icons.view_column_outlined : Icons.close_rounded, size: 16, color: const Color(0xFF94A3B8)),
            ),
          ]),
        );
      }

      final table = Container(
        width: tableW,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Column(children: [
          row(null),
          for (var i = 0; i < sample.length; i++) row(sample[i], zebra: i.isOdd),
        ]),
      );
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('عرض السلة في المعاينة: ${cartW.round()} px${tableW > cartW + 1 ? ' — الأعمدة أعرض منها: تمرير أفقي' : ''}',
            style: const TextStyle(fontSize: 12, color: kSetMuted)),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(
            width: cartW,
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: table),
          ),
        ),
      ]);
    });
  }

  Widget _columnTile(String k) {
    final locked = PosCartLayout.required.contains(k);
    final visible = locked || !_hidden.contains(k);
    final minW = PosCartLayout.minWidths[k] ?? 30;
    final width = (_widths[k] ?? PosCartLayout.defaultWidths[k] ?? 80).clamp(minW, PosCartLayout.maxWidth).toDouble();
    final toggle = locked
        ? const Tooltip(
            message: 'عمود ضروري للبيع',
            child: SizedBox(width: 44, child: Icon(Icons.lock_rounded, size: 18, color: Color(0xFF94A3B8))),
          )
        : SizedBox(
            width: 44,
            child: Checkbox(
              value: visible,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _hidden.remove(k);
                } else {
                  _hidden.add(k);
                }
              }),
            ),
          );
    final label = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(PosCartLayout.labels[k]!,
          style: TextStyle(fontWeight: FontWeight.w700, color: visible ? kSetText : const Color(0xFF94A3B8))),
      if (k == 'name')
        const Text('أقل عرض له؛ يتّسع ليملأ باقي السلة', style: TextStyle(fontSize: 11, color: kSetMuted)),
    ]);
    final slider = Row(children: [
      Expanded(
        child: Slider(
          value: width,
          min: minW,
          max: PosCartLayout.maxWidth,
          divisions: ((PosCartLayout.maxWidth - minW) / 2).round(),
          label: '${width.round()}',
          onChanged: visible ? (v) => setState(() => _widths[k] = v.roundToDouble()) : null,
        ),
      ),
      _pxBadge(width, visible),
    ]);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: visible ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kSetBorder),
      ),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 620) {
          return Row(children: [toggle, SizedBox(width: 200, child: label), Expanded(child: slider)]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [toggle, Expanded(child: label)]),
          slider,
        ]);
      }),
    );
  }
}
