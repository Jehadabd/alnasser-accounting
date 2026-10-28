// lib/invoice_designer/invoice_layout.dart
//
// 🎨 «مصمم الفاتورة»: تصميم فاتورة = ورقة (A4 / إيصال 80 / إيصال 58) عليها عناصر
// يضعها المستخدم حيث يشاء بالسحب: الشعار، اسم الشركة، معلومات الشركة، نص حر،
// حقول البيانات (العميل، الرقم، التاريخ…)، جدول المواد، المجاميع، خطوط ومستطيلات،
// باركود، علامة مائية، رقم الصفحة. المقاسات كلها بالمليمتر من الزاوية العليا اليسرى.
//
// جدول المواد هو العنصر «المتمدد»:
//   • A4: صفوفه بقدر ارتفاعه المصمَّم، وما زاد ينتقل لصفحة جديدة (يتكرر ما فوق
//     الجدول في كل صفحة، وما تحته — المجاميع — في الصفحة الأخيرة فقط).
//   • الإيصال: الورقة تطول وتقصر مع عدد المواد، وما تحت الجدول ينزل معه.

import 'dart:convert';

enum LayoutPaper { a4, roll80, roll58 }

extension LayoutPaperX on LayoutPaper {
  double get widthMm => switch (this) {
        LayoutPaper.a4 => 210,
        LayoutPaper.roll80 => 80,
        LayoutPaper.roll58 => 58,
      };

  double get defaultHeightMm => switch (this) {
        LayoutPaper.a4 => 297,
        LayoutPaper.roll80 => 150,
        LayoutPaper.roll58 => 140,
      };

  bool get isRoll => this != LayoutPaper.a4;

  String get label => switch (this) {
        LayoutPaper.a4 => 'A4 — فاتورة الجملة / الكبيرة',
        LayoutPaper.roll80 => 'إيصال 80 ملم',
        LayoutPaper.roll58 => 'إيصال 58 ملم',
      };

  String get shortLabel => switch (this) {
        LayoutPaper.a4 => 'A4',
        LayoutPaper.roll80 => '80 ملم',
        LayoutPaper.roll58 => '58 ملم',
      };
}

LayoutPaper parsePaper(String? s) =>
    LayoutPaper.values.firstWhere((p) => p.name == s, orElse: () => LayoutPaper.a4);

/// أنواع العناصر
class ElType {
  ElType._();
  static const logo = 'logo';
  static const companyName = 'companyName';
  static const companyInfo = 'companyInfo';
  static const text = 'text';
  static const field = 'field';
  static const table = 'table';
  static const totals = 'totals';
  static const line = 'line';
  static const box = 'box';
  static const barcode = 'barcode';
  static const watermark = 'watermark';
  static const pageNo = 'pageNo';

  /// (في القائمة فقط) مربع بيانات العميل/الفاتورة — عنصر «مجاميع» بنود من حقول البيانات
  static const infoBox = 'infoBox';

  static const labels = <String, String>{
    logo: 'الشعار',
    companyName: 'اسم الشركة',
    companyInfo: 'معلومات الشركة',
    text: 'نص حر',
    field: 'حقل بيانات',
    table: 'جدول المواد',
    totals: 'مربع مجاميع',
    infoBox: 'مربع بيانات (العميل والفاتورة)',
    line: 'خط',
    box: 'مستطيل / إطار',
    barcode: 'باركود / QR',
    watermark: 'علامة مائية',
    pageNo: 'رقم الصفحة',
  };
}

/// ما يمكن عرضه في الفاتورة
class LayoutCatalog {
  LayoutCatalog._();

