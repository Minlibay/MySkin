import 'ai_client.dart';
import 'repos.dart';

/// Picks the active AI provider per call based on the `ai_provider` row in
/// `app_settings`. Admin can flip providers live without restarting the
/// backend — the next chat / scan call reads the fresh setting.
///
/// Also resolves provider-specific model overrides from app_settings
/// (`gigachat_chat_model`, `qwen_chat_model`, etc.) so handlers stay
/// provider-agnostic: they call `ai.chat(...)` without looking up models
/// themselves.
class AiRouter implements AiClient {
  AiRouter({
    required this.gigachat,
    this.qwen,
    required this.settings,
  });

  final AiClient gigachat;
  final AiClient? qwen;
  final AppSettingsRepository settings;

  @override
  String get chatModel => gigachat.chatModel;
  @override
  String get visionModel => gigachat.visionModel;
  @override
  String get providerId => 'router';

  Future<AiClient> _pickProvider() async {
    final pref = await settings.get('ai_provider');
    if (pref == 'qwen' && qwen != null) return qwen!;
    return gigachat;
  }

  Future<String> _resolveChatModel(AiClient p) async {
    final key = '${p.providerId}_chat_model';
    return (await settings.get(key))?.trim().isNotEmpty == true
        ? (await settings.get(key))!.trim()
        : p.chatModel;
  }

  Future<String> _resolveVisionModel(AiClient p) async {
    final key = '${p.providerId}_vision_model';
    return (await settings.get(key))?.trim().isNotEmpty == true
        ? (await settings.get(key))!.trim()
        : p.visionModel;
  }

  @override
  Future<String> chat({
    required String systemPrompt,
    required String userMessage,
    double temperature = 0.4,
    int maxRetries = 2,
    String? model,
  }) async {
    final p = await _pickProvider();
    return p.chat(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
      temperature: temperature,
      maxRetries: maxRetries,
      model: model ?? await _resolveChatModel(p),
    );
  }

  @override
  Future<String> chatWithMessages({
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.6,
    int maxRetries = 2,
    String? model,
  }) async {
    final p = await _pickProvider();
    return p.chatWithMessages(
      systemPrompt: systemPrompt,
      messages: messages,
      temperature: temperature,
      maxRetries: maxRetries,
      model: model ?? await _resolveChatModel(p),
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
  }) async {
    final p = await _pickProvider();
    return p.analyzePhoto(
      systemPrompt: systemPrompt,
      userText: userText,
      photoBytes: photoBytes,
      mime: mime,
      temperature: temperature,
      model: model ?? await _resolveVisionModel(p),
    );
  }
}
