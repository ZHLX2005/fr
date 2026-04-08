import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 分类桶数据模型
class CategoryBucket {
  final String id;
  final String name;
  final IconData icon;
  final Color color;

  const CategoryBucket({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
  });
}

/// 分类桶选择行组件
///
/// 基于 photoo FolderDropRow 实现 (FolderDropTarget.kt)
/// - 下滑 > 300px 时从底部滑入显示
/// - 桶激活时有弹性缩放动画 (scale 0.82->1.2, lift 0->-8dp, width 68->88dp)
/// - 支持碰撞检测确定最近桶
/// - LazyRow 支持水平滚动
/// 分类桶边缘滚动状态
class CategoryDropEdgeScrollState {
  /// 卡片中心 X 坐标 (屏幕坐标)
  double cardCenterX = 0;
  /// 屏幕宽度
  double screenWidth = 0;
  /// 是否处于边缘滚动模式
  bool visible = false;

  CategoryDropEdgeScrollState();
}

/// 分类桶选择行组件
///
/// 基于 photoo FolderDropRow 实现 (FolderDropTarget.kt)
/// - 下滑 > 300px 时从底部滑入显示
/// - 桶激活时有弹性缩放动画 (scale 0.82->1.2, lift 0->-8dp, width 68->88dp)
/// - 支持碰撞检测确定最近桶
/// - LazyRow 支持水平滚动
/// - 支持边缘滚动：当卡片靠近列表边缘时自动滚动
class CategoryDropRow extends StatefulWidget {
  /// 是否显示
  final bool visible;
  /// 分类桶列表
  final List<CategoryBucket> buckets;
  /// 当前激活的桶 ID
  final String? activeBucketId;
  /// 桶位置变化回调
  final void Function(Map<String, Rect>)? onBucketPositionsChanged;
  /// 桶激活状态变化回调
  final void Function(String?)? onActiveBucketChanged;
  /// 桶被选中回调
  final void Function(String bucketId)? onBucketSelected;
  /// 边缘滚动状态引用
  final CategoryDropEdgeScrollState? edgeScrollState;

  const CategoryDropRow({
    super.key,
    required this.visible,
    required this.buckets,
    this.activeBucketId,
    this.onBucketPositionsChanged,
    this.onActiveBucketChanged,
    this.onBucketSelected,
    this.edgeScrollState,
  });

  @override
  State<CategoryDropRow> createState() => CategoryDropRowState();
}

