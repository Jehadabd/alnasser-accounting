// models/invoice_design_settings.dart
import 'dart:convert';

/// إعدادات عمود واحد في جدول الفاتورة
class InvoiceColumnConfig {
  final String id;        // 'serial', 'productId', 'details', 'quantity', 'unitsCount', 'price', 'amount', 'weight', 'expiry'
  final String label;     // الاسم العربي للعمود
  final bool visible;     // ظاهر أم مخفي
  final double widthFlex; // عرض العمود (نسبة مرنة أو ثابتة)
  final int order;        // ترتيب العمود

  const InvoiceColumnConfig({
    required this.id,
    required this.label,
    this.visible = true,
    this.widthFlex = 1.0,
    this.order = 0,
  });

  InvoiceColumnConfig copyWith({
    String? id,
    String? label,
    bool? visible,
    double? widthFlex,
    int? order,
  }) {
    return InvoiceColumnConfig(
      id: id ?? this.id,
      label: label ?? this.label,
      visible: visible ?? this.visible,
      widthFlex: widthFlex ?? this.widthFlex,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'visible': visible,
    'widthFlex': widthFlex,
    'order': order,
  };

  factory InvoiceColumnConfig.fromJson(Map<String, dynamic> json) {
    return InvoiceColumnConfig(
      id: json['id'] ?? '',
      label: json['label'] ?? '',
      visible: json['visible'] ?? true,
      widthFlex: (json['widthFlex'] as num?)?.toDouble() ?? 1.0,
      order: json['order'] ?? 0,
    );
  }

  /// الأعمدة الافتراضية للفاتورة
  static List<InvoiceColumnConfig> defaultColumns() {
    return [
      const InvoiceColumnConfig(id: 'serial', label: 'ت', visible: true, widthFlex: 0.4, order: 0),
      const InvoiceColumnConfig(id: 'productId', label: 'ID', visible: true, widthFlex: 0.9, order: 1),
      const InvoiceColumnConfig(id: 'details', label: 'التفاصيل', visible: true, widthFlex: 2.0, order: 2),
      const InvoiceColumnConfig(id: 'quantity', label: 'العدد', visible: true, widthFlex: 1.2, order: 3),
      const InvoiceColumnConfig(id: 'unitsCount', label: 'عدد الوحدات', visible: true, widthFlex: 1.0, order: 4),
      const InvoiceColumnConfig(id: 'priceBeforeDiscount', label: 'السعر قبل الخصم', visible: true, widthFlex: 1.1, order: 5),
      const InvoiceColumnConfig(id: 'discount', label: 'الخصم', visible: true, widthFlex: 0.9, order: 6),
      const InvoiceColumnConfig(id: 'price', label: 'السعر', visible: true, widthFlex: 1.1, order: 7),
      const InvoiceColumnConfig(id: 'amount', label: 'المبلغ', visible: true, widthFlex: 1.4, order: 8),
      const InvoiceColumnConfig(id: 'weight', label: 'الوزن', visible: false, widthFlex: 1.0, order: 9),
      const InvoiceColumnConfig(id: 'expiry', label: 'تاريخ الانتهاء', visible: false, widthFlex: 1.2, order: 10),
    ];
  }
}

/// إعدادات تصميم الفاتورة الكاملة
class InvoiceDesignSettings {
  final String? logoPath;           // مسار اللوجو المخصص
  final String companyName;         // اسم الشركة
  final String companyAddress;      // عنوان الشركة
  final List<String> phoneNumbers;  // أرقام الهاتف (حد أقصى 2)
  final List<InvoiceColumnConfig> columns; // إعدادات الأعمدة
  final String taxNumber;          // الرقم الضريبي (يظهر في رأس القائمة إن كُتب)
  final String commercialRegister; // رقم السجل التجاري
  final String footerNote;         // عبارة أسفل القائمة (شروط، شكر، سياسة الإرجاع)

