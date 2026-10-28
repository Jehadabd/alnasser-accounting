// lib/invoice_designer/invoice_layout_templates.dart
//
// 🧩 نماذج جاهزة على طريقة الفواتير المنتشرة (رسمية بإطار، مربعات منفردة،
// مجموعتا الفاتورة والدين، الصافي البارز، بسيط أنيق، جملة…) وإيصالات الكاشير،
// و«ورقة بيضاء». يبدأ منها المستخدم ثم يعدّل كل شيء بالسحب.

import 'invoice_layout.dart';

class LayoutTemplate {
  const LayoutTemplate(this.key, this.name, this.description, this.build);
  final String key;
  final String name;
  final String description;
  final InvoiceLayout Function() build;
}

class InvoiceLayoutTemplates {
  InvoiceLayoutTemplates._();

  static const _navy = 0xFF0F3460;
  static const _green = 0xFF2E7D32;
  static const _grey = 0xFF455A64;
  static const _red = 0xFFC62828;
  static const _light = 0xFFE8EEF5;
  static const _black = 0xFF000000;
  static const _white = 0xFFFFFFFF;

  static int _n = 0;
  static LayoutElement _e(String type, double x, double y, double w, double h, [Map<String, dynamic>? p]) =>
      LayoutElement(id: 'e${_n++}', type: type, x: x, y: y, w: w, h: h, props: p);

  static List<Map<String, dynamic>> _cols(List<List<Object>> c) => [
        for (final x in c)
          <String, dynamic>{
            'id': x[0],
            'label': LayoutCatalog.columns[x[0]] ?? '',
            'flex': x[1],
            'align': x.length > 2 ? x[2] : (x[0] == 'details' ? 'right' : 'center'),
          }
      ];

  static List<Map<String, dynamic>> get _colsStd => _cols([
        ['serial', 0.5],
        ['productId', 0.9],
        ['details', 3.2],
        ['quantity', 1.3],
        ['unitsCount', 1.0],
        ['priceBeforeDiscount', 1.1],
        ['discount', 0.9],
        ['price', 1.2],
        ['amount', 1.5],
      ]);

  static List<Map<String, dynamic>> get _colsSimple => _cols([
        ['serial', 0.5],
        ['details', 3.6],
        ['quantity', 1.4],
        ['priceBeforeDiscount', 1.1],
        ['discount', 0.9],
        ['price', 1.3],
        ['amount', 1.6],
      ]);

  static List<Map<String, dynamic>> get _colsWholesale => _cols([
        ['serial', 0.45],
        ['productId', 0.8],
        ['details', 2.8],
        ['qty', 0.8],
        ['unit', 0.9],
        ['unitsCount', 0.9],
        ['weight', 0.9],
        ['priceBeforeDiscount', 1.0],
        ['discount', 0.8],
        ['price', 1.1],
        ['amount', 1.4],
      ]);

  // ─────────────────────────── أدوات البناء ───────────────────────────

  static LayoutElement _table(double x, double y, double w, double h, List<Map<String, dynamic>> cols,
          {String borders = 'grid',
          double rowH = 8,
          double fs = 10,
          int headerBg = _light,
          int headerColor = _black,
          int lineColor = 0xFF9E9E9E,
          bool zebra = false,
          bool fill = false}) =>
      _e(ElType.table, x, y, w, h, {
        'columns': cols,
        'borders': borders,
        'rowHeight': rowH,
        'fontSize': fs,
        'headerBg': headerBg,
        'headerColor': headerColor,
        'gridColor': lineColor,
        'zebra': zebra,
        'fillRows': fill,
      });

  /// مربع مجاميع أو بيانات
  static LayoutElement _box(double x, double y, double w, double h, List<String> items,
          {String style = 'list',
          int cols = 2,
          String mode = 'group',
          String title = '',
          String highlight = '',
          int highlightColor = _navy,
          int titleBg = _navy,
          int borderColor = 0xFF90A4AE,
          double border = 0.6,
          double radius = 0,
          double fs = 10,
          String? labelPos,
          Map<String, String>? labels}) =>
      _e(ElType.totals, x, y, w, h, {
        'style': style,
        'cols': cols,
        'items': items,
        'boxMode': mode,
        'title': title,
        'highlight': highlight,
        'highlightColor': highlightColor,
        'titleBg': titleBg,
        'borderColor': borderColor,
        'border': border,
        'radius': radius,
        'fontSize': fs,
        if (labelPos != null) 'labelPos': labelPos,
        if (labels != null) 'labels': labels,
      });

  static LayoutElement _text(double x, double y, double w, double h, String text,
          {double fs = 10, bool bold = false, String align = 'right', int color = _black}) =>
      _e(ElType.text, x, y, w, h, {'text': text, 'fontSize': fs, 'bold': bold, 'align': align, 'color': color});

  static LayoutElement _field(double x, double y, double w, double h, String key,
          {String? label,
          bool showLabel = true,
          double fs = 10,
          bool bold = false,
          String align = 'right',
          int color = _black,
          double border = 0,
          int borderColor = _black,
          double radius = 0}) =>
      _e(ElType.field, x, y, w, h, {
        'key': key,
        'label': label ?? LayoutCatalog.fields[key] ?? '',
        'showLabel': showLabel,
        'fontSize': fs,
        'bold': bold,
        'align': align,
        'color': color,
        'border': border,
        'borderColor': borderColor,
        'radius': radius,
      });

  static LayoutElement _line(double x, double y, double w, {double t = 0.8, int color = _black, bool dashed = false}) =>
      _e(ElType.line, x, y, w, 1, {'thickness': t, 'color': color, 'dashed': dashed});

  static LayoutElement _rect(double x, double y, double w, double h,
          {double border = 0.8, int borderColor = _black, int bg = 0, double radius = 0}) =>
      _e(ElType.box, x, y, w, h, {'border': border, 'borderColor': borderColor, 'bg': bg, 'radius': radius});

  static List<LayoutElement> _signature(double x, double y, double w, String label) => [
        _text(x, y, w, 5, label, fs: 9, align: 'center', color: _grey),
        _line(x + 4, y + 10, w - 8, t: 0.6, color: _grey),
      ];

  static LayoutElement _pageNo(double y) => _e(ElType.pageNo, 80, y, 50, 5, {'fontSize': 8.5, 'align': 'center'});

  static List<LayoutElement> _header({int nameColor = _green, int infoColor = _grey}) => [
        _e(ElType.logo, 8, 5, 30, 24),
        _e(ElType.companyName, 42, 5, 160, 13, {'fontSize': 24.0, 'bold': true, 'align': 'right', 'color': nameColor}),
        _e(ElType.companyInfo, 42, 18, 160, 13, {
          'fontSize': 9.5,
          'align': 'right',
          'color': infoColor,
          'lines': ['description', 'address', 'phones'],
        }),
      ];

  static List<LayoutElement> _fields(double y) => [
        _field(110, y, 92, 7, 'customer', label: 'السيد', fs: 11, bold: true),
        _field(8, y, 100, 7, 'address'),
        _field(140, y + 7.5, 62, 7, 'invoiceNo'),
        _field(74, y + 7.5, 64, 7, 'dateTime', label: 'التاريخ', align: 'center'),
        _field(8, y + 7.5, 64, 7, 'phone', align: 'left'),
      ];

  static InvoiceLayout _a4(String name, List<LayoutElement> els) =>
      InvoiceLayout(id: InvoiceLayout.newId('L'), name: name, paper: LayoutPaper.a4, elements: els);

  // ═══════════════════ 🧾 إشعار مدين / دائن (سند إضافة أو إرجاع على فاتورة) ═══════════════════
  // على شكل الإشعارات في البرامج المحاسبية: نوع السند بارز، رقمه وتاريخه، الفاتورة
  // الأصلية والعميل، البنود، أثره على الفاتورة وعلى حساب العميل، المبلغ كتابةً، والتواقيع.

  static List<Map<String, dynamic>> get _colsVoucher => _cols([
        ['serial', 0.5],
        ['details', 3.6],
        ['quantity', 1.4],
        ['price', 1.3],
        ['amount', 1.6],
      ]);

  /// التصميم الأصلي للإشعار (حين لا يُختار تصميم له في المصمم)
  static InvoiceLayout defaultVoucher() => _voucherOfficial();

  static InvoiceLayout _voucherOfficial() => _a4('إشعار رسمي بإطار', [
        _rect(5, 5, 200, 287, border: 1.2, borderColor: _navy, radius: 2),
        _e(ElType.companyName, 112, 10, 88, 11, {'fontSize': 20.0, 'bold': true, 'align': 'right', 'color': _navy}),
        _e(ElType.companyInfo, 112, 21, 88, 15,
            {'fontSize': 9.0, 'align': 'right', 'color': _grey, 'lines': ['description', 'address']}),
        _e(ElType.logo, 88, 9, 34, 26),
        _e(ElType.companyInfo, 10, 10, 74, 24,
            {'fontSize': 9.0, 'align': 'left', 'color': _grey, 'lines': ['phones', 'tax', 'cr']}),
        _rect(68, 38, 74, 11, border: 0, bg: _navy, radius: 2),
        _text(68, 38, 74, 11, '{voucherTitle}', fs: 16, bold: true, align: 'center', color: _white),
        _box(10, 53, 190, 16, ['voucherNo', 'dateTime', 'invoiceNo', 'customer', 'phone', 'paymentType'],
            style: 'grid', cols: 3, mode: 'lines', borderColor: _navy, border: 0.5, fs: 9.5,
            labels: {'invoiceNo': 'الفاتورة الأصلية'}),
        _field(10, 71, 190, 8, 'voucherReason', label: 'البيان', fs: 10, border: 0.5, borderColor: _navy),
        _table(10, 82, 190, 108, _colsVoucher,
            borders: 'columns', rowH: 7.5, fs: 9.5, headerBg: _navy, headerColor: _white, lineColor: 0xFF546E7A, fill: true),
        _box(106, 194, 94, 30, ['invoiceBefore', 'voucherAmount', 'invoiceAfter'],
            mode: 'lines', title: 'أثر السند على الفاتورة', highlight: 'voucherAmount', borderColor: _navy, fs: 10),
        _box(10, 194, 92, 30, ['previousDebt', 'currentDebt'],
            mode: 'lines', title: 'حساب العميل', titleBg: _grey, highlight: 'currentDebt', highlightColor: _red,
            borderColor: _navy, fs: 10, labels: {'previousDebt': 'الرصيد قبل السند', 'currentDebt': 'الرصيد بعد السند'}),
        _field(10, 228, 190, 8, 'amountWords', showLabel: false, align: 'center', border: 0.5, borderColor: _navy, fs: 10),
        _text(10, 239, 190, 6, 'يُعتمد هذا الإشعار تسويةً على الفاتورة رقم {invoiceNo}، ولا يُعدّ فاتورة جديدة.',
            fs: 9, align: 'center', color: _grey),
        ..._signature(140, 252, 50, 'المحاسب: {accountant}'),
        ..._signature(80, 252, 50, 'المدير'),
        ..._signature(20, 252, 50, 'توقيع العميل'),
        _pageNo(285),
      ]);

