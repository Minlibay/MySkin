import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_storage.dart';
import '../domain/auth_service.dart';

enum AuthStatus { unknown, unauthenticated, awaitingCode, authenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.token,
    this.pendingPhone,
    this.errorCode,
    this.busy = false,
  });

  final AuthStatus status;
  final AuthUser? user;
  final String? token;
  final String? pendingPhone;
  final String? errorCode;
  final bool busy;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? token,
    String? pendingPhone,
    String? errorCode,
    bool? busy,
    bool clearError = false,
    bool clearPending = false,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        token: token ?? this.token,
        pendingPhone:
            clearPending ? null : (pendingPhone ?? this.pendingPhone),
        errorCode: clearError ? null : (errorCode ?? this.errorCode),
        busy: busy ?? this.busy,
      );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._service, this._storage) : super(const AuthState()) {
    _restore();
  }

  final AuthService _service;
  final AuthStorage _storage;

  Future<void> _restore() async {
    final token = await _storage.readToken();
    if (token == null) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final user = await _service.me(token);
      if (user == null) {
        await _storage.clear();
        state = state.copyWith(status: AuthStatus.unauthenticated);
        return;
      }
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        token: token,
      );
    } catch (_) {
      // Network error on cold start — keep token, allow offline access
      // by treating as authenticated if we have a saved phone.
      final phone = await _storage.readPhone();
      if (phone != null) {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          token: token,
          user: AuthUser(id: 'cached', phone: phone),
        );
      } else {
        state = state.copyWith(status: AuthStatus.unauthenticated);
      }
    }
  }

  Future<void> requestCode(String phone) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _service.sendCode(phone);
      state = state.copyWith(
        busy: false,
        status: AuthStatus.awaitingCode,
        pendingPhone: phone,
      );
    } on AuthException catch (e) {
      state = state.copyWith(busy: false, errorCode: e.code);
    } catch (e) {
      state = state.copyWith(busy: false, errorCode: 'network_error');
    }
  }

  Future<void> verify(String code) async {
    final phone = state.pendingPhone;
    if (phone == null) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final session = await _service.verifyCode(phone: phone, code: code);
      await _storage.save(token: session.token, phone: session.user.phone);
      state = state.copyWith(
        busy: false,
        status: AuthStatus.authenticated,
        user: session.user,
        token: session.token,
        clearPending: true,
      );
    } on AuthException catch (e) {
      state = state.copyWith(busy: false, errorCode: e.code);
    } catch (e) {
      state = state.copyWith(busy: false, errorCode: 'network_error');
    }
  }

  Future<void> resend() async {
    final phone = state.pendingPhone;
    if (phone != null) await requestCode(phone);
  }

  void backToPhone() {
    state = state.copyWith(
      status: AuthStatus.unauthenticated,
      clearPending: true,
      clearError: true,
    );
  }

  Future<void> logout() async {
    final token = state.token;
    if (token != null) await _service.logout(token);
    await _storage.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  throw UnimplementedError('Override authServiceProvider in main.dart');
});

final authStorageProvider = Provider<AuthStorage>((ref) => AuthStorage());

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    ref.watch(authServiceProvider),
    ref.watch(authStorageProvider),
  );
});