  /// حقول البيانات (عنصر «حقل بيانات»، أو {المفتاح} داخل النص الحر)
  static const fields = <String, String>{
    'invoiceNo': 'رقم الفاتورة',
    'date': 'التاريخ',
    'time': 'الوقت',
    'dateTime': 'التاريخ والوقت',
    'customer': 'السيد',
    'phone': 'الهاتف',
    'address': 'العنوان',
    'paymentType': 'طريقة الدفع',
    'user': 'المستخدم',
    'preparer': 'المجهز',
    'accountant': 'المحاسب',
    'branch': 'الفرع',
    'itemsCount': 'عدد المواد',
    'amountWords': 'المبلغ كتابةً',
    'footer': 'عبارة أسفل الفاتورة',
    'copy': 'نسخة',
    // 🧾 إشعار مدين / دائن (سند إضافة أو إرجاع على فاتورة)
    'voucherTitle': 'نوع السند (إشعار مدين/دائن)',
    'voucherNo': 'رقم السند',
    'voucherReason': 'سبب السند / ملاحظة',
    // 🧾 سندات القبض والصرف
    'boxName': 'الصندوق',
    'docNo': 'رقم المستند',
    // 🖨️ تُملأ لحظة الطباعة
    'printedAt': 'وقت الطباعة',
    'printedBy': 'طُبع بواسطة',
  };

  /// أعمدة جدول المواد
  static const columns = <String, String>{
    'serial': 'ت',
    'productId': 'المعرّف الداخلي (ID)',
    'barcode': 'الباركود',
    'itemCode': 'رمز المادة',
    'details': 'التفاصيل',
    'quantity': 'الكمية والوحدة',
    'qty': 'العدد',
    'unit': 'الوحدة',
    'unitsCount': 'عدد الوحدات',
    'priceBeforeDiscount': 'السعر قبل الخصم',
    'discount': 'الخصم',
    'price': 'السعر',
    'amount': 'المبلغ',
    'weight': 'الوزن',
    'expiry': 'تاريخ الانتهاء',
    'blank': 'ملاحظات',
  };

  /// المجاميع
  static const totals = <String, String>{
    'beforeDiscount': 'الإجمالي قبل الخصم',
    'discount': 'الخصم',
    'afterDiscount': 'الإجمالي بعد الخصم',
    'loadingFee': 'أجور التحميل',
    'net': 'الصافي للدفع',
    'paid': 'المبلغ المدفوع',
    'remaining': 'المبلغ المتبقي',
    'previousDebt': 'الدين السابق',
    'currentDebt': 'المطلوب الحالي',
    'itemsCount': 'عدد المواد',
    'paymentType': 'طريقة الدفع',
    // 🧾 إشعار مدين / دائن
    'voucherAmount': 'مبلغ السند',
    'invoiceBefore': 'الفاتورة قبل السند',
    'invoiceAfter': 'الفاتورة بعد السند',
  };

  /// أسطر «معلومات الشركة»
  static const companyLines = <String, String>{
    'description': 'نشاط الشركة',
    'address': 'العنوان',
    'phones': 'الهواتف',
    'tax': 'الرقم الضريبي',
    'cr': 'السجل التجاري',
  };
}

/// عنصر واحد على الورقة
class LayoutElement {
  LayoutElement({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    Map<String, dynamic>? props,
  }) : props = props ?? <String, dynamic>{};

  final String id;
  final String type;
  double x, y, w, h;
  Map<String, dynamic> props;

  double d(String k, double def) {
    final v = props[k];
    return v is num ? v.toDouble() : def;
  }

  int i(String k, int def) {
    final v = props[k];
    return v is num ? v.toInt() : def;
  }

  bool b(String k, bool def) {
    final v = props[k];
    return v is bool ? v : def;
  }

  String s(String k, String def) {
    final v = props[k];
    return v is String ? v : def;
  }

  List<String> strings(String k) {
    final v = props[k];
    return v is List ? v.map((e) => '$e').toList() : <String>[];
  }

  /// أعمدة الجدول: [{id, label, flex, align}]
  List<Map<String, dynamic>> get columns {
    final v = props['columns'];
    if (v is! List) return <Map<String, dynamic>>[];
    return v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  set columns(List<Map<String, dynamic>> cols) => props['columns'] = cols;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'props': props,
      };

