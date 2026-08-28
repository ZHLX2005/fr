// lib/lab/demos/jungle_chess_lua/jungle_constants.dart
// 斗兽棋 Lua 版 — 常量

/// relay 服务端地址（与五子棋/围棋/俄罗斯方块等共用）。
const String kJungleLuaRelayUrl = 'http://47.110.80.47:8988';

/// 顶部回合提示条固定高度（避免文案字数变化撑动棋盘）。
const double kJungleLuaTurnBarHeight = 44.0;

/// 顶部/底部面板高度（用于两侧玩家面板的固定高度，避免出现/消失撑动棋盘）。
const double kJungleLuaPanelHeight = 58.0;

/// 历史走法最大保留数（防 context 膨胀）。
const int kJungleLuaMaxHistory = 600;

/// device_id 前缀（区分各游戏，防止跨游戏窜台）。
const String kJungleLuaDevicePrefix = 'jc-';
