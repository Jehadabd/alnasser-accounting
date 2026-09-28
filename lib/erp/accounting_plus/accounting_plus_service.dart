// lib/erp/accounting_plus/accounting_plus_service.dart
//
// 🏛️ المحاسبة المتقدمة (المرحلة D — مثل الإداري):
//   • سند القيد المركّب: عدة حسابات مدينة ودائنة، بعملات مختلفة، في سند واحد.
//   • قوالب السندات: سند مصروف/قبض/... جاهز بصندوقه وحسابه وبيانه.
//   • إقفال السنة المالية: ترحيل الإيرادات والمصاريف إلى الأرباح المحتجزة.
//   • إعادة تقييم ذمم الموردين بالدولار بسعر الصرف الحالي.
//   • الحسابات النوعية (مجموعات حسابات للتقارير) والملاحظات.
//
// الأمان: كل قيد عبر Ledger.writeEntry (متوازن إجبارياً)، حسابات المراقبة ممنوعة في
// القيد اليدوي، وكل عملية تحترم تثبيت الفترة.

import '../../accounting/ledger.dart';
import '../../accounting/screens/acc_ui.dart' show fmtMoney, fmtDate;
import '../currency_service.dart';
import '../activity/activity_log.dart';
import '../erp_common.dart';

class VLine {
  VLine({
    required this.account,
    this.debit = 0,
    this.credit = 0,
    this.currency = 'IQD',
    this.fcAmount,
    this.fxRate,
    this.memo,
  });
  Account account;
  double debit;
  double credit;
  String currency;
  double? fcAmount;
  double? fxRate;
  String? memo;
}

// ═══════════════════════════ سند القيد المركّب ═══════════════════════════

class CompoundVoucherService {
  static const String type = 'compound';

  Future<int> create({
    required DateTime date,
    required List<VLine> lines,
    String? description,
    String? reference,
    String? docNo,
  }) async {
    final valid = lines.where((l) => l.debit > kMoneyEpsilon || l.credit > kMoneyEpsilon).toList();
    if (valid.length < 2) throw ErpException('السند المركّب يحتاج حسابين على الأقل');
    var dr = 0.0, cr = 0.0;
    for (final l in valid) {
      if (l.debit < 0 || l.credit < 0) throw ErpException('لا يجوز مبلغ سالب');
      if (l.debit > kMoneyEpsilon && l.credit > kMoneyEpsilon) {
        throw ErpException('السطر «${l.account.name}» فيه مدين ودائن معاً — افصلهما');
      }
      if (l.account.isGroup) throw ErpException('«${l.account.name}» حساب رئيسي — اختر حساباً فرعياً');
      if (l.account.isControl) {
        throw ErpException('«${l.account.name}» حساب ذمم — ديون العملاء والموردين تُسجَّل من شاشاتها لتبقى أرصدتهم صحيحة');
      }
      if (l.currency != CurrencyService.base) {
        final fc = l.fcAmount ?? 0;
        final rate = l.fxRate ?? 0;
        if (fc <= 0 || rate <= 0) throw ErpException('السطر «${l.account.name}»: أدخل المبلغ بالعملة وسعر الصرف');
        final iqd = roundMoney(fc * rate);
        final amt = l.debit > 0 ? l.debit : l.credit;
        if ((iqd - amt).abs() > 1) {
          throw ErpException('السطر «${l.account.name}»: المبلغ بالدينار لا يطابق العملة × السعر');
        }
      }
      dr += roundMoney(l.debit);
      cr += roundMoney(l.credit);
    }
    if ((dr - cr).abs() > kMoneyEpsilon) {
      throw ErpException('السند غير متوازن: المدين ${fmtMoney(dr)} والدائن ${fmtMoney(cr)}');
    }
    await PeriodLock.assertOpen(date);
    final db = await erpDb();
    final vid = await db.transaction((txn) async {
      final no = await nextDocNumber(txn, 'vouchers', 'voucher_number', where: 'voucher_type = ?', args: [type]);
      final id = await txn.insert('vouchers', {
        'voucher_number': no,
        'voucher_type': type,
        'voucher_date': date.toIso8601String(),
        'amount': roundMoney(dr),
        'description': description,
        'reference': reference,
        'doc_no': docNo,
        'branch_id': 1,
        'created_by_user_id': currentUserId(),
        'created_at': DateTime.now().toIso8601String(),
      });
      for (final l in valid) {
        await txn.insert('voucher_lines', {
          'voucher_id': id,
          'account_id': l.account.id,
          'debit': roundMoney(l.debit),
          'credit': roundMoney(l.credit),
          'currency': l.currency,
          'fc_amount': l.currency == CurrencyService.base ? null : l.fcAmount,
          'fx_rate': l.currency == CurrencyService.base ? null : l.fxRate,
          'memo': l.memo,
        });
      }
      await Ledger.writeEntry(txn,
          sourceType: 'voucher',
          sourceId: id,
          sourceHash: 'c1',
          date: date,
          description: 'سند قيد رقم $no${description == null || description.isEmpty ? '' : ' — $description'}',
          userId: currentUserId(),
          lines: [
            for (final l in valid)
              JournalLineInput(
                accountId: l.account.id,
                debit: l.debit,
                credit: l.credit,
                currency: l.currency,
                fcAmount: l.currency == CurrencyService.base ? null : l.fcAmount,
                exchangeRate: l.currency == CurrencyService.base ? null : l.fxRate,
                memo: l.memo,
              ),
          ]);
      return id;
    });
    ActivityLog.log('إنشاء', 'سند قيد مركّب', '${description ?? 'سند قيد'} — ${fmtMoney(dr)}');
    return vid;
  }

