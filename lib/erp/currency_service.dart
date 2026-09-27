// lib/erp/currency_service.dart
//
// 💱 العملات وسجل أسعار الصرف (مثل «إدخال العملات» و«حركة العملات» في الإداري).
//
// السعر = كم ديناراً تساوي وحدة واحدة من العملة. السعر المعتمد لأي عملية هو
// آخر سعر مسجَّل بتاريخ لا يتجاوز تاريخ العملية؛ فتغيير السعر اليوم لا يغيّر
// قيود الأمس.

import 'package:sqflite/sqflite.dart';

import '../accounting/ledger.dart';
import 'erp_common.dart';

class Currency {
  Currency({
    required this.code,
    required this.name,
    this.symbol,
    this.fractionName,
    this.decimals = 0,
    this.rate = 1,
    this.isBase = false,
    this.divide = false,
    this.isActive = true,
  });
  final String code;
  final String name;
  final String? symbol;
  final String? fractionName;
  final int decimals;
  final double rate;
  final bool isBase;
  final bool divide;
  final bool isActive;

  factory Currency.fromMap(Map<String, Object?> m) => Currency(
        code: m['code'] as String,
        name: m['name'] as String,
        symbol: m['symbol'] as String?,
        fractionName: m['fraction_name'] as String?,
        decimals: (m['decimals'] as int?) ?? 0,
        rate: d0(m['rate']) <= 0 ? 1 : d0(m['rate']),
        isBase: (m['is_base'] as int? ?? 0) == 1,
        divide: (m['divide'] as int? ?? 0) == 1,
        isActive: (m['is_active'] as int? ?? 1) == 1,
      );

  @override
  String toString() => '$name ($code)';
}

class CurrencyService {
  static const String base = 'IQD';

  Future<List<Currency>> all({bool activeOnly = true}) async {
    final db = await erpDb();
    final r = await db.query('currencies',
        where: activeOnly ? 'is_active = 1' : null, orderBy: 'is_base DESC, code');
    return r.map(Currency.fromMap).toList();
  }

  Future<Currency?> byCode(String code) async {
    final db = await erpDb();
    final r = await db.query('currencies', where: 'code = ?', whereArgs: [code], limit: 1);
    return r.isEmpty ? null : Currency.fromMap(r.first);
  }

  /// سعر العملة في تاريخ معيّن (آخر سعر مسجَّل حتى نهاية ذلك اليوم).
  static Future<double> rateAt(DatabaseExecutor db, String code, DateTime date) async {
    if (code == base) return 1;
    final r = await db.rawQuery(
        'SELECT rate FROM currency_rates WHERE code = ? AND rate_date < ? ORDER BY rate_date DESC, id DESC LIMIT 1',
        [code, isoDayAfter(date)]);
    if (r.isNotEmpty) {
      final v = d0(r.first['rate']);
      if (v > 0) return v;
    }
    final c = await db.query('currencies', columns: ['rate'], where: 'code = ?', whereArgs: [code], limit: 1);
    if (c.isNotEmpty && d0(c.first['rate']) > 0) return d0(c.first['rate']);
    if (code == 'USD') return Ledger.usdRate(db);
    return 1;
  }

  Future<void> save(Currency c, {bool isNew = false}) async {
    if (c.code.trim().isEmpty || c.name.trim().isEmpty) {
      throw ErpException('اكتب رمز العملة واسمها');
    }
    if (c.rate <= 0) throw ErpException('سعر التعادل يجب أن يكون أكبر من صفر');
    final db = await erpDb();
    await db.transaction((txn) async {
      final exists = await txn.query('currencies',
          columns: ['code', 'rate'], where: 'code = ?', whereArgs: [c.code], limit: 1);
      if (isNew && exists.isNotEmpty) throw ErpException('العملة ${c.code} موجودة');
      final row = {
        'code': c.code.trim().toUpperCase(),
        'name': c.name.trim(),
        'symbol': c.symbol,
        'fraction_name': c.fractionName,
        'decimals': c.decimals,
        'rate': c.code == base ? 1.0 : c.rate,
        'is_base': c.code == base ? 1 : 0,
        'divide': c.divide ? 1 : 0,
        'is_active': c.isActive ? 1 : 0,
      };
      if (exists.isEmpty) {
        await txn.insert('currencies', row);
        await _addRate(txn, row['code'] as String, c.rate, DateTime.now());
      } else {
        final old = d0(exists.first['rate']);
        await txn.update('currencies', row, where: 'code = ?', whereArgs: [c.code]);
        if ((old - c.rate).abs() > 1e-9 && c.code != base) {
          await _addRate(txn, c.code, c.rate, DateTime.now());
        }
      }
    });
  }

