// lib/services/database/business/customer_name_rule.dart
// 🛡️ قاعدة سجل الديون: الاسم يحدد الحساب (قرار المالك 2026-10-26)
//
// لا يوجد في سجل الديون حسابان نشطان بالاسم نفسه. «الاسم نفسه» = الاسم بعد
// حذف المسافات فقط («محمد علي» = «محمدعلي» = « محمد علي »)؛ الهاتف لا يفرّق
// بين حسابين.
//
// • الإنشاء والتعديل المحلي: يُرفض اسم موجود ([ensureAvailable]).
// • الحسابات المكررة الموجودة سابقاً: تُعرض للمستخدم ولا تُدمج إلا بتأكيده
//   ([duplicateGroups] ثم [mergeInto]) — وتؤخذ نسخة احتياطية قبل كل دمج.
// • قاعدة البيانات نفسها ترفض التكرار بفهرس فريد ([enforceUniqueIndex]) يُنشأ
//   متى خلت القاعدة من التكرار.
//
// الدمج لا يحذف شيئاً: الحساب المدموج يبقى صفاً مخفياً (is_deleted = 1) يشير
// إلى الحساب الباقي (merged_into_id)، فكل ما يصل لاحقاً بمعرّفه (من جهاز آخر)
// يُنسب للحساب الباقي ([resolveMerged]).

import 'package:sqflite/sqflite.dart';

/// محاولة إنشاء حساب ثانٍ (أو تسمية حساب) باسم حساب موجود.
class DuplicateCustomerNameException implements Exception {
  DuplicateCustomerNameException(this.existingName);

  /// اسم الحساب الموجود كما هو محفوظ.
  final String existingName;

  @override
  String toString() =>
      'يوجد في سجل الديون حساب باسم «$existingName» — لا يمكن وجود حسابين بالاسم نفسه';
}

/// مجموعة حسابات تحمل الاسم نفسه (للعرض في شاشة الدمج).
class DuplicateCustomerGroup {
  DuplicateCustomerGroup(this.key, this.accounts);

  /// الاسم بلا مسافات.
  final String key;

  /// الحسابات مرتبة من الأقدم.
  final List<DuplicateCustomerAccount> accounts;
}

