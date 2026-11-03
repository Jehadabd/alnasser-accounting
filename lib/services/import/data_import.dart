// lib/services/import/data_import.dart
//
// 📥 استيراد العملاء والمواد والموردين من جدول Excel/CSV — بخطوتين:
//
//   1) [DataImport.plan] — قراءة فقط: يربط الأعمدة بالحقول، يحوّل الأرقام بصرامة،
//      ويقسم الصفوف إلى «سيُضاف» و«مُتجاوز» (مع السبب) و«خطأ» (رقم غير مفهوم).
//      لا يكتب شيئاً.
//   2) [DataImport.execute] — بعد تأكيد المستخدم:
//        • نسخة احتياطية كاملة من القاعدة أولاً؛ إن فشلت لا يُستورد شيء.
//        • العملاء والموردون: كل الصفوف في معاملة واحدة — كلها أو لا شيء.
//          قبل الحفظ النهائي يُعاد حساب مجموع الأرصدة الافتتاحية من القاعدة نفسها،
//          وإن اختلف عن المعاينة فلساً واحداً تُلغى المعاملة كلها.
//        • المواد: كل مادة عبر مسار «إدخال بضاعة» نفسه (insertProduct: الرصيد
//          الافتتاحي في دفتر المخزون والمزامنة)، ثم تُطابق الكمية والسعر بعد الحفظ.
//
// قواعد الأمان الحسابي:
//   • عميل أو مورد موجود بالاسم نفسه: المستخدم يختار لكل اسم [ExistingAction]
//     (قرار المالك 2026-11-03): دمج الدينين (يُضاف مبلغ الملف)، أو مبلغ الملف هو
//     الصحيح (تسوية بالفرق فيصير الدين = مبلغ الملف)، أو الدين الحالي هو الصحيح
//     (لا شيء). بلا اختيار لا يبدأ الاستيراد. المعاملة تذكر الملف والصف ومن قام
//     بالاستيراد، ولا تُمس بطاقته (الهاتف والعنوان).
//   • إعادة استيراد الملف نفسه (بصمة محتواه) لا تضيف أي مبلغ مرة ثانية: لكل صف
//     مفتاح ثابت (البصمة + النوع + الاسم) في سجل data_import_rows وفي معرّف
//     المعاملة، والصف الذي سبق استيراده يُتجاوز مع ذكر تاريخه.
//   • المادة الموجودة تُتجاوز ولا يُمس سعرها ولا كميتها.
//   • الرصيد يُسجَّل «رصيداً افتتاحياً» بمعاملة بتاريخ يختاره المستخدم (قيد على
//     «رأس المال الافتتاحي» كما في إضافة عميل أو مورد يدوياً) — لا يُكتب رقم في
//     البطاقة بلا معاملة تسنده.
//   • الرقم غير الواضح («1.234,5» أو «abc») يُرفض ولا يُخمَّن.
//   • الفترة المثبّتة: لا رصيد افتتاحي بتاريخ داخلها.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha1;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../erp/activity/activity_log.dart';
import '../../erp/erp_common.dart' show PeriodLock;
import '../../models/customer.dart';
import '../../models/product.dart';
import '../../models/supplier.dart';
import '../backup_files.dart';
import '../database/business/customer_name_rule.dart';
import '../database/business/supplier_debt_reconciler.dart';
import '../database/business/tx_author.dart';
import '../database/core/database_helpers.dart';
import '../database/dao/customer_dao.dart';
import '../database/supplier_compat.dart';
import '../database_service.dart';
import '../firebase_sync/uuid_helper.dart';
import '../../utils/money_calculator.dart';
import '../name_search.dart';
import 'sheet_reader.dart';

enum ImportKind { customers, products, suppliers }

extension ImportKindText on ImportKind {
  String get label => switch (this) {
        ImportKind.customers => 'العملاء وأرصدتهم',
        ImportKind.products => 'المواد',
        ImportKind.suppliers => 'الموردون وأرصدتهم',
      };
  String get noun => switch (this) {
        ImportKind.customers => 'عميل',
        ImportKind.products => 'مادة',
        ImportKind.suppliers => 'مورد',
      };
}

/// حقل في التطبيق يُربط بعمود من الملف.
class ImportField {
  const ImportField(this.key, this.label, {this.required = false, this.numeric = false, this.synonyms = const []});
  final String key;
  final String label;
  final bool required;
  final bool numeric;
  final List<String> synonyms;
}

class ImportFields {
  ImportFields._();

  static const _name = ['الاسم', 'اسم', 'name'];
  static const _phone = ['الهاتف', 'هاتف', 'رقم الهاتف', 'رقم الموبايل', 'موبايل', 'جوال', 'تلفون', 'phone', 'mobile', 'tel'];
  static const _address = ['العنوان', 'عنوان', 'المنطقة', 'address'];
  static const _note = ['ملاحظة', 'ملاحظات', 'note', 'notes'];
  static const _balance = ['الرصيد', 'رصيد', 'الدين', 'دين', 'المتبقي', 'المبلغ', 'مبلغ', 'المطلوب', 'balance', 'debt', 'amount'];

  static List<ImportField> of(ImportKind k) => switch (k) {
        ImportKind.customers => const [
            ImportField('name', 'اسم العميل', required: true,
                synonyms: [..._name, 'اسم العميل', 'العميل', 'الزبون', 'اسم الزبون', 'customer', 'customer name']),
            ImportField('phone', 'رقم الهاتف', synonyms: _phone),
            ImportField('address', 'العنوان', synonyms: _address),
            ImportField('balance', 'الرصيد (الدين)', numeric: true, synonyms: _balance),
            ImportField('note', 'ملاحظة', synonyms: _note),
          ],
        ImportKind.suppliers => const [
            ImportField('name', 'اسم المورد', required: true,
                synonyms: [..._name, 'اسم المورد', 'المورد', 'الشركة', 'supplier', 'vendor', 'company']),
            ImportField('phone', 'رقم الهاتف', synonyms: _phone),
            ImportField('address', 'العنوان', synonyms: _address),
            ImportField('balance', 'الرصيد', numeric: true, synonyms: _balance),
            ImportField('currency', 'العملة (دينار/دولار)', synonyms: ['العملة', 'عملة', 'currency']),
            ImportField('note', 'ملاحظة', synonyms: _note),
          ],
        ImportKind.products => const [
            ImportField('name', 'اسم المادة', required: true,
                synonyms: [..._name, 'اسم المادة', 'المادة', 'الصنف', 'اسم الصنف', 'المنتج', 'product', 'item', 'description']),
            ImportField('price', 'سعر البيع', required: true, numeric: true,
                synonyms: ['سعر البيع', 'البيع', 'السعر', 'سعر', 'المفرد', 'price', 'sale price', 'selling price']),
            ImportField('cost', 'الكلفة (سعر الشراء)', numeric: true,
                synonyms: ['الكلفة', 'كلفة', 'التكلفة', 'سعر الشراء', 'الشراء', 'cost', 'purchase price']),
            ImportField('qty', 'الكمية الحالية', numeric: true,
                synonyms: ['الكمية', 'كمية', 'المخزون', 'الموجود', 'العدد', 'qty', 'quantity', 'stock']),
            ImportField('barcode', 'الباركود', synonyms: ['الباركود', 'باركود', 'الكود', 'كود', 'رمز', 'barcode', 'code', 'sku']),
            ImportField('unit', 'الوحدة (قطعة/متر)', synonyms: ['الوحدة', 'وحدة', 'unit']),
          ],
      };
}

