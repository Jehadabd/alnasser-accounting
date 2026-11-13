// lib/services/firebase_sync/match_verdict_service.dart
// ⚖️ قرارات المطابقة الموقّرة (Match Verdicts) — نشر نتيجة المطابقة للمجموعة
//
// المشكلة التي تحلها:
//   المطابقة المحصّنة (ArmoredReconciliationService) تصلح الجهازين
//   المشتركين في الجلسة فقط. جهاز خامس كان مغلقاً يبقى على رقمه الخاطئ
//   حتى تُجرى معه جلسة خاصة.
//
// الحل:
//   بعد كل جلسة مطابقة ناجحة، يبثّ الجهاز المطبِّق "قرار إبطال" لكل
//   معاملة زائدة أبطلها — مستنداً واحداً لكل UUID في مجموعة match_verdicts.
//   كل الأجهزة تستقبل القرارات (مستمع شامل) وتطبقها إدمبوتنت.
//
// 🧮 الضمانة الرياضية (القاعدة الذهبية):
//   القرار لا يضيف رقماً أبداً — يبطل فقط معاملة بـ UUID محدد،
//   والرصيد يُشتق دائماً من SUM(المتبقي). وبالتالي:
//   • استحالة التضاعف (لا مسار إضافة إطلاقاً)
//   • استحالة إصابة معاملة خاطئة (UUID واحد محدد)
//   • استحالة الازدواجية (معرّف مستند حتمي v_{customer}_{tx})
//   • استحالة ضرر الترتيب (قرارات معلّقة تُنفَّذ عند وصول معاملتها)
//   • استحالة البندول (الإبطال نهائي — لا إحياء تلقائي، والتعارض إنذار بشري)
//
// ⛔ معطّلة (المحاكاة: tools/sync_sim سيناريوهات 22، 24، 27):
//   القرار يُبطل معاملة على كل الأجهزة لمجرد أن «جهاز الحقيقة» لم يكن يعرفها.
//   لكن جهاز الحقيقة قد يكون متأخراً فقط: تسديد سُجّل على جهاز ثالث ولم يصله
//   بعد كان يُمحى من الشبكة كلها، ولا شيء يعيده لأن الإبطال نهائي. وأي جهاز
//   (أو أي شخص يملك مفاتيح المجموعة) يستطيع كتابة قرار يمحو أي معاملة.
//   الآن: لا نشر ولا تطبيق. كل جهاز يحكم ببياناته وبالسحابة وحدها
//   (شواهد الحذف + المطابقة المحصّنة التي لا تُبطل إلا ما لا أثر له).
//   تبقى الجداول المحلية للأرشيف، وتُهمل القرارات المعلّقة القديمة.
//   (p161: حُذف كود النشر والتطبيق المعطّل — كان لا يصل إليه شيء. السجل في git.)

import 'package:flutter/foundation.dart' show debugPrint;

import '../database_service.dart';
import 'firebase_sync_config.dart';

class MatchVerdictService {
  static final MatchVerdictService _instance = MatchVerdictService._internal();
  factory MatchVerdictService() => _instance;
  MatchVerdictService._internal();

  final DatabaseService _db = DatabaseService();
  bool _started = false;

  /// عند الإقلاع: يُبقي جداول الأرشيف، ويهمل القرارات المعلّقة من نسخ سابقة كي لا
  /// تُنفَّذ عند وصول معاملتها (انظر رأس الملف).
  Future<void> start() async {
    if (_started) return;
    if (!await FirebaseSyncConfig.isEnabled()) return;
    await _ensureTables();
    try {
      final db = await _db.database;
      final n = await db.delete('pending_void_verdicts');
      if (n > 0) debugPrint('⚖️ [Verdict] أُهمل $n قرار إبطال معلّق من نسخة سابقة');
    } catch (_) {}
    _started = true;
  }

  void stop() => _started = false;

  Future<void> _ensureTables() async {
    final db = await _db.database;
    // أرشيف محلي للمعاملات المُبطلة بقرار مطابقة (للمراجعة والتدقيق)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS voided_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_uuid TEXT NOT NULL UNIQUE,
        customer_sync_uuid TEXT,
        snapshot TEXT NOT NULL,
        verdict_doc_id TEXT NOT NULL,
        reason TEXT,
        voided_at TEXT NOT NULL
      )
    ''');
    // قرارات معلّقة من نسخ سابقة — لا تُنفَّذ، تُفرَّغ عند الإقلاع
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_void_verdicts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_uuid TEXT NOT NULL UNIQUE,
        customer_sync_uuid TEXT,
        verdict_doc_id TEXT NOT NULL,
        data TEXT NOT NULL,
        received_at TEXT NOT NULL
      )
    ''');
  }
}
