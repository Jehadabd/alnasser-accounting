// test/sync_harness/cloud.dart
// «سحابة Firestore وهمية» تعمل في الخيط الرئيسي للاختبار.
//
// تحاكي السلوك الذي يعتمد عليه كود المزامنة:
//   • set / set(merge) / update / delete — ذرية، مع serverTimestamp وdelete وincrement.
//   • قراءة مستند، استعلامات (== != < <= > >= in not-in array-contains)، ترتيب،
//     مؤشرات (startAfter…)، حدود، عدّ وجمع.
//   • معاملات (runTransaction) بتحقق متفائل من إصدار ما قُرئ، ودفعات (batch).
//   • مستمعون: لقطة أولى بكل المطابق (added)، ثم الفروق (added/modified/removed).
//   • انقطاع الإنترنت لكل جهاز: القراءات تفشل (unavailable)، الكتابات تنتظر حتى
//     العودة (كـ Firestore على سطح المكتب بلا persistence)، والمستمعون يصمتون ثم
//     يُرسل لهم الفرق عند العودة.

import 'dart:isolate';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    show Timestamp;

import 'protocol.dart';

class _Doc {
  Map<String, Object?> data;
  int version;
  _Doc(this.data, this.version);
}

class _Listener {
  final String id;
  final String device;
  final SendPort port;
  final String? docPath; // مستمع مستند
  final QuerySpec? query; // مستمع استعلام
  Map<String, int> lastSent = {}; // path → version (آخر ما أُرسل)
  List<String> lastOrder = [];
  bool dirty = false;
  bool sentOnce = false;
  _Listener(this.id, this.device, this.port, {this.docPath, this.query});
}

class CloudError implements Exception {
  final String code;
  final String message;
  CloudError(this.code, this.message);
  @override
  String toString() => 'CloudError($code: $message)';
}

class FakeCloud {
  final Map<String, _Doc> docs = {};
  final Map<String, bool> online = {};
  final Map<String, List<CloudRequest>> _queued = {};
  final Map<String, _Listener> _listeners = {};
  final ReceivePort _port = ReceivePort();
  int _ver = 0;
  int _lastMicros = 0;

  /// عدد الكتابات لكل مجموعة (للقياس: عواصف الكتابة).
  final Map<String, int> writesByCollection = {};
  int totalWrites = 0;
  DateTime lastWriteAt = DateTime.now();

  /// أخطاء غير متوقعة داخل السحابة (خلل في الأداة نفسها).
  final List<String> internalErrors = [];

  SendPort get sendPort => _port.sendPort;

  FakeCloud() {
    _port.listen(_onMessage);
  }

  void close() => _port.close();

  // ───────────────────────── الشبكة ─────────────────────────

  void setOnline(String device, bool value) {
    online[device] = value;
    if (!value) return;
    final q = _queued.remove(device) ?? const [];
    for (final r in q) {
      _handle(r);
    }
    for (final l in _listeners.values) {
      if (l.device == device && l.dirty) _flush(l);
    }
  }

  bool _isOnline(String device) => online[device] ?? true;

  /// يُسقط مستمعي جهاز (عند إعادة تشغيله أو إغلاقه).
  void dropDevice(String device) {
    _listeners.removeWhere((_, l) => l.device == device);
    _queued.remove(device);
  }

  // ───────────────────────── الرسائل ─────────────────────────

  void _onMessage(dynamic msg) {
    if (msg is! CloudRequest) return;
    final isWrite = msg.op == 'write' && (msg.args['pre'] == null);
    if (!_isOnline(msg.device)) {
      if (isWrite) {
        // كتابة بلا persistence: تنتظر حتى يعود الاتصال
        _queued.putIfAbsent(msg.device, () => []).add(msg);
        return;
      }
      if (msg.op != 'unlisten' && msg.op != 'listen') {
        msg.replyTo.send(CloudReply(msg.id, null, 'unavailable',
            'The service is currently unavailable (client offline).'));
        return;
      }
    }
    _handle(msg);
  }

