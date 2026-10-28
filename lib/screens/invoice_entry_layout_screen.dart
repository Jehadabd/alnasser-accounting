// lib/screens/invoice_entry_layout_screen.dart
//
// 🧩 تصميم جدول شاشة «إنشاء فاتورة» على طريقة الإداري: أي الأعمدة تظهر، عرض كل
// عمود بالبكسل، ارتفاع السطر، وإظهار/إخفاء شريط الإدخال — مع معاينة حيّة.
// 🧭 ومسار زر Enter: الخانات التي يقف عندها المؤشر في السطر وترتيبها.
// (الإعدادات ← الفاتورة والطباعة ← أعمدة شاشة إنشاء الفاتورة)

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../erp/erp_kit.dart' show ChoiceTile;
import '../models/invoice_entry_layout.dart';
import '../widgets/settings_kit.dart';

/// 🧩 مكان المجاميع والدفع وزر الحفظ في شاشة «إنشاء فاتورة»:
/// true = لوحة جانبية، false = شريط سفلي. يُحفظ على هذا الجهاز، وتتبعه كل شاشات
/// الفاتورة المفتوحة فوراً (بلا حاجة لإغلاقها وفتحها).
class InvoiceSidePanelPref {
  InvoiceSidePanelPref._();
  static const String key = 'invoice_side_panel_open';
  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(true);
  static bool _loaded = false;

  static Future<bool> load() async {
    if (!_loaded) {
      try {
        final v = (await SharedPreferences.getInstance()).getBool(key);
        if (v != null) notifier.value = v;
      } catch (_) {}
      _loaded = true;
    }
    return notifier.value;
  }

  static Future<void> set(bool sidePanel) async {
    _loaded = true;
    notifier.value = sidePanel;
    try {
      await (await SharedPreferences.getInstance()).setBool(key, sidePanel);
    } catch (_) {}
  }
}

class InvoiceEntryLayoutScreen extends StatefulWidget {
  const InvoiceEntryLayoutScreen({super.key});

  @override
  State<InvoiceEntryLayoutScreen> createState() => _InvoiceEntryLayoutScreenState();
}

class _InvoiceEntryLayoutScreenState extends State<InvoiceEntryLayoutScreen> {
  late Map<String, double> _widths;
  late Set<String> _hidden;
  double _rowHeight = 34;
  bool _showEntryBar = true;
  bool _loading = true;

  /// مكان المجاميع والدفع والحفظ: لوحة جانبية (true) أو شريط سفلي (false)
  bool _sidePanel = true;

  /// 🧭 كل خانات Enter بالترتيب الذي رتّبه المستخدم (المفعّلة أولاً) والمعطّلة منها
  List<String> _stopOrder = [...InvoiceEntryLayout.defaultEnterOrder];
  Set<String> _stopOff = {};
  bool _discountPercent = true;
  double _gridWidth = 1.0;
  int _gridDark = 0;

  /// تمرير أفقي للمعاينة حين تزيد الأعمدة عن العرض. الـ Scrollbar يحتاج وحدة تحكم
  /// خاصة به: بدونها يستعمل PrimaryScrollController غير المرتبط بالتمرير الأفقي
  /// فيرمي «The Scrollbar's ScrollController has no ScrollPosition attached» في كل إطار.
  final ScrollController _previewHScroll = ScrollController();

  @override
  void dispose() {
    _previewHScroll.dispose();
    super.dispose();
  }

  // (خريطة غير ثابتة: مفاتيح double لا تصلح في const map)
  static final _rowHeights = <double, String>{30: 'مضغوط', 34: 'عادي', 42: 'واسع'};
  static const _rowIcons = [Icons.density_small_rounded, Icons.density_medium_rounded, Icons.density_large_rounded];

