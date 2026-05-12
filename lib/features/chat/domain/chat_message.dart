import 'dart:convert';

import '../../catalog/domain/product.dart';

enum ChatRole { user, assistant }

class ChatAction {
  const ChatAction({required this.label, this.primary = false});
  final String label;
  final bool primary;

  factory ChatAction.fromJson(Map<String, dynamic> j) => ChatAction(
        label: j['label'] as String? ?? '',
        primary: j['primary'] as bool? ?? false,
      );
}

class ChatCardItem {
  const ChatCardItem({required this.icon, required this.text});
  final String icon;
  final String text;

  factory ChatCardItem.fromJson(Map<String, dynamic> j) => ChatCardItem(
        icon: j['ic'] as String? ?? '✿',
        text: j['t'] as String? ?? '',
      );
}

class ChatCard {
  const ChatCard({
    required this.title,
    required this.items,
    this.cta,
  });

  final String title;
  final List<ChatCardItem> items;
  final String? cta;

  factory ChatCard.fromJson(Map<String, dynamic> j) => ChatCard(
        title: j['title'] as String? ?? '',
        items: ((j['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ChatCardItem.fromJson)
            .toList(),
        cta: j['cta'] as String?,
      );
}

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    this.actions = const [],
    this.card,
    this.products = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final ChatRole role;
  /// Plain text payload — used for both display and serialisation back to API.
  final String content;
  final List<ChatAction> actions;
  final ChatCard? card;
  /// Products surfaced by the backend alongside this assistant message
  /// (top matches from catalog vs. user profile).
  final List<Product> products;
  final DateTime timestamp;

  bool get isUser => role == ChatRole.user;
  bool get hasRichContent =>
      actions.isNotEmpty || card != null || products.isNotEmpty;

  Map<String, String> toApiJson() => {
        'role': role == ChatRole.user ? 'user' : 'assistant',
        'content': content,
      };

  /// Best-effort parse of Лина's reply. Tries to read JSON `{text, actions?, card?}`,
  /// falls back to treating the whole string as plain text.
  factory ChatMessage.parseAssistantReply(
    String raw, {
    List<Product> products = const [],
  }) {
    final cleaned = _stripFence(raw.trim());
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {
      json = null;
    }
    if (json == null || json['text'] is! String) {
      return ChatMessage(
        role: ChatRole.assistant,
        content: raw.trim(),
        products: products,
      );
    }
    final actions = ((json['actions'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatAction.fromJson)
        .where((a) => a.label.isNotEmpty)
        .toList();
    final cardJson = json['card'];
    final card = (cardJson is Map<String, dynamic>)
        ? ChatCard.fromJson(cardJson)
        : null;
    return ChatMessage(
      role: ChatRole.assistant,
      content: (json['text'] as String).trim(),
      actions: actions,
      card: (card != null && card.items.isNotEmpty) ? card : null,
      products: products,
    );
  }

  static String _stripFence(String s) {
    if (s.startsWith('```')) {
      var t = s.replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '');
      if (t.endsWith('```')) t = t.substring(0, t.length - 3);
      return t.trim();
    }
    return s;
  }
}
