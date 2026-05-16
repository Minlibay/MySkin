import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ai/domain/models.dart';
import '../catalog/domain/product.dart';
import '../notifications/domain/app_notification.dart';
import '../profile/domain/user_settings.dart';
import '../progress/domain/progress.dart';
import '../ritual/domain/today.dart';
import '../scan/domain/scan_result.dart';

/// Authenticated client for `/me/*` endpoints.
class BackendApi {
  BackendApi({required this.baseUrl, required this.tokenProvider, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
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
    final r = await _dio.get('$baseUrl/catalog/$slug', options: _auth());
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
    List<double>? faceBbox,
  }) async {
    final r = await _dio.post(
      '$baseUrl/me/scans',
      data: {
        'photo_b64': photoBase64,
        'mime': mime,
        if (faceBbox != null && faceBbox.length == 4) 'face_bbox': faceBbox,
      },
      options: _auth(),
    );
    return ScanResult.fromJson(r.data as Map<String, dynamic>);
  }

  Future<List<ScanResult>> listScans() async {
    final r = await _dio.get('$baseUrl/me/scans', options: _auth());
    final items = ((r.data as Map)['items'] as List).cast<Map<String, dynamic>>();
    return items.map(ScanResult.fromJson).toList();
  }

  String scanPhotoUrl(String id) => '$baseUrl/me/scans/$id/photo';

  /// Per-zone drill-down — Лина's take on a single face zone of one scan.
  /// `zone` is one of: forehead | tzone | left_cheek | right_cheek | chin.
  Future<ZoneInsight> fetchZoneInsight(String scanId, String zone) async {
    final r = await _dio.get(
      '$baseUrl/me/scans/$scanId/zone/$zone',
      options: _auth(),
    );
    return ZoneInsight.fromJson(r.data as Map<String, dynamic>);
  }

  /// Raw scan photo bytes — used by the result screen when it needs to run
  /// ML Kit again on the saved image (older scans that pre-date face_bbox
  /// support, or scans where the backend skin-colour bbox is too broad to
  /// be useful for the heatmap).
  Future<List<int>?> scanPhotoBytes(String id) async {
    try {
      final r = await _dio.get<List<int>>(
        '$baseUrl/me/scans/$id/photo',
        options: _auth().copyWith(responseType: ResponseType.bytes),
      );
      return r.data;
    } catch (_) {
      return null;
    }
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

final backendApiProvider = Provider<BackendApi>((ref) {
  throw UnimplementedError('Override backendApiProvider in main.dart');
});
