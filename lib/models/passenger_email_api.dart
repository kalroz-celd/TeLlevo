import 'package:dio/dio.dart'
    show Dio, DioException, DioExceptionType, Options;
import 'package:tellevo/services/dio.dart' as api;

/// Envia por correo el listado de pasajeros de un service run.
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
    String? serviceDate,
    List<Map<String, dynamic>>? passengers,
  }) async {
    final payload = <String, dynamic>{
      'to': to,
      if (cc.isNotEmpty) 'cc': cc,
      'attach_csv': attachCsv,
      if (serviceDate != null && serviceDate.isNotEmpty) ...{
        'service_date': serviceDate,
        'run_date': serviceDate,
        'travel_date': serviceDate,
        'trip_date': serviceDate,
        'fecha_viaje': serviceDate,
        'date': serviceDate,
        'report_date': serviceDate,
        'run': {'service_date': serviceDate},
        'service_run': {'service_date': serviceDate},
      },
      if (passengers != null) 'passengers': passengers,
    };

    final res = await _dio.post(
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

  static List<Map<String, dynamic>> normalizePassengers(
    List<Map<String, dynamic>> raw,
  ) {
    return raw.map((p) {
      final name =
          p['name'] ??
          '${(p['first_name'] ?? '').toString().trim()} ${(p['last_name'] ?? p['lastname'] ?? '').toString().trim()}'
              .trim();
      final rut =
          p['rut'] ??
          (p['ci'] != null && p['digit'] != null
              ? '${p['ci']}-${p['digit']}'
              : null);

      final map = <String, dynamic>{
        'user_id': p['user_id'] ?? p['id'],
        'name': name,
        'rut': rut,
        'seat_number': p['seat_number'],
        'checked_in_at': p['checked_in_at'],
      };
      map.removeWhere((k, v) => v == null);
      return map;
    }).toList();
  }
}
