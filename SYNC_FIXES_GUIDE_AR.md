# دليل إصلاحات نظام المزامنة (Firebase) — للنقل إلى مشروع آخر

> هذا الدليل يشرح **كل** تعديل أُجري على نظام المزامنة في هذا المشروع: ما المشكلة التي كان يسببها الكود القديم، وما القاعدة الصحيحة، وماذا تغيّر بالضبط (الملف، الدالة، الكود).
> الهدف: أن تستطيع تطبيق نفس الإصلاحات على مشروع آخر خطوة بخطوة.
>
> كل إصلاح هنا اكتُشف واختُبر بمحاكِي كامل موجود في `tools/sync_sim` (شرحه في آخر الدليل).
> النتيجة النهائية بعد كل الإصلاحات: **43 من 43 سيناريو ناجحة، و700 من 700 تجربة فوضى عشوائية ناجحة** (400 بشبكة عادية و300 بشبكة قاسية؛ كل تجربة فيها 10 أجهزة و400 عملية عشوائية، ثم إعادة تشغيل كل الأجهزة والتحقق مرة ثانية).
> الكود القديم كان يفشل في 31 من 43 سيناريو، وفي كل تجارب الفوضى.
> **ثم اختبار كود التطبيق الحقيقي نفسه** (القسم 19.ب) على 10 أجهزة وهمية، في مرحلتين:
> 1. **الديون والمعاملات والفواتير:** 101 من 101 تجربة قاسية و20 من 20 عادية، ووجد 19 خللاً حقيقياً.
> 2. **المخزون المشترك والإرجاع وحسابات الفاتورة** (الأقسام 21–22)، على الكود النهائي: **20 من 20 قاسية** و**10 من 10 عادية** واختبار الحسابات واختبار الترقية — بلا أي فرق في رصيد أو كمية، وبلا خطأ غير ممسوك. ووجدت هذه المرحلة 16 خللاً آخر (القائمة في 19.ب).
> 3. **مراجعة الكود ثم إصلاح ما وجدته** (21.6–21.8): دمج نسختين من المنتج نفسه، وكلفة الشراء مع مخزون سالب، وكلفة قراءة الحركات — وثلاثة أخطاء ظهرت أثناء الإصلاح. على الكود النهائي: **20 من 20 قاسية** و**10 من 10 عادية** و**10 من 10 قاسية بأصناف مكررة الاسم كثيرة** (48 نسخة مكررة الاسم دُمجت في التجارب الأربعين)، واختبار الدمج (3 سيناريوهات) واختبار الكلفة — بلا أي فرق، وبلا خطأ غير ممسوك.
> 4. **المخاطر المتبقية** (القسم 25): قفل سجلات النسخة المستعادة، وتنبيهات صحة المزامنة في الشاشة الرئيسية (جهاز بإصدار قديم، ساعة خاطئة، قواعد Firebase، صنف مدموج، تكرار اسم قديم)، وعودة الأصناف والحركات المحذوفة من السحابة وحدها، ومنع الاسم المكرر — ووجدت تجاربها خللين آخرين (اسم مكرر بسباق، وظهور عميل محذوف بصف صافيه صفر). على الكود النهائي: **20 من 20 قاسية** و**10 من 10 عادية** و**10 من 10 قاسية بأصناف مكررة الاسم** (منها البذرتان اللتان كشفتا الخللين)، و14 من 14 اختباراً محدداً (منها 6 للمخاطر المتبقية واختبار الشريط) — بلا أي فرق، وبلا خطأ غير ممسوك.

---

## الفهرس

