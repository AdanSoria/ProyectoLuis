import 'package:connectivity_plus/connectivity_plus.dart';

/// Abstracción de conectividad para poder simularla en pruebas y
/// mantener a la capa de datos desacoplada del plugin concreto.
abstract class ConnectivityService {
  Future<bool> hasConnection();

  /// Emite `true`/`false` cada vez que cambia el estado de la red.
  Stream<bool> get onStatusChange;
}

class ConnectivityPlusService implements ConnectivityService {
  ConnectivityPlusService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> hasConnection() async =>
      _isOnline(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get onStatusChange =>
      _connectivity.onConnectivityChanged.map(_isOnline);
}
