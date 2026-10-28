// lib/services/database/core/database_doctor.dart
//
// 🩺 طبيب القاعدة — صيانة تلقائية بقاعدة واحدة صارمة:
//
//   ما لا يمسّ المال يفعله النظام وحده ويخبرك بما فعل:
//     إكمال الجداول والأعمدة، ضغط لقطات الفواتير وحذف المكرر منها حرفياً،
//     دمج صفّي العميل نفسه (المجموع كما هو)، حذف بقايا مزامنة Drive القديمة،
//     وإعادة بناء الملف متى امتلأ بمساحة فارغة.
//
//   ما يمسّ المال لا يغيّره النظام أبداً — يكتشفه ويعرضه عليك لتقرر:
//     رصيد عميل لا يساوي مجموع معاملاته، معاملات لعملاء محذوفين، معاملات
//     تشير إلى فاتورة غير موجودة، فواتير لعميل غير موجود.
//     (حارس الهجرة يضمن فوق ذلك أن رقماً مالياً واحداً لم يتغير بالتحويل.)

import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:intl/intl.dart' show NumberFormat;
import 'package:sqflite/sqflite.dart';

/// سجل ما فعلته الصيانة التلقائية في هذا الفتح (يُعرض بعد الاستعادة).
class MaintenanceLog {
  MaintenanceLog._();
  static final List<String> _entries = [];

  static void add(String s) {
    _entries.add(s);
    debugPrint('🧰 $s');
  }

  static List<String> take() {
    final l = List<String>.of(_entries);
    _entries.clear();
    return l;
  }

  static void clear() => _entries.clear();
}

/// مشكلة مالية تحتاج قرار صاحب المحل (لا يُغيَّر فيها شيء تلقائياً).
class DoctorFinding {
  const DoctorFinding(this.title, this.detail, {this.count = 0, this.amount = 0});
  final String title;
  final String detail;
  final int count;
  final double amount;
}

class DatabaseDoctor {
  DatabaseDoctor._();

  static final _nf = NumberFormat('#,##0', 'en_US');
  static String _m(num v) => _nf.format(v.round());

