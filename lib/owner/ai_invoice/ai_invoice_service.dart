// lib/owner/ai_invoice/ai_invoice_service.dart
//
// 🤖 قراءة فاتورة المورد (صورة أو PDF) بنماذج الذكاء الاصطناعي ثم مطابقة موادها مع موادنا.
// النماذج والمفاتيح والترتيب والتعاون بين نموذجين: الإعدادات ← النظام والأدوات ← نماذج
// الذكاء الاصطناعي (ai_invoice_engine.dart). متاحة لحساب المالك واشتراك المزامنة (SyncPerks).
//
// ترتيب المطابقة لكل سطر (الأقوى أولاً):
//   1) اسم تعلّمناه من تصحيح سابق لهذا المورد (أو عام)   ← ثقة 100%
//   2) اسم مطابق لاسم مادتنا بعد التطبيع                    ← ثقة 100%
//   3) مطابقة النموذج (matched_product_id) إن كان المعرّف موجوداً فعلاً
//   4) مطابقة محلية تقريبية (كلمات + أرقام المقاس)           ← ثقة أقل
//   5) لا شيء ⇒ «مادة جديدة»
//
// مفاتيح GEMINI_API_KEY في ملف ‎.env (الطريقة القديمة) تبقى تعمل إن لم يُضف مفتاح Gemini
// من الإعدادات.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../models/product.dart';
import '../../services/ai_models/ai_vision_client.dart' show AiBlob;
import '../../services/sync_perks.dart';
import 'ai_alias_store.dart';
import 'ai_invoice_engine.dart';

/// مصدر المطابقة — يظهر للمستخدم كشارة
enum AiMatchSource { learned, exact, ai, local, manual, none }

class AiInvoiceLine {
  AiInvoiceLine({
    required this.originalName,
    required this.cleanName,
    required this.qty,
    required this.price,
    required this.amount,
    required this.saleUnit,
    required this.unitType,
    required this.unitsCount,
    this.productId,
    this.confidence = 0,
    this.reason = '',
    this.source = AiMatchSource.none,
    this.isFree = false,
    this.note = '',
    this.expiry,
    this.rowNo,
    this.repGift = false,
  });

  final String originalName; // كما في فاتورة المورد
  final String cleanName; // الاسم المنظّف/المقترح من النموذج
  double qty;
  double price;
  double amount;
  String saleUnit; // وحدة الشراء في فاتورة المورد (كرتون، لفة...)
  final String unitType; // meter | piece
  double unitsCount; // التعبئة: كم وحدة أساسية في وحدة الشراء
  int? productId; // null = مادة جديدة
  double confidence;
  String reason;
  AiMatchSource source;
  final bool isFree; // بونص/هدية: يدخل المخزون بلا كلفة
  String note; // ملاحظة فحص (تصحيح سعر، اختلاف تعبئة...)

  /// 📅 تاريخ انتهاء الصلاحية لهذا السطر «yyyy-MM-dd» إن كان في الفاتورة (null = لا يوجد).
  String? expiry;

  /// 🔢 رقم السطر في جدول الفاتورة (عمود ت/#) — لمعرفة سطر فاتته القراءة. null = غير مرقّم.
  int? rowNo;

  /// 🎁 هدية المندوب (عمود «هدية مندوب»): سطر مجاني يدخل المخزون بلا كلفة، يُميَّز عن بونص الشركة.
  final bool repGift;
  bool userChanged = false;
  bool include = true;
}

class AiInvoiceResult {
  AiInvoiceResult({
    required this.lines,
    this.invoiceNumber = '',
    this.date,
    this.currency = 'IQD',
    this.supplierName = '',
    this.grandTotal = 0,
    this.discount = 0,
    this.shipping = 0,
    this.amountPaid = 0,
    this.isCash = false,
    this.remaining = 0,
    this.previousBalance = 0,
    this.paymentEvidence = '',
    this.model = '',
    this.engineNote = '',
    this.rowsCount = 0,
    this.missingRows = const [],
  });
  final List<AiInvoiceLine> lines;
  final String invoiceNumber;
  final DateTime? date;
  final String currency;
  final String supplierName;
  final double grandTotal;
  final double discount;
  final double shipping;
  final double amountPaid;
  final bool isCash;

  /// الباقي من هذه الفاتورة ديناً (إن كُتب أو حُسب: الإجمالي − المدفوع).
  final double remaining;

  /// رصيد المورد السابق إن ظهر في الفاتورة (للعرض فقط — ليس دفعاً).
  final double previousBalance;

  /// النص الذي استُدلّ منه على الدفع («الواصل: 250,000»).
  final String paymentEvidence;

  /// النموذج (أو النموذجان) الذي قرأ وطابق.
  final String model;

  /// ملاحظة للمستخدم (مثلاً: لم تكتمل المطابقة الذكية فطوبقت الأسطر محلياً).
  final String engineNote;

  /// 🔢 عدد أسطر المواد في جدول الفاتورة كما قرأه النموذج (آخر رقم تسلسل). 0 = غير معروف.
  final int rowsCount;

