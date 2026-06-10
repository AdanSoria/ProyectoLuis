import '../../core/utils/result.dart';
import '../entities/customer.dart';

abstract class CustomerRepository {
  /// Clientes más recientes para los chips de selección rápida.
  Future<List<Customer>> getRecent(int limit);

  Future<List<Customer>> search(String query);

  Future<Result<Customer>> save(Customer customer, {required bool isNew});
}
