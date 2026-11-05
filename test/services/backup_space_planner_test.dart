// test/services/backup_space_planner_test.dart
//
// حذف النسخ القديمة عند الرفع: للمساحة قبل الرفع، وللعدد بعده، ولا تُحذف أحدث نسختين.

import 'package:alnaser/services/backup_space_planner.dart';
import 'package:flutter_test/flutter_test.dart';

const mb = 1024 * 1024;

List<BackupItem<String>> items(List<int> sizesMb) => [
      for (var i = 0; i < sizesMb.length; i++)
        BackupItem('b$i', DateTime(2025, 1, 1).add(Duration(days: i * 30)), sizesMb[i] * mb),
    ];

void main() {
  test('المكان يكفي ⇒ لا حذف قبل الرفع', () {
    final p = BackupSpacePlanner.plan(existing: items([2, 2, 2]), newSize: 10 * mb, free: 500 * mb, maxCount: 20);
    expect(p.fits, isTrue);
    expect(p.beforeUpload, isEmpty);
    expect(p.afterUpload, isEmpty);
  });

  test('مثال المالك: النسخة 10 ميغا والقديمة 2 ميغا ⇒ تُحذف الأقدم حتى يكفي (قبل الرفع)', () {
    // المطلوب = 10 + هامش (10 + 0.5) = 20.5 ميغا تقريباً، الفارغ 10 ⇒ يلزم 10.5 ⇒ 6 نسخ × 2
    final p = BackupSpacePlanner.plan(existing: items([2, 2, 2, 2, 2, 2, 2, 2, 2]), newSize: 10 * mb, free: 10 * mb, maxCount: 20);
    expect(p.fits, isTrue);
    expect(p.beforeUpload.map((b) => b.ref), ['b0', 'b1', 'b2', 'b3', 'b4', 'b5']); // الأقدم أولاً
    expect(p.freeBefore! + p.freedBefore, greaterThanOrEqualTo(p.needed));
  });

  test('الأقدم يُحذف أولاً مهما كان ترتيب القائمة', () {
    final list = items([2, 2, 2, 2]).reversed.toList();
    final p = BackupSpacePlanner.plan(existing: list, newSize: 1 * mb, free: 9 * mb, maxCount: 20);
    expect(p.beforeUpload.first.ref, 'b0');
  });

  test('لا تُحذف أحدث نسختين، وإن لم يكفِ المكان ⇒ لا حذف إطلاقاً', () {
    final p = BackupSpacePlanner.plan(existing: items([2, 2, 2]), newSize: 50 * mb, free: 1 * mb, maxCount: 20);
    expect(p.fits, isFalse);
    expect(p.beforeUpload, isEmpty);
    expect(p.afterUpload, isEmpty);
  });

  test('حد العدد: يُحذف الزائد بعد الرفع فقط', () {
    final p = BackupSpacePlanner.plan(existing: items([1, 1, 1, 1, 1]), newSize: 1 * mb, free: 900 * mb, maxCount: 3);
    expect(p.beforeUpload, isEmpty);
    expect(p.afterUpload.map((b) => b.ref), ['b0', 'b1', 'b2']); // يبقى b3,b4 + الجديدة = 3
  });

  test('المساحة والعدد معاً: لا يُحذف شيء مرتين', () {
    final p = BackupSpacePlanner.plan(existing: items([5, 5, 5, 5, 5, 5]), newSize: 1 * mb, free: 6 * mb, maxCount: 3);
    expect(p.beforeUpload.map((b) => b.ref), ['b0', 'b1']);
    expect(p.afterUpload.map((b) => b.ref), ['b2', 'b3']);
    final all = [...p.beforeUpload, ...p.afterUpload].map((b) => b.ref).toSet();
    expect(all.length, 4);
    expect(all.contains('b4') || all.contains('b5'), isFalse);
  });

  test('حد العدد لا يحذف أحدث نسختين حتى لو كان الحد 1', () {
    final p = BackupSpacePlanner.plan(existing: items([1, 1, 1]), newSize: 1 * mb, free: null, maxCount: 1);
    expect(p.afterUpload.map((b) => b.ref), ['b0']);
  });

  test('المساحة غير معروفة ⇒ قاعدة العدد وحدها', () {
    final p = BackupSpacePlanner.plan(existing: items([1, 1, 1, 1]), newSize: 999 * mb, free: null, maxCount: 2);
    expect(p.fits, isTrue);
    expect(p.beforeUpload, isEmpty);
    expect(p.afterUpload.map((b) => b.ref), ['b0', 'b1']);
  });

  test('لا نسخ سابقة', () {
    final p = BackupSpacePlanner.plan<String>(existing: const [], newSize: 5 * mb, free: 100 * mb, maxCount: 5);
    expect(p.fits, isTrue);
    expect(p.beforeUpload, isEmpty);
  });

  test('عرض الأحجام', () {
    expect(BackupSpacePlanner.human(2 * 1024 * mb), '2.0 غيغابايت');
    expect(BackupSpacePlanner.human(820 * mb), '820 ميغابايت');
    expect(BackupSpacePlanner.human(1536 * 1024), '1.5 ميغابايت');
  });
}
