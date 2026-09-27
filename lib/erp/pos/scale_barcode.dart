// lib/erp/pos/scale_barcode.dart
//
// ⚖️ باركود الميزان (مثل سهل والإداري): EAN-13 يبدأ ببادئة (افتراضياً 2)
// ثم رمز المادة في الميزان (PLU) ثم الوزن (أو العدد) ثم رقم التحقق:
//   2 PPPPP WWWWW C   ← PLU = 5 أرقام، القيمة = 5 أرقام (غرام افتراضياً).
// المادة تُعرَّف في بطاقتها: «مادة ميزان» + «رمز الميزان».
//
// الأمان: السلة في الكاشير تقبل كميات صحيحة فقط، لذا لا نضيف إلا إذا كانت الكمية
// بالوحدة الأساسية عدداً صحيحاً (مثلاً مادة وحدتها «غرام»). غير ذلك نرفض برسالة
// واضحة بدل تقريب الكمية (التقريب يُفسد المخزون).

import '../../accounting/ledger.dart';
import '../erp_common.dart';

class ScaleSettings {
  ScaleSettings({this.prefix = '2', this.pluLength = 5, this.valueLength = 5, this.divisor = 1000});
  String prefix;
  int pluLength;
  int valueLength;

  /// القيمة في الباركود ÷ المقسوم = الكمية بالكيلو (1000 للغرام، 1 للعدد).
  double divisor;

  static Future<ScaleSettings> load() async {
    final db = await erpDb();
    final s = ScaleSettings();
    s.prefix = (await Ledger.getSetting(db, 'scale_prefix')) ?? '2';
    s.pluLength = int.tryParse((await Ledger.getSetting(db, 'scale_plu_len')) ?? '') ?? 5;
    s.valueLength = int.tryParse((await Ledger.getSetting(db, 'scale_value_len')) ?? '') ?? 5;
    s.divisor = double.tryParse((await Ledger.getSetting(db, 'scale_divisor')) ?? '') ?? 1000;
    return s;
  }

  Future<void> save() async {
    final db = await erpDb();
    await Ledger.setSetting(db, 'scale_prefix', prefix);
    await Ledger.setSetting(db, 'scale_plu_len', '$pluLength');
    await Ledger.setSetting(db, 'scale_value_len', '$valueLength');
    await Ledger.setSetting(db, 'scale_divisor', '$divisor');
  }
}

class ScaleHit {
  ScaleHit(this.productId, this.rawValue, this.quantityKg, this.unitName);
  final int productId;
  final int rawValue;

  /// الكمية بعد القسمة (كيلو عادةً).
  final double quantityKg;
  final String unitName;
}

class ScaleBarcode {
  ScaleBarcode._();

  /// يحلّل الباركود. يعيد null إن لم يكن باركود ميزان لمادة معرّفة.
  static Future<ScaleHit?> parse(String code) async {
    final c = code.trim();
    if (c.length < 8 || !RegExp(r'^\d+$').hasMatch(c)) return null;
    final s = await ScaleSettings.load();
    if (s.prefix.isEmpty || !c.startsWith(s.prefix)) return null;
    final need = s.prefix.length + s.pluLength + s.valueLength;
    if (c.length < need) return null;
    final plu = c.substring(s.prefix.length, s.prefix.length + s.pluLength);
    final value = int.tryParse(c.substring(s.prefix.length + s.pluLength, need));
    if (value == null || value <= 0) return null;
    final db = await erpDb();
    final r = await db.rawQuery('''
      SELECT d.product_id, p.unit FROM product_details d JOIN products p ON p.id = d.product_id
      WHERE COALESCE(d.is_scale_item, 0) = 1 AND COALESCE(p.is_deleted, 0) = 0
        AND (d.scale_code = ? OR CAST(d.scale_code AS INTEGER) = ?)
      LIMIT 1''', [plu, int.tryParse(plu) ?? -1]);
    if (r.isEmpty) return null;
    final q = s.divisor <= 0 ? value.toDouble() : value / s.divisor;
    return ScaleHit(r.first['product_id'] as int, value, q, '${r.first['unit'] ?? ''}');
  }

  /// الكمية الصحيحة بالوحدة الأساسية للمادة، أو null إن لم تكن عدداً صحيحاً.
  static int? integralBaseQty(ScaleHit h) {
    final u = h.unitName.trim().toLowerCase();
    double base;
    if (u.contains('غرام') || u.contains('gram') || u == 'g' || u == 'غ') {
      base = h.quantityKg * 1000;
    } else {
      base = h.quantityKg;
    }
    final r = base.roundToDouble();
    if ((base - r).abs() > 1e-9 || r <= 0) return null;
    return r.toInt();
  }
}
