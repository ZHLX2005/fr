import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/waveform_view.dart';

// 锁定 WaveformView 的 false→true 边沿语义:
// 新一次录音开始(active 由 false 翻 true)必须清空环形缓冲 _dbs,
// 否则用户会看到上一次 take 的波形从屏外滚入。
// 通过对 painter 公开 dbs 字段的观测来验证,无需访问私有 State。

void main() {
  testWidgets('active false→true 边沿清空 _dbs 波形缓冲', (tester) async {
    final db = ValueNotifier<double>(-60.0);

    // 1) active=true 挂载
    await tester.pumpWidget(
      MaterialApp(home: WaveformView(dbListenable: db, active: true)),
    );

    // 2) 推若干幅度帧 —— _onDb 因 active=true 会追加到 _dbs
    db.value = -10;
    await tester.pump();
    db.value = -20;
    await tester.pump();
    db.value = -5;
    await tester.pump();

    // 3) 读取渲染出的 painter,断言已累积帧
    var painter = _readPainter(tester);
    expect(painter.dbs.length, greaterThan(0), reason: 'active 期间应累积波形帧');

    // 4) 翻 true→false —— 不应清空(停止态保留最后形状)
    await tester.pumpWidget(
      MaterialApp(home: WaveformView(dbListenable: db, active: false)),
    );
    painter = _readPainter(tester);
    expect(painter.dbs.length, greaterThan(0),
        reason: 'true→false 不应清空,停止态保留最后形状');

    // 5) 翻 false→true —— 边沿应清空,新录音从头开始
    await tester.pumpWidget(
      MaterialApp(home: WaveformView(dbListenable: db, active: true)),
    );
    painter = _readPainter(tester);
    expect(painter.dbs, isEmpty, reason: 'false→true 边沿应清空缓冲');
  });
}

/// 从已挂载的树中取出 WaveformView 渲染时使用的 painter,
/// 通过其公开 dbs 字段观测内部缓冲状态。
WaveformPainter _readPainter(WidgetTester tester) {
  final customPaint = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is WaveformPainter,
    ),
  );
  return customPaint.painter as WaveformPainter;
}
