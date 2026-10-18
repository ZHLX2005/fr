import 'package:flutter/widgets.dart';

/// 限制最大下拉 overscroll 距离的 BouncingScrollPhysics。
///
/// Flutter 默认 [BouncingScrollPhysics] 允许几乎无限的橡皮筋拉伸，
/// 配合 `SliverAppBar(stretch: true)` 会让 banner 拉得过高。
/// 本物理在 overscroll 区对 user offset 做更陡的非线性衰减，
/// 让最大可拉伸距离收敛到 [maxOverscroll]。
class BoundedBouncingScrollPhysics extends BouncingScrollPhysics {
  const BoundedBouncingScrollPhysics({
    super.parent,
    this.maxOverscroll = 80.0,
  });

  /// 允许的最大 overscroll 距离（像素），默认 80。
  final double maxOverscroll;

  @override
  BoundedBouncingScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return BoundedBouncingScrollPhysics(
      parent: buildParent(ancestor),
      maxOverscroll: maxOverscroll,
    );
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // 完全沿用父类：允许 overscroll 进入负值 / 超出 maxScrollExtent。
    return super.applyBoundaryConditions(position, value);
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    // 仅在顶部 overscroll（pixels 接近/低于 minScrollExtent）时做限幅衰减。
    final min = position.minScrollExtent;
    final overscrollPast = (min - position.pixels).clamp(0.0, double.infinity);

    if (overscrollPast <= 0) {
      // 用户已经在 overscroll 之外（向 0 方向），交给默认逻辑
      return super.applyPhysicsToUserOffset(position, offset);
    }

    // 越接近 maxOverscroll 衰减越陡：iOS 公式是 0.52 * (1 - overscroll/(屏幕高))，
    // 这里改成基于固定上限的非线性衰减，让总拉伸不超过 maxOverscroll。
    final ratio = (overscrollPast / maxOverscroll).clamp(0.0, 1.0);
    // 拉得越多，每像素 user offset 转化的实际位移越小（指数衰减）
    final factor = (1.0 - ratio) * 0.55 + 0.02;
    return offset * factor;
  }
}
