import '../domain/constants.dart';
import '../domain/note_event.dart';

/// 根据 x 坐标计算所在列
int? columnFromX(double x, double screenWidth, int colCount) {
  if (screenWidth <= 0 || colCount <= 0) return null;
  final colWidth = screenWidth / colCount;
  final i = (x / colWidth).floor();
  if (i < 0 || i >= colCount) return null;
  return i;
}

/// 检测滑动方向（位移 + 可选速度）
SlideDirection? swipeDirection(
  double dx,
  double dy, {
  double distanceThreshold = swipeDistanceThreshold,
  double velocityPxPerSec = 0,
  double velocityThreshold = swipeVelocityThreshold,
}) {
  final farEnough = dx.abs() >= distanceThreshold || dy.abs() >= distanceThreshold;
  final fastEnough = velocityPxPerSec >= velocityThreshold;
  if (!farEnough && !fastEnough) return null;
  // 速度够但位移不够时仍要求最小位移，避免微抖
  final minDist = distanceThreshold * 0.45;
  if (dx.abs() < minDist && dy.abs() < minDist) return null;
  if (dx.abs() > dy.abs()) {
    return dx > 0 ? SlideDirection.right : SlideDirection.left;
  }
  return dy > 0 ? SlideDirection.down : SlideDirection.up;
}
