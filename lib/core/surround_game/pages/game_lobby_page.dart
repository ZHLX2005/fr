/// 游戏大厅页面
///
/// 围追堵截的入口页面，提供两种游戏模式入口：
///
/// 1. **本地对战** — 单机双人轮流操作，直接跳转至 [GamePage]
/// 2. **局域网对战** — 基于 [SurroundGameService] + [LocalNetService] 的
///    UDP 广播发现机制，创建或加入局域网房间
///
/// 布局结构：
/// - 顶部 AppBar（标题 + 刷新/创建房间按钮）
/// - 本机状态栏（玩家名称 + 在线/离线指示器）
/// - 本地对战按钮（[FilledButton.icon]）
/// - 分隔线
/// - 房间列表（[StreamBuilder] 监听 [roomsStream]，空时显示引导提示）
///
/// 房间列表通过 [RoomListTile] 渲染每项，已满房间的加入按钮置灰。
/// 创建房间后自动导航至游戏页。
import 'package:flutter/material.dart';
import '../surround_game_service.dart';
import '../../localnet/localnet_service.dart' show localnetService;
import '../models/game_room.dart';
import '../widgets/room_list_tile.dart';
import 'game_page.dart';

/// 游戏大厅页面 — 房间列表 + 本地对战入口
class GameLobbyPage extends StatefulWidget {
  const GameLobbyPage({super.key});

  @override
  State<GameLobbyPage> createState() => _GameLobbyPageState();
}

class _GameLobbyPageState extends State<GameLobbyPage> {
  final _service = surroundGameService;
  bool _isNetworkReady = false;
  String _networkStatus = '启动中...';

  @override
  void initState() {
    super.initState();
    _startLocalNet();
  }

  Future<void> _startLocalNet() async {
    setState(() => _networkStatus = '启动中...');
    if (!localnetService.isInitialized) {
      await localnetService.init();
    }
    if (localnetService.serviceState != 'RUNNING') {
      await localnetService.start();
    }
    setState(() {
      _isNetworkReady = localnetService.serviceState == 'RUNNING';
      _networkStatus = _isNetworkReady ? '在线' : '离线';
    });
  }

  Future<void> _refresh() async {
    setState(() => _networkStatus = '刷新中...');
    // 确保 LocalNet 各组件已启动（已运行则跳过）
    if (localnetService.serviceState != 'RUNNING') {
      await localnetService.start();
    } else {
      // 强制重启 UDP 组件以触发新的发现
      localnetService.stopUdpListener();
      await localnetService.startUdpListener();
      localnetService.startUdpBroadcast();
    }
    setState(() {
      _isNetworkReady = localnetService.serviceState == 'RUNNING';
      _networkStatus = _isNetworkReady ? '在线' : '离线';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('围追堵截'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '创建房间',
            onPressed: _createRoom,
          ),
        ],
      ),
      body: Column(
        children: [
          // 本机状态
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Row(
              children: [
                Icon(Icons.person, color: theme.colorScheme.primary, size: 32),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_service.myName,
                      style: theme.textTheme.titleMedium),
                    Row(
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isNetworkReady ? Colors.green : Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(_networkStatus,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _isNetworkReady ? Colors.green : Colors.orange)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 本地对战
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _startLocalGame,
                icon: const Icon(Icons.people),
                label: const Text('本地对战'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          // 房间列表
          Expanded(child: _buildRoomList(theme)),
        ],
      ),
    );
  }

  Widget _buildRoomList(ThemeData theme) {
    return StreamBuilder<List<GameRoom>>(
      stream: _service.roomsStream,
      initialData: _service.rooms,
      builder: (context, snapshot) {
        final rooms = snapshot.data ?? [];

        if (rooms.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_find, size: 64,
                  color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                Text('暂无可用房间',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.outline)),
                const SizedBox(height: 8),
                Text('点击右上角 + 创建房间',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: rooms.length,
          itemBuilder: (context, index) {
            final room = rooms[index];
            return RoomListTile(
              room: room,
              onJoin: () => _joinRoom(room),
            );
          },
        );
      },
    );
  }

  void _createRoom() {
    // 传入本机 IP（已通过 init 注入 _myIp）
    final room = _service.createRoom(
      roomName: '${_service.myName}的游戏',
      hostIp: _service.myIp,
    );
    _navigateToRoom(room, isHost: true);
  }

  void _startLocalGame() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const GamePage(),
      ),
    );
  }

  void _joinRoom(GameRoom room) {
    if (_service.joinRoom(room)) {
      _navigateToRoom(room, isHost: false);
    }
  }

  void _navigateToRoom(GameRoom room, {required bool isHost}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const GamePage(),
      ),
    );
  }
}
