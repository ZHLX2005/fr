// lib/core/game_kit/emoji/emoji_overlay.dart
//
// Emoji overlay — 监听 p2p 快照的 `emojis` 列表，转为 2s 飞行展示。
//
// 快照约定（由各游戏 Lua 的 EMOJI handler 写入 c.emojis）：
//   c.emojis: List<{ id, emoji_id, from, seq, at }>
//
// 客户端：seq 去重 + 打开时清空已见集合 → 每条只飞一次。
// 锚点：靠近发送方头像/边缘（简化：board 顶部按 from 侧浮动）。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../skin/file_resolver.dart';
import 'emoji_bundle.dart';

/// 快照中的单条 emoji 事件（服务端权威）。
class SnapshotEmojiEvent {
  final String id;
  final String emojiId;
  final String from;
  final int seq;
  final int atMs;

  const SnapshotEmojiEvent({
    required this.id,
    required this.emojiId,
    required this.from,
    required this.seq,
    required this.atMs,
  });

  factory SnapshotEmojiEvent.fromJson(Map<String, dynamic> j) =>
      SnapshotEmojiEvent(
        id: (j['id'] ?? j['emoji_id'] ?? j['emojiId'] ?? j['seq'])?.toString() ?? '',
        emojiId: (j['emoji_id'] ?? j['emojiId'] ?? j['id'] ?? j['emoji'] ?? '')
            .toString(),
        from: (j['from'] ?? j['device_id'] ?? '').toString(),
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        atMs: (j['at'] as num?)?.toInt() ??
            (j['ts'] as num?)?.toInt() ??
            0,
      );
}

/// 从快照 context 读取 emojis 列表（兼容多种字段名）。
List<SnapshotEmojiEvent> emojisFromSnapshot(Map<String, dynamic> ctx) {
  final candidates = <String>[
    'emojiRing',
    'emojis',
    'emoji_events',
    'recent_emojis',
  ];
  for (final key in candidates) {
    final raw = ctx[key];
    if (raw is List && raw.isNotEmpty) {
      final out = <SnapshotEmojiEvent>[];
      for (final item in raw) {
        if (item is! Map) continue;
        try {
          final e = SnapshotEmojiEvent.fromJson(
              Map<String, dynamic>.from(item as Map<String, dynamic>));
          if (e.emojiId.isEmpty) continue;
          out.add(e);
        } catch (_) {}
      }
      if (out.isNotEmpty) return out;
    }
  }
  return const [];
}

/// 单个飞行中的 emoji（用于 overlay 队列）。
class FlyingEmoji {
  final SnapshotEmojiEvent event;
  final String resolvedChar;
  final ImageProvider? image;
  final bool fromMe;
  final int seqKey;

  FlyingEmoji({
    required this.event,
    required this.resolvedChar,
    this.image,
    required this.fromMe,
    required this.seqKey,
  });
}

/// Emoji 飞行 overlay（Stack 底层之上）。
///
/// 用法：
/// ```dart
/// EmojiOverlay(
///   myDeviceId: handle.transport.deviceId,
///   bundle: bundle, // EmojiBundle.forGame('chess') 的结果
///   fileResolver: PublicFileResolver(baseUrl: ApiConfig.production().baseUrl),
///   emojis: emojisFromSnapshot(snapshot.context),
///   myColorIsWhite: _myColor == PieceColor.white, // 可选：锚点侧
/// )
/// ```
class EmojiOverlay extends StatefulWidget {
  /// 最新快照中的 emojis 列表（已按服务端顺序）。
  final List<SnapshotEmojiEvent> emojis;

  /// 本机 deviceId（用于判断 fromMe → 锚点侧）。
  final String myDeviceId;

  /// 当前生效的 bundle（用于把 emojiId 解析为字符或图）。
  final EmojiBundle bundle;

  /// 文件解析器（远端图走 NetworkImage 时需要）。
  final FileResolver? fileResolver;

  /// 单条飞行时长（默认 2s）。
  final Duration flyDuration;

  /// 我方是否执白（用于锚点侧；null = 不区分侧，统一居中起飞）。
  final bool? myColorIsWhite;

  const EmojiOverlay({
    super.key,
    required this.emojis,
    required this.myDeviceId,
    required this.bundle,
    this.fileResolver,
    this.flyDuration = const Duration(milliseconds: 2000),
    this.myColorIsWhite,
  });

  @override
  State<EmojiOverlay> createState() => _EmojiOverlayState();
}

class _EmojiOverlayState extends State<EmojiOverlay> {
  /// 已见 seq（去重：同 seq 不重复入队）。
  final Set<int> _seenSeq = {};
  final Set<String> _seenId = {};

  /// 飞行队列（每项带独立的 Timer 清理）。
  final List<FlyingEmoji> _flying = [];
  final Map<int, Timer> _timers = {};

  @override
  void initState() {
    super.initState();
    _ingest(widget.emojis);
  }

