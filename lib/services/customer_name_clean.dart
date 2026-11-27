// lib/services/customer_name_clean.dart
//
// 🧹 تنظيف اسم العميل قبل حفظه أو البحث به:
//   «جهاد          عبد الناصر» ⇐ «جهاد عبد الناصر»
// • أي فراغ (مسافة، Tab، سطر جديد، المسافة غير القابلة للكسر من النسخ واللصق، فراغات
//   يونيكود الأخرى) يصير مسافة واحدة، ويُقص من الطرفين.
// • علامات الاتجاه الخفية (RLM/LRM…) وعلامات العرض الصفري تُحذف — تأتي غالباً من
//   نسخ الاسم من واتساب، وتجعل اسمين متطابقين في الشكل مختلفين في الحفظ.
// لا يغيّر حرفاً ظاهراً، ولا يدمج حسابات، ولا يمس أي رقم: «الاسم نفسه» يبقى كما تحدده
// CustomerNameRule (الاسم بلا مسافات).

class CustomerNameClean {
  CustomerNameClean._();

  static final RegExp _invisible = RegExp('[​‌‍‎‏‪-‮⁦-⁩﻿؜]');
  static final RegExp _spaces = RegExp('[\\s   -     　]+');

  static String clean(String name) =>
      name.replaceAll(_invisible, '').replaceAll(_spaces, ' ').trim();
}
