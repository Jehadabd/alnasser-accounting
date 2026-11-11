// test/import/data_import_test.dart
//
// 📥 الاستيراد من Excel: قراءة xlsx/CSV، تحويل الأرقام بصرامة، تخمين الأعمدة،
// والمعاينة (ما يُضاف وما يُتجاوز ولماذا) — بلا كتابة في القاعدة.
// التشغيل: flutter test test/import/data_import_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alnaser/services/database/business/tx_author.dart';
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

    test('xls ناقص أو تالف: رسالة واضحة لا انهيار', () {
      final ole = Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0]);
      expect(() => SheetReader.read(ole, 'x.xls'), throwsA(isA<SheetReadException>()));
      final cut = File('test/import/fixtures/excel97_small.xls').readAsBytesSync().sublist(0, 1536);
      expect(() => SheetReader.read(cut, 'x.xls'), throwsA(isA<SheetReadException>()));
    });

    group('xls القديم', () {
      List<SheetTable> load(String f) => SheetReader.read(File('test/import/fixtures/$f').readAsBytesSync(), f);

      test('Excel 97: ملف صغير (تيار القطاعات الصغيرة)', () {
        final s = load('excel97_small.xls');
        expect(s.single.name, 'ورقة');
        expect(s.single.rows, [
          ['الاسم', 'الرصيد'],
          ['علي', '1500'],
          ['زينب', '-20.5'],
        ]);
      });

      test('Excel 97: نص طويل ينقسم بين سجلين، وأرقام وهواتف', () {
        final t = load('excel97_long_text.xls').single;
        expect(t.rows.length, 21);
        expect(t.cell(0, 4), 'ع' * 5000);
        expect(t.rows[1], ['زبون 1 أبو محمد', '07700000001', '250', '', 'after']);
        expect(t.rows[20], ['زبون 20 أبو محمد', '07700000020', '-5']);
      });

      test('Excel 97: انقسام نص مضغوط←عريض، تنسيق ونطق، معادلة نصية، ورسم مضمّن يُتجاهل', () {
        final t = load('excel97_sst_split.xls').single;
        expect(t.name, 'الموردون');
        expect(t.rows[0], ['abcde سلام', 'علي', 'ok', 'Z']);
        expect(t.rows[1], ['نص معادلة']);
        expect(t.rows[2], ['fillé']);
        expect(t.rows.length, 400);
      });

      test('Excel 95 (BIFF5) بترميز عربي 1256، RK وMULRK وNUMBER', () {
        final t = load('excel95_cp1256.xls').single;
        expect(t.name, 'العملاء');
        expect(t.rows[0], ['الاسم', 'الرصيد']);
        expect(t.rows[1], ['عميل رقم 1 ـ أبو علي', '250']);
        expect(t.rows[300], ['زينب', '-1234.75']);
        expect(t.rows[301], ['', '123.45', '7']);
      });
    });

    test('ملف ‎.xls هو في الحقيقة جدول HTML', () {
      const html = '<html><head><meta charset="utf-8"></head><body><table>'
          '<tr><th>الاسم</th><th colspan="2">الرصيد</th><th>ملاحظة</th></tr>'
          '<tr><td>جهاد&nbsp;عبد</td><td>1,250</td><td></td><td>أ &amp; ب</td></tr>'
          '<tr><td><b>علي</b><br>الثاني</td><td>-5</td></tr>'
          '</table></body></html>';
      final t = SheetReader.read(Uint8List.fromList(utf8.encode(html)), 'a.xls').single;
      expect(t.rows, [
        ['الاسم', 'الرصيد', '', 'ملاحظة'],
        ['جهاد عبد', '1,250', '', 'أ & ب'],
        ['علي الثاني', '-5'],
      ]);
    });

    test('ملف ‎.xls هو في الحقيقة XML Spreadsheet 2003', () {
      const xml = '<?xml version="1.0"?><Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
          'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"><Worksheet ss:Name="الزبائن"><Table>'
          '<Row><Cell><Data ss:Type="String">الاسم</Data></Cell><Cell><Data ss:Type="String">الرصيد</Data></Cell></Row>'
          '<Row ss:Index="3"><Cell><Data ss:Type="String">علي</Data></Cell><Cell ss:Index="3"><Data ss:Type="Number">1500</Data></Cell></Row>'
          '</Table></Worksheet></Workbook>';
      final t = SheetReader.read(Uint8List.fromList(utf8.encode(xml)), 'b.xls').single;
      expect(t.name, 'الزبائن');
      expect(t.rows, [
        ['الاسم', 'الرصيد'],
        <String>[],
        ['علي', '', '1500'],
      ]);
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
    // عناوين ملف .xls حقيقي من برنامج آخر (فيه خطأ إملائي «اليون»)
    final r = ColumnGuess.guess(['ت', 'الاسم', 'مبلغ اليون', 'ت البرنامج', 'العنوان'], ImportKind.customers);
    expect([r['name'], r['balance'], r['address']], [1, 2, 4]);
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

    test('العملاء: الموجود يُضاف إليه، مكرر في الملف يُتجاوز، رقم غير واضح خطأ، والمجموع دقيق', () async {
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
      expect(plan.rows.map((r) => r.name), ['جهاد عبد', 'علي', 'زينب', 'كاظم']);
      expect(plan.rows.first.phone, '9647701234567');
      expect(plan.existingRows.single.name, 'علي');
      expect(plan.existingRows.single.existingId, 1);
      expect(plan.existingTotal, 1000);
      expect(plan.newRows.length, 3);
      expect(plan.positiveTotal, 251000);
      // 💵 الرصيد بالدينار صحيح: (1,500.5) له علينا ⇒ −1,500 (النصف لصالح المحل)
      expect(plan.negativeTotal, -1500);
      expect(plan.balanceByCurrency['IQD'], 249500);
      expect(plan.errors.map((e) => e.line), [5]);
      expect(plan.skipped.length, 4);
      expect(plan.skipped.firstWhere((s) => s.line == 4).reason, contains('مكرر في الملف'));
      expect(plan.skipped.firstWhere((s) => s.line == 6).reason, contains('محذوف'));

      // الخيار القديم: الموجود يُتجاوز ولا يُمس
      final skip = await DataImport.plan(db, t, ImportKind.customers, {'name': 0, 'phone': 1, 'balance': 2},
          ImportOptions(openingDate: DateTime(2026, 1, 1), addToExisting: false));
      expect(skip.rows.map((r) => r.name), ['جهاد عبد', 'زينب', 'كاظم']);
      expect(skip.skipped.firstWhere((s) => s.line == 3).reason, contains('موجود'));
    });

    test('موجود بلا مبلغ في الملف: لا شيء يُضاف', () async {
      final t = SheetTable('s', [
        ['الاسم', 'الرصيد'],
        ['علي', ''],
        ['علي ', '0'], // مكرر
      ]);
      final plan = await DataImport.plan(
          db, t, ImportKind.customers, {'name': 0, 'balance': 1}, ImportOptions(openingDate: DateTime(2026, 1, 1)));
      expect(plan.rows, isEmpty);
      expect(plan.skipped.first.reason, contains('لا مبلغ'));
    });

    test('الملف نفسه مرة ثانية: صفوفه المستوردة سابقاً تُتجاوز', () async {
      await db.execute('CREATE TABLE data_import_rows (row_key TEXT PRIMARY KEY, kind TEXT, entity_id INTEGER, '
          'amount REAL, currency TEXT, file_name TEXT, at TEXT)');
      await db.insert('data_import_rows', {'row_key': 'f1|customers|زينب', 'kind': 'customers', 'at': '2026-11-03T10:00'});
      final t = SheetTable('s', [
        ['الاسم', 'الرصيد'],
        ['زينب', '500'],
        ['كاظم', '700'],
      ]);
      final plan = await DataImport.plan(db, t, ImportKind.customers, {'name': 0, 'balance': 1},
          ImportOptions(openingDate: DateTime(2026, 1, 1), sourceId: 'f1'));
      expect(plan.rows.map((r) => r.name), ['كاظم']);
      expect(plan.skipped.single.reason, contains('سابقاً (2026-11-03)'));
      // ملف آخر (بصمة أخرى): يُستورد
      final other = await DataImport.plan(db, t, ImportKind.customers, {'name': 0, 'balance': 1},
          ImportOptions(openingDate: DateTime(2026, 1, 1), sourceId: 'f2'));
      expect(other.rows.length, 2);
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
          ['شركة الفرات:USD:1500.0', 'شركة النور:IQD:100.0', 'مخزن بغداد:IQD:2000000.0']);
      expect(plan.existingRows.single.name, 'شركة النور');
      expect(plan.errors.single.line, 5);
    });

    test('المراجعة: الاستبعاد والتعديل يغيّران المجموع، والأصل محفوظ', () async {
      final t = SheetTable('s', [
        ['الاسم', 'الرصيد'],
        ['أ', '100'],
        ['ب', '200'],
        ['ج', '300'],
      ]);
      final plan = await DataImport.plan(db, t, ImportKind.customers, {'name': 0, 'balance': 1},
          ImportOptions(openingDate: DateTime(2026, 1, 1)));
      expect(plan.positiveTotal, 600);
      expect(plan.rows.any((r) => r.edited), isFalse);
      plan.allRows[1].include = false; // ب مستبعد
      plan.allRows[2].balance = 350; // ج عُدّل
      expect(plan.rows.map((r) => r.name), ['أ', 'ج']);
      expect(plan.positiveTotal, 450);
      expect(plan.allRows[2].edited, isTrue);
      expect(plan.allRows[2].originalBalance, 300);
      expect(plan.allRows.length, 3);
    });

    test('قاعدة جديدة: الأسماء الموجودة في القاعدة الحالية لا تُتجاوز', () async {
      final t = SheetTable('s', [
        ['الاسم', 'الرصيد'],
        ['علي', '1000'],
        ['علي', '5'], // مكرر في الملف ما زال يُتجاوز
      ]);
      final plan = await DataImport.plan(db, t, ImportKind.customers, {'name': 0, 'balance': 1},
          ImportOptions(openingDate: DateTime(2026, 1, 1)),
          freshTarget: true);
      expect(plan.rows.map((r) => r.name), ['علي']);
      expect(plan.skipped.single.line, 3);
    });

    test('تعديل غير صالح يُرفض قبل أي كتابة', () async {
      final t = SheetTable('s', [
        ['المادة', 'السعر', 'الكمية'],
        ['مفتاح', '1000', '5'],
      ]);
      final plan = await DataImport.plan(db, t, ImportKind.products, {'name': 0, 'price': 1, 'qty': 2},
          ImportOptions(openingDate: DateTime(2026, 1, 1)));
      plan.allRows.single.price = 0;
      expect(() => DataImport.execute(plan, ImportOptions(openingDate: DateTime(2026)), fileName: 'f', sheet: 's'),
          throwsArgumentError);
      plan.allRows.single.price = 10;
      plan.allRows.single.qty = double.nan;
      expect(() => DataImport.execute(plan, ImportOptions(openingDate: DateTime(2026)), fileName: 'f', sheet: 's'),
          throwsArgumentError);
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

  group('التنفيذ: إضافة مبلغ إلى عميل موجود', () {
    late Database db;
    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false));
      await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, phone TEXT, '
          'current_total_debt REAL DEFAULT 0, is_deleted INTEGER DEFAULT 0, last_modified_at TEXT)');
      await db.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, customer_id INTEGER, '
          'transaction_uuid TEXT, sync_uuid TEXT, transaction_date TEXT, amount_changed REAL, '
          'balance_before_transaction REAL, new_balance_after_transaction REAL, transaction_note TEXT, '
          'transaction_type TEXT, description TEXT, created_at TEXT, invoice_id INTEGER, is_deleted INTEGER, '
          'is_created_by_me INTEGER, is_uploaded INTEGER, checksum TEXT, created_by_username TEXT)');
      // علي: دين 1000 بتاريخ 2026-03-01، ثم تسديد 400 بتاريخ 2026-05-01 ⇒ 600
      await db.insert('customers', {'id': 1, 'name': 'علي', 'current_total_debt': 600});
      await db.insert('transactions', {'customer_id': 1, 'transaction_date': '2026-03-01T00:00:00.000',
          'amount_changed': 1000, 'new_balance_after_transaction': 1000, 'transaction_type': 'manual_debt', 'is_deleted': 0});
      await db.insert('transactions', {'customer_id': 1, 'transaction_date': '2026-05-01T00:00:00.000',
          'amount_changed': -400, 'new_balance_after_transaction': 600, 'transaction_type': 'manual_payment', 'is_deleted': 0});
    });
    tearDown(() => db.close());

    test('معاملة بالمبلغ والملف والصف ومن قام بها، وسلسلة الأرصدة تُعاد بالتاريخ، ولا تكرار', () async {
      TxAuthor.currentName = () => 'أحمد';
      addTearDown(() => TxAuthor.currentName = null);
      final t = SheetTable('s', [
        ['الاسم', 'الرصيد'],
        ['علي', '250'],
      ]);
      final o = ImportOptions(openingDate: DateTime(2026, 1, 1), sourceId: 'abc');
      final plan = await DataImport.plan(db, t, ImportKind.customers, {'name': 0, 'balance': 1}, o);
      expect(plan.existingRows.single.existingBalance, 600);
      // بلا اختيار لا يبدأ الاستيراد (قبل أي كتابة)
      expect(plan.undecided.length, 1);
      expect(() => DataImport.execute(plan, o, fileName: 'f', sheet: 's'), throwsArgumentError);
      plan.existingRows.single.action = ExistingAction.merge;
      expect(plan.existingRows.single.balanceAfter, 850);

      final res = await DataImport.debugExecuteCustomers(db, plan, o, 'ديون.xls');
      expect(res.added, 0);
      expect(res.addedToExisting, 1);

      final card = await db.query('customers', where: 'id = 1');
      expect(card.single['current_total_debt'], 850);
      final txs = await db.query('transactions', where: 'customer_id = 1', orderBy: 'transaction_date, id');
      expect(txs.map((x) => x['amount_changed']), [250, 1000, -400]); // المستورد بتاريخ أقدم أولاً
      expect(txs.map((x) => x['new_balance_after_transaction']), [250, 1250, 850]);
      expect(txs.map((x) => x['balance_before_transaction']), [0, 250, 1250]);
      final imp = txs.first;
      expect(imp['transaction_type'], 'opening_balance');
      expect(imp['description'], 'رصيد مستورد من Excel');
      expect(imp['transaction_note'], 'استيراد من Excel: «ديون.xls» — الصف 2 — بواسطة أحمد — دمج: أُضيف 250 إلى 600');
      expect(imp['created_by_username'], 'أحمد');
      expect('${imp['transaction_uuid']}', startsWith('tximp_'));

      // الملف نفسه مرة ثانية: المراجعة تتجاوزه ولا يتغير شيء
      final again = await DataImport.plan(db, t, ImportKind.customers, {'name': 0, 'balance': 1}, o);
      expect(again.rows, isEmpty);
      expect(again.skipped.single.reason, contains('سابقاً'));
      final res2 = await DataImport.debugExecuteCustomers(db, plan, o, 'ديون.xls'); // خطة قديمة أُعيد تنفيذها
      expect(res2.addedToExisting, 0);
      expect(res2.skippedAtSave.single.reason, contains('سابقاً'));
      expect((await db.query('customers', where: 'id = 1')).single['current_total_debt'], 850);
      expect((await db.query('transactions')).length, 3);
    });
    test('مبلغ الملف هو الصحيح: تسوية بالفرق فيصير الدين مبلغ الملف بالضبط', () async {
      final t = SheetTable('s', [
        ['الاسم', 'الرصيد'],
        ['علي', '1,000'],
      ]);
      final o = ImportOptions(openingDate: DateTime(2026, 6, 1), sourceId: 'x2');
      final plan = await DataImport.plan(db, t, ImportKind.customers, {'name': 0, 'balance': 1}, o);
      plan.existingRows.single.action = ExistingAction.useFile;
      expect(plan.existingRows.single.balanceAfter, 1000);
      expect(plan.existingDelta, 400);
      final res = await DataImport.debugExecuteCustomers(db, plan, o, 'f.xls');
      expect(res.addedToExisting, 1);
      expect((await db.query('customers', where: 'id = 1')).single['current_total_debt'], 1000);
      final imp = (await db.query('transactions', where: "transaction_uuid LIKE 'tximp_%'")).single;
      expect(imp['amount_changed'], 400); // الفرق فقط
      expect(imp['description'], 'تسوية رصيد من Excel');
      expect('${imp['transaction_note']}', contains('الدين صار 1000 بدل 600'));
      expect(imp['new_balance_after_transaction'], 1000); // آخر معاملة بالتاريخ
    });

    test('الدين الحالي هو الصحيح، أو لا فرق: لا تُكتب أي معاملة', () async {
      final t = SheetTable('s', [
        ['الاسم', 'الرصيد'],
        ['علي', '600'],
      ]);
      final o = ImportOptions(openingDate: DateTime(2026, 6, 1), sourceId: 'x3');
      for (final a in [ExistingAction.keep, ExistingAction.useFile]) {
        final plan = await DataImport.plan(db, t, ImportKind.customers, {'name': 0, 'balance': 1}, o);
        plan.existingRows.single.action = a;
        final res = await DataImport.debugExecuteCustomers(db, plan, o, 'f.xls');
        expect(res.addedToExisting, 0);
        expect(res.kept.length, 1);
      }
      expect((await db.query('transactions')).length, 2);
      expect((await db.query('customers', where: 'id = 1')).single['current_total_debt'], 600);
    });
  });
}
