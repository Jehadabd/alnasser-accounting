// lib/screens/purchase_sale_extras.dart
//
// 🏷️ «سعر بيع المفرد» والباركودات والأسعار الأخرى — من سطر فاتورة الشراء مباشرة.
//
//  • عمود «سعر بيع المفرد» (للوحدة الأساسية، مثل القطعة) في كل سطر.
//      - مادة موجودة: يبدأ بسعرها الحالي. مادة جديدة أو بلا سعر: يبدأ بالكلفة.
//  • «تسعير سريع»: الكلفة + مبلغ، أو الكلفة + نسبة، مع تقريب للأعلى إلى 250 دينار
//    (أصغر عملة متداولة). يُطبَّق على المواد الجديدة وحدها إلا إن اخترت «كل المواد».
//  • ✱ في السطر: الأسعار الخمسة الأخرى + باركودات متعددة.
//
// 🛡️ لا يُكتب شيء قبل حفظ الفاتورة: بعد نجاح الحفظ يُطبَّق فقط ما غيّرته أنت، عبر
//    المسارات الأصلية (PriceTools.applyPrices مع سجل تغيير الأسعار، وإضافة الباركود
//    من بطاقة المادة مع فحص التكرار). الفاتورة والمخزون والدين لا تتأثر بها.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../erp/erp_common.dart' show parseMoney;
import '../models/product.dart';
import '../providers/pos_provider.dart' show PosProvider;
import '../services/database_service.dart';
import '../widgets/formatters.dart' show ThousandSeparatorDecimalInputFormatter;

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);
const _bg = Color(0xFFF5F7FB);
const _navy = Color(0xFF0F3460);
const _teal = Color(0xFF0D9488);
const _good = Color(0xFF16A34A);
const _bad = Color(0xFFDC2626);
const _gold = Color(0xFFF59E0B);

final _fmt = intl.NumberFormat('#,##0.##', 'en_US');
String fmtSale(num v) => _fmt.format(v);

/// حساب السعر من الكلفة — منفصل ليُختبر.
class SalePriceMath {
  SalePriceMath._();

  /// أصغر عملة عراقية متداولة.
  static const double iqdStep = 250;

  /// تقريب للأعلى إلى مضاعف [step] (1,265 ← 1,500). القيمة التي هي مضاعف أصلاً تبقى.
  static double roundUp(double v, double step) {
    if (step <= 0 || !v.isFinite) return v;
    final q = v / step;
    final r = q.roundToDouble();
    if ((q - r).abs() < 1e-9) return r * step; // ضجيج الحساب لا يرفع خطوة كاملة
    return q.ceilToDouble() * step;
  }

  /// الكلفة + مبلغ، أو الكلفة + نسبة، ثم التقريب.
  static double fromCost(double cost, {required bool percent, required double value, double step = iqdStep}) {
    final raw = percent ? cost * (1 + value / 100) : cost + value;
    return roundUp(raw, step);
  }

  /// نسبة الربح على الكلفة (null إن لم تُعرف الكلفة).
  static double? marginPct(double price, double cost) => cost > 0 ? (price - cost) / cost * 100 : null;
}

/// ما يُدخله المستخدم لسطر واحد — يُطبَّق بعد حفظ الفاتورة.
class PurchaseSaleExtras {
  PurchaseSaleExtras({required double initialRetail, required this.originalRetail})
      : retail = TextEditingController(text: initialRetail > 0 ? _fmt.format(initialRetail) : '');

  final TextEditingController retail;

  /// سعر المفرد الحالي للمادة عند فتح الشاشة (0 = بلا سعر / غير معرّفة).
  double originalRetail;

  /// غيّره المستخدم (كتابة أو تسعير سريع) — وحده ما يُحفظ.
  bool touched = false;

  /// الأسعار 2..6 التي غيّرها: المستوى ← السعر.
  final Map<int, double> otherPrices = {};

