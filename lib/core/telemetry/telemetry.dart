import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Thin wrapper around Sentry so feature code can fire-and-forget without
/// pulling sentry_flutter in directly. Safe to call when SENTRY_DSN is empty
/// — Sentry just isn't initialised and these calls become no-ops.
class Telemetry {
  Telemetry._();

  /// Lightweight named event ("onboarding_complete", "scan_uploaded",
  /// "lina_message_sent"). Goes into Sentry as an INFO message — visible in
  /// the Issues tab grouped by message, so volume is observable per event
  /// without standing up a separate analytics pipeline.
  static void event(String name, {Map<String, dynamic>? data}) {
    Sentry.captureMessage(
      name,
      level: SentryLevel.info,
      withScope: data == null
          ? null
          : (scope) {
              for (final entry in data.entries) {
                scope.setExtra(entry.key, entry.value);
              }
            },
    ).ignore();
  }

  /// Drop-a-pin breadcrumb on the timeline (e.g. screen transitions, button
  /// taps). Surfaces in error reports as the trail of recent activity, not
  /// as standalone events.
  static void breadcrumb(String message, {String? category}) {
    Sentry.addBreadcrumb(Breadcrumb(
      message: message,
      category: category,
      timestamp: DateTime.now(),
    )).ignore();
  }

  /// Tag the current Sentry scope with the authenticated user's id so any
  /// later error gets correlated with them. Pass null on logout.
  static Future<void> setUser(String? userId) async {
    await Sentry.configureScope((scope) {
      if (userId == null) {
        scope.setUser(null);
      } else {
        scope.setUser(SentryUser(id: userId));
      }
    });
  }

  /// Manual capture for caught exceptions that the app handled gracefully
  /// but is worth knowing about (e.g., AI parse failed).
  static void captureException(Object error, [StackTrace? stack]) {
    if (kDebugMode) {
      // Keep debug builds quiet on the Sentry side — local console already
      // shows the same error.
      debugPrint('Telemetry.captureException: $error');
      return;
    }
    Sentry.captureException(error, stackTrace: stack).ignore();
  }
}
