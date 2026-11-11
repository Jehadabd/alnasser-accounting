// test/services/iqd_whole_dinar_test.dart
//
// 💵 الدينار بلا كسور: التقريب (lib/utils/iqd.dart)، أسطر الفاتورة، رأس الفاتورة،
// فاتورة الشراء، ومشغّلات القاعدة التي ترفض الكسر (IqdGuard).
// التشغيل: flutter test test/services/iqd_whole_dinar_test.dart

import 'package:alnaser/erp/erp_schema.dart';
import 'package:alnaser/models/invoice_input_data.dart';
import 'package:alnaser/models/invoice_item.dart';
import 'package:alnaser/models/purchase_invoice.dart';
import 'package:alnaser/models/purchase_invoice_item.dart';
import 'package:alnaser/services/database/core/database_migrations.dart';
import 'package:alnaser/services/database/core/iqd_guard.dart';
import 'package:alnaser/services/database/dao/transaction_dao.dart';
import 'package:alnaser/services/invoice_safety/iqd_normalize.dart';
import 'package:alnaser/utils/iqd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

InvoiceItem _item(double qty, double price, {double? total}) => InvoiceItem(
      invoiceId: 0,
      productName: 'مادة',
      unit: 'قطعة',
      unitPrice: price,
      quantityIndividual: qty,
      appliedPrice: price,
      itemTotal: total ?? qty * price,
      saleType: 'قطعة',
    );

