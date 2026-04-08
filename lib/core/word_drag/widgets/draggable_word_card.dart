import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// 滑动方向枚举
enum SwipeDirection { left, right, up, down }

/// Action 指示器类型
enum ActionIndicator {
  like,
  delete,
  skip,
  folder,
}

/// 弹性单词卡片组件
///
/// 基于 photoo DraggableCard 实现 (第 4388-4800 行)
/// 支持：上滑跳过、左滑稍后复习、右滑掌握、下滑显示分类桶
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
  /// 下滑进入文件夹模式回调
  final bool Function(double x, double y)? onFolderModeDragEnd;
  /// 开始拖动回调
  final VoidCallback? onDragStart;
  /// 拖动更新回调 (x, y)
  final void Function(double x, double y)? onDragUpdate;
  /// 拖动结束回调
  final void Function(double x, double y)? onDragEnd;
  /// 拖动取消回调
  final VoidCallback? onDragCancel;
  /// 详情页回调
  final VoidCallback? onDetail;

  const DraggableWordCard({
    super.key,
    required this.child,
    required this.index,
    required this.isTopCard,
    required this.stackIndex,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.onSwipeUp,
    this.onFolderModeDragEnd,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
    this.onDetail,
  });

  @override
  State<DraggableWordCard> createState() => _DraggableWordCardState();
}

