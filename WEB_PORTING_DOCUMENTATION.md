# 📄 توثيق تحويل التطبيق للعمل على الويب (Chrome/PWA)

> **التاريخ**: 2026-08-25
> **الهدف**: توثيق دقيق لكل تعديل أُجري ليعمل التطبيق على متصفح Chrome والويب عموماً — بدون المساس بأي منطق أعمال (الديون، الفواتير، المزامنة، خوارزمية FTS5) — مع خطوات رفعه على Firebase Hosting مجاناً.

---

## الفلسفة الحاكمة للتحويل

قاعدة واحدة حكمت كل قرار: **"حراس وشروط عند نقاط الدخول + ملفات جديدة — وصفر تعديل على منطق القلب"**.

- كل فروع الأصلي (ويندوز/أندرويد) بقيت بترتيب أسطرها نفسه — يكفيها فقط شرط `!kIsWeb &&` قبلها.
- كل ميزة مستحيلة فيزيائياً في المتصفح (طباعة حرارية، OCR، AI) عُزلت خلف **جسور مشروطة** (Conditional Exports) — نمط Flutter الرسمي — فلا تُجمَّع على الويب أصلاً.
- قاعدة البيانات: **نفس كود sqflite بالكامل** — تبديل المحرك فقط من تحت نفس الواجهة.

---

## 1. نقاط الإقلاع — `lib/main.dart`

كانت 5 نقاط تستدعي `dart:io`/`Platform` مباشرة وترمي استثناء على الويب قبل ظهور أي واجهة:

| السطر (قبل) | المشكلة على الويب | الحل |
|---|---|---|
| `if (Platform.isAndroid \|\| Platform.isIOS)` لتوجيه الشاشة | `Platform._operatingSystem` يرمي | `if (!kIsWeb && (...))` — نفس الفرع للأصلي |
| تحميل `.env` بـ `File` بجانب الـ exe | لا نظام ملفات | حُرس بـ `if (!kIsWeb)` — الويب يحمّل `.env` من الـ assets (المحاولة 2 الموجودة أصلاً) |
| `sqfliteFfiInit()` للديسكتوب | — | أُضيف فرع ويب قبلها (القسم 2 أدناه) |
| `windowManager.ensureInitialized()` | لا نوافذ نظام | `if (!kIsWeb && ...)`) |
| استيراد `printing_service_windows.dart` (win32/dart:ffi) | يكسر **التجميع** كلياً | استُبدل بالجسر المشروط (القسم 4) |

```dart
import 'package:flutter/foundation.dart' show kIsWeb; // 🌐
import 'web_db_init.dart'; // 🌐 مشروط

// في main():
if (kIsWeb) {
  await configureWebDatabase();          // ويب: محرك WASM
} else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;  // ديسكتوب: كما كان تماماً
}
```

---

## 2. محرك قاعدة البيانات — SQLite-WASM داخل IndexedDB

**ثلاثة ملفات جديدة بنمط Flutter القياسي للتصدير المشروط:**

`lib/web_db_init.dart` (المُوجِّه):
```dart
export 'web_db_init_stub.dart'
    if (dart.library.html) 'web_db_init_web.dart';
```

`lib/web_db_init_web.dart` (نسخة الويب):
```dart
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<void> configureWebDatabase() async {
  databaseFactory = databaseFactoryFfiWebNoWebWorker;
  print('🌐 [WebDB] محرك قاعدة البيانات: SQLite-WASM بلا عامل (IndexedDB)');
}
```

`lib/web_db_init_stub.dart` (الأصلي): دالة فارغة — لا شيء يتغير.

**قرارات هامة موثقة:**
- `databaseFactoryFfiWebNoWebWorker` تحديداً (بدل `databaseFactoryFfiWeb` الافتراضي): الوضع الافتراضي يحتاج ملف `sqflite_sw.js` (Shared Worker) يجب تجميعه بأداة معقدة — الوضع "بلا عامل" يحمّل `sqlite3.wasm` مباشرة. المقايضة: كل تبويب متصفح يفتح نسخته الخاصة — **استخدم تبويباً واحداً** للتطبيق.
- الحزمة أُضيفت في `pubspec.yaml`:
```yaml
sqflite_common_ffi_web: ^0.4.3+4  # 🌐 SQLite-WASM للويب (IndexedDB)
```
- ملف المحرك نُزّل يدوياً إلى `web/sqlite3.wasm` (706KB) من الإصدار الرسمي:
  `https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-2.4.6/sqlite3.wasm`
- **FTS5 لم يُمَس**: النسخة الرسمية من `sqlite3.wasm` تتضمن FTS5 — والدليل من سجل التشغيل: `✅ تم إعادة بناء فهرس FTS5`. خوارزمية البحث الذكي تعمل حرفياً كما هي.
- كل الـ DAOs والترحيلات (v1→v49) والـ Triggers عملت بلا تعديل واحد.

---

## 3. إعدادات المسارات و PRAGMA

