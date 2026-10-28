// lib/lab/demos/surround_game_lua/constants.dart
// 围追堵截 Lua 版 — 常量 + 持久化


// ── 持久化 key ──

const String kSgRelayUrl = 'http://47.110.80.47:8988';

// ── 阶段枚举 ──

enum SgLobbyPhase { entering, waitingAck, waitingDeal, playing, ended }
