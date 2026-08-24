# 🔧 توثيق إصلاح مشكلة مزامنة العملاء الجدد

> **التاريخ**: 2026-08-22
> **المشكلة**: عميل يُنشأ على جهاز (هاتف) بينما التطبيق مغلق على جهاز آخر (كمبيوتر) — الفاتورة تصل لكن العميل نفسه لا يظهر أبداً على الكمبيوتر، حتى بمزامنة يدوية.

---

## 📋 ملخص المشكلة الجذرية

اكتُشفت **ثلاث ثغرات متراكبة** في مسار مزامنة العملاء:

| # | الثغرة | الملف | الأثر |
|---|--------|-------|-------|
| 1 | **العملاء الجدد لا يولّدون `sync_uuid` عند الإنشاء** — `Customer.toMap()` يكتب `null`، ولا يوجد أي كود يولّده لحظة الإدراج (يوجد فقط في "الإصلاح الشامل" اليدوي) | `customer_dao.dart` | كل مسارات الرفع تشترط `sync_uuid IS NOT NULL` → **العميل الجديد غير مرئي للمزامنة للأبد** |
| 2 | **الإنشاء لا يرفع فوراً** — `insertCustomer` يكتب محلياً فقط، والرفع ينتظر الدورة الخلفية (10 دقائق) أو الـ watchdog (30 ثانية) | `app_provider.dart` | إغلاق التطبيق بسرعة بعد الإضافة = البيانات تبقى محلية |
| 3 | **مستمع الاستقبال مفلتر زمنياً** — `where('lastModifiedAt', '>', lastSyncAt)` بمقارنة نصية ISO وبساعات أجهزة مختلفة، ويعالج `docChanges` فقط | `firebase_sync_service.dart` | ما رُفع أثناء إيقاف الجهاز وقد فات اللقطة الأولى **لا يصل أبداً** (الفواتير وحدها كانت تستمع شمولياً — لهذا وصلت الفاتورة دون العميل) |

---

## 1️⃣ التعديلات على `lib/services/database/dao/customer_dao.dart`

### 1-أ: توليد `sync_uuid` فوري عند الإدراج (الإصلاح الجوهري)

**قبل**: كانت تُدرج خريطة العميل كما هي — و`sync_uuid` فيها `null`.

**بعد**:

```dart
/// 🆔 توليد sync_uuid فريد للعميل (نفس نمط الإصلاح الشامل)
static String newCustomerUuid() =>
    UuidHelper.sanitizeId('cust_${SyncSecurity.generateUuid()}');
```

```dart
return await db.transaction((txn) async {
  // 🆔 هوية مزامنة فورية للعميل الجديد:
  // بدونها يبقى sync_uuid فارغاً فلا يراه أي مسار رفع أبداً
  // (كان هذا سبب عدم وصول العملاء الجدد للأجهزة الأخرى).
  final customerMap = customer.toMap();
  if ((customerMap['sync_uuid'] as String?)?.isEmpty != false) {
    customerMap['sync_uuid'] = newCustomerUuid();
  }
  // 🏷️ هذا الجهاز هو المنشئ — شرط ملكية الرفع
  customerMap['is_created_by_me'] = 1;
  // ... ثم يُدرج customerMap بدل customer.toMap()
```

**الشرح**:
- `newCustomerUuid()` تتبع نفس نمط الإصلاح الشامل (`cust_` + UUID مبعثر) لضمان التوافق، و`sanitizeId` يضمن صلاحية المعرف كـ Firestore doc-id.
- `is_created_by_me = 1` ضروري لأن كل مسارات الرفع ترفع فقط ما أنشأه الجهاز (قاعدة الملكية) — بدونه يبقى العمود `NULL` وتعتمد المسارات على شرط التسامح `OR IS NULL`، والختم الصريح أضمن.
- الشرط `?.isEmpty != false` يعني: إذا كانت الهوية `null` أو `''` → ولّد جديدة؛ إذا كانت موجودة → احترمها.

### 1-ب: إعادة تنشيط العميل المحذوف تحافظ على هويته الأصلية

**قبل**: `copyWith` كان يعيد كتابة `toMap()` كاملاً وقد يمحو `sync_uuid` الأصلي.

