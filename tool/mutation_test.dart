// tool/mutation_test.dart
//
// 🧬 فحص الطفرات: هل تكشف اختباراتنا الخطأ إن وقع؟
//
// لكل «طفرة» (خطأ حسابي متعمّد واقعي في كود المال، سطر واحد):
//   1. يتحقق أن الملف كما هو (بصمته) وأن النص المستهدف موجود مرة واحدة بالضبط.
//   2. يحفظ نسخة من الملف الأصلي ويسجّل «طفرة جارية» في .dart_tool/mutation/active.json.
//   3. يكتب الخطأ، ويشغّل الاختبارات التي يجب أن تكشفه.
//   4. يعيد الملف الأصلي فوراً ويتحقق أن بصمته عادت كما كانت حرفاً بحرف.
// النتيجة لكل طفرة:
//   ✅ كُشفت  — فشل اختبار (هذا هو المطلوب: الاختبار يحمي من هذا الخطأ).
//   ❌ نجت    — نجحت كل الاختبارات والكود خاطئ: ثغرة في الاختبارات يجب سدّها.
//   ⚠️ لم تُبنَ — الكود لم يُترجم بعد الطفرة (لا تُحسب).
//
// الأمان: الإيقاف بـ Ctrl+C يعيد الملف قبل الخروج، وإن انطفأ الحاسوب في منتصف طفرة تُعاد
// في أول تشغيل تالٍ (قبل أي شيء آخر) من النسخة المحفوظة، مع التحقق من البصمة.
//
// التشغيل: claude_test_mutations.bat      (أو: dart run tool/mutation_test.dart [رقم الطفرة])
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show md5;

class Mutation {
  const Mutation(this.id, this.title, this.file, this.find, this.replace, this.tests);
  final String id;
  final String title;
  final String file;
  final String find;
  final String replace;
  final List<String> tests;
}

const _durability = 'test/sync_harness/durability_test.dart';
const _compound = 'test/sync_harness/compound_receipt_test.dart';
const _armored = 'test/sync_harness/armored_approval_test.dart';
const _lan = 'test/sync_harness/lan_money_test.dart';
const _scenarios = 'test/sync_harness/invoice_scenarios_test.dart';
const _iqd = 'test/services/iqd_whole_dinar_test.dart';
const _safety = 'test/services/disk_space_and_invoice_safety_test.dart';

const mutations = <Mutation>[
  Mutation('M01', 'تقريب الدينار: النصف لغير صالح المحل', 'lib/utils/iqd.dart',
      'static double up(num v) => _toWhole(v, true);', 'static double up(num v) => _toWhole(v, false);', [_iqd]),
  Mutation('M02', 'مبلغ سطر الفاتورة ≠ الكمية × السعر لا يُكشف', 'lib/services/invoice_safety/line_math_check.dart',
      'if ((it.itemTotal - expected).abs() > tolerance) {', 'if ((it.itemTotal - expected).abs() > tolerance * 1000000) {',
      [_safety]),
  Mutation('M03', 'حارس الرصيد السالب معطّل (تحويل/تعديل يُنزل دين العميل تحت الصفر)',
      'lib/controllers/invoice_controller.dart', 'if (debtChange < -0.01 && expectedNewBalance < -0.01) {',
      'if (debtChange < -0.01 && expectedNewBalance < -1000000000) {', [_durability]),
  Mutation('M04', 'الحفظ على القرص يعود NORMAL (انقطاع الكهرباء يضيّع آخر العمليات)',
      'lib/services/database/core/database_config.dart', "await db.rawQuery('PRAGMA synchronous = FULL');",
      "await db.rawQuery('PRAGMA synchronous = NORMAL');", [_durability]),
  Mutation('M05', 'التحويل إلى نقد بلا «سند قبض — تسديد فاتورة»', 'lib/services/invoice_edit_events.dart',
      'if (paidDelta >= 0.5) return kindInvoiceSettlement;', 'if (paidDelta >= 0.5) return null;', [_durability]),
  Mutation('M06', 'قيد الصندوق لتعديل الفاتورة مضاعف', 'lib/accounting/posting_engine.dart',
      "JournalLineInput(accountId: cashAcc, debit: dc, memo: 'مقبوض إضافة على فاتورة'),",
      "JournalLineInput(accountId: cashAcc, debit: dc * 2, memo: 'مقبوض إضافة على فاتورة'),", [_durability]),
  Mutation('M07', 'إكمال وصل منقطع يكرّر التسديد المسجّل (المعرّف المحجوز مُهمل)', 'lib/erp/debts/customer_money.dart',
      'if (had.isNotEmpty) return presetUuid;', 'if (had.isNotEmpty && presetUuid.isEmpty) return presetUuid;', [_compound]),
  Mutation('M08', 'إكمال وصل منقطع يعيد وصف أسطر سُجّلت', 'lib/erp/debts/receipts_service.dart',
      'if (resuming && (l.uuids.isEmpty || await _lineRecorded(db, receiptId, l))) continue;',
      'if (resuming && l.uuids.isEmpty) continue;', [_compound]),
  Mutation('M09', '«الرصيد قبل» في وصل منقطع بالإشارة المعكوسة', 'lib/erp/debts/receipts_service.dart',
      "'balance_before': roundMoney(before + already),", "'balance_before': roundMoney(before - already),", [_compound]),
  Mutation('M10', 'المطابقة المحصّنة تكتب على الجهاز الآخر بلا موافقة',
      'lib/services/firebase_sync/armored_reconciliation_service.dart',
      'bool get changesMoney => addCount > 0 || voidCount > 0;', 'bool get changesMoney => false;', [_armored]),
  Mutation('M11', 'طرفية تُنزل الحفظ على القرص عند السيرفر', 'lib/lan/lan_server.dart',
      "if (sql is String && _syncPragma.hasMatch(sql)) map['sql'] = 'PRAGMA synchronous = FULL';",
      'if (sql is String && _syncPragma.hasMatch(sql) && sql.isEmpty) map[\'sql\'] = \'PRAGMA synchronous = FULL\';',
      [_lan]),
  Mutation('M12', 'تحويل فاتورة آجلة إلى نقد يطرح ضعف دينها', 'lib/controllers/invoice_controller.dart',
      "if (data.paymentType == 'نقد') {\n      debtChange = -oldRemaining;",
      "if (data.paymentType == 'نقد') {\n      debtChange = -oldRemaining * 2;", [_durability, _scenarios]),
];