/// تخمين الربط من أسماء الأعمدة (يعدّله المستخدم قبل المعاينة).
class ColumnGuess {
  ColumnGuess._();

  static String _k(String s) => NameSearch.compact(s).toLowerCase();

  /// field.key ← رقم العمود (أو null).
  static Map<String, int?> guess(List<String> headers, ImportKind kind) {
    final fields = ImportFields.of(kind);
    final hk = headers.map(_k).toList();
    final used = <int>{};
    final out = <String, int?>{for (final f in fields) f.key: null};
    // مرور أول بالمطابقة التامة، ثم بالاحتواء
    for (final exact in [true, false]) {
      for (final f in fields) {
        if (out[f.key] != null) continue;
        for (final syn in f.synonyms) {
          final s = _k(syn);
          if (s.isEmpty) continue;
          final i = [
            for (var j = 0; j < hk.length; j++)
              if (!used.contains(j) && hk[j].isNotEmpty && (exact ? hk[j] == s : hk[j].contains(s))) j
          ];
          if (i.isNotEmpty) {
            out[f.key] = i.first;
            used.add(i.first);
            break;
          }
        }
      }
    }
    return out;
  }
}

class ImportOptions {
  ImportOptions({
    required this.openingDate,
    this.headerRow = 0,
    this.positiveIsNormal = true,
    this.defaultCurrency = 'IQD',
    this.addToExisting = true,
    this.sourceId = '',
  });

  /// العملاء والموردون الموجودون بالاسم نفسه: يُضاف مبلغهم بمعاملة (true) أو يُتجاوزون.
  bool addToExisting;

  /// بصمة محتوى الملف ([fileFingerprint]) — تمنع إضافة الملف نفسه مرتين. فارغة = بلا منع.
  String sourceId;

  /// تاريخ الرصيد الافتتاحي لكل العملاء/الموردين المستوردين.
  DateTime openingDate;

  /// صف العناوين (من 0). الصفوف بعده هي البيانات.
  int headerRow;

  /// العملاء: موجب = عليه لنا. الموردون: موجب = له علينا. false = العكس.
  bool positiveIsNormal;

  /// عملة رصيد المورد إن لم يُربط عمود عملة أو كانت الخلية فارغة.
  String defaultCurrency;
}

/// صف صالح للإضافة.
class PlanRow {
  PlanRow({required this.line, required this.name});
  final int line; // رقم الصف في Excel (من 1)
  final String name;
  String? phone;
  String? address;
  String? note;
  String? barcode;
  String unit = 'piece';
  String currency = 'IQD';
  double balance = 0; // بعد الإشارة: العميل موجب = عليه، المورد موجب = له
  double price = 0;
  double? cost;
  double qty = 0;

  /// المستخدم قد يستبعد الصف من المعاينة قبل الاستيراد.
  bool include = true;

  /// القيمة كما في الملف (لإظهار ما عدّله المستخدم).
  double? originalBalance;
  double? originalPrice;
  double? originalQty;

  /// حساب موجود بالاسم نفسه يُضاف إليه المبلغ بمعاملة (null = حساب جديد).
  int? existingId;
  String? existingName;

  /// رصيده الحالي قبل الاستيراد (بعملة الصف للمورد).
  double existingBalance = 0;

  /// المفتاح الثابت للصف (null إن لم تُعرف بصمة الملف).
  String? rowKey;

  bool get isExisting => existingId != null;

  /// اختيار المستخدم للحساب الموجود (null = لم يختر بعد — يمنع الاستيراد).
  ExistingAction? action;

  /// الرصيد بعد الاستيراد حسب الاختيار (للمعاينة؛ الحفظ يعيد الحساب من القاعدة).
  double get balanceAfter => switch (action) {
        ExistingAction.merge => ImportNumbers.money(existingBalance + balance),
        ExistingAction.useFile => balance,
        _ => existingBalance,
      };

  bool get edited =>
      (originalBalance != null && (originalBalance! - balance).abs() > 0.004) ||
      (originalPrice != null && (originalPrice! - price).abs() > 0.004) ||
      (originalQty != null && (originalQty! - qty).abs() > 0.00001);
}

/// ما يُفعل بحساب موجود بالاسم نفسه.
enum ExistingAction {
  /// دمج الدينين: يُضاف مبلغ الملف إلى دينه الحالي.
  merge,

  /// مبلغ الملف هو الصحيح: معاملة تسوية بالفرق فيصير دينه = مبلغ الملف.
  useFile,

  /// الدين الحالي هو الصحيح: لا يُكتب شيء.
  keep;

  String get label => switch (this) {
        ExistingAction.merge => 'دمج الدينين',
        ExistingAction.useFile => 'مبلغ الملف هو الصحيح',
        ExistingAction.keep => 'الدين الحالي هو الصحيح',
      };
}

/// صف لن يُضاف: [error] = خطأ في البيانات (رقم غير مفهوم...)، وإلا تجاوز (موجود/مكرر/فارغ).
class SkipRow {
  SkipRow(this.line, this.name, this.reason, {this.error = false});
  final int line;
  final String name;
  final String reason;
  final bool error;
}

class ImportPlan {
  ImportPlan(this.kind, List<PlanRow> all, this.skipped) : allRows = all;
  final ImportKind kind;

  /// كل الصفوف الصالحة (بما فيها ما استبعده المستخدم).
  final List<PlanRow> allRows;
  final List<SkipRow> skipped;

  /// ما سيُستورد فعلاً.
  List<PlanRow> get rows => allRows.where((r) => r.include).toList();

  List<SkipRow> get errors => skipped.where((s) => s.error).toList();

  /// مجموع الأرصدة لكل عملة.
  Map<String, double> get balanceByCurrency {
    final m = <String, double>{};
    for (final r in rows) {
      if (r.balance.abs() < 0.005) continue;
      m[r.currency] = ImportNumbers.money((m[r.currency] ?? 0) + r.balance);
    }
    return m;
  }

  double get positiveTotal => ImportNumbers.money(rows.where((r) => r.balance > 0).fold(0.0, (s, r) => s + r.balance));
  double get negativeTotal => ImportNumbers.money(rows.where((r) => r.balance < 0).fold(0.0, (s, r) => s + r.balance));
  double get qtyTotal => rows.fold(0.0, (s, r) => s + r.qty);

  /// الحسابات الجديدة / الموجودة التي سيُضاف إليها مبلغ.
  List<PlanRow> get newRows => rows.where((r) => !r.isExisting).toList();
  List<PlanRow> get existingRows => rows.where((r) => r.isExisting).toList();
  double get existingTotal => ImportNumbers.money(existingRows.fold(0.0, (s, r) => s + r.balance));