**بعد**:

```dart
if (isDeleted) {
  // إعادة تنشيط العميل المحذوف وتحديث بياناته (مع الحفاظ على هويته الأصلية)
  final oldSyncUuid = existingRows.first['sync_uuid'] as String?;
  final updatedCustomer = customer.copyWith(
    id: existingId,
    isDeleted: false,
    lastModifiedAt: DateTime.now(),
    syncUuid: oldSyncUuid ?? (customerMap['sync_uuid'] as String),
  );
  final updateMap = updatedCustomer.toMap();
  updateMap['is_created_by_me'] = existingRows.first['is_created_by_me'];
  updateMap['last_modified_at'] = DateTime.now().toIso8601String();
  ...
}
```

**الشرح**: العميل "المُعاد تنشيطه" هو نفسه الشخص على بقية الأجهزة — يجب أن يحتفظ بنفس `sync_uuid` حتى لا يُعامَل كشخص جديد وتتضاعف حساباته. كما نحفظ `is_created_by_me` الأصلي (ربما أنشأه جهاز آخر أصلاً).

### 1-ج: معاملة الدين المبدئي تحصل على هوية فورية

**قبل**: معاملة الرصيد الافتتاحي تُدرج بلا `transaction_uuid` ولا ملكية — تنتظر backfill الإقلاع القادم.

**بعد**:

```dart
if (customer.currentTotalDebt > 0) {
  final now = DateTime.now();
  final txUuid = UuidHelper.newTransactionUuid();
  await txn.insert('transactions', {
    'customer_id': customerId,
    'transaction_uuid': txUuid, // 🆔 هوية فورية — لا ننتظر backfill الإقلاع
    'sync_uuid': txUuid,
    'transaction_date': now.toIso8601String(),
    'amount_changed': customer.currentTotalDebt,
    ...
    'is_created_by_me': 1, // 🏷️ ملكية الرفع لهذا الجهاز
    'is_uploaded': 0,
  });
}
```

**الشرح**: قبل هذا التعديل، لو أُغلق التطبيق قبل أول إقلاعٍ يلي الإضافة، تبقى معاملة الديون المبدئية بلا هوية فلا تُرفع — أي أن العميل قد يصل (بعد إصلاح 1-أ) لكن **بدون دينه**. الآن الاثنان يُرفعان معاً ككتلة واحدة.

---

## 2️⃣ التعديلات على `lib/providers/app_provider.dart`

### 2-أ: رفع فوري لحظة إنشاء العميل أو تعديله

```dart
/// 🚀 رفع فوري لعميل إلى السحابة (إن كانت المزامنة مفعّلة) — لا يفعل شيئاً محلياً.
Future<void> _syncCustomerNow(int customerId) async {
  try {
    if (!await FirebaseSyncConfig.isEnabled()) return;
    await FirebaseSyncService().syncCustomerNow(customerId);
  } catch (_) {
    // المزامنة الخلفية ستتكفل به لاحقاً
  }
}

Future<void> addCustomer(Customer customer) async {
  final id = await _db.insertCustomer(customer);
  final newCustomer = customer.copyWith(id: id);
  _customers.add(newCustomer);
  _applySearchFilter();
  notifyListeners();

  // 🚀 رفع فوري للسحابة لحظة الإنشاء (لا ننتظر الدورة الخلفية):
  // إذا أُغلق التطبيق بسرعة بعد الإضافة يبقى العميل محلياً فقط.
  // fire-and-forget: لا نحظر الواجهة، والفشل تلتقطه المزامنة الخلفية.
  unawaited(_syncCustomerNow(id));
}

Future<void> updateCustomer(Customer customer) async {
  ...
  // 🚀 رفع فوري للتعديل أيضاً (الاسم/الهاتف/العنوان تصل فوراً)
  final editedId = customer.id;
  if (editedId != null) unawaited(_syncCustomerNow(editedId));
}
```

