// tool/rare_points_report.dart
//
// 🧭 تقرير نقاط المزامنة النادرة: لكل نقطة كتابة مال لم يمر بها اختبار سابقاً — هل مرّ بها
// اختبار فروع المزامنة النادرة الآن (من coverage/lcov.info)؟ وإن لم يمر، لماذا (تصنيف صريح:
// حماية لا يصل إليها التطبيق الحالي، أو بيانات من إصدارات قديمة، أو سباق لا يصنعه اختبار).
//
// كل نقطة تُحدَّد بالدالة التي هي فيها ونص السطر (لا برقم سطر يتغيّر مع كل تعديل).
// التشغيل: claude_test_rare_sync.bat cover   (أو: dart run tool/rare_points_report.dart)
// ignore_for_file: avoid_print

import 'dart:io';

class _Point {
  const _Point(this.file, this.function, this.text, this.occurrence, this.title, this.ifMissed);
  final String file;
  final String function;
  final String text;
  final int occurrence;
  final String title;
  final String ifMissed;
}

const _fss = 'lib/services/firebase_sync/firebase_sync_service.dart';
const _iss = 'lib/services/firebase_sync/invoice_sync_service.dart';

const _points = [
  _Point(_fss, 'Future<void> _handleOwnTxDoc(', "{'is_deleted': 1, 'is_uploaded': 1}", 1,
      'حذف العميل على جهاز آخر يصل في مستند معاملتي (U3)',
      'لم يصنعه U3: الحذف وصل عبر مسار مستند الجهاز الآخر (مغطى) لا عبر مستندي'),
  _Point(_fss, 'Future<void> _handleOwnTxDoc(', "{'is_uploaded': 0}", 1,
      'نسخة أقدم من معاملتي وصلت بعد رفعي الأحدث ⇒ أعيد رفع نسختي',
      'حماية: قفل الرفع لكل معاملة يمنع وصول كتابتين من جهاز واحد بغير ترتيبهما'),
  _Point(_fss, 'Future<void> _applyTransactionChange(', "{'is_uploaded': 0}", 1,
      'جهاز آخر أعاد بث نسخة قديمة من معاملتي ⇒ أعيد رفع نسختي (R5)',
      'لم يصنعه R5: الجهاز المستعاد لا يعيد بث معاملات غيره في الإصدار الحالي'),
  _Point(_fss, 'Future<bool> uploadTransaction(', "{'is_uploaded': 0}", 1,
      'تعديل المعاملة أثناء رفعها ⇒ لا تُعلَّم «مرفوعة» بالنسخة القديمة (U1)',
      'لم يصنعه U1: التعديل انتظر انتهاء الرفع (تسلسل أوامر الجهاز)'),
  _Point(_fss, 'Future<void> _forceUploadTransaction(', "{'is_uploaded': 1, 'last_uploaded_at': nowIso}", 1,
      '«أعد رفع معاملتي» من شاشة المطابقة (U2)', 'هنا وقع خطأ: U2 يستدعيها مباشرة'),
  _Point(_fss, 'Future<void> _forceUploadTransaction(', "{'is_uploaded': 0}", 1,
      'تعديل أثناء «أعد رفع معاملتي» (U2)', 'لم يصنعه U2: التعديل انتظر انتهاء الرفع'),
  _Point(_iss, 'Future<void> _processIncomingInvoice(', "{'version': incomingVersion + 1, 'is_synced': 0}", 1,
      'تصادم رقم نسخة فاتورتي بعد استعادة وتعديل',
      'حماية: تعديل ما استُعيد مقفول حتى يلحق الجهاز (قفل الاستعادة) — لا يصل إليه التطبيق الحالي'),
  _Point(_iss, 'Future<void> _processIncomingInvoice(', "{'version': incomingVersion + 1, 'is_synced': 0}", 2,
      'فاتورتي المستعادة عُدّلت محلياً قبل أن تصل نسختها السحابية',
      'حماية: نفس قفل الاستعادة'),
  _Point(_iss, 'Future<void> _processIncomingInvoice(', "invoiceId = await txn.insert('invoices', invoiceData);", 2,
      'إعادة إدراج فاتورة واردة برقم تسلسل جديد بعد تصادم (F3)',
      'سباق: الفحص قبل الإدراج في المعاملة نفسها يمنع التصادم على اتصال واحد متسلسل'),
  _Point(_iss, 'Future<void> _processIncomingInvoice(', "await txn.update('transactions', txMap,", 1,
      'صف معاملة فاتورة موجود مسبقاً بنفس المعرّف', 'بيانات إصدارات قديمة (كانت ترفع معاملات الفواتير منفصلة)'),
  _Point(_iss, 'Future<void> _repairCreditInvoicesMissingCustomers(', "await db.update('invoices', {'customer_id': customerId},", 1,
      'فاتورة آجلة واردة بلا عميل ⇒ يُربط عميلها', 'بيانات إصدارات قديمة (فواتير آجلة بلا customer_id)'),
  _Point(_iss, '_ensureCreditTransaction(', "await txn.insert('transactions', {", 1,
      'فاتورة آجلة واردة بلا معاملة دين ⇒ تُنشأ', 'بيانات إصدارات قديمة (حزمة فاتورة بلا صف دين)'),
  // (أُزيلت نقطة «إعادة معاملة من سجل الاسترداد»: p160 ألغى إعادة التنفيذ من السجل — rare_gaps_test R7)
  _Point('lib/services/database_service.dart', 'markDatabaseRestored(', 'UPDATE transactions SET restored_mark = 1', 1,
      'الاستعادة من الإعدادات والبرنامج يعمل (L1، L2)', 'هنا وقع خطأ: L1 وL2 يستدعيانها مباشرة'),
  _Point('lib/services/database_service.dart', 'clearRestoreIfNoSync(', 'UPDATE transactions SET restored_mark = 0', 1,
      'استعادة على جهاز بلا مزامنة ⇒ لا قفل', 'مغطاة في rare_gaps_test R8 (جهاز بلا مزامنة) لا في هذا الاختبار'),
];

