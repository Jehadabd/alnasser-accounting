// lib/services/fifo_cost.dart
//
// 📦 الكلفة بطريقة FIFO (الوارد أولاً يُباع أولاً — معتمدة في IAS 2).
//
//   مثال: 10 قطع بـ1000 ثم 10 بـ1100 ⇒ أول 10 تُباع بكلفة 1000، والتالية بـ1100.
//
//   • طبقات الكلفة (cost_layers): كل «تأكيد واستلام» لفاتورة شراء يسجّل طبقة
//     (الكمية بالأساسية وكلفتها بالدينار) لكل المواد — لأي طريقة — حتى يعمل FIFO متى اخترته.
//     أول طبقة لمادة تُسبق بطبقة «افتتاحية» = رصيدها قبل الشراء بكلفتها حينها.
//     تعديل/إلغاء فاتورة الشراء يحذف طبقاتها.
//   • الباقي من كل طبقة يُشتق من رصيد المادة الحالي (كما في دفعات الصلاحية): الرصيد
//     يُنسب للطبقات الأحدث، فالأقدم الباقية هي التي تُباع أولاً. لا عدّاد يُستهلك ⇒
//     المرتجعات والجرد والتالف لا تُفسد شيئاً.
//   • البيع: كلفة السطر = كلفة أقدم الكميات الباقية بعدد ما بيع (والأسطر المتعددة للمادة
//     نفسها في الفاتورة تُحسب متتابعة). ثم كلفة المادة = قيمة الباقي ÷ الرصيد.
//   • مادة بلا طبقات بعد (لم تُشترَ منذ هذا التحديث): كلفتها الحالية كما هي.
//   • الطبقات محلية على هذا الجهاز؛ جهاز آخر يبيع بكلفة المادة المتزامنة (متوسط الباقي).

import 'dart:convert';

import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../erp/inventory/usd_cost_service.dart';
import 'cost_method_policy.dart';
import 'settings_manager.dart';

class CostLayer {
  CostLayer(this.qty, this.cost);
  final double qty;
  final double cost;
}

class FifoCost {
  FifoCost._();

  static bool _ready = false;

  static Future<void> ensure(DatabaseExecutor d) async {
    if (_ready) return;
    await d.execute('''
      CREATE TABLE IF NOT EXISTS cost_layers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        layer_date TEXT NOT NULL,
        qty REAL NOT NULL,
        unit_cost REAL NOT NULL,
        source TEXT NOT NULL,
        ref_id INTEGER,
        created_at TEXT NOT NULL
      )''');
    await d.execute('CREATE INDEX IF NOT EXISTS idx_cost_layers_product ON cost_layers(product_id, layer_date)');
    _ready = true;
  }

  static double _d(Object? v) => (v as num?)?.toDouble() ?? double.tryParse('${v ?? ''}') ?? 0;

  // ─────────────────────────── الشراء ───────────────────────────

  /// بعد تحديث كلفة المادة في «تأكيد واستلام»: طبقة لهذا الشراء.
  static Future<void> recordPurchase(DatabaseExecutor d,
      {required int productId,
      required int? invoiceId,
      required DateTime date,
      required double qty,
      required double unitCostIqd,
      required double stockBefore,
      required double costBefore}) async {
    if (qty <= 0) return;
    await ensure(d);
    final now = DateTime.now().toIso8601String();
    final any = await d.query('cost_layers', columns: ['id'], where: 'product_id = ?', whereArgs: [productId], limit: 1);
    if (any.isEmpty && stockBefore > 0) {
      await d.insert('cost_layers', {
        'product_id': productId,
        'layer_date': '0000-01-01', // الرصيد السابق أقدم من أي شراء مسجّل
        'qty': stockBefore,
        'unit_cost': costBefore,
        'source': 'opening',
        'ref_id': null,
        'created_at': now,
      });
    }
    await d.insert('cost_layers', {
      'product_id': productId,
      'layer_date': date.toIso8601String(),
      'qty': qty,
      'unit_cost': unitCostIqd,
      'source': 'purchase',
      'ref_id': invoiceId,
      'created_at': now,
    });
  }

  /// تعديل/إلغاء فاتورة شراء: تُحذف طبقاتها (والجديدة تُسجَّل عند إعادة التأكيد).
  static Future<void> removePurchase(DatabaseExecutor d, int invoiceId, int productId) async {
    await ensure(d);
    await d.delete('cost_layers',
        where: "source = 'purchase' AND ref_id = ? AND product_id = ?", whereArgs: [invoiceId, productId]);
  }

  // ─────────────────────────── الحساب ───────────────────────────

  /// الطبقات الباقية لرصيد [stock] — من الأقدم إلى الأحدث. null = لا طبقات (FIFO غير متاح للمادة).
  static Future<List<CostLayer>?> remaining(DatabaseExecutor d, int productId, double stock, {double fallbackCost = 0}) async {
    await ensure(d);
    final rows = await d.query('cost_layers',
        columns: ['qty', 'unit_cost'], where: 'product_id = ?', whereArgs: [productId], orderBy: 'layer_date DESC, id DESC');
    if (rows.isEmpty) return null;
    final out = <CostLayer>[];
    var need = stock;
    for (final r in rows) {
      if (need <= 1e-9) break;
      final q = _d(r['qty']);
      final take = q < need ? q : need;
      out.add(CostLayer(take, _d(r['unit_cost'])));
      need -= take;
    }
    // رصيد أكثر من كل الطبقات (جرد زائد، مرتجع…) ⇒ الأقدم بكلفة أقدم طبقة
    if (need > 1e-9) out.add(CostLayer(need, rows.isEmpty ? fallbackCost : _d(rows.last['unit_cost'])));
    return out.reversed.toList();
  }

