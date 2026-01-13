import 'package:dio/dio.dart';
import 'package:tellevo/models/user_profile.dart';
import 'package:tellevo/services/dio.dart';

class PassengerApi {
  final Dio _http = dio();

  /// Trae el usuario autenticado (Sanctum). Ajusta el endpoint si usas otro.
  Future<UserProfile> fetchMe() async {
    final res = await _http.get('/user'); // Sanctum: retorna el usuario logueado
    return UserProfile.fromJson(res.data as Map<String, dynamic>);
  }
}