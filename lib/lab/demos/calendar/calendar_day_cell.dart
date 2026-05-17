import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 颜色解析：#RRGGBB / RRGGBB / #AARRGGBB
Color? parseHex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final s = hex.startsWith('#') ? hex.substring(1) : hex;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return Color(s.length == 6 ? 0xFF000000 | v : v);
}

/// 单日圆环 cell：
/// - 当天：填充蓝底，数字白色
/// - 本月其他天：灰色背景圆环；事件用等分弧标记
/// - 上/下月：仅淡色数字
class CalendarDayCell extends StatelessWidget {
  final int day;
  final bool isToday;
  final bool inCurrentMonth;
  final bool isWeekend;
  final List<String> colors;
  final VoidCallback? onTap;

  const CalendarDayCell({
    super.key,
    required this.day,
    required this.isToday,
    required this.inCurrentMonth,
    required this.isWeekend,
    required this.colors,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color numberColor;
    if (isToday) {
      numberColor = Colors.white;
    } else if (!inCurrentMonth) {
      numberColor = const Color(0xFFBDBDBD);
    } else if (isWeekend) {
      numberColor = const Color(0xFFE53935);
    } else {
      numberColor = const Color(0xFF212121);
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _DayCellPainter(
            isToday: isToday,
            inCurrentMonth: inCurrentMonth,
            colors: colors,
          ),
          child: Center(
            child: Text(
              '$day',
              style: TextStyle(
                fontSize: 15,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                color: numberColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayCellPainter extends CustomPainter {
  final bool isToday;
  final bool inCurrentMonth;
  final List<String> colors;

  _DayCellPainter({
    required this.isToday,
    required this.inCurrentMonth,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(size.width, size.height) * 0.4;
    final ringStroke = radius * 0.22;

    if (isToday) {
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF1976D2);
      canvas.drawCircle(Offset(cx, cy), radius, fill);
    } else if (inCurrentMonth) {
      final bg = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringStroke
        ..color = const Color(0xFFE0E0E0);
      canvas.drawCircle(Offset(cx, cy), radius, bg);
    }

    if (inCurrentMonth && colors.isNotEmpty) {
      final n = colors.length;
      final sweep = 2 * math.pi / n;
      final gap = n > 1 ? (math.pi / 90) : 0.0; // 2°
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);
      for (var i = 0; i < n; i++) {
        final c = parseHex(colors[i]) ?? Colors.black;
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringStroke
          ..strokeCap = StrokeCap.butt
          ..color = c;
        final start = -math.pi / 2 + sweep * i + gap / 2;
        canvas.drawArc(rect, start, sweep - gap, false, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DayCellPainter old) =>
      old.isToday != isToday ||
      old.inCurrentMonth != inCurrentMonth ||
      !_listEq(old.colors, colors);

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
