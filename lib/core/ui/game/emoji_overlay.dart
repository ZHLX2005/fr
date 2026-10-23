// lib/core/game_kit/emoji/emoji_overlay.dart
//
// Emoji 表情：微信风格小对话框气泡（圆角矩形 + 尖角），无飞行动画。
// - 对方发的：贴顶部对方侧（左侧），尖角朝上偏左
// - 自己发的：贴底部自己侧（右侧），尖角朝下偏右
// - 仅显示 bundle.byId[emojiId] 命中的上传表情；未知 id 静默忽略

import 'dart:async';

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
        id: (j['id'] ?? j['emoji_id'] ?? j['emojiId'] ?? j['seq']).toString(),
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
          final e = SnapshotEmojiEvent.fromJson(Map<String, dynamic>.from(item));
          if (e.emojiId.isEmpty) continue;
          out.add(e);
        } catch (_) {}
      }
      if (out.isNotEmpty) return out;
    }
  }
  return const [];
}

class _ActiveBubble {
  final SnapshotEmojiEvent event;
  final ImageProvider image;
  final bool fromMe;
  final int seqKey;

  _ActiveBubble({
    required this.event,
    required this.image,
    required this.fromMe,
    required this.seqKey,
  });
}

/// 微信风格对话框气泡：圆角白底 + 表情图 + 小尖角。
class _ChatBubble extends StatelessWidget {
  final ImageProvider image;
  final bool fromMe;

  const _ChatBubble({required this.image, required this.fromMe});

  static const double _size = 56;
  static const double _pad = 8;
  static const double _radius = 14;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = fromMe
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;

    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!fromMe)
            CustomPaint(
              size: const Size(12, 6),
              painter: _TailPainter(color: bg, up: true),
            ),
          Container(
            width: _size,
            height: _size,
            padding: const EdgeInsets.all(_pad),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(_radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Image(
              image: image,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          if (fromMe)
            CustomPaint(
              size: const Size(12, 6),
              painter: _TailPainter(color: bg, up: false),
            ),
        ],
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  final Color color;
  final bool up;

  _TailPainter({required this.color, required this.up});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (up) {
      // 尖角朝上（对方气泡贴顶部）
      path.moveTo(size.width * 0.25, size.height);
      path.lineTo(size.width * 0.45, 0);
      path.lineTo(size.width * 0.65, size.height);
    } else {
      // 尖角朝下（自己气泡贴底部）
      path.moveTo(size.width * 0.35, 0);
      path.lineTo(size.width * 0.55, size.height);
      path.lineTo(size.width * 0.75, 0);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TailPainter old) =>
      old.color != color || old.up != up;
}

/// EmojiOverlay：静态小气泡，无飞行/缩放动画。
class EmojiOverlay extends StatefulWidget {
  final List<SnapshotEmojiEvent> emojis;
  final String myDeviceId;
  final EmojiBundle bundle;
  final FileResolver? fileResolver;

  /// 单条气泡显示时长。
  final Duration displayDuration;

  /// 对方气泡距顶部的偏移（让出 AppBar）。
  final double topInset;

  /// 自己气泡距底部的偏移（让出操作条）。
  final double bottomInset;

  /// 左右边距。
  final double horizontalInset;

  /// 同屏最多保留多少条。
  final int maxVisible;

  const EmojiOverlay({
    super.key,
    required this.emojis,
    required this.myDeviceId,
    required this.bundle,
    this.fileResolver,
    this.displayDuration = const Duration(seconds: 3),
    this.topInset = 72,
    this.bottomInset = 120,
    this.horizontalInset = 20,
    this.maxVisible = 3,
  });

  @override
  State<EmojiOverlay> createState() => _EmojiOverlayState();
}

class _EmojiOverlayState extends State<EmojiOverlay> {
  final Set<int> _seenSeq = {};
  final Set<String> _seenId = {};
  final List<_ActiveBubble> _bubbles = [];
  final Map<int, Timer> _timers = {};

  @override
  void initState() {
    super.initState();
    _ingest(widget.emojis);
  }

  @override
  void didUpdateWidget(covariant EmojiOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.myDeviceId != widget.myDeviceId) {
      _seenSeq.clear();
      _seenId.clear();
    }
    _ingest(widget.emojis);
  }

  void _ingest(List<SnapshotEmojiEvent> events) {
    // lobby/RESET 后 ring 清空
    if (events.length < _seenSeq.length && events.isEmpty) {
      _seenSeq.clear();
      _seenId.clear();
    }

    var changed = false;
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
      if (entry == null) continue;
      final img = entry.imageProvider(widget.fileResolver);
      if (img == null) continue;

      final fromMe = e.from.isNotEmpty && e.from == widget.myDeviceId;
      _bubbles.add(_ActiveBubble(
        event: e,
        image: img,
        fromMe: fromMe,
        seqKey: seqKey,
      ));
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
      });
      changed = true;
    }
    if (changed) setState(() {});
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

    // 对方气泡叠在顶部左侧；自己的叠在底部右侧
    final theirs = <_ActiveBubble>[];
    final mine = <_ActiveBubble>[];
    for (final b in _bubbles) {
      (b.fromMe ? mine : theirs).add(b);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < theirs.length; i++)
          Positioned(
            top: widget.topInset + i * 68,
            left: widget.horizontalInset,
            child: IgnorePointer(
              child: _ChatBubble(image: theirs[i].image, fromMe: false),
            ),
          ),
        for (var i = 0; i < mine.length; i++)
          Positioned(
            bottom: widget.bottomInset + i * 68,
            right: widget.horizontalInset,
            child: IgnorePointer(
              child: _ChatBubble(image: mine[i].image, fromMe: true),
            ),
          ),
      ],
    );
  }
}
