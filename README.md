# دفتر ديوني (Debt Book)

تطبيق لإدارة ديون العملاء لمحل تجاري، يوفر واجهة سهلة لإضافة وتعديل الديون، تتبع سجل المعاملات لكل عميل، بحث متقدم، وإنشاء تقارير PDF يومية.

## المميزات

- إدارة العملاء وإضافة عملاء جدد
- تتبع ديون العملاء وإضافة معاملات جديدة
- البحث عن العملاء
- إنشاء تقارير PDF يومية
- رفع التقارير تلقائياً إلى Google Drive
- واجهة مستخدم سهلة الاستخدام باللغة العربية
- تخزين البيانات محلياً باستخدام SQLite
- دعم العمل دون اتصال بالإنترنت

## المتطلبات

- Flutter SDK (3.0.0 أو أحدث)
- حساب Google للوصول إلى Google Drive API
- مساحة تخزين كافية على الجهاز

## التثبيت

1. قم بتثبيت Flutter SDK من [موقع Flutter الرسمي](https://flutter.dev/docs/get-started/install)
2. قم بنسخ المشروع:
   ```bash
   git clone https://github.com/yourusername/debt_book.git
   ```
3. انتقل إلى مجلد المشروع:
   ```bash
   cd debt_book
   ```
4. قم بتثبيت التبعيات:
   ```bash
   flutter pub get
   ```
5. قم بتشغيل التطبيق:
   ```bash
   flutter run
   ```

## إعداد Google Drive API

1. قم بزيارة [Google Cloud Console](https://console.cloud.google.com)
2. أنشئ مشروعاً جديداً
3. قم بتمكين Google Drive API
4. أنشئ بيانات اعتماد OAuth 2.0
5. قم بتكوين شاشة الموافقة
6. أضف معرف العميل (Client ID) إلى التطبيق

## الاستخدام

1. عند أول تشغيل للتطبيق، ستحتاج إلى تسجيل الدخول بحساب Google للوصول إلى Google Drive
2. يمكنك إضافة عملاء جدد باستخدام زر "+" في الشاشة الرئيسية
3. انقر على أي عميل لعرض تفاصيله وإضافة معاملات جديدة
4. استخدم شريط البحث للعثور على العملاء بسرعة
5. يتم إنشاء تقارير PDF يومية تلقائياً ورفعها إلى Google Drive

## المساهمة

نرحب بمساهماتكم! يرجى اتباع الخطوات التالية:

1. قم بعمل Fork للمشروع
2. أنشئ فرعاً جديداً (`git checkout -b feature/amazing-feature`)
3. قم بعمل Commit للتغييرات (`git commit -m 'Add some amazing feature'`)
4. قم بعمل Push إلى الفرع (`git push origin feature/amazing-feature`)
5. افتح طلب Pull Request

## الترخيص

هذا المشروع مرخص تحت رخصة MIT - انظر ملف [LICENSE](LICENSE) للتفاصيل.

## الدعم

إذا واجهت أي مشاكل أو لديك أسئلة، يرجى فتح issue في GitHub.
# alnasser-llmbeat-
# alnasser-llmbeat-
