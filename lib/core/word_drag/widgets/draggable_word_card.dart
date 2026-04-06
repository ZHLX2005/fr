import 'package:flutter/material.dart';
import '../providers/draggable_word_card_controller.dart';

/// 弹性单词卡片 - 纯 UI 组件
///
/// 状态管理由 WordDragNotifier 处理，此组件只负责 UI 渲染和手势转发
class DraggableWordCard extends StatefulWidget {
  final Widget child;
  final DraggableWordCardController controller;

  const DraggableWordCard({
    super.key,
    required this.child,
    required this.controller,
  });

  @override
  State<DraggableWordCard> createState() => _DraggableWordCardState();
}

class _DraggableWordCardState extends State<DraggableWordCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Animation<Offset>? _animation;

  Offset _dragOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
    _controller.addListener(_onAnimationUpdate);

    // 注册控制器回调
    widget.controller.screenSize = MediaQuery.of(context).size;
    widget.controller.onDragStart = _onPanStart;
    widget.controller.onDragUpdate = _onPanUpdate;
    widget.controller.onDragEnd = _onPanEnd;
  }

  @override
  void dispose() {
    _controller.removeListener(_onAnimationUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _onAnimationUpdate() {
    if (_animation != null && _controller.isAnimating) {
      setState(() {
        _dragOffset = _animation!.value;
      });
    }
  }

  void _onPanStart() {
    _controller.stop();
    setState(() {
      _dragOffset = Offset.zero;
    });
  }

  void _onPanUpdate(Offset delta) {
    setState(() {
      _dragOffset += delta;
    });
  }

  void _onPanEnd() {
    // 通知控制器处理拖动结束
    widget.controller.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 弹性阻尼
    final dampingX = _calculateDamping(_dragOffset.dx, screenWidth);
    final dampingY = _calculateDamping(_dragOffset.dy, screenHeight);

    final dampedOffset = Offset(
      _dragOffset.dx * dampingX,
      _dragOffset.dy * dampingY,
    );

    // 旋转
    final rotation = dampedOffset.dx * 0.0015;

    // 缩放
    final distance = dampedOffset.distance;
    final maxDistance = screenWidth * 0.8;
    final scale = 1.0 - (distance / maxDistance * 0.08);

    // 透明度
    final opacity = (scale * 1.2).clamp(0.6, 1.0);

    return GestureDetector(
      onPanStart: (_) => widget.controller.onDragStart?.call(),
      onPanUpdate: (details) => widget.controller.onDragUpdate?.call(details.delta),
      onPanEnd: (_) => widget.controller.onDragEnd?.call(),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..translate(_dragOffset.dx, _dragOffset.dy)
          ..rotateZ(rotation)
          ..scale(scale.clamp(0.85, 1.0)),
        child: Opacity(
          opacity: opacity,
          child: widget.child,
        ),
      ),
    );
  }

  double _calculateDamping(double offset, double maxExtent) {
    final absOffset = offset.abs();
    if (absOffset > maxExtent) {
      final excess = absOffset - maxExtent;
      final dampedExcess = excess / (excess + maxExtent * 0.3);
      return 1.0 - dampedExcess * 0.5;
    }
    return 1.0;
  }
}
