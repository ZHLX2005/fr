// lib/core/chess/p2p/widgets/chat_sheet.dart
//
// 对局对话 BottomSheet：本局历史 + 快捷语 + 文字输入 + 表情网格。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../game_kit/chat/chat_event.dart';
import '../../../game_kit/emoji/emoji_bundle.dart';
import '../../../game_kit/skin/file_resolver.dart';

const List<String> kChatQuickPhrases = [
  '加油！',
  '好棋',
  '再想一下…',
  'GG',
];

/// 弹出对话面板。
Future<void> showChatSheet(
  BuildContext context, {
  required List<ChatEvent> history,
  required String myDeviceId,
  required Map<String, String> aliases,
  required EmojiBundle bundle,
  FileResolver? fileResolver,
  required Future<void> Function(String text) onSendText,
  required Future<void> Function(String emojiId) onSendEmoji,
  bool enabled = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.52,
          minChildSize: 0.36,
          maxChildSize: 0.88,
          expand: false,
          builder: (ctx2, scrollController) => ChatSheet(
            history: history,
            myDeviceId: myDeviceId,
            aliases: aliases,
            bundle: bundle,
            fileResolver: fileResolver,
            onSendText: onSendText,
            onSendEmoji: onSendEmoji,
            enabled: enabled,
            scrollController: scrollController,
          ),
        ),
      );
    },
  );
}

class ChatSheet extends StatefulWidget {
  final List<ChatEvent> history;
  final String myDeviceId;
  final Map<String, String> aliases;
  final EmojiBundle bundle;
  final FileResolver? fileResolver;
  final Future<void> Function(String text) onSendText;
  final Future<void> Function(String emojiId) onSendEmoji;
  final bool enabled;
  final ScrollController? scrollController;

  const ChatSheet({
    super.key,
    required this.history,
    required this.myDeviceId,
    required this.aliases,
    required this.bundle,
    this.fileResolver,
    required this.onSendText,
    required this.onSendEmoji,
    this.enabled = true,
    this.scrollController,
  });

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final List<ChatEvent> _pending = [];
  bool _sending = false;
  bool _emojiOpen = false;
  DateTime? _lastSendAt;

  static const _throttle = Duration(milliseconds: 800);
  static const _maxLen = 80;

