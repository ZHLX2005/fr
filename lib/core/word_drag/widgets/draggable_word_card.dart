import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 弹性单词卡片 - 核心拖动动效组件
///
/// 关键技术点：
/// 1. SpringSimulation 实现弹性回弹
/// 2. 拖动时卡片跟随手指，带有旋转和缩放反馈
/// 3. 超过阈值后触发方向判定
/// 4. 拖动边界有弹性阻尼效果
class DraggableWordCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSwipeLeft;    // 左滑回调
  final VoidCallback? onSwipeRight;   // 右滑回调（删除）
  final VoidCallback? onSwipeUp;       // 上滑回调（详细阅读）
  final Function(DragUpdateDetails)? onDragUpdate;
  final Function(DraggableCardState)? onCardStateChanged;

  // 弹性参数
  final double swipeThreshold;        // 触发滑动的阈值（默认0.3屏幕宽度）
  final double rotationFactor;         // 旋转角度系数
  final double scaleFactor;            // 拖动时缩小比例
  final SpringDescription spring;      // 弹簧参数

  const DraggableWordCard({
    super.key,
    required this.child,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.onSwipeUp,
    this.onDragUpdate,
    this.onCardStateChanged,
    this.swipeThreshold = 0.3,
    this.rotationFactor = 0.002,
    this.scaleFactor = 0.95,
    SpringDescription? spring,
  }) : spring = spring ?? const SpringDescription(
        mass: 1.0,
        stiffness: 500.0,
        damping: 25.0,
      );

  @override
  State<DraggableWordCard> createState() => DraggableCardState();
}

class DraggableCardState extends State<DraggableWordCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;

  Offset _dragOffset = Offset.zero;
  Offset _dragVelocity = Offset.zero;
  bool _isDragging = false;

  // 当前状态
  SwipeDirection? _swipeDirection;

  //  getters
  bool get isDragging => _isDragging;
  Offset get currentOffset => _dragOffset;
  SwipeDirection? get swipeDirection => _swipeDirection;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
    _animation = _controller
        .drive(Tween<Offset>(begin: Offset.zero, end: Offset.zero));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    _controller.stop();
    setState(() {
      _isDragging = true;
      _swipeDirection = null;
    });
    widget.onCardStateChanged?.call(this);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta;
    });
    widget.onDragUpdate?.call(details);
  }

  void _onPanEnd(DragEndDetails details) {
    _dragVelocity = details.velocity.pixelsPerSecond;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final thresholdX = screenWidth * widget.swipeThreshold;
    final thresholdY = screenHeight * 0.2; // 上滑阈值较小

    _isDragging = false;

    // 判定滑动方向
    SwipeDirection? direction;

    if (_dragOffset.dy < -thresholdY &&
        _dragOffset.dy.abs() > _dragOffset.dx.abs()) {
      // 上滑
      direction = SwipeDirection.up;
    } else if (_dragOffset.dx > thresholdX) {
      // 右滑
      direction = SwipeDirection.right;
    } else if (_dragOffset.dx < -thresholdX) {
      // 左滑
      direction = SwipeDirection.left;
    }

    if (direction != null) {
      _swipeDirection = direction;
      _animateOffScreen(direction);
    } else {
      _springBack();
    }

    widget.onCardStateChanged?.call(this);
  }

  void _springBack() {
    _animation = _controller.drive(
      Tween<Offset>(begin: _dragOffset, end: Offset.zero),
    );

    // 使用弹簧动画回弹
    _controller.animateWith(
      SpringSimulation(widget.spring, 0, 1, -_dragVelocity.distance / 1000),
    );

    _controller.addListener(_springBackListener);
  }

  void _springBackListener() {
    setState(() {
      _dragOffset = _animation.value;
    });
  }

  void _animateOffScreen(SwipeDirection direction) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    late Offset targetOffset;
    switch (direction) {
      case SwipeDirection.right:
        targetOffset = Offset(screenWidth * 1.5, _dragOffset.dy);
        widget.onSwipeRight?.call();
        break;
      case SwipeDirection.left:
        targetOffset = Offset(-screenWidth * 1.5, _dragOffset.dy);
        widget.onSwipeLeft?.call();
        break;
      case SwipeDirection.up:
        targetOffset = Offset(_dragOffset.dx, -screenHeight);
        widget.onSwipeUp?.call();
        break;
      case SwipeDirection.down:
        targetOffset = Offset(_dragOffset.dx, screenHeight * 1.5);
        break;
    }

    _animation = _controller.drive(
      Tween<Offset>(begin: _dragOffset, end: targetOffset),
    );

    _controller.animateTo(
      1.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    ).then((_) {
      setState(() {
        _dragOffset = targetOffset;
      });
    });

    _controller.addListener(() {
      setState(() {
        _dragOffset = _animation.value;
      });
    });
  }

  // 外部可以调用的重置方法
  void reset() {
    _controller.removeListener(_springBackListener);
    _springBack();
  }

  @override
  Widget build(BuildContext context) {
    // 计算弹性边界阻尼
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 弹性阻尼：越接近边界，阻力越大
    final dampingX = _calculateDamping(_dragOffset.dx, screenWidth);
    final dampingY = _calculateDamping(_dragOffset.dy, screenHeight);

    final dampedOffset = Offset(
      _dragOffset.dx * dampingX,
      _dragOffset.dy * dampingY,
    );

    // 旋转角度：随拖动距离变化
    final rotation = dampedOffset.dx * widget.rotationFactor;

    // 缩放：拖动时缩小
    final distance = dampedOffset.distance;
    final maxDistance = screenWidth;
    final scale = 1.0 - (distance / maxDistance * (1 - widget.scaleFactor));

    // 透明度：随拖动距离变化
    final opacity = (scale * 1.5).clamp(0.5, 1.0);

    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translate(dampedOffset.dx, dampedOffset.dy)
              ..rotateZ(rotation)
              ..scale(scale.clamp(0.8, 1.0)),
            child: Opacity(
              opacity: opacity,
              child: widget.child,
            ),
          );
        },
      ),
    );
  }

  /// 计算边界阻尼 - 核心弹性效果
  /// 越靠近边界，阻力越大，产生"推不动"的感觉
  double _calculateDamping(double offset, double maxExtent) {
    const boundaryZone = 0.25; // 边界区域比例

    final absOffset = offset.abs();

    if (absOffset > maxExtent) {
      // 超出边界后，阻尼急剧增大
      final excess = absOffset - maxExtent;
      final dampedExcess = excess / (excess + maxExtent * 0.3);
      return 1.0 - dampedExcess * 0.6; // 最多衰减到0.4
    }

    return 1.0; // 正常区域无阻尼
  }
}

enum SwipeDirection { left, right, up, down }