  /// كلفة الوحدة الأساسية لبيع [qty] بعد تجاوز [skip] (أسطر سابقة في الفاتورة نفسها).
  static double takeCost(List<CostLayer> layers, double qty, {double skip = 0}) {
    if (qty <= 0) return layers.isEmpty ? 0 : layers.first.cost;
    var s = skip, left = qty, value = 0.0;
    for (final l in layers) {
      var avail = l.qty;
      if (s > 0) {
        final k = s < avail ? s : avail;
        avail -= k;
        s -= k;
      }
      if (avail <= 0) continue;
      final t = left < avail ? left : avail;
      value += t * l.cost;
      left -= t;
      if (left <= 1e-9) break;
    }
    // بيع أكثر من الرصيد ⇒ الزائد بكلفة أحدث طبقة
    if (left > 1e-9) value += left * (layers.isEmpty ? 0 : layers.last.cost);
    return value / qty;
  }

  static double valueOf(List<CostLayer> layers) => layers.fold(0.0, (a, l) => a + l.qty * l.cost);

  // ─────────────────────────── البيع ───────────────────────────

  static Future<bool> isFifo(DatabaseExecutor d, int productId, String? global) async =>
      await CostMethodPolicy.effective(d, productId, global) == CostMethodPolicy.fifo;

  /// يضبط actual_cost_price لأسطر بيع لم تُدرج بعد (يعيد مواد FIFO التي لُمست).
  /// [sequential]: الأسطر ستُدرج واحداً واحداً والرصيد ينقص بعد كل سطر (لا إزاحة).
  static Future<Set<int>> applyToSaleLines(DatabaseExecutor d, List<Map<String, dynamic>> lines, {bool sequential = false}) async {
    final touched = <int>{};
    try {
      final global = (await SettingsManager.getAppSettings()).costingMethod;
      final taken = <int, double>{};
      final cache = <int, List<CostLayer>?>{};
      for (final m in lines) {
        final pid = await _productIdOf(d, m);
        if (pid == null || !await isFifo(d, pid, global)) continue;
        final large = _d(m['quantity_large_unit']) > 0;
        final units = large ? (_d(m['units_in_large_unit']) > 0 ? _d(m['units_in_large_unit']) : 1.0) : 1.0;
        final base = large ? _d(m['quantity_large_unit']) * units : _d(m['quantity_individual']);
        if (base <= 0) continue;
        if (sequential || !cache.containsKey(pid)) {
          final p = await d.query('products', columns: ['stock_quantity', 'cost_price'], where: 'id = ?', whereArgs: [pid], limit: 1);
          if (p.isEmpty) continue;
          cache[pid] = await remaining(d, pid, _d(p.first['stock_quantity']), fallbackCost: _d(p.first['cost_price']));
        }
        final layers = cache[pid];
        if (layers == null) continue; // لا طبقات بعد ⇒ كلفتها الحالية كما هي
        final unit = takeCost(layers, base, skip: sequential ? 0 : (taken[pid] ?? 0));
        taken[pid] = (taken[pid] ?? 0) + base;
        m['actual_cost_price'] = _round(unit * units);
        touched.add(pid);
      }
    } catch (_) {
      // FIFO اختياري: أي خلل ⇒ تبقى كلفة السطر كما حسبتها الشاشة
    }
    return touched;
  }

  /// بعد إدراج أسطر البيع: كلفة المادة = قيمة الباقي ÷ الرصيد (والوحدات الأكبر بالنسبة نفسها).
  static Future<void> refreshProducts(DatabaseExecutor d, Set<int> ids) async {
    for (final id in ids) {
      try {
        final p = await d.query('products', columns: ['stock_quantity', 'cost_price', 'unit_costs', 'unit'], where: 'id = ?', whereArgs: [id], limit: 1);
        if (p.isEmpty) continue;
        final stock = _d(p.first['stock_quantity']);
        final cur = _d(p.first['cost_price']);
        if (stock <= 0) continue; // لا رصيد ⇒ تبقى آخر كلفة (للبيع بلا رصيد)
        final layers = await remaining(d, id, stock, fallbackCost: cur);
        if (layers == null) continue;
        final next = _round(valueOf(layers) / stock);
        if ((next - cur).abs() < 0.005) continue;
        await UsdCostService.freezePastCosts(d, {id});
        final upd = <String, Object?>{'cost_price': next};
        final uc = p.first['unit_costs'] as String?;
        if (cur > 0 && uc != null && uc.isNotEmpty) {
          try {
            final m = Map<String, dynamic>.from(json.decode(uc) as Map);
            final ratio = next / cur;
            upd['unit_costs'] = json.encode({for (final e in m.entries) e.key: e.value is num ? _round((e.value as num) * ratio) : e.value});
          } catch (_) {}
        }
        await d.update('products', upd, where: 'id = ?', whereArgs: [id]);
      } catch (_) {}
    }
  }

  static double _round(num v) => (v * 100).roundToDouble() / 100;

  static Future<int?> _productIdOf(DatabaseExecutor d, Map<String, dynamic> m) async {
    final id = m['product_id'];
    if (id is int && id > 0) return id;
    final uuid = '${m['product_sync_uuid'] ?? ''}'.trim();
    if (uuid.isNotEmpty) {
      final r = await d.query('products', columns: ['id'], where: 'sync_uuid = ?', whereArgs: [uuid], limit: 1);
      if (r.isNotEmpty) return r.first['id'] as int;
    }
    final name = '${m['product_name'] ?? ''}'.trim();
    if (name.isEmpty) return null;
    final r = await d.query('products', columns: ['id'], where: 'name = ?', whereArgs: [name], limit: 1);
    return r.isEmpty ? null : r.first['id'] as int;
  }
}
