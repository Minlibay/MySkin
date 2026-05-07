/// User-tunable settings stored as JSONB on `users.settings`.
class UserSettings {
  const UserSettings({
    this.notifications = const NotificationSettings(),
  });

  final NotificationSettings notifications;

  UserSettings copyWith({NotificationSettings? notifications}) =>
      UserSettings(notifications: notifications ?? this.notifications);

  factory UserSettings.fromJson(Map<String, dynamic> j) => UserSettings(
        notifications: NotificationSettings.fromJson(
            (j['notifications'] as Map?)?.cast<String, dynamic>() ??
                const {}),
      );

  Map<String, dynamic> toJson() => {
        'notifications': notifications.toJson(),
      };
}

class NotificationSettings {
  const NotificationSettings({
    this.morning = true,
    this.morningTime = '08:30',
    this.evening = true,
    this.eveningTime = '21:00',
  });

  final bool morning;
  final String morningTime; // HH:mm
  final bool evening;
  final String eveningTime;

  NotificationSettings copyWith({
    bool? morning,
    String? morningTime,
    bool? evening,
    String? eveningTime,
  }) =>
      NotificationSettings(
        morning: morning ?? this.morning,
        morningTime: morningTime ?? this.morningTime,
        evening: evening ?? this.evening,
        eveningTime: eveningTime ?? this.eveningTime,
      );

  factory NotificationSettings.fromJson(Map<String, dynamic> j) =>
      NotificationSettings(
        morning: j['morning'] as bool? ?? true,
        morningTime: j['morning_time'] as String? ?? '08:30',
        evening: j['evening'] as bool? ?? true,
        eveningTime: j['evening_time'] as String? ?? '21:00',
      );

  Map<String, dynamic> toJson() => {
        'morning': morning,
        'morning_time': morningTime,
        'evening': evening,
        'evening_time': eveningTime,
      };
}