const _stateDir = '.dart_tool/mutation';
const _statePath = '$_stateDir/active.json';

String _md5(List<int> bytes) => md5.convert(bytes).toString();

/// يعيد ملفاً تركته طفرة سابقة لم تكتمل (انطفاء، إغلاق النافذة).
bool restoreLeftover() {
  final st = File(_statePath);
  if (!st.existsSync()) return true;
  final s = (jsonDecode(st.readAsStringSync()) as Map).cast<String, Object?>();
  final file = File(s['file'] as String);
  final backup = File(s['backup'] as String);
  if (!backup.existsSync()) {
    print('هنا وقع خطأ: طفرة سابقة لم تكتمل والنسخة المحفوظة مفقودة: ${s['backup']}');
    return false;
  }
  final bytes = backup.readAsBytesSync();
  if (_md5(bytes) != s['md5']) {
    print('هنا وقع خطأ: النسخة المحفوظة لـ ${s['file']} لا تطابق بصمتها — لم يُلمس شيء، راجعها يدوياً');
    return false;
  }
  file.writeAsBytesSync(bytes, flush: true);
  if (_md5(file.readAsBytesSync()) != s['md5']) {
    print('هنا وقع خطأ: تعذّر إعادة ${s['file']} كما كان');
    return false;
  }
  backup.deleteSync();
  st.deleteSync();
  print('♻️ أُعيد ${s['file']} من طفرة سابقة لم تكتمل (البصمة مطابقة)');
  return true;
}

Map<String, Object?>? _active;

void _restoreActive() {
  final s = _active;
  if (s == null) return;
  final original = File(s['backup'] as String).readAsBytesSync();
  File(s['file'] as String).writeAsBytesSync(original, flush: true);
  if (_md5(File(s['file'] as String).readAsBytesSync()) != s['md5']) {
    throw StateError('تعذّر إعادة ${s['file']} كما كان');
  }
  File(s['backup'] as String).deleteSync();
  File(_statePath).deleteSync();
  _active = null;
}