  static InvoiceLayout _voucherAmount() => _a4('إشعار — المبلغ بارز', [
        ..._header(nameColor: _navy),
        _line(8, 32.5, 194, color: _navy),
        _rect(8, 36, 70, 30, border: 0, bg: _navy, radius: 2),
        _text(10, 37, 66, 8, '{voucherTitle}', fs: 12, bold: true, align: 'center', color: _white),
        _text(10, 46, 66, 14, '{voucherAmount}', fs: 22, bold: true, align: 'center', color: _white),
        _text(10, 59, 66, 6, 'دينار عراقي', fs: 8.5, align: 'center', color: _white),
        _box(82, 36, 120, 30, ['voucherNo', 'invoiceNo', 'dateTime', 'customer'],
            mode: 'lines', borderColor: _navy, border: 0.6, radius: 1.5, fs: 10, labels: {'invoiceNo': 'الفاتورة الأصلية'}),
        _field(8, 70, 194, 8, 'voucherReason', label: 'البيان', border: 0.5, borderColor: _grey, radius: 1.5),
        _table(8, 82, 194, 110, _colsVoucher, borders: 'rows', zebra: true, headerBg: _navy, headerColor: _white),
        _box(106, 196, 96, 28, ['invoiceBefore', 'voucherAmount', 'invoiceAfter'],
            mode: 'group', title: 'الفاتورة', highlight: 'invoiceAfter', borderColor: _navy, border: 0.8, radius: 1.5),
        _box(8, 196, 94, 28, ['previousDebt', 'currentDebt'],
            mode: 'group', title: 'حساب العميل', titleBg: _grey, highlight: 'currentDebt', highlightColor: _red,
            borderColor: _grey, border: 0.8, radius: 1.5,
            labels: {'previousDebt': 'الرصيد قبل السند', 'currentDebt': 'الرصيد بعد السند'}),
        _field(8, 228, 194, 8, 'amountWords', showLabel: false, align: 'center', fs: 10),
        ..._signature(130, 250, 60, 'المحاسب: {accountant}'),
        ..._signature(20, 250, 60, 'توقيع العميل'),
        _text(8, 278, 194, 6, '{footer}', fs: 9, align: 'center', color: _grey),
        _pageNo(287),
      ]);

  static InvoiceLayout _voucherMinimal() => _a4('إشعار بسيط', [
        ..._header(),
        _line(8, 32.5, 194, t: 0.5, color: _grey),
        _text(8, 36, 194, 12, '{voucherTitle}', fs: 20, bold: true, align: 'center', color: _navy),
        _field(140, 50, 62, 7, 'voucherNo'),
        _field(74, 50, 64, 7, 'dateTime', label: 'التاريخ', align: 'center'),
        _field(8, 50, 64, 7, 'invoiceNo', label: 'الفاتورة الأصلية', align: 'left'),
        _field(110, 58, 92, 7, 'customer', label: 'السيد', fs: 11, bold: true),
        _field(8, 58, 100, 7, 'voucherReason', label: 'البيان'),
        _table(8, 69, 194, 120, _colsVoucher, borders: 'rows', headerBg: 0xFFDDE7F0),
        _line(8, 193, 194, t: 0.5, color: _grey),
        _box(112, 196, 90, 24, ['invoiceBefore', 'voucherAmount', 'invoiceAfter'],
            mode: 'none', highlight: 'voucherAmount', border: 0, fs: 10.5),
        _box(8, 196, 90, 24, ['previousDebt', 'currentDebt'], mode: 'none', border: 0, fs: 10.5,
            highlight: 'currentDebt', highlightColor: _red,
            labels: {'previousDebt': 'الرصيد قبل السند', 'currentDebt': 'الرصيد بعد السند'}),
        _field(8, 224, 194, 7, 'amountWords', showLabel: false, align: 'center', fs: 9.5),
        ..._signature(130, 245, 60, 'المحاسب'),
        ..._signature(20, 245, 60, 'المستلم'),
        _pageNo(287),
      ]);

  // ═══════════════════ 🧾 سند قبض — تسديد دين (ووصل عدة عملاء) ═══════════════════

  static List<Map<String, dynamic>> get _colsReceipt => [
        {'id': 'serial', 'label': 'ت', 'flex': 0.5, 'align': 'center'},
        {'id': 'details', 'label': 'العميل', 'flex': 3.0, 'align': 'right'},
        {'id': 'priceBeforeDiscount', 'label': 'الرصيد قبل', 'flex': 1.4, 'align': 'center'},
        {'id': 'discount', 'label': 'الخصم', 'flex': 1.0, 'align': 'center'},
        {'id': 'amount', 'label': 'المبلغ المقبوض', 'flex': 1.6, 'align': 'center'},
        {'id': 'blank', 'label': 'الرصيد بعد', 'flex': 1.4, 'align': 'center'},
      ];

  static const _receiptLabels = {
    'voucherAmount': 'المبلغ المقبوض',
    'previousDebt': 'الرصيد قبل التسديد',
    'currentDebt': 'الرصيد بعد التسديد',
  };

  static InvoiceLayout _receiptOfficial() => _a4('سند قبض رسمي بإطار', [
        _rect(5, 5, 200, 287, border: 1.2, borderColor: _green, radius: 2),
        _e(ElType.companyName, 112, 10, 88, 11, {'fontSize': 20.0, 'bold': true, 'align': 'right', 'color': _green}),
        _e(ElType.companyInfo, 112, 21, 88, 15,
            {'fontSize': 9.0, 'align': 'right', 'color': _grey, 'lines': ['description', 'address']}),
        _e(ElType.logo, 88, 9, 34, 26),
        _e(ElType.companyInfo, 10, 10, 74, 24,
            {'fontSize': 9.0, 'align': 'left', 'color': _grey, 'lines': ['phones', 'tax', 'cr']}),
        _rect(68, 38, 74, 11, border: 0, bg: _green, radius: 2),
        _text(68, 38, 74, 11, '{voucherTitle}', fs: 16, bold: true, align: 'center', color: _white),
        _box(10, 53, 190, 16, ['voucherNo', 'dateTime', 'customer', 'phone', 'boxName', 'docNo'],
            style: 'grid', cols: 3, mode: 'lines', borderColor: _green, border: 0.5, fs: 9.5),
        _field(10, 71, 190, 8, 'voucherReason', label: 'البيان', fs: 10, border: 0.5, borderColor: _green),
        _table(10, 82, 190, 92, _colsReceipt,
            borders: 'columns', rowH: 7.5, fs: 9.5, headerBg: _green, headerColor: _white, lineColor: 0xFF546E7A),
        _box(106, 180, 94, 30, ['voucherAmount', 'discount'],
            mode: 'lines', title: 'المبلغ', highlight: 'voucherAmount', highlightColor: _green, titleBg: _green,
            borderColor: _green, fs: 10.5, labels: _receiptLabels),
        _box(10, 180, 92, 30, ['previousDebt', 'currentDebt'],
            mode: 'lines', title: 'حساب العميل', titleBg: _grey, highlight: 'currentDebt', highlightColor: _red,
            borderColor: _green, fs: 10, labels: _receiptLabels),
        _field(10, 214, 190, 8, 'amountWords', showLabel: false, align: 'center', border: 0.5, borderColor: _green, fs: 10.5),
        ..._signature(140, 236, 50, 'المحاسب: {accountant}'),
        ..._signature(80, 236, 50, 'المدير'),
        ..._signature(20, 236, 50, 'الدافع'),
        _text(10, 278, 190, 5, 'طُبع في {printedAt} — بواسطة {printedBy}', fs: 8, align: 'center', color: _grey),
        _pageNo(284),
      ]);

  static InvoiceLayout _receiptAmount() => _a4('سند قبض — المبلغ بارز', [
        ..._header(nameColor: _green),
        _line(8, 32.5, 194, color: _green),
        _rect(8, 36, 76, 34, border: 0, bg: _green, radius: 2),
        _text(10, 37, 72, 8, '{voucherTitle} رقم {voucherNo}', fs: 12, bold: true, align: 'center', color: _white),
        _text(10, 46, 72, 15, '{voucherAmount}', fs: 24, bold: true, align: 'center', color: _white),
        _text(10, 62, 72, 6, 'دينار عراقي', fs: 8.5, align: 'center', color: _white),
        _box(88, 36, 114, 34, ['customer', 'dateTime', 'phone', 'boxName'],
            mode: 'lines', borderColor: _green, border: 0.6, radius: 1.5, fs: 10.5),
        _field(8, 74, 194, 8, 'amountWords', showLabel: false, align: 'center', fs: 11, border: 0.5, borderColor: _green, radius: 1.5),
        _field(8, 85, 194, 8, 'voucherReason', label: 'البيان', border: 0.5, borderColor: _grey, radius: 1.5),
        _box(8, 97, 194, 22, ['previousDebt', 'voucherAmount', 'currentDebt'],
            style: 'grid', cols: 3, mode: 'group', highlight: 'currentDebt', highlightColor: _red,
            borderColor: _grey, border: 0.8, radius: 1.5, fs: 11, labels: _receiptLabels),
        ..._signature(130, 132, 60, 'المحاسب: {accountant}'),
        ..._signature(20, 132, 60, 'الدافع'),
        _line(8, 150, 194, t: 0.4, color: _grey, dashed: true),
        _text(8, 152, 194, 5, 'طُبع في {printedAt}', fs: 8, align: 'center', color: _grey),
      ]);

