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

/// 双 tab composer 的表情包（mock 阶段 hardcoded 12 个 SVG icon +
/// sk 渐变背景；生产用 EmojiBundle.forGame('chess', ...) 拉 KV）。
///
/// 字段：id / svgPath (24x24 viewBox 描线) / sk (背景渐变 class) / category
class _KvEmojiEntry {
  final String id;
  final String svgPath;
  final String sk;
  final String category;
  const _KvEmojiEntry(this.id, this.svgPath, this.sk, this.category);
}

const List<_KvEmojiEntry> _kComposerEmojis = [
  _KvEmojiEntry('fist-bump',
      'M9 11V6.5a1.5 1.5 0 0 1 3 0V11M12 11V4.5a1.5 1.5 0 0 1 3 0V11M15 11V6.5a1.5 1.5 0 0 1 3 0v8.5a4 4 0 0 1-4 4h-3a4 4 0 0 1-4-4v-2.5',
      'sk-a', 'gesture'),
  _KvEmojiEntry('thumbs-up',
      'M7 22V11M14 11V4a2 2 0 0 0-4 0v7H7l3 11h7a3 3 0 0 0 3-2.5l1-5a2 2 0 0 0-2-2.5h-5z',
      'sk-b', 'gesture'),
  _KvEmojiEntry('party',
      'M5.8 11.3L2 22l10.7-3.79M4 16.5l5.5-5.5M14 8L8 14M19 5L5 19M14.5 5.5L18 9',
      'sk-c', 'celebrate'),
  _KvEmojiEntry('thinking',
      'M12 2a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM9.5 9a2.5 2.5 0 0 1 5 0c0 1.5-2.5 1.5-2.5 3M12 17.5v.01',
      'sk-d', 'face'),
  _KvEmojiEntry('frustrated',
      'M12 2a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM16 16s-1.5-2-4-2-4 2-4 2M9 9l-1.5-1M15 9l1.5-1',
      'sk-e', 'face'),
  _KvEmojiEntry('handshake',
      'M11 17l2 2a1 1 0 1 0 3-3M14 14l2.5 2.5a1 1 0 1 0 3-3l-3.88-3.88a3 3 0 0 0-4.24 0l-.88.88a1 1 0 1 1-3-3l2.81-2.81a5.79 5.79 0 0 1 7.06-.87l.47.28a2 2 0 0 0 1.42.25L21 4M3 4h2.5l1 2M16 4l1 2',
      'sk-f', 'gesture'),
  _KvEmojiEntry('wave',
      'M7 22V11M14 11V4a2 2 0 0 0-4 0v2M14 11V7a2 2 0 0 1 4 0v4M14 11h2a2 2 0 0 1 2 2v3a4 4 0 0 1-4 4h-2',
      'sk-g', 'gesture'),
  _KvEmojiEntry('applause',
      'M9 5l-4 4 4 4M15 5l4 4-4 4M12 4v16M9 12l3 3 3-3',
      'sk-h', 'gesture'),
  _KvEmojiEntry('pray',
      'M12 2v20M9 18l3-12 3 12M9 8h6',
      'sk-i', 'gesture'),
  _KvEmojiEntry('trophy',
      'M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0V4zM17 5h3a1 1 0 0 1 1 1v1a3 3 0 0 1-3 3M7 5H4a1 1 0 0 0-1 1v1a3 3 0 0 0 3 3',
      'sk-j', 'celebrate'),
  _KvEmojiEntry('good-luck',
      'M12 2a4 4 0 0 1 4 4 4 4 0 0 1-4 4 4 4 0 0 1-4-4 4 4 0 0 1 4-4zM12 10v12M9 16h6',
      'sk-k', 'gesture'),
  _KvEmojiEntry('cool',
      'M3 12a9 9 0 0 1 18 0v3a3 3 0 0 1-3 3h-1a3 3 0 0 1-3-3v-1a1 1 0 0 0-1-1h-2a1 1 0 0 0-1 1v1a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3v-3z',
      'sk-l', 'face'),
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
        // 卡片堆：右上角（在 board 上方的 padding 区）
        // 之前在左上：但 FAB/composer 也改到了左上角（避开键盘弹起遮挡），
        // 卡片堆改到右上避免与对话入口重叠。
        Positioned(
          top: 16,
          right: 16,
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

        // composer 关闭时：左上角 FAB
        // 之前在右下角：移到左上角避免键盘弹起时 FAB 被输入法遮住无法点。
        if (!_composerOpen)
          Positioned(
            left: 16,
            top: 16,
            child: _BoardChatFab(
              enabled: widget.enabled,
              onTap: _openComposer,
            ),
          ),
        // composer 打开时：左上角 composer 面板（替换 FAB，从左侧滑入）
        if (_composerOpen)
          Positioned(
            left: 16,
            top: 16,
            child: TweenAnimationBuilder<double>(
              // 首次构建 t=0→1；后续 composer 关闭再打开时也会重新构建
              // （if 条件让 _Composer 卸载/重建），故每次打开都播一次入场动画
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 180),
              curve: const Cubic(0.2, 0.9, 0.3, 1.2),
              builder: (ctx, t, child) {
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    // 从左侧 -8 滑入（位置在左上，故水平方向滑入更自然）
                    offset: Offset(-8 * (1 - t), 0),
                    child: Transform.scale(
                      scale: 0.96 + 0.04 * t,
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
    // bouncy 3-stop entry：60% 时 bouncy peak、40% 收尾
    const bouncy = Cubic(0.2, 0.9, 0.3, 1.4);
    _entryScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.3, end: 1.1), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(parent: _entryCtrl, curve: bouncy));
    _entryOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(_entryCtrl);
    _entryRot = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 2.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 2.0, end: 0.0), weight: 40),
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
            opacity: _entryOpacity.value * _dismissOpacity.value,
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

/// 右下角圆形 FAB（棋盘 quick-send 入口）
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
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 20,
                  color: scheme.onSurface.withValues(alpha: widget.enabled ? 1.0 : 0.4),
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

  /// 顶部 head：表情 / 记录 tab + 关闭按钮
  Widget _buildHead(ColorScheme scheme) {
    return Row(
      children: [
        // 表情 tab
        _buildTab('表情', 'emoji', scheme),
        // 记录 tab（角标显示本局条数）
        _buildTab('记录', 'history', scheme,
            count: _uniqueHistory().length),
        const Spacer(),
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

  /// emoji tab：4 列 SVG 表情网格（来自 _kComposerEmojis）
  Widget _buildEmojiGrid(ColorScheme scheme) {
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
          for (final e in _kComposerEmojis)
            InkResponse(
              onTap: widget.enabled && !widget.sending
                  ? () => _doSendEmoji(e.id)
                  : null,
              radius: 18,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: _KvEmojiGradients.bySk(e.sk),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CustomPaint(
                    painter: _SvgIconPainter(e.svgPath),
                  ),
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
      final entry = _kComposerEmojis.firstWhere(
        (x) => x.id == e.emojiId,
        orElse: () => _kComposerEmojis.first,
      );
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          gradient: _KvEmojiGradients.bySk(entry.sk),
          borderRadius: BorderRadius.circular(4),
        ),
        child: SizedBox(
          width: 22,
          height: 22,
          child: CustomPaint(painter: _SvgIconPainter(entry.svgPath)),
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
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

/// sk 渐变背景表（mock 阶段 hardcoded；生产用 kv 上传图）
class _KvEmojiGradients {
  static final Map<String, LinearGradient> _cache = {};
  static LinearGradient bySk(String sk) {
    return _cache.putIfAbsent(sk, () {
      final c = _stopColors[sk] ?? (_stopColors['sk-a']!);
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: c,
      );
    });
  }

  static const Map<String, List<Color>> _stopColors = {
    'sk-a': [Color(0xFFFFE08A), Color(0xFFF5A623)],
    'sk-b': [Color(0xFFA8E6CF), Color(0xFF3DDC97)],
    'sk-c': [Color(0xFFFFB3BA), Color(0xFFFF6B6B)],
    'sk-d': [Color(0xFFB5D5FF), Color(0xFF2A6FDB)],
    'sk-e': [Color(0xFFE0D4FF), Color(0xFF8B5CF6)],
    'sk-f': [Color(0xFFFFD6A5), Color(0xFFC2410C)],
    'sk-g': [Color(0xFFFFE0B2), Color(0xFFFF9800)],
    'sk-h': [Color(0xFFB2DFDB), Color(0xFF009688)],
    'sk-i': [Color(0xFFF8BBD0), Color(0xFFEC407A)],
    'sk-j': [Color(0xFFFFF59D), Color(0xFFFBC02D)],
    'sk-k': [Color(0xFFC8E6C9), Color(0xFF43A047)],
    'sk-l': [Color(0xFF90CAF9), Color(0xFF1565C0)],
  };
}

/// CustomPainter：把 SVG path 描成白色描线图标（24x24 viewBox）
class _SvgIconPainter extends CustomPainter {
  final String svgPath;
  _SvgIconPainter(this.svgPath);

  @override
  void paint(Canvas canvas, Size size) {
    final metrics = _parsePath(svgPath);
    if (metrics == null) return;
    final scaleX = size.width / 24.0;
    final scaleY = size.height / 24.0;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.2 / ((scaleX + scaleY) / 2)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final path in metrics) {
      canvas.save();
      canvas.scale(scaleX, scaleY);
      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  /// 极简 SVG path 解析：支持 M / L / H / V / C / Z / 数字。
  /// 不处理 S/Q/T/A 等（mock 数据里只用 M/L/C/Z 已够）。
  List<Path>? _parsePath(String d) {
    try {
      final tokens = d.split(RegExp(r'[\s,]'));
      final out = <Path>[];
      Path? cur;
      int i = 0;
      double lastX = 0, lastY = 0;
      while (i < tokens.length) {
        final tok = tokens[i].trim();
        if (tok.isEmpty) { i++; continue; }
        if (tok == 'M' || tok == 'L') {
          final x = double.parse(tokens[++i]);
          final y = double.parse(tokens[++i]);
          cur = Path()..moveTo(x, y);
          lastX = x; lastY = y;
          out.add(cur);
        } else if (tok == 'm' || tok == 'l') {
          final x = lastX + double.parse(tokens[++i]);
          final y = lastY + double.parse(tokens[++i]);
          cur ??= Path();
          cur.lineTo(x, y);
          lastX = x; lastY = y;
        } else if (tok == 'C' || tok == 'c') {
          final x1 = double.parse(tokens[++i]);
          final y1 = double.parse(tokens[++i]);
          final x2 = double.parse(tokens[++i]);
          final y2 = double.parse(tokens[++i]);
          final x = double.parse(tokens[++i]);
          final y = double.parse(tokens[++i]);
          if (tok == 'c') {
            cur!.cubicTo(
              lastX + x1, lastY + y1,
              lastX + x2, lastY + y2,
              lastX + x, lastY + y,
            );
          } else {
            cur!.cubicTo(x1, y1, x2, y2, x, y);
          }
          lastX = (tok == 'c') ? lastX + x : x;
          lastY = (tok == 'c') ? lastY + y : y;
        } else if (tok == 'Z' || tok == 'z') {
          cur?.close();
        } else {
          // 数字：作为隐式 L (lineTo) — 简化处理
          final n = double.parse(tok);
          if (cur == null) break;
          cur.lineTo(n, lastY);
          lastX = n;
        }
        i++;
      }
      return out.where((p) => p != null).toList();
    } catch (_) {
      return null;
    }
  }

  @override
  bool shouldRepaint(covariant _SvgIconPainter oldDelegate) =>
      oldDelegate.svgPath != svgPath;
}