  factory LayoutElement.fromJson(Map<String, dynamic> j) => LayoutElement(
        id: '${j['id'] ?? ''}',
        type: '${j['type'] ?? ElType.text}',
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        w: (j['w'] as num?)?.toDouble() ?? 20,
        h: (j['h'] as num?)?.toDouble() ?? 8,
        props: j['props'] is Map ? Map<String, dynamic>.from(j['props'] as Map) : null,
      );

  LayoutElement copy({String? id}) =>
      LayoutElement.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>)._withId(id);

  LayoutElement _withId(String? newId) => newId == null
      ? this
      : LayoutElement(id: newId, type: type, x: x, y: y, w: w, h: h, props: props);
}

/// تصميم فاتورة كامل
class InvoiceLayout {
  InvoiceLayout({
    required this.id,
    required this.name,
    required this.paper,
    double? heightMm,
    List<LayoutElement>? elements,
    this.kind = 'invoice',
    this.mono = false,
  })  : heightMm = heightMm ?? paper.defaultHeightMm,
        elements = elements ?? <LayoutElement>[];

  final String id;
  String name;
  final LayoutPaper paper;

  /// 🧾 نوع المستند: 'invoice' (فاتورة وإيصال) أو نوع سند من مصمم السندات
  /// (receipt / cash_receipt / cash_refund / debit_note / credit_note).
  String kind;

  /// ⚫ أبيض وأسود: كل الألوان تُطبع (وتُعرض) بتدرّج الرمادي — للطابعات بلا ألوان
  bool mono;
  double heightMm;
  List<LayoutElement> elements;

  double get widthMm => paper.widthMm;

  LayoutElement? get table {
    for (final e in elements) {
      if (e.type == ElType.table) return e;
    }
    return null;
  }

  LayoutElement? byId(String? id) {
    if (id == null) return null;
    for (final e in elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'paper': paper.name,
        'kind': kind,
        'mono': mono,
        'heightMm': heightMm,
        'elements': elements.map((e) => e.toJson()).toList(),
      };

  factory InvoiceLayout.fromJson(Map<String, dynamic> j) {
    final paper = parsePaper(j['paper'] as String?);
    return InvoiceLayout(
      id: '${j['id'] ?? ''}',
      name: '${j['name'] ?? 'تصميم'}',
      paper: paper,
      kind: (j['kind'] as String?)?.trim().isNotEmpty == true ? j['kind'] as String : 'invoice',
      mono: j['mono'] == true,
      heightMm: (j['heightMm'] as num?)?.toDouble(),
      elements: (j['elements'] is List)
          ? (j['elements'] as List)
              .whereType<Map>()
              .map((m) => LayoutElement.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : null,
    );
  }

  /// نسخة مستقلة (للتعديل دون لمس الأصل)
  InvoiceLayout copy({String? id, String? name}) {
    final j = jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>;
    if (id != null) j['id'] = id;
    if (name != null) j['name'] = name;
    return InvoiceLayout.fromJson(j);
  }

  static int _seq = 0;
  static String newId(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';
}

/// قواعد مشتركة بين الرسم على الشاشة والطباعة
class LayoutRules {
  LayoutRules._();

  /// خطوط الجدول: grid (شبكة) / columns (أعمدة وإطار) / rows (أسطر) / outer (إطار) / none
  static String tableBorders(LayoutElement t) {
    final m = t.s('borders', '');
    if (m.isNotEmpty) return m;
    if (t.b('grid', true)) return 'grid';
    if (t.b('rowLines', false)) return 'rows';
    return 'none';
  }

  /// مربعات المجاميع: each (كل بند بمربع) / group (مربع واحد) / lines (مربع بخطوط فاصلة) / none
  static String boxMode(LayoutElement e) {
    final m = e.s('boxMode', '');
    if (m.isNotEmpty) return m;
    return e.d('border', 0.6) > 0 ? 'each' : 'none';
  }

  static bool isTotal(String k) => LayoutCatalog.totals.containsKey(k);

  static String itemLabel(LayoutElement e, String k) {
    final labels = e.props['labels'];
    if (labels is Map && labels[k] != null) return '${labels[k]}';
    return LayoutCatalog.totals[k] ?? LayoutCatalog.fields[k] ?? k;
  }
}
