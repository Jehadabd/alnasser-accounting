# 🚀 الحل السريع لمشكلة صلاحيات Firebase

## المشكلة المحددة:
```
PERMISSION_DENIED: Missing or insufficient permissions
```

## ✅ الحل الأسرع (10 دقائق):

### 1️⃣ افتح Firebase Console

اذهب إلى: https://console.firebase.google.com/

### 2️⃣ اختر مشروعك واذهب إلى Firestore Database

من القائمة الجانبية → **Firestore Database** → **Rules**

### 3️⃣ غيّر القواعد إلى هذا (للتطوير):

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

### 4️⃣ اضغط Publish

### 5️⃣ أعد تشغيل التطبيق

**✨ المشكلة يجب أن تحل الآن!**

---

## ⚠️ تحذير مهم:

هذا الحل **للتطوير والاختبار فقط**!

للإنتاج، يجب عليك:
1. تفعيل Firebase Authentication
2. استخدام قواعد آمنة (انظر `FIREBASE_PERMISSION_FIX.md`)

---

## 🔍 إذا لم يعمل:

### تحقق من:
1. ✅ أن Firestore مفعّل في Firebase Console
2. ✅ أن التطبيق متصل بالإنترنت
3. ✅ أن google-services.json موجود في `android/app/`
4. ✅ أنك نشرت (Publish) القواعد الجديدة

### شاهد الأخطاء:
```bash
flutter run
```
وانظر في Console إذا كان هناك أخطاء Firebase

---

## 📖 للمزيد:

راجع ملف `FIREBASE_PERMISSION_FIX.md` للحل الكامل والآمن.