  void _handle(CloudRequest r) {
    try {
      final value = _dispatch(r);
      r.replyTo.send(CloudReply(r.id, value));
    } on CloudError catch (e) {
      r.replyTo.send(CloudReply(r.id, null, e.code, e.message));
    } catch (e, st) {
      internalErrors.add('${r.op}: $e\n$st');
      r.replyTo.send(CloudReply(r.id, null, 'internal', '$e'));
    }
  }

  Object? _dispatch(CloudRequest r) {
    final a = r.args;
    switch (r.op) {
      case 'get':
        return _snap(a['path'] as String);
      case 'query':
        return _runQuery(a['spec'] as QuerySpec);
      case 'agg':
        return _aggregate(a['spec'] as QuerySpec, (a['aggs'] as List).cast<List<Object?>>());
      case 'write':
        _write((a['ops'] as List).cast<WriteOp>(),
            (a['pre'] as Map?)?.cast<String, int>());
        return null;
      case 'listen':
        final l = _Listener(a['id'] as String, r.device, r.replyTo,
            docPath: a['doc'] as String?, query: a['query'] as QuerySpec?);
        _listeners[l.id] = l;
        if (_isOnline(r.device)) {
          _flush(l, initial: true);
        } else {
          l.dirty = true; // بلا persistence: لا لقطة حتى يعود الاتصال
        }
        return null;
      case 'unlisten':
        _listeners.remove(a['id'] as String);
        return null;
    }
    throw CloudError('unimplemented', 'op ${r.op}');
  }

  // ───────────────────────── القراءة ─────────────────────────

  DocSnap _snap(String path) {
    final d = docs[path];
    return d == null ? DocSnap(path, null, 0) : DocSnap(path, _deepCopy(d.data), d.version);
  }

