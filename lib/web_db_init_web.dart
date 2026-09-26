// web_db_init_web.dart
// 🌐 تهيئة محرك قاعدة البيانات على الويب:
// SQLite الحقيقي (WebAssembly) مع تخزين دائم في IndexedDB.
// نفس واجهة sqflite — كل الـ DAOs والترحيلات تعمل كما هي بلا أي تعديل.

import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<void> configureWebDatabase() async {
  // محرك الويب بدون SharedWorker: لا يحتاج ملف sqflite_sw.js — يحمّل
  // sqlite3.wasm مباشرة من جذر الاستضافة (نفس ملف web/sqlite3.wasm).
  // ملاحظة: كل تبويب متصفح يفتح نسخته الخاصة — استخدم تبويباً واحداً للتطبيق.
  databaseFactory = databaseFactoryFfiWebNoWebWorker;
  print('🌐 [WebDB] محرك قاعدة البيانات: SQLite-WASM بلا عامل (IndexedDB)');
}
