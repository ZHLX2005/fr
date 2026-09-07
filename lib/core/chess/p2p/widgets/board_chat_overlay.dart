// lib/core/chess/p2p/widgets/board_chat_overlay.dart
//
// F2 落地版：棋盘 absolute 浮层
//   · 左上角：近期对话卡片堆（最多 N 张，新卡 deal-in，旧卡 tuck 后退）
//   · 右下角：💬 FAB（点击展开 composer）
//   · composer：emoji 行 + 文字输入 + 发送
//   · 棋盘 100% 不被遮挡；player strip 镜像同尺寸；host-guest 通用
//
// 设计依据：plan/chess-chat-redesign-2026-09-07/F-card-stack.html
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

/// F2 棋盘对话浮层
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

  /// 卡片堆上限
  final int maxCards;

  /// 单张卡片可见时长（超时后开始 dismiss 动画）
  final Duration cardDisplayDuration;

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
    this.maxCards = 3,
    this.cardDisplayDuration = const Duration(milliseconds: 2800),
    this.sendThrottle = const Duration(milliseconds: 800),
  });

  @override
  State<BoardChatOverlay> createState() => _BoardChatOverlayState();
}

class _BoardChatOverlayState extends State<BoardChatOverlay> {
  // 卡片数据（FIFO，新卡在末尾）
  final List<_CardData> _cards = [];

  // 已 dismiss 但尚未真正移除（等待动画结束回调）
  // 集合；实际动画由 _ChatCardState 内部 controller 驱动
  final Set<String> _dismissing = {};

  // 自动 dismiss 定时器（卡片到达 cardDisplayDuration 后触发）
  final Map<String, Timer> _timers = {};

  // 去重缓存：FIFO，超过 _kSeenCapacity 淘汰最早
  // 注：server 端 chatRing append-only，长局可达上千条，故需有界
  final List<String> _seenList = [];

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
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 全量重置（myDeviceId 变化 / 跨局）
  void _resetAllState() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _seenList.clear();
    _dismissing.clear();
    _cards.clear();
    _draftText = '';
    _textController.text = '';
  }

  void _ingest(List<ChatEvent> events) {
    // 跨局 / RESET：events 被清空时同步清掉卡片，避免上局残影
    if (events.isEmpty) {
      if (_cards.isEmpty && _timers.isEmpty) return;
      // 取消所有 timer、立即清状态（不播 dismiss 动画：跨局无需动画）
      for (final t in _timers.values) {
        t.cancel();
      }
      _timers.clear();
      _dismissing.clear();
      _cards.clear();
      _seenList.clear();
      return;
    }

    // 收集本批次新增（循环外单次 setState，避免 N 次 rebuild）
    final newCards = <_CardData>[];
    final newTimers = <String, Timer>{};

    for (final e in events) {
      final key = _keyFor(e);
      if (_seenList.contains(key)) continue;
      _pushSeen(key);

      // 内容合法性校验：emoji 必须能解析到 image；文字必须非空（trim 与 ChatSpeechBubbles 对齐，拒纯空白）
      if (e.isEmoji) {
        final entry = widget.emojiBundle.byId[e.emojiId ?? ''];
        if (entry?.imageProvider(widget.fileResolver) == null) continue;
      } else if (e.text == null || e.text!.trim().isEmpty) {
        continue;
      }

      newCards.add(_CardData(event: e));
      newTimers[e.id] = Timer(widget.cardDisplayDuration, () {
        if (!mounted) return;
        _dismissCard(e.id);
      });
    }

    if (newCards.isEmpty && _timers.isEmpty == false) {
      // 仅新增 timer（无新增卡片，仍需补建 timer）—— 当前 ingest 设计里 newCards 非空才有 timer，可优化
    }

    if (newCards.isEmpty) return;

    // 溢出：超出 maxCards 的旧卡立即标记 dismiss（动画播放），再物理移除
    final overflow = (_cards.length + newCards.length) - widget.maxCards;
    final toDismiss = overflow > 0
        ? _cards.take(overflow).map((c) => c.event.id).toList()
        : const <String>[];

    setState(() {
      _cards.addAll(newCards);
      while (_cards.length > widget.maxCards) {
        _cards.removeAt(0);
      }
      for (final id in toDismiss) {
        _dismissing.add(id);
        _timers[id]?.cancel();
      }
    });

    _timers.addAll(newTimers);
  }

  void _pushSeen(String key) {
    _seenList.add(key);
    if (_seenList.length > _kSeenCapacity) {
      _seenList.removeAt(0); // FIFO 淘汰
    }
  }

  String _keyFor(ChatEvent e) => '${e.kind.name}:${e.id}:${e.seq}';

  /// 幂等 dismiss：取消 timer + 检查卡片仍在 + 标记 dismissing（动画由 _ChatCard 内部驱动）
  void _dismissCard(String eventId) {
    if (!mounted) return;
    _timers.remove(eventId)?.cancel();
    if (!_cards.any((c) => c.event.id == eventId)) return;
    if (_dismissing.contains(eventId)) return;
    setState(() => _dismissing.add(eventId));
  }

  /// _ChatCard 自身动画完成后回调，物理移除
  void _onCardDismissed(String eventId) {
    if (!mounted) return;
    setState(() {
      _cards.removeWhere((c) => c.event.id == eventId);
      _dismissing.remove(eventId);
    });
    _timers.remove(eventId)?.cancel();
  }

  void _openComposer() {
    if (!widget.enabled) return;
    setState(() => _composerOpen = true);
    // 关闭时已在 _draftText 中保留文字；打开后把草稿恢复给 controller
    _textController.text = _draftText;
    // 聚焦交给 _Composer 的 listener / FocusNode，延迟到 build 后
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
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
    setState(() => _sending = true);
    try {
      await widget.onSendEmoji(id);
      if (!mounted) return;
      _closeComposer();
    } catch (_) {
      if (mounted) _toast('表情发送失败');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendText(String text) async {
    if (!widget.enabled || _sending) return;
    if (_throttled()) {
      _toast('发送过快，稍后再试');
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.onSendText(text);
      // 文字发送后保留 composer（清空输入由 _Composer._doSendText 负责），便于连发
    } catch (_) {
      if (mounted) _toast('发送失败');
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 卡片堆：左上角（在 board 上方的 padding 区）
        Positioned(
          top: 16,
          left: 16,
          child: _CardStack(
            cards: _cards,
            dismissing: _dismissing,
            myDeviceId: widget.myDeviceId,
            emojiBundle: widget.emojiBundle,
            fileResolver: widget.fileResolver,
            onCardDismissed: _onCardDismissed,
          ),
        ),

        // composer 背景遮罩（仅在打开时）
        if (_composerOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeComposer,
            ),
          ),

        // composer 关闭时：右下角 FAB
        if (!_composerOpen)
          Positioned(
            right: 16,
            bottom: 16,
            child: _BoardChatFab(
              enabled: widget.enabled,
              onTap: _openComposer,
            ),
          ),
        // composer 打开时：右下角 composer 面板
        if (_composerOpen)
          Positioned(
            right: 16,
            bottom: 16,
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
            ),
          ),
      ],
    );
  }
}