class DuplicateCustomerAccount {
  DuplicateCustomerAccount({
    required this.id,
    required this.name,
    required this.phone,
    required this.balance,
    required this.transactionCount,
    required this.invoiceCount,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String? phone;

  /// مجموع المعاملات النشطة (المرجع المحاسبي للرصيد).
  final double balance;
  final int transactionCount;
  final int invoiceCount;
  final String? createdAt;
}

/// نتيجة دمج: الرصيد قبل وبعد للتحقق من أن المجموع لم يتغير.
class CustomerMergeResult {
  CustomerMergeResult({
    required this.survivorId,
    required this.mergedIds,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.uniqueIndexActive,
  });

  final int survivorId;
  final List<int> mergedIds;

  /// مجموع أرصدة كل الحسابات قبل الدمج.
  final double balanceBefore;

  /// رصيد الحساب الباقي بعد الدمج — يجب أن يساوي [balanceBefore].
  final double balanceAfter;

  /// هل صار الفهرس الفريد مفعّلاً بعد هذا الدمج (لم يبقَ تكرار)؟
  final bool uniqueIndexActive;
}

class CustomerNameRule {
  CustomerNameRule._();

  /// اسم الفهرس الفريد على الاسم.
  static const String uniqueIndexName = 'ux_customers_name_key';

  /// تعبير مفتاح الاسم في SQL — نفس [key] حرفاً بحرف.
  static const String sqlKey = "REPLACE(name, ' ', '')";

  /// الحساب النشط: غير محذوف وغير مدموج في غيره.
  static const String sqlActive = 'COALESCE(is_deleted, 0) = 0 AND merged_into_id IS NULL';

  /// مفتاح الاسم: الاسم بعد حذف المسافات.
  static String key(String name) => name.replaceAll(' ', '');

  /// يضيف عمود الدمج إن لم يوجد (آمن التكرار).
  static Future<void> ensureSchema(DatabaseExecutor db) async {
    final cols = await db.rawQuery('PRAGMA table_info(customers)');
    if (!cols.any((c) => c['name'] == 'merged_into_id')) {
      await db.execute('ALTER TABLE customers ADD COLUMN merged_into_id INTEGER');
    }
  }

  /// الحساب النشط الذي يحمل هذا الاسم (الأقدم إن وُجد تكرار قديم).
  static Future<Map<String, Object?>?> findActive(
    DatabaseExecutor db,
    String name, {
    int? excludeId,
  }) async {
    final k = key(name);
    if (k.isEmpty) return null;
    final args = <Object?>[k, if (excludeId != null) excludeId];
    final exclude = excludeId == null ? '' : ' AND id != ?';
    List<Map<String, Object?>> rows;
    try {
      rows = await db.rawQuery(
          'SELECT * FROM customers WHERE $sqlKey = ? AND $sqlActive$exclude ORDER BY id LIMIT 1', args);
    } on DatabaseException {
      // قاعدة لم يُضف لها عمود الدمج بعد: لا حسابات مدموجة فيها
      rows = await db.rawQuery(
          'SELECT * FROM customers WHERE $sqlKey = ? AND COALESCE(is_deleted, 0) = 0$exclude '
          'ORDER BY id LIMIT 1',
          args);
    }
    return rows.isEmpty ? null : rows.first;
  }

  /// يرمي [DuplicateCustomerNameException] إن وُجد حساب نشط آخر بهذا الاسم.
  static Future<void> ensureAvailable(
    DatabaseExecutor db,
    String name, {
    int? excludeId,
  }) async {
    final row = await findActive(db, name, excludeId: excludeId);
    if (row != null) {
      throw DuplicateCustomerNameException((row['name'] as String?) ?? name);
    }
  }

  /// الحساب الذي يُنسب إليه [customerId]: نفسه، أو الحساب الذي دُمج فيه.
  static Future<int> resolveMerged(DatabaseExecutor db, int customerId) async {
    final r = await db.rawQuery('SELECT * FROM customers WHERE id = ?', [customerId]);
    final m = r.isEmpty ? null : (r.first['merged_into_id'] as num?)?.toInt();
    return m ?? customerId;
  }

  /// كل مجموعات الأسماء المكررة بين الحسابات النشطة.
  static Future<List<DuplicateCustomerGroup>> duplicateGroups(DatabaseExecutor db) async {
    final keys = await db.rawQuery('''
      SELECT $sqlKey AS k FROM customers
      WHERE $sqlActive AND TRIM(name) != ''
      GROUP BY $sqlKey HAVING COUNT(*) > 1
      ORDER BY MIN(id)
    ''');
    final groups = <DuplicateCustomerGroup>[];
    for (final row in keys) {
      final k = row['k'] as String;
      final rows = await db.rawQuery('''
        SELECT c.id, c.name, c.phone, c.created_at,
          (SELECT COALESCE(SUM(t.amount_changed), 0) FROM transactions t
             WHERE t.customer_id = c.id AND COALESCE(t.is_deleted, 0) = 0) AS bal,
          (SELECT COUNT(*) FROM transactions t
             WHERE t.customer_id = c.id AND COALESCE(t.is_deleted, 0) = 0) AS txn,
          (SELECT COUNT(*) FROM invoices i
             WHERE i.customer_id = c.id AND COALESCE(i.is_deleted, 0) = 0) AS inv
        FROM customers c
        WHERE $sqlKey = ? AND $sqlActive
        ORDER BY c.id
      ''', [k]);
      groups.add(DuplicateCustomerGroup(k, [
        for (final r in rows)
          DuplicateCustomerAccount(
            id: (r['id'] as num).toInt(),
            name: (r['name'] as String?) ?? '',
            phone: r['phone'] as String?,
            balance: (r['bal'] as num?)?.toDouble() ?? 0.0,
            transactionCount: (r['txn'] as num?)?.toInt() ?? 0,
            invoiceCount: (r['inv'] as num?)?.toInt() ?? 0,
            createdAt: r['created_at'] as String?,
          ),
      ]));
    }
    return groups;
  }

  /// الجداول التي تشير إلى العميل بـ customer_id. الجداول التي يكون
  /// customer_id فيها مفتاحاً أساسياً (سجل واحد لكل عميل) تُعالج بلا تعارض:
  /// سجل الحساب المدموج يُنقل فقط إن لم يكن للباقي سجل.
  static const List<String> _customerIdTables = [
    'transactions',
    'invoices',
    'customer_receipt_vouchers',
    'customer_receipt_lines',
    'customer_reconciliations',
    'returns',
    'sales_returns',
    'quotations',
    'debt_reminders',
    'debt_reminder_members',
    'customer_brand_preferences',
    'transaction_backups',
  ];
  static const List<String> _onePerCustomerTables = ['customer_ext', 'party_links'];
  static const List<String> _partyTables = ['journal_lines', 'due_items', 'orders'];

  /// يدمج [mergedIds] في [survivorId] داخل معاملة واحدة: ينقل كل ما يشير إليها
  /// (معاملات، فواتير، سندات، تذكيرات...) إلى الباقي، ويخفي الحسابات المدموجة
  /// (لا حذف)، ويضيف هاتف الباقي من المدموج إن كان فارغاً.
  ///
  /// لا يغيّر أي مبلغ: رصيد الباقي بعد الدمج = مجموع أرصدة الحسابات قبله.
  /// إعادة بناء السلسلة التراكمية (الرصيد قبل/بعد لكل معاملة) مسؤولية المستدعي
  /// بعد هذه الدالة (عبر DatabaseService) — انظر [CustomerMergeService].
  static Future<CustomerMergeResult> mergeInto(
    Database db,
    int survivorId,
    List<int> mergedIds,
  ) async {
    final ids = mergedIds.where((id) => id != survivorId).toSet().toList();
    if (ids.isEmpty) {
      throw ArgumentError('لا توجد حسابات للدمج');
    }
    await ensureSchema(db);

    return db.transaction((txn) async {
      // 1) التحقق: كل الحسابات نشطة وتحمل الاسم نفسه
      final all = [survivorId, ...ids];
      final ph = List.filled(all.length, '?').join(',');
      final rows = await txn.rawQuery(
          'SELECT id, name, phone, $sqlKey AS k FROM customers WHERE id IN ($ph) AND $sqlActive', all);
      if (rows.length != all.length) {
        throw StateError('أحد الحسابات محذوف أو مدموج مسبقاً — أعد فتح الشاشة');
      }
      final keys = rows.map((r) => r['k']).toSet();
      if (keys.length != 1) {
        throw StateError('لا يُدمج إلا حسابات بالاسم نفسه');
      }

      Future<double> sumOf(List<int> list) async {
        final p = List.filled(list.length, '?').join(',');
        final r = await txn.rawQuery(
            'SELECT COALESCE(SUM(amount_changed), 0) AS s FROM transactions '
            'WHERE customer_id IN ($p) AND COALESCE(is_deleted, 0) = 0',
            list);
        return (r.first['s'] as num?)?.toDouble() ?? 0.0;
      }

      final before = await sumOf(all);

      final existingTables = {
        for (final r in await txn.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
          r['name'] as String,
      };
      Future<bool> hasColumn(String table, String column) async {
        final cols = await txn.rawQuery('PRAGMA table_info($table)');
        return cols.any((c) => c['name'] == column);
      }

      final idPh = List.filled(ids.length, '?').join(',');

      // 2) نقل كل ما يشير إلى الحسابات المدموجة
      for (final t in _customerIdTables) {
        if (!existingTables.contains(t) || !await hasColumn(t, 'customer_id')) continue;
        await txn.rawUpdate(
            'UPDATE $t SET customer_id = ? WHERE customer_id IN ($idPh)', [survivorId, ...ids]);
      }
      for (final t in _onePerCustomerTables) {
        if (!existingTables.contains(t) || !await hasColumn(t, 'customer_id')) continue;
        final has = await txn.rawQuery('SELECT 1 FROM $t WHERE customer_id = ? LIMIT 1', [survivorId]);
        if (has.isEmpty) {
          // أول سجل للمدموج ينتقل للباقي؛ البقية تبقى على المدموج المخفي
          final first = await txn.rawQuery(
              'SELECT customer_id FROM $t WHERE customer_id IN ($idPh) ORDER BY customer_id LIMIT 1', ids);
          if (first.isNotEmpty) {
            await txn.rawUpdate('UPDATE $t SET customer_id = ? WHERE customer_id = ?',
                [survivorId, first.first['customer_id']]);
          }
        }
      }
      for (final t in _partyTables) {
        if (!existingTables.contains(t) ||
            !await hasColumn(t, 'party_id') ||
            !await hasColumn(t, 'party_type')) {
          continue;
        }
        await txn.rawUpdate(
            "UPDATE $t SET party_id = ? WHERE party_type = 'customer' AND party_id IN ($idPh)",
            [survivorId, ...ids]);
      }

      // 3) هاتف الباقي: إن كان فارغاً يؤخذ أول هاتف من المدموجين
      final survivorRow = rows.firstWhere((r) => r['id'] == survivorId);
      final now = DateTime.now().toIso8601String();
      final update = <String, Object?>{'last_modified_at': now};
      if (((survivorRow['phone'] as String?) ?? '').trim().isEmpty) {
        for (final r in rows) {
          final p = ((r['phone'] as String?) ?? '').trim();
          if (r['id'] != survivorId && p.isNotEmpty) {
            update['phone'] = p;
            break;
          }
        }
      }

      // 4) إخفاء المدموجين (لا حذف): يشيرون للباقي، ورصيدهم صفر لأن معاملاتهم انتقلت
      await txn.rawUpdate(
          'UPDATE customers SET is_deleted = 1, merged_into_id = ?, current_total_debt = 0, '
          'last_modified_at = ? WHERE id IN ($idPh)',
          [survivorId, now, ...ids]);
      // دمج سابق في أحد المدموجين يتبع الباقي مباشرة (سلسلة بمستوى واحد)
      await txn.rawUpdate(
          'UPDATE customers SET merged_into_id = ? WHERE merged_into_id IN ($idPh)', [survivorId, ...ids]);

      // 5) رصيد الباقي = مجموع معاملاته (المرجع المحاسبي) — يجب أن يساوي المجموع قبل الدمج
      final after = await sumOf([survivorId]);
      if ((after - before).abs() > 0.005) {
        throw StateError('أُلغي الدمج: الرصيد بعد الدمج ($after) لا يساوي المجموع قبله ($before)');
      }
      update['current_total_debt'] = after;
      if (await hasColumn('customers', 'current_total_debt_cents')) {
        update['current_total_debt_cents'] = (after * 100).round();
      }
      try {
        await txn.update('customers', update, where: 'id = ?', whereArgs: [survivorId]);
      } on DatabaseException catch (e) {
        // قيد UNIQUE(name, phone) القديم: الهاتف المنقول يطابق حساباً آخر — يبقى بلا هاتف
        if (!e.isUniqueConstraintError()) rethrow;
        update.remove('phone');
        await txn.update('customers', update, where: 'id = ?', whereArgs: [survivorId]);
      }

      return CustomerMergeResult(
        survivorId: survivorId,
        mergedIds: ids,
        balanceBefore: before,
        balanceAfter: after,
        uniqueIndexActive: false,
      );
    });
  }

  /// معرّف الحساب المحلي لهوية مزامنة [syncUuid] بعد اتباع الدمج: إن كانت
  /// الهوية لحساب مدموج يُعاد الحساب الباقي، فلا يُسجَّل ما يصل بها على صف مخفي.
  static Future<Map<String, Object?>?> byUuidResolved(
    DatabaseExecutor db,
    String syncUuid, {
    List<String>? columns,
  }) async {
    final rows = await db.query('customers',
        where: 'sync_uuid = ?', whereArgs: [syncUuid], limit: 1);
    if (rows.isEmpty) return null;
    final merged = (rows.first['merged_into_id'] as num?)?.toInt();
    final target = merged == null
        ? rows
        : await db.query('customers', where: 'id = ?', whereArgs: [merged], limit: 1);
    if (target.isEmpty) return null;
    if (columns == null) return target.first;
    return {for (final c in columns) c: target.first[c]};
  }

  /// يضبط الفهرس الفريد حسب وضع الجهاز. مع المزامنة السحابية لا يُفرض في
  /// القاعدة: كل جهاز يحمل هوية مستقلة لكل حساب وفحوص المزامنة تقارن رصيد كل
  /// هوية بين الأجهزة، فدمج هويتين على جهاز واحد يفرّق الأرصدة بين الأجهزة
  /// (سيناريو 13)، ورفض حساب وارد يُيتّم معاملاته. قاعدة «الاسم فريد» تبقى
  /// مفروضة في التطبيق نفسه (حفظ الفاتورة، إضافة العميل وتعديله).
  static Future<bool> applyIndexForMode(DatabaseExecutor db, {required bool cloudSync}) async {
    if (cloudSync) {
      await dropUniqueIndex(db);
      return false;
    }
    return enforceUniqueIndex(db);
  }

  static Future<void> dropUniqueIndex(DatabaseExecutor db) async {
    try {
      await db.execute('DROP INDEX IF EXISTS $uniqueIndexName');
    } catch (_) {}
  }

  /// ينشئ الفهرس الفريد على الاسم إن خلت القاعدة من التكرار. يعيد true إن
  /// كان الفهرس مفعّلاً بعد الاستدعاء. آمن التكرار.
  static Future<bool> enforceUniqueIndex(DatabaseExecutor db) async {
    try {
      await ensureSchema(db);
      final exists = await db.rawQuery(
          "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = ?", [uniqueIndexName]);
      if (exists.isNotEmpty) return true;
      final dup = await db.rawQuery('''
        SELECT 1 FROM customers WHERE $sqlActive AND TRIM(name) != ''
        GROUP BY $sqlKey HAVING COUNT(*) > 1 LIMIT 1
      ''');
      if (dup.isNotEmpty) return false; // ينتظر دمج المستخدم
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS $uniqueIndexName ON customers($sqlKey) WHERE $sqlActive');
      return true;
    } catch (_) {
      return false;
    }
  }
}
