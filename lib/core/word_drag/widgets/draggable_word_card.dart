import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 弹性单词卡片 - 核心拖动动效组件
///
/// 关键技术点：
/// 1. SpringSimulation 实现弹性回弹
/// 2. 拖动时卡片跟随手指，带有旋转和缩放反馈
/// 3. 拖动边界有弹性阻尼效果
/// 4. 右滑时显示标新/删除区，必须拖入区域才执行操作
class DraggableWordCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSwipeLeft;      // 左滑回调（标记已复习）
  final VoidCallback? onSwipeRight;     // 右滑回调（非区域右滑→详情页）
  final VoidCallback? onMarkZoneAction; // 标新区触发
  final VoidCallback? onDeleteZoneAction; // 删除区触发
  final VoidCallback? onSwipeUp;        // 上滑回调（查看详情）
  final VoidCallback? onSwipeUpComplete; // 上滑完成（停留超过阈值）
  final Function(double progress)? onHorizontalDragProgress; // 横向拖动进度 (0-1)
  final Function(bool isInZone)? onDeleteZoneHover; // 是否进入删除区
  // 卡片位置变化回调，用于检测是否进入删除区，返回是否在任意区域内
  final bool Function(Offset cardCenter, Offset dragOffset, bool isSpringBack)? onCardPositionChanged;
  // 当右滑阈值首次交叉时，WordDragPage 调用此方法更新区域状态
  final VoidCallback? onRightThresholdFirstCrossed;
  final Function(DraggableCardState)? onCardStateChanged;
  final VoidCallback? onSpringBackComplete; // 弹簧动画完成回调
  final VoidCallback? onForceZoneAction; // 强制触发区域操作（用于提示显示时强制滑出）

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
    this.onMarkZoneAction,
    this.onDeleteZoneAction,
    this.onSwipeUp,
    this.onSwipeUpComplete,
    this.onHorizontalDragProgress,
    this.onDeleteZoneHover,
    this.onCardPositionChanged,
    this.onRightThresholdFirstCrossed,
    this.onCardStateChanged,
    this.onSpringBackComplete,
    this.onForceZoneAction,
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

  // 弹簧动画状态
  bool _isInSpringBack = false;

  // 右滑阈值交叉状态（用于判断是否应跳转到详情页）
  bool _hasRightThresholdCrossed = false;
  bool _wasInZoneWhenRightCrossed = false;
  bool _zoneActionInProgress = false; // 阻止重复触发 onSwipeRight
  bool _actionTriggered = false; // 标记区域操作已被外部触发

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
      _hasRightThresholdCrossed = false;
      _wasInZoneWhenRightCrossed = false;
    });
    widget.onCardStateChanged?.call(this);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta;
    });

    // 计算横向进度（用于显示删除区）
    final screenWidth = MediaQuery.of(context).size.width;
    final thresholdX = screenWidth * widget.swipeThreshold;
    final progress = (_dragOffset.dx / screenWidth).clamp(0.0, 1.0);
    widget.onHorizontalDragProgress?.call(progress);

    // 通知卡片位置变化（用于检测是否进入删除区）
    final cardCenter = _getCardCenter();
    final isInZone = widget.onCardPositionChanged?.call(cardCenter, _dragOffset, _isInSpringBack) ?? false;

    // 检测右滑阈值是否首次交叉（必须在 onCardPositionChanged 之后调用，确保区域状态已更新）
    if (!_hasRightThresholdCrossed && _dragOffset.dx > thresholdX) {
      _hasRightThresholdCrossed = true;
      // 立即更新区域状态
      _wasInZoneWhenRightCrossed = isInZone;
    }
  }

  Offset _getCardCenter() {
    final screenCenter = MediaQuery.of(context).size.center(Offset.zero);
    return screenCenter + _dragOffset;
  }

  /// 直接在卡片内检测是否在标新/删除区域内
  /// 返回 0 = 无区域, 1 = mark区, 2 = delete区
  int _checkZoneAtRelease() {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final cardCenter = _getCardCenter();

    // 标新区：右侧上方
    final markZoneRect = Rect.fromLTWH(
      screenWidth - 100,
      screenHeight * 0.15,
      80,
      screenHeight * 0.25,
    ).inflate(30);

    // 删除区：右侧下方
    final deleteZoneRect = Rect.fromLTWH(
      screenWidth - 100,
      screenHeight * 0.6,
      80,
      screenHeight * 0.25,
    ).inflate(30);

    if (markZoneRect.contains(cardCenter)) return 1;
    if (deleteZoneRect.contains(cardCenter)) return 2;
    return 0;
  }

  void _onPanEnd(DragEndDetails details) {
    // 先通知外部，让 WordDragPage 有机会在 _actionTriggered 设置之前介入
    widget.onForceZoneAction?.call();

    // 如果区域操作已被 WordDragPage 触发，跳过处理
    if (_actionTriggered) {
      return;
    }

    _isDragging = false;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final thresholdX = screenWidth * widget.swipeThreshold;
    final thresholdY = screenHeight * 0.15;

    // 重置横向进度
    widget.onHorizontalDragProgress?.call(0.0);

    // 关键修复：如果右滑阈值被交叉过（说明用户意图是右滑）
    // 并且卡片在区域内，滑出卡片并执行对应操作
    if (_hasRightThresholdCrossed && _wasInZoneWhenRightCrossed) {
      final zone = _checkZoneAtRelease();
      debugPrint('DraggableCard: _onPanEnd - zone=$zone, sliding out');

      // 确定要调用的回调
      VoidCallback? zoneCallback;
      if (zone == 1) {
        zoneCallback = widget.onMarkZoneAction;
      } else if (zone == 2) {
        zoneCallback = widget.onDeleteZoneAction;
      }

      _swipeDirection = SwipeDirection.right;
      _zoneActionInProgress = true; // 阻止动画完成后触发 onSwipeRight
      // 动画完成后才调用区域回调
      _animateOffScreen(SwipeDirection.right, onComplete: () {
        _zoneActionInProgress = false;
        zoneCallback?.call();
      });
      widget.onCardStateChanged?.call(this);
      return;
    }

    // 判定滑动方向
    SwipeDirection? direction;

    if (_dragOffset.dy < -thresholdY &&
        _dragOffset.dy.abs() > _dragOffset.dx.abs() * 1.5) {
      // 上滑（主要看垂直方向）
      direction = SwipeDirection.up;
    } else if (_dragOffset.dx > thresholdX) {
      // 右滑
      direction = SwipeDirection.right;
    } else if (_dragOffset.dx < -thresholdX) {
      // 左滑
      direction = SwipeDirection.left;
    }

    debugPrint('DraggableCard: _onPanEnd - dx=${_dragOffset.dx}, dy=${_dragOffset.dy}, thresholdX=$thresholdX, thresholdY=$thresholdY, direction=$direction');

    if (direction != null) {
      _swipeDirection = direction;
      _animateOffScreen(direction);
    } else {
      _isInSpringBack = true;
      _springBack();
    }

    widget.onCardStateChanged?.call(this);
  }

  void _springBack([VoidCallback? onComplete]) {
    // 先停止任何正在进行的动画
    _controller.stop();

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
        _isInSpringBack = false;
        onComplete?.call();
        widget.onSpringBackComplete?.call();
      });

    widget.onCardStateChanged?.call(this);
  }

  void _animateOffScreen(SwipeDirection direction, {VoidCallback? onComplete}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 先停止任何正在进行的动画
    _controller.stop();

    late Offset targetOffset;
    switch (direction) {
      case SwipeDirection.right:
        targetOffset = Offset(screenWidth * 1.5, _dragOffset.dy);
        break;
      case SwipeDirection.left:
        targetOffset = Offset(-screenWidth * 1.5, _dragOffset.dy);
        break;
      case SwipeDirection.up:
        targetOffset = Offset(_dragOffset.dx, -screenHeight);
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

    _controller
      ..value = 0.0
      ..animateTo(1.0, duration: const Duration(milliseconds: 300)).then((_) {
        debugPrint('DraggableCard: animation complete for direction=$direction, calling callback');
        // 动画完成后才调用回调
        switch (direction) {
          case SwipeDirection.right:
            if (!_zoneActionInProgress) {
              debugPrint('DraggableCard: calling onSwipeRight');
              widget.onSwipeRight?.call();
            }
            break;
          case SwipeDirection.left:
            debugPrint('DraggableCard: calling onSwipeLeft');
            widget.onSwipeLeft?.call();
            break;
          case SwipeDirection.up:
            debugPrint('DraggableCard: calling onSwipeUp');
            widget.onSwipeUp?.call();
            break;
          case SwipeDirection.down:
            break;
        }
        // 额外的完成回调（用于区域操作的回调）
        onComplete?.call();
      });
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

  /// 当右滑阈值首次交叉时，WordDragPage 调用此方法更新区域状态
  void updateZoneStateAtRightCrossing(bool isInZone) {
    _wasInZoneWhenRightCrossed = isInZone;
  }

  /// 强制触发区域操作并滑出（提示显示时调用）
  void forceZoneAction() {
    if (_actionTriggered) return;
    _actionTriggered = true;

    _swipeDirection = SwipeDirection.right;
    _zoneActionInProgress = true;

    // 动画完成后调用区域操作
    _animateOffScreen(SwipeDirection.right, onComplete: () {
      _zoneActionInProgress = false;
      _actionTriggered = false;
      // 根据区域类型调用对应回调
      if (_isInMarkZone()) {
        widget.onMarkZoneAction?.call();
      } else if (_isInDeleteZone()) {
        widget.onDeleteZoneAction?.call();
      }
    });
  }

  bool _isInMarkZone() {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final cardCenter = _getCardCenter();

    final markZoneRect = Rect.fromLTWH(
      screenWidth - 100,
      screenHeight * 0.15,
      80,
      screenHeight * 0.25,
    ).inflate(30);

    return markZoneRect.contains(cardCenter);
  }

  bool _isInDeleteZone() {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final cardCenter = _getCardCenter();

    final deleteZoneRect = Rect.fromLTWH(
      screenWidth - 100,
      screenHeight * 0.6,
      80,
      screenHeight * 0.25,
    ).inflate(30);

    return deleteZoneRect.contains(cardCenter);
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
