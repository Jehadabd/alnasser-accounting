// lib/services/database/dao/invoice_dao.dart
// 📄 DAO المسئول عن الفواتير - Crud Operations

import 'package:sqflite/sqflite.dart';
import '../../../models/invoice.dart';
import '../../../models/invoice_item.dart';
import '../../../models/invoice_adjustment.dart';

class InvoiceDao {
  // دالة للحصول على قاعدة البيانات
  final Future<Database> Function() getDatabase;

  InvoiceDao({required this.getDatabase});

  // 1️⃣ إدخال فاتورة (بدون Transaction Logic المعقد - فقط إدخال Row)
  Future<int> insertInvoice(Invoice invoice) async {
    final db = await getDatabase();
    final map = invoice.toMap();
    map.remove('id'); // auto-increment
    return await db.insert('invoices', map);
  }

  // 2️⃣ جلب فاتورة بواسطة ID
  Future<Invoice?> getInvoiceById(int id) async {
    final db = await getDatabase();
    final maps = await db.query(
      'invoices',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Invoice.fromMap(maps.first);
    }
    return null;
  }

  // 3️⃣ جلب كل الفواتير
  Future<List<Invoice>> getAllInvoices({String orderBy = 'invoice_date DESC, id DESC'}) async {
    final db = await getDatabase();
    final maps = await db.query('invoices', orderBy: orderBy);
    return List.generate(maps.length, (i) => Invoice.fromMap(maps[i]));
  }
  
