import 'dart:convert';
import 'package:dio/dio.dart';
import '../domain/ai_service.dart';
import '../domain/models.dart';

class GigachatConfig {
  const GigachatConfig({
    required this.authKey,
    this.scope = 'GIGACHAT_API_PERS',
    this.model = 'GigaChat',
    this.baseUrl = 'https://gigachat.devices.sberbank.ru/api/v1',
    this.oauthUrl = 'https://ngw.devices.sberbank.ru:9443/api/v2/oauth',
  });

  final String authKey;
  final String scope;
  final String model;
  final String baseUrl;
  final String oauthUrl;
}

class GigachatService implements AIService {
  GigachatService({required this.config, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 45),
            ));

  final GigachatConfig config;
  final Dio _dio;

  String? _accessToken;
  DateTime? _tokenExpiresAt;

  static const _standardSystemPrompt = '''
Ты профессиональный косметолог. Подбери уход за кожей лица.
Возвращай ТОЛЬКО валидный JSON по схеме:
{
  "morning": [{"title":"","ingredients":[],"explanation":""}],
  "evening": [{"title":"","ingredients":[],"explanation":""}],
  "warnings": [],
  "tips": []
}
Без markdown, без префиксов, только JSON.
''';

  static const _dermSystemPrompt = '''
Ты AI косметолог уровня Dermatologist 2.0. Работаешь как диалоговая система.

Правила:
- оцени confidence (0.0-1.0) на основе данных пользователя
- если confidence < 0.85 → задай ОДИН простой уточняющий вопрос
- если confidence >= 0.85 → выдай готовый уход
- никогда не ставь медицинских диагнозов
- простой человеческий язык
- один вопрос за раз

Если нужен вопрос, верни ТОЛЬКО JSON:
{"confidence": 0.0, "follow_up_question": "один простой вопрос"}

Если готов выдать уход, верни ТОЛЬКО JSON:
{
  "analysis": {"skin_summary":"", "confidence": 0.0},
  "morning_routine": [{"title":"","ingredients":[],"explanation":""}],
  "evening_routine": [{"title":"","ingredients":[],"explanation":""}],
  "warnings": [],
  "tips": [],
  "follow_up_question": null
}

Без markdown. Только JSON.
''';

  Future<String> _ensureToken() async {
    final now = DateTime.now();
    if (_accessToken != null &&
        _tokenExpiresAt != null &&
        _tokenExpiresAt!.isAfter(now.add(const Duration(seconds: 30)))) {
      return _accessToken!;
    }
    final resp = await _dio.post(
      config.oauthUrl,
      data: {'scope': config.scope},
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        headers: {
          'Authorization': 'Basic ${config.authKey}',
          'RqUID': DateTime.now().millisecondsSinceEpoch.toString(),
          'Accept': 'application/json',
        },
      ),
    );
    final data = resp.data as Map<String, dynamic>;
    _accessToken = data['access_token'] as String;
    final expiresAt = data['expires_at'];
    _tokenExpiresAt = expiresAt is int
        ? DateTime.fromMillisecondsSinceEpoch(expiresAt)
        : DateTime.now().add(const Duration(minutes: 25));
    return _accessToken!;
  }

  Future<String> _chat({
    required String systemPrompt,
    required String userMessage,
    int maxRetries = 2,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final token = await _ensureToken();
        final resp = await _dio.post(
          '${config.baseUrl}/chat/completions',
          data: {
            'model': config.model,
            'temperature': 0.4,
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userMessage},
            ],
          },
          options: Options(headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          }),
        );
        final data = resp.data as Map<String, dynamic>;
        final choices = data['choices'] as List;
        return (choices.first as Map<String, dynamic>)['message']['content']
            as String;
      } on DioException catch (e) {
        lastError = e;
        if (e.response?.statusCode == 401) {
          _accessToken = null;
          continue;
        }
        if (attempt == maxRetries) rethrow;
        await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      } catch (e) {
        lastError = e;
        if (attempt == maxRetries) rethrow;
      }
    }
    throw Exception('GigaChat request failed: $lastError');
  }

  @override
  Future<RoutineResult> generateRoutine(SkinProfile profile) async {
    final body = jsonEncode(profile.toJson());
    final raw = await _chat(
      systemPrompt: _standardSystemPrompt,
      userMessage: 'Данные пользователя:\n$body',
    );
    final cleaned = _stripFence(raw);
    final j = jsonDecode(cleaned) as Map<String, dynamic>;
    return RoutineResult.fromJson(j);
  }

  @override
  Future<DermResponse> dermAnalyze({
    required SkinProfile profile,
    required List<DermTurn> history,
  }) async {
    final payload = {
      'user_data': profile.toJson(),
      'clarification_history': history.map((t) => t.toJson()).toList(),
    };
    final raw = await _chat(
      systemPrompt: _dermSystemPrompt,
      userMessage: jsonEncode(payload),
    );
    return DermResponse.parse(raw);
  }

  static String _stripFence(String s) {
    var t = s.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '');
      if (t.endsWith('```')) t = t.substring(0, t.length - 3);
    }
    return t.trim();
  }
}

/// Mock implementation for development without API access.
class MockAIService implements AIService {
  int _dermCallCount = 0;

  @override
  Future<RoutineResult> generateRoutine(SkinProfile profile) async {
    await Future.delayed(const Duration(seconds: 2));
    return const RoutineResult(
      morning: [
        RoutineStep(
            title: 'Мягкое очищение',
            ingredients: ['Glycerin', 'Panthenol'],
            explanation: 'Гель без сульфатов — не пересушит кожу.'),
        RoutineStep(
            title: 'Увлажняющая сыворотка',
            ingredients: ['Hyaluronic Acid'],
            explanation: 'Притягивает влагу в верхние слои.'),
        RoutineStep(
            title: 'SPF 30+',
            ingredients: ['Zinc Oxide'],
            explanation: 'Базовая защита от UV.'),
      ],
      evening: [
        RoutineStep(
            title: 'Двойное очищение',
            ingredients: ['Cleansing oil', 'Foam'],
            explanation: 'Снимает SPF и загрязнения.'),
        RoutineStep(
            title: 'Активная сыворотка',
            ingredients: ['Niacinamide 5%'],
            explanation: 'Сужает поры, выравнивает тон.'),
        RoutineStep(
            title: 'Крем-барьер',
            ingredients: ['Ceramides', 'Squalane'],
            explanation: 'Восстанавливает липидный слой за ночь.'),
      ],
      warnings: ['Не сочетай ниацинамид с кислотами в одном слое.'],
      tips: ['Меняй наволочку 2 раза в неделю.'],
      skinSummary: 'Норма с тенденцией к обезвоженности.',
      confidence: 0.9,
    );
  }

  @override
  Future<DermResponse> dermAnalyze({
    required SkinProfile profile,
    required List<DermTurn> history,
  }) async {
    await Future.delayed(const Duration(milliseconds: 1400));
    _dermCallCount++;
    if (history.length < 1 && _dermCallCount < 2) {
      return const DermClarification(
        question: 'Стянутость появляется сразу после умывания или к вечеру?',
        confidence: 0.6,
      );
    }
    final base = await generateRoutine(profile);
    return DermReady(confidence: 0.92, result: base);
  }
}