  static String _parent(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  static String _id(String path) => path.substring(path.lastIndexOf('/') + 1);

  List<DocSnap> _runQuery(QuerySpec q) {
    final paths = _matchPaths(q);
    return [for (final p in paths) _snap(p)];
  }

  List<String> _matchPaths(QuerySpec q) {
    final out = <String>[];
    docs.forEach((path, d) {
      if (_parent(path) != q.collection) return;
      for (final w in q.where) {
        if (!_matches(path, d.data, w[0] as FieldPathSpec, w[1] as String, w[2])) return;
      }
      for (final o in q.orderBy) {
        final f = o[0] as FieldPathSpec;
        if (!_isDocId(f) && !_has(d.data, f)) return; // orderBy يستبعد من لا يملك الحقل
      }
      out.add(path);
    });
    final orders = <List<Object?>>[...q.orderBy];
    if (orders.isEmpty || !_isDocId(orders.last[0] as FieldPathSpec)) {
      final dir = orders.isEmpty ? false : orders.last[1] as bool;
      orders.add([const ['__name__'], dir]);
    }
    int cmpPaths(String a, String b) {
      for (final o in orders) {
        final f = o[0] as FieldPathSpec;
        final desc = o[1] as bool;
        final va = _isDocId(f) ? _id(a) : _get(docs[a]!.data, f);
        final vb = _isDocId(f) ? _id(b) : _get(docs[b]!.data, f);
        final c = _cmp(va, vb);
        if (c != 0) return desc ? -c : c;
      }
      return 0;
    }

    out.sort(cmpPaths);

    int cmpCursor(String path, List<Object?> cursor) {
      for (var i = 0; i < cursor.length && i < orders.length; i++) {
        final f = orders[i][0] as FieldPathSpec;
        final desc = orders[i][1] as bool;
        final v = _isDocId(f) ? _id(path) : _get(docs[path]!.data, f);
        var cv = cursor[i];
        if (_isDocId(f) && cv is String && cv.contains('/')) cv = _id(cv);
        final c = _cmp(v, cv);
        if (c != 0) return desc ? -c : c;
      }
      return 0;
    }

    var res = out;
    if (q.startAt != null) res = res.where((p) => cmpCursor(p, q.startAt!) >= 0).toList();
    if (q.startAfter != null) res = res.where((p) => cmpCursor(p, q.startAfter!) > 0).toList();
    if (q.endAt != null) res = res.where((p) => cmpCursor(p, q.endAt!) <= 0).toList();
    if (q.endBefore != null) res = res.where((p) => cmpCursor(p, q.endBefore!) < 0).toList();
    if (q.limit != null && res.length > q.limit!) res = res.sublist(0, q.limit!);
    if (q.limitToLast != null && res.length > q.limitToLast!) {
      res = res.sublist(res.length - q.limitToLast!);
    }
    return res;
  }

  Map<String, Object?> _aggregate(QuerySpec q, List<List<Object?>> aggs) {
    final paths = _matchPaths(QuerySpec(collection: q.collection, where: q.where));
    final out = <String, Object?>{'count': paths.length};
    for (final a in aggs) {
      final kind = a[0] as String;
      if (kind == 'count') continue;
      final field = (a[1] as String).split('.');
      num sum = 0;
      var n = 0;
      for (final p in paths) {
        final v = _get(docs[p]!.data, field);
        if (v is num) {
          sum += v;
          n++;
        }
      }
      out['$kind:${a[1]}'] = kind == 'sum' ? sum.toDouble() : (n == 0 ? null : sum / n);
    }
    return out;
  }

  // ───────────────────────── الكتابة ─────────────────────────

  Timestamp _serverNow() {
    var m = DateTime.now().microsecondsSinceEpoch;
    if (m <= _lastMicros) m = _lastMicros + 1;
    _lastMicros = m;
    return Timestamp.fromMicrosecondsSinceEpoch(m);
  }

  void _write(List<WriteOp> ops, Map<String, int>? pre) {
    // تحقق متفائل للمعاملات: ما قُرئ لم يتغير
    if (pre != null) {
      pre.forEach((path, ver) {
        final cur = docs[path]?.version ?? 0;
        if (cur != ver) {
          throw CloudError('aborted', 'Transaction conflict on $path');
        }
      });
    }
    // تحقق مسبق: update يتطلب وجود المستند (كل العملية تفشل ذرياً)
    final exists = <String, bool>{for (final p in docs.keys) p: true};
    for (final op in ops) {
      if (op.kind == 'update' && exists[op.path] != true) {
        throw CloudError('not-found', 'No document to update: ${op.path}');
      }
      if (op.kind == 'set') exists[op.path] = true;
      if (op.kind == 'delete') exists[op.path] = false;
    }
    final now = _serverNow();
    final changed = <String>{};
    for (final op in ops) {
      switch (op.kind) {
        case 'set':
          final prev = docs[op.path];
          Map<String, Object?> data;
          if (prev != null && (op.merge || op.mergeFields != null)) {
            data = _deepCopy(prev.data);
            if (op.mergeFields != null) {
              for (final f in op.mergeFields!) {
                final v = _get(op.data!, f);
                _setPath(data, f, v, now, prev: _get(prev.data, f));
              }
            } else {
              _mergeInto(data, op.data!, now);
            }
          } else {
            data = {};
            _mergeInto(data, op.data!, now);
          }
          docs[op.path] = _Doc(data, ++_ver);
          break;
        case 'update':
          final data = _deepCopy(docs[op.path]!.data);
          op.updates!.forEach((k, v) {
            final f = k.split('\u0000');
            _setPath(data, f, v, now, prev: _get(data, f));
          });
          docs[op.path] = _Doc(data, ++_ver);
          break;
        case 'delete':
          docs.remove(op.path);
          break;
      }
      changed.add(op.path);
      final coll = _parent(op.path);
      writesByCollection[coll] = (writesByCollection[coll] ?? 0) + 1;
      totalWrites++;
    }
    lastWriteAt = DateTime.now();
    _notify(changed);
  }

  void _mergeInto(Map<String, Object?> target, Map<String, Object?> src, Timestamp now) {
    src.forEach((k, v) {
      if (v is FV) {
        final r = _resolveFV(v, target[k], now);
        if (identical(r, _deleteMarker)) {
          target.remove(k);
        } else {
          target[k] = r;
        }
      } else if (v is Map) {
        final existing = target[k];
        final child = existing is Map
            ? Map<String, Object?>.from(existing)
            : <String, Object?>{};
        _mergeInto(child, v.cast<String, Object?>(), now);
        target[k] = child;
      } else {
        target[k] = _resolve(v, now);
      }
    });
  }

  static final Object _deleteMarker = Object();

  Object? _resolveFV(FV v, Object? prev, Timestamp now) {
    switch (v.kind) {
      case 'serverTimestamp':
        return now;
      case 'delete':
        return _deleteMarker;
      case 'increment':
        final n = v.arg as num;
        return prev is num ? prev + n : n;
      case 'arrayUnion':
        final list = prev is List ? List<Object?>.from(prev) : <Object?>[];
        for (final e in (v.arg as List)) {
          if (!list.any((x) => _eq(x, e))) list.add(e);
        }
        return list;
      case 'arrayRemove':
        final list = prev is List ? List<Object?>.from(prev) : <Object?>[];
        list.removeWhere((x) => (v.arg as List).any((e) => _eq(x, e)));
        return list;
    }
    throw CloudError('invalid-argument', 'Unknown FieldValue ${v.kind}');
  }

  Object? _resolve(Object? v, Timestamp now) {
    if (v is FV) return _resolveFV(v, null, now);
    if (v is DateTime) return Timestamp.fromDate(v);
    if (v is Map) {
      final m = <String, Object?>{};
      _mergeInto(m, v.cast<String, Object?>(), now);
      return m;
    }
    if (v is List) return [for (final e in v) _resolve(e, now)];
    return v;
  }

  void _setPath(Map<String, Object?> data, FieldPathSpec f, Object? v, Timestamp now,
      {Object? prev}) {
    Map<String, Object?> cur = data;
    for (var i = 0; i < f.length - 1; i++) {
      final next = cur[f[i]];
      final child = next is Map ? Map<String, Object?>.from(next) : <String, Object?>{};
      cur[f[i]] = child;
      cur = child;
    }
    final last = f.last;
    final r = v is FV ? _resolveFV(v, prev, now) : _resolve(v, now);
    if (identical(r, _deleteMarker)) {
      cur.remove(last);
    } else {
      cur[last] = r;
    }
  }

  // ───────────────────────── المستمعون ─────────────────────────

  void _notify(Set<String> changed) {
    for (final l in _listeners.values.toList()) {
      final relevant = l.docPath != null
          ? changed.contains(l.docPath)
          : changed.any((p) => _parent(p) == l.query!.collection);
      if (!relevant) continue;
      if (!_isOnline(l.device)) {
        l.dirty = true;
        continue;
      }
      _flush(l);
    }
  }

  void _flush(_Listener l, {bool initial = false}) {
    l.dirty = false;
    if (l.docPath != null) {
      final s = _snap(l.docPath!);
      final prevVer = l.lastSent[l.docPath!];
      if (!initial && l.sentOnce && prevVer == s.version) return;
      l.sentOnce = true;
      l.lastSent = {l.docPath!: s.version};
      l.port.send(ListenerEvent(l.id, [s], const []));
      return;
    }
    final paths = _matchPaths(l.query!);
    final now = {for (final p in paths) p: docs[p]!.version};
    final changes = <DocChangeMsg>[];
    final oldIndex = {for (var i = 0; i < l.lastOrder.length; i++) l.lastOrder[i]: i};
    for (var i = 0; i < paths.length; i++) {
      final p = paths[i];
      final before = l.lastSent[p];
      if (before == null) {
        changes.add(DocChangeMsg('added', -1, i, _snap(p)));
      } else if (before != now[p]) {
        changes.add(DocChangeMsg('modified', oldIndex[p] ?? -1, i, _snap(p)));
      }
    }
    for (final p in l.lastSent.keys) {
      if (!now.containsKey(p)) {
        changes.add(DocChangeMsg('removed', oldIndex[p] ?? -1, -1, DocSnap(p, null, 0)));
      }
    }
    if (!initial && l.sentOnce && changes.isEmpty) return;
    l.sentOnce = true;
    l.lastSent = now;
    l.lastOrder = paths;
    l.port.send(ListenerEvent(l.id, [for (final p in paths) _snap(p)], changes));
  }

  // ───────────────────────── القيم ─────────────────────────

  static bool _isDocId(FieldPathSpec f) => f.length == 1 && f[0] == '__name__';

  static bool _has(Map<String, Object?> data, FieldPathSpec f) {
    Object? cur = data;
    for (final c in f) {
      if (cur is! Map || !cur.containsKey(c)) return false;
      cur = cur[c];
    }
    return true;
  }

  static Object? _get(Map<String, Object?> data, FieldPathSpec f) {
    Object? cur = data;
    for (final c in f) {
      if (cur is! Map) return null;
      cur = cur[c];
    }
    return cur;
  }

  bool _matches(String path, Map<String, Object?> data, FieldPathSpec f, String op, Object? value) {
    final has = _isDocId(f) || _has(data, f);
    final v = _isDocId(f) ? _id(path) : _get(data, f);
    if (_isDocId(f) && value is String && value.contains('/')) value = _id(value);
    switch (op) {
      case '==':
        return has && _eq(v, value);
      case '!=':
        return has && v != null && !_eq(v, value);
      case '<':
        return has && _sameKind(v, value) && _cmp(v, value) < 0;
      case '<=':
        return has && _sameKind(v, value) && _cmp(v, value) <= 0;
      case '>':
        return has && _sameKind(v, value) && _cmp(v, value) > 0;
      case '>=':
        return has && _sameKind(v, value) && _cmp(v, value) >= 0;
      case 'in':
        return has && (value as List).any((e) => _eq(v, e));
      case 'not-in':
        return has && v != null && !(value as List).any((e) => _eq(v, e));
      case 'array-contains':
        return has && v is List && v.any((e) => _eq(e, value));
      case 'array-contains-any':
        return has && v is List && v.any((e) => (value as List).any((x) => _eq(e, x)));
    }
    throw CloudError('invalid-argument', 'Unsupported operator $op');
  }

  static int _rank(Object? v) {
    if (v == null) return 0;
    if (v is bool) return 1;
    if (v is num) return 2;
    if (v is Timestamp || v is DateTime) return 3;
    if (v is String) return 4;
    if (v is List) return 6;
    if (v is Map) return 7;
    return 8;
  }

  static bool _sameKind(Object? a, Object? b) => _rank(a) == _rank(b);

  static int _micros(Object v) => v is Timestamp
      ? v.seconds * 1000000 + v.nanoseconds ~/ 1000
      : (v as DateTime).microsecondsSinceEpoch;

  static int _cmp(Object? a, Object? b) {
    final ra = _rank(a), rb = _rank(b);
    if (ra != rb) return ra.compareTo(rb);
    if (a == null) return 0;
    if (a is bool) return (a ? 1 : 0).compareTo((b as bool) ? 1 : 0);
    if (a is num) return a.compareTo(b as num);
    if (ra == 3) return _micros(a).compareTo(_micros(b!));
    if (a is String) return a.compareTo(b as String);
    return 0;
  }

  static bool _eq(Object? a, Object? b) {
    if (a is num && b is num) return a == b;
    if (_rank(a) == 3 && _rank(b) == 3) return _micros(a!) == _micros(b!);
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_eq(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || !_eq(a[k], b[k])) return false;
      }
      return true;
    }
    return a == b;
  }

  static Map<String, Object?> _deepCopy(Map<String, Object?> m) {
    Object? copy(Object? v) {
      if (v is Map) return {for (final e in v.entries) e.key as String: copy(e.value)};
      if (v is List) return [for (final e in v) copy(e)];
      return v;
    }

    return {for (final e in m.entries) e.key: copy(e.value)};
  }

  // ───────────────────────── للفحص ─────────────────────────

  Map<String, Map<String, Object?>> collection(String name) => {
        for (final e in docs.entries)
          if (_parent(e.key) == name) _id(e.key): _deepCopy(e.value.data)
      };

  void clearCollection(String name) {
    final paths = docs.keys.where((p) => _parent(p) == name).toList();
    for (final p in paths) {
      docs.remove(p);
    }
    _notify(paths.toSet());
  }
}
