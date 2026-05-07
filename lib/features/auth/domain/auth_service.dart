class AuthUser {
  const AuthUser({required this.id, required this.phone});
  final String id;
  final String phone;

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] as String,
        phone: j['phone'] as String,
      );
}

class AuthSession {
  const AuthSession({required this.token, required this.user});
  final String token;
  final AuthUser user;
}

class AuthException implements Exception {
  const AuthException(this.code, [this.message]);
  final String code;
  final String? message;

  @override
  String toString() => 'AuthException($code${message != null ? ': $message' : ''})';
}

abstract class AuthService {
  /// Send a verification code to [phone]. Returns when SMS dispatch
  /// succeeded (not when delivered).
  Future<void> sendCode(String phone);

  /// Verify the SMS [code] for [phone]. Returns the session on success.
  Future<AuthSession> verifyCode({required String phone, required String code});

  /// Validate a stored token (e.g. on cold start).
  Future<AuthUser?> me(String token);

  /// Best-effort server logout.
  Future<void> logout(String token);
}
