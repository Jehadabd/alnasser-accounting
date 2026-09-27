// lib/erp/debts/customer_ext_service.dart
//
// 👤 بطاقة العميل الموسّعة (مثل بطاقة الحساب في الإداري): الرمز، اللقب،
// المجموعة، المنطقة، سقف الدين، نسبة الحسم، مستوى السعر، يوم التحصيل،
// المسؤول، رقم الهوية وصورتها، صورة العميل، ملاحظات إضافية، الإيقاف.
//
// لا تمسّ هذه البيانات رصيد العميل ولا جدول customers (الذي تزامنه Firebase).

import 'package:sqflite/sqflite.dart';

import '../erp_common.dart';

class CustomerExt {
  CustomerExt({
    required this.customerId,
    this.code,
    this.title,
    this.groupId,
    this.region,
    this.creditLimit,
    this.discountPercent,
    this.priceLevel,
    this.collectionDay,
    this.responsible,
    this.idNumber,
    this.idImagePath,
    this.photoPath,
    this.notes2,
    this.isBlocked = false,
  });

  final int customerId;
  String? code;
  String? title;
  int? groupId;
  String? region;
  double? creditLimit;
  double? discountPercent;
  String? priceLevel;
  String? collectionDay;
  String? responsible;
  String? idNumber;
  String? idImagePath;
  String? photoPath;
  String? notes2;
  bool isBlocked;

  factory CustomerExt.fromMap(Map<String, Object?> m) => CustomerExt(
        customerId: m['customer_id'] as int,
        code: m['code'] as String?,
        title: m['title'] as String?,
        groupId: m['group_id'] as int?,
        region: m['region'] as String?,
        creditLimit: (m['credit_limit'] as num?)?.toDouble(),
        discountPercent: (m['discount_percent'] as num?)?.toDouble(),
        priceLevel: m['price_level'] as String?,
        collectionDay: m['collection_day'] as String?,
        responsible: m['responsible'] as String?,
        idNumber: m['id_number'] as String?,
        idImagePath: m['id_image_path'] as String?,
        photoPath: m['photo_path'] as String?,
        notes2: m['notes2'] as String?,
        isBlocked: (m['is_blocked'] as int? ?? 0) == 1,
      );

  Map<String, Object?> toMap() => {
        'customer_id': customerId,
        'code': (code == null || code!.trim().isEmpty) ? null : code!.trim(),
        'title': title,
        'group_id': groupId,
        'region': region,
        'credit_limit': creditLimit,
        'discount_percent': discountPercent,
        'price_level': priceLevel,
        'collection_day': collectionDay,
        'responsible': responsible,
        'id_number': idNumber,
        'id_image_path': idImagePath,
        'photo_path': photoPath,
        'notes2': notes2,
        'is_blocked': isBlocked ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      };
}

class CustomerGroup {
  CustomerGroup(this.id, this.name, this.notes);
  final int id;
  final String name;
  final String? notes;
  @override
  String toString() => name;
}

/// ملخص مالي للعميل لبطاقته.
class CustomerSummary {
  CustomerSummary({
    required this.balance,
    required this.totalDebts,
    required this.totalPayments,
    required this.invoicesCount,
    this.lastPaymentDate,
    this.lastPaymentAmount,
    this.lastDebtDate,
    this.firstDate,
    required this.openDueAmount,
    this.lastReconDate,
  });
  final double balance;
  final double totalDebts;
  final double totalPayments;
  final int invoicesCount;
  final DateTime? lastPaymentDate;
  final double? lastPaymentAmount;
  final DateTime? lastDebtDate;
  final DateTime? firstDate;
  final double openDueAmount;
  final DateTime? lastReconDate;

  double get collectionRatio => totalDebts <= 0 ? 0 : (totalPayments / totalDebts * 100);
}

class CustomerExtService {
  Future<CustomerExt> get(int customerId) async {
    final db = await erpDb();
    final r = await db.query('customer_ext', where: 'customer_id = ?', whereArgs: [customerId], limit: 1);
    return r.isEmpty ? CustomerExt(customerId: customerId) : CustomerExt.fromMap(r.first);
  }

  Future<Map<int, CustomerExt>> all() async {
    final db = await erpDb();
    final r = await db.query('customer_ext');
    return {for (final m in r) m['customer_id'] as int: CustomerExt.fromMap(m)};
  }

