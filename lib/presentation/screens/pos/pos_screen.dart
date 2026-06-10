import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/money.dart';
import '../../providers.dart';
import 'widgets/catalog_panel.dart';
import 'widgets/ticket_panel.dart';

/// Flujo de Mostrador (Fricción Cero).
///
/// Árbol principal en pantallas grandes (split screen):
///
/// PosScreen
/// └── Row
///     ├── Expanded(flex 3) ──► CatalogPanel   (búsqueda + chips + grid)
///     │                         └── ProductCard (1 tap = al carrito)
///     ├── VerticalDivider
///     └── SizedBox(width 380) ► TicketPanel   (líneas + totales)
///                               ├── botón COBRAR  ► ChargeDialog
///                               └── botón PEDIDO  ► DeliveryFlowSheet (3 pasos)
///
/// En pantallas angostas el ticket se convierte en hoja inferior
/// invocada por un botón flotante con el total.
class PosScreen extends ConsumerWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= AppConfig.splitScreenBreakpoint;

        if (split) {
          return const Row(
            children: [
              Expanded(flex: 3, child: CatalogPanel()),
              VerticalDivider(thickness: 1, width: 1),
              SizedBox(width: 380, child: TicketPanel()),
            ],
          );
        }

        final cart = ref.watch(cartProvider);
        return Scaffold(
          body: const CatalogPanel(),
          floatingActionButton: cart.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _openTicketSheet(context),
                  icon: Badge.count(
                    count: cart.itemCount.round(),
                    child: const Icon(Icons.shopping_cart),
                  ),
                  label: Text(Money.format(cart.totalCents)),
                ),
        );
      },
    );
  }

  void _openTicketSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.92,
        child: TicketPanel(),
      ),
    );
  }
}