class _CardData {
  final ChatEvent event;
  _CardData({required this.event});
}

/// 卡片堆：渲染 N 张卡片，按 depth 偏移制造层叠感
class _CardStack extends StatelessWidget {
  final List<_CardData> cards;
  final Set<String> dismissing;
  final String myDeviceId;
  final EmojiBundle emojiBundle;
  final FileResolver? fileResolver;
  final ValueChanged<String> onCardDismissed;

  const _CardStack({
    required this.cards,
    required this.dismissing,
    required this.myDeviceId,
    required this.emojiBundle,
    required this.fileResolver,
    required this.onCardDismissed,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    // SizedBox 80 是为了给 3 张 60x60 卡 + 12px 偏移留出可见边界（hit-test 用）
    return IgnorePointer(
      child: SizedBox(
        width: 240,
        height: 80,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (int i = 0; i < cards.length; i++)
              Positioned(
                left: i * 6.0,
                top: i * 6.0,
                child: _ChatCard(
                  // key 必须稳定以保 didUpdateWidget 触发
                  key: ValueKey('chat-card-${cards[i].event.id}'),
                  card: cards[i],
                  isMe: cards[i].event.from == myDeviceId,
                  isDismissing: dismissing.contains(cards[i].event.id),
                  depth: cards.length - 1 - i,
                  emojiBundle: emojiBundle,
                  fileResolver: fileResolver,
                  onDismissed: () => onCardDismissed(cards[i].event.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 单张卡片：entry 用 cubic-bezier(.2,.9,.3,1.4) + -10→+2→0deg 旋转；dismiss 用 0→+8deg + scale 1→0.5
class _ChatCard extends StatefulWidget {
  final _CardData card;
  final bool isMe;
  final bool isDismissing;
  final int depth; // 0 = 最新，N-1 = 最旧
  final EmojiBundle emojiBundle;
  final FileResolver? fileResolver;
  final VoidCallback onDismissed;

  const _ChatCard({
    super.key,
    required this.card,
    required this.isMe,
    required this.isDismissing,
    required this.depth,
    required this.emojiBundle,
    required this.fileResolver,
    required this.onDismissed,
  });

  @override
  State<_ChatCard> createState() => _ChatCardState();
}

class _ChatCardState extends State<_ChatCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _opacityAnim;
  late final Animation<double> _rotationAnim;
  bool _dismissingStarted = false;
  bool _onDismissedFired = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    // entry 曲线：cubic-bezier(.2,.9,.3,1.4) → 落点弹性
    final entryCurve = CurvedAnimation(
      parent: _ctrl,
      curve: const Cubic(0.2, 0.9, 0.3, 1.4),
      reverseCurve: const Cubic(0.4, 0.0, 0.6, 1.0), // dismiss 用 ease-out
    );
    _scaleAnim = Tween<double>(begin: 0.4, end: 1.0).animate(entryCurve);
    _opacityAnim = Tween<double>(begin: 0.0, end: 1.0).animate(entryCurve);
    // entry: -10° → +2° → 0°（bouncy settle）；dismiss: 0° → +8°
    _rotationAnim = Tween<double>(begin: -10, end: 0).animate(entryCurve);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_ChatCard old) {
    super.didUpdateWidget(old);
    if (widget.isDismissing && !old.isDismissing) {
      _startDismiss();
    }
  }

  void _startDismiss() {
    if (_dismissingStarted) return;
    _dismissingStarted = true;
    // dismiss 时重新构造 Tween，让目标值指向"缩小 + 旋转 +8°"
    _scaleAnim = Tween<double>(begin: _scaleAnim.value, end: 0.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
    _opacityAnim = Tween<double>(begin: _opacityAnim.value, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
    _rotationAnim = Tween<double>(begin: _rotationAnim.value, end: 8).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
    _ctrl.duration = const Duration(milliseconds: 320);
    _ctrl.reverse(from: 1.0).then((_) {
      if (mounted && !_onDismissedFired) {
        _onDismissedFired = true;
        widget.onDismissed();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = widget.card.event;
    final isEmoji = e.isEmoji;

    // 卡片内容
    Widget content;
    if (isEmoji) {
      final entry = widget.emojiBundle.byId[e.emojiId ?? ''];
      final img = entry?.imageProvider(widget.fileResolver);
      content = SizedBox(
        width: 60,
        height: 60,
        child: img == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.all(6),
                child: Image(image: img, fit: BoxFit.contain),
              ),
      );
    } else {
      final text = e.text ?? '';
      // 关键：maxWidth 约束让 text 自适应一行 + 超出换行（shrink-to-content + wrap）
      content = Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: scheme.onSurface,
          ),
        ),
      );
    }

    // 层叠：越旧越缩、越淡、轻微旋转
    final baseScale = 1.0 - widget.depth * 0.04;
    final baseOpacity = 1.0 - widget.depth * 0.18;
    final baseRot = (widget.depth.isEven ? 1 : -1) * widget.depth * 1.5; // degrees

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, child) {
        return Opacity(
          opacity: _opacityAnim.value * baseOpacity,
          child: Transform.rotate(
            angle: (_rotationAnim.value + baseRot) * 3.1415926 / 180,
            child: Transform.scale(
              scale: _scaleAnim.value * baseScale,
              child: child,
            ),
          ),
        );
      },
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        elevation: 1,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            content,
            // 发送方色点
            Positioned(
              top: 5,
              left: 5,
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: widget.isMe ? const Color(0xFF2A6FDB) : const Color(0xFFC2410C),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 右下角圆形 FAB（棋盘 quick-send 入口）
/// 命名：区别于 chess_room_page.dart 的 _ChatFab（PlayerStrip 上的"详细历史"入口）
class _BoardChatFab extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _BoardChatFab({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: const CircleBorder(side: BorderSide(color: Color(0xFF1A1A1A))),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Icon(
            Icons.chat_bubble_outline_rounded,
            size: 20,
            color: scheme.onSurface.withValues(alpha: enabled ? 1.0 : 0.4),
          ),
        ),
      ),
    );
  }
}

/// 嵌入式 composer：emoji 行 + 文字输入 + 发送
/// 由 BoardChatOverlay 始终构造（不随 _composerOpen 销毁），保证：
///   · 关闭时输入文字保留（草稿暂存在 _draftText）
///   · 重开时不重建 FocusNode / TextEditingController
class _Composer extends StatefulWidget {
  final EmojiBundle emojiBundle;
  final FileResolver? fileResolver;
  final bool enabled;
  final bool sending;
  final TextEditingController textController;
  final FocusNode focusNode;
  final ValueChanged<String> onTextChanged;
  final Future<void> Function(String emojiId) onSendEmoji;
  final Future<void> Function(String text) onSendText;
  final VoidCallback onClose;

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
  });

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
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
    widget.textController.clear(); // listener 会同步清空 _draftText
    await widget.onSendText(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outline),
      ),
      elevation: 4,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 关闭按钮
              Align(
                alignment: Alignment.topRight,
                child: InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16, color: Color(0xFF9B9B9B)),
                  ),
                ),
              ),
              // emoji 行
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in kBoardChatQuickEmojis)
                    InkResponse(
                      onTap: widget.enabled && !widget.sending
                          ? () => _doSendEmoji(e)
                          : null,
                      radius: 18,
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        child: Text(
                          e,
                          style: TextStyle(
                            fontSize: 18,
                            color: widget.enabled && !widget.sending
                                ? null
                                : scheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // 文字输入 + 发送（单行，原型是固定 32px input）
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: widget.textController,
                        focusNode: widget.focusNode,
                        enabled: widget.enabled && !widget.sending,
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
                  SizedBox(
                    height: 32,
                    child: FilledButton(
                      onPressed: widget.enabled && !widget.sending &&
                              widget.textController.text.trim().isNotEmpty
                          ? _doSendText
                          : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('发', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
