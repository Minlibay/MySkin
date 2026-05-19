import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/telemetry/telemetry.dart';
import 'core/theme/app_theme.dart';
import 'features/ai/domain/models.dart';
import 'features/derm2/presentation/derm_state_machine_controller.dart' show aiServiceProvider;
import 'features/api/backend_api.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/auth/presentation/code_input_screen.dart';
import 'features/auth/presentation/phone_input_screen.dart';
import 'features/auth/presentation/splash_screen.dart';
import 'features/catalog/domain/product.dart';
import 'features/chat/presentation/chat_screen.dart';
import 'features/catalog/presentation/catalog_screen.dart';
import 'features/catalog/presentation/favorites_screen.dart';
import 'features/catalog/presentation/product_detail_screen.dart';
import 'features/catalog/presentation/add_custom_product_screen.dart';
import 'features/catalog/presentation/custom_product_detail_screen.dart';
import 'features/catalog/presentation/shelf_screen.dart';
import 'features/derm2/presentation/derm2_screen.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/notifications/data/local_notifications.dart';
import 'features/notifications/presentation/notifications_screen.dart';
import 'features/tutorial/presentation/welcome_tutorial_screen.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/profile/domain/user_settings.dart';
import 'features/profile/presentation/profile_screen.dart';
import 'features/progress/presentation/progress_screen.dart';
import 'features/ritual/domain/today.dart';
import 'features/ritual/presentation/daily_ritual_screen.dart';
import 'features/scan/domain/scan_result.dart';
import 'features/scan/presentation/scan_result_screen.dart';
import 'features/scan/presentation/scan_screen.dart';
import 'features/routine/presentation/loading_screen.dart';
import 'features/routine/presentation/quick_check_in_screen.dart';
import 'features/routine/presentation/routine_history_screen.dart';
import 'features/routine/presentation/routine_screen.dart';

class MySkinApp extends StatelessWidget {
  const MySkinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Моя Кожа',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const _AuthGate(),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 56, color: Color(0xFF8E8E93)),
              const SizedBox(height: 16),
              const Text(
                'Не удалось загрузить профиль',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF2E2E2E),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Проверь интернет и попробуй ещё раз.',
                style: TextStyle(color: Color(0xFF8E8E93)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 200,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Попробовать снова'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6E2A37),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    Widget child;
    switch (auth.status) {
      case AuthStatus.unknown:
        child = const SplashScreen();
      case AuthStatus.unauthenticated:
        child = const PhoneInputScreen();
      case AuthStatus.awaitingCode:
        child = CodeInputScreen(phone: auth.pendingPhone ?? '');
      case AuthStatus.authenticated:
        child = const _AppShell();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
      child: KeyedSubtree(key: ValueKey(auth.status), child: child),
    );
  }
}

enum _Shell {
  bootstrapping,
  bootstrapError,
  onboarding,
  tutorial,
  home,
  standardLoading,
  standardResult,
  derm2,
  catalog,
  productDetail,
  shelf,
  ritual,
  profile,
  scan,
  scanResult,
  progress,
  chat,
  notifications,
  quickCheckIn,
  favorites,
  addCustomProduct,
  customProductDetail,
}

class _AppShell extends ConsumerStatefulWidget {
  const _AppShell();

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> {
  _Shell _view = _Shell.bootstrapping;
  _Shell _previousView = _Shell.home;
  SkinProfile _profile = const SkinProfile();
  RoutineResult? _lastResult;
  String? _openProductSlug;
  Product? _openCustomProduct;
  Today? _today;
  ScanResult? _lastScan;
  String? _catalogInitialConcern;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    setState(() => _view = _Shell.bootstrapping);
    final api = ref.read(backendApiProvider);
    try {
      final results = await Future.wait([
        api.getProfile(),
        api.listRoutines(),
        api.getToday(),
        api.getSettings(),
      ]);
      final profile = results[0] as SkinProfile?;
      final routines = results[1] as List<RoutineRecord>;
      final today = results[2] as Today;
      final settings = results[3] as UserSettings;
      if (!mounted) return;
      setState(() {
        if (profile != null) _profile = profile;
        if (routines.isNotEmpty) _lastResult = routines.first.result;
        _today = today;
        if (profile == null) {
          _view = _Shell.onboarding;
        } else if (!settings.tutorialSeen) {
          // Existing user from a build that pre-dates the tutorial — show it
          // once on next launch.
          _view = _Shell.tutorial;
        } else {
          _view = _Shell.home;
        }
      });
      // Schedule local ritual reminders based on the user's stored settings.
      // No-op (silently) if OS-level notification permission was never granted.
      // ignore: unawaited_futures
      LocalNotificationsService.instance.reschedule(settings.notifications);
    } catch (_) {
      if (!mounted) return;
      setState(() => _view = _Shell.bootstrapError);
    }
  }

