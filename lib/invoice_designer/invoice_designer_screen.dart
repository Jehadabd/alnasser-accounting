// lib/invoice_designer/invoice_designer_screen.dart
//
// 🎨 مصمم الفاتورة: نماذج جاهزة أو ورقة بيضاء. اسحب العناصر من القائمة إلى
// الورقة، حرّكها بالسحب، وغيّر حجمها من الزوايا. لوحة الخصائص تتغير حسب العنصر،
// والمعاينة PDF حقيقية. واختيار التصميم لكل نوع طباعة من لوحة التصميم نفسها.
// (الإعدادات ← الفاتورة والطباعة ← مصمم الفاتورة)

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../screens/invoice_design_screen.dart';
import '../services/voucher_print.dart' show VoucherKinds, VoucherPrint;
import 'designer_widgets.dart';
import 'invoice_layout.dart';
import 'invoice_layout_store.dart';
import 'invoice_layout_templates.dart';
import 'invoice_print_data.dart';
import 'layout_canvas.dart';
import 'layout_pdf_renderer.dart';

class _C {
  _C._();
  static const navy = DesignerColors.navy;
  static const blue = DesignerColors.blue;
  static const bg = DesignerColors.bg;
  static const border = DesignerColors.border;
  static const muted = DesignerColors.muted;
  static const text = DesignerColors.text;
  static const soft = DesignerColors.soft;
}

class InvoiceDesignerScreen extends StatefulWidget {
  const InvoiceDesignerScreen({super.key, this.initialPaper = LayoutPaper.a4, this.docKind = 'invoice'});
  final LayoutPaper initialPaper;

  /// 'invoice' = مصمم الفاتورة؛ نوع سند = مصمم ذلك السند (من «مصمم السندات»)
  final String docKind;

  @override
  State<InvoiceDesignerScreen> createState() => _InvoiceDesignerScreenState();
}

class _Tool {
  const _Tool(this.type, this.icon, this.color);
  final String type;
  final IconData icon;
  final Color color;
}

class _InvoiceDesignerScreenState extends State<InvoiceDesignerScreen> {
  bool _loading = true;
  List<InvoiceLayout> _layouts = [];
  final Map<String, String> _targets = {};
  late LayoutPaper _paper = widget.initialPaper;
  String? _curId;
  String? _sel;
  bool _dirty = false;

  /// ↩️ خطوات الرجوع: كل تنقّل بين التصاميم (اختيار نموذج جاهز، نسخة، فتح تصميم آخر)
  /// يُسجَّل، فزر الرجوع يعيد خطوة خطوة قبل أن يخرج من المصمم.
  final List<_ViewStep> _steps = [];
  double _zoom = 1.0;
  bool _grid = true;
  int _leftTab = 0; // 0 إضافة، 1 الطبقات
  PrintCompany _company = const PrintCompany(name: '');
  InvoicePrintData? _sampleCache;
  final List<String> _undo = [];
  final List<String> _redo = [];
  final FocusNode _canvasFocus = FocusNode();
  final ScrollController _vScroll = ScrollController();
  final ScrollController _hScroll = ScrollController();
  final GlobalKey _pageKey = GlobalKey();

  /// يعيد رسم الورقة وحدها أثناء السحب (أسلس من إعادة بناء الشاشة كلها)
  final ValueNotifier<int> _tick = ValueNotifier(0);
  double _scale = 3;

  static const _groups = <String, List<_Tool>>{
    'الهوية': [
      _Tool(ElType.logo, Icons.image_outlined, Color(0xFF7C3AED)),
      _Tool(ElType.companyName, Icons.title, Color(0xFF7C3AED)),
      _Tool(ElType.companyInfo, Icons.business_outlined, Color(0xFF7C3AED)),
    ],
    'البيانات والنصوص': [
      _Tool(ElType.field, Icons.badge_outlined, Color(0xFF0284C7)),
      _Tool(ElType.infoBox, Icons.contact_page_outlined, Color(0xFF0284C7)),
      _Tool(ElType.text, Icons.text_fields, Color(0xFF0284C7)),
    ],
    'الفاتورة': [
      _Tool(ElType.table, Icons.table_chart_outlined, Color(0xFF059669)),
      _Tool(ElType.totals, Icons.calculate_outlined, Color(0xFF059669)),
    ],
    'أشكال وإضافات': [
      _Tool(ElType.line, Icons.horizontal_rule, Color(0xFFEA580C)),
      _Tool(ElType.box, Icons.crop_square, Color(0xFFEA580C)),
      _Tool(ElType.barcode, Icons.qr_code_2, Color(0xFFEA580C)),
      _Tool(ElType.watermark, Icons.water_drop_outlined, Color(0xFFEA580C)),
      _Tool(ElType.pageNo, Icons.numbers, Color(0xFFEA580C)),
    ],
  };

  static IconData _iconOf(LayoutElement e) {
    if (e.type == ElType.totals && _isInfoBox(e)) return Icons.contact_page_outlined;
    for (final g in _groups.values) {
      for (final t in g) {
        if (t.type == e.type) return t.icon;
      }
    }
    return Icons.widgets_outlined;
  }

  static bool _isInfoBox(LayoutElement e) {
    final ks = e.strings('items');
    return ks.isNotEmpty && ks.every((k) => !LayoutRules.isTotal(k));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _canvasFocus.dispose();
    _vScroll.dispose();
    _hScroll.dispose();
    _tick.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final layouts = await InvoiceLayoutStore.loadAll();
    for (final t in PrintTarget.everything) {
      _targets[t.key] = await InvoiceLayoutStore.target(t.key);
    }
    PrintCompany company;
    try {
      company = await PrintCompany.load();
    } catch (_) {
      company = const PrintCompany(name: 'اسم الشركة');
    }
    if (!mounted) return;
    setState(() {
      _layouts = layouts;
      _company = company;
      _sampleCache = null;
      _loading = false;
      _pickFirst();
    });
  }

  // ─────────────────────────── الحالة ───────────────────────────

  /// 🧾 مصمم سند (لا فاتورة)
  bool get _isVoucher => widget.docKind != 'invoice';

  /// أنواع الطباعة التي يخدمها هذا المصمم
  List<PrintTarget> get _modeTargets => PrintTarget.forKind(widget.docKind);

  /// تصاميم هذا الورق ولهذا النوع فقط (تصاميم الفواتير لا تظهر في السندات والعكس)
  List<InvoiceLayout> get _forPaper =>
      _layouts.where((l) => l.paper == _paper && l.kind == widget.docKind).toList();

  InvoiceLayout? get _cur {
    for (final l in _layouts) {
      if (l.id == _curId) return l;
    }
    return null;
  }

  LayoutElement? get _selEl => _cur?.byId(_sel);

  void _pickFirst() {
    final list = _forPaper;
    _curId = list.isEmpty ? null : list.first.id;
    _sel = null;
  }

  InvoicePrintData get _sample => _sampleCache ??=
      _isVoucher ? InvoicePrintData.sampleVoucher(_company, widget.docKind) : InvoicePrintData.sample(_company);

  String _nameOf(LayoutElement e) {
    if (e.type == ElType.totals) {
      final t = e.s('title', '').trim();
      final kind = _isInfoBox(e) ? 'مربع بيانات' : 'مربع مجاميع';
      return t.isEmpty ? kind : '$kind: $t';
    }
    if (e.type == ElType.field) return 'حقل: ${LayoutCatalog.fields[e.s('key', '')] ?? ''}';
    if (e.type == ElType.text) {
      final t = e.s('text', '').replaceAll('\n', ' ');
      return 'نص: ${t.length > 16 ? '${t.substring(0, 16)}…' : t}';
    }
    return ElType.labels[e.type] ?? e.type;
  }

