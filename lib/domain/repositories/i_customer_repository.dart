// lib/domain/repositories/i_customer_repository.dart
import '../../models/customer.dart';

/// واجهة المستودع لإدارة العملاء والديون المحسوبة ديناميكياً وفقاً لـ Clean Architecture
abstract class ICustomerRepository {
  Future<int> insertCustomer(Customer customer);
  Future<List<Customer>> getAllCustomers({String orderBy});
  Future<Customer?> getCustomerById(int id);
  Future<int> updateCustomer(Customer customer);
  Future<int> deleteCustomer(int id);
  Future<double> getCustomerBalanceFromView(int customerId);
}
