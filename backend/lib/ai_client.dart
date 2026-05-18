/// Provider-agnostic interface every AI backend (GigaChat, Qwen, future ones)
/// implements. Handler code talks to this so swapping providers is a single
/// app_settings flip — no code changes per call site.
abstract class AiClient {
  /// Default text-only chat model name. Used when caller doesn't pass one.
  String get chatModel;
  /// Default multimodal model name (must accept image input).
  String get visionModel;
  /// Stable identifier for this provider — used by AiRouter to look up
  /// provider-specific app_settings (e.g. `qwen_chat_model`).
  String get providerId;

  /// Single-turn convenience wrapper.
  Future<String> chat({
    required String systemPrompt,
    required String userMessage,
    double temperature = 0.4,
    int maxRetries = 2,
    String? model,
  });

  /// Multi-turn conversation. [messages] is a list of `{role, content}` —
  /// `role` is one of `user` or `assistant`.
  Future<String> chatWithMessages({
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.6,
    int maxRetries = 2,
    String? model,
  });

  /// Sends a JPEG/PNG to the vision model along with [userText] and returns
  /// the raw model reply (typically JSON, parsed by caller). Implementations
  /// can either upload-then-reference or inline the image as base64.
  Future<String> analyzePhoto({
    required String systemPrompt,
    required String userText,
    required List<int> photoBytes,
    String mime = 'image/jpeg',
    double temperature = 0.2,
    String? model,
  });
}

/// Common exception type. Provider-specific exceptions (GigaChatException,
/// QwenException) subclass this so catch-blocks can be written against the
/// interface, not the concrete client.
class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => 'AiException: $message';
}
