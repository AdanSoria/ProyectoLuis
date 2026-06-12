/// Resultados de la analítica local (calculada 100% en SQLite,
/// sin depender de la nube). Solo cuentan transacciones completadas.
library;

class TopBuyer {
  const TopBuyer({
    required this.customerId,
    required this.name,
    required this.totalCents,
    required this.purchases,
  });

  final String customerId;
  final String name;
  final int totalCents;
  final int purchases;

  int get averageTicketCents => purchases == 0 ? 0 : totalCents ~/ purchases;
}

class ChannelSales {
  const ChannelSales({
    required this.channelCode,
    required this.totalCents,
    required this.count,
  });

  final String channelCode;
  final int totalCents;
  final int count;
}

class CategorySales {
  const CategorySales({
    required this.category,
    required this.totalCents,
    required this.quantity,
  });

  final String category;
  final int totalCents;
  final double quantity;
}

/// Paquete completo para la pantalla de clientes/analítica.
class CustomerInsights {
  const CustomerInsights({
    required this.topBuyers,
    required this.byChannel,
    required this.topCategories,
  });

  final List<TopBuyer> topBuyers;
  final List<ChannelSales> byChannel;
  final List<CategorySales> topCategories;
}
