// test/sync_harness/accounting_ops.dart
//
// أفعال «اختبار الصندوق والمحاسبة» على الجهاز الوهمي — عبر الكود الحقيقي: السندات
// (VouchersService)، القيود اليدوية (Ledger)، الرواتب والسلف (HrStore)، الأصول الثابتة
// والإهلاك (FixedAssetsService)، جرد الصندوق (CashCountService)، التوصيل (DeliveryStore)،
// والثوابت المحاسبية بعد كل فعل. كل فعل يعيد نتيجته أو {'ok': false, 'err': ...}.

import 'package:alnaser/accounting/ledger.dart';
import 'package:alnaser/accounting/vouchers_service.dart';
import 'package:alnaser/erp/control/cash_count_service.dart';
import 'package:alnaser/erp/control/fixed_assets_service.dart';
import 'package:alnaser/erp/delivery/delivery_models.dart';
import 'package:alnaser/erp/delivery/delivery_store.dart';
import 'package:alnaser/erp/hr/hr_models.dart';
import 'package:alnaser/erp/hr/hr_store.dart';
import 'package:alnaser/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

double _d(Object? v) => (v as num?)?.toDouble() ?? 0.0;

Future<Object?> acctOp(String op, Map<String, Object?> a) async {
  try {
    return await _acctOp(op, a);
  } catch (e) {
    return {'ok': false, 'err': '$e'.split('\n').first};
  }
}

