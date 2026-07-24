import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/surround_game/local/local_game_page.dart';

/// 围追堵截游戏 Demo
class SurroundGameDemo extends DemoPage {
  @override
  String get title => '围追堵截';

  @override
  String get slug => 'surround-game';

  @override
  String get description => '本地双人对战';

  @override
  bool get preferFullScreen => true;

  @override
  DemoType get type => DemoType.game;

  @override
  Widget buildPage(BuildContext context) {
    return const LocalGamePage();
  }
}

void registerSurroundGameDemo() {
  demoRegistry.register(SurroundGameDemo());
}
