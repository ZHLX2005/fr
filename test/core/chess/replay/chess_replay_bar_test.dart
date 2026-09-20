// test/core/chess/replay/chess_replay_bar_test.dart
//
// ChessReplayBar 保存整局按钮：显隐（onSaveGame null = 隐藏）+ 回调透传。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_replay_bar.dart';

Widget _host({VoidCallback? onSaveGame, VoidCallback? onExport}) =>
    MaterialApp(
      home: Scaffold(
        body: ChessReplayBar(
          index: 2,
          total: 4,
          playing: false,
          onToStart: () {},
          onStepBack: () {},
          onTogglePlay: () {},
          onStepForward: () {},
          onToEnd: () {},
          onSeek: (_) {},
          onExit: () {},
          onExport: onExport,
          onSaveGame: onSaveGame,
        ),
      ),
    );

void main() {
  testWidgets('onSaveGame 非 null → 显示保存按钮并透传点击', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host(onSaveGame: () => calls++));

    final button = find.byTooltip('保存整局到对局库');
    expect(button, findsOneWidget);
    await tester.tap(button);
    expect(calls, 1);
  });

  testWidgets('onSaveGame null → 不显示保存按钮（向后兼容）', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.byTooltip('保存整局到对局库'), findsNothing);
  });

  testWidgets('onExport null 时保存按钮仍独立可见（互不依赖）', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host(onSaveGame: () => calls++));
    expect(find.byTooltip('导出残局快照'), findsNothing);
    expect(find.byTooltip('保存整局到对局库'), findsOneWidget);
  });
}
