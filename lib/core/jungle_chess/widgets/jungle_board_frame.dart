// lib/core/jungle_chess/widgets/jungle_board_frame.dart
import 'package:flutter/material.dart';

/// 棋盘装饰外框：白底卡片 + 柔和阴影 + 圆角
/// 卡通风格：简单、干净、轻盈
class JungleBoardFrame extends StatelessWidget {
  final Widget child;
  const JungleBoardFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E40AF).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
    );
  }
}