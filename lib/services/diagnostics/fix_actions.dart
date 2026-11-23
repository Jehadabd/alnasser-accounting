// lib/services/diagnostics/fix_actions.dart
//
// 🛠️ أزرار الإصلاح في «تشخيص الأخطاء».
//
// قواعد ثابتة:
//   • لا زر يغيّر مبلغاً أو ديناً أو رصيد عميل أو مخزوناً. ما يمسّ المال يبقى خطوات يدوية.
//   • كل زر يكتب في القاعدة ([FixAction.writes]) لا يعمل إلا بعد رفع ناجح (UploadGate) —
//     تفرضه الواجهة (runFixAction في شاشة التشخيص)، وتطلب تأكيداً بعده.
//   • الفحص (قراءة فقط) يعمل بلا رفع.
//   • زر الإصلاح لا يعمل إن لم يوجد خطأ: يفحص أولاً (FixActions.need) — إن كان كل شيء سليماً
//     يقول ذلك ويتوقف، بلا رفع ولا تنفيذ.
//   • على طرفية الشبكة المحلية لا إصلاح: القاعدة على حاسبة السيرفر.

import 'dart:io';

import 'package:flutter/material.dart';

import '../database/dao/transaction_dao.dart';
import '../database_service.dart';
import '../error_log.dart';
import '../firebase_sync/firebase_sync_service.dart';
import '../telegram_net/tor_engine.dart';

class FixResult {
  const FixResult(this.ok, this.message);
  final bool ok;
  final String message;
}

/// نتيجة الفحص المسبق لزر إصلاح: هل يوجد ما يُصلَح أصلاً؟
class FixNeed {
  const FixNeed(this.needed, this.message);
  final bool needed;
  final String message;
}

class FixAction {
  const FixAction({
    required this.key,
    required this.title,
    required this.what,
    required this.icon,
    required this.writes,
    this.opens = false,
    this.local = false,
  });

  final String key;
  final String title;

  /// ماذا يفعل بالضبط (يظهر قبل التنفيذ).
  final String what;
  final IconData icon;

  /// يكتب في القاعدة ⇒ يتطلب رفعاً ناجحاً قبله وتأكيداً.
  final bool writes;

  /// يفتح شاشة بدل أن ينفّذ شيئاً (الفحص العميق).
  final bool opens;

  /// لا يمسّ قاعدة البيانات (شبكة/Tor/المزامنة) ⇒ يعمل على الطرفية أيضاً.
  final bool local;
}

class FixActions {
  FixActions._();

  static const all = <FixAction>[
    FixAction(
      key: 'integrity',
      title: 'فحص سلامة قاعدة البيانات',
      what: 'يقرأ ملف القاعدة كله ويبحث عن تلف وعن سجلات مرتبطة بسجلات غير موجودة. قراءة فقط.',
      icon: Icons.fact_check_rounded,
      writes: false,
    ),
    FixAction(
      key: 'deep_check',
      title: 'الفحص العميق للحسابات',
      what: 'يفتح «الفحص العميق»: يعيد حساب كل دين من فاتورته ومعاملاته ويعرض الفروق. قراءة فقط.',
      icon: Icons.biotech_rounded,
      writes: false,
      opens: true,
    ),
    FixAction(
      key: 'chain_check',
      title: 'فحص «الرصيد قبل/بعد» في كشوف العملاء',
      what: 'يعدّ المعاملات التي «الرصيد قبلها/بعدها» المخزّن لا يطابق ترتيب الكشف. قراءة فقط.',
      icon: Icons.link_rounded,
      writes: false,
    ),
    FixAction(
      key: 'rechain',
      title: 'إصلاح «الرصيد قبل/بعد» في كشوف العملاء',
      what: 'يعيد كتابة عمودي «الرصيد قبل/بعد» لكل معاملة بترتيب الكشف (التاريخ ثم الرقم). '
          'لا يغيّر مبلغ أي معاملة ولا دين أي عميل — المجموع يبقى كما هو.',
      icon: Icons.auto_fix_high_rounded,
      writes: true,
    ),
    FixAction(
      key: 'checkpoint',
      title: 'تفريغ سجل الكتابة المؤقت (WAL)',
      what: 'يدمج التغييرات المعلّقة في ملف القاعدة الرئيسي ويصغّر الملف المؤقت. يفيد عند «القاعدة مشغولة» '
          'وبعد إغلاق مفاجئ. لا يغيّر أي بيانات.',
      icon: Icons.compress_rounded,
      writes: true,
    ),
    FixAction(
      key: 'net_check',
      title: 'فحص الاتصال',
      what: 'يجرّب الوصول إلى الإنترنت وخوادم Google وتيليجرام وDropbox ويقول أيها يعمل وأيها محجوب. لا يغيّر شيئاً.',
      icon: Icons.network_check_rounded,
      writes: false,
      local: true,
    ),
    FixAction(
      key: 'tor_reset',
      title: 'إعادة تشغيل Tor من الصفر',
      what: 'يوقف Tor، ويغلق أي نسخة Tor عالقة خاصة بالبرنامج (لا يمسّ Tor Browser)، ثم يشغّله ويخبرك هل اتصل. '
          'قد يستغرق حتى 3 دقائق. لا يمسّ البيانات.',
      icon: Icons.restart_alt_rounded,
      writes: false,
      local: true,
    ),
    FixAction(
      key: 'sync_retry',
      title: 'إعادة بدء المزامنة',
      what: 'يحاول بدء المزامنة الآن ويخبرك بحالتها (تعمل، لا إنترنت، غير مُعدّة…). لا يغيّر بيانات.',
      icon: Icons.sync_rounded,
      writes: false,
      local: true,
    ),
    FixAction(
      key: 'reindex',
      title: 'إعادة بناء الفهارس',
      what: 'يعيد بناء فهارس البحث في القاعدة (تلف الفهارس من أشهر أسباب «القاعدة تالفة»)، ثم يفحص السلامة. '
          'لا يغيّر أي سجل.',
      icon: Icons.build_rounded,
      writes: true,
    ),
  ];

