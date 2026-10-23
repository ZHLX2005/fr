// lib/core/remotetype/settings/rt_new_layout_row.dart
//
// 大卡下方的「新建自定义布局」虚线行：点按选朝向建空画布。
//
// 虚线描边自己画（Flutter 无内置虚线边框），只为一颗按钮不值得引包。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/context/colors.dart';
import '../data/rt_prefs.dart'
    show kRtCanvasOrientLandscape, kRtCanvasOrientPortrait;

/// 「新建自定义布局」：选朝向建空画布（rtLayoutsCopyToCustom）。
class RtNewLayoutRow extends StatelessWidget {
  const RtNewLayoutRow({super.key, required this.onCreate});

  /// 参数 = 用户选的朝向 kRtCanvasOrient*。
  final ValueChanged<String> onCreate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final border = _DashedRoundedRectBorder(color: c.scheme.outline, radius: 16);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: c.scheme.surface,
        shape: border,
        child: InkWell(
          customBorder: border,
          onTap: () => _pickOrientation(context),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_box_outlined, size: 18, color: c.textMuted),
                const SizedBox(width: 8),
                Text(
                  '新建自定义布局',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: c.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickOrientation(BuildContext context) async {
    final orient = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('新建自定义布局（选择朝向）'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(kRtCanvasOrientLandscape),
            child: const ListTile(
              leading: Icon(Icons.stay_current_landscape),
              title: Text('横屏布局'),
              subtitle: Text('空画布，横竖屏都可用'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(kRtCanvasOrientPortrait),
            child: const ListTile(
              leading: Icon(Icons.stay_current_portrait),
              title: Text('竖屏布局'),
              subtitle: Text('空画布，仅竖屏可用'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
    if (orient != null) onCreate(orient);
  }
}

/// 虚线圆角描边（新建行观感对齐原型 dashed border）。
class _DashedRoundedRectBorder extends ShapeBorder {
  const _DashedRoundedRectBorder({
    required this.color,
    this.radius = 14,
    this.dashWidth = 5,
    this.dashGap = 4,
    this.width = 1.1,
  });

  final Color color;
  final double radius;
  final double dashWidth;
  final double dashGap;
  final double width;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            rect.deflate(width),
            Radius.circular(radius),
          ),
        );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()
        ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = color;
    final path =
        Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              rect.deflate(width / 2),
              Radius.circular(radius),
            ),
          );
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = math.min(dist + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next + dashGap;
      }
    }
  }

  @override
  ShapeBorder scale(double t) => _DashedRoundedRectBorder(
    color: color,
    radius: radius * t,
    dashWidth: dashWidth * t,
    dashGap: dashGap * t,
    width: width * t,
  );
}
