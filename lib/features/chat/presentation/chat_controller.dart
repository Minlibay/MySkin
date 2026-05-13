import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api/backend_api.dart';
import '../../catalog/domain/product.dart';
import '../domain/chat_message.dart';

class ChatState {
  const ChatState({
    this.messages = const [],
    this.sending = false,
    this.error,
  });

  final List<ChatMessage> messages;
  final bool sending;
  final String? error;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? sending,
    String? error,
    bool clearError = false,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        error: clearError ? null : (error ?? this.error),
      );
}

class ChatController extends StateNotifier<ChatState> {
  ChatController(this._api) : super(ChatState(messages: [_greeting()])) {
    // ignore: unawaited_futures
    _loadHistory();
  }

  final BackendApi _api;

  static ChatMessage _greeting() => ChatMessage(
        role: ChatRole.assistant,
        content:
            'Привет ✿ Я Лина. Спрашивай про уход, ингредиенты или просто как сегодня кожа — помогу разобраться.',
      );

  /// Pulls persisted history from the backend and replaces the greeting-only
  /// seed if anything is found. Silent on error — chat still works ephemerally.
  Future<void> _loadHistory() async {
    try {
      final items = await _api.getChatHistory();
      if (items.isEmpty || !mounted) return;
      final restored = items
          .map((j) {
            final role = j['role'] == 'user'
                ? ChatRole.user
                : ChatRole.assistant;
            final products = ((j['products'] as List?) ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(Product.fromJson)
                .toList();
            if (role == ChatRole.assistant) {
              return ChatMessage.parseAssistantReply(
                j['content'] as String? ?? '',
                products: products,
              );
            }
            return ChatMessage(
              role: ChatRole.user,
              content: j['content'] as String? ?? '',
              timestamp: DateTime.tryParse(j['created_at'] as String? ?? ''),
            );
          })
          .toList();
      state = state.copyWith(
        messages: [_greeting(), ...restored],
      );
    } catch (_) {
      // Silent — keep ephemeral chat working even when the history endpoint
      // is unreachable.
    }
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.sending) return;

    final userMsg = ChatMessage(role: ChatRole.user, content: trimmed);
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      sending: true,
      clearError: true,
    );

    try {
      final reply = await _api.chat(
        state.messages.map((m) => m.toApiJson()).toList(),
      );
      final assistantMsg = ChatMessage.parseAssistantReply(
        reply.reply,
        products: reply.products,
      );
      state = state.copyWith(
        messages: [...state.messages, assistantMsg],
        sending: false,
      );
    } catch (e) {
      state = state.copyWith(
        sending: false,
        error: _friendlyError(e),
      );
    }
  }

  Future<void> clear() async {
    state = ChatState(messages: [_greeting()]);
    try {
      await _api.clearChatHistory();
    } catch (_) {/* silent */}
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('ai_failed')) return 'Лина задумалась. Попробуй ещё раз.';
    if (s.contains('network') || s.contains('SocketException')) {
      return 'Нет связи. Проверь интернет.';
    }
    return 'Что-то пошло не так. Попробуй ещё раз.';
  }
}

final chatControllerProvider =
    StateNotifierProvider.autoDispose<ChatController, ChatState>((ref) {
  return ChatController(ref.watch(backendApiProvider));
});