  static FixAction? byKey(String key) {
    for (final a in all) {
      if (a.key == key) return a;
    }
    return null;
  }

  /// 🔎 فحص قبل الإصلاح (قراءة فقط، بلا رفع): الزر لا يعمل إن لم يوجد خطأ يصلحه.
  static Future<FixNeed> need(String key) async {
    try {
      final db = await DatabaseService().database;
      switch (key) {
        case 'rechain':
          final r = await _run('chain_check');
          return FixNeed(!r.ok, r.message);
        case 'reindex':
          final rows = await db.rawQuery('PRAGMA integrity_check');
          final msgs = [for (final r in rows) '${r.values.first}'];
          final ok = msgs.length == 1 && msgs.first == 'ok';
          return FixNeed(!ok, ok ? 'القاعدة سليمة: لا تلف يحتاج إعادة بناء الفهارس.' : 'وُجد تلف: ${msgs.take(3).join(' | ')}');
        case 'checkpoint':
          final wal = File('${db.path}-wal');
          final size = await wal.exists() ? await wal.length() : 0;
          final mb = size / (1024 * 1024);
          return mb >= _walLimitMb
              ? FixNeed(true, 'سجل الكتابة المؤقت ${mb.toStringAsFixed(1)} ميغابايت (الطبيعي أقل من $_walLimitMb).')
              : FixNeed(false, 'سجل الكتابة المؤقت ${mb.toStringAsFixed(1)} ميغابايت — طبيعي، لا حاجة لتفريغه.');
      }
      return const FixNeed(true, '');
    } catch (e) {
      return FixNeed(false, 'تعذّر الفحص قبل الإصلاح: $e — لم يُنفَّذ شيء.');
    }
  }

  static const int _walLimitMb = 8;

  /// ينفّذ الإجراء (البوابة والتأكيد في الواجهة قبل الاستدعاء).
  static Future<FixResult> run(String key) async {
    try {
      final r = await _run(key);
      if (byKey(key)?.writes == true) ErrorLog.note('إصلاح «$key» من تشخيص الأخطاء: ${r.ok ? 'نجح' : 'لم ينجح'} — ${r.message}');
      return r;
    } catch (e) {
      ErrorLog.note('إصلاح «$key» فشل: $e');
      return FixResult(false, 'تعذّر التنفيذ: $e');
    }
  }

  /// إجراءات لا تمسّ القاعدة.
  static Future<FixResult?> _runLocal(String key) async {
    switch (key) {
      case 'net_check':
        const targets = <(String, String)>[
          ('الإنترنت', 'one.one.one.one'),
          ('Google/Firebase', 'firestore.googleapis.com'),
          ('الترخيص', 'script.google.com'),
          ('تيليجرام', 'api.telegram.org'),
          ('Dropbox', 'content.dropboxapi.com'),
        ];
        final lines = <String>[];
        var anyOk = false;
        for (final (label, host) in targets) {
          try {
            final s = await Socket.connect(host, 443, timeout: const Duration(seconds: 6));
            s.destroy();
            anyOk = true;
            lines.add('✔ $label: يعمل');
          } on SocketException catch (e) {
            final dns = '${e.osError?.errorCode}' == '11001' || e.message.contains('host lookup');
            lines.add(dns ? '✖ $label: الاسم لا يُحلّ (DNS أو حجب)' : '✖ $label: لا يصل (${e.osError?.message ?? e.message})');
          } catch (e) {
            lines.add('✖ $label: $e');
          }
        }
        return FixResult(anyOk && lines.first.startsWith('✔'),
            '${lines.join('\n')}\n\n${anyOk ? 'ما عليه ✖ محجوب أو متوقف من هذه الشبكة — جرّب «عند حظر تيليجرام» أو شبكة أخرى.' : 'لا اتصال بالإنترنت من هذه الحاسبة.'}');

      case 'tor_reset':
        if (!TorEngine.supported) return const FixResult(false, 'Tor متاح على Windows فقط.');
        if (!await TorEngine.isInstalled()) {
          return const FixResult(false, 'Tor غير مثبّت — من «إعدادات تيليجرام» ← «عند حظر تيليجرام» اضغط «تثبيت Tor».');
        }
        await TorEngine.stop();
        final killed = await TorEngine.killStray();
        try {
          final port = await TorEngine.ensureRunning(timeout: const Duration(minutes: 3));
          return FixResult(true,
              '${killed > 0 ? 'أُغلقت $killed نسخة عالقة. ' : ''}Tor يعمل الآن ومتصل (127.0.0.1:$port). أعد الرفع.');
        } catch (e) {
          return FixResult(false, '${killed > 0 ? 'أُغلقت $killed نسخة عالقة، لكن ' : ''}Tor لم يتصل: $e');
        }

      case 'sync_retry':
        final svc = FirebaseSyncService();
        final ok = await svc.initialize().timeout(const Duration(seconds: 60), onTimeout: () => false);
        final st = svc.status;
        final label = switch (st) {
          FirebaseSyncStatus.online => 'تعمل ومتصلة',
          FirebaseSyncStatus.syncing => 'تعمل (تزامن الآن)',
          FirebaseSyncStatus.idle => 'تعمل (في الانتظار)',
          FirebaseSyncStatus.offline => 'لا إنترنت أو تعذّرت المصادقة — ستعيد المحاولة وحدها',
          FirebaseSyncStatus.error => 'خطأ من Firebase — انظر «صحة المزامنة»',
          FirebaseSyncStatus.disabled => 'معطّلة (غير مشمولة في الترخيص أو تعمل في الشاشة الأولى)',
          FirebaseSyncStatus.notConfigured => 'غير مُعدّة على هذا الجهاز — من «إعدادات المزامنة»',
        };
        return FixResult(ok, 'المزامنة: $label.');
    }
    return null;
  }

