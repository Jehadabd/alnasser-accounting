// test/sync_harness/remote_firestore.dart
// طبقة Firestore «منصّة» داخل كل جهاز وهمي: مكتبة cloud_firestore الحقيقية
// (التي يستخدمها كود التطبيق كما هو) تستدعي هذه الطبقة، وهي ترسل الطلبات إلى
// السحابة الوهمية في الخيط الرئيسي. لا شيء في كود التطبيق يعرف أنه في اختبار.

// ignore_for_file: implementation_imports, invalid_use_of_protected_member

import 'dart:async';
import 'dart:isolate';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';

import 'protocol.dart';

class CloudLink {
  final String device;
  final SendPort cloud;
  final ReceivePort _inbox = ReceivePort();
  int _next = 1;
  final Map<int, Completer<Object?>> _pending = {};

  /// مسار الكود الذي أرسل كل طلب: خطأ السحابة يُرفق به، فخطأ «غير ممسوك»
  /// يدلّ على السطر الذي نسي معالجته (وإلا وصل بلا أي مسار).
  final Map<int, StackTrace> _origins = {};
  final Map<String, StreamController<ListenerEvent>> _streams = {};
  int _listenerSeq = 0;

  CloudLink(this.device, this.cloud) {
    _inbox.listen((m) {
      if (m is CloudReply) {
        final c = _pending.remove(m.id);
        final origin = _origins.remove(m.id);
        if (c == null) return;
        if (m.errorCode != null) {
          c.completeError(
              FirebaseException(
                  plugin: 'cloud_firestore', code: m.errorCode!, message: m.errorMessage),
              origin);
        } else {
          c.complete(m.value);
        }
      } else if (m is ListenerEvent) {
        _streams[m.listenerId]?.add(m);
      }
    });
  }

  Future<Object?> call(String op, Map<String, Object?> args) {
    final id = _next++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _origins[id] = StackTrace.current;
    cloud.send(CloudRequest(id, device, op, args, _inbox.sendPort));
    return c.future;
  }

  Stream<ListenerEvent> listen({String? doc, QuerySpec? query}) {
    final id = '$device#${++_listenerSeq}';
    late final StreamController<ListenerEvent> ctl;
    ctl = StreamController<ListenerEvent>(
      onListen: () {
        _streams[id] = ctl;
        call('listen', {'id': id, 'doc': doc, 'query': query}).catchError((e) {
          ctl.addError(e);
          return null;
        });
      },
      onCancel: () {
        _streams.remove(id);
        call('unlisten', {'id': id}).catchError((_) => null);
      },
    );
    return ctl.stream;
  }

  void close() => _inbox.close();
}

// ─────────────────────────── تحويل القيم ───────────────────────────

Object? encodeValue(Object? v) {
  if (v is FieldValuePlatform) return encodeValue(FieldValuePlatform.getDelegate(v));
  if (v is FV) return v;
  if (v is DocumentReferencePlatform) return v.path;
  if (v is Map) {
    return {for (final e in v.entries) e.key.toString(): encodeValue(e.value)};
  }
  if (v is List) return [for (final e in v) encodeValue(e)];
  return v;
}

FieldPathSpec fieldSpec(Object? f) {
  if (f == FieldPath.documentId || f is FieldPathType) return const ['__name__'];
  if (f is FieldPath) return List<String>.from(f.components);
  if (f is String) return f.split('.');
  throw ArgumentError('Unsupported field $f');
}

// ─────────────────────────── القيم الخاصة ───────────────────────────

class RemoteFieldValueFactory extends FieldValueFactoryPlatform {
  @override
  dynamic arrayRemove(List elements) => FV('arrayRemove', elements);
  @override
  dynamic arrayUnion(List elements) => FV('arrayUnion', elements);
  @override
  dynamic delete() => const FV('delete');
  @override
  dynamic increment(num value) => FV('increment', value);
  @override
  dynamic serverTimestamp() => const FV('serverTimestamp');
}

// ─────────────────────────── Firestore ───────────────────────────

class RemoteFirestore extends FirebaseFirestorePlatform {
  final CloudLink link;
  Settings _settings = const Settings();

  RemoteFirestore(this.link, {FirebaseApp? app}) : super(appInstance: app);

  @override
  FirebaseFirestorePlatform delegateFor(
          {required FirebaseApp app, required String databaseId}) =>
      this;

  @override
  CollectionReferencePlatform collection(String collectionPath) =>
      RemoteCollection(this, collectionPath);

  @override
  DocumentReferencePlatform doc(String documentPath) =>
      RemoteDocument(this, documentPath);

