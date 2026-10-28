// lib/erp/control/fixed_assets_service.dart
//
// 🏢 الأصول الثابتة والإهلاك.
//
// القيود (كلها مشتقة في ErpPosting من حالة يضعها المستخدم صراحة):
//   • شراء الأصل (asset_acq):
//       من صندوق   ⇒ مدين حساب الأصل / دائن الصندوق.
//       رصيد افتتاحي ⇒ مدين حساب الأصل / دائن الأرصدة الافتتاحية.
//       مسجّل مسبقاً (سند صرف سابق) ⇒ لا قيد (لا ازدواج).
//   • إهلاك شهر (depreciation): مدين مصروف الإهلاك / دائن مجمع الإهلاك — قيد واحد للشهر،
//     لا يُنشأ إلا بضغطة «إهلاك شهر …» من المستخدم.
//   • استبعاد/بيع (asset_disp): مدين الصندوق (المقبوض) + مدين مجمع الإهلاك /
//     دائن حساب الأصل (الكلفة)، والفرق إلى «أرباح وخسائر استبعاد الأصول».
//
// قواعد الأمان:
//   • لا تعديل لمبالغ أصل بعد إهلاكه (يُلغى الإهلاك أولاً)؛ الاسم والملاحظات فقط.
//   • لا إهلاك لشهر مرتين؛ ولا يتجاوز المجمّع (الكلفة − الخردة).
//   • الفترة المثبّتة تمنع كل ما بتاريخ داخلها.
//   • لا استبعاد وفيه إهلاك لشهر الاستبعاد أو بعده.

import 'package:sqflite/sqflite.dart';

import '../../accounting/ledger.dart';
import '../../models/app_user.dart' show AppPermissions;
import '../../services/auth_service.dart';
import '../activity/activity_log.dart';
import '../erp_common.dart';
import 'control_common.dart';
import 'depreciation_math.dart';

class AssetFunding {
  AssetFunding._();
  static const box = 'box'; // دُفع من صندوق الآن
  static const opening = 'opening'; // أصل قديم: رصيد افتتاحي
  static const already = 'already'; // سُجّل دفعه سابقاً بسند صرف

  static String label(String f) => switch (f) {
        box => 'دُفع من صندوق',
        opening => 'رصيد افتتاحي (أصل قديم)',
        already => 'مسجّل مسبقاً بسند صرف',
        _ => f,
      };
}

class FixedAsset {
  FixedAsset.fromRow(Map<String, Object?> r, {this.accumulated = 0})
      : id = r['id'] as int,
        no = (r['asset_no'] as num).toInt(),
        name = '${r['name']}',
        category = r['category'] as String?,
        acquiredOn = parseDate(r['acquired_on']),
        cost = d0(r['cost']),
        salvage = d0(r['salvage']),
        lifeMonths = (r['life_months'] as num).toInt(),
        depStart = '${r['dep_start']}',
        assetAccountId = r['asset_account_id'] as int?,
        funding = (r['funding'] as String?) ?? AssetFunding.already,
        fundingBoxId = r['funding_box_id'] as int?,
        status = (r['status'] as String?) ?? 'active',
        disposedOn = r['disposed_on'] == null ? null : parseDate(r['disposed_on']),
        disposalAmount = r['disposal_amount'] == null ? null : d0(r['disposal_amount']),
        disposalBoxId = r['disposal_box_id'] as int?,
        notes = r['notes'] as String?;

  final int id;
  final int no;
  final String name;
  final String? category;
  final DateTime acquiredOn;
  final double cost;
  final double salvage;
  final int lifeMonths;
  final String depStart;
  final int? assetAccountId;
  final String funding;
  final int? fundingBoxId;
  final String status;
  final DateTime? disposedOn;
  final double? disposalAmount;
  final int? disposalBoxId;
  final String? notes;
  final double accumulated;

  bool get disposed => status == 'disposed';
  double get book => bookValue(cost: cost, accumulated: accumulated);
  double get monthly => monthlyDepreciation(cost: cost, salvage: salvage, lifeMonths: lifeMonths);
  bool get fullyDepreciated => accumulated >= (cost - salvage) - 0.01;
}

