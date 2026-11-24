// lib/erp/stock_reservations.dart
//
// 📦 الحجز المؤقت للمسودّات المفتوحة (Soft allocation) — على نهج ERP.
//
// كيف تعمل الأنظمة العالمية (SAP «ATP»، Odoo «Forecasted / Reserved»، Dynamics
// «Available physical = On hand − Reserved»):
//   • الرصيد الفعلي (On hand) لا يتغير بمجرد كتابة المادة في فاتورة؛ يتغير عند
//     الترحيل (الحفظ) فقط — فالمسودة لا تمسّ دفتر المخزون ولا الحسابات.
//   • لكن «المتاح للبيع» = الفعلي − ما حجزته المستندات المفتوحة الأخرى. فلا يبيع
//     موظفان القطعة نفسها من فاتورتين مفتوحتين في الوقت نفسه.
//   • عند الترحيل فحص نهائي على الرصيد الفعلي من القاعدة لحظتها (الأول يحفظ يفوز):
//     يحمي من جهاز آخر على الشبكة باع المادة نفسها بين الكتابة والحفظ.
//
// هنا: كل شاشة بيع مفتوحة (إنشاء فاتورة، الكاشير) تسجّل أسطرها بالوحدة الأساسية
// باسم مسودّتها. المسودّة في الذاكرة فقط (لا قاعدة، لا مزامنة): تُغلق الشاشة ⇒ يزول حجزها.
// تعديل فاتورة محفوظة يحجز «الزيادة» فقط عمّا هو محفوظ (المحفوظ مطروح من الرصيد أصلاً).

import 'package:flutter/foundation.dart';

import '../models/invoice_item.dart';
import '../services/database_service.dart';

class StockReservations extends ChangeNotifier {
  StockReservations._();
  static final StockReservations instance = StockReservations._();

  /// مسودّة ← (مادة ← كمية أساسية محجوزة)
  final Map<String, Map<int, double>> _drafts = {};

  /// مسودّة ← اسمها للعرض («فاتورة محمد»، «الكاشير»)
  final Map<String, String> _labels = {};

  /// يزيد مع كل تغيّر في الحجز (لتحديث ما حُسب منه).
  int version = 0;

  /// يزيد بعد كل حفظ فاتورة على هذا الجهاز (تغيّر الرصيد الفعلي): الشاشات المفتوحة تعيد قراءة الأرصدة.
  static final ValueNotifier<int> committed = ValueNotifier<int>(0);

  void _changed() {
    version++;
    notifyListeners();
  }

  /// يسجّل حجز مسودّة (يستبدل السابق). لا إشعار إن لم يتغير شيء.
  void set(String draftId, Map<int, double> lines, {String label = ''}) {
    final clean = {for (final e in lines.entries) if (e.value > 1e-9) e.key: e.value};
    final old = _drafts[draftId] ?? const <int, double>{};
    final same = old.length == clean.length &&
        clean.entries.every((e) => old.containsKey(e.key) && (old[e.key]! - e.value).abs() < 1e-9);
    final labelSame = (_labels[draftId] ?? '') == label;
    if (same && labelSame) return;
    if (clean.isEmpty) {
      _drafts.remove(draftId);
    } else {
      _drafts[draftId] = clean;
    }
    _labels[draftId] = label;
    if (!same) _changed();
  }

  /// يزيل حجز مسودّة (حُفظت أو أُغلقت).
  void release(String draftId) {
    _labels.remove(draftId);
    if (_drafts.remove(draftId) != null) _changed();
  }

  /// ما تحجزه المسودّات الأخرى من مادة.
  double reservedByOthers(int? productId, String draftId) {
    if (productId == null) return 0;
    var s = 0.0;
    _drafts.forEach((id, m) {
      if (id != draftId) s += m[productId] ?? 0;
    });
    return s;
  }

  /// من يحجز المادة (غير هذه المسودّة): «فاتورة محمد: 10».
  List<(String, double)> holders(int? productId, String draftId) => [
        for (final e in _drafts.entries)
          if (e.key != draftId && (e.value[productId] ?? 0) > 1e-9)
            ((_labels[e.key] ?? '').isEmpty ? 'مسودّة مفتوحة' : _labels[e.key]!, e.value[productId]!),
      ];

