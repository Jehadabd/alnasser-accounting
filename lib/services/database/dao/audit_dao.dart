// lib/services/database/dao/audit_dao.dart
// عمليات سجل التدقيق المالي

import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart'; // 🗜️ ضغط لقطات الفواتير (يعمل على الويب وسطح المكتب)

/// DAO لسجل التدقيق المالي
class AuditDao {
  final Future<Database> Function() getDatabase;

  AuditDao({required this.getDatabase});

  // ═══════════════════════════════════════════════════════════════════════════
  // 🗜️ تصغير قاعدة البيانات: تنظيف وضغط لقطات الفواتير + سياسة حفظ السجلات
  // ═══════════════════════════════════════════════════════════════════════════

  /// حقول تُحذف من نصّ أصناف اللقطة التاريخية فقط (جدول invoice_items الحيّ لا يُمسّ).
  /// id / invoice_id: معرّفات صفوف لا معنى لها خارج الجدول الحيّ.
  /// unique_id: مفتاح صفّ مؤقّت للواجهة يُولَّد من الوقت ويُرمى بعد الحفظ.
  /// product_sync_uuid: تستعمله المزامنة من الجدول الحيّ، واللقطات لا تُرفع إطلاقاً.
  /// وكلّها نصوص عشوائية لا تنضغط — حذفها أنفع من ضغطها.
  static const Set<String> kSnapshotDropFields = {
    'id',
    'invoice_id',
    'unique_id',
    'product_sync_uuid',
  };

  /// مدة الاحتفاظ بسجل التدقيق المالي وسجل عمليات الفواتير
  static const int kLogRetentionDays = 365;
  static DateTime? _lastLogPruneAt;

  /// بناء نصّ أصناف اللقطة بعد التنظيف.
  /// القيم الفارغة تُحذف أيضاً: غياب الحقل يُقرأ null تماماً كوجوده فارغاً.
  static String buildSnapshotItemsJson(List<Map<String, dynamic>> rows) {
    final cleaned = rows.map((row) {
      final out = <String, dynamic>{};
      row.forEach((k, v) {
        if (kSnapshotDropFields.contains(k)) return;
        if (v == null) return;
        out[k] = v;
      });
      return out;
    }).toList();
    return jsonEncode(cleaned);
  }

  /// ضغط نصّ الأصناف للتخزين (gzip من حزمة archive — تعمل على الويب أيضاً).
  /// يُخزَّن BLOB داخل عمود معرّف TEXT، وSQLite ذو أنواع ديناميكية فيقبل ذلك
  /// بلا أي تعديل على المخطط ولا ترقية إصدار.
  static Uint8List encodeSnapshotItems(String itemsJson) {
    final raw = utf8.encode(itemsJson);
    try {
      final dynamic packed = GZipEncoder().encode(raw);
      if (packed is List<int> && packed.isNotEmpty) {
        return Uint8List.fromList(packed);
      }
    } catch (e) {
      print('⚠️ تعذّر ضغط أصناف اللقطة (سيُحفظ نصاً): $e');
    }
    return Uint8List.fromList(raw);
  }

  /// قراءة أصناف اللقطة — تتعامل مع الشكلين معاً:
  /// لقطة قديمة مخزّنة نصاً، ولقطة جديدة مضغوطة. لا هجرة إجبارية للبيانات القديمة.
  static String decodeSnapshotItems(dynamic raw) {
    if (raw == null) return '[]';
    if (raw is String) return raw.isEmpty ? '[]' : raw;
    if (raw is List<int>) {
      try {
        if (raw.length > 2 && raw[0] == 0x1f && raw[1] == 0x8b) {
          return utf8.decode(GZipDecoder().decodeBytes(raw));
        }
        return utf8.decode(raw);
      } catch (e) {
        print('⚠️ تعذّر فكّ ضغط أصناف اللقطة: $e');
      }
    }
    return '[]';
  }

