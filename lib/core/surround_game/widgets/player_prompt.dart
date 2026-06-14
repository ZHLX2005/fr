/// 合法落子提示叠加层
///
/// 当选中己方棋子后，在棋盘上以半透明高亮块标记所有合法移动目标格子。
///
/// 视觉效果：每个目标格中央有一个圆形"光圈"，alpha 在 0.35↔0.7 之间
/// 缓慢呼吸（~1.4s easeInOut），颜色来自 [BoardThemeData.validMoveRing]。
import 'package:flutter/material.dart';
import '../board_theme.dart';

/// validMoves 高亮叠加层
///
/// 必须使用 [StatefulWidget] 才能挂载 [AnimationController] 来驱动呼吸光圈。
/// 控件不显式 dispose controller（依赖父级 Widget 卸载时 dispose 链）。
class PlayerPrompt extends StatefulWidget {
  final Set<int> validMoves;
  final double cellSize;
  final BoardThemeData theme;
  final bool visible;

  const PlayerPrompt({
    super.key,
    required this.validMoves,
    required this.cellSize,
    required this.theme,
    this.visible = false,
  });

  @override
  State<PlayerPrompt> createState() => _PlayerPromptState();
}

class _PlayerPromptState extends State<PlayerPrompt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;
  late final Animation<double> _alpha;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    // 0.35 → 0.7 → 0.35
    _alpha = Tween<double>(begin: 0.35, end: 0.7).animate(
      CurvedAnimation(parent: _breath, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible || widget.validMoves.isEmpty) {
      return const SizedBox.shrink();
    }

    final distance = widget.cellSize * 1.25;
    // 严格对齐 ChessBoard 细胞坐标：x*distance + 1, 大小 = cellSize - 2
    final cellSize_ = widget.cellSize - 2;
    // 呼吸光圈直径 = 格子内切圆，留 25% 内边距
    final ringSize = cellSize_ * 0.5;
    final ringOffset = (cellSize_ - ringSize) / 2;
    final ringColor = widget.theme.validMoveRing;

    final children = widget.validMoves.map((cellId) {
      final x = (cellId % 9).toDouble();
      final y = (cellId ~/ 9).toDouble();
      final left = x * distance + 1;
      final top = y * distance + 1;

      return Positioned(
        left: left,
        top: top,
        child: Container(
          width: cellSize_,
          height: cellSize_,
          decoration: BoxDecoration(
            // 格子底色 — 极淡的环色，让目标格"亮一下"
            color: ringColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            children: [
              // 中央呼吸光圈
              Positioned(
                left: ringOffset,
                top: ringOffset,
                child: AnimatedBuilder(
                  animation: _alpha,
                  builder: (context, _) {
                    return Container(
                      width: ringSize,
                      height: ringSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ringColor.withValues(alpha: _alpha.value * 0.6),
                        boxShadow: [
                          BoxShadow(
                            color: ringColor.withValues(alpha: _alpha.value * 0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();

    return Stack(children: children);
  }
}
