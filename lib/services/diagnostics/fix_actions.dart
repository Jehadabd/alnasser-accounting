// lib/services/diagnostics/fix_actions.dart
//
// 🛠️ أزرار الإصلاح في «تشخيص الأخطاء».
//
// قواعد ثابتة:
//   • لا زر يغيّر مبلغاً أو ديناً أو رصيد عميل أو مخزوناً. ما يمسّ المال يبقى خطوات يدوية.
//   • كل زر يكتب في القاعدة ([FixAction.writes]) لا يعمل إلا بعد رفع ناجح (UploadGate) —
//     تفرضه الواجهة (runFixAction في شاشة التشخيص)، وتطلب تأكيداً بعده.
//   • الفحص (قراءة فقط) يعمل بلا رفع.
//   • على طرفية الشبكة المحلية لا إصلاح: القاعدة على حاسبة السيرفر.

import 'package:flutter/material.dart';

import '../database/dao/transaction_dao.dart';
import '../database_service.dart';
import '../error_log.dart';

class FixResult {
  const FixResult(this.ok, this.message);
  final bool ok;
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

  static Future<FixResult> _run(String key) async {
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
