import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import '../word_drag_constants.dart';

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
    ).animate(_animController); // tween(200) 默认 linear (FastOutLinearInEasing)

    _scrollController = ScrollController();

    _initBucketKeys();

    if (widget.visible) {
      _animController.value = 1.0;
    }

    // 初始化后延迟更新桶位置 (匹配 Kotlin onGloballyPositioned 行为)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateBucketRects();
    });
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
        // 重置滚动位置到开头 (匹配 Kotlin: folderListState.scrollToItem(0))
        _scrollController.jumpTo(0);
        _animController.forward();
        // 动画开始后更新桶位置（确保布局已完成）
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.visible) _updateBucketRects();
        });
      } else {
        // 隐藏时清除桶位置 (匹配 Kotlin: rects.clear())
        _bucketRects.clear();
        _animController.reverse();
      }
    }

    if (widget.buckets != oldWidget.buckets) {
      _initBucketKeys();
    }
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
      final renderBox =
          entry.value.currentContext?.findRenderObject() as RenderBox?;
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

  /// 强制立即更新桶位置（在碰撞检测前调用）
  /// 立即执行更新，不等待下一帧
  void forceUpdateRects() {
    if (mounted && widget.visible) {
      _updateBucketRects();
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

  /// 计算最近的桶 (匹配 Kotlin 碰撞检测逻辑)
  /// 包含 bandPadding 和水平滑动忽略逻辑
  String? _findClosestBucket(Offset cardCenter, double offsetX) {
    if (_bucketRects.isEmpty) return null;

    // 水平滑动检测: |offsetX| > 500 时忽略桶目标
    final isHorizontalSwipe =
        offsetX.abs() > WordDragConstants.horizontalSwipeThreshold;
    if (isHorizontalSwipe) return null;

    // 找出在垂直频道内的桶
    final inBand = <String, Rect>{};
    for (var entry in _bucketRects.entries) {
      final rect = entry.value;
      if (cardCenter.dy >= rect.top - WordDragConstants.bandPadding &&
          cardCenter.dy <= rect.bottom + WordDragConstants.bandPadding) {
        inBand[entry.key] = rect;
      }
    }

    // 使用 inBand 或所有有效 rect
    final pool = inBand.isNotEmpty ? inBand : _bucketRects;

    String? closestId;
    double minDist = double.infinity;

    for (var entry in pool.entries) {
      final rect = entry.value;
      final bucketCenter = rect.center;
      final dx = cardCenter.dx - bucketCenter.dx;
      final dy = cardCenter.dy - bucketCenter.dy;
      final dist = dx * dx + dy * dy;

      // 粘附条件: 距离 < 280px 或在频道内
      if ((dist <
                  WordDragConstants.stickyRadius *
                      WordDragConstants.stickyRadius ||
              inBand.isNotEmpty) &&
          dist < minDist) {
        minDist = dist;
        closestId = entry.key;
      }
    }

    return closestId;
  }

  /// 更新卡片碰撞检测
  void updateCardPosition(Offset cardCenter, double offsetX) {
    final closestId = _findClosestBucket(cardCenter, offsetX);
    if (closestId != widget.activeBucketId) {
      widget.onActiveBucketChanged?.call(closestId);
    }
    _updateEdgeScroll(cardCenter);
  }

  /// 清除活跃桶状态（退出文件夹模式时调用）
  void clearActiveBucket() {
    if (widget.activeBucketId != null) {
      widget.onActiveBucketChanged?.call(null);
    }
  }

  /// 计算边缘滚动速度
  double _calculateEdgeScrollSpeed(double cardCenterX, double screenWidth) {
    if (!_scrollController.hasClients) return 0;

    // 左边缘
    final leftOverflow = WordDragConstants.edgeScrollThreshold - cardCenterX;
    if (leftOverflow > 0) {
      final factor = (leftOverflow / WordDragConstants.edgeScrollThreshold)
          .clamp(0.0, 1.0);
      return -(WordDragConstants.minScrollSpeed +
          (WordDragConstants.maxScrollSpeed -
                  WordDragConstants.minScrollSpeed) *
              factor);
    }

    // 右边缘
    final rightOverflow =
        cardCenterX - (screenWidth - WordDragConstants.edgeScrollThreshold);
    if (rightOverflow > 0) {
      final factor = (rightOverflow / WordDragConstants.edgeScrollThreshold)
          .clamp(0.0, 1.0);
      // 检查是否还有可滚动内容
      final viewportWidth = _scrollController.position.viewportDimension;
      final maxScroll =
          _scrollController.position.maxScrollExtent +
          viewportWidth -
          _scrollController.offset;
      if (maxScroll > 0) {
        return WordDragConstants.minScrollSpeed +
            (WordDragConstants.maxScrollSpeed -
                    WordDragConstants.minScrollSpeed) *
                factor;
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
        height: WordDragConstants.categoryRowHeight,
        padding: const EdgeInsets.symmetric(
          vertical: WordDragConstants.categoryRowPaddingV,
        ),
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
  double _scale = WordDragConstants.bucketDefaultScale;
  double _width = WordDragConstants.bucketDefaultWidth;

  late AnimationController _scaleController;
  late AnimationController _widthController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController.unbounded(vsync: this);
    _widthController = AnimationController.unbounded(vsync: this);

    _scaleController.addListener(() {
      setState(() {
        _scale = _scaleController.value.clamp(
          WordDragConstants.bucketDefaultScale,
          WordDragConstants.bucketActiveScale,
        );
      });
    });
    _widthController.addListener(() {
      setState(() {
        _width = _widthController.value.clamp(
          WordDragConstants.bucketDefaultWidth,
          WordDragConstants.bucketActiveWidth,
        );
      });
    });

    if (widget.isActive) {
      _scale = WordDragConstants.bucketActiveScale;
      _width = WordDragConstants.bucketActiveWidth;
    }
  }

  @override
  void didUpdateWidget(_BucketItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        // 激活动画
        _scaleController.animateWith(
          SpringSimulation(
            WordDragConstants.bucketScaleSpring,
            _scale,
            WordDragConstants.bucketActiveScale,
            0,
          ),
        );
        _widthController.animateWith(
          SpringSimulation(
            WordDragConstants.bucketOtherSpring,
            _width,
            WordDragConstants.bucketActiveWidth,
            0,
          ),
        );
      } else {
        // 取消激活动画
        _scaleController.animateWith(
          SpringSimulation(
            WordDragConstants.bucketScaleSpring,
            _scale,
            WordDragConstants.bucketDefaultScale,
            0,
          ),
        );
        _widthController.animateWith(
          SpringSimulation(
            WordDragConstants.bucketOtherSpring,
            _width,
            WordDragConstants.bucketDefaultWidth,
            0,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _widthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 用 AnimatedContainer + padding 实现 lift 效果（替代 Transform.translate）
    // Transform.translate 只移动视觉，不改变布局，会被父容器截断
    // 通过动态 padding 让容器本身为 lift 留出空间，不会溢出
    return Container(
      width: _width,
      margin: const EdgeInsets.symmetric(
        horizontal: WordDragConstants.bucketSpacing / 2,
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              // 激活时增加顶部 padding，实现视觉上的向上移动效果
              padding: EdgeInsets.only(top: widget.isActive ? 8 : 0),
              child: Transform.scale(
                scale: _scale,
                child: Container(
                  width: WordDragConstants.bucketIconSize,
                  height: WordDragConstants.bucketIconSize,
                  decoration: BoxDecoration(
                    color: widget.isActive
                        ? const Color(0xFFEFF6FF)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(
                      WordDragConstants.bucketRadius,
                    ),
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
