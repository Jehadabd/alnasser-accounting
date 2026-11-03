// lib/erp/inventory/label_reprint.dart
//
// 🏷️ «ملصقات تحتاج إعادة طباعة»: كل مادة طُبع ملصقها بالسعر من البرنامج ثم تغيّر
// سعرها — حتى لا يختلف سعر الرف عن سعر الكاشير.
//
//   • جدول label_prints: لكل (مادة، مستوى سعر) آخر سعر طُبع على ملصقها ووقته.
//     بيانات تشغيلية فقط — لا علاقة لها بأي رصيد أو قيد أو كلفة.
//   • يُسجَّل عند إنشاء ملف الملصقات بسعر ظاهر (BarcodeLabels.printForProducts).
//   • المادة التي لم يُطبع لها ملصق من البرنامج لا تظهر (لا نعرف ما على رفّها).
//   • التسجيل لا يرمي ولا يوقف الطباعة.

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../accounting/screens/acc_ui.dart' show fmtMoney, fmtDate;
import '../../widgets/settings_kit.dart';
import '../erp_common.dart';
import '../stock_helpers.dart';
import 'barcode_labels.dart';

class StaleLabel {
  StaleLabel(this.productId, this.name, this.level, this.printedPrice, this.currentPrice, this.printedAt);
  final int productId;
  final String name;
  final int level;
  final double printedPrice;
  final double currentPrice;
  final DateTime? printedAt;
}

class LabelReprint {
  LabelReprint._();

  static Future<void> ensure(DatabaseExecutor db) => db.execute('''
      CREATE TABLE IF NOT EXISTS label_prints (
        product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        price_level INTEGER NOT NULL CHECK (price_level BETWEEN 1 AND 6),
        price REAL NOT NULL,
        printed_at TEXT NOT NULL,
        PRIMARY KEY (product_id, price_level)
      )''');

  /// يسجّل أسعار الملصقات المطبوعة (المستوى [level] من 1 إلى 6).
  static Future<void> record(DatabaseExecutor db, List<ProductLite> items, int level) async {
    final lv = level.clamp(1, 6).toInt();
    try {
      await ensure(db);
      final at = DateTime.now().toIso8601String();
      final batch = db.batch();
      for (final p in items) {
        final price = p.prices.length >= lv ? p.prices[lv - 1] : 0.0;
        batch.insert('label_prints', {'product_id': p.id, 'price_level': lv, 'price': price, 'printed_at': at},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('⚠️ تسجيل الملصقات: $e');
    }
  }

  /// سعر المستوى الحالي — نفس قاعدة ProductLite: المستوى 1 = price1 وإلا unit_price.
  static const _currentPrice = '''
    CASE l.price_level
      WHEN 1 THEN CASE WHEN COALESCE(p.price1, 0) > 0 THEN p.price1 ELSE COALESCE(p.unit_price, 0) END
      WHEN 2 THEN COALESCE(p.price2, 0) WHEN 3 THEN COALESCE(p.price3, 0)
      WHEN 4 THEN COALESCE(p.price4, 0) WHEN 5 THEN COALESCE(p.price5, 0)
      ELSE COALESCE(p.price6, 0) END''';

  /// المواد التي تغيّر سعرها بعد آخر طباعة لملصقها.
  static Future<List<StaleLabel>> stale(DatabaseExecutor db) async {
    await ensure(db);
    final rows = await db.rawQuery('''
      SELECT l.product_id, p.name, l.price_level, l.price AS printed, l.printed_at, $_currentPrice AS current
      FROM label_prints l JOIN products p ON p.id = l.product_id
      WHERE COALESCE(p.is_deleted, 0) = 0 AND ABS(($_currentPrice) - l.price) > 0.004
      ORDER BY p.name''');
    return [
      for (final r in rows)
        StaleLabel(r['product_id'] as int, '${r['name'] ?? ''}', (r['price_level'] as num).toInt(),
            (r['printed'] as num).toDouble(), (r['current'] as num).toDouble(), DateTime.tryParse('${r['printed_at']}')),
    ];
  }
}

/// شاشة القائمة: تحديد الكل وطباعة بضغطة.
class LabelReprintScreen extends StatefulWidget {
  const LabelReprintScreen({super.key});

  @override
  State<LabelReprintScreen> createState() => _LabelReprintScreenState();
}

class _LabelReprintScreenState extends State<LabelReprintScreen> {
  List<StaleLabel>? _rows;
  final Set<int> _sel = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await LabelReprint.stale(await erpDb());
      if (!mounted) return;
      setState(() {
        _rows = r;
        _sel
          ..clear()
          ..addAll(r.map((x) => x.productId));
      });
    } catch (e) {
      if (mounted) setToast(context, 'تعذّر التحميل: $e', error: true);
    }
  }

  Future<void> _print() async {
    if (_sel.isEmpty) return;
    await BarcodeLabels.printForProducts(context, _sel.toList());
    await _load(); // المطبوع بالسعر الحالي يختفي من القائمة
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return SettingsScaffold(
      title: 'ملصقات تحتاج إعادة طباعة',
      icon: Icons.new_label_rounded,
      subtitle: 'مواد تغيّر سعرها بعد طباعة ملصقها',
      maxWidth: 860,
      actions: [IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      loading: rows == null,
      children: rows == null
          ? null
          : [
              SetHero(
                icon: Icons.new_label_rounded,
                color: kSetOrange,
                title: rows.isEmpty ? 'كل الملصقات مطابقة' : '${rows.length} ملصق سعره قديم',
                text: 'تظهر هنا المواد التي طُبع ملصقها بالسعر من البرنامج ثم تغيّر سعرها. '
                    'اطبعها ليطابق سعر الرف سعر الكاشير. المواد التي لم يُطبع لها ملصق من البرنامج لا تظهر.',
                status: SetStatusPill(rows.isEmpty ? 'لا شيء لإعادة الطباعة' : 'المحدد ${_sel.length}', ok: rows.isEmpty),
              ),
              if (rows.isNotEmpty) ...[
                SetCard(
                  title: 'المواد',
                  icon: Icons.inventory_2_rounded,
                  color: kSetOrange,
                  trailing: TextButton(
                    onPressed: () => setState(() {
                      if (_sel.length == rows.length) {
                        _sel.clear();
                      } else {
                        _sel.addAll(rows.map((x) => x.productId));
                      }
                    }),
                    child: Text(_sel.length == rows.length ? 'إلغاء الكل' : 'تحديد الكل'),
                  ),
                  child: Column(children: [
                    for (final r in rows)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _sel.contains(r.productId),
                        onChanged: (v) => setState(() => v == true ? _sel.add(r.productId) : _sel.remove(r.productId)),
                        title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          'على الملصق ${fmtMoney(r.printedPrice)} ← الآن ${fmtMoney(r.currentPrice)}'
                          '${r.level > 1 ? ' (السعر ${r.level})' : ''}'
                          '${r.printedAt == null ? '' : ' • طُبع ${fmtDate(r.printedAt!)}'}',
                          style: TextStyle(color: r.currentPrice > r.printedPrice ? kSetRed : kSetGreen),
                        ),
                      ),
                  ]),
                ),
                SetPrimaryButton(
                  label: 'طباعة الملصقات المحددة (${_sel.length})',
                  icon: Icons.print_rounded,
                  color: kSetOrange,
                  onPressed: _sel.isEmpty ? null : _print,
                ),
              ],
              const SizedBox(height: 40),
            ],
    );
  }
}