  @override
  WriteBatchPlatform batch() => RemoteBatch(this);

  @override
  Future<T?> runTransaction<T>(TransactionHandler<T> transactionHandler,
      {Duration timeout = const Duration(seconds: 30), int maxAttempts = 5}) async {
    Future<T?> attemptLoop() async {
      for (var attempt = 1;; attempt++) {
        final tx = RemoteTransaction(this);
        final result = await transactionHandler(tx);
        try {
          await link.call('write', {'ops': tx.writes, 'pre': tx.reads});
          return result;
        } on FirebaseException catch (e) {
          if (e.code != 'aborted' || attempt >= maxAttempts) rethrow;
        }
      }
    }

    return attemptLoop().timeout(timeout);
  }

  @override
  Settings get settings => _settings;

  @override
  set settings(Settings settings) => _settings = settings;

  @override
  Future<void> enableNetwork() async {}
  @override
  Future<void> disableNetwork() async {}
  @override
  Future<void> clearPersistence() async {}
  @override
  Future<void> terminate() async {}
  @override
  Future<void> waitForPendingWrites() async {}
  @override
  Stream<void> snapshotsInSync() => const Stream.empty();

  DocumentSnapshotPlatform snapFrom(DocSnap s) => DocumentSnapshotPlatform(
        this,
        s.path,
        s.data?.cast<String?, Object?>(),
        PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
      );

  QuerySnapshotPlatform querySnapFrom(List<DocSnap> docs, List<DocChangeMsg> changes) {
    DocumentChangeType t(String s) => s == 'added'
        ? DocumentChangeType.added
        : s == 'modified'
            ? DocumentChangeType.modified
            : DocumentChangeType.removed;
    return QuerySnapshotPlatform(
      [for (final d in docs) snapFrom(d)],
      [
        for (final c in changes)
          DocumentChangePlatform(t(c.type), c.oldIndex, c.newIndex, snapFrom(c.doc))
      ],
      SnapshotMetadataPlatform(false, false),
    );
  }
}

// ─────────────────────────── المستندات ───────────────────────────

WriteOp setOp(String path, Map<String, dynamic> data, SetOptions? options) {
  final merge = options?.merge == true;
  final mergeFields = options?.mergeFields;
  return WriteOp('set', path,
      data: (encodeValue(data) as Map).cast<String, Object?>(),
      merge: merge,
      mergeFields: mergeFields == null ? null : [for (final f in mergeFields) fieldSpec(f)]);
}

WriteOp updateOp(String path, Map<dynamic, dynamic> data) => WriteOp('update', path,
    updates: {
      for (final e in data.entries) fieldSpec(e.key).join('\u0000'): encodeValue(e.value)
    });

class RemoteDocument extends DocumentReferencePlatform {
  final RemoteFirestore fs;
  RemoteDocument(this.fs, String path) : super(fs, path);

  @override
  Future<void> delete() => fs.link.call('write', {
        'ops': [WriteOp('delete', path)]
      });

  @override
  Future<DocumentSnapshotPlatform> get([GetOptions options = const GetOptions()]) async {
    final s = await fs.link.call('get', {'path': path}) as DocSnap;
    return fs.snapFrom(s);
  }

  @override
  Stream<DocumentSnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) =>
      fs.link.listen(doc: path).map((e) => fs.snapFrom(e.docs.first));

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) =>
      fs.link.call('write', {
        'ops': [setOp(path, data, options)]
      });

  @override
  Future<void> update(Map<FieldPath, dynamic> data) => fs.link.call('write', {
        'ops': [updateOp(path, data)]
      });
}

// ─────────────────────────── الاستعلامات ───────────────────────────

Map<String, dynamic> _initialParams() => <String, dynamic>{
      'where': <List<dynamic>>[],
      'orderBy': <List<dynamic>>[],
      'startAt': null,
      'startAfter': null,
      'endAt': null,
      'endBefore': null,
      'limit': null,
      'limitToLast': null,
    };

class RemoteQuery extends QueryPlatform {
  final RemoteFirestore fs;
  final String collectionPath;

  RemoteQuery(this.fs, this.collectionPath, [Map<String, dynamic>? params])
      : super(fs, Map<String, dynamic>.unmodifiable(params ?? _initialParams()));

  RemoteQuery _copy(Map<String, dynamic> changes) => RemoteQuery(
        fs,
        collectionPath,
        Map<String, dynamic>.from(parameters)..addAll(changes),
      );

