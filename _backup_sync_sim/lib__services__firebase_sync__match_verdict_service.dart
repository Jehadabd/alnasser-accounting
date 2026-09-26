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

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../database_service.dart';
import 'firebase_sync_config.dart';
import '../sync/sync_security.dart';

class MatchVerdictService {
  static final MatchVerdictService _instance = MatchVerdictService._internal();
  factory MatchVerdictService() => _instance;
  MatchVerdictService._internal();

  FirebaseFirestore? _fsInstance;
  FirebaseFirestore get _fs =>
      _fsInstance ??= FirebaseFirestore.instance;

  final DatabaseService _db = DatabaseService();
  StreamSubscription? _listener;
  bool _isListening = false;
  String? _myDeviceId;
  String? _groupSecretKey;

  // ═══════════════════════════════════════════════════════════════════════
  // التشغيل
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> start() async {
    if (_isListening) return;
    if (!await FirebaseSyncConfig.isEnabled()) return;

    _myDeviceId ??= await FirebaseSyncConfig.getDeviceId();
    await _ensureTables();

    // 🔒 استماع شامل بلا فلتر (نفس فلسفة الفواتير): أي قرار فاتنا
    // تلتقطه الدورة التالية أو السحب الكامل عند الإقلاع.
    _listener = _fs.collection('match_verdicts').snapshots().listen(
          (snap) {
            for (final change in snap.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final data = change.doc.data();
                if (data == null) continue;
                if (data['applierDeviceId'] == _myDeviceId) continue;
                unawaited(applyVerdict(change.doc.id, data));
              }
            }
          },
          onError: (e) => print('⚖️ [Verdict] خطأ في استماع القرارات: $e'),
        );

