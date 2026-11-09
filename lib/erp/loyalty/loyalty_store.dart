// lib/erp/loyalty/loyalty_store.dart
//
// 🗄️ برنامج الولاء: الأعضاء، ما صُرف من مكافآت، والإعدادات (في قاعدة البيانات: مشتركة لكل
// الأجهزة على القاعدة نفسها). أرصدة النقاط تُشتق من محرك التقارير (SalesFacts) — قراءة فقط
// للفواتير. صرف مكافأة لا يغيّر أي فاتورة ولا دين: الكاشير يطبّقها خصماً في الفاتورة.

import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../services/database_service.dart';
import '../../services/reports/sales_facts.dart';
import '../erp_common.dart';
import 'loyalty_models.dart';

class LoyaltyRow {
  LoyaltyRow(this.member, this.balance);
  final LoyaltyMember member;
  final LoyaltyBalance balance;
}

class LoyaltyStore {
  LoyaltyStore({Future<Database> Function()? db}) : _getDb = db ?? (() => DatabaseService().database);
  final Future<Database> Function() _getDb;
  static int _readyGen = -1;

  Future<Database> _db() async {
    final db = await _getDb();
    if (_readyGen != DatabaseService.openGeneration) {
      await ensureSchema(db);
      _readyGen = DatabaseService.openGeneration;
    }
    return db;
  }

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS loyalty_settings (k TEXT PRIMARY KEY, v TEXT)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS loyalty_members (
        customer_id INTEGER PRIMARY KEY,
        card_no TEXT NOT NULL UNIQUE,
        joined_at TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS loyalty_redemptions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        units INTEGER NOT NULL CHECK (units > 0),
        reward TEXT NOT NULL,
        at TEXT NOT NULL,
        by_user TEXT
      )''');
  }

  // ───────────── الإعدادات ─────────────

  Future<LoyaltySettings> settings() async {
    final db = await _db();
    final rows = await db.query('loyalty_settings');
    return LoyaltySettings.fromMap({for (final r in rows) '${r['k']}': '${r['v'] ?? ''}'});
  }

  Future<void> saveSettings(LoyaltySettings s) async {
    final db = await _db();
    await db.transaction((txn) async {
      for (final e in s.toMap().entries) {
        await txn.insert('loyalty_settings', {'k': e.key, 'v': e.value}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // ───────────── الأعضاء ─────────────

  static String _newCard(Random r) => List.generate(10, (_) => r.nextInt(10)).join();

  Future<String> join(int customerId) async {
    final db = await _db();
    final cur = await db.query('loyalty_members', where: 'customer_id = ?', whereArgs: [customerId]);
    if (cur.isNotEmpty) {
      await db.update('loyalty_members', {'active': 1}, where: 'customer_id = ?', whereArgs: [customerId]);
      return '${cur.first['card_no']}';
    }
    final r = Random.secure();
    for (var i = 0; i < 5; i++) {
      final card = _newCard(r);
      try {
        await db.insert('loyalty_members', {
          'customer_id': customerId,
          'card_no': card,
          'joined_at': DateTime.now().toIso8601String(),
          'active': 1,
        });
        return card;
      } on DatabaseException {
        // رقم بطاقة مكرر (نادر جداً): رقم آخر
      }
    }
    throw ErpException('تعذّر إنشاء رقم بطاقة — أعد المحاولة');
  }

  Future<void> setActive(int customerId, bool active) async {
    final db = await _db();
    await db.update('loyalty_members', {'active': active ? 1 : 0}, where: 'customer_id = ?', whereArgs: [customerId]);
  }

  /// الأعضاء مع أرصدتهم (من مبيعاتهم منذ الانضمام).
  Future<List<LoyaltyRow>> members({bool activeOnly = false}) async {
    final db = await _db();
    final s = await settings();
    final rows = await db.rawQuery('''
      SELECT m.customer_id, m.card_no, m.joined_at, m.active, c.name, c.phone
      FROM loyalty_members m JOIN customers c ON c.id = m.customer_id
      WHERE COALESCE(c.is_deleted, 0) = 0 ${activeOnly ? 'AND m.active = 1' : ''}
      ORDER BY c.name''');
    if (rows.isEmpty) return [];
    final members = [
      for (final r in rows)
        LoyaltyMember(
          customerId: r['customer_id'] as int,
          name: '${r['name'] ?? ''}',
          phone: r['phone'] as String?,
          cardNo: '${r['card_no']}',
          joinedAt: DateTime.tryParse('${r['joined_at']}') ?? DateTime(2000),
          active: r['active'] == 1,
        ),
    ];
    final from = members.map((m) => m.joinedAt).reduce((a, b) => a.isBefore(b) ? a : b);
    final facts = await SalesFacts.load(db, from: from);
    final redeemed = {
      for (final r in await db.rawQuery('SELECT customer_id AS c, SUM(units) AS u FROM loyalty_redemptions GROUP BY customer_id'))
        r['c'] as int: (r['u'] as num?)?.toInt() ?? 0,
    };
    final invoices = <int, List<int>>{};
    final returns = <int, int>{};
    final joined = {for (final m in members) m.customerId: m.joinedAt};
    bool after(int? c, DateTime d) => c != null && joined[c] != null && !d.isBefore(joined[c]!);
    for (final i in facts.invoices) {
      if (after(i.customerId, i.date)) (invoices[i.customerId!] ??= []).add((i.netSales * 100).round());
    }
    for (final r in facts.returns) {
      if (after(r.customerId, r.date)) returns[r.customerId!] = (returns[r.customerId!] ?? 0) + (r.total * 100).round();
    }
    return [
      for (final m in members)
        LoyaltyRow(
          m,
          LoyaltyBalance.of(s,
              invoiceNetFils: invoices[m.customerId] ?? const [],
              returnsFils: returns[m.customerId] ?? 0,
              redeemed: redeemed[m.customerId] ?? 0),
        ),
    ];
  }

  /// صرف مكافأة واحدة (يُرفض إن لم يكفِ الرصيد لحظة الصرف).
  Future<void> redeem(LoyaltyRow row) async {
    final s = await settings();
    final fresh = (await members()).where((r) => r.member.customerId == row.member.customerId).toList();
    if (fresh.isEmpty || fresh.first.balance.rewardsAvailable < 1) {
      throw ErpException('الرصيد لا يكفي لمكافأة الآن');
    }
    final db = await _db();
    await db.insert('loyalty_redemptions', {
      'customer_id': row.member.customerId,
      'units': s.unitsPerReward,
      'reward': s.rewardText,
      'at': DateTime.now().toIso8601String(),
      'by_user': currentUserName(),
    });
  }

  Future<List<Map<String, Object?>>> redemptions(int customerId) async {
    final db = await _db();
    return db.query('loyalty_redemptions', where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'id DESC');
  }
}