void main() {
  group('💵 التقريب لأقرب دينار', () {
    test('أمثلة صاحب المحل', () {
      expect(Iqd.up(20.83), 21);
      expect(Iqd.up(52.5), 53);
      expect(Iqd.up(52.4), 52);
      expect(Iqd.up(20.49), 20);
    });
    test('النصف بالضبط: up للأعلى، down للأسفل؛ غير النصف لأقرب دينار في الاتجاهين', () {
      expect(Iqd.down(52.5), 52);
      expect(Iqd.down(52.51), 53);
      expect(Iqd.up(-52.5), -52); // تسديد 52.5 ⇒ 52 (يبقى الدين أعلى)
      expect(Iqd.down(-52.5), -53);
      expect(Iqd.up(-20.83), -21);
      expect(Iqd.up(0.4), 0);
      expect(Iqd.up(-0.4), 0);
      expect(Iqd.up(-0.4).isNegative, isFalse); // لا «-0.0»
    });
    test('ضجيج الكسور العشرية لا يغيّر النتيجة', () {
      expect(Iqd.up(52.49999999999), 53); // هو 52.5 حسابياً
      expect(Iqd.up(52.495), 52); // أقل من النصف فعلاً
      expect(Iqd.up(0.1 + 0.2 + 999.7), 1000);
      expect(Iqd.up(987654321.5), 987654322);
      expect(Iqd.up(999999999999.5), 1000000000000); // ترليون: لا فيضان
      expect(Iqd.up(-999999999999.5), -999999999999);
    });
    test('centsUp: بالفلس إلى مضاعف 100', () {
      expect(Iqd.centsUp(5250), 5300);
      expect(Iqd.centsUp(5249), 5200);
      expect(Iqd.centsUp(-250), -200);
      expect(Iqd.centsUp(100000), 100000);
    });
    test('isWhole', () {
      expect(Iqd.isWhole(1000), isTrue);
      expect(Iqd.isWhole(1000.00000001), isTrue);
      expect(Iqd.isWhole(1000.2), isFalse);
      expect(Iqd.isWhole(null), isTrue);
    });
  });

  group('💵 تصفية كسر قديم في رصيد العميل', () {
    test('عميل رصيده صحيح: الكسر يُقرَّب', () {
      expect(Iqd.ledgerAmount(-1250.2, 5000), -1250);
      expect(Iqd.ledgerAmount(52.5, 0), 53);
    });
    test('عميل رصيده 1250.2: تسديد يجعل الرصيد صحيحاً يُقبل بكسره', () {
      expect(Iqd.ledgerAmount(-1250.2, 1250.2), -1250.2);
      expect(Iqd.ledgerAmount(-0.2, 1250.2), -0.2);
      expect(Iqd.ledgerAmount(-250.2, 1250.2), -250.2);
    });
    test('عميل رصيده 1250.2: كسر لا يصفّيه يُقرَّب، والصحيح يبقى صحيحاً', () {
      expect(Iqd.ledgerAmount(-1250.7, 1250.2), -1251);
      expect(Iqd.ledgerAmount(-1000, 1250.2), -1000);
    });
  });

  group('🛡️ قاعدة الرصيد السالب في تعديل المعاملة اليدوية وتحويلها', () {
    void check(double before, double after) => TransactionDao.assertNotNegative(before: before, after: after, what: 'التعديل');
    test('تعديل يُنقص الرصيد إلى ما دون الصفر يُرفض', () {
      expect(() => check(5000, -1000), throwsA(predicate((e) => '$e'.contains('رصيد العميل سيصبح'))));
      expect(() => check(0, -250), throwsException);
    });
    test('ما لا يُنقص الرصيد تحت الصفر يمر — حتى لعميل رصيده سالب أصلاً', () {
      check(5000, 0);
      check(5000, 1000);
      check(-3000, -2000); // سالب أصلاً والتعديل يرفعه
      check(-3000, -3000); // لا تغيير
    });
  });

  group('💵 أسطر فاتورة البيع', () {
    test('السطر لأقرب دينار والسعر صحيح إن طابق', () {
      final a = _item(1, 1250.5);
      expect(a.itemTotal, 1251);
      expect(a.appliedPrice, 1251);
      final b = _item(2, 1000);
      expect(b.itemTotal, 2000);
      expect(b.appliedPrice, 1000);
    });
    test('مجموع مكتوب لثلاث قطع: السطر كما كُتب والسعر يبقى مشتقاً', () {
      final c = _item(3, 3333.33, total: 10000);
      expect(c.itemTotal, 10000);
      expect(c.appliedPrice, closeTo(3333.33, 0.001));
    });
    test('كمية كسرية × سعر صحيح ⇒ سطر مقرَّب', () {
      final d = _item(2.25, 1333);
      expect(d.itemTotal, 2999); // 2999.25
      expect(d.appliedPrice, 1333);
      final e = _item(1.5, 333);
      expect(e.itemTotal, 500); // 499.5 ⇒ 500
    });
    test('التقريب ثابت: بناء السطر مرة ثانية لا يغيّره', () {
      final c = _item(3, 3333.33, total: 10000);
      final again = InvoiceItem.fromMap(c.toMap());
      expect(again.itemTotalCents, c.itemTotalCents);
      expect(again.appliedPriceCents, c.appliedPriceCents);
      final copy = c.copyWith();
      expect(copy.itemTotalCents, c.itemTotalCents);
      expect(copy.appliedPriceCents, c.appliedPriceCents);
    });
    test('المُعدِّل itemTotal يقرّب', () {
      final f = _item(1, 1000)..itemTotal = 999.6;
      expect(f.itemTotal, 1000);
    });
  });

  group('💵 رأس فاتورة البيع', () {
    InvoiceInputData data({double disc = 0, double fee = 0, double paid = 0, String pt = 'دين', List<InvoiceItem>? items}) =>
        InvoiceInputData(
          customerName: 'عميل',
          customerPhone: '',
          customerAddress: '',
          paidAmount: paid,
          loadingFee: fee,
          discount: disc,
          paymentType: pt,
          selectedDate: DateTime(2026, 11, 11),
          invoiceItems: items ?? [_item(3, 333.33)], // 999.99 ⇒ 1000
        );

    test('الخصم للأسفل عند النصف، الأجور للأعلى، والمسدد', () {
      final n = IqdNormalize.invoiceInput(data(disc: 0.5, fee: 0.5, paid: 100.5));
      expect(n.discount, 0);
      expect(n.loadingFee, 1);
      expect(n.paidAmount, 100);
    });
    test('نقد: المسدد = الإجمالي المعروض ⇒ = الإجمالي الجديد', () {
      // الأسطر 1000، الخصم 0.99 ⇒ 1، الإجمالي 999 (المعروض 999.01)
      final n = IqdNormalize.invoiceInput(data(disc: 0.99, paid: 999.01, pt: 'نقد'));
      expect(n.discount, 1);
      expect(n.paidAmount, 999);
    });
    test('مسدد لا يتجاوز الإجمالي ما دام المكتوب لم يتجاوزه', () {
      // أجور 0.4 ⇒ 0، خصم 0.6 ⇒ 1: الإجمالي 999 والمعروض 999.8
      final n = IqdNormalize.invoiceInput(data(fee: 0.4, disc: 0.6, paid: 999.7));
      expect(n.paidAmount, 999);
    });
    test('مبالغ صحيحة ⇒ الكائن نفسه (لا نسخ بلا داعٍ)', () {
      final d = data(disc: 100, fee: 250, paid: 500, items: [_item(2, 1000)]);
      expect(identical(IqdNormalize.invoiceInput(d), d), isTrue);
    });
    test('القيم السالبة تبقى سالبة فيرفضها الفحص', () {
      final n = IqdNormalize.invoiceInput(data(disc: -250.4, paid: -500));
      expect(n.discount, -250);
      expect(n.paidAmount, -500);
    });
  });

  group('💵 فاتورة الشراء', () {
    PurchaseInvoice inv(String cur, double total, double paid) =>
        PurchaseInvoice(invoiceNumber: '1', supplierId: 1, currency: cur, totalAmount: total, paidAmount: paid, date: DateTime(2026));
    PurchaseInvoiceItem it(double total) =>
        PurchaseInvoiceItem(productId: 1, unitName: 'قطعة', quantity: 3, unitPrice: total / 3, totalPrice: total);

    test('بالدينار: الأسطر للأسفل عند النصف والإجمالي مجموعها', () {
      final (i, items) = IqdNormalize.purchase(inv('IQD', 2001.0, 2001.0), [it(1000.5), it(1000.5)]);
      expect(items.map((x) => x.totalPrice), [1000, 1000]);
      expect(i.totalAmount, 2000);
      expect(i.paidAmount, 2000);
    });
    test('بالدولار: كما هي', () {
      final items = [it(10.25)];
      final (i, out) = IqdNormalize.purchase(inv('USD', 10.25, 3.5), items);
      expect(identical(out, items), isTrue);
      expect(i.totalAmount, 10.25);
      expect(i.paidAmount, 3.5);
    });
  });

  group('💵 القاعدة ترفض الكسر (IqdGuard)', () {
    late Database db;
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
      SharedPreferences.setMockInitialValues({});
    });
    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false));
      await DatabaseMigrations.createTables(db);
      await DatabaseMigrations.ensureSchema(db);
      await ErpSchema.ensure(db);
      await IqdGuard.ensure(db);
    });
    tearDown(() => db.close());

    Future<bool> ok(Future<Object?> Function() f) async {
      try {
        await f();
        return true;
      } catch (e) {
        expect(IqdGuard.isFractionError(e), isTrue, reason: 'خطأ غير متوقع: $e');
        return false;
      }
    }

    Future<int> customer() => db.insert('customers', {'name': 'ع${DateTime.now().microsecondsSinceEpoch}', 'current_total_debt': 0});
    Future<Object?> tx(int c, double amount, {int uploaded = 0, int? invoiceId}) => db.insert('transactions', {
          'customer_id': c,
          'amount_changed': amount,
          'transaction_date': '2026-11-11',
          'is_uploaded': uploaded,
          'invoice_id': invoiceId,
        });

    test('كل المشغّلات أُنشئت على المخطط الحقيقي', () async {
      final names = {
        for (final r in await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'iqd1_%'"))
          r['name'] as String,
      };
      expect(names.length, IqdGuard.sqlForReview().length, reason: 'الموجود: $names');
    });

    test('معاملة يكتبها هذا الجهاز: الكسر يُرفض والصحيح يُقبل', () async {
      final c = await customer();
      expect(await ok(() => tx(c, 1000)), isTrue);
      expect(await ok(() => tx(c, 52.5)), isFalse);
      expect(await ok(() => tx(c, -52)), isTrue);
    });

    test('الوارد بالمزامنة يُكتب كما جاء، ثم يُقبل تسديد يصفّي كسره فقط', () async {
      final c = await customer();
      expect(await ok(() => tx(c, 1250.2, uploaded: 1)), isTrue);
      expect(await ok(() => tx(c, -1250.7)), isFalse);
      expect(await ok(() => tx(c, -1250.2)), isTrue);
      final sum = (await db.rawQuery('SELECT SUM(amount_changed) AS s FROM transactions WHERE customer_id = ?', [c]))
          .first['s'] as num;
      expect(sum.abs() < 0.0001, isTrue);
    });

    test('معاملة الفاتورة مشتقة من رأسها: لا تُفحص مرتين', () async {
      final c = await customer();
      expect(await ok(() => tx(c, 10.5, invoiceId: 77)), isTrue);
    });

    test('رأس الفاتورة: المحلية تُرفض بكسر، والواردة تُقبل، وتحديث حقل آخر لا يُمنع', () async {
      Map<String, Object?> inv(double total, int synced) => {
            'invoice_date': '2026-11-11',
            'total_amount': total,
            'created_at': '2026-11-11',
            'is_synced': synced,
          };
      expect(await ok(() => db.insert('invoices', inv(1000.5, 0))), isFalse);
      expect(await ok(() => db.insert('invoices', inv(1000, 0))), isTrue);
      final legacy = await db.insert('invoices', inv(1000.5, 1));
      expect(await ok(() => db.update('invoices', {'notes': 'ملاحظة', 'is_synced': 0}, where: 'id = ?', whereArgs: [legacy])),
          isTrue);
      expect(await ok(() => db.update('invoices', {'discount': 0.5}, where: 'id = ?', whereArgs: [legacy])), isFalse);
    });

    test('المورد: الدينار بلا كسر، والدولار بكسوره', () async {
      Map<String, Object?> p(String cur, double amount) =>
          {'payment_number': '1', 'supplier_id': 1, 'amount': amount, 'currency': cur, 'payment_method': 'cash', 'date': '2026-11-11'};
      expect(await ok(() => db.insert('supplier_payments', p('USD', 3.25))), isTrue);
      expect(await ok(() => db.insert('supplier_payments', p('IQD', 3.25))), isFalse);
      expect(await ok(() => db.insert('supplier_payments', p('IQD', 3000))), isTrue);
    });

    test('ensure آمن التكرار', () async {
      await IqdGuard.ensure(db);
      await IqdGuard.ensure(db);
      final n = (await db.rawQuery("SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'iqd%'"))
          .first['n'] as int;
      expect(n, IqdGuard.sqlForReview().length);
    });
  });
}
