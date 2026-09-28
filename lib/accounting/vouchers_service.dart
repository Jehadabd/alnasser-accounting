// lib/accounting/vouchers_service.dart
//
// 🧾 السندات: مصروف، إيراد آخر، صرف، تحويل بين صناديق، رصيد افتتاحي.
//
// ديون العملاء والموردين لا تُسجَّل هنا — مكانها سجل الديون وشاشة الموردين،
// حتى يبقى رصيد كل عميل/مورد صحيحاً. هذه السندات لما سواها.

import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';
import '../erp/activity/activity_log.dart';
import '../erp/erp_common.dart' show PeriodLock;
import 'ledger.dart';

enum VoucherType {
  expense, // مصروف: مدين حساب المصروف / دائن الصندوق
  income, // إيراد آخر: مدين الصندوق / دائن حساب الإيراد
  payment, // صرف لأي حساب (مسحوبات، سلفة موظف، شراء أصل...)
  receipt, // قبض من أي حساب (رأس مال، استرداد سلفة...)
  transfer, // تحويل بين صندوقين
  opening, // رصيد افتتاحي لصندوق
}

const Map<VoucherType, String> voucherTypeLabels = {
  VoucherType.expense: 'سند مصروف',
  VoucherType.income: 'سند إيراد',
  VoucherType.payment: 'سند صرف',
  VoucherType.receipt: 'سند قبض',
  VoucherType.transfer: 'تحويل بين صناديق',
  VoucherType.opening: 'رصيد افتتاحي لصندوق',
};

class CashBox {
  CashBox({
    required this.id,
    required this.name,
    required this.accountId,
    required this.branchId,
    required this.kind,
    required this.isDefault,
    required this.isActive,
  });
  final int id;
  final String name;
  final int accountId;
  final int branchId;
  final String kind; // cash | bank
  final bool isDefault;
  final bool isActive;

  factory CashBox.fromMap(Map<String, Object?> m) => CashBox(
        id: m['id'] as int,
        name: m['name'] as String,
        accountId: m['account_id'] as int,
        branchId: (m['branch_id'] as int?) ?? 1,
        kind: (m['kind'] as String?) ?? 'cash',
        isDefault: (m['is_default'] as int? ?? 0) == 1,
        isActive: (m['is_active'] as int? ?? 1) == 1,
      );

  @override
  String toString() => name;
}

class VouchersService {
  VouchersService({Future<Database> Function()? getDatabase})
      : _getDb = getDatabase ?? (() => DatabaseService().database);

  final Future<Database> Function() _getDb;

  // ───────────────────────── الصناديق ─────────────────────────

  Future<List<CashBox>> cashBoxes({bool activeOnly = true}) async {
    final db = await _getDb();
    final rows = await db.query('cash_boxes',
        where: activeOnly ? 'is_active = 1' : null, orderBy: 'is_default DESC, id');
    return rows.map(CashBox.fromMap).toList();
  }

  /// أرصدة الصناديق من الدفتر.
  Future<Map<int, double>> cashBoxBalances() async {
    final db = await _getDb();
    final rows = await db.rawQuery('''
      SELECT b.id, COALESCE(SUM(l.debit - l.credit), 0) AS bal
      FROM cash_boxes b LEFT JOIN journal_lines l ON l.account_id = b.account_id
      GROUP BY b.id
    ''');
    return {for (final r in rows) r['id'] as int: (r['bal'] as num).toDouble()};
  }

