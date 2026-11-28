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

import '../../customer_name_clean.dart';
import 'customer_locking.dart';
import 'customer_name_rule.dart';

class InvoiceCustomerClaim {
  InvoiceCustomerClaim(this.locks);

  final LockService locks;
  static const String resourceType = 'customer_name';

  int? _held; // مفتاح الحساب (الجديد)
  int? _heldLegacy; // مفتاح النسخ السابقة (لأجهزة لم تُحدَّث بعد)
  Timer? _beat;

  /// 🖥️ الشاشات المفتوحة على هذا الجهاز نفسه: كاشير + فاتورة (أو فاتورتان) لنفس العميل
  /// كانتا مسموحتين لأن قفل القاعدة يعرف «الجهاز» لا «الشاشة».
  static final Map<int, InvoiceCustomerClaim> _inProcess = {};

  /// مفتاح الحساب: هوية الحساب نفسها (CustomerNameRule: الاسم بلا مسافات) — فـ«جهاد عبد الناصر»
  /// و«جهاد عبدالناصر» و«جهاد    عبد الناصر» حساب واحد ⇒ حجز واحد.
  static String normalize(String s) => CustomerNameRule.key(CustomerNameClean.clean(s)).toLowerCase();

  /// مفتاح النسخ السابقة (يدمج المسافات فقط). يُحجز معه ما دامت في الشبكة أجهزة لم تُحدَّث،
  /// فتمنعها ونمنعها: جهاز قديم لا يعرف المفتاح الجديد.
  static String legacyNormalize(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// رقم ثابت للاسم (FNV-1a، 31 بت) — مفتاح القفل في جدول الأقفال
  static int keyOf(String normalized) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(normalized)) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h == 0 ? 1 : h;
  }

  static String _blockedMsg(String name, String? by) =>
      'اسم العميل «${name.trim()}» مستخدم الآن في فاتورة قيد الإنشاء أو التعديل على جهاز آخر'
      '${by != null && by.isNotEmpty ? ' ($by)' : ''}.\n'
      'انتظر حتى تُحفظ تلك الفاتورة أو تُغلق، ثم أعد المحاولة.';

  /// يحجز الاسم لهذا الجهاز وهذه الشاشة. يُرجع null إن نجح (أو لا حاجة للحجز)، وإلا رسالة المنع.
  Future<String?> claim(String name) async {
    final n = normalize(name);
    if (n.length < 2) {
      await release();
      return null;
    }
    final key = keyOf(n);

    // 1) شاشة أخرى على هذا الجهاز تحجز الحساب نفسه
    final other = _inProcess[key];
    if (other != null && !identical(other, this)) {
      return 'اسم العميل «${name.trim()}» مفتوح الآن في فاتورة أخرى على هذا الجهاز '
          '(الكاشير أو شاشة فاتورة).\nاحفظ تلك الفاتورة أو امسح الاسم منها أولاً.';
    }

    // 2) جهاز آخر (قفل القاعدة المشتركة). الحجز داخل الجهاز يُسجَّل قبل الانتظار كي لا تمر
    //    شاشتان كتبتا الاسم في اللحظة نفسها.
    final hadKey = _held == key;
    _inProcess[key] = this;
    void undoLocal() {
      if (!hadKey && identical(_inProcess[key], this)) _inProcess.remove(key);
    }

    final r = await locks.acquireLock(resourceType: resourceType, resourceId: key);
    if (!r.success) {
      undoLocal();
      return _blockedMsg(name, r.lockedBy);
    }

    final legacy = keyOf(legacyNormalize(CustomerNameClean.clean(name)));
    if (legacy != key) {
      final r2 = await locks.acquireLock(resourceType: resourceType, resourceId: legacy);
      if (!r2.success) {
        undoLocal();
        if (!hadKey) await locks.releaseLock(resourceType: resourceType, resourceId: key);
        return _blockedMsg(name, r2.lockedBy);
      }
    }
    // تبديل الحجز القديم (اسم آخر كان مكتوباً) بالجديد
    final oldKey = _held;
    final oldLegacy = _heldLegacy;
    _held = key;
    _heldLegacy = legacy != key ? legacy : null;
    if (oldKey != null && oldKey != key) {
      if (identical(_inProcess[oldKey], this)) _inProcess.remove(oldKey);
      await locks.releaseLock(resourceType: resourceType, resourceId: oldKey);
    }
    if (oldLegacy != null && oldLegacy != _heldLegacy && oldLegacy != key) {
      await locks.releaseLock(resourceType: resourceType, resourceId: oldLegacy);
    }
    _inProcess[key] = this;

    _beat ??= Timer.periodic(const Duration(minutes: 2), (_) {
      final k = _held;
      if (k != null) locks.keepAlive(resourceType: resourceType, resourceId: k);
      final l = _heldLegacy;
      if (l != null) locks.keepAlive(resourceType: resourceType, resourceId: l);
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
    final l = _heldLegacy;
    _held = null;
    _heldLegacy = null;
    if (k != null) {
      if (identical(_inProcess[k], this)) _inProcess.remove(k);
      await locks.releaseLock(resourceType: resourceType, resourceId: k);
    }
    if (l != null) {
      await locks.releaseLock(resourceType: resourceType, resourceId: l);
    }
  }
}
