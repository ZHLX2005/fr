// lib/core/surround_game/lan/lan_lobby_page.dart
//
// 局域网模式"建房前"入口页 — 仅当用户在 lobby 选完"局域网对局"后进入。
//
// 提供：
// - 创建房间按钮 → 调度 HostCreateRoomPressed → 跳到 LanRoomPage
// - 房间列表占位（本轮 A 桩化：不扫描局域网）
//
// 此页是 LanHostViewModel 的持有者，因为它要管"建房"状态机。
// LanClient 流程不经过此页（客户端是从其他设备通过局域网发现的，本轮未实现）。

import 'package:flutter/material.dart';

import '../board_theme.dart';
import '../models/game_room.dart';
import 'lan_room_page.dart';
import 'lan_match_state.dart';
import 'lan_match_event.dart';
import 'lan_host_view_model.dart';

class LanLobbyPage extends StatefulWidget {
  const LanLobbyPage({super.key});

  @override
  State<LanLobbyPage> createState() => _LanLobbyPageState();
}

class _LanLobbyPageState extends State<LanLobbyPage> {
  late final LanHostViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = LanHostViewModel();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final boardTheme = BoardTheme.of(context);

    return Scaffold(
      backgroundColor: boardTheme.boardSurface,
      appBar: AppBar(
        title: const Text('局域网对局'),
        backgroundColor: boardTheme.panelBg,
        foregroundColor: boardTheme.btnText,
      ),
      body: Column(
        children: [
          // 本机状态（桩化：显示"离线"）
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Row(
              children: [
                Icon(Icons.person, size: 32, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('本机', style: theme.textTheme.titleMedium),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '本地模式（桩化）',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.orange),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 创建房间按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  _vm.dispatch(const HostCreateRoomPressed());
                  final state = _vm.value;
                  final roomId =
                      state is HostWaiting ? state.room.roomId : 'new';
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LanRoomPage(
                        roomId: roomId,
                        role: 'host',
                        initialRoom: state is HostWaiting
                            ? state.room
                            : GameRoom.placeholder(roomId: roomId),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('创建房间'),
                style: FilledButton.styleFrom(
                  backgroundColor: boardTheme.piecePlayerA,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const Divider(height: 1),

          // 房间列表占位（A 桩化）
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_find,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    '暂无可用房间',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '（本轮桩化：不扫描局域网）',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