  /// حسابات موجودة لم يُختر لها بعد.
  List<PlanRow> get undecided => existingRows.where((r) => r.action == null).toList();

  /// التغيّر المتوقع في أرصدة الحسابات الموجودة (حسب أرصدتها وقت المعاينة).
  double get existingDelta =>
      ImportNumbers.money(existingRows.fold(0.0, (s, r) => s + (r.balanceAfter - r.existingBalance)));
}

class ImportResult {
  ImportResult({required this.added, required this.skippedAtSave, required this.backupPath, required this.verified, this.problems = const []});
  final int added;

  /// حسابات موجودة أُضيف إليها مبلغ أو سُوّي دينها.
  int addedToExisting = 0;

  /// حسابات موجودة بقيت كما هي (اختيار «الدين الحالي هو الصحيح» أو لا فرق).
  List<SkipRow> kept = const [];

  /// صفوف تجاوزها الحفظ لأن اسمها ظهر بعد المعاينة (من جهاز آخر مثلاً).
  final List<SkipRow> skippedAtSave;
  final String backupPath;

  /// مطابقة ما حُفظ فعلاً مع المعاينة.
  final bool verified;
  final List<String> problems;
}

class DataImport {
  DataImport._();

  /// بصمة محتوى الملف (‎SHA-1، 20 حرفاً) — الملف نفسه بأي اسم يعطي البصمة نفسها.
  static String fileFingerprint(List<int> bytes) => sha1.convert(bytes).toString().substring(0, 20);

  static String _rowKey(String sourceId, ImportKind kind, String nameKey) => '$sourceId|${kind.name}|$nameKey';

  /// معرّف معاملة ثابت للصف: إعادة الاستيراد تجده فلا تكرر المبلغ (ولا المزامنة).
  static String _txUuid(String rowKey) => 'tximp_${sha1.convert(utf8.encode(rowKey)).toString().substring(0, 32)}';

  static String _author() {
    try {
      return TxAuthor.currentName?.call()?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  static String _fmt(double v) {
    final m = ImportNumbers.money(v);
    return m == m.truncateToDouble() ? m.toInt().toString() : m.toString();
  }

  static String _importNote(String fileName, PlanRow r) {
    final who = _author();
    return 'استيراد من Excel: «$fileName» — الصف ${r.line}${who.isEmpty ? '' : ' — بواسطة $who'}';
  }

  static Future<void> _ensureRowLedger(DatabaseExecutor db) => db.execute('''
      CREATE TABLE IF NOT EXISTS data_import_rows (
        row_key TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        entity_id INTEGER,
        amount REAL,
        currency TEXT,
        file_name TEXT,
        at TEXT NOT NULL
      )''');

  /// المفاتيح التي سبق استيرادها ← تاريخها.
  static Future<Map<String, String>> _importedBefore(DatabaseExecutor db, List<String> keys) async {
    final out = <String, String>{};
    if (keys.isEmpty) return out;
    try {
      for (var i = 0; i < keys.length; i += 500) {
        final part = keys.sublist(i, (i + 500).clamp(0, keys.length));
        final r = await db.rawQuery(
            'SELECT row_key, at FROM data_import_rows WHERE row_key IN (${List.filled(part.length, '?').join(',')})', part);
        for (final x in r) {
          out['${x['row_key']}'] = '${x['at'] ?? ''}';
        }
      }
    } on DatabaseException {
      // لا سجل بعد = لا استيراد سابق
    }
    return out;
  }

  // ─────────────────────────── 1) المعاينة (قراءة فقط) ───────────────────────────

  static String _customerKey(String n) => CustomerNameRule.key(n.trim());
  static String _looseKey(String n) => DatabaseHelpers.normalizeArabic(n.trim()).toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// رقم هاتف من خلية: Excel قد يخزّنه رقماً (7701234567) أو بصيغة علمية (7.701234567E9).
  static String? phoneOf(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (RegExp(r'^[0-9.]+[eE][+]?\d+$').hasMatch(s)) {
      final v = double.tryParse(s);
      if (v != null) s = v.toStringAsFixed(0);
    } else if (RegExp(r'^\d+\.0+$').hasMatch(s)) {
      s = s.substring(0, s.indexOf('.'));
    }
    var cleaned = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) return null;
    // نفس تنسيق «إضافة عميل»: 07xx ← 9647xx، و10 أرقام ← 964 + الرقم
    if (cleaned.startsWith('0')) cleaned = '964${cleaned.substring(1)}';
    if (!cleaned.startsWith('964') && cleaned.length == 10) cleaned = '964$cleaned';
    return cleaned;
  }

  static String? _currencyOf(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s.contains('usd') || s.contains('دولار') || s == r'$') return 'USD';
    if (s.contains('iqd') || s.contains('دينار') || s.contains('د.ع') || s == 'ع') return 'IQD';
    return '?';
  }

