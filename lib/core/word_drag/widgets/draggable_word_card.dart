import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 弹性单词卡片 - 核心拖动动效组件
///
/// 关键技术点：
/// 1. SpringSimulation 实现弹性回弹
/// 2. 拖动时卡片跟随手指，带有旋转和缩放反馈
/// 3. 拖动边界有弹性阻尼效果
/// 4. 右滑时显示删除区，必须拖入区域才删除
class DraggableWordCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSwipeLeft;      // 左滑回调（稍后重学）
  final VoidCallback? onSwipeRight;     // 右滑回调（进入删除区）
  final VoidCallback? onSwipeUp;        // 上滑回调（查看详情）
  final VoidCallback? onSwipeUpComplete; // 上滑完成（停留超过阈值）
  final Function(double progress)? onHorizontalDragProgress; // 横向拖动进度 (0-1)
  final Function(bool isInZone)? onDeleteZoneHover; // 是否进入删除区
  final Function(Offset cardCenter, Offset dragOffset)? onCardPositionChanged; // 卡片中心位置+拖动偏移
  final Function(DraggableCardState)? onCardStateChanged;

  // 弹性参数
  final double swipeThreshold;   // 触发滑动的阈值比例
  final double rotationFactor;   // 旋转角度系数
  final double scaleFactor;       // 拖动时缩小比例
  final SpringDescription spring; // 弹簧参数

  const DraggableWordCard({
    super.key,
    required this.child,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.onSwipeUp,
    this.onSwipeUpComplete,
    this.onHorizontalDragProgress,
    this.onDeleteZoneHover,
    this.onCardPositionChanged,
    this.onCardStateChanged,
    this.swipeThreshold = 0.25,
    this.rotationFactor = 0.0015,
    this.scaleFactor = 0.92,
    SpringDescription? spring,
  }) : spring = spring ?? const SpringDescription(
        mass: 1.0,
        stiffness: 400.0,
        damping: 22.0,
      );

  @override
  State<DraggableWordCard> createState() => DraggableCardState();
}

class DraggableCardState extends State<DraggableWordCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Animation<Offset>? _animation;

  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  SwipeDirection? _swipeDirection;

  Offset get currentOffset => _dragOffset;
  bool get isDragging => _isDragging;
  SwipeDirection? get swipeDirection => _swipeDirection;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
    _controller.addListener(_onAnimationUpdate);
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

    // 计算横向进度（用于显示删除区）
    final screenWidth = MediaQuery.of(context).size.width;
    final progress = (_dragOffset.dx / screenWidth).clamp(0.0, 1.0);
    widget.onHorizontalDragProgress?.call(progress);

    // 通知卡片位置变化（用于检测是否进入删除区）
    final cardCenter = _getCardCenter();
    widget.onCardPositionChanged?.call(cardCenter, _dragOffset);
  }

  Offset _getCardCenter() {
    final screenCenter = MediaQuery.of(context).size.center(Offset.zero);
    return screenCenter + _dragOffset;
  }

  void _onPanEnd(DragEndDetails details) {
    _isDragging = false;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final thresholdX = screenWidth * widget.swipeThreshold;
    final thresholdY = screenHeight * 0.15;

    // 重置横向进度
    widget.onHorizontalDragProgress?.call(0.0);

    // 判定滑动方向
    SwipeDirection? direction;

    if (_dragOffset.dy < -thresholdY &&
        _dragOffset.dy.abs() > _dragOffset.dx.abs() * 1.5) {
      // 上滑（主要看垂直方向）
      direction = SwipeDirection.up;
    } else if (_dragOffset.dx > thresholdX) {
      // 右滑 - 暂不自动删除，等待进入删除区
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
    // 重置控制器值，确保新动画能从0.0开始
    _controller.reset();

    _animation = Tween<Offset>(
      begin: _dragOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    _controller.animateTo(
      1.0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
    );

    widget.onCardStateChanged?.call(this);
  }

  void _animateOffScreen(SwipeDirection direction) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 重置控制器值，确保新动画能从0.0开始
    _controller.reset();

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

    _animation = Tween<Offset>(
      begin: _dragOffset,
      end: targetOffset,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.animateTo(
      1.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// 外部调用：完成删除动画
  void completeSwipeRight() {
    _swipeDirection = SwipeDirection.right;
    _animateOffScreen(SwipeDirection.right);
    widget.onSwipeRight?.call();
  }

  /// 外部调用：重置卡片
  void reset() {
    _springBack();
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

    // 旋转：随拖动水平距离变化
    final rotation = dampedOffset.dx * widget.rotationFactor;

    // 缩放：拖动时缩小
    final distance = dampedOffset.distance;
    final maxDistance = screenWidth * 0.8;
    final scale = 1.0 - (distance / maxDistance * (1 - widget.scaleFactor));

    // 透明度
    final opacity = (scale * 1.2).clamp(0.6, 1.0);

    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
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

  /// 边界阻尼：超出边界后阻力增大
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

enum SwipeDirection { left, right, up, down }
