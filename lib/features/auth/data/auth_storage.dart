import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the auth token across app restarts.
/// On web, flutter_secure_storage stores into IndexedDB with WebCrypto AES.
class AuthStorage {
  AuthStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _kToken = 'auth_token';
  static const _kPhone = 'auth_phone';

  Future<String?> readToken() => _storage.read(key: _kToken);
  Future<String?> readPhone() => _storage.read(key: _kPhone);

  Future<void> save({required String token, required String phone}) async {
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kPhone, value: phone);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kPhone);
  }
}
