/// 游戏房间等待页面
///
/// 局域网对战创建/加入房间后的等待页面，在双方就绪后进入 [GamePage]。
///
/// 角色区分：
/// - **Host（主机）**：显示"开始游戏"按钮，仅当房间满员（2 人）时可点击
/// - **非 Host**：显示等待中和加载指示器，由 Host 控制开始时机
///
/// 开始流程：点击按钮 → [_startCountdown] → 跳转至 [GamePage]
/// （当前倒计时逻辑为占位，直接跳转，预留 [_countdown] 状态变量实现 3-2-1 动画）
///
/// 顶部返回按钮调用 [_service.leaveRoom()] 退出房间并返回大厅。
/// 底部显示玩家列表（Host 蓝色 + Client 红色），空位用灰色⭕表示。
import 'dart:async';
import 'package:flutter/material.dart';
import '../surround_game_service.dart';
import '../models/game_room.dart';
import 'game_page.dart';

/// 房间等待页面
///
/// Host 可见"开始游戏"按钮，非 Host 显示等待状态。
/// 点击开始后 3-2-1 倒计时，然后进入游戏棋盘。
class GameRoomPage extends StatefulWidget {
  final GameRoom room;
  final bool isHost;

  const GameRoomPage({
    super.key,
    required this.room,
    required this.isHost,
  });

  @override
  State<GameRoomPage> createState() => _GameRoomPageState();
}

class _GameRoomPageState extends State<GameRoomPage> {
  final _service = surroundGameService;
  int? _countdown;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _startGame();
  }

  void _startGame() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const GamePage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.room.roomId),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _service.leaveRoom();
            Navigator.pop(context);
          },
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_esports, size: 80,
              color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text('房间: ${widget.room.roomId}',
              style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('${widget.room.playerCount} / ${widget.room.maxPlayers} 位玩家',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.outline)),
            const SizedBox(height: 24),
            _buildPlayerList(theme),
            const SizedBox(height: 24),
            Text(widget.isHost ? '你是主机' : '等待中...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline)),
            const SizedBox(height: 16),

            if (_countdown != null)
              Text('$_countdown',
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ))
            else if (widget.isHost) ...[
              if (widget.room.playerCount < 2)
                Column(
                  children: [
                    Text('等待玩家加入...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline)),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('开始游戏'),
                    ),
                  ],
                )
              else
                FilledButton.icon(
                  onPressed: _startCountdown,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始游戏'),
                ),
            ]
            else
              const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }

  /// 玩家名列表（Host + Client）
  Widget _buildPlayerList(ThemeData theme) {
    final players = <(Color, String, String)>[
      (
        Colors.blue.shade700,
        '🟦',
        widget.room.hostName.isEmpty ? '主机' : widget.room.hostName,
      ),
    ];
    if (widget.room.clientName != null && widget.room.clientName!.isNotEmpty) {
      players.add((
        Colors.red.shade700,
        '🟥',
        widget.room.clientName!,
      ));
    } else {
      players.add((
        Colors.grey.shade400,
        '⭕',
        '等待玩家加入...',
      ));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: players.map((p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(p.$2, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(
              p.$3,
              style: TextStyle(
                fontSize: 16,
                fontWeight: p.$3 == '等待玩家加入...'
                    ? FontWeight.normal
                    : FontWeight.bold,
                color: p.$1,
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }
}
