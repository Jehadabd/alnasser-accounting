// lib/erp/variants/variant_models.dart
//
// 👕 متغيّرات المادة (مقاس × لون...): كل متغيّر مادة حقيقية مستقلة (كمية، باركود، مزامنة)
// مربوطة بعائلة. لا يتغيّر منطق المخزون ولا الفواتير: البيع والجرد على المادة نفسها كما هي.
// هنا الدوال الصافية: توليد التركيبات وأسماؤها.

/// خاصية وقيمها، مثل («المقاس»، [S, M, L]).
class VariantAxis {
  VariantAxis(this.name, Iterable<String> values)
      : values = [
          for (final v in values.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet()) v,
        ];
  final String name;
  final List<String> values;

  /// «S، M ، L» ⇒ [S, M, L] (فاصلة عربية أو إنجليزية).
  static List<String> split(String raw) => raw.split(RegExp(r'[,،]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

/// تركيبة واحدة: خاصية ← قيمة.
typedef VariantCombo = Map<String, String>;

class Variants {
  Variants._();

  static const maxCombos = 200;

  /// كل التركيبات (حاصل الضرب) — الخصائص الفارغة تُتجاهل.
  static List<VariantCombo> combos(List<VariantAxis> axes) {
    final used = axes.where((a) => a.values.isNotEmpty).toList();
    if (used.isEmpty) return const [];
    var out = <VariantCombo>[{}];
    for (final a in used) {
      out = [
        for (final c in out)
          for (final v in a.values) {...c, a.name: v},
      ];
      if (out.length > maxCombos) throw StateError('أكثر من $maxCombos متغيّراً — قلّل القيم');
    }
    return out;
  }

  /// اسم المتغيّر: «قميص - M - أزرق».
  static String name(String base, VariantCombo c) => [base.trim(), ...c.values].join(' - ');
}
