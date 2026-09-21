// lib/core/chess/p2p/widgets/board_chat_overlay.dart
//
// F3 落地版：棋盘 absolute 浮层（聊天区统一在左上角）
//   · 左上角：💬 入口 + 最新一条消息预览（纯静态，无渐入/缩放/位移动画）
//   · 入口点击 → 左上角原地展开 composer（双 tab 表情 / 记录 + 文字输入 + 发送）
//   · 浮层 absolute，不挤 Column flex；竖屏 board-wrap 上下留白时入口可落在格外
//
// 性能约束：F2 的卡片堆（入场 bounce / 退场 / tuck + 每帧 Matrix4Tween）已整体
// 移除 —— 每条消息挂 2 个 AnimationController、外加 TweenAnimationBuilder 逐帧
// 重建，长局下纯属额外开销。现在只保留"最新一条"预览：来消息即时显示，超时
// [BoardChatOverlay.previewDuration] 后收回纯图标态，全程零动画。
//
// 设计依据：plan/chess-chat-redesign-2026-09-07/F-card-stack.html（卡片堆已废弃）
// 替换关系：EmojiOverlay + ChatSpeechBubbles（emoji/对话悬浮）→ BoardChatOverlay
// 保留关系：ChatSheet 走"详细历史"路径（PlayerStrip trailing 上的 _ChatFab 触发）

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../game_kit/chat/chat_event.dart';
import '../../../game_kit/emoji/emoji_bundle.dart';
import '../../../game_kit/skin/file_resolver.dart';

/// 卡片内可用的快速表情（与 composer emoji 行一致）
const List<String> kBoardChatQuickEmojis = [
  '👊', '👍', '🎉', '🤔', '😤', '🤝',
];

/// _seen 集合上限：超过此值按 seen 的插入顺序淘汰最早 key。
/// 服务端 chatRing append-only，跨长局可达上千条；_seen 是去重缓存需有界。
const int _kSeenCapacity = 256;

/// 棋盘对话浮层（左上角：入口 + 最新一条预览 + 展开输入面板）
class BoardChatOverlay extends StatefulWidget {
  final List<ChatEvent> events;
  final String myDeviceId;
  final EmojiBundle emojiBundle;
  final FileResolver? fileResolver;

  /// 发送 emoji（走 EMOJI action）；由宿主（chess room）实现
  final Future<void> Function(String emojiId) onSendEmoji;

  /// 发送文字（走 CHAT action）；由宿主实现
  final Future<void> Function(String text) onSendText;

  /// 是否允许发送（终局 / 断线时关闭）
  final bool enabled;

  /// 最新消息预览可见时长（到时收回纯图标态，无动画）
  final Duration previewDuration;

  /// 发送节流
  final Duration sendThrottle;

  const BoardChatOverlay({
    super.key,
    required this.events,
    required this.myDeviceId,
    required this.emojiBundle,
    this.fileResolver,
    required this.onSendEmoji,
    required this.onSendText,
    this.enabled = true,
    this.previewDuration = const Duration(milliseconds: 3000),
    this.sendThrottle = const Duration(milliseconds: 800),
  });

  @override
  State<BoardChatOverlay> createState() => _BoardChatOverlayState();
}

class _BoardChatOverlayState extends State<BoardChatOverlay> {
  // 预览：最新一条消息；null = 只显示 💬 图标
  ChatEvent? _preview;

  // 预览超时定时器（到 previewDuration 后收回图标态）
  Timer? _previewTimer;

  // 去重缓存：FIFO，超过 _kSeenCapacity 淘汰最早
  // 注：server 端 chatRing append-only，长局可达上千条，故需有界。
  // 用 LinkedHashSet：O(1) 命中判断（List.contains 在长局下是隐性的 O(n²)），
  // 且保留插入序 → first 即最早，可用于 FIFO 淘汰。
  final Set<String> _seen = <String>{};

  // 上次 ingest 的原始列表指纹（末条 key + 长度）：append-only 列表只要这两个
  // 没变就不可能来新消息 → 直接跳过 O(n) 去重，避免每次棋盘 rebuild 都白跑。
  String? _lastIngestKey;
  int _lastIngestLen = -1;

