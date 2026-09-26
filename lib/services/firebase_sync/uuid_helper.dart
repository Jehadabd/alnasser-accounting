import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// مولّد المعرّفات الفريدة للمزامنة عبر Firebase.
///
/// القاعدة الأساسية: كل سجل مالي (معاملة أو فاتورة) يحصل على معرّفه في نفس
/// اللحظة التي يُنشأ فيها، والمعرّف فريد بالبناء لا بالمصادفة. المعرّف يُستخدم
/// كمفتاح وثيقة في Firestore، لذلك يجب أن يخلو من "/" و "\" وألا يكون "." أو ".."
/// وألا يبدأ وينتهي بشرطتين سفليتين.
class UuidHelper {
  static final Random _random = Random.secure();

  /// بادئة تُميّز الجهاز، تُضبط مرة واحدة عند إقلاع التطبيق.
  /// وجودها يجعل التصادم بين جهازين مستحيلاً حتى لو تعطّل مولّد العشوائية.
  static String _devicePrefix = _randomBase36(6);

  /// يجب استدعاؤها مرة واحدة عند التهيئة بمعرّف الجهاز من إعدادات المزامنة.
  static void configureDevice(String deviceId) {
    final cleaned = deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (cleaned.isEmpty) return;
    _devicePrefix =
        cleaned.length > 8 ? cleaned.substring(0, 8).toLowerCase() : cleaned.toLowerCase();
  }

  static String _randomBase36(int length) {
    const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
    return List.generate(length, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  /// معرّف فاتورة جديد بنفس الضمانات.
  static String newInvoiceUuid() {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'inv_${micros.toRadixString(36)}_${_devicePrefix}_${_randomBase36(14)}';
  }

  /// معرّف معاملة مالية جديد (يُستخدم كمفتاح وثيقة في Firestore ومعرّف مزامنة).
  /// يُستدعى عند إنشاء المعاملة لضمان رفعها فوراً مع الفاتورة (مزامنة ذرية).
  static String newTransactionUuid() {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'tx_${micros.toRadixString(36)}_${_devicePrefix}_${_randomBase36(14)}';
  }

  /// معرّف منتج جديد (يُستخدم كمفتاح وثيقة في Firestore ومعرّف مزامنة).
  /// يُستدعى عند إنشاء المنتج لضمان رفعه للكتالوج الموحد.
  static String newProductUuid() {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'prod_${micros.toRadixString(36)}_${_devicePrefix}_${_randomBase36(14)}';
  }

  /// معرّف حركة مخزون (شراء، تعديل يدوي...) — مفتاح وثيقة في stock_movements.
  static String newStockMovementUuid() {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'mv_${micros.toRadixString(36)}_${_devicePrefix}_${_randomBase36(14)}';
  }

  /// هل المعرّف صالح كمفتاح وثيقة في Firestore؟
  static bool isValidId(String? id) {
    if (id == null || id.isEmpty) return false;
    if (id.contains('/') || id.contains('\\')) return false;
    if (id == '.' || id == '..') return false;
    if (RegExp(r'^__.*__$').hasMatch(id)) return false;
    return true;
  }

  /// ينقّي معرّفاً قديماً ليصلح لـ Firestore دون تغيير هويته على الأجهزة الأخرى
  /// (الاستبدال حتمي فيصل كل جهاز إلى نفس النتيجة).
  static String sanitizeId(String input) {
    final s = input.replaceAll('/', '_').replaceAll('\\', '_');
    if (s.isEmpty || s == '.' || s == '..') return 'unknown';
    if (RegExp(r'^__.*__$').hasMatch(s)) return 'id_$s';
    return s;
  }

  /// معرّف حتمي للسجلات القديمة فقط (التي أُنشئت قبل نظام المعرّفات الجديد
  /// ولا تحمل أي معرّف). يعتمد على بيانات ثابتة حتى يصل الجهازان إلى نفس
  /// المعرّف للسجل نفسه، فلا تتضاعف السجلات التاريخية في السحابة.
  ///
  /// ⚠️ لا تُستخدم للمعاملات الجديدة — استخدم
  /// [SyncSecurity.generateTransactionUuid] (اسم_المبلغ_التاريخ_الوقت).
  static String legacyTransactionUuid({
    required String customerName,
    required double amount,
    required DateTime date,
  }) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:'
        '${date.second.toString().padLeft(2, '0')}';
    final raw = '${customerName.trim()}_${amount.toStringAsFixed(2)}_$dateStr';
    // ⚠️ الصيغة الناتجة يجب ألا تتغير أبداً: سجلات قديمة تحمل هذا المعرّف بالفعل
    // على الأجهزة الأخرى، وأي تغيير هنا يُنتج نسخة ثانية منها في السحابة.
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// معرّف حتمي للفواتير القديمة فقط، بنفس منطق [legacyTransactionUuid].
  static String legacyInvoiceUuid({
    required String customerName,
    required double totalAmount,
    required DateTime invoiceDate,
  }) {
    final dateStr = '${invoiceDate.year}_'
        '${invoiceDate.month.toString().padLeft(2, '0')}_'
        '${invoiceDate.day.toString().padLeft(2, '0')}_'
        '${invoiceDate.hour.toString().padLeft(2, '0')}_'
        '${invoiceDate.minute.toString().padLeft(2, '0')}_'
        '${invoiceDate.second.toString().padLeft(2, '0')}';
    final raw = 'INV_${customerName.trim()}_${totalAmount.toStringAsFixed(2)}_$dateStr';
    // ⚠️ الصيغة الناتجة يجب ألا تتغير أبداً (انظر التعليق في legacyTransactionUuid).
    return 'INV_${sha256.convert(utf8.encode(raw))}';
  }
}