  QuerySpec get spec => QuerySpec(
        collection: collectionPath,
        where: [
          for (final c in (parameters['where'] as List))
            [fieldSpec((c as List)[0]), c[1], encodeValue(c[2])]
        ],
        orderBy: [
          for (final o in (parameters['orderBy'] as List))
            [fieldSpec((o as List)[0]), o[1] as bool]
        ],
        limit: parameters['limit'] as int?,
        limitToLast: parameters['limitToLast'] as int?,
        startAt: _vals(parameters['startAt']),
        startAfter: _vals(parameters['startAfter']),
        endAt: _vals(parameters['endAt']),
        endBefore: _vals(parameters['endBefore']),
      );

  static List<Object?>? _vals(Object? v) =>
      v == null ? null : [for (final e in (v as Iterable)) encodeValue(e)];

  @override
  Future<QuerySnapshotPlatform> get([GetOptions options = const GetOptions()]) async {
    final docs = (await fs.link.call('query', {'spec': spec}) as List).cast<DocSnap>();
    return fs.querySnapFrom(docs, [
      for (var i = 0; i < docs.length; i++) DocChangeMsg('added', -1, i, docs[i])
    ]);
  }

  @override
  Stream<QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) =>
      fs.link.listen(query: spec).map((e) => fs.querySnapFrom(e.docs, e.changes));

  @override
  QueryPlatform where(List<List<dynamic>> conditions) => _copy({'where': conditions});

  @override
  QueryPlatform orderBy(Iterable<List<dynamic>> orders) =>
      _copy({'orderBy': orders.toList()});

  @override
  QueryPlatform limit(int limit) => _copy({'limit': limit, 'limitToLast': null});

  @override
  QueryPlatform limitToLast(int limit) => _copy({'limit': null, 'limitToLast': limit});

  @override
  QueryPlatform startAfterDocument(List<dynamic> orders, List<dynamic> values) =>
      _copy({'orderBy': orders, 'startAt': null, 'startAfter': values});

  @override
  QueryPlatform startAtDocument(Iterable<dynamic> orders, Iterable<dynamic> values) =>
      _copy({'orderBy': orders.toList(), 'startAt': values.toList(), 'startAfter': null});

  @override
  QueryPlatform startAfter(Iterable<dynamic> fields) =>
      _copy({'startAt': null, 'startAfter': fields.toList()});

  @override
  QueryPlatform startAt(Iterable<dynamic> fields) =>
      _copy({'startAt': fields.toList(), 'startAfter': null});

  @override
  QueryPlatform endAtDocument(Iterable<dynamic> orders, Iterable<dynamic> values) =>
      _copy({'orderBy': orders.toList(), 'endAt': values.toList(), 'endBefore': null});

  @override
  QueryPlatform endAt(Iterable<dynamic> fields) =>
      _copy({'endAt': fields.toList(), 'endBefore': null});

  @override
  QueryPlatform endBeforeDocument(Iterable<dynamic> orders, Iterable<dynamic> values) =>
      _copy({'orderBy': orders.toList(), 'endAt': null, 'endBefore': values.toList()});

  @override
  QueryPlatform endBefore(Iterable<dynamic> fields) =>
      _copy({'endAt': null, 'endBefore': fields.toList()});

  @override
  AggregateQueryPlatform count() => RemoteAggregate(this, const [
        ['count']
      ]);

  @override
  AggregateQueryPlatform aggregate(
    AggregateField aggregateField1, [
    AggregateField? aggregateField2,
    AggregateField? aggregateField3,
    AggregateField? aggregateField4,
    AggregateField? aggregateField5,
    AggregateField? aggregateField6,
    AggregateField? aggregateField7,
    AggregateField? aggregateField8,
    AggregateField? aggregateField9,
    AggregateField? aggregateField10,
    AggregateField? aggregateField11,
    AggregateField? aggregateField12,
    AggregateField? aggregateField13,
    AggregateField? aggregateField14,
    AggregateField? aggregateField15,
    AggregateField? aggregateField16,
    AggregateField? aggregateField17,
    AggregateField? aggregateField18,
    AggregateField? aggregateField19,
    AggregateField? aggregateField20,
    AggregateField? aggregateField21,
    AggregateField? aggregateField22,
    AggregateField? aggregateField23,
    AggregateField? aggregateField24,
    AggregateField? aggregateField25,
    AggregateField? aggregateField26,
    AggregateField? aggregateField27,
    AggregateField? aggregateField28,
    AggregateField? aggregateField29,
    AggregateField? aggregateField30,
  ]) {
    final fields = [
      aggregateField1, aggregateField2, aggregateField3, aggregateField4, aggregateField5,
      aggregateField6, aggregateField7, aggregateField8, aggregateField9, aggregateField10,
      aggregateField11, aggregateField12, aggregateField13, aggregateField14, aggregateField15,
      aggregateField16, aggregateField17, aggregateField18, aggregateField19, aggregateField20,
      aggregateField21, aggregateField22, aggregateField23, aggregateField24, aggregateField25,
      aggregateField26, aggregateField27, aggregateField28, aggregateField29, aggregateField30,
    ].whereType<AggregateField>();
    return RemoteAggregate(this, [
      for (final f in fields)
        if (f is sum)
          ['sum', f.field]
        else if (f is average)
          ['avg', f.field]
        else
          ['count']
    ]);
  }
}

