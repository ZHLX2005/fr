// test/core/draughts/widgets/draughts_replay_bar_test.dart
//
// DraughtsReplayBar 无状态回放条的交互契约（对齐 ChessReplayBar 的语义）：
//   · 边界禁用：index == 0 禁 |< <；index == total 禁 > >|
//   · ▶/⏸ 图标随 playing 切换
//   · 步数标签 "$index / $total"（0 = 初始局面）
//   · 回调透传：onExit / onSeek

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/draughts/widgets/draughts_replay_bar.dart';

Widget _host({
  required int index,
  required int total,
  bool playing = false,
  VoidCallback? onExit,
  ValueChanged<int>? onSeek,
}) {
  return MaterialApp(
    home: Scaffold(
      body: DraughtsReplayBar(
        index: index,
        total: total,
        playing: playing,
        onToStart: () {},
        onStepBack: () {},
        onTogglePlay: () {},
        onStepForward: () {},
        onToEnd: () {},
        onSeek: onSeek ?? (_) {},
        onExit: onExit ?? () {},
      ),
    ),
  );
}

IconButton _buttonOf(WidgetTester tester, IconData icon) =>
    tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton)),
    );

void main() {
  group('DraughtsReplayBar 边界禁用', () {
    testWidgets('index == 0（初始局面）禁 |< 和 <，> 与 >| 可用', (tester) async {
      await tester.pumpWidget(_host(index: 0, total: 5));
      expect(_buttonOf(tester, Icons.first_page).onPressed, isNull);
      expect(_buttonOf(tester, Icons.chevron_left).onPressed, isNull);
      expect(_buttonOf(tester, Icons.chevron_right).onPressed, isNotNull);
      expect(_buttonOf(tester, Icons.last_page).onPressed, isNotNull);
    });

    testWidgets('index == total（终局）禁 > 和 >|，|< 与 < 可用', (tester) async {
      await tester.pumpWidget(_host(index: 5, total: 5));
      expect(_buttonOf(tester, Icons.first_page).onPressed, isNotNull);
      expect(_buttonOf(tester, Icons.chevron_left).onPressed, isNotNull);
      expect(_buttonOf(tester, Icons.chevron_right).onPressed, isNull);
      expect(_buttonOf(tester, Icons.last_page).onPressed, isNull);
    });

    testWidgets('中间步全部按钮可用', (tester) async {
      await tester.pumpWidget(_host(index: 2, total: 5));
      for (final icon in [
        Icons.first_page,
        Icons.chevron_left,
        Icons.chevron_right,
        Icons.last_page,
      ]) {
        expect(_buttonOf(tester, icon).onPressed, isNotNull, reason: '$icon');
      }
    });
  });

  group('DraughtsReplayBar 播放态与标签', () {
    testWidgets('playing=false 显示 ▶，playing=true 显示 ⏸', (tester) async {
      await tester.pumpWidget(_host(index: 2, total: 5));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsNothing);

      await tester.pumpWidget(_host(index: 2, total: 5, playing: true));
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets('步数标签 index / total，0 = 初始局面', (tester) async {
      await tester.pumpWidget(_host(index: 0, total: 5));
      expect(find.text('0 / 5'), findsOneWidget);

      await tester.pumpWidget(_host(index: 5, total: 5));
      expect(find.text('5 / 5'), findsOneWidget);
    });

    testWidgets('进度条存在且档位 = total', (tester) async {
      await tester.pumpWidget(_host(index: 2, total: 5));
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.max, 5);
      expect(slider.divisions, 5);
      expect(slider.value, 2);
    });

    testWidgets('点退出回调 onExit', (tester) async {
      var exited = false;
      await tester.pumpWidget(_host(index: 1, total: 5, onExit: () => exited = true));
      await tester.tap(find.text('退出回放'));
      expect(exited, isTrue);
    });
  });
}