  void _snapshot() {
    final c = _cur;
    if (c == null) return;
    _undo.add(jsonEncode(c.toJson()));
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void _mutate(VoidCallback f) {
    _snapshot();
    setState(() {
      f();
      _dirty = true;
    });
  }

  void _restore(String json, List<String> pushTo) {
    final restored = InvoiceLayout.fromJson(jsonDecode(json) as Map<String, dynamic>);
    final i = _layouts.indexWhere((l) => l.id == restored.id);
    if (i < 0) return;
    pushTo.add(jsonEncode(_layouts[i].toJson()));
    setState(() {
      _layouts[i] = restored;
      _curId = restored.id;
      _paper = restored.paper;
      if (restored.byId(_sel) == null) _sel = null;
      _dirty = true;
    });
  }

  void _undoLast() {
    if (_undo.isNotEmpty) _restore(_undo.removeLast(), _redo);
  }

  void _redoLast() {
    if (_redo.isNotEmpty) _restore(_redo.removeLast(), _undo);
  }

  Future<void> _save({bool quiet = false}) async {
    try {
      await InvoiceLayoutStore.saveAll(_layouts);
      for (final s in _steps) {
        s.createdId = null;
      }
      if (!mounted) return;
      setState(() => _dirty = false);
      if (!quiet) _snack('حُفظت التصاميم', icon: Icons.check_circle, color: Colors.green.shade700);
    } catch (e) {
      _snack('تعذّر الحفظ: $e', color: Colors.red);
    }
  }

  void _snack(String m, {IconData? icon, Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      width: 460,
      backgroundColor: color ?? _C.text,
      content: Row(children: [
        if (icon != null) ...[Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 8)],
        Expanded(child: Text(m)),
      ]),
    ));
  }

  /// تعديلات غير محفوظة عند الرجوع: 'save' | 'discard' | null (البقاء).
  Future<String?> _askUnsaved() async {
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديلات غير محفوظة'),
        content: const Text('هل تحفظ تعديلات التصميم قبل الرجوع؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('البقاء هنا')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('تجاهل التعديلات')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('حفظ')),
        ],
      ),
    );
    return r == 'save' || r == 'discard' ? r : null;
  }

  /// يتجاهل كل ما لم يُحفظ: التصاميم تعود كما هي محفوظة.
  Future<void> _discardChanges() async {
    final saved = await InvoiceLayoutStore.loadAll();
    if (!mounted) return;
    setState(() {
      _layouts = saved;
      _dirty = false;
      _undo.clear();
      _redo.clear();
      _sel = null;
      _sampleCache = null;
    });
  }

  /// بعد الحفظ أو التجاهل: خطوة واحدة إلى الوراء بلا سؤال (true = بقي في المصمم).
  /// تصميم من «نموذج جاهز» تُجوهل ← تُفتح النماذج من جديد؛ وإلا يعود التصميم السابق.
  Future<bool> _stepBackResolved() async {
    while (_steps.isNotEmpty) {
      final s = _steps.removeLast();
      final created = s.createdId;
      final createdGone = created != null && !_layouts.any((l) => l.id == created);
      final prev = s.prevCurId;
      if (prev != null && !_layouts.any((l) => l.id == prev)) continue;
      if (prev == null && !createdGone) continue;
      setState(() {
        _curId = prev;
        _sel = null;
        if (_cur == null) _pickFirst();
      });
      if (createdGone && s.fromGallery) await _newFromGallery();
      return true;
    }
    return false;
  }

  // ─────────────────────────── التصاميم ───────────────────────────

  Future<void> _newFromGallery() async {
    final tpl = await showDialog<LayoutTemplate>(
      context: context,
      builder: (ctx) => _GalleryDialog(
        paper: _paper,
        kind: widget.docKind,
        data: _isVoucher
            ? InvoicePrintData.sampleVoucher(_company, widget.docKind)
            : InvoicePrintData.sample(_company, rows: 5),
      ),
    );
    if (tpl == null) return;
    final l = tpl.build().copy(id: InvoiceLayout.newId('L'));
    l.kind = widget.docKind; // 🧾 يبقى في مصممه (فاتورة أو هذا السند)
    var name = tpl.name;
    var n = 2;
    while (_layouts.any((x) => x.name == name)) {
      name = '${tpl.name} $n';
      n++;
    }
    l.name = name;
    final prevCur = _curId, prevDirty = _dirty;
    setState(() {
      _layouts.add(l);
      _curId = l.id;
      _sel = null;
      _dirty = true;
      _zoom = 1;
    });
    _steps.add(_ViewStep(
        prevCurId: prevCur, prevDirty: prevDirty, createdId: l.id, fromGallery: true, undoLen: _undo.length));
    _snack('أُنشئ «${l.name}». عدّله كما تريد، ثم احفظ وفعّل استعماله في الطباعة من لوحة التصميم.',
        icon: Icons.auto_awesome);
  }

  void _duplicate() {
    final c = _cur;
    if (c == null) return;
    final copy = c.copy(id: InvoiceLayout.newId('L'), name: '${c.name} (نسخة)');
    final prevCur = _curId, prevDirty = _dirty;
    setState(() {
      _layouts.add(copy);
      _curId = copy.id;
      _sel = null;
      _dirty = true;
    });
    _steps.add(_ViewStep(prevCurId: prevCur, prevDirty: prevDirty, createdId: copy.id, undoLen: _undo.length));
  }

  Future<void> _rename() async {
    final c = _cur;
    if (c == null) return;
    final ctl = TextEditingController(text: c.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسم التصميم'),
        content: TextField(controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('حفظ')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    _mutate(() => c.name = name.trim());
  }

  Future<void> _delete() async {
    final c = _cur;
    if (c == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف التصميم؟'),
        content: Text('سيُحذف «${c.name}». إن كان مستعملاً في الطباعة يعود البرنامج للتصميم الأصلي.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _layouts.removeWhere((l) => l.id == c.id);
      _pickFirst();
      _dirty = true;
    });
    for (final t in PrintTarget.everything) {
      if (_targets[t.key] == c.id) {
        _targets[t.key] = '';
        await InvoiceLayoutStore.setTarget(t.key, '');
      }
    }
    await _save(quiet: true);
  }

  /// 🖨️ ما يُطبع الآن لكل نوع طباعة: التصميم الأصلي للبرنامج أو أحد التصاميم.
  /// الرجوع للتصميم الأصلي بضغطة واحدة في أي وقت.
  Future<void> _openPrintChoices() async {
    if (_dirty) await _save(quiet: true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('ما يُطبع الآن'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final t in _modeTargets) ...[
                    Text(t.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(t.hint, style: const TextStyle(fontSize: 11.5, color: _C.muted)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      key: ValueKey('print_target_${t.key}_${_targets[t.key] ?? ''}'),
                      initialValue: _layouts.any((l) => l.id == _targets[t.key] && t.accepts(l))
                          ? _targets[t.key]
                          : '',
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('التصميم الأصلي للبرنامج')),
                        for (final l in _layouts.where(t.accepts))
                          DropdownMenuItem(value: l.id, child: Text(l.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) async {
                        final id = v ?? '';
                        await InvoiceLayoutStore.setTarget(t.key, id);
                        if (!mounted) return;
                        setState(() => _targets[t.key] = id);
                        setLocal(() {});
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تم')),
          ],
        ),
      ),
    );
  }

  /// تفعيل/إيقاف استعمال هذا التصميم لنوع طباعة
  Future<void> _setUse(PrintTarget t, InvoiceLayout l, bool on) async {
    if (on && _dirty) await _save(quiet: true);
    await InvoiceLayoutStore.setTarget(t.key, on ? l.id : '');
    if (!mounted) return;
    setState(() => _targets[t.key] = on ? l.id : '');
    _snack(on ? '«${l.name}» يُطبع الآن في: ${t.label}' : 'عاد «${t.label}» للتصميم الأصلي',
        icon: Icons.print, color: on ? Colors.green.shade700 : null);
  }

  Future<void> _previewPdf() async {
    final c = _cur;
    if (c == null) return;
    final data = _sample;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 920,
          height: MediaQuery.of(ctx).size.height * 0.9,
          child: Column(children: [
            Container(
              color: _C.navy,
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(children: [
                const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('معاينة «${c.name}» ببيانات تجريبية — هكذا تُطبع',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                    icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
            Expanded(
              child: PdfPreview(
                // 🔢 السندات: المعاينة كالطباعة (رقم السند يُضاف إن لم يكن في التصميم)
                build: (_) async =>
                    (await (_isVoucher ? VoucherPrint.renderVoucher(c, data) : LayoutPdfRenderer.render(c, data))).save(),
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
                pdfFileName: 'معاينة_${c.name}.pdf',
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _openCompanySettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const InvoiceDesignScreen(fromDesigner: true)));
    try {
      final company = await PrintCompany.load();
      if (mounted) {
        setState(() {
          _company = company;
          _sampleCache = null;
        });
      }
    } catch (_) {}
  }

  // ─────────────────────────── العناصر ───────────────────────────

  void _addElement(String type, {double? x, double? y}) {
    final c = _cur;
    if (c == null) return;
    if (type == ElType.table && c.table != null) {
      _snack('في التصميم جدول مواد واحد — حدّدته لك لتعديله.', icon: Icons.info_outline);
      setState(() => _sel = c.table!.id);
      return;
    }
    final e = InvoiceLayoutTemplates.newElement(type, c, x: x, y: y ?? math.min(20, c.heightMm - 20));
    // لا يخرج عن الورقة
    e.x = e.x.clamp(0, math.max(0, c.widthMm - e.w)).toDouble();
    e.y = e.y.clamp(0, math.max(0, c.heightMm - e.h)).toDouble();
    _mutate(() {
      c.elements.add(e);
      _sel = e.id;
    });
    _canvasFocus.requestFocus();
  }

  /// 🧾 بيانات السند الجاهزة لنوعه: (المفتاح، الاسم على الورقة، مبلغ؟)
  List<(String, String, bool)> get _voucherItems {
    final k = widget.docKind;
    final receipt = k == 'receipt';
    final cash = k == 'cash_receipt' || k == 'cash_refund';
    final party = k == 'cash_refund' ? 'المستلم' : (receipt || k == 'cash_receipt' ? 'الدافع' : 'العميل');
    return [
      ('voucherTitle', 'عنوان السند', false),
      ('voucherNo', receipt ? 'رقم سند القبض' : 'رقم السند', false),
      ('customer', 'السيد', false),
      ('customer', party, false),
      ('dateTime', 'التاريخ والوقت', false),
      ('date', 'التاريخ', false),
      ('phone', 'الهاتف', false),
      if (receipt) ('boxName', 'الصندوق', false),
      if (receipt) ('docNo', 'رقم المستند', false),
      if (!receipt) ('invoiceNo', 'الفاتورة الأصلية', false),
      if (!receipt) ('paymentType', 'طريقة الدفع', false),
      ('voucherReason', 'البيان', false),
      ('voucherAmount', receipt ? 'المبلغ المقبوض' : (cash ? 'المبلغ نقداً' : 'مبلغ الإشعار'), true),
      if (receipt || !cash) ('previousDebt', receipt ? 'الرصيد قبل التسديد' : 'الرصيد قبل الإشعار', true),
      if (receipt || !cash) ('currentDebt', receipt ? 'الرصيد بعد التسديد' : 'الرصيد بعد الإشعار', true),
      if (receipt) ('discount', 'الخصم', true),
      if (!receipt) ('invoiceBefore', 'الفاتورة قبل', true),
      if (!receipt) ('invoiceAfter', 'الفاتورة بعد', true),
      ('amountWords', 'المبلغ كتابةً', false),
      ('accountant', 'المحاسب', false),
      ('printedAt', 'وقت الطباعة', false),
      ('printedBy', 'طُبع بواسطة', false),
    ];
  }

  /// يضيف حقلاً (نص) أو مبلغاً (مربع) من بيانات السند إلى الورقة.
  void _addDataItem(String key, String label, bool money) {
    final c = _cur;
    if (c == null) return;
    final e = InvoiceLayoutTemplates.newElement(money ? ElType.totals : ElType.field, c,
        y: math.min(20, c.heightMm - 20));
    if (money) {
      e.props
        ..['items'] = [key]
        ..['labels'] = {key: label}
        ..['highlight'] = key
        ..['boxMode'] = 'group'
        ..['style'] = 'list';
      e.w = 80;
      e.h = 10;
    } else {
      e.props
        ..['key'] = key
        ..['label'] = label;
      e.w = key == 'amountWords' || key == 'voucherReason' ? 150 : 70;
    }
    e.x = e.x.clamp(0, math.max(0, c.widthMm - e.w)).toDouble();
    e.y = e.y.clamp(0, math.max(0, c.heightMm - e.h)).toDouble();
    _mutate(() {
      c.elements.add(e);
      _sel = e.id;
    });
    _canvasFocus.requestFocus();
  }

  void _deleteSelected() {
    final c = _cur;
    final e = _selEl;
    if (c == null || e == null) return;
    _mutate(() {
      c.elements.removeWhere((x) => x.id == e.id);
      _sel = null;
    });
  }

  void _duplicateSelected() {
    final c = _cur;
    final e = _selEl;
    if (c == null || e == null) return;
    if (e.type == ElType.table) {
      _snack('جدول المواد واحد فقط في التصميم', icon: Icons.info_outline);
      return;
    }
    final copy = e.copy(id: InvoiceLayout.newId('e'))
      ..x = e.x + 3
      ..y = e.y + 3;
    _mutate(() {
      c.elements.add(copy);
      _sel = copy.id;
    });
  }

  void _zOrder(bool front) {
    final c = _cur;
    final e = _selEl;
    if (c == null || e == null) return;
    _mutate(() {
      c.elements.remove(e);
      if (front) {
        c.elements.add(e);
      } else {
        c.elements.insert(0, e);
      }
    });
  }

  void _moveBy(double dx, double dy) {
    final e = _selEl;
    if (e == null) return;
    _mutate(() {
      e.x = _r(e.x + dx);
      e.y = _r(e.y + dy);
    });
  }

  static double _r(double v) => (v * 2).roundToDouble() / 2; // نصف ملم

  KeyEventResult _onKey(FocusNode node, KeyEvent ev) {
    if (ev is! KeyDownEvent && ev is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = ev.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final step = HardwareKeyboard.instance.isShiftPressed ? 5.0 : 0.5;
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      HardwareKeyboard.instance.isShiftPressed ? _redoLast() : _undoLast();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyY) {
      _redoLast();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyS) {
      _save();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyD) {
      _duplicateSelected();
      return KeyEventResult.handled;
    }
    if (_selEl == null) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      _deleteSelected();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _moveBy(-step, 0);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _moveBy(step, 0);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _moveBy(0, -step);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _moveBy(0, step);
    } else if (k == LogicalKeyboardKey.escape) {
      setState(() => _sel = null);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ─────────────────────────── الرجوع خطوة خطوة ───────────────────────────

  void _switchTo(String id) {
    if (id == _curId) return;
    _steps.add(_ViewStep(prevCurId: _curId, prevDirty: _dirty, undoLen: _undo.length));
    setState(() {
      _curId = id;
      _sel = null;
    });
  }

  /// خطوة واحدة إلى الوراء. true = رجع خطوة (لا خروج).
  /// 1) عنصر محدد ← يُلغى تحديده.
  /// 2) تصميم من «نموذج جاهز» لم يُعدَّل ولم يُحفظ ← يُزال وتُفتح النماذج من جديد.
  /// 3) تصميم آخر فُتح ← يعود التصميم السابق.
  /// تصميم جديد عُدّل ← لا رجوع صامت: الخروج يسأل عن الحفظ كالمعتاد.
  Future<bool> _stepBack() async {
    if (_sel != null) {
      setState(() => _sel = null);
      return true;
    }
    while (_steps.isNotEmpty) {
      final s = _steps.removeLast();
      final created = s.createdId;
      final untouched = created != null && _curId == created && _undo.length == s.undoLen;
      if (created != null && !untouched) {
        // تصميم جديد عُدّل: يُسأل عن الحفظ أولاً، والخطوة تبقى ليرجع إليها بعده
        _steps.add(s);
        return false;
      }
      final prev = s.prevCurId;
      if (prev != null && !_layouts.any((l) => l.id == prev)) continue;
      setState(() {
        if (untouched) {
          _layouts.removeWhere((l) => l.id == created);
          _dirty = s.prevDirty;
        }
        _curId = prev;
        _sel = null;
      });
      if (untouched && s.fromGallery) await _newFromGallery();
      return true;
    }
    return false;
  }

  // ─────────────────────────── البناء ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty && _sel == null && _steps.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _stepBack()) return;
        if (_dirty) {
          final r = await _askUnsaved();
          if (r == null) return;
          if (r == 'save') {
            await _save(quiet: true);
            if (_dirty) return; // تعذّر الحفظ: نبقى
          } else {
            await _discardChanges();
          }
          // ↩️ خطوة إلى الوراء إن وُجدت (النماذج الجاهزة أو التصميم السابق)، وإلا خروج
          if (await _stepBackResolved()) return;
        }
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: _C.bg,
        appBar: _appBar(),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                _subToolbar(),
                Expanded(
                  child: LayoutBuilder(builder: (context, box) {
                    if (box.maxWidth >= 1100) {
                      return Row(children: [
                        SizedBox(width: 250, child: _leftPanel()),
                        Expanded(child: _canvasArea()),
                        SizedBox(width: 340, child: _propsPanel()),
                      ]);
                    }
                    return Column(children: [
                      SizedBox(height: 92, child: _toolsStrip()),
                      Expanded(child: _canvasArea()),
                      SizedBox(height: box.maxHeight * 0.4, child: _propsPanel()),
                    ]);
                  }),
                ),
                _statusBar(),
              ]),
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    final cur = _cur;
    return AppBar(
      backgroundColor: _C.navy,
      foregroundColor: Colors.white,
      titleSpacing: 8,
      title: Row(children: [
        const Icon(Icons.design_services_outlined),
        const SizedBox(width: 10),
        Text(_isVoucher ? 'مصمم السندات — ${VoucherKinds.label(widget.docKind)}' : 'مصمم الفاتورة',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        if (cur != null) ...[
          const SizedBox(width: 14),
          Flexible(
            child: InkWell(
              onTap: _rename,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(cur.name,
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Colors.white)),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.edit, size: 14, color: Colors.white70),
                ]),
              ),
            ),
          ),
        ],
      ]),
      actions: [
        IconButton(
          tooltip: 'تراجع (Ctrl+Z)',
          onPressed: _undo.isEmpty ? null : _undoLast,
          icon: const Icon(Icons.undo),
          disabledColor: Colors.white30,
        ),
        IconButton(
          tooltip: 'إعادة (Ctrl+Y)',
          onPressed: _redo.isEmpty ? null : _redoLast,
          icon: const Icon(Icons.redo),
          disabledColor: Colors.white30,
        ),
        const SizedBox(width: 6),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          onPressed: _openPrintChoices,
          icon: const Icon(Icons.print_outlined),
          label: const Text('ما يُطبع الآن'),
        ),
        const SizedBox(width: 6),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          onPressed: cur == null ? null : _previewPdf,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('معاينة الطباعة'),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _dirty ? Colors.white : Colors.white24,
            foregroundColor: _dirty ? _C.navy : Colors.white,
            disabledBackgroundColor: Colors.white24,
            disabledForegroundColor: Colors.white,
          ),
          onPressed: _dirty ? _save : null,
          icon: Icon(_dirty ? Icons.save : Icons.check),
          label: Text(_dirty ? 'حفظ' : 'محفوظ'),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _subToolbar() {
    final list = _forPaper;
    return Material(
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          // نوع الورق
          for (final p in _isVoucher ? const [LayoutPaper.a4] : LayoutPaper.values) ...[
            _PaperTab(
              label: p.shortLabel,
              sub: _isVoucher ? 'سند' : (p == LayoutPaper.a4 ? 'فاتورة كبيرة' : 'إيصال'),
              icon: p.isRoll ? Icons.receipt_long : Icons.description_outlined,
              selected: _paper == p,
              onTap: () => setState(() {
                _paper = p;
                _pickFirst();
                _zoom = 1;
              }),
            ),
            const SizedBox(width: 6),
          ],
          const SizedBox(width: 8),
          Container(width: 1, height: 34, color: _C.border),
          const SizedBox(width: 12),
          const Text('تصاميمي:', style: TextStyle(color: _C.muted, fontSize: 12.5)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final l in list) ...[
                  _DesignChip(
                    name: l.name,
                    selected: l.id == _curId,
                    used: _targets.values.contains(l.id),
                    onTap: () => _switchTo(l.id),
                  ),
                  const SizedBox(width: 6),
                ],
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18, color: _C.blue),
                  label: const Text('تصميم جديد'),
                  side: const BorderSide(color: _C.blue),
                  backgroundColor: Colors.white,
                  onPressed: _newFromGallery,
                ),
              ]),
            ),
          ),
          if (_cur != null) ...[
            const SizedBox(width: 8),
            _zoomBox(),
            const SizedBox(width: 4),
            IconToggle(
              icon: _grid ? Icons.grid_on : Icons.grid_off,
              on: _grid,
              tooltip: 'شبكة مساعدة كل 5 ملم',
              onTap: () => setState(() => _grid = !_grid),
            ),
            PopupMenuButton<String>(
              tooltip: 'المزيد',
              icon: const Icon(Icons.more_vert, color: _C.muted),
              onSelected: (v) {
                switch (v) {
                  case 'rename':
                    _rename();
                    break;
                  case 'dup':
                    _duplicate();
                    break;
                  case 'company':
                    _openCompanySettings();
                    break;
                  case 'delete':
                    _delete();
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.drive_file_rename_outline), title: Text('إعادة تسمية'))),
                PopupMenuItem(value: 'dup', child: ListTile(leading: Icon(Icons.copy_all_outlined), title: Text('نسخة من التصميم'))),
                PopupMenuItem(value: 'company', child: ListTile(leading: Icon(Icons.business_outlined), title: Text('معلومات الشركة والشعار'))),
                PopupMenuDivider(),
                PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                        leading: Icon(Icons.delete_outline, color: Colors.red),
                        title: Text('حذف التصميم', style: TextStyle(color: Colors.red)))),
              ],
            ),
          ],
        ]),
      ),
    );
  }

  Widget _zoomBox() => Container(
        height: 34,
        decoration: BoxDecoration(border: Border.all(color: _C.border), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            tooltip: 'تصغير',
            onPressed: () => setState(() => _zoom = math.max(0.3, _zoom - 0.1)),
            icon: const Icon(Icons.remove),
          ),
          InkWell(
            onTap: () => setState(() => _zoom = 1),
            child: Tooltip(
              message: 'ملاءمة الشاشة',
              child: SizedBox(
                width: 46,
                child: Text('${(_zoom * 100).round()}%',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            tooltip: 'تكبير (أو Ctrl + عجلة الفأرة)',
            onPressed: () => setState(() => _zoom = math.min(3, _zoom + 0.1)),
            icon: const Icon(Icons.add),
          ),
        ]),
      );

  // ── القائمة اليمنى: إضافة العناصر والطبقات ──

  Widget _leftPanel() {
    final cur = _cur;
    return Material(
      color: Colors.white,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              const ButtonSegment(value: 0, icon: Icon(Icons.add_box_outlined, size: 18), label: Text('إضافة')),
              ButtonSegment(
                  value: 1,
                  icon: const Icon(Icons.layers_outlined, size: 18),
                  label: Text('الطبقات${cur == null ? '' : ' (${cur.elements.length})'}')),
            ],
            selected: {_leftTab},
            onSelectionChanged: (s) => setState(() => _leftTab = s.first),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: cur == null ? const SizedBox() : (_leftTab == 0 ? _toolsGrid(cur) : _layers(cur))),
      ]),
    );
  }

  Widget _toolTile(_Tool t, InvoiceLayout cur) {
    final label = ElType.labels[t.type] ?? t.type;
    final tile = ToolTile(icon: t.icon, label: label, color: t.color, onTap: () => _addElement(t.type));
    return Draggable<String>(
      data: t.type,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: t.color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(t.icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }

  Widget _toolsGrid(InvoiceLayout cur) {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [
            Icon(Icons.touch_app_outlined, size: 18, color: _C.blue),
            SizedBox(width: 8),
            Expanded(
              child: Text('اسحب العنصر إلى الورقة، أو اضغطه ليُضاف.',
                  style: TextStyle(fontSize: 12, color: _C.navy, height: 1.4)),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        // 🧾 بيانات السند: اضغط لتُضاف (تُملأ تلقائياً عند الطباعة)
        if (_isVoucher) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text('بيانات السند — اضغط لتُضاف',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: _C.muted)),
          ),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final it in _voucherItems)
              ActionChip(
                avatar: Icon(it.$3 ? Icons.payments_outlined : Icons.short_text_rounded, size: 16, color: _C.blue),
                label: Text(it.$2, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: _C.blue.withValues(alpha: 0.35)),
                backgroundColor: _C.blue.withValues(alpha: 0.05),
                onPressed: () => _addDataItem(it.$1, it.$2, it.$3),
              ),
          ]),
        ],
        for (final g in _groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(g.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: _C.muted)),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.05,
            children: [
              for (final t in g.value)
                if (t.type != ElType.pageNo || !cur.paper.isRoll) _toolTile(t, cur),
            ],
          ),
        ],
      ],
    );
  }

  Widget _toolsStrip() {
    final cur = _cur;
    if (cur == null) return const SizedBox();
    final tools = [for (final g in _groups.values) ...g].where((t) => t.type != ElType.pageNo || !cur.paper.isRoll).toList();
    return Material(
      color: Colors.white,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        itemCount: tools.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => SizedBox(width: 92, child: _toolTile(tools[i], cur)),
      ),
    );
  }

  Widget _layers(InvoiceLayout cur) {
    final list = cur.elements.reversed.toList(); // الأعلى أولاً
    if (list.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('الورقة فارغة — أضف عناصر من «إضافة».', textAlign: TextAlign.center)));
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(8),
      buildDefaultDragHandles: false,
      itemCount: list.length,
      onReorderItem: (a, b) {
        _mutate(() {
          final moved = list.removeAt(a);
          list.insert(b, moved);
          cur.elements = list.reversed.toList();
        });
      },
      itemBuilder: (_, i) {
        final e = list[i];
        final sel = e.id == _sel;
        return Container(
          key: ValueKey('ly_${e.id}'),
          margin: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: sel ? _C.blue.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                _canvasFocus.requestFocus();
                setState(() => _sel = e.id);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Row(children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: const MouseRegion(
                        cursor: SystemMouseCursors.grab, child: Icon(Icons.drag_indicator, size: 18, color: _C.muted)),
                  ),
                  const SizedBox(width: 6),
                  Icon(_iconOf(e), size: 18, color: sel ? _C.blue : _C.navy),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_nameOf(e),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── الورقة ──

  Widget _canvasArea() {
    final cur = _cur;
    if (cur == null) return _emptyState();
    return LayoutBuilder(builder: (context, box) {
      final fit = math.max(1.0, (box.maxWidth - 80) / cur.widthMm);
      final cap = cur.paper.isRoll ? 7.0 : 4.2;
      final s = math.min(fit, cap) * _zoom;
      _scale = s;
      final w = cur.widthMm * s;
      final h = cur.heightMm * s;
      final sel = _selEl;
      return Stack(children: [
        Positioned.fill(
          child: Listener(
            onPointerSignal: (ev) {
              if (ev is PointerScrollEvent && HardwareKeyboard.instance.isControlPressed) {
                setState(() => _zoom = (_zoom - ev.scrollDelta.dy / 800).clamp(0.3, 3.0).toDouble());
              }
            },
            child: Focus(
              focusNode: _canvasFocus,
              onKeyEvent: _onKey,
              child: Scrollbar(
                controller: _vScroll,
                child: SingleChildScrollView(
                  controller: _vScroll,
                  padding: const EdgeInsets.fromLTRB(40, 64, 40, 40),
                  child: Center(
                    child: Scrollbar(
                      controller: _hScroll,
                      child: SingleChildScrollView(
                        controller: _hScroll,
                        scrollDirection: Axis.horizontal,
                        child: DragTarget<String>(
                          onAcceptWithDetails: (d) {
                            final rb = _pageKey.currentContext?.findRenderObject() as RenderBox?;
                            if (rb == null) return _addElement(d.data);
                            final local = rb.globalToLocal(d.offset);
                            _addElement(d.data, x: _r(local.dx / _scale), y: _r(local.dy / _scale));
                          },
                          builder: (context, cand, _) => AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            key: _pageKey,
                            width: w,
                            height: h,
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: cand.isNotEmpty
                                      ? _C.blue.withValues(alpha: 0.45)
                                      : Colors.black.withValues(alpha: 0.16),
                                  blurRadius: cand.isNotEmpty ? 22 : 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ValueListenableBuilder<int>(
                              valueListenable: _tick,
                              builder: (_, __, ___) => LayoutCanvas(
                                layout: cur,
                                data: _sample,
                                scale: s,
                                selectedId: _sel,
                                interactive: true,
                                showGrid: _grid,
                                labelOf: _nameOf,
                                onSelect: (id) {
                                  _canvasFocus.requestFocus();
                                  if (id != _sel) setState(() => _sel = id);
                                },
                                onDragStart: (_) => _snapshot(),
                                onMove: (id, dx, dy) {
                                  final e = cur.byId(id);
                                  if (e == null) return;
                                  e.x = (e.x + dx).clamp(-e.w + 2, cur.widthMm - 2).toDouble();
                                  e.y = (e.y + dy).clamp(-e.h + 1, cur.heightMm - 1).toDouble();
                                  _dirty = true;
                                  _tick.value++;
                                },
                                onResize: (id, corner, dx, dy) {
                                  final e = cur.byId(id);
                                  if (e == null) return;
                                  final minH = e.type == ElType.line ? 0.5 : 2.0;
                                  if (corner.endsWith('l')) {
                                    final nw = math.max(2.0, e.w - dx);
                                    e.x += e.w - nw;
                                    e.w = nw;
                                  } else {
                                    e.w = math.max(2.0, e.w + dx);
                                  }
                                  if (corner.startsWith('t')) {
                                    final nh = math.max(minH, e.h - dy);
                                    e.y += e.h - nh;
                                    e.h = nh;
                                  } else {
                                    e.h = math.max(minH, e.h + dy);
                                  }
                                  _dirty = true;
                                  _tick.value++;
                                },
                                onDragEnd: () {
                                  final e = _selEl;
                                  if (e == null) return;
                                  setState(() {
                                    e.x = _r(e.x);
                                    e.y = _r(e.y);
                                    e.w = math.max(1, _r(e.w));
                                    e.h = math.max(0.5, _r(e.h));
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // شريط إجراءات العنصر المحدد
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: sel == null
                  ? _hintPill('اضغط أي عنصر على الورقة لتعديله')
                  : _selectionBar(cur, sel),
            ),
          ),
        ),
      ]);
    });
  }

  Widget _hintPill(String text) => Container(
        key: const ValueKey('hint'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _C.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.touch_app_outlined, size: 16, color: _C.muted),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12.5, color: _C.muted)),
        ]),
      );

  Widget _selectionBar(InvoiceLayout c, LayoutElement e) {
    Widget act(IconData i, String tip, VoidCallback f, {Color? color}) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          iconSize: 19,
          onPressed: f,
          icon: Icon(i, color: color ?? _C.text),
        );
    return Material(
      key: ValueKey('bar_${e.id}'),
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 4),
          Icon(_iconOf(e), size: 18, color: _C.blue),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(_nameOf(e),
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 6),
          Container(width: 1, height: 22, color: _C.border),
          if (e.type != ElType.table) act(Icons.copy_outlined, 'نسخ (Ctrl+D)', _duplicateSelected),
          act(Icons.format_align_center, 'توسيط أفقي في الورقة',
              () => _mutate(() => e.x = _r((c.widthMm - e.w) / 2))),
          act(Icons.swap_horiz, 'بعرض الورقة', () {
            _mutate(() {
              e.x = c.paper.isRoll ? 1 : 8;
              e.w = c.widthMm - 2 * e.x;
            });
          }),
          act(Icons.flip_to_front, 'إلى الأمام', () => _zOrder(true)),
          act(Icons.flip_to_back, 'إلى الخلف', () => _zOrder(false)),
          Container(width: 1, height: 22, color: _C.border),
          act(Icons.delete_outline, 'حذف (Delete)', _deleteSelected, color: Colors.red),
          act(Icons.close, 'إلغاء التحديد (Esc)', () => setState(() => _sel = null), color: _C.muted),
        ]),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _C.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 18)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: _C.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(_paper.isRoll ? Icons.receipt_long : Icons.description_outlined, size: 36, color: _C.blue),
          ),
          const SizedBox(height: 14),
          Text('لا يوجد تصميم ${_paper.shortLabel} بعد',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _C.text)),
          const SizedBox(height: 6),
          const Text(
            'ابدأ من نموذج جاهز يشبه الفواتير المعروفة، أو من ورقة بيضاء، ثم عدّل كل شيء بالسحب.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _C.muted, height: 1.5),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _C.navy,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            ),
            onPressed: _newFromGallery,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('اختر نموذجاً أو ورقة بيضاء'),
          ),
        ]),
      ),
    );
  }

  Widget _statusBar() {
    final e = _selEl;
    String f(double v) => v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _C.border))),
      child: Row(children: [
        const Icon(Icons.keyboard_outlined, size: 15, color: _C.muted),
        const SizedBox(width: 6),
        const Expanded(
          child: Text(
            'سحب: تحريك • الزوايا: الحجم • الأسهم: تحريك دقيق (Shift أسرع) • Ctrl+Z تراجع • Ctrl+D نسخ • Delete حذف • Ctrl+عجلة: تكبير',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: _C.muted),
          ),
        ),
        if (e != null)
          Text('الموضع ${f(e.x)}، ${f(e.y)} — الحجم ${f(e.w)} × ${f(e.h)} ملم',
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontSize: 11.5, color: _C.navy, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ─────────────────────────── الخصائص ───────────────────────────

  Widget _propsPanel() {
    final cur = _cur;
    final e = _selEl;
    return Material(
      color: const Color(0xFFF8FAFC),
      child: cur == null
          ? const SizedBox()
          : ListView(
              padding: const EdgeInsets.all(12),
              children: e == null ? _layoutProps(cur) : _elementProps(cur, e),
            ),
    );
  }

  Widget _panelHeader(IconData icon, String title, String subtitle, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: _C.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: _C.blue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _C.text)),
              Text(subtitle, style: const TextStyle(fontSize: 11.5, color: _C.muted)),
            ]),
          ),
          if (trailing != null) trailing,
        ]),
      );

  List<Widget> _layoutProps(InvoiceLayout c) => [
        _panelHeader(c.paper.isRoll ? Icons.receipt_long : Icons.description_outlined, c.name,
            'التصميم كله — ${c.paper.label}'),
        PropSection('الاستعمال في الطباعة', icon: Icons.print_outlined, children: [
          const Text('فعّل ليُطبع بهذا التصميم بدل تصميم البرنامج الأصلي:',
              style: TextStyle(fontSize: 12, color: _C.muted)),
          for (final t in _modeTargets.where((t) => t.accepts(c)))
            SwitchRow(
              title: t.label,
              subtitle: t.hint,
              value: _targets[t.key] == c.id,
              onChanged: (v) => _setUse(t, c, v),
            ),
        ]),
        PropSection('إعدادات التصميم', icon: Icons.tune, children: [
          SwitchRow(
            title: 'أبيض وأسود',
            subtitle: 'للطابعة بلا ألوان: كل الألوان تُطبع بتدرّج الرمادي (والمعاينة كذلك)',
            value: c.mono,
            onChanged: (v) => _mutate(() => c.mono = v),
          ),
          SyncedField(
            label: 'اسم التصميم',
            value: c.name,
            onChanged: (v) => setState(() {
              c.name = v;
              _dirty = true;
            }),
          ),
          if (c.paper.isRoll)
            MiniNum(
              label: 'طول التصميم',
              suffix: 'ملم',
              value: c.heightMm,
              step: 5,
              min: 40,
              max: 1000,
              onChanged: (v) => _mutate(() => c.heightMm = v),
            ),
          OutlinedButton.icon(
            onPressed: _openCompanySettings,
            icon: const Icon(Icons.business_outlined, size: 18),
            label: const Text('معلومات الشركة والشعار'),
          ),
        ]),
        PropSection('كيف تعمل', icon: Icons.lightbulb_outline, children: [
          _step(1, 'اسحب العناصر من القائمة إلى الورقة، أو اضغطها لتُضاف.'),
          _step(2, 'حرّك أي عنصر بالسحب، وغيّر حجمه من الزوايا الزرقاء.'),
          _step(3, 'اضغط العنصر لتظهر خصائصه هنا: الخط والألوان والمربعات والأعمدة.'),
          _step(4, c.paper.isRoll
              ? 'الإيصال يطول ويقصر مع عدد المواد، وكل ما تحت الجدول ينزل معه.'
              : 'المواد بقدر ارتفاع الجدول في الصفحة، والزائد في صفحة جديدة؛ ما تحت الجدول في الصفحة الأخيرة.'),
          _step(5, 'جرّب «معاينة الطباعة»، ثم احفظ وفعّل الاستعمال أعلاه.'),
        ]),
      ];

  Widget _step(int n, String text) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: _C.navy, shape: BoxShape.circle),
          child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.45, color: _C.text))),
      ]);

  List<Widget> _elementProps(InvoiceLayout c, LayoutElement e) {
    void set(String k, Object? v) => _mutate(() => e.props[k] = v);
    final textual = {
      ElType.companyName,
      ElType.companyInfo,
      ElType.text,
      ElType.field,
      ElType.pageNo,
    }.contains(e.type);
    final tableEl = c.table;
    final belowTable = tableEl != null && e.type != ElType.table && e.y >= tableEl.y + tableEl.h - 0.5;

    return [
      _panelHeader(
        _iconOf(e),
        _nameOf(e),
        'العنصر المحدد',
        trailing: IconButton(
          tooltip: 'رجوع لإعدادات التصميم',
          onPressed: () => setState(() => _sel = null),
          icon: const Icon(Icons.close, color: _C.muted),
        ),
      ),
      ..._typeProps(c, e, set),
      if (textual) ...[
        PropSection('النص', icon: Icons.text_format, children: [
          Row(children: [
            Expanded(
              child: MiniNum(
                  label: 'حجم الخط',
                  value: e.d('fontSize', 10),
                  step: 0.5,
                  min: 4,
                  max: 120,
                  onChanged: (v) => set('fontSize', v)),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: IconToggle(
                icon: Icons.format_bold,
                on: e.b('bold', false),
                tooltip: 'عريض',
                onTap: () => set('bold', !e.b('bold', false)),
              ),
            ),
          ]),
          _alignRow(e.s('align', 'right'), (v) => set('align', v)),
          ColorRow(label: 'لون النص', value: e.i('color', 0xFF000000), onChanged: (v) => set('color', v)),
        ]),
        PropSection('الإطار والخلفية', icon: Icons.border_outer, initiallyOpen: false, children: [
          Row(children: [
            Expanded(
              child: MiniNum(
                  label: 'سُمك الإطار',
                  value: e.d('border', 0),
                  step: 0.2,
                  min: 0,
                  max: 5,
                  onChanged: (v) => set('border', v)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MiniNum(
                  label: 'استدارة الزوايا',
                  value: e.d('radius', 0),
                  step: 0.5,
                  min: 0,
                  max: 20,
                  onChanged: (v) => set('radius', v)),
            ),
          ]),
          if (e.d('border', 0) > 0)
            ColorRow(label: 'لون الإطار', value: e.i('borderColor', 0xFF000000), onChanged: (v) => set('borderColor', v)),
          ColorRow(label: 'الخلفية', value: e.i('bg', 0), allowNone: true, onChanged: (v) => set('bg', v)),
        ]),
      ],
      PropSection('الموضع والحجم', icon: Icons.open_with, initiallyOpen: false, children: [
        Row(children: [
          Expanded(
              child: MiniNum(label: 'من اليسار', suffix: 'ملم', value: e.x, step: 0.5, onChanged: (v) => _mutate(() => e.x = v))),
          const SizedBox(width: 8),
          Expanded(
              child: MiniNum(label: 'من الأعلى', suffix: 'ملم', value: e.y, step: 0.5, onChanged: (v) => _mutate(() => e.y = v))),
        ]),
        Row(children: [
          Expanded(
              child: MiniNum(
                  label: 'العرض',
                  suffix: 'ملم',
                  value: e.w,
                  step: 0.5,
                  min: 1,
                  max: 1000,
                  onChanged: (v) => _mutate(() => e.w = v))),
          const SizedBox(width: 8),
          Expanded(
              child: MiniNum(
                  label: 'الارتفاع',
                  suffix: 'ملم',
                  value: e.h,
                  step: 0.5,
                  min: 0.5,
                  max: 1000,
                  onChanged: (v) => _mutate(() => e.h = v))),
        ]),
        if (belowTable && !c.paper.isRoll)
          SwitchRow(
            title: 'يظهر في كل صفحة',
            subtitle: 'وإلا في الصفحة الأخيرة فقط (لأنه تحت الجدول)',
            value: e.b('everyPage', false),
            onChanged: (v) => set('everyPage', v),
          ),
      ]),
    ];
  }

  Widget _alignRow(String value, ValueChanged<String> onChanged) => Row(children: [
        const Expanded(child: Text('المحاذاة', style: TextStyle(fontSize: 12, color: _C.muted))),
        IconToggle(icon: Icons.format_align_right, on: value == 'right', tooltip: 'يمين', onTap: () => onChanged('right')),
        const SizedBox(width: 4),
        IconToggle(icon: Icons.format_align_center, on: value == 'center', tooltip: 'وسط', onTap: () => onChanged('center')),
        const SizedBox(width: 4),
        IconToggle(icon: Icons.format_align_left, on: value == 'left', tooltip: 'يسار', onTap: () => onChanged('left')),
      ]);

  Widget _dropdown<T>(String label, T value, List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged) =>
      DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _C.border),
          ),
        ),
        items: items,
        onChanged: onChanged,
      );

  List<Widget> _typeProps(InvoiceLayout c, LayoutElement e, void Function(String, Object?) set) {
    switch (e.type) {
      case ElType.text:
        return [
          PropSection('المحتوى', icon: Icons.edit_note, children: [
            SyncedField(
              value: e.s('text', ''),
              maxLines: 3,
              hint: 'اكتب النص…',
              onChanged: (v) => setState(() {
                e.props['text'] = v;
                _dirty = true;
              }),
            ),
            const Text('إدراج بيانات الفاتورة داخل النص:', style: TextStyle(fontSize: 12, color: _C.muted)),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final f in const ['invoiceNo', 'customer', 'dateTime', 'net', 'remaining', 'footer', 'company'])
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(LayoutCatalog.fields[f] ?? LayoutCatalog.totals[f] ?? (f == 'company' ? 'اسم الشركة' : f),
                      style: const TextStyle(fontSize: 11.5)),
                  onPressed: () => set('text', '${e.s('text', '')}{$f}'),
                ),
            ]),
          ]),
        ];
      case ElType.field:
        return [
          PropSection('البيان', icon: Icons.badge_outlined, children: [
            _dropdown<String>(
              'ماذا يعرض',
              LayoutCatalog.fields.containsKey(e.s('key', '')) ? e.s('key', '') : 'customer',
              [for (final f in LayoutCatalog.fields.entries) DropdownMenuItem(value: f.key, child: Text(f.value))],
              (v) => _mutate(() {
                e.props['key'] = v;
                e.props['label'] = LayoutCatalog.fields[v] ?? '';
              }),
            ),
            SyncedField(
              label: 'العنوان قبل القيمة',
              value: e.s('label', ''),
              onChanged: (v) => setState(() {
                e.props['label'] = v;
                _dirty = true;
              }),
            ),
            SwitchRow(title: 'إظهار العنوان', value: e.b('showLabel', true), onChanged: (v) => set('showLabel', v)),
          ]),
        ];
      case ElType.companyInfo:
        final lines = e.strings('lines');
        return [
          PropSection('الأسطر', icon: Icons.list_alt, children: [
            for (final l in LayoutCatalog.companyLines.entries)
              SwitchRow(
                title: l.value,
                value: lines.contains(l.key),
                onChanged: (v) => set('lines', [
                  for (final k in LayoutCatalog.companyLines.keys)
                    if (k == l.key ? v : lines.contains(k)) k,
                ]),
              ),
            OutlinedButton.icon(
              onPressed: _openCompanySettings,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('تعديل معلومات الشركة'),
            ),
          ]),
        ];
      case ElType.companyName:
      case ElType.logo:
        return [
          PropSection(e.type == ElType.logo ? 'الشعار' : 'اسم الشركة', icon: Icons.business_outlined, children: [
            Text(
              e.type == ElType.logo
                  ? 'الشعار يؤخذ من معلومات الشركة. غيّر حجمه من زوايا العنصر.'
                  : 'الاسم يؤخذ من معلومات الشركة. غيّر خطه ولونه من الأسفل.',
              style: const TextStyle(fontSize: 12, color: _C.muted),
            ),
            OutlinedButton.icon(
              onPressed: _openCompanySettings,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(e.type == ElType.logo ? 'تغيير الشعار' : 'تغيير اسم الشركة'),
            ),
          ]),
        ];
      case ElType.line:
        return [
          PropSection('الخط', icon: Icons.horizontal_rule, children: [
            MiniNum(
                label: 'السُمك',
                value: e.d('thickness', 0.8),
                step: 0.2,
                min: 0.2,
                max: 10,
                onChanged: (v) => set('thickness', v)),
            SwitchRow(title: 'متقطع', value: e.b('dashed', false), onChanged: (v) => set('dashed', v)),
            ColorRow(label: 'اللون', value: e.i('color', 0xFF000000), onChanged: (v) => set('color', v)),
            const Text('خط عمودي: اجعل ارتفاعه أكبر من عرضه.', style: TextStyle(fontSize: 11.5, color: _C.muted)),
          ]),
        ];
      case ElType.box:
        return [
          PropSection('المستطيل', icon: Icons.crop_square, children: [
            Row(children: [
              Expanded(
                child: MiniNum(
                    label: 'سُمك الإطار',
                    value: e.d('border', 0.8),
                    step: 0.2,
                    min: 0,
                    max: 10,
                    onChanged: (v) => set('border', v)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MiniNum(
                    label: 'استدارة الزوايا',
                    value: e.d('radius', 0),
                    step: 0.5,
                    min: 0,
                    max: 30,
                    onChanged: (v) => set('radius', v)),
              ),
            ]),
            ColorRow(label: 'لون الإطار', value: e.i('borderColor', 0xFF000000), onChanged: (v) => set('borderColor', v)),
            ColorRow(label: 'التعبئة', value: e.i('bg', 0), allowNone: true, onChanged: (v) => set('bg', v)),
          ]),
        ];
      case ElType.barcode:
        return [
          PropSection('الرمز', icon: Icons.qr_code_2, children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'qr', label: Text('QR'), icon: Icon(Icons.qr_code_2)),
                ButtonSegment(value: 'code128', label: Text('باركود'), icon: Icon(Icons.view_week_outlined)),
              ],
              selected: {e.s('kind', 'qr')},
              onSelectionChanged: (s) => set('kind', s.first),
            ),
            _dropdown<String>(
              'يحمل',
              (LayoutCatalog.fields.containsKey(e.s('data', '')) ||
                      e.s('data', '') == InvoicePrintData.barcodeInvoiceInfo)
                  ? e.s('data', '')
                  : 'invoiceNo',
              [
                const DropdownMenuItem(
                    value: InvoicePrintData.barcodeInvoiceInfo,
                    child: Text('كل بيانات الفاتورة (الرقم، التاريخ والوقت، السيد، الهاتف)')),
                for (final k in const ['invoiceNo', 'customer', 'phone', 'dateTime'])
                  DropdownMenuItem(value: k, child: Text(LayoutCatalog.fields[k]!)),
              ],
              (v) => set('data', v),
            ),
            if (e.s('kind', 'qr') != 'qr')
              const Text('الباركود العادي لا يحمل حروفاً عربية: يُطبع رقم الفاتورة إن كانت البيانات عربية. استعمل QR لكل البيانات.',
                  style: TextStyle(fontSize: 11, color: _C.muted)),
          ]),
        ];
      case ElType.watermark:
        return [
          PropSection('العلامة المائية', icon: Icons.water_drop_outlined, children: [
            SyncedField(
              label: 'النص (فارغ = اسم الشركة)',
              value: e.s('text', ''),
              onChanged: (v) => setState(() {
                e.props['text'] = v;
                _dirty = true;
              }),
            ),
            Row(children: [
              Expanded(
                child: MiniNum(
                    label: 'الشفافية %',
                    value: e.d('opacity', 0.08) * 100,
                    step: 2,
                    min: 1,
                    max: 100,
                    decimals: 0,
                    onChanged: (v) => set('opacity', v / 100)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MiniNum(
                    label: 'الميل °',
                    value: e.d('angle', 0.8) * 180 / math.pi,
                    step: 5,
                    min: -90,
                    max: 90,
                    decimals: 0,
                    onChanged: (v) => set('angle', v * math.pi / 180)),
              ),
            ]),
            MiniNum(
                label: 'حجم الخط',
                value: e.d('fontSize', 100),
                step: 5,
                min: 10,
                max: 300,
                decimals: 0,
                onChanged: (v) => set('fontSize', v)),
            ColorRow(label: 'اللون', value: e.i('color', 0xFF9E9E9E), onChanged: (v) => set('color', v)),
          ]),
        ];
      case ElType.table:
        return _tableProps(c, e, set);
      case ElType.totals:
        return _totalsProps(e, set);
      default:
        return const [];
    }
  }

  // ── جدول المواد ──

  List<Widget> _tableProps(InvoiceLayout c, LayoutElement e, void Function(String, Object?) set) {
    final cols = e.columns;
    final present = cols.map((x) => '${x['id']}').toSet();
    final keys = <String>[];
    final seen = <String, int>{};
    for (final col in cols) {
      final id = '${col['id']}';
      seen[id] = (seen[id] ?? 0) + 1;
      keys.add('$id#${seen[id]}');
    }
    final rowH = e.d('rowHeight', 8);
    final cap = math.max(1, ((e.h - e.d('headerHeight', rowH)) / rowH).floor());
    return [
      PropSection('الأعمدة', icon: Icons.view_column_outlined, children: [
        const Text('العمود الأول هو الأيمن. اسحب ⠿ لتغيير الترتيب، واكتب لتغيير الاسم.',
            style: TextStyle(fontSize: 11.5, color: _C.muted)),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: cols.length,
          onReorderItem: (a, b) => _mutate(() {
            final list = e.columns;
            list.insert(b, list.removeAt(a));
            e.columns = list;
          }),
          itemBuilder: (ctx, i) {
            final col = cols[i];
            final align = '${col['align'] ?? 'center'}';
            return Container(
              key: ValueKey(keys[i]),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _C.soft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _C.border),
              ),
              child: Column(children: [
                Row(children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: const MouseRegion(
                        cursor: SystemMouseCursors.grab, child: Icon(Icons.drag_indicator, size: 20, color: _C.muted)),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SyncedField(
                      value: '${col['label'] ?? ''}',
                      hint: LayoutCatalog.columns['${col['id']}'],
                      onChanged: (v) => setState(() {
                        final list = e.columns;
                        list[i]['label'] = v;
                        e.columns = list;
                        _dirty = true;
                      }),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'حذف العمود',
                    onPressed: () => _mutate(() {
                      final list = e.columns..removeAt(i);
                      e.columns = list;
                    }),
                    icon: const Icon(Icons.close, size: 18, color: Colors.red),
                  ),
                ]),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: MiniNum(
                      label: 'العرض',
                      value: (col['flex'] is num) ? (col['flex'] as num).toDouble() : 1.0,
                      step: 0.1,
                      min: 0.2,
                      max: 10,
                      decimals: 2,
                      onChanged: (v) => _mutate(() {
                        final list = e.columns;
                        list[i]['flex'] = v;
                        e.columns = list;
                      }),
                    ),
                  ),
                  const SizedBox(width: 6),
                  for (final a in const ['right', 'center', 'left']) ...[
                    IconToggle(
                      icon: a == 'right'
                          ? Icons.format_align_right
                          : (a == 'center' ? Icons.format_align_center : Icons.format_align_left),
                      on: align == a,
                      onTap: () => _mutate(() {
                        final list = e.columns;
                        list[i]['align'] = a;
                        e.columns = list;
                      }),
                    ),
                    const SizedBox(width: 3),
                  ],
                ]),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('البيان: ${LayoutCatalog.columns['${col['id']}'] ?? ''}',
                      style: const TextStyle(fontSize: 11, color: _C.muted)),
                ),
              ]),
            );
          },
        ),
        const SizedBox(height: 4),
        const Text('أضف عموداً:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in LayoutCatalog.columns.entries)
            if (k.key == 'blank' || !present.contains(k.key))
              ActionChip(
                avatar: const Icon(Icons.add, size: 16, color: _C.blue),
                label: Text(k.value, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: _C.blue.withValues(alpha: 0.4)),
                backgroundColor: _C.blue.withValues(alpha: 0.05),
                onPressed: () => _mutate(() {
                  final list = e.columns
                    ..add({
                      'id': k.key,
                      'label': LayoutCatalog.columns[k.key] ?? '',
                      'flex': k.key == 'details' ? 3.0 : 1.0,
                      'align': k.key == 'details' ? 'right' : 'center',
                    });
                  e.columns = list;
                }),
              ),
        ]),
        const SizedBox(height: 6),
        const Text('«الخصم» و«السعر قبل الخصم» يظهران فقط إن كان في الفاتورة صنف مخصوم.',
            style: TextStyle(fontSize: 11, color: _C.muted)),
      ]),
      PropSection('الخطوط والألوان', icon: Icons.grid_4x4, children: [
        _dropdown<String>(
          'خطوط الجدول',
          LayoutRules.tableBorders(e),
          const [
            DropdownMenuItem(value: 'grid', child: Text('شبكة كاملة (كل خلية بمربع)')),
            DropdownMenuItem(value: 'columns', child: Text('أعمدة فقط مع إطار خارجي')),
            DropdownMenuItem(value: 'rows', child: Text('خط تحت كل سطر')),
            DropdownMenuItem(value: 'outer', child: Text('إطار خارجي فقط')),
            DropdownMenuItem(value: 'none', child: Text('بلا خطوط')),
          ],
          (v) => set('borders', v ?? 'grid'),
        ),
        MiniNum(
            label: 'سُمك الخطوط',
            value: e.d('lineWidth', 0.4),
            step: 0.1,
            min: 0.1,
            max: 3,
            onChanged: (v) => set('lineWidth', v)),
        ColorRow(label: 'لون الخطوط', value: e.i('gridColor', 0xFF9E9E9E), onChanged: (v) => set('gridColor', v)),
        SwitchRow(title: 'تلوين الصفوف بالتناوب', value: e.b('zebra', false), onChanged: (v) => set('zebra', v)),
        ColorRow(
            label: 'خلفية رأس الجدول',
            value: e.i('headerBg', 0xFFE8EEF5),
            allowNone: true,
            onChanged: (v) => set('headerBg', v)),
        ColorRow(label: 'لون نص الرأس', value: e.i('headerColor', 0xFF000000), onChanged: (v) => set('headerColor', v)),
        ColorRow(label: 'لون نص المواد', value: e.i('color', 0xFF000000), onChanged: (v) => set('color', v)),
      ]),
      PropSection('الصفوف', icon: Icons.table_rows_outlined, children: [
        Row(children: [
          Expanded(
            child: MiniNum(
                label: 'ارتفاع الصف',
                suffix: 'ملم',
                value: rowH,
                step: 0.5,
                min: 3,
                max: 40,
                onChanged: (v) => set('rowHeight', v)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: MiniNum(
                label: 'حجم الخط',
                value: e.d('fontSize', 10),
                step: 0.5,
                min: 5,
                max: 30,
                onChanged: (v) => set('fontSize', v)),
          ),
        ]),
        if (!c.paper.isRoll) ...[
          Text('يتسع لـ $cap صفاً في الصفحة؛ الزائد ينتقل لصفحة جديدة.',
              style: const TextStyle(fontSize: 11.5, color: _C.muted)),
          SwitchRow(
            title: 'ملء الجدول بأسطر فارغة',
            subtitle: 'يظهر الجدول بارتفاعه كاملاً كالدفاتر المطبوعة',
            value: e.b('fillRows', false),
            onChanged: (v) => set('fillRows', v),
          ),
        ],
      ]),
    ];
  }

  // ── المجاميع / البيانات ──

  List<Widget> _totalsProps(LayoutElement e, void Function(String, Object?) set) {
    final items = e.strings('items');
    final style = e.s('style', 'list');
    final mode = LayoutRules.boxMode(e);
    Widget modeCard(String value, IconData icon, String label) {
      final on = mode == value;
      return Expanded(
        child: InkWell(
          onTap: () => set('boxMode', value),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: on ? _C.blue.withValues(alpha: 0.1) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: on ? _C.blue : _C.border, width: on ? 1.6 : 1),
            ),
            child: Column(children: [
              Icon(icon, size: 20, color: on ? _C.blue : _C.muted),
              const SizedBox(height: 4),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.5, height: 1.2, color: on ? _C.blue : _C.text)),
            ]),
          ),
        ),
      );
    }

    return [
      PropSection('شكل المربعات', icon: Icons.check_box_outline_blank, children: [
        Row(children: [
          modeCard('each', Icons.grid_view, 'كل بند\nبمربع'),
          const SizedBox(width: 6),
          modeCard('group', Icons.crop_square, 'مربع\nواحد'),
          const SizedBox(width: 6),
          modeCard('lines', Icons.view_agenda_outlined, 'مربع\nبخطوط'),
          const SizedBox(width: 6),
          modeCard('none', Icons.format_list_bulleted, 'بلا\nمربعات'),
        ]),
        SyncedField(
          label: 'عنوان المربع (اختياري)',
          hint: 'مثل: ملخص الفاتورة، حساب العميل',
          value: e.s('title', ''),
          onChanged: (v) => setState(() {
            e.props['title'] = v;
            _dirty = true;
          }),
        ),
        if (e.s('title', '').trim().isNotEmpty) ...[
          ColorRow(label: 'خلفية العنوان', value: e.i('titleBg', 0xFF0F3460), onChanged: (v) => set('titleBg', v)),
          ColorRow(label: 'لون نص العنوان', value: e.i('titleColor', 0xFFFFFFFF), onChanged: (v) => set('titleColor', v)),
        ],
        if (mode != 'none') ...[
          Row(children: [
            Expanded(
              child: MiniNum(
                  label: 'سُمك الإطار',
                  value: e.d('border', 0.6),
                  step: 0.2,
                  min: 0.2,
                  max: 5,
                  onChanged: (v) => set('border', v)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MiniNum(
                  label: 'استدارة الزوايا',
                  value: e.d('radius', 0),
                  step: 0.5,
                  min: 0,
                  max: 20,
                  onChanged: (v) => set('radius', v)),
            ),
          ]),
          ColorRow(label: 'لون الإطار', value: e.i('borderColor', 0xFF90A4AE), onChanged: (v) => set('borderColor', v)),
        ],
      ]),
      PropSection('ترتيب البنود', icon: Icons.dashboard_outlined, children: [
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'list', label: Text('فوق بعض'), icon: Icon(Icons.view_list)),
            ButtonSegment(value: 'grid', label: Text('أعمدة'), icon: Icon(Icons.grid_view)),
            ButtonSegment(value: 'row', label: Text('صف'), icon: Icon(Icons.view_column)),
          ],
          selected: {style},
          onSelectionChanged: (s) => set('style', s.first),
        ),
        if (style == 'grid')
          MiniNum(
            label: 'عدد الأعمدة (البنود تُوزّع من اليمين، فوق بعض)',
            value: e.i('cols', 2).toDouble(),
            step: 1,
            min: 1,
            max: 6,
            decimals: 0,
            onChanged: (v) => set('cols', v.round()),
          ),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'side', label: Text('العنوان بجانب المبلغ')),
            ButtonSegment(value: 'stacked', label: Text('العنوان فوقه')),
          ],
          selected: {e.s('labelPos', style == 'row' ? 'stacked' : 'side')},
          onSelectionChanged: (s) => set('labelPos', s.first),
        ),
      ]),
      PropSection('البنود', icon: Icons.format_list_numbered, children: [
        const Text('اسحب ⠿ للترتيب، واكتب لتغيير اسم البند.', style: TextStyle(fontSize: 11.5, color: _C.muted)),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: items.length,
          onReorderItem: (a, b) => _mutate(() {
            final list = e.strings('items');
            list.insert(b, list.removeAt(a));
            e.props['items'] = list;
          }),
          itemBuilder: (ctx, i) {
            final k = items[i];
            return Container(
              key: ValueKey('t_$k'),
              margin: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                ReorderableDragStartListener(
                  index: i,
                  child: const MouseRegion(
                      cursor: SystemMouseCursors.grab, child: Icon(Icons.drag_indicator, size: 20, color: _C.muted)),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SyncedField(
                    value: LayoutRules.itemLabel(e, k),
                    onChanged: (v) => setState(() {
                      final m = e.props['labels'] is Map
                          ? Map<String, dynamic>.from(e.props['labels'] as Map)
                          : <String, dynamic>{};
                      m[k] = v;
                      e.props['labels'] = m;
                      _dirty = true;
                    }),
                  ),
                ),
                IconToggle(
                  icon: Icons.star_rounded,
                  on: e.s('highlight', '') == k,
                  tooltip: 'إبراز هذا البند بلون',
                  onTap: () => set('highlight', e.s('highlight', '') == k ? '' : k),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'إزالة البند',
                  onPressed: () => _mutate(() => e.props['items'] = e.strings('items')..remove(k)),
                  icon: const Icon(Icons.close, size: 18, color: Colors.red),
                ),
              ]),
            );
          },
        ),
        PopupMenuButton<String>(
          tooltip: 'إضافة بند',
          onSelected: (k) => _mutate(() => e.props['items'] = e.strings('items')..add(k)),
          itemBuilder: (_) => [
            const PopupMenuItem<String>(
                enabled: false, child: Text('— المبالغ —', style: TextStyle(fontWeight: FontWeight.bold))),
            for (final t in LayoutCatalog.totals.entries)
              if (!items.contains(t.key)) PopupMenuItem<String>(value: t.key, child: Text(t.value)),
            const PopupMenuItem<String>(
                enabled: false, child: Text('— بيانات الفاتورة —', style: TextStyle(fontWeight: FontWeight.bold))),
            for (final f in LayoutCatalog.fields.entries)
              if (!items.contains(f.key) && !LayoutCatalog.totals.containsKey(f.key) && f.key != 'copy' && f.key != 'footer')
                PopupMenuItem<String>(value: f.key, child: Text(f.value)),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.blue.withValues(alpha: 0.5)),
            ),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add, color: _C.blue),
              SizedBox(width: 6),
              Text('إضافة بند', style: TextStyle(color: _C.blue, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        const Text(
          'تستطيع وضع أكثر من مربع: مربع للفاتورة (الإجمالي، الخصم، بعد الخصم) ومربع للدين '
          '(السابق، المطلوب)، ومربعات منفردة لبند واحد.',
          style: TextStyle(fontSize: 11, color: _C.muted, height: 1.4),
        ),
      ]),
      PropSection('الألوان والخط', icon: Icons.palette_outlined, initiallyOpen: false, children: [
        MiniNum(label: 'حجم الخط', value: e.d('fontSize', 10), step: 0.5, min: 5, max: 30, onChanged: (v) => set('fontSize', v)),
        ColorRow(label: 'لون البند البارز', value: e.i('highlightColor', 0xFF0F3460), onChanged: (v) => set('highlightColor', v)),
        ColorRow(label: 'لون المبالغ', value: e.i('color', 0xFF000000), onChanged: (v) => set('color', v)),
        ColorRow(label: 'لون العناوين', value: e.i('labelColor', 0xFF455A64), onChanged: (v) => set('labelColor', v)),
      ]),
    ];
  }
}

