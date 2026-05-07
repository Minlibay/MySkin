import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/lina_avatar.dart';
import '../domain/chat_message.dart';
import 'chat_controller.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _listening = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await ref.read(chatControllerProvider.notifier).send(text);
    _scrollToBottom();
  }

  Future<void> _onActionTap(String label) async {
    if (ref.read(chatControllerProvider).sending) return;
    await ref.read(chatControllerProvider.notifier).send(label);
    _scrollToBottom();
  }

  void _showAttachSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.dividerStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.center_focus_strong_rounded,
                  color: AppColors.roseDeep),
              title: Text('Сделать скан кожи', style: AppTypography.body),
              subtitle: Text(
                'Лина увидит метрики и зоны',
                style: AppTypography.caption.copyWith(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                ref
                    .read(chatControllerProvider.notifier)
                    .send('Хочу показать кожу — сделать скан.');
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.science_outlined, color: AppColors.roseDeep),
              title: Text('Спросить про состав',
                  style: AppTypography.body),
              subtitle: Text(
                'Вставь INCI и спроси можно ли сочетать',
                style: AppTypography.caption.copyWith(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _focus.requestFocus();
                _input.text = 'Можно ли сочетать ';
                _input.selection = TextSelection.collapsed(
                    offset: _input.text.length);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.warning),
              title: Text('Очистить чат', style: AppTypography.body),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(chatControllerProvider.notifier).clear();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _toggleMic() {
    // Speech recognition is a separate native dep that breaks on web. For now
    // surface a hint and let the user know it's coming.
    setState(() => _listening = !_listening);
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _listening = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Голосовой ввод подключим в native-сборке.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatControllerProvider, (prev, next) {
      if (prev?.messages.length != next.messages.length || next.sending) {
        _scrollToBottom();
      }
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!)),
        );
      }
    });
    final state = ref.watch(chatControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _Header(
            onBack: widget.onBack,
            onClear: () =>
                ref.read(chatControllerProvider.notifier).clear(),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(
                  20, AppSpacing.sm, 20, AppSpacing.md),
              itemCount: state.messages.length + (state.sending ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == state.messages.length && state.sending) {
                  return const _TypingBubble();
                }
                if (i == 0 ||
                    !_sameDay(
                      state.messages[i - 1].timestamp,
                      state.messages[i].timestamp,
                    )) {
                  return Column(
                    children: [
                      _DayDivider(date: state.messages[i].timestamp),
                      _Bubble(
                        message: state.messages[i],
                        onAction: _onActionTap,
                      ),
                    ],
                  );
                }
                return _Bubble(
                  message: state.messages[i],
                  onAction: _onActionTap,
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _InputBar(
                controller: _input,
                focus: _focus,
                onSend: _send,
                onAttach: _showAttachSheet,
                onMic: _toggleMic,
                busy: state.sending,
                listening: _listening,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack, required this.onClear});
  final VoidCallback onBack;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 8, 16, 12),
      decoration: const BoxDecoration(
        color: Color(0xD9FFF9FB),
        border: Border(
          bottom: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Material(
              color: Colors.white.withOpacity(0.8),
              shape: const CircleBorder(
                  side: BorderSide(color: AppColors.divider)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onBack,
                child: const Icon(Icons.arrow_back_ios_new, size: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const LinaAvatar(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Лина',
                    style: AppTypography.h2.copyWith(fontSize: 19)),
                Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'твой AI-помощник',
                      style: AppTypography.caption.copyWith(
                          fontSize: 11, color: AppColors.success),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded,
                color: AppColors.textSecondary),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            onSelected: (v) {
              if (v == 'clear') onClear();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'clear',
                child: Text('Очистить чат'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = now.year == date.year &&
        now.month == date.month &&
        now.day == date.day;
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    final label = isToday
        ? 'Сегодня · $hh:$mm'
        : '${date.day}.${date.month.toString().padLeft(2, '0')} · $hh:$mm';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          label.toUpperCase(),
          style: AppTypography.eyebrow().copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onAction});
  final ChatMessage message;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final maxW = MediaQuery.of(context).size.width * 0.86;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? AppColors.textPrimary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 20),
                ),
                border: isUser ? null : Border.all(color: AppColors.divider),
              ),
              child: Text(
                message.content,
                style: AppTypography.body.copyWith(
                  fontSize: 15,
                  color: isUser ? Colors.white : AppColors.textPrimary,
                  height: 1.45,
                ),
              ),
            ),
            if (message.actions.isNotEmpty)
              _ActionsRow(
                actions: message.actions,
                onTap: onAction,
              ),
            if (message.card != null)
              _PlanCard(card: message.card!, onApply: onAction),
          ],
        ),
      ),
    );
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({required this.actions, required this.onTap});
  final List<ChatAction> actions;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: actions
            .map(
              (a) => Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => onTap(a.label),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: a.primary
                          ? AppColors.roseDeep
                          : Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(99),
                      border: a.primary
                          ? null
                          : Border.all(color: AppColors.dividerStrong),
                    ),
                    child: Text(
                      a.label,
                      style: AppTypography.bodySm.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color:
                            a.primary ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.card, required this.onApply});
  final ChatCard card;
  final ValueChanged<String> onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, AppColors.blush],
        ),
        border:
            Border.all(color: AppColors.primaryAccent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ЛИНА РЕКОМЕНДУЕТ',
            style: AppTypography.eyebrow(color: AppColors.roseDeep),
          ),
          const SizedBox(height: 4),
          Text(
            card.title,
            style: AppTypography.h3.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < card.items.length; i++) ...[
            if (i > 0)
              const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                    ),
                    child: Text(
                      card.items[i].icon,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.roseDeep,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      card.items[i].text,
                      style: AppTypography.bodySm
                          .copyWith(fontSize: 14, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (card.cta != null && card.cta!.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: AppColors.textPrimary,
                borderRadius: BorderRadius.circular(99),
                child: InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => onApply(card.cta!),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      card.cta!,
                      textAlign: TextAlign.center,
                      style: AppTypography.button.copyWith(fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
        ..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) {
                  final t = (_ctrl.value - i * 0.15) % 1.0;
                  final lift = (t < 0.3) ? (1 - (t / 0.3)) : 0.0;
                  return Transform.translate(
                    offset: Offset(0, -4 * lift),
                    child: Opacity(
                      opacity: 0.4 + 0.6 * lift,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focus,
    required this.onSend,
    required this.onAttach,
    required this.onMic,
    required this.busy,
    required this.listening,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onMic;
  final bool busy;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.dividerStrong),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryAccent.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 6),
            spreadRadius: -8,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // + attach
          IconButton(
            onPressed: onAttach,
            icon: const Icon(Icons.add_rounded,
                size: 22, color: AppColors.textSecondary),
            tooltip: 'Прикрепить',
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              maxLines: 4,
              minLines: 1,
              style: AppTypography.body.copyWith(fontSize: 15),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Спросить Лину…',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // mic
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: listening
                  ? AppColors.roseDeep
                  : AppColors.primaryAccent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : onMic,
                child: Icon(
                  listening ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 18,
                  color: listening ? Colors.white : AppColors.roseDeep,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // send
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: busy
                  ? AppColors.primaryAccent.withOpacity(0.5)
                  : AppColors.roseDeep,
              shape: BoxShape.circle,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : onSend,
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send_rounded,
                        size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