  // 本局 ChatEvent 列表（去重后）—— 给 _Composer 记录 tab 用。
  // 每次 ingest 后刷新；_seen 同源。
  List<ChatEvent> _historyEvents = const [];

  // 草稿：composer 隐藏时保留用户输入（避免重建丢失）
  String _draftText = '';

  // composer 显隐（保持 _Composer widget 始终构造，仅切显隐，避免 state 丢失）
  bool _composerOpen = false;
  bool _sending = false;
  DateTime? _lastSendAt;

  // _Composer 共享的 TextEditingController（由 _BoardChatOverlayState 拥有）
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _textController.text = _draftText;
    _ingest(widget.events);
  }

  @override
  void didUpdateWidget(covariant BoardChatOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.myDeviceId != widget.myDeviceId) {
      _resetAllState();
    }
    _ingest(widget.events);
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 全量重置（myDeviceId 变化 / 跨局）
  void _resetAllState() {
    _previewTimer?.cancel();
    _previewTimer = null;
    _preview = null;
    _seen.clear();
    _lastIngestKey = null;
    _lastIngestLen = -1;
    _historyEvents = const [];
    _draftText = '';
    _textController.text = '';
  }

  void _ingest(List<ChatEvent> events) {
    // 跨局 / RESET：events 被清空时同步清掉预览，避免上局残影
    if (events.isEmpty) {
      if (_preview == null && _seen.isEmpty && _historyEvents.isEmpty) return;
      _previewTimer?.cancel();
      _previewTimer = null;
      _preview = null;
      _seen.clear();
      _lastIngestKey = null;
      _lastIngestLen = -1;
      _historyEvents = const [];
      return;
    }

    // 指纹未变 → 无新消息（chatRing append-only）：跳过整轮去重
    final lastKey = _keyFor(events.last);
    if (lastKey == _lastIngestKey && events.length == _lastIngestLen) return;
    _lastIngestKey = lastKey;
    _lastIngestLen = events.length;

    // 本批次最后一条合法新消息 = 预览内容；循环内不 setState，末尾单次提交
    ChatEvent? latest;
    for (final e in events) {
      final key = _keyFor(e);
      if (_seen.contains(key)) continue;
      _pushSeen(key);

      // 内容合法性校验：emoji 必须能解析到 image；文字必须非空（trim 与 ChatSpeechBubbles 对齐，拒纯空白）
      if (e.isEmoji) {
        final entry = widget.emojiBundle.byId[e.emojiId ?? ''];
        if (entry?.imageProvider(widget.fileResolver) == null) continue;
      } else if (e.text == null || e.text!.trim().isEmpty) {
        continue;
      }
      latest = e;
    }

    final history = _dedupEvents(events);

    if (latest == null) {
      // 无新消息：只在历史条数真的变了才 rebuild（长局下 events 每帧都来）
      if (history.length == _historyEvents.length) return;
      setState(() => _historyEvents = history);
      return;
    }

    // 预览刷新（同一批多条时只展示最后一条）+ 重置超时计时
    _showPreview(latest);
    setState(() => _historyEvents = history);
  }

  /// 显示最新消息预览，并重置 [BoardChatOverlay.previewDuration] 计时
  void _showPreview(ChatEvent e) {
    _preview = e;
    _previewTimer?.cancel();
    _previewTimer = Timer(widget.previewDuration, () {
      if (!mounted) return;
      setState(() => _preview = null);
    });
  }

  /// 从 append-only events 列表提取去重后的事件（保持原顺序）
  List<ChatEvent> _dedupEvents(List<ChatEvent> events) {
    final seen = <String>{};
    final out = <ChatEvent>[];
    for (final e in events) {
      if (seen.add(_keyFor(e))) out.add(e);
    }
    return out;
  }

  void _pushSeen(String key) {
    _seen.add(key);
    if (_seen.length > _kSeenCapacity) {
      _seen.remove(_seen.first); // FIFO 淘汰（LinkedHashSet 保插入序）
    }
  }

  String _keyFor(ChatEvent e) => '${e.kind.name}:${e.id}:${e.seq}';

  void _openComposer() {
    if (!widget.enabled) return;
    setState(() => _composerOpen = true);
    // 关闭时已在 _draftText 中保留文字；打开后把草稿恢复给 controller
    _textController.text = _draftText;
    // 不自动 requestFocus：一打开就抢焦点会弹 IME，发表情再 unfocus
    // 时键盘收起容易闪灰色蒙层。用户点输入框再聚焦即可。
  }

  void _closeComposer() {
    if (!mounted) return;
    _draftText = _textController.text;
    _focusNode.unfocus();
    setState(() => _composerOpen = false);
  }

  void _onComposerTextChanged(String text) {
    _draftText = text;
  }

  bool _throttled() {
    final now = DateTime.now();
    if (_lastSendAt != null && now.difference(_lastSendAt!) < widget.sendThrottle) {
      return true;
    }
    _lastSendAt = now;
    return false;
  }

  Future<void> _sendEmoji(String id) async {
    if (!widget.enabled || _sending) return;
    if (_throttled()) {
      _toast('发送过快，稍后再试');
      return;
    }
    // 先关 composer（清 barrier），再发网：避免 await 期间蒙层/键盘闪一下。
    _closeComposer();
    setState(() => _sending = true);
    try {
      await widget.onSendEmoji(id);
    } catch (_) {
      if (mounted) _toast('表情发送失败');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 发送文字。返回 true = 已发出（_Composer 据此决定是否清空输入框）。
  Future<bool> _sendText(String text) async {
    if (!widget.enabled || _sending) return false;
    if (_throttled()) {
      _toast('发送过快，稍后再试');
      return false;
    }
    setState(() => _sending = true);
    try {
      await widget.onSendText(text);
      // 文字发送后保留 composer（清空输入由 _Composer._doSendText 负责），便于连发
      return true;
    } catch (_) {
      if (mounted) _toast('发送失败');
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 聊天区统一左上角：关闭态 = 💬 入口（有预览则展开显示最新一条）；
    // 打开态 = 输入面板原地替换。两者互斥，不做任何过渡动画。
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // composer 背景：仅挡点击，不着色（着色会在开关瞬间闪灰色蒙层）
        if (_composerOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeComposer,
            ),
          ),

        // composer 关闭时：左上角聊天入口 + 最新消息预览
        if (!_composerOpen)
          Positioned(
            left: 16,
            top: 16,
            child: _ChatPill(
              enabled: widget.enabled,
              preview: _preview,
              myDeviceId: widget.myDeviceId,
              emojiBundle: widget.emojiBundle,
              fileResolver: widget.fileResolver,
              onTap: _openComposer,
            ),
          ),
        // composer 打开时：左上角面板
        if (_composerOpen)
          Positioned(
            left: 16,
            top: 16,
            child: _Composer(
              emojiBundle: widget.emojiBundle,
              fileResolver: widget.fileResolver,
              enabled: widget.enabled,
              sending: _sending,
              textController: _textController,
              focusNode: _focusNode,
              onTextChanged: _onComposerTextChanged,
              onSendEmoji: _sendEmoji,
              onSendText: _sendText,
              onClose: _closeComposer,
              // 双 tab 记录面板：本局 ChatEvent 列表（去重显示）
              events: _historyEvents,
              myDeviceId: widget.myDeviceId,
            ),
          ),
      ],
    );
  }
}

