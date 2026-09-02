// test/core/chess/p2p/chess_room_config_page_test.dart
//
// ChessRoomConfigPage 测试 —— 建房配置页。
//
// 覆盖：
//   · 默认选中 host=白/guest=黑
//   · 切到 host=黑/guest=白
//   · 切到随机
//   · 残局模式默认 first_moker=黑先 + 可切白先
//   · 标准开局模式 first_mover 始终 'w'（UI 不显示 chip）
//   · 点"创建房间" → onSubmit 回调收到正确 ChessRoomConfig
//   · 取消返回 → Navigator.pop(null)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/endgame/chess_endgame.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/chess_room_config_page.dart';

// chip 用 RichText 渲染（label + sublabel），find.textContaining 找不到
// 它的子 span。改用 byWidgetPredicate 匹配包含子串的任意文本。
Finder _chipContaining(String s) => find.byWidgetPredicate((w) {
      if (w is Text) return w.data?.contains(s) ?? false;
      if (w is RichText) {
        final span = w.text;
        if (span is TextSpan) return span.toPlainText().contains(s);
      }
      return false;
    });

Widget _host({
  ChessEndgameSnapshot? endgame,
  void Function(ChessRoomConfig)? onSubmit,
}) {
  return MaterialApp(
    home: ChessRoomConfigPage(
      alias: '小白',
      code: 'ABCD',
      endgame: endgame,
      relayUrl: 'http://fake',
      onSubmit: onSubmit ?? (cfg) {},
    ),
  );
}

void main() {
  testWidgets('默认：host=执白/guest=执黑 + 标准开局 first_mover=w', (tester) async {
    ChessRoomConfig? received;
    await tester.pumpWidget(_host(onSubmit: (cfg) => received = cfg));
    await tester.tap(find.text('创建房间'));
    await tester.pump();
    expect(received, isNotNull);
    expect(received!.hostColor, 'w');
    expect(received!.guestColor, 'b');
    expect(received!.firstMover, 'w'); // 标准开局棋规白先
  });

  testWidgets('切到 host=执黑/guest=执白 后提交', (tester) async {
    ChessRoomConfig? received;
    await tester.pumpWidget(_host(onSubmit: (cfg) => received = cfg));
    await tester.ensureVisible(_chipContaining("我执黑，他执白"));
    await tester.pump();
    await tester.tap(_chipContaining("我执黑，他执白"));
    await tester.pump();
    await tester.tap(find.text('创建房间'));
    await tester.pump();
    expect(received!.hostColor, 'b');
    expect(received!.guestColor, 'w');
  });

  testWidgets('切到"随机掷筛"：guestColor=null（服务端掷筛决定）', (tester) async {
    ChessRoomConfig? received;
    await tester.pumpWidget(_host(onSubmit: (cfg) => received = cfg));
    await tester.ensureVisible(_chipContaining("随机掷筛"));
    await tester.pump();
    await tester.tap(_chipContaining("随机掷筛"));
    await tester.pump();
    await tester.tap(find.text('创建房间'));
    await tester.pump();
    expect(received!.hostColor, 'random');
    expect(received!.guestColor, isNull);
  });

  testWidgets('残局模式：first_moker 默认黑先，可切白先', (tester) async {
    ChessRoomConfig? received;
    final endgame = ChessEndgameSnapshot(
      label: '测试残局',
      fen: '1r1bk2r/5ppp/3p3n/p1p1p3/4P1PP/2BP2P1/PP2B3/2KR2NR b k - 3 21',
    );
    await tester.pumpWidget(_host(endgame: endgame, onSubmit: (cfg) => received = cfg));

    // 默认黑先
    await tester.tap(find.text('创建房间'));
    await tester.pump();
    expect(received!.firstMover, 'b');

    // 切到白先
    received = null;
    await tester.tap(find.text('白先'));
    await tester.pump();
    await tester.tap(find.text('创建房间'));
    await tester.pump();
    expect(received!.firstMover, 'w');
  });

  testWidgets('标准开局模式：first_mover 始终 w，即使切 host=黑也不变', (tester) async {
    ChessRoomConfig? received;
    await tester.pumpWidget(_host(onSubmit: (cfg) => received = cfg));
    await tester.ensureVisible(_chipContaining("我执黑，他执白"));
    await tester.pump();
    await tester.tap(_chipContaining("我执黑，他执白"));
    await tester.pump();
    await tester.tap(find.text('创建房间'));
    await tester.pump();
    expect(received!.firstMover, 'w',
        reason: '标准开局棋规白先；first_mover 与 host_color 独立');
  });

  testWidgets('残局模式 UI 显示 first_moker 二选一 chip；标准开局不显示', (
    tester,
  ) async {
    // 标准开局：不显示 first_moker
    await tester.pumpWidget(_host());
    expect(find.text('黑先'), findsNothing);
    expect(find.text('白先'), findsNothing);

    // 残局模式：显示 first_moker 二选一
    final endgame = ChessEndgameSnapshot(
      label: '测试残局',
      fen: '8/8/8/4k3/8/8/4Q3/4K3 w - - 0 1',
    );
    await tester.pumpWidget(_host(endgame: endgame));
    expect(find.text('黑先'), findsOneWidget);
    expect(find.text('白先'), findsOneWidget);
  });

  testWidgets('AppBar 显示房间号 + 创建者', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.text('房间 ABCD'), findsOneWidget);
    expect(find.text('创建者：小白'), findsOneWidget);
  });
}
