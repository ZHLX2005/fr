import 'package:flutter/material.dart';

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
/// 基于 photoo FolderDropRow 实现：
/// - 下滑 > 300px 时从底部滑入显示
/// - 桶激活时有弹性缩放动画
/// - 支持碰撞检测确定最近桶
class CategoryDropRow extends StatefulWidget {
  /// 是否显示
  final bool visible;
  /// 分类桶列表
  final List<CategoryBucket> buckets;
  /// 当前激活的桶 ID
  final String? activeBucketId;
  /// 桶位置变化回调 (bucketId -> Rect)
  final void Function(Map<String, Rect>)? onBucketPositionsChanged;
  /// 桶激活状态变化回调
  final void Function(String?)? onActiveBucketChanged;
  /// 桶被选中回调
  final void Function(String bucketId)? onBucketSelected;

  const CategoryDropRow({
    super.key,
    required this.visible,
    required this.buckets,
    this.activeBucketId,
    this.onBucketPositionsChanged,
    this.onActiveBucketChanged,
    this.onBucketSelected,
  });

  @override
  State<CategoryDropRow> createState() => CategoryDropRowState();
}

class CategoryDropRowState extends State<CategoryDropRow> {
  final Map<String, GlobalKey> _bucketKeys = {};
  final Map<String, Rect> _bucketRects = {};

  @override
  void initState() {
    super.initState();
    for (var bucket in widget.buckets) {
      _bucketKeys[bucket.id] = GlobalKey();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateBucketRects());
  }

  @override
  void didUpdateWidget(CategoryDropRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buckets != widget.buckets) {
      _bucketKeys.clear();
      for (var bucket in widget.buckets) {
        _bucketKeys[bucket.id] = GlobalKey();
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateBucketRects());
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
    if (_bucketRects != newRects) {
      _bucketRects.clear();
      _bucketRects.addAll(newRects);
      widget.onBucketPositionsChanged?.call(Map.from(_bucketRects));
    }
  }

  /// 计算最近的桶
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

      // 280px 半径粘附阈值 (photox: 280f)
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
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: widget.visible ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: widget.buckets.map((bucket) {
              return _BucketItem(
                key: _bucketKeys[bucket.id],
                bucket: bucket,
                isActive: bucket.id == widget.activeBucketId,
                onTap: () => widget.onBucketSelected?.call(bucket.id),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// 单个分类桶组件
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
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _liftAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);

    // 弹性动画配置 (基于 photoo: dampingRatio=0.6f, stiffness=320f)
    _scaleAnimation = Tween<double>(begin: 0.82, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _liftAnimation = Tween<double>(begin: 0, end: -8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(_BucketItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _liftAnimation.value),
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: widget.bucket.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.bucket.color.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                widget.bucket.icon,
                color: widget.bucket.color,
                size: 32,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.bucket.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
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
