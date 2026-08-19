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

import '../../../widgets/context_game_colors.dart';

/// 参与者圆环卡片
///
/// [capacity] 房间总人数
/// [participants] 已就绪玩家（deviceId → alias），按 Map 插入顺序显示
/// [readyMap] 各玩家准备状态（deviceId → true/false），默认全 true
/// [colors] 颜色表；为 null 时从 `context.gameColors.avatarColors` 取（随主题切换）
/// [slotSize] 圆环直径，默认 66
/// [spectatorIds] 旁观者 deviceId 集合（房主不参与时标记为'旁观者'）
class LobbyParticipants extends StatelessWidget {
  const LobbyParticipants({
    super.key,
    required this.capacity,
    required this.participants,
    this.readyMap,
    this.spectatorIds,
    this.colors,
    this.slotSize = 66,
  });

  final int capacity;
  final Map<String, String> participants;
  final Map<String, bool>? readyMap;
  final Set<String>? spectatorIds;
  final List<Color>? colors;
  final double slotSize;

  /// 实际参与者数量（排除旁观者）
  int get activeCount {
    if (spectatorIds == null || spectatorIds!.isEmpty) return participants.length;
    return participants.keys.where((k) => !spectatorIds!.contains(k)).length;
  }

  /// 旁观看条目
  List<MapEntry<String, String>> get _spectatorEntries =>
      spectatorIds == null
          ? const []
          : participants.entries.where((e) => spectatorIds!.contains(e.key)).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = colors ?? context.gameColors.avatarColors;
    final allEntries = participants.entries.toList();
    // 按名字排序
    allEntries.sort((a, b) => a.value.compareTo(b.value));
    final playerEntries = spectatorIds == null || spectatorIds!.isEmpty
        ? allEntries
        : allEntries.where((e) => !spectatorIds!.contains(e.key)).toList();
    final watcherEntries = _spectatorEntries;

    final playerSlots = <Widget>[];
    // 参与者槽数 = max(牌数, 实际参与者人数)
    final playerSlotCount = playerEntries.length > capacity ? playerEntries.length : capacity;
    for (var i = 0; i < playerSlotCount; i++) {
      final delay = i * 60;
      if (i < playerEntries.length) {
        final e = playerEntries[i];
        final color = palette[i % palette.length];
        final isReady = readyMap?[e.key] == true;
        playerSlots.add(_AnimatedSlot(
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
                  border: Border.all(
                    color: isReady
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.9)
                        : color.withValues(alpha: 0.35),
                    width: isReady ? 3.5 : 2.0,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                  boxShadow: !isReady ? [] : [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    e.value.isNotEmpty ? e.value[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: slotSize * 0.4,
                      fontWeight: FontWeight.bold,
                      color: isReady ? Theme.of(context).colorScheme.primary : color,
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
                  color: isReady ? Theme.of(context).colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Text(
                isReady ? '已准备' : '未准备',
                style: TextStyle(fontSize: 10, color: isReady ? Theme.of(context).colorScheme.primary : theme.colorScheme.outline),
              ),
            ],
          ),
        ));
      } else {
        playerSlots.add(_AnimatedSlot(delay: delay, child: _EmptySlot(slotSize: slotSize)));
      }
    }

    return Column(
      children: [
        // ——— 参与者卡片 ———
        Card(
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
                      width: 8, height: 8,
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text('参与者',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Text('$activeCount/$capacity',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 28, runSpacing: 28,
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.start,
                  children: playerSlots,
                ),
              ],
            ),
          ),
        ),
        // ——— 旁观者卡片 ———
        if (watcherEntries.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
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
                      Icon(Icons.remove_red_eye_outlined, size: 14,
                          color: theme.colorScheme.outline),
                      const SizedBox(width: 6),
                      Text('旁观者',
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600, color: theme.colorScheme.outline)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 28, runSpacing: 20,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.start,
                    children: watcherEntries.map((e) {
                      return _AnimatedSlot(
                        delay: 0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: slotSize,
                              height: slotSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Icon(Icons.person_outline,
                                    size: slotSize * 0.45, color: theme.colorScheme.outline.withValues(alpha: 0.5)),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              e.value,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
                            ),
                            Text('旁观者',
                                style: TextStyle(fontSize: 10,
                                    color: theme.colorScheme.outline.withValues(alpha: 0.6))),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
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
      builder: (_, child) {
        // easeOutBack 会短暂 > 1.0（overshoot），opacity 必须 clamp
        final v = _anim.value.clamp(0.0, 1.0);
        return Transform.scale(scale: _anim.value, child: Opacity(opacity: v, child: child));
      },
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
