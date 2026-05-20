import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

/// Wraps `permission_handler` with our flow:
/// - On first launch, request the entire set up front.
/// - Per-feature entry points later check status and, when permanently
///   denied, kick the user to a "go to settings" screen — never silently
///   no-op a denied request (iOS won't show the OS dialog again).
class AppPermissions {
  AppPermissions._();
  static final instance = AppPermissions._();

  static const _storage = FlutterSecureStorage();
  static const _kInitialAskedKey = 'permissions_initial_asked_v1';

  /// Set requested at first launch — everything the app touches except
  /// internet. Photos is iOS-only (Android handles gallery picks via the
  /// system picker without runtime grant), notifications is iOS 13+
  /// and Android 13+.
  static List<Permission> get initialSet => [
        Permission.camera,
        Permission.microphone,
        Permission.notification,
        if (Platform.isIOS) Permission.photos,
        if (Platform.isIOS) Permission.speech,
      ];

  Future<bool> isInitialAsked() async {
    final v = await _storage.read(key: _kInitialAskedKey);
    return v == '1';
  }

  Future<void> markInitialAsked() async {
    await _storage.write(key: _kInitialAskedKey, value: '1');
  }

  /// Fire the system prompts for every permission in [initialSet] and
  /// persist that we've done the first-launch sweep. Subsequent launches
  /// skip the intro screen even if the user denied some — they can grant
  /// later via the per-feature gates.
  Future<Map<Permission, PermissionStatus>> requestInitial() async {
    final result = await initialSet.request();
    await markInitialAsked();
    return result;
  }

  /// Status snapshot for a single permission. Cheap, doesn't prompt.
  Future<PermissionStatus> status(Permission p) => p.status;

  /// Idempotent grant request: returns current status if already granted,
  /// shows the OS prompt if still "denied" (i.e. asked once and refused),
  /// returns `permanentlyDenied` without prompting if the user previously
  /// chose "Don't ask again" / iOS denial — caller should then show the
  /// settings CTA.
  Future<PermissionStatus> ensure(Permission p) async {
    final cur = await p.status;
    if (cur.isGranted || cur.isLimited) return cur;
    if (cur.isPermanentlyDenied) return cur;
    return p.request();
  }

  Future<bool> openSettings() => openAppSettings();
}
