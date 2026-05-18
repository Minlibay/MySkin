import 'dart:convert';

import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;

import 'ai_client.dart';

class QwenException extends AiException {
  QwenException(super.message);
  @override
  String toString() => 'QwenException: $message';
}

/// Alibaba Qwen client via DashScope's OpenAI-compatible endpoint.
///
/// Two regions: International (`dashscope-intl.aliyuncs.com`, defaults here
/// — works from RF without VPN) and China (`dashscope.aliyuncs.com`, lower
/// latency from CIS but blocked in some networks). Pick via env or the
/// `baseUrl` ctor arg.
///
/// Auth is a Bearer token (`DASHSCOPE_API_KEY`). Vision is sent inline as a
/// base64 data URL on the user message, so there's no separate upload step.
class QwenClient implements AiClient {
  QwenClient({
    required this.apiKey,
    this.chatModel = 'qwen-plus',
    this.visionModel = 'qwen-vl-max',
    this.baseUrl = 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
  });

  factory QwenClient.fromEnv(DotEnv env) => QwenClient(
        apiKey: env['DASHSCOPE_API_KEY']!,
        chatModel: env['QWEN_CHAT_MODEL'] ?? 'qwen-plus',
        visionModel: env['QWEN_VISION_MODEL'] ?? 'qwen-vl-max',
        baseUrl: env['DASHSCOPE_BASE_URL'] ??
            'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
      );

  final String apiKey;
  @override
  final String chatModel;
  @override
  final String visionModel;
  final String baseUrl;

  @override
  String get providerId => 'qwen';

  @override
  Future<String> chat({
    required String systemPrompt,
    required String userMessage,
    double temperature = 0.4,
    int maxRetries = 2,
    String? model,
  }) {
    return _completion(
      model: model ?? chatModel,
      temperature: temperature,
      maxRetries: maxRetries,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userMessage},
      ],
    );
  }

  @override
  Future<String> chatWithMessages({
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.6,
    int maxRetries = 2,
    String? model,
  }) {
    return _completion(
      model: model ?? chatModel,
      temperature: temperature,
      maxRetries: maxRetries,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        ...messages,
      ],
    );
  }

  @override
  Future<String> analyzePhoto({
    required String systemPrompt,
    required String userText,
    required List<int> photoBytes,
    String mime = 'image/jpeg',
    double temperature = 0.2,
    String? model,
  }) {
    // Vision messages use OpenAI-style content blocks. Image first then text
    // is the convention DashScope recommends — vision tokens attend to text
    // that follows.
    final dataUrl = 'data:$mime;base64,${base64Encode(photoBytes)}';
    return _completion(
      model: model ?? visionModel,
      temperature: temperature,
      maxRetries: 1,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {'url': dataUrl},
            },
            {'type': 'text', 'text': userText},
          ],
        },
      ],
    );
  }

  Future<String> _completion({
    required String model,
    required double temperature,
    required int maxRetries,
    required List<Map<String, dynamic>> messages,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final resp = await http
            .post(
              Uri.parse('$baseUrl/chat/completions'),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({
                'model': model,
                'temperature': temperature,
                'messages': messages,
              }),
            )
            .timeout(const Duration(seconds: 90));
        if (resp.statusCode != 200) {
          // 429 / 5xx → retry; everything else → bail with the body so the
          // admin can see the actual error (auth, quota, model-not-found).
          if ((resp.statusCode == 429 || resp.statusCode >= 500) &&
              attempt < maxRetries) {
            await Future.delayed(
                Duration(milliseconds: 600 * (attempt + 1)));
            continue;
          }
          throw QwenException('chat ${resp.statusCode}: ${resp.body}');
        }
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final choices = data['choices'] as List;
        final msg = (choices.first as Map)['message'] as Map;
        final content = msg['content'];
        if (content is String) return content;
        // Vision responses sometimes come back as an array of content blocks
        // when the model emits both text and structured data; join the text
        // bits in order so callers still get a single string.
        if (content is List) {
          return content
              .whereType<Map>()
              .map((b) => b['text'])
              .whereType<String>()
              .join('\n');
        }
        throw QwenException('chat: unexpected content shape: $content');
      } catch (e) {
        lastError = e;
        if (attempt == maxRetries) rethrow;
        await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
    }
    throw QwenException('Unreachable: $lastError');
  }
}