**الشرح**:
- `unawaited(...)`: الرفع يجري في الخلفية — الواجهة لا تتجمد ولا ينتظر المستخدم الشبكة.
- `_syncCustomerNow` تتحقق أولاً أن المزامنة مفعّلة (`FirebaseSyncConfig.isEnabled()`) — من لا يستخدم المزامنة لا يلمس Firebase إطلاقاً.
- أي فشل (انقطاع شبكة) يُبتلع بصمت — طوابير المزامنة الخلفية وwatchdog ستلتقط لاحقاً.
- ملاحظة `int?`: `Customer.id` اختياري النوع في الموديل، لذا في `updateCustomer` نتحقق من null قبل التمرير.

**الاستيرادات المضافة**:

```dart
import '../services/firebase_sync/firebase_sync_service.dart'; // 🚀 رفع فوري عند الإنشاء/التعديل
import '../services/firebase_sync/firebase_sync_config.dart';
```

---

## 3️⃣ التعديلات على `lib/services/firebase_sync/firebase_sync_service.dart`

### 3-أ: `syncCustomerNow` — الرفع الفوري بمنطق الكتل الآمن

```dart
/// 🚀 رفع فوري لعميل محدد ومعاملاته المعلقة (يُستدعى لحظة إنشاء/تعديل العميل).
Future<void> syncCustomerNow(int customerId) async {
  if (!_isInitialized || _groupId == null) return;

  final db = await _db.database;
  final rows = await db.query(
    'customers',
    where: 'id = ? AND sync_uuid IS NOT NULL AND sync_uuid != \'\' '
        'AND (is_deleted IS NULL OR is_deleted = 0) '
        'AND (is_created_by_me = 1 OR is_created_by_me IS NULL)',
    whereArgs: [customerId],
    limit: 1,
  );
  if (rows.isEmpty) return;

  final customer = rows.first;
  final customerSyncUuid = customer['sync_uuid'] as String;

  final customerOk = await uploadCustomer(customer);
  if (!customerOk) return; // لا نرفع معاملات عميل لم يصل نفسه

  final pendingTx = await db.query(
    'transactions',
    where: 'customer_id = ? AND transaction_uuid IS NOT NULL AND transaction_uuid != \'\' '
        'AND (is_deleted IS NULL OR is_deleted = 0) '
        'AND (is_uploaded = 0 OR is_uploaded IS NULL) '
        'AND (is_created_by_me = 1 OR is_created_by_me IS NULL)',
    whereArgs: [customerId],
    orderBy: 'transaction_date ASC, id ASC',
  );

  for (final tx in pendingTx) {
    await uploadTransaction(tx, customerSyncUuid);
  }
}
```

**الشرح**:
- نفس منطق `_syncPendingChanges` لكن لعميل واحد: **العميل أولاً ثم معاملاته** — لأن معاملة تصل قبل عميلها تُخزَّن "يتيمة" على الجهاز الآخر.
- تعتمد كلياً على أن `sync_uuid` موجود (إصلاح 1-أ) — لهذا كان الإصلاحان لازمَين معاً.

### 3-ب: إزالة الفلتر الزمني من المستمعين (استقبال شامل إدمبوتنت)

**قبل**:

```dart
// ❌ كان:
if (lastSyncAt != null) {
  customersQuery = customersQuery.where('lastModifiedAt', isGreaterThan: lastSyncAt);
  transactionsQuery = transactionsQuery.where('lastModifiedAt', isGreaterThan: lastSyncAt);
}
```

**بعد**:

```dart
// 🔒 استماع شامل بلا فلتر زمني (نفس نهج الفواتير المجرّب).
// الفلتر السابق (lastModifiedAt > lastSyncAt) كان يتجاوز أي عميل أو
// معاملة رُفعت أثناء إيقاف هذا الجهاز إذا سقطت خارج النافذة (فرق
// ساعات الأجهزة / مقارنة نصية ISO)، فلا تصل أبداً حتى بمزامنة يدوية.
// التطبيق الاستقبالي إدمبوتنت بالكالة (sync_uuid + مطابقة الاسم)،
// لذا الاستماع الشامل آمن ولا يكرر شيئاً.
final Query<Map<String, dynamic>> customersQuery = _firestore!.collection('customers');
final Query<Map<String, dynamic>> transactionsQuery = _firestore!.collection('transactions');
```