  Future<void> delete(int id) async {
    final db = await erpDb();
    final v = await db.query('vouchers', where: 'id = ? AND voucher_type = ?', whereArgs: [id, type], limit: 1);
    if (v.isEmpty) throw ErpException('السند غير موجود');
    if ((v.first['is_deleted'] as int? ?? 0) == 1) throw ErpException('السند محذوف مسبقاً');
    await PeriodLock.assertOpen(parseDate(v.first['voucher_date']));
    await db.transaction((txn) async {
      await txn.update(
          'vouchers',
          {
            'is_deleted': 1,
            'deleted_at': DateTime.now().toIso8601String(),
            'deleted_by_user_id': currentUserId(),
          },
          where: 'id = ?',
          whereArgs: [id]);
      await Ledger.deleteBySource(txn, 'voucher', id);
    });
    ActivityLog.log('حذف', 'سند قيد مركّب', 'حذف سند قيد رقم ${v.first['voucher_number']}');
  }

  Future<List<Map<String, Object?>>> list({DateTime? from, DateTime? to, bool includeDeleted = false}) async {
    final db = await erpDb();
    final where = ['voucher_type = ?'];
    final args = <Object?>[type];
    if (!includeDeleted) where.add('is_deleted = 0');
    if (from != null) {
      where.add('voucher_date >= ?');
      args.add(isoDay(from));
    }
    if (to != null) {
      where.add('voucher_date < ?');
      args.add(isoDayAfter(to));
    }
    return db.rawQuery('''
      SELECT v.*, (SELECT COUNT(*) FROM voucher_lines l WHERE l.voucher_id = v.id) AS n_lines
      FROM vouchers v WHERE ${where.join(' AND ')} ORDER BY voucher_date DESC, id DESC''', args);
  }

