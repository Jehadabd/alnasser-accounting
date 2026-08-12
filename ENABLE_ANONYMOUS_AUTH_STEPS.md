# 🔥 خطوات تفعيل Anonymous Authentication في Firebase Console

## ⚠️ هذه الخطوة إلزامية!

بدون تفعيل Anonymous Authentication، التطبيق **لن يعمل** وسيستمر ظهور خطأ PERMISSION_DENIED.

---

## 📋 الخطوات بالتفصيل

### 1️⃣ افتح Firebase Console
اذهب إلى: https://console.firebase.google.com/

---

### 2️⃣ اختر مشروعك
- ابحث عن اسم مشروعك (مثل: fdhjdl)
- اضغط عليه للدخول

---

### 3️⃣ اذهب إلى Authentication
من القائمة الجانبية اليسرى:
- ابحث عن **"Build"** أو **"Authentication"**
- اضغط على **Authentication**

---

### 4️⃣ ابدأ التفعيل (إذا كانت أول مرة)
إذا لم تكن قد فعّلت Authentication من قبل:
- سترى زر **"Get Started"**
- اضغط عليه

إذا كانت مفعّلة بالفعل:
- انتقل مباشرة للخطوة التالية

---

### 5️⃣ افتح تبويب Sign-in method
في أعلى الصفحة، ستجد تبويبات:
- **Users** (المستخدمون)
- **Sign-in method** (طرق تسجيل الدخول) ← **اضغط هنا**
- **Settings** (الإعدادات)

---

### 6️⃣ ابحث عن Anonymous
في قائمة Sign-in providers:
- ستجد قائمة بطرق المصادقة:
  - Email/Password
  - Google
  - **Anonymous** ← **هذا ما نريده**
  - Facebook
  - ... إلخ

---

### 7️⃣ فعّل Anonymous
- اضغط على سطر **"Anonymous"**
- سيفتح مربع حوار
- ستجد مفتاح (toggle) بعنوان **"Enable"** أو **"تفعيل"**
- **فعّل المفتاح** (يتحول للون الأزرق/الأخضر)

---

### 8️⃣ احفظ التغييرات
- اضغط على زر **"Save"** أو **"حفظ"**
- انتظر حتى يظهر تأكيد النجاح

---

### 9️⃣ تأكد من التفعيل
بعد الحفظ:
- يجب أن ترى حالة **Anonymous** في القائمة = **"Enabled"** (مفعّل)
- يجب أن يكون المفتاح أخضر أو أزرق

---

## ✅ انتهيت! الآن شغّل التطبيق

بعد هذه الخطوات:
```bash
flutter run
```

وستجد التطبيق يعمل بدون أخطاء PERMISSION_DENIED!

---

## 🔍 التحقق من النجاح

### في Console التطبيق:
```
✅ تم تهيئة Firebase بنجاح بالإعدادات المخصصة.
🔐 تسجيل دخول مجهول لـ Firebase...
✅ تم تسجيل الدخول المجهول بنجاح: [معرف فريد]
```

### في Firebase Console:
1. اذهب إلى **Authentication** → **Users**
2. ستجد مستخدماً جديداً بنوع **"Anonymous"**
3. هذا يعني أن التطبيق سجل دخول بنجاح!

---

## ⚠️ ماذا لو نسيت هذه الخطوة؟

سيظهر لك خطأ في Console:
```
⚠️ خطأ في تسجيل الدخول لـ Firebase Auth: 
[firebase_auth/operation-not-allowed] Anonymous auth is disabled
```

**الحل**: ارجع وفعّل Anonymous كما في الخطوات أعلاه.

---

## 📸 مرجع مرئي سريع

```
Firebase Console
    ↓
[اختر مشروعك]
    ↓
[Authentication من القائمة الجانبية]
    ↓
[تبويب Sign-in method]
    ↓
[Anonymous]
    ↓
[Enable = ON] ✅
    ↓
[Save]
```

---

## 🎉 تم!

الآن التطبيق جاهز للعمل بدون مشاكل صلاحيات Firebase!
