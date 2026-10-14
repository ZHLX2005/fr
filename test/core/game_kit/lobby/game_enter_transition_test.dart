// test/core/game_kit/lobby/game_enter_transition_test.dart
//
// GameEnterTransition 状态机测试：
//   · 准备态 → playing 首次切入 → 根 Overlay 播刷子，播完遮罩移除
//   · playing → 准备态（RESET 再来一局）→ 重新武装，再次进入再播
//   · 首次 update 即 playing（断线重连中途进入）→ 不盖屏
//   · 门控 Future 在揭开完成后才 resolve（实时游戏据此推迟引擎/计时）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/game_kit/lobby/brush_wipe_overlay.dart';
import 'package:xiaodouzi_fr/core/game_kit/lobby/game_enter_transition.dart';

/// 遮罩揭开链有微任务/定时器步进（pumpAndSettle 在无帧调度时会提前停）
/// → 追加泵帧直到遮罩消失。
Future<void> _pumpUntilOverlayGone(WidgetTester tester) async {
  await tester.pumpAndSettle();
  for (var i = 0; i < 20; i++) {
    if (find.byType(BrushWipeOverlay).evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('过渡结束后遮罩应移除');
}

void main() {
  testWidgets('准备态 → playing 首次切入 → 盖屏；门控在揭开后才 resolve', (tester) async {
    final fx = GameEnterTransition();
    var inGame = false;
    Future<void>? lastGate;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  lastGate = fx.update(context, inGame);
                },
                child: const Text('tick'),
              ),
            ),
          ),
        ),
      ),
    );

    // 1) 准备态快照：不盖屏、无门控。
    await tester.tap(find.text('tick'));
    await tester.pump();
    expect(find.byType(BrushWipeOverlay), findsNothing);
    expect(lastGate, isNull);

    // 2) 切到 playing：盖屏 + 返回门控。
    inGame = true;
    await tester.tap(find.text('tick'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(BrushWipeOverlay), findsOneWidget);
    expect(lastGate, isNotNull);

    // 3) 揭开完成前门控不 resolve（实时游戏此刻引擎/计时还没开始）。
    var gateResolved = false;
    lastGate!.then((_) => gateResolved = true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(gateResolved, isFalse, reason: '刷子铺满阶段门控不应 resolve');
    expect(find.byType(BrushWipeOverlay), findsOneWidget);

    // 4) 等过渡播完：遮罩移除 + 门控 resolve。
    await _pumpUntilOverlayGone(tester);
    await tester.pump();
    expect(gateResolved, isTrue, reason: '揭开完成后门控应 resolve');

    // 5) 对局中快照刷新：不重播。
    await tester.tap(find.text('tick'));
    await tester.pump();
    expect(find.byType(BrushWipeOverlay), findsNothing);
    expect(lastGate, isNull);
  });

  testWidgets('playing → 准备态（再来一局）→ 重新武装，再次进入再播', (tester) async {
    final fx = GameEnterTransition()..markPrep();
    var inGame = true;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => fx.update(context, inGame),
                child: const Text('tick'),
              ),
            ),
          ),
        ),
      ),
    );

    // 已在对局（markPrep 后首次 update(true) 应正常盖屏）。
    await tester.tap(find.text('tick'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(BrushWipeOverlay), findsOneWidget);
    await _pumpUntilOverlayGone(tester);

    // RESET 回 lobby：不盖屏，重新武装。
    inGame = false;
    await tester.tap(find.text('tick'));
    await tester.pump();

    // 再进对局：再次盖屏。
    inGame = true;
    await tester.tap(find.text('tick'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(BrushWipeOverlay), findsOneWidget);
    await _pumpUntilOverlayGone(tester);
  });

  testWidgets('首次 update 即 playing（断线重连中途进入）→ 不盖屏', (tester) async {
    final fx = GameEnterTransition();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => fx.update(context, true),
                child: const Text('tick'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('tick'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(BrushWipeOverlay), findsNothing,
        reason: '准备链没有发生过（重连进对局）不应盖屏');
  });

  testWidgets('keepArmed：对局中等待重连（waiting）不重新武装', (tester) async {
    final fx = GameEnterTransition()..markPrep();
    var inGame = false;
    var waiting = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    fx.update(context, inGame, keepArmed: waiting),
                child: const Text('tick'),
              ),
            ),
          ),
        ),
      ),
    );

    // 先进对局（盖屏 + 播完）。
    inGame = true;
    await tester.tap(find.text('tick'));
    await tester.pump();
    await tester.pump();
    await _pumpUntilOverlayGone(tester);

    // 掉线进 waiting：离开对局但 keepArmed → 回到 playing 不重播。
    inGame = false;
    waiting = true;
    await tester.tap(find.text('tick'));
    await tester.pump();
    inGame = true;
    waiting = false;
    await tester.tap(find.text('tick'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(BrushWipeOverlay), findsNothing,
        reason: '对局中断线重连不重播');
  });
}