  /// نص قصير لمن يحجز: «محجوز: فاتورة محمد 10، الكاشير 2».
  String holdersText(int? productId, String draftId) {
    final h = holders(productId, draftId);
    if (h.isEmpty) return '';
    String f(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return 'محجوز: ${h.map((x) => '${x.$1} ${f(x.$2)}').join('، ')}';
  }

  // ─────────────────────────── دوال صافية ───────────────────────────

  /// كمية سطر بالوحدة الأساسية — صيغة دفتر المخزون نفسها (StockLedger._itemBaseQty).
  static double lineBase(InvoiceItem it) {
    final ql = it.quantityLargeUnit ?? 0;
    if (ql > 0) {
      final u = it.unitsInLargeUnit ?? 0;
      return ql * (u > 0 ? u : 1);
    }
    return it.quantityIndividual ?? 0;
  }

  /// مجموع كل مادة في أسطر (الأسطر بلا مادة تُتجاهل).
  static Map<int, double> baseByProduct(Iterable<InvoiceItem> items) {
    final m = <int, double>{};
    for (final it in items) {
      final id = it.productId;
      if (id == null) continue;
      final q = lineBase(it);
      if (q <= 0) continue;
      m[id] = (m[id] ?? 0) + q;
    }
    return m;
  }

  /// الحجز = الزيادة على المحفوظ فقط (النقص لا يحرّر شيئاً قبل الحفظ).
  static Map<int, double> delta(Map<int, double> now, Map<int, double> saved) => {
        for (final e in now.entries)
          if (e.value - (saved[e.key] ?? 0) > 1e-9) e.key: e.value - (saved[e.key] ?? 0),
      };

  // ─────────────────────────── القاعدة ───────────────────────────

  /// كميات فاتورة محفوظة بالوحدة الأساسية (المطروحة فعلاً من الرصيد: لا المعلّقة ولا المحذوفة).
  static Future<Map<int, double>> savedBase(int invoiceId) async {
    final db = await DatabaseService().database;
    final r = await db.rawQuery('''
      SELECT ii.product_id AS pid,
             SUM(CASE WHEN COALESCE(ii.quantity_large_unit, 0) > 0
                      THEN ii.quantity_large_unit * COALESCE(NULLIF(ii.units_in_large_unit, 0), 1)
                      ELSE COALESCE(ii.quantity_individual, 0) END) AS q
      FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
      WHERE ii.invoice_id = ? AND ii.product_id IS NOT NULL
        AND COALESCE(i.is_deleted, 0) = 0 AND COALESCE(i.status, '') != 'معلقة'
      GROUP BY ii.product_id''', [invoiceId]);
    return {
      for (final x in r)
        if (x['pid'] is int) x['pid'] as int: (x['q'] as num?)?.toDouble() ?? 0,
    };
  }

  /// 🔒 الفحص النهائي عند الحفظ (الترحيل): الزيادة على المحفوظ ≤ الرصيد الفعلي الآن.
  /// null = مسموح. البيع بالسالب مسموح من الإعدادات ⇒ لا فحص.
  static Future<String?> commitBlockReason(
    Iterable<InvoiceItem> items, {
    int? editInvoiceId,
    required bool allowNegative,
  }) async {
    if (allowNegative) return null;
    final need = delta(baseByProduct(items), editInvoiceId == null ? const {} : await savedBase(editInvoiceId));
    if (need.isEmpty) return null;
    final db = await DatabaseService().database;
    final ids = need.keys.toList();
    final rows = await db.rawQuery(
        'SELECT id, name, stock_quantity FROM products WHERE id IN (${List.filled(ids.length, '?').join(',')})', ids);
    String f(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    final short = <String>[];
    for (final p in rows) {
      final id = p['id'] as int;
      final stock = (p['stock_quantity'] as num?)?.toDouble() ?? 0;
      final want = need[id] ?? 0;
      if (want > stock + 1e-9) {
        short.add('• ${p['name']}: المطلوب ${f(want)}، الموجود الآن ${f(stock < 0 ? 0 : stock)}');
      }
    }
    if (short.isEmpty) return null;
    return 'نفد جزء من البضاعة قبل الحفظ (بيعت من فاتورة أخرى أو جهاز آخر):\n${short.join('\n')}\n\n'
        'عدّل الكمية أو احذف السطر ثم احفظ. البيع بالسالب ممنوع من الإعدادات.';
  }
}
