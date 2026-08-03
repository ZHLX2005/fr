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
  });
}

WaveformPainter _makePainter(List<double> dbs) {
  return WaveformPainter(
    dbs: dbs,
    baseColor: const Color(0xFF7A9A7E),
    hotColor: const Color(0xFFA0594A),
    centerLine: const Color(0xFFD9D5C8),
  );
}
