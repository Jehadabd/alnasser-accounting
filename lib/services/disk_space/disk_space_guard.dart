// lib/services/disk_space/disk_space_guard.dart
//
// 💽 حماية امتلاء القرص (طلب المالك 2026-11-11).
//
// قاعدة البيانات (SQLite) نفسها آمنة عند الامتلاء: الكتابة التي لا تجد مكاناً تُلغى
// كاملة، فلا تُحفظ فاتورة نصفية ولا معاملة بلا فاتورتها. الخطر الحقيقي في غيرها:
//
//   1) النسخة الاحتياطية المحلية: نسخ ملف القاعدة يتوقف في منتصفه فيبقى ملف ناقص
//      باسم نسخة سليمة، ثم «الإبقاء على آخر 5 نسخ» يحذف النسخ السليمة القديمة
//      ويُبقي الناقصة. ⇐ [copyAtomically]: اسم مؤقت ← فحص الحجم ← إعادة تسمية،
//      والفشل لا يترك ملفاً ناقصاً، ولا تُحذف القديمة إلا بعد نجاح الجديدة.
//   2) الحفظ: خطأ تقني غامض («database or disk is full (code 13)»). ⇐ [isDiskFullError]
//      و[friendlyMessage]، ومنع محاولة الحفظ إن كان الفراغ دون الحد الحرج [blockSaveReason].
//   3) لا أحد يعلم حتى يقع. ⇐ [startMonitor]: فحص عند التشغيل وكل 30 دقيقة، وتنبيه
//      حين يقلّ الفراغ (برتقالي) وحين يصير حرجاً (أحمر)، مرة لكل مستوى في الجلسة.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../database_service.dart';
import 'disk_free.dart';

enum DiskLevel { unknown, ok, low, critical }

class DiskSpaceGuard {
  DiskSpaceGuard._();

  static const int _mb = 1024 * 1024;

  /// دون هذا: تنبيه برتقالي (أو 5 أضعاف حجم القاعدة إن كانت أكبر)
  static const int lowBytes = 1024 * _mb;

  /// دون هذا: تنبيه أحمر (أو ضعفا حجم القاعدة إن كانت أكبر)
  static const int criticalBytes = 200 * _mb;

  /// دون هذا: لا تُحاوَل كتابة فاتورة أصلاً
  static const int blockSaveBytes = 50 * _mb;

  // ─────────────────────────── نقي (مختبر) ───────────────────────────

  /// مستوى الفراغ [free] لقاعدة حجمها [dbSize] (null = غير معروف).
  static DiskLevel levelFor(int? free, {int dbSize = 0}) {
    if (free == null) return DiskLevel.unknown;
    final critical = criticalBytes > dbSize * 2 ? criticalBytes : dbSize * 2;
    final low = lowBytes > dbSize * 5 ? lowBytes : dbSize * 5;
    if (free < critical) return DiskLevel.critical;
    if (free < low) return DiskLevel.low;
    return DiskLevel.ok;
  }

  /// هل هذا الخطأ سببه امتلاء القرص؟ (SQLite: SQLITE_FULL = 13؛ ويندوز: 112 و39؛
  /// لينكس/أندرويد: ENOSPC = 28)
  static bool isDiskFullError(Object e) {
    if (e is FileSystemException) {
      final c = e.osError?.errorCode;
      if (c == 112 || c == 39 || ((Platform.isLinux || Platform.isAndroid) && c == 28)) return true;
    }
    final s = '$e'.toLowerCase();
    return s.contains('sqlite_full') ||
        s.contains('database or disk is full') ||
        RegExp(r'\(code 13\b').hasMatch(s) ||
        s.contains('no space left on device') ||
        s.contains('not enough space on the disk') ||
        s.contains('there is not enough space');
  }

  static String friendlyMessage(String what) =>
      '💽 القرص ممتلئ — لم يُحفظ $what، ولم يتغير شيء في البيانات.\n'
      'أفرغ مساحة على القرص (احذف ملفات لا تحتاجها أو أفرغ سلة المحذوفات)، ثم أعد المحاولة.';

  static String _size(int bytes) => bytes >= 1024 * _mb
      ? '${(bytes / (1024 * _mb)).toStringAsFixed(1)} غيغابايت'
      : '${(bytes / _mb).toStringAsFixed(0)} ميغابايت';

  // ─────────────────────────── القرص ───────────────────────────

  static String? _dbPathCache;

