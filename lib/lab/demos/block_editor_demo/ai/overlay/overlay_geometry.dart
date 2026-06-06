import 'dart:ui';

/// 窗口几何数据
class OverlayGeometry {
  Offset position;
  Size size;

  OverlayGeometry({
    required this.position,
    required this.size,
  });

  static const double minWidth = 260;
  static const double maxWidth = 600;
  static const double minHeight = 320;
  static const double maxHeight = 800;

  static const double edgeSize = 20;
  static const double cornerSize = 32;
  static const double headerHeight = 48;

  Size clampSize(Size size) => Size(
        size.width.clamp(minWidth, maxWidth),
        size.height.clamp(minHeight, maxHeight),
      );

  bool isInHeader(Offset local) =>
      local.dy < headerHeight && local.dx < size.width - 40;

  bool isInRightEdge(Offset local) =>
      local.dx > size.width - edgeSize && local.dy <= size.height - cornerSize;

  bool isInBottomEdge(Offset local) =>
      local.dy > size.height - edgeSize && local.dx <= size.width - cornerSize;

  bool isInCorner(Offset local) =>
      local.dx > size.width - cornerSize && local.dy > size.height - cornerSize;
}
