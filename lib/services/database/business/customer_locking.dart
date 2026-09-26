// lib/services/database/business/customer_locking.dart
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../../license_service.dart';
import 'dart:io';

/// نتيجة محاولة القفل
class LockResult {
  final bool success;
  final String? lockedBy;
  final String? message;

  /// هل جرى تخطي القفل لعطل بنيوي (لا لتعارض حقيقي)؟
  /// تُستخدم للتسجيل والتشخيص فقط — العملية المالية تمضي في الحالتين.
  final bool skipped;

  LockResult({
    required this.success,
    this.lockedBy,
    this.message,
    this.skipped = false,
  });
}

/// خدمة إدارة الأقفال (Lock Service)
/// تمنع التعديل المتزامن على نفس الموارد (عميل، فاتورة) من قبل مستخدمين مختلفين
///
/// ═══════════════════════════════════════════════════════════════════════════
/// 🛡️ مبدأ التصميم: القفل وسيلة تنسيق، لا بوّابة على المال
/// ═══════════════════════════════════════════════════════════════════════════
///
/// القفل يمنع جهازين من تعديل نفس العميل في اللحظة نفسها. هذه وظيفة مساعدة،
/// وليست شرطاً لصحة الحساب. فإذا تعطّلت بنية القفل نفسها (جدول مفقود، قاعدة
/// بيانات مقفلة، خطأ في القراءة) فالسلوك الصحيح أن **يُتخطّى القفل وتمضي
/// العملية**، لا أن يُمنع المستخدم من تسجيل دين أو تسديد.
///
/// قبل هذا الإصلاح كان العكس يحدث: جدول `resource_locks` غير موجود ⇒
/// `_cleanupExpiredLocks` ترمي استثناءً ⇒ يلتقطه `catch` ⇒ فيستعلم عن
/// **نفس الجدول المفقود** ⇒ استثناء ثانٍ غير ملتقَط يخرج من الدالة ويُفشل
/// حفظ المعاملة كلها:
///
///     DatabaseException(no such table: resource_locks ...)
///
/// أي أن عطلاً في وسيلة مساعدة كان يشلّ الوظيفة الأساسية للتطبيق.
///
/// الآن: الجدول يُنشأ عند الحاجة، والتعارض الحقيقي وحده يمنع العملية،
/// ولا ترمي أي دالة هنا استثناءً إلى مستدعيها.
class LockService {
  final Future<Database> Function() getDatabase;
  final LicenseService _licenseService = LicenseService();

  LockService({required this.getDatabase});

  // مدة صلاحية القفل (5 دقائق)
  static const int _lockExpirationMinutes = 5;

  // معرف الجهاز الحالي (يتم تحميله مرة واحدة)
  String? _deviceId;
  String? _userName;

  // هل تأكّدنا من وجود جدول الأقفال في هذه الجلسة؟
  bool _tableReady = false;

  /// تهيئة معرف الجهاز
  Future<void> _initMsg() async {
    if (_deviceId == null) {
      try {
        _deviceId = await _licenseService.generateDeviceId();
      } catch (e) {
        print('⚠️ [LockService] تعذّر توليد معرّف الجهاز: $e');
      }
      // locked_by_device_id عمود NOT NULL — لا نتركه فارغاً أبداً
      if (_deviceId == null || _deviceId!.isEmpty) {
        _deviceId = 'unknown_device';
      }
      try {
        _userName = Platform.environment['USERNAME'] ??
            Platform.environment['USER'] ??
            'Unknown User';
      } catch (_) {
        _userName = 'Unknown User';
      }
    }
  }

