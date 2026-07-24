// lib/core/net_engine/widgets/participants_grid.dart
//
// 通用参与者圆环卡片 — 显示房间中已就绪和等待中的玩家
//
// 用法：
// ```dart
// LobbyParticipants(
//   capacity: 4,
//   participants: {'id1': '小明', 'id2': '小红'},
// )
// ```
//
// 效果：彩色圆环头像 + 名字标签 + 等待中呼吸圆环

import 'package:flutter/material.dart';

/// 默认参与者颜色表
const kParticipantColors = [
  Color(0xFF4F8CF7),
  Color(0xFF34C759),
  Color(0xFFFF9500),
  Color(0xFFAF52DE),
  Color(0xFF5AC8FA),
  Color(0xFFFF2D55),
  Color(0xFF5856D6),
  Color(0xFF00C7BE),
  Color(0xFFFFD60A),
  Color(0xFFFF6B6B),
  Color(0xFFA2845E),
  Color(0xFFBF5AF2),
];

/// 参与者圆环卡片
///
/// [capacity] 房间总人数
/// [participants] 已就绪玩家（deviceId → alias），按 Map 插入顺序显示
/// [colors] 颜色表，默认 [kParticipantColors]
/// [slotSize] 圆环直径，默认 66
class LobbyParticipants extends StatelessWidget {
  const LobbyParticipants({
    super.key,
    required this.capacity,
    required this.participants,
    this.colors = kParticipantColors,
    this.slotSize = 66,
  });

  final int capacity;
  final Map<String, String> participants;
  final List<Color> colors;
  final double slotSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = participants.entries.toList();
    // 按名字排序保持稳定
    entries.sort((a, b) => a.value.compareTo(b.value));

    final slots = <Widget>[];
    for (var i = 0; i < capacity; i++) {
      final delay = i * 60;
      if (i < entries.length) {
        final e = entries[i];
        final color = colors[i % colors.length];
        slots.add(_AnimatedSlot(
          delay: delay,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: slotSize,
                height: slotSize,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.08)],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.5), width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.15),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    e.value.isNotEmpty ? e.value[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: slotSize * 0.4,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                e.value,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Text(
                '已就绪',
                style: TextStyle(fontSize: 10, color: Colors.green.shade400),
              ),
            ],
          ),
        ));
      } else {
        slots.add(_AnimatedSlot(
          delay: delay,
          child: _EmptySlot(slotSize: slotSize),
        ));
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: Colors.green.shade400, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  '参与者',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Text(
                  '${participants.length}/$capacity',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 28,
              runSpacing: 28,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: slots,
            ),
          ],
        ),
      ),
    );
  }
}

// ——— 飞入动画 slot ———

class _AnimatedSlot extends StatefulWidget {
  final int delay;
  final Widget child;
  const _AnimatedSlot({required this.delay, required this.child});

  @override
  State<_AnimatedSlot> createState() => _AnimatedSlotState();
}

class _AnimatedSlotState extends State<_AnimatedSlot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Transform.scale(scale: _anim.value, child: Opacity(opacity: _anim.value, child: child)),
      child: widget.child,
    );
  }
}

// ——— 空位呼吸圆环 ———

class _EmptySlot extends StatefulWidget {
  final double slotSize;
  const _EmptySlot({required this.slotSize});

  @override
  State<_EmptySlot> createState() => _EmptySlotState();
}

class _EmptySlotState extends State<_EmptySlot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
    _ctrl.repeat(reverse: true);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Opacity(opacity: 0.4 + _ctrl.value * 0.3, child: child),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: widget.slotSize,
            height: widget.slotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: 2,
                style: BorderStyle.solid,
              ),
            ),
            child: Center(
              child: Icon(Icons.person_add_alt_1, size: widget.slotSize * 0.36, color: theme.colorScheme.outlineVariant),
            ),
          ),
          const SizedBox(height: 6),
          Text('等待中', style: TextStyle(fontSize: 10, color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}
