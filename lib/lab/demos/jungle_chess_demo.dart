// lib/lab/demos/jungle_chess_demo.dart
import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/jungle_chess/local/local_game_page.dart';

class JungleChessDemo extends DemoPage {
  @override
  String get title => '斗兽棋';

  @override
  String get slug => 'jungle-chess';

  @override
  String get description => '本地双人斗兽棋';

  @override
  bool get preferFullScreen => true;

  @override
  DemoType get type => DemoType.game;

  @override
  Widget buildPage(BuildContext context) {
    return const LocalGamePage();
  }
}

void registerJungleChessDemo() {
  demoRegistry.register(JungleChessDemo());
}
