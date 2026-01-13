import 'package:dio/dio.dart' show Dio, DioException, Options;
import 'package:tellevo/services/dio.dart' as api;
import 'package:dio/dio.dart' show Dio, DioException, DioExceptionType, Options;

/// Envía por correo el listado de pasajeros de un "service run".
/// - runId: ID del service_run
/// - to: lista de destinatarios (si la dejas vacía, el backend puede usar sus defaults)
/// - cc: copia
/// - attachCsv: si el backend debe adjuntar CSV
/// - passengers: (opcional) payload de pasajeros si decides enviarlos desde el cliente
class PassengerEmailApi {
  final Dio _dio;

  PassengerEmailApi({Dio? client, String? bearerToken})
      : _dio = client ?? api.dio() {
    if (bearerToken != null && bearerToken.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $bearerToken';
    }
  }

  Future<void> sendRunEmail({
    required int runId,
    required List<String> to,
    List<String> cc = const [],
    bool attachCsv = true,
    List<Map<String, dynamic>>? passengers,
  }) async {
    final payload = <String, dynamic>{
      'to': to,
      if (cc.isNotEmpty) 'cc': cc,
      'attach_csv': attachCsv,
      if (passengers != null) 'passengers': passengers,
    };

    final res = await _dio.post(
      // Ajusta si tu endpoint difiere
      '/service-runs/$runId/email',
      data: payload,
      options: Options(validateStatus: (s) => s != null && s < 500),
    );

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        type: DioExceptionType.badResponse,
        error: res.data,
      );
    }
  }

  /// Utilidad para normalizar tu lista de pasajeros al formato esperado por el backend.
  /// Ajusta los nombres de campos según tu estructura real.
  static List<Map<String, dynamic>> normalizePassengers(
    List<Map<String, dynamic>> raw,
  ) {
    return raw.map((p) {
      final map = <String, dynamic>{
        'user_id': p['user_id'] ?? p['id'],
        'name': p['name'] ??
            '${(p['first_name'] ?? '').toString().trim()} ${(p['last_name'] ?? p['lastname'] ?? '').toString().trim()}'
                .trim(),
        'rut': p['rut'] ??
            (p['ci'] != null && p['digit'] != null ? '${p['ci']}-${p['digit']}' : null),
        'seat_number': p['seat_number'],
        'checked_in_at': p['checked_in_at'],
      };
      map.removeWhere((k, v) => v == null);
      return map;
    }).toList();
  }
}
