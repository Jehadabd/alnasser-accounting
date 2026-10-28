// ═══════════════════════════════════════════════════════════════════════════
// 🛡️ حارس الهجرة — الديون لا تتغير بتحويل القاعدة
// ═══════════════════════════════════════════════════════════════════════════
//
// كل فتح يكمل القاعدة (أعمدة، جداول، فهارس، ترقيم فواتير، دمج عميل مكرر...).
// هذه خطوات يُفترض ألّا تمسّ رقماً مالياً — والحارس يثبت ذلك بدل أن يفترضه:
//
//   1) قبل أي هجرة: لقطة كاملة لكل ما يصنع الدين (رصيد كل عميل، كل معاملة،
//      كل فاتورة وأصنافها، نقاط المؤسسين، أرصدة الموردين، سندات القبض)
//      + نسخة احتياطية من الملف نفسه.
//   2) تعمل الهجرات كالمعتاد.
//   3) بعدها: لقطة ثانية تُقارن بالأولى رقماً رقماً. المسموح فقط ما لا يغيّر
//      مالاً: إضافة أعمدة/جداول، إكمال حقول الترقيم، دمج صفّين للعميل نفسه
//      (يُقارن مجموع رصيديهما)، ملء معرّفات المزامنة.
//   4) أي اختلاف ⇒ تُعاد النسخة الاحتياطية كما كانت حرفياً ويُرفع
//      MigrationGuardException بقائمة الفروقات (لا يُفتح البرنامج على أرقام
//      تغيّرت ولا يُحذف شيء).
//
// يعمل الحارس عند: استيراد/استعادة قاعدة (forceNext)، أو قاعدة لم يمرّ عليها
// هذا البرنامج بهذا الإصدار (إصدار القاعدة + مراجعة الهجرات + بصمة البناء). الفتح العادي بلا تغيير
// لا يكلّف شيئاً.

import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class MigrationGuardException implements Exception {
  final List<String> problems;
  final String backupPath;
  const MigrationGuardException(this.problems, this.backupPath);

  @override
  String toString() =>
      'MigrationGuardException: ${problems.length} اختلاف — ${problems.take(5).join(' | ')}';
}

/// ملخص آخر تحقق ناجح (يعرضه الاستيراد للمستخدم).
class MigrationReport {
  final int customers;
  final int transactions;
  final int invoices;
  final int orphanTransactions;
  final double totalDebt;
  final String backupPath;
  const MigrationReport({
    required this.customers,
    required this.transactions,
    required this.invoices,
    required this.orphanTransactions,
    required this.totalDebt,
    required this.backupPath,
  });
}

class MigrationGuard {
  /// ⚠️ زِد هذا الرقم عند تعديل أي خطوة هجرة تكتب بيانات، فيعمل الحارس مرة
  /// على كل جهاز بعد التحديث حتى لو لم يتغير المخطط.
  static const int codeRev = 1;

  /// يُضبط قبل فتح قاعدة مستوردة/مستعادة: الحارس يعمل مهما كان ختمها.
  static bool forceNext = false;

  /// آخر تحقق ناجح في هذه الجلسة (null إن لم يعمل الحارس).
  static MigrationReport? lastReport;

  /// رفضٌ في هذه الجلسة: الفتح لا يُعاد صامتاً (كل محاولة = نسخة 80MB جديدة).
  /// الاستيراد يمسحه قبل إعادة فتح القاعدة السابقة.
  static MigrationGuardException? blocked;

  static const String _metaTable = 'app_meta';
  static const String _stampKey = 'migration_guard_stamp';
  static const int _keepBackups = 3;
  static const int _maxProblems = 150;

  final String dbPath;
  final String backupPath;
  final _Snap _before;
  MigrationGuard._(this.dbPath, this.backupPath, this._before);

  // ─────────────────────────────────────────────────────────────────────────
  // 1) قبل الهجرة
  // ─────────────────────────────────────────────────────────────────────────

  /// يُستدعى قبل openDatabase الحقيقي. يعيد null إن لم تلزم حراسة
  /// (قاعدة جديدة، أو مرّ عليها هذا البناء من قبل ولم يتغير مخططها).
  static Future<MigrationGuard?> prepare(String path) async {
    final marker = File('$path.guard_force');
    final force = forceNext || await marker.exists();
    forceNext = false;
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) return null;

