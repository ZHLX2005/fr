import '../surround_game_constants.dart';

/// 棋谱栈记录（Swift DataModel）
///
/// 同时表示「棋子移动」和「墙壁放置」。
/// history 中按时间顺序存储每次操作。
///
/// Swift 参考：DataModel.swift（id, x, y, h, t 字段）
///   t=false → 棋子，t=true → 墙壁
///   h=棋盘 → 上方/横向，h=false → 下方/竖向
class MoveRecord {
  /// 墙壁格点坐标 x (0-8)，或走棋后 cellId % 9
  final int x;

  /// 墙壁格点坐标 y (0-8)，或走棋后 cellId ~/ 9
  final int y;

  /// true=放墙, false=走棋
  final bool isWall;

  /// 仅 isWall=true 时有值，方向（横向/竖向）
  final WallOrientation? orientation;

  /// 哪方的操作
  final bool isTopPlayer;

  const MoveRecord({
    required this.x,
    required this.y,
    required this.isWall,
    required this.isTopPlayer,
    this.orientation,
  });

  /// 走棋记录工厂
  factory MoveRecord.move({
    required int cellId,
    required bool isTopPlayer,
  }) =>
      MoveRecord(
        x: cellId % 9,
        y: cellId ~/ 9,
        isWall: false,
        isTopPlayer: isTopPlayer,
      );

  /// 放墙记录工厂
  factory MoveRecord.wall({
    required int x,
    required int y,
    required WallOrientation orientation,
    required bool isTopPlayer,
  }) =>
      MoveRecord(
        x: x,
        y: y,
        isWall: true,
        orientation: orientation,
        isTopPlayer: isTopPlayer,
      );

  /// 序列化为 Map
  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'isWall': isWall,
        'orientation': orientation?.name,
        'isTopPlayer': isTopPlayer,
      };

  /// 反序列化
  factory MoveRecord.fromJson(Map<String, dynamic> json) => MoveRecord(
        x: json['x'] as int,
        y: json['y'] as int,
        isWall: json['isWall'] as bool,
        orientation: json['orientation'] != null
            ? WallOrientation.values.firstWhere(
                (e) => e.name == json['orientation'],
              )
            : null,
        isTopPlayer: json['isTopPlayer'] as bool,
      );

  @override
  String toString() =>
      'MoveRecord(${isTopPlayer ? "top" : "bottom"} ${isWall ? "wall" : "piece"} ($x,$y)${isWall ? " $orientation" : ""})';
}

/// Quoridor 游戏状态 — 不可变值对象
///
/// 内部容器按约定不可变：
///   - 引擎所有 mutator 都返回 copyWith 后的新 GameState
///   - 不暴露能修改容器的接口（adjacency/wallGrid 等直接暴露但约定只读）
///   - 测试和业务代码不要直接 .add() 或 [idx] = x
///
/// 所有构造逻辑（initialize、fromBoardSpec、邻接表构建）集中在
/// QuoridorEngine，避免 model 反向依赖 engine。
///
/// Swift 参考：
///   DataModel.swift — id, x, y, h, t 编码
///   GameModel.swift:142 — gameNears（adjacency 对应）
///   GameModel.swift:145 — gameWalls（wallGrid 对应）
///   GameModel.swift:113 — gameStack（history 对应）
class GameState {
  /// 81 个格子的邻接表（Swift gameNears）
  /// adjacency[i] = 与 i 直接相通的 cellId 集合（不可变约定）
  final List<Set<int>> adjacency;

  /// 289 个墙壁单元的占用标志（Swift gameWalls）
  /// wallGrid[id] = true 表示该墙壁格被占用，id=wallBaseId(x,y)+偏移
  final List<bool> wallGrid;

  /// 上方棋子位置 cellId（x + y*9, 0..80）
  final int topPlayerId;

  /// 下方棋子位置 cellId
  final int bottomPlayerId;

  /// true=当前轮到上方玩家操作, false=轮到下方玩家
  final bool currentPlayerIsTop;

  /// 上方已放置的墙壁数（≤ wallCountPerPlayer）
  final int topWallsPlaced;

