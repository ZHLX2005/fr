import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/waveform_view.dart';

void main() {
  group('WaveformPainter', () {
    test('shouldRepaint: dbs 引用不同 → 重绘', () {
      final a = _makePainter([-60, -30, 0]);
      final b = _makePainter([-60, -30, -10]); // 内容不同
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint: dbs 相同引用 → 不重绘', () {
      final dbs = <double>[-60, -30, 0];
      final a = _makePainter(dbs);
      final b = _makePainter(dbs); // 同一引用
      expect(a.shouldRepaint(b), isFalse);
    });

    test('dbToRatio: -60 → 0,0 → 1,中段线性', () {
      expect(dbToRatio(-60), 0.0);
      expect(dbToRatio(0), 1.0);
      expect(dbToRatio(-30), closeTo(0.5, 1e-9));
      // 钳制
      expect(dbToRatio(-100), 0.0);
      expect(dbToRatio(5), 1.0);
    });

    test('dbToRatio NaN → 0', () {
      expect(dbToRatio(double.nan), 0.0);
    });

    test('barCenterX: 固定列距,不随已录制帧数缩放(流式)', () {
      // 第 index 列的 x 只由 maxBars 决定 —— 帧数少时也不会整体铺满/堆叠
      expect(barCenterX(0, 200, 400), closeTo(1.0, 1e-9));
      expect(barCenterX(5, 200, 400), closeTo(11.0, 1e-9));
      expect(barCenterX(199, 200, 400), closeTo(399.0, 1e-9));
      // 回归:旧实现 step=width/dbs.length,3 帧时第 2 帧会被拉到 ~333px 处;
      // 现在固定列距,仍在 ~5px 处(列距 2px)。
      expect(barCenterX(2, 200, 400), closeTo(5.0, 1e-9));
    });

    test('shouldRepaint: maxBars 不同 → 重绘', () {
      final a = _makePainter([-60, -30, 0]);
      final b = _makePainter([-60, -30, 0], maxBars: 100);
      expect(a.shouldRepaint(b), isTrue);
    });
  });
}

WaveformPainter _makePainter(List<double> dbs, {int maxBars = 200}) {
  return WaveformPainter(
    dbs: dbs,
    maxBars: maxBars,
    baseColor: const Color(0xFF7A9A7E),
    hotColor: const Color(0xFFA0594A),
    centerLine: const Color(0xFFD9D5C8),
  );
}
