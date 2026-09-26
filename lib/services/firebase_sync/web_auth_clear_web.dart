// web_auth_clear_web.dart
// 🌐 تنظيف مخزن جلسة Firebase Auth في المتصفح:
// تلف قاعدة IndexedDB (firebaseLocalStorageDb) يجعل كل استرجاع/تجديد توكن
// يرمي TypeError — التنظيف + إعادة تسجيل مجهول يشفيان الحالة نهائياً.

import 'dart:js' as js;

Future<void> _eval(String script) {
  try {
    js.context.callMethod('eval', [script]);
  } catch (e) {
    print('🧹 [WebAuthClear] تعذر تنفيذ تنظيف: $e');
  }
  return Future.value();
}

Future<void> clearWebAuthStorage() async {
  // 1) قاعدة IndexedDB الخاصة بمصادقة Firebase
  await _eval("indexedDB && indexedDB.deleteDatabase('firebaseLocalStorageDb')");
  print('🧹 [WebAuthClear] طُلب حذف قاعدة firebaseLocalStorageDb');

  // 2) أي بقايا في localStorage
  await _eval(
      "Object.keys(localStorage).filter(k => k.includes('firebase')).forEach(k => localStorage.removeItem(k))");
  print('🧹 [WebAuthClear] نُظفت مفاتيح firebase من localStorage');
}
