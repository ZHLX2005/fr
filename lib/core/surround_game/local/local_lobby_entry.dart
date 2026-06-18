// lib/core/surround_game/local/local_lobby_entry.dart
//
// 单机热座模式导航入口。
// 通过 Navigator.push 跳转到 LocalGamePage，不依赖 go_router。
import 'package:flutter/material.dart';
import 'local_game_page.dart';

/// 导航到本地热座游戏页面
void navigateToLocalGame(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const LocalGamePage()),
  );
}
