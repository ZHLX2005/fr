import 'package:flutter/material.dart';
import '../providers/draggable_word_card_controller.dart';

/// 滑动方向枚举
enum SwipeDirection { left, right, up, none }

/// 弹性单词卡片
///
/// 状态管理由 WordDragNotifier 处理，此组件负责手势和动画
class DraggableWordCard extends StatefulWidget {
  final Widget child;
  final DraggableWordCardController controller;
  /// 偏移量变化回调
  final void Function(Offset offset)? onOffsetChanged;
  /// 拖动结束回调
  final VoidCallback? onDragEnd;
  /// 滑动方向回调
  final void Function(SwipeDirection direction)? onSwipeComplete;
  /// 动画目标偏移量
  final Offset? targetOffset;

  const DraggableWordCard({
    super.key,
    required this.child,
    required this.controller,
    this.onOffsetChanged,
    this.onDragEnd,
    this.onSwipeComplete,
    this.targetOffset,
  });

  @override
  State<DraggableWordCard> createState() => _DraggableWordCardState();
}

class _DraggableWordCardState extends State<DraggableWordCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Animation<Offset>? _animation;

  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  SwipeDirection _swipeDirection = SwipeDirection.none;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
    _controller.addListener(_onAnimationUpdate);

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
      widget.onOffsetChanged?.call(_dragOffset);
    }
  }

  void _onPanStart() {
    _controller.stop();
    setState(() {
      _dragOffset = Offset.zero;
      _isDragging = true;
    });
    widget.onOffsetChanged?.call(_dragOffset);
  }

  void _onPanUpdate(Offset delta) {
    if (!_isDragging) return;
    setState(() {
      _dragOffset += delta;
    });
    widget.onOffsetChanged?.call(_dragOffset);
  }

  void _onPanEnd() {
    if (!_isDragging) return;
    _isDragging = false;

    final screenSize = MediaQuery.of(context).size;
    final thresholdX = screenSize.width * 0.15;
    final thresholdY = screenSize.height * 0.12;

    // 判断滑动方向
    if (_dragOffset.dy < -thresholdY && _dragOffset.dy.abs() > _dragOffset.dx.abs()) {
      _swipeDirection = SwipeDirection.up;
    } else if (_dragOffset.dx > thresholdX) {
      _swipeDirection = SwipeDirection.right;
    } else if (_dragOffset.dx < -thresholdX) {
      _swipeDirection = SwipeDirection.left;
    } else {
      _swipeDirection = SwipeDirection.none;
    }

    // 如果有明确方向，滑出屏幕
    if (_swipeDirection != SwipeDirection.none) {
      _animateOffScreenDirection(_swipeDirection);
    } else {
      // 否则弹回
      _springBack();
    }
  }

  void _animateOffScreenDirection(SwipeDirection direction) {
    final screenSize = MediaQuery.of(context).size;
    Offset target;

    switch (direction) {
      case SwipeDirection.up:
        target = Offset(0, -screenSize.height);
        break;
      case SwipeDirection.left:
        target = Offset(-screenSize.width * 1.5, 0);
        break;
      case SwipeDirection.right:
        target = Offset(screenSize.width * 1.5, 0);
        break;
      case SwipeDirection.none:
        return;
    }

    _animation = Tween<Offset>(
      begin: _dragOffset,
      end: target,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller
      ..value = 0.0
      ..animateTo(1.0, duration: const Duration(milliseconds: 300)).then((_) {
        widget.onSwipeComplete?.call(direction);
        widget.onDragEnd?.call();
      });
  }

  void _springBack() {
    _animation = Tween<Offset>(
      begin: _dragOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    _controller
      ..value = 0.0
      ..animateTo(1.0, duration: const Duration(milliseconds: 600)).then((_) {
        widget.onDragEnd?.call();
      });
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