// lib/services/disk_space/disk_free_io.dart
//
// ويندوز: GetDiskFreeSpaceEx من kernel32 — المساحة المتاحة لهذا المستخدم (تراعي
// الحصص). أي فشل ⇒ null (غير معروفة) ولا يرمي.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class DiskFree {
  DiskFree._();

  /// البايتات المتاحة على القرص الذي فيه [path] (null = غير معروفة)
  static int? bytesFor(String path) {
    if (!Platform.isWindows) return null;
    final dir = path.toNativeUtf16();
    final free = calloc<Uint64>();
    try {
      final ok = GetDiskFreeSpaceEx(dir, free, nullptr, nullptr);
      if (ok == 0) return null;
      return free.value;
    } catch (_) {
      return null;
    } finally {
      calloc.free(dir);
      calloc.free(free);
    }
  }
}
