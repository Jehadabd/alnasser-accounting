// lib/services/firebase_sync/users_sync_service.dart
//
// 👥 مزامنة حسابات المستخدمين (المدير والموظفين) بين أجهزة الترخيص نفسه.
//
// • لنسخة «الشامل + المزامنة» فقط: الموظف الذي ينشئه المدير في أي جهاز يظهر في
//   كل الأجهزة، وتغيير كلمة سره أو صلاحياته أو حذفه ينتقل إليها.
// • المجموعة في Firestore: app_users/{sync_uuid}. تحمل اسم الدخول، وبصمة كلمة
//   السر (لا كلمة السر نفسها)، والدور، والصلاحيات، ووقت آخر تعديل.
// • التعارض: الأحدث تعديلاً يفوز (updated_ms).
// • الحذف: «شاهد حذف» (deleted=true) يُرفع قبل حذف الصف محلياً.
// • بلا إنترنت: التعديل يُعلَّم «غير مرفوع» ويُرفع عند عودة الاتصال.

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../database_service.dart';
import '../license_service.dart';

class UsersSyncService {
  UsersSyncService._();
  static final UsersSyncService instance = UsersSyncService._();

  static const String collection = 'app_users';

  FirebaseFirestore? _fs;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  Timer? _retry;
  bool _columnsReady = false;
  bool _uploading = false;
  final _changes = StreamController<void>.broadcast();

  /// يُطلق بعد تطبيق تغييرات واردة (تستمع له شاشة الدخول في الجهاز الإضافي)
  Stream<void> get changes => _changes.stream;
  bool get isRunning => _sub != null;

  bool get _allowed => LicenseService().getStoredLicense()?.isSyncAllowed ?? false;

  Future<void> _ensureSchema() async {
    if (_columnsReady) return;
    final db = await DatabaseService().database;
    final cols = (await db.rawQuery('PRAGMA table_info(users)')).map((r) => '${r['name']}').toSet();
    if (!cols.contains('sync_uuid')) await db.execute('ALTER TABLE users ADD COLUMN sync_uuid TEXT');
    if (!cols.contains('updated_ms')) await db.execute('ALTER TABLE users ADD COLUMN updated_ms INTEGER DEFAULT 0');
    if (!cols.contains('sync_dirty')) await db.execute('ALTER TABLE users ADD COLUMN sync_dirty INTEGER DEFAULT 1');
    if (!cols.contains('display_name')) await db.execute('ALTER TABLE users ADD COLUMN display_name TEXT');
    await db.execute('CREATE TABLE IF NOT EXISTS user_sync_tombstones ('
        'sync_uuid TEXT PRIMARY KEY, deleted_ms INTEGER NOT NULL, uploaded INTEGER NOT NULL DEFAULT 0)');
    _columnsReady = true;
  }

  static String _newUuid() {
    final r = Random.secure();
    return 'usr_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_'
        '${List.generate(10, (_) => r.nextInt(36).toRadixString(36)).join()}';
  }

  // ═══════════════════════════ التشغيل ═══════════════════════════

  Future<void> start(FirebaseFirestore fs) async {
    if (!_allowed) return;
    _fs = fs;
    await _ensureSchema();
    await _sub?.cancel();
    _sub = fs.collection(collection).snapshots().listen(
          _onSnapshot,
          onError: (Object e) => debugPrint('👥 [UsersSync] مستمع: $e'),
        );
    _retry ??= Timer.periodic(const Duration(minutes: 3), (_) => uploadPending());
    unawaited(uploadPending());
    debugPrint('👥 [UsersSync] بدأت مزامنة المستخدمين');
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _retry?.cancel();
    _retry = null;
    _fs = null;
  }

  // ═══════════════════════════ التعديلات المحلية ═══════════════════════════