  static String _unitOf(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.contains('متر') || s == 'm' || s.contains('meter') || s.contains('metre')) return 'meter';
    return 'piece';
  }

  /// يبني خطة الاستيراد. [db] للقراءة فقط (الأسماء والباركودات الموجودة).
  static Future<ImportPlan> plan(
    DatabaseExecutor db,
    SheetTable t,
    ImportKind kind,
    Map<String, int?> map,
    ImportOptions o, {
    bool freshTarget = false,
  }) async {
    final fields = ImportFields.of(kind);
    for (final f in fields.where((f) => f.required)) {
      if (map[f.key] == null) throw ArgumentError('اربط عموداً بحقل «${f.label}»');
    }
    String cell(int r, String key) {
      final c = map[key];
      return c == null ? '' : t.cell(r, c).trim();
    }

    // الموجود في القاعدة (مرة واحدة)
    final existing = <String, String>{}; // مفتاح ← الاسم المحفوظ
    final existingId = <String, int>{};
    final existingBal = <String, Map<String, double>>{}; // مفتاح ← العملة ← الرصيد
    final deleted = <String>{};
    final barcodes = <String>{};
    double d0(Object? v) => (v as num?)?.toDouble() ?? 0;
    // [freshTarget]: الاستيراد إلى قاعدة جديدة فارغة — لا «موجود» يُقارن به
    if (freshTarget) {
      // لا شيء
    } else if (kind == ImportKind.customers) {
      for (final r in await db.rawQuery('SELECT * FROM customers ORDER BY id')) {
        final n = '${r['name'] ?? ''}';
        final k = _customerKey(n);
        if (k.isEmpty) continue;
        final merged = r.containsKey('merged_into_id') && r['merged_into_id'] != null;
        if ((r['is_deleted'] as num? ?? 0) == 0 && !merged) {
          if (!existing.containsKey(k)) {
            existing[k] = n;
            existingId[k] = r['id'] as int;
            existingBal[k] = {'IQD': d0(r['current_total_debt'])};
          }
        } else if (!merged) {
          deleted.add(k);
        }
      }
      deleted.removeAll(existing.keys);
    } else if (kind == ImportKind.products) {
      for (final r in await db.rawQuery('SELECT name, name_norm, barcode FROM products')) {
        final n = '${r['name'] ?? ''}';
        existing.putIfAbsent(_looseKey(n), () => n);
        final nn = '${r['name_norm'] ?? ''}';
        if (nn.isNotEmpty) existing.putIfAbsent(_looseKey(nn), () => n);
        final b = '${r['barcode'] ?? ''}'.trim();
        if (b.isNotEmpty) barcodes.add(b);
      }
      try {
        for (final r in await db.rawQuery('SELECT barcode FROM product_barcodes')) {
          final b = '${r['barcode'] ?? ''}'.trim();
          if (b.isNotEmpty) barcodes.add(b);
        }
      } catch (_) {}
    } else {
      for (final r in await db.rawQuery('SELECT * FROM suppliers ORDER BY id')) {
        final n = '${r['name'] ?? ''}';
        final k = _looseKey(n);
        if (existing.containsKey(k)) continue;
        existing[k] = n;
        existingId[k] = r['id'] as int;
        existingBal[k] = {'IQD': d0(r['total_debt_iqd']), 'USD': d0(r['total_debt_usd'])};
      }
    }

    final rows = <PlanRow>[];
    final skipped = <SkipRow>[];
    final seen = <String, int>{}; // مفتاح ← رقم الصف الأول في الملف
    final seenBarcode = <String, int>{};
    for (var r = o.headerRow + 1; r < t.rows.length; r++) {
      final line = r + 1;
      final raw = t.rows[r];
      if (raw.every((c) => c.trim().isEmpty)) continue;
      final name = cell(r, 'name').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (name.isEmpty) {
        skipped.add(SkipRow(line, '', 'بلا اسم'));
        continue;
      }
      // الأرقام — بصرامة
      final nums = <String, double?>{};
      String? numError;
      for (final f in fields.where((f) => f.numeric)) {
        final txt = cell(r, f.key);
        final v = ImportNumbers.parse(txt);
        if (!v.ok) {
          numError = '«${f.label}» = «$txt» ليس رقماً واضحاً';
          break;
        }
        nums[f.key] = v.value;
      }
      if (numError != null) {
        skipped.add(SkipRow(line, name, numError, error: true));
        continue;
      }

      final key = kind == ImportKind.customers ? _customerKey(name) : _looseKey(name);
      final first = seen[key];
      if (first != null) {
        skipped.add(SkipRow(line, name, 'مكرر في الملف (أول ظهور في الصف $first)'));
        continue;
      }
      final have = existing[key];
      final addTo = have != null && kind != ImportKind.products && o.addToExisting;
      if (have != null && !addTo) {
        skipped.add(SkipRow(line, name, 'موجود في البرنامج باسم «$have» — لم يُمس'));
        continue;
      }
      if (kind == ImportKind.customers && deleted.contains(key)) {
        skipped.add(SkipRow(line, name, 'حساب محذوف سابقاً بالاسم نفسه — أعِد تفعيله يدوياً إن أردته'));
        continue;
      }

      final row = PlanRow(line: line, name: name)
        ..rowKey = o.sourceId.isEmpty ? null : _rowKey(o.sourceId, kind, key)
        ..phone = kind == ImportKind.products ? null : phoneOf(cell(r, 'phone'))
        ..address = _nullIfEmpty(cell(r, 'address'))
        ..note = _nullIfEmpty(cell(r, 'note'));

      if (kind == ImportKind.products) {
        final price = nums['price'];
        final cost = nums['cost'];
        final qty = nums['qty'] ?? 0;
        if (price == null || price <= 0) {
          skipped.add(SkipRow(line, name, 'بلا سعر بيع (أو سعر صفر/سالب)', error: true));
          continue;
        }
        if (cost != null && cost < 0) {
          skipped.add(SkipRow(line, name, 'كلفة سالبة', error: true));
          continue;
        }
        if (qty < 0) {
          skipped.add(SkipRow(line, name, 'كمية سالبة', error: true));
          continue;
        }
        final bc = cell(r, 'barcode');
        final barcode = bc.isEmpty ? null : (RegExp(r'^\d+\.0+$').hasMatch(bc) ? bc.substring(0, bc.indexOf('.')) : bc);
        if (barcode != null) {
          if (barcodes.contains(barcode)) {
            skipped.add(SkipRow(line, name, 'الباركود $barcode مستعمل لمادة موجودة'));
            continue;
          }
          final fb = seenBarcode[barcode];
          if (fb != null) {
            skipped.add(SkipRow(line, name, 'الباركود $barcode مكرر في الملف (الصف $fb)'));
            continue;
          }
          seenBarcode[barcode] = line;
        }
        row
          ..price = ImportNumbers.money(price)
          ..cost = cost == null ? null : ImportNumbers.money(cost)
          ..qty = qty
          ..barcode = barcode
          ..unit = _unitOf(cell(r, 'unit'));
      } else {
        final b = nums['balance'] ?? 0;
        row.balance = ImportNumbers.money(o.positiveIsNormal ? b : -b);
        if (kind == ImportKind.suppliers) {
          final cur = _currencyOf(cell(r, 'currency'));
          if (cur == '?') {
            skipped.add(SkipRow(line, name, 'العملة «${cell(r, 'currency')}» غير مفهومة (دينار أو دولار)', error: true));
            continue;
          }
          row.currency = cur ?? o.defaultCurrency;
        }
        if (addTo) {
          if (row.balance.abs() < 0.005) {
            skipped.add(SkipRow(line, name, 'موجود باسم «$have» ولا مبلغ له في الملف — لا شيء يُضاف'));
            continue;
          }
          row
            ..existingId = existingId[key]
            ..existingName = have
            ..existingBalance = existingBal[key]?[row.currency] ?? 0;
        }
      }
      row
        ..originalBalance = row.balance
        ..originalPrice = row.price
        ..originalQty = row.qty;
      seen[key] = line;
      rows.add(row);
    }

    // 🛡️ الملف نفسه استُورد سابقاً؟ صفوفه لا تُضاف مرة ثانية
    final before = await _importedBefore(db, [for (final r in rows) if (r.rowKey != null) r.rowKey!]);
    if (before.isNotEmpty) {
      rows.removeWhere((r) {
        final at = r.rowKey == null ? null : before[r.rowKey!];
        if (at == null) return false;
        final day = at.length >= 10 ? at.substring(0, 10) : at;
        skipped.add(SkipRow(r.line, r.name, 'استُورد من هذا الملف نفسه سابقاً ($day) — لا يُضاف مرة ثانية'));
        return true;
      });
      skipped.sort((a, b) => a.line.compareTo(b.line));
    }
    return ImportPlan(kind, rows, skipped);
  }

  static String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

  // ─────────────────────────── 2) التنفيذ ───────────────────────────

  /// نسخة كاملة من القاعدة قبل الاستيراد. يرمي إن فشلت (فلا يُستورد شيء).
  static Future<String> backupBeforeImport() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'نسخ_قبل_الاستيراد'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final now = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    final path = p.join(dir.path,
        'before_import_${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}-${two(now.minute)}-${two(now.second)}.db');
    await BackupFiles.snapshotForBackup(path);
    final f = File(path);
    if (!await f.exists() || await f.length() < 1024) {
      throw StateError('تعذّر أخذ نسخة احتياطية قبل الاستيراد — لم يُستورد شيء');
    }
    return path;
  }

  static Future<void> _ensureLog(DatabaseExecutor db) => db.execute('''
      CREATE TABLE IF NOT EXISTS data_imports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        at TEXT NOT NULL,
        kind TEXT NOT NULL,
        file_name TEXT,
        sheet TEXT,
        added INTEGER NOT NULL,
        skipped INTEGER NOT NULL,
        balance_total REAL,
        opening_date TEXT,
        backup_path TEXT,
        details TEXT
      )''');

  /// ينفّذ الخطة بعد التأكيد. يعيد ما حُفظ فعلاً ونتيجة المطابقة.
  static Future<ImportResult> execute(
    ImportPlan plan,
    ImportOptions o, {
    required String fileName,
    required String sheet,
    void Function(int done, int total)? onProgress,
  }) async {
    if (plan.rows.isEmpty) {
      return ImportResult(added: 0, skippedAtSave: const [], backupPath: '', verified: true);
    }
    // 🛡️ القيم بعد تعديل المستخدم في المعاينة: أرقام سليمة فقط
    for (final r in plan.rows) {
      final bad = !r.balance.isFinite ||
          (plan.kind == ImportKind.products && (!r.price.isFinite || r.price <= 0 || !r.qty.isFinite || r.qty < 0));
      if (bad) throw ArgumentError('الصف ${r.line} «${r.name}»: قيمة غير صالحة — صحّحها في المعاينة');
    }
    if (plan.undecided.isNotEmpty) {
      throw ArgumentError('اختر لكل اسم موجود عندنا: دمج الدينين، أو مبلغ الملف هو الصحيح، أو الدين الحالي هو الصحيح '
          '(${plan.undecided.length} بلا اختيار)');
    }
    final db = await DatabaseService().database;
    await _ensureRowLedger(db);
    final hasBalances = plan.rows.any((r) => r.balance.abs() >= 0.005);
    if (plan.kind != ImportKind.products && hasBalances) {
      await PeriodLock.assertOpen(o.openingDate, db);
    }
    final backup = await backupBeforeImport();

    late ImportResult result;
    switch (plan.kind) {
      case ImportKind.customers:
        result = await _customers(db, plan, o, backup, fileName, onProgress);
        DatabaseService().invalidateCustomersCache();
      case ImportKind.suppliers:
        result = await _suppliers(db, plan, o, backup, fileName, onProgress);
      case ImportKind.products:
        result = await _products(db, plan, backup, onProgress);
    }

    try {
      await _ensureLog(db);
      final bal = plan.balanceByCurrency.entries.map((e) => '${e.key} ${e.value}').join('، ');
      await db.insert('data_imports', {
        'at': DateTime.now().toIso8601String(),
        'kind': plan.kind.name,
        'file_name': fileName,
        'sheet': sheet,
        'added': result.added,
        'skipped': plan.skipped.length + result.skippedAtSave.length,
        'balance_total': plan.kind == ImportKind.products ? null : plan.rows.fold<double>(0, (s, r) => s + r.balance),
        'opening_date': plan.kind == ImportKind.products ? null : o.openingDate.toIso8601String(),
        'backup_path': backup,
        'details': result.problems.isEmpty ? (bal.isEmpty ? null : bal) : result.problems.join(' | '),
      });
    } catch (_) {}
    final ex = result.addedToExisting;
    await ActivityLog.log('استيراد', 'استيراد من Excel',
        'استيراد ${result.added} ${plan.kind.noun} جديد${ex > 0 ? '، وتغيير دين $ex حساب موجود (${plan.existingDelta})' : ''}'
        '${result.kept.isNotEmpty ? '، وبقي ${result.kept.length} موجود كما هو' : ''} '
        'من «$fileName» (${plan.skipped.length} مُتجاوز) — نسخة قبل الاستيراد: $backup');
    return result;
  }

  static Future<ImportResult> _customers(
    Database db,
    ImportPlan plan,
    ImportOptions o,
    String backup,
    String fileName,
    void Function(int, int)? onProgress,
  ) async {
    final rows = plan.rows;
    final lateSkips = <SkipRow>[];
    final kept = <SkipRow>[];
    var added = 0;
    var addedExisting = 0;
    await db.transaction((txn) async {
      kept.clear();
      lateSkips.clear();
      final txCols = {for (final c in await txn.rawQuery('PRAGMA table_info(transactions)')) '${c['name']}'};
      final ids = <int>[];
      var expected = 0.0;
      var expectedWithBalance = 0;
      // الحسابات الموجودة: رصيد كل منها قبل الإضافة (من معاملاته، مصدر الحقيقة)
      final exIds = <int>[];
      final exUuids = <String>[];
      var exExpected = 0.0;
      var exBefore = 0.0;
      final ledger = <Map<String, Object?>>[];
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final note = _importNote(fileName, r);
        final uuid = r.rowKey == null ? null : _txUuid(r.rowKey!);
        if (uuid != null) {
          final dup = await txn.query('transactions', columns: ['id'], where: 'transaction_uuid = ?', whereArgs: [uuid], limit: 1);
          if (dup.isNotEmpty) {
            lateSkips.add(SkipRow(r.line, r.name, 'استُورد من هذا الملف نفسه سابقاً — لم يُضف مرة ثانية'));
            continue;
          }
        }
        if (r.isExisting) {
          // حساب موجود: حسب اختيار المستخدم — والبطاقة (الهاتف والعنوان) كما هي
          if (r.action == ExistingAction.keep) {
            kept.add(SkipRow(r.line, r.name, 'الدين الحالي هو الصحيح — لم يتغير'));
            continue;
          }
          final cur = await txn.query('customers',
              columns: ['id'], where: 'id = ? AND COALESCE(is_deleted, 0) = 0', whereArgs: [r.existingId], limit: 1);
          if (cur.isEmpty) {
            lateSkips.add(SkipRow(r.line, r.name, 'الحساب «${r.existingName}» حُذف بعد المعاينة — لم يُضف شيء'));
            continue;
          }
          if (exIds.contains(r.existingId)) {
            lateSkips.add(SkipRow(r.line, r.name, 'الحساب نفسه مكرر في الملف — لم يُضف مرة ثانية'));
            continue;
          }
          final before = await _sumTx(txn, r.existingId!);
          final useFile = r.action == ExistingAction.useFile;
          // مبلغ الملف هو الصحيح: الفرق فقط (من القاعدة الآن، لا من المعاينة)
          final amount = useFile ? ImportNumbers.money(r.balance - before) : r.balance;
          if (amount.abs() < 0.005) {
            kept.add(SkipRow(r.line, r.name, 'دينه الحالي يساوي مبلغ الملف — لا تسوية'));
            continue;
          }
          exBefore += before;
          final txUuid = uuid ?? UuidHelper.newTransactionUuid();
          await txn.insert(
              'transactions',
              await TxAuthor.stamped(txn, {
                'customer_id': r.existingId,
                'transaction_uuid': txUuid,
                'sync_uuid': txUuid,
                'transaction_date': o.openingDate.toIso8601String(),
                'amount_changed': amount,
                'new_balance_after_transaction': 0.0, // يُضبط في إعادة الحساب أدناه
                if (txCols.contains('balance_before_transaction')) 'balance_before_transaction': 0.0,
                'transaction_note': useFile
                    ? '$note — الدين صار ${_fmt(r.balance)} بدل ${_fmt(before)} (مبلغ الملف هو الصحيح)'
                    : '$note — دمج: أُضيف ${_fmt(r.balance)} إلى ${_fmt(before)}',
                'transaction_type': 'opening_balance',
                'description': useFile ? 'تسوية رصيد من Excel' : 'رصيد مستورد من Excel',
                'created_at': DateTime.now().toIso8601String(),
                'invoice_id': null,
                'is_deleted': 0,
                'is_created_by_me': 1,
                'is_uploaded': 0,
              }));
          await _rebuildCustomerBalances(txn, r.existingId!, txCols);
          if (useFile) {
            // 🛡️ الدين صار مبلغ الملف بالضبط
            final now = await _sumTx(txn, r.existingId!);
            if ((now - ImportNumbers.money(r.balance)).abs() > 0.005) {
              throw StateError('أُلغي الاستيراد كله: دين «${r.name}» بعد التسوية ($now) لا يساوي مبلغ الملف (${r.balance})');
            }
          }
          exIds.add(r.existingId!);
          exUuids.add(txUuid);
          exExpected += amount;
          ledger.add({'row_key': r.rowKey, 'entity_id': r.existingId, 'amount': amount});
          if (i % 50 == 0) onProgress?.call(i + 1, rows.length);
          continue;
        }
        // ظهر الاسم بعد المعاينة (جهاز آخر، أو شاشة أخرى)؟ يُتجاوز ولا يُمس
        final now = await CustomerNameRule.findActive(txn, r.name);
        if (now != null) {
          lateSkips.add(SkipRow(r.line, r.name, 'أُضيف بالاسم نفسه بعد المعاينة — لم يُمس'));
          continue;
        }
        final id = await CustomerDao.insertCustomerIn(
          txn,
          Customer(
            name: r.name,
            phone: r.phone,
            address: r.address,
            generalNote: r.note,
            currentTotalDebt: r.balance,
          ),
          openingDate: o.openingDate,
          openingNote: note,
          openingUuid: uuid,
        );
        ids.add(id);
        if (r.balance.abs() >= 0.005) {
          expected += r.balance;
          expectedWithBalance++;
        }
        ledger.add({'row_key': r.rowKey, 'entity_id': id, 'amount': r.balance});
        if (i % 50 == 0) onProgress?.call(i + 1, rows.length);
      }
      // 🛡️ مطابقة قبل الحفظ النهائي: من القاعدة نفسها، لا من الذاكرة
      final check = await _sumCustomerOpenings(txn, ids);
      if (check.count != expectedWithBalance || (check.sum - expected).abs() > 0.005) {
        throw StateError('أُلغي الاستيراد كله: مجموع الأرصدة المحفوظة (${check.sum}، ${check.count} معاملة) '
            'لا يطابق المعاينة ($expected، $expectedWithBalance معاملة)');
      }
      final cards = await _sumCustomerCards(txn, ids);
      if ((cards - expected).abs() > 0.005) {
        throw StateError('أُلغي الاستيراد كله: أرصدة البطاقات ($cards) لا تطابق المعاملات ($expected)');
      }
      // 🛡️ الحسابات الموجودة: المعاملات المضافة = المعاينة، والبطاقات زادت بالمبلغ نفسه بالضبط
      if (exIds.isNotEmpty) {
        var got = 0.0;
        for (final u in exUuids) {
          final r = await txn.rawQuery(
              'SELECT COALESCE(SUM(amount_changed), 0) AS s, COUNT(*) AS n FROM transactions '
              'WHERE transaction_uuid = ? AND COALESCE(is_deleted, 0) = 0',
              [u]);
          if (((r.first['n'] as num?) ?? 0).toInt() != 1) {
            throw StateError('أُلغي الاستيراد كله: معاملة مستوردة ($u) لم تُحفظ مرة واحدة بالضبط');
          }
          got += (r.first['s'] as num?)?.toDouble() ?? 0;
        }
        var after = 0.0;
        for (final id in exIds) {
          final tx = await _sumTx(txn, id);
          final card = await txn.query('customers', columns: ['current_total_debt'], where: 'id = ?', whereArgs: [id], limit: 1);
          final c = (card.first['current_total_debt'] as num?)?.toDouble() ?? 0;
          if ((c - tx).abs() > 0.005) {
            throw StateError('أُلغي الاستيراد كله: بطاقة العميل #$id ($c) لا تساوي مجموع معاملاته ($tx)');
          }
          after += tx;
        }
        final want = ImportNumbers.money(exExpected);
        if ((ImportNumbers.money(got) - want).abs() > 0.005 ||
            (ImportNumbers.money(after - exBefore) - want).abs() > 0.005) {
          throw StateError('أُلغي الاستيراد كله: ما أُضيف للحسابات الموجودة (${ImportNumbers.money(got)}، '
              'تغيّر الأرصدة ${ImportNumbers.money(after - exBefore)}) لا يطابق المعاينة ($want)');
        }
      }
      await _writeLedger(txn, ledger, ImportKind.customers, 'IQD', fileName);
      added = ids.length;
      addedExisting = exIds.length;
    });
    onProgress?.call(rows.length, rows.length);
    return ImportResult(added: added, skippedAtSave: lateSkips, backupPath: backup, verified: true)
      ..addedToExisting = addedExisting
      ..kept = kept;
  }

  /// للاختبار فقط: تنفيذ العملاء على قاعدة معطاة (بلا نسخة احتياطية ولا فحص الفترة).
  static Future<ImportResult> debugExecuteCustomers(Database db, ImportPlan plan, ImportOptions o, String fileName) async {
    await _ensureRowLedger(db);
    return _customers(db, plan, o, '', fileName, null);
  }

  static Future<double> _sumTx(DatabaseExecutor db, int customerId) async {
    final r = await db.rawQuery(
        'SELECT COALESCE(SUM(amount_changed), 0) AS s FROM transactions WHERE customer_id = ? AND COALESCE(is_deleted, 0) = 0',
        [customerId]);
    return ImportNumbers.money((r.first['s'] as num?)?.toDouble() ?? 0);
  }

  /// سلسلة أرصدة العميل بترتيب التاريخ (المعاملة المستوردة قد تكون بتاريخ أقدم من
  /// معاملات لاحقة)، ثم البطاقة = المجموع — نفس [TransactionDao.recalculateCustomerTransactionBalances]
  /// و[recalculateAndApplyCustomerDebt] لكن داخل معاملة الاستيراد.
  static Future<void> _rebuildCustomerBalances(Transaction txn, int customerId, Set<String> txCols) async {
    final txs = await txn.rawQuery(
        'SELECT id, amount_changed, transaction_date FROM transactions '
        'WHERE customer_id = ? AND COALESCE(is_deleted, 0) = 0 ORDER BY transaction_date ASC, id ASC',
        [customerId]);
    var running = 0.0;
    for (final t in txs) {
      final before = running;
      final amt = (t['amount_changed'] as num?)?.toDouble() ?? 0;
      running = MoneyCalculator.add(running, amt);
      final date = DateTime.tryParse('${t['transaction_date'] ?? ''}');
      await txn.update(
        'transactions',
        {
          'new_balance_after_transaction': running,
          if (txCols.contains('balance_before_transaction')) 'balance_before_transaction': before,
          if (txCols.contains('checksum') && date != null)
            'checksum': MoneyCalculator.calculateTransactionChecksum(
                customerId: customerId, amount: amt, balanceBefore: before, balanceAfter: running, date: date),
        },
        where: 'id = ?',
        whereArgs: [t['id']],
      );
    }
    await txn.update('customers', {'current_total_debt': running, 'last_modified_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [customerId]);
  }

  static Future<void> _writeLedger(
      DatabaseExecutor db, List<Map<String, Object?>> rows, ImportKind kind, String currency, String fileName) async {
    final at = DateTime.now().toIso8601String();
    for (final r in rows) {
      if (r['row_key'] == null) continue;
      await db.insert('data_import_rows', {
        'row_key': r['row_key'],
        'kind': kind.name,
        'entity_id': r['entity_id'],
        'amount': r['amount'],
        'currency': r['currency'] ?? currency,
        'file_name': fileName,
        'at': at,
      });
    }
  }

  static Future<({double sum, int count})> _sumCustomerOpenings(DatabaseExecutor db, List<int> ids) async {
    var sum = 0.0;
    var count = 0;
    for (var i = 0; i < ids.length; i += 500) {
      final part = ids.sublist(i, (i + 500).clamp(0, ids.length));
      final r = await db.rawQuery(
          "SELECT COALESCE(SUM(amount_changed), 0) AS s, COUNT(*) AS n FROM transactions "
          "WHERE transaction_type = 'opening_balance' AND COALESCE(is_deleted, 0) = 0 "
          "AND customer_id IN (${List.filled(part.length, '?').join(',')})",
          part);
      sum += (r.first['s'] as num?)?.toDouble() ?? 0;
      count += (r.first['n'] as num?)?.toInt() ?? 0;
    }
    return (sum: ImportNumbers.money(sum), count: count);
  }

  static Future<double> _sumCustomerCards(DatabaseExecutor db, List<int> ids) async {
    var sum = 0.0;
    for (var i = 0; i < ids.length; i += 500) {
      final part = ids.sublist(i, (i + 500).clamp(0, ids.length));
      final r = await db.rawQuery(
          'SELECT COALESCE(SUM(current_total_debt), 0) AS s FROM customers WHERE id IN (${List.filled(part.length, '?').join(',')})',
          part);
      sum += (r.first['s'] as num?)?.toDouble() ?? 0;
    }
    return ImportNumbers.money(sum);
  }

  static Future<ImportResult> _suppliers(
    Database db,
    ImportPlan plan,
    ImportOptions o,
    String backup,
    String fileName,
    void Function(int, int)? onProgress,
  ) async {
    final rows = plan.rows;
    final lateSkips = <SkipRow>[];
    final kept = <SkipRow>[];
    var added = 0;
    var addedExisting = 0;
    await db.transaction((txn) async {
      kept.clear();
      lateSkips.clear();
      final names = {
        for (final r in await txn.rawQuery('SELECT name FROM suppliers')) _looseKey('${r['name'] ?? ''}'),
      };
      final ids = <int>[];
      final expected = <String, double>{};
      // الموجودون: رصيد كل عملة قبل الإضافة، والمتوقع إضافته
      final exIds = <int>{};
      final exBefore = <String, double>{};
      final exExpected = <String, double>{};
      final ledger = <Map<String, Object?>>[];
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        if (r.isExisting) {
          if (r.action == ExistingAction.keep) {
            kept.add(SkipRow(r.line, r.name, 'الدين الحالي هو الصحيح — لم يتغير'));
            continue;
          }
          final sup = await txn.query('suppliers', columns: ['id'], where: 'id = ?', whereArgs: [r.existingId], limit: 1);
          if (sup.isEmpty) {
            lateSkips.add(SkipRow(r.line, r.name, 'المورد «${r.existingName}» حُذف بعد المعاينة — لم يُضف شيء'));
            continue;
          }
          if (exIds.contains(r.existingId)) {
            lateSkips.add(SkipRow(r.line, r.name, 'المورد نفسه مكرر في الملف — لم يُضف مرة ثانية'));
            continue;
          }
          final curBefore = await _sumSupplierTx(txn, r.existingId!, r.currency);
          final useFile = r.action == ExistingAction.useFile;
          final amount = useFile ? ImportNumbers.money(r.balance - curBefore) : r.balance;
          if (amount.abs() < 0.005) {
            kept.add(SkipRow(r.line, r.name, 'رصيده الحالي يساوي مبلغ الملف — لا تسوية'));
            continue;
          }
          for (final cur in const ['IQD', 'USD']) {
            exBefore[cur] = (exBefore[cur] ?? 0) + await _sumSupplierTx(txn, r.existingId!, cur);
          }
          final note = _importNote(fileName, r);
          final ok = await SupplierDebtReconciler.addImportedBalance(txn,
              supplierId: r.existingId!,
              amount: amount,
              currency: r.currency,
              date: o.openingDate,
              description: useFile
                  ? 'تسوية رصيد — $note — صار ${_fmt(r.balance)} بدل ${_fmt(curBefore)} (مبلغ الملف هو الصحيح)'
                  : 'رصيد مستورد — $note — دمج: أُضيف ${_fmt(r.balance)} إلى ${_fmt(curBefore)}',
              uuid: r.rowKey == null ? 'simp_${UuidHelper.newTransactionUuid()}' : 's${_txUuid(r.rowKey!)}');
          if (!ok) {
            lateSkips.add(SkipRow(r.line, r.name, 'استُورد من هذا الملف نفسه سابقاً — لم يُضف مرة ثانية'));
            continue;
          }
          if (useFile) {
            final now = await _sumSupplierTx(txn, r.existingId!, r.currency);
            if ((ImportNumbers.money(now) - ImportNumbers.money(r.balance)).abs() > 0.005) {
              throw StateError('أُلغي الاستيراد كله: رصيد المورد «${r.name}» بعد التسوية ($now) لا يساوي مبلغ الملف (${r.balance})');
            }
          }
          exIds.add(r.existingId!);
          exExpected[r.currency] = (exExpected[r.currency] ?? 0) + amount;
          ledger.add({'row_key': r.rowKey, 'entity_id': r.existingId, 'amount': amount, 'currency': r.currency});
          if (i % 50 == 0) onProgress?.call(i + 1, rows.length);
          continue;
        }
        if (names.contains(_looseKey(r.name))) {
          lateSkips.add(SkipRow(r.line, r.name, 'أُضيف بالاسم نفسه بعد المعاينة — لم يُمس'));
          continue;
        }
        final now = DateTime.now();
        final map = Supplier(
          name: r.name,
          phone: r.phone,
          address: r.address,
          currency: r.currency,
          notes: r.note,
          createdAt: now,
          updatedAt: now,
        ).toMap()
          ..remove('id');
        final id = await txn.insert('suppliers', await supplierInsertCompat(txn, map));
        names.add(_looseKey(r.name));
        ids.add(id);
        if (r.balance.abs() >= 0.005) {
          // موجب = له علينا — نفس اصطلاح «رصيد افتتاحي» في شاشة المورد
          await SupplierDebtReconciler.setOpeningBalance(txn,
              supplierId: id, amount: r.balance, currency: r.currency, date: o.openingDate,
              description: _importNote(fileName, r));
          expected[r.currency] = (expected[r.currency] ?? 0) + r.balance;
        }
        ledger.add({'row_key': r.rowKey, 'entity_id': id, 'amount': r.balance, 'currency': r.currency});
        if (i % 50 == 0) onProgress?.call(i + 1, rows.length);
      }
      // 🛡️ مطابقة قبل الحفظ النهائي لكل عملة
      for (final cur in const ['IQD', 'USD']) {
        var got = 0.0;
        var cards = 0.0;
        for (var i = 0; i < ids.length; i += 500) {
          final part = ids.sublist(i, (i + 500).clamp(0, ids.length));
          final ph = List.filled(part.length, '?').join(',');
          final r = await txn.rawQuery(
              "SELECT COALESCE(SUM(amount_changed), 0) AS s FROM supplier_transactions "
              "WHERE transaction_type = 'opening_balance' AND COALESCE(is_deleted, 0) = 0 "
              "AND COALESCE(currency, 'IQD') = ? AND supplier_id IN ($ph)",
              [cur, ...part]);
          got += (r.first['s'] as num?)?.toDouble() ?? 0;
          final col = cur == 'USD' ? 'total_debt_usd' : 'total_debt_iqd';
          final c = await txn.rawQuery('SELECT COALESCE(SUM($col), 0) AS s FROM suppliers WHERE id IN ($ph)', part);
          cards += (c.first['s'] as num?)?.toDouble() ?? 0;
        }
        final want = ImportNumbers.money(expected[cur] ?? 0);
        if ((ImportNumbers.money(got) - want).abs() > 0.005 || (ImportNumbers.money(cards) - want).abs() > 0.005) {
          throw StateError('أُلغي الاستيراد كله: أرصدة الموردين بـ$cur المحفوظة ($got، البطاقات $cards) '
              'لا تطابق المعاينة ($want)');
        }
        // الموجودون: دفترهم وبطاقاتهم زادت بالمبلغ نفسه بالضبط
        if (exIds.isNotEmpty) {
          var after = 0.0;
          var cardsAfter = 0.0;
          final col = cur == 'USD' ? 'total_debt_usd' : 'total_debt_iqd';
          for (final id in exIds) {
            after += await _sumSupplierTx(txn, id, cur);
            final c = await txn.query('suppliers', columns: [col], where: 'id = ?', whereArgs: [id], limit: 1);
            cardsAfter += (c.first[col] as num?)?.toDouble() ?? 0;
          }
          final wantEx = ImportNumbers.money(exExpected[cur] ?? 0);
          final delta = ImportNumbers.money(after - (exBefore[cur] ?? 0));
          if ((delta - wantEx).abs() > 0.005 || (ImportNumbers.money(cardsAfter) - ImportNumbers.money(after)).abs() > 0.005) {
            throw StateError('أُلغي الاستيراد كله: ما أُضيف للموردين الموجودين بـ$cur ($delta، البطاقات $cardsAfter) '
                'لا يطابق المعاينة ($wantEx)');
          }
        }
      }
      await _writeLedger(txn, ledger, ImportKind.suppliers, 'IQD', fileName);
      added = ids.length;
      addedExisting = exIds.length;
    });
    onProgress?.call(rows.length, rows.length);
    return ImportResult(added: added, skippedAtSave: lateSkips, backupPath: backup, verified: true)
      ..addedToExisting = addedExisting
      ..kept = kept;
  }

  static Future<double> _sumSupplierTx(DatabaseExecutor db, int supplierId, String cur) async {
    final r = await db.rawQuery(
        "SELECT COALESCE(SUM(amount_changed), 0) AS s FROM supplier_transactions "
        "WHERE supplier_id = ? AND COALESCE(is_deleted, 0) = 0 AND COALESCE(currency, 'IQD') = ?",
        [supplierId, cur]);
    return (r.first['s'] as num?)?.toDouble() ?? 0;
  }

  static Future<ImportResult> _products(
    Database db,
    ImportPlan plan,
    String backup,
    void Function(int, int)? onProgress,
  ) async {
    final rows = plan.rows;
    final lateSkips = <SkipRow>[];
    final problems = <String>[];
    var added = 0;
    final svc = DatabaseService();
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final now = DateTime.now();
      try {
        final id = await svc.insertProduct(Product(
          name: r.name,
          unit: r.unit,
          unitPrice: r.price,
          price1: r.price,
          costPrice: r.cost,
          barcode: r.barcode,
          stockQuantity: r.qty,
          createdAt: now,
          lastModifiedAt: now,
        ));
        added++;
        // 🛡️ مطابقة كل مادة بعد حفظها
        final saved = await db.query('products',
            columns: ['stock_quantity', 'unit_price'], where: 'id = ?', whereArgs: [id], limit: 1);
        final q = saved.isEmpty ? null : (saved.first['stock_quantity'] as num?)?.toDouble();
        final pr = saved.isEmpty ? null : (saved.first['unit_price'] as num?)?.toDouble();
        if (q == null || (q - r.qty).abs() > 0.0001 || pr == null || (pr - r.price).abs() > 0.005) {
          problems.add('الصف ${r.line} «${r.name}»: المحفوظ (كمية $q، سعر $pr) لا يطابق الملف (${r.qty}، ${r.price})');
        }
      } on DuplicateProductNameException {
        lateSkips.add(SkipRow(r.line, r.name, 'أُضيفت بالاسم نفسه بعد المعاينة — لم تُمس'));
        continue;
      } catch (e) {
        final msg = '$e';
        // خطأ غير متوقع: يتوقف الاستيراد هنا. ما حُفظ قبله مواد كاملة وصحيحة،
        // وإعادة استيراد الملف نفسه تتجاوزها تلقائياً وتكمل الباقي.
        problems.add('توقف عند الصف ${r.line} «${r.name}»: $msg — حُفظت $added مادة قبله، '
            'وإعادة استيراد الملف تكمل الباقي (الموجود يُتجاوز)');
        break;
      }
      if (i % 20 == 0) onProgress?.call(i + 1, rows.length);
    }
    onProgress?.call(rows.length, rows.length);
    return ImportResult(
        added: added, skippedAtSave: lateSkips, backupPath: backup, verified: problems.isEmpty, problems: problems);
  }

  /// للاختبار: يقرأ ملفاً من القرص.
  static List<SheetTable> readFile(String path) =>
      SheetReader.read(Uint8List.fromList(File(path).readAsBytesSync()), path);
}
