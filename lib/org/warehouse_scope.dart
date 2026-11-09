// lib/org/warehouse_scope.dart
//
// 🔐 تقييد الموظف بمخازن (ومعها فروعها): يُحفظ ضمن صلاحيات المستخدم بمفاتيح
// «scope_wh:<رمز المخزن>» — فيُزامَن مع الصلاحيات نفسها بلا جدول جديد.
//   • بلا أي مفتاح = غير مقيّد (السلوك القديم تماماً). المدير لا يُقيَّد أبداً.
//   • البيع: مخزن هذا الجهاز (أو الرئيسي إن لم يُضبط) يجب أن يكون من مخازنه.
//   • الشراء والتحويل: المخزن المختار يجب أن يكون من مخازنه.
// يمنع الحفظ فقط — لا يغيّر أي رقم.

import 'package:sqflite/sqflite.dart';

import '../erp/device_defaults.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

class WarehouseScope {
  WarehouseScope._();

  static const prefix = 'scope_wh:';

  static bool isScopeKey(String k) => k.startsWith(prefix);

  /// رموز المخازن المسموحة لمستخدم (فارغة = غير مقيّد).
  static Set<String> codesOf(AppUser u) =>
      u.isAdmin ? const {} : {for (final p in u.permissions) if (isScopeKey(p)) p.substring(prefix.length)};

  /// دالة صافية: هل المخزن [code] مسموح لمن رموزه [allowed]؟
  static bool allows(Set<String> allowed, String? code) => allowed.isEmpty || (code != null && allowed.contains(code));

  static Future<Database> _db() => DatabaseService().database;

  static Future<String?> _codeOf(DatabaseExecutor db, int? warehouseId) async {
    final r = warehouseId == null
        ? await db.query('warehouses', columns: ['code'], where: 'is_default = 1', orderBy: 'id', limit: 1)
        : await db.query('warehouses', columns: ['code'], where: 'id = ?', whereArgs: [warehouseId], limit: 1);
    return r.isEmpty ? null : r.first['code'] as String?;
  }

  static Future<String> _nameOf(DatabaseExecutor db, int? warehouseId) async {
    final r = warehouseId == null
        ? await db.query('warehouses', columns: ['name'], where: 'is_default = 1', orderBy: 'id', limit: 1)
        : await db.query('warehouses', columns: ['name'], where: 'id = ?', whereArgs: [warehouseId], limit: 1);
    return r.isEmpty ? 'المخزن' : '${r.first['name']}';
  }

  /// null = مسموح. وإلا سبب المنع بالعربية. [warehouseId] null = المخزن الرئيسي.
  static Future<String?> blockReason(int? warehouseId, {String action = 'العمل على'}) async {
    final u = AuthService().currentUser;
    if (u == null) return null;
    final allowed = codesOf(u);
    if (allowed.isEmpty) return null;
    try {
      final db = await _db();
      final code = await _codeOf(db, warehouseId);
      if (allows(allowed, code)) return null;
      return 'لا يحق لـ«${u.shownName}» $action «${await _nameOf(db, warehouseId)}» — '
          'مخازنه المسموحة يحددها المدير من «الفروع والمخازن ← نطاق الموظفين».';
    } catch (_) {
      return null; // لا جداول مخازن (قاعدة قديمة): لا تقييد
    }
  }

  /// البيع من هذا الجهاز: مخزن الجهاز (أو الرئيسي).
  static Future<String?> saleBlockReason() async =>
      blockReason(await DeviceDefaults.warehouseId(), action: 'البيع من');

  /// يحفظ مخازن مستخدم دون المس بباقي صلاحياته. [codes] فارغة = بلا تقييد.
  static Future<void> setScope(AppUser u, Set<String> codes) async {
    if (u.id == null) return;
    final perms = [
      for (final p in u.permissions)
        if (!isScopeKey(p)) p,
      for (final c in codes.toList()..sort()) '$prefix$c',
    ];
    await AuthService().updateUserPermissions(u.id!, perms);
  }
}
