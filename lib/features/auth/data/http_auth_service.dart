import 'package:dio/dio.dart';
import '../domain/auth_service.dart';

class HttpAuthService implements AuthService {
  HttpAuthService({required this.baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: {'content-type': 'application/json'},
            ));

  final String baseUrl;
  final Dio _dio;

  Never _throwFromDio(DioException e) {
    final code = (e.response?.data is Map &&
            (e.response!.data as Map)['error'] is String)
        ? (e.response!.data as Map)['error'] as String
        : 'network_error';
    throw AuthException(code, e.message);
  }

  @override
  Future<void> sendCode(String phone) async {
    try {
      await _dio.post('$baseUrl/auth/send-code', data: {'phone': phone});
    } on DioException catch (e) {
      _throwFromDio(e);
    }
  }

  @override
  Future<AuthSession> verifyCode({
    required String phone,
    required String code,
  }) async {
    try {
      final resp = await _dio.post(
        '$baseUrl/auth/verify-code',
        data: {'phone': phone, 'code': code},
      );
      final data = resp.data as Map<String, dynamic>;
      return AuthSession(
        token: data['token'] as String,
        user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      _throwFromDio(e);
    }
  }

  @override
  Future<AuthUser?> me(String token) async {
    try {
      final resp = await _dio.get(
        '$baseUrl/auth/me',
        options: Options(headers: {'authorization': 'Bearer $token'}),
      );
      final data = resp.data as Map<String, dynamic>;
      return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return null;
      _throwFromDio(e);
    }
  }

  @override
  Future<void> logout(String token) async {
    try {
      await _dio.post(
        '$baseUrl/auth/logout',
        options: Options(headers: {'authorization': 'Bearer $token'}),
      );
    } catch (_) {
      // Best-effort.
    }
  }
}

/// In-memory mock — for running the app without the backend.
/// Last sent code is exposed via [lastCode] so tests/devs can verify.
class MockAuthService implements AuthService {
  String? _phone;
  String? _code;
  String? lastCode;

  @override
  Future<void> sendCode(String phone) async {
    await Future.delayed(const Duration(milliseconds: 600));
    _phone = phone;
    _code = '1234';
    lastCode = _code;
    // ignore: avoid_print
    print('[MockAuth] code for $phone → $_code');
  }

  @override
  Future<AuthSession> verifyCode({
    required String phone,
    required String code,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (phone != _phone || code != _code) {
      throw const AuthException('wrong_code');
    }
    return AuthSession(
      token: 'mock-token-${DateTime.now().millisecondsSinceEpoch}',
      user: AuthUser(id: 'mock-user', phone: phone),
    );
  }

  @override
  Future<AuthUser?> me(String token) async {
    if (token.startsWith('mock-token-') && _phone != null) {
      return AuthUser(id: 'mock-user', phone: _phone!);
    }
    return null;
  }

  @override
  Future<void> logout(String token) async {}
}
