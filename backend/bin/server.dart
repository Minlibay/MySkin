import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:myskin_backend/db.dart';
import 'package:myskin_backend/gigachat.dart';
import 'package:myskin_backend/handlers.dart';
import 'package:myskin_backend/repos.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

void main(List<String> args) async {
  final env = DotEnv(includePlatformEnvironment: true)..load();
  final dbUrl = env['DATABASE_URL'];
  if (dbUrl == null || dbUrl.isEmpty) {
    stderr.writeln('DATABASE_URL is required');
    exit(1);
  }

  final pool = await openPool(dbUrl);
  await Migrator(pool).run();

  final users = UserRepository(pool);
  final sessions = SessionRepository(pool);
  final otps = OtpRepository(pool);
  final admins = AdminRepository(pool);
  final stats = StatsRepository(pool);
  final profiles = ProfileRepository(pool);
  final routines = RoutineRepository(pool);
  final dermSessions = DermSessionRepository(pool);
  final products = ProductRepository(pool);
  final shelf = UserProductRepository(pool);
  final customShelf = UserCustomProductRepository(pool);
  final favorites = UserFavoriteRepository(pool);
  final completions = RoutineCompletionRepository(pool);
  final scans = ScanRepository(pool);
  final appSettings = AppSettingsRepository(pool);
  final notifications = NotificationRepository(pool);
  final chatMessages = ChatMessageRepository(pool);
  final partners = PartnerRepository(pool);
  final brands = BrandRepository(pool);
  final productEvents = ProductEventRepository(pool);

  final auth = AuthHandlers(
    users: users,
    sessions: sessions,
    otps: otps,
    env: env,
  );
  final admin = AdminHandlers(
    admins: admins,
    users: users,
    stats: stats,
    profiles: profiles,
    scans: scans,
    shelf: shelf,
    products: products,
    otps: otps,
    appSettings: appSettings,
    partners: partners,
    brands: brands,
  );
  final partner = PartnerHandlers(
    partners: partners,
    brands: brands,
    products: products,
    events: productEvents,
  );
  final me = MeHandlers(
    sessions: sessions,
    profiles: profiles,
    routines: routines,
    dermSessions: dermSessions,
    completions: completions,
    users: users,
    scans: scans,
    chatMessages: chatMessages,
    events: productEvents,
  );
  final catalog = CatalogHandlers(
    sessions: sessions,
    products: products,
    shelf: shelf,
    customShelf: customShelf,
    profiles: profiles,
    favorites: favorites,
    scans: scans,
  );
  final gigaKey = env['GIGACHAT_AUTH_KEY'];
  final giga = (gigaKey != null && gigaKey.isNotEmpty)
      ? GigaChatClient.fromEnv(env)
      : null;

  final scanHandlers = ScanHandlers(
    sessions: sessions,
    scans: scans,
    profiles: profiles,
    giga: giga,
    appSettings: appSettings,
    notifications: notifications,
  );

  final notificationHandlers = NotificationHandlers(
    sessions: sessions,
    notifications: notifications,
  );

  final legalHandlers = LegalHandlers(appSettings: appSettings);

  final ai = giga != null
      ? AiHandlers(
          sessions: sessions,
          giga: giga,
          products: products,
          profiles: profiles,
          scans: scans,
          appSettings: appSettings,
          chatMessages: chatMessages,
        )
      : null;

  final root = Router()
    ..get('/health', (Request _) => jsonResponse(200, {'ok': true}))
    ..mount('/', auth.router().call)
    ..mount('/', admin.router().call)
    ..mount('/', me.router().call)
    ..mount('/', catalog.router().call)
    ..mount('/', scanHandlers.router().call)
    ..mount('/', notificationHandlers.router().call)
    ..mount('/', legalHandlers.router().call)
    ..mount('/', partner.router().call);
  if (ai != null) root.mount('/', ai.router().call);

  final allowedOrigins = (env['CORS_ALLOWED_ORIGINS'] ?? '*')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final rateLimiter = RateLimiter();

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsMiddleware(allowedOrigins: allowedOrigins))
      .addMiddleware(rateLimitMiddleware(
        limiter: rateLimiter,
        protectedPaths: const {'/auth/send-code'},
      ))
      .addHandler(root.call);

  final port = int.parse(env['PORT'] ?? '8080');
  final server = await serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('MySkin backend listening on http://localhost:${server.port}');
  if ((env['SMSC_LOGIN'] ?? '').isEmpty) {
    stdout.writeln(
        '⚠  SMSC_LOGIN/SMSC_PASSWORD empty — codes printed to stdout.');
  }
  if (allowedOrigins.contains('*') || allowedOrigins.isEmpty) {
    stdout.writeln(
        '⚠  CORS open to all origins (dev mode). Set CORS_ALLOWED_ORIGINS for prod.');
  } else {
    stdout.writeln('✓  CORS whitelist: ${allowedOrigins.join(', ')}');
  }
  if (ai == null) {
    stdout.writeln('⚠  GIGACHAT_AUTH_KEY empty — AI endpoints disabled.');
  } else {
    stdout.writeln('✓  GigaChat enabled.');
  }
}
