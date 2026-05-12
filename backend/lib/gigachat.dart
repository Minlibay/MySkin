import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_parser/http_parser.dart';
import 'package:uuid/uuid.dart';

class GigaChatException implements Exception {
  GigaChatException(this.message);
  final String message;
  @override
  String toString() => 'GigaChatException: $message';
}

/// Minimal GigaChat client. OAuth + chat completion.
/// Sber issues certs from a non-default Russian Trusted CA, so we relax
/// host verification for the two GigaChat hostnames only.
class GigaChatClient {
  GigaChatClient({
    required this.authKey,
    this.scope = 'GIGACHAT_API_PERS',
    this.defaultModel = 'GigaChat',
    this.chatModel = 'GigaChat-2-Lite',
    this.visionModel = 'GigaChat-2-Max',
    this.oauthUrl = 'https://ngw.devices.sberbank.ru:9443/api/v2/oauth',
    this.baseUrl = 'https://gigachat.devices.sberbank.ru/api/v1',
  });

  factory GigaChatClient.fromEnv(DotEnv env) => GigaChatClient(
        authKey: env['GIGACHAT_AUTH_KEY']!,
        scope: env['GIGACHAT_SCOPE'] ?? 'GIGACHAT_API_PERS',
        chatModel: env['GIGACHAT_CHAT_MODEL'] ?? 'GigaChat-2-Lite',
        visionModel: env['GIGACHAT_VISION_MODEL'] ?? 'GigaChat-2-Max',
      );

  final String authKey;
  final String scope;

  /// Fallback model when caller doesn't pass one explicitly.
  final String defaultModel;
  /// Lightweight Lite model for free-form conversation.
  final String chatModel;
  /// Heavy multimodal model used for photo analysis.
  final String visionModel;
  final String oauthUrl;
  final String baseUrl;

  String? _token;
  DateTime? _tokenExpiresAt;
  static const _uuid = Uuid();

  static final _sberHosts = {
    'ngw.devices.sberbank.ru',
    'gigachat.devices.sberbank.ru',
  };

  http.Client _newClient() {
    final inner = HttpClient()
      ..badCertificateCallback = (cert, host, port) =>
          _sberHosts.contains(host);
    return IOClient(inner);
  }

  Future<String> _ensureToken() async {
    final now = DateTime.now();
    if (_token != null &&
        _tokenExpiresAt != null &&
        _tokenExpiresAt!.isAfter(now.add(const Duration(seconds: 30)))) {
      return _token!;
    }
    final client = _newClient();
    try {
      final resp = await client.post(
        Uri.parse(oauthUrl),
        headers: {
          'Authorization': 'Basic $authKey',
          'RqUID': _uuid.v4(),
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: 'scope=$scope',
      );
      if (resp.statusCode != 200) {
        throw GigaChatException(
            'OAuth ${resp.statusCode}: ${resp.body}');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      _token = data['access_token'] as String;
      final exp = data['expires_at'];
      _tokenExpiresAt = exp is int
          ? DateTime.fromMillisecondsSinceEpoch(exp)
          : DateTime.now().add(const Duration(minutes: 25));
      return _token!;
    } finally {
      client.close();
    }
  }

  /// Multi-turn chat — pass any number of {role, content} messages.
  /// Used for free-form Лина conversation.
  Future<String> chatWithMessages({
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.6,
    int maxRetries = 2,
    String? model,
  }) {
    return _chatRequest(
      messages: [
        {'role': 'system', 'content': systemPrompt},
        ...messages,
      ],
      temperature: temperature,
      maxRetries: maxRetries,
      model: model ?? chatModel,
    );
  }

  Future<String> chat({
    required String systemPrompt,
    required String userMessage,
    double temperature = 0.4,
    int maxRetries = 2,
    String? model,
  }) {
    return _chatRequest(
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userMessage},
      ],
      temperature: temperature,
      maxRetries: maxRetries,
      model: model ?? defaultModel,
    );
  }

