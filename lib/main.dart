import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'app.dart';
import 'features/ai/data/gigachat_service.dart';
import 'features/ai/data/http_ai_service.dart';
import 'features/derm2/presentation/derm_state_machine_controller.dart' show aiServiceProvider;
import 'features/api/backend_api.dart';
import 'features/auth/data/http_auth_service.dart';
import 'features/auth/domain/auth_service.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/derm2/presentation/derm_state_machine_controller.dart';
import 'features/notifications/data/local_notifications.dart';

const bool kUseMockAI =
    bool.fromEnvironment('USE_MOCK_AI', defaultValue: false);
const bool kUseMockAuth =
    bool.fromEnvironment('USE_MOCK_AUTH', defaultValue: false);

const String kBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  // Production default — мойскин.рф (Punycode form for HTTP).
  // Override locally with --dart-define=BACKEND_URL=http://localhost:8080
  defaultValue: 'https://api.xn--80allhkb1j.xn--p1ai',
);

/// Set via --dart-define=SENTRY_DSN=https://…@sentry.io/… on release builds.
/// Empty default means Sentry isn't initialised in dev, so the IDE console
/// stays clean and Telemetry.* calls become no-ops automatically.
const String kSentryDsn = String.fromEnvironment('SENTRY_DSN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fire-and-forget — plugin init does not block UI render.
  // Schedule lives across app launches in OS, so we only init the bridge here.
  LocalNotificationsService.instance.init();

  final AuthService authService = kUseMockAuth
      ? MockAuthService()
      : HttpAuthService(baseUrl: kBackendUrl);

  Widget buildApp() => ProviderScope(
        overrides: [
          aiServiceProvider.overrideWith((ref) {
            if (kUseMockAI) return MockAIService();
            return HttpAIService(
              baseUrl: kBackendUrl,
              tokenProvider: () => ref.read(authControllerProvider).token,
            );
          }),
          authServiceProvider.overrideWithValue(authService),
          backendApiProvider.overrideWith((ref) {
            return BackendApi(
              baseUrl: kBackendUrl,
              tokenProvider: () =>
                  ref.read(authControllerProvider).token,
            );
          }),
        ],
        child: const MySkinApp(),
      );

  if (kSentryDsn.isEmpty) {
    // Dev / non-prod: skip Sentry init entirely so the SDK doesn't even attach
    // its zone, error handler, or network listener.
    runApp(buildApp());
    return;
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = kSentryDsn;
      // Performance / replay sampling — start conservative; bump per env.
      options.tracesSampleRate = 0.2;
      options.attachScreenshot = false;
      options.sendDefaultPii = false;
      options.environment = const String.fromEnvironment(
        'SENTRY_ENV',
        defaultValue: 'production',
      );
    },
    appRunner: () => runApp(buildApp()),
  );
}
