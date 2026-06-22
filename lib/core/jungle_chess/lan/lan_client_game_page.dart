// lib/core/jungle_chess/lan/lan_client_game_page.dart
import 'package:flutter/material.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import 'lan_match_state.dart';
import 'lan_client_view_model.dart';

class LanClientGamePage extends StatefulWidget {
  final LanClientViewModel viewModel;
  const LanClientGamePage({super.key, required this.viewModel});

  @override
  State<LanClientGamePage> createState() => _LanClientGamePageState();
}

class _LanClientGamePageState extends State<LanClientGamePage> {
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('斗兽棋 - 客户端')),
      body: ValueListenableBuilder<LanClientState>(
        valueListenable: widget.viewModel,
        builder: (context, state, _) {
          return switch (state) {
            ClientIdle() => const Center(child: Text('已断开连接')),
            ClientJoining() => const Center(child: CircularProgressIndicator()),
            ClientWaiting() => const Center(child: Text('等待主机开始游戏...')),
            ClientCountdown(:final secondsLeft) => Center(
              child: Text('游戏即将开始: $secondsLeft', style: const TextStyle(fontSize: 48)),
            ),
            ClientInGame(:final gameState) => _buildGame(gameState),
            ClientFinished(:final gameState) => _buildFinished(gameState),
            ClientDisconnected(:final message) => Center(child: Text('断开: $message')),
          };
        },
      ),
    );
  }

  Widget _buildGame(GameState gameState) {
    return Center(
      child: Text('客户端游戏界面 - 等待主机走子\n当前回合: ${gameState.currentTurn == PlayerColor.blue ? "蓝" : "红"}方'),
    );
  }

  Widget _buildFinished(GameState gameState) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('游戏结束: ${gameState.winner == null ? "平局" : "${gameState.winner == PlayerColor.blue ? "蓝" : "红"}方获胜"}'),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('退出')),
        ],
      ),
    );
  }
}