Future<Object?> _acctOp(String op, Map<String, Object?> a) async {
  final db = await DatabaseService().database;
  switch (op) {
    case 'setup':
      // صندوقان، وحسابات فرعية غير نقدية للطرف المقابل
      final vs = VouchersService();
      var boxes = await vs.cashBoxes();
      if (boxes.length < 2) await vs.createCashBox('صندوق الاختبار الثاني');
      boxes = await vs.cashBoxes();
      final accs = await db.rawQuery('''
        SELECT id, type FROM accounts WHERE is_group = 0 AND is_control = 0 AND is_active = 1
          AND id NOT IN (SELECT account_id FROM cash_boxes WHERE account_id IS NOT NULL)
        ORDER BY id''');
      await HrStore().setEnabled(true);
      return {
        'boxes': [for (final b in boxes) b.id],
        'accounts': [for (final r in accs) r['id']],
        'expense': [for (final r in accs) if (r['type'] == 'expense') r['id']],
      };

    case 'boxBalances':
      return {for (final e in (await VouchersService().cashBoxBalances()).entries) '${e.key}': e.value};

    case 'voucher':
      final id = await VouchersService().create(
        type: VoucherType.values.byName(a['type'] as String),
        amount: _d(a['amount']),
        date: DateTime.now(),
        cashBoxId: (a['box'] as num).toInt(),
        toCashBoxId: (a['toBox'] as num?)?.toInt(),
        accountId: (a['acc'] as num?)?.toInt(),
        description: 'اختبار',
      );
      final v = (await db.query('vouchers', where: 'id = ?', whereArgs: [id])).first;
      return {'ok': true, 'id': id, 'amount': _d(v['amount'])};

    case 'voucherDelete':
      await VouchersService().delete((a['id'] as num).toInt());
      return {'ok': true};

    case 'manual':
      final id = await Ledger().postManualEntry(
        date: DateTime.now(),
        description: 'قيد اختبار',
        lines: [
          for (final l in (a['lines'] as List).cast<Map>())
            JournalLineInput(accountId: (l['acc'] as num).toInt(), debit: _d(l['debit']), credit: _d(l['credit']))
        ],
      );
      return {'ok': true, 'id': id};

    case 'manualDelete':
      await Ledger().deleteManualEntry((a['id'] as num).toInt());
      return {'ok': true};

    case 'hrEmp':
      final id = await HrStore().saveEmployee(HrEmployee(name: a['name'] as String, salaryFils: (a['salary'] as num).toInt()));
      return {'ok': true, 'id': id};

    case 'hrAdvance':
    case 'hrPay':
      final store = HrStore();
      final e = (await store.employees()).firstWhere((x) => x.id == (a['emp'] as num).toInt());
      if (op == 'hrAdvance') {
        await store.payAdvance(
            e: e, amountFils: (a['fils'] as num).toInt(), cashBoxId: (a['box'] as num).toInt(), accountId: (a['acc'] as num).toInt());
        return {'ok': true};
      }
      final month = a['month'] as String;
      final adv = Payslip.openAdvances(await store.advances(employeeId: e.id), e.id!, month);
      final p = Payslip(
          employeeId: e.id!,
          month: month,
          baseFils: e.salaryFils,
          bonusFils: (a['bonus'] as num).toInt(),
          deductionFils: (a['deduction'] as num).toInt(),
          advancesFils: adv);
      await store.payPayslip(e: e, p: p, cashBoxId: (a['box'] as num).toInt(), accountId: (a['acc'] as num).toInt());
      return {'ok': true, 'net': p.netFils, 'advances': adv};

    case 'asset':
      final id = await FixedAssetsService.create(
        name: a['name'] as String,
        acquiredOn: DateTime.now().subtract(const Duration(days: 400)),
        cost: _d(a['cost']),
        salvage: _d(a['salvage']),
        lifeMonths: (a['life'] as num).toInt(),
        funding: a['funding'] as String,
        fundingBoxId: (a['box'] as num?)?.toInt(),
      );
      return {'ok': true, 'id': id};

    case 'depRun':
      return {'ok': true, 'id': await FixedAssetsService.runPeriod(a['period'] as String)};

    case 'depVoid':
      await FixedAssetsService.voidRun((a['id'] as num).toInt());
      return {'ok': true};

    case 'assetDispose':
      await FixedAssetsService.dispose((a['id'] as num).toInt(),
          on: DateTime.now(), proceeds: _d(a['proceeds']), boxId: (a['box'] as num?)?.toInt());
      return {'ok': true};

    case 'assetUndispose':
      await FixedAssetsService.undispose((a['id'] as num).toInt());
      return {'ok': true};

    case 'assetDelete':
      await FixedAssetsService.delete((a['id'] as num).toInt());
      return {'ok': true};

    case 'cashCount':
      final id = await CashCountService.save(
          day: DateTime.now(),
          source: 'اختبار',
          boxId: (a['box'] as num).toInt(),
          opening: 0,
          expected: _d(a['expected']),
          counted: _d(a['counted']));
      return {'ok': true, 'id': id};

    case 'cashReview':
      await CashCountService.review((a['id'] as num).toInt(), post: true);
      return {'ok': true};

    case 'cashVoid':
      await CashCountService.voidCount((a['id'] as num).toInt(), 'اختبار');
      return {'ok': true};

    case 'delivery':
      // شركة، طلبات بمبالغ تحصيل، تسليم/إرجاع، ثم تسوية: مجموع التسوية = مجموع الطلبات المسلّمة
      final st = DeliveryStore();
      final cid = await st.saveCompany(DeliveryCompany(name: a['company'] as String));
      var cod = 0;
      for (final o in (a['orders'] as List).cast<Map>()) {
        final id = await st.saveOrder(DeliveryOrder(
            companyId: cid, customerName: 'زبون توصيل', codFils: (o['cod'] as num).toInt(), feeFils: (o['fee'] as num).toInt()));
        var ord = (await st.orders(companyId: cid)).firstWhere((x) => x.id == id);
        await st.setStatus(ord, DeliveryStatus.out);
        ord = (await st.orders(companyId: cid)).firstWhere((x) => x.id == id);
        final ok = o['delivered'] == true;
        await st.setStatus(ord, ok ? DeliveryStatus.delivered : DeliveryStatus.returned);
        if (ok) cod += (o['cod'] as num).toInt();
      }
      final s = await st.settle(cid);
      final row = (await db.query('delivery_settlements', where: 'id = ?', whereArgs: [s.id])).first;
      return {'ok': true, 'expectedCod': cod, 'cod': row['cod_fils'], 'again': (await st.orders(companyId: cid, unsettledOnly: true)).length};

    case 'acctInvariants':
      return await _invariants(db);
  }
  throw StateError('unknown acct op $op');
}

