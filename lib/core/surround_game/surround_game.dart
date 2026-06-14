/// 围追堵截（Quoridor 变体）游戏模块入口 - Barrel 文件
///
/// 统一导出模块内所有公开 API，外部引用只需 `import` 此文件：
///
/// 子模块分类：
/// - 常量与主题：[surround_game_constants]
/// - 主题令牌：[board_theme]（[BoardThemeData] / [BoardTheme]）
/// - 状态管理：[game_ui_state]（GameController + GameUiState）
/// - 游戏引擎：[engine/game_engine]、[engine/bfs_pathfinder]
/// - 数据模型：[models/game_event]、[models/game_state]、[models/game_room]、[models/player_input]
/// - 网络服务：[surround_game_service]（UDP 局域网对战）
/// - 页面：[pages/game_page]、[pages/game_lobby_page]、[pages/game_room_page]
/// - Widget：[widgets/chess_board]、[widgets/chess_player]、[widgets/chess_wall] 等
///
/// 注意：_legacy/ 内的旧文件不再导出（引擎重写阶段遗留）。
export 'surround_game_constants.dart';
export 'models/game_event.dart';
export 'models/game_room.dart';
export 'models/game_state.dart';
export 'models/player_input.dart';
export 'surround_game_service.dart';
export 'engine/bfs_pathfinder.dart';
export 'engine/game_engine.dart';
export 'pages/game_lobby_page.dart';
export 'pages/game_room_page.dart';
export 'widgets/room_list_tile.dart';
export 'board_theme.dart';
export 'game_ui_state.dart';
export 'pages/game_page.dart';
export 'widgets/chess_board.dart';
export 'widgets/chess_player.dart';
export 'widgets/chess_wall.dart';
export 'widgets/player_prompt.dart';
export 'widgets/wall_prompt.dart';
export 'widgets/touch_view.dart';
export 'widgets/player_panel.dart';
export 'replay/replay_controller.dart';
export 'pages/replay_page.dart';
