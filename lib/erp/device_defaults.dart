// lib/erp/device_defaults.dart
//
// 🖥️ صندوق ومخزن هذا الجهاز: كل فاتورة بيع تُحفظ من هذا الجهاز تُختم بصندوقه
// ومخزنه (إن لم تكن مختومة)، فيرحّل محرك الترحيل المقبوض إلى صندوق الكاشير
// الصحيح، وتُخصم الكمية من مخزنه.
//
// الإعداد محفوظ على الجهاز نفسه (SharedPreferences) — كل طرفية لها صندوقها.

import 'package:shared_preferences/shared_preferences.dart';

import 'erp_common.dart';

class DeviceDefaults {
  DeviceDefaults._();

  static const _kBox = 'erp_device_cash_box_id';
  static const _kWarehouse = 'erp_device_warehouse_id';

  static Future<int?> cashBoxId() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kBox);
  }

  static Future<int?> warehouseId() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kWarehouse);
  }

  static Future<void> set({int? cashBoxId, int? warehouseId}) async {
    final p = await SharedPreferences.getInstance();
    if (cashBoxId == null) {
      await p.remove(_kBox);
    } else {
      await p.setInt(_kBox, cashBoxId);
    }
    if (warehouseId == null) {
      await p.remove(_kWarehouse);
    } else {
      await p.setInt(_kWarehouse, warehouseId);
    }
  }

  /// يختم فاتورة محفوظة بصندوق ومخزن هذا الجهاز. لا يغيّر فاتورة مختومة
  /// مسبقاً، ولا يرمي أي خطأ (الحفظ الأصلي تمّ وهو الأهم).
  static Future<void> stampInvoice(int invoiceId) async {
    try {
      final box = await cashBoxId();
      final wh = await warehouseId();
      if (box == null && wh == null) return;
      final db = await erpDb();
      if (box != null) {
        await db.rawUpdate(
            'UPDATE invoices SET cash_box_id = ? WHERE id = ? AND cash_box_id IS NULL', [box, invoiceId]);
      }
      if (wh != null) {
        await db.rawUpdate(
            'UPDATE invoices SET warehouse_id = ? WHERE id = ? AND warehouse_id IS NULL', [wh, invoiceId]);
      }
    } catch (_) {}
  }
}