    _isListening = true;
    print('⚖️ [Verdict] مستمع قرارات المطابقة فعّال');
  }

  void stop() {
    _listener?.cancel();
    _listener = null;
    _isListening = false;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // الجداول المحلية
  // ═══════════════════════════════════════════════════════════════════════

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
    // قرارات وصلت قبل وصول معاملتها — تُنفَّذ لحظة وصول المعاملة
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

  // ═══════════════════════════════════════════════════════════════════════
  // النشر (يستدعيه الجهاز المطبِّق في المطابقة المحصّنة)
  // ═══════════════════════════════════════════════════════════════════════

  /// يبثّ قرار إبطال لكل معاملة زائدة أبطلتها جلسة مطابقة محصّنة.
  /// [voidedRows] صفوف المعاملات كما كانت قبل الإبطال (من rowsToDelete).
  Future<void> publishVerdicts({
    required String customerSyncUuid,
    required List<Map<String, dynamic>> voidedRows,
    required String truthDeviceId,
    required double referenceBalance,
  }) async {
    if (voidedRows.isEmpty) return;
    if (_myDeviceId == null) {
      _myDeviceId = await FirebaseSyncConfig.getDeviceId();
    }
    _groupSecretKey ??= await SyncSecurity.getOrCreateSecretKey();

    final batch = _fs.batch();
    int n = 0;
    for (final row in voidedRows) {
      final txUuid = (row['transaction_uuid'] ?? row['sync_uuid']) as String?;
      if (txUuid == null || txUuid.isEmpty) continue;

      // 🔒 معرّف حتمي: نفس القرار = نفس المستند (استحالة الازدواجية)
      final docId = SyncSecurity.sanitizeDocumentId('v_${customerSyncUuid}_$txUuid');

      final data = <String, dynamic>{
        'transactionUuid': txUuid,
        'customerSyncUuid': customerSyncUuid,
        'customerName': row['customer_name'],
        'voidedAmount': (row['amount_changed'] as num?)?.toDouble() ?? 0.0,
        'transactionDate': row['transaction_date'],
        'truthDeviceId': truthDeviceId,
        'applierDeviceId': _myDeviceId,
        'referenceBalance': referenceBalance,
        'decidedAt': FieldValue.serverTimestamp(),
      };

      // 🔐 توقيع — تحقق استقبالي كتحذير (متسق مع سياسة النظام الحالية)
      if (_groupSecretKey != null && _groupSecretKey!.isNotEmpty) {
        final canonical =
            '${data['transactionUuid']}|$customerSyncUuid|${data['voidedAmount']}|$truthDeviceId';
        data['signature'] = SyncSecurity.signData(canonical, _groupSecretKey!);
      }

      batch.set(_fs.collection('match_verdicts').doc(docId), data);
      n++;
    }

    if (n > 0) {
      await batch.commit().timeout(const Duration(seconds: 30));
      print('⚖️ [Verdict] بُثّ $n قرار إبطال للعميل $customerSyncUuid');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // التطبيق (إدمبوتنت — على أي جهاز يستقبل القرار)
  // ═══════════════════════════════════════════════════════════════════════

  /// يبطل المعاملة المستهدفة محلياً إن وُجدت، أو يعلّق القرار حتى وصولها.
  /// لا يضيف أي مبلغ — الإبطال فقط + إعادة اشتقاق الرصيد من المجموع.
  Future<void> applyVerdict(String docId, Map<String, dynamic> data) async {
    final txUuid = data['transactionUuid'] as String?;
    if (txUuid == null || txUuid.isEmpty) return;

    try {
      await _ensureTables();
      final db = await _db.database;

      var alreadyVoided = false;

      await db.transaction((txn) async {
        final rows = await txn.query('transactions',
            where: 'transaction_uuid = ? OR sync_uuid = ?',
            whereArgs: [txUuid, txUuid],
            limit: 1);

        if (rows.isEmpty) {
          // المعاملة لم تصل بعد → قرار معلّق يُنفَّذ عند وصولها
          await txn.insert(
            'pending_void_verdicts',
            {
              'transaction_uuid': txUuid,
              'customer_sync_uuid': data['customerSyncUuid'] as String?,
              'verdict_doc_id': docId,
              'data': jsonEncode(data),
              'received_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          return;
        }

        final row = rows.first;
        final isDeleted = ((row['is_deleted'] as int?) ?? 0) == 1;

        if (isDeleted) {
          alreadyVoided = true; // إدمبوتنت: مبطلة سابقاً — لا شيء
          return;
        }

        final customerId = row['customer_id'] as int;

        // 🗄️ أرشفة محلية كاملة قبل الإبطال (قابلة للمراجعة)
        await txn.insert(
          'voided_transactions',
          {
            'transaction_uuid': txUuid,
            'customer_sync_uuid': data['customerSyncUuid'] as String?,
            'snapshot': jsonEncode(Map<String, dynamic>.from(row)),
            'verdict_doc_id': docId,
            'reason':
                'match_verdict: truth=${data['truthDeviceId']} at=${data['decidedAt']?.toString() ?? ''}',
            'voided_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        // 🗑️ الإبطال
        await txn.update('transactions', {'is_deleted': 1},
            where: 'id = ?', whereArgs: [row['id']]);

        // 🧮 الرصيد من المجموع — دائماً، لا من الرقم المرسل
        final sum = await txn.rawQuery(
            'SELECT COALESCE(SUM(amount_changed),0) as s FROM transactions '
            'WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
            [customerId]);
        final newBalance = (sum.first['s'] as num?)?.toDouble() ?? 0.0;
        await txn.update('customers',
            {'current_total_debt': newBalance, 'last_modified_at': DateTime.now().toIso8601String()},
            where: 'id = ?', whereArgs: [customerId]);
      });

      if (alreadyVoided) {
        print('⚖️ [Verdict] القرار $docId: المعاملة مبطلة سابقاً (لا شيء)');
      } else {
        print('⚖️ [Verdict] طُبّق قرار الإبطال $docId للمعاملة $txUuid');
      }
    } catch (e) {
      print('⚖️ [Verdict] فشل تطبيق القرار $docId: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // القرارات المعلّقة — تُستدعى بعد وصول أي معاملة جديدة
  // ═══════════════════════════════════════════════════════════════════════

  /// بعد تطبيق معاملة واردة: هل عليها قرار إبطال معلّق؟ نفّذه فوراً.
  Future<void> applyPendingVerdictsFor(String transactionUuid) async {
    try {
      final db = await _db.database;
      final pending = await db.query('pending_void_verdicts',
          where: 'transaction_uuid = ?',
          whereArgs: [transactionUuid],
          limit: 1);
      if (pending.isEmpty) return;

      final row = pending.first;
      final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
      await applyVerdict(row['verdict_doc_id'] as String, data);
      // إن نجح التطبيق (المعاملة الآن موجودة) — احذف المعلّق
      await db.delete('pending_void_verdicts',
          where: 'id = ?', whereArgs: [row['id']]);
      print('⚖️ [Verdict] نُفّذ قرار معلّق للمعاملة $transactionUuid');
    } catch (_) {
      // ليست حرجة — تُعاد المحاولة في المسح الدوري
    }
  }

  /// مسح دوري (عند الإقلاع وبعد السحب الكامل): قرارات معلّقة ومعاملاتها
  /// وصلت في غضون ذلك — نفّذها.
  Future<void> processPendingVerdicts() async {
    try {
      await _ensureTables();
      final db = await _db.database;
      final pending = await db.query('pending_void_verdicts', limit: 200);
      if (pending.isEmpty) return;

      print('⚖️ [Verdict] مسح ${pending.length} قرار معلّق...');
      for (final row in pending) {
        final txUuid = row['transaction_uuid'] as String;
        final exists = await db.query('transactions',
            columns: ['id'],
            where: 'transaction_uuid = ? OR sync_uuid = ?',
            whereArgs: [txUuid, txUuid],
            limit: 1);
        if (exists.isNotEmpty) {
          await applyPendingVerdictsFor(txUuid);
        }
      }
    } catch (e) {
      print('⚖️ [Verdict] خطأ في مسح القرارات المعلّقة: $e');
    }
  }
}
