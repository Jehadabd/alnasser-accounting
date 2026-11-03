// test/control/screen_usage_test.dart

import 'package:alnaser/erp/activity/screen_usage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('اسم ثابت للشاشة', () {
    expect(ScreenUsage.normalize(' مواعيد المطالبة بالسداد — جهاد عبد '), 'مواعيد المطالبة بالسداد');
    expect(ScreenUsage.normalize('بضاعة العميل: علي'), 'بضاعة العميل');
    expect(ScreenUsage.normalize('س' * 80).length, 60);
  });

  test('سطر واحد لكل شاشة في اليوم، والمجموع لآخر 30 يوماً', () async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    final d1 = DateTime(2026, 11, 1, 10), d2 = DateTime(2026, 11, 3, 9), old = DateTime(2026, 9, 1);
    await ScreenUsage.bump(db, 'إنشاء فاتورة', now: d1);
    await ScreenUsage.bump(db, 'إنشاء فاتورة', now: d1);
    await ScreenUsage.bump(db, 'إنشاء فاتورة', now: d2);
    await ScreenUsage.bump(db, 'المحاسبة', now: d2);
    await ScreenUsage.bump(db, 'قديمة', now: old);
    expect((await db.rawQuery('SELECT COUNT(*) AS n FROM screen_usage')).first['n'], 4);
    final top = await ScreenUsage.top(db, now: DateTime(2026, 11, 3));
    expect(top.map((r) => '${r.screen}:${r.opens}:${r.days}'), ['إنشاء فاتورة:3:2', 'المحاسبة:1:1']);
    expect(top.first.lastDay, '2026-11-03');
    await db.close();
  });
}
