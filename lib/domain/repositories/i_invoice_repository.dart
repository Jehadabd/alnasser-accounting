// lib/domain/repositories/i_invoice_repository.dart
import '../../models/invoice.dart';
import '../../models/invoice_item.dart';

/// واجهة المستودع لجميع عمليات الفواتير وبنودها المنظمة بدون JSON
abstract class IInvoiceRepository {
  Future<int> insertInvoice(Invoice invoice);
  Future<Invoice?> getInvoiceById(int id);
  Future<List<Invoice>> getAllInvoices({String orderBy});
  Future<int> updateInvoice(Invoice invoice);
  Future<int> deleteInvoice(int id);
  Future<int> insertInvoiceItem(InvoiceItem item);
  Future<List<InvoiceItem>> getInvoiceItems(int invoiceId);
}
