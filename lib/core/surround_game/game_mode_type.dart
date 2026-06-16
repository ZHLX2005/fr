// lib/core/surround_game/game_mode_type.dart
//
// 游戏模式类型 — 用于工厂注册和运行时切换。
//
// 与 widgets/touch_controller.dart 的 GameMode（move/placeWall，操作模式）不同：
// GameModeType 是"对局模式"（local/lanHost/lanClient），决定整个 UI 子树和行为。

/// 对局模式类型
enum GameModeType { local, lanHost, lanClient }
