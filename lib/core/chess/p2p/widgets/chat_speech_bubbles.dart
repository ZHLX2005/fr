// lib/core/chess/p2p/widgets/chat_speech_bubbles.dart
//
// 贴头像对话框：从 PlayerStrip 旁弹出，~3s 后消失。
// 合并 text + emoji（emoji 需 EmojiBundle 解析图）。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../game_kit/chat/chat_event.dart';
import '../../../game_kit/emoji/emoji_bundle.dart';
import '../../../game_kit/skin/file_resolver.dart';

/// 头像旁短暂气泡栈（IgnorePointer）。
class ChatSpeechBubbles extends StatefulWidget {
  final List<ChatEvent> events;
  final String myDeviceId;
  final bool forMe;
  final EmojiBundle bundle;
  final FileResolver? fileResolver;
  final Duration displayDuration;
  final int maxVisible;
  final ValueChanged<bool>? onSpeakingChanged;

  const ChatSpeechBubbles({
    super.key,
    required this.events,
    required this.myDeviceId,
    required this.forMe,
    required this.bundle,
    this.fileResolver,
    this.displayDuration = const Duration(seconds: 3),
    this.maxVisible = 2,
    this.onSpeakingChanged,
  });

  @override
  State<ChatSpeechBubbles> createState() => _ChatSpeechBubblesState();
}

class _Active {
  final ChatEvent event;
  final ImageProvider? image;
  final int seqKey;

  _Active({required this.event, this.image, required this.seqKey});
}

class _ChatSpeechBubblesState extends State<ChatSpeechBubbles> {
  final Set<String> _seen = {};
  final List<_Active> _bubbles = [];
  final Map<int, Timer> _timers = {};

  @override
  void initState() {
    super.initState();
    _ingest(widget.events);
  }

  @override
  void didUpdateWidget(covariant ChatSpeechBubbles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.myDeviceId != widget.myDeviceId ||
        oldWidget.forMe != widget.forMe) {
      _seen.clear();
    }
    _ingest(widget.events);
  }

  void _ingest(List<ChatEvent> events) {
    if (events.isEmpty && _seen.isNotEmpty) {
      _seen.clear();
    }

    var changed = false;
    for (final e in events) {
      final fromMe = e.from.isNotEmpty && e.from == widget.myDeviceId;
      if (fromMe != widget.forMe) continue;

      final key = '${e.kind.name}:${e.id}:${e.seq}';
      if (_seen.contains(key)) continue;
      _seen.add(key);

      ImageProvider? img;
      if (e.isEmoji) {
        final entry = widget.bundle.byId[e.emojiId ?? ''];
        img = entry?.imageProvider(widget.fileResolver);
        if (img == null) continue;
      } else if (e.text == null || e.text!.isEmpty) {
        continue;
      }

      final seqKey = key.hashCode;
      _bubbles.add(_Active(event: e, image: img, seqKey: seqKey));
      while (_bubbles.length > widget.maxVisible) {
        final oldest = _bubbles.removeAt(0);
        _timers.remove(oldest.seqKey)?.cancel();
      }
      _timers[seqKey]?.cancel();
      _timers[seqKey] = Timer(widget.displayDuration, () {
        if (!mounted) return;
        setState(() {
          _bubbles.removeWhere((b) => b.seqKey == seqKey);
          _timers.remove(seqKey);
        });
        _notifySpeaking();
      });
      changed = true;
    }
    if (changed) {
      setState(() {});
      _notifySpeaking();
    }
  }

  void _notifySpeaking() {
    widget.onSpeakingChanged?.call(_bubbles.isNotEmpty);
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bubbles.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in _bubbles)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: IgnorePointer(
              child: _SpeechBubble(
                event: b.event,
                image: b.image,
                fromMe: widget.forMe,
                scheme: scheme,
              ),
            ),
          ),
      ],
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  final ChatEvent event;
  final ImageProvider? image;
  final bool fromMe;
  final ColorScheme scheme;

  const _SpeechBubble({
    required this.event,
    required this.image,
    required this.fromMe,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final bg = fromMe ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final radius = fromMe
        ? const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomRight: Radius.circular(14),
            bottomLeft: Radius.circular(4),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(14),
            bottomRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
          );

    final child = event.isEmoji && image != null
        ? SizedBox(
            width: 48,
            height: 48,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Image(
                image: image!,
                fit: BoxFit.contain,
                errorBuilder: (_, error, stackTrace) => const SizedBox.shrink(),
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Text(
              event.text ?? '',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: fromMe
                    ? scheme.onPrimaryContainer
                    : scheme.onSurface,
              ),
            ),
          );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -4,
            top: event.isEmoji ? 18 : 12,
            child: Transform.rotate(
              angle: 0.785398, // 45°
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: bg,
                  border: Border(
                    left: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                    bottom: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(maxWidth: 220),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
              border: Border.all(
                color: fromMe
                    ? scheme.primary.withValues(alpha: 0.18)
                    : scheme.outlineVariant.withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}