**الشرح — لماذا كان الفلتر كارثياً؟**
1. `lastModifiedAt` يُخزَّن كنص ISO محلي (`DateTime.now().toIso8601String()`) والمقارنة في Firestore **نصية** — أي فرق ساعات بين جهازين يُسقط المستندات.
2. حتى بدون فرق ساعات: المستندات المرفوعة أثناء إيقاف هذا الجهاز تقع قبل `lastSyncAt` إن حُدِّثت قيمة الأخير في جلسة أحدث → تُصفى للأبد.
3. الدليل التجريبي: الفواتير تستمع شمولياً (سجل التطبيق يقول حرفياً "بلا فلتر زمني") فوصلت كلها، بينما لم يصل عميل واحد.

**لماذا الاستماع الشامل آمن؟** دوال التطبيق (`_applyCustomerChange`, `_applyTransactionChange`) إدمبوتنت: تبحث بالـ `sync_uuid` فتهمل الموجود، والرصيد يُشتق دائماً من `SUM(transactions)` داخل معاملة SQLite — فالتكرار مستحيل.

### 3-ج: `performFullCatchUp` — السحب الكامل عند الإقلاع وعودة الاتصال

```dart
/// 🔄 سحب كامل عند التشغيل (Catch-Up) — ضمان تقارب لا يعتمد على المستمعين.
Future<void> performFullCatchUp() async {
  if (!_isInitialized || _groupId == null || _firestore == null) return;

  // 1️⃣ العملاء أولاً (المعاملات تتيمة بدون عملائها)
  final custSnap = await _firestore!.collection('customers').get();
  for (final doc in custSnap.docs) {
    final data = doc.data();
    if (data['deviceId'] == _deviceId) continue; // من صنعي — عندي نسخة أصلية
    await _applyCustomerChange(doc.id, data);
  }

  // 2️⃣ المعاملات
  final txSnap = await _firestore!.collection('transactions').get();
  for (final doc in txSnap.docs) {
    final data = doc.data();
    if (data['deviceId'] == _deviceId) continue;
    await _applyTransactionChange(doc.id, data);
  }
}
```

**الشرح**: المستمعون اللحظيون يعالجون `docChanges` فقط — أي مستند فاتتهم لا يُعالج لاحقاً أبداً. هذه الدالة تمرّ على **كل** مستندات السحابة عند كل إقلاع وتطبّقها إدمبوتنت، فأي جهاز يعود بعد أي غياب يصل للحقيقة كاملة مهما كان سبب فوات المستمعين (إصدار قديم، جدولة شبكة، سباق تهيئة).

**مواضع الاستدعاء**:

```dart
// عند الإقلاع (بعد المزامنة الخلفية في initialize):
Future(() async {
  await _syncPendingChanges();
  // 🔄 سحب كامل إدمبوتنت بعد رفع المعلق
  await performFullCatchUp();
});

// وعند عودة الاتصال (onConnectionRestored):
await _syncPendingChanges();
// 🔄 سحب كامل إدمبوتنت: كل ما فات أثناء الانقطاع
await performFullCatchUp();
```

---

## 🛡️ طبقات الحماية الأربع المتراكبة الآن

```
إنشاء عميل على أي جهاز:
   │
   ▼
[1] customer_dao: sync_uuid + is_created_by_me + معاملة دين معرّفة  ← الهوية فورية
   │
   ▼
[2] app_provider → syncCustomerNow: رفع فوري (العميل ثم معاملاته)  ← لا انتظار
   │
   ▼
[3] الجهاز الآخر: مستمع شامل بلا فلتر زمني                          ← لا مستند يفلت
   │
   ▼
[4] وأيضاً: performFullCatchUp عند كل إقلاع/عودة اتصال             ← شبكة أمان أخيرة
```

فشل أي طبقة تلتقطها التالية — العميل يصل للحقيقة كاملة مهما تزامنت الأعطال.

---

## ✅ سيناريو الاختبار المعتمد

1. أغلق تطبيق الكمبيوتر.
2. على الهاتف: أنشئ عميلاً جديداً بدين مبدئي (مثلاً 1,000,000).
3. شغّل الكمبيوتر واتركه دقيقة.
4. **المتوقع**: العميل يظهر في سجل الديون بدينه كاملاً، مع سطور `[Catch-Up]` في السجل تثبت المراجعة الكاملة.
