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
