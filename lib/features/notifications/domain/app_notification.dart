/// One row from the user's notifications inbox.
/// `kind` is the discriminator that drives icon + tap target on the client.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.payload,
    required this.readAt,
    required this.createdAt,
  });

  final String id;
  final String kind;
  final String title;
  final String? body;
  final Map<String, dynamic> payload;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;

  AppNotification copyWith({DateTime? readAt}) => AppNotification(
        id: id,
        kind: kind,
        title: title,
        body: body,
        payload: payload,
        readAt: readAt ?? this.readAt,
        createdAt: createdAt,
      );

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        kind: j['kind'] as String,
        title: j['title'] as String,
        body: j['body'] as String?,
        payload: ((j['payload'] as Map?) ?? const {}).cast<String, dynamic>(),
        readAt: j['read_at'] == null
            ? null
            : DateTime.parse(j['read_at'] as String),
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