  Future<void> save(CustomerExt e) async {
    final db = await erpDb();
    final code = e.code?.trim();
    if (code != null && code.isNotEmpty) {
      final dup = await db.query('customer_ext',
          where: 'code = ? AND customer_id != ?', whereArgs: [code, e.customerId], limit: 1);
      if (dup.isNotEmpty) throw ErpException('الرمز $code مستخدم لعميل آخر');
    }
    if ((e.creditLimit ?? 0) < 0) throw ErpException('سقف الدين لا يكون سالباً');
    final dp = e.discountPercent ?? 0;
    if (dp < 0 || dp > 100) throw ErpException('نسبة الحسم بين 0 و 100');
    await db.insert('customer_ext', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// رمز مقترح تالٍ (C0001...).
  Future<String> suggestCode() async {
    final db = await erpDb();
    final r = await db.rawQuery(
        "SELECT code FROM customer_ext WHERE code LIKE 'C%' ORDER BY LENGTH(code) DESC, code DESC LIMIT 1");
    var n = 0;
    if (r.isNotEmpty) n = int.tryParse(((r.first['code'] as String?) ?? 'C0').substring(1)) ?? 0;
    return 'C${(n + 1).toString().padLeft(4, '0')}';
  }

  // ─────────────── المجموعات ───────────────

  Future<List<CustomerGroup>> groups() async {
    final db = await erpDb();
    final r = await db.query('customer_groups', orderBy: 'name');
    return r.map((m) => CustomerGroup(m['id'] as int, m['name'] as String, m['notes'] as String?)).toList();
  }

  Future<int> addGroup(String name, {String? notes}) async {
    if (name.trim().isEmpty) throw ErpException('اكتب اسم المجموعة');
    final db = await erpDb();
    return db.insert('customer_groups',
        {'name': name.trim(), 'notes': notes, 'created_at': DateTime.now().toIso8601String()});
  }

  Future<void> renameGroup(int id, String name) async {
    if (name.trim().isEmpty) throw ErpException('اكتب اسم المجموعة');
    final db = await erpDb();
    await db.update('customer_groups', {'name': name.trim()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteGroup(int id) async {
    final db = await erpDb();
    await db.transaction((txn) async {
      await txn.update('customer_ext', {'group_id': null}, where: 'group_id = ?', whereArgs: [id]);
      await txn.delete('customer_groups', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ─────────────── الملخص ───────────────

  Future<CustomerSummary> summary(int customerId) async {
    final db = await erpDb();
    final t = await db.rawQuery('''
      SELECT COALESCE(SUM(amount_changed), 0) AS bal,
             COALESCE(SUM(CASE WHEN amount_changed > 0 THEN amount_changed ELSE 0 END), 0) AS debts,
             COALESCE(SUM(CASE WHEN amount_changed < 0 THEN -amount_changed ELSE 0 END), 0) AS pays,
             MIN(transaction_date) AS first_date
      FROM transactions WHERE customer_id = ? AND COALESCE(is_deleted, 0) = 0
    ''', [customerId]);
    final lp = await db.rawQuery('''
      SELECT transaction_date, amount_changed FROM transactions
      WHERE customer_id = ? AND amount_changed < 0 AND COALESCE(is_deleted, 0) = 0
      ORDER BY transaction_date DESC, id DESC LIMIT 1
    ''', [customerId]);
    final ld = await db.rawQuery('''
      SELECT transaction_date FROM transactions
      WHERE customer_id = ? AND amount_changed > 0 AND COALESCE(is_deleted, 0) = 0
      ORDER BY transaction_date DESC, id DESC LIMIT 1
    ''', [customerId]);
    final inv = await db.rawQuery('''
      SELECT COUNT(*) AS n FROM invoices WHERE customer_id = ? AND COALESCE(is_deleted, 0) = 0
        AND status = 'محفوظة'
    ''', [customerId]);
    final due = await db.rawQuery('''
      SELECT COALESCE(SUM(amount - paid_amount), 0) AS a FROM due_items
      WHERE party_type = 'customer' AND party_id = ? AND status IN ('open', 'partial')
    ''', [customerId]);
    final rc = await db.rawQuery(
        'SELECT MAX(recon_date) AS d FROM customer_reconciliations WHERE customer_id = ?', [customerId]);
    DateTime? dt(Object? v) => v == null ? null : DateTime.tryParse(v as String);
    return CustomerSummary(
      balance: d0(t.first['bal']),
      totalDebts: d0(t.first['debts']),
      totalPayments: d0(t.first['pays']),
      invoicesCount: ((inv.first['n'] as num?) ?? 0).toInt(),
      lastPaymentDate: lp.isEmpty ? null : dt(lp.first['transaction_date']),
      lastPaymentAmount: lp.isEmpty ? null : -d0(lp.first['amount_changed']),
      lastDebtDate: ld.isEmpty ? null : dt(ld.first['transaction_date']),
      firstDate: dt(t.first['first_date']),
      openDueAmount: d0(due.first['a']),
      lastReconDate: dt(rc.first['d']),
    );
  }

  /// فحص سقف الدين: كم يبقى للعميل؟ null = بلا سقف.
  Future<double?> remainingCredit(int customerId) async {
    final e = await get(customerId);
    if (e.creditLimit == null || e.creditLimit! <= 0) return null;
    final s = await summary(customerId);
    return e.creditLimit! - s.balance;
  }

  /// العميل بالاسم (للربط مع شاشة الفاتورة التي تعمل بالاسم).
  Future<int?> customerIdByName(String name) async {
    final n = name.trim();
    if (n.isEmpty) return null;
    final db = await erpDb();
    final r = await db.query('customers',
        columns: ['id'], where: 'name = ? AND COALESCE(is_deleted, 0) = 0', whereArgs: [n], limit: 1);
    return r.isEmpty ? null : r.first['id'] as int;
  }
}
