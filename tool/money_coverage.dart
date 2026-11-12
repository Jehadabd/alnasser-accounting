// tool/money_coverage.dart
//
// 📊 خريطة مسارات المال وتغطيتها بالاختبارات.
//
// 1) يمسح lib/ عن كل مكان يكتب في جدول فيه مال (ديون العملاء والموردين، الفواتير،
//    الوصولات، المرتجعات، السندات والقيود، الرواتب، الأصول، التوصيل...).
// 2) يقرأ coverage/lcov.info (من flutter test --coverage) ويعلّم كل مكان: نفّذه اختبار أم لا.
// 3) يكتب التقرير: النسبة، وكل مسار مالي لم يمر به أي اختبار (الملف، السطر، الدالة).
//
// التشغيل: claude_money_coverage.bat (يشغّل الاختبارات بالتغطية ثم هذه الأداة)
//          أو مباشرة بعد تغطية موجودة: dart run tool/money_coverage.dart
// ignore_for_file: avoid_print

import 'dart:io';

const moneyTables = {
  'transactions', 'invoices', 'invoice_items', 'invoice_adjustments', 'customers',
  'customer_receipts', 'customer_receipt_lines', 'customer_receipt_vouchers', 'customer_tx_ext',
  'customer_reconciliations', 'sales_returns', 'sales_return_items', 'returns',
  'purchase_invoices', 'purchase_invoice_items', 'purchase_returns', 'purchase_return_items',
  'supplier_payments', 'supplier_transactions', 'suppliers', 'supplier_payment_ext',
  'vouchers', 'voucher_lines', 'journal_entries', 'journal_lines', 'cash_boxes', 'cash_counts',
  'bank_recs', 'delivery_orders', 'delivery_settlements', 'hr_advances', 'hr_payslips',
  'founder_opening', 'founder_return_links', 'fixed_assets', 'depreciation_lines', 'depreciation_runs',
  'landed_costs', 'due_items', 'invoice_extras', 'invoice_edit_vouchers', 'stock_lots',
};

/// للجداول التي تحمل غير المال أيضاً: لا يُعدّ مساراً مالياً إلا إن ذُكر عمود مالي قريباً
const mixedTables = {
  'customers': ['current_total_debt', 'debt'],
  'suppliers': ['total_debt', 'debt', 'balance'],
  'cash_boxes': ['balance', 'opening'],
};

final _write = RegExp(
    r'''(?:\.(insert|update|delete)\(\s*['"]([a-z_]+)['"])|(?:(INSERT\s+(?:OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM)\s+([a-z_]+))''',
    caseSensitive: false);
// دالة على مستوى الملف (بلا مسافة) أو عضو صنف (مسافتان) — لا الدوال المحلية ولا أسطر SQL
final _fn = RegExp(
    r'^( {0,2})(?:static\s+|@override\s+|external\s+)*(?:Future<.*?>+|Stream<.*?>+|void|int|double|bool|String|num|dynamic|[A-Z]\w*(?:<.*?>+)?)\??\s+([a-z_]\w*)\s*[(<]');

/// احتياطي لملفات بمسافات غير معتادة: أي مسافة، والاسم يبدأ بحرف صغير (لا كلمات SQL)
final _fnLoose = RegExp(
    r'^( *)(?:static\s+|@override\s+)*(?:Future<.*?>+|Stream<.*?>+|void|int|double|bool|String|num|dynamic|[A-Z]\w*(?:<.*?>+)?)\??\s+([a-z_]\w*)\s*\(');

/// ملفات ترحيل قاعدة البيانات: تعمل مرة عند الترقية من إصدار قديم — تُعرض وحدها ولا تدخل النسبة
bool _isMigration(String path) => path.endsWith('/database_migrations.dart');

class Point {
  Point(this.file, this.line, this.table, this.op, this.fn, {this.kind = 'code'});
  final String file;
  final int line;
  final String table, op, fn;
  /// code = كود يُنفَّذ؛ trigger = SQL داخل مشغّل (يعمل في SQLite لا يقاس بالأسطر)؛ migration = ترحيل قاعدة بيانات
  final String kind;
  int? hits; // null = السطر لا يظهر في التغطية
}

