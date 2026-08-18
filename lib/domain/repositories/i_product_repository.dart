// lib/domain/repositories/i_product_repository.dart
import '../../models/product.dart';

/// واجهة المستودع لجميع عمليات المنتجات وفقاً لـ Clean Architecture
abstract class IProductRepository {
  Future<int> insertProduct(Product product);
  Future<List<Product>> getAllProducts({String orderBy});
  Future<Product?> getProductById(int id);
  Future<Product?> getProductByName(String name);
  Future<int> updateProduct(Product product);
  Future<int> deleteProduct(int id);
  Future<List<ProductPrice>> getProductPrices(int productId);
  Future<List<ProductUnit>> getProductUnits(int productId);
  Future<int> insertProductPrice(ProductPrice price);
  Future<int> insertProductUnit(ProductUnit unit);
}