  // 📄 جلب الفواتير بشكل صفحات (Pagination)
  Future<List<Invoice>> getInvoicesPaginated({
    required int limit,
    required int offset,
    String? searchName,
    String? searchId,
  }) async {
    final db = await getDatabase();
    
    String whereClause = '1=1';
    List<dynamic> args = [];
    
    if (searchName != null && searchName.isNotEmpty) {
      whereClause += ' AND customer_name LIKE ?';
      args.add('%$searchName%');
    }
    
    if (searchId != null && searchId.isNotEmpty) {
      // ✅ البحث برقم الفاتورة التجاري فقط (invoice_number)؛ الـ id الداخلي للتتبع التقني حصراً
      whereClause += ' AND invoice_number LIKE ?';
      args.add('%$searchId%');
    }
    
    final maps = await db.query(
      'invoices',
      where: whereClause,
      whereArgs: args,
      orderBy: 'invoice_date DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    
    return List.generate(maps.length, (i) => Invoice.fromMap(maps[i]));
  }
  
  // 📄 جلب تعديلات الفواتير لعدة فواتير دفعة واحدة
  Future<Map<int, List<InvoiceAdjustment>>> getInvoiceAdjustmentsMapForIds(List<int> invoiceIds) async {
    if (invoiceIds.isEmpty) return {};
    
    final db = await getDatabase();
    final placeholders = List.filled(invoiceIds.length, '?').join(',');
    
    final maps = await db.query(
      'invoice_adjustments',
      where: 'invoice_id IN ($placeholders)',
      whereArgs: invoiceIds,
      orderBy: 'created_at DESC',
    );
    
    final Map<int, List<InvoiceAdjustment>> result = {};
    for (var map in maps) {
      final adj = InvoiceAdjustment.fromMap(map);
      final invoiceId = adj.invoiceId;
      result.putIfAbsent(invoiceId, () => []);
      result[invoiceId]!.add(adj);
    }
    
    return result;
  }
  
  // 4️⃣ جلب الفواتير الأحدث من تاريخ معين
  Future<List<Invoice>> getInvoicesCreatedAfter(DateTime date) async {
    final db = await getDatabase();
    final maps = await db.query(
      'invoices',
      where: 'created_at > ?',
      whereArgs: [date.toIso8601String()],
    );
     return List.generate(maps.length, (i) => Invoice.fromMap(maps[i]));
  }

  // 5️⃣ تحديث الفاتورة (بيانات أساسية فقط)
  // ⚠️ تنبيه: تحديث المبالغ هنا قد يسبب خلل محاسبي إذا لم يتم عبر Manager
  // هذه الدالة لتحديث الحالات، الملاحظات، أو البيانات غير المالية
  Future<int> updateInvoice(Invoice invoice) async {
    final db = await getDatabase();
    
    // 🛡️ حماية على مستوى قاعدة البيانات: منع تعديل فواتير مزامنة من أجهزة أخرى
    if (!invoice.isCreatedByMe) {
      throw Exception('لا يمكن تعديل هذه الفاتورة لأنها مستوردة من جهاز آخر.');
    }
    
    return await db.update(
      'invoices',
      invoice.toMap(),
      where: 'id = ?',
      whereArgs: [invoice.id],
    );
  }

  // 6️⃣ حذف فاتورة
  // ⚠️ تنبيه: الحذف المالي المعقد يتم في DatabaseService للربط مع Transactions
  // هذه الدالة تحذف الـ Row فقط
  Future<int> deleteInvoice(int id) async {
    final db = await getDatabase();
    
    // 🛡️ حماية على مستوى قاعدة البيانات: منع حذف فواتير مزامنة من أجهزة أخرى
    final check = await db.query('invoices', columns: ['is_created_by_me'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (check.isNotEmpty && check.first['is_created_by_me'] == 0) {
      throw Exception('لا يمكن حذف هذه الفاتورة لأنها مستوردة من جهاز آخر.');
    }
    
    return await db.transaction((txn) async {
      // حذف العناصر أولاً
      await txn.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);
      // حذف الفاتورة
      return await txn.delete('invoices', where: 'id = ?', whereArgs: [id]);
    });
  }

  // 📦 التعامل مع عناصر الفاتورة (Invoice Items)
  Future<int> insertInvoiceItem(InvoiceItem item) async {
    final db = await getDatabase();
    final map = item.toMap();
    map.remove('id');
    return await db.insert('invoice_items', map);
  }

  Future<List<InvoiceItem>> getInvoiceItems(int invoiceId) async {
    final db = await getDatabase();
    final maps = await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
    );
    return List.generate(maps.length, (i) => InvoiceItem.fromMap(maps[i]));
  }
  
  // 🔧 تعديلات الفاتورة (Adjustments)
  Future<int> insertInvoiceAdjustment(InvoiceAdjustment adj) async {
    final db = await getDatabase();
    final map = adj.toMap();
    map.remove('id');
    
    // إضافة التعديل وتحديث إجمالي الفاتورة في نفس الوقت
    return await db.transaction((txn) async {
      final id = await txn.insert('invoice_adjustments', map);
      
      // تحديث إجمالي الفاتورة (انعكاس التعديل)
      // هذا تحديث "محلي" للفاتورة، أما التأثير على دين العميل فيجب أن يتم عبر Manager
      final adjustmentAmount = adj.amountDelta;
      await txn.rawUpdate(
        'UPDATE invoices SET total_amount = total_amount + ? WHERE id = ?',
        [adjustmentAmount, adj.invoiceId]
      );
      
      return id;
    });
  }
  
  Future<List<InvoiceAdjustment>> getInvoiceAdjustments(int invoiceId) async {
    final db = await getDatabase();
    final maps = await db.query(
      'invoice_adjustments',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'created_at DESC'
    );
    return maps.map((m) => InvoiceAdjustment.fromMap(m)).toList();
  }
  
  // 🔒 قفل وفتح الفواتير
  Future<void> lockInvoice(int invoiceId, {String? createdBy}) async {
    final db = await getDatabase();
    await db.update(
      'invoices', 
      {'is_locked': 1},
      where: 'id = ?',
      whereArgs: [invoiceId]
    );
  }
  
  Future<void> unlockInvoice(int invoiceId, {String? createdBy}) async {
     final db = await getDatabase();
    await db.update(
      'invoices', 
      {'is_locked': 0},
      where: 'id = ?',
      whereArgs: [invoiceId]
    );
  }
  
  // 🔎 استعلامات متقدمة
  
  /// الحصول على آخر N أسعار لمنتج معين مع عميل معين
  Future<List<Map<String, dynamic>>> getLastNPricesForCustomerProduct({
    required String customerName,
    String? customerPhone,
    required String productName,
    int limit = 3,
    String? saleType,
  }) async {
    final db = await getDatabase();
    String whereClause = 'i.customer_name = ? AND ii.product_name = ?';
    List<dynamic> args = [customerName, productName];

    if (saleType != null) {
      whereClause += ' AND ii.unit_name = ?';
      args.add(saleType);
    }

    final query = '''
      SELECT
        ii.applied_price,
        ii.unit_name,
        i.invoice_date,
        i.id as invoice_id,
        i.invoice_number
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      WHERE $whereClause
      ORDER BY i.invoice_date DESC
      LIMIT ?
    ''';
    args.add(limit);

    return await db.rawQuery(query, args);
  }
}
