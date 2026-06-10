import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../../domain/entities/sync_queue.dart';
import '../../domain/repositories/sync_gateway.dart';

/// Implementación HTTP del puerto de sincronización.
///
/// Contrato REST agnóstico (ver README para implementarlo en Laravel/Node):
///
/// ```
/// POST {baseUrl}/api/v1/sync/batch
/// {
///   "device_id": "uuid",
///   "enviado_en": "2026-06-10T12:00:00Z",
///   "operaciones": [
///     { "id": "uuid", "entidad": "transaccion", "entidad_id": "uuid",
///       "operacion": "create", "creado_en": "...", "payload": { ... } }
///   ]
/// }
///
/// 200 OK
/// { "resultados": [ { "id": "uuid", "ok": true, "mensaje": null } ] }
/// ```
class HttpSyncGateway implements SyncGateway {
  HttpSyncGateway({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 20);

  @override
  Future<Result<List<SyncOpResult>>> sendBatch({
    required String deviceId,
    required List<SyncQueueEntry> entries,
  }) async {
    if (baseUrl.isEmpty) {
      return const Err(NetworkFailure(
          'Servidor central no configurado (AGROPOS_API_URL).'));
    }

    final uri = Uri.parse('$baseUrl/api/v1/sync/batch');
    final body = jsonEncode({
      'device_id': deviceId,
      'enviado_en': DateTime.now().toUtc().toIso8601String(),
      'operaciones': [
        for (final e in entries)
          {
            'id': e.id,
            'entidad': e.entityType,
            'entidad_id': e.entityId,
            'operacion': e.operation.code,
            'creado_en': e.createdAt.toIso8601String(),
            'payload': e.payload,
          },
      ],
    });

    try {
      final response = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return Err(NetworkFailure(
            'El servidor respondió HTTP ${response.statusCode}.'));
      }

      return Ok(_parseResults(response.body));
    } on TimeoutException {
      return const Err(
          NetworkFailure('El servidor tardó demasiado en responder.'));
    } on Exception catch (e) {
      return Err(NetworkFailure('Sin conexión con el servidor: $e'));
    }
  }

  /// Tolerante a backends simples: si no hay detalle por operación se
  /// asume que el lote completo fue aceptado (el caso de uso decide).
  List<SyncOpResult> _parseResults(String body) {
    try {
      final decoded = jsonDecode(body);
      final results = (decoded as Map<String, dynamic>)['resultados'];
      if (results is! List) return const [];
      return [
        for (final r in results.whereType<Map<String, dynamic>>())
          SyncOpResult(
            entryId: r['id'] as String? ?? '',
            ok: r['ok'] as bool? ?? true,
            message: r['mensaje'] as String?,
          ),
      ];
    } on FormatException {
      return const [];
    }
  }
}