  @override
  void didUpdateWidget(covariant EmojiOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.myDeviceId, widget.myDeviceId) ||
        oldWidget.myDeviceId != widget.myDeviceId) {
      _seenSeq.clear();
      _seenId.clear();
      // 切号不清空飞行队列（视觉连贯），仅重置去重集合
    }
    _ingest(widget.emojis);
  }

  void _ingest(List<SnapshotEmojiEvent> events) {
    // lobby/RESET 后 ring 清空：events 变短时清理已见集合以免跨局泄漏
    if (events.length < _seenSeq.length) {
      _seenSeq.clear();
      _seenId.clear();
    }
    for (final e in events) {
      final seqKey = e.seq != 0 ? e.seq : e.id.hashCode;
      final idKey = e.id.isNotEmpty ? e.id : 'seq-$seqKey';
      if (e.seq != 0) {
        if (_seenSeq.contains(e.seq)) continue;
        _seenSeq.add(e.seq);
      } else {
        if (_seenId.contains(idKey)) continue;
        _seenId.add(idKey);
      }
      final entry = widget.bundle.byId[e.emojiId];
      final ch = entry?.unicode ?? _fallbackChar(e.emojiId);
      final img = entry?.imageProvider(widget.fileResolver);
      final fromMe = e.from.isNotEmpty && e.from == widget.myDeviceId;
      final flying = FlyingEmoji(
        event: e,
        resolvedChar: ch,
        image: img,
        fromMe: fromMe,
        seqKey: seqKey,
      );
      setState(() => _flying.add(flying));
      final timer = Timer(widget.flyDuration, () {
        if (!mounted) return;
        setState(() => _flying.removeWhere((f) => f.seqKey == seqKey));
        _timers.remove(seqKey);
      });
      _timers[seqKey]?.cancel();
      _timers[seqKey] = timer;
    }
  }

  String _fallbackChar(String emojiId) {
    const fallback = {
      'thumbs-up': '\u{1F44D}',
      'heart': '\u{2764}\u{FE0F}',
      'fire': '\u{1F525}',
      'laugh': '\u{1F602}',
      'cry': '\u{1F62D}',
      'angry': '\u{1F620}',
      'clap': '\u{1F44F}',
      'party': '\u{1F389}',
    };
    return fallback[emojiId] ?? '\u{2728}';
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
    if (_flying.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Stack(
        children: [
          for (var i = 0; i < _flying.length; i++)
            _FlyingEmojiWidget(
              key: ValueKey('emoji-fly-${_flying[i].seqKey}'),
              flying: _flying[i],
              index: i,
              total: _flying.length,
              duration: widget.flyDuration,
              myColorIsWhite: widget.myColorIsWhite,
            ),
        ],
      ),
    );
  }
}

class _FlyingEmojiWidget extends StatefulWidget {
  final FlyingEmoji flying;
  final int index;
  final int total;
  final Duration duration;
  final bool? myColorIsWhite;

  const _FlyingEmojiWidget({
    super.key,
    required this.flying,
    required this.index,
    required this.total,
    required this.duration,
    this.myColorIsWhite,
  });

  @override
  State<_FlyingEmojiWidget> createState() => _FlyingEmojiWidgetState();
}

class _FlyingEmojiWidgetState extends State<_FlyingEmojiWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rise;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _rise = Tween<double>(begin: 0, end: -120).animate(curve);
    _fade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(curve);
    _scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.6, end: 1.15)
              .chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.85), weight: 55),
    ]).animate(curve);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fromMe = widget.flying.fromMe;
    // 锚点：我方发的靠底边起飞，对方发的靠顶边起飞；
    // 未知侧（myColorIsWhite == null）统一居中偏下。
    final Alignment alignment;
    if (widget.myColorIsWhite == null) {
      alignment = fromMe ? Alignment.bottomCenter : Alignment.topCenter;
    } else {
      alignment = fromMe ? Alignment.bottomCenter : Alignment.topCenter;
    }
    // dedup on lobby re-enter: state 快照离开 playing -> 见 _ingest 清理
    // 同屏多条时横向错开（-0.2..0.2）
    final jitter = (widget.index % 5 - 2) * 0.08;
    // 轻微弧线：用 sin 做 x 偏移
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final arcX = math.sin(t * math.pi) * 18 * (fromMe ? 1 : -1);
        final y = _rise.value;
        return Align(
          alignment: alignment,
          child: FractionalTranslation(
            translation: Offset(jitter + arcX / 360, 0),
            child: Transform.translate(
              offset: Offset(arcX, y),
              child: Opacity(
                opacity: _fade.value.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: _scale.value,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    final img = widget.flying.image;
    if (img != null) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(6),
        child: Image(
          image: img,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Text(
            widget.flying.resolvedChar,
            style: const TextStyle(fontSize: 28, height: 1),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        widget.flying.resolvedChar,
        style: const TextStyle(fontSize: 28, height: 1),
      ),
    );
  }
}
