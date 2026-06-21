// lib/core/jungle_chess/lan/lan_lobby_page.dart
import 'package:flutter/material.dart';
import 'service/lan_service_adapter.dart';
import 'lan_host_view_model.dart';
import 'lan_match_event.dart';
import 'lan_host_game_page.dart';

class LanLobbyPage extends StatefulWidget {
  const LanLobbyPage({super.key});

  @override
  State<LanLobbyPage> createState() => _LanLobbyPageState();
}

class _LanLobbyPageState extends State<LanLobbyPage> {
  final _aliasController = TextEditingController(text: 'Player');
  final _hostViewModel = LanHostViewModel();

  @override
  void dispose() {
    _aliasController.dispose();
    _hostViewModel.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    final alias = _aliasController.text.trim();
    if (alias.isEmpty) return;

    await JungleLanServiceAdapter.instance.start(myAlias: alias);
    final roomId = DateTime.now().millisecondsSinceEpoch.toString();
    _hostViewModel.dispatch(HostCreateRoom(roomId: roomId, hostName: alias));

    // 进入房间等待页（简化版：直接开始游戏）
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => LanHostGamePage(viewModel: _hostViewModel),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('斗兽棋 - 局域网')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _aliasController,
              decoration: const InputDecoration(labelText: '昵称'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _createRoom,
              icon: const Icon(Icons.add),
              label: const Text('创建房间'),
            ),
          ],
        ),
      ),
    );
  }
}
