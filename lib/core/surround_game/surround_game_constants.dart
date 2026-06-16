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

/// 游戏状态
///
/// 注：Swift 拼写为 `Runing`（typo），新 Dart 代码改为正确的 `running`。
enum GameStatus { running, topWin, bottomWin, draw }

/// 围追堵截 (Quoridor) 游戏常量
class SurroundGameConstants {
  SurroundGameConstants._();

  /// 289 个墙壁单元（= 17 * 17）
  static const int totalWallCells = 289;

  /// 每人 10 块挡板
  static const int wallCountPerPlayer = 10;

  // ─── 起始位置（Swift GameModel.swift:163-164）───
  static const int topPlayerStart = 4;       // x=4, y=0
  static const int bottomPlayerStart = 76;   // x=4, y=8
}