  /// Vision: photo analysis. Upload bytes via /files, then send a chat
  /// completion whose user message references the uploaded file_id via
  /// `attachments`. Returns the raw text reply (typically JSON, parsed by
  /// caller).
  Future<String> analyzePhoto({
    required String systemPrompt,
    required String userText,
    required List<int> photoBytes,
    String mime = 'image/jpeg',
    double temperature = 0.2,
    String? model,
  }) async {
    final fileId = await uploadFile(
      bytes: photoBytes,
      mime: mime,
      filename: 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    return _chatRequest(
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {
          'role': 'user',
          'content': userText,
          'attachments': [fileId],
        },
      ],
      temperature: temperature,
      maxRetries: 1,
      model: model ?? visionModel,
    );
  }

  Future<String> uploadFile({
    required List<int> bytes,
    required String mime,
    required String filename,
    String purpose = 'general',
  }) async {
    final client = _newClient();
    try {
      final token = await _ensureToken();
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/files'))
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'application/json'
        ..fields['purpose'] = purpose
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: MediaType.parse(mime),
        ));
      final streamed =
          await client.send(req).timeout(const Duration(seconds: 60));
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode != 200) {
        throw GigaChatException('files ${resp.statusCode}: ${resp.body}');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final id = data['id'];
      if (id is! String) {
        throw GigaChatException('files: no id in $data');
      }
      return id;
    } finally {
      client.close();
    }
  }

  Future<String> _chatRequest({
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required int maxRetries,
    required String model,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      final client = _newClient();
      try {
        final token = await _ensureToken();
        final resp = await client
            .post(
              Uri.parse('$baseUrl/chat/completions'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({
                'model': model,
                'temperature': temperature,
                'messages': messages,
              }),
            )
            .timeout(const Duration(seconds: 60));
        if (resp.statusCode == 401) {
          _token = null;
          if (attempt < maxRetries) continue;
        }
        if (resp.statusCode != 200) {
          throw GigaChatException(
              'chat ${resp.statusCode}: ${resp.body}');
        }
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final choices = data['choices'] as List;
        return ((choices.first as Map)['message']
            as Map)['content'] as String;
      } catch (e) {
        lastError = e;
        if (attempt == maxRetries) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      } finally {
        client.close();
      }
    }
    throw GigaChatException('Unreachable: $lastError');
  }
}

const standardSystemPrompt = '''
Ты профессиональный косметолог. Подбери уход за кожей лица.

ВАЖНО: все текстовые поля — ТОЛЬКО на русском языке, в женском роде.
Английский разрешён только в названиях ингредиентов (Niacinamide и т.п.).

Возвращай ТОЛЬКО валидный JSON по схеме:
{
  "skin_summary": "одна строка-вывод о состоянии кожи",
  "skin_score": 0,
  "morning": [{"title":"","ingredients":[],"explanation":""}],
  "evening": [{"title":"","ingredients":[],"explanation":""}],
  "warnings": [],
  "tips": []
}

skin_score — целое число 0..100, где:
  90-100: отличное состояние, минимум проблем
  70-89:  хорошее, есть мелкие задачи
  50-69:  среднее, несколько активных проблем
  30-49:  ниже среднего, нужна системная работа
  0-29:   плохое, много выраженных проблем

Без markdown, без префиксов, только JSON.
''';