void main(List<String> args) {
  final root = Directory('lib');
  final points = <Point>[];
  for (final f in root.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    final path = f.path.replaceAll('\\', '/');
    if (path.contains('/devtools/') || path.endsWith('.g.dart')) continue;
    final lines = f.readAsLinesSync();
    var inTrigger = false;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.trimLeft().startsWith('//')) continue;
      // جسم المشغّل (CREATE TRIGGER ... END;) نص SQL ينفّذه SQLite نفسه — ليس سطر Dart يُقاس
      if (RegExp(r'CREATE\s+TRIGGER', caseSensitive: false).hasMatch(l)) inTrigger = true;
      final triggerLine = inTrigger;
      if (inTrigger && RegExp(r'\bEND\s*;', caseSensitive: false).hasMatch(l)) inTrigger = false;
      for (final m in _write.allMatches(l)) {
        final table = (m.group(2) ?? m.group(4) ?? '').toLowerCase();
        if (!moneyTables.contains(table)) continue;
        if (l.contains('CREATE TABLE') || l.contains('CREATE INDEX')) continue;
        final mixed = mixedTables[table];
        if (mixed != null) {
          final near = lines.sublist(i, i + 12 > lines.length ? lines.length : i + 12).join(' ');
          if (!mixed.any(near.contains)) continue;
        }
        var fn = '?';
        final indent = l.length - l.trimLeft().length;
        for (var j = i; j >= 0 && j > i - 1500; j--) {
          final fm = _fn.firstMatch(lines[j]);
          if (fm != null && fm.group(1)!.length < indent && !const {'if', 'for', 'while', 'switch', 'return', 'catch'}.contains(fm.group(2))) {
            fn = fm.group(2)!;
            break;
          }
        }
        for (var j = i; fn == '?' && j >= 0 && j > i - 1500; j--) {
          final fm = _fnLoose.firstMatch(lines[j]);
          if (fm != null && fm.group(1)!.length < indent && !const {'if', 'for', 'while', 'switch', 'return', 'catch'}.contains(fm.group(2))) {
            fn = fm.group(2)!;
          }
        }
        points.add(Point(path, i + 1, table, (m.group(1) ?? m.group(3) ?? '').split(RegExp(r'\s')).first.toUpperCase(), fn,
            kind: triggerLine ? 'trigger' : _isMigration(path) ? 'migration' : 'code'));
      }
    }
  }

  final lcov = File('coverage/lcov.info');
  if (!lcov.existsSync()) {
    print('هنا وقع خطأ: لا يوجد coverage/lcov.info — شغّل claude_money_coverage.bat');
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
      final ln = int.parse(parts[0]), n = int.parse(parts[1]);
      hits[cur]![ln] = (hits[cur]![ln] ?? 0) + n;
    }
  }

  for (final p in points) {
    final h = hits[p.file];
    if (h == null) continue;
    for (final d in const [0, 1, 2, 3, -1]) {
      if (h.containsKey(p.line + d)) {
        p.hits = h[p.line + d];
        break;
      }
    }
  }

  // فحص سلامة القياس: كود الأجهزة الوهمية (المزامنة) يجب أن يظهر منفَّذاً
  final syncHits = (hits['lib/services/firebase_sync/firebase_sync_service.dart'] ?? const {}).values.fold<int>(0, (a, b) => a + b);
  final code = points.where((p) => p.kind == 'code').toList();
  final triggers = points.where((p) => p.kind == 'trigger').toList();
  final migrations = points.where((p) => p.kind == 'migration').toList();
  final covered = code.where((p) => (p.hits ?? 0) > 0).toList();
  final missed = code.where((p) => p.hits == 0).toList();
  final unknown = code.where((p) => p.hits == null).toList();

  final out = StringBuffer()
    ..writeln('📊 خريطة مسارات المال وتغطيتها — ${DateTime.now().toIso8601String().substring(0, 16)}')
    ..writeln('مكان في الكود يكتب مالاً: ${code.length} — نفّذه اختبار: ${covered.length} — لم ينفّذه أي اختبار: ${missed.length} — لم يُقَس: ${unknown.length}')
    ..writeln('النسبة: ${covered.isEmpty && missed.isEmpty ? 0 : (100 * covered.length / (covered.length + missed.length)).toStringAsFixed(1)}% (من المقاس)')
    ..writeln('خارج النسبة: ${triggers.length} كتابة داخل مشغّلات SQLite (تعمل مع كل إدخال، لا تقاس بالأسطر) — '
        '${migrations.length} في ترحيل قاعدة البيانات (مرة عند الترقية من إصدار قديم)')
    ..writeln(syncHits == 0
        ? '⚠️ هنا وقع خطأ في القياس: كود المزامنة يظهر غير منفَّذ — تغطية الأجهزة الوهمية لم تُجمع، فالأرقام أدناه ناقصة'
        : '✓ تغطية الأجهزة الوهمية جُمعت (كود المزامنة منفَّذ $syncHits مرة)')
    ..writeln();
  void group(String title, List<Point> ps) {
    out.writeln('━━ $title (${ps.length}) ━━');
    final byFile = <String, List<Point>>{};
    for (final p in ps) {
      byFile.putIfAbsent(p.file, () => []).add(p);
    }
    for (final e in (byFile.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length)))) {
      out.writeln('  ${e.key}');
      for (final p in e.value) {
        out.writeln('     سطر ${p.line}  ${p.op} ${p.table}  — في ${p.fn}()');
      }
    }
    out.writeln();
  }

  group('❌ مسارات مال لم يمر بها أي اختبار', missed);
  group('❔ لم تُقَس (الملف كله لم يُحمَّل في أي اختبار)', unknown);
  group('🗄️ ترحيل قاعدة البيانات — خارج النسبة (لا يعمل على تثبيت جديد)', migrations.where((p) => (p.hits ?? 0) == 0).toList());
  group('⚙️ داخل مشغّلات SQLite — خارج النسبة', triggers);
  final tables = <String, List<int>>{};
  for (final p in code) {
    final t = tables.putIfAbsent(p.table, () => [0, 0]);
    if ((p.hits ?? 0) > 0) t[0]++;
    t[1]++;
  }
  out.writeln('━━ لكل جدول: المنفَّذ / الكل ━━');
  for (final e in (tables.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
    out.writeln('  ${e.key.padRight(28)} ${e.value[0]} / ${e.value[1]}');
  }
  final dir = Directory('test_results/money_coverage')..createSync(recursive: true);
  File('${dir.path}/report.txt').writeAsStringSync(out.toString());
  print(out);
  print('التقرير: ${dir.path}/report.txt');
}