  static InvoiceLayout _receiptMinimal() => _a4('سند قبض بسيط', [
        ..._header(),
        _line(8, 32.5, 194, t: 0.5, color: _grey),
        _text(8, 36, 194, 12, '{voucherTitle}', fs: 20, bold: true, align: 'center', color: _green),
        _field(140, 50, 62, 7, 'voucherNo'),
        _field(74, 50, 64, 7, 'dateTime', label: 'التاريخ', align: 'center'),
        _field(8, 50, 64, 7, 'boxName', align: 'left'),
        _field(110, 58, 92, 7, 'customer', label: 'استلمنا من السيد', fs: 11, bold: true),
        _field(8, 58, 100, 7, 'voucherReason', label: 'وذلك عن'),
        _table(8, 69, 194, 60, _colsReceipt, borders: 'rows', headerBg: 0xFFDDF0E0),
        _line(8, 133, 194, t: 0.5, color: _grey),
        _box(112, 136, 90, 24, ['voucherAmount', 'discount'],
            mode: 'none', highlight: 'voucherAmount', highlightColor: _green, border: 0, fs: 11, labels: _receiptLabels),
        _box(8, 136, 90, 24, ['previousDebt', 'currentDebt'], mode: 'none', border: 0, fs: 10.5,
            highlight: 'currentDebt', highlightColor: _red, labels: _receiptLabels),
        _field(8, 163, 194, 7, 'amountWords', showLabel: false, align: 'center', fs: 10),
        ..._signature(130, 178, 60, 'المحاسب: {accountant}'),
        ..._signature(20, 178, 60, 'الدافع'),
        _text(8, 280, 194, 5, 'طُبع في {printedAt}', fs: 8, align: 'center', color: _grey),
      ]);

  // ═══════════ 🧾 سند قبض/صرف لتعديل فاتورة نقدية (بلا حساب عميل — نقداً) ═══════════

  static const _cashLabels = {'voucherAmount': 'المبلغ نقداً', 'invoiceNo': 'الفاتورة الأصلية'};

  static InvoiceLayout _cashOfficial() => _a4('سند نقدي رسمي بإطار', [
        _rect(5, 5, 200, 287, border: 1.2, borderColor: _navy, radius: 2),
        _e(ElType.companyName, 112, 10, 88, 11, {'fontSize': 20.0, 'bold': true, 'align': 'right', 'color': _navy}),
        _e(ElType.companyInfo, 112, 21, 88, 15,
            {'fontSize': 9.0, 'align': 'right', 'color': _grey, 'lines': ['description', 'address']}),
        _e(ElType.logo, 88, 9, 34, 26),
        _e(ElType.companyInfo, 10, 10, 74, 24,
            {'fontSize': 9.0, 'align': 'left', 'color': _grey, 'lines': ['phones', 'tax', 'cr']}),
        _rect(58, 38, 94, 11, border: 0, bg: _navy, radius: 2),
        _text(58, 38, 94, 11, '{voucherTitle}', fs: 15, bold: true, align: 'center', color: _white),
        _box(10, 53, 190, 16, ['voucherNo', 'dateTime', 'invoiceNo', 'customer', 'phone', 'paymentType'],
            style: 'grid', cols: 3, mode: 'lines', borderColor: _navy, border: 0.5, fs: 9.5, labels: _cashLabels),
        _field(10, 71, 190, 8, 'voucherReason', label: 'البيان', fs: 10, border: 0.5, borderColor: _navy),
        _table(10, 82, 190, 108, _colsVoucher,
            borders: 'columns', rowH: 7.5, fs: 9.5, headerBg: _navy, headerColor: _white, lineColor: 0xFF546E7A, fill: true),
        _box(106, 194, 94, 30, ['invoiceBefore', 'voucherAmount', 'invoiceAfter'],
            mode: 'lines', title: 'أثر السند على الفاتورة', highlight: 'voucherAmount', borderColor: _navy, fs: 10,
            labels: _cashLabels),
        _rect(10, 194, 92, 30, border: 0.8, borderColor: _navy, bg: _light, radius: 2),
        _text(12, 196, 88, 7, 'المبلغ نقداً', fs: 10, align: 'center', color: _navy),
        _text(12, 204, 88, 14, '{voucherAmount}', fs: 22, bold: true, align: 'center', color: _navy),
        _field(10, 228, 190, 8, 'amountWords', showLabel: false, align: 'center', border: 0.5, borderColor: _navy, fs: 10),
        _text(10, 239, 190, 6, 'يُعتمد هذا السند تعديلاً على الفاتورة رقم {invoiceNo}، ولا يُعدّ فاتورة جديدة.',
            fs: 9, align: 'center', color: _grey),
        ..._signature(140, 252, 50, 'المحاسب: {accountant}'),
        ..._signature(80, 252, 50, 'المدير'),
        ..._signature(20, 252, 50, 'توقيع الزبون'),
        _text(10, 278, 190, 5, 'طُبع في {printedAt} — بواسطة {printedBy}', fs: 8, align: 'center', color: _grey),
        _pageNo(284),
      ]);

  static InvoiceLayout _cashAmount() => _a4('سند نقدي — المبلغ بارز', [
        ..._header(nameColor: _navy),
        _line(8, 32.5, 194, color: _navy),
        _rect(8, 36, 70, 30, border: 0, bg: _navy, radius: 2),
        _text(10, 37, 66, 8, '{voucherTitle}', fs: 11, bold: true, align: 'center', color: _white),
        _text(10, 46, 66, 14, '{voucherAmount}', fs: 22, bold: true, align: 'center', color: _white),
        _text(10, 59, 66, 6, 'دينار عراقي — نقداً', fs: 8.5, align: 'center', color: _white),
        _box(82, 36, 120, 30, ['voucherNo', 'invoiceNo', 'dateTime', 'customer'],
            mode: 'lines', borderColor: _navy, border: 0.6, radius: 1.5, fs: 10, labels: _cashLabels),
        _field(8, 70, 194, 8, 'voucherReason', label: 'البيان', border: 0.5, borderColor: _grey, radius: 1.5),
        _table(8, 82, 194, 110, _colsVoucher, borders: 'rows', zebra: true, headerBg: _navy, headerColor: _white),
        _box(8, 196, 194, 22, ['invoiceBefore', 'voucherAmount', 'invoiceAfter'],
            style: 'grid', cols: 3, mode: 'group', title: 'الفاتورة', highlight: 'invoiceAfter', borderColor: _navy,
            border: 0.8, radius: 1.5, labels: _cashLabels),
        _field(8, 222, 194, 8, 'amountWords', showLabel: false, align: 'center', fs: 10),
        ..._signature(130, 244, 60, 'المحاسب: {accountant}'),
        ..._signature(20, 244, 60, 'توقيع الزبون'),
        _text(8, 278, 194, 6, '{footer}', fs: 9, align: 'center', color: _grey),
        _pageNo(287),
      ]);

  static InvoiceLayout _cashMinimal() => _a4('سند نقدي بسيط', [
        ..._header(),
        _line(8, 32.5, 194, t: 0.5, color: _grey),
        _text(8, 36, 194, 12, '{voucherTitle}', fs: 19, bold: true, align: 'center', color: _navy),
        _field(140, 50, 62, 7, 'voucherNo'),
        _field(74, 50, 64, 7, 'dateTime', label: 'التاريخ', align: 'center'),
        _field(8, 50, 64, 7, 'invoiceNo', label: 'الفاتورة الأصلية', align: 'left'),
        _field(110, 58, 92, 7, 'customer', label: 'السيد', fs: 11, bold: true),
        _field(8, 58, 100, 7, 'voucherReason', label: 'البيان'),
        _table(8, 69, 194, 120, _colsVoucher, borders: 'rows', headerBg: 0xFFDDE7F0),
        _line(8, 193, 194, t: 0.5, color: _grey),
        _box(8, 196, 194, 14, ['invoiceBefore', 'voucherAmount', 'invoiceAfter'],
            style: 'grid', cols: 3, mode: 'none', highlight: 'voucherAmount', border: 0, fs: 10.5, labels: _cashLabels),
        _field(8, 213, 194, 7, 'amountWords', showLabel: false, align: 'center', fs: 9.5),
        ..._signature(130, 232, 60, 'المحاسب'),
        ..._signature(20, 232, 60, 'توقيع الزبون'),
        _text(8, 280, 194, 5, 'طُبع في {printedAt}', fs: 8, align: 'center', color: _grey),
      ]);

  // ═══════════ ⚫ أبيض وأسود — للطابعات بلا ألوان (ليزر/نقطية): خطوط سوداء بلا تعبئة ═══════════

  static InvoiceLayout _bw(InvoiceLayout l) => l..mono = true;

  /// مربع بيانات/مجاميع بلا تعبئة: عنوان أسود على أبيض، بلا تظليل للبند البارز
  static LayoutElement _bwB(LayoutElement e) {
    e.props['titleBg'] = _white;
    e.props['titleColor'] = _black;
    e.props['highlight'] = '';
    e.props['borderColor'] = _black;
    return e;
  }

