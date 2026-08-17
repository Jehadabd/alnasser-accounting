// lib/services/firebase_sync/invoice_sync_coordinator.dart
import '../database_service.dart';

class InvoiceSyncCoordinator {
  static final InvoiceSyncCoordinator _instance = InvoiceSyncCoordinator._internal();
  factory InvoiceSyncCoordinator() => _instance;
  InvoiceSyncCoordinator._internal();

  final DatabaseService _dbService = DatabaseService();

  /// 📥 قراءة الفواتير غير المرفوعة للفايربيس (مع أصنافها ومعاملاتها المالية والعميل)
  Future<List<Map<String, dynamic>>> getPendingInvoices() async {
    final db = await _dbService.database;

    final pendingInvoices = await db.query(
      'invoices',
      where: 'is_synced = 0 AND invoice_uuid IS NOT NULL',
    );

    List<Map<String, dynamic>> fullInvoices = [];

    for (var inv in pendingInvoices) {
      final invoiceMap = Map<String, dynamic>.from(inv);
      await _attachInvoiceRelations(invoiceMap);
      fullInvoices.add(invoiceMap);
    }

    return fullInvoices;
  }

  /// 📥 قراءة فاتورة واحدة كاملة (للرفع الفوري بعد الحفظ)
  /// تشمل: بيانات الفاتورة + items + transactions + لقطة العميل
  Future<Map<String, dynamic>?> getFullInvoiceByUuid(String invoiceUuid) async {
    final db = await _dbService.database;

    final invoiceRows = await db.query(
      'invoices',
      where: 'invoice_uuid = ?',
      whereArgs: [invoiceUuid],
      limit: 1,
    );
    if (invoiceRows.isEmpty) return null;

    final invoiceMap = Map<String, dynamic>.from(invoiceRows.first);
    await _attachInvoiceRelations(invoiceMap);
    return invoiceMap;
  }

  /// يرفق البنود والمعاملات ولقطة العميل حتى تصل حزمة الدين كاملة للجهاز الآخر.
  Future<void> _attachInvoiceRelations(Map<String, dynamic> invoiceMap) async {
    final db = await _dbService.database;
    final invoiceId = invoiceMap['id'] as int;
    final invoiceUuid = invoiceMap['invoice_uuid'] as String?;

    invoiceMap['items'] = await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
    );

    List<Map<String, Object?>> transactions = const [];
    if (invoiceUuid != null && invoiceUuid.isNotEmpty) {
      transactions = await db.query(
        'transactions',
        where: 'invoice_sync_uuid = ?',
        whereArgs: [invoiceUuid],
      );
    }
    // احتياط: معاملات رُبطت بـ invoice_id فقط (إصدارات قديمة بلا invoice_sync_uuid)
    if (transactions.isEmpty) {
      transactions = await db.query(
        'transactions',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );
    }
    invoiceMap['transactions'] = transactions;

    final customerId = invoiceMap['customer_id'] as int?;
    if (customerId != null && customerId != 0) {
      final customers = await db.query(
        'customers',
        columns: ['name', 'phone', 'address', 'sync_uuid'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );
      if (customers.isNotEmpty) {
        invoiceMap['customer'] = Map<String, dynamic>.from(customers.first);
      }
    }
  }

  /// ✅ التأشير على أن المعاملة المالية رُفعت بنجاح (جزء من حزمة الفاتورة)
  Future<void> markTransactionAsSynced(String transactionUuid) async {
    final db = await _dbService.database;
    await db.update(
      'transactions',
      {'is_uploaded': 1},
      where: 'transaction_uuid = ? OR sync_uuid = ?',
      whereArgs: [transactionUuid, transactionUuid],
    );
  }

  /// ✅ التأشير على أن الفاتورة تم رفعها بنجاح
  Future<void> markAsSynced(String invoiceUuid) async {
    final db = await _dbService.database;
    await db.update(
      'invoices',
      {'is_synced': 1},
      where: 'invoice_uuid = ?',
      whereArgs: [invoiceUuid],
    );
  }

  /// 🔢 جلب رقم النسخة (Version) المحلي للفاتورة
  Future<int> getLocalInvoiceVersion(String invoiceUuid) async {
    final db = await _dbService.database;
    final result = await db.query(
      'invoices',
      columns: ['version'],
      where: 'invoice_uuid = ?',
      whereArgs: [invoiceUuid],
      limit: 1,
    );
    if (result.isEmpty) return 0;
    return (result.first['version'] as int?) ?? 0;
  }
}