**`lib/services/database/core/database_config.dart`**:
```dart
static Future<String> getDatabasePath() async {
  if (kIsWeb) return databaseName;   // اسم فقط — IndexedDB يدير التخزين
  final dir = await getApplicationSupportDirectory();
  return join(dir.path, databaseName);
}
```
- `migrateFromOldPath()`: تخطٍّ كامل على الويب (لا نظام ملفات).
- PRAGMAs: فرع ويب متحفظ (بدون WAL/mmap الفيزيائية):
```dart
if (kIsWeb) {
  await db.rawQuery('PRAGMA mmap_size = 268435456');
  await db.rawQuery('PRAGMA cache_size = -16000');
} else if (Platform.isWindows || ...) { /* كما كان */ }
```

**`lib/services/database_service.dart`** (نقطتان):
```dart
// 1) فشل فتح القاعدة: على الويب أعد المحاولة مباشرة — لا ملفات تُحذف ولا نسخ تُستعاد
if (kIsWeb) {
  _database = await _initDatabase();
  return _database!;
}

// 2) إنشاء مجلد القاعدة: أصلي فقط
if (!kIsWeb) {
  await Directory(dirname(path)).create(recursive: true);
}
```

**`lib/services/smart_search/smart_search_db.dart`** (قاعدة البحث الثانية):
```dart
final String path;
if (kIsWeb) {
  path = 'smart_search.db';          // IndexedDB
} else {
  final dir = await getApplicationDocumentsDirectory();
  path = join(dir.path, 'smart_search.db');
}
```

---

## 4. الجسور المشروطة للأجزاء المستحيلة في المتصفح

نمط واحد موحد (التصدير المشروط الرسمي):

```dart
// الملف: xxx_factory.dart
export 'xxx_web.dart' if (dart.library.io) 'xxx.dart';
```
الويب يأخذ `_web.dart`، وكل منصة io تأخذ الملف الأصلي كما هو — **والتجميع لا يرى كوداً غير متوافق إطلاقاً**.

| الجسر | الويب يحصل على | الأصلي يحصل على |
|---|---|---|
| `printing_service_factory.dart` | `PrintingServiceWeb` — كل الطرق ترمي UnsupportedError مع رسالة عربية واضحة + قوائم فارغة (الأزرار تختفي بسلام) | أندرويد/ويندوز كما كانا حرفياً |
| `ensemble_ai_service_factory.dart` | `EnsembleAIService` ويب — `extractInvoiceData` يرمي (ميزة native)، و`matchProducts` يعمل **بمطابقة نصية خفيفة** | الخدمة الكاملة (onnxruntime) |
| `ocr_service_factory.dart` | `OcrService` ويب — رسالة "متاح على الكمبيوتر/أندرويد" | الخدمة الكاملة (tesseract) |

الملفات الجديدة: `printing_service_platform_web.dart`, `ensemble_ai_service_web.dart`, `ocr_service_web.dart` + 3 ملفات جسور. والمستوردون الثلاثة (main.dart + شاشتا الشراء) حُوّلوا للاستيراد من الجسور.

---

## 5. إصلاح SQL: الاقتباس المزدوج

SQLite-WASM صارم مع معيار SQL: `= ""` تُفسَّر **اسم عمود** لا نصاً (`no such column: ""`). المحركات الأصلية كانت متسامحة. أُصلحت 4 مواضع بتحويلها لاقتباس مفرد `'...'` داخل سلاسل Dart مزدوجة:

```dart
// قبل (يعمل native فقط):
where: 'transaction_uuid = ? OR (invoice_sync_uuid = ? AND ... != "")'
// بعد (قياسي — يعمل على الجميع):
where: "transaction_uuid = ? OR (invoice_sync_uuid = ? AND ... != '')"
```

**المواضع**: `database_service.dart` (فهرسا الوحدانية + استعلام backfill + تعريف الجداول في `_installSyncIdentityGuards`)، `pdf_service.dart:576`، `firebase_sync_service.dart:1581`، `invoice_sync_service.dart:856`.

---

## 6. الترخيص على الويب — بصمة الجهاز + CORS

**`lib/services/license_service.dart`** — مشكلتان:

**أ) بصمة الجهاز** (كانت `Platform.localHostname` + `wmic`):
```dart
if (kIsWeb) {
  // معرف ثابت يُولَّد مرة ويُخزَّن في GetStorage (localStorage دائم)
  final stored = _storage.read<String>('web_device_id');
  if (stored != null && stored.isNotEmpty) return stored;
  final newId = sha256.convert(utf8.encode('web_${...}')).toString().substring(0, 32);
  await _storage.write('web_device_id', newId);
  return newId;
}
```

**ب) CORS مع Google Apps Script**: المتصفح يرفض POST بـ `Content-Type: application/json` لخدمة خارجية (يطلب preflight لا يرد عليه Apps Script). الحل القياسي:
```dart
request.headers['Content-Type'] =
    kIsWeb ? 'text/plain;charset=utf-8' : 'application/json';
```
طلب "بسيط" بلا preflight — والسيرفر يقرأ `e.postData.contents` بنفس الطريقة. **الأصلي بقي على application/json كما كان.** والدليل من سجل التشغيل: `{"success":true,"type":"lifetime",...}` على المتصفح.