  static Future<FixResult> _run(String key) async {
    final local = await _runLocal(key);
    if (local != null) return local;
    final db = await DatabaseService().database;
    switch (key) {
      case 'integrity':
        final rows = await db.rawQuery('PRAGMA integrity_check');
        final msgs = [for (final r in rows) '${r.values.first}'];
        final healthy = msgs.length == 1 && msgs.first == 'ok';
        final fk = await db.rawQuery('PRAGMA foreign_key_check');
        if (!healthy) {
          return FixResult(false,
              'وُجد تلف في القاعدة (${msgs.length} ملاحظة): ${msgs.take(4).join(' | ')}\nجرّب «إعادة بناء الفهارس»، وإن بقي فاستعد آخر نسخة سليمة.');
        }
        if (fk.isNotEmpty) {
          final tables = {for (final r in fk) '${r['table']}'};
          return FixResult(false, 'لا تلف في الملف، لكن ${fk.length} سجلاً مرتبط بسجل غير موجود (${tables.join('، ')}). شغّل «الفحص العميق للحسابات».');
        }
        return const FixResult(true, 'القاعدة سليمة: لا تلف ولا روابط مكسورة.');

      case 'chain_check':
      case 'rechain':
        final dry = key == 'chain_check';
        final ids = [
          for (final r in await db.rawQuery('SELECT DISTINCT customer_id AS id FROM transactions WHERE customer_id IS NOT NULL'))
            (r['id'] as num).toInt()
        ];
        var rows = 0, customers = 0;
        for (final id in ids) {
          final n = dry ? await TransactionDao.rechainIn(db, id, dryRun: true) : await db.transaction((txn) => TransactionDao.rechainIn(txn, id));
          if (n > 0) {
            rows += n;
            customers++;
          }
        }
        if (rows == 0) return FixResult(true, 'كشوف ${ids.length} عميلاً سليمة: «الرصيد قبل/بعد» مطابق لكل معاملة.');
        return dry
            ? FixResult(false, '$rows معاملة عند $customers عميلاً «الرصيد قبلها/بعدها» لا يطابق الكشف. اضغط «إصلاح «الرصيد قبل/بعد»». المجموع سليم.')
            : FixResult(true, 'أُصلح «الرصيد قبل/بعد» في $rows معاملة عند $customers عميلاً. لم يتغيّر أي مبلغ أو دين.');

      case 'checkpoint':
        final r = await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        final row = r.isEmpty ? const <String, Object?>{} : r.first;
        final busy = (row['busy'] as num?)?.toInt() ?? 0;
        return busy == 0
            ? const FixResult(true, 'دُمجت كل التغييرات في ملف القاعدة وصُغّر الملف المؤقت.')
            : const FixResult(false, 'القاعدة مشغولة الآن بعملية أخرى (مزامنة أو رفع). أعد المحاولة بعد دقيقة.');

      case 'reindex':
        await db.execute('REINDEX');
        final rows = await db.rawQuery('PRAGMA integrity_check');
        final msgs = [for (final r in rows) '${r.values.first}'];
        return msgs.length == 1 && msgs.first == 'ok'
            ? const FixResult(true, 'أُعيد بناء الفهارس، والقاعدة الآن سليمة.')
            : FixResult(false, 'أُعيد بناء الفهارس لكن التلف باقٍ: ${msgs.take(3).join(' | ')}\nاستعد آخر نسخة سليمة.');
    }
    return FixResult(false, 'إجراء غير معروف: $key');
  }
}
