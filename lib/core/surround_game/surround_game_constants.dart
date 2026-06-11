/// 围追堵截 (Quoridor) 游戏全局常量
///
/// 棋盘编码说明：
///   - cellId = x + y * 9（Swift DataModel.swift:78 id 计算方式）
///     其中 x=column(0-8), y=row(0-8), 0,0 为左上角
///   - wallGridId = (x*2+1) + (y*2+1)*17（DataModel.swift:86 的 wallId）
///     17×17 墙壁网格
///
/// 对齐参考：.claude/repo/Quoridor-ios/Quoridor/Classes/Models/

/// 墙壁方向
enum WallOrientation { horizontal, vertical }

/// 玩家当前回合的动作选择（UI 层用，引擎不强依赖）
enum TurnAction { move, placeWall }

/// 游戏状态
///
/// 注：Swift 拼写为 `Runing`（typo），新 Dart 代码改为正确的 `running`。
enum GameStatus { running, topWin, bottomWin, draw }

/// 格子状态（UI 渲染用，本轮暂不进入引擎核心数据）
enum CellState {
  empty,
  playerTop,
  playerBottom,
  validMove,
  invalidWall,
}

// ─── @Deprecated 旧枚举 — 仅用于 _legacy/ 编译过渡，下轮删除 ───

/// @deprecated 仅用于 _legacy/ 编译过渡，下轮删除。
@Deprecated('迁移到 CellState / WallOrientation')
enum Direction { up, down, left, right }

@Deprecated('旧版房间状态，下轮删除')
enum RoomState { waiting, countdown, playing, finished }

@Deprecated('旧版玩家编号，下轮删除')
enum PlayerId { host, client }

/// 围追堵截 (Quoridor) 游戏常量
class SurroundGameConstants {
  SurroundGameConstants._();

  // ─── 棋盘尺寸 ───
  /// 9×9 棋子网格
  static const int boardSize = 9;
  /// 81 个格子，cellId = 0..80
  static const int totalCells = 81;
  /// 17×17 墙壁网格（= boardSize * 2 - 1）
  static const int wallGridSize = 17;
  /// 289 个墙壁单元
  static const int totalWallCells = 289;
  /// 每人 10 块挡板
  static const int wallCountPerPlayer = 10;

  // ─── 起始位置（Swift GameModel.swift:163-164）───
  static const int topPlayerStart = 4;       // x=4, y=0
  static const int bottomPlayerStart = 76;   // x=4, y=8

  // ─── 胜负目标行 ───
  static const int topGoalRow = 8;
  static const int bottomGoalRow = 0;

  // ─── 保留：surround_game_service 仍在用 ───
  static const String kPathGameInfo = '/api/game/info';
  static const String kPathGameJoin = '/api/game/join';
  static const String kPathGameLeave = '/api/game/leave';
  static const String kPathGameSync = '/api/game/sync';
  static const String kPathGameInput = '/api/game/input';
  static const String kBroadcastGame = 'g';
  static const String kBroadcastRoom = 'r';
  static const String kBroadcastPlayers = 'p';
  static const String kGameType = 'surround';
  static const int kMaxPlayers = 2;

  // ─── @Deprecated 旧常量 — 仅用于 _legacy/ 编译过渡 ───

  @Deprecated('旧棋盘尺寸，下轮删除')
  static const int boardRows = 20;
  @Deprecated('旧棋盘尺寸，下轮删除')
  static const int boardCols = 15;
  @Deprecated('旧起始位置，下轮删除')
  static const int hostStartRow = 1;
  @Deprecated('旧起始位置，下轮删除')
  static const int hostStartCol = 1;
  @Deprecated('旧起始位置，下轮删除')
  static const int clientStartRow = 18;
  @Deprecated('旧起始位置，下轮删除')
  static const int clientStartCol = 13;
  @Deprecated('旧积分制，下轮删除')
  static const int winScore = 3;
  @Deprecated('旧倒计时，下轮删除')
  static const int countdownSeconds = 3;
  @Deprecated('旧超时，下轮删除')
  static const int clientTimeoutSeconds = 30;
}
