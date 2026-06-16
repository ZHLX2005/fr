/// 房间列表项 Widget
///
/// 在游戏大厅中展示一个可加入的局域网房间。
/// 使用 Card + ListTile 布局，显示房间名称、Host 名称、
/// 人数状态（1/2），并提供"加入"按钮。
///
/// 当房间已满（玩家数 == 2）时，加入按钮置灰禁用。
import 'package:flutter/material.dart';
import '../../models/game_room.dart';

/// 房间列表项 Widget
class RoomListTile extends StatelessWidget {
  final GameRoom room;
  final VoidCallback onJoin;

  const RoomListTile({
    super.key,
    required this.room,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.sports_esports,
            color: theme.colorScheme.primary,
          ),
        ),
        title: Text(
          room.roomId,
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Text(
          '玩家: ${room.playerCount}/${room.maxPlayers} · ${room.state.name}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: FilledButton.tonal(
          onPressed: room.isFull ? null : onJoin,
          child: const Text('加入'),
        ),
      ),
    );
  }
}
