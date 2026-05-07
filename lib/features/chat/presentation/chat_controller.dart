import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api/backend_api.dart';
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
  ChatController(this._api)
      : super(ChatState(messages: [_greeting()]));

  final BackendApi _api;

  static ChatMessage _greeting() => ChatMessage(
        role: ChatRole.assistant,
        content:
            'Привет ✿ Я Лина. Спрашивай про уход, ингредиенты или просто как сегодня кожа — помогу разобраться.',
      );

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
      final assistantMsg = ChatMessage.parseAssistantReply(reply);
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

  void clear() {
    state = ChatState(messages: [_greeting()]);
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