  static List<LayoutElement> _bwHeader() => [
        _e(ElType.logo, 8, 5, 30, 24),
        _e(ElType.companyName, 42, 5, 160, 13, {'fontSize': 24.0, 'bold': true, 'align': 'right', 'color': _black}),
        _e(ElType.companyInfo, 42, 18, 160, 13, {
          'fontSize': 9.5,
          'align': 'right',
          'color': _black,
          'lines': ['description', 'address', 'phones'],
        }),
        _line(8, 32.5, 194, t: 1.2),
      ];

  static List<LayoutElement> _bwTitle(double y) => [
        _rect(58, y, 94, 11, border: 1.4, borderColor: _black),
        _text(58, y, 94, 11, '{voucherTitle}', fs: 15, bold: true, align: 'center'),
      ];

  static List<LayoutElement> _bwSig(double x, double y, double w, String label) => [
        _text(x, y, w, 5, label, fs: 9.5, align: 'center'),
        _line(x + 4, y + 10, w - 8, t: 0.6),
      ];

  static InvoiceLayout _receiptBW() => _bw(_a4('سند قبض — أبيض وأسود', [
        ..._bwHeader(),
        ..._bwTitle(36),
        _bwB(_box(8, 50, 194, 16, ['voucherNo', 'dateTime', 'customer', 'phone', 'boxName', 'docNo'],
            style: 'grid', cols: 3, mode: 'lines', border: 0.6, fs: 9.5)),
        _field(8, 68, 194, 8, 'voucherReason', label: 'البيان', border: 0.6, borderColor: _black),
        _table(8, 79, 194, 70, _colsReceipt, borders: 'grid', headerBg: _white, headerColor: _black, lineColor: _black),
        _bwB(_box(106, 153, 96, 26, ['voucherAmount', 'discount'],
            mode: 'lines', title: 'المبلغ', border: 0.8, fs: 11, labels: _receiptLabels)),
        _bwB(_box(8, 153, 94, 26, ['previousDebt', 'currentDebt'],
            mode: 'lines', title: 'حساب العميل', border: 0.8, fs: 10.5, labels: _receiptLabels)),
        _field(8, 183, 194, 8, 'amountWords', showLabel: false, align: 'center', border: 0.6, borderColor: _black, fs: 10.5),
        ..._bwSig(140, 200, 50, 'المحاسب: {accountant}'),
        ..._bwSig(80, 200, 50, 'المدير'),
        ..._bwSig(20, 200, 50, 'الدافع: {customer}'),
        _text(8, 280, 194, 5, 'طُبع في {printedAt} — بواسطة {printedBy}', fs: 8, align: 'center'),
      ]));

  static InvoiceLayout _cashBW() => _bw(_a4('سند نقدي — أبيض وأسود', [
        ..._bwHeader(),
        ..._bwTitle(36),
        _bwB(_box(8, 50, 194, 16, ['voucherNo', 'dateTime', 'invoiceNo', 'customer', 'phone', 'paymentType'],
            style: 'grid', cols: 3, mode: 'lines', border: 0.6, fs: 9.5, labels: _cashLabels)),
        _field(8, 68, 194, 8, 'voucherReason', label: 'البيان', border: 0.6, borderColor: _black),
        _table(8, 79, 194, 110, _colsVoucher, borders: 'grid', headerBg: _white, headerColor: _black, lineColor: _black),
        _bwB(_box(8, 193, 194, 22, ['invoiceBefore', 'voucherAmount', 'invoiceAfter'],
            style: 'grid', cols: 3, mode: 'group', title: 'أثر السند على الفاتورة', border: 0.8, fs: 11,
            labels: _cashLabels)),
        _field(8, 219, 194, 8, 'amountWords', showLabel: false, align: 'center', border: 0.6, borderColor: _black, fs: 10.5),
        ..._bwSig(140, 236, 50, 'المحاسب: {accountant}'),
        ..._bwSig(80, 236, 50, 'المدير'),
        ..._bwSig(20, 236, 50, 'توقيع الزبون: {customer}'),
        _text(8, 280, 194, 5, 'طُبع في {printedAt} — بواسطة {printedBy}', fs: 8, align: 'center'),
      ]));

  static InvoiceLayout _noteBW() => _bw(_a4('إشعار — أبيض وأسود', [
        ..._bwHeader(),
        ..._bwTitle(36),
        _bwB(_box(8, 50, 194, 16, ['voucherNo', 'dateTime', 'invoiceNo', 'customer', 'phone', 'paymentType'],
            style: 'grid', cols: 3, mode: 'lines', border: 0.6, fs: 9.5, labels: {'invoiceNo': 'الفاتورة الأصلية'})),
        _field(8, 68, 194, 8, 'voucherReason', label: 'البيان', border: 0.6, borderColor: _black),
        _table(8, 79, 194, 110, _colsVoucher, borders: 'grid', headerBg: _white, headerColor: _black, lineColor: _black),
        _bwB(_box(106, 193, 96, 30, ['invoiceBefore', 'voucherAmount', 'invoiceAfter'],
            mode: 'lines', title: 'أثر الإشعار على الفاتورة', border: 0.8, fs: 10.5)),
        _bwB(_box(8, 193, 94, 30, ['previousDebt', 'currentDebt'],
            mode: 'lines', title: 'حساب العميل', border: 0.8, fs: 10.5,
            labels: {'previousDebt': 'الرصيد قبل الإشعار', 'currentDebt': 'الرصيد بعد الإشعار'})),
        _field(8, 227, 194, 8, 'amountWords', showLabel: false, align: 'center', border: 0.6, borderColor: _black, fs: 10.5),
        ..._bwSig(140, 242, 50, 'المحاسب: {accountant}'),
        ..._bwSig(80, 242, 50, 'المدير'),
        ..._bwSig(20, 242, 50, 'توقيع العميل'),
        _text(8, 280, 194, 5, 'طُبع في {printedAt} — بواسطة {printedBy}', fs: 8, align: 'center'),
      ]));

  /// فاتورة A4 أبيض وأسود
  static InvoiceLayout _a4BW() => _bw(_a4('أبيض وأسود', [
        ..._bwHeader(),
        ..._fields(36),
        _table(8, 53, 194, 150, _colsStd, borders: 'grid', headerBg: _white, headerColor: _black, lineColor: _black),
        _bwB(_box(106, 207, 96, 44, ['beforeDiscount', 'discount', 'loadingFee', 'net', 'paid', 'remaining'],
            mode: 'lines', title: 'ملخص الفاتورة', border: 0.8, fs: 10)),
        _bwB(_box(8, 207, 94, 24, ['previousDebt', 'currentDebt'],
            mode: 'lines', title: 'حساب العميل', border: 0.8, fs: 10)),
        _field(8, 235, 94, 8, 'amountWords', showLabel: false, align: 'center', fs: 9.5),
        ..._bwSig(140, 258, 50, 'المحاسب: {accountant}'),
        ..._bwSig(80, 258, 50, 'المجهز: {preparer}'),
        ..._bwSig(20, 258, 50, 'المستلم'),
        _text(8, 276, 194, 5, '{footer}', fs: 9, align: 'center'),
        _pageNo(284),
      ]));

  // ─────────────────────────── قوالب السندات حسب النوع ───────────────────────────

  /// قوالب نوع سند ('receipt', 'cash_receipt', 'cash_refund', 'debit_note', 'credit_note').
  static List<LayoutTemplate> forKind(String kind) => switch (kind) {
        'receipt' => [
            const LayoutTemplate('vr_official', 'رسمي بإطار',
                'إطار أخضر، بيانات السند في جدول، العملاء والمبالغ، المبلغ وحساب العميل في مربعين، المبلغ كتابةً وثلاثة تواقيع',
                _receiptOfficial),
            const LayoutTemplate('vr_amount', 'المبلغ بارز (نصف صفحة)',
                'المبلغ كبير في مربع ملوّن، الرصيد قبل وبعد، توقيعان — يكفي نصف الصفحة', _receiptAmount),
            const LayoutTemplate('vr_minimal', 'بسيط', '«استلمنا من السيد… وذلك عن…» بخطوط خفيفة', _receiptMinimal),
            const LayoutTemplate('vr_bw', 'أبيض وأسود', 'للطابعات بلا ألوان: خطوط سوداء بلا تعبئة، والدافع والمحاسب', _receiptBW),
            LayoutTemplate('blank', 'ورقة بيضاء', 'صمّم كل شيء بنفسك من قائمة العناصر', () => _blank(LayoutPaper.a4)),
          ],
        'cash_receipt' || 'cash_refund' => [
            const LayoutTemplate('vc_official', 'رسمي بإطار',
                'المواد التي تغيّرت، أثر السند على الفاتورة، والمبلغ نقداً في مربع بارز، وثلاثة تواقيع', _cashOfficial),
            const LayoutTemplate('vc_amount', 'المبلغ بارز', 'المبلغ نقداً في مربع ملوّن، والفاتورة قبل وبعد في صف', _cashAmount),
            const LayoutTemplate('vc_minimal', 'بسيط', 'بخطوط خفيفة بلا مربعات', _cashMinimal),
            const LayoutTemplate('vc_bw', 'أبيض وأسود', 'للطابعات بلا ألوان: خطوط سوداء بلا تعبئة', _cashBW),
            LayoutTemplate('blank', 'ورقة بيضاء', 'صمّم كل شيء بنفسك من قائمة العناصر', () => _blank(LayoutPaper.a4)),
          ],
        _ => [
            const LayoutTemplate('v_official', 'إشعار رسمي بإطار',
                'النوع بارز، رقم السند والفاتورة الأصلية، البنود، أثره على الفاتورة وحساب العميل، وثلاثة تواقيع',
                _voucherOfficial),
            const LayoutTemplate('v_amount', 'المبلغ بارز', 'مبلغ الإشعار في مربع كبير، والفاتورة وحساب العميل في مربعين', _voucherAmount),
            const LayoutTemplate('v_minimal', 'بسيط', 'بخطوط خفيفة بلا مربعات', _voucherMinimal),
            const LayoutTemplate('v_bw', 'أبيض وأسود', 'للطابعات بلا ألوان: خطوط سوداء بلا تعبئة', _noteBW),
            LayoutTemplate('blank', 'ورقة بيضاء', 'صمّم كل شيء بنفسك من قائمة العناصر', () => _blank(LayoutPaper.a4)),
          ],
      };