  /// صندوق جديد = حساب جديد تحت «النقدية».
  Future<int> createCashBox(String name, {String kind = 'cash', int branchId = 1}) async {
    final db = await _getDb();
    return db.transaction((txn) async {
      final groupId = await Ledger.systemAccountId(txn, 'cash_group');
      final g = await txn.query('accounts', where: 'id = ?', whereArgs: [groupId]);
      final groupCode = g.first['code'] as String;
      final kids = await txn.query('accounts',
          columns: ['code'], where: 'parent_id = ?', whereArgs: [groupId]);
      var max = 0;
      for (final k in kids) {
        final code = k['code'] as String;
        final tail = int.tryParse(code.substring(groupCode.length));
        if (code.startsWith(groupCode) && tail != null && tail > max) max = tail;
      }
      final code = '$groupCode${(max + 1).toString().padLeft(2, '0')}';
      final now = DateTime.now().toIso8601String();
      final accId = await txn.insert('accounts', {
        'code': code,
        'name': name.trim(),
        'parent_id': groupId,
        'type': 'asset',
        'is_group': 0,
        'is_control': 0,
        'currency': 'IQD',
        'created_at': now,
      });
      return txn.insert('cash_boxes', {
        'name': name.trim(),
        'account_id': accId,
        'branch_id': branchId,
        'kind': kind,
        'is_default': 0,
        'created_at': now,
      });
    });
  }

