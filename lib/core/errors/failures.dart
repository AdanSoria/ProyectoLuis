/// Fallas de dominio tipadas. Las capas superiores deciden cómo mostrarlas;
/// el dominio solo describe QUÉ salió mal, nunca lanza excepciones crudas
/// hacia la interfaz.
sealed class Failure {
  const Failure(this.message);

  /// Mensaje listo para mostrarse al usuario final (en español).
  final String message;

  @override
  String toString() => message;
}

/// Datos de entrada inválidos (carrito vacío, cantidades negativas, etc.).
class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

/// Un producto no tiene existencias suficientes para la venta.
class InsufficientStockFailure extends Failure {
  InsufficientStockFailure(this.itemName, this.available)
      : super(
          'Stock insuficiente de "$itemName" '
          '(disponible: ${available % 1 == 0 ? available.toInt() : available}).',
        );

  final String itemName;
  final double available;
}

/// Transición inválida en la máquina de estados de pedidos.
class InvalidTransitionFailure extends Failure {
  const InvalidTransitionFailure(super.message);
}

/// El registro solicitado no existe en la base local.
class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

/// Error de persistencia local (SQLite).
class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message);
}

/// Error de red o del servidor central durante la sincronización.
class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}
