// test/maintenance/db_size_test.dart
//
// 🗜️ حجم القاعدة: نسخ الفاتورة بالفروق (إعادة بناء حرفية)، أحداث التعديل بالأسطر
// المتغيّرة فقط، تقليم علاقات البحث الذكي، وسياسة سجل التصفح.
// التشغيل: flutter test test/maintenance/db_size_test.dart

import 'dart:convert';

import 'package:alnaser/services/database/business/snapshot_chain.dart';
import 'package:alnaser/services/database/core/data_retention.dart';
import 'package:alnaser/services/invoice_edit_events.dart';
import 'package:alnaser/services/smart_search/smart_search_prune.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> _line(String name, double qty, double price, {String st = 'قطعة', double cost = 0}) => {
      'product_name': name,
      'quantity_individual': qty,
      'applied_price': price,
      'item_total': qty * price,
      'sale_type': st,
      if (cost > 0) 'actual_cost_price': cost,
    };

String _list(List<Map<String, dynamic>> rows) => jsonEncode(rows);

/// مواد ثابتة لا تتغير (الفاتورة الحقيقية أطول من سطرين؛ الفرق يُحفظ حين يكون أصغر من الكاملة)
final _same = [
  for (final n in ['سلك نحاس 2.5', 'سلك نحاس 4', 'مفتاح إنارة', 'بريزة', 'شريط عازل', 'لمبة LED 12 واط'])
    _line(n, 3, 1250, cost: 900),
];

/// صفوف invoice_snapshots كما تُخزَّن: الأولى كاملة، وما بعدها فرق (إن كان أصغر).
List<Map<String, dynamic>> _chainRows(int invoiceId, List<List<Map<String, dynamic>>> versions) {
  final rows = <Map<String, dynamic>>[];
  final stored = <String>[];
  String? prevFull;
  for (var v = 0; v < versions.length; v++) {
    final full = _list(versions[v]);
    var text = full;
    if (prevFull != null) {
      text = SnapshotChain.encodeDelta(prevFull, full, chainLength: SnapshotChain.trailingDeltas(stored)) ?? full;
    }
    stored.add(text);
    rows.add({'id': rows.length + 1, 'invoice_id': invoiceId, 'version_number': v + 1, 'items_json': text, 'total_amount': 1});
    prevFull = full;
  }
  return rows;
}