0. [كيف تستخدم هذا الدليل](#0)
1. [القواعد الذهبية العشر](#1)
2. [مصطلحات](#2)
3. [تعديلات قاعدة البيانات (المخطط)](#3)
4. [ملف جديد: قاعدة ظهور العميل](#4)
5. [تعديلات طبقة البيانات (DAO)](#5)
6. [تعديلات DatabaseService والنسخ الاحتياطي والفواتير في الواجهة](#6)
7. [خدمة المزامنة الرئيسية FirebaseSyncService](#7)
8. [مزامنة الفواتير InvoiceSyncService](#8)
9. [الحارس المحاسبي للفواتير InvoiceDebtReconciler](#9)
10. [المراقب SyncWatchdog](#10)
11. [المطابقة المحصّنة ArmoredReconciliationService](#11)
12. [قرارات الإبطال MatchVerdictService (تعطيل)](#12)
13. [المطابقة الحية LiveMatchService](#13)
14. [التنظيف الذكي SmartPipe والإقرارات ACK](#14)
15. [التدقيق الذاتي ReconciliationService](#15)
16. [الأمان: سرّ المجموعة والتوقيع والوضع الصارم](#16)
17. [ترتيب التطبيق على مشروع آخر + قائمة تحقق](#17)
18. [جدول: كل سيناريو ← الإصلاح الذي يحله](#18)
19. [المحاكِي: كيف تشغّله وكيف تستخدمه في مشروع آخر](#19)
20. [تحذيرات مهمة قبل النشر](#20)
21. [المخزون المشترك: دفتر حركات بدل رقم مطلق](#21)
22. [الإرجاع وحسابات الفاتورة](#22)
23. [قائمة فحص على أجهزة حقيقية (قبل البيع)](#23)
24. [خطة المراقبة بعد النشر (أول أسبوعين)](#24)
25. [المخاطر المتبقية بعد الإصلاحات — وكيف عولجت](#25)

---

<a id="0"></a>
## 0. كيف تستخدم هذا الدليل

- الإصلاحات **مترابطة**. لا تطبّق إصلاحاً واحداً وتترك الباقي؛ بعضها يعتمد على أعمدة وقواعد يضيفها غيره. اتّبع الترتيب في القسم 17.
- كل قسم مكتوب بهذا الشكل:
  - **المشكلة:** ماذا كان يحدث فعلاً (مع رقم السيناريو في المحاكي).
  - **القاعدة:** المبدأ الصحيح.
  - **التعديل:** الملف والدالة وما تغيّر، مع الكود.
- الكود المنقول هنا هو الكود الفعلي في هذا المشروع. إن اختلفت أسماء الجداول أو الأعمدة في المشروع الآخر، غيّر الأسماء وحافظ على المنطق.
- النسخ الأصلية للملفات قبل التعديل محفوظة في المجلد `_backup_sync_sim/` (اسم كل ملف فيه هو مساره مع استبدال `/` بـ `__`). لرؤية الفرق الكامل لأي ملف:

```bash
diff -u _backup_sync_sim/lib__services__firebase_sync__firebase_sync_service.dart lib/services/firebase_sync/firebase_sync_service.dart
```

---

<a id="1"></a>
## 1. القواعد الذهبية العشر

كل الإصلاحات تطبيق لهذه القواعد. إن فهمتها، فهمت كل شيء بعدها.

1. **الهوية هي `sync_uuid` وحده، لا الاسم.** عميلان بنفس الاسم شخصان مختلفان ما لم يحملا نفس المعرّف. الربط بالاسم مسموح فقط لسجل قديم لم يُعطَ معرّفاً قط.
2. **الرصيد = مجموع المعاملات النشطة.** لا يُكتب رصيد من الشبكة أبداً، ولا يُحسب بـ«الرصيد السابق + المبلغ».
3. **الملكية:** المعاملة يعدّلها ويرفعها **منشئها فقط**. ووثيقة العميل يرفعها منشئه فقط. الاستثناء الوحيد: «شاهد الحذف» (انظر 4).
4. **الحذف نهائي وينتقل بشواهد.** حذف عميل = شاهد حذف للعميل + شاهد حذف لكل معاملة كان الجهاز الحاذف يعرفها (حتى معاملات الأجهزة الأخرى). لا يُكتب `isDeleted:false` لمعاملة أبداً، ولا تُحيي نسخةٌ نشطة معاملةً محذوفة.
5. **اختفاء مستند من السحابة ليس أمر حذف.** (تنظيف، أو زر «حذف قاعدة البيانات السحابية»). الحذف الحقيقي فقط `isDeleted:true`.
6. **إصدار المستند = وقت الخادم `uploadedAt`.** لا تُطبَّق نسخة أقدم مما طُبّق، ويُسجَّل دائماً أعلى إصدار رُئي.
7. **الرفع الآمن:** اقرأ الصف من القاعدة لحظة الرفع (لا لقطة قديمة من طابور)، خذ القفل قبل أي انتظار، ولا تعلّم الصف «مرفوعاً» إلا إن لم يتغير أثناء الرفع (CAS).
8. **معاملات الفواتير تسافر داخل حزمة الفاتورة فقط** (إلا شاهد الحذف).
9. **استعادة نسخة احتياطية = «وضع استعادة»:** لا رفع حتى تُقارن النسخة بالسحابة. ما رفعه الجهاز بعد أخذ النسخة يتقدّم على ما في النسخة، **إلا** ما عدّله المستخدم بعد الاستعادة.
10. **لا إبطال عن بُعد.** لا جهاز يأمر جهازاً آخر بحذف معاملة. المطابقة لا تُبطل إلا صفاً لا يوجد أي دليل على صحته.

---

<a id="2"></a>
## 2. مصطلحات

| المصطلح | المعنى |
|---|---|
| المالك / المنشئ | الجهاز الذي أنشأ المعاملة أو العميل. محلياً: `is_created_by_me = 1` (أو NULL في السجلات القديمة جداً = يُعامل كمالك). |
| شاهد الحذف (Tombstone) | مستند في السحابة يحمل `isDeleted: true`. هو الطريقة الوحيدة لنقل الحذف. |
| الإصدار | `uploadedAt` (وقت خادم Firestore) للمستند. يُخزّن محلياً في `transactions.remote_ver` بالملّي ثانية. |
| CAS | Compare-And-Set: بعد الرفع نقارن الصف الحالي ببصمة ما أُرسل؛ إن تغيّر أثناء الرفع لا نعلّمه مرفوعاً. |
| وضع الاستعادة | حالة بعد استعادة نسخة احتياطية: الرفع موقوف حتى يكتمل «التمهيد» (طلب إعادة البث + سحب كامل). |
| التمهيد (Bootstrap) | جهاز جديد أو مستعيد يطلب من جهاز آخر إعادة بثّ المستندات الغائبة من السحابة. |
| SmartPipe | خدمة تحذف مستندات المعاملات من السحابة بعد أن تقرأها كل الأجهزة (لتوفير المساحة). |
| ACK | إقرار استلام يكتبه الجهاز المستقبِل بعد تطبيق نسخة معاملة. |

---

<a id="3"></a>
## 3. تعديلات قاعدة البيانات (المخطط)

**الملف:** `lib/services/database/core/database_migrations.dart` داخل دالة ضمان المخطط (`ensureSchema`)، بعد إنشاء الجداول (في هذا المشروع وُضعت قبل «23. إضافة رقم الفاتورة التجاري»).

`addColumnIfNotExists` تضيف العمود إن لم يوجد، فهي آمنة التكرار عند كل تشغيل.

```dart
// 22.ب. 🛡️ أعمدة سلامة المزامنة
await DatabaseHelpers.addColumnIfNotExists(db, 'transactions', 'origin_device_id', 'TEXT');
await DatabaseHelpers.addColumnIfNotExists(db, 'transactions', 'remote_ver', 'INTEGER');
await DatabaseHelpers.addColumnIfNotExists(db, 'transactions', 'remote_modified_at', 'TEXT');
await DatabaseHelpers.addColumnIfNotExists(db, 'transactions', 'last_uploaded_at', 'TEXT');
await DatabaseHelpers.addColumnIfNotExists(db, 'transactions', 'restored_mark', 'INTEGER DEFAULT 0');
await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'restored_mark', 'INTEGER DEFAULT 0');
await DatabaseHelpers.addColumnIfNotExists(db, 'invoices', 'owner_device_id', 'TEXT'); // القسم 8.12
await DatabaseHelpers.addColumnIfNotExists(db, 'customers', 'tombstoned', 'INTEGER DEFAULT 0');
// العملاء المحذوفون قبل هذا العمود: نثبّت وسم حذفهم كي لا تُظهرهم قاعدة الظهور الجديدة
try {
  await db.execute(
      'UPDATE customers SET tombstoned = 1 WHERE is_deleted = 1 AND (tombstoned IS NULL OR tombstoned = 0)');
} catch (_) {}
```

### معنى كل عمود ومن يكتبه

| العمود | المعنى | يُكتب في |
|---|---|---|
| `transactions.origin_device_id` | معرّف جهاز Firebase المالك لمعاملة وصلت من المزامنة. يُستخدم عند إعادة البث حتى لا يسرق الجهاز المُجيب ملكيتها. | الاستقبال (`_applyTransactionChange`)، استعادة معاملتي (`_handleOwnTxDoc`)، كشف المطابقة. |
| `transactions.remote_ver` | إصدار آخر نسخة طُبّقت (uploadedAt بالملّي ثانية). يمنع تطبيق نسخة أقدم فوق أحدث. | الاستقبال. |
| `transactions.remote_modified_at` | `lastModifiedAt` كما كتبه المالك؛ يُعاد بثّه كما هو للجهاز الجديد. | الاستقبال. |
| `transactions.last_uploaded_at` | متى رفع هذا الجهاز آخر نسخة من معاملته. يُقارن به في وضع الاستعادة. | الرفع (بعد نجاح CAS). |
| `transactions.restored_mark` | 1 = الصف جاء من نسخة احتياطية مستعادة ولم يُعدَّل بعدها. أي تعديل محلي يجعله 0. | الاستعادة (=1)، كل تعديل محلي (=0)، انتهاء الاستعادة (=0). |
| `invoices.restored_mark` | نفس الفكرة للفواتير المملوكة. | الاستعادة، الحفظ/التعديل/الحذف المحلي، انتهاء الاستعادة، الاستقبال (=0). |
| `invoices.owner_device_id` | معرّف جهاز Firebase المالك لفاتورة **واردة**. يُعاد بثّه مع الحزمة فيتعرّف المالك (بعد استعادة نسخة احتياطية) على فاتورته. | استقبال الحزمة (القسم 8.12). |
| `customers.tombstoned` | حالة حذف العميل للمزامنة: **0** لا شيء، **1** محذوف (شاهد مرفوع أو وارد)، **2** حذف محلي بانتظار رفع الشاهد، **3** إعادة تنشيط محلية بانتظار الرفع. | الحذف المحلي (=2)، إعادة إنشاء عميل محذوف (=3)، بعد الرفع (2←1، 3←0)، استقبال شاهد (=1). |

> **لماذا `tombstoned` منفصل عن `is_deleted`؟** لأن `is_deleted` صار «مخفي في الواجهة»، و`tombstoned` صار «هل عليه شاهد حذف». العميل قد يكون عليه شاهد حذف لكنه ظاهر لأن جهازاً آخر سجّل عليه بيعاً أوفلاين بعد الحذف (القسم 4).

---

<a id="4"></a>
## 4. ملف جديد: قاعدة ظهور العميل

**الملف الجديد:** `lib/services/database/business/customer_visibility.dart`

**المشكلة (سيناريو 41):** حذف عميل على جهاز D1، بينما D4 أوفلاين سجّل عليه بيعاً جديداً. النتيجة كانت تختلف حسب ترتيب الوصول: D4 يُبقي العميل بكل ديونه القديمة، وبقية الأجهزة تحذفه أو تعيده بالبيع الجديد فقط. كل جهاز رقم مختلف.

**القاعدة:** الظهور دالة حتمية على حالة تتقارب عند كل الأجهزة:
> **العميل مخفي ⇔ عليه شاهد حذف (`tombstoned` = 1 أو 2) ولا معاملة نشطة له.**

الجهاز الحاذف يُبطل كل معاملة كان يعرفها (بشواهد تصل للجميع)، فما يبقى نشطاً عند الجميع هو نفسه بالضبط: ما سُجّل بعد الحذف. فتصل كل الأجهزة لنفس النتيجة.

**«نشطة»** = معاملة يدوية أو تسديد غير محذوفة، أو **فاتورة مساهمتها غير صفرية** (مجموع صفوف دينها). فاتورة صافيها صفر (نُقلت لعميل آخر أو سُدّدت) لا تعيد عميلاً محذوفاً — كانت النسخة الأولى تعدّ أي صف غير محذوف، فيظهر العميل على بعض الأجهزة دون غيرها (25.6.ج).

**الكود كاملاً:**

```dart
import 'package:sqflite/sqflite.dart';

import 'invoice_debt_reconciler.dart';

class CustomerVisibility {
  static Future<void> apply(DatabaseExecutor db, int customerId) async {
    final r = await db.rawQuery('''
      SELECT c.tombstoned AS tomb, c.is_deleted AS del
      FROM customers c WHERE c.id = ?
    ''', [customerId]);
    if (r.isEmpty) return;
    final tomb = (r.first['tomb'] as num?)?.toInt() ?? 0;
    final tombstoned = tomb == 1 || tomb == 2;
    final hidden = (tombstoned && await _activeCount(db, customerId) == 0) ? 1 : 0;
    final del = (r.first['del'] as num?)?.toInt() ?? 0;
    if (del != hidden) {
      await db.update('customers', {'is_deleted': hidden},
          where: 'id = ?', whereArgs: [customerId]);
    }
  }

  static Future<int> _activeCount(DatabaseExecutor db, int customerId) async {
    const types = InvoiceDebtReconciler.nonContributionTypes;
    final ph = List.filled(types.length, '?').join(',');
    const linked = "(invoice_id IS NOT NULL OR COALESCE(invoice_sync_uuid, '') != '')";
    final manual = await db.rawQuery('''
      SELECT COUNT(*) AS n FROM transactions
      WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)
        AND (NOT $linked OR transaction_type IN ($ph))
    ''', <Object?>[customerId, ...types]);
    final invoices = await db.rawQuery('''
      SELECT COUNT(*) AS n FROM (
        SELECT SUM(amount_changed) AS s FROM transactions
        WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)
          AND $linked
          AND (transaction_type IS NULL OR transaction_type NOT IN ($ph))
        GROUP BY COALESCE(NULLIF(invoice_sync_uuid, ''), 'id:' || invoice_id)
      ) WHERE ABS(s) > 0.005
    ''', <Object?>[customerId, ...types]);
    return ((manual.first['n'] as num?)?.toInt() ?? 0) +
        ((invoices.first['n'] as num?)?.toInt() ?? 0);
  }
}
```

**أين تُستدعى:** بعد **كل** تغيير في معاملات عميل أو في حالة حذفه: الاستقبال، استقبال شاهد الحذف، حزمة الفاتورة الواردة، الحارس المحاسبي للفواتير، المطابقة المحصّنة. (في خدمة المزامنة عبر الغلاف `_applyCustomerVisibility(customerId)`.)

---

<a id="5"></a>
## 5. تعديلات طبقة البيانات (DAO)

### 5.1 إضافة معاملة: الرصيد السابق من المجموع لا من «آخر صف»

**الملف:** `lib/services/database/dao/transaction_dao.dart` — الدالة `insertTransaction`.

**المشكلة (سيناريو 40):** كان الكود يقارن رصيد العميل المخزّن بـ `new_balance_after_transaction` لآخر معاملة **بالتاريخ**، ويرمي «خطأ أمني حرج» إن اختلفا بأكثر من 1. لكن المزامنة تُدرج معاملات قديمة التاريخ (سُجّلت أوفلاين على جهاز آخر)، فيصبح «آخر صف بالتاريخ» غير آخر صف أُدرج، ويختلف الرقمان دون أي تلف. النتيجة: **المستخدم يُمنع من إضافة أي معاملة لهذا العميل.**

**التعديل:** احذف كتلة «جلب آخر معاملة والتحقق الصارم» كلها، واستبدلها بـ:

```dart
// 2. 🛡️ الرصيد قبل المعاملة = مجموع المعاملات الفعّالة (مصدر الحقيقة الوحيد).
final sumRows = await txn.rawQuery(
  'SELECT COALESCE(SUM(amount_changed), 0) AS total FROM transactions '
  'WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
  [transaction.customerId],
);
double verifiedBalanceBefore =
    (sumRows.first['total'] as num?)?.toDouble() ?? 0.0;
if ((verifiedBalanceBefore - customer.currentTotalDebt).abs() > 0.01) {
  print('🛡️ رصيد العميل ${transaction.customerId} المخزّن '
      '(${customer.currentTotalDebt}) ≠ مجموع معاملاته '
      '($verifiedBalanceBefore) — اعتُمد المجموع');
}
```

### 5.2 تعديل معاملة يدوياً: يمحو وسم الاستعادة

**الملف:** `transaction_dao.dart` — الدالة `updateManualTransaction`، داخل خريطة `update`:

```dart
'is_uploaded': fromSync ? 1 : 0,
// 🛡️ تعديل بعد استعادة نسخة احتياطية = نية جديدة لا تُستبدل بنسخة السحابة
if (!fromSync) 'restored_mark': 0,
```

### 5.3 تحويل نوع المعاملة (دين ↔ تسديد)

**الملف:** `transaction_dao.dart` — الدالة `convertTransactionType`.

**المشكلة 1 (سيناريو 32):** التحويل كان يغيّر النوع والإشارة محلياً ولا يضع `is_uploaded = 0`، فلا يُرفع أبداً: الجهاز يعرض −1000 وبقية الأجهزة +1000 إلى الأبد (فرق 2000).
**المشكلة 2 (سيناريو 34):** الواجهة تسمح بتحويل معاملة وصلت من جهاز آخر. التحويل يقلب رصيد هذا الجهاز وحده ولا يصل لأحد (لأنه ليس مالكها) — تباعد دائم.

**التعديل:**

```dart
if (transaction.invoiceId != null) {
  throw Exception('لا يمكن تحويل نوع معاملة مرتبطة بفاتورة');
}
// 🛡️ حماية الملكية (كما في التعديل)
if (!transaction.isCreatedByMe) {
  throw Exception('هذه المعاملة أُنشئت على جهاز آخر ولا يمكن تحويلها من هذا الجهاز.');
}
```

وفي خريطة `update` للمعاملة المحوّلة أضف:

```dart
'is_uploaded': 0,
'restored_mark': 0,
```

### 5.4 حذف عميل

**الملف:** `lib/services/database/dao/customer_dao.dart` — الدالة `deleteCustomer`.

**التعديل:**
1. المعاملات: علّم **النشطة فقط** محذوفة، و`is_uploaded = 0` لكل واحدة منها (حتى معاملات الأجهزة الأخرى — المزامنة سترفع لكل واحدة شاهد حذف)، و`restored_mark = 0`.
   - لماذا النشطة فقط؟ صف محذوف سابقاً ورُفع شاهده لا يجب أن يعود للطابور.
2. العميل: `tombstoned = 2` (حذف محلي بانتظار الرفع).

```dart
await txn.update(
  'transactions',
  {'is_deleted': 1, 'is_uploaded': 0, 'restored_mark': 0},
  where: 'customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
  whereArgs: [id],
);
final result = await txn.update(
  'customers',
  {
    'is_deleted': 1,
    'tombstoned': 2,
    'current_total_debt': 0.0,
    'current_total_debt_cents': 0,
    'last_modified_at': now,
    // ... باقي الحقول كما كانت
  },
  where: 'id = ?',
  whereArgs: [id],
);
```

### 5.5 إعادة إنشاء عميل محذوف (إعادة تنشيط صريحة)

**الملف:** `customer_dao.dart` — الدالة `insertCustomer`، في الفرع الذي يجد عميلاً موجوداً (محذوفاً) ويعيد تفعيله:

```dart
final updateMap = updatedCustomer.toMap();
updateMap['is_created_by_me'] = existingRows.first['is_created_by_me'];
updateMap['last_modified_at'] = DateTime.now().toIso8601String();
// 🛡️ إعادة تنشيط صريحة: تُرفع isDeleted=false مرة واحدة لتلغي شاهد الحذف
final prevTomb = (existingRows.first['tombstoned'] as int?) ?? 0;
updateMap['tombstoned'] = (prevTomb == 1 || prevTomb == 2) ? 3 : 0;
```

> تأكد أن الاستعلام الذي يجلب `existingRows` يجلب عمود `tombstoned` (أو كل الأعمدة).

### 5.6 تعديل الفاتورة: رقم النسخة لا ينزل أبداً

**الملف:** `lib/services/database/dao/invoice_dao.dart` — الدالة `updateInvoice`.

**المشكلة:** شاشات القفل، مبلغ الإرجاع، التعليق تكتب `invoice.toMap()` كما هو، ومعه رقم النسخة من كائن الشاشة (قد يكون أقدم من الصف). فتنزل النسخة؛ ثم يأخذ التعديل التالي رقماً سبق رفعه بمحتوى مختلف، فتتجاهله الأجهزة الأخرى (لأن نسختها «مساوية»)، ويبقى دينها القديم.

**التعديل:** داخل معاملة SQLite: اقرأ نسخة الصف، واكتب `max(نسخة الصف، نسخة الكائن) + 1`، و`is_synced = 0`، و`restored_mark = 0`:

```dart
return await db.transaction((txn) async {
  final cur = await txn.query('invoices',
      columns: ['version'], where: 'id = ?', whereArgs: [invoice.id], limit: 1);
  final dbVersion =
      cur.isEmpty ? 0 : ((cur.first['version'] as num?)?.toInt() ?? 1);
  final map = invoice.toMap();
  map['version'] =
      (dbVersion > invoice.version ? dbVersion : invoice.version) + 1;
  map['is_synced'] = 0;
  map['restored_mark'] = 0;
  return await txn.update('invoices', map,
      where: 'id = ?', whereArgs: [invoice.id]);
});
```

---

<a id="6"></a>
## 6. تعديلات DatabaseService والنسخ الاحتياطي والفواتير في الواجهة

**الملف:** `lib/services/database_service.dart`

أضف الاستيرادات:

```dart
import 'dart:async' show unawaited;
import 'firebase_sync/invoice_sync_service.dart';
```

### 6.1 حذف عميل ← رفع الحذف فوراً

**المشكلة (سيناريو 15):** كان `deleteCustomer` يرفع وثيقة العميل فقط. ثم كل جهاز يستقبل الحذف كان يحذف محلياً ويعيد **رفع** الوثيقة، فترتد بين الأجهزة بلا نهاية: **9983 كتابة لمستند عميل واحد**، حتى يُستنفد حد المعدل ويُشلّ رفع كل شيء آخر (معاملة جديدة وصلت بعد 48 دقيقة).

**التعديل:** استبدل كتلة الرفع بعد الحذف بـ:

```dart
if (syncUuid != null && syncUuid.isNotEmpty) {
  try {
    unawaited(FirebaseSyncService().syncCustomerDeletionNow(id));
  } catch (e) {
    print('⚠️ تعذّر إرسال أمر حذف العميل لـ Firebase: $e');
  }
}
```

(`syncCustomerDeletionNow` في القسم 7.12: ترفع شاهد العميل وشاهد كل معاملة. وإن فشلت، التقطتها دورات المزامنة لأن DAO علّم كل شيء `is_uploaded = 0` و`tombstoned = 2`.)

### 6.2 تعديل/تحويل معاملة ← رفع فوري

**المشكلة (سيناريوهات 04، 05، 33):** شاشة العميل تستدعي `updateManualTransaction` مباشرة (لا عبر AppProvider)، فكان التعديل ينتظر إعادة تشغيل أو تبدّل الشبكة. ولعملاء أنشأتهم أجهزة أخرى لا يُرفع أبداً.

**التعديل:**

```dart
Future<Customer> updateManualTransaction(DebtTransaction updated, {bool fromSync = false}) async {
  await database;
  await _transactionDao.updateManualTransaction(updated, fromSync: fromSync);
  if (!fromSync) {
    _triggerCustomerSync(updated.customerId);
  }
  // ... كما كان
}

/// رفع فوري لمعاملات هذا الجهاز المعلّقة على عميل (بلا انتظار — الفشل تلتقطه الدورات).
void _triggerCustomerSync(int customerId) {
  try {
    unawaited(FirebaseSyncService().syncCustomerNow(customerId).catchError((_) {}));
  } catch (_) {}
}
```

وفي `convertTransactionType` بعد استدعاء DAO:

```dart
await _transactionDao.convertTransactionType(transactionId);
_triggerCustomerSync(tx.customerId);
```

### 6.3 حذف فاتورة ← حذف منطقي يتزامن

**المشكلة (سيناريو 20):** كان `deleteInvoice` يحذف صف الفاتورة نهائياً ويترك معاملة دينها نشطة (`ON DELETE SET NULL` تمسح الربط فقط)، فيبقى الدين على الجهاز وعلى كل الأجهزة، ولا يُرفع شيء لأن الفاتورة لم تعد موجودة. (ملاحظة: هذه الدالة لا تستدعيها الواجهة حالياً في هذا المشروع، لكنها صُحّحت.)

**التعديل:** الدالة كاملة:

```dart
Future<int> deleteInvoice(int id) async {
  final db = await database;
  final check = await db.query('invoices',
      columns: ['is_created_by_me', 'invoice_uuid', 'customer_id', 'version'],
      where: 'id = ?', whereArgs: [id], limit: 1);
  if (check.isEmpty) return 0;
  if (check.first['is_created_by_me'] == 0) {
    throw Exception('لا يمكن حذف هذه الفاتورة لأنها مستوردة من جهاز آخر.');
  }

  final res = await db.transaction((txn) async {
    // 1. إرجاع الكميات للمخزن
    final itemsMaps = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);
    final items = itemsMaps.map((m) => InvoiceItem.fromMap(m)).toList();
    await InventoryHelpers.adjustStockForItems(txn, items, isAddition: true);

    // 2. حذف منطقي + نسخة جديدة + طابور الرفع
    final version = (check.first['version'] as int?) ?? 1;
    final updated = await txn.update('invoices', {
      'is_deleted': 1,
      'version': version + 1,
      'is_synced': 0,
      'restored_mark': 0,
      'last_modified_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);

    // 3. الحارس المحاسبي: مساهمة فاتورة محذوفة = صفر
    await InvoiceDebtReconciler.reconcileInvoice(txn, id,
        createMissing: false, reason: 'حذف الفاتورة');
    return updated;
  });

  // 4. رفع فوري لحزمة الفاتورة
  final uuid = check.first['invoice_uuid'] as String?;
  if (uuid != null && uuid.isNotEmpty) {
    try {
      unawaited(InvoiceSyncService().syncInvoiceBundleNow(uuid).catchError((_) => false));
    } catch (_) {}
  }
  return res;
}
```

> يحتاج هذا أن تكون كل الاستعلامات التي تعرض الفواتير تستبعد `is_deleted = 1` في المشروع الآخر.

### 6.4 استعادة نسخة احتياطية ← وضع الاستعادة

**المشكلة (سيناريو 26 + الفوضى القاسية):** نسخة احتياطية قديمة تفتقد ما وصل بعد أخذها (وقد يكون نُظّف من السحابة)، وقد تحمل تعديلات «بانتظار الرفع» سبق أن رُفعت نسخ أحدث منها. بعد الاستعادة كان الجهاز يرفع هذه البيانات القديمة فوق الأحدث في السحابة، فتنتشر لكل الأجهزة.

**التعديل:** ثوابت ودالتان في `DatabaseService`:

```dart
static const String restoredFlagKey = 'sync_db_restored_pending';
static const String restoredRowsMarkedKey = 'sync_db_restored_rows_marked';

/// يُضبط العلَم فقط (عندما يُستبدل ملف القاعدة وهي مغلقة، كاستعادة Dropbox)؛
/// وتُوسم الصفوف عند أول تهيئة للمزامنة بعدها.
static Future<void> flagDatabaseRestored() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(restoredFlagKey, true);
    await prefs.setBool(restoredRowsMarkedKey, false);
  } catch (e) {
    print('⚠️ تعذّر ضبط علَم الاستعادة: $e');
  }
}

Future<void> markDatabaseRestored([Database? db]) async {
  await flagDatabaseRestored();
  try {
    final d = db ?? await database;
    await d.rawUpdate('UPDATE transactions SET restored_mark = 1');
    await d.rawUpdate('UPDATE invoices SET restored_mark = 1 WHERE is_created_by_me = 1 OR is_created_by_me IS NULL');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(restoredRowsMarkedKey, true);
  } catch (e) {
    print('⚠️ تعذّر وسم صفوف النسخة المستعادة: $e');
  }
}
```

**واستدعِهما:**
- في `restoreDatabaseFromFile` بعد التحقق من صلاحية الملف المستورد: `await markDatabaseRestored(newDb);`
- في `lib/services/dropbox_backup_service.dart` بعد نسخ الملف فوق القاعدة: `await DatabaseService.flagDatabaseRestored();`
- **أي** مسار آخر في المشروع الآخر يستبدل ملف قاعدة البيانات (استيراد، Google Drive، …) يجب أن يستدعي أحدهما.

(إن فشل الوسم لأن الملف المستعاد قديم ولا يحوي العمود بعد، يعيد `_loadRecoveryState` الوسم عند أول تشغيل للمزامنة — القسم 7.2.)

### 6.5 ختم الفاتورة قبل الحفظ

**الملف:** `database_service.dart` — الدالة `stampInvoiceForSync` (تُستدعى قبل أي إدراج/تحديث فاتورة من الشاشة). أضف في آخرها:

```dart
map['is_synced'] = 0;
// وتعديل المستخدم بعد استعادة نسخة احتياطية يتقدّم على نسخة السحابة
map['restored_mark'] = 0;
```

### 6.6 حفظ الفاتورة من الشاشة: النسخة من الأكبر

**الملف:** `lib/controllers/invoice_controller.dart` — قبل استدعاء `stampInvoiceForSync`.

**المشكلة:** النسخة الجديدة كانت تُبنى على نسخة كائن الشاشة (`data.invoiceToManage?.version`). إن رفعها الحارس المحاسبي أو تعديل سابق في القاعدة، يعيد الحفظ رقماً سبق رفعه → تتجاهله الأجهزة الأخرى.

```dart
int? baseVersion = data.invoiceToManage?.version;
final existingId = data.invoiceToManage?.id;
if (!data.isNewInvoice && existingId != null) {
  final vr = await txn.query('invoices',
      columns: ['version'], where: 'id = ?', whereArgs: [existingId], limit: 1);
  final dbVersion = vr.isEmpty ? null : (vr.first['version'] as num?)?.toInt();
  if (dbVersion != null && (baseVersion == null || dbVersion > baseVersion)) {
    baseVersion = dbVersion;
  }
}
await DatabaseService.stampInvoiceForSync(
  invoiceMap,
  isNew: data.isNewInvoice,
  currentVersion: baseVersion,
);
```


---

<a id="7"></a>
## 7. خدمة المزامنة الرئيسية FirebaseSyncService

**الملف:** `lib/services/firebase_sync/firebase_sync_service.dart` — أكبر التعديلات. مرتبة هنا حسب ترتيب الملف.

الاستيرادات الجديدة:

```dart
import 'package:shared_preferences/shared_preferences.dart';
import '../database/business/customer_visibility.dart';
```

### 7.1 حد معدل العمليات (Rate Limiter)

**المشكلة (سيناريوهات 07، 08، 15):**
- الحد القديم (120/دقيقة، 1000/ساعة) جعل رفع يوم عمل أوفلاين (1500 معاملة) يستغرق **86 دقيقة**، و30 معاملة **93 ثانية**.
- عند أي عاصفة كتابة يُشلّ الرفع كله ساعةً كاملة.
- **الأخطر:** العملية المحجوبة بالحد كانت تُرجع `true` («نجاح»)، فتُحذف من طابور الإعادة وتضيع.

**التعديل:**

```dart
final SyncRateLimiter _rateLimiter = SyncRateLimiter(
  maxOperationsPerMinute: 600,
  maxOperationsPerHour: 20000,
);
```

وفي كل دوال الرفع: المحجوب يُرجع `false` (يُعاد لاحقاً) لا `true`:

```dart
if (!_rateLimiter.canProceed()) return false;
_rateLimiter.recordOperation();
```

**النتيجة:** 30 معاملة في 7 ثوانٍ، 1500 معاملة في 6 دقائق.

### 7.1.ب لا تهيئتان متوازيتان (اكتُشف باختبار الكود الحقيقي)

**المشكلة:** `initialize` لم يكن يحمي نفسه من الاستدعاء المتوازي. التهيئة قد تطول (مثلاً رفع معلّق بلا إنترنت)، وأثناءها يستدعيها `_onConnectionRestored` عند عودة الاتصال، أو مؤقت إعادة المحاولة، فتبدأ **تهيئة ثانية فوق الأولى**: مستمعون وخدمات مزدوجة تعالج نفس المستند مرتين في آن واحد.

**التعديل:** غيّر اسم جسم الدالة إلى `_initializeImpl`، واجعل `initialize` غلافاً يعيد التهيئة الجارية إن وُجدت:

```dart
Future<bool>? _initInFlight;

Future<bool> initialize({void Function(double progress, String message)? onProgress}) {
  if (_isInitialized) {
    onProgress?.call(1.0, 'تم التهيئة مسبقاً');
    return Future.value(true);
  }
  final inFlight = _initInFlight;
  if (inFlight != null) return inFlight;
  final f = _initializeImpl(onProgress: onProgress);
  _initInFlight = f;
  return f.whenComplete(() => _initInFlight = null);
}
```

### 7.1.ج خطاف العودة للتطبيق لا يُسقط التهيئة

`_startLifecycleHook` ينشئ `AppLifecycleListener`، وهذا يحتاج بيئة واجهة Flutter. خارج الخيط الرئيسي (مهام `workmanager` الخلفية، أو اختبار الأجهزة الوهمية) يرمي استثناءً كان يُسقط `initialize` كلها. الحل: لفّه بـ `try/catch`، فالخطاف تحسين للعودة من الخلفية لا شرط للمزامنة.

وأُضيفت دالة للاختبار فقط تشغّل الدورة الخلفية فوراً بدل انتظار 10 دقائق:

```dart
@visibleForTesting
Future<void> debugRunBackgroundCycle() => _performBackgroundSync();
```

### 7.2 حقول وضع الاستعادة

```dart
bool _recoveryMode = false;
bool _bootstrapping = false;
bool get isRecovering => _recoveryMode;
```

**تحميل الحالة** — تُستدعى في `initialize` مباشرة بعد ضبط معرّف الجهاز (`UuidHelper.configureDevice`):

```dart
await _loadRecoveryState();
```

```dart
Future<void> _loadRecoveryState() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    _recoveryMode = prefs.getBool(DatabaseService.restoredFlagKey) ?? false;
    if (_recoveryMode && !(prefs.getBool(DatabaseService.restoredRowsMarkedKey) ?? false)) {
      // استُبدل ملف القاعدة وهي مغلقة (Dropbox): نوسم الصفوف الآن
      final db = await _db.database;
      await db.rawUpdate('UPDATE transactions SET restored_mark = 1');
      await db.rawUpdate('UPDATE invoices SET restored_mark = 1 WHERE is_created_by_me = 1 OR is_created_by_me IS NULL');
      await prefs.setBool(DatabaseService.restoredRowsMarkedKey, true);
    }
    if (_recoveryMode) {
      _syncEventController.add('استعادة نسخة احتياطية: جاري طلب ما فاتها من الأجهزة الأخرى...');
    }
  } catch (e) {
    print('⚠️ _loadRecoveryState: $e');
  }
}
```

**إنهاء الاستعادة** (بعد اكتمال التمهيد):

```dart
Future<void> _finishRecovery() async {
  if (!_recoveryMode) return;
  try {
    final db = await _db.database;
    await db.rawUpdate('UPDATE transactions SET restored_mark = 0 WHERE restored_mark = 1');
    // فاتورة من النسخة لم تحلّ محلها نسخة سحابية وفيها تغيير معلّق:
    // نسخة جديدة فوق كل ما سبق رفعه، ثم يُمحى الوسم.
    await db.rawUpdate('UPDATE invoices SET version = COALESCE(version, 1) + 1 '
        'WHERE restored_mark = 1 AND is_synced = 0');
    await db.rawUpdate('UPDATE invoices SET restored_mark = 0 WHERE restored_mark = 1');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(DatabaseService.restoredFlagKey);
    await prefs.remove(DatabaseService.restoredRowsMarkedKey);
  } catch (e) {
    print('⚠️ _finishRecovery: $e');
  }
  _recoveryMode = false;
  _syncEventController.add('اكتملت استعادة البيانات من الأجهزة الأخرى');
  unawaited(_syncPendingChanges().catchError((_) {}));
}

Future<void> _markBootstrapComplete(DocumentReference selfRef) async {
  await selfRef.set({'bootstrapCompletedAt': DateTime.now().toIso8601String()},
      SetOptions(merge: true));
  await _finishRecovery();
}
```

**أثر وضع الاستعادة:** كل دوال الرفع تبدأ بـ `if (_recoveryMode) return false;` (أو ترمي استثناء في الرفع القسري)، وكذلك رفع الفواتير (القسم 8.1).

### 7.3 التهيئة: الرفع المعلّق والسحب الكامل يعملان فعلاً

**المشكلة:** داخل `initialize` كان `_syncPendingChanges()` و`performFullCatchUp()` يُستدعيان **قبل** `_isInitialized = true`، وكلاهما يبدأ بـ `if (!_isInitialized) return;` — فلا يعملان أبداً. تعديلات أوفلاين لا تُرفع عند الإقلاع، وشواهد الحذف التي فاتت المستمع لا تُسحب.

**التعديل:** بعد `_isInitialized = true;` و`_updateStatus(FirebaseSyncStatus.online);` أضف:

```dart
unawaited(() async {
  try {
    await _syncPendingChanges();
  } catch (e) {
    print('⚠️ رفع المعلّق بعد التهيئة: $e');
  }
  try {
    await performFullCatchUp();
  } catch (e) {
    print('⚠️ السحب الكامل بعد التهيئة: $e');
  }
}());
```

### 7.4 المزامنة الخلفية (كل 10 دقائق)

**الدالة:** `_performBackgroundSync` — بعد `_retryOldOrphans()` أضف:

```dart
// وضع الاستعادة لم يكتمل (لا شبكة/لا مستجيب)؟ أعد المحاولة
if (_recoveryMode) {
  await ensureNewDeviceBootstrap();
}
// كل ما يملكه هذا الجهاز ولم يُرفع — أياً كان منشئ العميل
await _uploadAllOwnedPending();
await _syncPendingChanges();
```

**وفي `_periodicCleanup`:** احذف استدعاء `_ackService?.cleanupOldAcks();`. الإقرارات دليل تعتمد عليه المطابقة المحصّنة (القسم 11). زر التنظيف اليدوي في الإعدادات باقٍ.

### 7.5 المستمعون (Listeners)

**مستمع العملاء `_onCustomersChanged`:**

**المشكلة (سيناريو 17):** عند `DocumentChangeType.removed` كان يستدعي `_deleteLocalCustomer` فيحذف العميل ومعاملاته محلياً. فزر «حذف قاعدة البيانات السحابية بالكامل» (أو أي تنظيف) **كان يمحو العملاء من كل الأجهزة** (19 خللاً في السيناريو، كل الأجهزة فقدت العملاء).

**التعديل:**

```dart
final syncUuid = change.doc.id;
final sourceDeviceId = data['deviceId'] as String?;

// اختفاء المستند ليس أمر حذف. الحذف الحقيقي = isDeleted.
if (change.type == DocumentChangeType.removed) continue;

// مستند آخر كاتب له هو أنا: قد يحمل شاهد حذف كتبه غيري ودُمج فيه،
// أو عميلاً فقدتُه باستعادة نسخة احتياطية قديمة.
if (sourceDeviceId == _deviceId) {
  try {
    await _handleOwnCustomerDoc(syncUuid, data);
  } catch (e) {
    print('⚠️ مستند عميل ذاتي $syncUuid: $e');
  }
  continue;
}

try {
  await _applyCustomerChange(syncUuid, data); // added و modified بنفس المسار
} catch (e) { ... }
```

**مستمع المعاملات `_onTransactionsChanged`:** مستندي أنا لم يعد يُتجاهل:

```dart
if (sourceDeviceId == _deviceId) {
  if (change.type != DocumentChangeType.removed) {
    try {
      await _handleOwnTxDoc(syncUuid, data);
    } catch (e) {
      print('⚠️ مستند معاملة ذاتي $syncUuid: $e');
    }
  }
  continue;
}
```

**لماذا نعالج مستنداتي؟** سببان:
1. جهاز آخر حذف العميل فكتب شاهد حذف (`isDeleted:true`) على مستند معاملتي، أو كتبتُ أنا بعده بـ merge. يجب أن أطبّق الحذف على نسختي.
2. استعدتُ نسخة احتياطية قديمة لا تحوي معاملتي، فيجب أن أستعيدها من السحابة كمعاملة أملكها.

**نفس التوجيه** في `applyRemoteTransaction` و`applyRemoteCustomer` (تستخدمهما شاشات التدقيق):

```dart
Future<void> applyRemoteTransaction(String syncUuid, Map<String, dynamic> data) async {
  if (data['deviceId'] == _deviceId) {
    await _handleOwnTxDoc(syncUuid, data);
    return;
  }
  await _applyTransactionChange(syncUuid, data);
}

Future<void> applyRemoteCustomer(String syncUuid, Map<String, dynamic> data) async {
  if (data['deviceId'] == _deviceId) {
    await _handleOwnCustomerDoc(syncUuid, data);
    return;
  }
  await _applyCustomerChange(syncUuid, data);
}
```

وكذلك في `performFullCatchUp` و`_downloadAllData` (performFullSync): بدل `continue` لمستنداتي، استدعِ `_handleOwnCustomerDoc` / `_handleOwnTxDoc`.

### 7.5.ب تاريخ آخر مزامنة بإدراج ذرّي (اكتُشف باختبار الكود الحقيقي)

في آخر `_onCustomersChanged` و`_onTransactionsChanged` كان «اقرأ `sync_state` ثم أدرج إن لم يوجد». المستمعان يصلان هنا معاً فيحاولان الإدراج كلاهما: `UNIQUE constraint failed: sync_state.id` خطأ غير ممسوك. استبدل الكتلة في الموضعين بـ:

```dart
await db.rawInsert(
    'INSERT OR IGNORE INTO sync_state (id, last_sync_at) VALUES (1, ?)', [nowStr]);
await db.update('sync_state', {'last_sync_at': nowStr}, where: 'id = 1');
```

### 7.6 استقبال عميل `_applyCustomerChange` (إعادة كتابة)

الخطوات الجديدة بالترتيب:

**(أ) شاهد الحذف قد يخلو من الاسم:**

```dart
final isTombstone = data['isDeleted'] == true || data['is_deleted'] == 1;
final validation = SyncValidation.validateFirebaseCustomerData(data);
if (!validation.isValid && !isTombstone) return;
```

**(ب) التوقيع** (يُفرض فقط في الوضع الصارم — القسم 16):

```dart
if (!await _verifyIncomingSignature(syncUuid, data, isCustomer: true)) return;
```

**(ج) شاهد الحذف له مسار خاص:**

**المشكلة (سيناريو 15):** كان المستقبِل يحذف العميل ومعاملاته محلياً ثم **يعيد رفع** الوثيقة → عاصفة الكتابة. وسياسة «إعادة التنشيط الذكي» كانت تحكم بمعاملات هذا الجهاز وحده، فتختلف النتيجة بين الأجهزة.

```dart
if (isTombstone) {
  await _applyCustomerTombstone(syncUuid, sanitizedData);
  return;
}
```

**(د) الربط بالاسم فقط لسجل بلا هوية:**

**المشكلة (سيناريوهات 12، 13):** إن لم يجد العميل بـ `sync_uuid`، كان يبحث عن **أي** عميل محلي بنفس الاسم ويستبدل معرّفه. فـ«محمد علي» من D1 و«محمد علي» آخر من D2 يُدمجان، وتُكتب هوية أحدهما فوق الآخر، وتتيتّم معاملات الآخر للأبد (20 خللاً).

```dart
final legacyCandidates = await db.query(
  'customers',
  where: "(is_deleted IS NULL OR is_deleted = 0) AND (sync_uuid IS NULL OR sync_uuid = '')",
);
// ... ابحث بالاسم المطبّع داخل legacyCandidates فقط
```

**(هـ) عميل جديد:** عبر `_insertReceivedCustomer` (أدناه) ثم `_processOrphans` ثم `_applyCustomerVisibility`.

**(و) عميل موجود:** تحديث البيانات الوصفية **دون** لمس `is_created_by_me`:

**المشكلة (سيناريو 37):** كان التحديث يضع `is_created_by_me = 0` دائماً. فإذا حرّر D2 فاتورة لعميل أنشأه D1، ورفع D2 وثيقة العميل، يفقد D1 ملكية عميله وتتوقف مسارات رفعه الفوري له.

```dart
final values = <String, Object?>{
  'name': data['name'] ?? localData['name'],
  'phone': data['phone'] ?? localData['phone'],
  'general_note': data['generalNote'] ?? localData['general_note'],
  'address': data['address'] ?? localData['address'],
  'last_modified_at': data['lastModifiedAt'] ?? DateTime.now().toIso8601String(),
  'audio_note_path': data['audioNotePath'] ?? localData['audio_note_path'],
  'synced_at': DateTime.now().toIso8601String(),
  // لا is_created_by_me ولا current_total_debt
};
// إعادة تنشيط صريحة من جهاز آخر (isDeleted=false تُكتب فقط عند التنشيط)
final localTomb = (localData['tombstoned'] as int?) ?? 0;
if (data['isDeleted'] == false && localTomb == 1) {
  values['tombstoned'] = 0;
}
try {
  await db.update('customers', values, where: 'sync_uuid = ?', whereArgs: [syncUuid]);
} on DatabaseException catch (e) {
  // UNIQUE(name, phone) مع عميل آخر مستقل: نميّز الهاتف بمحرف غير مرئي
  if (e.isUniqueConstraintError()) {
    values['phone'] = await _uniquePhoneFor(
        db, values['name']?.toString() ?? '', values['phone']?.toString(), excludeId: customerId);
    await db.update('customers', values, where: 'sync_uuid = ?', whereArgs: [syncUuid]);
  } else {
    rethrow;
  }
}
await _applyCustomerVisibility(customerId);
```

### 7.7 دوال مساعدة جديدة (انسخها كما هي)

**`_insertReceivedCustomer`** — إدراج عميل وارد مع تجاوز قيد `UNIQUE(name, phone)`:

**المشكلة (سيناريوهات 38، 39):** المخطط فيه قيد `UNIQUE(name, phone)`. عميل مستقل يحمل نفس الاسم والهاتف (أُنشئ على جهازين أوفلاين، أو اسم عميل محذوف) يفشل إدراجه، فتتيتّم معاملاته للأبد.
**الحل:** الهوية هي `sync_uuid`، فنُبقي العميلين منفصلين ونميّز الهاتف بمحرف عرض صفري `​` (لا يُرى).

```dart
Future<int> _insertReceivedCustomer(
    Database db, String syncUuid, Map<String, dynamic> data, String name) async {
  final row = <String, Object?>{
    'name': name,
    'phone': data['phone'],
    'current_total_debt': 0.0,
    'general_note': data['generalNote'],
    'address': data['address'],
    'created_at': data['createdAt'],
    'last_modified_at': data['lastModifiedAt'],
    'audio_note_path': data['audioNotePath'],
    'sync_uuid': syncUuid,
    'is_deleted': 0,
    'synced_at': DateTime.now().toIso8601String(),
    'is_created_by_me': 0,
  };
  try {
    return await db.insert('customers', row);
  } on DatabaseException catch (e) {
    if (!e.isUniqueConstraintError()) rethrow;
    row['phone'] = await _uniquePhoneFor(db, name, data['phone']?.toString());
    return await db.insert('customers', row);
  }
}

Future<String> _uniquePhoneFor(Database db, String name, String? phone, {int? excludeId}) async {
  var candidate = phone ?? '';
  for (var k = 1; k <= 20; k++) {
    candidate = '${phone ?? ''}${'​' * k}';
    final clash = await db.query('customers', columns: ['id'],
      where: excludeId == null ? 'name = ? AND phone = ?' : 'name = ? AND phone = ? AND id != ?',
      whereArgs: excludeId == null ? [name, candidate] : [name, candidate, excludeId],
      limit: 1);
    if (clash.isEmpty) break;
  }
  return candidate;
}
```

**`_applyCustomerTombstone`** — تطبيق شاهد حذف عميل وارد:
- لا يحذف المعاملات هنا (يبطلها الجهاز الحاذف بشواهدها الخاصة).
- لا يعيد رفع أي شيء (لا ارتداد).
- إن كان العميل غير موجود محلياً يُنشئه (ليصير موسوماً ويُخفى).
- إن كان عندي إعادة تنشيط محلية لم تُرفع (`tombstoned = 3`) فنسختي أحدث من الشاهد → تجاهل.
- لا يمسّ حذفاً محلياً بانتظار الرفع (`tombstoned = 2`).
- سياسة «الحذف الصارم» (إن اختارها المستخدم): المالك يُبطل معاملاته هو فقط ويرفع شواهدها.

```dart
Future<void> _applyCustomerTombstone(String syncUuid, Map<String, dynamic> data) async {
  final db = await _db.database;
  final rows = await db.query('customers',
      columns: ['id', 'tombstoned'], where: 'sync_uuid = ?', whereArgs: [syncUuid], limit: 1);
  int customerId;
  if (rows.isEmpty) {
    final name = (data['name']?.toString() ?? '').trim();
    customerId = await _insertReceivedCustomer(db, syncUuid, data, name.isEmpty ? 'عميل محذوف' : name);
    await _coordinator!.registerOperation(entityType: 'customer', syncUuid: syncUuid, source: SyncSource.firebase);
    await _coordinator!.markFirebaseSynced('customer', syncUuid);
  } else {
    customerId = rows.first['id'] as int;
    final tomb = (rows.first['tombstoned'] as int?) ?? 0;
    if (tomb == 3) return; // تنشيطي المحلي لم يُرفع بعد — نسختي أحدث
  }
  await db.update('customers',
      {'tombstoned': 1, 'synced_at': DateTime.now().toIso8601String()},
      where: 'id = ? AND (tombstoned IS NULL OR tombstoned != 2)', whereArgs: [customerId]);
  try {
    final policy = await FirebaseSyncSecuritySettings.getCustomerConflictPolicy();
    if (policy == CustomerConflictPolicy.strictDelete) {
      await db.update('transactions', {'is_deleted': 1, 'is_uploaded': 0, 'restored_mark': 0},
        where: 'customer_id = ? AND (is_created_by_me = 1 OR is_created_by_me IS NULL) '
            'AND (is_deleted IS NULL OR is_deleted = 0)',
        whereArgs: [customerId]);
    }
  } catch (_) {}
  await _rebuildCustomerBalances(customerId);
  await _applyCustomerVisibility(customerId);
  _customerUpdatedController.add(syncUuid);
}
```

**`_handleOwnCustomerDoc`** — مستند عميل آخر كاتب له أنا:

```dart
Future<void> _handleOwnCustomerDoc(String syncUuid, Map<String, dynamic> data) async {
  final db = await _db.database;
  final rows = await db.query('customers',
      columns: ['id', 'tombstoned'], where: 'sync_uuid = ?', whereArgs: [syncUuid], limit: 1);
  final isTomb = data['isDeleted'] == true || data['is_deleted'] == 1;
  if (rows.isNotEmpty) {
    // شاهد حذف كتبه جهاز آخر ثم دُمج رفعي أنا فوقه
    if (isTomb && ((rows.first['tombstoned'] as int?) ?? 0) == 0) {
      await _applyCustomerTombstone(syncUuid, SyncValidation.sanitizeMap(data));
    }
    return;
  }
  // عميلي أنا مفقود محلياً: قاعدة استُعيدت من نسخة قديمة
  final name = SyncValidation.sanitizeString(data['name']?.toString() ?? '').trim();
  if (name.isEmpty || isTomb) return;
  final id = await _insertReceivedCustomer(db, syncUuid, SyncValidation.sanitizeMap(data), name);
  await db.update('customers', {'is_created_by_me': 1}, where: 'id = ?', whereArgs: [id]);
  await _coordinator!.registerOperation(entityType: 'customer', syncUuid: syncUuid, source: SyncSource.firebase);
  await _coordinator!.markFirebaseSynced('customer', syncUuid);
  await _processOrphans(id, syncUuid);
}
```

**`_handleOwnTxDoc`** — مستند معاملة آخر كاتب له أنا. ثلاث حالات:
1. **شاهد حذف دُمج في مستندي** (حذف عميل على جهاز آخر) ومعاملتي نشطة → أبطلها (`is_deleted=1`, `is_uploaded=1`)، ثم أعد بناء الرصيد والظهور. الحذف نهائي.
2. **وضع الاستعادة وصف ما زال من النسخة (`restored_mark = 1`)**: إن كان `lastModifiedAt` في المستند أحدث من `last_uploaded_at` المحلي، فما رفعتُه بعد أخذ النسخة يلغي ما فيها → انسخ المبلغ والنوع والملاحظة من المستند.
3. **معاملتي مفقودة محلياً** (نسخة قديمة) → أدرجها كمعاملة **أملكها** (`is_created_by_me = 1`، `origin_device_id = جهازي`). إن كان عميلها غير موجود → يتيمة. إن كانت معاملة فاتورة وفاتورتها موجودة → تجاهل (الحزمة هي المرجع).

(انسخ الدالة كاملة من الملف؛ طولها ~85 سطراً.)

**مساعدات صغيرة:**

```dart
Future<void> _applyCustomerVisibility(int customerId) async {
  try {
    final db = await _db.database;
    await CustomerVisibility.apply(db, customerId);
  } catch (e) { print('⚠️ _applyCustomerVisibility: $e'); }
}

Future<void> _rebuildCustomerBalances(int customerId) async {
  try {
    final dbService = DatabaseService();
    await dbService.recalculateCustomerTransactionBalances(customerId);
    await dbService.recalculateAndApplyCustomerDebt(customerId);
  } catch (e) {
    await _verifyAndRepairCustomerBalance(customerId);
  }
}

/// وقت الخادم (uploadedAt) بالملّي ثانية — إصدار المستند.
int? _serverMillis(dynamic v) {
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is DateTime) return v.millisecondsSinceEpoch;
  if (v is String) return DateTime.tryParse(v)?.millisecondsSinceEpoch;
  return null;
}

Future<void> _sendAckFor(String syncUuid, Map<String, dynamic> data) async {
  final senderDeviceId = data['originDeviceId'] as String? ?? data['deviceId'] as String?;
  if (senderDeviceId != null && senderDeviceId != _deviceId) {
    await _ackService?.sendAck(transactionUuid: syncUuid, senderDeviceId: senderDeviceId);
  }
}
```

### 7.8 استقبال معاملة `_applyTransactionChange` (إعادة كتابة)

الخطوات بالترتيب:

**(1) التوقيع:** `if (!await _verifyIncomingSignature(syncUuid, data)) return;`

**(2) «رفض المعاملات القديمة» صار تنبيهاً فقط:**
**المشكلة (سيناريو 10):** جهاز غاب 40 يوماً والإعداد مفعّل على 30 يوماً: يرفض كل معاملة رُفعت قبل 40 يوماً → رصيده ناقص للأبد. والتكرار أصلاً مستحيل بفضل المعرّف الفريد، فالرفض لا يحمي من شيء.
**التعديل:** أبقِ الفحص لكن سجّل تحذيراً في `SyncDiagnostics` ولا تُرجع.

**(3) لا سياسة تعارض هنا:** احذف كتلة «إعادة التنشيط الذكي / رفض معاملة لعميل محذوف». الظهور صار دالة `CustomerVisibility`.

**(4) معاملة فاتورة نشطة ← حزمة الفاتورة هي المرجع:**
**المشكلة (سيناريو 18):** فاتورة دين 5000 حُفظت أوفلاين (فرُفعت معاملتها في مجموعة `transactions`)، ثم حُوّلت لنقد. نسخة المعاملة القديمة في `transactions` كانت تعيد الدين الوهمي (5000) عند كل سحب كامل أو إعادة تشغيل.

```dart
final incomingInvUuid = (data['invoiceSyncUuid'] ?? data['invoice_sync_uuid'])?.toString();
if (!isTxDeleted && incomingInvUuid != null && incomingInvUuid.isNotEmpty) {
  final inv = await db.query('invoices',
      columns: ['id'], where: 'invoice_uuid = ?', whereArgs: [incomingInvUuid], limit: 1);
  if (inv.isNotEmpty) return;
}
```

**(5) الإصدار:**
**المشكلة (الفوضى):** السحب الكامل أو التدقيق يقرأ لقطة، ثم يطبّقها بعد ثوانٍ، وقد وصلت في الأثناء نسخة أحدث عبر المستمع → كان يكتب الرقم القديم فوق الجديد.

```dart
final int? incomingVer = _serverMillis(data['uploadedAt']);
final String? incomingModified = data['lastModifiedAt']?.toString();
```

**(6) المعاملة موجودة محلياً:**

```dart
final localVer = (existingTx['remote_ver'] as num?)?.toInt();
if (incomingVer != null && localVer != null && incomingVer < localVer) {
  return; // نسخة أقدم مما طُبّق
}
if (incomingVer != null && (localVer == null || incomingVer > localVer)) {
  // نسجّل أحدث إصدار رأيناه حتى لو تطابق المحتوى، وإلا تسللت نسخة أقدم بعده
  await db.update('transactions',
      {'remote_ver': incomingVer, 'remote_modified_at': incomingModified},
      where: 'id = ?', whereArgs: [txId]);
}

final isMine = (existingTx['is_created_by_me'] as int?) != 0;
final localDeleted = ((existingTx['is_deleted'] as int?) ?? 0) == 1;

if (isMine) {
  // صاحب المعاملة: لا يقبل من غيره إلا شاهد الحذف
  if (isTxDeleted && !localDeleted) {
    await db.update('transactions', {'is_deleted': 1, 'is_uploaded': 1},
        where: 'id = ?', whereArgs: [txId]);
    await _rebuildCustomerBalances(existingCustomerId);
    await _applyCustomerVisibility(existingCustomerId);
    await _sendAckFor(syncUuid, data);
  } else if (!isTxDeleted && !localDeleted && (currentAmount - amountChanged).abs() > 0.01) {
    // نسخة مختلفة في السحابة (إعادة بث قديمة): أعد رفع نسختي لتصحيحها
    await db.update('transactions', {'is_uploaded': 0}, where: 'id = ?', whereArgs: [txId]);
  }
  return;
}

// الحذف نهائي: لا نُحيي معاملة محذوفة بمستند نشط
if (localDeleted) return;

final needsUpdate = (currentAmount - amountChanged).abs() > 0.01 ||
    currentType != transactionType || currentNote != transactionNote || isTxDeleted;
if (!needsUpdate) return;

// تحقق مطابقة العميل (sync_uuid) ثم تحديث مباشر للصف:
await db.update('transactions', {
  'amount_changed': amountChanged,
  'transaction_note': transactionNote,
  'transaction_type': transactionType,
  'description': data['description'],
  'transaction_date': transactionDate ?? existingTx['transaction_date'],
  'is_deleted': isTxDeleted ? 1 : 0,
  'is_uploaded': 1,
}, where: 'id = ?', whereArgs: [txId]);
await _rebuildCustomerBalances(existingCustomerId);
await _applyCustomerVisibility(existingCustomerId);
await _sendAckFor(syncUuid, data);
```

> لاحظ: التحديث صار **مباشراً على الصف** ثم إعادة بناء الأرصدة، بدل المرور عبر `updateManualTransaction` (التي ترفض معاملات الفواتير وتُعيد الوسم).

**(7) معاملة جديدة:** الإدراج كما كان (داخل معاملة SQLite مع فحص المعرّف) مع هذه الحقول الجديدة:

```dart
'new_balance_after_transaction': balanceBefore + (isTxDeleted ? 0.0 : amountChanged),
'invoice_sync_uuid': incomingInvUuid,
// شاهد حذف لمعاملة لم تصلنا نسختها النشطة: تُسجَّل محذوفة (فلا تُحييها نسخة أقدم لاحقاً)
'is_deleted': isTxDeleted ? 1 : 0,
'origin_device_id': data['originDeviceId'] ?? data['deviceId'],
'remote_ver': incomingVer,
'remote_modified_at': incomingModified,
```

ثم `_applyCustomerVisibility`، ثم `_sendAckFor`. **واحذف** استدعاء `_verdictService.applyPendingVerdictsFor(...)` (القسم 12).

### 7.8.ب الكتابة فوق صف قُرئ قبل لحظة: مشروطة (اكتُشف باختبار الكود الحقيقي)

**المشكلة:** `_applyTransactionChange` تقرأ الصف (نشطاً)، ثم تنتظر عمليات أخرى، ثم تكتب التحديث الوارد بـ `where: 'id = ?'` ومعه `is_deleted: isTxDeleted ? 1 : 0` و`is_uploaded: 1`. إن حذف المستخدم العميل على هذا الجهاز **بين القراءة والكتابة**، تكتب فوق الحذف: **تُحيي المعاملة، وتعلّم شاهد حذفها «مرفوعاً» قبل رفعه** — فيضيع الحذف من كل الأجهزة (مثال فعلي: بقي 250 ديناً على عميل حُذف).

**التعديل:** لا تكتب `is_deleted = 0` أبداً، واشترط أن الصف ما زال نشطاً:

```dart
final updated = await db.update('transactions', {
  'amount_changed': amountChanged,
  'transaction_note': transactionNote,
  'transaction_type': transactionType,
  'description': data['description'],
  'transaction_date': transactionDate ?? existingTx['transaction_date'],
  if (isTxDeleted) 'is_deleted': 1,
  'is_uploaded': 1,
}, where: 'id = ? AND (is_deleted IS NULL OR is_deleted = 0)', whereArgs: [txId]);
if (updated == 0) return; // حُذفت هنا أثناء المعالجة
```

ونفس الشرط في كل «أخذ» لنسخة مستند فوق صف محلي (القسم 7.16.ب): فرع المالك (`... AND is_uploaded = 1`)، واسترداد ملكية معاملتي، والأخذ في `_handleOwnTxDoc` (`... AND restored_mark = 1` لصف مستعاد، وإلا `... AND is_uploaded = 1`).

> **درس عام:** كل «اقرأ ثم اكتب» حول `await` هو سباق. الكتابة يجب أن تحمل شرط الحالة التي قُرئت (CAS)، خاصة كل ما يمسّ `is_deleted` و`is_uploaded`.

### 7.9 دمج العملاء المكررين بالاسم `mergeDuplicateCustomersByName`

**المشكلة (سيناريو 13):** الدمج المحلي كان ينقل معاملات هوية إلى هوية أخرى **على هذا الجهاز وحده**، فتختلف أرصدة كل عميل بين الأجهزة.

**التعديل:** داخل حلقة المجموعات: لا ندمج هويتين مزامنتين مختلفتين أبداً. ندمج فقط السجلات القديمة التي لا هوية لها، في سجل واحد (ذي هوية إن وُجد)، والسجل ذو الهوية هو الأساس دائماً:

```dart
final withId = entry.value.where((c) => (c['sync_uuid'] as String? ?? '').isNotEmpty).toList();
final legacy = entry.value.where((c) => (c['sync_uuid'] as String? ?? '').isEmpty).toList();
if (legacy.isEmpty) continue;
final list = <Map<String, dynamic>>[...legacy, if (withId.isNotEmpty) withId.first];
if (list.length <= 1) continue;
list.sort((a, b) {
  final aHasId = (a['sync_uuid'] as String? ?? '').isNotEmpty ? 1 : 0;
  final bHasId = (b['sync_uuid'] as String? ?? '').isNotEmpty ? 1 : 0;
  if (aHasId != bHasId) return bHasId.compareTo(aHasId);
  // ... باقي معايير الترتيب كما كانت
});
```

### 7.10 رفع عميل `uploadCustomer` (إعادة كتابة)

**المشاكل:**
- القفل كان يُفحص، ثم انتظار (await)، ثم يُؤخذ → رفعان متوازيان.
- كان يرفع البيانات الممرَّرة (لقطة قديمة من طابور الإعادة أو WAL) لا الصف الحالي.
- أي جهاز كان يرفع وثيقة عميل لا يملكه (مثلاً عند فاتورة لعميل جهاز آخر) فيسرق `deviceId` ويُفقد المنشئ ملكيته (سيناريو 37).
- كان يكتب `isDeleted: false` في كل رفع عادي، فيمحو (بـ merge) شاهد حذف كتبه جهاز آخر في نفس اللحظة.
- أوفلاين: كان ينتظر مهلة 60 ثانية وهو يحبس القفل.
- كان يكتب `groupSecret` (السرّ نصاً) في الوثيقة.

**التعديل (الهيكل):**

```dart
Future<bool> uploadCustomer(Map<String, dynamic> customerData) async {
  if (!_isInitialized || _groupId == null) return true;
  if (_status == FirebaseSyncStatus.offline) return false; // لا ننتظر مهلة ونحن أوفلاين
  if (_recoveryMode) return false;
  final syncUuid = customerData['sync_uuid'] as String?;
  if (syncUuid == null || syncUuid.isEmpty) return true;
  if (!SyncSecurity.isValidDocumentId(syncUuid)) return true;

  // القفل قبل أي await
  final lockKey = 'customer_$syncUuid';
  if (_uploadLocks[lockKey] == true) return true;
  _uploadLocks[lockKey] = true;
  try {
    // قراءة حديثة
    final db = await _db.database;
    final fresh = await db.query('customers', where: 'sync_uuid = ?', whereArgs: [syncUuid], limit: 1);
    if (fresh.isEmpty) return true;
    final row = Map<String, dynamic>.from(fresh.first);
    if (!_validateCustomerData(row)) return true;

    final tomb = (row['tombstoned'] as int?) ?? 0;
    final pendingTomb = tomb == 2 || tomb == 3;
    final isMine = (row['is_created_by_me'] as int?) != 0;
    // وثيقة العميل يرفعها منشئه وحده؛ الاستثناء: شاهد حذف أو تنشيط قام بهما هذا الجهاز
    if (!isMine && !pendingTomb) return true;

    if (!pendingTomb && await _coordinator!.isFirebaseSynced('customer', syncUuid)) {
      // كما كان: لا رفع إن لم يتغير منذ آخر مزامنة (last_modified_at <= synced_at)
    }
    if (!_rateLimiter.canProceed()) return false;
    _rateLimiter.recordOperation();
    // WAL كما كان (بالصف الحديث)

    final isDeleted = tomb == 2 || ((row['is_deleted'] as int?) ?? 0) == 1;
    final doc = <String, dynamic>{
      'syncUuid': syncUuid, 'name': row['name'], 'phone': row['phone'],
      'currentTotalDebt': isDeleted ? 0.0 : row['current_total_debt'],
      // ... expected*، generalNote، address، createdAt، lastModifiedAt، audioNotePath
      'deviceId': _deviceId, 'originDeviceId': _deviceId,
      'checksum': checksum, 'uploadedAt': FieldValue.serverTimestamp(),
      // لا groupSecret
    };
    // isDeleted يُكتب فقط عند حذف أو إعادة تنشيط صريحين
    if (tomb == 2) {
      doc['isDeleted'] = true; doc['is_deleted'] = 1;
      doc['deletedAt'] = DateTime.now().toIso8601String();
    } else if (tomb == 3) {
      doc['isDeleted'] = false; doc['is_deleted'] = 0;
    }
    doc['signature'] = _signDoc(syncUuid, doc, isCustomer: true);
    await _firestore!.collection('customers').doc(syncUuid)
        .set(doc, SetOptions(merge: true)).timeout(const Duration(seconds: 60));

    // المنسق + synced_at كما كان، ثم تقدّم حالة الشاهد:
    if (tomb == 2) {
      await db.update('customers', {'tombstoned': 1},
          where: 'sync_uuid = ? AND tombstoned = 2', whereArgs: [syncUuid]);
    } else if (tomb == 3) {
      await db.update('customers', {'tombstoned': 0},
          where: 'sync_uuid = ? AND tombstoned = 3', whereArgs: [syncUuid]);
    }
    return true;
  } catch (e) {
    // WAL failed + طابور الإعادة (بالصف الحديث) كما كان
    return false;
  } finally {
    _uploadLocks.remove(lockKey);
  }
}
```

### 7.11 رفع معاملة `uploadTransaction` (إعادة كتابة)

**المشاكل:**
- **سيناريو 09:** تعديل معاملة أوفلاين بعد إنشائها أوفلاين: طابور الإعادة يحمل لقطة الإنشاء (1000)، فيرفعها فوق التعديل (250) ويعلّم الصف «مرفوعاً» → السحابة 1000 وكل الأجهزة 1000، والجهاز المنشئ 250.
- القفل غير ذري.
- تعليم «مرفوعة» حتى لو عُدّلت أثناء الرفع.
- المحجوب بحد المعدل = «نجاح».
- `isDeleted: false` في كل رفع → تعديلٌ يُرفع بعد شاهد حذف «يُحيي» المعاملة.
- معاملات الفواتير كانت تُرفع في `transactions` أيضاً → نسخ قديمة تعيد ديوناً وهمية (سيناريو 18).
- لم يكن يسمح برفع شاهد حذف لمعاملة جهاز آخر (مطلوب عند حذف العميل).

**التعديل:**

```dart
/// بصمة الحقول المالية لمعاملة — للمقارنة قبل الرفع وبعده (CAS).
String _txFingerprint(Map<String, dynamic> t) =>
    '${(t['amount_changed'] as num?)?.toDouble()}|${t['transaction_type']}|'
    '${t['is_deleted'] ?? 0}|${t['customer_id']}|${t['transaction_note']}|${t['invoice_sync_uuid']}';

Future<bool> uploadTransaction(Map<String, dynamic> txData, String customerSyncUuid,
    {bool force = false}) async {
  if (!_isInitialized || _groupId == null) return true;
  if (_status == FirebaseSyncStatus.offline) return false;
  if (_recoveryMode) return false;
  final syncUuid = (txData['transaction_uuid'] as String?) ?? '';
  if (syncUuid.isEmpty || !SyncSecurity.isValidDocumentId(syncUuid)) return true;

  final lockKey = 'transaction_$syncUuid';
  if (_uploadLocks[lockKey] == true) return true;
  _uploadLocks[lockKey] = true;
  try {
    final db = await _db.database;
    // قراءة حديثة + معرّف العميل الحالي
    final rows = await db.rawQuery(
      'SELECT t.*, c.sync_uuid AS _customer_sync_uuid FROM transactions t '
      'LEFT JOIN customers c ON c.id = t.customer_id WHERE t.transaction_uuid = ? LIMIT 1',
      [syncUuid]);
    if (rows.isEmpty) return true;
    final tx = Map<String, dynamic>.from(rows.first);
    final cs = tx.remove('_customer_sync_uuid') as String?;
    final custUuid = (cs != null && cs.isNotEmpty) ? cs : customerSyncUuid;

    final isMine = (tx['is_created_by_me'] as int?) != 0; // NULL = قديم = من هذا الجهاز
    final isTxDeleted = ((tx['is_deleted'] as int?) ?? 0) == 1;
    if (!isMine && !isTxDeleted) return true;     // معاملة غيري: فقط شاهد حذفها
    if (!force && (tx['is_uploaded'] as int?) == 1) return true;
    final invUuid = tx['invoice_sync_uuid'] as String?;
    if (!isTxDeleted && invUuid != null && invUuid.isNotEmpty) return true; // قناة الحزمة
    if (!_validateTransactionData(tx)) return true;
    if (!_rateLimiter.canProceed()) return false;
    _rateLimiter.recordOperation();
    // WAL كما كان

    final sentFingerprint = _txFingerprint(tx);
    final nowIso = DateTime.now().toIso8601String();
    final doc = <String, dynamic>{
      'syncUuid': syncUuid, 'customerSyncUuid': custUuid,
      'invoiceSyncUuid': tx['invoice_sync_uuid'],
      'transactionDate': tx['transaction_date'], 'amountChanged': tx['amount_changed'],
      'balanceBeforeTransaction': tx['balance_before_transaction'],
      'newBalanceAfterTransaction': tx['new_balance_after_transaction'],
      'transactionNote': tx['transaction_note'], 'transactionType': tx['transaction_type'],
      'description': tx['description'], 'createdAt': tx['created_at'],
      'lastModifiedAt': nowIso, 'audioNotePath': tx['audio_note_path'],
      'deviceId': _deviceId,
      'originDeviceId': isMine ? _deviceId : (tx['origin_device_id'] ?? _deviceId),
      'checksum': _calculateChecksum(tx),
      'uploadedAt': FieldValue.serverTimestamp(),
    };
    // لا نكتب isDeleted=false أبداً: الحذف نهائي
    if (isTxDeleted) { doc['isDeleted'] = true; doc['is_deleted'] = 1; }
    doc['signature'] = _signDoc(syncUuid, doc);

    await _firestore!.collection('transactions').doc(syncUuid)
        .set(doc, SetOptions(merge: true)).timeout(const Duration(seconds: 60));
    // المنسق كما كان

    // CAS: «مرفوعة» فقط إن لم تتغير المعاملة أثناء الرفع
    final cur = await db.query('transactions', where: 'transaction_uuid = ?', whereArgs: [syncUuid], limit: 1);
    if (cur.isNotEmpty) {
      if (_txFingerprint(cur.first) == sentFingerprint) {
        await db.update('transactions', {'is_uploaded': 1, 'last_uploaded_at': nowIso},
            where: 'transaction_uuid = ?', whereArgs: [syncUuid]);
      } else {
        await db.update('transactions', {'is_uploaded': 0},
            where: 'transaction_uuid = ?', whereArgs: [syncUuid]);
      }
    }
    return true;
  } catch (e) {
    // WAL failed + طابور الإعادة بالصف الحديث
    return false;
  } finally {
    _uploadLocks.remove(lockKey);
  }
}
```

### 7.12 مسار رفع واحد لكل «معلّق أملكه»

**المشكلة (سيناريوهات 04، 05، 32، 33):** مسارات الرفع كانت ثلاثة مختلفة الشروط: المراقب (Watchdog) يرفع فقط ما لم يُسجَّل في المنسق (فأي معاملة رُفعت مرة لا يُرفع تعديلها أبداً)، و`_syncPendingChanges` يرفع معاملات «عملاء أنشأتُهم» فقط، و`syncCustomerNow` يعود فوراً لعملاء الأجهزة الأخرى. النتيجة: تعديل معاملة على عميل أنشأه جهاز آخر **لا يُرفع أبداً**.

**التعديل:** شرط SQL واحد يستخدمه الجميع:

```dart
/// أملكها ولم تُرفع (بما فيها المحذوفة = شاهد حذف)، أو معاملة غيري أبطلها حذفي أنا للعميل.
/// معاملات الفواتير النشطة مستثناة: تسافر داخل حزمة الفاتورة.
static const String _ownedPendingWhere =
    "t.transaction_uuid IS NOT NULL AND t.transaction_uuid != '' "
    "AND (t.is_uploaded = 0 OR t.is_uploaded IS NULL) "
    "AND ((t.is_created_by_me = 1 OR t.is_created_by_me IS NULL) "
    "     OR (t.is_created_by_me = 0 AND t.is_deleted = 1)) "
    "AND (t.invoice_sync_uuid IS NULL OR t.invoice_sync_uuid = '' OR t.is_deleted = 1)";

Future<int> uploadAllOwnedPending({int? limit}) => _uploadAllOwnedPending(limit: limit);

Future<int> _uploadAllOwnedPending({int? limit}) async {
  if (!_isInitialized || _groupId == null || _recoveryMode) return 0;
  if (_status == FirebaseSyncStatus.offline) return 0;
  final db = await _db.database;
  final rows = await db.rawQuery('''
    SELECT t.*, c.sync_uuid AS customer_sync_uuid
    FROM transactions t JOIN customers c ON c.id = t.customer_id
    WHERE c.sync_uuid IS NOT NULL AND c.sync_uuid != '' AND $_ownedPendingWhere
    ORDER BY t.transaction_date ASC, t.id ASC
    ${limit != null ? 'LIMIT $limit' : ''}
  ''');
  int ok = 0;
  for (final r in rows) {
    try {
      if (await uploadTransaction(Map<String, dynamic>.from(r), r['customer_sync_uuid'] as String)) ok++;
    } catch (_) {}
  }
  return ok;
}

/// رفع حذف عميل فوراً: شاهد العميل + شاهد لكل معاملة كانت معروفة هنا.
Future<void> syncCustomerDeletionNow(int customerId) async {
  if (!_isInitialized || _groupId == null) return;
  try {
    final db = await _db.database;
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [customerId], limit: 1);
    if (rows.isEmpty) return;
    final c = rows.first;
    final cs = c['sync_uuid'] as String?;
    if (cs == null || cs.isEmpty) return;
    await uploadCustomer(c);
    final pend = await db.rawQuery(
      'SELECT t.* FROM transactions t WHERE t.customer_id = ? AND $_ownedPendingWhere', [customerId]);
    for (final t in pend) {
      await uploadTransaction(Map<String, dynamic>.from(t), cs);
    }
  } catch (e) {
    print('⚠️ رفع حذف العميل $customerId: $e (ستتكفل به المزامنة الخلفية)');
  }
}
```

### 7.13 `syncCustomerNow` (الرفع الفوري لعميل)

**التعديل:** لعميل أنشأه جهاز آخر لا نرفع وثيقته، لكن نرفع معاملاتي المعلّقة عليه:

```dart
final rows = await db.query('customers', where: 'id = ?', whereArgs: [customerId], limit: 1);
if (rows.isEmpty) return;
final customer = rows.first;
final customerSyncUuid = customer['sync_uuid'] as String?;
if (customerSyncUuid == null || customerSyncUuid.isEmpty) return;

final isMine = (customer['is_created_by_me'] as int?) != 0;
final tomb = (customer['tombstoned'] as int?) ?? 0;
final isDeleted = ((customer['is_deleted'] as int?) ?? 0) == 1;
if ((isMine && !isDeleted) || tomb == 2 || tomb == 3) {
  final customerOk = await uploadCustomer(customer);
  if (!customerOk) return;
}
final pendingTx = await db.rawQuery(
  'SELECT t.* FROM transactions t WHERE t.customer_id = ? AND $_ownedPendingWhere '
  'ORDER BY t.transaction_date ASC, t.id ASC', [customerId]);
for (final tx in pendingTx) {
  await uploadTransaction(Map<String, dynamic>.from(tx), customerSyncUuid);
}
```

### 7.14 `_syncPendingChanges`

```dart
if (!_isInitialized || _groupId == null) return;
if (_recoveryMode) return;

// وثائق العملاء: ما أنشأه هذا الجهاز وتغيّر، + كل شاهد حذف/تنشيط محلي بانتظار الرفع
final customers = await db.query('customers',
  where: "sync_uuid IS NOT NULL AND sync_uuid != '' AND ("
         "  ((is_deleted IS NULL OR is_deleted = 0) "
         "   AND (synced_at IS NULL OR last_modified_at > synced_at) "
         "   AND (is_created_by_me = 1 OR is_created_by_me IS NULL)) "
         "  OR tombstoned IN (2, 3))",
  orderBy: 'id ASC');
for (final customer in customers) {
  try { await uploadCustomer(customer); } catch (_) {}
}
// ثم كل المعاملات المعلّقة التي أملكها (بغض النظر عن منشئ العميل)
await _uploadAllOwnedPending();
// ثم الفواتير والمنتجات كما كان
```

> لاحظ: لم تعد المعاملات مشروطة بنجاح رفع عميلها. معاملة تصل قبل عميلها يحفظها المستقبِل «يتيمة» ثم يطبقها عند وصول العميل.

### 7.15 `verifyDataIntegrity` (عدّ المستندات)

**المشكلة:** `where('isDeleted', isNotEqualTo: true)` في Firestore **يستبعد الوثائق التي لا تحمل الحقل أصلاً**. والوثائق الحية لم تعد تكتب `isDeleted: false` (القاعدة 4) → كان العدّ يُسقطها كلها.

**التعديل:** الكل − شواهد الحذف:

```dart
final remoteCustomersAll = await _firestore!.collection('customers').count().get();
final remoteCustomersDel = await _firestore!.collection('customers')
    .where('isDeleted', isEqualTo: true).count().get();
final remoteCustomerCount = (remoteCustomersAll.count ?? 0) - (remoteCustomersDel.count ?? 0);
// ونفس الشيء لـ transactions
```

> **قاعدة عامة لأي مشروع:** بعد تطبيق القاعدة 4، ابحث في كل الكود عن `isNotEqualTo: true` و`isEqualTo: false` على `isDeleted` واستبدلها بـ «الكل ناقص `isEqualTo: true`» أو فلترة في الذاكرة.

### 7.16 التمهيد (جهاز جديد / جهاز مستعيد)

**`ensureNewDeviceBootstrap`:**

**المشاكل:**
- **سيناريو 27:** الشرط كان «دفتر غير فارغ ⇒ لست جديداً». جهاز جديد عليه معاملة محلية واحدة (استُخدم أوفلاين قبل تفعيل المزامنة) لا يطلب شيئاً، ولا يحصل أبداً على تاريخ نظّفه SmartPipe من السحابة.
- **سيناريو 26:** جهاز استعاد نسخة قديمة لم يكن يُكتشف أصلاً.
- تُستدعى أثناء التهيئة قبل اكتمالها، و`performFullSync` يشترط الاكتمال.

**التعديل (الفروق):**

```dart
Future<void> ensureNewDeviceBootstrap() async {
  if (_firestore == null || _deviceId == null || _groupId == null) return;
  if (_bootstrapping) return;
  _bootstrapping = true;
  try {
    // ننتظر اكتمال التهيئة (حتى 3 دقائق)
    for (var i = 0; i < 180 && !_isInitialized; i++) {
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!_isInitialized) return;
    final selfRef = _firestore!.collection('devices').doc(_deviceId);
    final selfDoc = await selfRef.get().timeout(const Duration(seconds: 20));
    if (selfDoc.data()?['bootstrapCompletedAt'] != null && !_recoveryMode) return;
    // ❌ احذف شرط «عدد المعاملات > 0 ⇒ لست جديداً»

    final devices = await _firestore!.collection('devices').get().timeout(const Duration(seconds: 20));
    final others = devices.docs.where((d) => d.id != _deviceId).length;
    if (others == 0) {
      if (_recoveryMode) await performFullSync();
      await _markBootstrapComplete(selfRef);
      return;
    }
    // اكتب طلب bootstrap_requests/{deviceId} بحالة pending (بلا groupSecret)
    // انتظر حتى ready/failed (10 دقائق)، مع try/catch حول كل قراءة
    if (status != 'ready') {
      if (_recoveryMode) {
        // نكمل الاستعادة من السحابة وحدها ثم نفك حظر الرفع
        await performFullSync();
        await _markBootstrapComplete(selfRef);
        return;
      }
      return; // يبقى الطلب معلَّقاً
    }
    await performFullSync();
    await _markBootstrapComplete(selfRef);
    try { await reqRef.delete(); } catch (_) {}
  } catch (e) {
    print('⚠️ [Bootstrap] فشل التمهيد: $e (يُعاد في الدورة الخلفية)');
  } finally {
    _bootstrapping = false;
  }
}
```

**`_serveBootstrapRequest`:** إصلاح نوع: `final data = snap.data() as Map<String, dynamic>?;`

**`rebroadcastEverything`** (يشغّله الجهاز المُجيب):

**المشاكل:**
- كان يرفع بالقوة فوق مستندات موجودة، فقد يُرجع نسخة أحدث إلى أقدم.
- كان يستخدم `_forceUploadTransaction` الذي يرفض معاملات الأجهزة الأخرى، فلا يستلم الجهاز الجديد بعد التنظيف إلا جزءاً من الدفتر.
- كان يضع `deviceId = المُجيب` فيسرق الملكية.
- الفواتير: كان يعيد تعليم كل الفواتير «غير مرفوعة» ويعيد رفعها.

**التعديل:** كتابة المستند **الغائب فقط** داخل معاملة Firestore، لكل المعاملات النشطة (غير الفواتير)، بمالكها الأصلي:

```dart
Future<bool> createIfAbsent(String coll, String id, Map<String, dynamic> data) async {
  final ref = _firestore!.collection(coll).doc(id);
  return await _firestore!.runTransaction<bool>((txn) async {
    final snap = await txn.get(ref);
    if (snap.exists) return false;
    txn.set(ref, data);
    return true;
  }).timeout(const Duration(seconds: 30));
}

// العملاء النشطون:
final mine = (c['is_created_by_me'] as int?) != 0;
final doc = {
  'syncUuid': uuid, 'name': c['name'], 'phone': c['phone'],
  'generalNote': c['general_note'], 'address': c['address'],
  'createdAt': c['created_at'], 'lastModifiedAt': c['last_modified_at'],
  'deviceId': mine ? _deviceId : 'rebroadcast',
  'originDeviceId': mine ? _deviceId : 'rebroadcast',
  'uploadedAt': FieldValue.serverTimestamp(),
};
doc['signature'] = _signDoc(uuid, doc, isCustomer: true);
await createIfAbsent('customers', uuid, doc);

// المعاملات النشطة غير المرتبطة بفواتير (JOIN مع customers لجلب sync_uuid):
final mine = (t['is_created_by_me'] as int?) != 0;
final owner = mine ? _deviceId : ((t['origin_device_id'] as String?) ?? 'rebroadcast');
final doc = {
  'syncUuid': uuid, 'customerSyncUuid': t['customer_sync_uuid'],
  'transactionDate': t['transaction_date'], 'amountChanged': t['amount_changed'],
  'transactionNote': t['transaction_note'], 'transactionType': t['transaction_type'],
  'description': t['description'], 'createdAt': t['created_at'],
  'lastModifiedAt': (mine ? t['last_uploaded_at'] : t['remote_modified_at']) ?? t['created_at'],
  'deviceId': owner, 'originDeviceId': owner,
  'uploadedAt': FieldValue.serverTimestamp(),
};
doc['signature'] = _signDoc(uuid, doc);
await createIfAbsent('transactions', uuid, doc);

// الفواتير: الغائبة فقط، كلها (القسم 8.2)
invOk = await InvoiceSyncService().rebroadcastMissingInvoices();
```

**`registerDevice`:** استبدل `'groupSecret': _groupSecret` بـ `'secretFingerprint': _secretFingerprint()`.

### 7.16.ب لا تنتهي الاستعادة على تنزيل فاشل، والمالك لا يفرض نسخة أقدم (اكتُشف باختبار الكود الحقيقي)

**المشكلة 1 — نهاية مبكرة للاستعادة:** في `ensureNewDeviceBootstrap` كانت نتيجة `performFullSync()` تُهمل في المواضع الثلاثة (أول جهاز، لا مستجيب، المستجيب جاهز). وهي تعيد `false` بلا إنترنت، أو إن كانت مزامنة أخرى جارية (`_isSyncing`)، أو إن فشل سحب المعاملات. وتنزيل الفواتير داخلها كان يبتلع أخطاءه. النتيجة: **تنتهي الاستعادة وبيانات الجهاز ما زالت بيانات النسخة الاحتياطية القديمة**، فيُمحى `restored_mark`، ثم يعتبرها الجهاز «نسختي المرجعية» ويرفعها فوق التعديلات الأحدث عند كل الأجهزة (مثال فعلي: تعديل 300- رجع إلى 100- على عشرة أجهزة).

**التعديل:**

```dart
/// تنزيل كامل يُبنى عليه إنهاء التمهيد/الاستعادة: نجاح حقيقي أو لا إنهاء.
Future<bool> _downloadForBootstrap() async {
  final ok = await performFullSync();
  if (!ok) print('⚠️ [Bootstrap] التنزيل الكامل لم يكتمل — لا إنهاء للتمهيد الآن');
  return ok;
}
```

وفي `ensureNewDeviceBootstrap` استبدل كل `await performFullSync();` قبل `_markBootstrapComplete` بـ:

```dart
if (!await _downloadForBootstrap()) return;   // تعيد الدورة الخلفية المحاولة
await _markBootstrapComplete(selfRef);
```

وفي `_downloadAllData`:
- قراءة العملاء والمعاملات من **الخادم**: `.get(const GetOptions(source: Source.server))`. على الجوال (persistence مفعّلة) كان `get()` بلا إنترنت يعيد نسخة الذاكرة المحلية «بنجاح».
- تنزيل الفواتير **لا يبتلع** فشل الشبكة:

```dart
await InvoiceSyncService().downloadAllInvoices(rethrowErrors: true, onProgress: ...);
try { await ProductSyncService().downloadAllProducts(); } catch (e) { ... } // المنتجات كما كانت
```

وفي `InvoiceSyncService.downloadAllInvoices`: معامل `bool rethrowErrors = false`، والقراءة من الخادم، وكل وثيقة داخل `try/catch` خاص بها (وثيقة تالفة لا تُسقط البقية)، و`if (rethrowErrors) rethrow;` في `catch` الخارجي.

**المشكلة 2 — المالك يفرض نسخته القديمة:** إن انتهت الاستعادة مبكراً لأي سبب (أو استُعيدت قاعدة في إصدار قديم من التطبيق)، يصل للمالك مستند معاملته بتعديله الأحدث. `_handleOwnTxDoc` كان لا يفعل شيئاً خارج وضع الاستعادة، وفرع المالك في `_applyTransactionChange` كان يعيد رفع نسخته فوقه.

**القاعدة:** وقت التعديل في المستند (`lastModifiedAt`) ووقت آخر رفع محلي (`last_uploaded_at`) **كلاهما من ساعة المالك نفسه** (وإعادة البثّ تحفظ الأول كما هو). إن لم يكن عندي تعديل معلّق (`is_uploaded = 1`)، والمستند أحدث من آخر رفع أعرفه، فهو تعديلي أنا قبل استعادة النسخة: **آخذه**. وإن كان عندي تعديل معلّق فتعديلي بعد الاستعادة هو الأحدث نيةً: أرفعه.

في `_handleOwnTxDoc` صار الشرط:

```dart
final restoredRow = _recoveryMode && ((loc['restored_mark'] as int?) ?? 0) == 1;
final locPending = ((loc['is_uploaded'] as int?) ?? 0) == 0;
final locInv = (loc['invoice_sync_uuid'] as String?) ?? '';          // صف فاتورة: الحزمة مرجعه
final locUpKnown = (loc['last_uploaded_at']?.toString() ?? '').isNotEmpty;
if (!locDeleted && !isDel &&
    (restoredRow || (!locPending && locInv.isEmpty && locUpKnown))) {
  final docMod = data['lastModifiedAt']?.toString() ?? '';
  final locUp = loc['last_uploaded_at']?.toString() ?? '';
  if (docMod.compareTo(locUp) > 0) { /* خذ المبلغ والنوع والملاحظة، last_uploaded_at = docMod */ }
}
```

وفي فرع المالك في `_applyTransactionChange` (حين يختلف المبلغ):

```dart
final locPending = ((existingTx['is_uploaded'] as int?) ?? 0) == 0;
final docMod = incomingModified ?? '';
final locUp = existingTx['last_uploaded_at']?.toString() ?? '';
final locInv = (existingTx['invoice_sync_uuid'] as String?) ?? '';
if (!locPending && locInv.isEmpty && locUp.isNotEmpty && docMod.compareTo(locUp) > 0) {
  // خذ نسخة المستند + أعد حساب الرصيد والظهور
} else {
  // كما كان: is_uploaded = 0 فتُعاد نسختي للرفع
}
```

**المشكلة 3 — معاملتي محفوظة «كمعاملة جهاز آخر»:** كشف مطابقة قديم (القسم 11، القاعدة 15) كان يُدرج معاملة الجهاز نفسه بـ `is_created_by_me = 0` وبمبلغ الكشف القديم. بعدها لا يطبّق أي مسار نسخة السحابة الأحدث عليها. في `_handleOwnTxDoc`، بعد فحص شاهد الحذف مباشرة:

```dart
if (!locDeleted && !isDel && ((loc['is_created_by_me'] as int?) ?? 1) == 0) {
  final inVer = _serverMillis(data['uploadedAt']);
  final locVer = (loc['remote_ver'] as num?)?.toInt();
  if (inVer == null || locVer == null || inVer >= locVer) {
    await db.update('transactions', {
      'amount_changed': (data['amountChanged'] as num?)?.toDouble() ?? loc['amount_changed'],
      'transaction_type': data['transactionType'] ?? loc['transaction_type'],
      'transaction_note': data['transactionNote'] ?? loc['transaction_note'],
      'is_created_by_me': 1, 'origin_device_id': _deviceId, 'is_uploaded': 1,
      'restored_mark': 0, 'remote_ver': inVer,
      'last_uploaded_at': data['lastModifiedAt']?.toString(),
    }, where: 'id = ?', whereArgs: [loc['id']]);
    // ثم إعادة حساب الرصيد والظهور
  }
  return;
}
```

**للاختبار:** `@visibleForTesting bool get debugBootstrapping => _bootstrapping;` — أداة الاختبار لا تفحص جهازاً قبل أن ينهي تمهيده.

**المشكلة 4 — إعادة بثّ بيانات قديمة:** `_serveBootstrapRequest` لم يكن يفحص وضع الاستعادة. جهاز استعاد نسخة احتياطية (ولم تكتمل مقارنته) قد يلبّي طلب جهاز جديد، فيكتب نسخه القديمة في السحابة للمستندات الغائبة، **بوقت خادم جديد**، فتقبلها الأجهزة الأخرى كأنها الأحدث. التعديل في أول الدالة:

```dart
if (_recoveryMode) return; // بياناتي من نسخة احتياطية لم تكتمل مقارنتها
```

وشبكة أمان عند المالك في `_handleOwnTxDoc` (نفس الفرع أعلاه): إن كان في السحابة نسخة من معاملتي **أقدم** من آخر ما رفعتُ ومبلغها مختلف، أعيد رفع نسختي لتصحّحها عند الجميع:

```dart
} else if (!restoredRow && docMod.compareTo(locUp) < 0 &&
    (((data['amountChanged'] as num?)?.toDouble() ?? 0.0) -
            ((loc['amount_changed'] as num?)?.toDouble() ?? 0.0)).abs() > 0.01) {
  await db.update('transactions', {'is_uploaded': 0},
      where: 'id = ?', whereArgs: [loc['id']]);
}
```

> **لماذا لا ترفض الأجهزة الأخرى المحتوى الأقدم بساعة المالك مباشرة؟** جُرِّب ذلك ثم أُلغي عمداً: لو أرجع صاحب المحل تاريخ جهازه للوراء، ستحمل تعديلاته الجديدة وقتاً أقدم، فترفضها كل الأجهزة. أما المقارنة عند المالك وحده فتقارن ساعته بساعته، والتصحيح يمرّ عبر رفع جديد بوقت خادم جديد.

**المشكلة 5 — طلب تمهيد لا يلبّيه أحد إلى الأبد:** المستجيب يحجز الطلب (`pending ← in_progress`) ثم يعيد البثّ. إن أُغلق تطبيقه أثناء ذلك، بقي الطلب `in_progress` إلى الأبد، والمستجيبون لا يستمعون إلا لـ `pending`. وإن كان كل المستجيبين مشغولين لحظة وصول الطلب (`if (_bootstrapResponding) return;`) تخطّوه، ولا حدث جديد يعيدهم إليه. والدورة الخلفية لم تكن تعيد تمهيد **جهاز جديد** (فقط وضع الاستعادة). مثال فعلي: جهاز بقي بلا تاريخ المجموعة المنظَّف طوال التجربة.

**التعديل:**

1. حقل `bool _bootstrapIncomplete = false;`: يصير `true` **قبل** قراءة `selfDoc` (قراءة فاشلة بلا إنترنت عند الإقلاع كانت تُسقط التمهيد حتى التشغيل التالي)، ويُمحى إن قال `selfDoc` إن التمهيد اكتمل، وفي `_markBootstrapComplete`. والدورة الخلفية: `if (_recoveryMode || _bootstrapIncomplete) await ensureNewDeviceBootstrap();`
2. حلقة الانتظار عند الطالب تعيد التنبيه كل دقيقة:

```dart
var lastNudge = DateTime.now();
while (DateTime.now().isBefore(deadline)) {
  await Future.delayed(const Duration(seconds: 10));
  Map<String, dynamic>? req;
  try {
    final snap = await reqRef.get();
    req = snap.data();
    status = (req?['status'] as String?) ?? 'pending';
  } catch (_) {}
  if (status == 'ready' || status == 'failed') break;
  final now = DateTime.now();
  if (now.difference(lastNudge) >= const Duration(seconds: 60)) {
    final beat = req?['respondingAt'];
    final responderDead = status == 'in_progress' && beat is Timestamp &&
        now.difference(beat.toDate()) > const Duration(minutes: 2);
    if (status == 'pending' || responderDead) {
      try {
        await reqRef.update({'status': 'pending', 'nudgedAt': FieldValue.serverTimestamp()});
      } catch (_) {}
      lastNudge = now;
    }
  }
}
```

3. المستجيب ينبض كل 30 ثانية أثناء البثّ الطويل (`rebroadcastEverything` تقبل `onProgress` أصلاً):

```dart
var lastBeat = DateTime.now();
final stats = await rebroadcastEverything(onProgress: (_, __) {
  final now = DateTime.now();
  if (now.difference(lastBeat) < const Duration(seconds: 30)) return;
  lastBeat = now;
  unawaited(reqRef.update({'respondingAt': FieldValue.serverTimestamp()}).catchError((_) {}));
});
```

إعادة البثّ إدمبوتنت (`createIfAbsent`)، فلو عمل مستجيبان معاً لا يضرّ ذلك.


### 7.17 اليتيمات `_processOrphans`

**المشكلة (الفوضى):** معاملة وصلت قبل عميلها فخُزّنت يتيمة. ثم وصلت نسختها الأحدث عبر المستمع (بعد وصول العميل). عند معالجة اليتيمات لاحقاً كانت تُطبَّق اللقطة المخزّنة القديمة فوق الجديد.

```dart
// وصلت المعاملة (بنسخة أحدث) عبر المستمع بعد تخزين اليتيمة
final already = await db.query('transactions',
    columns: ['id'], where: 'transaction_uuid = ?', whereArgs: [syncUuid], limit: 1);
if (already.isNotEmpty) {
  await db.delete('sync_orphans', where: 'sync_uuid = ?', whereArgs: [syncUuid]);
  continue;
}
if (data['deviceId'] == _deviceId) {
  await _handleOwnTxDoc(syncUuid, data); // معاملتي المفقودة بعد استعادة
} else {
  await _applyTransactionChange(syncUuid, data);
}
```

### 7.18 الرفع القسري (زر «الرفع الشامل»)

**`_forceUploadCustomer`:**
- في وضع الاستعادة: `throw Exception('وضع الاستعادة: الرفع موقوف...')`.
- **لا يكتب `isDeleted` إطلاقاً** (الرفع الشامل لعملاء نشطين؛ كتابة `isDeleted=false` بـ merge كانت «تُحيي» عميلاً حذفه جهاز آخر للتو).
- لا `groupSecret`، ويُضاف `signature`.

**`_forceUploadTransaction`:**
- في وضع الاستعادة: `throw`.
- يقرأ الصف الحديث من القاعدة بدل البيانات الممرَّرة.
- يرفض معاملات الأجهزة الأخرى، ويتخطى معاملات الفواتير النشطة.
- `isDeleted` يُكتب فقط إن كانت محذوفة (true).
- CAS بعد الرفع بنفس `_txFingerprint`.
- لا `groupSecret`، ويُضاف `signature`، و`invoiceSyncUuid`.


---

<a id="8"></a>
## 8. مزامنة الفواتير InvoiceSyncService

**الملف:** `lib/services/firebase_sync/invoice_sync_service.dart`

الاستيرادات الجديدة:

```dart
import 'firebase_sync_service.dart';
import '../database/business/customer_visibility.dart';
```

### 8.1 الحذف يتزامن + وضع الاستعادة يوقف الرفع

- أضف `'is_deleted'` إلى مجموعة `_invoiceColumns` (الأعمدة المسموح كتابتها من السحابة). كان يُهمل، فيبقى دين الفاتورة المحذوفة على الأجهزة.
- في بداية `syncPendingInvoices`: `if (FirebaseSyncService().isRecovering) return 0;`
- في بداية `syncInvoiceBundleNow`: `if (FirebaseSyncService().isRecovering) return false;`

### 8.2 حمولة الحزمة (Payload)

في `_buildInvoiceBundlePayload`:

```dart
payload.remove('id');
payload.remove('is_synced');
payload.remove('restored_mark'); // حالة محلية لهذا الجهاز
// ...
payload['uploadedAt'] = FieldValue.serverTimestamp();
// 🛡️ معرّف جهاز Firebase الرافع: creator_device_id رقم فواتير (افتراضياً 1
// لكل الأجهزة) لا يميّز الجهاز، فلا يتعرف المنشئ على فواتيره بعد استعادة نسخة.
payload['uploaderDeviceId'] = await FirebaseSyncConfig.getDeviceId();
```

**دالة جديدة `rebroadcastMissingInvoices`** — للجهاز المُجيب في التمهيد: يعيد بثّ حزم الفواتير **الغائبة** من السحابة (كل الفواتير المعروفة لديه، لا فواتيره وحده)، دون الكتابة فوق حزمة موجودة ودون تغيير `is_synced` أو الإصدار:

```dart
Future<int> rebroadcastMissingInvoices() async {
  if (!await FirebaseSyncConfig.isEnabled()) return 0;
  final db = await _db.database;
  final rows = await db.query('invoices',
      columns: ['invoice_uuid'], where: "invoice_uuid IS NOT NULL AND invoice_uuid != ''");
  final collection = _firestore.collection('invoices');
  int n = 0;
  for (final r in rows) {
    final uuid = r['invoice_uuid'] as String;
    try {
      final full = await _coordinator.getFullInvoiceByUuid(uuid);
      if (full == null) continue;
      final payload = await _buildInvoiceBundlePayload(full, collection);
      if (payload == null) continue;
      final ref = collection.doc(uuid);
      final created = await _firestore.runTransaction<bool>((txn) async {
        final snap = await txn.get(ref);
        if (snap.exists) return false;
        txn.set(ref, payload);
        return true;
      }).timeout(const Duration(seconds: 30));
      if (created) n++;
    } catch (e) {
      print('⚠️ إعادة بث الفاتورة $uuid: $e');
    }
  }
  return n;
}
```

### 8.3 تعليم معاملات الحزمة «مرفوعة»

في `_markInvoiceTransactionsAsSynced`: تخطَّ الصفوف المحذوفة:

```dart
// شاهد حذف (حذف العميل) يُرفع عبر قناة المعاملات — لا نعلّمه مرفوعاً هنا
// وإلا لم يصل الحذف لجهاز يتجاهل نسخة الحزمة المكررة الإصدار.
if ((((tx as Map)['is_deleted'] as num?)?.toInt() ?? 0) == 1) continue;
```

### 8.4 استقبال حزمة `_processIncomingInvoice`

**(أ) الملكية واستعادة فواتيري:**

```dart
final existing = await db.query('invoices',
    columns: ['id', 'is_created_by_me', 'restored_mark'],
    where: 'invoice_uuid = ?', whereArgs: [uuid], limit: 1);

if (existing.isNotEmpty && localVersion >= incomingVersion) return; // إدمبوتنت

// فاتورتي أنا: نسختي المحلية هي المرجع — إلا إن كانت الحزمة الواردة من رفعي أنا
// بإصدار أحدث (قاعدتي استُعيدت من نسخة احتياطية).
final uploader = data['uploaderDeviceId']?.toString();
final localIsMine = existing.isNotEmpty && (existing.first['is_created_by_me'] as int?) != 0;
final ownRestore = uploader != null && uploader == myDeviceId && (existing.isEmpty || localIsMine);
if (localIsMine && !ownRestore) return;

if (ownRestore && existing.isNotEmpty &&
    ((existing.first['restored_mark'] as int?) ?? 0) == 0) {
  // عُدّلت محلياً بعد استعادة النسخة الاحتياطية: تعديل المستخدم هو الأحدث نيةً.
  // نتقدّم على نسخة السحابة ليحلّ رفعنا محلها.
  await db.update('invoices', {'version': incomingVersion + 1, 'is_synced': 0},
      where: 'id = ?', whereArgs: [existing.first['id']]);
  return;
}
```

**المشكلة التي حلّها الشرط الأخير (اكتُشفت في الفوضى القاسية، seed=20001):**
1. D4 عدّل فاتورته (v3، رُفعت).
2. استعاد D4 نسخة احتياطية أقدم (فيها v1).
3. أثناء الاستعادة عدّل المستخدم الفاتورة (صارت v2 محلياً).
4. وصلت نسخة D4 نفسه من السحابة (v3 > v2) → **مُحي تعديل المستخدم**، وكل الأجهزة بقيت على الفاتورة القديمة (فرق 400).

الحل: `restored_mark` للفواتير. صف لم يُعدَّل بعد الاستعادة (`=1`) تحلّ محله نسخة السحابة. صف عدّله المستخدم (`=0`) يبقى ويقفز رقمه فوق نسخة السحابة.

**(ب) الحقول عند الإدراج/التحديث:**

```dart
invoiceData['version'] = incomingVersion;
invoiceData['is_synced'] = 1;
invoiceData['restored_mark'] = 0;
invoiceData['is_locked'] = ownRestore ? 0 : 1;
invoiceData['is_created_by_me'] = ownRestore ? 1 : 0;
invoiceData['is_deleted'] = ((data['is_deleted'] as num?)?.toInt() ?? 0) == 1 ? 1 : 0;
```

**(ج) معاملات الحزمة (مزامنة ذرية):**

**المشاكل (سيناريوهات 18، 35، 36 + الفوضى):**
- الحذف القديم كان يحدث **عند التحديث فقط** (`if (isUpdate)`)، فصفوف قديمة وصلت من مجموعة `transactions` تبقى.
- الحذف كان يشمل صفوفاً **يملكها هذا الجهاز** فيُمحى سجلّه نهائياً.
- حزمة أحدث كانت «تُحيي» صفاً أُبطل هنا بحذف العميل.
- معرّفات التسوية القديمة `recon_inv<id>_cus<id>` مبنية على أرقام محلية تتكرر بين الأجهزة، فكان الإدراج بـ `ConflictAlgorithm.replace` يكتب فوق صف فاتورة أخرى.

**التعديل:** استبدل الكتلة بـ:

```dart
// تذكّر الصفوف المحذوفة (الحذف نهائي)
final deletedBefore = <String, int>{};
final prevDeleted = await txn.query('transactions',
    columns: ['transaction_uuid', 'is_uploaded'],
    where: 'invoice_sync_uuid = ? AND is_deleted = 1', whereArgs: [uuid]);
for (final r in prevDeleted) {
  final u = r['transaction_uuid'] as String?;
  if (u != null) deletedBefore[u] = (r['is_uploaded'] as int?) ?? 1;
}
// احذف دائماً صفوف هذه الفاتورة التي لا أملكها (أو النشطة فقط عند استعادة فاتورتي)
if (ownRestore) {
  await txn.delete('transactions',
      where: 'invoice_sync_uuid = ? AND (is_deleted IS NULL OR is_deleted = 0)', whereArgs: [uuid]);
} else {
  await txn.delete('transactions',
      where: 'invoice_sync_uuid = ? AND is_created_by_me = 0', whereArgs: [uuid]);
}
for (final txRaw in transactionsList) {
  // ... بناء txMap كما كان
  txMap['is_created_by_me'] = ownRestore ? 1 : 0;
  txMap['is_uploaded'] = 1;
  // ...
  if (txUuid != null && txUuid.isNotEmpty) {
    txMap['transaction_uuid'] = txUuid;
    txMap['sync_uuid'] = txUuid;
    if (deletedBefore.containsKey(txUuid)) {   // الحذف نهائي
      txMap['is_deleted'] = 1;
      txMap['is_uploaded'] = deletedBefore[txUuid];
    }
    final existingTx = await txn.query('transactions',
        columns: ['id', 'invoice_sync_uuid', 'is_created_by_me'],
        where: 'transaction_uuid = ? OR sync_uuid = ?', whereArgs: [txUuid, txUuid], limit: 1);
    if (existingTx.isNotEmpty) {
      final exInv = existingTx.first['invoice_sync_uuid'] as String?;
      final exMine = (existingTx.first['is_created_by_me'] as int?) != 0;
      // لا نكتب فوق صف لفاتورة أخرى أو صف أملكه
      if ((exInv != null && exInv.isNotEmpty && exInv != uuid) || (exMine && !ownRestore)) {
        continue;
      }
      await txn.update('transactions', txMap, where: 'id = ?', whereArgs: [existingTx.first['id']]);
      continue;
    }
  }
  await txn.insert('transactions', txMap, conflictAlgorithm: ConflictAlgorithm.ignore); // لا replace
}
// ... _ensureCreditTransaction و إعادة حساب الرصيد كما كان، ثم:
await CustomerVisibility.apply(txn, localCustomerId);
```

### 8.5 إنشاء/إيجاد عميل الفاتورة `_resolveOrCreateLocalCustomer`

**المشكلة (سيناريو 12):** مع وجود معرّف مزامنة معروف للعميل في الحزمة، كان يبحث بالاسم ويربط أي عميل محلي بنفس الاسم → دين شخص يُسجَّل على آخر.

**التعديل:**
- بعد البحث بالمعرّف: إن كان المعرّف معروفاً (`uuid != null`)، اربط بالاسم **فقط** سجلاً قديماً بلا هوية، واكتب فيه المعرّف:

```dart
if (name != null && name.isNotEmpty && uuid != null) {
  final legacy = await db.rawQuery(
    "SELECT id FROM customers WHERE REPLACE(name, ' ', '') = ? "
    "AND (sync_uuid IS NULL OR sync_uuid = '') LIMIT 1",
    [name.replaceAll(' ', '')]);
  if (legacy.isNotEmpty) {
    final id = legacy.first['id'] as int;
    await db.update('customers', {'sync_uuid': uuid}, where: 'id = ?', whereArgs: [id]);
    return id;
  }
} else if (name != null && name.isNotEmpty) {
  // البحث القديم بالاسم/الهاتف (فقط حين لا نعرف المعرّف)
}
```

- عند فشل الإدراج بسبب `UNIQUE(name, phone)` لعميل له هوية: أعد المحاولة بهاتف مميّز بمحرف غير مرئي (حتى 20 مرة) قبل اللجوء للعميل الموجود:

```dart
final hadIdentity = uuid != null;
// ...
} catch (e) {
  if (hadIdentity) {
    for (var k = 1; k <= 20; k++) {
      row['phone'] = '${phone ?? ''}${'​' * k}';
      try { return await db.insert('customers', row); } catch (_) {}
    }
  }
  // الرجوع للسلوك القديم
}
```

### 8.6 إنشاء دين فاتورة وصلت بلا معاملات `_ensureCreditTransaction`

**المشكلة (سيناريو 35):** الفاتورة **المعلّقة** مسوّدة لا تُنتج ديناً عند منشئها، لكن كل الأجهزة الأخرى كانت تسجّل ديناً وهمياً لكل مسوّدة دين.
**ومشكلة أخرى:** البحث عن «معاملة غير مربوطة بنفس المبلغ» كان يلتقط أي معاملة (دين يدوي لهذا الجهاز مثلاً) ويربطها بالفاتورة، ثم يحذفها تحديث الحزمة التالي.

```dart
if (paymentType != 'دين') return;
final status = invoiceData['status'] as String? ?? 'محفوظة';
if (status != 'محفوظة') return;
if (((invoiceData['is_deleted'] as num?)?.toInt() ?? 0) == 1) return;
// ...
// في استعلام unlinkedMatch أضف:
//   AND is_created_by_me = 0
//   AND transaction_type IN ('invoice_debt', 'invoice_debt_sync')
```

### 8.7 تحديث فاتورة واردة لا يعيد كتابة الترقيم المحلي (اكتُشف باختبار الكود الحقيقي)

**المشكلة:** جدول الفواتير عليه قيد فريد:

```sql
CREATE UNIQUE INDEX idx_invoices_unique_composite
ON invoices(creator_device_id, invoice_year, invoice_month, monthly_sequence_number)
```

و`creator_device_id` هو «رقم جهاز الفواتير» من الإعدادات، وقيمته الافتراضية **1 على كل الأجهزة**. فالفاتورة السادسة في الشهر على D2 تحمل نفس الرقم المركّب الذي تحمله الفاتورة السادسة على D1.

- مسار **الإدراج** في `_processIncomingInvoice` يعالج التصادم: يعيد ترقيم الفاتورة الواردة محلياً (`max + 1`).
- مسار **التحديث** كان يكتب الرقم الأصلي من السحابة فوق الصف، فيصطدم بفاتورة محلية ويفشل. كل تحديث لاحق لهذه الفاتورة يفشل بنفس الطريقة، **فيبقى الجهاز على النسخة الأولى من الفاتورة ودينها إلى الأبد**. مثال فعلي من الاختبار: فاتورة عُدّلت من نقد 500 إلى دين 900، وجهازان بقيا على نقد 500، فعرضا رصيد العميل ‎-90 بدل 810.

**التعديل:** في `_processIncomingInvoice`، فرع التحديث، احذف حقول الترقيم من البيانات قبل `update`. الصف يحتفظ بالرقم الذي أخذه عند الإدراج، وكان فريداً وقتها:

```dart
invoiceId = rows.first['id'] as int;
final updateData = Map<String, dynamic>.from(invoiceData)
  ..remove('monthly_sequence_number')
  ..remove('invoice_year')
  ..remove('invoice_month');
await txn.update('invoices', updateData,
    where: 'invoice_uuid = ?', whereArgs: [uuid]);
```

> **درس عام:** أي قيد فريد محلي على بيانات تأتي من أجهزة أخرى يجب أن يُعامل في **كل** مسارات الكتابة (الإدراج والتحديث)، وإلا صار «فشلاً صامتاً» يوقف المزامنة لهذا السجل. ابحث في المشروع الآخر عن كل `UNIQUE` في المخطط وتأكد من ذلك.

### 8.8 تعليم صفوف الحزمة «مرفوعة» بمقارنة (اكتُشف باختبار الكود الحقيقي)

**المشكلة:** بعد رفع حزمة فاتورة، كانت `_markInvoiceTransactionsAsSynced` تستدعي `markTransactionAsSynced(uuid)` التي تكتب `is_uploaded = 1` بالمعرّف فقط. لكن الحمولة لقطة من **قبل** الرفع. إن حذف المستخدم العميل **أثناء** رفع الحزمة، يصير صف الدين «شاهد حذف بانتظار الرفع» (`is_deleted=1, is_uploaded=0`)، ثم تأتي هذه الخطوة فتعلّمه «مرفوعاً». النتيجة: **شاهد الحذف لا يُرفع أبداً، فيبقى دين الفاتورة حياً على كل الأجهزة الأخرى** (مثال فعلي: 750 زائدة على تسعة أجهزة).

**التعديل:** في `_markInvoiceTransactionsAsSynced` استبدل استدعاء المنسق بتحديث مشروط:

```dart
final db = await _db.database;
await db.update(
  'transactions',
  {'is_uploaded': 1},
  where: '(transaction_uuid = ? OR sync_uuid = ?) '
      'AND (is_deleted IS NULL OR is_deleted = 0)',
  whereArgs: [txUuid, txUuid],
);
```

> **درس عام:** كل «تعليم مرفوع» بعد رفع شبكي يجب أن يتحقق أن الصف ما زال كما كان في اللقطة المرفوعة (CAS). ابحث عن كل `is_uploaded': 1` بعد `await` لعملية شبكة.

### 8.9 رفع الفواتير لا يحجز التهيئة، وله مهلة (اكتُشف باختبار الكود الحقيقي)

**المشكلة:** `startSync` كان ينتظر `syncPendingInvoices()` قبل أن يبدأ الاستماع للفواتير. ورفع الحزمة `set()` بلا مهلة. وFirestore على سطح المكتب (بلا persistence) لا يُكمل `set()` حتى يعود الاتصال. النتيجة: **فتح التطبيق بلا إنترنت مع فاتورة غير مرفوعة يحجز تهيئة المزامنة كلها** (`initialize` ينتظر `startSync`) حتى يعود الإنترنت.

**التعديل في `invoice_sync_service.dart`:**

```dart
// في startSync: لا ننتظر الرفع
unawaited(syncPendingInvoices().catchError((e) {
  print('⚠️ تعذّر رفع الفواتير المعلقة أولية: $e');
  return 0;
}));

// في syncPendingInvoices و syncInvoiceBundleNow: مهلة كبقية عمليات الرفع
await collection
    .doc(uuid)
    .set(payload, SetOptions(merge: true))
    .timeout(const Duration(seconds: 60));
```

### 8.10 هوية العميل فريدة في قاعدة البيانات (اكتُشف باختبار الكود الحقيقي)

**المشكلة:** عدة مسارات تُدرج عميلاً وارداً: مستمع العملاء، وحزمة الفاتورة، والمطابقة المحصّنة. كلها «تتحقق أنه غير موجود ثم تُدرج» دون قيد فريد على `sync_uuid`. إن وصل العميل وفاتورته في نفس اللحظة، يتسابق المساران فيُدرج كل منهما صفاً: **العميل يظهر مرتين**، أحدهما عليه كل المعاملات والآخر فارغ برصيد صفر.

**التعديل:**

1. في `database_migrations.dart` داخل `ensureSchema` (بعد أعمدة القسم 3): `await mergeDuplicateCustomerIdentities(db);`
2. الدالة (انسخها من الملف كما هي): لكل `sync_uuid` مكرر تُبقي الصف الأقدم، وتنقل إليه `transactions` و`invoices` و`customer_receipt_vouchers` من الصفوف الأخرى، وتحذفها، وتعيد حساب الرصيد والظهور. ثم:

```sql
CREATE UNIQUE INDEX IF NOT EXISTS ux_customers_sync_uuid
ON customers(sync_uuid) WHERE sync_uuid IS NOT NULL AND sync_uuid != ''
```

   > **مهم:** بلا `db.transaction` داخلها، لأن `ensureSchema` تُستدعى أيضاً داخل `onUpgrade` (وهي معاملة أصلاً). إن انقطع الدمج أكمله التشغيل التالي.

3. في كل مسار إدراج عميل وارد، عند فشل الإدراج بقيد فريد، **ابحث أولاً بالمعرّف** وأعد الصف الموجود:

```dart
} on DatabaseException catch (e) {
  if (!e.isUniqueConstraintError()) rethrow;
  final same = await db.query('customers',
      columns: ['id'], where: 'sync_uuid = ?', whereArgs: [syncUuid], limit: 1);
  if (same.isNotEmpty) return same.first['id'] as int;
  // ... ثم معالجة UNIQUE(name, phone) كما كانت
}
```

   المسارات في هذا المشروع: `_insertReceivedCustomer` (خدمة المزامنة)، و`_resolveOrCreateLocalCustomer` (خدمة الفواتير)، و`_resolveCustomer` (المطابقة المحصّنة).

### 8.11 تأشير الفاتورة «مرفوعة» بمقارنة الإصدار (اكتُشف أثناء فحص اختبار الكود الحقيقي)

**المشكلة:** بعد `set()` الحزمة كانت `markAsSynced(uuid)` تكتب `is_synced = 1` بالمعرّف فقط. لكن الحمولة لقطة من **قبل** الرفع. إن تغيّرت الفاتورة **أثناء** الرفع (المستخدم عدّلها، أو الحارس المحاسبي غيّر صف التسوية فرفع الإصدار وأعادها `is_synced = 0`) تأتي هذه الخطوة فتمحو «غير مرفوعة». النتيجة: **النسخة الجديدة لا تُرفع أبداً**، وتبقى السحابة والأجهزة الأخرى على المبلغ القديم.

**التعديل 1 — `invoice_sync_coordinator.dart`:**

```dart
Future<bool> markAsSynced(String invoiceUuid, {int? uploadedVersion}) async {
  final db = await _dbService.database;
  final n = await db.update(
    'invoices',
    {'is_synced': 1},
    where: uploadedVersion == null
        ? 'invoice_uuid = ?'
        : 'invoice_uuid = ? AND COALESCE(version, 1) = ?',
    whereArgs:
        uploadedVersion == null ? [invoiceUuid] : [invoiceUuid, uploadedVersion],
  );
  return n > 0;
}
```

**التعديل 2 — `invoice_sync_service.dart`** في `syncPendingInvoices`:

```dart
final marked = await _coordinator.markAsSynced(uuid,
    uploadedVersion: (invMap['version'] as num?)?.toInt() ?? 1);
if (!marked) continue; // تغيّرت أثناء الرفع: تبقى معلّقة وتُرفع في الدورة التالية
await _markInvoiceTransactionsAsSynced(invMap);
uploaded++;
```

وفي `syncInvoiceBundleNow`:

```dart
final marked = await _coordinator.markAsSynced(invoiceUuid,
    uploadedVersion: (fullInvoice['version'] as num?)?.toInt() ?? 1);
if (!marked) return false;
await _markInvoiceTransactionsAsSynced(fullInvoice);
```

**لماذا يكفي الإصدار؟** كل تغيير محلي على فاتورة يرفع إصدارها: `stampInvoiceForSync` (التعديل)، و`deleteInvoice` (الحذف)، والحارس المحاسبي (تغيير صف التسوية). الاستثناء الوحيد هو الحارس في وضع الاستعادة (`restored_mark = 1`)، ويكتب `is_synced = 0` بلا رفع إصدار، لكن الرفع كله موقوف في وضع الاستعادة فلا تسابق. وقراءة الفاتورة ثم معاملاتها استعلامان منفصلان؛ إن تغيّر صف التسوية بينهما يختلف الإصدار فتفشل المقارنة وتُعاد الحزمة كاملة.

### 8.12 الفاتورة تحمل مالكها الحقيقي (اكتُشف باختبار الكود الحقيقي)

**المشكلة:** كان المالك يُعرف من `uploaderDeviceId` (آخر من كتب الحزمة). لكن حين يعيد جهازٌ بثّ حزمة غائبة لجهاز جديد أو مستعيد (`rebroadcastMissingInvoices`) يصير هو «الرافع». المالك الذي استعاد نسخة احتياطية يرى «الرافع ليس أنا» فيرفض نسخة فاتورته الأحدث ويبقى على القديمة. وإن عدّلها بعد ذلك يرفعها بإصدار أقل مما عند الآخرين فيتجاهلونها.

**التعديل 1 — المخطط:** `invoices.owner_device_id TEXT` (القسم 3).

**التعديل 2 — `_buildInvoiceBundlePayload`** بعد حذف `restored_mark` من الحمولة:

```dart
final storedOwner = payload.remove('owner_device_id') as String?;
final ownInvoice = ((invMap['is_created_by_me'] as num?)?.toInt() ?? 1) != 0;
final ownerId = ownInvoice ? await FirebaseSyncConfig.getDeviceId() : storedOwner;
if (ownerId != null && ownerId.isNotEmpty) payload['ownerDeviceId'] = ownerId;
```

**التعديل 3 — `_processIncomingInvoice`:**

```dart
// المالك: الحقل الصريح، أو الرافع لحزم الإصدارات السابقة
final owner = (data['ownerDeviceId'] ?? data['uploaderDeviceId'])?.toString();
final localIsMine = existing.isNotEmpty && (existing.first['is_created_by_me'] as int?) != 0;
final localRestored = existing.isNotEmpty &&
    ((existing.first['restored_mark'] as int?) ?? 0) == 1;
// فاتورتي من النسخة الاحتياطية ولم تُعدَّل بعدها: أي نسخة أحدث هي الحقيقة
final ownRestore = (owner != null && owner == myDeviceId &&
        (existing.isEmpty || localIsMine)) ||
    (localIsMine && localRestored);
```

وعند كتابة الفاتورة الواردة: `if (owner != null && owner.isNotEmpty) invoiceData['owner_device_id'] = owner;`

### 8.13 تصادم رقم نسخة الفاتورة بعد استعادة نسخة احتياطية (اكتُشف باختبار الكود الحقيقي)

**المشكلة:** جهاز عدّل فاتورته فرفعها بالنسخة 4، ثم استعاد نسخة احتياطية فيها النسخة 3، ثم عدّلها المستخدم **قبل أن يصله رفعه السابق** ⇒ التعديل الجديد أخذ رقم النسخة 4 نفسه بمحتوى مختلف. الأجهزة الأخرى عندها «نسخة 4» فتتجاهل التعديل (الفحص كان `localVersion >= incomingVersion ⇒ تجاهل`) — الكمية والدين يختلفان بينها وبين المالك إلى الأبد.

**التعديل في `_processIncomingInvoice`** (اقرأ `last_modified_at` و`is_synced` مع الصف الموجود):

```dart
/// نسخة واردة أحدث؟ رقم النسخة أولاً، وعند التساوي وقت التعديل
/// (بساعة المالك — لا يعدّل الفاتورة غيره).
static bool _isNewerInvoice(int inVer, String inMod, int localVer, String localMod) {
  if (inVer != localVer) return inVer > localVer;
  return inMod.isNotEmpty && localMod.isNotEmpty && inMod.compareTo(localMod) > 0;
}
```

1. **عند المالك:** نسختي المحلية بنفس رقم الواردة ووقتها أحدث ⇒ `version = incoming + 1, is_synced = 0` (مشروطة بأن الرقم لم يتغير) ثم `return` — فيصل تعديلي برقم أعلى.
2. **الإدمبوتنت:** `if (existing.isNotEmpty && !_isNewerInvoice(...)) return;` بدل `localVersion >= incomingVersion`، ونفس الدالة في الفحص داخل المعاملة (أضف `last_modified_at` لأعمدة الاستعلام هناك).

### 8.14 رفع الحزمة لا يكتب فوق نسخة أحدث في السحابة (اكتُشف باختبار الكود الحقيقي)

**المشكلة:** الحمولة لقطة من لحظة بنائها، والرفع كان `set(merge: true)` بلا شرط. رفع المعلّق عند الإقلاع أخذ لقطة النسخة 2، ثم عُدّلت الفاتورة ورُفعت النسخة 6، ثم وصلت لقطة النسخة 2 **فكتبت فوق السادسة**. الأجهزة التي لم تلحق بالسادسة بقيت على الثانية إلى الأبد، والمالك يظن فاتورته مرفوعة.

**التعديل:** دالة واحدة للرفع في `syncPendingInvoices` و`syncInvoiceBundleNow` بدل `set` المباشر:

```dart
Future<bool> _uploadBundleIfNotOlder(DocumentReference ref, Map<String, dynamic> payload) async {
  final ver = (payload['version'] as num?)?.toInt() ?? 1;
  final mod = payload['last_modified_at']?.toString() ?? '';
  return _firestore.runTransaction<bool>((txn) async {
    final snap = await txn.get(ref);
    final d = snap.data() as Map<String, dynamic>?;
    if (d != null) {
      final cloudVer = (d['version'] as num?)?.toInt() ?? 1;
      final cloudMod = d['last_modified_at']?.toString() ?? '';
      if (_isNewerInvoice(cloudVer, cloudMod, ver, mod)) return false; // السحابة أحدث
    }
    txn.set(ref, payload, SetOptions(merge: true));
    return true;
  }).timeout(const Duration(seconds: 60));
}
```

نسخة مساوية تُكتب (إعادة رفع لا تضر). بلا إنترنت ترمي المعاملة فتبقى الفاتورة معلّقة وتُعاد (كانت `set` تنتظر في الطابور). وحُذف المتغير `isUpdate` الذي لم يعد مستخدماً بعد نقل المخزون إلى الدفتر.

---

<a id="9"></a>
## 9. الحارس المحاسبي للفواتير InvoiceDebtReconciler

**الملف:** `lib/services/database/business/invoice_debt_reconciler.dart`

هذه الدالة تضبط «صف تسوية» واحداً لكل (فاتورة، عميل) بحيث مساهمة الفاتورة في الدين = الإجمالي − المسدد (للدين) أو صفر.

### 9.1 معرّف صف التسوية عالمي

**المشكلة (سيناريو 36):** المعرّف كان `recon_inv<رقم الفاتورة المحلي>_cus<رقم العميل المحلي>`. جهازان يبدآن من قاعدة فارغة: أول فاتورة دين لأول عميل على كل منهما تحمل **نفس المعرّف** (`recon_inv1_cus1`) → صف جهاز يكتب فوق صف جهاز آخر لفاتورة مختلفة.

```dart
static String adjustmentUuid(int invoiceId, int customerId) =>
    'recon_inv${invoiceId}_cus$customerId';   // القديم — للبحث عن صفوف قديمة فقط

static const String _suspendedStatus = 'معلقة';

static Future<String> _globalAdjustmentUuid(
    DatabaseExecutor db, int invoiceId, String? invoiceUuid, int customerId) async {
  if (invoiceUuid == null || invoiceUuid.isEmpty) return adjustmentUuid(invoiceId, customerId);
  final cu = await db.query('customers',
      columns: ['sync_uuid'], where: 'id = ?', whereArgs: [customerId], limit: 1);
  final cs = cu.isEmpty ? null : cu.first['sync_uuid'] as String?;
  if (cs == null || cs.isEmpty) return adjustmentUuid(invoiceId, customerId);
  return 'recon_${invoiceUuid}_$cs';
}
```

### 9.2 قواعد `reconcileInvoice`

اقرأ أعمدة إضافية للفاتورة: `status`, `is_deleted`, `is_created_by_me`, `restored_mark`. ثم:

```dart
// فاتورة مستلمة من جهاز آخر: أثرها المالي يصل كاملاً في حزمتها
if ((inv['is_created_by_me'] as int?) == 0) return false;

// فاتورة محذوفة أو معلّقة مساهمتها صفر
final bool contributes = (inv['is_deleted'] as int?) != 1 &&
    (inv['status'] as String?) != _suspendedStatus;
double expectedForCurrent = 0.0;
if (contributes && paymentType == 'دين') {
  // ... الحساب كما كان
}
```

> **لماذا `!= 'معلقة'` وليس `== 'محفوظة'`؟** الحالتان الموجودتان فقط `محفوظة` و`معلقة`. المقارنة بـ `معلقة` تعامل أي قيمة قديمة/فارغة كـ «محفوظة» فلا تُصفّر ديناً حقيقياً بالخطأ. والمتحكم (`invoice_controller`) يضبط الحالة `محفوظة` قبل استدعاء الحارس.

لكل عميل معنيّ داخل الحلقة:

```dart
final String adjUuid = await _globalAdjustmentUuid(db, invoiceId, invoiceUuid, customerId);
final String legacyUuid = adjustmentUuid(invoiceId, customerId);

// صف تسوية أبطله حذف العميل: لا نعيد الدين إلى الحياة
final voided = await db.rawQuery('''
  SELECT 1 FROM transactions
  WHERE is_deleted = 1
    AND ((transaction_uuid = ? OR sync_uuid = ?)
         OR (transaction_uuid = ? AND invoice_id = ? AND customer_id = ?))
  LIMIT 1
''', [adjUuid, adjUuid, legacyUuid, invoiceId, customerId]);
if (voided.isNotEmpty) continue;

var adjRows = await db.query('transactions', columns: ['id', 'amount_changed'],
    where: '(transaction_uuid = ? OR sync_uuid = ?) AND (is_deleted IS NULL OR is_deleted = 0)',
    whereArgs: [adjUuid, adjUuid], limit: 1);
if (adjRows.isEmpty && legacyUuid != adjUuid) {
  // صف من نسخة سابقة: نعتمده فقط إن كان لنفس الفاتورة ونفس العميل ومن إنشائي
  adjRows = await db.query('transactions', columns: ['id', 'amount_changed'],
      where: 'transaction_uuid = ? AND invoice_id = ? AND customer_id = ? '
          'AND is_created_by_me = 1 AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [legacyUuid, invoiceId, customerId], limit: 1);
}
// ... الإنشاء/التحديث كما كان، مع إضافة 'restored_mark': 0 في خريطة التحديث
// بعد إعادة بناء الأرصدة:
await rebuildCustomerBalances(db, customerId);
await CustomerVisibility.apply(db, customerId);
```

بعد الحلقة:

```dart
if (changed) {
  // الأثر المالي تغيّر = نسخة جديدة من الفاتورة. بدون هذا يرى المستقبِل
  // نفس رقم النسخة بمحتوى مختلف فيتجاهله، ويبقى دينه القديم.
  // استثناء: صف ما زال من نسخة احتياطية مستعادة — تُرفع نسخته عند انتهاء الاستعادة.
  if ((inv['restored_mark'] as int?) == 1) {
    await db.rawUpdate('UPDATE invoices SET is_synced = 0 WHERE id = ?', [invoiceId]);
  } else {
    await db.rawUpdate(
      'UPDATE invoices SET version = COALESCE(version, 1) + 1, is_synced = 0 WHERE id = ?',
      [invoiceId]);
  }
}
```

### 9.3 `reconcileCustomerLedger` (شبكة الأمان عند عرض سجل الديون)

في استعلام المرشحين:
- `expected` يصبح صفراً للفاتورة المحذوفة أو المعلّقة:

```sql
CASE WHEN i.payment_type = 'دين'
          AND COALESCE(i.is_deleted, 0) = 0
          AND COALESCE(i.status, '') != 'معلقة'
     THEN MAX(...)
     ELSE 0 END AS expected
```

- وفلتر الملكية:

```sql
WHERE COALESCE(i.is_created_by_me, 1) = 1
  AND (i.customer_id = ? OR i.id IN (...))
```

---

<a id="10"></a>
## 10. المراقب SyncWatchdog

**الملف:** `lib/services/firebase_sync/sync_watchdog.dart`

**(أ) رفع المعاملات:** استبدل جسم `_syncPendingTransactions` بمسار الرفع الموحّد (7.12):

```dart
Future<void> _syncPendingTransactions() async {
  // الشرط القديم (غير مسجّلة في المنسق) كان يتخطى أي معاملة سبق رفعها مرة،
  // فتعديلها أو تحويل نوعها أو حذفها لا يُرفع أبداً إلا لعملاء أنشأهم هذا الجهاز.
  try {
    final n = await FirebaseSyncService().uploadAllOwnedPending(limit: 200);
    _transactionsSynced += n;
  } catch (e) {
    print('🛡️ SyncWatchdog: خطأ في رفع المعاملات المعلّقة: $e');
  }
}
```

(الجسم القديم نُقل إلى `_syncPendingTransactionsLegacy` غير المستخدمة؛ يمكنك حذفها.)

**(ب) رفع العملاء:** في استعلام العملاء غير المرفوعين أضف:

```sql
AND (c.is_created_by_me = 1 OR c.is_created_by_me IS NULL)
```

---

<a id="11"></a>
## 11. المطابقة المحصّنة ArmoredReconciliationService

**الملف:** `lib/services/firebase_sync/armored_reconciliation_service.dart` — **أُعيدت كتابته بالكامل.** الأفضل أن تنسخ الملف كاملاً من هذا المشروع إلى المشروع الآخر، ثم تعدّل أسماء الأعمدة إن اختلفت.

هذه الخدمة وراء زرّي «بياناتي صحيحة» (truth_push) و«الجهاز الآخر صحيح» (truth_pull) في شاشة المطابقة.

### المشاكل في النسخة القديمة

| المشكلة | السيناريو | النتيجة |
|---|---|---|
| الجهاز المرجعي قد يكون متأخراً (لم يستلم بعد تسديداً حقيقياً من D3). الأجهزة الأخرى تُبطل كل ما ليس في كشفه. | 22 | **يُمحى تسديد حقيقي** من كل الأجهزة. |
| بعد الإبطال تُبثّ «قرارات إبطال» لكل الأجهزة، والإبطال نهائي. | 22، 29 | لا شيء يعيد المعاملة. وأي شخص يملك مفاتيح Firebase يكتب قراراً يمحو أي معاملة. |
| الكشف وثيقة واحدة. | 30 | عميل بـ 6000 معاملة ← كشف ≈ 2.4 MiB > حد Firestore (1 MiB) ← **المطابقة مستحيلة**. |
| الربط بالاسم إن لم يوجد العميل بالمعرّف (يسرق هوية عميل آخر بنفس الاسم). | 12، 25 | ديون عميلين تختلط. |
| ينسخ `invoice_id` (رقم الفاتورة **المحلي عند المرسل**) إلى قاعدة المستقبِل. | — | المعاملة تُربط بفاتورة محلية مختلفة، والحارس المحاسبي يحسبها ضمن فاتورة لا علاقة لها بها. |
| يحذف وثائق الكشف عند أول رد. | — | الأجهزة الأخرى التي لم تقرأه بعد لا تجده. |
| المستمع يدمج التغييرات: قد لا يرى جهازٌ الحالة `pending` أبداً بل `completed` مباشرة (بعد رد جهاز آخر). | — | لا يطبّق الكشف أصلاً. |
| لا تمييز بين الردود: رد قديم من طلب سابق يُحسب للطلب الحالي. | — | نجاح/فشل كاذب. |
| جهاز استعاد نسخة احتياطية يستطيع إعلان «بياناتي صحيحة». | 26 | نسخة قديمة تفرض نفسها على الجميع. |

### القواعد الجديدة (انسخ الملف لتطبيقها كلها)

1. **قبل الدفع (truth_push):**
   - إن كان الجهاز في وضع الاستعادة ← رفض.
   - إن كانت المزامنة غير متصلة/غير مهيّأة ← رفض (لأن السحب الكامل يعود بصمت فنكمل بكشف قديم).
   - `await FirebaseSyncService().performFullCatchUp();` أولاً: «لا تعلن بياناتي صحيحة وأنت متأخر».
2. **الكشف مجزّأ:** رأس في `reconciliation_data/{customerSyncUuid}` (الرصيد المرجعي + عدد الأجزاء + nonce) وأجزاء في `reconciliation_data/{customerSyncUuid}__p{i}` (حتى 400 معاملة أو ~600KB لكل جزء). **تُكتب الأجزاء أولاً ثم الرأس**، فمن يقرأ رأساً يجد كل أجزائه.
3. **كل طلب يحمل `nonce` عشوائياً.** الأجزاء والرد مربوطة به. عند القراءة: إن اختلف nonce رأس أو جزء عن الطلب ← الكشف غير مكتمل ← لا تطبيق. وانتظار الرد يقبل فقط رداً يحمل نفس nonce.
4. **الرصيد المرجعي = مجموع المعاملات النشطة** (لا الرصيد المخزّن).
5. **الكشف لا يحمل أعمدة محلية:** `id, customer_id, invoice_id, is_uploaded, is_read_by_others, remote_ver, last_uploaded_at, remote_modified_at, restored_mark, synced_at`. ويحمل `origin_device_id` = الجهاز المالك الحقيقي (جهازي لمعاملاتي، و`origin_device_id` المخزّن لغيرها).
6. **النظير يعالج كل طلب مرة واحدة** (مجموعة `_handledRequests` بمفتاح `requestId|nonce`)، ويعالج طلب الدفع في الحالات `pending` أو `completed` أو `mismatch` (لأن المستمع قد يدمج التغييرات). ويتجاهل الطلبات الأقدم من ساعتين (كشف قديم لا يصف الحاضر).
7. **التطبيق على ثلاث مراحل:**
   - **المرحلة 1 (معاملة SQLite واحدة، بلا أي قراءة سحابية):** أضف المعاملات الناقصة بالمعرّف (**الموجود نشطاً أو محذوفاً يُهمل؛ الحذف نهائي**). فلترة الأعمدة على أعمدة الجدول المحلي الفعلية (`PRAGMA table_info`). `invoice_id` يُحسب محلياً من `invoice_sync_uuid`. ثم حدّد المرشحين للإبطال: صفوف نشطة ليست في الكشف. **صفوف هذا الجهاز تُصان** ولا تُبطل: الصف اليدوي يعود للرفع (`is_uploaded=0`)، أما صف فاتورة (`invoice_sync_uuid` غير فارغ) فلا يُرفع وحده أبداً، **فتعود حزمة فاتورته للطابور** بدلاً منه: `UPDATE invoices SET is_synced = 0 WHERE invoice_uuid = ? AND COALESCE(is_created_by_me, 1) = 1` (نفس الإصدار: من يملك الحزمة يتجاهلها ومن ينقصه الصف يُدرجه). *(اكتُشف باختبار الكود الحقيقي: تأشير صف الفاتورة «غير مرفوع» كان يبقى عالقاً للأبد.)*
   - **المرحلة 2 (قراءات سحابية):** لكل مرشح (صف جهاز آخر) افحص «دليل الحياة» `_hasEvidenceOfLife`. أي دليل ← يبقى.
   - **المرحلة 3 (معاملة SQLite):** أبطل من لا دليل له، بشرط أن الصف لم يتغير أثناء الفحص (`WHERE id=? AND is_deleted=0 AND amount_changed=? AND is_created_by_me=0`). ثم الرصيد = المجموع، ثم `CustomerVisibility.apply`.
8. **دليل الحياة** (أي واحد يكفي لمنع الإبطال):

```dart
Future<bool> _hasEvidenceOfLife(DatabaseExecutor db, Map<String, dynamic> r) async {
  // وصلت من مستند سحابي يوماً: غيابه الآن تنظيف لا حذف (الحذف يترك شاهداً)
  if (r['remote_ver'] != null) return true;
  // صف فاتورة: أثر الفاتورة يحكمه صاحبها (حزمتها) لا المطابقة — أبداً.
  // (كان «والفاتورة موجودة هنا»: صف دين أدرجه كشفٌ قبل وصول حزمة فاتورته، ثم
  //  أبطله كشف ثانٍ لا يعرفه، وبقي مُبطلاً للأبد — اكتُشف باختبار الكود الحقيقي)
  final invUuid = r['invoice_sync_uuid'] as String?;
  if (invUuid != null && invUuid.isNotEmpty) return true;
  final tu = (r['transaction_uuid'] as String?)?.isNotEmpty == true
      ? r['transaction_uuid'] as String : r['sync_uuid'] as String?;
  if (tu == null || tu.isEmpty) return false;
  try {
    final doc = await _firestore.collection('transactions').doc(tu)
        .get(const GetOptions(source: Source.server));
    final d = doc.data();
    if (d != null) return d['isDeleted'] != true; // مستند نشط = حقيقية
    // لا مستند: هل كان في السحابة ثم نظّفه SmartPipe؟ الإقرارات تشهد
    final acks = await _firestore.collection('transaction_acks')
        .where('transactionUuid', isEqualTo: tu).limit(1)
        .get(const GetOptions(source: Source.server));
    return acks.docs.isNotEmpty;
  } catch (e) {
    return true; // تعذّر التحقق = لا إبطال
  }
}
```

9. **إيجاد العميل:** بالمعرّف. الربط بالاسم **فقط** لسجل بلا هوية. إن لم يوجد يُنشأ (مع معالجة `UNIQUE(name, phone)` بالهاتف المميّز).
10. **لا قرارات إبطال** (لا استدعاء لـ `MatchVerdictService().publishVerdicts`).
11. **الرد يحمل تفسيراً:** `preservedCount/preservedSum` (صفوفي التي صِينت)، `keptCount` (صفوف أُبقيت بدليل)، `voidedCount`. والرسالة للمستخدم تشرح سبب أي فرق: «انتظر اكتمال المزامنة ثم أعد المطابقة».
12. **وثائق المطابقة لا تُحذف عند أول رد**؛ تنظيف دوري كل 30 دقيقة لما هو أقدم من **24 ساعة** (`requests.createdAt`, `results.respondedAt`, `data.builtAt`). (القديم كان يبحث عن `createdAt` في النتائج، وهو غير موجود فيها، فلم تكن تُحذف أبداً.)
13. **الطلب «الجهاز الآخر صحيح» (truth_pull):** مزوّد واحد فقط. أول نظير «يحجز» الطلب داخل معاملة Firestore (`pending ← providing`) ثم يسحب كل شيء ويكتب كشفه ثم `data_ready`. الجهاز في وضع الاستعادة لا يزوّد.
14. **الجهاز في وضع الاستعادة لا يطبّق كشفاً** (ولا يسجّل الطلب معالَجاً): معرفته قديمة، وما سيُحدَّث إليه يأتيه من الأجهزة الأخرى.
15. **الكشف لا يُدرج معاملات الجهاز المطبِّق نفسه:** في المرحلة 1، `if (tx['origin_device_id'] == myId) continue;` (بعد إضافة المعرّف إلى `incomingUuids`). مثال فعلي: جهاز استعاد نسخة أقدم من معاملته، ثم طبّق كشفاً بُني قبل تعديلها، فأُدرجت معاملته «كمعاملة جهاز آخر» بالمبلغ القديم ولم تقبل بعدها تعديله من السحابة.
16. **الطلبات المعالَجة محفوظة في الإعدادات** (`armored_handled_requests`، آخر 300): كانت في الذاكرة فقط، فكل إعادة تشغيل تعيد تطبيق كل كشف عمره أقل من ساعتين.
17. **صف فاتورة يُصان** (القاعدة 7): تعود حزمة فاتورته للطابور بدل تأشيره «غير مرفوع».

---

<a id="12"></a>
## 12. قرارات الإبطال MatchVerdictService (تعطيل)

**الملف:** `lib/services/firebase_sync/match_verdict_service.dart`

**المشكلة (سيناريوهات 22، 24، 29):** القرار يُبطل معاملة على **كل** الأجهزة لمجرد أن «جهاز الحقيقة» لم يكن يعرفها. لكنه قد يكون متأخراً فقط، فتسديد سُجّل على جهاز ثالث ولم يصله بعد يُمحى من الشبكة كلها، ولا شيء يعيده لأن الإبطال نهائي. وأي جهاز (أو أي شخص يملك مفاتيح المجموعة) يستطيع كتابة قرار يمحو أي معاملة (سيناريو 29: 10 أجهزة فقدت تسديداً حقيقياً).

**التعديل:** تعطيل كامل مع الإبقاء على الواجهة البرمجية والجداول المحلية للأرشيف:

```dart
/// ⛔ القرارات عن بُعد معطّلة
static const bool _publishingEnabled = false;

Future<void> start() async {
  if (_isListening) return;
  if (!await FirebaseSyncConfig.isEnabled()) return;
  _myDeviceId ??= await FirebaseSyncConfig.getDeviceId();
  await _ensureTables();
  // لا مستمع. القرارات المعلّقة من نسخ سابقة تُهمل كي لا تُنفَّذ عند وصول معاملتها.
  try {
    final db = await _db.database;
    await db.delete('pending_void_verdicts');
  } catch (_) {}
  _isListening = true;
}

// في أول publishVerdicts و applyVerdict:
if (!_publishingEnabled) return;
```

وفي خدمة المزامنة احذف كل استدعاء لـ `_verdictService.applyPendingVerdictsFor` و`_verdictService.processPendingVerdicts`.

> **في المشروع الآخر:** أبسط حل أن تحذف المستمع على `match_verdicts` كلياً. المهم ألا يُبطل أي جهاز معاملة بناءً على مستند كتبه جهاز آخر.

---

<a id="13"></a>
## 13. المطابقة الحية LiveMatchService

**الملف:** `lib/services/firebase_sync/live_match_service.dart`

### 13.1 المقارنة بالهوية لا بالاسم

**المشكلة (سيناريو 25):** `recompute` كان يجمع العملاء بالاسم المطبّع، ومن النظير يختار صاحب الدين الأكبر عند التكرار. عميلان مختلفان بنفس الاسم ← تطابق كاذب أو فرق كاذب (21 خللاً)، وكان زر «الجهاز الآخر صحيح» يبني عليه تصحيحاً.

**التعديل:** استبدل كتلة `localByName` و`peerByName` و`allNormNames` بـ:

```dart
final localByUuid = <String, ({String syncUuid, String name, int id, double debt, int txCount, double txSum})>{
  for (final c in local.customers) c.syncUuid: c,
};
final allUuids = <String>{...localByUuid.keys, ...peer.customers.keys};

final matches = <LiveCustomerMatch>[];
for (final uuid in allUuids) {
  final loc = localByUuid[uuid];
  final rem = peer.customers[uuid];
  final name = loc?.name ?? rem?.name ?? 'غير معروف';
  final syncUuid = uuid;
  // ... باقي الحلقة كما كانت (rem.debt, rem.txCount, rem.txSum)
}
```

### 13.2 «الجهاز الآخر صحيح» لا يُنشئ معاملات

**المشكلة (سيناريو 24):** كانت تُسجَّل معاملة «تصحيح» بفرق الرصيد (`peerDebt − localDebt`) يملكها هذا الجهاز. لكنها تنتشر لكل الأجهزة، **ومنها الجهاز الذي كان صحيحاً** فيختلّ رصيده بنفس الفرق. وحين تصل المعاملة الأصلية المتأخرة التي سبّبت الفرق **يُحسب المبلغ مرتين**. الفرق سببه معاملات لم تصل، فالعلاج إيصالها.

**التعديل:** الدالتان `addCorrectiveTransactionsForPeerTruth` و`addCorrectiveTransactionsForSelectedPeerTruth` تُرجعان 0 دائماً وتنفّذان:

```dart
Future<void> _pullFromPeerTruth(Set<String> customerSyncUuids) async {
  if (customerSyncUuids.isEmpty) return;
  _peerNotificationController.add(
      '📥 جاري سحب ما ينقص هذا الجهاز من السحابة، وطلب إعادة الرفع من الجهاز الآخر...');
  try {
    await _sync.performFullCatchUp();
  } catch (_) {}
  await requestPeerToUploadCustomers(customerSyncUuids);
  await _publishLocalState();
  await recompute();
}
```

### 13.3 إعادة رفع معاملات عميل بطلب النظير

في `reuploadLocalCustomerTransactionsToPeer`: كانت تضع `is_uploaded = 0` لكل معاملات العميل (حتى معاملات الأجهزة الأخرى والمحذوفة). صارت لمعاملات هذا الجهاز النشطة فقط:

```dart
await db.update('transactions', {'is_uploaded': 0},
  where: 'customer_id = ? AND (is_created_by_me = 1 OR is_created_by_me IS NULL) '
      'AND (is_deleted IS NULL OR is_deleted = 0)',
  whereArgs: [customerId]);
```


### 13.4 ⚠️ ما لم يُنقل إلى كود التطبيق: المقارنة مع كل الأجهزة (سيناريو 23)

في المطابقة الحية بين 10 أجهزة، كل جهاز يقارن نفسه بجهاز واحد فقط (المختار). النتيجة: 9 أزواج مُقارنة من 45 ممكنة، ولا أحد يقارن D5 بـ D7. هذه مشكلة **تغطية أداة تشخيص**، لا مشكلة أرصدة. أُصلحت في المحاكي (كل جهاز يقارن مع كل المدعوين)، **لكنها لم تُنقل إلى `LiveMatchService` في التطبيق**؛ الشاشة ما زالت تقارن مع جهاز مختار واحد. إن أردتها: اجعل `_onPeerState` يحتفظ بخريطة `deviceId → _PeerState` لكل المدعوين، واجعل `recompute` يبني مقارنة لكل نظير.


### 13.5 قراءة الأجهزة المتصلة بلا إنترنت (اكتُشف باختبار الكود الحقيقي)

`getOnlineDevices` تقرأ مجموعة `devices` احتياطاً إن كان الكاش اللحظي فارغاً. بلا إنترنت ترمي القراءة، ومستدعوها (`recompute` وغيرها) كثيراً ما يُطلقون بلا انتظار (`unawaited`) فيصير خطأً غير ممسوك. الاحتياط صار داخل `try/catch` ويعيد الجهاز الحالي وحده عند الفشل:

```dart
try {
  return await _devices.getOnlineDevices();
} catch (e) {
  print('⚠️ المطابقة الحية: تعذّرت قراءة الأجهزة المتصلة: $e');
  final myId = _myId;
  return [
    if (myId != null) {'deviceId': myId, 'deviceName': 'هذا الجهاز', 'isCurrentDevice': true},
  ];
}
```
---

<a id="14"></a>
## 14. التنظيف الذكي SmartPipe والإقرارات ACK

### 14.1 SmartPipe: لا حذف لنسخة لم يقرأها الجميع

**الملف:** `lib/services/firebase_sync/smart_pipe_cleanup_service.dart`

**المشاكل:**
1. **إقرار قديم يكفي لحذف نسخة أحدث:** جهاز قرأ النسخة الأولى من معاملة وأقرّ. ثم عُدّلت (أو كُتب عليها شاهد حذف). SmartPipe يرى «كل الأجهزة أقرّت» فيحذف المستند، والجهاز الذي لم يقرأ النسخة الجديدة **يفوته التعديل أو الحذف إلى الأبد**.
2. **سباق بين الفحص والحذف:** بين قراءة المستند وحذفه قد يكتب جهاز شاهد حذف جديداً؛ الحذف يمحوه.
3. **حذف شواهد حذف العملاء بعد المدة دون أي تأكيد قراءة:** جهاز غاب أطول من المدة يبقى العميل حياً عنده.
4. **حذف الإقرارات القديمة:** الإقرار دليل تعتمده المطابقة المحصّنة (القسم 11) على أن المعاملة كانت في السحابة.

**التعديل في `_cleanupCollection`:** بدل مجموعة «الأجهزة التي أقرّت»، خذ **أحدث وقت قراءة لكل جهاز**، واشترط أن يكون ≥ `uploadedAt` للنسخة الحالية، ثم احذف **داخل معاملة Firestore** بشرط أن الإصدار لم يتغير:

```dart
final readBy = <String, DateTime>{};
for (final a in acksSnapshot.docs) {
  final ad = a.data();
  final dev = ad[ackDeviceField] as String? ?? '';
  final at = _ackTime(ad);
  if (dev.isEmpty || at == null) continue;
  final prev = readBy[dev];
  if (prev == null || at.isAfter(prev)) readBy[dev] = at;
}

bool allRead = true;
for (final device in eligibleDevices) {
  if (device == senderId) continue;
  final at = readBy[device];
  if (at == null || at.isBefore(uploadedAt)) { allRead = false; break; }
}

if (allRead) {
  final expected = data[timestampField];
  final removed = await _firestore!.runTransaction<bool>((txn) async {
    final cur = await txn.get(doc.reference);
    final cd = cur.data();
    if (cd == null || cd[timestampField] != expected) return false; // تغيّر بعد الفحص
    txn.delete(doc.reference);
    return true;
  });
  if (removed) deleted++; else skipped++;
} else {
  skipped++;
}
```

ودالة وقت الإقرار:

```dart
/// readAt (توقيت الخادم). الإقرارات القديمة تحمل receivedAt بساعة الجهاز فقط؛
/// نطرح منها هامشاً كي لا تجعلها ساعة متقدمة تبدو أحدث من نسخة لم تُقرأ.
static DateTime? _ackTime(Map<String, dynamic> ack) {
  final r = ack['readAt'];
  if (r is Timestamp) return r.toDate();
  if (r is String) {
    final d = DateTime.tryParse(r);
    if (d != null) return d;
  }
  final rec = ack['receivedAt'];
  if (rec is String) {
    final d = DateTime.tryParse(rec);
    if (d != null) return d.subtract(const Duration(minutes: 10));
  }
  return null;
}
```

**وفي `_runCleanup`:** احذف استدعاء `_cleanupDeletedCustomers` و`_cleanupOrphanedAcks` (وحُذفت الدالتان نفسهما).

**وشواهد حذف المعاملات لا تُحذف أبداً (اكتُشف باختبار الكود الحقيقي):** «كل من يعرف المستند قرأه» لا يشمل جهازاً ينضم لاحقاً، ولا جهازاً يستعيد نسخة احتياطية أقدم من الحذف. كلاهما يستلم الدين حياً (من حزمة الفاتورة أو من نسخته القديمة)، وإعادة البث للجهاز الجديد لا تحمل إلا النشط، فلا يصله الحذف أبداً. مثال فعلي: جهاز انضم بعد حذف عميل فظهر عنده دين فاتورة 3000 أُبطلت. التعديل: معامل `bool keepTombstones = false` في `_cleanupCollection`، وفي أول الحلقة:

```dart
if (keepTombstones && (data['isDeleted'] == true || data['is_deleted'] == 1)) continue;
```

ويُمرَّر `keepTombstones: true` لمجموعة `transactions` فقط. الشواهد صغيرة، ولا تنشأ إلا من حذف العملاء.

**وفي `markTransactionRead` و`markInvoiceRead`:** احذف الحقل `'groupSecret': groupSecret` (كان يكشف السرّ في كل إقرار). يبقى `'readAt': FieldValue.serverTimestamp()`.

### 14.2 الإقرار يحمل وقت الخادم

**الملف:** `lib/services/firebase_sync/transaction_ack_service.dart` — الدالة `sendAck`:

```dart
await _firestore!.collection('transaction_acks').doc(ackId).set({
  'transactionUuid': transactionUuid,
  'senderDeviceId': senderDeviceId,
  'receiverDeviceId': _deviceId,
  'receiverDeviceName': _deviceName,
  'receivedAt': now.toIso8601String(),
  // توقيت الخادم: SmartPipe لا يحذف نسخة إلا إن قرأها كل جهاز بعد رفعها
  'readAt': FieldValue.serverTimestamp(),
  'status': status.name,
  'errorMessage': errorMessage,
  'createdAt': DateTime.now().toIso8601String(),
}, SetOptions(merge: true)); // merge: نفس المستند قد يكتبه markTransactionRead
```

### 14.3 متى يُرسل الإقرار (مهم للصحة)

القاعدة: **لا يُرسل الجهاز إقراراً إلا بعد أن يطبّق النسخة فعلاً.** في خدمة المزامنة، `_sendAckFor` تُستدعى فقط: بعد إدراج معاملة جديدة، وبعد تحديث معاملة موجودة، وبعد تطبيق شاهد حذف على معاملتي. لا إقرار عند الرفض أو التخطي. فغياب الإقرار يؤخّر الحذف فقط (آمن)، أما إقرار بلا تطبيق فيسمح بحذف نسخة لم تُخزَّن (خطير).

### 14.4 إيقاف التنظيف التلقائي للإقرارات

في `FirebaseSyncService._periodicCleanup` احذف `await _ackService?.cleanupOldAcks();`. (الإقرارات صغيرة جداً؛ بقاؤها يزيد التخزين قليلاً مع الوقت.)

---

<a id="15"></a>
## 15. التدقيق الذاتي ReconciliationService

**الملف:** `lib/services/firebase_sync/reconciliation_service.dart` — الدالة `runSelfAudit`.

**المشكلة 1:** الطبقة الأولى كانت تجمع `where('isDeleted', isEqualTo: false)`. الوثائق الحية لم تعد تحمل الحقل، فالتجميع يعدّ **صفراً** دائماً ← كل عميل يبدو مختلفاً ← ينزل للطبقة الثانية المكلفة ← إنذار كاذب.

**التعديل:** الكل − المحذوف:

```dart
final base = fs.collection('transactions').where('customerSyncUuid', isEqualTo: uuid);
final all = await base.aggregate(count(), sum('amountChanged')).get(source: AggregateSource.server);
final del = await base.where('isDeleted', isEqualTo: true)
    .aggregate(count(), sum('amountChanged')).get(source: AggregateSource.server);
cloudCount = (all.count ?? 0) - (del.count ?? 0);
cloudSum = (all.getSum('amountChanged')?.toDouble() ?? 0.0) -
    (del.getSum('amountChanged')?.toDouble() ?? 0.0);
```

**المشكلة 2:** في الطبقة الثانية، شاهد حذف في السحابة لمعاملة ما زالت نشطة محلياً كان يُعدّ «ناقصاً في السحابة»، فيحاول رفعها — أي **إحياءها**.

**التعديل:** اجمع شواهد الحذف في خريطة منفصلة، وطبّقها قبل محاولة الرفع:

```dart
final cloudUuids = <String, Map<String, dynamic>>{};
final cloudTombstones = <String, Map<String, dynamic>>{};
for (final doc in cloudDocs.docs) {
  final data = doc.data();
  if (data['isDeleted'] == true) { cloudTombstones[doc.id] = data; continue; }
  cloudUuids[doc.id] = data;
}
// ...
if (repair) {
  for (final u in missingInCloud.toList()) {
    final tomb = cloudTombstones[u];
    if (tomb == null) continue;
    await _sync.applyRemoteTransaction(u, tomb); // الحذف نهائي
    missingInCloud.remove(u);
    fetched++;
  }
  // ... باقي العلاج كما كان
}
```

**نفس الإصلاح** في `discrepancy_resolution_service.dart` (فلتر `isNotEqualTo: true` استُبدل بفلترة في الذاكرة `doc.data()['isDeleted'] != true`).

---

<a id="16"></a>
## 16. الأمان: سرّ المجموعة والتوقيع والوضع الصارم

### 16.1 المشكلة (سيناريو 28)

- قواعد Firestore المنشورة تسمح لأي مستخدم مسجّل بالكتابة (`allow read, write: if request.auth != null`).
- **سرّ المجموعة كان يُكتب نصاً** في كل وثيقة عميل ومعاملة وجهاز وإقرار وعملية (`'groupSecret': _groupSecret`). من يقرأ أي وثيقة يعرفه.
- التوقيع كان يغطي `(المعرّف|الجهاز|checksum)`، والمستقبِل لا يستطيع إعادة حساب الـ checksum من المستند، فيمكن تغيير **المبلغ** مع إبقاء التوقيع صحيحاً.
- التحقق كان «تحذيراً فقط».

النتيجة: مستخدم يملك إعدادات Firebase يكتب معاملة مزوّرة فتُقبل على كل الأجهزة.

### 16.2 التعديلات

**(أ) حذف السرّ من كل كتابة سحابية.** ابحث في المشروع عن `groupSecret'` واحذف كل كتابة له في مستند:
- `firebase_sync_service.dart`: `uploadCustomer`, `uploadTransaction`, `_forceUploadCustomer`, `_forceUploadTransaction`, طلب التمهيد `bootstrap_requests`, وثيقة الجهاز في `registerDevice` (استُبدل بـ `secretFingerprint`).
- `smart_pipe_cleanup_service.dart`: `markTransactionRead`, `markInvoiceRead`.
- `sync_operation_tracker.dart`: `_uploadOperation` (وحُذف الحقل `_groupSecret` غير المستخدم).
- `invoice_resolution_service.dart` (غير مستخدم في هذا المشروع، لكنه صُحّح).

**(ب) توقيع يغطي الحقول المالية** (في خدمة المزامنة):

```dart
String _canonAmount(dynamic v) =>
    v is num ? v.toDouble().toStringAsFixed(2) : (v?.toString() ?? '');

String _canonicalFor(String uuid, Map<String, dynamic> d, {bool isCustomer = false}) {
  final del = d['isDeleted'] == true ? '1' : (d['isDeleted'] == false ? '0' : '');
  if (isCustomer) return 'c|$uuid|$del|${d['deviceId'] ?? ''}';
  return 't|$uuid|${d['customerSyncUuid'] ?? ''}|${_canonAmount(d['amountChanged'])}|$del|${d['deviceId'] ?? ''}';
}

String? _signDoc(String uuid, Map<String, dynamic> doc, {bool isCustomer = false}) {
  final key = _groupSecretKey;
  if (key == null || key.isEmpty) return null;
  return SyncSecurity.signData(_canonicalFor(uuid, doc, isCustomer: isCustomer), key);
}

String _secretFingerprint() {
  final key = _groupSecretKey;
  if (key == null || key.isEmpty) return '';
  return sha256.convert(utf8.encode('fp|$key')).toString().substring(0, 16);
}
```

كل مستند يُرفع: `doc['signature'] = _signDoc(...)` **بعد** بناء كل حقوله (بما فيها `isDeleted`).

**(ج) التحقق عند الاستقبال** — يرفض فقط في الوضع الصارم:

```dart
Future<bool> _verifyIncomingSignature(String uuid, Map<String, dynamic> data,
    {bool isCustomer = false}) async {
  bool strict = false;
  try { strict = await FirebaseSyncSecuritySettings.isStrictSignatureEnabled(); } catch (_) {}
  final key = _groupSecretKey;
  if (!strict || key == null || key.isEmpty) return true;
  final sig = data['signature'] as String?;
  final ok = sig != null &&
      SyncSecurity.verifySignature(_canonicalFor(uuid, data, isCustomer: isCustomer), sig, key);
  if (!ok) {
    SyncDiagnostics.log('security', 'رُفض مستند غير موقّع: $uuid من ${data['deviceId']}');
  }
  return ok;
}
```

يُستدعى في أول `_applyCustomerChange` و`_applyTransactionChange`.

**(د) إعداد الوضع الصارم** — `lib/services/firebase_sync/firebase_sync_config.dart` داخل `FirebaseSyncSecuritySettings`:

```dart
static const String _strictSignatureKey = 'firebase_sync_strict_signature';

static Future<bool> isStrictSignatureEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_strictSignatureKey) ?? false; // معطّل افتراضياً
}

static Future<void> setStrictSignatureEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_strictSignatureKey, enabled);
}
```

**(هـ) فحص تطابق السرّ بين الأجهزة** (في خدمة المزامنة):

```dart
/// أسماء الأجهزة (غير الخارجة عن الخدمة) التي لا تطابق بصمة سرّها سرّ هذا الجهاز،
/// أو لم تُحدَّث بعد فلا تنشر بصمة. الوضع الصارم آمن فقط إن كانت القائمة فارغة.
Future<List<String>> devicesWithMismatchedSecret() async {
  if (_firestore == null) throw StateError('المزامنة غير مُهيّأة');
  final mine = _secretFingerprint();
  final snap = await _firestore!.collection('devices').get(const GetOptions(source: Source.server));
  final out = <String>[];
  for (final d in snap.docs) {
    if (d.id == _deviceId) continue;
    final data = d.data();
    if (data['isRetired'] == true) continue;
    if (mine.isEmpty || data['secretFingerprint'] != mine) {
      out.add((data['deviceName'] as String?) ?? d.id);
    }
  }
  return out;
}
```

**(و) مفتاح في الإعدادات** — `lib/screens/firebase_sync_settings_screen.dart`، في بطاقة «إعدادات الأمان»:
- متغير حالة `bool _strictSignature = false;` يُحمَّل مع بقية الإعدادات بـ `isStrictSignatureEnabled()`.
- `SwitchListTile` بعنوان «رفض البيانات غير الموقّعة (الوضع الصارم)».
- عند التفعيل:
  1. استدعِ `devicesWithMismatchedSecret()` (إن فشل: رسالة «يلزم اتصال» ولا تفعيل).
  2. إن كانت القائمة غير فارغة: نافذة «لا يمكن التفعيل الآن» تعرض أسماء الأجهزة المختلفة، ولا تفعيل.
  3. وإلا: نافذة تأكيد تشرح الشروط، ثم `setStrictSignatureEnabled(true)`.

### 16.3 ما يجب أن يفعله صاحب المحل (خارج الكود)

1. **غيّر سرّ المجموعة**؛ القديم كان مكشوفاً في السحابة. أدخل السرّ الجديد نفسه على كل الأجهزة (شاشة إعداد Firebase المخصص تحفظه بـ `SyncSecurity.saveSecretKey`).
2. حدّث كل الأجهزة، وافتح كل واحد مرة واحدة متصلاً (لتنشر بصمتها)، ثم فعّل الوضع الصارم.
3. **شدّد قواعد Firestore**: حالياً أي حساب مسجّل يكتب أي شيء. الأفضل تقييد الكتابة بحسابات المحل فقط.

---

<a id="17"></a>
## 17. ترتيب التطبيق على مشروع آخر + قائمة تحقق

طبّق بهذا الترتيب (كل خطوة تعتمد على ما قبلها):

| # | الخطوة | الأقسام |
|---|---|---|
| 1 | الأعمدة الجديدة في المخطط | 3 |
| 2 | ملف `CustomerVisibility` | 4 |
| 3 | تعديلات DAO (إضافة/تعديل/تحويل معاملة، حذف/إعادة إنشاء عميل، تعديل فاتورة) | 5 |
| 4 | الحد، حقول الاستعادة، التوقيع (الدوال فقط، الوضع الصارم معطّل) | 7.1، 7.2، 16.2 (ب، ج، د، هـ) |
| 5 | الرفع: `uploadCustomer`، `uploadTransaction`، `_ownedPendingWhere`، `uploadAllOwnedPending`، `syncCustomerDeletionNow`، `syncCustomerNow`، `_syncPendingChanges`، الرفع القسري | 7.10–7.14، 7.18 |
| 6 | الاستقبال: المستمعون، `_applyCustomerChange`، الدوال المساعدة، `_applyTransactionChange`، اليتيمات، السحب الكامل | 7.5–7.8، 7.17 |
| 7 | الدمج بالاسم | 7.9 |
| 8 | DatabaseService (حذف عميل، رفع فوري، حذف فاتورة، الاستعادة، الختم) + النسخ الاحتياطي + المتحكم | 6 |
| 9 | التهيئة والمزامنة الخلفية والتمهيد وإعادة البث | 7.3، 7.4، 7.16 |
| 10 | الفواتير + الحارس المحاسبي | 8، 9 |
| 11 | المراقب | 10 |
| 12 | المطابقة المحصّنة + تعطيل القرارات + المطابقة الحية | 11، 12، 13 |
| 13 | SmartPipe والإقرارات والتدقيق وعدّ المستندات | 14، 15، 7.15 |
| 14 | حذف السرّ من السحابة + مفتاح الوضع الصارم | 16 |

### قائمة تحقق بعد التطبيق

- [ ] ابحث في المشروع: لا يوجد أي `'groupSecret':` يُكتب في مستند Firestore.
- [ ] ابحث: لا يوجد `'isDeleted': false` أو `'isDeleted': isTxDeleted` يُكتب لمعاملة (فقط `true` عند الحذف).
- [ ] ابحث: لا يوجد `isNotEqualTo: true` أو `isEqualTo: false` على `isDeleted` في استعلامات Firestore.
- [ ] ابحث: لا يوجد `DocumentChangeType.removed` يؤدي لحذف محلي.
- [ ] ابحث: كل `return true` عند حجب حد المعدل صار `return false`.
- [ ] كل مسار يستبدل ملف قاعدة البيانات يستدعي `flagDatabaseRestored` أو `markDatabaseRestored`.
- [ ] كل تعديل محلي لمعاملة يضع `is_uploaded = 0` و`restored_mark = 0`.
- [ ] كل تعديل محلي لفاتورة يرفع النسخة (لا ينزلها) ويضع `is_synced = 0` و`restored_mark = 0`.
- [ ] كل تغيير في معاملات عميل يتبعه `CustomerVisibility.apply`.
- [ ] `flutter analyze` بلا أخطاء، والتطبيق يُبنى.

### اختبار يدوي على أجهزة حقيقية (قبل البيع)

جهّز جهازين أو ثلاثة على نفس مشروع Firebase، ثم:
1. أضف معاملة على A ← تظهر على B خلال ثوانٍ.
2. عدّل مبلغ معاملة A من A ← يتغير على B. **وعدّلها على عميل أنشأه B** ← يتغير على B.
3. حوّل نوع معاملة (دين↔تسديد) ← يتغير على B.
4. افصل الإنترنت عن A، أضف وعدّل 20 معاملة، أعد الإنترنت ← كلها تصل.
5. احذف عميلاً من A ← يختفي على B. وأعد تشغيل A ← لا يعود.
6. احذف عميلاً على A بينما B أوفلاين يضيف عليه بيعاً ← بعد الاتصال: العميل ظاهر على الجهازين وعليه البيع الجديد فقط.
7. فاتورة دين أوفلاين ثم حوّلها لنقد ← الدين يختفي على كل الأجهزة، وبعد إعادة التشغيل لا يعود.
8. عميلان بنفس الاسم على جهازين أوفلاين ← بعد الاتصال عميلان منفصلان بديون صحيحة.
9. خذ نسخة احتياطية من A، أضف معاملات، استعد النسخة ← A يستعيد المعاملات من السحابة، ولا يرفع القديم فوق الجديد.
10. «بياناتي صحيحة» على A بينما B لديه تسديد لم يصل A بعد ← التسديد **لا يُمحى**.

---

<a id="18"></a>
## 18. جدول: كل سيناريو ← الإصلاح الذي يحله

| # | السيناريو | القديم | الإصلاح (القسم) |
|---|---|---|---|
| 01 | 10 أجهزة، كل جهاز 20 معاملة | ✅ | — |
| 02 | معاملة تصل قبل عميلها | ✅ | — |
| 03 | نفس المعاملة تصل 3 مرات | ✅ | — |
| 04 | المالك يعدّل مبلغ معاملته | ❌ 9 | رفع موحّد + رفع فوري (7.12، 6.2، 10) |
| 05 | جهاز مطفأ يعود فيجد تعديلاً | ❌ 9 | نفسه + الإصدار (7.8) |
| 06 | جهازان أوفلاين 30 معاملة | ✅ | — |
| 07 | زمن وصول 30 معاملة أوفلاين | ✅ (93 ث) | الحد + الفشل السريع أوفلاين (7.1، 7.10) ← 7 ث |
| 08 | زمن وصول 1500 معاملة | ✅ (86 د) | الحد (7.1) ← 6 د |
| 09 | تعديل أوفلاين بعد إنشاء أوفلاين | ❌ 9 | قراءة حديثة + CAS (7.11) |
| 10 | جهاز غاب 40 يوماً ورفض القديم مفعّل | ❌ 1 | التنبيه بدل الرفض (7.8-2) |
| 11 | انقطاع أثناء الرفع | ✅ | — |
| 12 | نفس الاسم لشخصين مختلفين | ❌ 20 | الهوية فقط (7.6-د، 8.5، 11) |
| 13 | نفس الاسم مرتين لنفس الشخص | ❌ 18 | الدمج للسجلات بلا هوية فقط (7.9) |
| 14 | تعديل اسم على جهازين معاً | ✅ | — |
| 15 | حذف عميل (عاصفة 9983 كتابة) | ❌ 2 | شواهد الحذف بلا ارتداد (6.1، 7.6-ج، 7.7، 7.10) |
| 16 | حذف ثم إعادة تشغيل الحاذف | ❌ 1 | شواهد + مستنداتي (7.5، 7.7) |
| 17 | زر حذف السحابة بالكامل | ❌ 19 | الاختفاء ليس حذفاً (7.5) |
| 18 | فاتورة دين أوفلاين ← نقد ← إعادة تشغيل | ❌ 9 | قناة الحزمة (7.8-4، 7.11، 8.4) |
| 19 | تعديل مبلغ فاتورة الدين | ✅ | — |
| 20 | حذف فاتورة دين | ❌ 10 | حذف منطقي يتزامن (6.3، 8.1، 9) |
| 21 | «بياناتي صحيحة» مع تلف قديم | ✅ | (يبقى ناجحاً بالقواعد الجديدة) |
| 22 | «بياناتي صحيحة» والمرجع متأخر | ❌ 10 | دليل الحياة + لا قرارات (11، 12) |
| 23 | مطابقة حية: مع مَن يقارن كل جهاز؟ | ❌ 1 | في المحاكي فقط (13.4) |
| 24 | «الجهاز الآخر صحيح» ← معاملة تصحيحية | ❌ 10 | لا معاملات تصحيحية (13.2) |
| 25 | مطابقة حية مع عميلين بنفس الاسم | ❌ 21 | المقارنة بالهوية (13.1) |
| 26 | تنظيف السحابة ثم استعادة نسخة قديمة | ❌ 2 | وضع الاستعادة + التمهيد (6.4، 7.2، 7.16) |
| 27 | جهاز جديد بعد التنظيف ولديه معاملة | ❌ 1 | التمهيد بلا شرط الدفتر الفارغ + إعادة بث الكل (7.16) |
| 28 | معاملة مزوّرة من مستخدم مجهول | ❌ 11 | التوقيع + الوضع الصارم (16) — **يتطلب التفعيل** |
| 29 | قرار إبطال مزوّر يمسح تسديداً | ❌ 10 | تعطيل القرارات (12) |
| 30 | كشف مطابقة 6000 معاملة (2.4 MiB) | ❌ 1 | كشف مجزّأ (11) |
| 32 | تحويل نوع معاملة على المالك | ❌ 9 | `is_uploaded=0` + رفع فوري (5.3، 6.2) |
| 33 | تعديل معاملة D2 على عميل D1 | ❌ 9 | رفع موحّد + `syncCustomerNow` (7.12، 7.13) |
| 34 | تحويل نوع معاملة جهاز آخر | ❌ 9 | منع التحويل لغير المالك (5.3) |
| 35 | فاتورة دين معلّقة (مسوّدة) | ❌ 9 | المعلّقة لا تُنتج ديناً (8.6، 9.2) |
| 36 | أول فاتورة على جهازين من قاعدة فارغة | ❌ 10 | معرّف تسوية عالمي + منع الكتابة فوق صف آخر (9.1، 8.4) |
| 37 | فاتورة من D2 لعميل D1 ← D1 يفقد ملكيته | ❌ 2 | لا مسّ لـ `is_created_by_me` + لا رفع لعميل لا أملكه (7.6-و، 7.10) |
| 38 | نفس الاسم والهاتف على جهازين (UNIQUE) | ❌ 20 | الهاتف المميّز (7.7، 8.5) |
| 39 | عميل محذوف ثم جديد بنفس الاسم والهاتف | ❌ 9 | نفسه (7.7) |
| 40 | معاملة قديمة التاريخ ← لا يمكن الإضافة | ❌ 1 | الرصيد من المجموع (5.1) |
| 41 | حذف عميل بينما جهاز أوفلاين يبيع عليه | ❌ 10 | قاعدة الظهور + شواهد لكل معاملة (4، 7.7) |
| 42 | موبايل أوفلاين: إنشاء ثم تعديل ثم عودة | ✅ | — |
| 43 | التطبيق يُقتل أثناء الرفع | ✅ | — |
| — | فوضى: فاتورة عُدّلت بعد استعادة نسخة | ❌ (seed 20001) | `restored_mark` للفواتير (8.4، 9.2، 7.2) |
| 31 | فوضى عشوائية (20 تجربة × 400 عملية) | ❌ 20/20 | كل ما سبق |

(الأرقام بعد ❌ = عدد الأخطاء المكتشفة في السيناريو، مثل «جهاز يعرض رصيداً خاطئاً».)

---

<a id="19"></a>
## 19. المحاكِي: كيف تشغّله وكيف تستخدمه في مشروع آخر

**المكان:** `tools/sync_sim/` (بايثون 3، بلا مكتبات خارجية).

| الملف | الدور |
|---|---|
| `engine.py` | محرك الزمن والأحداث، وسحابة Firestore وهمية (set/merge/delete/query/listen/transactions)، والشبكة (انقطاع، ضياع أثناء الإرسال، طابور كتابات الموبايل). |
| `device.py` | نموذج كامل لجهاز: قاعدة SQLite حقيقية في الذاكرة + كل منطق المزامنة، بنسختين (الحالي والمُصلَح) تُختاران بمفاتيح `fx('...')`. |
| `world.py` | «الحقيقة» (ما يجب أن تكون عليه الأرصدة)، ومجموعة الإصلاحات `ALL_FIXES`، والتحقق من كل الأجهزة. |
| `scenarios.py` | السيناريوهات 01–43. |
| `run.py` | المشغّل. |
| `debug_chaos.py` | تشخيص تجربة فوضى فاشلة: يطبع العميل المختلف ومعاملاته على كل جهاز وفي السحابة. |

**التشغيل:**

```bash
cd tools/sync_sim
python run.py                                  # كل السيناريوهات: الحالي مقابل المُصلَح + 20 تجربة فوضى
python run.py --only 09 18                     # سيناريوهات محددة
python run.py --mode fixed                     # المُصلَح فقط
python run.py --only 31 --mode fixed --chaos 100 --seed0 10000                  # فوضى فقط، بذور جديدة
python run.py --only 31 --mode fixed --chaos 100 --seed0 20000 --profile harsh  # شبكة قاسية
python run.py --ablate                         # أي إصلاح يحل أي سيناريو
python debug_chaos.py 20001 fixed "" 400 0 harsh   # تشخيص تجربة بعينها
```

**لاستخدامه مع مشروع آخر:** المحاكي نموذج لكود **هذا** المشروع. إن كان منطق المشروع الآخر مطابقاً (نفس البنية)، فنتائجه تنطبق. وإن اختلف في شيء، عدّل الدالة المقابلة في `device.py` لتطابق كود المشروع الآخر، ثم شغّل السيناريوهات والفوضى. **أي تعديل على منطق المزامنة مستقبلاً: عدّله في `device.py` أولاً (بمفتاح `fx` جديد)، وشغّل 700 تجربة فوضى، ثم انقله لـ Dart.**

---

<a id="19b"></a>
## 19.ب اختبار كود التطبيق الحقيقي (test/sync_harness)

المحاكي (القسم 19) نموذج للكود بلغة بايثون. أما هذه الأداة فتشغّل **كود Dart الحقيقي نفسه**: `DatabaseService` و`AppProvider` و`InvoiceController` و`FirebaseSyncService` وكل خدمات المزامنة، بلا أي تعديل، على عدة «أجهزة وهمية» داخل اختبار Flutter واحد.

**كيف تعمل:**

| الملف | الدور |
|---|---|
| `cloud.dart` | «سحابة Firestore وهمية» في الخيط الرئيسي: كتابة ودمج وحذف ووقت الخادم، واستعلامات وترتيب وعدّ وجمع، ومعاملات ذرية، ودفعات، ومستمعون، وانقطاع إنترنت لكل جهاز (القراءة تفشل، والكتابة تنتظر حتى يعود الاتصال كـ Firestore على سطح المكتب). |
| `remote_firestore.dart` | طبقة «منصة» داخل كل جهاز: مكتبة `cloud_firestore` الحقيقية تستدعيها، وهي ترسل الطلبات للسحابة الوهمية. |
| `fake_platforms.dart` | منصات وهمية: Firebase الأساسية، والمصادقة، وفحص الإنترنت، ومسارات الملفات. |
| `device.dart` | «جهاز وهمي» في خيط منفصل بقاعدة SQLite حقيقية خاصة به. ينفّذ أفعال المستخدم عبر نفس دوال الشاشات: `AppProvider.addCustomer/addTransaction/deleteCustomer`، و`DatabaseService.updateTransaction/convertTransactionType`، و`InvoiceController.saveInvoice` ثم رفع الحزمة كما تفعل الشاشة. |
| `harness.dart` | المتحكّم: يشغّل الأجهزة، ويحفظ «الحقيقة»، وينفّذ الفوضى العشوائية، ويعيد تشغيل الأجهزة (قتل مفاجئ مع نسخة SQLite لحظية)، ويفحص كل جهاز مقابل الحقيقة. |
| `smoke_test.dart`، `chaos_test.dart` | الاختبارات. |

**ملاحظة تقنية مهمة:** مكتبة SQLite في بيئة اختبار ويندوز تُفسد اتصالات خيط إذا استخدمها خيط آخر في نفس الوقت. لذلك تمرّ قواعد كل الأجهزة عبر **خادم SQLite واحد** في خيط واحد (نفس آلية `sqflite_common_ffi` الداخلية)، ولكل جهاز ملفه الخاص.

**التشغيل:**

```bash
flutter test test/sync_harness/smoke_test.dart
```

```bash
flutter test test/sync_harness/invoice_math_test.dart test/sync_harness/stock_migration_test.dart test/sync_harness/product_merge_test.dart test/sync_harness/residual_risks_test.dart
```

```bash
flutter test test/sync_harness/chaos_test.dart --dart-define=SEEDS=20 --dart-define=DEVICES=10 --dart-define=OPS=400
```

```bash
flutter test test/sync_harness/chaos_test.dart --dart-define=SEEDS=20 --dart-define=DEVICES=10 --dart-define=OPS=400 --dart-define=HARSH=true
```

- `SEEDS` عدد التجارب، `SEED0` أول بذرة، `DEVICES` عدد الأجهزة، `OPS` عدد العمليات لكل تجربة.
- `HARSH=true`: يضيف تنظيف السحابة الذكي بمدة صفر أيام، ونسخاً احتياطياً واستعادة، و«بياناتي صحيحة»، وفواتير معلّقة، وانضمام أجهزة جديدة متأخراً.
- `DEVLOG=true`: كل جهاز يكتب سجله فوراً في ملف `device.log` داخل مجلده المؤقت (للتشخيص).
- عند أي فشل يطبع الاختبار شرحاً كاملاً للعميل المختلف: الحقيقة، ثم فواتيره ومعاملاته على كل جهاز، ثم ما في السحابة.

**النتيجة على الكود النهائي:**

| التجارب | النتيجة | ما مرّت به |
|---|---|---|
| فوضى قاسية، بذور 300–339 و340–399 وإعادة 318 | **101 من 101** بلا فرق حسابي (تجربة واحدة أعيدت بعد تصحيح «الحقيقة» في الأداة لا في التطبيق) | 68 استعادة نسخة احتياطية، 845 تنظيف سحابي بمدة صفر، 87 انضمام جهاز متأخر، 377 «بياناتي صحيحة»، نحو 571 ألف كتابة سحابية |
| فوضى عادية، بذور 100–119 | **20 من 20** | انقطاع إنترنت وإعادة تشغيل مفاجئة |
| أخطاء غير ممسوكة | **صفر** في كل ما سبق | — |
| **المرحلة الثانية (الكود النهائي):** فوضى قاسية، بذور 700–719، مع المخزون والإرجاع ونقل الفواتير بين العملاء | **20 من 20** | 14 استعادة، 135 تنظيفاً، 15 انضماماً متأخراً، 77 «بياناتي صحيحة»، 148 منتجاً، 2943 وحدة مبيعة، 4405 وحدة حركات، نحو 102 ألف كتابة سحابية |
| فوضى عادية، بذور 800–809 | **10 من 10** | 76 منتجاً، 1235 وحدة مبيعة، 1814 وحدة حركات، 53 إرجاعاً بتعديل الفاتورة |
| اختبار حسابات الفاتورة (`invoice_math_test.dart`) واختبار ترقية المخزون (`stock_migration_test.dart`) | **ناجحان** | — |
| **المرحلة الثالثة (بعد إصلاحات المراجعة 21.6–21.8):** فوضى قاسية، بذور 900–919، ومنها أصناف بالاسم نفسه على جهازين | **20 من 20** | 11 استعادة، 127 تنظيفاً، 17 انضماماً متأخراً، 81 «بياناتي صحيحة»، 681 فاتورة، 140 منتجاً (7 نسخ مكررة الاسم)، 3132 وحدة مبيعة، 4016 وحدة حركات، نحو 107 آلاف كتابة سحابية |
| فوضى عادية، بذور 1000–1009 | **10 من 10** | 277 فاتورة، 87 منتجاً (6 نسخ مكررة الاسم)، 1384 وحدة مبيعة، 2102 وحدة حركات |
| فوضى قاسية بأصناف مكررة الاسم كثيرة (`--dart-define=TWINS=true`)، بذور 1100–1109 | **10 من 10** | 205 منتجات (**35 نسخة مكررة الاسم** دُمجت)، 9 استعادات، 66 تنظيفاً، 11 انضماماً، 332 فاتورة، نحو 53 ألف كتابة سحابية |
| اختبار الدمج (`product_merge_test.dart`، 3 سيناريوهات) + كلفة المتوسط المرجّح (في `invoice_math_test.dart`) + الترقية + الاختبار السريع | **كلها ناجحة** | — |
| **المرحلة الرابعة (المخاطر المتبقية — القسم 25، الكود النهائي):** فوضى قاسية، بذور 1700–1719 | **20 من 20** | 17 استعادة، 158 تنظيفاً، 18 انضماماً متأخراً، 65 «بياناتي صحيحة»، 687 فاتورة، 161 منتجاً، 4 تعديلات رفضها قفل الاستعادة، نحو 108 آلاف كتابة سحابية |
| فوضى عادية، بذور 1600–1609 (منها 1608 التي كشفت خلل الظهور) | **10 من 10** | 303 فواتير، 73 منتجاً (8 نسخ مكررة الاسم)، نحو 51 ألف كتابة |
| فوضى قاسية بأصناف مكررة الاسم، بذور 1400–1409 (منها 1402 و1407) | **10 من 10** | 178 منتجاً (**30 نسخة مكررة دُمجت**، واسم مكرر واحد رُفض بسباق الوصول)، 11 استعادة، 5 تعديلات مقفلة |
| `residual_risks_test.dart` (6) + الدمج (3) + الحسابات (2) + الترقية + السريع + اختبار الشريط | **14 من 14** | — |

**ما وجدته هذه الأداة ولم يجده المحاكي (19 خللاً):** الأقسام 7.1.ب، و7.5.ب، و7.16.ب (خمس مشكلات)، و8.7، و8.8، و8.9، و8.10، و8.11، و8.12، و8.13، و8.14، والقواعد 14–17 في القسم 11 (أربع مشكلات)، وشواهد الحذف الدائمة في القسم 14.1، و13.5.

**ثم في مرحلة المخزون والإرجاع وحسابات الفاتورة (القسمان 21 و22):** الخصم المزدوج للمخزون، وتعديل/حذف الفاتورة لا يصلان لمخزون الأجهزة الأخرى، والحدّ عند الصفر، والمشتريات والتعديل اليدوي لا يتزامنان، وهوية مزامنة المنتجات (رقم ترقيم الفواتير)، وتعليق التهيئة برفع المنتجات بلا إنترنت، ومنتج يصل بعد حركاته، ومنتجي لا يعود بعد الاستعادة، وسباق حذف العميل مع تحديث وارد يُحيي المعاملة (7.8.ب)، ورصيد العميل القديم عند نقل الفاتورة (22.2). كلها ناتجة عن تفاصيل لا يحويها النموذج: قيود فريدة في المخطط، وتسابق حقيقي بين عمليات غير متزامنة، وسلوك Firestore أثناء انقطاع الإنترنت.

**ثم مراجعة الكود (21.6–21.8):** بنود وحركات تصل بعد دمج نسختين من المنتج بالمعرّف الخاسر فلا تُحسب، واختيار الباقية بالوقت وحده (التساوي يُبقي نسخة مختلفة على كل جهاز)، وكلفة المتوسط المرجّح مع مخزون سالب، وقراءة كل حركات المخزون مرتين عند كل تشغيل. **وظهر أثناء إصلاحها:** نسخة محلية دُمجت قبل رفع مستندها (لا تعرف الأجهزة الأخرى معرّفها)، وشاشة تعديل منتج فُتحت قبل الدمج تعيد المعرّف القديم عند الحفظ، و**معالجة مستندات المنتجات متزامنة** (الأحدث يفشل بـ UNIQUE والأقدم يبقى للأبد — وجده اختبار الدمج الجديد، والخلل قديم).

**للضغط على دمج النسخ:** أضف `--dart-define=TWINS=true` لأمر الفوضى (أصناف جديدة أكثر، وأغلبها بالاسم نفسه لصنف على جهاز آخر).

**ثم في مرحلة المخاطر المتبقية (القسم 25):** صنفان بالاسم نفسه على جهاز واحد بسباق وصول (25.6.ب — seed=1402)، وعميل محذوف يظهر على بعض الأجهزة بصف تسوية صافيه صفر (25.6.ج — seed=1407 وseed=1608؛ خلل قديم في قاعدة الظهور). وسجلّ تقدّم الأداة صار ملفاً لكل عملية (`sync_harness_progress_<pid>.log`) — الدفعات المتوازية كانت تخلط سجلاتها — ويسجّل حفظ الفواتير ونقلها.

**كيف تُحسب «الحقيقة» في لحظات التزامن:** حذف العميل = المعاملات التي حذفها التطبيق فعلاً على ذلك الجهاز (المحذوف بعد ناقص المحذوف قبل)، لا «ما كان نشطاً قبل الاستعلام» — معاملة تصل بين اللحظتين يحذفها التطبيق وهذا صحيح. والتحويل (دين ↔ تسديد) = ناتجه الفعلي على الجهاز، لأنه يقلب ما يراه المستخدم هناك. والأداة تنتظر انتهاء تمهيد أي جهاز جديد/مستعيد قبل الفحص، وتسجّل «ما زال في التمهيد» خللاً إن لم ينته.

**لمشروع آخر:** انسخ المجلد `test/sync_harness` كما هو، وغيّر في `device.dart` أسماء الدوال التي تستدعيها الشاشات (إضافة عميل، معاملة، فاتورة…) واسم الحزمة `package:alnaser`. طبقة السحابة والمنصات لا تحتاج تغييراً ما دام المشروع يستخدم نفس مكتبات Firebase.

<a id="20"></a>
## 20. تحذيرات مهمة قبل النشر

1. **المحاكي نموذج للكود، لا الكود نفسه.** كل إصلاح نُقل إلى Dart بعناية، والتطبيق يمرّ بـ `flutter analyze` بلا أخطاء (في الملفات المعدّلة) ويُبنى بنجاح (`flutter build bundle`)، لكنه **لم يُجرَّب على أجهزة حقيقية مع Firebase**. نفّذ الاختبار اليدوي (القسم 17) قبل البيع.
2. **حدّث كل الأجهزة معاً.** جهاز يبقى على النسخة القديمة يعيد الأخطاء القديمة، مثلاً يكتب `isDeleted:false` فيمحو شاهد حذف، أو يرفع وثيقة عميل لا يملكه.
3. **الوضع الصارم معطّل افتراضياً.** سيناريو 28 (الكتابة المزوّرة) لا يُحل إلا بعد تغيير السرّ، وإدخاله على كل الأجهزة، وتفعيل الوضع الصارم. وتشديد قواعد Firestore مستحسن جداً.
4. **التخزين السحابي يزيد قليلاً:** الإقرارات وشواهد حذف العملاء لم تعد تُحذف تلقائياً (صغيرة جداً).
5. **السحب الكامل عند كل تشغيل:** صار يعمل فعلاً (كان معطّلاً بخطأ)، فيقرأ مجموعتي العملاء والمعاملات مرة عند الإقلاع. التنظيف الذكي يُبقي المجموعتين صغيرتين.
6. **أخطاء المحلل الموجودة مسبقاً:** شاشات الموردين/المثبّتين/الاستيراد بالذكاء الاصطناعي ونسخة مكررة من `smart_search` فيها أخطاء قديمة، لكنها ملفات لا يستوردها التطبيق، ولم تُمسّ.
7. **لم يُعمل commit** لأي تعديل. النسخ الأصلية في `_backup_sync_sim/`.
8. **بعد استعادة نسخة احتياطية تظهر البيانات القديمة لحظات** حتى يلحق الجهاز بالمجموعة (وضع الاستعادة). أي تعديل يجريه المستخدم في هذه اللحظات يُطبَّق على ما يراه هو: «تحويل» معاملة ظهرت 1000 (وهي عند الآخرين 300 بعد تعديل سابق) يجعلها 1000- **على كل الأجهزة**. الأجهزة تبقى متفقة (لا خلل حسابي بينها)، لكن النتيجة قد لا تكون ما قصده المستخدم. **← عولج (25.1):** السجلات المستعادة صارت مقفلة للتعديل حتى تكتمل الاستعادة، مع شريط في الشاشة الرئيسية.

---

<a id="21"></a>
## 21. المخزون المشترك: دفتر حركات بدل رقم مطلق

> **القرار (من صاحب المحل):** مخزن واحد مشترك بين كل الأجهزة، والكمية **قد تصير سالبة** (مع تنبيه في شاشة البيع حسب إعداد «السماح بالسالب»). الموردون أنفسهم لا يتزامنون — لكن **كمية** الشراء تتزامن.

### 21.1 ما كان خاطئاً (كله في الكود الأصلي)

| الخلل | النتيجة |
|---|---|
| مشغّلا SQLite (`trg_invoice_items_stock_deduct/restore`) يخصمان `quantity_individual` عند إدراج بند له `product_id`، **فوق** خصم كود التطبيق (`InventoryHelpers`) | الجهاز البائع يخصم بيع القطعة/المتر **مرتين**، والأجهزة الأخرى مرة واحدة (بنودها الواردة بلا `product_id`) ⇒ الكميات تختلف |
| الوارد من السحابة يُخصم عند الإدراج الأول فقط | تعديل فاتورة أو حذفها على جهاز لا يغيّر كمية الأجهزة الأخرى؛ وفاتورة وصلت محذوفة أصلاً كانت تُخصم |
| الخصم يتوقف عند الصفر (`InventoryHelpers`) | الكمية تتوقف على ترتيب وصول الفواتير ⇒ جهازان بنفس الفواتير يختلفان |
| الشراء، والتعديل اليدوي، والكمية من شاشة المنتج: رقم مطلق محلي | لا يصل للأجهزة الأخرى أبداً |
| شاشة تعديل المنتج تحفظ الكمية التي حُمّلت عند فتحها | بيعٌ أثناء فتح الشاشة يُمحى عند الحفظ |
| الجهاز الجديد يستلم الكمية المطلقة ثم يُعاد عليه خصم كل الفواتير القديمة | كل شيء يُخصم مرتين |
| خصم «اللفة» (متر) بلا هرمية وحدات = 1 متر للفة | كمية خاطئة حتى على جهاز واحد |
| `ProductSyncService` تميّز الأجهزة برقم ترقيم الفواتير (افتراضياً 1 للجميع) | جهازان برقم 1 يعدّ كلٌّ منهما منتجات الآخر منتجاته ⇒ **لا يصل منتج ولا تعديل منتج إطلاقاً** |

### 21.2 القاعدة الجديدة (مثل رصيد العميل = مجموع معاملاته)

```
كمية المنتج = مجموع حركات المخزون
            − مجموع بنود الفواتير المحفوظة غير المحذوفة (بالوحدة الأساسية)
```

- **حركة المخزون** (`stock_movements`): رصيد افتتاحي، شراء، إلغاء شراء، تعديل يدوي. لكل حركة معرّف فريد، **لا تُعدَّل أبداً** (التصحيح حركة جديدة)، وتصل لكل الأجهزة عبر مجموعة Firestore `stock_movements`.
- **البيع لا يكتب حركة:** بنود الفاتورة تصل لكل جهاز داخل حزمتها أصلاً. تعديل الفاتورة أو حذفها أو تعليقها ينعكس تلقائياً على كل جهاز.
- **الفاتورة المعلّقة لا تخصم** حتى تُحفظ (مثل دينها).
- **كمية البند بالوحدة الأساسية** من حقوله المحفوظة لحظة البيع (والتي تسافر في الحزمة): `quantity_large_unit × units_in_large_unit` للوحدة الكبيرة، وإلا `quantity_individual`. لا تتغير إن عُدّلت وحدات المنتج لاحقاً، وهي نفسها على كل جهاز.
- **الحساب داخل SQLite (مشغّلات):** أي مسار يكتب بنداً أو يغيّر حالة فاتورة يُبقي الكمية صحيحة — حتى الحفظ المؤقت للفاتورة المعلّقة وأي مسار لم نعرفه.

### 21.3 الملفات

**جديد:** `lib/services/database/business/stock_ledger.dart` — انسخه كما هو. فيه:
- `ensureSchema(db)`: جدول `stock_movements (movement_uuid UNIQUE, product_sync_uuid, delta, kind, note, created_at, origin_device_id, is_uploaded)` وفهارسه.
- `setupTriggers(db)`: يحذف المشغّلين القديمين، وينشئ مشغّلات إعادة الحساب: إدراج/حذف/تعديل بند، تغيّر `status` أو `is_deleted` لفاتورة، حذف فاتورة، إدراج/حذف/تعديل حركة، **وإدراج منتج أو تغيّر معرّفه** (منتج وصل بعد حركاته كان يبقى على كمية مستنده). ومشغّل يملأ `product_sync_uuid` لبند بلا معرّف (بالرقم ثم بالاسم، كالمطابقة القديمة).
- `migrate(db)`: ربط البنود القديمة بمنتجاتها، ثم `ensureOpenings`.
- `ensureOpenings(db, {onlyUuid, upload})`: لكل منتج بلا رصيد افتتاحي: رصيد = كميته الحالية + ما بيع منه ⇒ بعد الحساب تبقى الكمية المحلية كما هي (لا قفزة).
- `addMovement(db, {productSyncUuid, delta, kind, note})`، و`productSyncUuidForId`، و`recompute`، و`rekeyProduct`.

**جديد:** `lib/services/firebase_sync/stock_movement_sync_service.dart` — الرفع (`uploadPending`، مؤجَّل 800ms ليكتمل أي commit)، والاستماع، و`downloadAll(rethrowErrors)`، وتبنّي الرصيد الافتتاحي.

**الرصيد الافتتاحي** معرّفه ثابت `opening_<معرّف المنتج>`: يُرفع داخل معاملة Firestore «أنشئ إن غاب»، فأول جهاز يثبّته للمجموعة كلها، والبقية يتبنّون قيمته. المعادلة لا تحسب إلا هذا المعرّف، فلا يتكرر رصيد افتتاحي أبداً. ومنتجٌ وصل من جهاز آخر قبل رصيد منشئه يأخذ رصيداً **مؤقتاً محلياً لا يُرفع** (`is_uploaded = 2`) — لو رُفع لسبق رصيدَ المنشئ (المنشئ بلا إنترنت) بكمية قديمة من مستند المنتج.

**التعديلات:**

| الملف | التعديل |
|---|---|
| `database_migrations.dart` | `_setupDatabaseTriggers` ← `StockLedger.ensureSchema` + `setupTriggers`. ومشغّل فهرس البحث `products_au` صار `AFTER UPDATE OF name, unit` (لا إعادة فهرسة مع كل تغيّر كمية). |
| `database_service.dart` | بعد `ensureSchema` في `_initDatabase`: `await StockLedger.migrate(db);`. `insertProduct`: `ensureOpenings(onlyUuid)` (الكمية الأولى = رصيد افتتاحي يُرفع). `adjustProductStock`: `addMovement(kind: 'adjust')` بدل تحديث الكمية، ولا منع للسالب. `deleteInvoice`: حُذف إرجاع الكميات (الحذف المنطقي يكفي). |
| `product_dao.dart` | `updateProduct`: `productMap.remove('stock_quantity')` — تعديل بيانات المنتج لا يلمس الكمية. |
| `invoice_controller.dart`، `invoice_manager.dart`، `invoice_sync_service.dart` | حُذفت كل استدعاءات `InventoryHelpers` (الخصم/الإرجاع) — المشغّلات تكفي. |
| `purchase_service.dart` | الكمية بـ `addMovement(kind: 'purchase')`، والإلغاء بـ `'purchase_reverse'` (بلا حدّ عند الصفر). التكلفة كما هي. |
| `suppliers_service.dart` | زيادة الكمية بـ `addMovement(kind: 'purchase')`. |
| `product_sync_service.dart` | الهوية = `FirebaseSyncConfig.getDeviceId()`. أعمدة الجهاز فقط (عمود زائد كان يُفشل الإدراج). `last_synced_at` عند الوصول. منتج جديد وارد ⇒ `ensureOpenings(upload: false)`. منتج طوبق بالاسم فتغيّر معرّفه ⇒ `rekeyProduct` ثم `ensureOpenings(upload: false)`. **مستند منتجي** يُتجاهل فقط إن كان المنتج موجوداً هنا — وإلا يُستعاد (قاعدة استُعيدت من نسخة أقدم منه؛ كان يُتجاهل دائماً فلا يعود منتجي أبداً). `startSync`: الرفع **بلا انتظار** (`unawaited`) و`set()` بمهلة 60 ثانية — بلا إنترنت كان يحجز تهيئة المزامنة كلها (كالفواتير 8.9). المعلّق = `last_synced_at IS NULL OR sync_uuid فارغ OR (last_modified_by_device_id = أنا AND last_modified_at > last_synced_at)` — كان «كل ما عدّلتُه» فيُعاد رفع كل المنتجات عند كل تشغيل. |
| `product_dao.dart` (هوية الجهاز) | `_getDeviceIdStr` ← `FirebaseSyncConfig.getDeviceId()` (التخزين الآمن). كان يقرأ `firebase_sync_device_id` من SharedPreferences حيث لا يُحفظ أصلاً، فيرجع رقم ترقيم الفواتير، فلا يُعرف تعديلي معلّقاً للرفع. |
| `firebase_sync_service.dart` | تشغيل `StockMovementSyncService().start()` بعد محرك المنتجات؛ `uploadPending` في الدورة الخلفية ورفع المعلّق وبعد انتهاء الاستعادة؛ `downloadAll(rethrowErrors: true)` في السحب الكامل (الاستعادة والتمهيد يُبنيان عليه)، و`downloadAll()` في سحب الإقلاع. |
| `uuid_helper.dart` | `newStockMovementUuid()` (`mv_...`). |

### 21.4 بعد التحديث (مهم)

1. **حدّث كل الأجهزة معاً.** جهاز قديم يبقى يخصم بطريقته.
2. **أول تشغيل بعد التحديث** يثبّت لكل منتج رصيداً افتتاحياً من كمية أول جهاز يرفعه. الكميات القديمة كانت منحرفة بين الأجهزة (الأخطاء أعلاه)، فالرقم الفائز هو رقم ذلك الجهاز. **بعد تحديث كل الأجهزة: اجرد مرة واحدة** وصحّح بـ «تعديل المخزون» (يصل للجميع).
3. التنظيف الذكي لا يلمس `stock_movements`: الجهاز الجديد أو المستعيد يحتاج كل الحركات.

### 21.5 الاختبار

أداة الاختبار (19.ب) صارت تنشئ أصنافاً (منها بكرتون 12 أو 6)، وتبيع بالقطعة والكرتون داخل فواتير عادية ومعلّقة ومعدّلة، وتشتري، وتعدّل يدوياً، مع الانقطاع والاستعادة والانضمام المتأخر — وتفحص أن كمية كل منتج على كل جهاز = الحقيقة. واختبار مستقل للترقية: `test/sync_harness/stock_migration_test.dart` (كميات قديمة مختلفة بين ثلاثة أجهزة ⇒ رصيد افتتاحي واحد وكمية واحدة).

### 21.6 نسختان من المنتج نفسه (الاسم نفسه على جهازين) — وجدته مراجعة الكود

**المشكلة:** جهازان بلا إنترنت ينشئ كلٌّ منهما «سكر» بمعرّف مختلف (a وb). عند التزامن يطابق كل جهاز بالاسم ويُبقي نسخة واحدة، لكن:

1. **حركات وبنود تصل لاحقاً بالمعرّف الخاسر لا تُحسب لأي منتج.** الجهاز الذي دمج a في b نقل ما عنده فقط؛ ما يصل بعدها بالمعرّف a (حركة شراء، بنود فاتورة) يُدرج كما هو بلا منتج ⇒ الكمية تختلف بين الأجهزة، والجهاز الجديد يخسر كل ما سُجّل على a.
2. **اختيار الباقية بالوقت وحده:** وقتان متساويان ⇒ كل جهاز يُبقي نسخته. ووارد أقدم كان يُهمل كلياً (لا ربط).
3. **نسخة محلية دُمجت قبل أن يُرفع مستندها:** الأجهزة الأخرى لا ترى مستند a أبداً، فلا تعرف أن a هو «سكر» ⇒ بنود فواتير هذا الجهاز بالمعرّف a تبقى عندها بلا منتج.
4. **شاشة تعديل منتج فُتحت قبل الدمج:** حفظها يكتب المعرّف القديم (`sync_uuid` من كائن الشاشة) فوق الصف ⇒ المنتج ينفصل عن بنوده وحركاته، ويُرفع مستند الخاسرة بأحدث وقت فتعود هي الباقية للجميع.
5. **معالجة متزامنة لمستندات المنتجات:** المستمع والتنزيل الكامل كانا يعالجان نسختين من المستند نفسه في آن واحد: كلتاهما لا تجد الصف فتُدرجه، فتفشل الأحدث (UNIQUE) وتبقى الأقدم للأبد — فيبقى جهاز على النسخة الخاسرة (وجده اختبار الدمج).

**الإصلاح:**

| الملف | التعديل |
|---|---|
| `stock_ledger.dart` | جدول `product_uuid_alias (old_uuid PK, new_uuid, pending_doc)`. `rekeyProduct(old, new)` يسجّل التحويل بخطوة واحدة دائماً (الحي لا يُحوَّل، ومن كان يُحوَّل للقديم يُحوَّل للحي — بلا سلاسل ولا حلقات، ويقبل الدمج في أي اتجاه لاحقاً)، وينقل كل بند وحركة (عدا الرصيد الافتتاحي) من أي معرّف مُحوَّل للحي. مشغّلان `trg_stock_item_alias` و`trg_stock_mv_alias`: بند أو حركة **تصل لاحقاً** بمعرّف مُحوَّل تتبع الحي مهما كان مسار الوصول. |
| `product_sync_service.dart` | نسختان مختلفتا المعرّف: الباقية بـ `_copyWins` — **ترتيب كامل**: وقت التعديل الأحدث، والمعروف يغلب المجهول، ثم المعرّف الأكبر. الوارد الخاسر ⇒ `rekeyProduct(الوارد ← المحلي)` بدل الإهمال. نسخة محلية لم تُرفع قط (`last_synced_at IS NULL`) وتُستبدل ⇒ تُحفظ في `pending_doc` ويرفعها `uploadPendingCopies()` بمعاملة «أنشئ إن غاب» (مع كل رفع للمعلّق حتى ينجح). المعالجة الواردة **واحداً تلو الآخر** لكل نسخ الخدمة (`static _incomingQueue`). |
| `product_dao.dart` | `updateProduct`: `productMap.remove('sync_uuid')` — الشاشة لا تغيّر هوية المنتج. |
| `database_service.dart` | `updateProduct`: الرفع بالصف كما حُفظ (معرّفه وكميته الحاليان) لا بكائن الشاشة. |

**القاعدة:** الرصيد الافتتاحي المعتمد = رصيد **النسخة الباقية** وحدها (رصيد الخاسرة يُهمل)، والكمية = هذا الرصيد + حركات النسختين − مبيعهما. إن أدخل الجهازان رصيداً افتتاحياً مختلفاً للصنف نفسه، **صحّحه بجرد و«تعديل المخزون»** — التطبيق لا يعرف أيّهما عدّ البضاعة فعلاً.

**الاختبار:** `test/sync_harness/product_merge_test.dart` (ثلاثة سيناريوهات: بيع وشراء وتعديل على النسختين بلا إنترنت ثم إرجاع في فاتورة قديمة بنودها بالمعرّف الخاسر ثم جهاز جديد ثم إعادة تشغيل الجميع؛ الباقية بآخر تعديل لا بترتيب الإنشاء + حفظ شاشة فُتحت قبل الدمج؛ نسخة محلية دُمجت قبل رفعها). وتجارب الفوضى صارت تنشئ أحياناً صنفاً **بالاسم نفسه** لصنف لم يصل الجهاز بعد، والحقيقة تحسب الباقية من مستندات السحابة بالقاعدة نفسها وتفحص أن لا يبقى صف للخاسرة على أي جهاز.

### 21.7 كلفة الشراء بالمتوسط المرجّح مع مخزون سالب — وجدته مراجعة الكود

**المشكلة (`purchase_service.dart`، `_updateProductStockAndCost`):** المعادلة `(الكمية × الكلفة + الشراء × سعره) ÷ (الكمية + الشراء)` كانت تُدخل المخزون السالب بقيمة سالبة. مثال: −19 بكلفة 5 ثم شراء 20 بـ 6 ⇒ (−95 + 120) ÷ 1 = **25** بدل **6**. صار ممكناً بسهولة بعد قرار «المخزون قد يصير سالباً» (بيع متزامن على جهازين)، ويفسد تقارير الأرباح.

**الإصلاح:** الكمية السالبة بيعت فعلاً بالكلفة القديمة، فلا تدخل في المتوسط:

```dart
final costBasisQty = currentStock > 0 ? currentStock : 0.0;
final basisTotal = costBasisQty + newQty;
finalCost = basisTotal > 0
    ? (costBasisQty * currentCost + newQty * newUnitCost) / basisTotal
    : newUnitCost;
```

**الاختبار:** `invoice_math_test.dart` ← «كلفة الشراء بالمتوسط المرجّح» عبر `PurchaseService.savePurchaseInvoice` الحقيقية: موجب (10 بـ 0.5 + 10 بـ 1.5 ⇒ 1.0)، سالب (−19 ثم 20 بـ 6 ⇒ 6)، صفر (⇒ سعر الشراء).

### 21.8 كلفة قراءة حركات المخزون

**المشكلة:** مجموعة `stock_movements` تكبر بلا حدّ (التنظيف لا يلمسها عمداً)، وكل تشغيل كان يقرأها **كاملة مرتين**: المستمع (لقطته الأولى) والسحب عند الإقلاع.

**الإصلاح (`stock_movement_sync_service.dart`):**
- **`downloadMissing()`:** كل حركة مؤشَّرة «مرفوعة» محلياً (`is_uploaded = 1`) موجودة في السحابة (لا شيء يحذف الحركات)، فتساوي عدد السحابة (`count()` — قراءة واحدة لكل ألف حركة) مع العدد المحلي يعني أن لا شيء ينقص. عند الاختلاف أو التعذّر: سحب كامل كما كان. سحب الإقلاع صار يستعملها؛ والتمهيد والاستعادة يبقيان على السحب الكامل.
- **المستمع:** من وقت رفع أحدث حركة في السحابة (بساعة السيرفر) ناقص ساعة فقط، ثم `downloadMissing` لما قبله. تعذّر أيٌّ من الخطوتين ⇒ المستمع الكامل كما كان.

---

<a id="22"></a>
## 22. الإرجاع وحسابات الفاتورة

> **القرار (من صاحب المحل):** ميزة «التسوية» ملغاة نهائياً (أزرارها معطّلة في الواجهة ولا يُستدعى كودها). **الإرجاع = تعديل الفاتورة نفسها**: إنقاص كمية بند أو حذفه، فينقص المجموع.

### 22.1 ما يحدث عند الإرجاع بتعديل الفاتورة

- **الدين:** الحارس المحاسبي (القسم 9) يعيد حساب دين الفاتورة = المجموع − المسدد، ويُرفع الفرق داخل حزمة الفاتورة لكل الأجهزة.
- **المخزون:** البنود القديمة تُحذف والجديدة تُدرج ⇒ الكمية تعود تلقائياً على كل جهاز (دفتر المخزون — القسم 21).
- **فاتورة النقد:** المسدد = المجموع الجديد (يُعاد الفرق للزبون نقداً).
- **منع:** لا يُقبل مجموع أقل من المسدد (يجب تقليل المسدد أولاً)، ولا تعديل يجعل رصيد العميل سالباً.

### 22.2 خلل وجده اختبار الحسابات: نقل الفاتورة لعميل آخر

**المشكلة:** عند نقل فاتورة دين من عميل إلى آخر، الجهاز **المستقبِل** كان يعيد حساب رصيد العميل الجديد فقط. العميل القديم يبقى رصيده المخزّن (`current_total_debt`) على دين الفاتورة (مثال: 1150) بينما مجموع معاملاته صفر.

**التعديل في `_processIncomingInvoice`:** قبل حذف صفوف الفاتورة واستبدالها، اجمع عملاءها:

```dart
final prevCustomers = (await txn.rawQuery(
        'SELECT DISTINCT customer_id AS c FROM transactions WHERE invoice_sync_uuid = ?',
        [uuid]))
    .map((r) => r['c'] as int?)
    .whereType<int>()
    .toSet();
```

وبعد الإدراج، أعد حساب رصيد وظهور كل عميل منهم غير العميل الحالي:

```dart
for (final cid in prevCustomers) {
  if (cid == localCustomerId) continue;
  await _recalculateCustomerBalanceInsideTxn(txn, cid);
  await CustomerVisibility.apply(txn, cid);
}
```

### 22.3 الاختبار

- `test/sync_harness/invoice_math_test.dart`: سيناريوهات بأرقام معروفة مسبقاً، يتحقق على الجهاز المنشئ **وعلى جهاز آخر**: المجموع = البنود + التحميل − الخصم؛ السنتات في كل حقل؛ كسور بلا انجراف (3 × 333.33 − 0.99 = 999.00)؛ الإرجاع الجزئي وحذف بند (دين ومخزون)؛ التحويل نقد ↔ دين؛ نقل الفاتورة لعميل آخر؛ ورفض 6 إدخالات خاطئة (خصم = المجموع، خصم أو تحميل سالب، مسدد > المجموع، نقد بمسدد ناقص، مجموع تحت المسدد).
- تجارب الفوضى صارت تُرجع بنوداً من فواتير محفوظة، وتنقل فواتير لعملاء آخرين عشوائياً.

### 22.4 تنبيه البيع بلا رصيد

في شاشة الفاتورة (`create_invoice_screen.dart`)، عند إضافة بند كميته أكبر من المتاح:
- إعداد «السماح بالبيع عند نفاذ الكمية» **مطفأ** ⇒ يُمنع البيع (كما كان).
- **مفعّل** ⇒ يُقبل البيع مع تنبيه برتقالي: «الكمية المتاحة X أقل من المطلوب Y — سيصبح المخزون سالباً» (كان يُقبل بصمت).

---

<a id="23"></a>
## 23. قائمة فحص على أجهزة حقيقية (قبل البيع)

> الاختبار الآلي يشغّل كود التطبيق الحقيقي لكن على **سحابة وهمية**. هذه القائمة تتحقق من Firebase الحقيقي والأجهزة الحقيقية. تحتاج **3 أجهزة** على الأقل (مثلاً: حاسوب ويندوز + هاتفين أندرويد)، ومشروع Firebase **تجريبي** غير مشروع المحل.

### 23.1 التحضير

1. نسخة احتياطية كاملة من كل جهاز قبل التحديث.
2. ثبّت الإصدار الجديد على الأجهزة الثلاثة **في نفس اليوم**، وافتح التطبيق على كلٍّ منها مرة (هنا تحدث ترقية المخزون).
3. تأكد أن رقم الجهاز في إعدادات الفواتير مختلف أو متماثل — لا يهم بعد الآن (هوية المزامنة صارت معرّف Firebase)، لكن سجّله.
4. **قواعد Firestore:** تأكد أن قواعد المشروع فيها القاعدة الشاملة `match /{document=**} { allow read, write: if request.auth != null; }` (زر «نسخ قواعد الأمان» في شاشة إعداد Firebase ينسخها). المجموعة الجديدة `stock_movements` ليست في القوائم القديمة المخصصة؛ بدون القاعدة الشاملة تُرفض حركات المخزون (`permission-denied`) فلا تتزامن الكميات.

### 23.2 الاختبارات (سجّل النتيجة: ✅ / ❌ مع لقطة شاشة)

| # | الخطوات | النتيجة المتوقعة |
|---|---|---|
| 1 | جهاز أ: عميل جديد + دين 1000. انتظر دقيقة. | يظهر العميل برصيد 1000 على ب و ج. |
| 2 | ب: تسديد 300 لنفس العميل. | الرصيد 700 على الثلاثة. |
| 3 | ج: تعديل التسديد إلى 250، ثم تحويل دين إلى تسديد لمعاملة أخرى. | نفس الأرقام على الثلاثة. |
| 4 | **بلا إنترنت:** اقطع الإنترنت عن أ، سجّل فيه دين 500، أغلق التطبيق وافتحه، ثم أعد الإنترنت. | يصل 500 للجهازين الآخرين خلال دقائق، ولا يتكرر. |
| 5 | **في نفس اللحظة:** أ وب بلا إنترنت، كلٌّ يسجّل على نفس العميل (أ: 200، ب: 150-). أعد الإنترنت للاثنين. | الرصيد = السابق + 200 − 150 على الثلاثة. |
| 6 | أ: فاتورة دين بصنفين (قطعة + كرتون) وخصم وأجور تحميل ومسدد جزئي. | المجموع والمتبقي ودين العميل متطابقة على الثلاثة؛ كمية الصنفين نقصت بنفس المقدار على الثلاثة (الكرتون = عدد قطعه). |
| 7 | أ: **إرجاع** قطعة بتعديل نفس الفاتورة. | الدين والكمية يعودان بنفس المقدار على الثلاثة. |
| 8 | أ: تحويل الفاتورة إلى نقد، ثم نقلها لعميل آخر (دين). | العميل الأول رصيده يعود، والثاني يأخذ الدين — على الثلاثة. |
| 9 | ب: شراء من مورد لصنف (فاتورة شراء). ج: تعديل مخزون يدوي (+5) لنفس الصنف. | الكمية = السابق + الشراء + 5 على الثلاثة. |
| 10 | أ وب: بيع **نفس الصنف** في نفس الوقت بكمية تتجاوز المتاح (مع تفعيل «السماح بالبيع عند نفاذ الكمية»). | تنبيه برتقالي؛ الكمية سالبة **ومتطابقة** على الثلاثة. |
| 11 | ج: حذف عميل عليه فاتورة دين. | يختفي على الثلاثة، ولا يعود بعد إغلاق/فتح أي جهاز. |
| 12 | **استعادة نسخة احتياطية:** على ب، استعد نسخة أُخذت قبل الخطوات 6–10. | بعد دقائق يعود ب إلى الأرقام الحالية (لا القديمة)، ولا يتغير شيء على أ وج. **لا تعدّل شيئاً على ب حتى يكتمل.** |
| 13 | **جهاز رابع جديد:** ثبّت التطبيق على جهاز لم يُستخدم وفعّل المزامنة. | يستلم كل العملاء والأرصدة والفواتير والمنتجات والكميات مطابقة. |
| 14 | شغّل «التنظيف الذكي» من الإعدادات، ثم كرر 13 بجهاز خامس (أو امسح بيانات الرابع). | نفس النتيجة: لا ناقص ولا دين محذوف يعود. |
| 15 | على كل جهاز: الإعدادات ← مزامنة Firebase ← **«التحقق من الأرصدة بعد المزامنة»** و**«🩺 حالة المزامنة والتشخيص»**. | لا فروق، ولا أخطاء متكررة. |
| 16 | شاشة المطابقة ← **«المطابقة الحية بين الأجهزة»** بين أ وب. | إجمالي الديون متساوٍ على الجهازين. |
| 17 | **الاسم نفسه على جهازين:** أ وب بلا إنترنت، كلٌّ ينشئ صنف «تجربة دمج» (أ: 10، ب: 20) ويبيع منه قطعة. أعد الإنترنت للاثنين وانتظر دقيقتين. | صنف واحد فقط باسم «تجربة دمج» على الثلاثة، بكمية **متطابقة** = رصيد إحدى النسختين − قطعتين. (ثم صحّح الرصيد بـ «تعديل المخزون» — 21.6.) |
| 18 | ب: فاتورة شراء بطريقة «المتوسط المرجّح» لصنف كميته سالبة. | كلفة الصنف = سعر الشراء الجديد (لا رقم أكبر منه). |
| 19 | **قفل الاستعادة:** على ب، اقطع الإنترنت واستعد نسخة احتياطية قديمة. حاول تعديل معاملة قديمة، ثم سجّل تسديداً جديداً. أعد الإنترنت وانتظر. | شريط أزرق «جاري استرجاع آخر البيانات…»؛ التعديل مرفوض برسالة واضحة، والتسديد الجديد مقبول. بعد عودة الإنترنت يختفي الشريط، وتظهر المعاملة بقيمتها الحالية، ويُقبل تعديلها. |
| 20 | **الساعة:** غيّر وقت ج يدوياً 10 دقائق للأمام، ثم أعد فتح التطبيق. | شريط برتقالي «ساعة هذا الجهاز غير مضبوطة (فرق 10 دقيقة متقدمة)». أعد الضبط التلقائي وأعد فتح التطبيق ⇒ يختفي. |
| 21 | **حذف السحابة من خارجها (المشروع التجريبي فقط!):** من لوحة Firebase احذف مجموعة `stock_movements`، ثم أعد فتح التطبيق على أ، ثم انتظر دقيقة. | تعود الحركات للسحابة وحدها، والكميات لا تتغير على أي جهاز. |
| 22 | **اسم مكرر:** أ: أضف صنفاً باسم صنف موجود، ثم أعد تسمية صنف آخر إلى ذلك الاسم. | الحالتان مرفوضتان برسالة «يوجد صنف بالاسم نفسه…»؛ تعديل سعر صنف بلا تغيير اسمه يُقبل. |

### 23.3 شروط النجاح

كل البنود ✅. أي ❌: لا تنشر؛ احفظ لقطات الشاشة، وصدّر سجل التشخيص من الجهاز المعني، ولاحظ الوقت بالدقيقة.

---

<a id="24"></a>
## 24. خطة المراقبة بعد النشر (أول أسبوعين)

### 24.1 يوم التحديث

1. نسخة احتياطية من كل جهاز، ثم حدّث **كل الأجهزة في نفس اليوم** (جهاز قديم يعيد الأخطاء القديمة).
2. افتح التطبيق على كل جهاز وانتظر اكتمال المزامنة.
3. **جرد المخزون مرة واحدة:** الترقية ثبّتت لكل صنف رصيداً افتتاحياً من أول جهاز رفعه، والأرقام القديمة كانت منحرفة. صحّح كل صنف مختلف بـ «تعديل المخزون» (يصل لكل الأجهزة).
4. اختر **5 عملاء مرجعيين** (أكثرهم حركة) و**5 أصناف مرجعية** (أكثرها بيعاً)، واكتب أرقامهم على كل جهاز.

### 24.2 يومياً (5 دقائق، آخر الدوام)

| الفحص | أين | علامة الخطر |
|---|---|---|
| أرصدة العملاء الخمسة | صفحة العميل على كل جهاز | رقم مختلف بين جهازين بعد 10 دقائق من آخر حركة |
| كميات الأصناف الخمسة | صفحة المنتج على كل جهاز | كمية مختلفة بين جهازين |
| إجمالي الديون | «المطابقة الحية بين الأجهزة» بين جهازين متصلين | فرق لا يزول |
| الأخطاء | «🩺 حالة المزامنة والتشخيص» | خطأ يتكرر، أو «معاملات فاشلة» لا تنقص |
| الأرصدة | «التحقق من الأرصدة بعد المزامنة» | أي فرق مُبلَّغ |
| **شريط التنبيهات** | أعلى الشاشة الرئيسية على كل جهاز (القسم 25) | أي شريط أحمر أو برتقالي: جهاز بإصدار قديم، ساعة غير مضبوطة، قواعد Firebase، أو صنف مدموج يحتاج جرداً |

### 24.3 أسبوعياً

- جرد سريع لـ 10 أصناف عشوائية ومقارنتها بالتطبيق.
- مراجعة عميلين عشوائيين: كشف الحساب على جهازين متطابق سطراً بسطر.
- نسخة احتياطية جديدة.

### 24.4 عند ظهور فرق (مهم)

1. **لا تضغط «بياناتي صحيحة» فوراً.** انتظر 10 دقائق مع اتصال كل الأجهزة، ثم أعد الفحص — أغلب الفروق المؤقتة سببها جهاز لم يصله آخر تعديل بعد.
2. إن بقي الفرق: لقطة شاشة من الجهازين (صفحة العميل/الصنف + «حالة المزامنة والتشخيص»)، ووقت آخر حركة على هذا العميل، وأي جهاز كان بلا إنترنت أو استُعيدت عليه نسخة.
3. بعد التوثيق فقط: «بياناتي صحيحة» من الجهاز الذي يحمل الأرقام الصحيحة (جهاز **ليس** في وضع الاستعادة).

### 24.5 انتهاء المراقبة

أسبوعان متتاليان بلا أي فرق باقٍ في الفحوص اليومية ⇒ تخفيف المراقبة إلى الأسبوعية فقط.

---

<a id="25"></a>
## 25. المخاطر المتبقية بعد الإصلاحات — وكيف عولجت

بعد إصلاحات الأقسام السابقة بقيت مخاطر لا تأتي من خطأ في الحساب بل من **ظروف التشغيل**: استعادة نسخة قديمة، جهاز لم يُحدَّث، ساعة خاطئة، قواعد Firebase ناقصة، حذف بيانات السحابة من خارج التطبيق، ودمج صنفين بالاسم نفسه. كلها كانت **تمرّ بصمت**. الآن كل واحد منها إما يُمنع أو يُصلَح وحده أو يظهر تنبيهاً واضحاً في الشاشة الرئيسية.

**الملفان الجديدان:** `lib/services/firebase_sync/sync_health.dart` (حالة التنبيهات) و`lib/widgets/sync_health_banner.dart` (الشريط أعلى الشاشة الرئيسية — لا يظهر شيء ما دام كل شيء سليماً).

### 25.1 التعديل بعد استعادة نسخة احتياطية ← قفل

| | |
|---|---|
| **كان** | بعد استعادة نسخة قديمة يعرض الجهاز قيمها (معاملة 1000 صارت 300 عند الآخرين). تعديلها أو تحويلها أو حذف فاتورتها أو عميلها يُطبَّق على القيمة القديمة ويُنشر للجميع. |
| **الآن** | كل سجل من النسخة لم تؤكده السحابة بعد (`restored_mark = 1`) **مقفل حتى تكتمل الاستعادة**: تعديل مبلغ المعاملة، وتحويلها، وتعديل الفاتورة أو تعليقها أو حذفها، وحذف عميل له سجل مستعاد — برسالة: «هذا السجل من نسخة احتياطية مستعادة… اتصل بالإنترنت وانتظر اكتمال الاستعادة». **الجديد مسموح دائماً** (بيع، تسديد، فاتورة جديدة). وشريط أزرق في الشاشة الرئيسية طوال الاستعادة. بلا مزامنة مفعّلة لا قفل. |
| **الكود** | `DatabaseService`: `isRestoredRecordLocked` / `assertNotRestoredLocked` / `assertCustomerNotRestoredLocked` / `isRestoreLockActive`، واستثناء `RestoredRecordLockedException`. الحراسة في: `updateManualTransaction` (إلا الوارد من المزامنة)، `convertTransactionType`، `deleteCustomer`، `deleteInvoice`، `assertInvoiceEditable` (فتشمل `updateInvoice` والتعليق والإرجاع)، و`InvoiceController.saveInvoice` للتعديل. وفي `invoice_suspend_service` و`autoSaveSuspendedInvoice` صار الفحص **قبل** تغيير الأصناف (كان تغيير الأصناف يسبق رفض تحديث الفاتورة ⇒ حفظ ناقص). |

### 25.2 جهاز لم يُحدَّث ← تنبيه باسمه

كل جهاز يكتب `syncProtocol` (حالياً 3) في مستنده بمجموعة `devices`، والإصدارات السابقة لا تكتبه. فحص عند التشغيل ثم كل ساعة (`FirebaseSyncService.checkGroupHealth`): جهاز ظهر خلال 14 يوماً برقم أقدم ⇒ «أجهزة بإصدار قديم من التطبيق: …»، وبرقم أحدث ⇒ «هذا الجهاز بإصدار أقدم من: …». **ارفع `SyncHealth.syncProtocol` مع كل تغيير يلزم كل الأجهزة بالتحديث معاً.**

### 25.3 ساعة جهاز غير مضبوطة ← تنبيه

الفحص نفسه يكتب `clockProbe` بوقت السيرفر ثم يقرؤه، ويقارنه بوقت الجهاز لحظة الكتابة. فرق أكبر من 5 دقائق ⇒ «ساعة هذا الجهاز غير مضبوطة (فرق N دقيقة متقدمة/متأخرة) — فعّل ضبط الوقت تلقائياً». (الأرصدة والمخزون لا تعتمد على الساعات؛ «آخر تعديل يغلب» في بيانات الصنف ودمج النسخ هو ما يعتمد عليها.)

### 25.4 قواعد Firestore ناقصة ← تنبيه

رفع حركة مخزون أو صنف يُرفض بـ `permission-denied` ⇒ «قواعد Firebase تمنع مزامنة: حركات المخزون/الأصناف — انسخ قواعد الأمان…». يزول مع أول رفع ناجح. (أخطاء الشبكة لا تُعدّ.)

### 25.5 حذف بيانات السحابة من خارج التطبيق ← تعود وحدها

لا شيء في التطبيق يحذف مستندات الأصناف أو حركات المخزون (ولا زر «مسح السحابة» يلمسها)، فغيابها يعني حذفاً من لوحة Firebase أو نقل المجموعة لمشروع جديد — وكان الجهاز الجديد يستلم بنوداً بلا أصناف وكميات خاطئة.
- **الأصناف:** كل تنزيل كامل من السيرفر (`downloadAllProducts`) يقارن معرّفات السحابة بأصناف الجهاز ويعيد إنشاء الغائب («أنشئ إن غاب» — لا يكتب فوق مستند قائم، وبلا قراءة إضافية).
- **الحركات:** عدّ الإقلاع (`downloadMissing`) يكشف النقص فيُجري سحباً كاملاً، وهذا يعيد إنشاء كل حركة «مرفوعة» هنا غابت (الرصيد الافتتاحي بقيمته المعتمدة).
- **الجهاز الجديد:** `rebroadcastEverything` صار يشمل الأصناف والحركات (بعدّ أولاً، فلا كلفة في الحالة العادية).

### 25.6 دمج صنفين بالاسم نفسه ← تنبيه للمراجعة

عند الدمج (21.6) يُهمل الرصيد الافتتاحي لإحدى النسختين. الآن يظهر «دُمج صنفان بالاسم نفسه: «X» — راجع الكمية بالجرد» **على الجهازين اللذين أُدخلت عليهما النسختان فقط** (منشئ الصنف صار يُحفظ في `created_by_device_id` عند إضافته ويسافر مع مستنده)، مع زر «تمت المراجعة». لا يتكرر عند إعادة التشغيل، ولا يظهر على جهاز انضم لاحقاً.

### 25.6.ب اسمان متطابقان لصنفين على جهاز واحد ← ممنوع (وجدته تجارب الفوضى)

| | |
|---|---|
| **كان** | شاشات إضافة الصنف لا تمنع اسماً موجوداً. جهاز عليه صنفان بالاسم نفسه لا يدمجهما (كل مستند يطابق معرّفه هناك)، بينما الأجهزة الأخرى تدمجهما (الاسم نفسه = صنف واحد) ⇒ كمية مختلفة بين الأجهزة. ظهر في الفوضى القاسية (seed=1402) بسباق: الصنف وصل من جهاز آخر في لحظة إضافة صنف بالاسم نفسه. |
| **الآن** | `DatabaseService.insertProduct` يرفض اسماً موجوداً برسالة «يوجد صنف بالاسم نفسه «X» على هذا الجهاز (ربما أُضيف للتو من جهاز آخر)…» (كل شاشات الإضافة تعرض الرسالة)، و`updateProduct` يرفض **إعادة التسمية** لاسم صنف آخر — وتعديل صنف بلا تغيير اسمه مسموح دائماً. الفحص والإدراج داخل طابور معالجة الأصناف الواردة (`ProductSyncService.runExclusive`)، فلا يتسلّل صنف وارد بينهما. الاستيراد الجماعي كان يتخطى الأسماء الموجودة أصلاً. |
| **التكرار القديم** | صنفان بالاسم نفسه من إصدار سابق ⇒ تنبيه «أصناف مكررة الاسم على هذا الجهاز: …» — أعد تسمية أحدهما (جهاز ينضم لاحقاً كان سيدمجهما). وصنف يُدرج حيّاً بمعرّف كان مُحوَّلاً (أُعيدت تسميته بعد دمج قديم) يُمحى تحويله، فما يصل بمعرّفه بعدها يبقى له. |

### 25.6.ج عميل محذوف يظهر بسبب صف صافيه صفر (وجدته تجارب الفوضى — خلل قديم)

| | |
|---|---|
| **كان** | قاعدة الظهور (القسم 4: `CustomerVisibility`) تعدّ **أي** معاملة غير محذوفة «نشطة» — حتى صف تسوية فاتورة صافيه صفر. نقل فاتورة من عميل إلى آخر يترك عند **المالك** صف تسوية صفرياً للعميل القديم، بينما الأجهزة الأخرى تنسب كل صفوف الحزمة لعميلها **الحالي**. فإن حُذف العميل القديم: يبقى ظاهراً على المالك وحده (فوضى قاسية seed=1407)؛ وفي الحالة المعاكسة — فاتورة نقد نُقلت **إلى** عميل ثم حُذف — يظهر على كل الأجهزة إلا المالك (فوضى عادية seed=1608). الأرصدة صفر في الحالتين، لكن عميلاً محذوفاً يظهر على بعض الأجهزة دون غيرها. |
| **الآن** | «نشطة» = معاملة يدوية أو تسديد غير محذوفة، **أو فاتورة مساهمتها غير صفرية** (مجموع صفوف دينها، بالأنواع نفسها التي يحسبها الحارس المحاسبي — القسم 9). فاتورة صافي دينها صفر (نُقلت، أو سُدّدت كاملة) لا تعيد عميلاً محذوفاً، أياً كان العميل الذي نُسب إليه صفها. |
| **الاختبار** | `residual_risks_test.dart` ← «فاتورة نُقلت من عميل ثم حُذف العميل على جهاز آخر»: يفشل بالقاعدة القديمة («العميل … ظاهر والصحيح مخفي» على المالك) وينجح بالجديدة. |

### 25.7 ما لا يُحل بالكود

- **السحابة في الاختبار وهمية:** سلوك Firebase الحقيقي (الانقطاع، الحدود) يُتحقق منه بقائمة الفحص (23).
- **الجرد بعد التحديث:** التطبيق لا يعرف الكمية الفعلية على الرف؛ الترقية تأخذ رقم أول جهاز رفعه (21.4).

### 25.8 الاختبار

`test/sync_harness/residual_risks_test.dart`: قفل سجلات النسخة المستعادة (تعديل وتحويل وحذف عميل وتعديل فاتورة ⇒ مرفوض، والجديد مقبول، وبعد اكتمال الاستعادة يُقبل التعديل على القيمة الصحيحة)؛ حذف الأصناف والحركات من السحابة ثم جهاز جديد (يعيدها المُجيب) ثم حذفها ثانية وإعادة تشغيل جهاز (يعيدها وحده) — والكمية صحيحة على الجهاز الجديد؛ جهاز بإصدار قديم (وآخر مهمل منذ شهر لا يُحسب)، وجهاز أحدث، وساعة متقدمة 20 دقيقة؛ ورفض قواعد؛ ومنع الاسم المكرر (إضافة وإعادة تسمية) وتنبيه التكرار القديم. واختبار الدمج صار يتحقق من تنبيه الدمج (يظهر على الجهازين المنشئين فقط، ويختفي بالمراجعة ولا يعود). وتجارب الفوضى القاسية صارت تعدّ «تعديل مقفل بعد استعادة».
