// lib/invoice_designer/summary_placement.dart
//
// 📌 مكان ملخص الفاتورة (المجاميع، المدفوع، المتبقي، المطلوب الحالي، وما تحت الجدول)
// — إعداد عام ثابت في الإعدادات ← الفاتورة والطباعة، يسري لحظة الطباعة على كل
// فاتورة تُطبع، الجديدة والمحفوظة سابقاً:
//   • design: كما في كل تصميم (التصميم الأصلي: تحت آخر بند).
//   • flow:   تحت آخر بند دائماً.
//   • bottom: أسفل الورقة دائماً.
// لا يغيّر أي رقم ولا أي تصميم محفوظ — يحدد المكان وقت الرسم فقط.

import 'package:shared_preferences/shared_preferences.dart';

enum SummaryPlacement { design, flow, bottom }

class SummaryPlacementPref {
  SummaryPlacementPref._();

  static const _key = 'invoice_summary_placement_v1';

  static Future<SummaryPlacement> get() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_key);
      return SummaryPlacement.values.firstWhere((m) => m.name == v, orElse: () => SummaryPlacement.design);
    } catch (_) {
      return SummaryPlacement.design;
    }
  }

  static Future<void> set(SummaryPlacement p) async {
    await (await SharedPreferences.getInstance()).setString(_key, p.name);
  }
}