void main() {
  final lcov = File('coverage/lcov.info');
  if (!lcov.existsSync()) {
    print('هنا وقع خطأ: لا يوجد coverage/lcov.info — شغّل claude_test_rare_sync.bat cover');
    exit(1);
  }
  final hits = <String, Map<int, int>>{};
  String? cur;
  for (final l in lcov.readAsLinesSync()) {
    if (l.startsWith('SF:')) {
      final p = l.substring(3).replaceAll('\\', '/');
      final k = p.indexOf('lib/');
      cur = k >= 0 ? p.substring(k) : p;
      hits.putIfAbsent(cur, () => {});
    } else if (l.startsWith('DA:') && cur != null) {
      final parts = l.substring(3).split(',');
      hits[cur]![int.parse(parts[0])] = (hits[cur]![int.parse(parts[0])] ?? 0) + int.parse(parts[1]);
    }
  }

  var passed = 0, missed = 0, unknown = 0;
  final out = StringBuffer('🧭 نقاط المزامنة النادرة — ${DateTime.now().toIso8601String().substring(0, 16)}\n\n');
  for (final p in _points) {
    final lines = File(p.file).readAsLinesSync();
    final start = lines.indexWhere((l) => l.contains(p.function));
    var line = -1;
    if (start >= 0) {
      var n = 0;
      for (var i = start; i < lines.length; i++) {
        if (lines[i].contains(p.text) && ++n == p.occurrence) {
          line = i + 1;
          break;
        }
      }
    }
    final h = hits[p.file];
    int? count;
    if (line > 0 && h != null) {
      for (final d in const [0, 1, 2, 3, -1]) {
        if (h.containsKey(line + d)) {
          count = h[line + d];
          break;
        }
      }
    }
    final where = '${p.file.split('/').last}:${line > 0 ? line : '؟'}';
    if (count == null) {
      unknown++;
      out.writeln('❔ ${p.title}\n     $where — لم يُقَس (الملف لم يُحمَّل أو السطر لم يوجد)');
    } else if (count > 0) {
      passed++;
      out.writeln('✅ ${p.title}\n     $where — مرّ به $count مرة');
    } else {
      missed++;
      out.writeln('➖ ${p.title}\n     $where — لم يمر به اختبار: ${p.ifMissed}');
    }
  }
  out.writeln('\nالمجموع ${_points.length}: مرّ ${passed} — لم يمر $missed — لم يُقَس $unknown');
  print(out);
  Directory('test_results/rare_sync').createSync(recursive: true);
  File('test_results/rare_sync/rare_points.txt').writeAsStringSync(out.toString());
}