  /// يتأكد من وجود جدول الأقفال، ويُنشئه عند الحاجة.
  /// يُرجع false إن تعذّر ذلك — وعندها يُتخطّى القفل ولا تُمنع العملية.
  Future<bool> _ensureLockTable(Database db) async {
    if (_tableReady) return true;
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS resource_locks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            resource_type TEXT NOT NULL,
            resource_id INTEGER NOT NULL,
            locked_by_device_id TEXT NOT NULL,
            locked_by_user_name TEXT,
            locked_at TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            UNIQUE(resource_type, resource_id)
        )
      ''');
      // قواعد قديمة قد تحوي الجدول بلا قيد UNIQUE ⇒ القفل بلا أثر
      try {
        await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_resource_locks_unique '
            'ON resource_locks(resource_type, resource_id);');
      } catch (_) {
        // فهرس فريد قد يفشل لو كانت هناك صفوف مكررة قديمة — ننظّفها ونعيد
        try {
          await db.execute('''
            DELETE FROM resource_locks
            WHERE id NOT IN (
              SELECT MIN(id) FROM resource_locks GROUP BY resource_type, resource_id
            )
          ''');
          await db.execute(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_resource_locks_unique '
              'ON resource_locks(resource_type, resource_id);');
        } catch (_) {}
      }
      _tableReady = true;
      return true;
    } catch (e) {
      print('⚠️ [LockService] تعذّر تجهيز جدول الأقفال: $e');
      return false;
    }
  }

  /// محاولة حجز مورد (Acquire Lock)
  ///
  /// تُرجع `success: false` **فقط** عند تعارض حقيقي: جهاز آخر يحجز المورد.
  /// أي عطل آخر يُنتج `success: true, skipped: true` كي لا تُمنع العملية.
  Future<LockResult> acquireLock({
    required String resourceType, // 'customer' or 'invoice'
    required int resourceId,
  }) async {
    late final Database db;
    try {
      await _initMsg();
      db = await getDatabase();
    } catch (e) {
      print('⚠️ [LockService] تخطي القفل (تعذّر الوصول لقاعدة البيانات): $e');
      return LockResult(
          success: true, skipped: true, message: 'تُخطّي القفل: $e');
    }

    if (!await _ensureLockTable(db)) {
      return LockResult(
          success: true,
          skipped: true,
          message: 'تُخطّي القفل: تعذّر تجهيز جدول الأقفال');
    }

    try {
      // 1. تنظيف الأقفال المنتهية الصلاحية أولاً
      await _cleanupExpiredLocks(db);

      // 2. محاولة الحجز
      final now = DateTime.now();
      final expires = now.add(const Duration(minutes: _lockExpirationMinutes));

      await db.insert('resource_locks', {
        'resource_type': resourceType,
        'resource_id': resourceId,
        'locked_by_device_id': _deviceId,
        'locked_by_user_name': _userName,
        'locked_at': now.toIso8601String(),
        'expires_at': expires.toIso8601String(),
      });

      return LockResult(success: true);
    } catch (e) {
      // فشل الإدراج له سببان محتملان: تعارض حقيقي (UNIQUE)، أو عطل بنيوي.
      // نفرّق بينهما بالاستعلام — وهذا الاستعلام نفسه محاط بحماية، فقد كان
      // هو مصدر الاستثناء الثاني غير الملتقَط في النسخة السابقة.
      try {
        final existingLock = await db.query(
          'resource_locks',
          where: 'resource_type = ? AND resource_id = ?',
          whereArgs: [resourceType, resourceId],
        );

        if (existingLock.isNotEmpty) {
          final lock = existingLock.first;
          final lockedByDevice = lock['locked_by_device_id'] as String?;

          // إذا كان جهازي هو من يحجز، نقوم بتحديث مدة القفل (تمديد)
          if (lockedByDevice == _deviceId) {
            await keepAlive(resourceType: resourceType, resourceId: resourceId);
            return LockResult(success: true);
          }

          // 🔴 تعارض حقيقي — هذا وحده يمنع العملية
          final lockedByUser =
              lock['locked_by_user_name'] as String? ?? 'مستخدم آخر';
          return LockResult(
              success: false,
              lockedBy: lockedByUser,
              message: 'المورد قيد الاستخدام حالياً من قبل $lockedByUser');
        }

        // لا يوجد قفل ⇒ الفشل لم يكن تعارضاً، بل عطلاً. لا نمنع العملية.
        print('⚠️ [LockService] تخطي القفل (فشل غير تعارضي): $e');
        return LockResult(
            success: true, skipped: true, message: 'تُخطّي القفل: $e');
      } catch (inner) {
        print('⚠️ [LockService] تخطي القفل (تعذّر فحص القفل القائم): $inner');
        return LockResult(
            success: true, skipped: true, message: 'تُخطّي القفل: $inner');
      }
    }
  }

  /// تحرير القفل (Release Lock) — لا يرمي استثناءً أبداً.
  ///
  /// تُستدعى غالباً داخل `finally`، فرمي استثناء منها يُخفي الخطأ الأصلي
  /// أو يُفشل عملية نجحت فعلاً.
  Future<void> releaseLock({
    required String resourceType,
    required int resourceId,
  }) async {
    try {
      await _initMsg();
      final db = await getDatabase();
      if (!await _ensureLockTable(db)) return;

      // نحذف القفل فقط إذا كان تابعاً لهذا الجهاز
      await db.delete(
        'resource_locks',
        where:
            'resource_type = ? AND resource_id = ? AND locked_by_device_id = ?',
        whereArgs: [resourceType, resourceId, _deviceId],
      );
    } catch (e) {
      print('⚠️ [LockService] تعذّر تحرير القفل ($resourceType/$resourceId): $e');
    }
  }

  /// تمديد صلاحية القفل (Heartbeat)
  /// يجب استدعاء هذه الدالة دورياً طالما المستخدم يعمل على المورد
  Future<bool> keepAlive({
    required String resourceType,
    required int resourceId,
  }) async {
    try {
      await _initMsg();
      final db = await getDatabase();
      if (!await _ensureLockTable(db)) return false;

      final expires =
          DateTime.now().add(const Duration(minutes: _lockExpirationMinutes));

      final count = await db.update(
        'resource_locks',
        {'expires_at': expires.toIso8601String()},
        where:
            'resource_type = ? AND resource_id = ? AND locked_by_device_id = ?',
        whereArgs: [resourceType, resourceId, _deviceId],
      );

      return count > 0;
    } catch (e) {
      print('⚠️ [LockService] تعذّر تمديد القفل: $e');
      return false;
    }
  }

  /// التحقق من حالة القفل.
  /// عند أي عطل تُرجع false (غير مقفول) — فشل آمن لا يمنع المستخدم.
  Future<bool> isLockedByOther({
    required String resourceType,
    required int resourceId,
  }) async {
    try {
      await _initMsg();
      final db = await getDatabase();
      if (!await _ensureLockTable(db)) return false;

      await _cleanupExpiredLocks(db); // Clean up first

      final result = await db.query(
        'resource_locks',
        columns: ['locked_by_device_id'],
        where: 'resource_type = ? AND resource_id = ?',
        whereArgs: [resourceType, resourceId],
      );

      if (result.isEmpty) return false;

      final lockedByDevice = result.first['locked_by_device_id'] as String?;
      return lockedByDevice != null && lockedByDevice != _deviceId;
    } catch (e) {
      print('⚠️ [LockService] تعذّر فحص القفل: $e');
      return false;
    }
  }

  /// تنظيف الأقفال المنتهية — لا يرمي استثناءً.
  Future<void> _cleanupExpiredLocks(Database db) async {
    try {
      final now = DateTime.now().toIso8601String();
      await db.delete(
        'resource_locks',
        where: 'expires_at < ?',
        whereArgs: [now],
      );
    } catch (e) {
      print('⚠️ [LockService] تعذّر تنظيف الأقفال المنتهية: $e');
    }
  }

  /// 🧹 تحرير كل أقفال هذا الجهاز — تُستدعى عند بدء التشغيل لتنظيف أقفال
  /// بقيت معلّقة بعد إغلاق مفاجئ للتطبيق.
  Future<void> releaseAllLocksForThisDevice() async {
    try {
      await _initMsg();
      final db = await getDatabase();
      if (!await _ensureLockTable(db)) return;
      final n = await db.delete(
        'resource_locks',
        where: 'locked_by_device_id = ?',
        whereArgs: [_deviceId],
      );
      if (n > 0) {
        print('🧹 [LockService] حُرّرت $n قفلاً معلّقاً من جلسة سابقة');
      }
    } catch (e) {
      print('⚠️ [LockService] تعذّر تحرير أقفال الجهاز: $e');
    }
  }
}
