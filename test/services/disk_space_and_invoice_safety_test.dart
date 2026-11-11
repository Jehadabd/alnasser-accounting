// test/services/disk_space_and_invoice_safety_test.dart
//
// 💽 حماية امتلاء القرص + 🚨 فحص مبلغ السطر (2026-11-11)

import 'dart:io';

import 'package:alnaser/models/invoice_item.dart';
import 'package:alnaser/services/disk_space/disk_space_guard.dart';
import 'package:alnaser/services/invoice_safety/line_math_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

InvoiceItem _item(String name, {double? qi, double? ql, required double price, required double total,
        String? discountType}) =>
    InvoiceItem(
      invoiceId: 0,
      productName: name,
      unit: 'piece',
      quantityIndividual: qi,
      quantityLargeUnit: ql,
      appliedPrice: price,
      itemTotal: total,
      saleType: ql != null ? 'كرتون' : 'قطعة',
      discountType: discountType,
    );

void main() {
  group('💽 مستوى الفراغ', () {
    const mb = 1024 * 1024;
    test('غير معروف / سليم / قليل / حرج', () {
      expect(DiskSpaceGuard.levelFor(null), DiskLevel.unknown);
      expect(DiskSpaceGuard.levelFor(5000 * mb), DiskLevel.ok);
      expect(DiskSpaceGuard.levelFor(800 * mb), DiskLevel.low);
      expect(DiskSpaceGuard.levelFor(150 * mb), DiskLevel.critical);
    });
    test('قاعدة كبيرة ترفع الحدود', () {
      // قاعدة 300MB: الحرج دون 600MB، والقليل دون 1500MB
      expect(DiskSpaceGuard.levelFor(500 * mb, dbSize: 300 * mb), DiskLevel.critical);
      expect(DiskSpaceGuard.levelFor(1200 * mb, dbSize: 300 * mb), DiskLevel.low);
      expect(DiskSpaceGuard.levelFor(2000 * mb, dbSize: 300 * mb), DiskLevel.ok);
    });
  });

  group('💽 تمييز خطأ امتلاء القرص', () {
    test('رسائل SQLite وويندوز', () {
      expect(DiskSpaceGuard.isDiskFullError(Exception('DatabaseException(database or disk is full (code 13))')), isTrue);
      expect(DiskSpaceGuard.isDiskFullError(Exception('SqliteException(13): SQLITE_FULL')), isTrue);
      expect(DiskSpaceGuard.isDiskFullError(const FileSystemException('x', 'f', OSError('full', 112))), isTrue);
      expect(DiskSpaceGuard.isDiskFullError(Exception('There is not enough space on the disk.')), isTrue);
    });
    test('أخطاء أخرى ليست امتلاء', () {
      expect(DiskSpaceGuard.isDiskFullError(Exception('UNIQUE constraint failed (code 2067)')), isFalse);
      expect(DiskSpaceGuard.isDiskFullError(Exception('database is locked (code 5)')), isFalse);
      expect(DiskSpaceGuard.isDiskFullError(Exception('(code 131)')), isFalse);
      expect(DiskSpaceGuard.isDiskFullError(const FileSystemException('x', 'f', OSError('denied', 5))), isFalse);
    });
  });

  group('💽 النسخ الذرّي', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('disk_guard_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('ينسخ كاملاً ولا يترك ملفاً مؤقتاً، ويستبدل القديم', () async {
      final src = File(p.join(dir.path, 'db.sqlite'))..writeAsBytesSync(List.generate(300000, (i) => i % 251));
      final dest = p.join(dir.path, 'backup.db');
      File(dest).writeAsStringSync('قديم');
      await DiskSpaceGuard.copyAtomically(src, dest);
      expect(File(dest).readAsBytesSync(), src.readAsBytesSync());
      expect(File('$dest.part').existsSync(), isFalse);
    });

    test('فشل النسخ لا يترك ملفاً ناقصاً ولا يمسّ القديم', () async {
      final dest = p.join(dir.path, 'backup.db');
      File(dest).writeAsStringSync('نسخة سليمة');
      final missing = File(p.join(dir.path, 'لا_يوجد.db'));
      await expectLater(DiskSpaceGuard.copyAtomically(missing, dest), throwsA(isA<FileSystemException>()));
      expect(File(dest).readAsStringSync(), 'نسخة سليمة');
      expect(File('$dest.part').existsSync(), isFalse);
    });

    test('بقايا .part تُحذف ولا يُمسّ غيرها', () async {
      File(p.join(dir.path, 'a.db.part')).writeAsStringSync('ناقص');
      File(p.join(dir.path, 'b.db')).writeAsStringSync('سليم');
      await DiskSpaceGuard.removeLeftovers(dir);
      expect(File(p.join(dir.path, 'a.db.part')).existsSync(), isFalse);
      expect(File(p.join(dir.path, 'b.db')).existsSync(), isTrue);
    });
  });

  group('🚨 مبلغ السطر = الكمية × السعر', () {
    test('أسطر سليمة تمر (قطعة، كرتون، كسور، تقريب نصف الفلس، هدية)', () {
      expect(
          LineMathCheck.firstMismatch([
            _item('برغي', qi: 3, price: 250, total: 750),
            _item('صمام', ql: 2, price: 24000, total: 48000),
            _item('أنبوب', qi: 2.25, price: 1750.5, total: 3938.63),
            // سعر بعد خصم 1%: 1732.995 يُخزَّن 1733.00 والمبلغ من غير المقرَّب
            _item('أنبوب مخصوم', qi: 100, price: 1732.995, total: 173299.5),
            _item('هدية', qi: 5, price: 0, total: 0, discountType: 'gift'),
            _item('', qi: 0, price: 0, total: 0), // سطر فارغ
          ]),
          isNull);
    });
    test('مبلغ لا يطابق الكمية × السعر يُمنع', () {
      final m = LineMathCheck.firstMismatch([
        _item('برغي', qi: 3, price: 250, total: 750),
        _item('صمام', qi: 4, price: 4000, total: 12000), // الصحيح 16000
      ]);
      expect(m, isNotNull);
      expect(m, contains('صمام'));
    });
    test('فرق سعر وحدة واحدة يُكشف حتى في كمية كبيرة', () {
      expect(LineMathCheck.firstMismatch([_item('برغي', qi: 1000, price: 250, total: 249750)]), isNotNull);
    });
  });
}
