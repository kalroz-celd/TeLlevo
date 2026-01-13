import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart' as Dio;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:tellevo/models/user.dart';
import 'package:tellevo/services/dio.dart';

class Auth extends ChangeNotifier {
  bool _isLoggedIn = false;
  late User _user;
  String _token = '';

  // Cache-busting para avatar
  int _avatarCacheKey = 0;

  // 🔒 Control de ciclo de vida para evitar “fatídico”
  bool _disposed = false;

  // Cancela requests cuando el Auth se descarta
  final Dio.CancelToken _cancelToken = Dio.CancelToken();

  bool get isLoggedIn => _isLoggedIn;
  bool get authenticated => _isLoggedIn;
  User get user => _user;
  String? get token => _token.isNotEmpty ? _token : null;

  /// Devuelve true si el usuario ya tiene avatar/foto
  bool get hasProfilePhoto => _isLoggedIn && _user.avatar.isNotEmpty;

  // ⚠️ Usa secure storage (mantén la misma key en todo el proyecto)
  static const _kTokenKey = 'token';
  final storage = const FlutterSecureStorage();

  Auth() {
    _user = User(id: 0, name: '', email: '', avatar: '', roles: []);
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel('Auth disposed');
    }
    super.dispose();
  }

  void safeNotify() {
    if (!_disposed) notifyListeners();
  }

  Dio.Options _authHeader(String token) =>
      Dio.Options(headers: {'Authorization': 'Bearer $token'});

  /// URL de avatar con o sin cache-busting (?v=)
  String? avatarUrl({bool bust = true}) {
    if (_user.avatar.isEmpty) return null;
    if (!bust) return _user.avatar;
    final sep = _user.avatar.contains('?') ? '&' : '?';
    return '${_user.avatar}${sep}v=$_avatarCacheKey';
  }

  /// Headers para imágenes protegidas (si tu file server requiere Bearer)
  Map<String, String>? imageAuthHeaders() {
    return token != null ? {'Authorization': 'Bearer $_token'} : null;
  }

  Future<bool> login({required Map creds}) async {
    try {
      final Dio.Response response = await dio().post(
        '/sanctum/token',
        data: creds,
        cancelToken: _cancelToken,
      );
      final String token = response.data.toString();
      if (_disposed) return false;
      return await tryToken(token: token);
    } catch (e) {
      debugPrint('Login error: $e');
      return false;
    }
  }

  /// Valida token contra /user y, si es válido, lo persiste y setea Authorization global (Dio).
  Future<bool> tryToken({required String token}) async {
    if (token.isEmpty || _disposed) return false;

    try {
      final Dio.Response response = await dio().get(
        '/user',
        options: _authHeader(token),
        cancelToken: _cancelToken,
      );

      if (_disposed) return false;

      _isLoggedIn = true;
      _user = User.fromJson(response.data);
      _token = token;

      await storeToken(token: token);
      if (_disposed) return false;

      setDioAuthToken(token); // ✅ inyecta el token globalmente
      _bumpAvatarCache();

      safeNotify();
      return true;
    } catch (e) {
      if (_disposed) return false;
      debugPrint('tryToken error: $e');
      await cleanUp();
      return false;
    }
  }

  Future<void> storeToken({required String token}) async {
    if (_disposed) return;
    await storage.write(key: _kTokenKey, value: token);
  }

  /// Restaura sesión desde SecureStorage y setea Authorization global
  Future<bool> restoreSession() async {
    try {
      final token = await storage.read(key: _kTokenKey);
      if (_disposed) return false;

      if (token == null || token.isEmpty) {
        await cleanUp();
        return false;
      }

      final Dio.Response resp = await dio().get(
        '/user',
        options: _authHeader(token),
        cancelToken: _cancelToken,
      );

      if (_disposed) return false;

      _isLoggedIn = true;
      _user = User.fromJson(resp.data);
      _token = token;

      setDioAuthToken(token); // ✅ importantísimo
      _bumpAvatarCache();

      safeNotify();
      return true;
    } catch (e) {
      if (_disposed) return false;
      debugPrint('restoreSession error: $e');
      await cleanUp();
      return false;
    }
  }

  /// Cierra sesión en backend y limpia local
  Future<void> logout() async {
    try {
      if (_token.isNotEmpty) {
        await dio().get(
          '/user/revoke',
          options: _authHeader(_token),
          cancelToken: _cancelToken,
        );
      } else {
        await dio().post('/logout', cancelToken: _cancelToken);
      }
    } catch (e) {
      debugPrint('logout revoke error: $e');
      try {
        await dio().post('/logout', cancelToken: _cancelToken);
      } catch (e2) {
        debugPrint('logout fallback (/logout) error: $e2');
      }
    } finally {
      await cleanUp();
      safeNotify();
    }
  }

  /// Limpia estado local, borra token y quita Authorization global
  Future<void> cleanUp() async {
    _user = User(id: 0, name: '', email: '', avatar: '', roles: []);
    _isLoggedIn = false;
    _token = '';
    _avatarCacheKey = 0;
    try {
      await storage.delete(key: _kTokenKey);
    } catch (_) {}
    setDioAuthToken(null); // ✅ quita header Authorization del cliente global
  }

  /// Sube la foto y **recarga /user** para que el avatar nuevo esté disponible.
  Future<bool> uploadProfileImage(File file) async {
    final token = await storage.read(key: _kTokenKey);
    if (_disposed || token == null || token.isEmpty) return false;

    final client = dio();
    client.options.headers['Authorization'] = 'Bearer $token';

    final fileName = basename(file.path);
    final formData = Dio.FormData.fromMap({
      'photo': await Dio.MultipartFile.fromFile(file.path, filename: fileName),
    });

    _debugFormData(formData);

    try {
      final Dio.Response resp = await client.post(
        '/user/photo',
        data: formData,
        cancelToken: _cancelToken,
      );
      final ok = (resp.statusCode ?? 0) >= 200 && (resp.statusCode ?? 0) < 300;

      if (!ok || _disposed) return false;

      await reloadMe();
      return true;
    } on Dio.DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      debugPrint('Upload falló. Status: $status, body: $data');
      return false;
    } catch (e) {
      debugPrint('Error genérico en upload: $e');
      return false;
    }
  }

  /// Recarga el usuario desde /user y notifica a listeners.
  Future<void> reloadMe() async {
    if (_token.isEmpty || _disposed) return;

    final Dio.Response response = await dio().get(
      '/user',
      options: _authHeader(_token),
      cancelToken: _cancelToken,
    );

    if (_disposed) return;

    _user = User.fromJson(response.data);
    _bumpAvatarCache();
    safeNotify();
  }

  void _bumpAvatarCache() {
    _avatarCacheKey = DateTime.now().millisecondsSinceEpoch;
  }

  void _debugFormData(Dio.FormData formData) {
    debugPrint('--- FormData fields ---');
    for (final field in formData.fields) {
      debugPrint('  ${field.key}: ${field.value}');
    }
    debugPrint('--- FormData files ---');
    for (final fileEntry in formData.files) {
      final key = fileEntry.key;
      final multipart = fileEntry.value;
      debugPrint(
        '  $key → filename=${multipart.filename}, contentType=${multipart.contentType}',
      );
    }
    debugPrint('-----------------------');
  }
}
