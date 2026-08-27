// lib/lab/demos/go_lua/go_constants.dart
// 联机围棋 — 常量 + 布局常量

/// relay 服务端地址（与 gomoku/reversi 等共用同一后端）。
const String kGoRelayUrl = 'http://47.110.80.47:8988';

/// 棋盘尺寸（9×9 交点）。规则算法与 19×19 一致。
const int kGoSize = 9;

/// 顶部回合提示条固定高度（避免文案字数变化撑动棋盘）。
const double kGoTurnBarHeight = 44.0;

/// 待确认按钮条预留高度（不待确认时也保留，棋盘区域高度恒定）。
const double kGoConfirmBarHeight = 56.0;