  /// باركودات جديدة (الرمز، الوصف).
  final List<(String, String?)> newBarcodes = [];

  double? get retailValue => parseMoney(retail.text);
  bool get hasPending => touched || otherPrices.isNotEmpty || newBarcodes.isNotEmpty;

  void setRetail(double v) {
    retail.text = _fmt.format(v);
    touched = true;
  }

  void dispose() => retail.dispose();
}

// ─────────────────────────── التسعير السريع ───────────────────────────

class QuickPriceRule {
  const QuickPriceRule({required this.percent, required this.value, required this.round, required this.allRows});
  final bool percent;
  final double value;
  final bool round;
  final bool allRows;
}

/// نافذة «تسعير سريع». [newCount] عدد المواد الجديدة، [allCount] كل المواد.
Future<QuickPriceRule?> showQuickPriceDialog(BuildContext context,
        {required int newCount, required int allCount, required double? sampleCost, String? note}) =>
    showDialog<QuickPriceRule>(
      context: context,
      builder: (_) => _QuickPriceDialog(newCount: newCount, allCount: allCount, sampleCost: sampleCost, note: note),
    );

class _QuickPriceDialog extends StatefulWidget {
  const _QuickPriceDialog({required this.newCount, required this.allCount, this.sampleCost, this.note});
  final int newCount;
  final int allCount;
  final double? sampleCost;
  final String? note;

  @override
  State<_QuickPriceDialog> createState() => _QuickPriceDialogState();
}