/// 左上角聊天入口：💬 图标 + 最新一条消息预览（同一 pill 内，无动画）
///
/// 命名：区别于 chess_room_page.dart 的 _ChatFab（PlayerStrip 上的"详细历史"入口）
/// 形态：无预览 = 48×48 圆形（只有图标）；有预览 = 胶囊，图标右侧跟最新内容
/// （文字单行省略 / emoji 缩略图），超时由宿主清空 preview → 立即收回圆形。
/// 身份色点复用 F2 约定：蓝 = 我 / 橙 = 对方。
class _ChatPill extends StatefulWidget {
  final bool enabled;
  final ChatEvent? preview;
  final String myDeviceId;
  final EmojiBundle emojiBundle;
  final FileResolver? fileResolver;
  final VoidCallback onTap;

  const _ChatPill({
    required this.enabled,
    required this.preview,
    required this.myDeviceId,
    required this.emojiBundle,
    required this.fileResolver,
    required this.onTap,
  });

  @override
  State<_ChatPill> createState() => _ChatPillState();
}

class _ChatPillState extends State<_ChatPill> {
  bool _hover = false;
  bool _active = false;

  /// 预览主体：文字单行省略 / emoji 缩略图
  Widget _buildPreview(ChatEvent e, ColorScheme scheme) {
    if (e.isEmoji) {
      final entry = widget.emojiBundle.byId[e.emojiId ?? ''];
      return SizedBox(
        width: 22,
        height: 22,
        child: _EmojiImage(
          image: entry?.imageProvider(widget.fileResolver),
          id: e.emojiId ?? '',
        ),
      );
    }
    return Flexible(
      child: Text(
        e.text ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          height: 1.2,
          color: scheme.onSurface,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = widget.preview;
    // scale: 1.0 → 1.05 (hover) → 0.95 (active)
    final scale = _active ? 0.95 : (_hover ? 1.05 : 1.0);
    final isMe = preview?.from == widget.myDeviceId;
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _active = false;
      }),
      child: Listener(
        onPointerDown: (_) {
          if (widget.enabled) setState(() => _active = true);
        },
        onPointerUp: (_) {
          if (mounted) setState(() => _active = false);
        },
        onPointerCancel: (_) {
          if (mounted) setState(() => _active = false);
        },
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Material(
            color: scheme.surface,
            // 无预览时 48×48 = 圆；有预览时撑成胶囊（同 radius 24 视觉一致）
            shape: const StadiumBorder(side: BorderSide(color: Color(0xFF1A1A1A))),
            elevation: _hover ? 3 : 2,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: widget.enabled ? widget.onTap : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // mock: 22×22 自定义 SVG 聊天气泡
                      // （区别于 Icons.chat_bubble_outline_rounded）
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CustomPaint(
                          painter: _ChatBubbleIconPainter(
                            color: const Color(0xFF1A1A1A)
                                .withValues(alpha: widget.enabled ? 1.0 : 0.4),
                          ),
                        ),
                      ),
                      if (preview != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isMe
                                ? const Color(0xFF2A6FDB)
                                : const Color(0xFFC2410C),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        _buildPreview(preview, scheme),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 嵌入式 composer：emoji 行 + 文字输入 + 发送
/// 仅 _composerOpen 时构造；文字草稿与输入控件由 [_BoardChatOverlayState] 持有，
/// 关闭时草稿存 _draftText、controller / focusNode 由宿主复用，重开不丢内容。
class _Composer extends StatefulWidget {
  final EmojiBundle emojiBundle;
  final FileResolver? fileResolver;
  final bool enabled;
  final bool sending;
  final TextEditingController textController;
  final FocusNode focusNode;
  final ValueChanged<String> onTextChanged;
  final Future<void> Function(String emojiId) onSendEmoji;

  /// 返回 true = 已发出（据此决定是否清空输入框）
  final Future<bool> Function(String text) onSendText;
  final VoidCallback onClose;
  // 双 tab 记录面板：本局对话历史（去重后展示）
  final List<ChatEvent> events;
  final String myDeviceId;

  const _Composer({
    required this.emojiBundle,
    required this.fileResolver,
    required this.enabled,
    required this.sending,
    required this.textController,
    required this.focusNode,
    required this.onTextChanged,
    required this.onSendEmoji,
    required this.onSendText,
    required this.onClose,
    required this.events,
    required this.myDeviceId,
  });

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  // 双 tab 状态：'emoji' / 'history'
  String _tab = 'emoji';

  @override
  void initState() {
    super.initState();
    widget.textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    widget.onTextChanged(widget.textController.text);
  }

  @override
  void dispose() {
    widget.textController.removeListener(_onTextChanged);
    super.dispose();
  }

  Future<void> _doSendEmoji(String id) async {
    await widget.onSendEmoji(id);
  }

  Future<void> _doSendText() async {
    final text = widget.textController.text.trim();
    if (text.isEmpty || !widget.enabled || widget.sending) return;
    // 发送成功才清空：被节流 / 失败时保留草稿，避免用户输入被吞
    final sent = await widget.onSendText(text);
    if (!mounted || !sent) return;
    widget.textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        // mock: border:1px solid var(--text-1) 硬黑边（F2 身份色）
        side: const BorderSide(color: Color(0xFF1A1A1A)),
      ),
      // mock: box-shadow 0 8px 24px rgba(0,0,0,0.14) + 0 2px 4px rgba(0,0,0,0.06)
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Padding(
          // mock: padding: 8px 4px 8px 8px (LTRB) — top 从 4 → 8
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部 head：双 tab + 关闭按钮
              _buildHead(scheme),
              const SizedBox(height: 6),
              // tab 内容区
              if (_tab == 'emoji')
                _buildEmojiGrid(scheme)
              else
                _buildHistoryList(scheme),
              const SizedBox(height: 6),
              // 文字输入 + 发送（底部固定）
              _buildInputRow(scheme),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部 head：表情 / 记录 tab（segmented control 容器）+ 关闭按钮
  /// mock .tabs: bg #FAFAF7, radius 6, padding 2, gap 2 (F2 风格分段控件)
  Widget _buildHead(ColorScheme scheme) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAF7), // var(--bg)
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                _buildTab('表情', 'emoji', scheme),
                _buildTab('记录', 'history', scheme,
                    count: _uniqueHistory().length),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        // 关闭按钮
        InkWell(
          onTap: widget.onClose,
          borderRadius: BorderRadius.circular(10),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close, size: 16, color: Color(0xFF9B9B9B)),
          ),
        ),
      ],
    );
  }

  Widget _buildTab(String label, String key, ColorScheme scheme, {int? count}) {
    final active = _tab == key;
    final badge = (count != null && count > 0)
        ? Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFC2410C) : const Color(0xFF2A6FDB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        : null;
    return InkWell(
      onTap: () => setState(() => _tab = key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? scheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            if (badge != null) badge,
          ],
        ),
      ),
    );
  }

  /// emoji tab：从 [EmojiBundle] 渲染 KV 上的真实表情图片
  /// （board_chat_overlay.dart 原版 line 810-834 的行为）。
  Widget _buildEmojiGrid(ColorScheme scheme) {
    final entries = widget.emojiBundle.entries;
    if (entries.isEmpty) {
      // 表情包尚未加载完成（chess_room_page 的 _ensureEmojiBundle 异步）——
      // 占位避免空 grid 闪一下。
      return const SizedBox(
        height: 100,
        child: Center(
          child: SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 156),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        childAspectRatio: 1.0,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        padding: EdgeInsets.zero,
        children: [
          for (final entry in entries)
            InkResponse(
              onTap: widget.enabled && !widget.sending
                  ? () => _doSendEmoji(entry.id)
                  : null,
              radius: 18,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.all(6),
                child: _EmojiImage(
                  image: entry.imageProvider(widget.fileResolver),
                  id: entry.id,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 记录 tab：本局 ChatEvent 列表（去重）
  Widget _buildHistoryList(ColorScheme scheme) {
    final items = _uniqueHistory();
    if (items.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        child: Text(
          '还没有消息',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 156),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outline.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 3),
        itemBuilder: (ctx, i) {
          final e = items[i];
          final isMe = e.from == widget.myDeviceId;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFF2A6FDB) : const Color(0xFFC2410C),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isMe ? '我' : '对方',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isMe ? const Color(0xFF2A6FDB) : const Color(0xFFC2410C),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildHistoryBody(e, scheme),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHistoryBody(ChatEvent e, ColorScheme scheme) {
    if (e.isEmoji) {
      final entry = widget.emojiBundle.byId[e.emojiId ?? ''];
      if (entry == null) {
        return const SizedBox(width: 22, height: 22);
      }
      return SizedBox(
        width: 22,
        height: 22,
        child: _EmojiImage(
          image: entry.imageProvider(widget.fileResolver),
          id: entry.id,
        ),
      );
    }
    return Text(
      e.text ?? '',
      style: TextStyle(
        fontSize: 11,
        height: 1.3,
        color: scheme.onSurface,
      ),
    );
  }

  Widget _buildInputRow(ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SizedBox(
            height: 32,
            child: TextField(
              controller: widget.textController,
              focusNode: widget.focusNode,
              // 发送在途时不再禁用输入框：禁用会让聚焦中的输入框失焦、
              // 收起 IME，连发体验很差；重复发送由 _doSendText 的 sending
              // 守卫 + 按钮可用态兜住。
              enabled: widget.enabled,
              maxLines: 1,
              maxLength: 40,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _doSendText(),
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: '说点什么…',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
                counterText: '',
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // 可用态必须跟着输入内容实时刷新：此前 onPressed 直接读
        // textController.text，但 textController 的 listener 只把草稿转给父层
        // （父层不 setState），本层不 rebuild → 输入后按钮仍是灰的，得切 tab
        // 触发重建才会亮。这里用 ValueListenableBuilder 只重建按钮本身。
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.textController,
          builder: (ctx, value, _) {
            final canSend = widget.enabled &&
                !widget.sending &&
                value.text.trim().isNotEmpty;
            return SizedBox(
              height: 32,
              child: FilledButton(
                onPressed: canSend ? _doSendText : null,
                // mock: 黑色 1px 边框 + 黑色背景 + 白字 + radius 6 (F2 硬黑 identity)
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: const Color(0xFF1A1A1A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(color: Color(0xFF1A1A1A)),
                  ),
                ),
                child: const Text('发', style: TextStyle(fontSize: 12)),
              ),
            );
          },
        ),
      ],
    );
  }

  /// 提取本局去重历史（仅保留文字/表情）
  List<ChatEvent> _uniqueHistory() {
    final seen = <String>{};
    final out = <ChatEvent>[];
    for (final e in widget.events) {
      final key = '${e.kind.name}:${e.id}:${e.seq}';
      if (seen.add(key)) out.add(e);
    }
    return out;
  }
}

/// 统一渲染 emoji 表情（KV 拉来的 imageProvider）。
///
/// 处理 imageProvider 为 null 的情况（EmojiEntry.imageProvider 在无 fileResolver
/// 且无本地缓存时返回 null —— board_chat_overlay.dart:38-44）。
class _EmojiImage extends StatelessWidget {
  final ImageProvider? image;
  final String id;
  const _EmojiImage({required this.image, required this.id});

  @override
  Widget build(BuildContext context) {
    final img = image;
    if (img == null) {
      // 兜底：emoji 加载不出来 → 显示浅灰占位 + id 前 2 字符（调试用）
      final hint = id.length >= 2 ? id.substring(0, 2) : '?';
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          hint,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Image(
      image: img,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.broken_image_outlined, size: 14),
      ),
    );
  }
}

/// FAB 聊天气泡 icon（mock 的 22×22 自定义 SVG）。
/// path data: M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z
/// （圆角矩形主体 + 左下小尾巴 — 与 Icons.chat_bubble_outline_rounded 不同）。
class _ChatBubbleIconPainter extends CustomPainter {
  final Color color;
  _ChatBubbleIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 24.0;
    final scaleY = size.height / 24.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0 / ((scaleX + scaleY) / 2)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final path = _buildBubblePath();
    canvas.save();
    canvas.scale(scaleX, scaleY);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  /// 24x24 viewBox：圆角矩形 + 左下小尾巴
  Path _buildBubblePath() {
    final p = Path();
    // M21 15  : 起点右上偏左 (21, 15)
    p.moveTo(21, 15);
    // a2 2 0 0 1-2 2 : 弧到 (19, 17) 圆角
    p.arcToPoint(const Offset(19, 17), radius: const Radius.circular(2), clockwise: true);
    // H7 : 水平到 (7, 17)
    p.lineTo(7, 17);
    // l-4 4 : 相对位移 (-4, 4) → 画左下小尾巴到 (3, 21)
    p.lineTo(3, 21);
    // V5 : 垂直回到 (3, 5)
    p.lineTo(3, 5);
    // a2 2 0 0 1 2-2 : 弧到 (5, 3) 圆角
    p.arcToPoint(const Offset(5, 3), radius: const Radius.circular(2), clockwise: true);
    // h14 : 水平到 (19, 3)
    p.lineTo(19, 3);
    // a2 2 0 0 1 2 2 : 弧到 (21, 5) 圆角
    p.arcToPoint(const Offset(21, 5), radius: const Radius.circular(2), clockwise: true);
    // z : 闭合（回到 (21, 15)）
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant _ChatBubbleIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
