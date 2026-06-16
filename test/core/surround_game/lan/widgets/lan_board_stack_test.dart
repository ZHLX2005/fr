// Temporary widget test for LanBoardStack: simulate page's isMyTurn logic.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/widgets/touch_view.dart';
import 'package:xiaodouzi_fr/core/surround_game/widgets/touch_controller.dart';
import 'package:xiaodouzi_fr/core/surround_game/widgets/chess_board.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/widgets/lan_board_stack.dart';

void main() {
  testWidgets('LanBoardStack mounts TouchView only when isMyTurn=true', (tester) async {
    final toc = TouchController();
    var pointerDownCount = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            bool isMyTurn = true;  // pretend
            return LanBoardStack(
              gameState: QuoridorEngine.initialize(),
              touchController: toc,
              theme: BoardThemeData.warm,
              cellSize: 30.0,
              flipY: true,
              isMyTurn: isMyTurn,
              onChanged: () => setState(() {}),
              onConfirm: () {},
              onCancel: () {},
              validateWall: (_, __, ___, ____) => true,
            );
          },
        ),
      ),
    ));

    // TouchView should be mounted
    expect(find.byType(TouchView), findsOneWidget);

    // Now rebuild without isMyTurn
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            bool isMyTurn = false;  // pretend
            return LanBoardStack(
              gameState: QuoridorEngine.initialize(),
              touchController: toc,
              theme: BoardThemeData.warm,
              cellSize: 30.0,
              flipY: true,
              isMyTurn: isMyTurn,
              onChanged: () => setState(() {}),
              onConfirm: () {},
              onCancel: () {},
              validateWall: (_, __, ___, ____) => true,
            );
          },
        ),
      ),
    ));

    // TouchView should be unmounted
    expect(find.byType(TouchView), findsNothing);
  });
}
