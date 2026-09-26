// test/sync_harness/protocol.dart
// رسائل مشتركة بين «السحابة الوهمية» (الخيط الرئيسي) و«الأجهزة الوهمية» (خيوط منفصلة).
// كل الأصناف هنا تُرسل عبر SendPort بين خيوط نفس المجموعة (نسخ تلقائي).

import 'dart:isolate';

/// قيمة خاصة تُحلّ في السحابة: serverTimestamp / delete / increment / arrayUnion / arrayRemove.
class FV {
  final String kind;
  final Object? arg;
  const FV(this.kind, [this.arg]);
  @override
  String toString() => 'FV($kind)';
}

/// مسار حقل: قائمة مكونات، و['__name__'] لمعرّف المستند.
typedef FieldPathSpec = List<String>;

class QuerySpec {
  final String collection;
  final List<List<Object?>> where; // [FieldPathSpec, op, value]
  final List<List<Object?>> orderBy; // [FieldPathSpec, bool descending]
  final int? limit;
  final int? limitToLast;
  final List<Object?>? startAt;
  final List<Object?>? startAfter;
  final List<Object?>? endAt;
  final List<Object?>? endBefore;
  const QuerySpec({
    required this.collection,
    this.where = const [],
    this.orderBy = const [],
    this.limit,
    this.limitToLast,
    this.startAt,
    this.startAfter,
    this.endAt,
    this.endBefore,
  });
}

class WriteOp {
  final String kind; // set | update | delete
  final String path;
  final Map<String, Object?>? data; // set
  final Map<String, Object?>? updates; // update: 'a.b.c' → قيمة (المسار مفصول بـ \u0000)
  final bool merge;
  final List<FieldPathSpec>? mergeFields;
  const WriteOp(this.kind, this.path,
      {this.data, this.updates, this.merge = false, this.mergeFields});
}

class CloudRequest {
  final int id;
  final String device;
  final String op;
  final Map<String, Object?> args;
  final SendPort replyTo;
  CloudRequest(this.id, this.device, this.op, this.args, this.replyTo);
}

class CloudReply {
  final int id;
  final Object? value;
  final String? errorCode;
  final String? errorMessage;
  CloudReply(this.id, this.value, [this.errorCode, this.errorMessage]);
}

class DocSnap {
  final String path;
  final Map<String, Object?>? data; // null = غير موجود
  final int version; // 0 = غير موجود
  const DocSnap(this.path, this.data, this.version);
}

class DocChangeMsg {
  final String type; // added | modified | removed
  final int oldIndex;
  final int newIndex;
  final DocSnap doc;
  const DocChangeMsg(this.type, this.oldIndex, this.newIndex, this.doc);
}

class ListenerEvent {
  final String listenerId;
  final List<DocSnap> docs;
  final List<DocChangeMsg> changes;
  const ListenerEvent(this.listenerId, this.docs, this.changes);
}

/// أمر من المتحكّم (الاختبار) إلى جهاز وهمي.
class DeviceCommand {
  final int id;
  final String op;
  final Map<String, Object?> args;
  const DeviceCommand(this.id, this.op, [this.args = const {}]);
}

class DeviceReply {
  final int id;
  final Object? value;
  final String? error;
  const DeviceReply(this.id, this.value, [this.error]);
}

/// إعدادات تشغيل جهاز وهمي (تُمرَّر عند إنشاء الخيط).
class DeviceBoot {
  final String name;
  final String dir; // مجلد ملفاته (قاعدة البيانات…)
  final SendPort cloud;
  final SendPort controller;
  final SendPort sqlite; // خادم SQLite المشترك (خيط واحد لكل القواعد)
  final Map<String, Object> prefs;
  final Map<String, String> secure;
  final bool online;
  const DeviceBoot({
    required this.name,
    required this.dir,
    required this.cloud,
    required this.controller,
    required this.sqlite,
    required this.prefs,
    required this.secure,
    required this.online,
  });
}