  /// قالب البرنامج لنوع سند إن لم يُختر تصميم وليس له شكل قديم.
  static InvoiceLayout defaultFor(String kind) => switch (kind) {
        'receipt' => _receiptOfficial(),
        'cash_receipt' || 'cash_refund' => _cashOfficial(),
        _ => _voucherOfficial(),
      };

  // ─────────────────────────── القائمة ───────────────────────────

  static List<LayoutTemplate> forPaper(LayoutPaper paper) => switch (paper) {
        LayoutPaper.a4 => [
            const LayoutTemplate('a4_default', 'النموذج الأصلي للبرنامج',
                'تخطيط الفاتورة التي يطبعها البرنامج حين لا يُفعَّل تصميم: الاسم والشعار في الرأس، سطر السيد والعنوان والهاتف ورقم الفاتورة والتاريخ، الجدول، المجاميع في سطرين، التنويه، واسم الشركة علامة مائية',
                _a4Default),
            const LayoutTemplate('a4_alnasser', 'الناصر (فاتورة debt_book)',
                'شكل فاتورة برنامج سجل الديون: الختم (نقد/دين) مع QR، سطر بيانات واحد، جدول ت/ID/التفاصيل/العدد/التعبئة، المجاميع في سطرين، التنويه، والمجهز والمحاسب',
                _a4AlNasser),
            const LayoutTemplate('a4_official', 'رسمية بإطار', 'إطار للصفحة، عنوان «فاتورة مبيعات»، بيانات في جدول، مربع ملخص الفاتورة ومربع حساب العميل، وتواقيع', _a4Official),
            const LayoutTemplate('a4_two_boxes', 'مربع الفاتورة ومربع الدين', 'الإجمالي والخصم وبعد الخصم في مربع، والدين السابق والمطلوب في مربع، والمتبقي في مربع منفرد', _a4TwoBoxes),
            const LayoutTemplate('a4_boxes', 'مربعات منفردة', 'كل مبلغ في مربعه: ثلاث فوق بعض في كل جهة', _a4Boxes),
            const LayoutTemplate('a4_amount_due', 'المطلوب بارز', 'مربع كبير للمبلغ المطلوب أعلى الفاتورة، وبيانات العميل مربعات', _a4AmountDue),
            const LayoutTemplate('a4_classic', 'كلاسيكي', 'الشعار واسم الشركة في الأعلى، والملخص في مربع بخطوط فاصلة', _a4Classic),
            const LayoutTemplate('a4_minimal', 'بسيط أنيق', 'بلا مربعات: خطوط خفيفة ومساحات بيضاء والصافي بلون بارز', _a4Minimal),
            const LayoutTemplate('a4_modern', 'حديث', 'شريط ملوّن في الرأس، الصافي في مربع ملوّن، ورمز QR', _a4Modern),
            const LayoutTemplate('a4_green', 'زوايا مستديرة', 'مربعات بزوايا مستديرة ولون أخضر', _a4Green),
            const LayoutTemplate('a4_wholesale', 'جملة ومستودع', 'أعمدة كثيرة (الوحدة، عدد الوحدات، الوزن) ومجاميع في صف، وثلاثة تواقيع', _a4Wholesale),
            const LayoutTemplate('a4_compact', 'مضغوط', 'رأس صغير وصفوف أكثر في الصفحة', _a4Compact),
            const LayoutTemplate('a4_bw', 'أبيض وأسود', 'للطابعات بلا ألوان: خطوط سوداء، مربعات بلا تعبئة، وتواقيع', _a4BW),
            // 🧾 قوالب السندات صارت في «مصمم السندات» (لكل نوع قوالبه)
            LayoutTemplate('blank', 'ورقة بيضاء', 'صمّم كل شيء بنفسك من قائمة العناصر', () => _blank(LayoutPaper.a4)),
          ],
        LayoutPaper.roll80 => [
            LayoutTemplate('r80_basic', 'إيصال كاشير', 'مختصر وواضح للبيع السريع', () => _roll(LayoutPaper.roll80, 'basic')),
            LayoutTemplate('r80_boxed', 'إيصال بإطار', 'المجموع في مربع، والصافي بخط كبير في مربع', () => _roll(LayoutPaper.roll80, 'boxed')),
            LayoutTemplate('r80_debt', 'إيصال دين', 'مربع الفاتورة ومربع حساب العميل (السابق والمطلوب)', () => _roll(LayoutPaper.roll80, 'debt')),
            LayoutTemplate('r80_market', 'سوبرماركت', 'خطوط بين المواد، الإجمالي البارز، وباركود رقم الفاتورة', () => _roll(LayoutPaper.roll80, 'market')),
            LayoutTemplate('r80_detailed', 'إيصال مفصّل', 'التسلسل والوحدة والمبلغ كتابةً ورمز QR', () => _roll(LayoutPaper.roll80, 'detailed')),
            LayoutTemplate('blank', 'ورقة بيضاء', 'صمّم كل شيء بنفسك من قائمة العناصر', () => _blank(LayoutPaper.roll80)),
          ],
        LayoutPaper.roll58 => [
            LayoutTemplate('r58_basic', 'إيصال صغير', 'للطابعات الحرارية الصغيرة', () => _roll(LayoutPaper.roll58, 'basic')),
            LayoutTemplate('r58_boxed', 'صغير بإطار', 'الصافي بخط كبير في مربع', () => _roll(LayoutPaper.roll58, 'boxed')),
            LayoutTemplate('r58_debt', 'صغير مع الدين', 'مع حساب العميل', () => _roll(LayoutPaper.roll58, 'debt')),
            LayoutTemplate('blank', 'ورقة بيضاء', 'صمّم كل شيء بنفسك من قائمة العناصر', () => _blank(LayoutPaper.roll58)),
          ],
      };

  static InvoiceLayout _blank(LayoutPaper p) =>
      InvoiceLayout(id: InvoiceLayout.newId('L'), name: 'ورقة بيضاء', paper: p, elements: []);

  // ─────────────────────────── A4 ───────────────────────────

  /// 🧾 النموذج الأصلي للبرنامج (ما يُطبع بلا تصميم مفعّل — invoice_actions.dart):
  /// الرأس (اسم الشركة كبيراً في الوسط مع الوصف والعنوان والهواتف، والشعار
  /// يساراً)، سطر البيانات، الجدول، المجاميع في سطرين، التنويه، ورقم الصفحة،
  /// واسم الشركة علامة مائية مائلة. نقطة بداية للتعديل بالسحب.
  static InvoiceLayout _a4Default() {
    List<Map<String, dynamic>> cols(List<List<Object>> c) => [
          for (final x in c) <String, dynamic>{'id': x[0], 'label': x[1], 'flex': x[2], 'align': x[0] == 'details' ? 'right' : 'center'}
        ];
    return _a4('النموذج الأصلي للبرنامج', [
      _e(ElType.watermark, 20, 95, 170, 120, {'opacity': 0.11, 'angle': 0.8, 'fontSize': 200.0, 'color': 0xFFBDBDBD}),
      // الرأس: الاسم والوصف والعنوان والهواتف في الوسط-اليمين، والشعار يساراً
      _e(ElType.logo, 4, 2, 50, 50),
      _e(ElType.companyName, 58, 2, 148, 17, {'fontSize': 45.0, 'bold': true, 'align': 'center', 'color': _green}),
      _e(ElType.companyInfo, 58, 19, 148, 8, {'fontSize': 17.0, 'align': 'center', 'color': _black, 'lines': ['description']}),
      _e(ElType.companyInfo, 58, 27, 148, 13,
          {'fontSize': 13.0, 'align': 'center', 'color': _black, 'lines': ['address', 'phones', 'tax', 'cr']}),
      // سطر البيانات
      _field(160, 54, 46, 7, 'customer', label: 'السيد', fs: 11),
      _field(126, 54, 33, 7, 'address', label: 'العنوان', fs: 11),
      _field(90, 54, 35, 7, 'phone', label: 'الهاتف', fs: 11),
      _field(48, 54, 41, 7, 'invoiceNo', label: 'رقم الفاتورة', fs: 11),
      _field(4, 54, 43, 7, 'dateTime', label: 'التاريخ', fs: 11, align: 'left'),
      _line(4, 62, 202, t: 0.5),
      // الجدول
      _table(4, 64, 202, 179, cols([
        ['serial', 'ت', 0.4],
        ['productId', 'ID', 0.8],
        ['details', 'التفاصيل', 3.0],
        ['quantity', 'العدد', 1.6],
        ['unitsCount', 'التعبئة', 1.1],
        ['price', 'السعر', 1.2],
        ['amount', 'المبلغ', 1.5],
      ]),
          borders: 'grid', rowH: 8.5, fs: 10.5, headerBg: _white, headerColor: _black, lineColor: _black),
      _line(4, 245, 202, t: 0.4),
      // المجاميع في سطرين
      _box(4, 247, 202, 8, ['beforeDiscount', 'discount', 'afterDiscount', 'paid'],
          style: 'row', mode: 'none', border: 0, labelPos: 'side', fs: 11,
          labels: {'beforeDiscount': 'الإجمالي قبل الخصم', 'afterDiscount': 'الإجمالي بعد الخصم', 'paid': 'المبلغ المدفوع'}),
      _box(56, 257, 150, 8, ['remaining', 'currentDebt', 'loadingFee'],
          style: 'row', mode: 'none', border: 0, labelPos: 'side', fs: 11,
          labels: {'remaining': 'المبلغ المتبقي', 'currentDebt': 'المبلغ المطلوب الحالي', 'loadingFee': 'أجور التحميل'}),
      _text(4, 268, 202, 6,
          'تنويه: أي ملاحظات على تجهيز المواد تُقبل خلال 3 أيام من تاريخ الفاتورة فقط وشكراً لتعاملكم معنا',
          fs: 11, align: 'center', color: _red),
      _pageNo(289),
    ]);
  }