  /// تسجيل سعر جديد بتاريخ (يُحدِّث السعر الحالي إن كان التاريخ اليوم أو بعده).
  Future<void> setRate(String code, double rate, DateTime date) async {
    if (code == base) return;
    if (rate <= 0) throw ErpException('السعر يجب أن يكون أكبر من صفر');
    // سعر بتاريخ داخل فترة مثبّتة يغيّر قيود مستندات مثبّتة بالدولار
    await PeriodLock.assertOpen(date);
    final db = await erpDb();
    await db.transaction((txn) async {
      await _addRate(txn, code, rate, date);
      final latest = await txn.rawQuery(
          'SELECT rate FROM currency_rates WHERE code = ? ORDER BY rate_date DESC, id DESC LIMIT 1', [code]);
      if (latest.isNotEmpty) {
        await txn.update('currencies', {'rate': d0(latest.first['rate'])},
            where: 'code = ?', whereArgs: [code]);
      }
    });
  }

  static Future<void> _addRate(DatabaseExecutor db, String code, double rate, DateTime date) async {
    await db.insert('currency_rates', {
      'code': code,
      'rate': rate,
      'rate_date': isoDay(date),
      'created_at': DateTime.now().toIso8601String(),
    });
    // التوافق مع الكود السابق: إعداد usd_rate يتبع آخر سعر للدولار
    if (code == 'USD') {
      final latest = await db.rawQuery(
          "SELECT rate FROM currency_rates WHERE code = 'USD' ORDER BY rate_date DESC, id DESC LIMIT 1");
      if (latest.isNotEmpty) {
        await Ledger.setSetting(db, 'usd_rate', d0(latest.first['rate']).toString());
      }
    }
  }

  Future<List<Map<String, Object?>>> history({String? code}) async {
    final db = await erpDb();
    return db.query('currency_rates',
        where: code == null ? null : 'code = ?',
        whereArgs: code == null ? null : [code],
        orderBy: 'rate_date DESC, id DESC',
        limit: 500);
  }

  Future<void> deleteRate(int id) async {
    final db = await erpDb();
    final one = await db.query('currency_rates', columns: ['rate_date'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (one.isNotEmpty) await PeriodLock.assertOpen(parseDate(one.first['rate_date']));
    await db.transaction((txn) async {
      final r = await txn.query('currency_rates', where: 'id = ?', whereArgs: [id], limit: 1);
      if (r.isEmpty) return;
      final code = r.first['code'] as String;
      final n = await txn.rawQuery('SELECT COUNT(*) AS n FROM currency_rates WHERE code = ?', [code]);
      if (((n.first['n'] as num?) ?? 0) <= 1) {
        throw ErpException('لا يمكن حذف آخر سعر مسجَّل للعملة');
      }
      await txn.delete('currency_rates', where: 'id = ?', whereArgs: [id]);
      final latest = await txn.rawQuery(
          'SELECT rate FROM currency_rates WHERE code = ? ORDER BY rate_date DESC, id DESC LIMIT 1', [code]);
      if (latest.isNotEmpty) {
        await txn.update('currencies', {'rate': d0(latest.first['rate'])}, where: 'code = ?', whereArgs: [code]);
        if (code == 'USD') await Ledger.setSetting(txn, 'usd_rate', d0(latest.first['rate']).toString());
      }
    });
  }

  /// تحويل مبلغ بعملة إلى الدينار.
  static double toBase(double amount, double rate, {bool divide = false}) =>
      roundMoney(divide ? amount / rate : amount * rate);
}
