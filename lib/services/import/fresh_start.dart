// lib/services/import/fresh_start.dart
//
// 🆕 «قاعدة بيانات جديدة» للاستيراد: قاعدة فارغة تحل محل الحالية، مع إبقاء
// المستخدمين والإعدادات (قرار المالك 2026-11-03).
//
// الخطوات — ولا شيء يُحذف نهائياً:
//   1) أرشيف كامل من القاعدة الحالية (VACUUM INTO) في «أرشيف_البداية_الجديدة»،
//      يبقى دائماً ويُستعاد من «استعادة» متى أردت.
//   2) نسخة ثانية من الأرشيف تُفرَّغ من كل البيانات التجارية (عملاء، فواتير،
//      معاملات، مواد، موردون، قيود، مخزون، سجلات مزامنة...) في معاملة واحدة،
//      وتبقى الجداول المحفوظة [keepTables] كما هي: المستخدمون وصلاحياتهم،
//      الحسابات المحاسبية، الصناديق والمخازن والفروع، العملات، الأقسام والوحدات،
//      قوالب السندات، الإعدادات. ثم مطابقة: كل جدول مُفرَّغ = صفر، وكل جدول
//      محفوظ بعدد صفوفه نفسه.
//   3) تُستبدل القاعدة الحية بالنسخة المفرَّغة عبر مسار «الاستعادة» نفسه
//      (نسخة سلامة، فحص السلامة، وتراجع تلقائي عند أي فشل).
//
// ممنوع إن كانت المزامنة السحابية أو الشبكة المحلية مفعّلة، أو شاشة أخرى من
// البرنامج مفتوحة على القاعدة نفسها — استبدال قاعدة يعمل عليها جهاز آخر يفسد عمله.
// إعدادات البرنامج المحفوظة خارج القاعدة (الشركة، الطباعة، الواجهة) لا تتأثر.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../erp/activity/activity_log.dart';
import '../../lan/lan_settings.dart';
import '../backup_files.dart';
import '../database_service.dart';
import '../firebase_sync/firebase_sync_config.dart';
import '../seat_service.dart';

class FreshStartResult {
  FreshStartResult(this.archivePath, this.cleared, this.kept);
  final String archivePath;

  /// الجدول ← عدد الصفوف التي كانت فيه (في الأرشيف).
  final Map<String, int> cleared;
  final Map<String, int> kept;
}

class FreshStart {
  FreshStart._();

  /// جداول الإعداد التي تبقى كما هي في القاعدة الجديدة. كل ما عداها يُفرَّغ.
  static const Set<String> keepTables = {
    'users',
    'user_permissions',
    'app_seats',
    'accounting_settings',
    'accounts',
    'account_groups',
    'account_group_members',
    'branches',
    'warehouses',
    'cash_boxes',
    'currencies',
    'currency_rates',
    'categories',
    'units',
    'voucher_templates',
    'customer_groups',
    'sellers',
  };

  /// مفاتيح إعدادات مرتبطة بالبيانات القديمة تُحذف من accounting_settings.
  static const _staleSettings = ['lock_date'];