// ─────────────────────────── أدوات الشريط العلوي ───────────────────────────

class _PaperTab extends StatelessWidget {
  const _PaperTab({required this.label, required this.sub, required this.icon, required this.selected, required this.onTap});
  final String label;
  final String sub;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? _C.navy : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _C.navy : _C.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: selected ? Colors.white : _C.muted),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13, color: selected ? Colors.white : _C.text, height: 1.1)),
            Text(sub, style: TextStyle(fontSize: 10, color: selected ? Colors.white70 : _C.muted, height: 1.1)),
          ]),
        ]),
      ),
    );
  }
}

class _DesignChip extends StatelessWidget {
  const _DesignChip({required this.name, required this.selected, required this.used, required this.onTap});
  final String name;
  final bool selected;
  final bool used;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: used ? 'مستعمل في الطباعة' : '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? _C.blue.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? _C.blue : _C.border, width: selected ? 1.6 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (used) ...[
              const Icon(Icons.print, size: 14, color: Colors.green),
              const SizedBox(width: 5),
            ],
            Text(name,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? _C.blue : _C.text)),
          ]),
        ),
      ),
    );
  }
}

/// معرض النماذج الجاهزة (معاينات مصغّرة)
class _GalleryDialog extends StatelessWidget {
  const _GalleryDialog({required this.paper, required this.data, this.kind = 'invoice'});
  final LayoutPaper paper;
  final InvoicePrintData data;