  static Future<bool> _has(DatabaseExecutor db, String table, [String? col]) async {
    final r = await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [table]);
    if (r.isEmpty) return false;
    if (col == null) return true;
    return (await db.rawQuery('PRAGMA table_info("$table")')).any((c) => c['name'] == col);
  }

  /// حجم القاعدة الفعلي (صفحات × حجم الصفحة) والمساحة الفارغة فيها.
  static Future<({int total, int free})> size(DatabaseExecutor db) async {
    int v(List<Map<String, Object?>> r) => (r.first.values.first as num?)?.toInt() ?? 0;
    final page = v(await db.rawQuery('PRAGMA page_size'));
    final count = v(await db.rawQuery('PRAGMA page_count'));
    final free = v(await db.rawQuery('PRAGMA freelist_count'));
    return (total: page * count, free: page * free);
  }

  static String mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  /// 🧹 إعادة بناء الملف تلقائياً متى صار ربعه (أو 20 ميغابايت منه) مساحة فارغة.
  static Future<void> autoVacuumIfBloated(Database db) async {
    try {
      final s = await size(db);
      if (s.free < 20 * 1024 * 1024 && s.free < s.total ~/ 4) return;
      if (s.free < 2 * 1024 * 1024) return; // قاعدة صغيرة: لا فائدة
      await db.execute('VACUUM');
      final after = await size(db);
      MaintenanceLog.add('أُعيد بناء ملف القاعدة لاسترجاع المساحة الفارغة: '
          '${mb(s.total)} ← ${mb(after.total)} ميغابايت');
    } catch (e) {
      debugPrint('⚠️ إعادة بناء القاعدة تلقائياً تعذّرت: $e');
    }
  }

  /// 🔍 فحص مالي — قراءة فقط. لا يضيف ولا يحذف ولا يعدّل.
  static Future<List<DoctorFinding>> scan(DatabaseExecutor db) async {
    final out = <DoctorFinding>[];
    try {
      final txDel = await _has(db, 'transactions', 'is_deleted') ? 'COALESCE(t.is_deleted, 0) = 0' : '1 = 1';
      final cDel = await _has(db, 'customers', 'is_deleted') ? 'COALESCE(c.is_deleted, 0) = 0' : '1 = 1';

      // 1) رصيد العميل المسجّل لا يساوي مجموع معاملاته
      final mism = await db.rawQuery('''
        SELECT c.name AS name, c.current_total_debt AS rec, COALESCE(SUM(t.amount_changed), 0) AS calc
        FROM customers c
        LEFT JOIN transactions t ON t.customer_id = c.id AND $txDel
        WHERE $cDel
        GROUP BY c.id
        HAVING ABS(COALESCE(c.current_total_debt, 0) - COALESCE(SUM(t.amount_changed), 0)) >= 1
        ORDER BY ABS(COALESCE(c.current_total_debt, 0) - COALESCE(SUM(t.amount_changed), 0)) DESC''');
      if (mism.isNotEmpty) {
        final total = mism.fold<double>(
            0, (s, r) => s + (((r['rec'] as num?) ?? 0) - ((r['calc'] as num?) ?? 0)).toDouble());
        out.add(DoctorFinding(
          '${mism.length} عميل رصيده المسجّل لا يساوي مجموع معاملاته',
          'أكبرها: ${mism.take(3).map((r) => '${r['name']} (المسجّل ${_m(r['rec'] as num? ?? 0)} — '
              'المعاملات ${_m(r['calc'] as num? ?? 0)})').join('، ')}. '
              'افتح العميل لترى الفرق وتختار أيهما الصحيح.',
          count: mism.length,
          amount: total,
        ));
      }

      // 2) معاملات لعملاء محذوفين أو غير موجودين
      final orphan = await db.rawQuery('''
        SELECT COUNT(*) AS n, COALESCE(SUM(t.amount_changed), 0) AS s
        FROM transactions t LEFT JOIN customers c ON c.id = t.customer_id
        WHERE $txDel AND (c.id IS NULL ${cDel == '1 = 1' ? '' : 'OR NOT ($cDel)'})''');
      final on = ((orphan.first['n'] as num?) ?? 0).toInt();
      if (on > 0) {
        out.add(DoctorFinding(
          '$on معاملة لعملاء محذوفين أو غير موجودين',
          'مجموعها ${_m(orphan.first['s'] as num? ?? 0)}. لا تدخل في أي رصيد ظاهر، وبقيت كما هي. '
              'إن كانت بيانات تجربة يمكنك تنظيفها من «فحص شامل» في المحاسبة.',
          count: on,
          amount: ((orphan.first['s'] as num?) ?? 0).toDouble(),
        ));
      }

      // 3) معاملات تشير إلى فاتورة غير موجودة
      if (await _has(db, 'invoices')) {
        final lost = await db.rawQuery('''
          SELECT COUNT(*) AS n, COALESCE(SUM(t.amount_changed), 0) AS s
          FROM transactions t LEFT JOIN invoices i ON i.id = t.invoice_id
          WHERE $txDel AND t.invoice_id IS NOT NULL AND i.id IS NULL''');
        final ln = ((lost.first['n'] as num?) ?? 0).toInt();
        if (ln > 0) {
          out.add(DoctorFinding(
            '$ln معاملة مرتبطة بفاتورة غير موجودة',
            'مجموعها ${_m(lost.first['s'] as num? ?? 0)} — تبقى في رصيد العميل كما هي.',
            count: ln,
            amount: ((lost.first['s'] as num?) ?? 0).toDouble(),
          ));
        }

        // 4) فواتير آجلة لعميل غير موجود
        final iDel = await _has(db, 'invoices', 'is_deleted') ? 'AND COALESCE(i.is_deleted, 0) = 0' : '';
        final noCust = await db.rawQuery('''
          SELECT COUNT(*) AS n, COALESCE(SUM(i.total_amount), 0) AS s
          FROM invoices i LEFT JOIN customers c ON c.id = i.customer_id
          WHERE i.customer_id IS NOT NULL AND i.customer_id > 0 AND c.id IS NULL $iDel''');
        final nn = ((noCust.first['n'] as num?) ?? 0).toInt();
        if (nn > 0) {
          out.add(DoctorFinding(
            '$nn فاتورة لعميل غير موجود',
            'مجموعها ${_m(noCust.first['s'] as num? ?? 0)}. تظهر في المبيعات ولا تظهر في حساب أي عميل.',
            count: nn,
            amount: ((noCust.first['s'] as num?) ?? 0).toDouble(),
          ));
        }
      }
    } catch (e) {
      out.add(DoctorFinding('تعذّر إكمال الفحص المالي', '$e'));
    }
    return out;
  }

  /// نص التقرير بعد الاستعادة: ما فعله النظام وحده، وما يحتاج قرارك.
  static String reportText({
    required List<String> done,
    required List<DoctorFinding> findings,
    int? sizeBefore,
    int? sizeAfter,
  }) {
    final b = StringBuffer();
    b.writeln('🧰 ما فعله النظام تلقائياً (لا شيء منه يغيّر رقماً مالياً):');
    if (done.isEmpty) {
      b.writeln('• القاعدة سليمة ومكتملة — لم تحتج شيئاً.');
    } else {
      for (final d in done) {
        b.writeln('• $d');
      }
    }
    if (sizeBefore != null && sizeAfter != null) {
      b.writeln('• حجم القاعدة: ${mb(sizeBefore)} ← ${mb(sizeAfter)} ميغابايت');
    }
    b.writeln();
    if (findings.isEmpty) {
      b.writeln('✅ الفحص المالي: لا شيء يحتاج قرارك.');
    } else {
      b.writeln('⚠️ يحتاج قرارك — لم يُضف ولم يُحذف ولم يُعدَّل شيء منه:');
      for (final f in findings) {
        b.writeln('• ${f.title}');
        b.writeln('   ${f.detail}');
      }
    }
    return b.toString().trimRight();
  }

  /// حجم ملف على القرص (0 إن تعذّر).
  static Future<int> fileSize(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return 0;
    }
  }
}