  /// 🔢 أرقام أسطر في الفاتورة لم تُقرأ حتى بعد إعادة المحاولة (تُعرض للمستخدم ليضيفها).
  final List<int> missingRows;
}

class AiInvoiceException implements Exception {
  AiInvoiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiInvoiceService {
  AiInvoiceService._();

  static List<String> get apiKeys {
    final keys = <String>[];
    for (final k in const ['GEMINI_API_KEY', 'GEMINI_API_KEY_2', 'GEMINI_API_KEY_3', 'GEMINI_API_KEY_4']) {
      String v = '';
      try {
        v = (dotenv.env[k] ?? '').trim();
      } catch (_) {}
      if (v.isNotEmpty && !keys.contains(v)) keys.add(v);
    }
    return keys;
  }

  static bool get hasKeys => apiKeys.isNotEmpty;

  static String mimeFor(String fileName) {
    final n = fileName.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  // ───────────────────────── الوحدات ─────────────────────────

  static String baseUnitName(Product p) => p.unit == 'piece' ? 'قطعة' : (p.unit == 'meter' ? 'متر' : p.unit);

  /// كل وحدات المادة: الأساسية ثم الهرم (كرتون، باكيت...)
  static List<String> unitsOf(Product p) {
    final out = <String>[baseUnitName(p)];
    try {
      for (final level in p.getUnitHierarchyList()) {
        final u = (level['unit_name'] ?? '').toString().trim();
        if (u.isNotEmpty && !out.contains(u)) out.add(u);
      }
    } catch (_) {}
    return out;
  }

  /// نفس منطق شاشة فاتورة الشراء: كم وحدة أساسية في الوحدة المختارة.
  /// يُرجع null إن لم تكن الوحدة ضمن هرم المادة (نستعمل عندها تعبئة الفاتورة).
  static double? factorFromProduct(Product p, String unit) {
    final u = unit.trim();
    if (u.isEmpty || u == baseUnitName(p) || u == p.unit) return 1.0;
    double cumulative = 1.0;
    try {
      for (final level in p.getUnitHierarchyList()) {
        final name = (level['unit_name'] ?? '').toString().trim();
        final q = (level['quantity'] as num?)?.toDouble() ?? 1.0;
        if (name.isEmpty) continue;
        cumulative *= q;
        if (AiAliasStore.normalize(name) == AiAliasStore.normalize(u)) return cumulative > 0 ? cumulative : 1.0;
      }
    } catch (_) {}
    // وحدة غير معرّفة في هرم المادة ⇒ null فنستعمل تعبئة الفاتورة
    // (كان الرجوع إلى piecesPerUnit يعطي «لفة» مادةٍ بالمتر عدد قطع الكرتون)
    return null;
  }

  // ───────────────────────── الطلب ─────────────────────────

  static Future<AiInvoiceResult> extract({
    required List<int> bytes,
    required String mimeType,
    required List<Product> products,
    required int? supplierId,
    String supplierName = '',
    void Function(String status)? onStatus,
    /// 🖼️ صور إضافية لفاتورة من عدة صفحات (مع الصورة الأولى [bytes]) — تُقرأ فاتورةً واحدة
    List<AiBlob> moreImages = const [],
  }) async {
    if (!SyncPerks.enabled) {
      throw AiInvoiceException('هذه الميزة متاحة لحساب المالك واشتراك المزامنة');
    }
    final size = bytes.length + moreImages.fold<int>(0, (s, b) => s + b.bytes.length);
    if (size > 18 * 1024 * 1024) {
      throw AiInvoiceException('الملفات أكبر من 18 ميغابايت — صغّر الصور أو قسّم الـ PDF');
    }
    final live = products.where((p) => p.id != null && !p.isDeleted).toList();
    final aliases = await AiAliasStore.forSupplier(supplierId);
    try {
      return await AiInvoiceEngine.run(
        bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        mimeType: mimeType,
        products: live,
        aliases: aliases,
        supplierId: supplierId,
        supplierName: supplierName,
        onStatus: onStatus,
        moreImages: moreImages,
      );
    } on AiInvoiceException {
      rethrow;
    } catch (e) {
      throw AiInvoiceException('فشلت قراءة الفاتورة:\n$e');
    }
  }

  /// نص JSON من رد النموذج (مع إزالة ``` وما حوله).
  static Map<String, dynamic> decodeJson(String raw) => _decodeJson(raw);

  /// أسطر الفاتورة ورأسها من JSON النموذج (مع فحص الكمية × السعر = المبلغ).
  static AiInvoiceResult parse(Map<String, dynamic> j) => _parse(j);

  static Map<String, dynamic> _decodeJson(String raw) {
    var t = raw.trim();
    t = t.replaceAll(RegExp(r'^```(json)?', multiLine: false), '').replaceAll(RegExp(r'```$'), '').trim();
    dynamic v;
    try {
      v = jsonDecode(t);
    } catch (_) {
      final a = t.indexOf('{');
      final b = t.lastIndexOf('}');
      if (a < 0 || b <= a) throw AiInvoiceException('رد النموذج ليس JSON صالحاً');
      v = jsonDecode(t.substring(a, b + 1));
    }
    final Object? decoded = v;
    if (decoded is List) return <String, dynamic>{'line_items': decoded};
    if (decoded is! Map) throw AiInvoiceException('رد النموذج بصيغة غير متوقعة');
    return Map<String, dynamic>.from(decoded);
  }

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    var s = v.toString().trim();
    const ar = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(ar[i], '$i');
    }
    s = s.replaceAll('٫', '.').replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(s) ?? 0;
  }

