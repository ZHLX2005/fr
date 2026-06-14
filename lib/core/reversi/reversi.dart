// Core reversi module - 黑白翻转棋（Othello / Reversi）
//
// 方案 b（planb）模块化：完整游戏逻辑与 UI 集中在 core/reversi，
// lab/demos/reversi_demo.dart 通过 buildPage 导入 ReversiPage。

export 'reversi_constants.dart';
export 'board_theme.dart';
export 'models/reversi_board.dart';
export 'providers/reversi_state.dart';
export 'providers/reversi_notifier.dart';
export 'pages/reversi_page.dart';