// ignore: avoid_implementing_value_types
class RemoteCollection extends RemoteQuery implements CollectionReferencePlatform {
  RemoteCollection(RemoteFirestore fs, String path) : super(fs, path);

  @override
  String get id => collectionPath.split('/').last;

  @override
  String get path => collectionPath;

  @override
  DocumentReferencePlatform? get parent {
    final parts = collectionPath.split('/');
    if (parts.length < 2) return null;
    return fs.doc(parts.sublist(0, parts.length - 1).join('/'));
  }

  static int _autoSeq = 0;

  @override
  DocumentReferencePlatform doc([String? path]) {
    final id = path ??
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(++_autoSeq).toRadixString(36)}${fs.link.device}';
    return fs.doc('$collectionPath/$id');
  }
}

class RemoteAggregate extends AggregateQueryPlatform {
  final List<List<Object?>> aggs;
  RemoteAggregate(RemoteQuery query, this.aggs) : super(query);

  @override
  Future<AggregateQuerySnapshotPlatform> get({required AggregateSource source}) async {
    final q = query as RemoteQuery;
    final r = (await q.fs.link.call('agg', {'spec': q.spec, 'aggs': aggs}) as Map)
        .cast<String, Object?>();
    return AggregateQuerySnapshotPlatform(
      count: r['count'] as int?,
      sum: [
        for (final a in aggs)
          if (a[0] == 'sum')
            AggregateQueryResponse(
                type: AggregateType.sum,
                field: a[1] as String,
                value: (r['sum:${a[1]}'] as num?)?.toDouble())
      ],
      average: [
        for (final a in aggs)
          if (a[0] == 'avg')
            AggregateQueryResponse(
                type: AggregateType.average,
                field: a[1] as String,
                value: (r['avg:${a[1]}'] as num?)?.toDouble())
      ],
    );
  }

  @override
  AggregateQueryPlatform count() => RemoteAggregate(query as RemoteQuery, [...aggs, ['count']]);
  @override
  AggregateQueryPlatform sum(String field) =>
      RemoteAggregate(query as RemoteQuery, [...aggs, ['sum', field]]);
  @override
  AggregateQueryPlatform average(String field) =>
      RemoteAggregate(query as RemoteQuery, [...aggs, ['avg', field]]);
}

// ─────────────────────────── المعاملات والدفعات ───────────────────────────

class RemoteTransaction extends TransactionPlatform {
  final RemoteFirestore fs;
  final Map<String, int> reads = {};
  final List<WriteOp> writes = [];
  RemoteTransaction(this.fs);

  @override
  List<PigeonTransactionCommand> get commands => const [];

  @override
  Future<DocumentSnapshotPlatform> get(String documentPath) async {
    final s = await fs.link.call('get', {'path': documentPath}) as DocSnap;
    reads[documentPath] = s.version;
    return fs.snapFrom(s);
  }

  @override
  TransactionPlatform delete(String documentPath) {
    writes.add(WriteOp('delete', documentPath));
    return this;
  }

  @override
  TransactionPlatform update(String documentPath, Map<String, dynamic> data) {
    writes.add(updateOp(documentPath, data));
    return this;
  }

  @override
  TransactionPlatform set(String documentPath, Map<String, dynamic> data,
      [SetOptions? options]) {
    writes.add(setOp(documentPath, data, options));
    return this;
  }
}

class RemoteBatch extends WriteBatchPlatform {
  final RemoteFirestore fs;
  final List<WriteOp> ops = [];
  RemoteBatch(this.fs);

  @override
  Future<void> commit() async {
    if (ops.isEmpty) return;
    await fs.link.call('write', {'ops': List<WriteOp>.from(ops)});
  }

  @override
  void delete(String documentPath) => ops.add(WriteOp('delete', documentPath));

  @override
  void set(String documentPath, Map<String, dynamic> data, [SetOptions? options]) =>
      ops.add(setOp(documentPath, data, options));

  @override
  void update(String documentPath, Map<String, dynamic> data) =>
      ops.add(updateOp(documentPath, data));
}
