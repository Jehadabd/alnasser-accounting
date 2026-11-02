// test/import/data_import_test.dart
//
// 📥 الاستيراد من Excel: قراءة xlsx/CSV، تحويل الأرقام بصرامة، تخمين الأعمدة،
// والمعاينة (ما يُضاف وما يُتجاوز ولماذا) — بلا كتابة في القاعدة.
// التشغيل: flutter test test/import/data_import_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:alnaser/services/import/data_import.dart';
import 'package:alnaser/services/import/sheet_reader.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// مصنف xlsx صغير مبني يدوياً: نصوص مشتركة، نص مضمّن، أرقام، خلية مفقودة، وصف فارغ.
Uint8List _xlsx() {
  final files = <String, String>{
    'xl/workbook.xml': '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        '<sheet name="الزبائن" sheetId="1" r:id="rId1"/><sheet name="فارغة" sheetId="2" r:id="rId2"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="ws" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="ws" Target="/xl/worksheets/sheet2.xml"/></Relationships>',
    'xl/sharedStrings.xml': '<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<si><t>اسم العميل</t></si><si><t>الهاتف</t></si><si><t>الرصيد</t></si>'
        '<si><r><t>جهاد </t></r><r><t>عبد</t></r></si><si><t>علي</t></si></sst>',
    'xl/worksheets/sheet1.xml': '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
        '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c></row>'
        '<row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2"><v>7701234567</v></c><c r="C2"><v>250000</v></c></row>'
        '<row r="4"><c r="A4" t="s"><v>4</v></c><c r="C4"><v>-1500.5</v></c></row>'
        '<row r="5"><c r="A5" t="inlineStr"><is><t>حسين</t></is></c><c r="C5" t="str"><v>abc</v></c></row>'
        '</sheetData></worksheet>',
    'xl/worksheets/sheet2.xml': '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>',
  };
  final a = Archive();
  files.forEach((name, text) {
    final b = utf8.encode(text);
    a.addFile(ArchiveFile(name, b.length, b));
  });
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

void main() {
  sqfliteFfiInit();

  group('قراءة الملف', () {
    test('xlsx: الأوراق والنصوص المشتركة والمنسّقة والمضمّنة والخلايا المفقودة', () {
      final sheets = SheetReader.read(_xlsx(), 'customers.xlsx');
      expect(sheets.map((s) => s.name), ['الزبائن', 'فارغة']);
      final t = sheets.first;
      expect(t.rows[0], ['اسم العميل', 'الهاتف', 'الرصيد']);
      expect(t.rows[1], ['جهاد عبد', '7701234567', '250000']);
      expect(t.rows[2], isEmpty); // الصف 3 غير موجود في الملف
      expect(t.rows[3], ['علي', '', '-1500.5']);
      expect(t.cell(4, 0), 'حسين');
      expect(sheets[1].rows, isEmpty);
    });

    test('xls القديم مرفوض برسالة واضحة', () {
      final ole = Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0]);
      expect(() => SheetReader.read(ole, 'x.xls'), throwsA(isA<SheetReadException>()));
    });

    test('CSV: فاصل منقوطة، تنصيص، UTF-8 مع BOM', () {
      final text = '﻿الاسم;الرصيد\n"جهاد; عبد";"1,250"\nعلي;"قال ""مرحبا"""\n';
      final t = SheetReader.read(Uint8List.fromList(utf8.encode(text)), 'a.csv').first;
      expect(t.rows[1], ['جهاد; عبد', '1,250']);
      expect(t.rows[2], ['علي', 'قال "مرحبا"']);
    });

    test('مرجع العمود', () {
      expect(SheetReader.colIndex('A1'), 0);
      expect(SheetReader.colIndex('Z9'), 25);
      expect(SheetReader.colIndex('AB12'), 27);
    });
  });

  group('الأرقام: صارمة، لا تخمين', () {
    double? v(String s) {
      final r = ImportNumbers.parse(s);
      expect(r.ok, isTrue, reason: s);
      return r.value;
    }

    test('صيغ مقبولة', () {
      expect(v('250000'), 250000);
      expect(v('1,250,000'), 1250000);
      expect(v('1,250.5'), 1250.5);
      expect(v('٢٥٠٠٠٠'), 250000);
      expect(v('١٬٢٥٠٫٥'), 1250.5);
      expect(v('(5,000)'), -5000);
      expect(v('5000-'), -5000);
      expect(v('25,000 د.ع'), 25000);
      expect(v(r'$100'), 100);
      expect(v('2.5E5'), 250000);
      expect(v(''), isNull);
    });

    test('صيغ مرفوضة', () {
      for (final s in ['abc', '1.234,5', '12,34', '1,2345', '5 آلاف', '--5']) {
        expect(ImportNumbers.parse(s).ok, isFalse, reason: s);
      }
    });

    test('الهاتف من خلية رقمية', () {
      expect(DataImport.phoneOf('7701234567'), '9647701234567');
      expect(DataImport.phoneOf('07701234567'), '9647701234567');
      expect(DataImport.phoneOf('7.701234567E9'), '9647701234567');
      expect(DataImport.phoneOf('0770 123 4567'), '9647701234567');
      expect(DataImport.phoneOf(''), isNull);
    });
  });

  test('تخمين الأعمدة من العناوين', () {
    final m = ColumnGuess.guess(['م', 'اسم الزبون', 'رقم الموبايل', 'الدين المتبقي', 'العنوان'], ImportKind.customers);
    expect(m['name'], 1);
    expect(m['phone'], 2);
    expect(m['balance'], 3);
    expect(m['address'], 4);
    final p = ColumnGuess.guess(['Item', 'Barcode', 'Price', 'Cost', 'Qty'], ImportKind.products);
    expect([p['name'], p['barcode'], p['price'], p['cost'], p['qty']], [0, 1, 2, 3, 4]);
  });

  group('المعاينة (قراءة فقط)', () {
    late Database db;
    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false));
      await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, phone TEXT, is_deleted INTEGER)');
      await db.execute('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, name_norm TEXT, barcode TEXT)');
      await db.execute('CREATE TABLE product_barcodes (id INTEGER PRIMARY KEY, product_id INTEGER, barcode TEXT)');
      await db.execute('CREATE TABLE suppliers (id INTEGER PRIMARY KEY, name TEXT)');
      await db.insert('customers', {'name': 'علي', 'is_deleted': 0});
      await db.insert('customers', {'name': 'محمود', 'is_deleted': 1});
      await db.insert('products', {'name': 'سلك 2.5', 'name_norm': 'سلك 2.5', 'barcode': '111'});
      await db.insert('suppliers', {'name': 'شركة النور'});
    });
    tearDown(() => db.close());

    test('العملاء: موجود يُتجاوز، مكرر في الملف يُتجاوز، رقم غير واضح خطأ، والمجموع دقيق', () async {
      final t = SheetTable('s', [
        ['الاسم', 'الهاتف', 'الرصيد'],
        ['جهاد عبد', '0770 123 4567', '250,000'],
        ['علي', '', '1000'], // موجود
        ['جهادعبد', '', '5'], // نفس جهاد عبد بلا مسافة
        ['حسين', '', 'abc'], // خطأ
        ['محمود', '', '10'], // محذوف سابقاً
        ['', '', '99'], // بلا اسم
        ['زينب', '', '(1,500.5)'], // له علينا
        ['كاظم', '', ''],
      ]);
      final plan = await DataImport.plan(db, t, ImportKind.customers, {'name': 0, 'phone': 1, 'balance': 2},
          ImportOptions(openingDate: DateTime(2026, 1, 1)));
      expect(plan.rows.map((r) => r.name), ['جهاد عبد', 'زينب', 'كاظم']);
      expect(plan.rows.first.phone, '9647701234567');
      expect(plan.positiveTotal, 250000);
      expect(plan.negativeTotal, -1500.5);
      expect(plan.balanceByCurrency['IQD'], 248499.5);
      expect(plan.errors.map((e) => e.line), [5]);
      expect(plan.skipped.length, 5);
      expect(plan.skipped.firstWhere((s) => s.line == 4).reason, contains('مكرر في الملف'));
      expect(plan.skipped.firstWhere((s) => s.line == 3).reason, contains('موجود'));
    });

    test('عكس الإشارة: الموجب = له علينا', () async {
      final t = SheetTable('s', [
        ['name', 'balance'],
        ['سعد', '700'],
      ]);
      final plan = await DataImport.plan(db, t, ImportKind.customers, {'name': 0, 'balance': 1},
          ImportOptions(openingDate: DateTime(2026, 1, 1), positiveIsNormal: false));
      expect(plan.rows.single.balance, -700);
    });

    test('المواد: سعر مطلوب، كمية سالبة مرفوضة، باركود مستعمل يُتجاوز', () async {
      final t = SheetTable('s', [
        ['المادة', 'السعر', 'الكلفة', 'الكمية', 'الباركود'],
        ['مفتاح', '1,250', '900', '30', '222'],
        ['سلك 2.5', '500', '', '', ''], // موجودة
        ['بريزة', '', '', '5', ''], // بلا سعر
        ['لمبة', '1000', '', '-3', ''], // كمية سالبة
        ['شريط', '250', '', '', '111'], // باركود مستعمل
        ['كيبل', '3000', '2500', '12.5', '222.0'], // باركود مكرر في الملف
      ]);
      final plan = await DataImport.plan(db, t, ImportKind.products,
          {'name': 0, 'price': 1, 'cost': 2, 'qty': 3, 'barcode': 4}, ImportOptions(openingDate: DateTime(2026, 1, 1)));
      expect(plan.rows.map((r) => r.name), ['مفتاح']);
      expect(plan.rows.single.price, 1250);
      expect(plan.rows.single.qty, 30);
      expect(plan.skipped.map((s) => s.line), [3, 4, 5, 6, 7]);
    });

    test('الموردون: العملة من العمود، وغير المفهومة خطأ', () async {
      final t = SheetTable('s', [
        ['المورد', 'الرصيد', 'العملة'],
        ['شركة الفرات', '1500', 'دولار'],
        ['شركة النور', '100', ''], // موجود
        ['مخزن بغداد', '2,000,000', ''],
        ['شركة س', '5', 'يورو'],
      ]);
      final plan = await DataImport.plan(db, t, ImportKind.suppliers,
          {'name': 0, 'balance': 1, 'currency': 2}, ImportOptions(openingDate: DateTime(2026, 1, 1)));
      expect(plan.rows.map((r) => '${r.name}:${r.currency}:${r.balance}'),
          ['شركة الفرات:USD:1500.0', 'مخزن بغداد:IQD:2000000.0']);
      expect(plan.errors.single.line, 5);
    });

    test('حقل مطلوب غير مربوط ⇒ لا معاينة', () async {
      final t = SheetTable('s', [
        ['a'],
        ['b'],
      ]);
      expect(() => DataImport.plan(db, t, ImportKind.products, {'name': 0}, ImportOptions(openingDate: DateTime(2026))),
          throwsArgumentError);
    });
  });
}
