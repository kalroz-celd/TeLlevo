import 'package:dio/dio.dart';
import 'package:tellevo/services/dio.dart' as api;

/// API para envío de correo/reporte de un run.
/// Asegura que acepte `CancelToken` para poder cancelar requests si la vista se cierra.
class PassengerEmailApi {
  PassengerEmailApi({required this.bearerToken});

  final String bearerToken;

  Dio _dio() {
    final d = api.dio();
    if (bearerToken.isNotEmpty) {
      d.options.headers['Authorization'] = 'Bearer $bearerToken';
    }
    return d;
  }

  /// Envía el reporte del run. Ajusta la URL si tu backend es distinto.
  Future<void> sendRunEmail({
    required int runId,
    required List<String> to,
    List<String> cc = const [],
    bool attachCsv = true,
    required List<Map<String, dynamic>> passengers,
    CancelToken? cancelToken, // ← AQUÍ ESTÁ EL PARÁMETRO
  }) async {
    await _dio().post(
      // Ajusta si tu ruta real difiere:
      '/service-runs/$runId/dispatch-report',
      data: {
        'to': to,
        'cc': cc,
        'attach_csv': attachCsv,
        'passengers': passengers, // si no lo usas en backend, puedes quitarlo
      },
      cancelToken: cancelToken, // ← Y AQUÍ SE USA
    );
  }
}
