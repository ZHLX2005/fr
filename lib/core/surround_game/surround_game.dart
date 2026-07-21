// 围追堵截（Quoridor 变体）游戏模块入口 - Barrel 文件
//
// 统一导出模块内所有公开 API，外部引用只需 `import` 此文件。

// 常量与主题
export 'surround_game_constants.dart';
export 'board_theme.dart';

// 游戏引擎
export 'engine/bfs_pathfinder.dart';
export 'engine/game_engine.dart';

// 数据模型
export 'models/game_event.dart';
export 'lan/game_room.dart';
export 'models/game_state.dart';

// 游戏模式类型与工厂
export 'mode_factory.dart';

// 触摸交互
export 'widgets/touch_controller.dart';

// 共享 Widget
export 'widgets/chess_board.dart';
export 'widgets/chess_player.dart';
export 'widgets/chess_wall.dart';
export 'widgets/player_prompt.dart';
export 'widgets/wall_prompt.dart';
export 'widgets/touch_view.dart';
export 'widgets/player_panel.dart';
export 'widgets/confirm_actions.dart';

// 回放
export 'replay/replay_controller.dart';
export 'replay/replay_page.dart';

// 单机热座
export 'local/local_game_page.dart';

// 局域网
export 'lan/lan_lobby_page.dart';
export 'lan/lan_room_page.dart';
export 'lan/lan_host_game_page.dart';
export 'lan/lan_client_game_page.dart';
export 'lan/widgets/lan_board_stack.dart';
export 'lan/widgets/touch_controller_factory.dart';
export 'lan/relay_lobby_page.dart';

// 共享入口（local + lan 的模式选择页）
export 'lobby/lobby_page.dart';
