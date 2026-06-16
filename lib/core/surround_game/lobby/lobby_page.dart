// lib/core/surround_game/lobby/lobby_page.dart
//
// 围追堵截（Quoridor）的统一入口页 — local 和 lan 共享。
//
// 提供两个入口：
// - 本地对战  → Navigator.push 到 LocalGamePage
// - 局域网对局 → Navigator.push 到 LanLobbyPage 之外的"局域网模式入口"（
//                本轮桩化为占位，下轮接 LanLobbyPage 或 LanRoomPage）
//
// 此页是 UI 层最外层的导航 dispatcher，不持有 ViewModel，不调任何 service。
// 状态机转移发生于用户点击按钮的瞬间，由 Navigator.push 接管。

import 'package:flutter/material.dart';

import '../board_theme.dart';
import '../local/local_game_page.dart';
import '../lan/lan_lobby_page.dart';

class LobbyPage extends StatelessWidget {
  const LobbyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final boardTheme = BoardTheme.of(context);

    return Scaffold(
      backgroundColor: boardTheme.boardSurface,
      appBar: AppBar(
        title: const Text('围追堵截'),
        backgroundColor: boardTheme.panelBg,
        foregroundColor: boardTheme.btnText,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            Text(
              '选择游戏模式',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '本地 = 同设备热座；局域网 = 两台设备对战',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 48),

            // 本地对战
            _ModeButton(
              icon: Icons.people,
              title: '本地对战',
              subtitle: '同设备双人轮流操作',
              color: boardTheme.piecePlayerA,
              theme: theme,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LocalGamePage()),
              ),
            ),
            const SizedBox(height: 16),

            // 局域网对局
            _ModeButton(
              icon: Icons.wifi,
              title: '局域网对局',
              subtitle: '两台设备通过 WiFi 对战',
              color: boardTheme.piecePlayerB,
              theme: theme,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LanLobbyPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.theme,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 32, color: Colors.white),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
        ],
      ),
    );
  }
}
