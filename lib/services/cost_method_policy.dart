// lib/services/cost_method_policy.dart
//
// 💰 طريقة كلفة المادة عند شراء كمية جديدة بكلفة مختلفة.
//
//   الطرق المعتمدة محاسبياً هنا:
//     • المتوسط المرجّح (AVCO): (الباقي × كلفته + الجديد × كلفته) ÷ المجموع.
//       معتمد في المعيار الدولي IAS 2، ويوزّع فرق السعر على كل القطع.
//     • آخر سعر شراء: الكلفة = كلفة الشراء الأخير. شائعة في المحلات للتسعير،
//       لكنها ترفع/تخفض كلفة القطع القديمة الباقية فجأة.
//   لا نعرض «الأعلى» أو «الأدنى» أو «إبقاء القديمة» كطرق كلفة: تجعل قيمة المخزون
//   والأرباح غير حقيقية (لا يقبلها IAS 2). وFIFO يحتاج كلفة لكل دفعة عند البيع (غير متاح الآن).
//
//   الترتيب: اختيارك في نافذة الشراء ← طريقة المادة في بطاقتها ← الإعداد العام.
//   «اسألني» تُحسم في الشاشة قبل الحفظ؛ إن لم تُحسم (حفظ بلا شاشة) ⇒ المتوسط المرجّح.

import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import 'database_service.dart';

class CostMethodPolicy {
  CostMethodPolicy._();

  static const avco = 'avco';
  static const last = 'last_purchase';
  static const ask = 'ask';

  /// قيم بطاقة المادة (product_details.cost_method). 'last' القديمة كانت القيمة
  /// الافتراضية للعمود ولم تكن تُطبَّق ⇒ تعني «اتبع الإعدادات» حتى لا يتغير شيء.
  static const itemDefault = 'default';
  static const itemAverage = 'average';
  static const itemLast = 'last_purchase';
  static const itemAsk = 'ask';

  static String? _fromItem(String? v) => switch (v) {
        itemAverage => avco,
        itemLast => last,
        itemAsk => ask,
        _ => null,
      };

  /// قيمة صالحة لقائمة بطاقة المادة (ما ليس منها ⇒ «اتبع الإعدادات»).
  static String itemValue(String? v) => (v == itemAverage || v == itemLast || v == itemAsk) ? v! : itemDefault;

  static String _global(String? g) => g == avco ? avco : (g == ask ? ask : last);

  static Future<String?> itemMethod(DatabaseExecutor db, int productId) async {
    try {
      final r = await db.query('product_details', columns: ['cost_method'], where: 'product_id = ?', whereArgs: [productId], limit: 1);
      return r.isEmpty ? null : _fromItem(r.first['cost_method'] as String?);
    } catch (_) {
      return null; // لا جدول تفاصيل بعد
    }
  }

  /// الطريقة قبل حسم «اسألني».
  static Future<String> effective(DatabaseExecutor db, int productId, String? global) async =>
      await itemMethod(db, productId) ?? _global(global);

  /// الطريقة النهائية للحفظ (لا تعيد «اسألني» أبداً).
  static Future<String> resolve(DatabaseExecutor db, int productId, String? global, Map<int, String>? chosen) async {
    final c = chosen?[productId];
    if (c == avco || c == last) return c!;
    final m = await effective(db, productId, global);
    return m == last ? last : avco;
  }

  /// يحفظ الطريقة في بطاقة المادة («تذكّر لهذه المادة»).
  static Future<void> remember(int productId, String method) async {
    final db = await DatabaseService().database;
    final v = method == avco ? itemAverage : itemLast;
    await db.rawInsert(
      'INSERT INTO product_details (product_id, cost_method, updated_at) VALUES (?, ?, ?) '
      'ON CONFLICT(product_id) DO UPDATE SET cost_method = excluded.cost_method, updated_at = excluded.updated_at',
      [productId, v, DateTime.now().toIso8601String()],
    );
  }

  /// المتوسط المرجّح (المخزون السالب لا يدخل — بيع فعلاً بالكلفة القديمة).
  static double average({required double stock, required double cost, required double qty, required double newCost}) {
    final basis = stock > 0 ? stock : 0.0;
    final total = basis + qty;
    return total > 0 ? (basis * cost + qty * newCost) / total : newCost;
  }
}
