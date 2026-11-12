// test/sync_harness/product_card_test.dart
//
// 🗂️ حركة المادة بكود التطبيق الحقيقي (InventoryReports.productCard كما تعرضه الشاشتان):
//   رصيد افتتاحي 100 ← شراء 20 ← فاتورة 10 ← تعديلها إلى 7 ← ثم إلى 12 ← فاتورة ثانية 4
//   ← حذف المادة منها بالتعديل ← مرتجع 2.
// ما يُفحص:
//   1. كل حركة بنوعها وكميتها وترتيبها الزمني، والتعديل حركة مستقلة «كانت X صارت Y».
//   2. رقم الفاتورة في البيان هو المطبوع (invoice_number)، لا الرقم الداخلي.
//   3. الرصيد بعد كل حركة = ما قبلها + كميتها، وآخر رصيد = كمية المادة المسجّلة (110).
//   4. فرق مصطنع في كمية المادة ⇒ البطاقة تكشفه صراحة ولا تخترع له حركة.
//
// التشغيل: claude_test_product_card.bat
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('🗂️ حركة المادة: البيع والتعديل «كانت X صارت Y» والرصيد', () async {
    final h = Harness(seed: 158);
    final problems = <String>[];
    void bad(String p) {
      problems.add(p);
      print('✗ هنا وقع خطأ: $p');
    }

    void ok(String p) => print('✓ $p');
    double dd(Object? v) => (v as num?)?.toDouble() ?? 0.0;
    bool near(double a, double b) => (a - b).abs() <= 0.0005;
    const cust = 'زبون حركة المادة';

    try {
      await h.spawn('D1');
      await h.initDevice('D1');
      final d = h.d('D1');

      final uA = (await h.addProduct('D1', 'مادة الحركة', 100))!;
      await h.addProduct('D1', 'مادة مرافقة', 50);
      final prods = ((await d.call('scen', {'op': 'prodIds', 'args': const {}})) as Map)['rows'] as List;
      int pidOf(String name) => ((prods.firstWhere((r) => (r as Map)['name'] == name) as Map)['id'] as num).toInt();
      final pidA = pidOf('مادة الحركة'), pidB = pidOf('مادة مرافقة');
      await d.call('purchase', {'prod': uA, 'qty': 20});

      Future<String> save(List<Map<String, Object?>> items, {String? inv}) async {
        final r = (await d.call('scen', {
          'op': 'invSave',
          'args': {
            'inv': inv,
            'name': cust,
            'items': items,
            'discount': 0,
            'fee': 0,
            'paid': 0,
            'ptype': 'دين',
          },
        }, const Duration(minutes: 2))) as Map;
        if (r['ok'] != true) throw StateError('حفظ الفاتورة رُفض: ${r['stage']} ${r['err']}');
        return r['uuid'] as String;
      }

      Map<String, Object?> line(int pid, double qty) => {'prodId': pid, 'qty': qty, 'price': 1000};

      final inv1 = await save([line(pidA, 10)]);
      await save([line(pidA, 7)], inv: inv1);
      await save([line(pidA, 12)], inv: inv1);
      final inv2 = await save([line(pidA, 4), line(pidB, 1)]);
      await save([line(pidB, 1)], inv: inv2);

      final cu = (((await d.call('scen', {'op': 'custByName', 'args': {'name': cust}})) as Map)['rows'] as List);
      final rr = (await d.call('salesReturn', {
        'inv': inv1,
        'cust': (cu.single as Map)['uuid'],
        'items': [
          {'prod': uA, 'qty': 2, 'price': 1000}
        ],
        'mode': 'credit',
      })) as Map;
      if (rr['ok'] != true) throw StateError('المرتجع رُفض: ${rr['err']}');

      Future<String> printedNo(String inv) async {
        final r = (await d.call('sqlRaw', {
          'sql': "SELECT invoice_number AS n, id FROM invoices WHERE invoice_uuid = '$inv'"
        })) as List;
        final m = r.single as Map;
        final n = '${m['n'] ?? ''}'.trim();
        return n.isEmpty ? '#${'${m['id']}'.padLeft(5, '0')}' : n;
      }

      final no1 = await printedNo(inv1), no2 = await printedNo(inv2);
      print('  رقما الفاتورتين المطبوعان: $no1، $no2');

      // ── البطاقة ──
      final card = (await d.call('scen', {'op': 'productCard', 'args': {'prodId': pidA}})) as Map;
      final rows = [for (final r in (card['rows'] as List).reversed) (r as Map).cast<String, Object?>()];
      for (final r in rows) {
        print('  ${'${r['d']}'.padRight(26)} ${'${r['kind']}'.padRight(14)} ${dd(r['q']).toStringAsFixed(2).padLeft(8)}'
            '  رصيد ${dd(r['balance']).toStringAsFixed(2).padLeft(7)}  ${r['note'] ?? ''}');
      }

      // 1) الحركات بالترتيب
      final expected = <(String, double, String?)>[
        ('opening', 100, null),
        ('purchase', 20, null),
        ('sale', -10, 'فاتورة رقم $no1 — $cust'),
        ('sale_edit', 3, 'تعديل الفاتورة رقم $no1: كانت 10 صارت 7 — $cust'),
        ('sale_edit', -5, 'تعديل الفاتورة رقم $no1: كانت 7 صارت 12 — $cust'),
        ('sale', -4, 'فاتورة رقم $no2 — $cust'),
        ('sale_edit', 4, 'تعديل الفاتورة رقم $no2: كانت 4 صارت 0 — $cust'),
        ('sales_return', 2, null),
      ];
      if (rows.length != expected.length) {
        bad('1: عدد الحركات ${rows.length} والمتوقع ${expected.length}');
      } else {
        for (var i = 0; i < expected.length; i++) {
          final (kind, q, note) = expected[i];
          final r = rows[i];
          if (r['kind'] != kind || !near(dd(r['q']), q)) {
            bad('1: الحركة ${i + 1} ${r['kind']} ${r['q']} والمتوقع $kind $q');
          }
          if (note != null && r['note'] != note) bad('1: بيان الحركة ${i + 1} «${r['note']}» والمتوقع «$note»');
        }
        if (problems.isEmpty) ok('1: ثماني حركات بنوعها وكميتها وترتيبها، والتعديلات «كانت X صارت Y»');
      }

      // 2) الرقم المطبوع لا الداخلي
      final p2 = problems.length;
      for (final r in rows) {
        if ('${r['note'] ?? ''}'.contains('فاتورة #')) bad('2: بيان برقم داخلي: ${r['note']}');
      }
      if (problems.length == p2) ok('2: كل البيانات برقم الفاتورة المطبوع');

      // 3) الرصيد التراكمي والمطابقة
      final p3 = problems.length;
      var run = 0.0;
      for (var i = 0; i < rows.length; i++) {
        run += dd(rows[i]['q']);
        if (!near(dd(rows[i]['balance']), run)) bad('3: رصيد الحركة ${i + 1} ${rows[i]['balance']} والمتوقع $run');
      }
      final stock = dd((((await d.call('scen', {'op': 'prodIds', 'args': const {}})) as Map)['rows'] as List)
          .firstWhere((r) => (r as Map)['id'] == pidA)['stock']);
      if (!near(stock, 110)) bad('3: كمية المادة المسجّلة $stock والمتوقع 110');
      if (!near(dd(card['ledger']), 110) || !near(dd(card['stored']), stock) || card['matches'] != true) {
        bad('3: آخر رصيد ${card['ledger']} والمسجّل ${card['stored']} (مطابق: ${card['matches']})');
      }
      if (problems.length == p3) ok('3: الرصيد بعد كل حركة صحيح، وآخره 110 = كمية المادة');

      // 4) فرق مصطنع ⇒ تنبيه صريح، بلا حركة مخترعة
      final p4 = problems.length;
      await d.call('sqlRaw', {'sql': 'UPDATE products SET stock_quantity = stock_quantity + 5 WHERE id = $pidA'});
      final c4 = (await d.call('scen', {'op': 'productCard', 'args': {'prodId': pidA}})) as Map;
      await d.call('sqlRaw', {'sql': 'UPDATE products SET stock_quantity = stock_quantity - 5 WHERE id = $pidA'});
      if (c4['matches'] != false) bad('4: فرق 5 في كمية المادة ولم تكشفه البطاقة');
      if ((c4['rows'] as List).length != rows.length) bad('4: البطاقة اخترعت حركة لتسدّ الفرق');
      if (!near(dd(c4['ledger']), 110)) bad('4: آخر رصيد تغيّر إلى ${c4['ledger']}');
      if (problems.length == p4) ok('4: فرق 5 مكشوف صراحة ولا حركة مخترعة');

      for (final e in ((await h.rest('D1', 'invariants')) as List).cast<String>()) {
        bad('فحص المال الشامل: $e');
      }
      problems.addAll(await h.deviceErrors());
      print('\n${problems.isEmpty ? '✅ نجح: حركة المادة صحيحة وواضحة' : '❌ هنا وقع خطأ: ${problems.length} مشكلة'}');
      expect(problems, isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
