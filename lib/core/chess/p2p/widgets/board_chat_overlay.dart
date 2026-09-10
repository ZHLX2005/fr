// lib/core/chess/p2p/widgets/board_chat_overlay.dart
//
// F2 落地版：棋盘 absolute 浮层
//   · 左上角：近期对话卡片堆（最多 N 张，新卡 deal-in，旧卡 tuck 后退）
//   · 右上角：💬 FAB（点击展开 composer）
//   · composer：双 tab（表情 / 记录）+ 文字输入 + 发送
//   · 浮层 absolute，不挤 Column flex；竖屏 board-wrap 上下留白时 FAB 可落在格外
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

  // 本局 ChatEvent 列表（去重后）—— 给 _Composer 记录 tab 用。
  // 每次 ingest 后刷新；_seenList 同源。
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
      _historyEvents = const [];
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
      // 同步本局历史快照（去重）—— 给 _Composer 记录 tab 用
      _historyEvents = _dedupEvents(events);
    });

    _timers.addAll(newTimers);
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
        // 卡片堆：左上角（与右上对话入口分开，避免重叠）
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

        // composer 背景：仅挡点击，不着色（着色会在开关瞬间闪灰色蒙层）
        if (_composerOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeComposer,
            ),
          ),

        // composer 关闭时：右上角 FAB
        if (!_composerOpen)
          Positioned(
            right: 16,
            top: 16,
            child: _BoardChatFab(
              enabled: widget.enabled,
              onTap: _openComposer,
            ),
          ),
        // composer 打开时：右上角面板（替换 FAB，从右侧滑入）
        if (_composerOpen)
          Positioned(
            right: 16,
            top: 16,
            child: TweenAnimationBuilder<double>(
              // 首次构建 t=0→1；后续 composer 关闭再打开时也会重新构建
              // （if 条件让 _Composer 卸载/重建），故每次打开都播一次入场动画
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 180),
              // 不用 Cubic y>1 过冲：Opacity 要求 [0,1]，过冲会 assert / 闪层
              curve: Curves.easeOutCubic,
              builder: (ctx, t, child) {
                final clamped = t.clamp(0.0, 1.0);
                return Opacity(
                  opacity: clamped,
                  child: Transform.translate(
                    // 从右侧 +8 滑入
                    offset: Offset(8 * (1 - clamped), 0),
                    child: Transform.scale(
                      scale: 0.96 + 0.04 * clamped,
                      alignment: Alignment.topRight,
                      child: child,
                    ),
                  ),
                );
              },
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

/// 单张卡片：entry 用 TweenSequence 三段 bounce（scale/rot）；dismiss 用 easeIn
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

class _ChatCardState extends State<_ChatCard> with TickerProviderStateMixin {
  // 入场：TweenSequence 三关键帧（scale 0.3→1.1→1.0、rotation -10°→+2°→0°）
  // 与原型 F2 keyframe 严格对齐
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryScale;
  late final Animation<double> _entryOpacity;
  late final Animation<double> _entryRot;

  // 退场：scale 1→0.5、rotation 0°→+8°、opacity 1→0
  late final AnimationController _dismissCtrl;
  late final Animation<double> _dismissScale;
  late final Animation<double> _dismissOpacity;
  late final Animation<double> _dismissRot;

  bool _onDismissedFired = false;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    // Bounce 已由 TweenSequence 关键（0.3→1.1→1.0）。禁止再套
    // Cubic(..., y>1) 过冲曲线：CurvedAnimation 会产出 t>1，TweenSequence
    // 断言失败，debug 下连闪灰色错误蒙层（发表情立刻能复现）。
    _entryScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.3, end: 1.1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.1, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
    ]).animate(_entryCtrl);
    _entryOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut),
    );
    _entryRot = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: -10.0, end: 2.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 2.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
    ]).animate(_entryCtrl);
    _entryCtrl.forward();

    _dismissCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _dismissScale = Tween<double>(begin: 1.0, end: 0.5).animate(
      CurvedAnimation(parent: _dismissCtrl, curve: Curves.easeIn),
    );
    _dismissOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(_dismissCtrl);
    _dismissRot = Tween<double>(begin: 0.0, end: 8.0).animate(_dismissCtrl);
  }

  @override
  void didUpdateWidget(_ChatCard old) {
    super.didUpdateWidget(old);
    if (widget.isDismissing && !old.isDismissing && !_dismissCtrl.isAnimating) {
      _dismissCtrl.forward().then((_) {
        if (mounted && !_onDismissedFired) {
          _onDismissedFired = true;
          widget.onDismissed();
        }
      });
    }
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _dismissCtrl.dispose();
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
      content = SizedBox(
        width: 60,
        height: 60,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: _EmojiImage(
            image: entry?.imageProvider(widget.fileResolver),
            id: e.emojiId ?? '',
          ),
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

    // depth-based base 值（旧卡缩、淡、转）
    final baseScale = 1.0 - widget.depth * 0.04;
    final baseOpacity = 1.0 - widget.depth * 0.18;
    final baseRot = (widget.depth.isEven ? 1 : -1) * widget.depth * 1.5; // 度

    // depth-based transform matrix（position + base scale + base rot）
    // 用 TweenAnimationBuilder 实现"被新卡挤下来时的 tuck 过渡"
    final baseMatrix = Matrix4.identity()
      ..translateByDouble(widget.depth * 6.0, widget.depth * 6.0, 0, 1)
      ..rotateZ(baseRot * 3.1415926 / 180)
      ..scaleByDouble(baseScale, baseScale, 1, 1);

    return TweenAnimationBuilder<Matrix4>(
      tween: Matrix4Tween(begin: Matrix4.identity(), end: baseMatrix),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      builder: (ctx, matrix, child) {
        return Transform(
          transform: matrix,
          alignment: Alignment.center,
          child: AnimatedOpacity(
            opacity: baseOpacity,
            duration: const Duration(milliseconds: 300),
            child: child,
          ),
        );
      },
      // 在 base transform 之上叠加入场/退场动画
      child: AnimatedBuilder(
        animation: Listenable.merge([_entryCtrl, _dismissCtrl]),
        builder: (ctx, child) {
          return Opacity(
            opacity: (_entryOpacity.value * _dismissOpacity.value)
                .clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: (_entryRot.value + _dismissRot.value) * 3.1415926 / 180,
              child: Transform.scale(
                scale: _entryScale.value * _dismissScale.value,
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
          // 原型 box-shadow 0 3px 10px rgba(0,0,0,0.10), 0 1px 2px rgba(0,0,0,0.06)
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.10),
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
                    color: widget.isMe
                        ? const Color(0xFF2A6FDB)
                        : const Color(0xFFC2410C),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 右上角圆形 FAB（棋盘 quick-send 入口）
/// 命名：区别于 chess_room_page.dart 的 _ChatFab（PlayerStrip 上的"详细历史"入口）
/// 视觉对齐 F2 原型：圆形、黑色边、💬 图标、hover/active scale 反馈
class _BoardChatFab extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _BoardChatFab({required this.enabled, required this.onTap});

  @override
  State<_BoardChatFab> createState() => _BoardChatFabState();
}

class _BoardChatFabState extends State<_BoardChatFab> {
  bool _hover = false;
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // scale: 1.0 → 1.05 (hover) → 0.95 (active)
    final scale = _active ? 0.95 : (_hover ? 1.05 : 1.0);
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
            shape: const CircleBorder(side: BorderSide(color: Color(0xFF1A1A1A))),
            elevation: _hover ? 3 : 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.enabled ? widget.onTap : null,
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                // mock: 22×22 自定义 SVG 聊天气泡（区别于 Icons.chat_bubble_outline_rounded）
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CustomPaint(
                    painter: _ChatBubbleIconPainter(
                      color: const Color(0xFF1A1A1A)
                          .withValues(alpha: widget.enabled ? 1.0 : 0.4),
                    ),
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
    widget.textController.clear();
    await widget.onSendText(text);
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