  Future<void> _onTutorialFinished() async {
    setState(() => _view = _Shell.home);
    // Persist tutorial_seen so we don't show it again on this account.
    // Read current settings first so we don't stomp notification prefs.
    try {
      final api = ref.read(backendApiProvider);
      final current = await api.getSettings();
      await api.updateSettings(current.copyWith(tutorialSeen: true));
    } catch (_) {/* best-effort */}
  }

  Future<void> _refreshToday() async {
    try {
      final t = await ref.read(backendApiProvider).getToday();
      if (!mounted) return;
      setState(() => _today = t);
    } catch (_) {/* silent */}
  }

  Future<void> _onOnboardingComplete(SkinProfile profile) async {
    setState(() {
      _profile = profile;
      _view = _Shell.tutorial;
    });
    try {
      await ref.read(backendApiProvider).putProfile(profile);
    } catch (_) {/* best-effort */}
    Telemetry.event('onboarding_complete', data: {
      'has_name': profile.name != null,
      'gender': profile.gender,
      'skin_type': profile.skinType,
      'concerns_count': profile.concerns.length,
    });
    // Brand-new user: ask for notification permission once and schedule
    // the default morning+evening ritual reminders.
    final granted =
        await LocalNotificationsService.instance.requestPermission();
    if (granted) {
      // ignore: unawaited_futures
      LocalNotificationsService.instance
          .reschedule(const NotificationSettings());
    }
  }