  const InvoiceDesignSettings({
    this.logoPath,
    this.companyName = 'الــــــنــــــاصــــــر',
    this.companyAddress = 'الموصل - الجدعة - مقابل البرج',
    this.phoneNumbers = const [],
    List<InvoiceColumnConfig>? columns,
    this.taxNumber = '',
    this.commercialRegister = '',
    this.footerNote = 'شكراً لتعاملكم معنا',
  }) : columns = columns ?? const [];

  /// الإعدادات الافتراضية
  factory InvoiceDesignSettings.defaultSettings() {
    return InvoiceDesignSettings(
      companyName: 'الــــــنــــــاصــــــر',
      companyAddress: 'الموصل - الجدعة - مقابل البرج',
      phoneNumbers: const [],
      columns: InvoiceColumnConfig.defaultColumns(),
    );
  }

  InvoiceDesignSettings copyWith({
    String? logoPath,
    String? companyName,
    String? companyAddress,
    List<String>? phoneNumbers,
    List<InvoiceColumnConfig>? columns,
    String? taxNumber,
    String? commercialRegister,
    String? footerNote,
  }) {
    return InvoiceDesignSettings(
      logoPath: logoPath ?? this.logoPath,
      companyName: companyName ?? this.companyName,
      companyAddress: companyAddress ?? this.companyAddress,
      phoneNumbers: phoneNumbers ?? this.phoneNumbers,
      columns: columns ?? this.columns,
      taxNumber: taxNumber ?? this.taxNumber,
      commercialRegister: commercialRegister ?? this.commercialRegister,
      footerNote: footerNote ?? this.footerNote,
    );
  }

  Map<String, dynamic> toJson() => {
    'logoPath': logoPath,
    'companyName': companyName,
    'companyAddress': companyAddress,
    'phoneNumbers': phoneNumbers,
    'columns': columns.map((c) => c.toJson()).toList(),
    'taxNumber': taxNumber,
    'commercialRegister': commercialRegister,
    'footerNote': footerNote,
  };

  factory InvoiceDesignSettings.fromJson(Map<String, dynamic> json) {
    List<InvoiceColumnConfig> cols = [];
    if (json['columns'] != null) {
      cols = (json['columns'] as List)
          .map((c) => InvoiceColumnConfig.fromJson(c as Map<String, dynamic>))
          .toList();
    }
    if (cols.isEmpty) {
      cols = InvoiceColumnConfig.defaultColumns();
    } else {
      // 🆕 أعمدة أُضيفت بعد حفظ التصميم (مثل «السعر قبل الخصم» و«الخصم»):
      //    تُضاف قبل «السعر» بترتيبه الحالي، ظاهرة، ويمكن إخفاؤها من تصميم الفاتورة.
      final have = cols.map((c) => c.id).toSet();
      final priceIdx = cols.indexWhere((c) => c.id == 'price');
      final priceOrder = priceIdx >= 0 ? cols[priceIdx].order : cols.last.order;
      var insertAt = priceIdx >= 0 ? priceIdx : cols.length;
      for (final d in InvoiceColumnConfig.defaultColumns()) {
        if (have.contains(d.id)) continue;
        // نفس ترتيب «السعر» وقبله في القائمة ⇒ يظهران قبله (الترتيب مستقر)
        cols.insert(insertAt++, d.copyWith(order: priceOrder));
      }
    }
    
    return InvoiceDesignSettings(
      logoPath: json['logoPath'],
      companyName: json['companyName'] ?? 'الــــــنــــــاصــــــر',
      companyAddress: json['companyAddress'] ?? 'الموصل - الجدعة - مقابل البرج',
      phoneNumbers: List<String>.from(json['phoneNumbers'] ?? []),
      columns: cols,
      taxNumber: (json['taxNumber'] as String?) ?? '',
      commercialRegister: (json['commercialRegister'] as String?) ?? '',
      footerNote: (json['footerNote'] as String?) ?? 'شكراً لتعاملكم معنا',
    );
  }

  /// الحصول على الأعمدة المرئية مرتبة حسب الترتيب
  List<InvoiceColumnConfig> get visibleColumns {
    return columns.where((c) => c.visible).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }
}
