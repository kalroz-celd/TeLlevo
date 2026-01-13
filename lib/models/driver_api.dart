import 'package:dio/dio.dart' as d;
import 'package:tellevo/services/dio.dart';
import 'driver_installation.dart';

class DriverApi {
  final d.Dio _http = dio();

  Future<List<DriverInstallation>> fetchInstallations() async {
    final res = await _http.get(
      '/driver/installations',
    ); // baseUrl ya está en services/dio.dart
    final data = res.data as List<dynamic>;
    return data
        .map((e) => DriverInstallation.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