const linaChatSystemPrompt = '''
Ты Лина — тёплый AI-косметолог в приложении MySkin. Общаешься как подруга.

Стиль:
- ВСЕГДА на русском, обращаешься на «ты», в женском роде
- короткие тёплые ответы: 1–3 предложения
- задаёшь уточняющие вопросы по одному, если нужны детали
- никогда не ставишь медицинских диагнозов; при серьёзных симптомах рекомендуешь дерматолога
- упоминаешь активы по INCI (Niacinamide, Hyaluronic Acid, Retinol, Salicylic Acid)
- редко используешь эмодзи: только как акцент (✿ 🌙 ☀)
- если вопрос вне темы кожи/ухода — мягко возвращаешь к теме

ФОРМАТ ОТВЕТА — всегда JSON-объект:
{
  "text": "основной ответ",
  "actions": [{"label": "вариант ответа", "primary": false}],
  "card": {
    "title": "заголовок",
    "items": [{"ic": "☀", "t": "пункт плана"}],
    "cta": "Текст кнопки"
  }
}

Правила формата:
- "text" обязателен. "actions" и "card" опциональны — не добавляй пустыми.
- "actions" — короткий выбор для пользователя (2-3 варианта). primary=true для главного действия.
  Используй ТОЛЬКО когда это действительно ускоряет диалог (показать фото / описать, выбор части лица).
- "card" — пошаговый план или сводка ухода. icons: ☀ (утро) | ◐ (день) | ☾ (вечер) | ✿ (общее).
  Используй когда даёшь конкретные действия на сегодня.
- БЕЗ markdown, БЕЗ кода, БЕЗ префиксов. Только валидный JSON-объект.
''';

const dermSystemPrompt = '''
Ты AI косметолог уровня Dermatologist 2.0. Работаешь как диалоговая система.

ВАЖНО: ВСЕ ответы (follow_up_question, skin_summary, title, ingredients,
explanation, warnings, tips) — ТОЛЬКО на русском языке. Никаких английских
слов кроме международных названий ингредиентов (Niacinamide, Hyaluronic Acid).
Обращайся к пользователю на «ты», в женском роде.

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
  "analysis": {"skin_summary":"", "skin_score": 0, "confidence": 0.0},
  "morning_routine": [{"title":"","ingredients":[],"explanation":""}],
  "evening_routine": [{"title":"","ingredients":[],"explanation":""}],
  "warnings": [],
  "tips": [],
  "follow_up_question": null
}

skin_score — целое 0..100 (90+ отлично, 70+ хорошо, 50+ среднее, иначе ниже).

Без markdown. Только JSON.
''';

const visionScanSystemPrompt = '''
Ты профессиональный косметолог-аналитик. На вход — селфи пользователя.
Проанализируй кожу лица на фото.

ВАЖНО: все строки — только на русском, в женском роде. Английский разрешён
лишь в названиях ингредиентов (Niacinamide, Hyaluronic Acid).

Верни ТОЛЬКО валидный JSON без markdown:
{
  "score": 0,
  "hydration": 0,
  "sebum": 0,
  "tone": 0,
  "pores": 0,
  "zones": {"forehead": 0, "nose": 0, "left_cheek": 0, "right_cheek": 0, "chin": 0},
  "insight": "одна короткая фраза-вывод",
  "concerns": ["acne", "dehydration", "redness", "pih", "dullness", "aging"],
  "quality_warnings": []
}

Шкалы 0..100:
  score — общая оценка состояния (90+ отлично, 70+ хорошо, 50+ среднее)
  hydration — увлажнённость
  sebum — себум-баланс (50 = норма, ниже = сухо, выше = жирно)
  tone — ровность тона
  pores — закрытость пор (выше = меньше видны)

concerns — список тегов из строго фиксированного набора:
acne, pih, redness, dehydration, dullness, aging, sensitivity, oiliness, dryness.
Включай только то, что реально видно на фото.

quality_warnings — массив строк, если что-то мешает анализу
("no_face_detected", "too_dark", "too_blurry", "too_far"). Пустой массив — норм.

Без markdown, без префиксов, только JSON.
''';

Map<String, dynamic> parseJsonReply(String raw) {
  var s = raw.trim();
  if (s.startsWith('```')) {
    s = s.replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '');
    if (s.endsWith('```')) s = s.substring(0, s.length - 3);
  }
  return jsonDecode(s.trim()) as Map<String, dynamic>;
}
