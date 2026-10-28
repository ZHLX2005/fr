// game/lobby —— 联机准备区（房间码 + 玩家就绪 + 开始 CTA）。
//
// 三个 lua 联机游戏（go / gomoku / surround_game）的 _buildLobby() 逐字相同，
// 差异只有 Room 类名（players/readyMap 的来源）—— 共 130 行 × 3 份。
// 底部 CTA 由**服务端动作权限**驱动（DEAL / ACK），故对所有联机游戏通用，
// 归位到这里后「准备区」只有一处真相。
//
// 依赖方向：ui/game/ready_room → ui/global/*（共享件）。

import 'package:flutter/material.dart';

import '../ready/main.dart';

/// 联机准备区：房间码、玩家就绪列表、开局/准备 CTA。
class GameLobbyBody extends StatelessWidget {
  const GameLobbyBody({
    super.key,
    required this.roomCode,
    required this.players,
    required this.readyMap,
    required this.myId,
    required this.bothReady,
    required this.iAmReady,
    required this.canDeal,
    required this.canAck,
    required this.onDeal,
    required this.onAck,
  });

  /// 房间码（未建房时显示占位）。
  final String roomCode;

  /// 玩家表：device_id → 玩家标识。
  final Map<String, String> players;

  /// 准备状态：device_id → 是否已 ACK。
  final Map<String, bool> readyMap;

  /// 本机 device_id。
  final String myId;

  /// 是否双方都已就绪（snapshot.state == 'ready'）。
  final bool bothReady;

  /// 本机是否已就绪（含本地已 ACK 但服务端尚未回传的乐观态）。
  final bool iAmReady;

  /// 是否有权开局（服务端 action_permissions 的 DEAL）。
  final bool canDeal;

  /// 是否有权准备（服务端 action_permissions 的 ACK）。
  final bool canAck;

  /// 开局回调。
  final VoidCallback onDeal;

  /// 准备（ACK）回调。
  final VoidCallback onAck;

@override
Widget build(BuildContext context) {
  final title = bothReady ? '双方已就绪' : '等待对手';
  final scheme = Theme.of(context).colorScheme;

  return Scaffold(
    backgroundColor: scheme.surfaceContainerLowest,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: GameReadyFloatCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    )),
                const SizedBox(height: 8),
                const GameReadyTitleRule(),
                const SizedBox(height: 16),
                GameReadyRoomCodeChip(code: roomCode),
                const SizedBox(height: 20),

                // 玩家头像列表（圆环 + ACK 状态）
                ...players.entries.map((e) {
                  final isMe = e.key == myId;
                  final isReady = readyMap[e.key] == true;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      GameReadyAvatar(label: e.value, isReady: isReady),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          '${e.value}${isMe ? "  (我)" : ""}',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 15,
                            fontWeight:
                                isMe ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                      GameReadyStatusBadge(isReady: isReady),
                    ]),
                  );
                }),

                if (players.length < 2) ...[
                  const SizedBox(height: 16),
                  Text(
                    '把房间号发给朋友',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],

                if (players.length >= 2) ...[
                  const SizedBox(height: 22),
                  if (bothReady)
                    canDeal
                        ? FilledButton(
                            onPressed: onDeal,
                            style: GameReadyCtaStyle.filled(scheme),
                            child: const Text(
                              '开始游戏 ▸',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                            ),
                          )
                        : Text(
                            '等待房主开始…',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
                              letterSpacing: 1,
                            ),
                          )
                  else if (iAmReady)
                    FilledButton(
                      onPressed: null,
                      style: GameReadyCtaStyle.filled(scheme),
                      child: const Text(
                        '已准备 ✓',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                    )
                  else
                    OutlinedButton(
                      onPressed: canAck ? onAck : null,
                      style: GameReadyCtaStyle.outlined(scheme),
                      child: const Text(
                        '准备好了',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
