// lib/services/firebase_sync/safe_transaction.dart
//
// 🛡️ معاملات Firestore آمنة على ويندوز.
//
// على ويندوز، runTransaction في cloud_firestore يستدعي دالة Dart من خيط عامل
// تابع لمكتبة Firestore (C++)، فيظهر في السجل:
//   "channel sent a message from native to Flutter on a non-platform thread"
// ثم ينهار البرنامج بلا رسالة (0xC0000409). ظهر هذا في اختبار التحمّل: عند
// أول تشغيل بعد ربط فايربيس كان البرنامج يُغلق خلال ثوانٍ وهو يرفع المواد
// والأرصدة الافتتاحية («أنشئ إن غاب» بمعاملة).
//
// الحل: على ويندوز تُنفَّذ «المعاملة» قراءةً من السيرفر ثم كتابة بدفعة واحدة
// (WriteBatch). كل استخدامات المعاملات هنا من نوع «أنشئ إن غاب» أو «اكتب إن
// لم تكن السحابة أحدث» أو «احجز طلباً»، وصاحب الكتابة واحد في الغالب، فنافذة
// السباق بين القراءة والكتابة لا تغيّر النتيجة عملياً. وعلى بقية المنصات تبقى
// المعاملة الحقيقية كما هي.

import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'sync_breadcrumbs.dart';

/// واجهة موحّدة لـ Transaction الحقيقية أو بديلها على ويندوز.
class SafeTxn {
  SafeTxn._real(this._txn) : _batch = null;
  SafeTxn._batch(this._batch) : _txn = null;

  final Transaction? _txn;
  final WriteBatch? _batch;
  int _writes = 0;

  Future<DocumentSnapshot<T>> get<T extends Object?>(DocumentReference<T> ref) {
    final t = _txn;
    if (t != null) return t.get<T>(ref);
    return ref.get(const GetOptions(source: Source.server));
  }

  SafeTxn set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) {
    final t = _txn;
    if (t != null) {
      t.set<T>(ref, data, options);
    } else {
      _batch!.set<T>(ref, data, options);
      _writes++;
    }
    return this;
  }

  SafeTxn update(DocumentReference ref, Map<String, dynamic> data) {
    final t = _txn;
    if (t != null) {
      t.update(ref, data);
    } else {
      _batch!.update(ref, data);
      _writes++;
    }
    return this;
  }

  SafeTxn delete(DocumentReference ref) {
    final t = _txn;
    if (t != null) {
      t.delete(ref);
    } else {
      _batch!.delete(ref);
      _writes++;
    }
    return this;
  }
}

bool get _useBatchPath => !kIsWeb && Platform.isWindows;

/// بديل `firestore.runTransaction` — نفس الاستعمال تقريباً:
///   `await runSafeTransaction<bool>(fs, (txn) async { ... })`
Future<T> runSafeTransaction<T>(FirebaseFirestore fs, Future<T> Function(SafeTxn txn) body,
    {String label = ''}) async {
  if (!_useBatchPath) {
    return fs.runTransaction<T>((t) => body(SafeTxn._real(t)));
  }
  SyncCrumb.mark('safeTxn:start $label');
  final b = fs.batch();
  final txn = SafeTxn._batch(b);
  final result = await body(txn);
  if (txn._writes > 0) await b.commit();
  SyncCrumb.mark('safeTxn:done $label');
  return result;
}
