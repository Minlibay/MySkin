import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../profile/domain/user_settings.dart';

/// Schedules the morning/evening ritual reminders locally on the device.
/// Pure device-side scheduling — no server, no push token, no FCM/APNs.
///
/// Notification IDs are stable so re-scheduling cancels the previous slot
/// instead of stacking up duplicates.
const int _morningId = 1;
const int _eveningId = 2;
const String _channelId = 'ritual_reminders';

/// ID space for product-expiry reminders. Each shelf item occupies three
/// slots (30d / 7d / 0d), keyed by a stable hash of the product id. Kept
/// well clear of the ritual ID range so cancelAll-by-prefix isn't needed.
const int _expiryIdBase = 100000;
const String _expiryChannelId = 'product_expiry';

class LocalNotificationsService {
  LocalNotificationsService._();
  static final instance = LocalNotificationsService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    // tz database + map device's IANA zone onto tz.local so HH:mm we schedule
    // is interpreted in the user's local time, not UTC.
    tz_data.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      debugPrint('Failed to resolve local timezone, falling back to UTC: $e');
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      // We ask explicitly via requestPermission() so the prompt happens at a
      // sensible moment in the UX, not on first plugin init.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  /// Returns true if the user granted (or already had) permission to post
  /// notifications. On platforms without a runtime prompt assumes granted.
  Future<bool> requestPermission() async {
    await init();
    if (Platform.isIOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    if (Platform.isAndroid) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return granted ?? true;
    }
    return true;
  }

  /// Cancels any previously scheduled ritual reminders and schedules new ones
  /// matching [settings]. Safe to call repeatedly — each call fully replaces
  /// the schedule.
  Future<void> reschedule(NotificationSettings settings) async {
    await init();
    await _plugin.cancel(_morningId);
    await _plugin.cancel(_eveningId);

    if (settings.morning) {
      final (h, m) = _parseHM(settings.morningTime);
      await _scheduleDaily(
        id: _morningId,
        hour: h,
        minute: m,
        title: 'Утренний ритуал ✿',
        body: 'Время уделить коже немного внимания.',
      );
    }
    if (settings.evening) {
      final (h, m) = _parseHM(settings.eveningTime);
      await _scheduleDaily(
        id: _eveningId,
        hour: h,
        minute: m,
        title: 'Вечерний ритуал ✿',
        body: 'Несколько минут на себя перед сном.',
      );
    }
  }

  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }

  /// Schedule -30d / -7d / day-of reminders for every shelf item that has an
  /// [effectiveExpiry] in the future. Pass the full list each call: anything
  /// not in [items] gets cancelled, so removed/updated products don't fire
  /// stale notifications. [keyOf] returns the stable id used to slot the
  /// reminders (mobile product id), [labelOf] is the user-facing name,
  /// [expiryOf] is the effective expiry date.
  Future<void> rescheduleExpiryReminders<T>({
    required Iterable<T> items,
    required String Function(T) keyOf,
    required String Function(T) labelOf,
    required DateTime? Function(T) expiryOf,
  }) async {
    await init();
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id >= _expiryIdBase) await _plugin.cancel(p.id);
    }

    final now = tz.TZDateTime.now(tz.local);
    for (final item in items) {
      final exp = expiryOf(item);
      if (exp == null) continue;
      final label = labelOf(item);
      final slot = _slotFor(keyOf(item));
      final triggers = <(int offsetDays, String title, String body)>[
        (
          -30,
          'Скоро истечёт срок',
          '«$label» истекает через 30 дней.',
        ),
        (
          -7,
          'Через неделю срок',
          '«$label» истекает через 7 дней — пора заканчивать.',
        ),
        (
          0,
          'Срок истёк',
          'У «$label» сегодня истекает срок. Лучше не использовать.',
        ),
      ];
      for (var i = 0; i < triggers.length; i++) {
        final (days, title, body) = triggers[i];
        final when = tz.TZDateTime(
          tz.local,
          exp.year,
          exp.month,
          exp.day,
          10,
        ).add(Duration(days: days));
        if (!when.isAfter(now)) continue;
        await _plugin.zonedSchedule(
          slot + i,
          title,
          body,
          when,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _expiryChannelId,
              'Сроки годности',
              channelDescription:
                  'Напоминания о приближающемся сроке годности средств',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }

  /// Maps an arbitrary product id string to a stable integer slot in the
  /// expiry reminder ID space. Three consecutive IDs are reserved per item
  /// (offsets 0/1/2 for the 30d/7d/0d reminders).
  int _slotFor(String key) {
    final h = key.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0x3fffffff);
    return _expiryIdBase + (h % 100000) * 3;
  }

  Future<void> _scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Ритуалы',
          channelDescription:
              'Утренние и вечерние напоминания о ритуале ухода',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      // Inexact is enough for daily reminders and avoids the SCHEDULE_EXACT_ALARM
      // permission requirement on Android 12+.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  (int, int) _parseHM(String hm) {
    final parts = hm.split(':');
    final h = int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 8;
    final m = int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 30;
    return (h.clamp(0, 23), m.clamp(0, 59));
  }
}

final localNotificationsProvider = Provider<LocalNotificationsService>(
  (ref) => LocalNotificationsService.instance,
);