  static Future<String?> _dbPath() async {
    if (_dbPathCache != null) return _dbPathCache;
    try {
      _dbPathCache = (await DatabaseService().database).path;
    } catch (_) {}
    return _dbPathCache;
  }

  /// الفراغ على قرص قاعدة البيانات وحجمها (null = غير معروف).
  static Future<({int? free, int dbSize})> status() async {
    final path = await _dbPath();
    if (path == null) return (free: null, dbSize: 0);
    var size = 0;
    try {
      size = await File(path).length();
      final wal = File('$path-wal');
      if (await wal.exists()) size += await wal.length();
    } catch (_) {}
    return (free: DiskFree.bytesFor(p.dirname(path)), dbSize: size);
  }

  /// سبب منع الحفظ إن كان القرص على وشك الامتلاء (null = احفظ).
  static Future<String?> blockSaveReason(String what) async {
    try {
      final s = await status();
      final free = s.free;
      if (free != null && free < blockSaveBytes) {
        return '💽 القرص شبه ممتلئ (المتبقي ${_size(free)}) — لن يُحفظ $what حتى تُفرغ مساحة.\n'
            'احذف ملفات لا تحتاجها أو أفرغ سلة المحذوفات، ثم أعد المحاولة. لم يتغير شيء.';
      }
    } catch (_) {}
    return null;
  }

  /// ينسخ [src] إلى [dest] بلا ملف ناقص أبداً: يُكتب باسم مؤقت (.part) ثم يُفحص حجمه
  /// ثم يُعاد تسميته. أي فشل (امتلاء القرص مثلاً) يحذف المؤقت ويرمي الخطأ، وتبقى
  /// [dest] القديمة إن وُجدت كما هي.
  static Future<void> copyAtomically(File src, String dest) async {
    final need = await src.length();
    final free = DiskFree.bytesFor(p.dirname(dest));
    // هامش: 20 ميغابايت + 5%
    if (free != null && free < need + 20 * _mb + need ~/ 20) {
      throw FileSystemException(
          'not enough space on the disk: المطلوب ${_size(need)} والمتاح ${_size(free)}', dest);
    }
    final part = File('$dest.part');
    try {
      if (await part.exists()) await part.delete();
      await src.copy(part.path);
      final got = await part.length();
      if (got != need) {
        throw FileSystemException('نسخ ناقص: $got من $need بايت', part.path);
      }
      final old = File(dest);
      if (await old.exists()) await old.delete();
      await part.rename(dest);
    } catch (_) {
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// يحذف بقايا نسخ ناقصة (.part) من فشل سابق في [dir].
  static Future<void> removeLeftovers(Directory dir) async {
    try {
      await for (final e in dir.list()) {
        if (e is File && e.path.endsWith('.part')) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // ─────────────────────────── التنبيه ───────────────────────────

  static Timer? _timer;
  static DiskLevel _warned = DiskLevel.ok;

  /// فحص عند التشغيل وكل 30 دقيقة. يُنبّه مرة لكل مستوى أسوأ في الجلسة.
  static void startMonitor(BuildContext context) {
    _timer?.cancel();
    Future<void> tick() async {
      try {
        final s = await status();
        final level = levelFor(s.free, dbSize: s.dbSize);
        if (level == DiskLevel.ok) _warned = DiskLevel.ok; // أُفرغت مساحة: ينبّه من جديد إن عاد
        if (level.index <= _warned.index || level.index < DiskLevel.low.index) return;
        if (!context.mounted) return;
        _warned = level;
        final free = s.free ?? 0;
        if (level == DiskLevel.critical) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('💽 القرص على وشك الامتلاء', style: TextStyle(color: Colors.red)),
              content: Text(
                'المتبقي على القرص ${_size(free)} فقط.\n\n'
                'إذا امتلأ القرص فلن يُحفظ أي شيء جديد (فاتورة، وصل، نسخة احتياطية) حتى '
                'تُفرغ مساحة. البيانات المحفوظة تبقى سليمة.\n\n'
                'أفرغ مساحة الآن: احذف ملفات لا تحتاجها، أو أفرغ سلة المحذوفات.',
                style: const TextStyle(height: 1.6),
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
            ),
          );
        } else {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Text('💽 المساحة الفارغة على القرص قليلة (${_size(free)}) — أفرغ مساحة قبل أن يمتلئ.'),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 8),
          ));
        }
      } catch (e) {
        debugPrint('💽 فحص القرص: $e');
      }
    }

    unawaited(tick());
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => unawaited(tick()));
  }
}
