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

  // ─────────────────────────── القائمة ───────────────────────────

  static List<LayoutTemplate> forPaper(LayoutPaper paper) => switch (paper) {
        LayoutPaper.a4 => [
            LayoutTemplate('a4_official', 'رسمية بإطار', 'إطار للصفحة، عنوان «فاتورة مبيعات»، بيانات في جدول، مربع ملخص الفاتورة ومربع حساب العميل، وتواقيع', _a4Official),
            LayoutTemplate('a4_two_boxes', 'مربع الفاتورة ومربع الدين', 'الإجمالي والخصم وبعد الخصم في مربع، والدين السابق والمطلوب في مربع، والمتبقي في مربع منفرد', _a4TwoBoxes),
            LayoutTemplate('a4_boxes', 'مربعات منفردة', 'كل مبلغ في مربعه: ثلاث فوق بعض في كل جهة', _a4Boxes),
            LayoutTemplate('a4_amount_due', 'المطلوب بارز', 'مربع كبير للمبلغ المطلوب أعلى الفاتورة، وبيانات العميل مربعات', _a4AmountDue),
            LayoutTemplate('a4_classic', 'كلاسيكي', 'الشعار واسم الشركة في الأعلى، والملخص في مربع بخطوط فاصلة', _a4Classic),
            LayoutTemplate('a4_minimal', 'بسيط أنيق', 'بلا مربعات: خطوط خفيفة ومساحات بيضاء والصافي بلون بارز', _a4Minimal),
            LayoutTemplate('a4_modern', 'حديث', 'شريط ملوّن في الرأس، الصافي في مربع ملوّن، ورمز QR', _a4Modern),
            LayoutTemplate('a4_green', 'زوايا مستديرة', 'مربعات بزوايا مستديرة ولون أخضر', _a4Green),
            LayoutTemplate('a4_wholesale', 'جملة ومستودع', 'أعمدة كثيرة (الوحدة، عدد الوحدات، الوزن) ومجاميع في صف، وثلاثة تواقيع', _a4Wholesale),
            LayoutTemplate('a4_compact', 'مضغوط', 'رأس صغير وصفوف أكثر في الصفحة', _a4Compact),
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
        ..._signature(20, 272, 50, 'توقيع البائع / المحاسب'),
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
        _e(ElType.barcode, 176, 234, 26, 26, {'kind': 'qr', 'data': 'invoiceNo'}),
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
        ..._signature(79, 272, 52, 'أمين المخزن'),
        ..._signature(8, 272, 52, 'المحاسب'),
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
      add(_e(ElType.barcode, (w - 20) / 2, y, 20, 20, {'kind': 'qr', 'data': 'invoiceNo'}), 21);
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
        return mk(type, 20, 20, {'kind': 'qr', 'data': 'invoiceNo'});
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