  /// أسباب المنع (فارغة = مسموح).
  static Future<List<String>> blockers() async {
    final out = <String>[];
    try {
      if (await FirebaseSyncConfig.isEnabled()) {
        out.add('المزامنة السحابية (Firebase) مفعّلة — أطفئها أولاً. قاعدة جديدة مع مزامنة تعيد البيانات القديمة من السحابة أو تحذفها من الأجهزة الأخرى.');
      }
    } catch (_) {}
    try {
      final lan = await LanSettings.load();
      if (lan.mode != LanMode.standalone) {
        out.add('هذا الجهاز ${lan.isServer ? 'سيرفر' : 'طرفية'} في الشبكة المحلية — اجعله «جهاز مستقل» أولاً.');
      }
    } catch (_) {}
    try {
      final db = await DatabaseService().database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final r = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM app_seats WHERE instance_id != ? AND heartbeat_at >= ?',
          [SeatService.instanceId, now - 75 * 1000]);
      final n = (r.first['n'] as num?)?.toInt() ?? 0;
      if (n > 0) out.add('البرنامج مفتوح على $n شاشة أخرى — أغلقها كلها واترك هذه وحدها.');
    } catch (_) {
      // لا جدول شاشات = لا شاشات أخرى
    }
    return out;
  }

  static String _stamp() {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}_${two(n.hour)}-${two(n.minute)}-${two(n.second)}';
  }

  static Future<Map<String, int>> _counts(DatabaseExecutor db, Iterable<String> tables) async {
    final m = <String, int>{};
    for (final t in tables) {
      final r = await db.rawQuery('SELECT COUNT(*) AS n FROM "$t"');
      m[t] = (r.first['n'] as num?)?.toInt() ?? 0;
    }
    return m;
  }

  /// ينفّذ البداية الجديدة. يرمي عند أي مانع أو خلل — والقاعدة الحالية سليمة كما هي.
  static Future<FreshStartResult> run() async {
    final b = await blockers();
    if (b.isNotEmpty) throw StateError(b.join('\n'));

    // 1) الأرشيف الكامل
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'أرشيف_البداية_الجديدة'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final stamp = _stamp();
    final archive = p.join(dir.path, 'archive_before_fresh_$stamp.db');
    await BackupFiles.snapshotForBackup(archive);
    if (!await File(archive).exists() || await File(archive).length() < 4096) {
      throw StateError('تعذّر أخذ أرشيف القاعدة الحالية — لم يتغير شيء');
    }

    // 2) نسخة مفرَّغة
    final freshPath = p.join(dir.path, 'fresh_$stamp.db');
    await File(archive).copy(freshPath);
    final cleared = <String, int>{};
    final kept = <String, int>{};
    final fresh = await openDatabase(freshPath, singleInstance: false);
    try {
      final master = await fresh.rawQuery("SELECT name, sql FROM sqlite_master WHERE type = 'table'");
      final virtual = <String>{
        for (final r in master)
          if ('${r['sql'] ?? ''}'.toUpperCase().startsWith('CREATE VIRTUAL TABLE')) '${r['name']}',
      };
      bool shadow(String t) => virtual.any((v) => t.startsWith('${v}_'));
      final toClear = <String>[
        for (final r in master)
          if (!keepTables.contains('${r['name']}') &&
              !'${r['name']}'.startsWith('sqlite_') &&
              !virtual.contains('${r['name']}') &&
              !shadow('${r['name']}'))
            '${r['name']}',
      ];
      final toKeep = [for (final r in master) if (keepTables.contains('${r['name']}')) '${r['name']}'];
      cleared.addAll(await _counts(fresh, toClear));
      kept.addAll(await _counts(fresh, toKeep));

      // المشغّلات (المخزون، الفهرس) قد تكتب في جداول أخرى أثناء الحذف ⇒ يُكرَّر
      // المرور حتى تفرغ كلها. القيود الأجنبية تُطفأ حتى لا يهمّ ترتيب الحذف.
      await fresh.execute('PRAGMA foreign_keys = OFF');
      await fresh.transaction((txn) async {
        for (var pass = 0; pass < 5; pass++) {
          for (final t in toClear) {
            await txn.execute('DELETE FROM "$t"');
          }
          final left = await _counts(txn, toClear);
          if (left.values.every((n) => n == 0)) break;
        }
        final left = await _counts(txn, toClear);
        final notEmpty = left.entries.where((e) => e.value != 0).map((e) => e.key).toList();
        if (notEmpty.isNotEmpty) {
          throw StateError('تعذّر تفريغ: ${notEmpty.join('، ')} — لم يتغير شيء');
        }
        // الترقيم يبدأ من جديد في الجداول المفرَّغة
        try {
          final ph = List.filled(toClear.length, '?').join(',');
          if (toClear.isNotEmpty) await txn.rawDelete('DELETE FROM sqlite_sequence WHERE name IN ($ph)', toClear);
        } catch (_) {}
        try {
          for (final k in _staleSettings) {
            await txn.delete('accounting_settings', where: 'key = ?', whereArgs: [k]);
          }
        } catch (_) {}
        // 🛡️ الجداول المحفوظة لم تتغير (عدا مفاتيح الإعداد القديمة أعلاه)
        final after = await _counts(txn, toKeep);
        for (final t in toKeep) {
          if (t == 'accounting_settings') continue;
          if (after[t] != kept[t]) {
            throw StateError('الجدول المحفوظ $t تغيّر أثناء التفريغ (${kept[t]} ← ${after[t]}) — لم يتغير شيء');
          }
        }
      });
      // فهارس البحث النصي (FTS5): تُعاد بناؤها من جداولها (المفرَّغة) — والبرنامج
      // يعيد بناءها عند التشغيل أيضاً
      for (final v in virtual) {
        try {
          await fresh.execute('INSERT INTO "$v"("$v") VALUES(\'rebuild\')');
        } catch (_) {
          try {
            await fresh.execute('INSERT INTO "$v"("$v") VALUES(\'delete-all\')');
          } catch (_) {}
        }
      }
      await fresh.execute('PRAGMA foreign_keys = ON');
      final ok = await fresh.rawQuery('PRAGMA quick_check');
      if ('${ok.first.values.first}'.toLowerCase() != 'ok') {
        throw StateError('فحص سلامة القاعدة الجديدة فشل — لم يتغير شيء');
      }
    } finally {
      await fresh.close();
    }

    // 3) الاستبدال بمسار الاستعادة نفسه (نسخة سلامة + تراجع تلقائي عند الفشل)
    final ok = await DatabaseService().restoreDatabaseFromFile(File(freshPath));
    if (!ok) throw StateError('تعذّر تفعيل القاعدة الجديدة — القاعدة السابقة أُعيدت كما كانت');

    // 4) تأكيد أن القاعدة الحية هي الفارغة
    final live = await DatabaseService().database;
    for (final t in const ['customers', 'transactions', 'invoices', 'products', 'suppliers']) {
      try {
        final r = await live.rawQuery('SELECT COUNT(*) AS n FROM "$t"');
        final n = (r.first['n'] as num?)?.toInt() ?? 0;
        if (n != 0) throw StateError('القاعدة الحية ما زال فيها $n صف في $t — راجع قبل الاستيراد');
      } on DatabaseException {
        // جدول غير موجود في هذا الإصدار
      }
    }
    try {
      await File(freshPath).delete(); // صارت هي القاعدة الحية؛ الأرشيف يبقى
    } catch (_) {}
    await ActivityLog.log('إنشاء', 'قاعدة بيانات جديدة',
        'بداية جديدة: أُرشفت القاعدة السابقة في $archive (${cleared['customers'] ?? 0} عميل، '
        '${cleared['invoices'] ?? 0} فاتورة، ${cleared['transactions'] ?? 0} معاملة)');
    return FreshStartResult(archive, cleared, kept);
  }
}
