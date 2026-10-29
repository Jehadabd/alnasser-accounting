// test/control/control_test.dart
//
// 🛡️ الرقابة والأدوات المالية: الحسابات الصافية، وقيود الترحيل المشتقة.
// التشغيل: flutter test test/control/control_test.dart

import 'package:alnaser/accounting/accounting_schema.dart';
import 'package:alnaser/accounting/ledger.dart';
import 'package:alnaser/erp/control/approval_gate.dart';
import 'package:alnaser/erp/control/bank_rec_service.dart';
import 'package:alnaser/erp/control/business_math.dart';
import 'package:alnaser/erp/control/depreciation_math.dart';
import 'package:alnaser/erp/control/landed_cost_service.dart';
import 'package:alnaser/erp/erp_posting.dart';
import 'package:alnaser/erp/erp_schema.dart';
import 'package:alnaser/models/invoice_item.dart';
import 'package:alnaser/services/printed_vouchers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _db() async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  await db.execute('''CREATE TABLE invoices (id INTEGER PRIMARY KEY, invoice_number TEXT, customer_name TEXT,
      invoice_date TEXT, status TEXT, is_deleted INTEGER DEFAULT 0)''');
  await AccountingSchema.ensure(db);
  await ErpSchema.ensure(db);
  return db;
}

Future<int> _acc(Database db, String key) => Ledger.systemAccountId(db, key);

/// رصيد حساب (مدين − دائن).
Future<double> _bal(Database db, int accountId) async {
  final r = await db.rawQuery(
      'SELECT COALESCE(SUM(debit - credit), 0) AS b FROM journal_lines WHERE account_id = ?', [accountId]);
  return (r.first['b'] as num).toDouble();
}

Future<int> _boxAccount(Database db, int boxId) async =>
    (await db.query('cash_boxes', where: 'id = ?', whereArgs: [boxId])).first['account_id'] as int;

Future<void> _balanced(Database db) async {
  final r = await db.rawQuery('SELECT COALESCE(SUM(debit), 0) AS d, COALESCE(SUM(credit), 0) AS c FROM journal_lines');
  expect((r.first['d'] as num).toDouble(), closeTo((r.first['c'] as num).toDouble(), 0.001));
}

InvoiceItem _item(String name, double qty, double price, {double? cost, bool gift = false, double? before}) => InvoiceItem(
      invoiceId: 0,
      productName: name,
      unit: 'piece',
      quantityIndividual: qty,
      appliedPrice: price,
      itemTotal: qty * price,
      actualCostPrice: cost,
      saleType: 'قطعة',
      discountType: gift ? 'gift' : (before != null ? 'amount' : null),
      priceBeforeDiscount: before,
      discountValue: before == null ? null : before - price,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('الإهلاك (قسط ثابت)', () {
    test('القسط الشهري والسقف', () {
      expect(monthlyDepreciation(cost: 1200000, salvage: 0, lifeMonths: 12), 100000);
      expect(monthlyDepreciation(cost: 1000, salvage: 100, lifeMonths: 0), 0);
      // آخر قسط يأخذ الباقي فقط
      expect(
          depreciationFor(
              period: '2026-12', startPeriod: '2026-01', cost: 1000, salvage: 0, lifeMonths: 3, accumulated: 666.66),
          333.34);
      // لا شيء بعد اكتمال الإهلاك
      expect(
          depreciationFor(period: '2027-05', startPeriod: '2026-01', cost: 1000, salvage: 100, lifeMonths: 3, accumulated: 900),
          0);
    });

    test('قبل البدء وشهر الاستبعاد لا يُهلكان', () {
      expect(depreciationFor(period: '2025-12', startPeriod: '2026-01', cost: 1200, salvage: 0, lifeMonths: 12, accumulated: 0), 0);
      expect(
          depreciationFor(
              period: '2026-03', startPeriod: '2026-01', disposedPeriod: '2026-03', cost: 1200, salvage: 0, lifeMonths: 12, accumulated: 200),
          0);
      expect(
          depreciationFor(
              period: '2026-02', startPeriod: '2026-01', disposedPeriod: '2026-03', cost: 1200, salvage: 0, lifeMonths: 12, accumulated: 100),
          100);
    });

    test('تواريخ الشهر والربح/الخسارة', () {
      expect(periodEnd('2026-02'), DateTime(2026, 2, 28));
      expect(periodEnd('2028-02'), DateTime(2028, 2, 29));
      expect(validPeriod('2026-13'), isFalse);
      expect(validPeriod('2026-07'), isTrue);
      expect(disposalGain(cost: 1200000, accumulated: 100000, proceeds: 1000000), -100000);
      expect(disposalGain(cost: 1000, accumulated: 900, proceeds: 300), 200);
    });
  });

  group('نقطة التعادل واقتراح الطلبية', () {
    test('المبيعات اللازمة', () {
      final be = BreakEven(fixedMonthly: 3000000, marginPct: 20, daysInMonth: 30);
      expect(be.monthlySales, 15000000);
      expect(be.dailySales, 500000);
      expect(be.requiredToDate(10), 5000000);
      expect(be.coveredPct(1500000), 50);
      expect(BreakEven(fixedMonthly: 1000, marginPct: 0, daysInMonth: 30).valid, isFalse);
      expect(daysInMonthOf(DateTime(2026, 2, 10)), 28);
    });

    test('الكمية المقترحة والعاجل', () {
      final r = ReorderInput(soldBaseQty: 60, lookbackDays: 30, stockBaseQty: 10, leadDays: 5, coverDays: 10);
      expect(r.dailyVelocity, 2);
      expect(r.targetStock, 30);
      expect(r.suggested, 20);
      expect(r.urgent, isTrue);
      // الرصيد يكفي
      expect(ReorderInput(soldBaseQty: 30, lookbackDays: 30, stockBaseQty: 100, leadDays: 5, coverDays: 10).suggested, 0);
      // بلا مبيعات لكن تحت الحد الأدنى
      expect(ReorderInput(soldBaseQty: 0, lookbackDays: 30, stockBaseQty: 3, leadDays: 5, coverDays: 10, minStock: 10).suggested, 7);
      expect(toLargeUnits(25, 12), 3);
    });
  });

  group('مصاريف الشحن', () {
    test('حصة الوحدة والكلفة النهائية', () {
      expect(landedPerUnit(100000, 50), 2000);
      expect(landedPerUnit(100, 0), 0);
      final p = LandedPlan(
        purchaseUnitCost: 10000,
        baseQty: 50,
        extras: [LandedExtra('شحن', 60000), LandedExtra('جمارك', 40000)],
        mode: LandedMode.box,
        boxId: 1,
      );
      expect(p.totalExtra, 100000);
      expect(p.finalUnitCost, 12000);
      expect(() => LandedCostService.validate(p), returnsNormally);
      expect(
          () => LandedCostService.validate(LandedPlan(
              purchaseUnitCost: 1, baseQty: 0, extras: [LandedExtra('x', 5)], mode: LandedMode.none)),
          throwsA(anything));
      expect(
          () => LandedCostService.validate(LandedPlan(
              purchaseUnitCost: 1, baseQty: 2, extras: [LandedExtra('x', 5)], mode: LandedMode.box)),
          throwsA(anything));
    });
  });

  group('قواعد موافقة المدير', () {
    final all = ApprovalSettings(pastDate: true, belowCost: true, discountPct: 10);
    final today = DateTime(2026, 10, 29, 15);

    test('فاتورة سليمة لا تحتاج موافقة', () {
      final v = invoiceViolations(
          settings: all,
          items: [_item('سلك', 10, 1000, cost: 700)],
          invoiceDiscount: 500,
          selectedDate: today,
          today: today);
      expect(v, isEmpty);
    });

    test('تاريخ سابق: تعديل فاتورة أمس، أو فاتورة جديدة بتاريخ رجعي', () {
      final edit = invoiceViolations(
          settings: all,
          items: [_item('سلك', 1, 1000, cost: 700)],
          invoiceDiscount: 0,
          selectedDate: today,
          originalDate: DateTime(2026, 10, 28),
          today: today);
      expect(edit.map((x) => x.rule), [ApprovalRule.pastDate]);
      final back = invoiceViolations(
          settings: all,
          items: [_item('سلك', 1, 1000, cost: 700)],
          invoiceDiscount: 0,
          selectedDate: DateTime(2026, 10, 20),
          today: today);
      expect(back.map((x) => x.rule), [ApprovalRule.pastDate]);
      // فاتورة اليوم نفسه بساعة مختلفة: ليست سابقة
      final same = invoiceViolations(
          settings: all,
          items: [_item('سلك', 1, 1000, cost: 700)],
          invoiceDiscount: 0,
          selectedDate: DateTime(2026, 10, 29, 1),
          originalDate: DateTime(2026, 10, 29, 9),
          today: today);
      expect(same, isEmpty);
    });

    test('تحت الكلفة والهدية', () {
      final v = invoiceViolations(
          settings: all,
          items: [_item('سلك', 10, 600, cost: 700), _item('شريط', 1, 0, cost: 500, gift: true)],
          invoiceDiscount: 0,
          selectedDate: today,
          today: today);
      expect(v.map((x) => x.rule), contains(ApprovalRule.belowCost));
      // كلفة غير معروفة: لا حكم
      expect(
          invoiceViolations(
              settings: all, items: [_item('سلك', 10, 1, cost: null)], invoiceDiscount: 0, selectedDate: today, today: today),
          isEmpty);
    });

    test('الخصم: خصم الفاتورة + خصومات الأسطر', () {
      // 10 × 1000 = 10,000؛ خصم السطر 0 + خصم الفاتورة 1,500 = 15% > 10%
      final v = invoiceViolations(
          settings: all,
          items: [_item('سلك', 10, 1000, cost: 500)],
          invoiceDiscount: 1500,
          selectedDate: today,
          today: today);
      expect(v.map((x) => x.rule), [ApprovalRule.discount]);
      // سعر 900 بعد خصم 100 للقطعة: 1,000 من 10,000 = 10% — ضمن المسموح
      final ok = invoiceViolations(
          settings: all,
          items: [_item('سلك', 10, 900, cost: 500, before: 1000)],
          invoiceDiscount: 0,
          selectedDate: today,
          today: today);
      expect(ok, isEmpty);
      // الإعداد 0 = بلا قيد
      final off = invoiceViolations(
          settings: ApprovalSettings(pastDate: true, belowCost: true, discountPct: 0),
          items: [_item('سلك', 10, 1000, cost: 500)],
          invoiceDiscount: 9000,
          selectedDate: today,
          today: today);
      expect(off, isEmpty);
    });
  });

  group('قيود الترحيل المشتقة', () {
    test('فرق عدّ الدرج: لا قيد قبل اعتماد المدير، ثم قيد بالعجز، والإلغاء يحذفه', () async {
      final db = await _db();
      final box = await _boxAccount(db, 1);
      final over = await _acc(db, 'cash_over_short');
      Future<void> addCount(int id, String status, double diff) => db.insert('cash_counts', {
            'id': id,
            'count_no': id,
            'count_day': DateTime(2026, 10, 28).toIso8601String(),
            'counted_at': DateTime(2026, 10, 28, 22).toIso8601String(),
            'box_id': 1,
            'expected': 100000,
            'counted': 100000 + diff,
            'diff': diff,
            'counted_by': 'علي',
            'status': status,
            'created_at': DateTime(2026, 10, 28, 22).toIso8601String(),
          });
      await addCount(1, 'pending', -5000);
      await addCount(2, 'approved', -3000); // اعتماد بلا قيد
      await addCount(3, 'posted', 0.4); // فرق أقل من دينار: لا قيد
      await ErpPosting(db).syncAll();
      expect(await _bal(db, over), 0);

      await db.update('cash_counts', {'status': 'posted'}, where: 'id = 1');
      await ErpPosting(db).syncAll();
      expect(await _bal(db, over), 5000);
      expect(await _bal(db, box), -5000);
      await _balanced(db);

      // زيادة
      await addCount(4, 'posted', 2000);
      await ErpPosting(db).syncAll();
      expect(await _bal(db, over), 3000);
      expect(await _bal(db, box), -3000);

      // إعادة التشغيل لا تكرر
      await ErpPosting(db).syncAll();
      final n = await db.rawQuery("SELECT COUNT(*) AS n FROM journal_entries WHERE source_type = 'cash_count'");
      expect(n.first['n'], 2);

      await db.update('cash_counts', {'status': 'void'}, where: 'id = 1');
      await ErpPosting(db).syncAll();
      expect(await _bal(db, over), -2000);
      expect(await _bal(db, box), 2000);
      await _balanced(db);
      await db.close();
    });

    test('أصل: شراء من صندوق، إهلاك شهر، ثم بيع بخسارة', () async {
      final db = await _db();
      final box = await _boxAccount(db, 1);
      final assetAcc = (await db.query('accounts', where: "code = '1401'")).first['id'] as int;
      await db.insert('fixed_assets', {
        'id': 1,
        'asset_no': 1,
        'name': 'مولدة',
        'acquired_on': DateTime(2026, 1, 5).toIso8601String(),
        'cost': 1200000,
        'salvage': 0,
        'life_months': 12,
        'dep_start': '2026-01',
        'asset_account_id': assetAcc,
        'funding': 'box',
        'funding_box_id': 1,
        'created_at': DateTime(2026, 1, 5).toIso8601String(),
      });
      // أصل «مسجّل مسبقاً» لا قيد شراء له
      await db.insert('fixed_assets', {
        'id': 2,
        'asset_no': 2,
        'name': 'رفوف',
        'acquired_on': DateTime(2026, 1, 5).toIso8601String(),
        'cost': 500000,
        'life_months': 60,
        'dep_start': '2026-01',
        'asset_account_id': assetAcc,
        'funding': 'already',
        'created_at': DateTime(2026, 1, 5).toIso8601String(),
      });
      await ErpPosting(db).syncAll();
      expect(await _bal(db, assetAcc), 1200000);
      expect(await _bal(db, box), -1200000);

      await db.insert('depreciation_runs', {
        'id': 1,
        'period': '2026-01',
        'run_date': DateTime(2026, 1, 31).toIso8601String(),
        'total': 100000,
        'status': 'posted',
        'created_at': DateTime(2026, 2, 1).toIso8601String(),
      });
      await db.insert('depreciation_lines', {'run_id': 1, 'asset_id': 1, 'amount': 100000});
      await ErpPosting(db).syncAll();
      final accDep = await _acc(db, 'accum_depreciation');
      final depExp = await _acc(db, 'depreciation_expense');
      expect(await _bal(db, depExp), 100000);
      expect(await _bal(db, accDep), -100000);

      // بيع بمليون: الدفترية 1,100,000 ⇒ خسارة 100,000
      await db.update(
          'fixed_assets',
          {
            'status': 'disposed',
            'disposed_on': DateTime(2026, 2, 10).toIso8601String(),
            'disposal_amount': 1000000,
            'disposal_box_id': 1,
          },
          where: 'id = 1');
      await ErpPosting(db).syncAll();
      final gl = await _acc(db, 'asset_disposal');
      expect(await _bal(db, gl), 100000);
      expect(await _bal(db, accDep), 0); // المجمّع أُقفل
      expect(await _bal(db, assetAcc), 0); // الأصل خرج
      expect(await _bal(db, box), -200000);
      await _balanced(db);

      // إلغاء الاستبعاد يحذف قيده
      await db.update('fixed_assets', {'status': 'active', 'disposed_on': null, 'disposal_amount': null}, where: 'id = 1');
      await ErpPosting(db).syncAll();
      expect(await _bal(db, gl), 0);
      expect(await _bal(db, assetAcc), 1200000);
      await db.close();
    });

    test('مصاريف الشحن: من صندوق، وإعادة تصنيف، و«بلا قيد»', () async {
      final db = await _db();
      final box = await _boxAccount(db, 1);
      final inv = await _acc(db, 'inventory');
      final transport = (await db.query('accounts', where: "code = '5204'")).first['id'] as int;
      Future<void> add(int id, String mode, double total, {int? boxId, int? exp}) => db.insert('landed_costs', {
            'id': id,
            'product_id': 1,
            'product_name': 'سلك',
            'cost_date': DateTime(2026, 10, 1).toIso8601String(),
            'base_qty': 50,
            'purchase_unit_cost': 10000,
            'extras': '[]',
            'total_extra': total,
            'per_unit': total / 50,
            'mode': mode,
            'box_id': boxId,
            'expense_account_id': exp,
            'created_at': DateTime(2026, 10, 1).toIso8601String(),
          });
      await add(1, LandedMode.box, 50000, boxId: 1);
      await add(2, LandedMode.reclass, 20000, exp: transport);
      await add(3, LandedMode.none, 99999);
      await ErpPosting(db).syncAll();
      expect(await _bal(db, inv), 70000);
      expect(await _bal(db, box), -50000);
      expect(await _bal(db, transport), -20000);
      await _balanced(db);
      await db.update('landed_costs', {'status': 'void'}, where: 'id = 1');
      await ErpPosting(db).syncAll();
      expect(await _bal(db, inv), 20000);
      expect(await _bal(db, box), 0);
      await db.close();
    });
  });

  group('رمز التحقق للسندات المطبوعة', () {
    test('ثابت لنفس السند، ويتغيّر بتغيّر المبلغ أو الاسم أو الملح', () {
      const salt = 'abcdefghijklmnopqrstuvwx';
      final a = PrintedVouchers.codeOf(salt, 'receipt', '15', 250000, 'محمد أحمد');
      expect(a.length, 6);
      expect(RegExp(r'^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$').hasMatch(a), isTrue);
      expect(PrintedVouchers.codeOf(salt, 'receipt', '15', 250000, '  محمد   أحمد '), a);
      expect(PrintedVouchers.codeOf(salt, 'receipt', '15', 260000, 'محمد أحمد'), isNot(a));
      expect(PrintedVouchers.codeOf(salt, 'receipt', '15', 250000, 'محمد علي'), isNot(a));
      expect(PrintedVouchers.codeOf(salt, 'debit_note', '15', 250000, 'محمد أحمد'), isNot(a));
      expect(PrintedVouchers.codeOf('zyxwvutsrqponmlkjihgfedc', 'receipt', '15', 250000, 'محمد أحمد'), isNot(a));
      expect(PrintStamp(a, 1, 1).line, a);
      expect(PrintStamp(a, 2, 1).line, '$a — نسخة 2');
    });
  });

  group('مطابقة البنك', () {
    test('الفرق والمعلَّق', () {
      final rec = BankRec.fromRow({
        'id': 1,
        'box_id': 2,
        'statement_date': '2026-10-31',
        'statement_balance': 700,
        'status': 'draft',
      });
      final lines = [
        BankLine(key: 'voucher:1', date: DateTime(2026, 10, 1), amount: 1000, description: '', entryNo: 1),
        BankLine(key: 'voucher:2', date: DateTime(2026, 10, 5), amount: -300, description: '', entryNo: 2),
        BankLine(key: 'voucher:3', date: DateTime(2026, 10, 9), amount: -200, description: '', entryNo: 3),
      ];
      final st = BankRecState(rec: rec, lines: lines, marked: {'voucher:1', 'voucher:2'}, priorCleared: 0, bookBalance: 500);
      expect(st.clearedBalance, 700);
      expect(st.difference, 0);
      expect(st.balanced, isTrue);
      expect(st.unclearedOut, 200);
      final st2 = BankRecState(rec: rec, lines: lines, marked: {'voucher:1'}, priorCleared: 0, bookBalance: 500);
      expect(st2.difference, -300);
      expect(st2.balanced, isFalse);
    });
  });
}
