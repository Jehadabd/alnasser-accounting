# التحليل الشامل لآلية حفظ وتعديل الفواتير وانعكاسها على الديون وسجل المعاملات

**تاريخ التحليل:** 28 يونيو 2026  
**النظام:** برنامج محلات النسر (Alnaser / Shop Manager)  
**قاعدة البيانات:** SQLite (Flutter sqflite)  
**الملف الرئيسي لمعالجة الديون:** `lib/controllers/invoice_controller.dart`  
**ملف الواجهة:** `lib/screens/invoice_actions.dart`  
**ملف شاشة الإنشاء:** `lib/screens/create_invoice_screen.dart`  
**ملف الموديلات:** `lib/models/invoice.dart`, `lib/models/transaction.dart`, `lib/models/customer.dart`  

---

## جدول المحتويات

1. [هيكل قاعدة البيانات والجداول المعنية](#1)
2. [الموديلات المستخدمة](#2)
3. [الدوال الرئيسية في InvoiceController](#3)
4. [السيناريوهات الكاملة لتعديل الفاتورة (50+ سيناريو)](#4)
5. [حالات خاصة وتفاصيل دقيقة](#5)
6. [آلية Snapshot والتدقيق](#6)
7. [التسويات (InvoiceAdjustments)](#7)
8. [مشاكل وحلول معروفة](#8)

---

## <a name="1"></a>1. هيكل قاعدة البيانات والجداول المعنية

### جدول `invoices`

| الحقل | النوع | الوصف |
|-------|-------|-------|
| `id` | INTEGER PK | رقم الفاتورة (Auto-increment) |
| `customer_name` | TEXT | اسم العميل |
| `customer_phone` | TEXT | رقم الهاتف (موحد إلى 964xx) |
| `customer_address` | TEXT | العنوان |
| `installer_name` | TEXT | اسم الفني / المركب |
| `invoice_date` | TEXT (ISO8601) | تاريخ الفاتورة |
| `payment_type` | TEXT | 'نقد' أو 'دين' |
| `total_amount` | REAL | الإجمالي (items + أجور - خصم) |
| `discount` | REAL | قيمة الخصم |
| `amount_paid_on_invoice` | REAL | المبلغ المدفوع نقداً |
| `loading_fee` | REAL | أجور التحميل |
| `created_at` | TEXT | تاريخ الإنشاء |
| `last_modified_at` | TEXT | آخر تعديل |
| `customer_id` | INTEGER | FK → customers.id |
| `status` | TEXT | 'محفوظة' أو 'معلقة' |
| `return_amount` | REAL | مبلغ المرتجع |
| `is_locked` | INTEGER (0/1) | هل الفاتورة مقفلة؟ |
| `points_rate` | REAL | معدل النقاط |
| `created_by_user_id` | INTEGER | معرف المستخدم المنشئ |
| `created_by_username` | TEXT | اسم المستخدم المنشئ |
| `notes` | TEXT | ملاحظات |

### جدول `customers`

| الحقل | النوع | الوصف |
|-------|-------|-------|
| `id` | INTEGER PK | |
| `name` | TEXT | |
| `phone` | TEXT | |
| `current_total_debt` | REAL | **رصيد الدين الجاري — يتم تحديثه يدوياً مع كل معاملة** |
| `general_note` | TEXT | |
| `address` | TEXT | |
| `created_at` | TEXT | |
| `last_modified_at` | TEXT | |
| `audio_note_path` | TEXT | |
| `sync_uuid` | TEXT | |

### جدول `transactions` (سجل الديون — مصدر الحقيقة)

| الحقل | النوع | الوصف |
|-------|-------|-------|
| `id` | INTEGER PK | |
| `customer_id` | INTEGER | FK → customers.id |
| `transaction_date` | TEXT | |
| `amount_changed` | REAL | **موجب = زيادة دين / سالب = تخفيض دين** |
| `balance_before_transaction` | REAL | رصيد العميل قبل |
| `new_balance_after_transaction` | REAL | رصيد العميل بعد |
| `transaction_note` | TEXT | |
| `transaction_type` | TEXT | انظر الجدول أدناه |
| `description` | TEXT | شرح (مثال: 'دين فاتورة رقم 5') |
| `invoice_id` | INTEGER | FK → invoices.id **الربط مع الفاتورة** |
| `created_at` | TEXT | |
| `is_created_by_me` | INTEGER (0/1) |
| `is_uploaded` | INTEGER (0/1) |
| `transaction_uuid` | TEXT | UUID فريد |
| `is_read_by_others` | INTEGER (0/1) |
| `sync_uuid` | TEXT | |

### أنواع `transaction_type`

```dart
'invoice_debt'              = دين فاتورة جديدة
'invoice_edit'              = تعديل فاتورة دين قائمة (نفس العميل)
'invoice_payment_type_change' = تحويل نقد↔دين
'invoice_customer_change'    = نقل الدين بين العملاء
```

### جدول `invoice_items`

| الحقل | النوع | الوصف |
|-------|-------|-------|
| `id` | INTEGER PK | |
| `invoice_id` | INTEGER | FK → invoices.id |
| `product_id` | INTEGER | FK → products.id |
| `product_name` | TEXT | |
| `unit` | TEXT | |
| `unit_price` | REAL | سعر الوحدة الأساسي |
| `cost_price` | REAL | التكلفة الإجمالية |
| `actual_cost_price` | REAL | التكلفة الفعلية للوحدة المباعة |
| `quantity_individual` | REAL | كمية قطع/أمتار |
| `quantity_large_unit` | REAL | كمية وحدات كبيرة (كرتون/لفة) |
| `applied_price` | REAL | السعر المطبق |
| `item_total` | REAL | إجمالي البند |
| `sale_type` | TEXT | 'قطعة', 'متر', 'كرتون', 'باكيت', ... |
| `units_in_large_unit` | REAL | عدد القطع في الوحدة الكبيرة |
| `unique_id` | TEXT | |

### جدول `invoice_adjustments` (التسويات اللاحقة)

| الحقل | النوع | الوصف |
|-------|-------|-------|
| `id` | INTEGER PK | |
| `invoice_id` | INTEGER | |
| `type` | TEXT | 'debit' أو 'credit' |
| `amount_delta` | REAL | موجب = debit (زيادة), سالب = credit (نقص) |
| `product_id` | INTEGER | |
| `product_name` | TEXT | |
| `quantity` | REAL | |
| `price` | REAL | |
| `unit` | TEXT | |
| `sale_type` | TEXT | |
| `units_in_large_unit` | REAL | |
| `settlement_payment_type` | TEXT | 'نقد' أو 'دين' (تأثير التسوية على الديون) |
| `note` | TEXT | |
| `created_at` | TEXT | |

### جدول `invoice_snapshots`

يُحفظ فيه صور للفاتورة قبل التعديل وبعده للأرشفة والتدقيق.

---

## <a name="2"></a>2. الموديلات المستخدمة

### `Invoice` (`lib/models/invoice.dart`)
```dart
class Invoice {
  int? id;
  String customerName;
  String? customerPhone;
  String? customerAddress;
  String? installerName;
  DateTime invoiceDate;
  String paymentType;         // 'نقد' | 'دين'
  double totalAmount;         // الإجمالي (items + أجور - خصم)
  double discount;
  double amountPaidOnInvoice; // المبلغ المدفوع
  double loadingFee;          // أجور التحميل
  DateTime createdAt;
  DateTime lastModifiedAt;
  int? customerId;
  String status;              // 'محفوظة' | 'معلقة'
  double returnAmount;
  bool isLocked;
  double pointsRate;
  int? createdByUserId;
  String? createdByUsername;
  String? notes;
}
```

### `DebtTransaction` (`lib/models/transaction.dart`)
```dart
class DebtTransaction {
  int? id;
  int customerId;
  DateTime transactionDate;
  double amountChanged;        // موجب=دين, سالب=تخفيض
  double? balanceBeforeTransaction;
  double? newBalanceAfterTransaction;
  String? transactionNote;
  String transactionType;      // 'invoice_debt' | 'invoice_edit' | ...
  String? description;
  int? invoiceId;
  DateTime createdAt;
  bool isCreatedByMe;
  bool isUploaded;
  String? transactionUuid;
  bool isReadByOthers;
  String? syncUuid;
}
```

### `Customer` (`lib/models/customer.dart`)
```dart
class Customer {
  int? id;
  String name;
  String? phone;
  double currentTotalDebt;  // 👈 الرصيد الجاري
  String? generalNote;
  String? address;
  DateTime createdAt;
  DateTime lastModifiedAt;
  String? audioNotePath;
  String? syncUuid;
}
```

### `InvoiceAdjustment` (`lib/models/invoice_adjustment.dart`)
```dart
class InvoiceAdjustment {
  int? id;
  int invoiceId;
  String type;             // 'debit' أو 'credit'
  double amountDelta;      // موجب للزيادة / سالب للنقص
  int? productId;
  String? productName;
  double? quantity;
  double? price;
  String? unit;
  String? saleType;
  double? unitsInLargeUnit;
  String? settlementPaymentType;  // 'نقد' أو 'دين'
  String? note;
  DateTime createdAt;
}
```

---

## <a name="3"></a>3. الدوال الرئيسية في InvoiceController

### `InvoiceController.saveInvoice(InvoiceInputData data)` ← السطر 334

هذه هي الدالة الأم. تستقبل `InvoiceInputData` الذي يحتوي:
- `invoiceToManage` ← الفاتورة الأصلية (قديمة) — أو null للجديدة
- `customerName`, `customerPhone`, ...
- `paidAmount`, `loadingFee`, `discount`, `paymentType`
- `invoiceItems` (قائمة الأصناف)
- `isNewInvoice` (محسوبة: `invoiceToManage == null`)

**الخطوات بالترتيب داخل `saveInvoice`:**

```
1. validateInvoiceData(data)          → التحقق الأولي
2. validateDebtChangeWontCauseNegativeBalance(data) → التحقق من الرصيد
3. حفظ Snapshot "original" (إذا أول تعديل)
4. حفظ Snapshot "before_edit"
5. BEGIN TRANSACTION
   5.1 البحث عن العميل أو إنشائه
   5.2 حساب الإجمالي (items + أجور - خصم)
   5.3 إذا paymentType == 'نقد' و edit → paid = totalAmount
   5.4 تحديث الحالة: إذا كانت 'معلقة' ← 'محفوظة'
   5.5 INSERT أو UPDATE invoices
   5.6 حماية الأصناف: ربط product_id + حساب actualCostPrice
   5.7 عكس المخزون القديم (isAddition: true)
   5.8 DELETE old invoice_items
   5.9 INSERT new invoice_items
   5.10 خصم المخزون الجديد (isAddition: false)
   5.11 ── معالجة الديون (5 حالات رئيسية) ──
   5.12 جلب الفاتورة المحدثة
6. COMMIT TRANSACTION
7. Audit Log (تسجيل old_values vs new_values)
8. Snapshot "after_edit"
9. حذف temp_invoice_data
10. تدريب Smart Search
```

### `validateDebtChangeWontCauseNegativeBalance(InvoiceInputData data)` ← السطر 239

تحسب `debtChange` المتوقع بناءً على نوع التغيير، وتتحقق من أن رصيد العميل القديم لن يصبح سالباً.

```dart
// منطق حساب debtChange:
إذا تحويل دين→نقد:
  debtChange = -oldRemaining
إذا تغيير عميل (مع دين):
  debtChange = -oldRemaining
إذا تعديل دين (نفس العميل):
  debtChange = newRemaining - oldRemaining
إذا تحويل نقد→دين:
  debtChange = 0 (لا تأثير على العميل القديم)

expectedNewBalance = currentCustomerDebt + debtChange
if expectedNewBalance < -0.01 → رفض الحفظ 🚫
```

---

## <a name="4"></a>4. السيناريوهات الكاملة لتعديل الفاتورة (50+ سيناريو)

### الاصطلاحات المستخدمة:
- **A1**: الفاتورة الأصلية كانت **نقد** بمبلغ 100,000 دينار (مدفوع بالكامل)
- **A2**: الفاتورة الأصلية كانت **دين** بمبلغ 100,000 دينار، مدفوع 20,000 دينار (باقي 80,000)
- **A3**: الفاتورة الأصلية كانت **دين** بمبلغ 100,000 دينار، مدفوع 0 (دين كامل 100,000)
- **B**: العميل "أحمد" — رصيده الحالي قبل التعديل: 200,000 دينار دين
- **C**: العميل "محمد" — رصيده الحالي: 50,000 دينار دين
- **oldRemaining**: ما تبقى من الدين في الفاتورة الأصلية
- **newRemaining**: ما سيبقى من الدين بعد التعديل
- **debtChange**: الفرق الذي سيُضاف/يُطرح من رصيد العميل

---

### القسم الأول: تحويل نوع الدفع (Payment Type Change) — 6 سيناريوهات

#### السيناريو 1: تحويل دين → نقد (مع بقاء العميل نفسه)
```
الأصل: A2 (دين، باقي 80,000)، العميل B (رصيده 200,000)
التعديل: paymentType → 'نقد'
↓↓↓
debtChange = -oldRemaining = -80,000
رصيد B الجديد = 200,000 + (-80,000) = 120,000 ✅
المعاملة المسجلة:
  customer_id: B.id
  amount_changed: -80,000
  balance_before: 200,000
  new_balance: 120,000
  transaction_type: 'invoice_payment_type_change'
  description: 'إلغاء دين فاتورة رقم X (تحويل لنقد)'
```

#### السيناريو 2: تحويل دين → نقد (الرصيد لا يكفي — ممنوع)
```
الأصل: A2 (باقي 80,000)، العميل B (رصيده 50,000)
التعديل: paymentType → 'نقد'
↓↓↓
debtChange = -80,000
expectedNewBalance = 50,000 + (-80,000) = -30,000 🚫
→ يتم رفض الحفظ مع رسالة:
  "رصيد العميل أحمد الحالي: 50,000"
  "المبلغ الذي سيُخصم: 80,000"
  "الرصيد المتوقع: -30,000 (سالب!)"
  الحل: "راجع معاملات العميل أو أبقِ الفاتورة بالدين"
```

#### السيناريو 3: تحويل نقد → دين
```
الأصل: A1 (نقد، مدفوع 100,000)، العميل B (رصيده 200,000)
التعديل: paymentType → 'دين', paidAmount → 0
↓↓↓
newRemaining = 100,000 - 0 = 100,000
debtChange = 0 (لا تأثير على العميل القديم لأنه نقدي)
→ يضاف 100,000 إلى رصيد B:
رصيد B الجديد = 200,000 + 100,000 = 300,000 ✅
المعاملة المسجلة:
  customer_id: B.id
  amount_changed: +100,000
  transaction_type: 'invoice_payment_type_change'
  description: 'إضافة دين فاتورة رقم X (تحويل من نقد)'
```

#### السيناريو 4: تحويل نقد → دين (مع دفع جزء)
```
الأصل: A1 (نقد، مدفوع 100,000)، العميل B (رصيده 200,000)
التعديل: paymentType → 'دين', paidAmount → 30,000
↓↓↓
newRemaining = 100,000 - 30,000 = 70,000
→ يضاف 70,000 إلى رصيد B:
رصيد B الجديد = 270,000 ✅
```

#### السيناريو 5: تحويل دين → نقد (دين كامل)
```
الأصل: A3 (دين، باقي 100,000)، العميل B (رصيده 150,000)
التعديل: paymentType → 'نقد'
↓↓↓
debtChange = -100,000
رصيد B الجديد = 150,000 - 100,000 = 50,000 ✅
```

#### السيناريو 6: تحويل دين → نقد (دين كامل والرصيد أقل)
```
الأصل: A3 (دين، باقي 100,000)، العميل B (رصيده 80,000)
التعديل: paymentType → 'نقد'
↓↓↓
expectedNewBalance = 80,000 - 100,000 = -20,000 🚫
→ ممنوع. يجب تسديد جزء من الدين أولاً.
```

---

### القسم الثاني: تغيير العميل (Customer Change) — 12 سيناريو

#### السيناريو 7: تغيير العميل (دين → دين، عميل مختلف)
```
الأصل: A2 (دين، باقي 80,000)، العميل B (رصيده 200,000)
التعديل: customerName → 'محمد' (C, رصيده 50,000), paymentType → 'دين', paidAmount → 20,000
↓↓↓
الخطوة 1: سحب الدين من B:
  debtChange = -oldRemaining = -80,000
  رصيد B الجديد = 200,000 - 80,000 = 120,000 ✅
  transaction(B, -80,000, 'invoice_customer_change', 'نقل دين فاتورة رقم X إلى عميل آخر')

الخطوة 2: إضافة الدين لـ C:
  newRemaining = 100,000 - 20,000 = 80,000
  رصيد C الجديد = 50,000 + 80,000 = 130,000 ✅
  transaction(C, +80,000, 'invoice_customer_change', 'استلام دين فاتورة رقم X من عميل آخر')
```

#### السيناريو 8: تغيير العميل (دين → دين، مع تغيير المبلغ)
```
الأصل: A2 (دين، باقي 80,000)، العميل B (رصيده 200,000)
التعديل: customerName → 'محمد', items زادت → totalAmount 150,000, paid → 30,000
↓↓↓
الخطوة 1: سحب الدين من B = -80,000 → رصيد B = 120,000
الخطوة 2: newRemaining = 150,000 - 30,000 = 120,000
  رصيد C = 50,000 + 120,000 = 170,000 ✅
```

#### السيناريو 9: تغيير العميل (دين → دين، مع نقصان المبلغ)
```
الأصل: A2 (باقي 80,000)، العميل B (رصيده 200,000)
التعديل: customerName → 'محمد', items نقصت → totalAmount 60,000, paid → 10,000
↓↓↓
الخطوة 1: سحب الدين من B = -80,000 → رصيد B = 120,000
الخطوة 2: newRemaining = 60,000 - 10,000 = 50,000
  رصيد C = 50,000 + 50,000 = 100,000 ✅
```

#### السيناريو 10: تغيير العميل (دين → نقد)
```
الأصل: A2 (باقي 80,000)، العميل B (رصيده 200,000)
التعديل: customerName → 'محمد', paymentType → 'نقد'
↓↓↓
→ الحالة الأولى (دين→نقد) تتفعل، وليس تغيير العميل
لأن الشرط `oldPaymentType == 'دين' && data.paymentType == 'نقد'` يسبق شرط تغيير العميل
debtChange = -80,000
رصيد B = 200,000 - 80,000 = 120,000 ✅
العميل C لا يتأثر لأنه نقد (لا يوجد باقي)
transaction(B, -80,000, 'invoice_payment_type_change')
```

#### السيناريو 11: تغيير العميل (نقد → دين)
```
الأصل: A1 (نقد)، العميل B (ليس له دين مرتبط لأنها نقد)
التعديل: customerName → 'محمد', paymentType → 'دين', paid → 10,000
↓↓↓
→ الحالة الثانية (نقد→دين) تتفعل
newRemaining = 100,000 - 10,000 = 90,000
رصيد C = 50,000 + 90,000 = 140,000 ✅
transaction(C, +90,000, 'invoice_payment_type_change')
```

#### السيناريو 12: تغيير العميل مع زيادة الأصناف وزيادة الدين
```
الأصل: A2 (باقي 80,000)، B (200,000)
التعديل: customerName → 'محمد', items زادت , total=200,000, paid=50,000
↓↓↓
سحب 80,000 من B → B=120,000
newRemaining=150,000 → C=50,000+150,000=200,000 ✅
```

#### السيناريو 13: تغيير العميل مع نقصان الأصناف (حتى يصفر الدين)
```
الأصل: A2 (باقي 80,000)، B (200,000)
التعديل: customerName → 'محمد', items نقصت, total=30,000, paid=30,000 (نقد)
↓↓↓
case 1 (debt→cash) because paymentType='نقد'
debtChange = -80,000 من B
B = 200,000 - 80,000 = 120,000 ✅
(لا دين جديد لأن مدفوع بالكامل)
```

#### السيناريو 14: تغيير العميل (دين → دين) مع رصيد B غير كافٍ للخصم
```
الأصل: A2 (باقي 80,000)، B (رصيده 50,000 فقط!)
التعديل: customerName → 'محمد', paymentType → 'دين'
↓↓↓
التحقق المسبق:
debtChange = -80,000
expectedNewBalance = 50,000 - 80,000 = -30,000 🚫
→ يتم رفض الحفظ قبل أي تغيير
الرسالة: "رصيد العميل أحمد الحالي: 50,000"
          "المبلغ الذي سيُخصم: 80,000"
          "الرصيد المتوقع: -30,000 (سالب!)"
          "السبب: تم تغيير اسم العميل، وسيُخصم الدين من العميل القديم أحمد."
          "الحل: تأكد من أن العميل القديم لديه رصيد كافٍ، أو عدّل المعاملات أولاً."
```

#### السيناريو 15: تغيير العميل مع إضافة خصم
```
الأصل: A2 (باقي 80,000)، total=100,000، B (200,000)
التعديل: customerName→'محمد', discount=20,000 (بدلاً من 0), paid=10,000
↓↓↓
سحب 80,000 من B → B=120,000
newTotal = 100,000 - 20,000 = 80,000
newRemaining = 80,000 - 10,000 = 70,000 → C=50,000+70,000=120,000 ✅
```

#### السيناريو 16: تغيير العميل مع إضافة أجور تحميل
```
الأصل: A2 (باقي 80,000)، loadingFee=0
التعديل: customerName→'محمد', loadingFee=10,000, paid=20,000
↓↓↓
سحب 80,000 من B → B=120,000
newTotal = 100,000 + 10,000 = 110,000
newRemaining = 110,000 - 20,000 = 90,000 → C=50,000+90,000=140,000 ✅
```

#### السيناريو 17: تغيير العميل مع تغيير التاريخ فقط (بدون تغيير مالي)
```
الأصل: A2 (باقي 80,000)، B (200,000)
التعديل: customerName→'محمد', كل المبالغ المالية نفسها
↓↓↓
سحب 80,000 من B → B=120,000
newRemaining = 80,000 → C=50,000+80,000=130,000 ✅
``` 

#### السيناريو 18: تغيير العميل من جديد إلى جديد
```
الأصل: A2 (باقي 80,000)، B (200,000) ← العميل حالياً
التعديل الأول: غيرناه لـ C
التعديل الثاني: غيرناه لـ D (عميل جديد رصيده 0)
↓↓↓
سحب 80,000 من... C؟ لا!
كوّد الحفظ الثاني:
data.invoiceToManage هو الفاتورة الأصلية (من snapshot)
oldPaymentType من الفاتورة الأصلية = 'دين'
oldCustomerId من الفاتورة الأصلية = B.id
newCustomerId = D.id
→ case 3 يتفعل: يسحب من B الأصلي ويضيف لـ D
⚠️ ملاحظة مهمة: C الذي أخذ الدين في التعديل الأول لن يُسحب منه!!
لأن oldCustomerId يُقرأ من `data.invoiceToManage` (الفاتورة الأصلية قبل أي تعديل)
هذه قد تكون مشكلة إذا لم يُحدّث `invoiceToManage` بشكل صحيح.
``` 

---

### القسم الثالث: تعديل فاتورة دين (نفس العميل) — 15 سيناريو

#### السيناريو 19: زيادة المبلغ الإجمالي (إضافة أصناف)
```
الأصل: A2 (باقي 80,000)، العميل B (رصيده 200,000)
التعديل: totalAmount ← 150,000 (زاد 50,000)، paid ← 20,000 (نفسه)
↓↓↓
newRemaining = 150,000 - 20,000 = 130,000
currentDebtFromTx = 80,000 (المبلغ المسجل في transactions لهذه الفاتورة)
debtChange = 130,000 - 80,000 = +50,000
رصيد B الجديد = 200,000 + 50,000 = 250,000 ✅
transaction(B, +50,000, 'invoice_edit', 'تعديل فاتورة دين رقم X')
```

#### السيناريو 20: نقصان المبلغ الإجمالي (حذف أصناف)
```
الأصل: A2 (باقي 80,000)، B (200,000)
التعديل: totalAmount ← 60,000، paid ← 20,000
↓↓↓
newRemaining = 60,000 - 20,000 = 40,000
debtChange = 40,000 - 80,000 = -40,000
رصيد B الجديد = 200,000 - 40,000 = 160,000 ✅
transaction(B, -40,000, 'invoice_edit')
```

#### السيناريو 21: زيادة المبلغ المدفوع (تقليل الدين)
```
الأصل: A2 (باقي 80,000)، B (200,000)
التعديل: paid ← 50,000 (كانت 20,000)
↓↓↓
newRemaining = 100,000 - 50,000 = 50,000
debtChange = 50,000 - 80,000 = -30,000
رصيد B الجديد = 200,000 - 30,000 = 170,000 ✅
```

#### السيناريو 22: إنقاص المبلغ المدفوع (زيادة الدين)
```
الأصل: A2 (باقي 80,000)، B (200,000)
التعديل: paid ← 0 (كانت 20,000)
↓↓↓
newRemaining = 100,000 - 0 = 100,000
debtChange = 100,000 - 80,000 = +20,000
رصيد B الجديد = 200,000 + 20,000 = 220,000 ✅
```

#### السيناريو 23: زيادة الخصم
```
الأصل: A2 (باقي 80,000)، total=100,000، discount=0، B (200,000)
التعديل: discount ← 20,000، paid ← 30,000
↓↓↓
newTotal = 100,000 - 20,000 = 80,000
newRemaining = 80,000 - 30,000 = 50,000
debtChange = 50,000 - 80,000 = -30,000
رصيد B = 200,000 - 30,000 = 170,000 ✅
```

#### السيناريو 24: إنقاص الخصم
```
الأصل: A2 (باقي 80,000)، discount=10,000 (يعني total أصلها 110,000 - 10,000 = 100,000)، B (200,000)
التعديل: discount ← 0، paid ← 20,000
↓↓↓
newTotal = 110,000 - 0 = 110,000
newRemaining = 110,000 - 20,000 = 90,000
debtChange = 90,000 - 80,000 = +10,000
رصيد B = 200,000 + 10,000 = 210,000 ✅
```

#### السيناريو 25: إضافة أجور تحميل
```
الأصل: A2 (باقي 80,000)، loadingFee=0، B (200,000)
التعديل: loadingFee ← 15,000، paid ← 35,000
↓↓↓
newTotal = 100,000 + 15,000 = 115,000
newRemaining = 115,000 - 35,000 = 80,000
debtChange = 80,000 - 80,000 = 0
رصيد B = 200,000 (لا تغيير لأن الفرق 0) ✅
(مع أنه زاد loadingFee، لكن paid زادت بالمقابل فبقي الدين نفسه)
```

#### السيناريو 26: إلغاء أجور التحميل
```
الأصل: A2 (باقي 80,000)، loadingFee=10,000، total=110,000، paid=30,000، B(200,000)
التعديل: loadingFee ← 0، paid ← 20,000
↓↓↓
newTotal = 100,000 - 0 = 100,000 (مع discount)
newRemaining = 100,000 - 20,000 = 80,000
debtChange = 80,000 - 80,000 = 0
رصيد B = 200,000 (لا تغيير) ✅
```

#### السيناريو 27: حذف جميع الأصناف وإضافة صنف واحد جديد (نفس الإجمالي)
```
الأصل: A2 (باقي 80,000)
التعديل: حذف كل الأصناف وإضافة صنف جديد بإجمالي 100,000، paid=20,000
↓↓↓
newRemaining = 100,000 - 20,000 = 80,000
debtChange = 0
رصيد B = 200,000 (لا تغيير) ✅
```

#### السيناريو 28: حذف جميع الأصناف وإضافة صنف واحد بإجمالي أقل
```
الأصل: A2 (باقي 80,000)
التعديل: حذف كل الأصناف وإضافة صنف جديد total=50,000، paid=10,000
↓↓↓
newRemaining = 50,000 - 10,000 = 40,000
debtChange = 40,000 - 80,000 = -40,000
رصيد B = 200,000 - 40,000 = 160,000 ✅
```

#### السيناريو 29: تغيير الأصناف (نفس العدد والإجمالي)
```
الأصل: A2 (باقي 80,000)، B (200,000)
التعديل: نفس العدد من الأصناف ونفس الإجمالي لكن بمنتجات مختلفة
↓↓↓
newRemaining = 80,000
debtChange = 0
رصيد B = 200,000 ✅
(لا تأثير على الدين لأن الإجمالي والمدفوع لم يتغيرا)
```

#### السيناريو 30: تعديل يؤدي إلى جعل الدين صفراً (تسديد كامل)
```
الأصل: A2 (باقي 80,000)، B (200,000)
التعديل: paid ← 100,000 (تسديد كامل)
↓↓↓
newRemaining = 100,000 - 100,000 = 0
debtChange = 0 - 80,000 = -80,000
رصيد B = 200,000 - 80,000 = 120,000 ✅
transaction(B, -80,000, 'invoice_edit')
```

#### السيناريو 31: زيادة الإجمالي لدرجة أن الرصيصيد لا يكفي (خصوصاً مع عميل آخر مدين لهذا العميل)
هذا سيناريو معقد:
```
الأصل: A2 (باقي 80,000)، B (200,000)
التعديل: customerName → 'محمد' (C, رصيده 30,000 فقط)
         totalAmount ← 200,000، paid ← 0
↓↓↓
التحقق المسبق:
debtChange = -80,000 (للخصم من B)
expectedNewBalance(B) = 200,000 - 80,000 = 120,000 ✅ (B بخير)

التنفيذ:
سحب 80,000 من B → B=120,000 ✅
newRemaining = 200,000 → C=30,000+200,000=230,000 ✅
(هذا يمر لأن التحقق فقط من الرصيد B وليس C)
⚠️ C ممكن يصبح مديون ب 230,000 دون أي تحقق مسبق من قدرته!
```

#### السيناريو 32: تعديل دين مع سحوبات متعددة (عدة تعديلات متتالية)
```
الأصل: A2 (باقي 80,000)، B (200,000)
التعديل الأول: total=90,000، paid=20,000 ← newRem=70,000 ← debtChange=-10,000 B=190,000
التعديل الثاني: total=80,000، paid=20,000 ← newRem=60,000 ← debtChange=-20,000 B=170,000
التعديل الثالث: total=120,000، paid=20,000 ← newRem=100,000 ← debtChange=+20,000 B=190,000
⚠️ في كل تعديل، oldRemaining يُقرأ من `data.invoiceToManage` (الفاتورة الأصلية)
لكن في الكود، `currentDebtFromTx` يُقرأ من جدول transactions:
  SELECT SUM(amount_changed) as total FROM transactions WHERE invoice_id = X
هذا يعيد 80,000 (الدين الأصلي) + (-10,000 من التعديل الأول) + (-20,000 من الثاني) ...
لذا الحساب في التعديل الثالث سيكون:
  currentDebtFromTx = 80,000 - 10,000 - 20,000 = 50,000
  newRemaining = 100,000
  debtChange = 100,000 - 50,000 = +50,000
  B = 170,000 + 50,000 = 220,000 ✅
```

#### السيناريو 33: تعديل دين مع تغيير المبلغ المدفوع فقط (بدون تغيير الأصناف)
```
الأصل: A2 (باقي 80,000)، B (200,000)
التعديل: paid فقط من 20,000 إلى 50,000 (نفس الأصناف)
↓↓↓
newRemaining = 100,000 - 50,000 = 50,000
debtChange = 50,000 - 80,000 = -30,000
B = 200,000 - 30,000 = 170,000 ✅
```

#### السيناريو 34: تعديل دين مع تغيير الخصم فقط
```
الأصل: A2 (باقي 80,000)، total=100,000، discount=0، B(200,000)
التعديل: discount=30,000 فقط
↓↓↓
newTotal = 100,000 - 30,000 = 70,000
newRemaining = 70,000 - 20,000 = 50,000
debtChange = 50,000 - 80,000 = -30,000
B = 200,000 - 30,000 = 170,000 ✅
```

---

### القسم الرابع: فاتورة جديدة بالدين (New Debt Invoice) — 6 سيناريوهات

#### السيناريو 35: فاتورة جديدة بالدين بالكامل
```
جديد: total=100,000، paid=0، paymentType='دين'، العميل B (رصيده 200,000)
↓↓↓
case 5: newRemaining = 100,000 - 0 = 100,000
رصيد B = 200,000 + 100,000 = 300,000 ✅
transaction(B, +100,000, 'invoice_debt', 'دين فاتورة جديدة رقم X')
```

#### السيناريو 36: فاتورة جديدة بالدين مع دفع جزء
```
جديد: total=100,000، paid=30,000، paymentType='دين'، B(200,000)
↓↓↓
newRemaining = 70,000
رصيد B = 200,000 + 70,000 = 270,000 ✅
```

#### السيناريو 37: فاتورة جديدة بالدين (عميل جديد)
```
جديد: total=50,000، paid=0، paymentType='دين'، عميل جديد D (رصيده 0)
↓↓↓
العميل ينشأ أولاً
newRemaining = 50,000
رصيد D = 0 + 50,000 = 50,000 ✅
transaction(D, +50,000, 'invoice_debt')
```

#### السيناريو 38: فاتورة نقدية جديدة (بدون تأثير على الديون)
```
جديد: total=100,000، paid=100,000، paymentType='نقد'
↓↓↓
case 5 لا يتفعل لأن paymentType != 'دين'
لا يوجد أي تأثير على الديون
(ولكن المخزون يتأثر!)
```

#### السيناريو 39: فاتورة نقدية جديدة بدفع كامل مع فكة
```
جديد: total=100,000، paid=100,000، paymentType='نقد'
↓↓↓
لا تأثير على الديون
``` 

#### السيناريو 40: فاتورة جديدة بدين مع أجور تحميل
```
جديد: total=100,000، loadingFee=10,000، paid=0، paymentType='دين'
↓↓↓
newTotal = 100,000 + 10,000 = 110,000
newRemaining = 110,000 - 0 = 110,000
رصيد B = 200,000 + 110,000 = 310,000 ✅
```

---

### القسم الخامس: التعديلات المتداخلة (Complex Combinations) — 8 سيناريوهات

#### السيناريو 41: دين → نقد مع زيادة المبلغ الإجمالي
```
الأصل: A2 (باقي 80,000)، B (200,000)
التعديل: paymentType='نقد', total=150,000 (زاد)، paid=150,000
↓↓↓
case 1 (debt→cash) يتفعل:
debtChange = -80,000
B = 200,000 - 80,000 = 120,000 ✅
(paid أُجبرت على totalAmount لأن paymentType='نقد' في saveInvoice سطر 428-431)
```

#### السيناريو 42: دين → نقد مع إنقاص المبلغ الإجمالي
```
الأصل: A2 (باقي 80,000)، B (200,000)
التعديل: paymentType='نقد', total=50,000 (نقص)، paid=50,000
↓↓↓
debtChange = -80,000
B = 200,000 - 80,000 = 120,000 ✅
``` 

#### السيناريو 43: تغيير العميل + تحويل نقد ← دين (في نفس التعديل)
```
الأصل: A1 (نقد)، B ليس له علاقة
التعديل: customerName='محمد', paymentType='دين', paid=0
↓↓↓
case 2 (cash→debt) يتفعل:
newRemaining = 100,000
C = 50,000 + 100,000 = 150,000 ✅
transaction(C, +100,000, 'invoice_payment_type_change')
B لا يتأثر (لم يكن له دين مرتبط)
```

#### السيناريو 44: تغيير العميل + دين ← نقد (فيه العميل الجديد)
```
الأصل: A2 (باقي 80,000)، B(200,000)
التعديل: customerName='محمد', paymentType='نقد'
↓↓↓
case 1 (debt→cash) له الأولوية على case 3
debtChange = -80,000
B = 200,000 - 80,000 = 120,000 ✅
C لا يتأثر (نقد)
transaction(B, -80,000, 'invoice_payment_type_change')
→ الخلاصة: عندما نحول إلى نقد، العميل الجديد لا يهم. السحب من العميل القديم.
```

#### السيناريو 45: تعديل دين مع تغيير اسم العميل إلى نفس الاسم (باختلاف المسافة)
```
الأصل: A2 (باقي 80,000)، customerName='أحمد'
التعديل: customerName='أحمد ' (مع مسافة)
↓↓↓
isCustomerChanged = false (لأن الكود يشيل المسافات ويقارن lowercase)
→ case 4 (edit same customer) يتفعل
debtChange = newRem - oldRem
``` 

#### السيناريو 46: تعديل دين مع تغيير اسم العميل تماماً (لكن نفس العميل ID)
```
الأصل: A2 (باقي 80,000)، customerName='أحمد', customerId=5
التعديل: customerName='أحمد الجديد', نفس الـ customerId
↓↓↓
isCustomerChanged = true (لأن الاسم اختلف)
oldCustomerId = 5, newCustomerId = 5 (نفسهما)
→ شرط case 3 يتطلب oldCustomerId != newCustomerId → هذا false
→ case 4: oldPaymentType == 'دين' && data.paymentType == 'دين' && customer != null
  و (oldCustomerId == newCustomerId) → يتفعل case 4 ✅
debtChange = newRem - oldRem
```

#### السيناريو 47: فاتورة معلقة → تعديل → حفظ
```
الأصل: فاتورة معلقة (status='معلقة', isLocked=true)، دين، باقي 80,000
التعديل: فتحها، تعديل الأصناف، حفظ
↓↓↓
في saveInvoice سطر 442-449:
  if old status == 'معلقة' → newStatus = 'محفوظة', newIsLocked = false
ثم معالجة الديون كالمعتاد (case 4)
``` 

#### السيناريو 48: فاتورة محفوظة ← فتح للعرض فقط ← لا تعديل
```
الأصل: فاتورة محفوظة (status='محفوظة')
→ تُفتح مع isViewOnly = true
→ لا يمكن التعديل
→ زر التعديل يفعل وضع التعديل (setState: isViewOnly = false)
→ بعد التعديل والحفظ، تبقى 'محفوظة' (لأن status لا تتغير)
``` 

---

### القسم السادس: السيناريوهات الحدودية والحالات الخاصة — 8 سيناريوهات

#### السيناريو 49: نفس الفاتورة، نفس البيانات (تعديل بدون أي تغيير حقيقي)
```
الأصل: A2 (باقي 80,000)، B (200,000)
التعديل: نفس البيانات بالكامل
↓↓↓
newRemaining = 80,000
currentDebtFromTx = 80,000
debtChange = 0
→ لا يتم تسجيل أي transaction (لأن |debtChange| < 0.001)
→ B يبقى 200,000 ✅
``` 

#### السيناريو 50: الفرق في amount_changed أقل من 0.001 (تجاهل)
```
الأصل: A2 بكميات كسرية، باقي 80,000.5 (مثلاً 100,000 - 19,999.5)
التعديل: تغيير طفيف جداً ← newRemaining = 80,000.4
↓↓↓
debtChange = 80,000.4 - 80,000.5 = -0.1
|debtChange| = 0.1 > 0.001 → يسجل ✅
لو كان الفرق 0.0005 → لا يسجل (أقل من 0.001)
``` 

#### السيناريو 51: عميل مدين لهذا العميل (حسابات متقاطعة) — ليس في الكود
هذا لا يتعامل معه الكود مباشرة. لا يوجد مفهوم "الدائن" مقابل "المدين" بل مجرد
`current_total_debt` (إذا كان موجباً فهو دين عليه، إذا سالباً... لكن الكود لا يسمح بالسالب)

#### السيناريو 52: عدة فواتير لنفس العميل تم تعديلها في نفس الوقت
```
العميل B عنده فاتورتين: F1 (باقي 80,000) و F2 (باقي 50,000)
التعديل: F1 ← paid زاد → باقي 40,000، F2 ← total زاد → باقي 70,000
↓↓↓
كل فاتورة تُعدّل بشكل مستقل:
F1: debtChange = -40,000
F2: debtChange = +20,000
بعد F1: B = 200,000 - 40,000 = 160,000
بعد F2: B = 160,000 + 20,000 = 180,000 ✅
``` 

#### السيناريو 53: فتح فاتورة للتعديل من قبل مستخدمين اثنين (Locking)
```
المستخدم A فتح الفاتورة للتعديل أولاً ← حصل على Lock
المستخدم B حاول فتحها ← Lock فشل ← رسالة:
  "الفاتورة قيد التعديل من قبل مستخدم آخر"
لا يمكن التعديل ← يخرج
``` 

#### السيناريو 54: انقطاع الكهرباء أثناء الحفظ
```
الـ Transaction يضمن atomicity:
- قبل commit: إذا انقطعت الكهرباء، التراجع عن كل شيء
- بعد commit: الفاتورة محفوظة + `PRAGMA synchronous = FULL` + `PRAGMA wal_checkpoint(FULL)`
→ الفاتورة محفوظة بالكامل أو ملغية بالكامل (no partial save)
```

#### السيناريو 55: Audit Log — تتبع التغييرات
```
بعد كل حفظ (إنشاء أو تعديل)، يُسجل audit log:
oldValues: JSON {total_amount, discount, payment_type, paid_amount, customer_id}
newValues: JSON {total_amount, discount, payment_type, paid_amount, customer_id, customer_name, items_count}
و snapshot في جدول invoice_snapshots
``` 

#### السيناريو 56: Error Handling — خطأ في قاعدة البيانات
```
إذا فشلت أي خطوة داخل الـ Transaction:
  → throw Exception
  → التراجع عن كل شيء (ROLLBACK)
  → رسالة خطأ للمستخدم
``` 

---

## <a name="5"></a>5. حالات خاصة وتفاصيل دقيقة

### 5.1. متغير `currentDebtFromTx` (سطر 638-643)

```dart
final txSum = await txn.rawQuery(
  'SELECT COALESCE(SUM(amount_changed), 0) as total FROM transactions WHERE invoice_id = ?',
  [invoiceId]
);
currentDebtFromTx = (txSum.first['total'] as num?)?.toDouble() ?? 0.0;
```

هذا هو **إجمالي كل معاملات الدين** لهذه الفاتورة عبر تاريخها. يختلف عن `oldRemaining` المحسوب من `data.invoiceToManage` الذي هو الفرق بين `totalAmount` و `amountPaidOnInvoice` في **النسخة الأصلية** من الفاتورة.

**الفرق الحرج:** بعد التعديل الأول، `oldRemaining` من `invoiceToManage` يبقى كما هو (80,000) لكن `currentDebtFromTx` يصبح 70,000 (بعد خصم التعديل الأول). لذا في التعديل الثاني، `debtChange` يحسب الفرق بشكل صحيح.

### 5.2. متغير `balanceBeforeTransaction` — هل هو دقيق؟

في حالات التعديل داخل الـ Transaction، يتم جلب `currentCustomer.currentTotalDebt` **بعد** أن يكون الـ Transaction قد عدّل `invoices` لكن **قبل** أن يعدّل `customers`. هذا يعني أن `balanceBeforeTransaction` قد يكون الرصيد **الحالي** وليس الرصيد الأصلي قبل التعديل الأول. هذا بسبب أن `txn.update('invoices', ...)` حدث قبل جلب رصيد العميل.

### 5.3. `InvoiceDao.insertInvoiceAdjustment` — تأثير جانبي (سطر 100-119)

```dart
await txn.rawUpdate(
  'UPDATE invoices SET total_amount = total_amount + ? WHERE id = ?',
  [adjustmentAmount, adj.invoiceId]
);
```

كل تسوية تُحدّث تلقائياً `total_amount` في جدول `invoices`. لكن **لا تُحدّث** `current_total_debt` في `customers`. تأثير التسوية على الديون يحتاج معالجة منفصلة (لم يتم تنفيذها بشكل كامل في DAO).

### 5.4. `InvoiceManager.saveCompleteInvoice` (ملف منفصل)

هذه دائرة **مختلفة** عن `InvoiceController.saveInvoice`. تستخدم `LockService` و `PRAGMA synchronous = FULL`. تتعامل مع إنشاء الفاتورة فقط (ليس التعديل). معالجة الديون فيها أبسط:
```
إذا دين ← أضف الباقي إلى current_total_debt
وإلا ← لا شيء
```

### 5.5. `DebtCalculator.verifyCustomerBalance` — التحقق من صحة الرصيد

```dart
final storedBalance = customer['current_total_debt'];
final calculatedBalance = SUM(amount_changed FROM transactions WHERE customer_id = X);
if (MoneyCalculator.areEqual(storedBalance, calculatedBalance)) → صحيح
else → خطأ (يمكن إصلاحه بـ fixCustomerBalance)
```

هذا يعني أن جدول `transactions` هو **مصدر الحقيقة** و `customers.current_total_debt` مجرد **خلاصة سريعة**.

---

## <a name="6"></a>6. آلية Snapshot والتدقيق

### 6.1. متى يتم أخذ Snapshot؟

في `saveInvoice` (سطور 358-378):

1. **إذا أول تعديل:** snapshot `original` — "النسخة الأصلية قبل أي تعديل"
2. **قبل كل تعديل:** snapshot `before_edit` — "قبل التعديل"
3. **بعد كل حفظ إنشاء:** snapshot `original` — "النسخة الأصلية عند الإنشاء"
4. **بعد كل تعديل:** snapshot `after_edit` — "بعد التعديل - الإجمالي: X"

### 6.2. Audit Log (سطور 850-928)

يُسجل لكل عملية حفظ:
- `operationType`: `invoice_create` أو `invoice_update`
- `entityType`: `invoice` و `customer`
- `oldValues` ← JSON للقيم القديمة
- `newValues` ← JSON للقيم الجديدة

---

## <a name="7"></a>7. التسويات (InvoiceAdjustments)

### 7.1. أنواع التسويات

من `EditInvoicesScreen` و `CreateInvoiceScreen`:

1. **تسوية بند (Item Settlement):**
   - اختيار منتج + كمية + سعر
   - إما debit (زيادة) أو credit (نقص/راجع)
   - `settlementPaymentType`: 'نقد' أو 'دين'

2. **تسوية مبلغ مباشر (Amount Settlement):**
   - مبلغ مباشر + ملاحظة
   - اختيار نوع الدفع للزيادة (نقد/دين)
   - النقص (credit) دائماً 'دين' (سطر 1783)

### 7.2. تأثير التسويات

عند إدراج تسوية عبر `InvoiceDao.insertInvoiceAdjustment`:
- يتم تحديث `total_amount` في `invoices`
- **لا** يتم تحديث `current_total_debt` في `customers`
- **لا** يتم إضافة سجل في `transactions`

أي أن التسويات تؤثر على إجمالي الفاتورة لكن تأثيرها على الديون يحتاج خطوة منفصلة.

### 7.3. أنواع `settlementPaymentType`

في `_openSettlementAmountDialog` (سطر 1782-1784):
```dart
String paymentKind = _settlementIsDebit
    ? ((invoiceToManage?.paymentType == 'دين') ? 'دين' : 'نقد')
    : 'دين';
```
- للزيادة (debit): تتبع نوع دفع الفاتورة الأصلية (إذا كانت دين ← 'دين'، إذا نقد ← 'نقد')
- للنقص (credit): دائماً 'دين' (لأن الراجع يُخصم من الدين)

---

## <a name="8"></a>8. مشاكل وحلول معروفة (معتمدة من ملفات الـ Fix في المشروع)

### 8.1. مشكلة الرصيد المزدوج
الموجودة في `FINAL_INITIAL_DEBT_FIX.md` و `إصلاح_كشف_الحساب_النهائي.md`

المشكلة: عند إنشاء فاتورة دين، يتم إضافة الدين عبر `InvoiceManager` (في إنشاء الفاتورة) لكن قد يتم أيضاً إضافته عبر `InvoiceController` (في الحفظ). هذا يؤدي لمضاعفة الدين.

### 8.2. مشكلة `current_total_debt` يصبح سالباً
تمت معالجتها في الدالة `validateDebtChangeWontCauseNegativeBalance` التي تمنع التعديل إذا كان سيؤدي لرصيد سالب.

### 8.3. تضارب التعديلات المتزامنة
تمت معالجتها عبر `LockService` (قفل الفاتورة والعميل أثناء التعديل).

### 8.4. مشكلة عدم تطابق الرصيد مع المعاملات
يمكن إصلاحها عبر `DebtCalculator.fixCustomerBalance` أو `fixAllCustomerBalances`.

### 8.5. `InvoiceInputData.invoiceToManage` — هل هو النسخة الأصلية أم المعدلة؟

من تعليقات الكود (سطور 613-628):
> "I will assume `data.invoiceToManage` might be the modified one."
> "I will require `originalInvoice` in `InvoiceInputData` for edit operations."

هذا **غموض خطير** في التصميم. في `InvoiceActionsMixin.saveInvoice`:
```dart
final inputData = InvoiceInputData(
  invoiceToManage: invoiceToManage,  // ← هل هذا هو الأصل أم المُعدّل؟
  ...
);
```
إذا كان `invoiceToManage` هو **النسخة المعدلة** (وليس الأصلية)، فإن `data.invoiceToManage.totalAmount` و `data.invoiceToManage.amountPaidOnInvoice` و `data.invoiceToManage.paymentType` قد لا تعكس الحالة الأصلية. الكود يعتمد أن `invoiceToManage` هو الأصل (لأنه يُستخدم في حساب `oldRemaining` و `oldPaymentType`)، لكن في الـ UI، `invoiceToManage` يتغير (مثلاً سطر 580 في invoice_actions: `invoiceToManage = savedInvoice`).

### 8.6. الأصناف غير المكتملة
الكود (سطر 423) يجمع فقط `_isInvoiceItemComplete(item)` لحساب الإجمالي. أي صنف بدون كمية أو سعر يُتجاهل تماماً. هذا يمنع "تضخم الإجمالي بعناصر ناقصة".

---

## الملخص النهائي

```
+------------------+     +------------------+     +---------------------+
|  Invoice         |     |  Customer        |     |  Transactions       |
|  (فاتورة)        |     |  (عميل)          |     |  (سجل ديون)         |
+------------------+     +------------------+     +---------------------+
| id               |     | id               |     | id                  |
| total_amount     |     | name             |     | customer_id ------->|
| amount_paid      |     | current_total_   |     | invoice_id -------->|
| payment_type     |     |   debt (مشتق)    |     | amount_changed      |
| customer_id ---->|     +------------------+     | balance_before      |
| discount         |           ↑                   | balance_after       |
| loading_fee      |           | sync via          | transaction_type    |
+------------------+           | transactions      +---------------------+
        |                      |
        | v (عبر التسويات)     |
+------------------+           |
| InvoiceAdjust-   |           | (لا تؤثر مباشرة
| ments (تسويات)   |           |  على debt!
| لا تؤثر على      |           |
| transactions)    |           |
+------------------+           |
                               |
              +----------------+----------------+
              |                                   |
     DebtCalculator.verifyCustomerBalance()    DebtCalculator.fixCustomerBalance()
     (يقارن current_total_debt مع SUM           (يعيد حساب current_total_debt
      of transactions)                           من transactions)
```

### تدفق القرار داخل `saveInvoice` لتحديد أي case ينفذ:

```
هل هو تعديل (isNewInvoice == false)؟
  ├── لا → هل paymentType == 'دين' و customer != null؟
  │     ├── نعم → Case 5: new debt invoice (+transaction)
  │     └── لا → لا شيء (نقدي)
  │
  └── نعم → oldPaymentType من data.invoiceToManage
        │
        ├── old = 'دين' و new = 'نقد'
        │     → Case 1: إلغاء الدين ← oldCustomer (invoice_payment_type_change)
        │
        ├── old = 'نقد' و new = 'دين'
        │     → Case 2: إضافة دين ← customer (invoice_payment_type_change)
        │
        ├── old = 'دين' و new = 'دين' و oldCustomerId != newCustomerId
        │     → Case 3: نقل الدين (سحب من old + إضافة لـ new)
        │
        ├── old = 'دين' و new = 'دين' ونفس العميل
        │     → Case 4: تعديل الدين (debtChange = diff)
        │
        └── حالات أخرى → لا تأثير على الديون
```

**ملاحظة ختامية:** `current_total_debt` في جدول `customers` هو قيمة **مشتقة** (derived). المصدر الأساسي هو `transactions`. يجب استخدام `DebtCalculator.verifyCustomerBalance` دورياً للتحقق من صحة الأرصدة، و `DebtCalculator.fixCustomerBalance` لإصلاح أي اختلاف.