class _QuickPriceDialogState extends State<_QuickPriceDialog> {
  bool _percent = true;
  bool _round = true;
  late bool _all = widget.newCount == 0;
  final _value = TextEditingController(text: '15');

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  double get _v => parseMoney(_value.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    final cost = widget.sampleCost;
    final count = _all ? widget.allCount : widget.newCount;
    final valid = _v > 0 && count > 0;
    final sample = cost == null || cost <= 0
        ? null
        : SalePriceMath.fromCost(cost, percent: _percent, value: _v, step: _round ? SalePriceMath.iqdStep : 1);

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Header(icon: Icons.auto_awesome_rounded, title: 'تسعير سريع', subtitle: 'سعر بيع المفرد من الكلفة — لكل قطعة'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: _Choice(label: 'الكلفة + نسبة %', icon: Icons.percent_rounded, on: _percent, onTap: () => setState(() => _percent = true))),
                const SizedBox(width: 10),
                Expanded(child: _Choice(label: 'الكلفة + مبلغ', icon: Icons.add_card_rounded, on: !_percent, onTap: () => setState(() => _percent = false))),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: _value,
                autofocus: true,
                textDirection: TextDirection.ltr,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                decoration: _dec(_percent ? 'النسبة' : 'المبلغ بالدينار', suffix: _percent ? '%' : 'د.ع'),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final q in _percent ? const [10, 15, 20, 25, 30] : const [250, 500, 1000, 2000])
                  ActionChip(
                    label: Text(_percent ? '$q%' : '+${_fmt.format(q)}'),
                    onPressed: () => setState(() => _value.text = _fmt.format(q)),
                    backgroundColor: _bg,
                    side: const BorderSide(color: _line),
                    shape: const StadiumBorder(),
                  ),
              ]),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _round,
                onChanged: (v) => setState(() => _round = v),
                title: const Text('تقريب للأعلى إلى 250 دينار', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('مثال: 1,265 ← 1,500'),
              ),
              if (widget.newCount > 0 && widget.newCount < widget.allCount)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _all,
                  onChanged: (v) => setState(() => _all = v),
                  title: const Text('على كل المواد', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(_all
                      ? 'سيتغير سعر المواد الموجودة أيضاً (${widget.allCount})'
                      : 'المواد الجديدة فقط (${widget.newCount}) — أسعار الموجودة تبقى'),
                ),
              if (sample != null)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _teal.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.calculate_outlined, color: _teal),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('مثال: كلفة ${_fmt.format(cost!)} ← بيع ${_fmt.format(sample)}',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
                    ),
                  ]),
                ),
              if (widget.note != null) ...[
                const SizedBox(height: 8),
                Text(widget.note!, style: const TextStyle(color: _bad, fontSize: 12.5)),
              ],
            ]),
          ),
          _Footer(
            okLabel: count > 0 ? 'طبّق على $count' : 'لا مواد',
            onOk: valid
                ? () => Navigator.pop(context, QuickPriceRule(percent: _percent, value: _v, round: _round, allRows: _all))
                : null,
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────── ✱ تفاصيل البيع ───────────────────────────

/// يفتح ✱ لمادة. يعدّل [extras] فقط (لا قاعدة بيانات) — true = حُفظ.
Future<bool?> showSaleExtrasDialog(BuildContext context,
        {required Product product,
        required PurchaseSaleExtras extras,
        required double baseCost,
        required String baseUnit,
        required bool canPrice,
        required bool canBarcodes,
        required Set<String> pendingElsewhere}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => _SaleExtrasDialog(
          product: product,
          extras: extras,
          baseCost: baseCost,
          baseUnit: baseUnit,
          canPrice: canPrice,
          canBarcodes: canBarcodes,
          pendingElsewhere: pendingElsewhere),
    );

class _SaleExtrasDialog extends StatefulWidget {
  const _SaleExtrasDialog(
      {required this.product,
      required this.extras,
      required this.baseCost,
      required this.baseUnit,
      required this.canPrice,
      required this.canBarcodes,
      required this.pendingElsewhere});
  final Product product;
  final PurchaseSaleExtras extras;
  final double baseCost;
  final String baseUnit;
  final bool canPrice;
  final bool canBarcodes;
  final Set<String> pendingElsewhere;

  @override
  State<_SaleExtrasDialog> createState() => _SaleExtrasDialogState();
}

class _SaleExtrasDialogState extends State<_SaleExtrasDialog> {
  late final List<TextEditingController> _p;
  late final List<double> _orig;
  late final List<(String, String?)> _codes = List.of(widget.extras.newBarcodes);
  final _code = TextEditingController();
  final _label = TextEditingController();
  final _codeFocus = FocusNode();
  List<String> _existing = [];
  String? _codeErr;
  bool _checking = false;

  static double _priceOf(Product p, int level) => switch (level) {
        1 => p.price1,
        2 => p.price2 ?? 0,
        3 => p.price3 ?? 0,
        4 => p.price4 ?? 0,
        5 => p.price5 ?? 0,
        _ => p.price6 ?? 0,
      };

  @override
  void initState() {
    super.initState();
    final ex = widget.extras;
    _orig = [for (var l = 1; l <= 6; l++) _priceOf(widget.product, l)];
    _p = [
      for (var l = 1; l <= 6; l++)
        TextEditingController(
            text: l == 1
                ? ex.retail.text
                : (() {
                    final v = ex.otherPrices[l] ?? _orig[l - 1];
                    return v > 0 ? _fmt.format(v) : '';
                  })()),
    ];
    _loadCodes();
  }

  Future<void> _loadCodes() async {
    final id = widget.product.id;
    if (id == null || id <= 0) return;
    try {
      final db = await DatabaseService().database;
      final rows = await db.query('product_barcodes', columns: ['barcode'], where: 'product_id = ?', whereArgs: [id], orderBy: 'id');
      final primary = widget.product.barcode?.trim() ?? '';
      if (!mounted) return;
      setState(() => _existing = [
            if (primary.isNotEmpty) primary,
            for (final r in rows) '${r['barcode']}',
          ]);
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in _p) {
      c.dispose();
    }
    _code.dispose();
    _label.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// فحص التكرار قبل الإضافة (قراءة فقط) — والإضافة الفعلية تعيد الفحص عند الحفظ.
  Future<void> _addCode() async {
    final b = _code.text.trim();
    if (b.isEmpty || _checking) return;
    String? err;
    if (_existing.contains(b) || _codes.any((c) => c.$1 == b)) {
      err = 'هذا الباركود مضاف لهذه المادة';
    } else if (widget.pendingElsewhere.contains(b)) {
      err = 'هذا الباركود أضفته لمادة أخرى في هذه الفاتورة';
    } else {
      setState(() => _checking = true);
      try {
        final db = await DatabaseService().database;
        final dup = await db.rawQuery('''
          SELECT p.name FROM product_barcodes pb JOIN products p ON p.id = pb.product_id WHERE pb.barcode = ?
          UNION SELECT name FROM products WHERE barcode = ? AND id != ?
        ''', [b, b, widget.product.id ?? -1]);
        if (dup.isNotEmpty) err = 'الباركود مستخدم للمادة «${dup.first['name']}»';
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _codeErr = err;
      if (err == null) {
        final l = _label.text.trim();
        _codes.add((b, l.isEmpty ? null : l));
        _code.clear();
        _label.clear();
      }
    });
    _codeFocus.requestFocus();
  }

  void _save() {
    final ex = widget.extras;
    if (widget.canPrice) {
      final r = parseMoney(_p[0].text);
      if (_p[0].text != ex.retail.text) {
        ex.retail.text = _p[0].text;
        ex.touched = true;
      }
      if (r != null && r <= 0) ex.touched = false;
      ex.otherPrices.clear();
      for (var l = 2; l <= 6; l++) {
        final v = parseMoney(_p[l - 1].text) ?? 0;
        if ((v - _orig[l - 1]).abs() >= 0.005) ex.otherPrices[l] = v;
      }
    }
    if (widget.canBarcodes) {
      ex.newBarcodes
        ..clear()
        ..addAll(_codes);
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cost = widget.baseCost;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Header(
            icon: Icons.stars_rounded,
            title: widget.product.name,
            subtitle: cost > 0 ? 'الكلفة ${_fmt.format(cost)} لكل ${widget.baseUnit}' : 'الأسعار لكل ${widget.baseUnit}',
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _sectionTitle(Icons.sell_outlined, 'أسعار البيع', widget.canPrice ? null : 'لا تملك صلاحية تعديل الأسعار'),
                const SizedBox(height: 10),
                LayoutBuilder(builder: (context, c) {
                  final w = c.maxWidth >= 520 ? (c.maxWidth - 12) / 2 : c.maxWidth;
                  return Wrap(spacing: 12, runSpacing: 12, children: [
                    for (var i = 0; i < 6; i++) SizedBox(width: w, child: _priceField(i, cost)),
                  ]);
                }),
                const SizedBox(height: 22),
                _sectionTitle(Icons.qr_code_2_rounded, 'الباركودات', widget.canBarcodes ? null : 'لا تملك صلاحية بطاقة المادة'),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final b in _existing)
                    Chip(
                      avatar: const Icon(Icons.qr_code_rounded, size: 16, color: _navy),
                      label: Text(b, textDirection: TextDirection.ltr),
                      backgroundColor: _bg,
                      side: const BorderSide(color: _line),
                    ),
                  for (final c in _codes)
                    InputChip(
                      avatar: const Icon(Icons.fiber_new_rounded, size: 18, color: _teal),
                      label: Text(c.$2 == null ? c.$1 : '${c.$1} · ${c.$2}', textDirection: TextDirection.ltr),
                      backgroundColor: _teal.withValues(alpha: 0.08),
                      side: BorderSide(color: _teal.withValues(alpha: 0.35)),
                      onDeleted: () => setState(() => _codes.remove(c)),
                    ),
                  if (_existing.isEmpty && _codes.isEmpty)
                    const Text('لا يوجد باركود بعد — امسح بالقارئ أو اكتب ثم Enter', style: TextStyle(color: _muted)),
                ]),
                if (widget.canBarcodes) ...[
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _code,
                        focusNode: _codeFocus,
                        textDirection: TextDirection.ltr,
                        onSubmitted: (_) => _addCode(),
                        decoration: _dec('الباركود', icon: Icons.qr_code_scanner_rounded).copyWith(errorText: _codeErr),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _label,
                        onSubmitted: (_) => _addCode(),
                        decoration: _dec('وصف (اختياري)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _checking ? null : _addCode,
                        style: FilledButton.styleFrom(backgroundColor: _teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        child: _checking
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.add_rounded),
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _gold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                  child: const Row(children: [
                    Icon(Icons.info_outline_rounded, color: _gold),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('لا يُحفظ شيء الآن — تُطبَّق مع حفظ الفاتورة («تأكيد واستلام» أو «حفظ كمسودة»).',
                          style: TextStyle(color: _ink, fontSize: 12.5, height: 1.5)),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          _Footer(okLabel: 'تم', onOk: _save),
        ]),
      ),
    );
  }

  Widget _priceField(int i, double cost) {
    final v = parseMoney(_p[i].text) ?? 0;
    final m = v > 0 ? SalePriceMath.marginPct(v, cost) : null;
    final below = m != null && m < 0;
    final changed = (v - _orig[i]).abs() >= 0.005;
    return TextField(
      controller: _p[i],
      enabled: widget.canPrice,
      textDirection: TextDirection.ltr,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
      onChanged: (_) => setState(() {}),
      style: TextStyle(fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600),
      decoration: _dec(PosProvider.priceLevels[i], icon: i == 0 ? Icons.star_rounded : null).copyWith(
        helperText: m == null ? (changed ? 'تغيّر' : null) : '${m >= 0 ? '+' : ''}${m.toStringAsFixed(1)}% على الكلفة${changed ? ' · تغيّر' : ''}',
        helperStyle: TextStyle(color: below ? _bad : (changed ? _teal : _muted), fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String t, String? warn) => Row(children: [
        Icon(icon, size: 20, color: _navy),
        const SizedBox(width: 8),
        Text(t, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: _ink)),
        if (warn != null) ...[
          const SizedBox(width: 10),
          Flexible(child: Text(warn, style: const TextStyle(color: _bad, fontSize: 12))),
        ],
      ]);
}

// ─────────────────────────── عناصر مشتركة ───────────────────────────

InputDecoration _dec(String label, {String? suffix, IconData? icon}) => InputDecoration(
      labelText: label,
      suffixText: suffix,
      prefixIcon: icon == null ? null : Icon(icon, size: 20, color: icon == Icons.star_rounded ? _gold : _muted),
      isDense: true,
      filled: true,
      fillColor: _bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _navy, width: 1.6)),
    );

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_navy, Color(0xFF1D4ED8)], begin: Alignment.topRight, end: Alignment.bottomLeft),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
            ]),
          ),
          IconButton(
            tooltip: 'إغلاق',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ]),
      );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.okLabel, required this.onOk});
  final String okLabel;
  final VoidCallback? onOk;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
        child: Row(children: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          const Spacer(),
          FilledButton.icon(
            onPressed: onOk,
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.check_rounded),
            label: Text(okLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.icon, required this.on, required this.onTap});
  final String label;
  final IconData icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: on ? _navy.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? _navy : _line, width: on ? 1.8 : 1),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 20, color: on ? _navy : _muted),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: on ? _navy : _ink))),
          ]),
        ),
      );
}

/// للاستعمال في العمود: لون/نص الربح تحت الحقل.
({String text, Color color}) marginHint(double? price, double cost) {
  if (price == null || price <= 0) return (text: cost > 0 ? 'كلفة ${_fmt.format(cost)}' : '', color: _muted);
  final m = SalePriceMath.marginPct(price, cost);
  if (m == null) return (text: '', color: _muted);
  return (text: '${m >= 0 ? '+' : ''}${m.toStringAsFixed(0)}% · كلفة ${_fmt.format(cost)}', color: m < 0 ? _bad : _good);
}
