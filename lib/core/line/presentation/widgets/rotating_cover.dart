import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 旋转封面组件（胶片效果）
class RotatingCover extends StatefulWidget {
  final String imagePath;
  final double size;
  final double borderWidth;

  const RotatingCover({
    super.key,
    required this.imagePath,
    this.size = 120,
    this.borderWidth = 2,
  });

  @override
  State<RotatingCover> createState() => _RotatingCoverState();
}

class _RotatingCoverState extends State<RotatingCover>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * math.pi,
          child: child,
        );
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: 0.5),
            width: widget.borderWidth,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.2),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipOval(
          child: _buildImage(),
        ),
      ),
    );
  }

  Widget _buildImage() {
    // 判断是远程 URL 还是本地 assets
    if (widget.imagePath.startsWith('http://') || widget.imagePath.startsWith('https://')) {
      return Image.network(
        widget.imagePath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }
    return Image.asset(
      widget.imagePath,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _placeholder(),
    );
  }

  Widget _placeholder() {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      color: color.withValues(alpha: 0.1),
      child: Icon(
        Icons.music_note,
        color: color.withValues(alpha: 0.5),
        size: widget.size * 0.4,
      ),
    );
  }
}
