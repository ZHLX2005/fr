import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/surround_game/surround_game.dart';

/// 围追堵截游戏 Demo
class SurroundGameDemo extends DemoPage {
  @override
  String get title => '围追堵截';

  @override
  String get description => '局域网联机游戏';

  @override
  bool get preferFullScreen => true;

  @override
  DemoType get type => DemoType.game;

  @override
  Widget buildPage(BuildContext context) {
    return const LobbyPage();
  }
}

void registerSurroundGameDemo() {
  demoRegistry.register(SurroundGameDemo());
}
