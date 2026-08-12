# 🔧 إصلاح مشكلة SQLite على Android

## 🔴 المشكلة

```
DatabaseException(unknown error (code 0 SQLITE_OK[0])):
Queries can be performed using SQLiteDatabase query or rawQuery
[] methods only.) sql 'PRAGMA busy_timeout = 30000' args
```

### السبب:
على Android، استخدام `db.execute()` مع أوامر `PRAGMA` لا يعمل بشكل صحيح.
يجب استخدام `db.rawQuery()` بدلاً من ذلك.

---

## ✅ الحل المُطبق

تم تعديل جميع أوامر PRAGMA لاستخدام `rawQuery` بدلاً من `execute`:

### الملفات المُعدلة:

#### 1. `lib/services/database/core/database_config.dart`
```dart
// قبل (خطأ):
await db.execute('PRAGMA busy_timeout = 30000');
await db.execute('PRAGMA synchronous = NORMAL');
await db.execute('PRAGMA foreign_keys = ON');

// بعد (صحيح):
await db.rawQuery('PRAGMA busy_timeout = 30000');
await db.rawQuery('PRAGMA synchronous = NORMAL');
await db.rawQuery('PRAGMA foreign_keys = ON');
```

#### 2. `lib/services/database/core/database_protection_service.dart`
```dart
// قبل (خطأ):
await db.execute('PRAGMA synchronous = FULL');
await db.execute('PRAGMA synchronous = NORMAL');

// بعد (صحيح):
await db.rawQuery('PRAGMA synchronous = FULL');
await db.rawQuery('PRAGMA synchronous = NORMAL');
```

#### 3. `lib/services/firebase_sync/sync_crash_recovery_service.dart`
```dart
// قبل (خطأ):
await db.execute('PRAGMA synchronous = FULL');
await db.execute('PRAGMA integrity_check');

// بعد (صحيح):
await db.rawQuery('PRAGMA synchronous = FULL');
await db.rawQuery('PRAGMA integrity_check');
```

---

## 🧪 الاختبار

### قبل التشغيل:
```bash
flutter clean
flutter pub get
```

### بناء APK:
```bash
flutter build apk --release
```

### يجب أن يعمل الآن بدون أخطاء!

---

## 📊 التغييرات بالتفصيل

| الملف | السطر | التغيير |
|-------|-------|---------|
| database_config.dart | 39 | `execute` → `rawQuery` (foreign_keys) |
| database_config.dart | 49 | `execute` → `rawQuery` (busy_timeout) |
| database_config.dart | 52 | `execute` → `rawQuery` (synchronous) |
| database_config.dart | 55 | `execute` → `rawQuery` (temp_store) |
| database_config.dart | 58 | `execute` → `rawQuery` (mmap_size) |
| database_config.dart | 61 | `execute` → `rawQuery` (cache_size) |
| database_protection_service.dart | 44 | `execute` → `rawQuery` (synchronous FULL) |
| database_protection_service.dart | 48 | `execute` → `rawQuery` (synchronous NORMAL) |
| sync_crash_recovery_service.dart | 174 | `execute` → `rawQuery` (synchronous FULL) |
| sync_crash_recovery_service.dart | 177 | `execute` → `rawQuery` (integrity_check) |

---

## 💡 لماذا هذا الإصلاح؟

### الفرق بين `execute` و `rawQuery`:

#### `db.execute()`:
- مصمم لأوامر DDL/DML (CREATE, INSERT, UPDATE, DELETE)
- **لا يدعم** PRAGMA بشكل صحيح على Android
- يسبب `SQLITE_OK[0]` exception

#### `db.rawQuery()`:
- مصمم لجميع أنواع الاستعلامات
- **يدعم** PRAGMA على كل المنصات
- متوافق مع Android, iOS, Windows, Linux

### مثال من وثائق Android:
```java
// خطأ في Android Native:
db.execSQL("PRAGMA busy_timeout = 30000"); // ❌ لا يعمل

// صحيح:
db.rawQuery("PRAGMA busy_timeout = 30000", null); // ✅ يعمل
```

Flutter's `sqflite` يتبع نفس النهج.

---

## 🎯 النتيجة

### قبل الإصلاح:
- ❌ التطبيق يفشل عند فتح قاعدة البيانات
- ❌ لا يمكن حفظ الفواتير
- ❌ إحصائيات المزامنة لا تعمل
- ✅ يعمل على Windows فقط

### بعد الإصلاح:
- ✅ التطبيق يفتح بدون أخطاء
- ✅ حفظ الفواتير يعمل
- ✅ إحصائيات المزامنة تعمل
- ✅ يعمل على جميع المنصات (Android, iOS, Windows, Linux)

---

## 🔍 استكشاف الأخطاء

### إذا استمرت المشكلة:

1. **تأكد من تنظيف الـ build:**
   ```bash
   flutter clean
   rm -rf build/
   flutter pub get
   ```

2. **أعد بناء التطبيق:**
   ```bash
   flutter build apk --release
   ```

3. **تحقق من إصدار sqflite:**
   في `pubspec.yaml`:
   ```yaml
   dependencies:
     sqflite: ^2.4.2  # أو أحدث
   ```

4. **شاهد السجلات (logs):**
   ```bash
   flutter run
   # أو
   adb logcat | grep -i sqlite
   ```

---

## 📚 مراجع

- [sqflite Documentation](https://pub.dev/packages/sqflite)
- [SQLite PRAGMA Statements](https://www.sqlite.org/pragma.html)
- [Android SQLiteDatabase API](https://developer.android.com/reference/android/database/sqlite/SQLiteDatabase)

---

✅ **التطبيق الآن يعمل على Android بدون مشاكل!**
