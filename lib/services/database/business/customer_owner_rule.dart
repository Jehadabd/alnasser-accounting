// lib/services/database/business/customer_owner_rule.dart
//
// 🔐 قاعدة المالك (قرار المالك 2026-11-11): اسم العميل يغيّره الجهاز الذي أنشأه فقط.
//
// السبب: المزامنة ترفع بطاقة العميل من الجهاز الذي أنشأه وحده (FirebaseSyncService.
// syncCustomerNow)، فاسم غيّره جهاز آخر لا يُرفع ويكتب فوقه أول تحديث يصل من السحابة —
// يضيع بلا أي تنبيه، وقد يُنشئ حساباً مكرراً إن كُتب الاسم الجديد في فاتورة (كشفه
// اختبار التعذيب متعدد الأجهزة). مثل قاعدة الفواتير: لا يعدّل فاتورة إلا جهازها.

/// محاولة تغيير اسم عميل أنشأه جهاز آخر.
class CustomerRenameNotOwnedException implements Exception {
  CustomerRenameNotOwnedException(this.name);
  final String name;

  @override
  String toString() => 'اسم العميل «$name» يُغيَّر من الجهاز الذي أنشأه فقط — '
      'هذا الجهاز استلمه بالمزامنة، فتغيير اسمه هنا لا يصل الأجهزة الأخرى ويعود قديماً.';
}

class CustomerOwnerRule {
  CustomerOwnerRule._();

  /// هل أنشأ هذا الجهاز العميل؟ (القيمة الفارغة من الإصدارات القديمة = أنشأه، كما في المزامنة)
  static bool isMine(Object? isCreatedByMe) => (isCreatedByMe as int?) != 0;
}
