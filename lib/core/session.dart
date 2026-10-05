import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Jetons de session, conservés dans le trousseau sécurisé du téléphone.
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _refreshKey = 'refresh_token';
  static const _accessKey = 'access_token';

  String? _access;

  String? get accessToken => _access;

  Future<String?> refreshToken() => _storage.read(key: _refreshKey);

  Future<void> load() async => _access = await _storage.read(key: _accessKey);

  Future<void> save({required String access, required String refresh}) async {
    _access = access;
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<void> clear() async {
    _access = null;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
