import '../entities/insights.dart';
import '../repositories/transaction_repository.dart';

/// Analítica local del mini-CRM: top de compradores y análisis de
/// mercado básico (canales y categorías), todo resuelto con consultas
/// SQL sobre la base local — cero dependencia de la nube.
class GetCustomerInsightsUseCase {
  GetCustomerInsightsUseCase({required TransactionRepository transactions})
      : _transactions = transactions;

  final TransactionRepository _transactions;

  Future<CustomerInsights> call() async => CustomerInsights(
        topBuyers: await _transactions.getTopBuyers(),
        byChannel: await _transactions.getSalesByChannel(),
        topCategories: await _transactions.getTopCategories(),
      );
}