  Future<void> _runStandard({Map<String, String>? checkIn}) async {
    setState(() => _view = _Shell.standardLoading);
    try {
      final ai = ref.read(aiServiceProvider);
      final api = ref.read(backendApiProvider);
      final result =
          await ai.generateRoutine(_profile, checkIn: checkIn);
      if (!mounted) return;
      setState(() {
        _lastResult = result;
        _view = _Shell.standardResult;
      });
      // ignore: unawaited_futures
      api.saveRoutine(kind: 'standard', result: result).catchError((_) {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _view = _Shell.home);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_view) {
      case _Shell.bootstrapping:
        return const SplashScreen();
      case _Shell.bootstrapError:
        return _BootstrapErrorScreen(onRetry: _bootstrap);
      case _Shell.onboarding:
        return OnboardingScreen(onComplete: _onOnboardingComplete);
      case _Shell.tutorial:
        return WelcomeTutorialScreen(onFinish: _onTutorialFinished);
      case _Shell.home:
        return HomeScreen(
          profile: _profile,
          lastResult: _lastResult,
          today: _today,
          onStandardMode: () => setState(() => _view = _Shell.quickCheckIn),
          onDermMode: () => setState(() => _view = _Shell.chat),
          onRetake: () => setState(() {
            _view = _Shell.onboarding;
            _profile = const SkinProfile();
            _lastResult = null;
          }),
          onLogout: () =>
              ref.read(authControllerProvider.notifier).logout(),
          onOpenRoutine: () => setState(() => _view = _Shell.ritual),
          onOpenCatalog: () => setState(() => _view = _Shell.catalog),
          onOpenShelf: () => setState(() => _view = _Shell.profile),
          onOpenScan: () => setState(() => _view = _Shell.scan),
          onOpenNotifications: () =>
              setState(() => _view = _Shell.notifications),
          onOpenProduct: (Product p) => setState(() {
            _previousView = _Shell.home;
            _openProductSlug = p.slug;
            _view = _Shell.productDetail;
          }),
        );
      case _Shell.standardLoading:
        return AILoadingScreen(
          onCancel: () => setState(() => _view = _Shell.home),
        );
      case _Shell.standardResult:
        return RoutineScreen(
          result: _lastResult!,
          onBack: () => setState(() => _view = _Shell.home),
          onOpenProduct: (Product p) => setState(() {
            _previousView = _Shell.standardResult;
            _openProductSlug = p.slug;
            _view = _Shell.productDetail;
          }),
        );
      case _Shell.derm2:
        return Derm2Screen(
          profile: _profile,
          onBack: () => setState(() => _view = _Shell.home),
        );
      case _Shell.catalog:
        final concern = _catalogInitialConcern;
        // Consume — next time user opens the catalog from the home tab
        // it should start unfiltered.
        _catalogInitialConcern = null;
        return CatalogScreen(
          onBack: () => setState(() => _view = _Shell.home),
          initialConcern: concern,
          onOpen: (Product p) => setState(() {
            _previousView = _Shell.catalog;
            _openProductSlug = p.slug;
            _view = _Shell.productDetail;
          }),
        );
      case _Shell.shelf:
        return ShelfScreen(
          onBack: () => setState(() => _view = _Shell.home),
          onOpen: (Product p) {
            if (p.isCustom) {
              setState(() {
                _openCustomProduct = p;
                _view = _Shell.customProductDetail;
              });
            } else {
              setState(() {
                _previousView = _Shell.shelf;
                _openProductSlug = p.slug;
                _view = _Shell.productDetail;
              });
            }
          },
          onAddCustom: () =>
              setState(() => _view = _Shell.addCustomProduct),
        );
      case _Shell.addCustomProduct:
        return AddCustomProductScreen(
          onBack: () => setState(() => _view = _Shell.shelf),
          onSaved: () => setState(() => _view = _Shell.shelf),
        );
      case _Shell.customProductDetail:
        return CustomProductDetailScreen(
          product: _openCustomProduct!,
          onBack: () => setState(() => _view = _Shell.shelf),
          onDeleted: () => setState(() => _view = _Shell.shelf),
          onAskLina: () => setState(() => _view = _Shell.chat),
        );
      case _Shell.productDetail:
        return ProductDetailScreen(
          slug: _openProductSlug!,
          onBack: () => setState(() => _view = _previousView),
        );
      case _Shell.ritual:
        return DailyRitualScreen(
          onBack: () {
            _refreshToday();
            setState(() => _view = _Shell.home);
          },
          onOpenProduct: (p) => setState(() {
            _openProductSlug = p.slug;
            _previousView = _Shell.ritual;
            _view = _Shell.productDetail;
          }),
          onOpenCatalog: () => setState(() => _view = _Shell.catalog),
        );
      case _Shell.profile:
        return ProfileScreen(
          profile: _profile,
          skinScore: _lastResult?.skinScore,
          streak: _today?.streak,
          onBack: () => setState(() => _view = _Shell.home),
          onRetake: () => setState(() {
            _view = _Shell.onboarding;
            _profile = const SkinProfile();
            _lastResult = null;
          }),
          onOpenShelf: () => setState(() => _view = _Shell.shelf),
          onOpenProgress: () => setState(() => _view = _Shell.progress),
          onProfileUpdated: (p) => setState(() => _profile = p),
          onOpenFavorites: () => setState(() => _view = _Shell.favorites),
          onOpenRoutineHistory: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (ctx) => RoutineHistoryScreen(
                onBack: () => Navigator.of(ctx).pop(),
              ),
            ),
          ),
        );
      case _Shell.scan:
        return ScanScreen(
          onBack: () => setState(() => _view = _Shell.home),
          onResult: (r) => setState(() {
            _lastScan = r;
            _view = _Shell.scanResult;
          }),
        );
      case _Shell.scanResult:
        return ScanResultScreen(
          scan: _lastScan!,
          onBack: () => setState(() => _view = _Shell.home),
          onAccept: _runStandard,
          onOpenCatalog: (concern) => setState(() {
            _catalogInitialConcern = concern.isEmpty ? null : concern;
            _view = _Shell.catalog;
          }),
        );
      case _Shell.progress:
        return ProgressScreen(
          onBack: () => setState(() => _view = _Shell.profile),
          onScan: () => setState(() => _view = _Shell.scan),
        );
      case _Shell.chat:
        return ChatScreen(
          onBack: () => setState(() => _view = _Shell.home),
          onOpenScan: () => setState(() => _view = _Shell.scan),
          onOpenProduct: (Product p) => setState(() {
            _previousView = _Shell.chat;
            _openProductSlug = p.slug;
            _view = _Shell.productDetail;
          }),
        );
      case _Shell.notifications:
        return NotificationsScreen(
          onBack: () => setState(() => _view = _Shell.home),
          onOpenScan: _openScanById,
          onOpenRitual: () => setState(() => _view = _Shell.ritual),
        );
      case _Shell.quickCheckIn:
        return QuickCheckInScreen(
          onBack: () => setState(() => _view = _Shell.home),
          onSubmit: (answers) {
            // ignore: unawaited_futures
            _runStandard(checkIn: answers);
          },
        );
      case _Shell.favorites:
        return FavoritesScreen(
          onBack: () => setState(() => _view = _Shell.profile),
          onOpen: (p) => setState(() {
            _previousView = _Shell.favorites;
            _openProductSlug = p.slug;
            _view = _Shell.productDetail;
          }),
        );
    }
  }

  Future<void> _openScanById(String scanId) async {
    try {
      final scan =
          await ref.read(backendApiProvider).getScan(scanId);
      if (!mounted) return;
      setState(() {
        _lastScan = scan;
        _view = _Shell.scanResult;
      });
    } catch (_) {
      // Silent — notification stays marked read, user just doesn't deep-link.
    }
  }
}
