// lib/services/database/business/invoice_update_guard.dart
//
// 🛡️ حارس «تحديث صف الفاتورة» خارج مسار الحفظ (InvoiceDao.updateInvoice).
//
// الحادثة: في تطبيق المتجر القديم ضُغط «تعليق» على فاتورة دين محفوظة، فأعادت
// دالة التحديث كتابة صفها كاملاً بعميل آخر وجدته بحث جزئي بالاسم، دون أي قيد
// في سجل الديون. ثم حُفظت الفاتورة فظنّ الحفظ أن الدين على العميل الخطأ،
// فطرحه منه وأضافه مرة ثانية على العميل الصحيح (فاتورة 1202610191: ضِعف الدين).
//
// القاعدة هنا تمنع ذلك في طبقة القاعدة نفسها، مهما كان من يستدعي التحديث:
//   • فاتورة معلّقة في القاعدة: تُحدَّث بحرية، لكنها تبقى معلّقة. تحويلها إلى
//     محفوظة يكون فقط عبر حفظ الفاتورة (الذي يُشغّل الحارس المحاسبي).
//   • أي فاتورة غير معلّقة في القاعدة (محفوظة أو غيرها): لا يتغير عبر هذا
//     المسار ما يحدد دينها: الحالة، العميل، نوع الدفع، الإجمالي، المسدد،
//     الخصم، أجور التحميل. باقي الحقول (ملاحظات، قفل…) تبقى قابلة للتحديث.
// المقارنة مع الصف المخزّن في القاعدة، لا مع كائن الشاشة (قد يكون قديماً).

class InvoiceUpdateGuard {
  InvoiceUpdateGuard._();

  static const String heldStatus = 'معلقة';
  static const double _tolerance = 0.005;

  /// الأعمدة التي يجب قراءتها من الصف الحالي قبل التحديث.
  static const List<String> columns = <String>[
    'status',
    'customer_id',
    'payment_type',
    'total_amount',
    'amount_paid_on_invoice',
    'discount',
    'loading_fee',
  ];

  static const Map<String, String> _moneyLabels = <String, String>{
    'total_amount': 'الإجمالي',
    'amount_paid_on_invoice': 'المبلغ المسدد',
    'discount': 'الخصم',
    'loading_fee': 'أجور التحميل',
  };

  /// `null` إن كان التحديث مسموحاً، وإلا نص سبب الرفض (يُعرض للمستخدم).
  /// [current] الصف المخزّن الآن (`null` إن لم يوجد: لا شيء نحرسه).
  /// [incoming] الخريطة التي ستُكتب.
  static String? violation(Map<String, Object?>? current, Map<String, Object?> incoming) {
    if (current == null) return null;

    final String curStatus = _text(current['status']);
    final String newStatus = _text(incoming['status']);

    if (curStatus == heldStatus) {
      if (newStatus != heldStatus) {
        return 'فاتورة معلّقة لا تُحفظ من هنا: افتحها وأكمل حفظها من شاشة الفاتورة';
      }
      return null;
    }

    final changed = <String>[];
    if (newStatus != curStatus) changed.add('الحالة');
    if (_id(incoming['customer_id']) != _id(current['customer_id'])) changed.add('العميل');
    if (_text(incoming['payment_type']) != _text(current['payment_type'])) changed.add('نوع الدفع');
    _moneyLabels.forEach((field, label) {
      if ((_num(incoming[field]) - _num(current[field])).abs() > _tolerance) changed.add(label);
    });
    if (changed.isEmpty) return null;
    return 'فاتورة محفوظة: لا يتغير (${changed.join('، ')}) إلا بحفظ الفاتورة من شاشتها';
  }

  static String _text(Object? v) => v?.toString().trim() ?? '';

  /// العميل: null و0 سواء (بلا عميل)
  static int _id(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }

  static double _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? 0.0;
    return 0.0;
  }
}
