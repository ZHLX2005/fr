// lib/core/game_kit/emoji/emoji_panel.dart
//
// Emoji grid picker — 从操作条按钮弹出，走 p2p 发送 EMOJI。
// 只展示 KV 发布的上传图（无 unicode）。

import 'dart:async';

import 'package:flutter/material.dart';

import '../skin/file_resolver.dart';
import 'emoji_bundle.dart';

/// 表情面板（网格选择器，BottomSheet 内使用）。
///
/// 点击后走 [onPick]（内部做节流），由外层发 p2p：
/// `handle.applyAction(type: 'EMOJI', params: {'emoji_id': id})`
class EmojiPanel extends StatefulWidget {
  final EmojiBundle bundle;
  final FileResolver? fileResolver;
  final Future<void> Function(String emojiId) onPick;
  final Duration throttle;

  const EmojiPanel({
    super.key,
    required this.bundle,
    this.fileResolver,
    required this.onPick,
    this.throttle = const Duration(milliseconds: 800),
  });

  @override
  State<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  bool _sending = false;
  DateTime? _lastPickAt;
  String? _lastPickedId;

  Future<void> _pick(String emojiId) async {
    final now = DateTime.now();
    if (_lastPickAt != null &&
        _lastPickedId == emojiId &&
        now.difference(_lastPickAt!) < widget.throttle) {
      return;
    }
    if (_sending) return;
    setState(() {
      _sending = true;
      _lastPickAt = now;
      _lastPickedId = emojiId;
    });
    try {
      await widget.onPick(emojiId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('表情发送失败')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.bundle.entries;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '表情',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).maybePop(),
                  tooltip: '关闭',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '暂无表情',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              )
            else
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return _EmojiCell(
                      entry: e,
                      fileResolver: widget.fileResolver,
                      onTap: () => _pick(e.id),
                      enabled: !_sending,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmojiCell extends StatelessWidget {
  final EmojiEntry entry;
  final FileResolver? fileResolver;
  final VoidCallback onTap;
  final bool enabled;

  const _EmojiCell({
    required this.entry,
    this.fileResolver,
    required this.onTap,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final img = entry.imageProvider(fileResolver);
    final Widget content = img == null
        ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Image(
            image: img,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, size: 20),
          );
    return Material(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Center(child: content),
        ),
      ),
    );
  }
}

/// 便捷：弹出表情面板（BottomSheet）。
Future<void> showEmojiPanel(
  BuildContext context, {
  required EmojiBundle bundle,
  FileResolver? fileResolver,
  required Future<void> Function(String emojiId) onPick,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx2, scrollController) => SingleChildScrollView(
        controller: scrollController,
        child: EmojiPanel(
          bundle: bundle,
          fileResolver: fileResolver,
          onPick: (id) async {
            await onPick(id);
            if (ctx2.mounted) Navigator.of(ctx2).maybePop();
          },
        ),
      ),
    ),
  );
}