  @override
  void initState() {
    super.initState();
    InvoiceSidePanelPref.load().then((v) {
      if (mounted) setState(() => _sidePanel = v);
    });
    InvoiceEntryLayout.load().then((l) {
      if (!mounted) return;
      setState(() {
        _widths = {for (final k in InvoiceEntryLayout.keys) k: l.w(k)};
        _hidden = {...l.hidden};
        _rowHeight = l.rowHeight;
        _showEntryBar = l.showEntryBar;
        _setStops(l.enterOrder);
        _discountPercent = l.discountTypedAsPercent;
        _gridWidth = l.gridLineWidth;
        _gridDark = l.gridLineDarkness;
        _loading = false;
      });
    });
  }

  InvoiceEntryLayout get _draft => InvoiceEntryLayout(
        widths: _widths,
        hidden: _hidden,
        rowHeight: _rowHeight,
        showEntryBar: _showEntryBar,
        enterOrder: _enterOrder,
        discountTypedAsPercent: _discountPercent,
        gridLineWidth: _gridWidth,
        gridLineDarkness: _gridDark,
      );

  /// الخانات المفعّلة بالترتيب
  List<String> get _enterOrder => [for (final k in _stopOrder) if (!_stopOff.contains(k)) k];

  void _setStops(List<String> enabled) {
    final on = InvoiceEntryLayout.cleanEnterOrder(enabled);
    _stopOrder = [
      ...on,
      for (final k in InvoiceEntryLayout.enterStopKeys) if (!on.contains(k)) k,
    ];
    _stopOff = {for (final k in InvoiceEntryLayout.enterStopKeys) if (!on.contains(k)) k};
  }

  Future<void> _save() async {
    await _draft.save();
    await InvoiceSidePanelPref.set(_sidePanel);
    if (!mounted) return;
    setToast(context, 'حُفظ تخطيط الجدول — يظهر في شاشة «إنشاء فاتورة» عند فتحها');
    Navigator.pop(context);
  }

  void _reset() => setState(() {
        _widths = {...InvoiceEntryLayout.defaultWidths};
        _hidden = {...InvoiceEntryLayout.defaultHidden};
        _rowHeight = 34;
        _showEntryBar = true;
        _sidePanel = true;
        _setStops(InvoiceEntryLayout.defaultEnterOrder);
        _discountPercent = true;
        _gridWidth = 1.0;
        _gridDark = 0;
      });

  /// إظهار كل الأعمدة دفعة واحدة (مثل شاشة الإداري الممتلئة)
  void _showAll() => setState(() => _hidden = {});