class _DraggableWordCardState extends State<DraggableWordCard>
    with TickerProviderStateMixin {
  // 动画状态 - 使用 Animatable 支持自由拖动值
  late AnimationController _offsetXController;
  late AnimationController _offsetYController;
  late AnimationController _alphaController;
  late AnimationController _exitScaleController;
  late AnimationController _pressScaleController;

  // 动画值
  double _offsetX = 0;
  double _offsetY = 0;
  double _alpha = 1;
  double _exitScale = 1;
  double _pressScale = 1;

  // 状态标志
  bool _isAnimating = false;

  // ==================== 常量 (完全匹配 photoo) ====================
  static const double _threshold = 160;           // 滑动确认阈值
  static const double _folderModeThreshold = 420;  // 下滑进入文件夹模式 (拖拽被消耗)
  static const double _folderDropRowThreshold = 300; // 下滑显示桶选择器
  static const double _flingThreshold = 800;       // 快速滑动速度阈值

  // Action Indicator 阈值
  static const double _actionIndicatorThreshold = 100;

  // 堆叠效果常量
  double get _stackScale => 1.0 - (widget.stackIndex.clamp(0, 2) * 0.04);
  double get _stackYOffset => widget.stackIndex * 15.0;

  @override
  void initState() {
    super.initState();
    _offsetXController = AnimationController.unbounded(vsync: this);
    _offsetYController = AnimationController.unbounded(vsync: this);
    _alphaController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _exitScaleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _pressScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _offsetXController.addListener(_onOffsetChanged);
    _offsetYController.addListener(_onOffsetChanged);
    _alphaController.addListener(_onAlphaChanged);
    _exitScaleController.addListener(_onExitScaleChanged);
    _pressScaleController.addListener(_onPressScaleChanged);
  }

  @override
  void dispose() {
    _offsetXController.dispose();
    _offsetYController.dispose();
    _alphaController.dispose();
    _exitScaleController.dispose();
    _pressScaleController.dispose();
    super.dispose();
  }

  void _onOffsetChanged() {
    setState(() {
      _offsetX = _offsetXController.value;
      _offsetY = _offsetYController.value;
    });
    widget.onDragUpdate?.call(_offsetX, _offsetY);
  }

  void _onAlphaChanged() {
    setState(() {
      _alpha = _alphaController.value;
    });
  }

  void _onExitScaleChanged() {
    setState(() {
      _exitScale = _exitScaleController.value;
    });
  }

  void _onPressScaleChanged() {
    setState(() {
      _pressScale = _pressScaleController.value;
    });
  }

  // 触觉反馈 (photox: HapticFeedbackType.LongPress)
  void _performHaptic() {
    HapticFeedback.heavyImpact();
  }

  // 处理拖动更新
  void _handleDragUpdate(double dx, double dy) {
    if (!widget.isTopCard || _isAnimating) return;
    _offsetXController.value += dx;
    _offsetYController.value += dy;
  }

  // 处理拖动结束
  void _handleDragEnd(double velocityX, double velocityY) {
    if (!widget.isTopCard || _isAnimating) return;

    final offsetX = _offsetXController.value;
    final offsetY = _offsetYController.value;

    // 检查是否是文件夹模式
    final isFolderMode = offsetY > _folderModeThreshold;

    // 文件夹模式：交给父组件处理
    if (isFolderMode) {
      final consumed = widget.onFolderModeDragEnd?.call(offsetX, offsetY) ?? false;
      if (consumed) {
        // 吸进动画
        _animateSuckIntoFolder();
        return;
      }
    }

    // 左滑 - 删除/稍后复习
    if (offsetX < -_threshold) {
      _performHaptic();
      _animateSwipeOut(-1500, 0, onComplete: widget.onSwipeLeft);
      return;
    }

    // 右滑 - 掌握
    if (offsetX > _threshold) {
      _performHaptic();
      _animateSwipeOut(1500, 0, onComplete: widget.onSwipeRight);
      return;
    }

    // 上滑 - 跳过 (位置或速度触发)
    if (offsetY < -_threshold || velocityY < -_flingThreshold) {
      _performHaptic();
      _animateSwipeOut(0, -2000, onComplete: widget.onSwipeUp);
      return;
    }

    // 回弹
    _animateSpringBack();
  }

  // 拖动取消 (photoo: tween(160, LinearOutSlowInEasing) -> Curves.fastOutSlowIn)
  void _handleDragCancel() {
    if (!widget.isTopCard || _isAnimating) return;
    _pressScaleController.reverse();
    widget.onDragCancel?.call();
    _isAnimating = true;
    _offsetXController.animateTo(
      0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.fastOutSlowIn,
    );
    _offsetYController.animateTo(
      0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.fastOutSlowIn,
    ).then((_) {
      _isAnimating = false;
    });
  }

  // 吸进动画 (放入文件夹)
  void _animateSuckIntoFolder() {
    _isAnimating = true;

    _exitScaleController.animateTo(0.1, duration: const Duration(milliseconds: 250));
    _alphaController.animateTo(0, duration: const Duration(milliseconds: 250));
    _offsetYController.animateTo(
      _offsetYController.value + 200,
      duration: const Duration(milliseconds: 250),
    ).then((_) {
      _isAnimating = false;
    });
  }

  // 滑出动画 (photoo: FastOutLinearInEasing - 线性加速)
  void _animateSwipeOut(double targetX, double targetY, {VoidCallback? onComplete}) {
    _isAnimating = true;

    _offsetXController.animateTo(
      targetX,
      duration: const Duration(milliseconds: 200),
      curve: Curves.linear,
    );
    _offsetYController.animateTo(
      targetY,
      duration: const Duration(milliseconds: 200),
      curve: Curves.linear,
    ).then((_) {
      _isAnimating = false;
      onComplete?.call();
    });
  }

  // Spring 回弹动画 (phoot: stiffness=2000f, dampingRatio=0.85f)
  void _animateSpringBack() {
    _isAnimating = true;

    final spring = SpringDescription(
      mass: 1.0,
      stiffness: 2000.0,
      damping: 76.0, // dampingRatio = 0.85
    );

    final simX = SpringSimulation(spring, _offsetXController.value, 0, 0);
    final simY = SpringSimulation(spring, _offsetYController.value, 0, 0);

    _offsetXController.animateWith(simX);
    _offsetYController.animateWith(simY).then((_) {
      _isAnimating = false;
    });
  }

  // 计算动态缩放
  double get _dynamicScale {
    if (_offsetY < 0) {
      return (1.0 + _offsetY / 1000).clamp(0.9, 1.0);
    } else if (_offsetY > 0) {
      return (1.0 - _offsetY / 1000).clamp(0.5, 1.0);
    }
    return 1.0;
  }

  // 计算当前 Action Indicator
  ActionIndicator? get _currentActionIndicator {
    final isFolderMode = _offsetY > _folderDropRowThreshold;

    if (isFolderMode) {
      return ActionIndicator.folder;
    }
    if (_offsetX > _actionIndicatorThreshold) {
      return ActionIndicator.like;
    }
    if (_offsetX < -_actionIndicatorThreshold) {
      return ActionIndicator.delete;
    }
    if (_offsetY < -_actionIndicatorThreshold) {
      return ActionIndicator.skip;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final cardWidth = screenSize.width * 0.8;
    final cardHeight = screenSize.height * 0.6;

    // 总缩放 = 堆叠缩放 * 动态缩放 * 退出缩放 * 按压缩放
    final totalScale = _stackScale * _dynamicScale * _exitScale * _pressScale;
    final actionIndicator = _currentActionIndicator;

    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 卡片本身
          Positioned(
            top: _stackYOffset,
            left: 0,
            right: 0,
            child: Transform.translate(
              offset: Offset(_offsetX, _offsetY),
              child: Transform.scale(
                scale: totalScale,
                child: Opacity(
                  opacity: _alpha.clamp(0.0, 1.0),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GestureDetector(
                        onTap: widget.isTopCard ? widget.onDetail : null,
                        onPanStart: widget.isTopCard ? (_) {
                          if (_isAnimating) return;
                          // photoo: spring(stiffness=Medium, dampingRatio=0.6f)
                          // Animate from 1.0 to 0.96 (press down effect)
                          final spring = SpringDescription(mass: 1.0, stiffness: 500.0, damping: 15.0);
                          final simulation = SpringSimulation(spring, 1.0, 0.96, 0);
                          _pressScaleController.animateWith(simulation);
                          widget.onDragStart?.call();
                        } : null,
                        onPanUpdate: widget.isTopCard ? (details) {
                          if (_isAnimating) return;
                          _handleDragUpdate(details.delta.dx, details.delta.dy);
                        } : null,
                        onPanEnd: widget.isTopCard ? (details) {
                          if (_isAnimating) return;
                          _pressScaleController.reverse();
                          _handleDragEnd(
                            details.velocity.pixelsPerSecond.dx,
                            details.velocity.pixelsPerSecond.dy,
                          );
                        } : null,
                        onPanCancel: widget.isTopCard ? _handleDragCancel : null,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: widget.child,
                          ),
                        ),
                      ),
                      // Action Indicator (位于卡片右上角，跟随卡片移动)
                      // Note: Stack already translated by card offset, so indicator position is relative
                      if (widget.isTopCard && actionIndicator != null)
                        Positioned(
                          top: 16,
                          right: 16,
                          child: _ActionIndicatorWidget(indicator: actionIndicator),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Action Indicator 组件
class _ActionIndicatorWidget extends StatelessWidget {
  final ActionIndicator indicator;

  const _ActionIndicatorWidget({required this.indicator});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String text;

    switch (indicator) {
      case ActionIndicator.like:
        color = const Color(0xFFFF9800);
        icon = Icons.favorite;
        text = 'LIKE';
        break;
      case ActionIndicator.delete:
        color = const Color(0xFFEF4444);
        icon = Icons.delete_outline;
        text = 'DELETE';
        break;
      case ActionIndicator.skip:
        color = const Color(0xFF3B82F6);
        icon = Icons.arrow_upward;
        text = 'SKIP';
        break;
      case ActionIndicator.folder:
        color = const Color(0xFF9C27B0);
        icon = Icons.drive_file_move;
        text = 'FOLDER';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
