import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// 滑动方向枚举
enum SwipeDirection { left, right, up, down, none }

/// 弹性单词卡片组件
///
/// 基于 photoo DraggableCard 实现，支持：
/// - 上滑跳过
/// - 左滑删除/稍后复习
/// - 右滑喜欢/掌握
/// - 下滑显示分类桶
class DraggableWordCard extends StatefulWidget {
  final Widget child;
  /// 单词索引
  final int index;
  /// 是否顶层卡片
  final bool isTopCard;
  /// 堆叠索引
  final int stackIndex;
  /// 左滑回调
  final VoidCallback? onSwipeLeft;
  /// 右滑回调
  final VoidCallback? onSwipeRight;
  /// 上滑回调
  final VoidCallback? onSwipeUp;
  /// 开始拖动回调
  final VoidCallback? onDragStart;
  /// 拖动更新回调 (offsetX, offsetY)
  final void Function(double x, double y)? onDragUpdate;
  /// 拖动结束回调，返回是否消耗事件
  final bool Function(double x, double y)? onDragEnd;
  /// 拖动取消回调
  final VoidCallback? onDragCancel;

  const DraggableWordCard({
    super.key,
    required this.child,
    required this.index,
    required this.isTopCard,
    required this.stackIndex,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.onSwipeUp,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
  });

  @override
  State<DraggableWordCard> createState() => _DraggableWordCardState();
}