  double get _totalWidth {
    final d = _draft;
    return d
        .visibleKeys(isViewOnly: false, canSeeCost: true)
        .fold<double>(0, (a, k) => a + d.w(k));
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'تخطيط شاشة إنشاء الفاتورة',
      subtitle: 'الأعمدة الظاهرة وعرضها، ارتفاع السطر، ومكان المجاميع',
      icon: Icons.view_week_rounded,
      maxWidth: 1100,
      loading: _loading,
      actions: [
        IconButton(
          tooltip: 'إظهار كل الأعمدة',
          onPressed: _loading ? null : _showAll,
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
                'اختر الأعمدة الظاهرة في جدول المواد وعرض كل عمود بالبكسل. إذا زاد مجموع العروض عن عرض الشاشة '
                'يظهر شريط تمرير أفقي أسفل الجدول (مثل الإداري)، وإن قلّ يتّسع «اسم المادة» ليملأ الباقي. '
                'اسم المادة والكمية والوحدة والسعر والإجمالي ضرورية ولا تُخفى.',
              ),
              const SizedBox(height: 14),
              _generalCard(),
              SetCard(
                title: 'معاينة حيّة',
                subtitle: 'هكذا سيظهر جدول المواد',
                icon: Icons.preview_rounded,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(20)),
                  child: Text('المجموع ${_totalWidth.round()} px',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kSetNavy)),
                ),
                child: Padding(padding: const EdgeInsets.only(top: 12), child: _preview()),
              ),
              _enterCard(),
              SetCard(
                title: 'الأعمدة',
                subtitle: 'فعّل العمود وحرّك المؤشر لتحديد عرضه',
                icon: Icons.view_column_rounded,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(children: [for (final k in InvoiceEntryLayout.keys) _columnTile(k)]),
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
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: kSetMuted),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('التغييرات لا تُطبَّق على الجدول قبل الحفظ (مكان المجاميع يُطبَّق فوراً).',
                      style: TextStyle(fontSize: 12.5, color: kSetMuted)),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 200,
                  child: SetPrimaryButton(label: 'حفظ التخطيط', icon: Icons.save_rounded, onPressed: _save),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _generalCard() {
    final heights = _rowHeights.entries.toList();
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
                icon: _rowIcons[i],
                title: heights[i].value,
                subtitle: '${heights[i].key.round()} بكسل',
                selected: _rowHeight == heights[i].key,
                onTap: () => setState(() => _rowHeight = heights[i].key),
              ),
          ]);
        }),
        const SizedBox(height: 8),
        const Divider(height: 18),
        _gridLinesControl(),
        const Divider(height: 18),
        SetSwitch(
          title: 'شريط الإدخال فوق الجدول',
          subtitle: 'عند إيقافه تُكتب المواد مباشرة في آخر سطر فارغ من الجدول كما في الإداري، ويبقى للجدول ارتفاع أكبر.',
          icon: Icons.input_rounded,
          value: _showEntryBar,
          onChanged: (v) => setState(() => _showEntryBar = v),
        ),
        const Divider(height: 18),
        const Text('مكان المجاميع والدفع وزر الحفظ', style: TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth >= 540 ? (c.maxWidth - 10) / 2 : c.maxWidth;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            _placementOption(w, side: true),
            _placementOption(w, side: false),
          ]);
        }),
        const SizedBox(height: 10),
        const Text(
          'الشريط السفلي يعرض كل ما في اللوحة الجانبية: الإجمالي قبل الخصم وبعده، المبلغ المسدد والمتبقي، '
          'الخصم المسموح به وأجور التحميل أو النقل، نقد أو دين، والصافي للدفع مع زر حفظ الفاتورة. '
          'يُطبَّق اختيارك فوراً على شاشات الفاتورة المفتوحة.',
          style: TextStyle(fontSize: 12, color: kSetMuted, height: 1.55),
        ),
      ]),
    );
  }

  /// ▦ خطوط الجدول: سماكة ودرجة لون (من الرمادي الفاتح إلى الأسود)
  Widget _gridLinesControl() {
    final color = _draft.gridColor;
    Widget sample() => Container(
          width: 120,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: color, width: _gridWidth),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(children: [
            Expanded(
              child: Row(children: [
                Expanded(child: Container(decoration: BoxDecoration(border: BorderDirectional(end: BorderSide(color: color, width: _gridWidth))))),
                const Expanded(child: SizedBox()),
              ]),
            ),
            Container(height: _gridWidth, color: color),
            Expanded(
              child: Row(children: [
                Expanded(child: Container(decoration: BoxDecoration(border: BorderDirectional(end: BorderSide(color: color, width: _gridWidth))))),
                const Expanded(child: SizedBox()),
              ]),
            ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('خطوط الجدول بين الأسطر والأعمدة', style: TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
      const SizedBox(height: 4),
      const Text('اجعلها أوضح إن كانت الشاشة باهتة أو تعمل في محل مضيء.',
          style: TextStyle(fontSize: 12, color: kSetMuted)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const SizedBox(width: 70, child: Text('درجة اللون', style: TextStyle(fontSize: 13))),
              Expanded(
                child: Slider(
                  value: _gridDark.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: _gridDark == 0 ? 'فاتح' : (_gridDark == 100 ? 'أسود' : '$_gridDark%'),
                  onChanged: (v) => setState(() => _gridDark = v.round()),
                ),
              ),
              SizedBox(width: 44, child: Text(_gridDark == 100 ? 'أسود' : '$_gridDark%', style: const TextStyle(fontSize: 12))),
            ]),
            Row(children: [
              const SizedBox(width: 70, child: Text('السماكة', style: TextStyle(fontSize: 13))),
              Expanded(
                child: Slider(
                  value: _gridWidth,
                  min: 0.5,
                  max: 3,
                  divisions: 5,
                  label: '${_gridWidth.toStringAsFixed(1)} بكسل',
                  onChanged: (v) => setState(() => _gridWidth = v),
                ),
              ),
              SizedBox(width: 44, child: Text(_gridWidth.toStringAsFixed(1), style: const TextStyle(fontSize: 12))),
            ]),
          ]),
        ),
        const SizedBox(width: 12),
        sample(),
      ]),
    ]);
  }

  /// خيار مكان المجاميع مع رسم مصغّر يوضّح الشكل.
  Widget _placementOption(double width, {required bool side}) {
    final selected = _sidePanel == side;
    const c = kSetNavy;
    Widget box(Color color, {double? w, double? h}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        );
    final sketch = SizedBox(
      width: 74,
      height: 50,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? c : kSetBorder),
        ),
        child: side
            ? Row(children: [
                Expanded(child: box(const Color(0xFFE2E8F0))),
                const SizedBox(width: 3),
                box(selected ? c : const Color(0xFF94A3B8), w: 18),
              ])
            : Column(children: [
                Expanded(child: box(const Color(0xFFE2E8F0))),
                const SizedBox(height: 3),
                box(selected ? c : const Color(0xFF94A3B8), h: 10),
              ]),
      ),
    );
    return SizedBox(
      width: width,
      child: Material(
        color: selected ? c.withValues(alpha: 0.06) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? c : kSetBorder, width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            setState(() => _sidePanel = side);
            InvoiceSidePanelPref.set(side); // يُطبَّق فوراً
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              sketch,
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(side ? 'لوحة جانبية' : 'شريط سفلي',
                      style: TextStyle(fontWeight: FontWeight.w800, color: selected ? c : kSetText)),
                  Text(side ? 'المجاميع بجانب الجدول' : 'الجدول بعرض الشاشة كاملاً',
                      style: const TextStyle(fontSize: 12, color: kSetMuted)),
                ]),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: selected ? 1 : 0,
                child: const Icon(Icons.check_circle_rounded, color: c, size: 20),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _preview() {
    final d = _draft;
    final shown = d.visibleKeys(isViewOnly: false, canSeeCost: true);
    final stops = d.enterStops(shown); // رقم كل خانة في مسار Enter يظهر على رأس عمودها
    return LayoutBuilder(builder: (context, box) {
      final widths = d.resolve(box.maxWidth - 2, isViewOnly: false, canSeeCost: true);
      final tableWidth = widths.values.fold<double>(0, (a, b) => a + b) + 2;
      Widget row(Map<String, String> cells, {bool header = false, bool zebra = false}) => Container(
            decoration: BoxDecoration(
              color: header ? const Color(0xFF0F3460) : (zebra ? const Color(0xFFF8FAFC) : Colors.white),
              border: Border(bottom: d.gridSide),
            ),
            child: Row(children: [
              for (final k in shown)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: widths[k],
                  height: header ? 30 : _rowHeight,
                  alignment: k == 'details' ? AlignmentDirectional.centerStart : Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      end: header ? const BorderSide(color: Colors.white24) : d.gridSide,
                    ),
                  ),
                  child: header && stops.contains(k)
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          _stepBadge(stops.indexOf(k) + 1, onDark: true),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(InvoiceEntryLayout.headers[k]!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white)),
                          ),
                        ])
                      : Text(
                    header ? InvoiceEntryLayout.headers[k]! : (cells[k] ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: header ? FontWeight.w800 : null,
                      fontSize: _rowHeight < 34 && !header ? 12 : 13,
                      color: header
                          ? Colors.white
                          : (k == 'stock' && cells[k] == '0'
                              ? kSetRed
                              : (k == 'profit' && (cells[k] ?? '').startsWith('-') ? kSetRed : kSetText)),
                    ),
                  ),
                ),
            ]),
          );
      final table = Container(
        width: tableWidth,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Column(children: [
          row(const {}, header: true),
          row(const {
            'index': '1',
            'code': '1024',
            'itemCode': 'EL-32',
            'barcode': '6281000012',
            'details': 'قاطع 32 أمبير',
            'qty': '10',
            'saleType': 'قطعة',
            'price': '9,000',
            'listPrice': '10,000',
            'discount': '10%',
            'units': '',
            'total': '90,000',
            'stock': '140',
            'cost': '7,500',
            'profit': '15,000',
          }),
          row(const {
            'index': '2',
            'code': '2210',
            'itemCode': 'LD-20',
            'barcode': '6281000098',
            'details': 'لمبة LED 20 واط',
            'qty': '2',
            'saleType': 'كرتون',
            'price': '0',
            'listPrice': '36,000',
            'discount': 'هدية',
            'units': '24',
            'total': '0',
            'stock': '0',
            'cost': '28,000',
            'profit': '-56,000',
          }, zebra: true),
          row(const {}),
        ]),
      );
      if (tableWidth <= box.maxWidth) return table;
      return Scrollbar(
        controller: _previewHScroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _previewHScroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 12),
          child: table,
        ),
      );
    });
  }

  Widget _columnTile(String k) {
    final locked = InvoiceEntryLayout.required.contains(k);
    final visible = locked || !_hidden.contains(k);
    final width = _widths[k] ?? InvoiceEntryLayout.defaultWidths[k] ?? 80;
    final isCost = InvoiceEntryLayout.costColumns.contains(k);

    final toggle = locked
        ? const Tooltip(
            message: 'عمود ضروري لإدخال السطر',
            child: SizedBox(
              width: 44,
              child: Icon(Icons.lock_rounded, size: 18, color: Color(0xFF94A3B8)),
            ),
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
      Text(InvoiceEntryLayout.labels[k]!,
          style: TextStyle(fontWeight: FontWeight.w700, color: visible ? kSetText : const Color(0xFF94A3B8))),
      if (isCost)
        const Text('يظهر فقط لمن لديه صلاحية رؤية الكلفة والأرباح', style: TextStyle(fontSize: 11, color: kSetOrange)),
      if (k == 'discount')
        const Text('إخفاؤه يخفي أيضاً حقل الخصم وزر الهدية', style: TextStyle(fontSize: 11, color: kSetMuted)),
    ]);

    final slider = Row(children: [
      Expanded(
        child: Slider(
          value: width.clamp(InvoiceEntryLayout.minWidth, InvoiceEntryLayout.maxWidth).toDouble(),
          min: InvoiceEntryLayout.minWidth,
          max: InvoiceEntryLayout.maxWidth,
          divisions: ((InvoiceEntryLayout.maxWidth - InvoiceEntryLayout.minWidth) / 2).round(),
          label: '${width.round()}',
          onChanged: visible ? (v) => setState(() => _widths[k] = v.roundToDouble()) : null,
        ),
      ),
      Container(
        width: 66,
        padding: const EdgeInsets.symmetric(vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: visible ? const Color(0xFFEFF4FF) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('${width.round()} px',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: visible ? kSetNavy : const Color(0xFF94A3B8),
            )),
      ),
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
          return Row(children: [
            toggle,
            SizedBox(width: 230, child: label),
            Expanded(child: slider),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [toggle, Expanded(child: label)]),
          slider,
        ]);
      }),
    );
  }
  // ───────────── 🧭 مسار زر Enter ─────────────

  static const Map<String, String> _stopTitles = {
    'qty': 'الكمية',
    'saleType': 'الوحدة (قطعة، كرتون…)',
    'price': 'السعر',
    'discount': 'الخصم / الهدية',
  };

  static const Map<String, String> _stopHints = {
    'qty': 'إن تخطّاها: الكمية 1',
    'saleType': 'Enter يفتح قائمة الوحدات · إن تخطّاها: الوحدة الأساسية للمادة',
    'price': 'إن تخطّاه: السعر المقترح تلقائياً',
    'discount': 'تُكتب فيه 10% أو 500 أو «هدية» · إن تخطّاه: بلا خصم',
  };

  bool _columnShown(String k) => _draft.show(k);

  Widget _stepBadge(int? n, {bool onDark = false, bool muted = false}) => Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: muted ? const Color(0xFFE2E8F0) : (onDark ? Colors.white : kSetNavy),
        ),
        child: Text(n == null ? '–' : '$n',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: muted ? const Color(0xFF94A3B8) : (onDark ? kSetNavy : Colors.white),
            )),
      );

  void _moveStop(String k, int delta) => setState(() {
        final i = _stopOrder.indexOf(k);
        final j = i + delta;
        if (i < 0 || j < 0 || j >= _stopOrder.length) return;
        _stopOrder
          ..removeAt(i)
          ..insert(j, k);
      });

  void _toggleStop(String k, bool on) => setState(() {
        if (on) {
          _stopOff.remove(k);
          // المفعّلة حديثاً تنضم إلى آخر المسار المفعّل
          _stopOrder.remove(k);
          final lastOn = _stopOrder.lastIndexWhere((x) => !_stopOff.contains(x));
          _stopOrder.insert(lastOn + 1, k);
        } else {
          _stopOff.add(k);
          // المعطّلة تنزل إلى آخر القائمة
          _stopOrder
            ..remove(k)
            ..add(k);
        }
      });

  /// ملاحظات حيّة على الترتيب الحالي (ماذا سيحدث فعلاً)
  List<(IconData, Color, String)> _enterNotes() {
    final order = _enterOrder;
    final notes = <(IconData, Color, String)>[];
    final iUnit = order.indexOf('saleType');
    final iPrice = order.indexOf('price');
    final iDisc = order.indexOf('discount');
    if (iUnit >= 0 && iPrice >= 0 && iUnit > iPrice) {
      notes.add((
        Icons.warning_amber_rounded,
        kSetOrange,
        'الوحدة بعد السعر: إذا اخترت وحدة غير الحالية يرجع السعر إلى سعر تلك الوحدة، فيضيع السعر الذي كتبته قبلها. '
            'إبقاء الوحدة نفسها لا يغيّر شيئاً.',
      ));
    }
    if (iDisc >= 0 && iPrice >= 0 && iDisc < iPrice) {
      notes.add((
        Icons.warning_amber_rounded,
        kSetOrange,
        'الخصم قبل السعر: الخصم يُحسب من السعر الموجود لحظتها، وأي سعر تكتبه بعده يُعتبر السعر الصافي بعد الخصم.',
      ));
    }
    if (_enterOrder.contains('discount') && !_columnShown('discount')) {
      notes.add((
        Icons.visibility_off_outlined,
        kSetOrange,
        'عمود «الخصم» مخفي من الجدول، فلن يقف عنده Enter حتى تُظهره.',
      ));
    }
    if (order.isEmpty) {
      notes.add((
        Icons.info_outline_rounded,
        kSetBlue,
        'لا خانات بعد اسم المادة: Enter ينقلك مباشرة إلى السطر التالي (الكمية 1، الوحدة الأساسية، السعر المقترح). '
            'مناسب للبيع السريع بالباركود.',
      ));
    }
    return notes;
  }

  Widget _enterCard() {
    final order = _enterOrder;
    final path = ['details', for (final k in order) if (_columnShown(k)) k];
    Widget chip(String text, {bool first = false, bool end = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: first ? kSetNavy : (end ? const Color(0xFFECFDF5) : const Color(0xFFEFF4FF)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: end ? const Color(0xFFA7F3D0) : Colors.transparent),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (end) ...[
              const Icon(Icons.keyboard_return_rounded, size: 15, color: kSetGreen),
              const SizedBox(width: 4),
            ],
            Text(text,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: first ? Colors.white : (end ? kSetGreen : kSetNavy),
                )),
          ]),
        );
    const arrow = Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF94A3B8));
    final notes = _enterNotes();

    return SetCard(
      title: 'مسار زر Enter في سطر المادة',
      subtitle: 'أين يقف المؤشر كلما ضغطت Enter، وبأي ترتيب',
      icon: Icons.keyboard_return_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 12),
        // المسار كما سيحدث فعلاً
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kSetBorder),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < path.length; i++) ...[
                if (i > 0) arrow,
                chip(i == 0 ? 'اسم المادة' : _stopTitles[path[i]]!.split(' (').first, first: i == 0),
              ],
              arrow,
              chip('اسم المادة في السطر التالي', end: true),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // الخانة الأولى ثابتة
        _stopRow(
          leading: _stepBadge(1),
          title: 'اسم المادة',
          hint: 'أول خانة دائماً — تُختار المادة قبل كمّيتها وسعرها',
          enabled: true,
          locked: true,
        ),
        for (final k in _stopOrder) _stopTile(k),
        for (final n in notes)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: n.$2.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(n.$1, size: 18, color: n.$2),
              const SizedBox(width: 8),
              Expanded(child: Text(n.$3, style: TextStyle(fontSize: 12.5, height: 1.5, color: n.$2))),
            ]),
          ),
        if (order.contains('discount')) ...[
          const Divider(height: 26),
          const Text('الرقم الذي تكتبه في خانة الخصم يعني',
              style: TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('نسبة %')),
                ButtonSegment(value: false, label: Text('مبلغ من سعر الوحدة')),
              ],
              selected: {_discountPercent},
              onSelectionChanged: (v) => setState(() => _discountPercent = v.first),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _discountPercent
                ? 'مثال: 10 تعني خصم 10%. اكتب «هدية» لتصبح مجاناً، واتركها فارغة لإلغاء الخصم.'
                : 'مثال: 500 تعني خصم 500 من سعر الوحدة، و10% تبقى نسبة. اكتب «هدية» لتصبح مجاناً، واتركها فارغة لإلغاء الخصم.',
            style: const TextStyle(fontSize: 12, color: kSetMuted, height: 1.5),
          ),
        ],
        const SizedBox(height: 4),
      ]),
    );
  }

  Widget _stopTile(String k) {
    final on = !_stopOff.contains(k);
    final shownCol = _columnShown(k);
    final step = on ? _enterOrder.indexOf(k) + 2 : null; // 1 = اسم المادة
    final enabledCount = _enterOrder.length;
    final pos = on ? _enterOrder.indexOf(k) : -1;
    return _stopRow(
      leading: _stepBadge(step, muted: step == null),
      title: _stopTitles[k]!,
      hint: on && !shownCol ? 'العمود مخفي — لن يقف عنده Enter' : _stopHints[k]!,
      hintColor: on && !shownCol ? kSetOrange : null,
      enabled: on,
      onToggle: (v) => _toggleStop(k, v),
      onUp: on && pos > 0 ? () => _moveStop(k, -1) : null,
      onDown: on && pos >= 0 && pos < enabledCount - 1 ? () => _moveStop(k, 1) : null,
    );
  }

  Widget _stopRow({
    required Widget leading,
    required String title,
    required String hint,
    required bool enabled,
    bool locked = false,
    Color? hintColor,
    ValueChanged<bool>? onToggle,
    VoidCallback? onUp,
    VoidCallback? onDown,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: enabled ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: enabled && !locked ? const Color(0xFFC7D2FE) : kSetBorder),
      ),
      child: Row(children: [
        SizedBox(
          width: 40,
          child: locked
              ? const Tooltip(
                  message: 'خانة ثابتة',
                  child: Icon(Icons.lock_rounded, size: 18, color: Color(0xFF94A3B8)),
                )
              : Checkbox(
                  value: enabled,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  onChanged: onToggle == null ? null : (v) => onToggle(v ?? false),
                ),
        ),
        leading,
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: enabled ? kSetText : const Color(0xFF94A3B8),
                  decoration: enabled ? null : TextDecoration.lineThrough,
                )),
            Text(hint, style: TextStyle(fontSize: 11.5, color: hintColor ?? kSetMuted)),
          ]),
        ),
        if (!locked) ...[
          IconButton(
            tooltip: 'قبلها في المسار',
            visualDensity: VisualDensity.compact,
            onPressed: onUp,
            icon: const Icon(Icons.arrow_upward_rounded, size: 19),
          ),
          IconButton(
            tooltip: 'بعدها في المسار',
            visualDensity: VisualDensity.compact,
            onPressed: onDown,
            icon: const Icon(Icons.arrow_downward_rounded, size: 19),
          ),
        ],
      ]),
    );
  }
}
