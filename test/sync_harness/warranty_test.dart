// test/sync_harness/warranty_test.dart
//
// 🛡️ ضمان المادة على سطر الفاتورة — بكود التطبيق الحقيقي على جهازين متزامنين:
//   • D1: السيناريو الكامل (warranty_ops.dart): الحساب، بطاقة المادة، الفاتورة الجديدة،
//     التعديل بعد تغيير المدة، بلا ضمان، المعلّقة، الكاشير، من تاريخ الشراء، أعمدة الطباعة.
//   • D2: يستلم الفاتورة بضمان سطورها كما ثُبِّت على D1 (لا يُعاد حسابه)، ويستلم مدة ضمان المادة.
//   • فحص المال الشامل على الجهازين: الضمان لا يمسّ أي مبلغ.
//
// التشغيل: claude_test_warranty.bat
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('🛡️ الضمان: يُثبَّت على السطر عند البيع، ويبقى عند التعديل، ويصل الجهاز الآخر كما هو', () async {
    final h = Harness(seed: 1630);
    final problems = <String>[];
    void bad(String p) {
      problems.add(p);
      print('✗ هنا وقع خطأ: $p');
    }

    void ok(String p) => print('✓ $p');

    try {
      await h.start(2);
      Future<void> invariants(String dev, String stage) async {
        for (final e in ((await h.rest(dev, 'invariants')) as List).cast<String>()) {
          bad('$stage ($dev) — فحص المال الشامل: $e');
        }
      }

      final prod = (await h.addProduct('D1', 'مادة الضمان', 100))!;
      final e0 = await h.settle();
      if (e0.isNotEmpty) throw StateError('البداية: ${e0.join('\n')}');

      final r = (await h.d('D1').call('gap', {
        'op': 'warranty',
        'args': {'prod': prod}
      }, const Duration(minutes: 3))) as Map;
      final fails = (r['fails'] as List).cast<String>();
      for (final f in fails) {
        bad('D1: $f');
      }
      if (fails.isEmpty) ok('D1 — ${(r['notes'] as List).join('؛ ')}');
      await invariants('D1', 'بعد السيناريو');

      final e1 = await h.settle();
      for (final e in e1) {
        bad('المزامنة: $e');
      }

      final invA = r['invA'] as String?;
      final exp = ((r['expA'] as List?) ?? const []).cast<Map>();
      if (invA != null && exp.length == 2) {
        final rows = (await h.d('D2').call('sqlRaw', {
          'sql': 'SELECT it.warranty_spec AS s, it.warranty_end AS e, it.warranty_terms AS t FROM invoice_items it '
              "JOIN invoices i ON i.id = it.invoice_id WHERE i.invoice_uuid = '$invA' ORDER BY it.id"
        })) as List;
        if (rows.length != 2) {
          bad('D2: فاتورة الضمان وصلت بـ ${rows.length} سطر والمتوقع 2');
        } else {
          var same = true;
          for (var i = 0; i < 2; i++) {
            final got = rows[i] as Map;
            if (got['s'] != exp[i]['spec'] || got['e'] != exp[i]['end'] || got['t'] != exp[i]['terms']) {
              same = false;
              bad('D2 السطر ${i + 1}: ${got['s']} حتى ${got['e']} «${got['t']}» '
                  'والمتوقع ${exp[i]['spec']} حتى ${exp[i]['end']} «${exp[i]['terms']}»');
            }
          }
          if (same) ok('D2 استلم الفاتورة بضمان سطريها كما ثُبِّت على D1 (${exp[0]['end']} و${exp[1]['end']})');
        }
      }

      final spec = (await h.d('D2').call('sqlRaw', {
        'sql': "SELECT warranty_spec AS s FROM products WHERE sync_uuid = '$prod'"
      })) as List;
      final got = spec.isEmpty ? null : (spec.first as Map)['s'];
      if (got != r['spec']) {
        bad('D2: مدة ضمان المادة «$got» والمتوقع «${r['spec']}»');
      } else {
        ok('D2 استلم مدة ضمان المادة «$got»');
      }

      await invariants('D1', 'النهاية');
      await invariants('D2', 'النهاية');
      problems.addAll(await h.deviceErrors());
      print('\n${problems.isEmpty ? '✅ نجح: الضمان يُثبَّت ويُطبع ويُزامَن ولا يمسّ المال' : '❌ هنا وقع خطأ: ${problems.length} مشكلة'}');
      expect(problems, isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