class DepreciationRun {
  DepreciationRun.fromRow(Map<String, Object?> r)
      : id = r['id'] as int,
        period = '${r['period']}',
        total = d0(r['total']),
        status = '${r['status']}',
        createdBy = r['created_by'] as String?,
        createdAt = parseDate(r['created_at']);
  final int id;
  final String period;
  final double total;
  final String status;
  final String? createdBy;
  final DateTime createdAt;
}

class FixedAssetsService {
  FixedAssetsService._();

  static void _guard() {
    final auth = AuthService();
    if (auth.currentUser != null && !auth.hasPermission(AppPermissions.accountingPost)) {
      throw ErpException('الأصول الثابتة تحتاج صلاحية «السندات والقيود اليدوية»');
    }
  }

  /// مجمّع إهلاك كل أصل من التشغيلات المرحّلة.
  static Future<Map<int, double>> accumulatedByAsset(DatabaseExecutor db, {String? beforePeriod}) async {
    final rows = await db.rawQuery('''
      SELECT l.asset_id AS a, COALESCE(SUM(l.amount), 0) AS s
      FROM depreciation_lines l JOIN depreciation_runs r ON r.id = l.run_id
      WHERE r.status = 'posted' ${beforePeriod == null ? '' : 'AND r.period < ?'}
      GROUP BY l.asset_id''', [if (beforePeriod != null) beforePeriod]);
    return {for (final r in rows) r['a'] as int: d0(r['s'])};
  }

  static Future<List<FixedAsset>> list({bool includeDisposed = true}) async {
    final db = await controlDb();
    final acc = await accumulatedByAsset(db);
    final rows = await db.query('fixed_assets',
        where: includeDisposed ? null : "status = 'active'", orderBy: 'asset_no DESC');
    return [for (final r in rows) FixedAsset.fromRow(r, accumulated: acc[r['id'] as int] ?? 0)];
  }

  /// الحساب الافتراضي للأصل: أول حساب غير تجميعي تحت «الأصول الثابتة» عدا مجمع الإهلاك.
  static Future<int?> defaultAssetAccount(DatabaseExecutor db) async {
    final r = await db.rawQuery('''
      SELECT a.id FROM accounts a JOIN accounts p ON p.id = a.parent_id
      WHERE p.code = '14' AND a.is_group = 0 AND COALESCE(a.is_active, 1) = 1
        AND COALESCE(a.system_key, '') <> 'accum_depreciation'
      ORDER BY a.code LIMIT 1''');
    return r.isEmpty ? null : r.first['id'] as int;
  }

  /// حسابات يمكن أن يُسجّل عليها أصل (تحت «الأصول الثابتة»).
  static Future<List<Map<String, Object?>>> assetAccounts() async {
    final db = await controlDb();
    return db.rawQuery('''
      SELECT a.id, a.code, a.name FROM accounts a JOIN accounts p ON p.id = a.parent_id
      WHERE p.code = '14' AND a.is_group = 0 AND COALESCE(a.is_active, 1) = 1
        AND COALESCE(a.system_key, '') <> 'accum_depreciation'
      ORDER BY a.code''');
  }

  static void _validate({required double cost, required double salvage, required int lifeMonths}) {
    if (cost <= 0) throw ErpException('كلفة الأصل يجب أن تكون أكبر من صفر');
    if (salvage < 0) throw ErpException('قيمة الخردة لا تكون سالبة');
    if (salvage >= cost) throw ErpException('قيمة الخردة يجب أن تكون أقل من الكلفة');
    if (lifeMonths < 1 || lifeMonths > 1200) throw ErpException('العمر بالأشهر بين 1 و1200');
  }