class CategoryDropRowState extends State<CategoryDropRow>
    with SingleTickerProviderStateMixin {
  final Map<String, GlobalKey> _bucketKeys = {};
  final Map<String, Rect> _bucketRects = {};

  // 滚动控制器
  late ScrollController _scrollController;

  // 动画控制器
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // 边缘滚动
  static const double _edgeScrollThreshold = 80.0; // 边缘触发阈值
  static const double _maxScrollSpeed = 15.0; // 最大滚动速度

  // 边缘滚动循环控制器
  bool _isEdgeScrolling = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_animController);

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));

    _scrollController = ScrollController();

    _initBucketKeys();

    if (widget.visible) {
      _animController.value = 1.0;
    }
  }

  void _initBucketKeys() {
    _bucketKeys.clear();
    for (var bucket in widget.buckets) {
      _bucketKeys[bucket.id] = GlobalKey();
    }
  }

  @override
  void didUpdateWidget(CategoryDropRow oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    }

    if (widget.buckets != oldWidget.buckets) {
      _initBucketKeys();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _updateBucketRects());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _updateBucketRects() {
    final newRects = <String, Rect>{};
    for (var entry in _bucketKeys.entries) {
      final renderBox = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final position = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        newRects[entry.key] = Rect.fromLTWH(
          position.dx,
          position.dy,
          size.width,
          size.height,
        );
      }
    }

    if (_bucketRects.isEmpty || !_rectsEqual(_bucketRects, newRects)) {
      _bucketRects.clear();
      _bucketRects.addAll(newRects);
      widget.onBucketPositionsChanged?.call(Map.from(_bucketRects));
    }
  }

  bool _rectsEqual(Map<String, Rect> a, Map<String, Rect> b) {
    if (a.length != b.length) return false;
    for (var entry in a.entries) {
      final other = b[entry.key];
      if (other == null || entry.value != other) return false;
    }
    return true;
  }

  /// 计算最近的桶 (280px 半径粘附阈值)
  String? _findClosestBucket(Offset cardCenter) {
    if (_bucketRects.isEmpty) return null;

    String? closestId;
    double minDist = double.infinity;

    for (var entry in _bucketRects.entries) {
      final rect = entry.value;
      final bucketCenter = rect.center;
      final dx = cardCenter.dx - bucketCenter.dx;
      final dy = cardCenter.dy - bucketCenter.dy;
      final dist = dx * dx + dy * dy;

      if (dist < 280 * 280 && dist < minDist) {
        minDist = dist;
        closestId = entry.key;
      }
    }

    return closestId;
  }

  /// 更新卡片碰撞检测
  void updateCardPosition(Offset cardCenter) {
    final closestId = _findClosestBucket(cardCenter);
    if (closestId != widget.activeBucketId) {
      widget.onActiveBucketChanged?.call(closestId);
    }
    _updateEdgeScroll(cardCenter);
  }

  /// 计算边缘滚动速度
  double _calculateEdgeScrollSpeed(double cardCenterX, double screenWidth) {
    if (!_scrollController.hasClients) return 0;

    final viewportWidth = _scrollController.position.viewportDimension;
    final contentWidth = _scrollController.position.maxScrollExtent + viewportWidth;
    final scrollOffset = _scrollController.offset;

    // 左边缘区域
    if (cardCenterX < _edgeScrollThreshold) {
      final proximity = 1 - (cardCenterX / _edgeScrollThreshold);
      return -_maxScrollSpeed * proximity;
    }

    // 右边缘区域
    if (cardCenterX > screenWidth - _edgeScrollThreshold) {
      final proximity = 1 - ((screenWidth - cardCenterX) / _edgeScrollThreshold);
      final maxScroll = contentWidth - scrollOffset - viewportWidth;
      if (maxScroll > 0) {
        return _maxScrollSpeed * proximity;
      }
    }

    return 0;
  }

  /// 更新边缘滚动
  void _updateEdgeScroll(Offset cardCenter) {
    if (!widget.visible || !widget.edgeScrollState!.visible) return;

    final speed = _calculateEdgeScrollSpeed(
      cardCenter.dx,
      widget.edgeScrollState!.screenWidth > 0
          ? widget.edgeScrollState!.screenWidth
          : MediaQuery.of(context).size.width,
    );

    if (speed != 0 && !_isEdgeScrolling) {
      _startEdgeScrollLoop();
    }
  }

  /// 开始边缘滚动循环
  void _startEdgeScrollLoop() {
    _isEdgeScrolling = true;
    _runEdgeScroll();
  }

  void _runEdgeScroll() async {
    while (_isEdgeScrolling && mounted) {
      await Future.delayed(const Duration(milliseconds: 16)); // ~60fps

      if (!widget.visible || !mounted) {
        _isEdgeScrolling = false;
        break;
      }

      final speed = _calculateEdgeScrollSpeed(
        widget.edgeScrollState!.cardCenterX,
        widget.edgeScrollState!.screenWidth > 0
            ? widget.edgeScrollState!.screenWidth
            : MediaQuery.of(context).size.width,
      );

      if (speed == 0) {
        _isEdgeScrolling = false;
        break;
      }

      if (_scrollController.hasClients) {
        final newOffset = (_scrollController.offset + speed).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(newOffset);
      }
    }
    _isEdgeScrolling = false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value.clamp(0.0, 1.0),
          child: FractionalTranslation(
            translation: _slideAnimation.value,
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: ListView.builder(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: widget.buckets.length,
          itemBuilder: (context, index) {
            final bucket = widget.buckets[index];
            return _BucketItem(
              key: _bucketKeys[bucket.id],
              bucket: bucket,
              isActive: bucket.id == widget.activeBucketId,
              onTap: () => widget.onBucketSelected?.call(bucket.id),
            );
          },
        ),
      ),
    );
  }
}

