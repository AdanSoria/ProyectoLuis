import 'package:uuid/uuid.dart';

/// Generador de identificadores universales.
///
/// Todos los registros (ventas, pedidos, clientes, catálogo, cola de
/// sincronización) usan **UUID v4 generados en el cliente** para evitar
/// colisiones al sincronizar dispositivos que trabajaron sin conexión.
abstract class IdGenerator {
  String newId();
}

class UuidV4Generator implements IdGenerator {
  const UuidV4Generator();

  static const Uuid _uuid = Uuid();

  @override
  String newId() => _uuid.v4();
}
