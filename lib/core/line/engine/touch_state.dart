import '../domain/constants.dart';
import '../domain/note_event.dart';

// ── 触摸列映射 ──

/// 根据 x 坐标计算所在列
int? columnFromX(double x, double screenWidth, int colCount) {
  if (screenWidth <= 0 || colCount <= 0) return null;
  final colWidth = screenWidth / colCount;
  final i = (x / colWidth).floor();
  if (i < 0 || i >= colCount) return null;
  return i;
}

/// 检测滑动方向（纯函数）
SlideDirection? swipeDirection(
  double dx,
  double dy, {
  double distanceThreshold = swipeDistanceThreshold,
}) {
  if (dx.abs() < distanceThreshold && dy.abs() < distanceThreshold) {
    return null;
  }
  if (dx.abs() > dy.abs()) {
    return dx > 0 ? SlideDirection.right : SlideDirection.left;
  }
  return dy > 0 ? SlideDirection.down : SlideDirection.up;
}
