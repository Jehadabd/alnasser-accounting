// lib/marketing/marketing_store.dart
//
// 📣 مركز التسويق — البيانات: الحسابات (صفحة فيسبوك وإنستغرامها)، المنشورات المجدولة،
// والحملات. الرمز في التخزين الآمن فقط. جداول محلية لا تمس الحسابات المالية.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';

enum MkStatus { draft, scheduled, publishing, published, failed }

class MkPost {
  MkPost({
    this.id,
    required this.text,
    this.imagePath,
    this.imageUrl,
    required this.at,
    this.facebook = true,
    this.instagram = false,
    this.status = MkStatus.scheduled,
    this.fbId,
    this.igId,
    this.error,
    this.campaignId,
    this.publishedAt,
  });
  final int? id;
  final String text;

  /// صورة من الجهاز (فيسبوك) و/أو رابط عام (إنستغرام).
  final String? imagePath, imageUrl;
  final DateTime at;
  final bool facebook, instagram;
  final MkStatus status;
  final String? fbId, igId, error;
  final int? campaignId;
  final DateTime? publishedAt;

  Map<String, Object?> toMap() => {
        'text': text,
        'image_path': imagePath,
        'image_url': imageUrl,
        'at': at.toIso8601String(),
        'facebook': facebook ? 1 : 0,
        'instagram': instagram ? 1 : 0,
        'status': status.name,
        'fb_id': fbId,
        'ig_id': igId,
        'error': error,
        'campaign_id': campaignId,
        'published_at': publishedAt?.toIso8601String(),
      };

  factory MkPost.fromMap(Map<String, Object?> m) => MkPost(
        id: m['id'] as int?,
        text: '${m['text'] ?? ''}',
        imagePath: m['image_path'] as String?,
        imageUrl: m['image_url'] as String?,
        at: DateTime.tryParse('${m['at']}') ?? DateTime.now(),
        facebook: m['facebook'] == 1,
        instagram: m['instagram'] == 1,
        status: MkStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => MkStatus.draft),
        fbId: m['fb_id'] as String?,
        igId: m['ig_id'] as String?,
        error: m['error'] as String?,
        campaignId: m['campaign_id'] as int?,
        publishedAt: DateTime.tryParse('${m['published_at'] ?? ''}'),
      );

  /// سبب عدم صلاحية المنشور للنشر، أو null. دالة صافية.
  String? get problem {
    if (text.trim().isEmpty && (imagePath ?? '').isEmpty) return 'منشور فارغ';
    if (!facebook && !instagram) return 'اختر فيسبوك أو إنستغرام';
    if (instagram && !(imageUrl ?? '').startsWith('https://')) {
      return 'إنستغرام يحتاج رابط صورة عاماً يبدأ بـ https:// (شرط Meta)';
    }
    if (text.length > 2200 && instagram) return 'نص إنستغرام حتى 2200 حرف';
    return null;
  }
}

class MarketingStore {
  MarketingStore({Future<Database> Function()? db}) : _getDb = db ?? (() => DatabaseService().database);
  final Future<Database> Function() _getDb;
  static int _readyGen = -1;
  static const _secure = FlutterSecureStorage();
  static const _kToken = 'mk_meta_page_token';

  Future<Database> _db() async {
    final db = await _getDb();
    if (_readyGen != DatabaseService.openGeneration) {
      await ensureSchema(db);
      _readyGen = DatabaseService.openGeneration;
    }
    return db;
  }

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS mk_settings (k TEXT PRIMARY KEY, v TEXT)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS mk_posts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        text TEXT NOT NULL, image_path TEXT, image_url TEXT, at TEXT NOT NULL,
        facebook INTEGER NOT NULL DEFAULT 1, instagram INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL, fb_id TEXT, ig_id TEXT, error TEXT, campaign_id INTEGER, published_at TEXT
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS mk_campaigns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, from_day TEXT NOT NULL, to_day TEXT NOT NULL, goal TEXT, notes TEXT
      )''');
  }

  // ───────────── الحساب ─────────────

  Future<String?> token() => _secure.read(key: _kToken);
  Future<void> setToken(String? t) async =>
      (t == null || t.trim().isEmpty) ? _secure.delete(key: _kToken) : _secure.write(key: _kToken, value: t.trim());

  Future<Map<String, String>> settings() async {
    final db = await _db();
    return {for (final r in await db.query('mk_settings')) '${r['k']}': '${r['v'] ?? ''}'};
  }

  Future<void> setSetting(String k, String? v) async {
    final db = await _db();
    if (v == null) {
      await db.delete('mk_settings', where: 'k = ?', whereArgs: [k]);
    } else {
      await db.insert('mk_settings', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // ───────────── المنشورات ─────────────

  Future<List<MkPost>> posts({int limit = 300}) async {
    final db = await _db();
    return (await db.query('mk_posts', orderBy: 'at DESC', limit: limit)).map(MkPost.fromMap).toList();
  }

  Future<List<MkPost>> due(DateTime now) async {
    final db = await _db();
    return (await db.query('mk_posts', where: "status = 'scheduled' AND at <= ?", whereArgs: [now.toIso8601String()], orderBy: 'at'))
        .map(MkPost.fromMap)
        .toList();
  }

  Future<int> savePost(MkPost p) async {
    final db = await _db();
    if (p.id == null) return db.insert('mk_posts', p.toMap());
    await db.update('mk_posts', p.toMap(), where: "id = ? AND status != 'published'", whereArgs: [p.id]);
    return p.id!;
  }

  Future<void> deletePost(int id) async {
    final db = await _db();
    await db.delete('mk_posts', where: "id = ? AND status != 'published'", whereArgs: [id]);
  }

  /// يحجز المنشور للنشر (scheduled ⇒ publishing) — يمنع نشره مرتين من جهازين أو مؤقّتين.
  Future<bool> claim(int id) async {
    final db = await _db();
    return await db.update('mk_posts', {'status': 'publishing'}, where: "id = ? AND status = 'scheduled'", whereArgs: [id]) == 1;
  }

  Future<void> markResult(int id, {String? fbId, String? igId, String? error}) async {
    final db = await _db();
    await db.update(
      'mk_posts',
      {
        'status': error == null ? 'published' : 'failed',
        'fb_id': fbId,
        'ig_id': igId,
        'error': error,
        'published_at': error == null ? DateTime.now().toIso8601String() : null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> publishedToday() async {
    final db = await _db();
    final d = DateTime.now();
    final day = DateTime(d.year, d.month, d.day).toIso8601String();
    final r = await db.rawQuery("SELECT COUNT(*) AS n FROM mk_posts WHERE status = 'published' AND published_at >= ?", [day]);
    return ((r.first['n'] as num?) ?? 0).toInt();
  }

  Future<DateTime?> lastPublished() async {
    final db = await _db();
    final r = await db.rawQuery("SELECT MAX(published_at) AS t FROM mk_posts WHERE status = 'published'");
    return DateTime.tryParse('${r.first['t'] ?? ''}');
  }

  // ───────────── الحملات ─────────────

  Future<List<Map<String, Object?>>> campaigns() async {
    final db = await _db();
    return db.query('mk_campaigns', orderBy: 'id DESC');
  }

  Future<int> addCampaign(String name, DateTime from, DateTime to, String goal) async {
    final db = await _db();
    return db.insert('mk_campaigns', {
      'name': name.trim(),
      'from_day': from.toIso8601String().substring(0, 10),
      'to_day': to.toIso8601String().substring(0, 10),
      'goal': goal.trim(),
    });
  }
}