---

## 7. حراس الواجهات

**`general_settings_screen.dart`**:
- نص "لم يتم العثور على طابعات": فرع ويب برسالة الطباعة-عبر-PDF.
- بطاقة اتجاه الشاشة: `if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))`.
- حفظ كشوفات الحسابات: فرع ويب جديد — تنزيل PDF من الذاكرة (`XFile.fromData` + share_plus) بدل `getTemporaryDirectory()`:
```dart
} else if (kIsWeb) {
  await _downloadBytesOnWeb(pdfBytes, fileName);
}
```

---

## 8. أخطاء معروفة متبقية (غير معطِّلة)

| الخطأ | الحالة | السبب |
|---|---|---|
| `Backup error: MissingPluginException (getTemporaryDirectory)` | مطبوع فقط — زر النسخ الاحتياطي يفشل على الويب | يحتاج بديل "تنزيل النسخة كملف" (بند المرحلة 3) |
| طباعة/مشاركة الفاتورة PDF | قيد المعالجة | مسارات ملفات native — تحتاج نفس نمط `_downloadBytesOnWeb` في مواضع PDF |
| مصادقة Firebase متقطعة على الويب | قيد المعالجة | غالباً حقول Web config (authDomain) — انظر القسم التالي |

---

## 9. رفع التطبيق على Firebase Hosting (مجاناً)

### خطوات النشر على مشروع العميل

```bash
# مرة واحدة على جهاز الناشر:
npm install -g firebase-tools
firebase login

# من مجلد المشروع:
flutter build web --release          # يتضمن web/sqlite3.wasm تلقائياً
firebase init hosting                # public dir: build/web | SPA: Yes | overwrite index.html: NO
firebase deploy --only hosting
# النتيجة: https://اسم-المشروع.web.app
```

### إعدادات Firebase للويب (شاشة الإعداد المخصص)
من Firebase Console ← Project Settings ← Your apps ← **Web App** (وليس Android):
- `apiKey` + `projectId` + `appId` (**صيغة Web: يبدأ بـ `1:...:web:`**) + `messagingSenderId` + **`authDomain`: `<projectId>.firebaseapp.com`** (حقل إضافي يطلبه الويب فقط — غيابه أشهر أسباب فشل المصادقة على الويب).

### البقاء داخل الخطة المجانية (Spark)
- **لا تُدخل وسيلة دفع إطلاقاً** — الخطة المجانية لا تطلبها.
- حدود Hosting: 10GB تخزين + 360MB/يوم تنزيل — التطبيق يُنزَّل مرة لكل جهاز ثم يعمل محلياً.
- حدود Firestore: 1GB + 50K قراءة/يوم — المزامنة رسائل صغيرة.
- نظّف النسخ القديمة بعد كل نشر: Hosting ← Releases.
- التحديث لاحقاً: `flutter build web --release && firebase deploy --only hosting`.

### بقاء البيانات على iPhone (حرج)
- التطبيق **المثبَّت على الشاشة الرئيسية** (Safari ← مشاركة ← Add to Home Screen) **معفى** من محو Safari لبيانات 7 أيام عدم الاستخدام.
- التبويب العادي غير محمي — لذلك شاشة الترحيب يجب أن توصي بالتثبيت دائماً.
- شبكة الأمان البنيوية: حتى لو مُحيت نسخة الجهاز، فتح التطبيق ونفس حساب Firebase يعيد بناء كل شيء من بقية الأجهزة (السحب الكامل `performFullCatchUp`).

---

## 10. قائمة كل الملفات (نهائياً)

**ملفات جديدة (8):**
1. `lib/web_db_init.dart` — مُوجِّه المحرك المشروط
2. `lib/web_db_init_web.dart` — تهيئة SQLite-WASM
3. `lib/web_db_init_stub.dart` — stub الأصلي
4. `lib/services/printing_service_platform_web.dart` + `printing_service_factory.dart`
5. `lib/services/ensemble_ai_service_web.dart` + `ensemble_ai_service_factory.dart`
6. `lib/services/ocr_service_web.dart` + `ocr_service_factory.dart`
7. `lib/screens/web_hosting_guide_screen.dart` — شاشة دليل الاستضافة داخل التطبيق
8. `web/sqlite3.wasm` — محرك قاعدة البيانات (706KB)

**ملفات معدلة (11):** `main.dart`, `pubspec.yaml`, `database_config.dart`, `database_service.dart`, `smart_search_db.dart`, `license_service.dart`, `general_settings_screen.dart`, `pdf_service.dart`, `firebase_sync_service.dart` (اقتباس SQL فقط), `invoice_sync_service.dart` (اقتباس SQL فقط), شاشتا الشراء (استيراد الجسور).

**ما لم يُمَس إطلاقاً:** كل الـ DAOs، منطق الأرصدة والإدمبوتنت، خوارزمية FTS5 والبحث الذكي، طبقة المزامنة كاملة (رفع/استقبال/ACKs/مطابقة/قرارات)، الترحيلات، Triggers، شاشات الديون والفواتير.