    Database? raw;
    try {
      // فتح خام: بلا version فلا onUpgrade، وبلا singleInstance فلا يُشارك
      // الاتصال الذي سيفتحه البرنامج بعده.
      raw = await openDatabase(path, singleInstance: false);
      final core = await raw.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('customers','transactions')");
      if (core.length < 2) return null; // ليست قاعدة ديون (أو فارغة)

      if (!force) {
        final stored = await _readStamp(raw);
        if (stored != null && stored == await _stamp(raw)) return null;
      }

      final snap = await _Snap.take(raw);
      try {
        if (await marker.exists()) await marker.delete();
      } catch (_) {}
      try {
        await raw.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {}
      await raw.close();
      raw = null;

      final backup = await _backup(path);
      debugPrint('🛡️ حارس الهجرة: لقطة قبل التحويل — ${snap.custDebt.length} عميل، '
          '${snap.tx.length} معاملة، ${snap.inv.length} فاتورة. نسخة: $backup');
      return MigrationGuard._(path, backup, snap);
    } catch (e) {
      // تعذّر أخذ اللقطة ⇒ لا ضمان ⇒ لا نهاجر على العمياء
      throw MigrationGuardException(
          ['تعذّر فحص القاعدة قبل تحويلها: $e'], '');
    } finally {
      try {
        await raw?.close();
      } catch (_) {}
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2) بعد الهجرة
  // ─────────────────────────────────────────────────────────────────────────

  /// يقارن القاعدة بعد الهجرة بلقطة ما قبلها. يعيد قائمة الفروقات (فارغة = سليم).
  Future<List<String>> verify(DatabaseExecutor db) async {
    final a = await _Snap.take(db, like: _before);
    final b = _before;
    final out = <String>[];
    void add(String s) {
      if (out.length < _maxProblems) out.add(s);
    }

    // ── العملاء: كل صف قديم يجب أن يبقى بنفس id، أو يُدمج في صف يحمل نفس sync_uuid
    final afterByUuid = <String, int>{};
    a.custUuid.forEach((id, u) {
      if (u != null && u.isNotEmpty) afterByUuid.putIfAbsent(u, () => id);
    });
    final mapCust = <int, int>{};
    for (final id in b.custDebt.keys) {
      if (a.custDebt.containsKey(id)) {
        mapCust[id] = id;
      } else {
        final u = b.custUuid[id];
        final to = (u != null && u.isNotEmpty) ? afterByUuid[u] : null;
        if (to != null) {
          mapCust[id] = to;
        } else {
          add('اختفى العميل «${b.custName[id]}» (#$id) ورصيده ${_m(b.custDebt[id]!)}');
        }
      }
    }
    final expected = <int, int>{};
    mapCust.forEach((from, to) => expected[to] = (expected[to] ?? 0) + b.custDebt[from]!);
    expected.forEach((id, cents) {
      final got = a.custDebt[id] ?? 0;
      if (got != cents) {
        add('تغيّر رصيد «${a.custName[id] ?? b.custName[id]}» (#$id): ${_m(cents)} ← ${_m(got)}');
      }
    });
    a.custDebt.forEach((id, cents) {
      if (!expected.containsKey(id) && cents != 0) {
        add('ظهر عميل جديد «${a.custName[id]}» (#$id) برصيد ${_m(cents)}');
      }
    });
    int custOf(int? beforeCust) =>
        beforeCust == null ? -1 : (mapCust[beforeCust] ?? beforeCust);

    // ── المعاملات: كل معاملة بنفس المبلغ والرصيد والنوع والعميل — لا حذف ولا إضافة
    b.tx.forEach((id, sig) {
      final s = a.tx[id];
      if (s == null) {
        add('حُذفت المعاملة #$id ($sig)');
      } else if (s != sig) {
        add('تغيّرت المعاملة #$id: $sig ← $s');
      } else if ((a.txCust[id] ?? -1) != custOf(b.txCust[id])) {
        add('انتقلت المعاملة #$id من العميل #${b.txCust[id]} إلى #${a.txCust[id]}');
      }
    });
    for (final id in a.tx.keys) {
      if (!b.tx.containsKey(id)) add('أُضيفت معاملة جديدة #$id أثناء التحويل (${a.tx[id]})');
    }

    // ── الفواتير
    b.inv.forEach((id, sig) {
      final s = a.inv[id];
      if (s == null) {
        add('حُذفت الفاتورة #$id');
      } else if (s != sig) {
        add('تغيّرت الفاتورة #$id: $sig ← $s');
      } else if ((a.invCust[id] ?? -1) != custOf(b.invCust[id])) {
        add('انتقلت الفاتورة #$id من العميل #${b.invCust[id]} إلى #${a.invCust[id]}');
      }
      final n = b.invNumber[id];
      if (n != null && n.isNotEmpty && a.invNumber[id] != n) {
        add('تغيّر رقم الفاتورة #$id: $n ← ${a.invNumber[id]}');
      }
    });
    for (final id in a.inv.keys) {
      if (!b.inv.containsKey(id)) add('أُضيفت فاتورة جديدة #$id أثناء التحويل');
    }

    // ── أصناف الفواتير، المؤسسون، الموردون، السندات (مجاميع مسمّاة)
    b.extra.forEach((k, v) {
      final w = a.extra[k];
      if (w != v) add('تغيّر $k: $v ← ${w ?? 'غير موجود'}');
    });

    if (b.totalDebt != a.totalDebt && out.isEmpty) {
      add('تغيّر مجموع الديون: ${_m(b.totalDebt)} ← ${_m(a.totalDebt)}');
    }

    if (out.isEmpty) {
      lastReport = MigrationReport(
        customers: a.custDebt.length,
        transactions: a.tx.length,
        invoices: a.inv.length,
        orphanTransactions: a.orphanTx,
        totalDebt: a.totalDebt / 100.0,
        backupPath: backupPath,
      );
      debugPrint('✅ حارس الهجرة: مطابق 100% — ${a.custDebt.length} عميل، ${a.tx.length} معاملة، '
          '${a.inv.length} فاتورة، مجموع الديون ${_m(a.totalDebt)}');
    } else {
      debugPrint('⛔ حارس الهجرة: ${out.length} اختلاف بعد التحويل:\n  ${out.take(20).join('\n  ')}');
    }
    return out;
  }

  /// يعيد الملف كما كان قبل الهجرة حرفياً. القاعدة يجب أن تكون مغلقة.
  Future<void> rollback() async {
    for (final s in ['-wal', '-shm', '-journal']) {
      try {
        final f = File('$dbPath$s');
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await File(backupPath).copy(dbPath);
    final bw = File('$backupPath-wal');
    if (await bw.exists()) await bw.copy('$dbPath-wal');
    debugPrint('↩️ حارس الهجرة: أُعيدت القاعدة كما كانت من $backupPath');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // الختم: «مرّ هذا البناء على هذه القاعدة بهذا المخطط»
  // ─────────────────────────────────────────────────────────────────────────

  /// ملف القاعدة استُبدل وهي مغلقة (استعادة Dropbox ونحوها، وقد يُعاد تشغيل
  /// البرنامج بعدها): الحارس يعمل في الفتح القادم مهما كان ختم الملف.
  static Future<void> requestOnNextOpen(String dbPath) async {
    try {
      await File('$dbPath.guard_force').writeAsString('1');
    } catch (_) {}
  }

  /// يُستدعى في نهاية كل فتح ناجح.
  static Future<void> writeStamp(Database db) async {
    try {
      await db.execute(
          'CREATE TABLE IF NOT EXISTS $_metaTable (key TEXT PRIMARY KEY, value TEXT)');
      final st = await _stamp(db);
      await db.rawInsert(
          'INSERT OR REPLACE INTO $_metaTable(key, value) VALUES(?, ?)', [_stampKey, st]);
    } catch (e) {
      debugPrint('⚠️ حارس الهجرة: تعذّر حفظ الختم: $e');
    }
  }

  static Future<String?> _readStamp(DatabaseExecutor db) async {
    try {
      final r = await db.rawQuery(
          'SELECT value FROM $_metaTable WHERE key = ?', [_stampKey]);
      return r.isEmpty ? null : r.first['value'] as String?;
    } catch (_) {
      return null; // قاعدة من برنامج آخر: لا جدول ختم
    }
  }

  /// الختم = إصدار القاعدة + رقم مراجعة الهجرات + بصمة البناء. (لا يدخل فيه
  /// المخطط كاملاً: جداول تُنشأ عند الحاجة بعد الفتح كانت ستغيّره فيعمل
  /// الحارس — ونسخة 80MB — عند كل تشغيل.)
  static Future<String> _stamp(DatabaseExecutor db) async {
    final v = await db.rawQuery('PRAGMA user_version');
    final s = 'v=${v.first.values.first}|rev=$codeRev|build=${_buildId()}';
    return sha1.convert(utf8.encode(s)).toString();
  }

  /// بصمة البناء على الحاسبة: كل بناء جديد للبرنامج ⇒ يعمل الحارس مرة.
  static String? _buildIdCache;
  static String _buildId() {
    if (_buildIdCache != null) return _buildIdCache!;
    String id = '-';
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final dir = p.dirname(Platform.resolvedExecutable);
        for (final rel in [
          p.join('data', 'app.so'),
          p.join('data', 'flutter_assets', 'kernel_blob.bin'),
          p.join('lib', 'libapp.so'),
        ]) {
          final f = File(p.join(dir, rel));
          if (f.existsSync()) {
            final st = f.statSync();
            id = '${st.size}-${st.modified.millisecondsSinceEpoch}';
            break;
          }
        }
      }
    } catch (_) {}
    return _buildIdCache = id;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // النسخة الاحتياطية
  // ─────────────────────────────────────────────────────────────────────────

  static Future<String> _backup(String path) async {
    final dir = Directory(p.join(p.dirname(path), 'migration_backups'));
    await dir.create(recursive: true);
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    final name = 'before_migration_${n.year}${two(n.month)}${two(n.day)}_'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}.db';
    final target = p.join(dir.path, name);
    await File(path).copy(target);
    final wal = File('$path-wal');
    if (await wal.exists() && await wal.length() > 0) {
      await wal.copy('$target-wal');
    }
    // تبقى أحدث 3 نسخ فقط (نسخ هذا الحارس وحده)
    try {
      final all = dir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('before_migration_') &&
              f.path.endsWith('.db'))
          .toList()
        ..sort((x, y) => y.path.compareTo(x.path));
      for (final old in all.skip(_keepBackups)) {
        try {
          await old.delete();
          final w = File('${old.path}-wal');
          if (await w.exists()) await w.delete();
        } catch (_) {}
      }
    } catch (_) {}
    return target;
  }

  static String _m(int cents) {
    final neg = cents < 0;
    final s = (cents.abs() / 100).toStringAsFixed(2);
    return '${neg ? '-' : ''}$s';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// اللقطة
// ═══════════════════════════════════════════════════════════════════════════

class _Snap {
  final custDebt = <int, int>{}; // id → الرصيد بالفلس
  final custUuid = <int, String?>{};
  final custName = <int, String>{};
  final tx = <int, String>{}; // id → توقيع (مبلغ|رصيد قبل|رصيد بعد|نوع|محذوفة|فاتورة|تاريخ)
  final txCust = <int, int?>{};
  final inv = <int, String>{};
  final invCust = <int, int?>{};
  final invNumber = <int, String?>{};
  final extra = <String, String>{};
  int totalDebt = 0;
  int orphanTx = 0;

  /// الأعمدة التي اعتُمدت في اللقطة الأولى — الثانية تقرأ نفسها بالضبط
  final cols = <String, List<String>>{};

  static int _c(Object? v) => (((v as num?)?.toDouble() ?? 0.0) * 100).round();
  static String _s(Object? v) => v == null ? '' : '$v';

  static Future<Set<String>> _colsOf(DatabaseExecutor db, String t) async {
    try {
      final r = await db.rawQuery("PRAGMA table_info('$t')");
      return r.map((e) => '${e['name']}').toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<_Snap> take(DatabaseExecutor db, {_Snap? like}) async {
    final s = _Snap();
    Future<List<String>> pick(String table, List<String> wanted) async {
      if (like != null) return like.cols[table] ?? const [];
      final have = await _colsOf(db, table);
      final l = wanted.where(have.contains).toList();
      s.cols[table] = l;
      return l;
    }

    // العملاء
    final cc = await pick('customers', ['sync_uuid', 'name']);
    final custSel = ['id', 'current_total_debt', ...cc].join(', ');
    for (final r in await db.rawQuery('SELECT $custSel FROM customers')) {
      final id = r['id'] as int;
      final d = _c(r['current_total_debt']);
      s.custDebt[id] = d;
      s.custUuid[id] = cc.contains('sync_uuid') ? r['sync_uuid'] as String? : null;
      s.custName[id] = _s(r['name']);
      s.totalDebt += d;
    }

    // المعاملات
    final tc = await pick('transactions', [
      'balance_before_transaction',
      'new_balance_after_transaction',
      'transaction_type',
      'is_deleted',
      'invoice_id',
      'transaction_date',
    ]);
    final txSel = ['id', 'customer_id', 'amount_changed', ...tc].join(', ');
    for (final r in await db.rawQuery('SELECT $txSel FROM transactions')) {
      final id = r['id'] as int;
      final cid = r['customer_id'] as int?;
      final parts = <String>[_c(r['amount_changed']).toString()];
      for (final c in tc) {
        if (c.startsWith('balance') || c.startsWith('new_balance')) {
          parts.add(r[c] == null ? '' : _c(r[c]).toString());
        } else if (c == 'is_deleted') {
          parts.add('${(r[c] as num?)?.toInt() ?? 0}');
        } else {
          parts.add(_s(r[c]));
        }
      }
      s.tx[id] = parts.join('|');
      s.txCust[id] = cid;
      if (cid == null || !s.custDebt.containsKey(cid)) s.orphanTx++;
    }

    // الفواتير
    const money = [
      'total_amount',
      'final_total',
      'discount',
      'amount_paid_on_invoice',
      'return_amount',
      'loading_fee',
    ];
    final ic = await pick('invoices', [
      ...money,
      'payment_type',
      'status',
      'installer_name',
      'invoice_date',
      'is_deleted',
      'invoice_number',
    ]);
    final invSel = ['id', 'customer_id', ...ic].join(', ');
    for (final r in await db.rawQuery('SELECT $invSel FROM invoices')) {
      final id = r['id'] as int;
      final parts = <String>[];
      for (final c in ic) {
        if (c == 'invoice_number') continue; // يُقارن وحده (يُسمح بملء الفارغ)
        if (money.contains(c)) {
          parts.add(r[c] == null ? '' : _c(r[c]).toString());
        } else if (c == 'is_deleted') {
          parts.add('${(r[c] as num?)?.toInt() ?? 0}');
        } else {
          parts.add(_s(r[c]));
        }
      }
      s.inv[id] = parts.join('|');
      s.invCust[id] = r['customer_id'] as int?;
      s.invNumber[id] = ic.contains('invoice_number') ? (r['invoice_number'] as String?) : null;
    }

    // مجاميع مسمّاة لبقية ما يحمل مالاً
    Future<void> agg(String label, String table, List<String> wanted,
        String Function(List<String> cols) sql) async {
      final c = await pick(table, wanted);
      if (like == null && (await _colsOf(db, table)).isEmpty) return;
      if (like != null && !like.extra.keys.any((k) => k.startsWith(label))) return;
      try {
        final rows = await db.rawQuery(sql(c));
        for (final r in rows) {
          final key = r.length > 1 && r.containsKey('k') ? '$label ${r['k']}' : label;
          s.extra[key] = r.entries.where((e) => e.key != 'k').map((e) => _s(e.value)).join('|');
        }
      } catch (_) {}
    }

    String cents(String col) => 'CAST(ROUND(COALESCE($col,0)*100) AS INTEGER)';

    await agg('أصناف الفاتورة', 'invoice_items',
        ['item_total', 'quantity_individual', 'quantity_large_unit'], (c) {
      final f = <String>['COUNT(*) AS n'];
      if (c.contains('item_total')) f.add('SUM(${cents('item_total')}) AS t');
      if (c.contains('quantity_individual')) {
        f.add('SUM(CAST(ROUND(COALESCE(quantity_individual,0)*1000) AS INTEGER)) AS q');
      }
      if (c.contains('quantity_large_unit')) {
        f.add('SUM(CAST(ROUND(COALESCE(quantity_large_unit,0)*1000) AS INTEGER)) AS ql');
      }
      return 'SELECT invoice_id AS k, ${f.join(', ')} FROM invoice_items GROUP BY invoice_id';
    });

    await agg('نقاط المؤسس', 'installers', ['total_points', 'total_billed_amount'], (c) {
      final f = <String>['name AS nm'];
      for (final x in c) {
        f.add('${cents(x)} AS $x');
      }
      return 'SELECT id AS k, ${f.join(', ')} FROM installers';
    });

    await agg('سجل النقاط', 'installer_points', ['points'], (c) =>
        'SELECT COUNT(*) AS n${c.contains('points') ? ', SUM(${cents('points')}) AS p' : ''} FROM installer_points');

    await agg('رصيد المورد', 'suppliers',
        ['current_balance', 'opening_balance', 'total_debt_iqd', 'total_debt_usd'], (c) {
      if (c.isEmpty) return 'SELECT id AS k FROM suppliers';
      return 'SELECT id AS k, ${c.map((x) => '${cents(x)} AS $x').join(', ')} FROM suppliers';
    });

    await agg('سندات القبض', 'customer_receipt_vouchers', ['paid_amount', 'amount'], (c) =>
        'SELECT COUNT(*) AS n${c.map((x) => ', SUM(${cents(x)}) AS $x').join()} FROM customer_receipt_vouchers');

    await agg('فواتير الموردين', 'supplier_invoices', ['total_amount', 'amount_paid'], (c) =>
        'SELECT COUNT(*) AS n${c.map((x) => ', SUM(${cents(x)}) AS $x').join()} FROM supplier_invoices');

    await agg('المرتجعات', 'returns', ['total_amount', 'amount'], (c) =>
        'SELECT COUNT(*) AS n${c.map((x) => ', SUM(${cents(x)}) AS $x').join()} FROM returns');

    if (like != null) s.cols.addAll(like.cols);
    return s;
  }
}
