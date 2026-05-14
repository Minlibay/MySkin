import 'package:dio/dio.dart';
import '../domain/ai_service.dart';
import '../domain/models.dart';

class AIException implements Exception {
  AIException(this.userMessage, {this.code});
  final String userMessage;
  final String? code;
  @override
  String toString() => userMessage;
}

/// Map a network/parse failure to a user-friendly Russian message.
AIException _mapError(Object e) {
  if (e is AIException) return e;
  if (e is DioException) {
    final code = (e.response?.data is Map &&
            (e.response!.data as Map)['error'] is String)
        ? (e.response!.data as Map)['error'] as String
        : null;
    final status = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return AIException(
        'Нет связи с сервисом. Проверь интернет и попробуй ещё раз.',
        code: 'network',
      );
    }
    if (status == 401) {
      return AIException(
          'Войди заново — сессия истекла.',
          code: 'unauthorized');
    }
    if (status == 403) {
      return AIException(
          'Доступ ограничен. Свяжись с поддержкой.',
          code: 'forbidden');
    }
    if (code == 'ai_failed') {
      return AIException(
        'AI временно недоступен. Попробуй через минуту.',
        code: code,
      );
    }
    if (code == 'ai_bad_json') {
      return AIException(
        'AI вернул некорректный ответ. Попробуй ещё раз.',
        code: code,
      );
    }
    return AIException(
      'Сервис временно недоступен. Попробуй чуть позже.',
      code: code ?? 'http_$status',
    );
  }
  if (e is FormatException) {
    return AIException(
      'Не удалось разобрать ответ AI.',
      code: 'parse_error',
    );
  }
  return AIException('Что-то пошло не так. Попробуй ещё раз.');
}

/// AI client that calls our backend, which proxies to GigaChat.
/// Keeps the GigaChat auth key server-side.
class HttpAIService implements AIService {
  HttpAIService({required this.baseUrl, required this.tokenProvider, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 90),
              headers: {'content-type': 'application/json'},
            ));

  final String baseUrl;
  final String? Function() tokenProvider;
  final Dio _dio;

  Options _auth() => Options(headers: {
        if (tokenProvider() != null)
          'authorization': 'Bearer ${tokenProvider()}',
      });

  @override
  Future<RoutineResult> generateRoutine(SkinProfile profile,
      {Map<String, String>? checkIn}) async {
    try {
      final resp = await _dio.post(
        '$baseUrl/ai/generate-routine',
        data: {
          'profile': profile.toJson(),
          if (checkIn != null && checkIn.isNotEmpty) 'check_in': checkIn,
        },
        options: _auth(),
      );
      return RoutineResult.fromJson(resp.data as Map<String, dynamic>);
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<DermResponse> dermAnalyze({
    required SkinProfile profile,
    required List<DermTurn> history,
  }) async {
    final Map<String, dynamic> data;
    try {
      final resp = await _dio.post(
        '$baseUrl/ai/derm-analyze',
        data: {
          'profile': profile.toJson(),
          'history': history.map((t) => t.toJson()).toList(),
        },
        options: _auth(),
      );
      data = resp.data as Map<String, dynamic>;
    } catch (e) {
      throw _mapError(e);
    }
    final followUp = data['follow_up_question'];
    final confidence = (data['confidence'] as num?)?.toDouble() ??
        ((data['analysis'] as Map?)?['confidence'] as num?)?.toDouble() ??
        0.0;

    // "Ready" only if at least one step is present. Empty list still
    // type-matches `List` — that's a Lina hallucination, not a real recommendation.
    final morning = data['morning_routine'];
    final evening = data['evening_routine'];
    final hasNonEmptyRoutine =
        (morning is List && morning.isNotEmpty) ||
            (evening is List && evening.isNotEmpty);

    if (followUp is String &&
        followUp.trim().isNotEmpty &&
        !hasNonEmptyRoutine) {
      return DermClarification(question: followUp, confidence: confidence);
    }
    if (!hasNonEmptyRoutine) {
      throw AIException(
        'AI вернул пустой ответ. Попробуй ещё раз.',
        code: 'ai_empty_routine',
      );
    }
    return DermReady(
      confidence: confidence,
      result: RoutineResult.fromJson(data),
    );
  }
}