  List<ChatEvent> get _displayHistory {
    if (_pending.isEmpty) return widget.history;
    return [...widget.history, ..._pending];
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _alias(String deviceId, {required bool me}) {
    final a = widget.aliases[deviceId];
    if (a != null && a.isNotEmpty) return a;
    return me ? '我' : '对手';
  }

  void _appendLocal({required ChatKind kind, String? text, String? emojiId}) {
    final seq = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _pending.add(ChatEvent(
        id: 'local-$seq',
        kind: kind,
        from: widget.myDeviceId,
        seq: seq,
        atMs: seq,
        text: text,
        emojiId: emojiId,
      ));
    });
  }

  Future<void> _sendText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || !widget.enabled) return;
    final now = DateTime.now();
    if (_lastSendAt != null && now.difference(_lastSendAt!) < _throttle) {
      _toast('发送过快，稍后再试');
      return;
    }
    if (_sending) return;
    setState(() => _sending = true);
    _lastSendAt = now;
    try {
      await widget.onSendText(text);
      if (!mounted) return;
      _controller.clear();
      _appendLocal(kind: ChatKind.text, text: text);
    } catch (_) {
      if (!mounted) return;
      _toast('发送失败');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendEmoji(String id) async {
    if (!widget.enabled) return;
    final now = DateTime.now();
    if (_lastSendAt != null && now.difference(_lastSendAt!) < _throttle) {
      _toast('发送过快，稍后再试');
      return;
    }
    if (_sending) return;
    setState(() => _sending = true);
    _lastSendAt = now;
    try {
      await widget.onSendEmoji(id);
      if (!mounted) return;
      _appendLocal(kind: ChatKind.emoji, emojiId: id);
    } catch (_) {
      if (!mounted) return;
      _toast('表情发送失败');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = widget.bundle.entries;
    final n = _controller.text.length;

    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 8),
            child: Row(
              children: [
                Text(
                  '对话',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('收起'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _displayHistory.isEmpty
                ? Center(
                    child: Text(
                      '还没有消息\n发句「加油」或丢个表情',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    itemCount: _displayHistory.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '本局',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      final e = _displayHistory[i - 1];
                      final me = e.from == widget.myDeviceId;
                      return _HistoryRow(
                        event: e,
                        fromMe: me,
                        alias: _alias(e.from, me: me),
                        bundle: widget.bundle,
                        fileResolver: widget.fileResolver,
                        scheme: scheme,
                      );
                    },
                  ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              color: Color.alphaBlend(
                scheme.surface.withValues(alpha: 0.92),
                scheme.surfaceContainerLowest,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final p in kChatQuickPhrases)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text(p, style: const TextStyle(fontSize: 12)),
                            visualDensity: VisualDensity.compact,
                            onPressed: widget.enabled && !_sending
                                ? () => _sendText(p)
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_emojiOpen) ...[
                  const SizedBox(height: 8),
                  Container(
                    height: 148,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: entries.isEmpty
                        ? Center(
                            child: Text(
                              '暂无表情',
                              style: TextStyle(color: scheme.outline),
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(8),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 6,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                            ),
                            itemCount: entries.length,
                            itemBuilder: (context, i) {
                              final entry = entries[i];
                              final img =
                                  entry.imageProvider(widget.fileResolver);
                              return Material(
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: widget.enabled && !_sending
                                      ? () => _sendEmoji(entry.id)
                                      : null,
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: img == null
                                        ? const SizedBox.shrink()
                                        : Image(
                                            image: img,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, error, stackTrace) =>
                                                const Icon(
                                              Icons.broken_image,
                                              size: 18,
                                            ),
                                          ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton.filledTonal(
                      onPressed: () =>
                          setState(() => _emojiOpen = !_emojiOpen),
                      isSelected: _emojiOpen,
                      icon: const Icon(Icons.mood_outlined),
                      tooltip: '表情',
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        enabled: widget.enabled && !_sending,
                        minLines: 1,
                        maxLines: 3,
                        maxLength: _maxLen,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        buildCounter: (
                          context, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) =>
                            null,
                        textInputAction: TextInputAction.send,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) {
                          if (_controller.text.trim().isNotEmpty) {
                            _sendText(_controller.text);
                          }
                        },
                        decoration: InputDecoration(
                          hintText: '说点什么…',
                          filled: true,
                          fillColor: scheme.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: widget.enabled &&
                              !_sending &&
                              _controller.text.trim().isNotEmpty
                          ? () => _sendText(_controller.text)
                          : null,
                      icon: const Icon(Icons.send_rounded),
                      tooltip: '发送',
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$n / $_maxLen',
                    style: TextStyle(
                      fontSize: 11,
                      color: n >= 72 ? scheme.error : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final ChatEvent event;
  final bool fromMe;
  final String alias;
  final EmojiBundle bundle;
  final FileResolver? fileResolver;
  final ColorScheme scheme;

  const _HistoryRow({
    required this.event,
    required this.fromMe,
    required this.alias,
    required this.bundle,
    this.fileResolver,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final initial = alias.trim().isEmpty
        ? (fromMe ? '我' : '?')
        : String.fromCharCodes(alias.trim().runes.take(1)).toUpperCase();

    final av = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fromMe
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fromMe
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    );

    Widget body;
    if (event.isEmoji) {
      final img =
          bundle.byId[event.emojiId ?? '']?.imageProvider(fileResolver);
      body = Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: fromMe
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: img == null
            ? const SizedBox(width: 36, height: 36)
            : Image(image: img, width: 36, height: 36, fit: BoxFit.contain),
      );
    } else {
      body = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: fromMe
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: fromMe
              ? const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                )
              : const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
        ),
        child: Text(
          event.text ?? '',
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: fromMe ? scheme.onPrimaryContainer : scheme.onSurface,
          ),
        ),
      );
    }

    final stack = Column(
      crossAxisAlignment:
          fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            fromMe ? '我' : alias,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 2),
        body,
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            fromMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: fromMe
            ? [
                Flexible(child: stack),
                const SizedBox(width: 8),
                av,
              ]
            : [
                av,
                const SizedBox(width: 8),
                Flexible(child: stack),
              ],
      ),
    );
  }
}
