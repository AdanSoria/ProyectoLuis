import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../providers.dart';
import '../widgets/sync_status_chip.dart';
import 'customers/customers_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'inventory/inventory_screen.dart';
import 'orders/orders_screen.dart';
import 'pos/pos_screen.dart';

/// Armazón de navegación adaptable:
/// - escritorio/tablet ancha: NavigationRail lateral;
/// - teléfono: NavigationBar inferior.
/// Las pantallas viven en un IndexedStack para no perder estado al cambiar.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _titles = [
    'Mostrador',
    'Pedidos',
    'Clientes',
    'Inventario',
    'Resumen',
  ];

  @override
  void initState() {
    super.initState();
    // Arranca la sincronización silenciosa en segundo plano.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncEngineProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pendingOrders = ref
        .watch(pendingOrdersCountProvider)
        .maybeWhen(data: (n) => n, orElse: () => 0);

    const pages = [
      PosScreen(),
      OrdersScreen(),
      CustomersScreen(),
      InventoryScreen(),
      DashboardScreen(),
    ];

    final ordersIcon = Badge.count(
      count: pendingOrders,
      isLabelVisible: pendingOrders > 0,
      child: const Icon(Icons.local_shipping_outlined),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= AppConfig.railBreakpoint;

        final appBar = AppBar(
          title: Text('${AppConfig.appName} · ${_titles[_index]}'),
          actions: const [SyncStatusChip(), SizedBox(width: 12)],
        );

        if (useRail) {
          return Scaffold(
            appBar: appBar,
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  leading: const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Icon(Icons.storefront, size: 32),
                  ),
                  destinations: [
                    const NavigationRailDestination(
                      icon: Icon(Icons.point_of_sale_outlined),
                      selectedIcon: Icon(Icons.point_of_sale),
                      label: Text('Mostrador'),
                    ),
                    NavigationRailDestination(
                      icon: ordersIcon,
                      label: const Text('Pedidos'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: Text('Clientes'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      selectedIcon: Icon(Icons.inventory_2),
                      label: Text('Inventario'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.insights_outlined),
                      selectedIcon: Icon(Icons.insights),
                      label: Text('Resumen'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: IndexedStack(index: _index, children: pages)),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: appBar,
          body: IndexedStack(index: _index, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.point_of_sale_outlined),
                selectedIcon: Icon(Icons.point_of_sale),
                label: 'Mostrador',
              ),
              NavigationDestination(icon: ordersIcon, label: 'Pedidos'),
              const NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Clientes',
              ),
              const NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2),
                label: 'Inventario',
              ),
              const NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: 'Resumen',
              ),
            ],
          ),
        );
      },
    );
  }
}
