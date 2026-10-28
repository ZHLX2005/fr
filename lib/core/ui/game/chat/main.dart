// lib/core/ui/game/chat/main.dart
//
// 棋盘对话浮层 —— 所有 relay v3 对弈房通用（自 chess/p2p/widgets 下沉：
// 本组件只依赖 game_kit 的 chat_event / emoji_bundle / file_resolver，零棋种依赖）。
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
//
// 主题豁免（逐项，F2 设计规格移植保真，不随主题漂移）：
//   · 1A1A1A 硬黑边框/发送按钮底 —— F2 --text-1 identity 硬黑
//   · FAFAF7 tabs 容器底 —— F2 var(--bg)
//   · 9B9B9B 关闭图标 —— F2 --text-2
//   · 2A6FDB / C2410C 我方/对方身份色点 —— F2 身份色对（与 PlayerStrip 一致）
//
// 用法（宿主 = 对弈房页）：
//   Positioned.fill(
//     child: BoardChatOverlay(
//       events: chatEvents,                    // mergedChatEventsFromSnapshot(snap.context)
//       myDeviceId: handle.transport.deviceId,
//       emojiBundle: _emojiBundle,             // EmojiBundle.forGame(<game>) 懒加载
//       onSendEmoji: ..., onSendText: ...,     // 宿主实现 EMOJI / CHAT action
//       enabled: ...,
//     ),
//   )

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../game_kit/chat/chat_event.dart';
import '../../../game_kit/emoji/emoji_bundle.dart';
import '../../../game_kit/skin/file_resolver.dart';
import '../../global/notification/main.dart';

part 'chat_pill.dart';
part 'composer.dart';
part 'painters.dart';

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
      if (mounted) _toast('表情发送失败', type: AppNotificationType.error);
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
      if (mounted) _toast('发送失败', type: AppNotificationType.error);
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String msg, {AppNotificationType type = AppNotificationType.warning}) {
    if (!mounted) return;
    AppNotification.show(context, msg,
        type: type, duration: const Duration(milliseconds: 1000));
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
