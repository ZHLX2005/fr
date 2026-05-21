import '../domain/note_event.dart';

// ── 触摸列映射 ──

/// 根据 x 坐标计算所在列
int? columnFromX(double x, double screenWidth, int colCount) {
  final colWidth = screenWidth / colCount;
  for (int i = 0; i < colCount; i++) {
    if (x >= colWidth * i && x < colWidth * (i + 1)) return i;
  }
  return null;
}

/// 检测滑动方向（纯函数）
SlideDirection? swipeDirection(double dx, double dy) {
  const threshold = 100.0;
  if (dx.abs() < threshold && dy.abs() < threshold) return null;
  if (dx.abs() > dy.abs()) {
    return dx > 0 ? SlideDirection.right : SlideDirection.left;
  } else {
    return dy > 0 ? SlideDirection.down : SlideDirection.up;
  }
}