  static AiInvoiceResult _parse(Map<String, dynamic> j) {
    final items = (j['line_items'] ?? j['items'] ?? const []) as List;
    final lines = <AiInvoiceLine>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final original = (m['original_name'] ?? m['name'] ?? '').toString().trim();
      final clean = (m['name'] ?? original).toString().trim();
      if (original.isEmpty && clean.isEmpty) continue;
      var qty = _num(m['qty'] ?? m['quantity']);
      var price = _num(m['price'] ?? m['unit_price']);
      var amount = _num(m['amount'] ?? m['line_total'] ?? m['total']);
      final isFree = m['is_free'] == true || m['is_free']?.toString() == 'true';
      var note = '';
      if (qty <= 0) qty = 1;
      if (price <= 0 && amount > 0) price = amount / qty;
      if (amount <= 0 && price > 0) amount = price * qty;
      if (price <= 0 && amount <= 0 && !isFree) continue; // ضجيج (عنوان، سطر فارغ)
      // 🔎 فحص السطر: الكمية × السعر يجب أن تساوي المبلغ (خطأ قراءة فاصل الآلاف شائع)
      if (price > 0 && amount > 0 && (qty * price - amount).abs() > amount * 0.02) {
        note = 'السعر المقروء ${price.toStringAsFixed(2)} لا يطابق المبلغ ÷ الكمية — اعتمدتُ المبلغ';
        price = amount / qty;
      }
      final unitType = (m['unit_type'] ?? 'piece').toString() == 'meter' ? 'meter' : 'piece';
      var units = _num(m['units_count']);
      if (units <= 0) units = 1;
      final mid = m['matched_product_id'];
      lines.add(AiInvoiceLine(
        originalName: original.isEmpty ? clean : original,
        cleanName: clean.isEmpty ? original : clean,
        qty: qty,
        price: price,
        amount: amount,
        saleUnit: (m['sale_unit'] ?? '').toString().trim(),
        unitType: unitType,
        unitsCount: units,
        productId: mid == null ? null : int.tryParse(mid.toString()),
        confidence: _num(m['confidence']).clamp(0, 1).toDouble(),
        reason: (m['reason'] ?? '').toString(),
        source: mid == null ? AiMatchSource.none : AiMatchSource.ai,
        isFree: isFree,
        note: note,
        expiry: normalizeExpiry(m['expiry'] ?? m['expiry_date'] ?? m['exp_date']),
        rowNo: _rowNo(m['row_no'] ?? m['row']),
        repGift: isFree && (m['rep_gift'] == true || m['rep_gift']?.toString() == 'true'),
      ));
    }
    final totals = (j['totals'] is Map) ? Map<String, dynamic>.from(j['totals']) : const <String, dynamic>{};
    final cur = (j['currency'] ?? '').toString().toUpperCase();
    final grand = _num(totals['grand_total']);
    final pay = paymentOf(j, grand);
    return AiInvoiceResult(
      lines: lines,
      invoiceNumber: (j['invoice_number'] ?? '').toString().trim(),
      date: DateTime.tryParse((j['invoice_date'] ?? '').toString().trim()),
      currency: (cur.contains('USD') || cur.contains(r'$') || cur.contains('دولار')) ? 'USD' : 'IQD',
      supplierName: (j['supplier_name'] ?? '').toString().trim(),
      grandTotal: grand,
      discount: _num(totals['discount']),
      shipping: _num(totals['shipping']),
      amountPaid: pay.paid,
      isCash: pay.cash,
      remaining: pay.remaining,
      previousBalance: pay.previous,
      paymentEvidence: pay.evidence,
      model: 'gemini-flash-latest',
      rowsCount: _rowNo(j['rows_count']) ?? 0,
    );
  }

  static int? _rowNo(Object? v) {
    final n = _num(v);
    return n >= 1 && n < 10000 && n == n.roundToDouble() ? n.toInt() : null;
  }

  /// 🔢 أرقام أسطر جدول الفاتورة التي لم تُقرأ: الفجوات في أرقام التسلسل (ت/#)، وما بعد
  /// آخر رقم حتى [rowsCount]. لا حكم إن لم يكن نصف الأسطر على الأقل مرقّماً.
  static List<int> missingRows(List<AiInvoiceLine> lines, int rowsCount) {
    final nums = <int>{for (final l in lines) if (l.rowNo != null) l.rowNo!};
    if (nums.isEmpty) return const [];
    final numbered = lines.where((l) => l.rowNo != null).length;
    if (numbered * 2 < lines.length) return const [];
    var last = nums.reduce((a, b) => a > b ? a : b);
    if (rowsCount > last && rowsCount <= last + 50) last = rowsCount;
    if (last > 500) return const [];
    return [for (var i = 1; i <= last; i++) if (!nums.contains(i)) i];
  }

  /// يضع أسطراً مقروءة من جديد في أماكنها حسب رقم السطر (ما بلا رقم يبقى مكانه).
  static void insertByRow(List<AiInvoiceLine> lines, Iterable<AiInvoiceLine> extra) {
    for (final x in extra) {
      final n = x.rowNo;
      final at = n == null ? -1 : lines.indexWhere((l) => l.rowNo != null && l.rowNo! > n);
      if (at < 0) {
        lines.add(x);
      } else {
        lines.insert(at, x);
      }
    }
  }

  /// 📅 تاريخ الصلاحية كما يكتبه النموذج أو الفاتورة ⇒ «yyyy-MM-dd» أو null.
  ///   2028-09-01 • 2028/9/1 • 01/09/2028 • 1-9-2028 • 09/2028 • 2028-09 • 09/28 ⇒ أول الشهر.
  ///   الشهر بلا يوم يُعدّ من أوله (الأحوط: لا نطيل صلاحية لم تُكتب). غير ذلك ⇒ null.
  static String? normalizeExpiry(Object? v) {
    if (v == null) return null;
    var s = v.toString().trim();
    const ar = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(ar[i], '$i');
    }
    if (s.isEmpty || s.toLowerCase() == 'null' || s == '-' || s == '—') return null;
    s = s.split(RegExp(r'[T ]')).first; // «2028-09-01T00:00:00»
    final parts = s.split(RegExp(r'[-/.]')).where((x) => x.isNotEmpty).toList();
    if (parts.any((x) => int.tryParse(x) == null)) return null;
    final n = parts.map(int.parse).toList();
    final int y0, mo, d;
    if (n.length == 3) {
      final yearFirst = parts[0].length == 4; // سنة-شهر-يوم، وإلا يوم/شهر/سنة (كما في الفواتير العراقية)
      y0 = yearFirst ? n[0] : n[2];
      mo = n[1];
      d = yearFirst ? n[2] : n[0];
    } else if (n.length == 2) {
      final yearFirst = parts[0].length == 4;
      y0 = yearFirst ? n[0] : n[1];
      mo = yearFirst ? n[1] : n[0];
      d = 1;
    } else {
      return null;
    }
    final y = y0 < 100 ? y0 + 2000 : y0;
    if (y < 2000 || y > 2100 || mo < 1 || mo > 12 || d < 1) return null;
    final last = DateTime(y, mo + 1, 0).day;
    if (d > last) return null;
    String two(int x) => x.toString().padLeft(2, '0');
    return '$y-${two(mo)}-${two(d)}';
  }

  /// الدفع من رد النموذج: «payment» الجديد، أو amount_paid/status القديمان.
  ///   • المدفوع غير مكتوب والباقي مكتوب ⇒ المدفوع = الإجمالي − الباقي (والعكس).
  ///   • المدفوع ≥ الإجمالي ⇒ نقد. باقٍ > 0 أو «دين/آجل» ⇒ دين. لا شيء مكتوب ⇒ دين بلا مدفوع.
  static ({double paid, bool cash, double remaining, double previous, String evidence}) paymentOf(
      Map<String, dynamic> j, double total) {
    final pay = j['payment'] is Map ? Map<String, dynamic>.from(j['payment'] as Map) : const <String, dynamic>{};
    final st = '${pay['status'] ?? j['status'] ?? ''}'.trim().toLowerCase();
    var paid = _num(pay['paid'] ?? j['amount_paid']);
    var remaining = _num(pay['remaining'] ?? j['remaining']);
    final previous = _num(pay['previous_balance'] ?? j['previous_balance']);
    final evidence = '${pay['evidence'] ?? ''}'.trim();
    if (total > 0) {
      if (paid <= 0 && remaining > 0 && remaining < total) paid = total - remaining;
      if (remaining <= 0 && paid > 0 && paid < total) remaining = total - paid;
      if (paid > total) paid = total;
    }
    final saysCredit = st == 'credit' || st == 'partial' || st.contains('دين') || st.contains('اجل') || st.contains('آجل') || st.contains('جزئي');
    final saysCash = st == 'cash' || (st.contains('نقد') && !st.contains('دين'));
    var cash = saysCash && !saysCredit;
    if (total > 0 && paid >= total - 0.5) cash = true;
    if (remaining > 0.5) cash = false;
    if (cash) {
      remaining = 0;
      if (total > 0) paid = total;
    }
    return (paid: paid, cash: cash, remaining: remaining, previous: previous, evidence: evidence);
  }

  /// قواعد قراءة الدفع والإجمالي (مشتركة بين التعليمات).
  static const paymentRules = '''## الإجمالي والدفع (مهم جداً — ابحث في أسفل الفاتورة وأعلاها، وفي الختم والكتابة اليدوية):
- grand_total: صافي مبلغ هذه الفاتورة وحدها بعد الخصم وقبل أي رصيد سابق. إن وُجد «المجموع» و«الخصم» و«الصافي» فالصافي هو grand_total.
  تحقّق: مجموع مبالغ الأسطر − الخصم + النقل ≈ grand_total. إن اختلف فأعد قراءة الإجمالي والأسطر.
- payment.paid: المدفوع الآن من هذه الفاتورة. كلماته: المدفوع، الواصل، المسدد، المستلم، دفعة، عربون، «نقداً» مع مبلغ.
- payment.remaining: الباقي منها ديناً. كلماته: المتبقي، الباقي، الآجل، المطلوب، دين، بالدين، على الحساب.
- payment.status: "cash" إن دُفعت كاملة (نقداً، مدفوعة، واصل بالكامل، المتبقي صفر)؛ "credit" إن لم يُدفع منها شيء (آجل، دين، على الحساب)؛ "partial" إن دُفع جزء.
- لم يُكتب شيء عن الدفع ⇒ status "credit" و paid 0.
- لا تخلط: «الرصيد السابق» و«الرصيد الحالي/الكلي» و«مجموع الحساب» حساب المورد كله — ليست دفعاً ولا باقياً من هذه الفاتورة. ضعها في payment.previous_balance فقط.
- payment.evidence: النص كما في الفاتورة الذي استدللت منه على الدفع (مثلاً «الواصل: 250,000») أو "".''';

  /// قواعد عدّ الأسطر: لا سطر يُترك ولا يُدمج (مشتركة بين التعليمات).
  static const rowsRules = '''### كل سطر في الجدول (مهم جداً):
- row_no: رقم السطر من عمود التسلسل (ت، #، No، م) إن وُجد، وإلا ترتيبه في الجدول بدءاً من 1. سطر الهدية/البونص الإضافي يأخذ رقم سطر مادته
- rows_count: عدد أسطر المواد في جدول الفاتورة كلها (آخر رقم تسلسل)
- اقرأ كل سطر مرقّم حتى آخر رقم، ولا تقفز فوق أي رقم
- لا تدمج سطرين متشابهين: نفس المادة بتركيز أو حجم مختلف (0.025% و 0.05%، 30G و 50G، 5mg و 10mg) سطران ومادتان
- السطر الذي خاناته فارغة (بلا صلاحية أو رقم دفعة) أو أرقامه مزاحة قليلاً عن خطه يبقى سطراً كاملاً — اقرأه''';

  /// قواعد قراءة تاريخ الصلاحية لكل سطر (مشتركة بين التعليمات).
  static const expiryRules = '''### تاريخ الصلاحية expiry (لكل سطر):
- إن كان في الجدول عمود صلاحية (Exp، Exp Date، Expiry، EXP، الصلاحية، تاريخ الانتهاء، ينتهي) فاكتب تاريخ ذلك السطر بصيغة YYYY-MM-DD
- اقرأ التاريخ كما في الفاتورة: 01/09/2028 = يوم/شهر/سنة ⇒ 2028-09-01؛ 09/2028 أو 9/28 ⇒ 2028-09-01
- لا عمود صلاحية، أو الخانة فارغة لهذا السطر ⇒ null. لا تخترع تاريخاً
- لا تضع هنا تاريخ الفاتورة، ولا رقم الدفعة (B.No، Batch، Lot)، ولا تاريخ الإنتاج (MFG)''';

  /// حقل الدفع في بنية JSON المطلوبة.
  static const paymentJson =
      '"payment": {"status": "credit", "paid": 0, "remaining": 0, "previous_balance": 0, "evidence": ""}';

  // ───────────────────────── المطابقة ─────────────────────────

  /// تُستدعى بعد القراءة، وتُعاد عند تغيير المورد (لا تمسّ ما غيّره المستخدم).
  static void applyMatching(List<AiInvoiceLine> lines, List<Product> products, List<AiAlias> aliases, int? supplierId) {
    final byId = {for (final p in products) p.id!: p};
    final byNorm = <String, Product>{};
    for (final p in products) {
      byNorm.putIfAbsent(AiAliasStore.normalize(p.name), () => p);
    }
    for (final l in lines) {
      if (l.userChanged) continue;
      // 1) تعلّم سابق
      final learned = AiAliasStore.lookup(aliases, l.originalName, supplierId);
      if (learned != null && byId.containsKey(learned)) {
        l.productId = learned;
        l.confidence = 1;
        l.source = AiMatchSource.learned;
        l.reason = 'صحّحتَ هذا الاسم سابقاً لهذه المادة';
        continue;
      }
      // 2) الاسم نفسه
      final exact = byNorm[AiAliasStore.normalize(l.originalName)] ?? byNorm[AiAliasStore.normalize(l.cleanName)];
      if (exact != null) {
        l.productId = exact.id;
        l.confidence = 1;
        l.source = AiMatchSource.exact;
        if (l.reason.isEmpty) l.reason = 'الاسم مطابق لاسم المادة';
        continue;
      }
      // 3) النموذج — بشرط أن يكون المعرّف حقيقياً
      if (l.source == AiMatchSource.ai && l.productId != null && byId.containsKey(l.productId) && l.confidence >= 0.5) {
        continue;
      }
      // 4) محلي تقريبي
      final best = _localBest(l, products);
      if (best != null) {
        l.productId = best.$1.id;
        l.confidence = best.$2;
        l.source = AiMatchSource.local;
        l.reason = 'مطابقة تقريبية بالكلمات والمقاسات — راجعها';
      } else {
        l.productId = null;
        l.confidence = 0;
        l.source = AiMatchSource.none;
        if (l.reason.isEmpty) l.reason = 'لم أجد مادة مطابقة';
      }
    }
  }

  static final _numRe = RegExp(r'\d+(?:\.\d+)?');

  static Set<String> _tokens(String s) => AiAliasStore.normalize(s)
      .replaceAll('x', ' ')
      .split(' ')
      .where((t) => t.length > 1 || _numRe.hasMatch(t))
      .toSet();

  static (Product, double)? _localBest(AiInvoiceLine l, List<Product> products) {
    final a = _tokens('${l.originalName} ${l.cleanName}');
    if (a.isEmpty) return null;
    final aNums = a.where((t) => _numRe.hasMatch(t)).toSet();
    (Product, double)? best;
    for (final p in products) {
      final b = _tokens(p.name);
      if (b.isEmpty) continue;
      final bNums = b.where((t) => _numRe.hasMatch(t)).toSet();
      // أرقام المقاس يجب أن تتفق إن وُجدت في الطرفين (2×1.5 ≠ 2×2.5)
      if (aNums.isNotEmpty && bNums.isNotEmpty && !bNums.every(aNums.contains)) continue;
      final inter = a.intersection(b).length;
      if (inter == 0) continue;
      final score = inter / b.length * 0.7 + inter / a.length * 0.3;
      if (best == null || score > best.$2) best = (p, score);
    }
    if (best == null || best.$2 < 0.6) return null;
    return (best.$1, (best.$2 * 0.75).clamp(0.4, 0.75).toDouble());
  }

  // ───────────────────────── التعليمات ─────────────────────────

  /// كم وحدة أساسية في كل مستوى (الهرم يُحفظ نسبةً للمستوى السابق ⇒ نضرب تراكمياً)
  static List<List<Object>> cumulativeUnits(Product p) {
    final out = <List<Object>>[];
    double f = 1;
    try {
      for (final level in p.getUnitHierarchyList()) {
        final u = (level['unit_name'] ?? '').toString().trim();
        final q = (level['quantity'] as num?)?.toDouble() ?? 1;
        if (u.isEmpty || q <= 0) continue;
        f *= q;
        out.add([u, f == f.roundToDouble() ? f.toInt() : f]);
      }
    } catch (_) {}
    return out;
  }

  static String buildPrompt({
    required List<Product> products,
    required List<AiAlias> aliases,
    required int? supplierId,
    String supplierName = '',
  }) {
    final byId = {for (final p in products) p.id!: p};
    // صيغة مضغوطة (أقل رموزاً ⇒ أرخص وأسرع ولا تتجاوز حصة المفتاح المجاني بسرعة):
    // [id, الاسم, الوحدة الأساسية, [[وحدة, كم وحدة أساسية فيها], ...], الكلفة]
    final catalog = [
      for (final p in products)
        [
          p.id,
          p.name,
          baseUnitName(p),
          cumulativeUnits(p),
          if ((p.costPrice ?? 0) > 0) p.costPrice,
        ]
    ];
    final learned = [
      for (final a in aliases)
        if (byId.containsKey(a.productId))
          [a.alias, a.productId, byId[a.productId]!.name, if (a.supplierId != 0) 1],
    ];
    final productsJson = jsonEncode(catalog);
    final learnedJson = jsonEncode(learned.take(400).toList());
    final who = supplierName.trim().isEmpty ? '' : ' (المورد: ${supplierName.trim()})';

    return '''أنت محاسب ذكي خبير في تحليل فواتير الشراء التجارية العراقية$who. تعمل كإنسان يقرأ الفاتورة ويبحث عن المنتجات في قاعدة بيانات المحل.

## مهمتك الأساسية:
1. اقرأ الفاتورة (صورة أو PDF، مطبوعة أو بخط اليد، كل الصفحات) واستخرج كل المنتجات بدقة
2. لكل منتج في الفاتورة، ابحث عن أقرب تطابق في قائمة منتجاتنا أدناه
3. استخدم اسم المنتج من القاعدة (وليس من الفاتورة) إذا وجدت تطابق
4. **مهم جداً**: حدّد وحدة الشراء والتعبئة (كم وحدة أساسية فيها) لكل منتج

## قائمة منتجاتنا (كل عنصر: [id, الاسم, الوحدة الأساسية, الوحدات الأكبر, الكلفة]):
- "الوحدات الأكبر" = [[اسم الوحدة, كم وحدة أساسية فيها], ...]
  مثال: [12, "كوب ماء", "قطعة", [["باكيت", 20], ["كرتون", 120]], 250]
  يعني: الباكيت = 20 قطعة، الكرتون = 120 قطعة، كلفة القطعة 250
- الوحدة الأساسية ليست دائماً قطعة أو متر: قد تكون كغم، لتر، غرام، زوج، درزن... حسب المادة
$productsJson

## 🧠 أسماء تعلّمناها من تصحيحات المستخدم (الأولوية القصوى):
كل عنصر: [الاسم كما كتبه المورد, id مادتنا, اسم مادتنا, 1 إن كان خاصاً بهذا المورد]
إذا ظهر في الفاتورة اسم مطابق لأحدها أو قريب جداً منه (اختلاف إملائي/مسافات/ترتيب) →
استخدم id نفسه و confidence = 0.99 و reason = "تعلّم سابق".
تعلّم منها أيضاً أسلوب هذا المورد في التسمية (اختصاراته، ترتيب المقاسات، كتابة الماركة) وطبّقه على بقية المواد.
$learnedJson

## كيف تُطابق المنتجات (تعلم من البيانات):

### الخطوة 1: حلل أسماء المنتجات في القاعدة
انظر للأسماء الموجودة وافهم التنسيق المستخدم. مثلاً إذا رأيت:
- "سيمنس 2×1.5 بيرلي" → التنسيق هو: [نوع] [عدد×مقاس] [ماركة]
- "فلكس 3×2.5 ناشيونال" → نفس التنسيق

### الخطوة 2: استخرج العناصر من اسم المنتج في الفاتورة
مثال: "Berly 80M 1.5*2 سيمس" يحتوي على:
- ماركة: Berly (بالإنجليزي)
- طول اللفة: 80M (يُحذف من الاسم لكن يُحفظ في units_count!)
- مقاس: 1.5*2
- نوع: سيمس

### الخطوة 3: طابق مع القاعدة
ابحث عن منتج يحتوي على نفس العناصر (ماركة + نوع + مقاس/حجم/وزن/لون)
- اختلاف المقاس أو الحجم أو الوزن (2×1.5 مقابل 2×2.5، 500مل مقابل 1لتر، 16mm مقابل 20mm) = منتج مختلف، لا تطابقهما أبداً
- لا تخترع id: يجب أن يكون موجوداً حرفياً في القائمة أعلاه
- إذا تردّدت بين مادتين فاختر الأقرب واخفض confidence واذكر البديل في reason

## قواعد أساسية ثابتة:

### 1. وحدة الشراء sale_unit:
- انظر لعمود "الوحدة" في جدول الفاتورة (لفة، كرتون، باكيت، قطعة، كيس، شدة، درزن، متر، كغم، طن، لتر...)
- صحّح الإملاء: "كارتون" → "كرتون"، "باكت" → "باكيت"، "كيلو" → "كغم"
- **إذا كان للمادة المطابقة وحدة بنفس المعنى في "الوحدات الأكبر" أو الأساسية فاكتب اسمها كما هو عندنا حرفياً**
  (مثلاً الفاتورة "كارتونة" وعندنا "كرتون" → sale_unit: "كرتون")
- إذا لا يوجد عمود وحدة: الوحدة الأساسية للمادة

### 2. التعبئة units_count = كم وحدة أساسية (للمادة المطابقة) في وحدة الشراء:
- إذا كانت sale_unit من وحدات المادة عندنا → units_count = الرقم المسجّل عندنا لها
  إلا إذا كتبت الفاتورة تعبئة مختلفة صراحةً (مثل "كرتون 24" وعندنا كرتون = 20) → اكتب رقم الفاتورة 24 واذكر الاختلاف في reason
- رقم متبوع بـ M أو متر في الاسم → طول اللفة: "80M" → units_count: 80، "M 91.4" → 91.4، "250M" → 250، "90 متر" → 90، و sale_unit: "لفة"
- كيبل/سلك بلا طول في الاسم والوحدة "متر" والكمية كبيرة → الكمية بالمتر: sale_unit: "متر"، units_count: 1
- "تعبئة 20" أو "20 قطعة" أو "×20" بجانب الكرتون/الباكيت → units_count: 20
- عمود فيه رقم + وحدة مثل "10 باكيت" أو "100 قطعة": استعمل فحص qty × price ≈ amount لتعرف لأي شيء السعر:
  السعر لعبوة كاملة → sale_unit = العبوة (كرتون/كيس/باكيت) و units_count = الرقم؛ السعر للقطعة → sale_unit = الوحدة المكتوبة و units_count = 1
- "درزن" = 12، "شدة" حسب ما يُكتب
- أوزان: طن = 1000 كغم، كغم = 1000 غرام (إذا الأساسية كغم والشراء بالطن → units_count: 1000)
- الوحدة = الأساسية → units_count: 1
- طول اللفة والتعبئة تُحذف من الاسم المنظّف لكن تُحفظ في units_count

### 3. ترتيب المقاس قد يكون معكوساً:
- في الفاتورة: 1.5*2 (مقاس×عدد)
- في القاعدة: 2×1.5 (عدد×مقاس)
- المهم: نفس الأرقام = نفس المنتج

### 4. الترجمة بين الإنجليزي والعربي:
ابحث عن الكلمات المتشابهة صوتياً (أمثلة):
- Berly/BERLY ≈ بيرلي
- Flex/FLEX ≈ فلكس
- National ≈ ناشيونال
- Pioneer ≈ بايونير
- SIMS/Siemens/سيمس ≈ سيمنس

### 5. الرموز المختصرة (أمثلة):
- B = بيرلي (Berly)
- XW/W = سيمنس
- F = فلكس
- مثال: B2-4-80XW = بيرلي 2×4 سيمنس 80 متر

### 6. قراءة الأرقام في الفواتير العراقية (مهم جداً!):
- الأرقام العربية ٠١٢٣٤٥٦٧٨٩ → 0123456789
- بالدينار: النقطة أو الفارزة قبل 3 أرقام بالضبط فاصل آلاف وليست كسراً: "1.500" أو "1,500" = 1500، "12.750.000" = 12750000
- بالدولار الكسور طبيعية: "12.5" = 12.5
- "الأسعار بالألف" أو "×1000" في رأس العمود → اضرب السعر والمبلغ في 1000
- **تحقّق من كل سطر: qty × price ≈ amount**. إذا لم يتطابق فأعد قراءة الأرقام؛ وإذا بقي الاختلاف فاعتمد amount و qty واحسب price = amount ÷ qty
- الخصم على السطر (عمود خصم أو %): price = السعر الصافي بعد الخصم، و amount = المبلغ الصافي
- خصم على كامل الفاتورة: ضعه في totals.discount ولا توزّعه على الأسطر

### 7. البونص والهدايا:
- سطر "بونص" أو "هدية" أو "مجاناً" أو كمية إضافية بسعر 0 → أدرجه بـ price: 0 و amount: 0 و is_free: true (يدخل المخزون بلا كلفة)
- "10+1" في عمود الكمية → سطر بكمية 10 بسعرها، وسطر ثانٍ للمادة نفسها بكمية 1 و is_free: true
- عمود «هدية» أو «بونص» بجانب الكمية وفيه رقم أكبر من صفر → سطر ثانٍ للمادة نفسها بتلك الكمية و is_free: true
- عمود «هدية مندوب» أو «هدية المندوب» وفيه رقم أكبر من صفر → سطر آخر للمادة نفسها بتلك الكمية و is_free: true و rep_gift: true
- الصفر في عمودي الهدية لا يُنشئ سطراً

$expiryRules

### 8. ما لا يُدرج كمنتجات:
- أسطر المجموع، الخصم، الأجور، النقل، الرصيد السابق، الملاحظات، العناوين
- (أجور النقل إن وُجدت ضعها في totals.shipping)

## البنية المطلوبة (JSON object فقط، ليس مصفوفة):
{
  "supplier_name": "اسم المورد/الشركة كما في رأس الفاتورة",
  "invoice_date": "YYYY-MM-DD",
  "invoice_number": "",
  "currency": "IQD أو USD",
  "line_items": [
    {
      "name": "اسم المنتج من قاعدة البيانات (إذا وُجد تطابق) أو الاسم المُنظف",
      "original_name": "الاسم الأصلي كما في الفاتورة بالضبط",
      "qty": 0,
      "price": 0,
      "amount": 0,
      "unit_type": "meter أو piece أو weight",
      "sale_unit": "وحدة الشراء",
      "units_count": 1,
      "is_free": false,
      "rep_gift": false,
      "expiry": null,
      "row_no": 1,
      "matched_product_id": null,
      "confidence": 0.0,
      "reason": "شرح المطابقة باختصار"
    }
  ],
  "rows_count": 0,
  "totals": {"subtotal": 0, "discount": 0, "shipping": 0, "grand_total": 0},
  $paymentJson
}

$paymentRules

$rowsRules

## قواعد الحقول:

### confidence (0.0 - 1.0):
- 0.90-1.0: تطابق مؤكد (كل العناصر متطابقة)
- 0.70-0.89: تطابق جيد (معظم العناصر متطابقة)
- 0.50-0.69: تطابق محتمل (بعض العناصر متطابقة)
- أقل من 0.50: منتج جديد → matched_product_id = null

### reason (مهم جداً):
اشرح بالعربي باختصار كيف طابقت المنتج:
- "تطابق: Berly=بيرلي، سيمس=سيمنس، 1.5*2=2×1.5"
- "منتج جديد: لم أجد ماركة X في القاعدة"
- "تعبئة الكرتون في الفاتورة 24 وعندنا 20"

## تنبيهات:
- أرجع JSON object فقط (ليس مصفوفة!) بدون أي نص إضافي
- اقرأ الأرقام بدقة (الكمية، السعر، المبلغ) وتحقّق منها كما في القاعدة 6
- استخرج العملة من الفاتورة (IQD أو USD أو \$ أو دولار)
- التاريخ: إذا كُتب يوم/شهر/سنة (مثل 18/10/2026) فحوّله إلى 2026-10-18
- **لا تنسَ وحدة الشراء والتعبئة لكل منتج!**''';
  }
}