  /// 🧾 شكل فاتورة debt_book (generateInvoicePdf هناك) بعناصر المصمم — يُعدَّل بالسحب
  static InvoiceLayout _a4AlNasser() {
    List<Map<String, dynamic>> cols(List<List<Object>> c) => [
          for (final x in c) <String, dynamic>{'id': x[0], 'label': x[1], 'flex': x[2], 'align': x[0] == 'details' ? 'right' : 'center'}
        ];
    return _a4('الناصر (فاتورة debt_book)', [
      _e(ElType.watermark, 20, 95, 170, 120, {'opacity': 0.11, 'angle': 0.8, 'fontSize': 200.0, 'color': 0xFFBDBDBD}),
      // الرأس: الشعار يميناً، الاسم والنشاط في الوسط، ختم الدفع مع QR يساراً
      _e(ElType.logo, 172, 4, 32, 26),
      _e(ElType.companyName, 50, 3, 118, 16, {'fontSize': 34.0, 'bold': true, 'align': 'center', 'color': _green}),
      _e(ElType.companyInfo, 50, 19, 118, 11,
          {'fontSize': 9.5, 'align': 'center', 'color': _grey, 'lines': ['description', 'address', 'phones']}),
      _rect(8, 7, 42, 18, border: 1.5, borderColor: _navy, radius: 2),
      _text(9, 9, 22, 14, '{paymentType}', fs: 19, bold: true, align: 'center', color: _navy),
      // QR بكل بيانات الفاتورة: الرقم، التاريخ والوقت، السيد، الهاتف
      _e(ElType.barcode, 32, 7.5, 17, 17, {'data': 'invoiceInfo', 'kind': 'qr'}),
      _line(8, 31, 194, t: 0.5),
      // سطر البيانات
      _field(150, 33, 52, 7, 'customer', label: 'السيد', fs: 11.5),
      _field(118, 33, 31, 7, 'address', fs: 10.5),
      _field(82, 33, 35, 7, 'invoiceNo', fs: 10),
      _field(46, 33, 35, 7, 'phone', fs: 10.5),
      _field(8, 33, 37, 7, 'dateTime', label: 'التاريخ', fs: 10.5, align: 'left'),
      _line(8, 41, 194, t: 0.5),
      // الجدول
      _table(8, 43, 194, 200, cols([
        ['serial', 'ت', 0.4],
        ['productId', 'ID', 0.8],
        ['details', 'التفاصيل', 3.0],
        ['quantity', 'العدد', 1.6],
        ['unitsCount', 'التعبئة', 1.1],
        ['price', 'السعر', 1.2],
        ['amount', 'المبلغ', 1.5],
      ]),
          borders: 'grid', rowH: 8.5, fs: 10.5, headerBg: _white, headerColor: _black, lineColor: _black),
      _line(8, 245, 194, t: 0.4),
      // المجاميع في سطرين كما في debt_book
      _box(8, 247, 194, 8, ['beforeDiscount', 'discount', 'afterDiscount', 'paid'],
          style: 'row', mode: 'none', border: 0, labelPos: 'side', fs: 10.5),
      _box(56, 256, 146, 8, ['remaining', 'currentDebt', 'loadingFee'],
          style: 'row', mode: 'none', border: 0, labelPos: 'side', fs: 10.5,
          labels: {'remaining': 'المبلغ المتبقي', 'currentDebt': 'المبلغ المطلوب الحالي', 'loadingFee': 'أجور التحميل'}),
      _text(8, 266, 194, 6,
          'تنويه: أي ملاحظات على تجهيز المواد تُقبل خلال 3 أيام من تاريخ الفاتورة فقط وشكراً لتعاملكم معنا',
          fs: 10.5, align: 'center', color: _red),
      ..._signature(146, 274, 56, 'المجهز: {preparer}'),
      ..._signature(77, 274, 56, 'المحاسب: {accountant}'),
      ..._signature(8, 274, 56, 'توقيع المستلم'),
      _pageNo(289),
    ]);
  }

  static InvoiceLayout _a4Official() => _a4('رسمية بإطار', [
        _rect(5, 5, 200, 287, border: 1.2, borderColor: _navy, radius: 2),
        _e(ElType.companyName, 112, 10, 88, 11, {'fontSize': 20.0, 'bold': true, 'align': 'right', 'color': _navy}),
        _e(ElType.companyInfo, 112, 21, 88, 15,
            {'fontSize': 9.0, 'align': 'right', 'color': _grey, 'lines': ['description', 'address']}),
        _e(ElType.logo, 88, 9, 34, 26),
        _e(ElType.companyInfo, 10, 10, 74, 24,
            {'fontSize': 9.0, 'align': 'left', 'color': _grey, 'lines': ['phones', 'tax', 'cr']}),
        _rect(75, 37, 60, 9, border: 0, bg: _navy, radius: 2),
        _text(75, 37, 60, 9, 'فاتورة مبيعات', fs: 14, bold: true, align: 'center', color: _white),
        _box(10, 49, 190, 15, ['customer', 'invoiceNo', 'phone', 'dateTime', 'address', 'paymentType'],
            style: 'grid', cols: 3, mode: 'lines', borderColor: _navy, border: 0.5, fs: 9.5),
        _table(10, 67, 190, 161, _colsStd,
            borders: 'columns', rowH: 7.5, fs: 9.5, headerBg: _navy, headerColor: _white, lineColor: 0xFF546E7A, fill: true),
        _box(106, 231, 94, 29, ['beforeDiscount', 'discount', 'net'],
            mode: 'lines', title: 'ملخص الفاتورة', highlight: 'net', borderColor: _navy, fs: 9.5),
        _box(10, 231, 92, 29, ['previousDebt', 'paid', 'currentDebt'],
            mode: 'lines', title: 'حساب العميل', titleBg: _grey, highlight: 'currentDebt', highlightColor: _red,
            borderColor: _navy, fs: 9.5),
        _field(10, 262, 190, 7, 'amountWords', showLabel: false, align: 'center', border: 0.5, borderColor: _navy, fs: 9.5),
        ..._signature(140, 272, 50, 'توقيع المستلم'),
        ..._signature(20, 272, 50, 'المحاسب: {accountant}'),
        _pageNo(285),
      ]);

  static InvoiceLayout _a4TwoBoxes() => _a4('مربع الفاتورة ومربع الدين', [
        ..._header(),
        _line(8, 32.5, 194, t: 1, color: _navy),
        ..._fields(35),
        _table(8, 52, 194, 172, _colsStd, borders: 'rows', zebra: true, headerBg: _navy, headerColor: _white),
        _box(106, 227, 96, 30, ['beforeDiscount', 'discount', 'afterDiscount'],
            mode: 'group', title: 'الفاتورة', highlight: 'afterDiscount', borderColor: _navy, border: 0.8, radius: 1.5),
        _box(8, 227, 94, 30, ['previousDebt', 'paid', 'currentDebt'],
            mode: 'group', title: 'الدين', titleBg: _grey, highlight: 'currentDebt', highlightColor: _red,
            borderColor: _grey, border: 0.8, radius: 1.5),
        _field(106, 259, 96, 7, 'paymentType', label: 'طريقة الدفع', border: 0.6, borderColor: _navy, radius: 1.5),
        _box(8, 259, 94, 7, ['remaining'], mode: 'each', border: 0.6, borderColor: _navy, radius: 1.5),
        _field(8, 269, 194, 7, 'amountWords', showLabel: false, align: 'center', fs: 9.5),
        _text(8, 278, 194, 6, '{footer}', fs: 9, align: 'center', color: _grey),
        _pageNo(287),
      ]);

  static InvoiceLayout _a4Boxes() => _a4('مربعات منفردة', [
        ..._header(),
        _line(8, 32.5, 194, color: _grey),
        ..._fields(35),
        _table(8, 52, 194, 168, _colsStd, headerBg: 0xFFDDE7F0),
        _box(8, 224, 194, 42, ['beforeDiscount', 'discount', 'net', 'paid', 'remaining', 'currentDebt'],
            style: 'grid', cols: 2, mode: 'each', highlight: 'net', radius: 1.5, fs: 11),
        _field(8, 268, 194, 7, 'amountWords', showLabel: false, align: 'center', border: 0.4),
        _text(8, 277, 194, 7, '{footer}', fs: 9.5, align: 'center', color: _grey),
        _pageNo(287),
      ]);

  static InvoiceLayout _a4AmountDue() => _a4('المطلوب بارز', [
        ..._header(nameColor: _navy),
        _line(8, 32.5, 194, color: _navy),
        _rect(8, 36, 62, 24, border: 0, bg: _navy, radius: 2),
        _text(10, 37, 58, 7, 'المبلغ المطلوب', fs: 10, align: 'center', color: _white),
        _text(10, 44, 58, 13, '{net}', fs: 20, bold: true, align: 'center', color: _white),
        _box(74, 36, 128, 24, ['customer', 'invoiceNo', 'phone', 'dateTime'],
            style: 'grid', cols: 2, mode: 'each', radius: 1.5, border: 0.5),
        _table(8, 64, 194, 164, _colsStd, headerBg: 0xFFE3F2FD, headerColor: _navy, zebra: true),
        _box(8, 232, 104, 32, ['beforeDiscount', 'discount', 'paid', 'remaining'],
            style: 'grid', cols: 2, mode: 'each', radius: 1.5),
        _box(116, 232, 86, 32, ['previousDebt', 'net', 'currentDebt'],
            mode: 'lines', title: 'حساب العميل', highlight: 'currentDebt', highlightColor: _red, borderColor: _navy,
            labels: {'net': 'هذه الفاتورة'}),
        _field(8, 266, 194, 7, 'amountWords', showLabel: false, align: 'center', border: 0.4),
        _text(8, 276, 194, 7, '{footer}', fs: 9.5, align: 'center', color: _grey),
        _pageNo(287),
      ]);

