// lib/core/game_kit/emoji/emoji_button.dart
//
// Chess AppBar emoji 按钮（Track B 最小集成）。
//
// 职责：
//   · 惰性加载 EmojiBundle.forGame('chess')
//   · 展示 IconButton（未就绪时仍可点，面板内显示内置 24 兜底）
//   · 点开 BottomSheet 选表情 → 发 EMOJI
//   · 本按钮不直接渲染 overlay（overlay 由 ChessRoomPage 顶层 Stack 挂载 EmojiOverlay）

import 'package:flutter/material.dart';

import '../../../api/goframe/goframe_config.dart';
import '../skin/file_resolver.dart';
import 'emoji_bundle.dart';
import 'emoji_panel.dart';

class EmojiButton extends StatefulWidget {
  /// p2p 房间句柄的 applyAction 回调（由 ChessRoomPage 注入）.
  ///
  /// 签名保持与 RoomHandle.applyAction 对齐：
  /// `Future<void> Function({required String type, required Map<String,dynamic> params})`
  final Future<void> Function({required String type, required Map<String, dynamic> params}) applyAction;

  /// emoji bundle（若外层已加载可直接传入，避免重复拉 KV）。
  final EmojiBundle? bundle;

  /// FileResolver（与 bundle 同源）。
  final FileResolver? fileResolver;

  /// gameId（用于 forGame；默认 chess）。
  final String gameId;

  /// 是否启用（feature flag；默认 true 即 Track B 总开）。
  final bool enabled;

  const EmojiButton({
    super.key,
    required this.applyAction,
    this.bundle,
    this.fileResolver,
    this.gameId = 'chess',
    this.enabled = true,
  });

  @override
  State<EmojiButton> createState() => _EmojiButtonState();
}

class _EmojiButtonState extends State<EmojiButton> {
  EmojiBundle? _bundle;
  FileResolver? _resolver;
  bool _loading = false;

  EmojiBundle get _effectiveBundle => _bundle ?? widget.bundle ?? EmojiBundle.builtin();

  FileResolver get _effectiveResolver =>
      _resolver ??
      widget.fileResolver ??
      PublicFileResolver(baseUrl: GoframeConfig.baseUrl);

  Future<void> _ensureBundle() async {
    if (widget.bundle != null) {
      _bundle = widget.bundle;
      return;
    }
    if (_bundle != null) return;
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final b = await EmojiBundle.forGame(
        widget.gameId,
        fileResolver: widget.fileResolver,
        defaultBaseUrl: GoframeConfig.baseUrl,
      );
      if (!mounted) return;
      setState(() => _bundle = b);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPanel() async {
    if (!widget.enabled) return;
    await _ensureBundle();
    if (!mounted) return;
    final bundle = _effectiveBundle;
    final resolver = _effectiveResolver;
    await showEmojiPanel(
      context,
      bundle: bundle,
      fileResolver: resolver,
      onPick: (emojiId) => widget.applyAction(
        type: 'EMOJI',
        params: {'emoji_id': emojiId},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    return IconButton(
      icon: _loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.mood_outlined),
      onPressed: _openPanel,
      tooltip: '表情',
    );
  }
}
