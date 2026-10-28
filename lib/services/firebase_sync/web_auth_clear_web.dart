// web_auth_clear_web.dart
// 🌐 تنظيف مخزن جلسة Firebase Auth في المتصفح:
// تلف قاعدة IndexedDB (firebaseLocalStorageDb) يجعل كل استرجاع/تجديد توكن
// يرمي TypeError — التنظيف + إعادة تسجيل مجهول يشفيان الحالة نهائياً.

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart' show debugPrint;

Future<void> _eval(String script) {
  try {
    globalContext.callMethod('eval'.toJS, script.toJS);
  } catch (e) {
    debugPrint('🧹 [WebAuthClear] تعذر تنفيذ تنظيف: $e');
  }
  return Future.value();
}

Future<void> clearWebAuthStorage() async {
  // 1) قاعدة IndexedDB الخاصة بمصادقة Firebase
  await _eval("indexedDB && indexedDB.deleteDatabase('firebaseLocalStorageDb')");
  debugPrint('🧹 [WebAuthClear] طُلب حذف قاعدة firebaseLocalStorageDb');

  // 2) أي بقايا في localStorage
  await _eval(
      "Object.keys(localStorage).filter(k => k.includes('firebase')).forEach(k => localStorage.removeItem(k))");
  debugPrint('🧹 [WebAuthClear] نُظفت مفاتيح firebase من localStorage');
}