  static InvoiceLayout _a4Classic() => _a4('كلاسيكي', [
        _e(ElType.watermark, 25, 95, 160, 110, {'opacity': 0.07, 'angle': 0.8, 'fontSize': 110.0}),
        ..._header(),
        _line(8, 32.5, 194, t: 1.2, color: _green),
        ..._fields(35),
        _table(8, 52, 194, 178, _colsStd),
        _box(8, 234, 92, 44, ['beforeDiscount', 'discount', 'afterDiscount', 'paid', 'remaining', 'currentDebt'],
            mode: 'lines', title: 'ملخص الفاتورة', titleBg: _green, highlight: 'afterDiscount', highlightColor: _green,
            fs: 10),
        _field(104, 234, 98, 12, 'amountWords', showLabel: false, fs: 9.5, border: 0.4),
        _text(104, 262, 98, 12, '{footer}', fs: 9.5, color: _grey),
        _pageNo(286),
      ]);

  static InvoiceLayout _a4Minimal() => _a4('بسيط أنيق', [
        _e(ElType.logo, 8, 8, 26, 22),
        _text(36, 8, 50, 13, 'فاتورة', fs: 26, bold: true, align: 'left', color: _navy),
        _field(36, 21, 50, 6, 'invoiceNo', label: 'رقم', align: 'left'),
        _field(36, 27, 50, 6, 'date', align: 'left', fs: 9.5, color: _grey),
        _e(ElType.companyName, 90, 8, 112, 12, {'fontSize': 22.0, 'bold': true, 'align': 'right', 'color': _navy}),
        _e(ElType.companyInfo, 90, 20, 112, 14,
            {'fontSize': 9.0, 'align': 'right', 'color': _grey, 'lines': ['address', 'phones', 'tax']}),
        _line(8, 38, 194, t: 0.5, color: 0xFFB0BEC5),
        _text(150, 41, 52, 6, 'إلى السيد', fs: 9, color: _grey),
        _field(100, 47, 102, 7, 'customer', showLabel: false, fs: 12, bold: true),
        _field(100, 54, 102, 6, 'phone', showLabel: false, fs: 9.5),
        _field(100, 60, 102, 6, 'address', showLabel: false, fs: 9.5, color: _grey),
        _field(8, 47, 70, 7, 'paymentType', label: 'الدفع', align: 'left'),
        _table(8, 70, 194, 160, _colsSimple, borders: 'rows', headerBg: 0, headerColor: _navy, lineColor: 0xFFCFD8DC),
        _box(8, 234, 80, 27, ['beforeDiscount', 'discount', 'net'], mode: 'none', highlight: 'net', fs: 10.5),
        _text(110, 234, 92, 6, 'ملاحظات', fs: 10, bold: true, color: _navy),
        _text(110, 240, 92, 16, '{footer}', fs: 9.5, color: _grey),
        _line(8, 277, 194, t: 0.5, color: 0xFFB0BEC5),
        _text(8, 279, 194, 6, 'شكراً لتعاملكم معنا', fs: 10, align: 'center', color: _navy),
        _e(ElType.pageNo, 8, 287, 40, 5, {'fontSize': 8.0, 'align': 'left', 'color': _grey}),
      ]);

  static InvoiceLayout _a4Modern() => _a4('حديث', [
        _rect(0, 0, 210, 34, border: 0, bg: _navy),
        ..._header(nameColor: _white, infoColor: _white),
        _rect(8, 38, 194, 18, border: 0.6, borderColor: _navy, radius: 2),
        ..._fields(39.5),
        _table(8, 60, 194, 170, _colsStd, headerBg: _navy, headerColor: _white, zebra: true),
        _box(8, 234, 90, 40, ['beforeDiscount', 'discount', 'loadingFee', 'paid', 'remaining'], mode: 'lines', fs: 10),
        _rect(102, 234, 70, 22, border: 0, bg: _navy, radius: 2),
        _text(104, 235, 66, 7, 'الصافي للدفع', fs: 10, align: 'center', color: _white),
        _text(104, 242, 66, 12, '{net}', fs: 20, bold: true, align: 'center', color: _white),
        _e(ElType.barcode, 176, 234, 26, 26, {'kind': 'qr', 'data': 'invoiceInfo'}),
        _field(102, 258, 100, 10, 'amountWords', showLabel: false, fs: 9),
        _text(8, 278, 194, 7, '{footer}', fs: 9.5, align: 'center', color: _grey),
        _pageNo(287),
      ]);

  static InvoiceLayout _a4Green() => _a4('زوايا مستديرة', [
        _rect(8, 5, 194, 30, border: 0.8, borderColor: _green, radius: 3),
        _e(ElType.logo, 11, 8, 26, 24),
        _e(ElType.companyName, 40, 7, 159, 12, {'fontSize': 22.0, 'bold': true, 'align': 'right', 'color': _green}),
        _e(ElType.companyInfo, 40, 19, 159, 13,
            {'fontSize': 9.0, 'align': 'right', 'color': _grey, 'lines': ['description', 'address', 'phones']}),
        _box(8, 38, 194, 16, ['customer', 'phone', 'address', 'invoiceNo', 'dateTime', 'paymentType'],
            style: 'grid', cols: 3, mode: 'each', radius: 2, borderColor: _green, border: 0.5, fs: 9.5),
        _table(8, 58, 194, 170, _colsStd,
            borders: 'outer', headerBg: _green, headerColor: _white, zebra: true, lineColor: _green),
        _box(8, 232, 96, 36, ['beforeDiscount', 'discount', 'net', 'paid', 'remaining'],
            mode: 'group', title: 'ملخص الفاتورة', titleBg: _green, highlight: 'net', highlightColor: _green,
            borderColor: _green, radius: 3, fs: 9.5),
        _box(108, 232, 94, 22, ['previousDebt', 'currentDebt'],
            mode: 'group', title: 'حساب العميل', titleBg: _green, highlight: 'currentDebt', highlightColor: _red,
            borderColor: _green, radius: 3, fs: 9.5),
        _field(108, 257, 94, 11, 'amountWords',
            showLabel: false, align: 'center', fs: 9, border: 0.5, borderColor: _green, radius: 2),
        _text(8, 272, 194, 7, '{footer}', fs: 9.5, align: 'center', color: _green),
        _pageNo(287),
      ]);

  static InvoiceLayout _a4Wholesale() => _a4('جملة ومستودع', [
        _e(ElType.logo, 8, 5, 22, 18),
        _text(32, 6, 56, 8, 'فاتورة جملة', fs: 14, bold: true, align: 'center', color: _navy),
        _field(32, 15, 56, 6, 'invoiceNo', align: 'center'),
        _e(ElType.companyName, 90, 5, 112, 10, {'fontSize': 18.0, 'bold': true, 'align': 'right', 'color': _navy}),
        _e(ElType.companyInfo, 90, 15, 112, 8, {'fontSize': 8.5, 'align': 'right', 'color': _grey, 'lines': ['address', 'phones']}),
        _line(8, 24.5, 194, color: _navy),
        _box(8, 27, 194, 10, ['customer', 'phone', 'address', 'dateTime', 'paymentType'],
            style: 'row', mode: 'lines', borderColor: _navy, border: 0.5, fs: 9),
        _table(8, 40, 194, 205, _colsWholesale, rowH: 7, fs: 8.5),
        _box(8, 248, 194, 14, ['itemsCount', 'beforeDiscount', 'discount', 'net', 'paid', 'remaining', 'currentDebt'],
            style: 'row', mode: 'each', highlight: 'net', fs: 9.5),
        _field(8, 264, 194, 6, 'amountWords', showLabel: false, align: 'center', fs: 9.5),
        ..._signature(150, 272, 52, 'المستلم'),
        ..._signature(79, 272, 52, 'المجهز: {preparer}'),
        ..._signature(8, 272, 52, 'المحاسب: {accountant}'),
        _pageNo(288),
      ]);

  static InvoiceLayout _a4Compact() => _a4('مضغوط', [
        _e(ElType.logo, 8, 5, 18, 14),
        _e(ElType.companyName, 28, 5, 100, 9, {'fontSize': 16.0, 'bold': true, 'align': 'right', 'color': _navy}),
        _e(ElType.companyInfo, 28, 14, 100, 6, {'fontSize': 8.5, 'align': 'right', 'color': _grey, 'lines': ['address', 'phones']}),
        _field(132, 5, 70, 6, 'invoiceNo', bold: true, align: 'left'),
        _field(132, 11.5, 70, 6, 'dateTime', label: 'التاريخ', fs: 9, align: 'left'),
        _line(8, 21, 194, color: _navy),
        _field(110, 23, 92, 6, 'customer', label: 'السيد', bold: true),
        _field(8, 23, 100, 6, 'phone', fs: 9.5, align: 'left'),
        _table(8, 31, 194, 222, _colsStd, rowH: 6.5, fs: 9),
        _box(8, 256, 194, 14, ['beforeDiscount', 'discount', 'net', 'paid', 'remaining', 'currentDebt'],
            style: 'row', mode: 'each', highlight: 'net', border: 0.4, fs: 9.5),
        _field(8, 272, 194, 6, 'amountWords', showLabel: false, fs: 9, align: 'center'),
        _text(8, 279, 194, 6, '{footer}', fs: 8.5, align: 'center', color: _grey),
        _pageNo(287),
      ]);

  // ─────────────────────────── الإيصال ───────────────────────────

