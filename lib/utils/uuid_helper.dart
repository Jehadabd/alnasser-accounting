// lib/utils/uuid_helper.dart
// 🔁 ملف إعادة تصدير فقط (re-export shim).
//
// التنفيذ الفعلي لـ UuidHelper يعيش في:
//   lib/services/firebase_sync/uuid_helper.dart
// (ملف مُجرّب ومختبر لا يُعدّل).
//
// لكن بعض مكوّنات firebase_sync تستورده من المسار القديم '../../utils/uuid_helper.dart'.
// لتلبية هذا الاستيراد دون لمس ملفات firebase_sync، نُعيد تصديره من هنا.
export '../services/firebase_sync/uuid_helper.dart' show UuidHelper;
