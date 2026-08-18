import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'novel_render_page.dart';

class NovelPageRenderer {
  const NovelPageRenderer();

  ui.Picture render({
    required NovelRenderPage page,
    required Size size,
    required EdgeInsets padding,
    required TextStyle textStyle,
  }) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bounds = Offset.zero & size;
    final borderRadius = BorderRadius.circular(18);
    final rrect = borderRadius.toRRect(bounds);

    final backgroundPaint = Paint()..color = const Color(0xFFF9F1E4);
    canvas.drawRRect(rrect, backgroundPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFFD9C4AE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(rrect, borderPaint);

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.fromRGBO(255, 255, 255, 0.28),
            Color.fromRGBO(255, 255, 255, 0.0),
            Color.fromRGBO(165, 42, 42, 0.03),
          ],
        ).createShader(bounds),
    );
    canvas.restore();

    final painter = TextPainter(
      text: TextSpan(text: page.text.trimLeft(), style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.start,
    );
    painter.layout(maxWidth: size.width - padding.horizontal);
    painter.paint(canvas, Offset(padding.left, padding.top));

    return recorder.endRecording();
  }
}
