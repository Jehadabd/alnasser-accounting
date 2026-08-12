// lib/services/firebase_sync/invoice_sync_coordinator.dart
import '../database_service.dart';

class InvoiceSyncCoordinator {
  static final InvoiceSyncCoordinator _instance = InvoiceSyncCoordinator._internal();
  factory InvoiceSyncCoordinator() => _instance;
  InvoiceSyncCoordinator._internal();

  final DatabaseService _dbService = DatabaseService();

  /// 📥 قراءة الفواتير غير المرفوعة للفايربيس
  Future<List<Map<String, dynamic>>> getPendingInvoices() async {
    final db = await _dbService.database;
    
    // جلب الفواتير التي فيها is_synced = 0
    final pendingInvoices = await db.query(
      'invoices',
      where: 'is_synced = 0 AND invoice_uuid IS NOT NULL',
    );

    List<Map<String, dynamic>> fullInvoices = [];

    for (var inv in pendingInvoices) {
      final invoiceMap = Map<String, dynamic>.from(inv);
      final invoiceId = inv['id'] as int;

      // جلب بنود الفاتورة المرفقة معها
      final items = await db.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );

      invoiceMap['items'] = items;
      fullInvoices.add(invoiceMap);
    }

    return fullInvoices;
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
