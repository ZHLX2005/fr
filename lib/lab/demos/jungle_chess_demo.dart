// lib/lab/demos/jungle_chess_demo.dart
import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/jungle_chess/local/local_game_page.dart';
import '../../core/jungle_chess/lan/lan_lobby_page.dart';

class JungleChessDemo extends DemoPage {
  @override
  String get title => '斗兽棋';

  @override
  String get description => '本地+局域网双人斗兽棋';

  @override
  bool get preferFullScreen => true;

  @override
  DemoType get type => DemoType.game;

  @override
  Widget buildPage(BuildContext context) {
    return _JungleChessHome();
  }
}

class _JungleChessHome extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('斗兽棋')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('斗兽棋', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('经典双人对战棋类游戏', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LocalGamePage())),
              icon: const Icon(Icons.people),
              label: const Text('本地对战', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LanLobbyPage())),
              icon: const Icon(Icons.wifi),
              label: const Text('局域网对战', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

void registerJungleChessDemo() {
  demoRegistry.register(JungleChessDemo());
}
