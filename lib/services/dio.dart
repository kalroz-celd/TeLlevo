import 'package:dio/dio.dart';

Dio? _client;

/// Devuelve un único cliente Dio con baseUrl y logs.
/// El token se inyecta con [setDioAuthToken].
Dio dio() {
  if (_client != null) return _client!;

  final d = Dio();
  d.options.baseUrl = "https://tellevo.celd.cl/api";
  d.options.headers['accept'] = 'application/json';

  d.interceptors.add(LogInterceptor(
    requestHeader: true,
    requestBody: true,
    responseHeader: true,
    responseBody: true,
  ));

  _client = d;
  return _client!;
}

/// Inyecta o limpia el header Authorization del cliente global.
void setDioAuthToken(String? token) {
  final d = dio();
  if (token == null || token.isEmpty) {
    d.options.headers.remove('Authorization');
  } else {
    d.options.headers['Authorization'] = 'Bearer $token';
  }
}