  /// أصناف اللقطة كصفوف جاهزة للعرض والمقارنة
  static List<Map<String, dynamic>> decodeSnapshotItemRows(dynamic raw) {
    try {
      final dynamic source =
          (raw is List && raw is! List<int>) ? raw : jsonDecode(decodeSnapshotItems(raw));
      if (source is List) {
        return source
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (e) {
      print('⚠️ تعذّرت قراءة أصناف اللقطة: $e');
    }
    return <Map<String, dynamic>>[];
  }

  /// مقارنة رقمية متسامحة مع فروق الفاصلة العائمة
  static bool sameSnapshotNum(Object? a, Object? b) =>
      (((a as num?)?.toDouble() ?? 0.0) - ((b as num?)?.toDouble() ?? 0.0)).abs() <
      0.001;

  /// هل حالة الفاتورة الآن مطابقة تماماً لآخر لقطة محفوظة؟
  /// [last] صفّ آخر لقطة، [invoice] صفّ الفاتورة الحيّ، [itemsJson] الأصناف بعد التنظيف.
  static bool isSameAsLastSnapshot(
    Map<String, Object?> last,
    Map<String, Object?> invoice,
    String itemsJson,
  ) {
    return decodeSnapshotItems(last['items_json']) == itemsJson &&
        (last['customer_name'] as String?) == (invoice['customer_name'] as String?) &&
        (last['customer_phone'] as String?) == (invoice['customer_phone'] as String?) &&
        (last['customer_address'] as String?) == (invoice['customer_address'] as String?) &&
        (last['invoice_date'] as String?) == (invoice['invoice_date'] as String?) &&
        (last['payment_type'] as String?) == (invoice['payment_type'] as String?) &&
        (last['invoice_notes'] as String?) == (invoice['notes'] as String?) &&
        sameSnapshotNum(last['total_amount'], invoice['total_amount']) &&
        sameSnapshotNum(last['discount'], invoice['discount']) &&
        sameSnapshotNum(last['amount_paid'], invoice['amount_paid_on_invoice']) &&
        sameSnapshotNum(last['loading_fee'], invoice['loading_fee']);
  }

  /// 🧹 حذف السجلات الأقدم من [kLogRetentionDays] — مرة كل ٦ ساعات كحد أقصى.
  /// ملفوفة بـ try/catch كاملة فلا تُفشل إدراجاً ناجحاً.
  Future<void> _pruneOldLogsIfDue(Database db) async {
    try {
      final now = DateTime.now();
      if (_lastLogPruneAt != null &&
          now.difference(_lastLogPruneAt!).inHours < 6) {
        return;
      }
      _lastLogPruneAt = now;
      final cutoff = now
          .subtract(const Duration(days: kLogRetentionDays))
          .toIso8601String();

      int deletedAudit = 0;
      int deletedLogs = 0;
      try {
        deletedAudit = await db.delete('financial_audit_log',
            where: 'created_at < ?', whereArgs: [cutoff]);
      } catch (_) {}
      try {
        deletedLogs = await db.delete('invoice_logs',
            where: 'created_at < ?', whereArgs: [cutoff]);
      } catch (_) {}

      if (deletedAudit > 0 || deletedLogs > 0) {
        print(
            '🧹 تنظيف السجلات: $deletedAudit سجل تدقيق و $deletedLogs سجل فاتورة أقدم من $kLogRetentionDays يوماً');
      }
    } catch (e) {
      print('⚠️ تعذّر تنظيف السجلات القديمة: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // دوال سجل التدقيق المالي (Financial Audit Log)
  // ═══════════════════════════════════════════════════════════════════════════

  /// إدراج سجل تدقيق
  Future<int> insertAuditLog({
    required String operationType,
    required String entityType,
    required int entityId,
    String? oldValues,
    String? newValues,
    String? notes,
  }) async {
    final db = await getDatabase();
    try {
      final insertedId = await db.insert('financial_audit_log', {
        'operation_type': operationType,
        'entity_type': entityType,
        'entity_id': entityId,
        'old_values': oldValues,
        'new_values': newValues,
        'notes': notes,
        'created_at': DateTime.now().toIso8601String(),
      });
      // 🧹 سياسة الحفظ: لا ينمو السجل بلا حدّ
      await _pruneOldLogsIfDue(db);
      return insertedId;
    } catch (e) {
      print('خطأ في إدراج سجل التدقيق: $e');
      return 0;
    }
  }

  /// جلب سجل التدقيق لكيان معين
  Future<List<Map<String, dynamic>>> getAuditLogForEntity(
    String entityType,
    int entityId,
  ) async {
    final db = await getDatabase();
    try {
      return await db.query(
        'financial_audit_log',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [entityType, entityId],
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      print('خطأ في جلب سجل التدقيق: $e');
      return [];
    }
  }

  /// جلب سجل التدقيق لفترة زمنية
  Future<List<Map<String, dynamic>>> getAuditLogForPeriod(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await getDatabase();
    try {
      return await db.query(
        'financial_audit_log',
        where: 'created_at >= ? AND created_at <= ?',
        whereArgs: [
          startDate.toIso8601String(),
          endDate.toIso8601String(),
        ],
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      print('خطأ في جلب سجل التدقيق للفترة: $e');
      return [];
    }
  }

  /// جلب آخر العمليات المالية
  Future<List<Map<String, dynamic>>> getRecentAuditLogs({int limit = 50}) async {
    final db = await getDatabase();
    try {
      return await db.query(
        'financial_audit_log',
        orderBy: 'created_at DESC',
        limit: limit,
      );
    } catch (e) {
      print('خطأ في جلب آخر العمليات: $e');
      return [];
    }
  }

  /// حذف سجلات التدقيق القديمة (أقدم من 6 أشهر)
  Future<int> cleanOldAuditLogs() async {
    final db = await getDatabase();
    try {
      final sixMonthsAgo = DateTime.now().subtract(const Duration(days: 180));
      return await db.delete(
        'financial_audit_log',
        where: 'created_at < ?',
        whereArgs: [sixMonthsAgo.toIso8601String()],
      );
    } catch (e) {
      print('خطأ في حذف سجلات التدقيق القديمة: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📸 دوال نسخ الفواتير (Invoice Snapshots)
  // ═══════════════════════════════════════════════════════════════════════════

  /// حفظ نسخة من الفاتورة قبل التعديل
  Future<int> saveInvoiceSnapshot({
    required int invoiceId,
    required String snapshotType,
    String? notes,
    String? createdBy,
  }) async {
    final db = await getDatabase();
    try {
      // جلب بيانات الفاتورة الحالية
      final invoiceMaps = await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId]);
      if (invoiceMaps.isEmpty) {
        throw Exception('الفاتورة غير موجودة');
      }
      final invoice = invoiceMaps.first;
      
      // جلب أصناف الفاتورة (بعد حذف الحقول الحشو التي لا معنى لها في اللقطة)
      final items = await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      final itemsJson = buildSnapshotItemsJson(items);
      
      // حساب رقم النسخة
      final existingSnapshots = await db.query(
        'invoice_snapshots',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'version_number DESC',
        limit: 1,
      );

      // 🗜️ منع اللقطات المكررة: إن لم يتغيّر شيء عن آخر لقطة فلا نكتب صفاً جديداً.
      // لا تُتخطّى إلا لقطة مطابقة حرفياً لما هو محفوظ بالفعل، فلا تضيع أي حالة فريدة.
      if (existingSnapshots.isNotEmpty &&
          isSameAsLastSnapshot(existingSnapshots.first, invoice, itemsJson)) {
        return (existingSnapshots.first['id'] as int?) ?? -1;
      }

      final nextVersion = existingSnapshots.isEmpty 
          ? 1 
          : ((existingSnapshots.first['version_number'] as int?) ?? 0) + 1;
      
      return await db.insert('invoice_snapshots', {
        'invoice_id': invoiceId,
        'version_number': nextVersion,
        'snapshot_type': snapshotType,
        'customer_name': invoice['customer_name'],
        'customer_phone': invoice['customer_phone'],
        'customer_address': invoice['customer_address'],
        'invoice_date': invoice['invoice_date'],
        'payment_type': invoice['payment_type'],
        'total_amount': invoice['total_amount'],
        'discount': invoice['discount'],
        'amount_paid': invoice['amount_paid_on_invoice'],
        'loading_fee': invoice['loading_fee'],
        'items_json': encodeSnapshotItems(itemsJson),
        'created_at': DateTime.now().toIso8601String(),
        'notes': notes,
        'invoice_notes': invoice['notes'],
        'created_by': createdBy,
      });
    } catch (e) {
      print('خطأ في حفظ نسخة الفاتورة: $e');
      return 0;
    }
  }

  /// جلب جميع نسخ فاتورة معينة
  Future<List<Map<String, dynamic>>> getInvoiceSnapshots(int invoiceId) async {
    final db = await getDatabase();
    try {
      return await db.query(
        'invoice_snapshots',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'version_number ASC',
      );
    } catch (e) {
      print('خطأ في جلب نسخ الفاتورة: $e');
      return [];
    }
  }

  /// التحقق من وجود تعديلات على الفاتورة
  Future<bool> hasInvoiceBeenModified(int invoiceId) async {
    final db = await getDatabase();
    try {
      final result = await db.rawQuery('''
        SELECT COUNT(1) as c FROM invoice_snapshots WHERE invoice_id = ?
      ''', [invoiceId]);
      return ((result.first['c'] as int?) ?? 0) > 1;
    } catch (e) {
      return false;
    }
  }

  /// جلب عدد التعديلات على الفاتورة
  Future<int> getInvoiceModificationCount(int invoiceId) async {
    final db = await getDatabase();
    try {
      final result = await db.rawQuery('''
        SELECT COUNT(1) as c FROM invoice_snapshots WHERE invoice_id = ?
      ''', [invoiceId]);
      return (result.first['c'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔒 دوال سجل عمليات الفاتورة (Invoice Logs)
  // ═══════════════════════════════════════════════════════════════════════════

  /// تسجيل عملية على فاتورة
  Future<int> insertInvoiceLog({
    required int invoiceId,
    required String action,
    String? details,
    String? createdBy,
  }) async {
    final db = await getDatabase();
    try {
      final insertedId = await db.insert('invoice_logs', {
        'invoice_id': invoiceId,
        'action': action,
        'details': details,
        'created_at': DateTime.now().toIso8601String(),
        'created_by': createdBy,
      });
      // 🧹 سياسة الحفظ نفسها لسجل عمليات الفواتير
      await _pruneOldLogsIfDue(db);
      return insertedId;
    } catch (e) {
      print('خطأ في تسجيل عملية الفاتورة: $e');
      return 0;
    }
  }

  /// جلب سجل عمليات فاتورة
  Future<List<Map<String, dynamic>>> getInvoiceLogs(int invoiceId) async {
    final db = await getDatabase();
    try {
      return await db.query(
        'invoice_logs',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      print('خطأ في جلب سجل عمليات الفاتورة: $e');
      return [];
    }
  }
}