Set<String> _set(String json) => {for (final e in jsonDecode(json) as List) jsonEncode(e)};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('نسخ الفاتورة بالفروق', () {
    test('مثال الماء والبيبسي: إعادة البناء حرفية لكل نسخة', () {
      final v1 = [..._same, _line('ماء', 2, 250), _line('بيبسي', 1, 500)];
      final v2 = [..._same, _line('ماء', 3, 250), _line('بيبسي', 1, 500), _line('عصير', 1, 750)];
      final v3 = [..._same, _line('بيبسي', 1, 500), _line('عصير', 2, 750)];
      final rows = _chainRows(7, [v1, v2, v3]);
      expect(SnapshotChain.isDelta(rows[0]['items_json'] as String), isFalse);
      expect(SnapshotChain.isDelta(rows[1]['items_json'] as String), isTrue);
      final m = SnapshotChain.materialize(rows, (r) => '$r');
      expect(_set(m[0]['items_json'] as String), _set(_list(v1)));
      expect(_set(m[1]['items_json'] as String), _set(_list(v2)));
      expect(_set(m[2]['items_json'] as String), _set(_list(v3)));
      expect(m.any((r) => r['items_unknown'] == 1), isFalse);
    });

    test('سطران متطابقان يُعدّان اثنين (طرح متعدد المجموعات)', () {
      final v1 = [_line('ماء', 1, 250), _line('ماء', 1, 250), _line('ماء', 1, 250)];
      final v2 = [_line('ماء', 1, 250)];
      final m = SnapshotChain.materialize(_chainRows(1, [v1, v2]), (r) => '$r');
      expect((jsonDecode(m[1]['items_json'] as String) as List).length, 1);
    });

    test('سلسلة مكسورة: لا تخمين — «غير معروف» ثم تعود السلسلة عند أول نسخة كاملة', () {
      final v1 = [..._same, _line('ماء', 2, 250)];
      final v2 = [..._same, _line('ماء', 3, 250)];
      final rows = _chainRows(3, [v1, v2]);
      expect(SnapshotChain.isDelta(rows[1]['items_json'] as String), isTrue);
      // نسخة أولى عُبث بها (الماء صار 5): الفرق يحذف «ماء 2» غير الموجود
      rows[0]['items_json'] = _list([..._same, _line('ماء', 5, 250)]);
      final m = SnapshotChain.materialize(rows, (r) => '$r');
      expect(m[1]['items_json'], isNull);
      expect(m[1]['items_unknown'], 1);
    });

    test('بصمة لا تطابق ⇒ غير معروف', () {
      final rows = _chainRows(4, [
        [..._same, _line('ماء', 2, 250)],
        [..._same, _line('ماء', 3, 250)],
      ]);
      expect(SnapshotChain.isDelta(rows[1]['items_json'] as String), isTrue);
      final d = jsonDecode(rows[1]['items_json'] as String) as Map<String, dynamic>;
      d['fp'] = '0000000000000000';
      rows[1]['items_json'] = jsonEncode(d);
      final m = SnapshotChain.materialize(rows, (r) => '$r');
      expect(m[1]['items_unknown'], 1);
    });

    test('نسخة كاملة بعد سلسلة طويلة، وفواتير متعددة لا تختلط', () {
      final versions = [
        for (var i = 1; i <= SnapshotChain.kFullEvery + 3; i++)
          [_line('ماء', i.toDouble(), 250), _line('شاي', 1, 1000), _line('سكر', 2, 1500), _line('ملح', 1, 250)]
      ];
      final rows = [..._chainRows(1, versions), ..._chainRows(2, versions.take(3).toList())];
      final texts = [for (final r in rows.where((r) => r['invoice_id'] == 1)) r['items_json'] as String];
      expect(texts.where((t) => !SnapshotChain.isDelta(t)).length, greaterThanOrEqualTo(2));
      final m = SnapshotChain.materialize(rows, (r) => '$r');
      for (var i = 0; i < versions.length; i++) {
        expect(_set(m[i]['items_json'] as String), _set(_list(versions[i])));
      }
      expect(_set(m[versions.length + 2]['items_json'] as String), _set(_list(versions[2])));
    });

    test('المساواة بلا ترتيب', () {
      final a = _list([_line('ماء', 1, 250), _line('شاي', 1, 1000)]);
      final b = _list([_line('شاي', 1, 1000), _line('ماء', 1, 250)]);
      expect(SnapshotChain.sameItems(a, b), isTrue);
      expect(SnapshotChain.sameItems(a, _list([_line('ماء', 2, 250), _line('شاي', 1, 1000)])), isFalse);
    });
  });

  group('أحداث التعديل: الأسطر المتغيّرة فقط', () {
    test('المجموع (بعد − قبل) لا يتغيّر', () {
      Map<String, Object?> l(String n, double q, double t) => {'product_name': n, 'qi': q, 'item_total': t};
      final before = [l('ماء', 2, 500), l('بيبسي', 1, 500), l('ماء', 2, 500)];
      final after = [l('ماء', 2, 500), l('بيبسي', 2, 1000), l('عصير', 1, 750)];
      final (b, a) = InvoiceEditEvents.changedLines(before, after);
      double sum(List<Map<String, Object?>> x) => x.fold(0.0, (s, e) => s + (e['item_total'] as double));
      expect(sum(a) - sum(b), sum(after) - sum(before));
      expect(b.length, 2); // بيبسي 1 + أحد سطري الماء
      expect(a.length, 2); // بيبسي 2 + عصير
    });
  });

  group('تقليم علاقات البحث الذكي', () {
    test('أقوى 20 لكل مادة، والحديث لا يُحذف', () {
      const cutoff = '2026-09-29';
      final rows = <PruneRow>[
        for (var i = 1; i <= 30; i++) PruneRow(i, 1, 100 + i, 100 - i, '2026-01-01'),
        const PruneRow(999, 1, 500, 1, '2026-10-20'), // حديث وضعيف
      ];
      final del = SmartSearchPrune.idsToDelete(rows, keep: 20, cutoffIso: cutoff);
      expect(del.length, 10); // من 21 إلى 30
      expect(del.contains(5), isFalse);
      expect(del.contains(999), isFalse);
    });

    test('تبقى العلاقة إن كانت ضمن الأقوى لطرفها الآخر', () {
      final rows = <PruneRow>[
        for (var i = 1; i <= 25; i++) PruneRow(i, 1, 100 + i, 100, '2026-01-01'),
        const PruneRow(50, 1, 777, 1, '2026-01-01'), // ضعيف عند المادة 1 لكنه الوحيد للمادة 777
      ];
      final del = SmartSearchPrune.idsToDelete(rows, keep: 20, cutoffIso: '2026-09-29');
      expect(del.contains(50), isFalse);
    });
  });

  group('سجل التصفح', () {
    test('يُحذف التصفح الأقدم من 7 أيام فقط، والعمليات المالية لا تُمسّ', () async {
      final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false));
      await db.execute('CREATE TABLE accounting_settings (key TEXT PRIMARY KEY, value TEXT)');
      await db.execute('CREATE TABLE activity_logs (id INTEGER PRIMARY KEY, at TEXT, user_name TEXT, action TEXT, screen TEXT, details TEXT)');
      final now = DateTime(2026, 10, 29, 12);
      Future<void> add(String action, int daysAgo) =>
          db.insert('activity_logs', {'at': now.subtract(Duration(days: daysAgo)).toIso8601String(), 'action': action});
      await add('تصفح', 30);
      await add('تصفح', 8);
      await add('تصفح', 2);
      await add('حذف', 400);
      await add('تعديل', 30);
      expect(await DataRetention.runIfDue(db, now: now), 2);
      final left = await db.query('activity_logs');
      expect(left.length, 3);
      expect(left.where((r) => r['action'] == 'حذف').length, 1);
      // مرة في اليوم
      await add('تصفح', 9);
      expect(await DataRetention.runIfDue(db, now: now), 0);
      await db.close();
    });
  });
}