  static Future<int> create({
    required String name,
    String? category,
    required DateTime acquiredOn,
    required double cost,
    double salvage = 0,
    required int lifeMonths,
    String? depStart,
    int? assetAccountId,
    required String funding,
    int? fundingBoxId,
    String? notes,
  }) async {
    _guard();
    if (name.trim().isEmpty) throw ErpException('اكتب اسم الأصل');
    _validate(cost: cost, salvage: salvage, lifeMonths: lifeMonths);
    if (funding == AssetFunding.box && fundingBoxId == null) throw ErpException('اختر الصندوق الذي دُفع منه');
    final start = depStart ?? periodOf(acquiredOn);
    if (!validPeriod(start)) throw ErpException('شهر بدء الإهلاك غير صحيح (YYYY-MM)');
    if (start.compareTo(periodOf(acquiredOn)) < 0) throw ErpException('لا يبدأ الإهلاك قبل شهر الشراء');
    final db = await controlDb();
    final id = await db.transaction((txn) async {
      if (funding != AssetFunding.already) await PeriodLock.assertOpen(acquiredOn, txn);
      final acc = assetAccountId ?? await defaultAssetAccount(txn);
      if (acc == null) throw ErpException('لا يوجد حساب أصول ثابتة في الشجرة');
      final no = await nextDocNumber(txn, 'fixed_assets', 'asset_no');
      return txn.insert('fixed_assets', {
        'asset_no': no,
        'name': name.trim(),
        'category': (category ?? '').trim().isEmpty ? null : category!.trim(),
        'acquired_on': isoDay(acquiredOn),
        'cost': round2(cost),
        'salvage': round2(salvage),
        'life_months': lifeMonths,
        'dep_start': start,
        'asset_account_id': acc,
        'funding': funding,
        'funding_box_id': funding == AssetFunding.box ? fundingBoxId : null,
        'status': 'active',
        'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
        'created_by': currentUserName(),
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    ActivityLog.log('إضافة', 'الأصول الثابتة', 'أصل «${name.trim()}» بكلفة ${cost.round()} (${AssetFunding.label(funding)})')
        .catchError((_) {});
    return id;
  }

  static Future<bool> hasDepreciation(DatabaseExecutor db, int assetId) async {
    final r = await db.rawQuery('''
      SELECT 1 FROM depreciation_lines l JOIN depreciation_runs r ON r.id = l.run_id
      WHERE l.asset_id = ? AND r.status = 'posted' LIMIT 1''', [assetId]);
    return r.isNotEmpty;
  }

  /// تعديل الاسم والفئة والملاحظات (دائماً مسموح).
  static Future<void> rename(int id, {required String name, String? category, String? notes}) async {
    _guard();
    if (name.trim().isEmpty) throw ErpException('اكتب اسم الأصل');
    final db = await controlDb();
    await db.update(
        'fixed_assets',
        {
          'name': name.trim(),
          'category': (category ?? '').trim().isEmpty ? null : category!.trim(),
          'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  /// حذف أصل أُدخل خطأً: فقط إن لم يُهلك ولم يُستبعد.
  static Future<void> delete(int id) async {
    _guard();
    final db = await controlDb();
    await db.transaction((txn) async {
      final r = await txn.query('fixed_assets', where: 'id = ?', whereArgs: [id], limit: 1);
      if (r.isEmpty) return;
      final a = FixedAsset.fromRow(r.first);
      if (a.disposed) throw ErpException('أصل مستبعد — لا يُحذف');
      if (await hasDepreciation(txn, id)) throw ErpException('على الأصل إهلاك مرحّل — ألغِ تشغيلات الإهلاك أولاً');
      if (a.funding != AssetFunding.already) await PeriodLock.assertOpen(a.acquiredOn, txn);
      await txn.delete('fixed_assets', where: 'id = ?', whereArgs: [id]);
    });
    ActivityLog.log('حذف', 'الأصول الثابتة', 'أصل رقم $id').catchError((_) {});
  }

  // ───────────────────────── الإهلاك ─────────────────────────

  /// معاينة إهلاك شهر: (الأصل، القسط) لكل أصل له قسط.
  static Future<List<(FixedAsset, double)>> preview(String period) async {
    if (!validPeriod(period)) throw ErpException('الشهر غير صحيح');
    final db = await controlDb();
    final acc = await accumulatedByAsset(db);
    final rows = await db.query('fixed_assets');
    final out = <(FixedAsset, double)>[];
    for (final r in rows) {
      final a = FixedAsset.fromRow(r, accumulated: acc[r['id'] as int] ?? 0);
      final amt = depreciationFor(
        period: period,
        startPeriod: a.depStart,
        disposedPeriod: a.disposedOn == null ? null : periodOf(a.disposedOn!),
        cost: a.cost,
        salvage: a.salvage,
        lifeMonths: a.lifeMonths,
        accumulated: a.accumulated,
      );
      if (amt > 0) out.add((a, amt));
    }
    return out;
  }

  static Future<bool> periodPosted(DatabaseExecutor db, String period) async {
    final r = await db.query('depreciation_runs',
        columns: ['id'], where: "period = ? AND status = 'posted'", whereArgs: [period], limit: 1);
    return r.isNotEmpty;
  }

  /// يرحّل إهلاك شهر واحد. يعيد معرّف التشغيل.
  static Future<int> runPeriod(String period) async {
    _guard();
    if (!validPeriod(period)) throw ErpException('الشهر غير صحيح');
    final end = periodEnd(period);
    final today = DateTime.now();
    if (periodStart(period).isAfter(DateTime(today.year, today.month, today.day))) {
      throw ErpException('لا يُهلك شهر لم يبدأ بعد');
    }
    final db = await controlDb();
    final runId = await db.transaction((txn) async {
      await PeriodLock.assertOpen(end, txn);
      if (await periodPosted(txn, period)) throw ErpException('إهلاك $period مرحّل سابقاً');
      final acc = await accumulatedByAsset(txn);
      final rows = await txn.query('fixed_assets');
      final lines = <(int, double)>[];
      for (final r in rows) {
        final a = FixedAsset.fromRow(r, accumulated: acc[r['id'] as int] ?? 0);
        final amt = depreciationFor(
          period: period,
          startPeriod: a.depStart,
          disposedPeriod: a.disposedOn == null ? null : periodOf(a.disposedOn!),
          cost: a.cost,
          salvage: a.salvage,
          lifeMonths: a.lifeMonths,
          accumulated: a.accumulated,
        );
        if (amt > 0) lines.add((a.id, amt));
      }
      if (lines.isEmpty) throw ErpException('لا يوجد ما يُهلك في $period');
      final total = round2(lines.fold<double>(0, (s, l) => s + l.$2));
      final id = await txn.insert('depreciation_runs', {
        'period': period,
        'run_date': isoDay(end),
        'total': total,
        'status': 'posted',
        'created_by': currentUserName(),
        'created_at': DateTime.now().toIso8601String(),
      });
      for (final l in lines) {
        await txn.insert('depreciation_lines', {'run_id': id, 'asset_id': l.$1, 'amount': l.$2});
      }
      return id;
    });
    ActivityLog.log('ترحيل', 'الأصول الثابتة', 'إهلاك شهر $period').catchError((_) {});
    return runId;
  }

  static Future<List<DepreciationRun>> runs() async {
    final db = await controlDb();
    final rows = await db.query('depreciation_runs', orderBy: 'period DESC, id DESC');
    return rows.map(DepreciationRun.fromRow).toList();
  }

  /// إلغاء تشغيل إهلاك (يُحذف قيده عند الترحيل التالي). لا يُلغى إن كان بعده
  /// استبعاد لأصل فيه (لأن قيد الاستبعاد بُني على المجمّع).
  static Future<void> voidRun(int runId) async {
    _guard();
    final db = await controlDb();
    await db.transaction((txn) async {
      final r = await txn.query('depreciation_runs', where: 'id = ?', whereArgs: [runId], limit: 1);
      if (r.isEmpty) return;
      final run = DepreciationRun.fromRow(r.first);
      if (run.status != 'posted') return;
      await PeriodLock.assertOpen(periodEnd(run.period), txn);
      final blocked = await txn.rawQuery('''
        SELECT a.name FROM depreciation_lines l JOIN fixed_assets a ON a.id = l.asset_id
        WHERE l.run_id = ? AND a.status = 'disposed' LIMIT 1''', [runId]);
      if (blocked.isNotEmpty) {
        throw ErpException('الأصل «${blocked.first['name']}» مستبعد بعد هذا الإهلاك — ألغِ الاستبعاد أولاً');
      }
      await txn.update('depreciation_runs', {'status': 'void'}, where: 'id = ?', whereArgs: [runId]);
    });
    ActivityLog.log('إلغاء', 'الأصول الثابتة', 'إلغاء إهلاك تشغيل رقم $runId').catchError((_) {});
  }

  // ───────────────────────── الاستبعاد ─────────────────────────

  static Future<void> dispose(int assetId, {required DateTime on, required double proceeds, int? boxId}) async {
    _guard();
    if (proceeds < 0) throw ErpException('المقبوض لا يكون سالباً');
    if (proceeds > 0 && boxId == null) throw ErpException('اختر الصندوق الذي قُبض فيه ثمن الأصل');
    final db = await controlDb();
    await db.transaction((txn) async {
      await PeriodLock.assertOpen(on, txn);
      final r = await txn.query('fixed_assets', where: 'id = ?', whereArgs: [assetId], limit: 1);
      if (r.isEmpty) throw ErpException('الأصل غير موجود');
      final a = FixedAsset.fromRow(r.first);
      if (a.disposed) throw ErpException('الأصل مستبعد سابقاً');
      if (on.isBefore(a.acquiredOn)) throw ErpException('تاريخ الاستبعاد قبل تاريخ الشراء');
      final later = await txn.rawQuery('''
        SELECT r.period FROM depreciation_lines l JOIN depreciation_runs r ON r.id = l.run_id
        WHERE l.asset_id = ? AND r.status = 'posted' AND r.period >= ? LIMIT 1''', [assetId, periodOf(on)]);
      if (later.isNotEmpty) {
        throw ErpException('على الأصل إهلاك لشهر ${later.first['period']} (شهر الاستبعاد أو بعده) — ألغِه أولاً');
      }
      await txn.update(
          'fixed_assets',
          {
            'status': 'disposed',
            'disposed_on': isoDay(on),
            'disposal_amount': round2(proceeds),
            'disposal_box_id': proceeds > 0 ? boxId : null,
          },
          where: 'id = ?',
          whereArgs: [assetId]);
    });
    ActivityLog.log('استبعاد', 'الأصول الثابتة', 'أصل رقم $assetId بمبلغ ${proceeds.round()}').catchError((_) {});
  }

  /// إلغاء استبعاد (خطأ إدخال).
  static Future<void> undispose(int assetId) async {
    _guard();
    final db = await controlDb();
    await db.transaction((txn) async {
      final r = await txn.query('fixed_assets', where: 'id = ?', whereArgs: [assetId], limit: 1);
      if (r.isEmpty) return;
      final a = FixedAsset.fromRow(r.first);
      if (!a.disposed || a.disposedOn == null) return;
      await PeriodLock.assertOpen(a.disposedOn!, txn);
      await txn.update(
          'fixed_assets',
          {'status': 'active', 'disposed_on': null, 'disposal_amount': null, 'disposal_box_id': null},
          where: 'id = ?',
          whereArgs: [assetId]);
    });
    ActivityLog.log('إلغاء', 'الأصول الثابتة', 'إلغاء استبعاد أصل رقم $assetId').catchError((_) {});
  }

  /// رصيد مجمع الإهلاك في الدفتر (للمطابقة مع السجل).
  static Future<double> ledgerAccumulated() async {
    final db = await controlDb();
    try {
      final id = await Ledger.systemAccountId(db, 'accum_depreciation');
      final r = await db.rawQuery(
          'SELECT COALESCE(SUM(credit - debit), 0) AS b FROM journal_lines WHERE account_id = ?', [id]);
      return d0(r.first['b']);
    } catch (_) {
      return 0;
    }
  }
}