Future<Map<String, Object?>> _invariants(Database db) async {
  final out = <String>[];
  final notes = <String>[];
  // 1) كل قيد متوازن
  for (final r in await db.rawQuery('''
      SELECT e.id, e.source_type AS st, SUM(l.debit) AS d, SUM(l.credit) AS c
      FROM journal_entries e JOIN journal_lines l ON l.entry_id = e.id GROUP BY e.id
      HAVING ABS(SUM(l.debit) - SUM(l.credit)) > 0.005''')) {
    out.add('قيد ${r['id']} (${r['st']}) غير متوازن: مدين ${r['d']} دائن ${r['c']}');
  }
  // 2) ميزان المراجعة كله
  final tb = (await db.rawQuery('SELECT COALESCE(SUM(debit), 0) AS d, COALESCE(SUM(credit), 0) AS c FROM journal_lines')).first;
  if ((_d(tb['d']) - _d(tb['c'])).abs() > 0.005) out.add('ميزان المراجعة غير متوازن: ${tb['d']} ≠ ${tb['c']}');
  // 3) لا أسطر يتيمة ولا قيود فارغة
  final orphan = (await db.rawQuery(
          'SELECT COUNT(*) AS n FROM journal_lines l WHERE NOT EXISTS (SELECT 1 FROM journal_entries e WHERE e.id = l.entry_id)'))
      .first['n'] as int;
  if (orphan > 0) out.add('$orphan سطر قيد بلا قيد');
  final empty = (await db.rawQuery(
          'SELECT COUNT(*) AS n FROM journal_entries e WHERE NOT EXISTS (SELECT 1 FROM journal_lines l WHERE l.entry_id = e.id)'))
      .first['n'] as int;
  if (empty > 0) out.add('$empty قيد بلا أسطر');
  // 4) كل سند حي له قيده بمبلغه، والمحذوف لا قيد له
  for (final v in await db.query('vouchers')) {
    final e = await db.rawQuery('''
        SELECT COALESCE(SUM(l.debit), 0) AS d FROM journal_entries e JOIN journal_lines l ON l.entry_id = e.id
        WHERE e.source_type = 'voucher' AND e.source_id = ?''', [v['id']]);
    final has = await db.query('journal_entries', columns: ['id'], where: "source_type = 'voucher' AND source_id = ?", whereArgs: [v['id']]);
    if (v['is_deleted'] == 1) {
      if (has.isNotEmpty) out.add('سند محذوف ${v['voucher_number']} ما زال له قيد');
    } else if (has.isEmpty) {
      out.add('سند ${v['voucher_number']} (${v['voucher_type']}) بلا قيد');
    } else if ((_d(e.first['d']) - _d(v['amount'])).abs() > 0.005) {
      out.add('سند ${v['voucher_number']}: قيده ${e.first['d']} ومبلغه ${v['amount']}');
    }
  }
  // 5) الأصل: مجمع الإهلاك لا يتجاوز (الكلفة − الخردة)
  for (final r in await db.rawQuery('''
      SELECT a.id, a.name, a.cost, a.salvage,
             (SELECT COALESCE(SUM(l.amount), 0) FROM depreciation_lines l JOIN depreciation_runs r ON r.id = l.run_id
              WHERE l.asset_id = a.id AND r.status = 'posted') AS acc
      FROM fixed_assets a''')) {
    if (_d(r['acc']) > _d(r['cost']) - _d(r['salvage']) + 0.005) {
      out.add('الأصل «${r['name']}»: مجمع إهلاكه ${r['acc']} يتجاوز ${_d(r['cost']) - _d(r['salvage'])}');
    }
  }
  // 6) الدينار بلا كسور في القيود (ملاحظة: الإهلاك الشهري قسمة)
  final frac = (await db.rawQuery('''
      SELECT e.source_type AS st, COUNT(*) AS n FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      WHERE l.currency = 'IQD' AND (ABS(l.debit - ROUND(l.debit)) > 0.0001 OR ABS(l.credit - ROUND(l.credit)) > 0.0001)
      GROUP BY e.source_type'''));
  for (final r in frac) {
    notes.add('${r['n']} سطر قيد بكسور من «${r['st']}»');
  }
  return {'problems': out, 'notes': notes};
}
