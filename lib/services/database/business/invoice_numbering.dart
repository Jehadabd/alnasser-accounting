// lib/services/database/business/invoice_numbering.dart
//
// 🔢 رقم الفاتورة الجديدة: [رقم الجهاز][السنة][الشهر][التسلسل الشهري].
//
// في القاعدة قيدان فريدان: رقم الفاتورة نفسه، و(رقم الجهاز + السنة + الشهر +
// التسلسل). كان التسلسل يُحسب من فواتير هذا الجهاز وحدها، بينما فواتير جهاز
// آخر (وصلت بالمزامنة، أو جهاز آخر على «رقم الجهاز 1» نفسه) تحمل الأرقام نفسها،
// فيفشل الحفظ: UNIQUE constraint failed: invoices.invoice_number.
// والصيغة بلا فواصل أيضاً: يناير/تسلسل 15 = نوفمبر/تسلسل 5 (12026115).
//
// الحل: نجمع الأرقام المستعملة فعلاً في القيدين، ونأخذ أول تسلسل بعد آخر تسلسل
// لنا لا يصطدم بأي منهما. وإن سبقنا جهاز آخر بالرقم نفسه في اللحظة نفسها
// (طرفيتان على الشبكة) نعيد الحساب ونحاول ثانية بدل أن يفشل الحفظ.

import 'package:sqflite/sqflite.dart';

class InvoiceNumber {
  const InvoiceNumber(this.seq, this.number);
  final int seq;
  final String number;
}

class InvoiceNumbering {
  InvoiceNumbering._();

  /// أول رقم متاح لهذا الجهاز في هذا الشهر (لا يتكرر في القاعدة كلها).
  static Future<InvoiceNumber> next(
    DatabaseExecutor db, {
    required int deviceNum,
    required int year,
    required int month,
  }) async {
    final prefix = '$deviceNum$year$month';
    final seqRows = await db.rawQuery(
      'SELECT monthly_sequence_number AS s FROM invoices '
      'WHERE creator_device_id = ? AND invoice_year = ? AND invoice_month = ?',
      ['$deviceNum', year, month],
    );
    final takenSeq = <int>{};
    for (final r in seqRows) {
      final s = r['s'];
      if (s is num) takenSeq.add(s.toInt());
    }
    // GLOB: مطابقة البادئة بحساسية الحروف (أرقام فقط) ويستفيد من الفهرس
    final numRows = await db.rawQuery(
      'SELECT invoice_number AS n FROM invoices WHERE invoice_number GLOB ?',
      ['$prefix*'],
    );
    final takenNum = <String>{
      for (final r in numRows)
        if (r['n'] != null) '${r['n']}',
    };
    var seq = 1;
    for (final s in takenSeq) {
      if (s >= seq) seq = s + 1;
    }
    while (takenSeq.contains(seq) || takenNum.contains('$prefix$seq')) {
      seq++;
    }
    return InvoiceNumber(seq, '$prefix$seq');
  }

  /// خطأ «الرقم مستعمل» من أحد القيدين الفريدين على رقم الفاتورة؟
  static bool isNumberClash(Object e) {
    final s = e.toString();
    return s.contains('UNIQUE constraint failed: invoices.invoice_number') ||
        s.contains('UNIQUE constraint failed: invoices.creator_device_id') ||
        s.contains('idx_invoices_unique_composite') ||
        s.contains('idx_invoices_invoice_number');
  }

  /// يُدرج فاتورة جديدة. إن سبقها جهاز آخر بالرقم نفسه يعيد الترقيم ويحاول
  /// ثانية (حتى 5 مرات). يعدّل [invoiceMap] بالرقم الذي حُفظ فعلاً.
  static Future<int> insertNew(DatabaseExecutor db, Map<String, dynamic> invoiceMap) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await db.insert('invoices', invoiceMap);
      } catch (e) {
        final dev = int.tryParse('${invoiceMap['creator_device_id'] ?? ''}');
        final y = invoiceMap['invoice_year'];
        final m = invoiceMap['invoice_month'];
        if (attempt >= 5 || dev == null || y is! int || m is! int || !isNumberClash(e)) rethrow;
        final n = await next(db, deviceNum: dev, year: y, month: m);
        invoiceMap['monthly_sequence_number'] = n.seq;
        invoiceMap['invoice_number'] = n.number;
      }
    }
  }
}
