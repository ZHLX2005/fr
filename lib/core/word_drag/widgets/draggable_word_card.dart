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
    with SingleTickerProviderStateMixin {
  // 动画状态
  late AnimationController _animControllerX;
  late AnimationController _animControllerY;
  late AnimationController _alphaController;
  late AnimationController _scaleController;

  double _offsetX = 0;
  double _offsetY = 0;
  double _alpha = 1;
  double _scale = 1;

  bool _isPressed = false;

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
    _animControllerX = AnimationController(vsync: this);
    _animControllerY = AnimationController(vsync: this);
    _alphaController = AnimationController(vsync: this);
    _scaleController = AnimationController(vsync: this);

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
    setState(() {
      _offsetX = _animControllerX.value;
    });
  }

  void _onAnimationY() {
    setState(() {
      _offsetY = _animControllerY.value;
    });
  }

  void _onAlpha() {
    setState(() {
      _alpha = _alphaController.value;
    });
  }

  void _onScale() {
    setState(() {
      _scale = _scaleController.value;
    });
  }

  // 触觉反馈
  void _performHaptic() {
    HapticFeedback.mediumImpact();
  }

  // 处理拖动更新
  void _handleDragUpdate(double dx, double dy) {
    if (!widget.isTopCard) return;
    setState(() {
      _offsetX += dx;
      _offsetY += dy;
    });
    widget.onDragUpdate?.call(_offsetX, _offsetY);
  }

  // 处理拖动结束
  bool _handleDragEnd(double velocityX, double velocityY) {
    if (!widget.isTopCard) return false;

    // 检查是否是下滑桶模式 (父组件处理)
    final isFolderMode = _offsetY > _folderModeThreshold;

    // 检查水平滑动意图
    final isHorizontalSwipe = _offsetX.abs() > 500;

    // 如果是下滑模式且不是水平滑动，交给父组件处理
    if (isFolderMode && !isHorizontalSwipe) {
      final consumed = widget.onDragEnd?.call(_offsetX, _offsetY) ?? false;
      if (consumed) {
        // 吸进动画
        _animateSuckIn();
        return true;
      }
    }

    // 左滑 - 删除
    if (_offsetX < -_threshold) {
      _performHaptic();
      _animateSwipeOut(-1500, 0);
      widget.onSwipeLeft?.call();
      return true;
    }

    // 右滑 - 掌握
    if (_offsetX > _threshold) {
      _performHaptic();
      _animateSwipeOut(1500, 0);
      widget.onSwipeRight?.call();
      return true;
    }

    // 上滑 - 跳过
    if (_offsetY < -_threshold || velocityY < -_flingThreshold) {
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
  void _animateSuckIn() {
    _alphaController.animateTo(0, duration: const Duration(milliseconds: 250));
    _scaleController.animateTo(0.1, duration: const Duration(milliseconds: 250));
    _animControllerY.animateTo(_offsetY + 200, duration: const Duration(milliseconds: 250));
  }

  // 滑出动画
  void _animateSwipeOut(double targetX, double targetY) {
    _animControllerX.animateTo(targetX, duration: const Duration(milliseconds: 200));
    _animControllerY.animateTo(targetY, duration: const Duration(milliseconds: 200));
  }

  // Spring 回弹动画 (基于 photoo 的 snappy 效果: stiffness=2000f, dampingRatio=0.85f)
  void _animateSpringBack() {
    final spring = SpringDescription(
      mass: 1.0,
      stiffness: 2000.0,
      damping: 76.0, // damping = dampingRatio * 2 * sqrt(mass * stiffness) = 0.85 * 2 * sqrt(2000) ≈ 76
    );

    // 使用 SpringSimulation 实现真正的弹簧回弹
    final simulationX = SpringSimulation(spring, _offsetX, 0, 0);
    final simulationY = SpringSimulation(spring, _offsetY, 0, 0);

    _animControllerX.animateWith(simulationX);
    _animControllerY.animateWith(simulationY);
  }

  // 计算动态缩放 (上下滑动时卡片变薄/变小)
  double get _dynamicScale {
    if (_offsetY < 0) {
      // 上滑变薄
      return (1.0 + _offsetY / 1000).clamp(0.9, 1.0);
    } else if (_offsetY > 0) {
      // 下滑变小
      return (1.0 - _offsetY / 1000).clamp(0.5, 1.0);
    }
    return 1.0;
  }

  // 计算旋转角度
  double get _rotation => (_offsetX / 60).clamp(-10, 10);

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Transform.translate(
      offset: Offset(_offsetX, _offsetY + _stackYOffset),
      child: Transform.scale(
        scale: _stackScale * _dynamicScale * _scale * (_isPressed ? 0.96 : 1.0),
        child: Opacity(
          opacity: _alpha.clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: _rotation * 3.14159 / 180,
            child: GestureDetector(
              onPanStart: widget.isTopCard ? (_) {
                _isPressed = true;
                widget.onDragStart?.call();
              } : null,
              onPanUpdate: widget.isTopCard ? (details) {
                _handleDragUpdate(details.delta.dx, details.delta.dy);
              } : null,
              onPanEnd: widget.isTopCard ? (details) {
                _isPressed = false;
                _handleDragEnd(details.velocity.pixelsPerSecond.dx, details.velocity.pixelsPerSecond.dy);
              } : null,
              onPanCancel: widget.isTopCard ? () {
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
          ),
        ),
      ),
    );
  }
}
