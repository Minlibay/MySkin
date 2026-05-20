import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ai/domain/models.dart';
import '../catalog/domain/product.dart';
import '../notifications/domain/app_notification.dart';
import '../profile/domain/user_settings.dart';
import '../pro/domain/pro_status.dart';
import '../progress/domain/progress.dart';
import '../ritual/domain/today.dart';
import '../scan/domain/scan_result.dart';

/// Thrown by [BackendApi.buildRoutineFromShelf] when the user's shelf has
/// no `have` items yet — the UI shows a "add some products first" prompt.
class EmptyShelfException implements Exception {
  EmptyShelfException(this.message);
  final String message;
  @override
  String toString() => 'EmptyShelfException: $message';
}

/// Thrown by [BackendApi.uploadScan] when the server refused the photo
/// because the metrics would be meaningless (no face, dark, blurry, far).
/// The camera screen catches this to show a "retake" prompt instead of a
/// generic network error.
class ScanQualityException implements Exception {
  ScanQualityException({required this.warnings, required this.message});
  final List<String> warnings;
  final String message;

  @override
  String toString() => 'ScanQualityException($warnings): $message';
}

/// Authenticated client for `/me/*` endpoints.
class BackendApi {
  BackendApi({required this.baseUrl, required this.tokenProvider, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              // Scan upload goes through GigaChat Vision (≈10s) + the
              // MediaPipe face-mesh sidecar (≈1-5s cold, <500ms warm).
              // 60s gives healthy headroom for both, plus mobile cellular.
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 30),
              headers: {'content-type': 'application/json'},
            ));

  final String baseUrl;
  final String? Function() tokenProvider;
  final Dio _dio;

  Options _auth() {
    final t = tokenProvider();
    return Options(headers: {
      if (t != null) 'authorization': 'Bearer $t',
    });
  }

  Future<SkinProfile?> getProfile() async {
    try {
      final r = await _dio.get('$baseUrl/me/profile', options: _auth());
      final j = r.data as Map<String, dynamic>;
      return SkinProfile(
        name: j['name'] as String?,
        gender: j['gender'] as String?,
        skinType: j['skin_type'] as String?,
        pores: j['pores'] as String?,
        concerns: ((j['concerns'] as List?) ?? const []).cast<String>(),
        acneType: j['acne_type'] as String?,
        sensitivity: j['sensitivity'] as String?,
        sensitivityReaction: j['sensitivity_reaction'] as String?,
        budget: j['budget'] as String?,
        extras: ((j['extras'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k as String, v?.toString() ?? ''),
        ),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> putProfile(SkinProfile profile) async {
    await _dio.put(
      '$baseUrl/me/profile',
      data: profile.toJson(),
      options: _auth(),
    );
  }

  Future<List<RoutineRecord>> listRoutines() async {
    final r = await _dio.get('$baseUrl/me/routines', options: _auth());
    final items = ((r.data as Map)['items'] as List).cast<Map<String, dynamic>>();
    return items.map(RoutineRecord.fromJson).toList();
  }

  /// Routine + scan history merged into one timeline with stats. Backend
  /// does the diffing/adherence/sorting work so the screen can stay thin.
  Future<RoutineTimeline> getRoutinesTimeline() async {
    final r =
        await _dio.get('$baseUrl/me/routines/timeline', options: _auth());
    return RoutineTimeline.fromJson((r.data as Map).cast<String, dynamic>());
  }

  /// Resume a past routine by cloning it as a fresh row. Today screen picks
  /// the newest non-empty one, so the clone makes the chosen routine active.
  Future<String> resumeRoutine(String routineId) async {
    final r = await _dio.post(
      '$baseUrl/me/routines/$routineId/resume',
      options: _auth(),
    );
    return (r.data as Map)['id'] as String;
  }

  Future<void> saveRoutine({
    required String kind,
    required RoutineResult result,
  }) async {
    await _dio.post(
      '$baseUrl/me/routines',
      data: {
        'kind': kind,
        'confidence': result.confidence,
        'payload': {
          'morning': result.morning.map(_step).toList(),
          'evening': result.evening.map(_step).toList(),
          'warnings': result.warnings,
          'tips': result.tips,
          'skin_summary': result.skinSummary,
          'skin_score': result.skinScore,
        },
      },
      options: _auth(),
    );
  }

  Future<void> saveDermSession({
    required SkinProfile profile,
    required List<Map<String, dynamic>> history,
    String? finalPhase,
    double? confidence,
  }) async {
    await _dio.post(
      '$baseUrl/me/derm-sessions',
      data: {
        'profile': profile.toJson(),
        'history': history,
        'final_phase': finalPhase,
        'confidence': confidence,
      },
      options: _auth(),
    );
  }

  static Map<String, dynamic> _step(RoutineStep s) => {
        'title': s.title,
        'ingredients': s.ingredients,
        'explanation': s.explanation,
      };

  // ===== Catalog =====

  Future<List<Product>> listCatalog({
    String? kind,
    String? concern,
    String? query,
  }) async {
    final r = await _dio.get(
      '$baseUrl/catalog',
      queryParameters: {
        if (kind != null) 'kind': kind,
        if (concern != null) 'concern': concern,
        if (query != null && query.isNotEmpty) 'q': query,
      },
      options: _auth(),
    );
    final items = ((r.data as Map)['items'] as List).cast<Map<String, dynamic>>();
    return items.map(Product.fromJson).toList();
  }

  Future<Product> getProduct(String slug) async {
    // Slugs imported from RU feeds keep Cyrillic letters — they have to be
    // percent-encoded before going into the URL path, otherwise Dio sends
    // raw UTF-8 bytes and the backend router can't match the route.
    final r = await _dio.get(
      '$baseUrl/catalog/${Uri.encodeComponent(slug)}',
      options: _auth(),
    );
    return Product.fromJson(r.data as Map<String, dynamic>);
  }

  Future<List<Product>> getShelf() async {
    final r = await _dio.get('$baseUrl/me/shelf', options: _auth());
    final items = ((r.data as Map)['items'] as List).cast<Map<String, dynamic>>();
    return items.map(Product.fromJson).toList();
  }

  Future<void> addToShelf({
    required String productId,
    String status = 'have',
  }) async {
    await _dio.put(
      '$baseUrl/me/shelf/$productId',
      data: {'status': status},
      options: _auth(),
    );
  }

  Future<void> removeFromShelf(String productId) async {
    await _dio.delete('$baseUrl/me/shelf/$productId', options: _auth());
  }

  /// Builds a morning/evening routine from products the user has on their
  /// shelf (status='have'). Returns the saved routine's id + payload. Throws
  /// [EmptyShelfException] if the shelf has no `have` items yet.
  Future<Map<String, dynamic>> buildRoutineFromShelf({
    bool preview = false,
  }) async {
    try {
      final r = await _dio.post(
        '$baseUrl/me/routines/from-shelf',
        data: {if (preview) 'preview': true},
        options: _auth(),
      );
      return (r.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      if (e.response?.statusCode == 409 &&
          (e.response?.data as Map?)?['error'] == 'empty_shelf') {
        throw EmptyShelfException(
          (e.response?.data as Map)['message'] as String? ??
              'Полка пустая.',
        );
      }
      rethrow;
    }
  }

  /// Patch fill_level / opened_at / expires_at / pao_months for a catalog
  /// product already on the user's shelf. Pass `null` for any key in
  /// [clear] to null it out server-side; non-null fields are written as-is.
  Future<void> patchShelfItem({
    required String productId,
    String? fillLevel,
    DateTime? openedAt,
    DateTime? expiresAt,
    int? paoMonths,
    Set<String> clear = const {},
  }) async {
    final body = <String, dynamic>{};
    if (fillLevel != null) body['fill_level'] = fillLevel;
    if (openedAt != null) body['opened_at'] = _dateOnly(openedAt);
    if (expiresAt != null) body['expires_at'] = _dateOnly(expiresAt);
    if (paoMonths != null) body['pao_months'] = paoMonths;
    for (final k in clear) {
      body[k] = null;
    }
    if (body.isEmpty) return;
    await _dio.patch('$baseUrl/me/shelf/$productId',
        data: body, options: _auth());
  }

  Future<Product> addCustomProduct({
    required String brand,
    required String name,
    required String kind,
    String? accentColor,
    List<String> ingredients = const [],
    String status = 'have',
    String? fillLevel,
    DateTime? openedAt,
    DateTime? expiresAt,
    int? paoMonths,
    String? notes,
    String? photoBase64,
    String photoMime = 'image/jpeg',
  }) async {
    final body = <String, dynamic>{
      'brand': brand,
      'name': name,
      'kind': kind,
      if (accentColor != null) 'accent_color': accentColor,
      if (ingredients.isNotEmpty) 'ingredients': ingredients,
      'status': status,
      if (fillLevel != null) 'fill_level': fillLevel,
      if (openedAt != null) 'opened_at': _dateOnly(openedAt),
      if (expiresAt != null) 'expires_at': _dateOnly(expiresAt),
      if (paoMonths != null) 'pao_months': paoMonths,
      if (notes != null) 'notes': notes,
      if (photoBase64 != null) ...{
        'photo_b64': photoBase64,
        'photo_mime': photoMime,
      },
    };
    final r =
        await _dio.post('$baseUrl/me/shelf/custom', data: body, options: _auth());
    return Product.fromJson(r.data as Map<String, dynamic>);
  }

  Future<Product> patchCustomProduct({
    required String id,
    String? brand,
    String? name,
    String? kind,
    String? status,
    String? fillLevel,
    DateTime? openedAt,
    DateTime? expiresAt,
    int? paoMonths,
    String? notes,
    Set<String> clear = const {},
  }) async {
    final body = <String, dynamic>{};
    if (brand != null) body['brand'] = brand;
    if (name != null) body['name'] = name;
    if (kind != null) body['kind'] = kind;
    if (status != null) body['status'] = status;
    if (fillLevel != null) body['fill_level'] = fillLevel;
    if (openedAt != null) body['opened_at'] = _dateOnly(openedAt);
    if (expiresAt != null) body['expires_at'] = _dateOnly(expiresAt);
    if (paoMonths != null) body['pao_months'] = paoMonths;
    if (notes != null) body['notes'] = notes;
    for (final k in clear) {
      body[k] = null;
    }
    final r = await _dio.patch('$baseUrl/me/shelf/custom/$id',
        data: body, options: _auth());
    return Product.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> removeCustomProduct(String id) async {
    await _dio.delete('$baseUrl/me/shelf/custom/$id', options: _auth());
  }

  String customProductPhotoUrl(String id) =>
      '$baseUrl/me/shelf/custom/$id/photo';

  Future<void> setCustomProductPhoto({
    required String id,
    required String photoBase64,
    String mime = 'image/jpeg',
  }) async {
    await _dio.put(
      '$baseUrl/me/shelf/custom/$id/photo',
      data: {'photo_b64': photoBase64, 'mime': mime},
      options: _auth(),
    );
  }

  static String _dateOnly(DateTime d) {
    final u = d.toUtc();
    return '${u.year.toString().padLeft(4, '0')}-'
        '${u.month.toString().padLeft(2, '0')}-'
        '${u.day.toString().padLeft(2, '0')}';
  }

  Future<void> addFavorite(String productId) async {
    await _dio.put('$baseUrl/me/favorites/$productId', options: _auth());
  }

  Future<void> removeFavorite(String productId) async {
    await _dio.delete('$baseUrl/me/favorites/$productId', options: _auth());
  }

  // ===== Avatar =====

  String avatarUrl({int cacheBust = 0}) =>
      cacheBust == 0 ? '$baseUrl/me/avatar' : '$baseUrl/me/avatar?v=$cacheBust';

  Future<void> setAvatar({
    required String photoBase64,
    String mime = 'image/jpeg',
  }) async {
    await _dio.put(
      '$baseUrl/me/avatar',
      data: {'photo_b64': photoBase64, 'mime': mime},
      options: _auth(),
    );
  }

  Future<void> removeAvatar() async {
    await _dio.delete('$baseUrl/me/avatar', options: _auth());
  }

  Future<List<Product>> listFavorites() async {
    final r = await _dio.get('$baseUrl/me/favorites', options: _auth());
    final items =
        ((r.data as Map)['items'] as List).cast<Map<String, dynamic>>();
    return items.map(Product.fromJson).toList();
  }

  // ===== Daily ritual =====

  Future<Today> getToday() async {
    final r = await _dio.get('$baseUrl/me/today', options: _auth());
    return Today.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> checkStep({
    required String phase,
    required int stepIndex,
    String? stepTitle,
  }) async {
    await _dio.post(
      '$baseUrl/me/today/check',
      data: {
        'phase': phase,
        'step_index': stepIndex,
        if (stepTitle != null) 'step_title': stepTitle,
      },
      options: _auth(),
    );
  }

  Future<void> uncheckStep({
    required String phase,
    required int stepIndex,
  }) async {
    await _dio.post(
      '$baseUrl/me/today/uncheck',
      data: {'phase': phase, 'step_index': stepIndex},
      options: _auth(),
    );
  }

  // ===== Settings & account =====

  Future<UserSettings> getSettings() async {
    final r = await _dio.get('$baseUrl/me/settings', options: _auth());
    return UserSettings.fromJson(
        (r.data as Map?)?.cast<String, dynamic>() ?? const {});
  }

  /// Returns whether the user is on the Pro tier plus the expiry.
  /// Free users get `{is_pro: false, pro_until: null}`.
  Future<ProStatus> getProStatus() async {
    final r = await _dio.get('$baseUrl/me/pro/status', options: _auth());
    return ProStatus.fromJson(
        (r.data as Map?)?.cast<String, dynamic>() ?? const {});
  }

  Future<void> updateSettings(UserSettings settings) async {
    await _dio.put(
      '$baseUrl/me/settings',
      data: settings.toJson(),
      options: _auth(),
    );
  }

  Future<void> deleteAccount() async {
    await _dio.delete('$baseUrl/me/account', options: _auth());
  }

  /// Returns full export as JSON map. UI can stringify and offer download.
  Future<Map<String, dynamic>> exportData() async {
    final r = await _dio.get('$baseUrl/me/export', options: _auth());
    return (r.data as Map).cast<String, dynamic>();
  }

  // ===== Scans =====

  Future<ScanResult> uploadScan({
    required String photoBase64,
    String mime = 'image/jpeg',
  }) async {
    try {
      final r = await _dio.post(
        '$baseUrl/me/scans',
        data: {
          'photo_b64': photoBase64,
          'mime': mime,
        },
        options: _auth(),
      );
      return ScanResult.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) {
      // Server refused the photo because face/lighting/focus made the metrics
      // meaningless. Surface a typed error so the camera screen can show
      // "перефоткай" instead of falling back to the generic network toast.
      if (e.response?.statusCode == 422) {
        final data = e.response?.data;
        if (data is Map && data['error'] == 'scan_quality') {
          throw ScanQualityException(
            warnings: ((data['quality_warnings'] as List?) ?? const [])
                .map((e) => '$e')
                .toList(),
            message: (data['message'] as String?) ??
                'Фото не подошло для анализа. Попробуй ещё раз.',
          );
        }
      }
      rethrow;
    }
  }

  Future<List<ScanResult>> listScans() async {
    final r = await _dio.get('$baseUrl/me/scans', options: _auth());
    final items = ((r.data as Map)['items'] as List).cast<Map<String, dynamic>>();
    return items.map(ScanResult.fromJson).toList();
  }

  String scanPhotoUrl(String id) => '$baseUrl/me/scans/$id/photo';

  /// Fire-and-forget catalog telemetry. Server validates kinds/surfaces and
  /// dedups impressions by (product, session_key). Failures are caller's
  /// problem to ignore — see ProductTelemetry.
  Future<void> logProductEvents(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;
    await _dio.post(
      '$baseUrl/events/product',
      data: {'events': events},
      options: _auth(),
    );
  }

  /// Per-zone drill-down — Лина's take on a single face zone of one scan.
  /// `zone` is one of: forehead | tzone | left_cheek | right_cheek | chin.
  Future<ZoneInsight> fetchZoneInsight(String scanId, String zone) async {
    final r = await _dio.get(
      '$baseUrl/me/scans/$scanId/zone/$zone',
      options: _auth(),
    );
    return ZoneInsight.fromJson(r.data as Map<String, dynamic>);
  }

  String productPhotoUrl(String id, {int? slot}) =>
      slot == null
          ? '$baseUrl/products/$id/photo'
          : '$baseUrl/products/$id/photo/$slot';

  Future<ScanResult> getScan(String id) async {
    final r = await _dio.get('$baseUrl/me/scans/$id', options: _auth());
    return ScanResult.fromJson(r.data as Map<String, dynamic>);
  }

  /// Free-form Лина chat — pass full {role, content} message history.
  /// Returns Лина's reply + a (possibly empty) list of products picked
  /// from the catalog based on the user's profile match.
  Future<ChatReply> chat(List<Map<String, String>> messages) async {
    try {
      final resp = await _dio.post(
        '$baseUrl/ai/chat',
        data: {'messages': messages},
        options: _auth(),
      );
      final data = resp.data as Map;
      final products = ((data['recommended_products'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Product.fromJson)
          .toList();
      return ChatReply(
        reply: data['reply'] as String? ?? '',
        products: products,
      );
    } on DioException catch (e) {
      final code = (e.response?.data is Map &&
              (e.response!.data as Map)['error'] is String)
          ? (e.response!.data as Map)['error'] as String
          : 'network';
      throw Exception(code);
    }
  }

  Map<String, String> imageAuthHeaders() {
    final t = tokenProvider();
    return {if (t != null) 'authorization': 'Bearer $t'};
  }

  // ===== Chat history =====

  Future<List<Map<String, dynamic>>> getChatHistory() async {
    final r = await _dio.get('$baseUrl/me/chat', options: _auth());
    return ((r.data as Map)['items'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const [];
  }

  Future<void> clearChatHistory() async {
    await _dio.delete('$baseUrl/me/chat', options: _auth());
  }

  // ===== Legal documents =====

  Future<String> getLegal(String key) async {
    try {
      final r = await _dio.get('$baseUrl/legal/$key');
      return (r.data as Map)['markdown'] as String? ?? '';
    } on DioException {
      return '';
    }
  }

  // ===== Notifications =====

  Future<({List<AppNotification> items, int unreadCount})>
      listNotifications() async {
    final r = await _dio.get('$baseUrl/me/notifications', options: _auth());
    final data = r.data as Map<String, dynamic>;
    final items = ((data['items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(AppNotification.fromJson)
        .toList();
    return (
      items: items,
      unreadCount: (data['unread_count'] as int?) ?? 0,
    );
  }

  Future<int> notificationsUnreadCount() async {
    try {
      final r = await _dio.get('$baseUrl/me/notifications/unread_count',
          options: _auth());
      return ((r.data as Map)['unread_count'] as int?) ?? 0;
    } on DioException {
      return 0;
    }
  }

  Future<void> markNotificationRead(String id) async {
    await _dio.post('$baseUrl/me/notifications/$id/read', options: _auth());
  }

  Future<void> markAllNotificationsRead() async {
    await _dio.post('$baseUrl/me/notifications/read_all', options: _auth());
  }

  // ===== Progress =====

  Future<ProgressData> getProgress({int days = 30}) async {
    final r = await _dio.get(
      '$baseUrl/me/progress',
      queryParameters: {'days': days},
      options: _auth(),
    );
    return ProgressData.fromJson(r.data as Map<String, dynamic>);
  }
}

class RoutineRecord {
  RoutineRecord({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.result,
  });
  final String id;
  final String kind;
  final DateTime createdAt;
  final RoutineResult result;

  factory RoutineRecord.fromJson(Map<String, dynamic> j) {
    final payload = (j['payload'] as Map).cast<String, dynamic>();
    return RoutineRecord(
      id: j['id'] as String,
      kind: j['kind'] as String,
      createdAt: DateTime.parse(j['created_at'] as String),
      result: RoutineResult.fromJson({
        ...payload,
        'confidence': j['confidence'],
      }),
    );
  }
}

class ChatReply {
  const ChatReply({required this.reply, required this.products});
  final String reply;
  final List<Product> products;
}

/// Timeline payload from /me/routines/timeline. Nodes are pre-sorted
/// newest-first and already include the month-divider rows the screen
/// renders verbatim.
class RoutineTimeline {
  RoutineTimeline({
    required this.totalRoutines,
    required this.currentStreakDays,
    required this.lastAdherence,
    required this.activeRoutineId,
    required this.nodes,
  });

  final int totalRoutines;
  final int currentStreakDays;
  final RoutineAdherence? lastAdherence;
  final String? activeRoutineId;
  final List<TimelineNode> nodes;

  factory RoutineTimeline.fromJson(Map<String, dynamic> j) {
    final stats = (j['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rawNodes = ((j['nodes'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    return RoutineTimeline(
      totalRoutines: (stats['total_routines'] as num?)?.toInt() ?? 0,
      currentStreakDays:
          (stats['current_streak_days'] as num?)?.toInt() ?? 0,
      lastAdherence: stats['last_routine_adherence'] is Map
          ? RoutineAdherence.fromJson(
              (stats['last_routine_adherence'] as Map)
                  .cast<String, dynamic>())
          : null,
      activeRoutineId: j['active_routine_id'] as String?,
      nodes: rawNodes.map(TimelineNode.fromJson).toList(),
    );
  }
}

class RoutineAdherence {
  RoutineAdherence({
    required this.completedDays,
    required this.totalDays,
    required this.percent,
  });
  final int completedDays;
  final int totalDays;
  final int percent;

  factory RoutineAdherence.fromJson(Map<String, dynamic> j) =>
      RoutineAdherence(
        completedDays: (j['completed_days'] as num?)?.toInt() ?? 0,
        totalDays: (j['total_days'] as num?)?.toInt() ?? 0,
        percent: (j['percent'] as num?)?.toInt() ?? 0,
      );
}

/// One row in the timeline. Discriminated by [type] — 'month_divider',
/// 'routine', or 'scan'. Fields not relevant to the row's type are null.
class TimelineNode {
  TimelineNode({
    required this.type,
    this.label,
    this.id,
    this.kind,
    this.createdAt,
    this.isActive = false,
    this.stepsPreview,
    this.morningCount,
    this.eveningCount,
    this.adherence,
    this.diffAdded = const [],
    this.diffRemoved = const [],
    this.skinScoreBefore,
    this.skinScoreAfter,
    this.skinSummary,
    this.scanScore,
    this.scanDeltaVsPrev,
  });

  final String type;
  // Month divider
  final String? label;
  // Routine + scan share these
  final String? id;
  final DateTime? createdAt;
  // Routine
  final String? kind;
  final bool isActive;
  final String? stepsPreview;
  final int? morningCount;
  final int? eveningCount;
  final RoutineAdherence? adherence;
  final List<String> diffAdded;
  final List<String> diffRemoved;
  final int? skinScoreBefore;
  final int? skinScoreAfter;
  final String? skinSummary;
  // Scan
  final int? scanScore;
  final int? scanDeltaVsPrev;

  factory TimelineNode.fromJson(Map<String, dynamic> j) {
    final type = j['type'] as String;
    final diff = (j['diff_vs_prev'] as Map?)?.cast<String, dynamic>();
    return TimelineNode(
      type: type,
      label: j['label'] as String?,
      id: j['id'] as String?,
      kind: j['kind'] as String?,
      createdAt: j['created_at'] is String
          ? DateTime.tryParse(j['created_at'] as String)
          : null,
      isActive: j['is_active'] as bool? ?? false,
      stepsPreview: j['steps_preview'] as String?,
      morningCount: (j['morning_count'] as num?)?.toInt(),
      eveningCount: (j['evening_count'] as num?)?.toInt(),
      adherence: j['adherence'] is Map
          ? RoutineAdherence.fromJson(
              (j['adherence'] as Map).cast<String, dynamic>())
          : null,
      diffAdded: ((diff?['added'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      diffRemoved: ((diff?['removed'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      skinScoreBefore: (j['skin_score_before'] as num?)?.toInt(),
      skinScoreAfter: (j['skin_score_after'] as num?)?.toInt(),
      skinSummary: j['skin_summary'] as String?,
      scanScore: (j['score'] as num?)?.toInt(),
      scanDeltaVsPrev: (j['delta_vs_prev'] as num?)?.toInt(),
    );
  }
}

final backendApiProvider = Provider<BackendApi>((ref) {
  throw UnimplementedError('Override backendApiProvider in main.dart');
});
