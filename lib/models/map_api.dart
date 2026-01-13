import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:dio/dio.dart';
import 'package:tellevo/services/dio.dart' as api;

/// DTO con datos esenciales de una ruta (Directions).
class DirectionsDto {
  final String polyline; // overview polyline codificada
  final LatLng start;
  final LatLng end;
  final String? distanceText;
  final int? distanceValue;   // metros
  final String? durationText;
  final int? durationValue;   // segundos

  DirectionsDto({
    required this.polyline,
    required this.start,
    required this.end,
    this.distanceText,
    this.distanceValue,
    this.durationText,
    this.durationValue,
  });
}

/// Cliente para consumir un proxy de Directions en tu backend Laravel
/// para evitar exponer la API key en el cliente.
class MapApi {
  final Dio _http = api.dio();

  /// Llama a tu backend, que a su vez llama a Google Directions.
  /// Envía los parámetros como 'origin' y 'destination' en formato "lat,lng".
  /// Acepta múltiples formatos de respuesta comunes.
  Future<DirectionsDto> getDirections(LatLng start, LatLng end) async {
    try {
      final res = await _http.get(
        '/maps/directions',
        queryParameters: {
          // ⚠️ Si tu backend usa otros nombres, cámbialos aquí.
          'origin': '${start.latitude},${start.longitude}',
          'destination': '${end.latitude},${end.longitude}',
        },
      );

      final data = res.data;

      // Variables de salida (se garantizarán valores por defecto).
      String? parsedPolyline;
      LatLng? parsedStart;
      LatLng? parsedEnd;
      String? distanceText;
      int? distanceValue;
      String? durationText;
      int? durationValue;

      if (data is Map<String, dynamic>) {
        // Formato 2 y alias:
        // { polyline:"...", start:{lat,lng}, end:{lat,lng}, distance_text, distance_value, duration_text, duration_value }
        if (data['polyline'] is String) {
          parsedPolyline = data['polyline'] as String;
        } else if (data['points'] is String) {
          // alias habitual
          parsedPolyline = data['points'] as String;
        }

        if (data['start'] is Map) {
          final m = (data['start'] as Map).cast<String, dynamic>();
          if (m['lat'] != null && m['lng'] != null) {
            parsedStart = LatLng(
              (m['lat'] as num).toDouble(),
              (m['lng'] as num).toDouble(),
            );
          }
        }
        if (data['end'] is Map) {
          final m = (data['end'] as Map).cast<String, dynamic>();
          if (m['lat'] != null && m['lng'] != null) {
            parsedEnd = LatLng(
              (m['lat'] as num).toDouble(),
              (m['lng'] as num).toDouble(),
            );
          }
        }

        // Formato 1 (similar al de Google):
        // { routes:[ { overview_polyline:{points:"..."}, legs:[{ distance:{text,value}, duration:{text,value}, start_location:{lat,lng}, end_location:{lat,lng} }] } ] }
        if (data['routes'] is List && (data['routes'] as List).isNotEmpty) {
          final route0 = (data['routes'] as List).first;
          if (route0 is Map<String, dynamic>) {
            final op = (route0['overview_polyline'] ?? route0['overviewPolyline']);
            if (op is Map) {
              final points = op['points'] ?? op['encoded'];
              if (points is String) parsedPolyline = points;
            }
            if (route0['legs'] is List && (route0['legs'] as List).isNotEmpty) {
              final leg0 = (route0['legs'] as List).first;
              if (leg0 is Map<String, dynamic>) {
                final dist = leg0['distance'];
                if (dist is Map) {
                  distanceText = dist['text']?.toString();
                  final v = dist['value'];
                  if (v is num) distanceValue = v.toInt();
                }
                final dur = leg0['duration'];
                if (dur is Map) {
                  durationText = dur['text']?.toString();
                  final v = dur['value'];
                  if (v is num) durationValue = v.toInt();
                }
                final sl = leg0['start_location'];
                if (sl is Map && sl['lat'] != null && sl['lng'] != null) {
                  parsedStart = LatLng(
                    (sl['lat'] as num).toDouble(),
                    (sl['lng'] as num).toDouble(),
                  );
                }
                final el = leg0['end_location'];
                if (el is Map && el['lat'] != null && el['lng'] != null) {
                  parsedEnd = LatLng(
                    (el['lat'] as num).toDouble(),
                    (el['lng'] as num).toDouble(),
                  );
                }
              }
            }
          }
        }
      }

      // Valores por defecto para evitar caminos sin retorno.
      final polyline = parsedPolyline ?? '';
      final s = parsedStart ?? start;
      final e = parsedEnd ?? end;

      return DirectionsDto(
        polyline: polyline,
        start: s,
        end: e,
        distanceText: distanceText,
        distanceValue: distanceValue,
        durationText: durationText,
        durationValue: durationValue,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      final msg = (data is Map && data['message'] != null)
          ? data['message'].toString()
          : e.message ?? 'Request failed';
      final errors = (data is Map && data['errors'] != null) ? data['errors'] : null;
      throw Exception('(${code ?? '?'}) $msg ${errors != null ? errors.toString() : ''}');
    } catch (e) {
      throw Exception('Unexpected error in getDirections: $e');
    }
  }

  /// Adaptador para pantallas que esperan un Map con:
  /// { polyline, bounds:{south,west,north,east}, distance_m, duration_s, start:{lat,lng}, end:{lat,lng} }
  /// Internamente usa getDirections(...). Siempre retorna o lanza.
  Future<Map<String, dynamic>> fetchDirections({
    required LatLng start,
    required LatLng end,
  }) async {
    try {
      final dto = await getDirections(start, end);

      // Bounds aproximados (si quieres bounds exactos de la ruta,
      // haz que el backend los envíe y reemplázalos aquí).
      final south = (dto.start.latitude <= dto.end.latitude)
          ? dto.start.latitude
          : dto.end.latitude;
      final north = (dto.start.latitude >= dto.end.latitude)
          ? dto.start.latitude
          : dto.end.latitude;
      final west = (dto.start.longitude <= dto.end.longitude)
          ? dto.start.longitude
          : dto.end.longitude;
      final east = (dto.start.longitude >= dto.end.longitude)
          ? dto.start.longitude
          : dto.end.longitude;

      return {
        'polyline': dto.polyline, // puede ser '' si el backend no la envía
        'bounds': {'south': south, 'west': west, 'north': north, 'east': east},
        'distance_m': dto.distanceValue,
        'duration_s': dto.durationValue,
        'start': {'lat': dto.start.latitude, 'lng': dto.start.longitude},
        'end': {'lat': dto.end.latitude, 'lng': dto.end.longitude},
      };
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      final msg = (data is Map && data['message'] != null)
          ? data['message'].toString()
          : e.message ?? 'Request failed';
      final errors = (data is Map && data['errors'] != null) ? data['errors'] : null;
      throw Exception('(${code ?? '?'}) $msg ${errors != null ? errors.toString() : ''}');
    } catch (e) {
      throw Exception('Unexpected error in fetchDirections: $e');
    }
  }
}
