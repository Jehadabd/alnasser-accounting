// lib/services/database/business/invoice_customer_claim.dart
//
// 🔒 حجز «اسم العميل» أثناء إنشاء فاتورة أو تعديلها.
//
// حين يكتب جهاز اسم عميل في فاتورة مفتوحة، يُحجز هذا الاسم باسم الجهاز
// والمستخدم في جدول الأقفال (resource_locks) داخل قاعدة السيرفر. فإذا كتب
// جهاز آخر الاسم نفسه في فاتورة أخرى يُمنع برسالة واضحة، حتى تُحفظ الفاتورة
// الأولى أو تُغلق. يعمل لعميل موجود ولعميل جديد لم يُحفظ بعد (بالاسم لا بالرقم)،
// فلا يُنشئ جهازان عميلين مكررين بالاسم نفسه في اللحظة نفسها.
//
// • على الشبكة المحلية: كل الأجهزة تقرأ جدول الأقفال نفسه في قاعدة السيرفر.
// • الحجز يتجدد كل دقيقتين ما دامت الشاشة مفتوحة، وينتهي وحده بعد 5 دقائق
//   إن انطفأ الجهاز فجأة، فلا يبقى اسم محجوزاً إلى الأبد.

import 'dart:async';
import 'dart:convert';

import 'customer_locking.dart';

class InvoiceCustomerClaim {
  InvoiceCustomerClaim(this.locks);

  final LockService locks;
  static const String resourceType = 'customer_name';

  int? _held;
  Timer? _beat;

  /// تطبيع الاسم: بلا فراغات زائدة، وبلا فرق بين الأحرف الكبيرة والصغيرة
  static String normalize(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// رقم ثابت للاسم (FNV-1a، 31 بت) — مفتاح القفل في جدول الأقفال
  static int keyOf(String normalized) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(normalized)) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h == 0 ? 1 : h;
  }

  /// يحجز الاسم لهذا الجهاز. يُرجع null إن نجح (أو لا حاجة للحجز)، وإلا رسالة المنع.
  Future<String?> claim(String name) async {
    final n = normalize(name);
    if (n.length < 2) {
      await release();
      return null;
    }
    final key = keyOf(n);
    final r = await locks.acquireLock(resourceType: resourceType, resourceId: key);
    if (!r.success) {
      return 'اسم العميل «${name.trim()}» مستخدم الآن في فاتورة قيد الإنشاء أو التعديل على جهاز آخر'
          '${r.lockedBy != null && r.lockedBy!.isNotEmpty ? ' (${r.lockedBy})' : ''}.\n'
          'انتظر حتى تُحفظ تلك الفاتورة أو تُغلق، ثم أعد المحاولة.';
    }
    final old = _held;
    _held = key;
    if (old != null && old != key) {
      await locks.releaseLock(resourceType: resourceType, resourceId: old);
    }
    _beat ??= Timer.periodic(const Duration(minutes: 2), (_) {
      final k = _held;
      if (k != null) locks.keepAlive(resourceType: resourceType, resourceId: k);
    });
    return null;
  }

  /// قبل الحفظ مباشرة: يتأكد أن الاسم ما زال محجوزاً لهذا الجهاز (أو يحجزه الآن).
  Future<String?> verify(String name) => claim(name);

  /// يحرر الاسم (عند الحفظ أو إغلاق الشاشة أو مسح الاسم)
  Future<void> release() async {
    _beat?.cancel();
    _beat = null;
    final k = _held;
    _held = null;
    if (k != null) {
      await locks.releaseLock(resourceType: resourceType, resourceId: k);
    }
  }
}
