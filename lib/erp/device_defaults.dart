// lib/erp/device_defaults.dart
//
// 🖥️ صندوق ومخزن هذا الجهاز: كل فاتورة بيع تُحفظ من هذا الجهاز تُختم بصندوقه
// ومخزنه (إن لم تكن مختومة)، فيرحّل محرك الترحيل المقبوض إلى صندوق الكاشير
// الصحيح، وتُخصم الكمية من مخزنه.
//
// الإعداد محفوظ على الجهاز نفسه (SharedPreferences) — كل طرفية لها صندوقها.
//
// 🖥️🖥️ تعدد الشاشات على الحاسبة الواحدة: كل الشاشات تتشارك ملف الإعدادات نفسه،
// فلكل شاشة مفتاح خاص (‎__seat2، ‎__seat3...). الشاشة الأولى على المفتاح القديم
// كما كانت. شاشة لم يُضبط لها شيء تأخذ إعداد الشاشة الأولى (نفس السلوك السابق
// تماماً)، و«بلا» لشاشة غير الأولى تُحفظ صفراً صريحاً = الصندوق الافتراضي.

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../services/seat_service.dart';
import 'erp_common.dart';

/// إعداد شاشة واحدة: [inherited] = لم يُضبط لها شيء فتأخذ إعداد الشاشة الأولى.
class SeatDefaults {
  const SeatDefaults(this.seat, this.cashBoxId, this.warehouseId, {this.inherited = false});
  final int seat;
  final int? cashBoxId;
  final int? warehouseId;
  final bool inherited;
}

class DeviceDefaults {
  DeviceDefaults._();

  static const _kBox = 'erp_device_cash_box_id';
  static const _kWarehouse = 'erp_device_warehouse_id';

  static String _key(String base, int seat) => seat <= 1 ? base : '${base}__seat$seat';

  /// القيمة الفعلية لشاشة: مفتاحها، وإلا (لغير الأولى) مفتاح الشاشة الأولى.
  /// صفر محفوظ = «بلا» صريحة.
  static int? _read(SharedPreferences p, String base, int seat) {
    final own = p.getInt(_key(base, seat));
    if (own != null) return own <= 0 ? null : own;
    if (seat <= 1) return null;
    final first = p.getInt(base);
    return (first == null || first <= 0) ? null : first;
  }

  static bool _inherited(SharedPreferences p, int seat) =>
      seat > 1 && p.getInt(_key(_kBox, seat)) == null && p.getInt(_key(_kWarehouse, seat)) == null;

  static Future<int?> cashBoxId({int? seat}) async {
    final p = await SharedPreferences.getInstance();
    return _read(p, _kBox, seat ?? SeatService.seat);
  }

  static Future<int?> warehouseId({int? seat}) async {
    final p = await SharedPreferences.getInstance();
    return _read(p, _kWarehouse, seat ?? SeatService.seat);
  }

  /// إعداد كل الشاشات ‎1..[seats] على هذه الحاسبة. يعيد القراءة من الملف لأن
  /// شاشة أخرى (عملية أخرى) قد تكون غيّرته.
  static Future<List<SeatDefaults>> allSeats(int seats) async {
    final p = await SharedPreferences.getInstance();
    try {
      await p.reload();
    } catch (_) {}
    return [
      for (var s = 1; s <= (seats < 1 ? 1 : seats); s++)
        SeatDefaults(s, _read(p, _kBox, s), _read(p, _kWarehouse, s), inherited: _inherited(p, s)),
    ];
  }

  static Future<void> set({int? cashBoxId, int? warehouseId, int? seat}) async {
    final p = await SharedPreferences.getInstance();
    // الشاشات الأخرى تكتب الملف نفسه: نقرأ آخر نسخة قبل الكتابة حتى لا نمحو ما كتبته
    try {
      await p.reload();
    } catch (_) {}
    final s = seat ?? SeatService.seat;
    Future<void> write(String base, int? v) async {
      final k = _key(base, s);
      if (v != null) {
        await p.setInt(k, v);
      } else if (s <= 1) {
        await p.remove(k);
      } else {
        await p.setInt(k, 0); // «بلا» صريحة: لا ترث إعداد الشاشة الأولى
      }
    }

    await write(_kBox, cashBoxId);
    await write(_kWarehouse, warehouseId);
  }

  /// صندوق هذه الشاشة ومخزنها الآن (يُقرأ قبل معاملة الحفظ). الإعداد قد يُضبط لهذه
  /// الشاشة من شاشة أخرى على الحاسبة نفسها، فيُعاد تحميل الملف أولاً.
  static Future<({int? box, int? warehouse})> current() async {
    try {
      await (await SharedPreferences.getInstance()).reload();
    } catch (_) {}
    return (box: await cashBoxId(), warehouse: await warehouseId());
  }

  /// يختم فاتورة بصندوق ومخزن [d] داخل معاملة حفظها [db] — فلا تبقى فاتورة محفوظة بلا
  /// ختم إن انقطعت الكهرباء بين الحفظ والختم. لا يغيّر ختماً موجوداً. قاعدة قديمة لم
  /// يُضَف إليها العمودان بعد ⇒ لا ختم (لا تفشل الفاتورة بسببه).
  static Future<void> stampInvoiceIn(DatabaseExecutor db, int invoiceId, ({int? box, int? warehouse}) d) async {
    if (d.box == null && d.warehouse == null) return;
    final cols = (await db.rawQuery('PRAGMA table_info(invoices)')).map((c) => c['name']).toSet();
    if (d.box != null && cols.contains('cash_box_id')) {
      await db.rawUpdate(
          'UPDATE invoices SET cash_box_id = ? WHERE id = ? AND cash_box_id IS NULL', [d.box, invoiceId]);
    }
    if (d.warehouse != null && cols.contains('warehouse_id')) {
      await db.rawUpdate(
          'UPDATE invoices SET warehouse_id = ? WHERE id = ? AND warehouse_id IS NULL', [d.warehouse, invoiceId]);
    }
  }

  /// يختم فاتورة محفوظة بصندوق ومخزن هذا الجهاز (بعد حفظها — الكاشير). لا يغيّر فاتورة
  /// مختومة مسبقاً، ولا يرمي أي خطأ (الحفظ الأصلي تمّ وهو الأهم).
  static Future<void> stampInvoice(int invoiceId) async {
    try {
      await stampInvoiceIn(await erpDb(), invoiceId, await current());
    } catch (_) {}
  }
}