  Future<List<Map<String, Object?>>> lines(int id) async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT l.*, a.code, a.name FROM voucher_lines l JOIN accounts a ON a.id = l.account_id
      WHERE l.voucher_id = ? ORDER BY l.id''', [id]);
  }
}

// ═══════════════════════════ قوالب السندات ═══════════════════════════

class VoucherTemplatesService {
  Future<List<Map<String, Object?>>> list() async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT t.*, a.name AS account_name, b.name AS box_name FROM voucher_templates t
      LEFT JOIN accounts a ON a.id = t.account_id LEFT JOIN cash_boxes b ON b.id = t.cash_box_id
      ORDER BY t.name''');
  }

  Future<int> save({
    int? id,
    required String name,
    String? abbrev,
    required String voucherType,
    int? cashBoxId,
    int? accountId,
    String? notes,
  }) async {
    if (name.trim().isEmpty) throw ErpException('اكتب اسم القالب');
    final db = await erpDb();
    final row = {
      'name': name.trim(),
      'abbrev': abbrev?.trim(),
      'voucher_type': voucherType,
      'cash_box_id': cashBoxId,
      'account_id': accountId,
      'notes': notes,
    };
    if (id == null) {
      return db.insert('voucher_templates', {...row, 'created_at': DateTime.now().toIso8601String()});
    }
    await db.update('voucher_templates', row, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<void> delete(int id) async {
    final db = await erpDb();
    await db.delete('voucher_templates', where: 'id = ?', whereArgs: [id]);
  }
}

// ═══════════════════════════ إقفال السنة المالية ═══════════════════════════

class ClosingLine {
  ClosingLine(this.account, this.balance);
  final Account account;

  /// بطبيعة الحساب: إيراد = دائن − مدين، مصروف = مدين − دائن.
  final double balance;
}

class FiscalCloseService {
  static const String source = 'year_close';

  /// أرصدة الإيرادات والمصاريف حتى نهاية [year] (بعد إقفالات السنوات السابقة).
  Future<List<ClosingLine>> preview(int year) async {
    final db = await erpDb();
    final end = DateTime(year + 1, 1, 1).toIso8601String();
    final rows = await db.rawQuery('''
      SELECT a.*, COALESCE(SUM(l.debit), 0) AS dr, COALESCE(SUM(l.credit), 0) AS cr
      FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id JOIN accounts a ON a.id = l.account_id
      WHERE e.entry_date < ? AND a.type IN ('revenue', 'expense')
        AND NOT (e.source_type = ? AND e.source_id = ?)
      GROUP BY a.id ORDER BY a.code''', [end, source, year]);
    final out = <ClosingLine>[];
    for (final r in rows) {
      final a = Account.fromMap(r);
      final dr = d0(r['dr']), cr = d0(r['cr']);
      final bal = roundMoney(a.type == 'revenue' ? cr - dr : dr - cr);
      if (bal.abs() < kMoneyEpsilon) continue;
      out.add(ClosingLine(a, bal));
    }
    return out;
  }

  static double netProfit(List<ClosingLine> lines) => roundMoney(lines.fold<double>(
      0, (s, l) => s + (l.account.type == 'revenue' ? l.balance : -l.balance)));

  Future<List<Map<String, Object?>>> closings() async {
    final db = await erpDb();
    return db.query('fiscal_closings', orderBy: 'year DESC');
  }

  /// إقفال السنة: قيد بتاريخ 31/12 يصفّر الإيرادات والمصاريف ويرحّل الصافي
  /// إلى الأرباح المحتجزة. [lockAfter]: تثبيت كل ما قبل 1/1 من السنة التالية.
  Future<double> close(int year, {bool lockAfter = true}) async {
    final now = DateTime.now();
    if (year >= now.year) throw ErpException('لا يمكن إقفال سنة لم تنتهِ بعد');
    final db = await erpDb();
    final done = await db.query('fiscal_closings', where: 'year = ?', whereArgs: [year], limit: 1);
    if (done.isNotEmpty) throw ErpException('السنة $year مقفلة مسبقاً — أعد فتحها أولاً لإعادة الإقفال');
    final lines = await preview(year);
    final net = netProfit(lines);
    final closeDate = DateTime(year, 12, 31, 23, 59);
    await db.transaction((txn) async {
      final retained = await Ledger.systemAccountId(txn, 'retained_earnings');
      final jl = <JournalLineInput>[];
      for (final l in lines) {
        final isRev = l.account.type == 'revenue';
        // عكس رصيد الحساب ليصبح صفراً
        final positive = l.balance > 0;
        final amt = l.balance.abs();
        if (isRev) {
          jl.add(JournalLineInput(accountId: l.account.id, debit: positive ? amt : 0, credit: positive ? 0 : amt));
        } else {
          jl.add(JournalLineInput(accountId: l.account.id, credit: positive ? amt : 0, debit: positive ? 0 : amt));
        }
      }
      if (net > 0) {
        jl.add(JournalLineInput(accountId: retained, credit: net, memo: 'صافي ربح $year'));
      } else if (net < 0) {
        jl.add(JournalLineInput(accountId: retained, debit: -net, memo: 'صافي خسارة $year'));
      }
      if (jl.isNotEmpty) {
        await Ledger.writeEntry(txn,
            sourceType: source,
            sourceId: year,
            sourceHash: 'y1',
            date: closeDate,
            description: 'قيد إقفال السنة المالية $year',
            userId: currentUserId(),
            lines: jl);
      }
      await txn.insert('fiscal_closings', {
        'year': year,
        'close_date': closeDate.toIso8601String(),
        'net_profit': net,
        'created_by': currentUserName(),
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    ActivityLog.log('اعتماد', 'إقفال السنة', 'إقفال السنة المالية $year — صافي ${fmtMoney(net)}');
    if (lockAfter) {
      final current = await PeriodLock.lockDate();
      final target = DateTime(year + 1, 1, 1);
      if (current == null || current.isBefore(target)) await PeriodLock.setLockDate(target);
    }
    return net;
  }

  /// إعادة فتح سنة: حذف قيد الإقفال. تتطلب ألّا تكون 31/12 داخل فترة مثبّتة.
  Future<void> reopen(int year) async {
    // حذف قيد إقفال داخل فترة مثبّتة يغيّر أرصدة مثبّتة ⇒ ألغِ التثبيت أولاً
    await PeriodLock.assertOpen(DateTime(year, 12, 31));
    final db = await erpDb();
    final later = await db.query('fiscal_closings', where: 'year > ?', whereArgs: [year], limit: 1);
    if (later.isNotEmpty) throw ErpException('أعد فتح السنوات اللاحقة أولاً (${later.first['year']})');
    await db.transaction((txn) async {
      await Ledger.deleteBySource(txn, source, year);
      await txn.delete('fiscal_closings', where: 'year = ?', whereArgs: [year]);
    });
    ActivityLog.log('إلغاء', 'إقفال السنة', 'إعادة فتح السنة المالية $year');
  }

  /// بعد الإقفال يجب أن يكون صافي الإيرادات والمصاريف حتى نهاية السنة (مع قيد
  /// الإقفال) صفراً؛ غير الصفر يعني مستنداً عُدِّل بعد الإقفال ⇒ أعد الإقفال.
  Future<double> driftAfterClose(int year) async {
    final db = await erpDb();
    final c = await db.query('fiscal_closings', where: 'year = ?', whereArgs: [year], limit: 1);
    if (c.isEmpty) return 0;
    final end = DateTime(year + 1, 1, 1).toIso8601String();
    final r = await db.rawQuery('''
      SELECT COALESCE(SUM(l.credit - l.debit), 0) AS n
      FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id JOIN accounts a ON a.id = l.account_id
      WHERE e.entry_date < ? AND a.type IN ('revenue', 'expense')''', [end]);
    return roundMoney(d0(r.first['n']));
  }
}

// ═══════════════════════════ إعادة تقييم العملة ═══════════════════════════

class FxRevalRow {
  FxRevalRow(this.supplierId, this.name, this.usd, this.bookIqd, this.targetIqd);
  final int supplierId;
  final String name;

  /// رصيد الدين بالدولار (موجب = علينا للمورد).
  final double usd;
  final double bookIqd;
  final double targetIqd;
  double get diff => roundMoney(targetIqd - bookIqd);
}

class FxRevaluationService {
  static const String source = 'fx_reval';

  /// مفتاح قيد اليوم (إعادة التشغيل في اليوم نفسه تستبدل قيده، فيُستثنى من الرصيد الدفتري).
  static int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  Future<List<FxRevalRow>> preview(DateTime date, {double? rate}) async {
    final db = await erpDb();
    final r = rate ?? await CurrencyService.rateAt(db, 'USD', date);
    if (r <= 0) throw ErpException('لا يوجد سعر صرف للدولار');
    final apUsd = await Ledger.systemAccountId(db, 'ap_usd');
    final rows = await db.rawQuery('''
      SELECT l.party_id AS sid, s.name,
        SUM(CASE WHEN l.currency = 'USD' THEN (CASE WHEN l.credit > 0 THEN COALESCE(l.fc_amount, 0) ELSE -COALESCE(l.fc_amount, 0) END) ELSE 0 END) AS usd,
        SUM(l.credit - l.debit) AS iqd
      FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      LEFT JOIN suppliers s ON s.id = l.party_id
      WHERE l.account_id = ? AND l.party_type = 'supplier' AND e.entry_date < ?
        AND NOT (e.source_type = ? AND e.source_id = ?)
      GROUP BY l.party_id''', [apUsd, isoDayAfter(date), source, dayKey(date)]);
    final out = <FxRevalRow>[];
    for (final x in rows) {
      final sid = x['sid'] as int?;
      if (sid == null) continue;
      final usd = d0(x['usd']);
      final book = roundMoney(d0(x['iqd']));
      final target = roundMoney(usd * r);
      final row = FxRevalRow(sid, '${x['name'] ?? '#$sid'}', usd, book, target);
      if (row.diff.abs() < 1) continue;
      out.add(row);
    }
    return out;
  }

  /// قيد فروقات العملة بتاريخ (مصدر واحد لكل يوم: إعادة التشغيل تستبدل القيد).
  Future<double> post(DateTime date, {double? rate}) async {
    await PeriodLock.assertOpen(date);
    final rows = await preview(date, rate: rate);
    if (rows.isEmpty) return 0;
    final db = await erpDb();
    final sid = dayKey(date);
    var total = 0.0;
    await db.transaction((txn) async {
      final apUsd = await Ledger.systemAccountId(txn, 'ap_usd');
      final fx = await Ledger.systemAccountId(txn, 'fx_diff');
      final lines = <JournalLineInput>[];
      for (final r in rows) {
        final d = r.diff;
        total += d;
        if (d > 0) {
          // الدين بالدينار زاد ⇒ خسارة فروقات
          lines.add(JournalLineInput(accountId: fx, debit: d, memo: r.name));
          lines.add(JournalLineInput(
              accountId: apUsd, credit: d, partyType: 'supplier', partyId: r.supplierId, memo: 'إعادة تقييم'));
        } else {
          lines.add(JournalLineInput(
              accountId: apUsd, debit: -d, partyType: 'supplier', partyId: r.supplierId, memo: 'إعادة تقييم'));
          lines.add(JournalLineInput(accountId: fx, credit: -d, memo: r.name));
        }
      }
      await Ledger.writeEntry(txn,
          sourceType: source,
          sourceId: sid,
          sourceHash: 'r1',
          date: DateTime(date.year, date.month, date.day, 23, 59),
          description: 'إعادة تقييم ذمم الموردين بالدولار',
          userId: currentUserId(),
          lines: lines);
    });
    ActivityLog.log('إنشاء', 'إعادة تقييم العملة', 'قيد فروقات ${fmtDate(date)} — ${fmtMoney(total)}');
    return roundMoney(total);
  }

  Future<List<Map<String, Object?>>> history() async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT e.id, e.entry_date, e.entry_number, e.source_id,
        (SELECT SUM(l.debit) FROM journal_lines l WHERE l.entry_id = e.id) AS total
      FROM journal_entries e WHERE e.source_type = ? ORDER BY e.entry_date DESC''', [source]);
  }

  Future<void> deleteEntry(int sourceId) async {
    final db = await erpDb();
    final e = await db.query('journal_entries',
        where: 'source_type = ? AND source_id = ?', whereArgs: [source, sourceId], limit: 1);
    if (e.isEmpty) return;
    await PeriodLock.assertOpen(parseDate(e.first['entry_date']));
    await db.transaction((txn) => Ledger.deleteBySource(txn, source, sourceId));
  }
}

// ═══════════════════════════ الحسابات النوعية ═══════════════════════════

class AccountGroupsService {
  Future<List<Map<String, Object?>>> groups() async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT g.*, (SELECT COUNT(*) FROM account_group_members m WHERE m.group_id = g.id) AS n
      FROM account_groups g ORDER BY g.name''');
  }

  Future<int> save({int? id, required String name, String? notes}) async {
    if (name.trim().isEmpty) throw ErpException('اكتب اسم المجموعة');
    final db = await erpDb();
    final dup = await db.query('account_groups',
        where: 'name = ? AND id != ?', whereArgs: [name.trim(), id ?? -1], limit: 1);
    if (dup.isNotEmpty) throw ErpException('يوجد مجموعة بهذا الاسم');
    if (id == null) {
      return db.insert('account_groups', {'name': name.trim(), 'notes': notes, 'created_at': DateTime.now().toIso8601String()});
    }
    await db.update('account_groups', {'name': name.trim(), 'notes': notes}, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<void> delete(int id) async {
    final db = await erpDb();
    await db.transaction((txn) async {
      await txn.delete('account_group_members', where: 'group_id = ?', whereArgs: [id]);
      await txn.delete('account_groups', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<int>> members(int groupId) async {
    final db = await erpDb();
    final r = await db.query('account_group_members', where: 'group_id = ?', whereArgs: [groupId]);
    return [for (final x in r) x['account_id'] as int];
  }

  Future<void> setMembers(int groupId, List<int> accountIds) async {
    final db = await erpDb();
    await db.transaction((txn) async {
      await txn.delete('account_group_members', where: 'group_id = ?', whereArgs: [groupId]);
      for (final a in accountIds.toSet()) {
        await txn.insert('account_group_members', {'group_id': groupId, 'account_id': a});
      }
    });
  }

  /// تقرير مجموعة لفترة: لكل حساب (يشمل أبناء الحسابات الرئيسية) مدين/دائن/رصيد.
  Future<List<Map<String, Object?>>> report(int groupId, DateTime from, DateTime to) async {
    final db = await erpDb();
    final ids = await members(groupId);
    if (ids.isEmpty) return const [];
    final all = await db.query('accounts');
    final children = <int, List<int>>{};
    for (final a in all) {
      final p = a['parent_id'] as int?;
      if (p != null) children.putIfAbsent(p, () => []).add(a['id'] as int);
    }
    final out = <Map<String, Object?>>[];
    for (final id in ids) {
      final acc = all.where((a) => a['id'] == id).toList();
      if (acc.isEmpty) continue;
      final leafs = <int>[];
      void walk(int x) {
        final ch = children[x];
        if (ch == null || ch.isEmpty) {
          leafs.add(x);
        } else {
          ch.forEach(walk);
        }
      }

      walk(id);
      final ph = List.filled(leafs.length, '?').join(',');
      final r = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN e.entry_date < ? THEN l.debit - l.credit ELSE 0 END), 0) AS opening,
               COALESCE(SUM(CASE WHEN e.entry_date >= ? THEN l.debit ELSE 0 END), 0) AS dr,
               COALESCE(SUM(CASE WHEN e.entry_date >= ? THEN l.credit ELSE 0 END), 0) AS cr
        FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
        WHERE l.account_id IN ($ph) AND e.entry_date < ? AND e.source_type != 'year_close'
      ''', [isoDay(from), isoDay(from), isoDay(from), ...leafs, isoDayAfter(to)]);
      final opening = d0(r.first['opening']);
      final dr = d0(r.first['dr']);
      final cr = d0(r.first['cr']);
      out.add({
        'code': acc.first['code'],
        'name': acc.first['name'],
        'type': acc.first['type'],
        'opening': opening,
        'debit': dr,
        'credit': cr,
        'closing': opening + dr - cr,
      });
    }
    return out;
  }
}

// ═══════════════════════════ الملاحظات ═══════════════════════════

class ErpNotesService {
  Future<List<Map<String, Object?>>> list() async {
    final db = await erpDb();
    return db.query('erp_notes', orderBy: 'updated_at DESC');
  }

  Future<int> save({int? id, required String title, String? body}) async {
    final db = await erpDb();
    final row = {
      'title': title.trim().isEmpty ? 'ملاحظة' : title.trim(),
      'body': body,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (id == null) return db.insert('erp_notes', row);
    await db.update('erp_notes', row, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<void> delete(int id) async {
    final db = await erpDb();
    await db.delete('erp_notes', where: 'id = ?', whereArgs: [id]);
  }
}
