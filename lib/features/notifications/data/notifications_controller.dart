import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api/backend_api.dart';
import '../domain/app_notification.dart';

class NotificationsState {
  const NotificationsState({
    this.items = const [],
    this.unreadCount = 0,
    this.loading = false,
    this.error,
    this.loadedOnce = false,
  });

  final List<AppNotification> items;
  final int unreadCount;
  final bool loading;
  final String? error;

  /// True after the first load attempt finishes (success or failure).
  /// Lets the UI distinguish "never tried" from "loaded but empty".
  final bool loadedOnce;

  NotificationsState copyWith({
    List<AppNotification>? items,
    int? unreadCount,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? loadedOnce,
  }) =>
      NotificationsState(
        items: items ?? this.items,
        unreadCount: unreadCount ?? this.unreadCount,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        loadedOnce: loadedOnce ?? this.loadedOnce,
      );
}

class NotificationsController extends StateNotifier<NotificationsState> {
  NotificationsController(this._api) : super(const NotificationsState());

  final BackendApi _api;

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final r = await _api.listNotifications();
      state = state.copyWith(
        items: r.items,
        unreadCount: r.unreadCount,
        loading: false,
        loadedOnce: true,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        loadedOnce: true,
        error: 'Не удалось загрузить уведомления',
      );
    }
  }

  /// Cheap call — used by the bell badge on home, without fetching bodies.
  Future<void> refreshUnreadCount() async {
    try {
      final n = await _api.notificationsUnreadCount();
      if (mounted) state = state.copyWith(unreadCount: n);
    } catch (_) {
      // swallow — badge degrades gracefully
    }
  }

  Future<void> markRead(String id) async {
    final idx = state.items.indexWhere((n) => n.id == id);
    if (idx == -1 || !state.items[idx].isUnread) return;
    // Optimistic.
    final next = [...state.items];
    next[idx] = next[idx].copyWith(readAt: DateTime.now());
    state = state.copyWith(
      items: next,
      unreadCount: (state.unreadCount - 1).clamp(0, 1 << 30),
    );
    try {
      await _api.markNotificationRead(id);
    } catch (_) {
      // Re-sync from server on failure.
      await refresh();
    }
  }

  Future<void> markAllRead() async {
    if (state.unreadCount == 0) return;
    final now = DateTime.now();
    final next = state.items
        .map((n) => n.isUnread ? n.copyWith(readAt: now) : n)
        .toList();
    state = state.copyWith(items: next, unreadCount: 0);
    try {
      await _api.markAllNotificationsRead();
    } catch (_) {
      await refresh();
    }
  }
}

final notificationsControllerProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>((ref) {
  return NotificationsController(ref.watch(backendApiProvider));
});