  /// يُستدعى بعد أي تعديل محلي على مستخدم (إنشاء، كلمة سر، صلاحيات، اسم...).
  Future<void> markChanged(int? userId) async {
    if (userId == null) return;
    try {
      await _ensureSchema();
      final db = await DatabaseService().database;
      final rows = await db.query('users', columns: ['sync_uuid'], where: 'id = ?', whereArgs: [userId]);
      if (rows.isEmpty) return;
      final old = rows.first['sync_uuid'] as String?;
      await db.update(
        'users',
        {
          'sync_uuid': (old != null && old.isNotEmpty) ? old : _newUuid(),
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
          'sync_dirty': 1,
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
      unawaited(uploadPending());
    } catch (e) {
      debugPrint('👥 [UsersSync] markChanged: $e');
    }
  }

  /// يُستدعى قبل حذف مستخدم محلياً: يُرفع «شاهد حذف» فيُحذف من بقية الأجهزة.
  Future<void> markDeleted(int userId) async {
    try {
      await _ensureSchema();
      final db = await DatabaseService().database;
      final rows = await db.query('users', columns: ['sync_uuid'], where: 'id = ?', whereArgs: [userId]);
      final uuid = rows.isEmpty ? null : rows.first['sync_uuid'] as String?;
      if (uuid == null || uuid.isEmpty) return;
      await db.rawInsert(
        'INSERT OR REPLACE INTO user_sync_tombstones(sync_uuid, deleted_ms, uploaded) VALUES(?, ?, 0)',
        [uuid, DateTime.now().millisecondsSinceEpoch],
      );
      unawaited(uploadPending());
    } catch (e) {
      debugPrint('👥 [UsersSync] markDeleted: $e');
    }
  }

  /// رفع كل ما لم يُرفع بعد (عند التشغيل، بعد كل تعديل، وكل 3 دقائق).
  Future<void> uploadPending() async {
    final fs = _fs;
    if (fs == null || !_allowed || _uploading) return;
    _uploading = true;
    try {
      await _ensureSchema();
      final db = await DatabaseService().database;
      final rows = await db.query('users', where: 'sync_dirty = 1 OR sync_uuid IS NULL');
      for (final row in rows) {
        final id = row['id'] as int;
        var uuid = row['sync_uuid'] as String?;
        var ms = (row['updated_ms'] as num?)?.toInt() ?? 0;
        if (uuid == null || uuid.isEmpty || ms == 0) {
          uuid = (uuid == null || uuid.isEmpty) ? _newUuid() : uuid;
          if (ms == 0) ms = DateTime.now().millisecondsSinceEpoch;
          await db.update('users', {'sync_uuid': uuid, 'updated_ms': ms}, where: 'id = ?', whereArgs: [id]);
        }
        final perms = (await db.query('user_permissions',
                columns: ['permission_key'], where: 'user_id = ?', whereArgs: [id]))
            .map((r) => '${r['permission_key']}')
            .toList();
        await fs.collection(collection).doc(uuid).set({
          'uuid': uuid,
          'username': row['username'],
          'password_hash': row['password_hash'],
          'role': row['role'],
          'display_name': row['display_name'],
          'permissions': perms,
          'updated_ms': ms,
          'deleted': false,
          'uploadedAt': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 20));
        await db.update('users', {'sync_dirty': 0},
            where: 'id = ? AND IFNULL(updated_ms, 0) = ?', whereArgs: [id, ms]);
      }
      final tombs = await db.query('user_sync_tombstones', where: 'uploaded = 0');
      for (final t in tombs) {
        final uuid = '${t['sync_uuid']}';
        await fs.collection(collection).doc(uuid).set({
          'uuid': uuid,
          'deleted': true,
          'updated_ms': t['deleted_ms'],
          'uploadedAt': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 20));
        await db.update('user_sync_tombstones', {'uploaded': 1}, where: 'sync_uuid = ?', whereArgs: [uuid]);
      }
    } catch (e) {
      debugPrint('👥 [UsersSync] رفع (سيُعاد لاحقاً): $e');
    } finally {
      _uploading = false;
    }
  }

  // ═══════════════════════════ التغييرات الواردة ═══════════════════════════

  Future<void> _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) async {
    var applied = 0;
    for (final c in snap.docChanges) {
      if (c.doc.metadata.hasPendingWrites) continue;
      final d = c.doc.data();
      if (d == null) continue;
      try {
        if (await _apply(c.doc.id, d)) applied++;
      } catch (e) {
        debugPrint('👥 [UsersSync] تطبيق ${c.doc.id}: $e');
      }
    }
    if (applied > 0) debugPrint('👥 [UsersSync] طُبّق $applied تغيير وارد');
    _changes.add(null);
  }

  Future<bool> _apply(String docId, Map<String, dynamic> d) async {
    await _ensureSchema();
    final db = await DatabaseService().database;
    final uuid = '${d['uuid'] ?? docId}';
    final remoteMs = (d['updated_ms'] as num?)?.toInt() ?? 0;

    var local = await db.query('users', where: 'sync_uuid = ?', whereArgs: [uuid], limit: 1);

    if (d['deleted'] == true) {
      if (local.isEmpty || local.first['role'] == 'admin') return false;
      final id = local.first['id'] as int;
      await db.delete('user_permissions', where: 'user_id = ?', whereArgs: [id]);
      await db.delete('users', where: 'id = ?', whereArgs: [id]);
      return true;
    }

    final username = '${d['username'] ?? ''}'.trim();
    final hash = '${d['password_hash'] ?? ''}';
    if (username.isEmpty || hash.isEmpty) return false;
    if (local.isEmpty) {
      local = await db.query('users', where: 'username = ?', whereArgs: [username], limit: 1);
    }
    final perms = (d['permissions'] as List? ?? const []).map((e) => '$e').toList();
    final values = <String, Object?>{
      'username': username,
      'password_hash': hash,
      'role': '${d['role'] ?? 'accountant'}',
      'display_name': d['display_name'],
      'sync_uuid': uuid,
      'updated_ms': remoteMs,
      'sync_dirty': 0,
    };

    int id;
    if (local.isNotEmpty) {
      final row = local.first;
      final localMs = (row['updated_ms'] as num?)?.toInt() ?? 0;
      final dirty = (row['sync_dirty'] as num?)?.toInt() == 1;
      final sameUuid = (row['sync_uuid'] as String?) == uuid;
      if (remoteMs < localMs || (remoteMs == localMs && (dirty || sameUuid))) {
        // المحلي أحدث (أو هو نفسه): يبقى، ويُرفع هو إن لزم
        if (!sameUuid) {
          await db.update('users', {'sync_uuid': uuid, 'sync_dirty': 1}, where: 'id = ?', whereArgs: [row['id']]);
        }
        return false;
      }
      id = row['id'] as int;
      final clash = await db.query('users',
          columns: ['id'], where: 'username = ? AND id != ?', whereArgs: [username, id], limit: 1);
      if (clash.isNotEmpty) values.remove('username');
      await db.update('users', values, where: 'id = ?', whereArgs: [id]);
    } else {
      id = await db.insert('users', {...values, 'created_at': DateTime.now().toIso8601String()});
    }
    await db.delete('user_permissions', where: 'user_id = ?', whereArgs: [id]);
    for (final p in perms.toSet()) {
      await db.insert('user_permissions', {'user_id': id, 'permission_key': p});
    }
    return true;
  }
}
