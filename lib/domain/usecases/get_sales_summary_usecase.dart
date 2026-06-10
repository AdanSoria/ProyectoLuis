import '../entities/transaction.dart';
import '../repositories/transaction_repository.dart';

/// Artículo dentro del ranking de más vendidos.
class TopItem {
  const TopItem({
    required this.name,
    required this.quantity,
    required this.totalCents,
  });

  final String name;
  final double quantity;
  final int totalCents;
}

/// Métricas del día para el panel de resumen.
class SalesSummary {
  const SalesSummary({
    required this.totalSalesCents,
    required this.netProfitCents,
    required this.ticketCount,
    required this.pendingOrders,
    required this.topItems,
  });

  /// Ventas cobradas (transacciones completadas) del día.
  final int totalSalesCents;

  /// `utilidad_neta` acumulada del día.
  final int netProfitCents;

  final int ticketCount;

  /// Pedidos vivos (pendientes + asignados), histórico completo.
  final int pendingOrders;

  final List<TopItem> topItems;

  int get averageTicketCents =>
      ticketCount == 0 ? 0 : totalSalesCents ~/ ticketCount;
}

/// Calcula el flujo de caja del día a partir de las transacciones
/// completadas: solo cuenta dinero que realmente entró.
class GetSalesSummaryUseCase {
  GetSalesSummaryUseCase({
    required TransactionRepository transactions,
    DateTime Function()? now,
  })  : _transactions = transactions,
        _now = now ?? DateTime.now;

  final TransactionRepository _transactions;
  final DateTime Function() _now;

  Future<SalesSummary> call({DateTime? day}) async {
    final reference = day ?? _now();
    final start = DateTime(reference.year, reference.month, reference.day);
    final end = start.add(const Duration(days: 1));

    final todays = await _transactions.getByDateRange(start, end);
    final completed =
        todays.where((t) => t.status == OrderStatus.completado).toList();

    var totalSales = 0;
    var netProfit = 0;
    final byItem = <String, ({String name, double qty, int total})>{};

    for (final txn in completed) {
      totalSales += txn.totalCents;
      netProfit += txn.netProfitCents;
      for (final line in txn.lines) {
        final prev = byItem[line.itemId];
        byItem[line.itemId] = (
          name: line.itemName,
          qty: (prev?.qty ?? 0) + line.quantity,
          total: (prev?.total ?? 0) + line.totalCents,
        );
      }
    }

    final ranked = byItem.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return SalesSummary(
      totalSalesCents: totalSales,
      netProfitCents: netProfit,
      ticketCount: completed.length,
      pendingOrders: await _transactions.countOrders(
        statuses: const [OrderStatus.pendiente, OrderStatus.asignado],
      ),
      topItems: [
        for (final item in ranked.take(5))
          TopItem(name: item.name, quantity: item.qty, totalCents: item.total),
      ],
    );
  }
}
