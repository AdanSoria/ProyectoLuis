import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers.dart';
import 'product_card.dart';

/// Catálogo visual rápido: búsqueda incremental + chips de categoría +
/// cuadrícula de tarjetas. Sin formularios, sin IDs, sin fricción.
class CatalogPanel extends ConsumerWidget {
  const CatalogPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(filteredCatalogProvider);
    final categories = ref.watch(categoriesProvider);
    final selectedCategory = ref.watch(categoryFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            onChanged: (value) =>
                ref.read(catalogSearchProvider.notifier).state = value,
            decoration: const InputDecoration(
              hintText: 'Buscar producto o servicio…',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: categories.maybeWhen(
            data: (names) => ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('Todo'),
                    selected: selectedCategory == null,
                    onSelected: (_) =>
                        ref.read(categoryFilterProvider.notifier).state = null,
                  ),
                ),
                for (final name in names)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(name),
                      selected: selectedCategory == name,
                      onSelected: (_) => ref
                          .read(categoryFilterProvider.notifier)
                          .state = selectedCategory == name ? null : name,
                    ),
                  ),
              ],
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ),
        Expanded(
          child: catalog.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Error: $error')),
            data: (items) => items.isEmpty
                ? const Center(child: Text('Sin resultados en el catálogo.'))
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 210,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.15,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) => ProductCard(item: items[i]),
                  ),
          ),
        ),
      ],
    );
  }
}
