// Prueba de humo de la capa visual: tema y formato de moneda en pantalla.
// (Las reglas de negocio se prueban a fondo en test/domain/.)
import 'package:agropos/core/theme/app_theme.dart';
import 'package:agropos/core/utils/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('el tema construye y la moneda se formatea en centavos',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(child: Text(Money.format(175050))),
        ),
      ),
    );

    expect(find.text(r'$1,750.50'), findsOneWidget);
  });
}