/// 单个分类桶组件
///
/// 基于 photoo FolderItem:
///
/// val scale by animateFloatAsState(
///     targetValue = if (isActive) 1.2f else 0.82f,
///     animationSpec = spring(dampingRatio = 0.6f, stiffness = 320f)
/// )
/// val lift by animateDpAsState(
///     targetValue = if (isActive) (-8).dp else 0.dp,
///     animationSpec = spring(dampingRatio = 0.7f, stiffness = 320f)
/// )
/// val itemWidth by animateDpAsState(
///     targetValue = if (isActive) 88.dp else 68.dp,
///     animationSpec = spring(dampingRatio = 0.7f, stiffness = 320f)
/// )
class _BucketItem extends StatefulWidget {
  final CategoryBucket bucket;
  final bool isActive;
  final VoidCallback? onTap;

  const _BucketItem({
    super.key,
    required this.bucket,
    required this.isActive,
    this.onTap,
  });

  @override
  State<_BucketItem> createState() => _BucketItemState();
}

class _BucketItemState extends State<_BucketItem>
    with SingleTickerProviderStateMixin {
  // 动画值
  double _scale = 0.82;
  double _lift = 0;
  double _width = 68;

  // Spring 参数 (匹配 Kotlin: spring(dampingRatio=0.6f, stiffness=320f))
  static final SpringDescription _scaleSpring = SpringDescription(
    mass: 1.0,
    stiffness: 320.0,
    damping: 0.6 * 2 * sqrt(320.0), // ≈ 21.47
  );
  // lift 和 width 共用同一个 spring (dampingRatio=0.7f, stiffness=320f)
  static final SpringDescription _otherSpring = SpringDescription(
    mass: 1.0,
    stiffness: 320.0,
    damping: 0.7 * 2 * sqrt(320.0), // ≈ 25.05
  );

  late AnimationController _scaleController;
  late AnimationController _liftController;
  late AnimationController _widthController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController.unbounded(vsync: this);
    _liftController = AnimationController.unbounded(vsync: this);
    _widthController = AnimationController.unbounded(vsync: this);

    _scaleController.addListener(() {
      setState(() {
        _scale = _scaleController.value.clamp(0.82, 1.2);
      });
    });
    _liftController.addListener(() {
      setState(() {
        _lift = _liftController.value.clamp(-8.0, 0.0);
      });
    });
    _widthController.addListener(() {
      setState(() {
        _width = _widthController.value.clamp(68.0, 88.0);
      });
    });

    if (widget.isActive) {
      _scale = 1.2;
      _lift = -8;
      _width = 88;
    }
  }

  @override
  void didUpdateWidget(_BucketItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        // 激活动画
        _scaleController.animateWith(
          SpringSimulation(_scaleSpring, _scale, 1.2, 0),
        );
        _liftController.animateWith(
          SpringSimulation(_otherSpring, _lift, -8, 0),
        );
        _widthController.animateWith(
          SpringSimulation(_otherSpring, _width, 88, 0),
        );
      } else {
        // 取消激活动画
        _scaleController.animateWith(
          SpringSimulation(_scaleSpring, _scale, 0.82, 0),
        );
        _liftController.animateWith(
          SpringSimulation(_otherSpring, _lift, 0, 0),
        );
        _widthController.animateWith(
          SpringSimulation(_otherSpring, _width, 68, 0),
        );
      }
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _liftController.dispose();
    _widthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _width,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: Offset(0, _lift),
              child: Transform.scale(
                scale: _scale,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: widget.isActive
                        ? const Color(0xFFEFF6FF)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: widget.isActive
                          ? const Color(0xFF3B82F6)
                          : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.bucket.icon,
                    color: widget.isActive
                        ? const Color(0xFF3B82F6)
                        : Colors.grey.shade600,
                    size: 32,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.bucket.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: widget.isActive ? FontWeight.bold : FontWeight.w500,
                color: widget.isActive
                    ? const Color(0xFF3B82F6)
                    : Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
