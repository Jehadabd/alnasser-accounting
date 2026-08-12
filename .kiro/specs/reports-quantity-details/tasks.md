# Implementation Plan

- [x] 1. إضافة دوال جديدة في ReportsService
  - [x] 1.1 إضافة دالة getCustomerProductsPurchased
    - دالة حسابية لجلب المنتجات التي اشتراها عميل
    - تجميع الكميات والمبالغ والأرباح من الفواتير الموجودة
    - دعم فلترة حسب السنة والشهر
    - _Requirements: 2.2, 6.1, 6.2_
  - [x] 1.2 إضافة دالة getProductCustomersBought
    - دالة حسابية لجلب العملاء الذين اشتروا منتج
    - تجميع الكميات والمبالغ والأرباح
    - دعم فلترة حسب السنة والشهر
    - _Requirements: 4.2, 6.3, 6.4_
  - [x] 1.3 إضافة دالة calculateHierarchicalDisplay
    - تحويل الكمية للعرض الهرمي (مثل: 500 متر = 5 لفات)
    - _Requirements: 2.4, 4.4, 7.1, 7.2, 7.3, 7.4, 7.5_

- [x] 2. إنشاء CustomerProductsDialog
  - [x] 2.1 إنشاء الـ Dialog الأساسي
    - عرض قائمة المنتجات مع الكمية والتحويل الهرمي والمبلغ والربح
    - _Requirements: 2.2, 2.3, 2.4, 2.5_
  - [x] 2.2 إضافة خيارات الترتيب الثلاثة
    - الأكثر سحباً (كمية)، الأكثر سحباً (مبلغ)، الأكثر ربحاً
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 3. إنشاء ProductCustomersDialog
  - [x] 3.1 إنشاء الـ Dialog الأساسي
    - عرض قائمة العملاء مع الكمية والتحويل الهرمي والمبلغ والربح
    - _Requirements: 4.2, 4.3, 4.4_
  - [x] 3.2 إضافة خيارات الترتيب الثلاثة
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [x] 4. تحديث PeopleReportsScreen
  - [x] 4.1 إضافة نسبة الربح في بطاقة العميل
    - _Requirements: 1.1, 1.2, 1.3_
  - [x] 4.2 إضافة زر "المنتجات المشتراة"
    - _Requirements: 2.1_

- [x] 5. تحديث ProductReportsScreen
  - [x] 5.1 إضافة زر "العملاء المشترين"
    - _Requirements: 4.1_

- [x] 6. تحديث شاشات السنة والشهر للأشخاص
  - [x] 6.1 تحديث PersonYearDetailsScreen
    - إضافة زر "المنتجات المشتراة" مع فلتر السنة
    - _Requirements: 6.1_
  - [x] 6.2 تحديث PersonMonthDetailsScreen
    - إضافة زر "المنتجات المشتراة" مع فلتر السنة والشهر
    - _Requirements: 6.2_

- [x] 7. Checkpoint النهائي
  - Ensure all tests pass, ask the user if questions arise.