  static InvoiceLayout _roll(LayoutPaper p, String variant) {
    final w = p.widthMm;
    final small = p == LayoutPaper.roll58;
    final fs = small ? 7.5 : 8.5;
    const m = 2.0; // هامش
    final cw = w - 2 * m;
    var y = 2.0;
    final els = <LayoutElement>[];
    void add(LayoutElement e, double next) {
      els.add(e);
      y += next;
    }

    void dashed() => add(_line(m, y, cw, t: 0.6, dashed: true), 1.5);

    final logoW = small ? 20.0 : 26.0;
    add(_e(ElType.logo, (w - logoW) / 2, y, logoW, small ? 13 : 16), small ? 14 : 17);
    add(_e(ElType.companyName, m, y, cw, 8, {'fontSize': small ? 12.0 : 14.0, 'bold': true, 'align': 'center'}), 8.5);
    add(
        _e(ElType.companyInfo, m, y, cw, small ? 8 : 9, {
          'fontSize': fs - 1,
          'align': 'center',
          'lines': ['address', 'phones'],
        }),
        small ? 8.5 : 9.5);
    dashed();
    add(_field(m, y, cw, 5, 'invoiceNo', label: 'فاتورة', fs: fs, bold: true), 5);
    add(_field(m, y, cw, 5, 'dateTime', label: 'التاريخ', fs: fs), 5);
    add(_field(m, y, cw, 5, 'customer', label: 'العميل', fs: fs), 5);
    if (variant == 'detailed' || variant == 'debt') {
      add(_field(m, y, cw, 5, 'paymentType', label: 'الدفع', fs: fs), 5);
    }
    add(_text(m, y, cw, 4, '{copy}', fs: fs, bold: true, align: 'center'), 4.5);

    final cols = small
        ? _cols([
            ['details', 2.6],
            ['qty', 0.9],
            ['amount', 1.4],
          ])
        : variant == 'detailed'
            ? _cols([
                ['serial', 0.45],
                ['details', 2.6],
                ['qty', 0.8],
                ['unit', 0.9],
                ['price', 1.2],
                ['amount', 1.4],
              ])
            : _cols([
                ['details', 2.8],
                ['qty', 0.8],
                ['price', 1.2],
                ['amount', 1.4],
              ]);
    const tableH = 46.0;
    add(
        _table(m - 1, y, cw + 2, tableH, cols,
            borders: variant == 'market' ? 'rows' : (variant == 'boxed' ? 'outer' : 'none'),
            rowH: small ? 7.0 : 7.5,
            fs: fs - 0.5,
            headerBg: variant == 'market' ? 0 : _light,
            lineColor: 0xFF9E9E9E),
        tableH + 1.5);

    switch (variant) {
      case 'boxed':
        add(_box(m, y, cw, 16, ['beforeDiscount', 'discount', 'paid'], mode: 'lines', title: 'المجموع', fs: fs), 17);
        add(_rect(m, y, cw, 12, border: 1.2, radius: 1.5), 0);
        add(_text(m, y + 0.5, cw * 0.4, 11, 'الصافي', fs: fs + 1, align: 'center'), 0);
        add(_text(m + cw * 0.4, y + 0.5, cw * 0.6 - 1, 11, '{net}', fs: small ? 13 : 16, bold: true, align: 'center'), 13);
        break;
      case 'debt':
        add(_box(m, y, cw, 17, ['beforeDiscount', 'discount', 'net'], mode: 'lines', title: 'الفاتورة', highlight: 'net', fs: fs),
            18);
        add(
            _box(m, y, cw, 17, ['previousDebt', 'paid', 'currentDebt'],
                mode: 'lines', title: 'حساب العميل', titleBg: _grey, highlight: 'currentDebt', highlightColor: _red, fs: fs),
            18);
        break;
      case 'market':
        add(_box(m, y, cw, 10, ['beforeDiscount', 'discount'], mode: 'none', fs: fs), 10.5);
        add(_box(m, y, cw, 9, ['net'], mode: 'each', border: 1.0, borderColor: _black, fs: fs + 2, labels: {'net': 'الإجمالي'}),
            9.5);
        add(_box(m, y, cw, 5, ['paid'], mode: 'none', fs: fs), 5.5);
        add(_field(m, y, cw, 5, 'itemsCount', fs: fs, align: 'center'), 5.5);
        break;
      default:
        final items = variant == 'detailed'
            ? ['beforeDiscount', 'discount', 'net', 'paid', 'remaining', 'currentDebt']
            : ['beforeDiscount', 'discount', 'net', 'paid', 'remaining'];
        final th = items.length * 5.2;
        add(_box(m, y, cw, th, items, mode: variant == 'detailed' ? 'lines' : 'none', highlight: 'net', fs: fs), th + 1);
        if (variant == 'detailed') {
          add(_field(m, y, cw, 8, 'amountWords', showLabel: false, fs: fs - 1, align: 'center'), 8.5);
        }
    }
    dashed();
    add(_text(m, y, cw, 6, '{footer}', fs: fs, align: 'center'), 6.5);
    if (variant == 'detailed') {
      add(_e(ElType.barcode, (w - 20) / 2, y, 20, 20, {'kind': 'qr', 'data': 'invoiceInfo'}), 21);
    } else if (variant == 'market') {
      add(_e(ElType.barcode, m + 6, y, cw - 12, 12, {'kind': 'code128', 'data': 'invoiceNo'}), 13);
    }
    final names = {
      'basic': small ? 'إيصال صغير' : 'إيصال كاشير',
      'boxed': small ? 'صغير بإطار' : 'إيصال بإطار',
      'debt': small ? 'صغير مع الدين' : 'إيصال دين',
      'market': 'سوبرماركت',
      'detailed': 'إيصال مفصّل',
    };
    return InvoiceLayout(
      id: InvoiceLayout.newId('L'),
      name: names[variant] ?? 'إيصال',
      paper: p,
      heightMm: y + 3,
      elements: els,
    );
  }

  /// عنصر جديد بإعدادات معقولة يُضاف من قائمة المصمم
  static LayoutElement newElement(String type, InvoiceLayout l, {double? x, double? y}) {
    final pw = l.widthMm;
    final roll = l.paper.isRoll;
    final cx = x ?? (roll ? 2.0 : 20.0);
    final cy = y ?? 10.0;
    final cw = roll ? pw - 4 : 80.0;
    final id = InvoiceLayout.newId('e');
    LayoutElement mk(String t, double w, double h, Map<String, dynamic> p) =>
        LayoutElement(id: id, type: t, x: cx, y: cy, w: w, h: h, props: p);
    switch (type) {
      case ElType.logo:
        return mk(type, roll ? 24 : 30, roll ? 15 : 24, {});
      case ElType.companyName:
        return mk(type, cw, roll ? 8 : 12, {
          'fontSize': roll ? 14.0 : 22.0,
          'bold': true,
          'align': roll ? 'center' : 'right',
          'color': _green,
        });
      case ElType.companyInfo:
        return mk(type, cw, roll ? 9 : 12, {
          'fontSize': roll ? 7.5 : 9.5,
          'align': roll ? 'center' : 'right',
          'lines': ['address', 'phones'],
        });
      case ElType.text:
        return mk(type, roll ? cw : 60, 7,
            {'text': 'نص جديد', 'fontSize': roll ? 8.5 : 11.0, 'align': roll ? 'center' : 'right'});
      case ElType.field:
        return mk(type, roll ? cw : 60, roll ? 5 : 7,
            {'key': 'customer', 'label': 'السيد', 'fontSize': roll ? 8.5 : 10.5, 'align': 'right'});
      case ElType.table:
        return mk(
            type,
            roll ? pw - 2 : 170,
            roll ? 40 : 120,
            roll
                ? <String, dynamic>{
                    'columns': _cols([
                      ['details', 2.8],
                      ['qty', 0.8],
                      ['amount', 1.4],
                    ]),
                    'borders': 'none',
                    'rowHeight': 7.0,
                    'fontSize': 8.0,
                    'headerBg': _light,
                    'headerColor': _black,
                  }
                : <String, dynamic>{
                    'columns': _colsStd,
                    'borders': 'grid',
                    'rowHeight': 8.0,
                    'fontSize': 10.0,
                    'headerBg': _light,
                    'headerColor': _black,
                  });
      case ElType.totals:
        return mk(type, roll ? cw : 90, roll ? 26 : 36, {
          'style': 'list',
          'items': ['beforeDiscount', 'discount', 'net', 'paid', 'remaining'],
          'boxMode': roll ? 'none' : 'group',
          'highlight': 'net',
          'fontSize': roll ? 8.5 : 10.5,
          'border': 0.6,
        });
      case ElType.infoBox:
        return mk(ElType.totals, roll ? cw : 120, roll ? 16 : 16, {
          'style': roll ? 'list' : 'grid',
          'cols': 2,
          'items': roll ? ['customer', 'phone', 'invoiceNo'] : ['customer', 'invoiceNo', 'phone', 'dateTime'],
          'boxMode': 'lines',
          'fontSize': roll ? 8.0 : 10.0,
          'border': 0.5,
        });
      case ElType.line:
        return mk(type, roll ? cw : 100, 1, {'thickness': 0.8, 'color': _black});
      case ElType.box:
        return mk(type, roll ? cw : 60, roll ? 10 : 25, {'border': 0.8, 'borderColor': _black, 'radius': 1.5});
      case ElType.barcode:
        return mk(type, 20, 20, {'kind': 'qr', 'data': 'invoiceInfo'});
      case ElType.watermark:
        return mk(type, roll ? cw : 150, roll ? 30 : 100,
            {'opacity': 0.08, 'angle': 0.8, 'fontSize': roll ? 30.0 : 100.0});
      case ElType.pageNo:
        return mk(type, 40, 6, {'fontSize': 9.0, 'align': 'center'});
      default:
        return mk(type, 40, 8, {});
    }
  }
}