class _DraggableWordCardState extends State<DraggableWordCard>
    with TickerProviderStateMixin {
  // 动画状态
  late AnimationController _animControllerX;
  late AnimationController _animControllerY;

  // 透明度控制器
  late AnimationController _alphaController;
  late Animation<double> _alphaAnimation;

  // 缩放控制器
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  bool _isPressed = false;
  bool _isAnimating = false;

  // 阈值常量 (基于 photoo)
  static const double _threshold = 160;        // 滑动确认阈值
  static const double _folderModeThreshold = 300; // 下滑进入桶模式
  static const double _flingThreshold = 800;      // 快速滑动速度阈值

  // 堆叠效果常量
  double get _stackScale => 1.0 - (widget.stackIndex.clamp(0, 2) * 0.04);
  double get _stackYOffset => widget.stackIndex * 15.0;

  @override
  void initState() {
    super.initState();
    _animControllerX = AnimationController.unbounded(vsync: this);
    _animControllerY = AnimationController.unbounded(vsync: this);

    _alphaController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _alphaAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(_alphaController);

    _scaleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.1).animate(_scaleController);

    _animControllerX.addListener(_onAnimationX);
    _animControllerY.addListener(_onAnimationY);
    _alphaController.addListener(_onAlpha);
    _scaleController.addListener(_onScale);
  }

  @override
  void dispose() {
    _animControllerX.dispose();
    _animControllerY.dispose();
    _alphaController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _onAnimationX() {
    widget.onDragUpdate?.call(_animControllerX.value, _animControllerY.value);
  }

  void _onAnimationY() {
    widget.onDragUpdate?.call(_animControllerX.value, _animControllerY.value);
  }

  void _onAlpha() {
    // 透明度动画不需要通知
  }

  void _onScale() {
    // 缩放动画不需要通知
  }

  // 触觉反馈
  void _performHaptic() {
    HapticFeedback.mediumImpact();
  }

  // 处理拖动更新 - 直接修改 AnimationController 的 value
  void _handleDragUpdate(double dx, double dy) {
    if (!widget.isTopCard || _isAnimating) return;
    _animControllerX.value += dx;
    _animControllerY.value += dy;
    widget.onDragUpdate?.call(_animControllerX.value, _animControllerY.value);
  }

  // 处理拖动结束
  bool _handleDragEnd(double velocityX, double velocityY) {
    if (!widget.isTopCard || _isAnimating) return false;

    final offsetX = _animControllerX.value;
    final offsetY = _animControllerY.value;

    // 检查是否是下滑桶模式 (父组件处理)
    final isFolderMode = offsetY > _folderModeThreshold;

    // 检查水平滑动意图
    final isHorizontalSwipe = offsetX.abs() > 500;

    // 如果是下滑模式且不是水平滑动，交给父组件处理
    if (isFolderMode && !isHorizontalSwipe) {
      final consumed = widget.onDragEnd?.call(offsetX, offsetY) ?? false;
      if (consumed) {
        // 吸进动画
        _animateSuckIn(offsetY);
        return true;
      }
    }

    // 左滑 - 删除
    if (offsetX < -_threshold) {
      _performHaptic();
      _animateSwipeOut(-1500, 0);
      widget.onSwipeLeft?.call();
      return true;
    }

    // 右滑 - 掌握
    if (offsetX > _threshold) {
      _performHaptic();
      _animateSwipeOut(1500, 0);
      widget.onSwipeRight?.call();
      return true;
    }

    // 上滑 - 跳过
    if (offsetY < -_threshold || velocityY < -_flingThreshold) {
      _performHaptic();
      _animateSwipeOut(0, -2000);
      widget.onSwipeUp?.call();
      return true;
    }

    // 回弹 - 使用 Spring 动画
    _animateSpringBack();
    return false;
  }

  // 吸进动画 (放入桶)
  void _animateSuckIn(double currentY) {
    _isAnimating = true;
    _alphaController.forward();
    _scaleController.forward();

    final targetY = currentY + 200;
    _animControllerY
        .animateTo(targetY, duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
        .then((_) {
      _isAnimating = false;
    });
  }

  // 滑出动画
  void _animateSwipeOut(double targetX, double targetY) {
    _isAnimating = true;

    _animControllerX.animateTo(targetX, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    _animControllerY.animateTo(targetY, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  // Spring 回弹动画 (基于 photoo 的 snappy 效果: stiffness=2000f, dampingRatio=0.85f)
  void _animateSpringBack() {
    _isAnimating = true;

    final spring = SpringDescription(
      mass: 1.0,
      stiffness: 2000.0,
      damping: 76.0,
    );

    final currentX = _animControllerX.value;
    final currentY = _animControllerY.value;

    final simulationX = SpringSimulation(spring, currentX, 0, 0);
    final simulationY = SpringSimulation(spring, currentY, 0, 0);

    _animControllerX.animateWith(simulationX);
    _animControllerY.animateWith(simulationY);

    // 监听动画完成
    void onComplete() {
      _isAnimating = false;
      _animControllerX.removeListener(onComplete);
      _animControllerY.removeListener(onComplete);
    }
    _animControllerX.addListener(onComplete);
    _animControllerY.addListener(onComplete);
  }

  // 计算动态缩放 (上下滑动时卡片变薄/变小)
  double get _dynamicScale {
    final offsetY = _animControllerY.value;
    if (offsetY < 0) {
      return (1.0 + offsetY / 1000).clamp(0.9, 1.0);
    } else if (offsetY > 0) {
      return (1.0 - offsetY / 1000).clamp(0.5, 1.0);
    }
    return 1.0;
  }

  // 计算旋转角度
  double get _rotation => (_animControllerX.value / 60).clamp(-10, 10);

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: Listenable.merge([
        _animControllerX,
        _animControllerY,
        _alphaController,
        _scaleController,
      ]),
      builder: (context, child) {
        final offsetX = _animControllerX.value;
        final offsetY = _animControllerY.value;

        return Transform.translate(
          offset: Offset(offsetX, offsetY + _stackYOffset),
          child: Transform.scale(
            scale: _stackScale * _dynamicScale * _scaleAnimation.value * (_isPressed ? 0.96 : 1.0),
            child: Opacity(
              opacity: _alphaAnimation.value.clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: _rotation * 3.14159 / 180,
                child: child,
              ),
            ),
          ),
        );
      },
      child: GestureDetector(
        onPanStart: widget.isTopCard ? (_) {
          if (_isAnimating) return;
          _isPressed = true;
          widget.onDragStart?.call();
        } : null,
        onPanUpdate: widget.isTopCard ? (details) {
          if (_isAnimating) return;
          _handleDragUpdate(details.delta.dx, details.delta.dy);
        } : null,
        onPanEnd: widget.isTopCard ? (details) {
          if (_isAnimating) return;
          _isPressed = false;
          _handleDragEnd(details.velocity.pixelsPerSecond.dx, details.velocity.pixelsPerSecond.dy);
        } : null,
        onPanCancel: widget.isTopCard ? () {
          if (_isAnimating) return;
          _isPressed = false;
          widget.onDragCancel?.call();
          _animateSpringBack();
        } : null,
        child: Container(
          width: screenSize.width * 0.85,
          height: screenSize.height * 0.55,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