  Future<void> setDefaultCashBox(int id) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      await txn.update('cash_boxes', {'is_default': 0});
      await txn.update('cash_boxes', {'is_default': 1}, where: 'id = ?', whereArgs: [id]);
    });
  }

  // ───────────────────────── السندات ─────────────────────────

  Future<int> _nextNumber(DatabaseExecutor d, VoucherType type) async {
    final r = await d.rawQuery(
        'SELECT COALESCE(MAX(voucher_number), 0) + 1 AS n FROM vouchers WHERE voucher_type = ?',
        [type.name]);
    return (r.first['n'] as num).toInt();
  }

  /// ينشئ سنداً وقيده في معاملة واحدة.
  ///
  /// [cashBoxId] الصندوق المعني (المصدر في التحويل).
  /// [accountId] الحساب المقابل (مصروف/إيراد/أي حساب) — غير مطلوب للتحويل.
  Future<int> create({
    required VoucherType type,
    required double amount,
    required DateTime date,
    required int cashBoxId,
    int? toCashBoxId,
    int? accountId,
    String? description,
    String? reference,
    int branchId = 1,
    int? userId,
  }) async {
    if (amount <= 0) throw LedgerException('المبلغ يجب أن يكون أكبر من صفر');
    await PeriodLock.assertOpen(date);
    final db = await _getDb();
    final newId = await db.transaction((txn) async {
      final box = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId]);
      if (box.isEmpty) throw LedgerException('الصندوق غير موجود');
      final boxAcc = box.first['account_id'] as int;

      final int counterAcc;
      if (type == VoucherType.transfer) {
        if (toCashBoxId == null || toCashBoxId == cashBoxId) {
          throw LedgerException('اختر صندوقاً مختلفاً للتحويل إليه');
        }
        final to = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [toCashBoxId]);
        if (to.isEmpty) throw LedgerException('الصندوق المحوَّل إليه غير موجود');
        counterAcc = to.first['account_id'] as int;
      } else if (type == VoucherType.opening) {
        counterAcc = await Ledger.systemAccountId(txn, 'opening_equity');
      } else {
        if (accountId == null) throw LedgerException('اختر الحساب');
        final a = await txn.query('accounts', where: 'id = ?', whereArgs: [accountId]);
        if (a.isEmpty) throw LedgerException('الحساب غير موجود');
        if ((a.first['is_group'] as int) == 1) {
          throw LedgerException('«${a.first['name']}» حساب رئيسي — اختر حساباً فرعياً');
        }
        if ((a.first['is_control'] as int) == 1) {
          throw LedgerException(
              'ديون العملاء والموردين تُسجَّل من سجل الديون وشاشة الموردين، لا من السندات');
        }
        if (type == VoucherType.expense && a.first['type'] != 'expense') {
          throw LedgerException('سند المصروف يجب أن يكون على حساب مصروف');
        }
        if (type == VoucherType.income && a.first['type'] != 'revenue') {
          throw LedgerException('سند الإيراد يجب أن يكون على حساب إيراد');
        }
        counterAcc = accountId;
      }

      final number = await _nextNumber(txn, type);
      final id = await txn.insert('vouchers', {
        'voucher_number': number,
        'voucher_type': type.name,
        'voucher_date': date.toIso8601String(),
        'amount': roundMoney(amount),
        'cash_box_id': cashBoxId,
        'to_cash_box_id': toCashBoxId,
        'account_id': type == VoucherType.transfer ? null : counterAcc,
        'description': description,
        'reference': reference,
        'branch_id': branchId,
        'created_by_user_id': userId,
        'created_at': DateTime.now().toIso8601String(),
      });

      // المال يدخل الصندوق: قبض، إيراد، رصيد افتتاحي، والوجهة في التحويل.
      final List<JournalLineInput> lines;
      switch (type) {
        case VoucherType.expense:
        case VoucherType.payment:
          lines = [
            JournalLineInput(accountId: counterAcc, debit: amount),
            JournalLineInput(accountId: boxAcc, credit: amount),
          ];
          break;
        case VoucherType.income:
        case VoucherType.receipt:
        case VoucherType.opening:
          lines = [
            JournalLineInput(accountId: boxAcc, debit: amount),
            JournalLineInput(accountId: counterAcc, credit: amount),
          ];
          break;
        case VoucherType.transfer:
          lines = [
            JournalLineInput(accountId: counterAcc, debit: amount),
            JournalLineInput(accountId: boxAcc, credit: amount),
          ];
          break;
      }
      await Ledger.writeEntry(txn,
          sourceType: 'voucher',
          sourceId: id,
          sourceHash: 'v1',
          date: date,
          description:
              '${voucherTypeLabels[type]} رقم $number${description == null || description.isEmpty ? '' : ' — $description'}',
          lines: lines,
          branchId: branchId,
          userId: userId);
      return id;
    });
    ActivityLog.log('إنشاء', 'السندات',
        '${voucherTypeLabels[type]} #$newId — ${roundMoney(amount)}${description == null || description.isEmpty ? '' : ' — $description'}');
    return newId;
  }

  /// حذف سند = حذف منطقي + حذف قيده (يبقى في السجل لمن يراجع).
  Future<void> delete(int voucherId, {int? userId}) async {
    final db = await _getDb();
    final v = await db.query('vouchers', columns: ['voucher_date'], where: 'id = ?', whereArgs: [voucherId], limit: 1);
    if (v.isNotEmpty) await PeriodLock.assertOpen(DateTime.parse(v.first['voucher_date'] as String));
    await db.transaction((txn) async {
      await txn.update(
        'vouchers',
        {
          'is_deleted': 1,
          'deleted_at': DateTime.now().toIso8601String(),
          'deleted_by_user_id': userId,
        },
        where: 'id = ?',
        whereArgs: [voucherId],
      );
      await Ledger.deleteBySource(txn, 'voucher', voucherId);
    });
    ActivityLog.log('حذف', 'السندات', 'حذف سند #$voucherId');
  }

  Future<List<Map<String, Object?>>> list({
    DateTime? from,
    DateTime? to,
    VoucherType? type,
    bool includeDeleted = false,
  }) async {
    final db = await _getDb();
    final where = <String>[];
    final args = <Object?>[];
    if (!includeDeleted) where.add('v.is_deleted = 0');
    if (type != null) {
      where.add('v.voucher_type = ?');
      args.add(type.name);
    } else {
      // السندات المركّبة لها شاشتها الخاصة
      where.add("v.voucher_type IN (${VoucherType.values.map((t) => "'${t.name}'").join(', ')})");
    }
    if (from != null) {
      where.add('v.voucher_date >= ?');
      args.add(DateTime(from.year, from.month, from.day).toIso8601String());
    }
    if (to != null) {
      where.add('v.voucher_date < ?');
      args.add(DateTime(to.year, to.month, to.day).add(const Duration(days: 1)).toIso8601String());
    }
    return db.rawQuery('''
      SELECT v.*, b.name AS cash_box_name, tb.name AS to_cash_box_name,
             a.code AS account_code, a.name AS account_name
      FROM vouchers v
      LEFT JOIN cash_boxes b ON b.id = v.cash_box_id
      LEFT JOIN cash_boxes tb ON tb.id = v.to_cash_box_id
      LEFT JOIN accounts a ON a.id = v.account_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY v.voucher_date DESC, v.id DESC
    ''', args);
  }
}