  /// 'invoice' أو نوع سند — لكل نوع قوالبه
  final String kind;

  @override
  Widget build(BuildContext context) {
    final templates =
        kind == 'invoice' ? InvoiceLayoutTemplates.forPaper(paper) : InvoiceLayoutTemplates.forKind(kind);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 1000,
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(children: [
          Container(
            color: _C.navy,
            padding: const EdgeInsets.fromLTRB(20, 14, 10, 14),
            child: Row(children: [
              const Icon(Icons.auto_awesome, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('اختر نموذجاً — ${paper.label}',
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                  const Text('كل نموذج قابل للتعديل الكامل بعد اختياره',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Expanded(
            child: Container(
              color: _C.bg,
              child: GridView.builder(
                padding: const EdgeInsets.all(18),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 230,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.62,
                ),
                itemCount: templates.length,
                itemBuilder: (_, i) => _TemplateCard(template: templates[i], data: data),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TemplateCard extends StatefulWidget {
  const _TemplateCard({required this.template, required this.data});
  final LayoutTemplate template;
  final InvoicePrintData data;

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard> {
  bool _hover = false;
  late final InvoiceLayout _l = widget.template.build();

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final blank = t.key == 'blank';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => Navigator.pop(context, t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          transform: Matrix4.translationValues(0.0, _hover ? -4.0 : 0.0, 0.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hover ? _C.blue : _C.border, width: _hover ? 2 : 1),
            boxShadow: [
              BoxShadow(
                color: _hover ? _C.blue.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.06),
                blurRadius: _hover ? 18 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                final s = math.min(box.maxWidth / _l.widthMm, box.maxHeight / _l.heightMm);
                return Center(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: _C.border),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6)],
                    ),
                    child: blank
                        ? Container(
                            width: _l.widthMm * s,
                            height: _l.heightMm * s,
                            color: Colors.white,
                            alignment: Alignment.center,
                            child: const Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.note_add_outlined, size: 44, color: _C.blue),
                              SizedBox(height: 6),
                              Text('ابدأ من الصفر', style: TextStyle(color: _C.muted, fontSize: 12)),
                            ]),
                          )
                        : IgnorePointer(child: LayoutCanvas(layout: _l, data: widget.data, scale: s)),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _C.text)),
            const SizedBox(height: 3),
            Text(t.description,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: _C.muted, height: 1.35)),
          ]),
        ),
      ),
    );
  }
}

/// خطوة رجوع في المصمم: التصميم المعروض قبلها، وما أُنشئ فيها إن وُجد.
class _ViewStep {
  _ViewStep({
    required this.prevCurId,
    required this.prevDirty,
    required this.undoLen,
    this.createdId,
    this.fromGallery = false,
  });

  final String? prevCurId;
  final bool prevDirty;
  final int undoLen;

  /// التصميم الذي أنشأته هذه الخطوة؛ يصير null بعد الحفظ (صار محفوظاً فلا يُزال).
  String? createdId;
  final bool fromGallery;
}