Future<String> _runTests(List<String> tests, IOSink log) async {
  final args = ['test', ...tests, '--dart-define=QUICK=true', '--reporter', 'expanded'];
  final p = await Process.start('flutter', args, runInShell: true);
  final out = StringBuffer();
  final done = Completer<void>();
  var pending = 2;
  void collect(Stream<List<int>> s) => s.transform(utf8.decoder).listen((t) {
        out.write(t);
        log.write(t);
      }, onDone: () {
        if (--pending == 0) done.complete();
      });
  collect(p.stdout);
  collect(p.stderr);
  final code = await p.exitCode.timeout(const Duration(minutes: 30), onTimeout: () {
    p.kill();
    return -1;
  });
  await done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  final text = out.toString();
  if (code == 0) return 'survived';
  if (code == -1) return 'timeout';
  final compileError = text.contains('Error: ') && (text.contains('Compilation failed') ||
      text.contains('Failed to load') || RegExp(r'\.dart:\d+:\d+: Error').hasMatch(text));
  return compileError ? 'invalid' : 'killed';
}

Future<void> main(List<String> argv) async {
  if (!restoreLeftover()) exit(2);
  Directory(_stateDir).createSync(recursive: true);
  Directory('test_results/mutations').createSync(recursive: true);
  final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '');
  final log = File('test_results/mutations/log_$stamp.txt').openWrite();

  // Ctrl+C: يُعاد الملف قبل الخروج
  ProcessSignal.sigint.watch().listen((_) {
    try {
      _restoreActive();
      print('\n⏹️ أُوقف — أُعيد الملف الأصلي');
    } catch (e) {
      print('\nهنا وقع خطأ عند الإيقاف: $e — شغّل الأداة مرة أخرى لتعيده');
    }
    exit(130);
  });

  final only = argv.isEmpty ? null : argv.first.toUpperCase();
  final list = [for (final m in mutations) if (only == null || m.id == only) m];
  final results = <String, String>{};
  final report = StringBuffer('🧬 فحص الطفرات — $stamp\n\n');

  for (var i = 0; i < list.length; i++) {
    final m = list[i];
    print('\n━━ ${i + 1}/${list.length} ${m.id}: ${m.title}');
    final file = File(m.file);
    final bytes = file.readAsBytesSync();
    final text = utf8.decode(bytes);
    final normalized = text.replaceAll('\r\n', '\n');
    final hits = m.find.allMatches(normalized).length;
    if (hits != 1) {
      results[m.id] = 'stale';
      final line = '⚠️ ${m.id} ${m.title}: النص المستهدف موجود $hits مرة في ${m.file} (تغيّر الكود) — لم تُجرَّب';
      print(line);
      report.writeln(line);
      continue;
    }
    // الطفرة تحترم نهايات الأسطر في الملف (CRLF أو LF)
    final crlf = text.contains('\r\n');
    String nl(String s) => crlf ? s.replaceAll('\n', '\r\n') : s;
    final mutated = text.replaceFirst(nl(m.find), nl(m.replace));

    final backup = '$_stateDir/${m.id}.orig';
    File(backup).writeAsBytesSync(bytes, flush: true);
    _active = {'file': m.file, 'backup': backup, 'md5': _md5(bytes), 'id': m.id};
    File(_statePath).writeAsStringSync(jsonEncode(_active), flush: true);
    String r;
    try {
      file.writeAsStringSync(mutated, flush: true);
      log.writeln('\n===== ${m.id} ${m.title} =====');
      r = await _runTests(m.tests, log);
    } finally {
      _restoreActive();
    }
    results[m.id] = r;
    final line = switch (r) {
      'killed' => '✅ كُشفت ${m.id}: ${m.title}',
      'survived' => '❌ نجت ${m.id}: ${m.title} — الاختبارات (${m.tests.map((t) => t.split('/').last).join('، ')}) لم تكشفها',
      'invalid' => '⚠️ لم تُبنَ ${m.id}: ${m.title} (خطأ ترجمة بعد الطفرة — لا تُحسب)',
      _ => '⚠️ انتهت المهلة ${m.id}: ${m.title}',
    };
    print(line);
    report.writeln(line);
  }

  final killed = results.values.where((r) => r == 'killed').length;
  final survived = results.values.where((r) => r == 'survived').length;
  final counted = killed + survived;
  final summary = '\nكُشفت $killed من $counted طفرة محسوبة'
      '${counted == 0 ? '' : ' (${(100 * killed / counted).toStringAsFixed(0)}%)'}'
      '${survived > 0 ? ' — هنا وقع خطأ: $survived نجت (ثغرات في الاختبارات)' : ''}';
  print(summary);
  report.writeln(summary);
  await log.close();
  File('test_results/mutations/report.txt').writeAsStringSync(report.toString());
  exit(survived > 0 ? 1 : 0);
}