  /// 下方已放置的墙壁数
  final int bottomWallsPlaced;

  /// 棋谱栈（Swift gameStack）
  /// 按时间顺序记录每次走棋/放墙操作。本轮仅追加、不实现 undo（悔棋）。
  /// toJson 序列化它，为下轮 LAN 同步预留。
  final List<MoveRecord> history;

  /// 游戏状态
  final GameStatus status;

  /// 当前玩家可走到的格子集合（含跳跃规则）
  /// 在 switchTurn 时由引擎重算并缓存，避免 UI 每帧重算
  final Set<int> validMoves;

  const GameState({
    required this.adjacency,
    required this.wallGrid,
    required this.topPlayerId,
    required this.bottomPlayerId,
    required this.currentPlayerIsTop,
    required this.topWallsPlaced,
    required this.bottomWallsPlaced,
    required this.history,
    required this.status,
    required this.validMoves,
  });

  /// 创建新 GameState，成功拷贝传入参数
  GameState copyWith({
    List<Set<int>>? adjacency,
    List<bool>? wallGrid,
    int? topPlayerId,
    int? bottomPlayerId,
    bool? currentPlayerIsTop,
    int? topWallsPlaced,
    int? bottomWallsPlaced,
    List<MoveRecord>? history,
    GameStatus? status,
    Set<int>? validMoves,
  }) =>
      GameState(
        adjacency: adjacency ?? this.adjacency,
        wallGrid: wallGrid ?? this.wallGrid,
        topPlayerId: topPlayerId ?? this.topPlayerId,
        bottomPlayerId: bottomPlayerId ?? this.bottomPlayerId,
        currentPlayerIsTop:
            currentPlayerIsTop ?? this.currentPlayerIsTop,
        topWallsPlaced: topWallsPlaced ?? this.topWallsPlaced,
        bottomWallsPlaced: bottomWallsPlaced ?? this.bottomWallsPlaced,
        history: history ?? this.history,
        status: status ?? this.status,
        validMoves: validMoves ?? this.validMoves,
      );

  /// 序列化为 JSON Map
  Map<String, dynamic> toJson() => {
        'topPlayerId': topPlayerId,
        'bottomPlayerId': bottomPlayerId,
        'currentPlayerIsTop': currentPlayerIsTop,
        'topWallsPlaced': topWallsPlaced,
        'bottomWallsPlaced': bottomWallsPlaced,
        'history': history.map((m) => m.toJson()).toList(),
        'status': status.name,
        'validMoves': validMoves.toList(),
        // 注意：adjacency 和 wallGrid 不序列化。反序列化后由调用方
        // 调用 QuoridorEngine.replayHistory(history) 重建（见 fromJson 注释）。
        // validMoves 序列化作为 hints；权威值由 replayHistory 重算。
      };

  /// 反序列化
  ///
  /// **调用方须知（方案 A，保持 model 不依赖 engine）**：
  /// 反序列化后 adjacency/wallGrid 为空、validMoves 仅为 hint。
  /// 需要完整可玩状态时，由调用方显式调用：
  ///   `QuoridorEngine.replayHistory(state.history)`
  /// 重建 adjacency/wallGrid/validMoves/status。replayHistory 已在引擎层就绪。
  factory GameState.fromJson(Map<String, dynamic> json) => GameState(
        topPlayerId: json['topPlayerId'] as int,
        bottomPlayerId: json['bottomPlayerId'] as int,
        currentPlayerIsTop: json['currentPlayerIsTop'] as bool,
        topWallsPlaced: json['topWallsPlaced'] as int? ?? 0,
        bottomWallsPlaced: json['bottomWallsPlaced'] as int? ?? 0,
        history: (json['history'] as List?)
                ?.map(
                    (m) => MoveRecord.fromJson(m as Map<String, dynamic>))
                .toList() ??
            [],
        status: GameStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => GameStatus.running,
        ),
        validMoves: (json['validMoves'] as List?)
                ?.map((e) => e as int)
                .toSet() ??
            {},
        adjacency: List.generate(81, (_) => <int>{}),
        wallGrid: List.filled(289, false),
      );
}
