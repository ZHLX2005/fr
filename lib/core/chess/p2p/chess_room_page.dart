// lib/core/chess/p2p/chess_room_page.dart
//
// P2P 在线对弈页 —— 快照驱动的国际象棋房间（net_p2p v3 Relay + kChessScript）。
//
// 权威方：服务端 Lua 状态机。客户端只做"乐观渲染 + 服务端调和"：
//   · 本地走子 → 立即 applyMove 乐观推进 → 发 MOVE action → 等服务端 snapshot 调和
//   · snapshot.context['fen'] 永远作为棋盘真相源；收到新快照整体重建 BoardState
//
// 阵营判定：host = 白方（先手），guest = 黑方。
//   对比 transport.deviceId 与 context['host_id'] 得出本地棋子颜色。
//   注意：每次快照都重算（_myColor = _resolveMyColor(snap)），
//   避免重连 / 服务端改判后阵营锁定过期。
//
// 棋盘翻转：由"角色"驱动（_myColor == black），整局稳定 —— 与走子轮次解耦，
//   棋盘不会在对手走子时 180° 翻转（isMyTurn 仍由 sideToMove == _myColor 独立推导）。
//
// 本页拥有棋盘状态（Option A）—— 不复用 ChessController（它自带内部 BoardState），
// 直接渲染无状态 ChessBoard + 自己实现选中 / 合法目标 / 升变状态机。
//
// 回放（复盘）：终局后从服务端权威棋谱 context['moves'] 重演整局 ——
//   步进 / 自动播放 / 拖动进度条（ChessReplayBar）。回放中棋盘只读
//   （tap / 拖动 / 升变输入全部断开）；进入时一次性构建局面子序列缓存；
//   RESET 重开（快照离开 ended）→ 自动退出回放回实况。
//
// 颜色走 context.chessColors（v6.2.1 第 6 strategy 通道），不写死 Color(0xFF...)。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../widgets/context_chess_colors.dart';
import '../../game_audio/piece_sound.dart';
import '../../net_engine/relay_v3/relay_v3_transport.dart';
import '../../theme/colors/strategy/chess_color_strategy/chess_color_strategy.dart'
    show ChessColorStrategy;
import '../engine/chess_engine.dart';
import '../engine/fen_codec.dart';
import '../engine/make_move.dart';
import '../endgame/chess_endgame.dart';
import '../endgame/chess_endgame_store.dart';
import '../models/board_state.dart';
import '../models/game_status.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../skins/chess_skin.dart';
import '../skins/local_chess_skin.dart';
import '../widgets/board_palette.dart';
import '../widgets/chess_board.dart';
import '../widgets/chess_connection_status.dart';
import '../widgets/chess_replay_bar.dart';
import '../widgets/promotion_panel.dart';
import 'chess_net.dart';

/// 快照驱动的在线对弈房间页（v3 Relay + kChessScript）。
class ChessRoomPage extends StatefulWidget {
  /// 房间句柄（由外层创建：host createRoom(kChessScript) / guest joinRoom）。
  final RoomHandle handle;

  /// 返回回调（页面 pop 后由外层处理 handle.dispose 等）。
  final VoidCallback? onLeave;

  /// 引擎（注入方便测试）。
  final ChessEngine engine;

  /// 皮肤 id（默认 '1'）。
  final String skinId;

  /// 已本地化的皮肤（可选）。非 null → 优先用本地文件渲染（零网络 / 离线可用）；
  /// null → 回退 [ChessSkinBundle.byId]（RemoteChessSkin / unicode），向后兼容。
  final LocalChessSkin? localSkin;

  /// 自定义棋盘配色（可选）。null = 跟随主题（context.chessColors）；
  /// 非 null → 用户自定义覆盖主题（boardPalette?.X ?? 主题 X），向后兼容。
  final BoardPalette? boardPalette;

  /// 残局快照信息（可选；来自入口残局库选择）。用于：
  ///   · 回放起点（lineage 存在 → 从该局面起演，null 回退快照 initial_fen）
  ///   · 导出残局标题上下文（label）
  ///   · lobby/ready 卡片显示残局名 chip
  /// null = 标准开局房间（服务端 initial_fen 仍可能存在 —— 换设备进房兜底读快照）。
  final ChessEndgameSnapshot? initialEndgame;

  const ChessRoomPage({
    super.key,
    required this.handle,
    this.onLeave,
    this.engine = const ChessEngine(),
    this.skinId = '1',
    this.localSkin,
    this.boardPalette,
    this.initialEndgame,
  });

  @override
  State<ChessRoomPage> createState() => _ChessRoomPageState();
}

class _ChessRoomPageState extends State<ChessRoomPage> {
  StreamSubscription<Snapshot>? _snapSub;
  StreamSubscription<WSCloseEvent>? _closeSub;

  /// 最新服务端快照（null = 尚未收到）。
  Snapshot? _snapshot;

  /// 网络动作封装（懒初始化：拿到首份快照后建，拿到 host_id 后才有意义）。
  ChessRoom? _room;

  /// 本地棋盘（权威真相源 = 快照 fen；本地走子时乐观推进）。
  BoardState? _board;

  /// 本地棋子颜色（null = 尚未判定；host=白，guest=黑）。
  /// 每次快照都重算 —— 不缓存，避免重连 / 角色变更后阵营过期。
  PieceColor? _myColor;

  /// 本地是否为房主（host）—— 终局后"再来一局"按钮仅 host 可见。
  bool _isHost = false;

  /// 当前选中格（1D index）。
  int? _selectedSquare;

  /// 拖动状态（board-gesture-patterns）：正在拖动的格 + 手指位置 + 悬停格。
  /// 值来自 ChessBoard 顶层手势层回调并回传渲染（浮起棋子跟手）。
  int? _draggingSquare;
  Offset? _dragFingerPos;
  int? _dragHoverSquare;

  /// 上一步走法（from/to 高亮）。
  Move? _lastMove;

  /// 升变待决（兵到底线时暂停走法，等玩家选 Q/R/B/N）。
  ({int from, int to})? _pendingPromotion;

  /// 是否轮到本地走（由快照 sideToMove == _myColor 推出）。
  bool _myTurn = false;

  /// 服务端 status（"playing"/"check"/"checkmate"/"stalemate"/"resigned"/"draw"）。
  String _status = 'playing';

  /// 上一份快照的 state（用于检测 RESET：ended → playing 时清本地态）。
  String? _prevState;

  /// 发送锁 —— 本地 MOVE 已乐观应用但服务端尚未调和时，禁止再走。
  bool _sendLock = false;

  /// 是否已触发终局覆盖层（防重复）。
  bool _gameOverShown = false;

  /// 上一次应用到本地的 FEN（用于 [_applySnapshot] 检测"fen 是否变了"以触发落子音）。
  /// 初始 null 表示还没收到首份快照 → 不播音，避免页面首次进入就响。
  String? _prevFen;

  /// 本地刚乐观提交的 FEN —— [_applySnapshot] 收到匹配该值的快照视为自己走子的
  /// 服务端 echo（已在 [_commitMove] 里响过），不重复播放。
  String? _pendingLocalFen;

  // ─────────────────────────── READY 门 / 断连状态 ───────────────────────────
  //
  // v2 协议升级：
  //   · state 走到 lobby/ready 时，页面渲染准备卡片（"准备好了" / "开始游戏"）
  //   · 玩家离开（playing/ready 内）→ 服务端标 c.disconnected[id] = true，
  //     房间不销毁，等待重连；本页听 snapshot.context['disconnected'] 显示
  //     "对手掉线"提示 / 禁用本地输入。
  //   · WS 真正断开（on_leave 之前）→ 短暂 overlay "重连中…"，不退出页面。
  //
  // ── 5s grace 重连保护（UX 不变量）──
  //
  // 服务端 WS 关闭后 5s 内是"宽限期"：只要同 device_id 在宽限内重新连上，
  // 服务端 on_join 的"断线重连"分支会清掉 disconnected[id]，房间状态
  // （fen / moves / ready / disconnected）完全保留 —— 玩家视角是"画面
  // 冻结了一下然后继续"，不会丢任何进度。客户端依赖三条保证：
  //   1. 稳定身份：transport.deviceId = ChessIdentity.resolve()（登录 uid
  //      优先，设备 UUID 兜底），断线重连后被识别为同一玩家（不会占新坑）。
  //   2. 本页不退出：_wsOffline 只是 UI 态，棋盘数据不动；即便 on_leave
  //      被触发（>5s），重连快照 disconnected[me] 被清后 banner 也自动消失。
  //   3. RoomHandle 自动重连（指数退避 500ms→30s）+ 20s heartbeat
  //      兜底拉快照 —— 无论哪条路径先恢复，快照都会把 UI 拉回实况。

  /// lobby 阶段乐观 ACK：点了"准备好了"立即本地置位（按钮变"已准备 ✓"），
  /// 等服务端 ACK 回写快照后清掉（防双发）。
  bool _ackedLocally = false;

  /// 我方当前是否掉线（disconnected[myId] = true）。WS 重连拿到快照自动清。
  bool _isMeDisconnected = false;

  /// WS 断开过渡（closeEvents 0 → set true；快照回到 → 清）。
  /// 与 [RoomHandle] 自动重连配合：客户端不主动重连，仅 UI 提示。
  bool _wsOffline = false;

  /// 手动刷新 / 409 reconcile 时 fetchSnapshot 调用的 UI 反馈标记。
  /// true → 顶部显示 LinearProgressIndicator + 刷新按钮变 spinner。
  /// RoomHandle 内部的 20s heartbeat 不走这里（无 UI 反馈）。
  bool _fetching = false;

  /// lobby/ready 阶段房主点"开始游戏"发送锁（防双击）。
  bool _dealLock = false;

  // ─────────────────────────── 回放（复盘）状态 ───────────────────────────
  //
  // 终局后复盘整局：步进 / 自动播放 / 拖动进度条。回放中棋盘只读
  // （tap / 拖动 / 升变输入全部断开），局面从服务端权威棋谱
  // context['moves'] 重演（起始 = 初始局面；RESET 后 moves 即新一局
  // 棋谱 —— 每次进入回放都从最新快照解析，天然无上局残留）。

  /// 回放模式开关（true = 棋盘渲染回放局面 + 底部显示回放控制条）。
  bool _replayMode = false;

  /// 当前回放到第几步（0 = 初始局面，_replayMoves.length = 终局）。
  int _replayIndex = 0;

  /// 自动播放中（播放键显示 ⏸）。
  bool _replayPlaying = false;

  /// 自动播放定时器（每 [_kReplayTickInterval] 前进一步）。
  Timer? _replayTimer;

  /// 解析后的走法序列（含易位 / 吃过路兵正确 flag —— 由引擎合法走法匹配补全）。
  List<Move> _replayMoves = const [];

  /// 局面子序列缓存（states[0] = 初始局面，states[i] = 走完第 i 手）。
  /// 进入回放时一次性构建 → 步进 / 拖动进度条都是 O(1)。
  List<BoardState> _replayStates = const [];

  /// 自动播放步进间隔（毫秒）。
  static const Duration _kReplayTickInterval = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _room = ChessRoom(widget.handle);
    final snap = widget.handle.latest;
    if (snap != null) {
      _applySnapshot(snap);
    }
    // RoomHandle 构造时已自动 connect WS（createRoom / joinRoom 路径）。
    // 这里只需订阅 snapshot 流。
    _snapSub = widget.handle.snapshots.listen(_onSnapshot);
    // 监听 WS 关闭事件（断线 / 被踢 / 房间过期等）。
    _closeSub = widget.handle.closeEvents.listen(_onCloseEvent);
    // 预加载落子音，消除首次落子的加载延迟（PieceSound 单例跨页复用）
    PieceSound.instance.preload();
  }

  @override
  void dispose() {
    _snapSub?.cancel();
    _closeSub?.cancel();
    _replayTimer?.cancel(); // 回放定时器随页面销毁回收
    // 不给 handle.dispose() —— 页面退出时 handle 由外层拥有；
    // 用户按了断开按钮时外层处理 dispose。
    super.dispose();
  }

  // ─────────────────────────── 快照处理 ───────────────────────────

  void _onSnapshot(Snapshot snap) {
    if (!mounted) return;
    setState(() => _applySnapshot(snap));
  }

  /// 把服务端权威快照应用到本地状态（棋盘重建 + 阵营 + 轮次 + 状态）。
  void _applySnapshot(Snapshot snap) {
    _snapshot = snap;
    final state = snap.state;

    // ── 断连态同步（playing/ready 内）──
    // disconnected 字典含我 → 我掉线（断连等重连）；空 → 我回来了。
    final disc = ChessRoom.disconnectedPlayers(snap);
    final myId = widget.handle.transport.deviceId;
    _isMeDisconnected = disc[myId] == true;
    // 收到任意快照 = WS 已恢复（即便内容是同一份 disconnected 状态）。
    if (_wsOffline) {
      _wsOffline = false;
    }

    // ── lobby / ready：棋盘为空（初始 FEN），不解析棋盘 / 不走回合逻辑 ──
    if (state == 'lobby' || state == 'ready') {
      _board = null;
      _myTurn = false;
      _status = 'playing';
      _gameOverShown = false;
      _selectedSquare = null;
      _draggingSquare = null;
      _dragFingerPos = null;
      _dragHoverSquare = null;
      _pendingPromotion = null;
      _lastMove = null;
      _sendLock = false;
      // 清音效基线：RESET 回 lobby 后下一局首份 playing 快照不响（避免
      // 旧终局 FEN → 新局 FEN 的"假对手走子"音）。
      _prevFen = null;
      _pendingLocalFen = null;
      // 离开 lobby / ready 阶段 → 清掉本地乐观 ACK（被服务端 ACK 后已无意义）。
      if (_ackedLocally) {
        _ackedLocally = false;
      }
      // 阵营判定仍需（lobby 卡片显示"执白 / 执黑"标签）
      final myColor = _resolveMyColor(snap);
      _myColor = myColor;
      _isHost = _resolveIsHost(snap);
      _prevState = state;
      return;
    }

    // 1. 棋盘：context['fen'] 永远是最新真相源，整体重建。
    final rawFen = snap.context['fen'];
    if (rawFen is String && rawFen.isNotEmpty) {
      try {
        final board = FenCodec.fromFen(rawFen);
        _board = board;
        // 服务端调和：本地已选中的格子在权威局面下失效，清选（含拖动）。
        _selectedSquare = null;
        _pendingPromotion = null;
        _draggingSquare = null;
        _dragFingerPos = null;
        _dragHoverSquare = null;
      } on ArgumentError {
        // 畸形 FEN —— 保持上一份棋盘不动（防御）。
      }
    }

    // 1.5 上一步高亮：永远从服务端权威棋谱 moves 的最后一条派生 ——
    //    不缓存本地值。对手走子后快照重建，高亮跟到最新一手
    //    （旧版 _lastMove 只在本地走子时更新，对手回合时残留本方上一步 → 污染）。
    _lastMove = _latestMoveFrom(snap);

    // 2. 阵营：host 执 c.host_color，guest 执对侧（每次快照重算）。
    final myColor = _resolveMyColor(snap);
    _myColor = myColor;
    _isHost = _resolveIsHost(snap);

    // 3. 轮次：快照 sideToMove == 本地颜色 → 轮到我。
    final board = _board;
    if (board != null && myColor != null) {
      _myTurn = board.sideToMove == myColor;
    }

    // 4. 状态：context['status']（playing/check/...）。
    final rawStatus = snap.context['status'];
    if (rawStatus is String) {
      _status = rawStatus;
    }

    // 5. 终局覆盖层（ended → 只显示一次）。
    if (snap.state == 'ended') {
      if (!_gameOverShown) {
        _gameOverShown = true;
      }
    } else {
      _gameOverShown = false;
    }

    // 6. 服务端 RESET 后（ended → lobby）：清掉本局本地状态（发送锁）。
    //    上一步高亮由 [._latestMoveFrom] 从新棋谱派生（RESET 清空 moves → null）。
    if (_prevState == 'ended' && snap.state != 'ended') {
      _sendLock = false;
    }
    // 6.5 回放中收到非 ended 快照（host RESET 重开 / 状态回退）→
    //     自动退出回放回实况棋盘（复盘针对已结束的那一局，新对局优先）。
    if (_replayMode && snap.state != 'ended') {
      _clearReplay();
    }
    // 7. 落子音效（PieceSound 单例）：
    //   · 首份快照（_prevFen == null）→ 页面刚进，不响。
    //   · FEN 未变（同状态重推 / 走子后尚未到下一手）→ 不响。
    //   · FEN == _pendingLocalFen → 自己走子的服务端 echo（已在 _commitMove 响过）→ 不响。
    //   · 回放模式（_replayMode）→ 棋盘只读复盘，不响。
    //   · 其余 = 对手走子 → 响（双方都听到对弈节奏）。
    if (!_replayMode &&
        rawFen is String &&
        rawFen.isNotEmpty &&
        _prevFen != null &&
        rawFen != _prevFen &&
        rawFen != _pendingLocalFen) {
      PieceSound.instance.play();
    }
    if (rawFen is String && rawFen.isNotEmpty) {
      _prevFen = rawFen;
    }
    _pendingLocalFen = null; // 每次快照清一次（echo 已消费 / 其它情况丢弃）。
    _prevState = snap.state;
  }

  /// 从服务端权威棋谱 context['moves'] 取最后一手（from/to）→ 上一步高亮。
  ///
  /// moves 形如 `[{uci: "e2e4", by: ..., ts: ...}, ...]`，追加式唯一走法权威。
  /// 解析失败 / 空棋谱 → null（无高亮）。
  Move? _latestMoveFrom(Snapshot snap) {
    final raw = snap.context['moves'];
    if (raw is! List || raw.isEmpty) return null;
    final last = raw.last;
    if (last is! Map) return null;
    final uci = last['uci']?.toString();
    if (uci == null || uci.length < 4) return null;
    try {
      return Move.fromUci(uci);
    } on ArgumentError {
      return null; // 畸形 uci —— 防御：不高亮。
    }
  }

  /// 判定本地棋子颜色：host 执 c.host_color，guest 执对侧（棋规）。
  ///
  /// v5：host_color 与 first_moker (initial_side) 完全解耦。
  ///   · c.host_color   = host 执子色（用户决策；标准开局 / 残局都尊重）
  ///   · c.initial_side = FEN 第 2 字段（first_moker；棋规本身）
  ///   · host 是 first_moker 当且仅当 host_color == initial_side
  /// Bug 1 修复：之前 v4 把 host_color 与 initial_side 合并为同一字段，
  /// 导致 host 选 'b' 时被 role_check 误判为先手方。
  ///
  /// 身份 = 稳定登录 uid（transport.deviceId，见 chess_identity.dart），
  /// 与快照 context 里的 host_id / guest_id 同源 —— 断线重连 / 重新进房
  /// 身份不丢。
  ///
  /// 防御回退：host_id 缺失时用 guest_id 反推（我方 == guest_id → 对侧色）；
  /// 仍无法判定 → 回退 host_color（棋盘照常渲染，走子合法性由服务端兜底），不崩溃。
  PieceColor? _resolveMyColor(Snapshot snap) {
    final myDeviceId = widget.handle.transport.deviceId;
    final hostId = snap.context['host_id']?.toString();
    final guestId = snap.context['guest_id']?.toString();
    final hostIsWhite = ChessRoom.hostColor(snap) == 'w';
    final hostColor =
        hostIsWhite ? PieceColor.white : PieceColor.black;
    final guestColor =
        hostIsWhite ? PieceColor.black : PieceColor.white;
    if (myDeviceId.isEmpty) return hostColor; // 防御：身份空 → host 执子色兜底
    if (myDeviceId == hostId) return hostColor;
    if (myDeviceId == guestId) return guestColor;
    if (hostId != null && hostId.isNotEmpty) return guestColor;
    // host_id 缺失且我方不是 guest → 无法判定：host 执子色兜底。
    return hostColor;
  }

  /// 判定本地是否房主：device_id 精确比对（身份判定，与执子色无关）。
  ///
  /// v6 修复：旧实现 `myColor == PieceColor.white` 用颜色判 host，在残局
  /// host 执黑（host_color='b'）时误判 —— host 看不到"开始游戏"按钮，而
  /// guest（执白）被误判为 host 但服务端 role_check 拒绝其 DEAL，出现
  /// "guest 显示开始游戏但点击无响应" 的两端不一致。
  ///
  /// host_id 缺失（快照尚未到齐）→ false 兜底（lobby 卡片仍可渲染）。
  bool _resolveIsHost(Snapshot snap) {
    final myDeviceId = widget.handle.transport.deviceId;
    final hostId = snap.context['host_id']?.toString();
    if (hostId == null || hostId.isEmpty) return false;
    return myDeviceId == hostId;
  }

  // ── 阵营标签（lobby 卡片）：v5 host/guest 的"先手/后手"由 host_color
  //   与 initial_side 的等价关系决定 —— chess 规则决定先手方。
  //   · host_color == initial_side → host 是先手方；guest 是后手方
  //   · host_color != initial_side → guest 是先手方；host 是后手方
  //   标准开局（initial_side='w'）+ host_color='w' → host=执白先手（默认）
  //   标准开局（initial_side='w'）+ host_color='b' → host=执黑后手（Bug 1 修复点）

  String get _colorLabelHost {
    final hostIsFirst =
        ChessRoom.hostColor(_snapshot) == ChessRoom.initialSide(_snapshot);
    return hostIsFirst
        ? (ChessRoom.hostColor(_snapshot) == 'w' ? '执白（先手）' : '执黑（先手）')
        : (ChessRoom.hostColor(_snapshot) == 'w' ? '执白（后手）' : '执黑（后手）');
  }

  String get _colorLabelGuest {
    final hostIsFirst =
        ChessRoom.hostColor(_snapshot) == ChessRoom.initialSide(_snapshot);
    return hostIsFirst
        ? (ChessRoom.hostColor(_snapshot) == 'w' ? '执黑（后手）' : '执白（后手）')
        : (ChessRoom.hostColor(_snapshot) == 'w' ? '执黑（先手）' : '执白（先手）');
  }

  /// 残局标题（lobby 卡片 chip）：v5 不再"强翻转"残局 FEN，
  /// 所有残局原貌保留，不再有"· 镜像"标记。
  String? get _endgameTitle {
    final e = widget.initialEndgame;
    if (e != null) return '残局：${e.label ?? '快照'}';
    // 换设备进房（widget 无残局信息）→ 服务端 initial_fen 存在 = 残局房。
    if (ChessRoom.initialFen(_snapshot) != null) return '残局对局';
    return null;
  }

  void _onCloseEvent(WSCloseEvent event) {
    if (!mounted) return;
    // WS close code 0 = 暂时断开（RoomHandle 自动 reconnect 中），其余
    // 4403 / 4404 / 4408 是 terminal → 提示 + 断开。
    if (event.code == 0) {
      // 短暂断线：显示 overlay，RoomHandle 内部指数退避重连。
      // 拿到下一份快照时自动清（[_applySnapshot]）。
      setState(() => _wsOffline = true);
      return;
    }
    // 终端关闭（被踢 / 房间过期 / 慢消费者）—— 提示 + 断开。
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(WSCloseCode.describe(event.code)),
        action: SnackBarAction(
          label: '断开',
          onPressed: _leaveAndPop,
        ),
      ),
    );
  }

  // ─────────────────────────── 交互：选中 / 走子 ───────────────────────────

  Set<int> get _legalTargets {
    final board = _board;
    final sel = _selectedSquare;
    if (board == null || sel == null) return const <int>{};
    if (board.pieceColorAt(sel) != board.sideToMove) {
      return const <int>{};
    }
    final moves = widget.engine.generateLegalMoves(board);
    return {for (final m in moves)
      if (m.from == sel) m.to};
  }

  /// 交互门：非回放 + 我的回合 + 未在乐观发送 + 对局进行中（playing/check）。
  /// tap 与拖动共用同一道门（回放中棋盘只读复盘）。
  ///
  /// v2 新增：lobby / ready 阶段棋盘为空，禁走子；自己掉线时禁走子。
  bool get _canInteract =>
      !_replayMode &&
      !_isMeDisconnected &&
      _myTurn &&
      !_sendLock &&
      (_status == 'playing' || _status == 'check');

  void _handleTap(int square) {
    final board = _board;
    if (board == null) return;
    // 轮次 / 发送锁 / 状态门：不是我的回合或已乐观发送 → 忽略。
    if (!_canInteract) return;

    final pieceColor = board.pieceColorAt(square);
    final sel = _selectedSquare;

    // 情况 1：未选中 → 点到己方棋子 → 选中。
    if (sel == null) {
      if (pieceColor == board.sideToMove) {
        setState(() => _selectedSquare = square);
      }
      return;
    }

    // 情况 2：已选中 → 点到同一格 → 清选。
    if (square == sel) {
      setState(() => _selectedSquare = null);
      return;
    }

    // 情况 3：已选中 → 点到另一颗己方棋子 → 切换选中。
    if (pieceColor == board.sideToMove) {
      setState(() => _selectedSquare = square);
      return;
    }

    // 情况 4：已选中 → 点到合法目标（空格或对方）→ 走子。
    if (_legalTargets.contains(square)) {
      _tryMove(sel, square);
      return;
    }

    // 情况 5：其它（非法目标）→ 清选。
    setState(() => _selectedSquare = null);
  }

  // ─────────────────────────── 拖动（board-gesture-patterns） ───────────────────────────

  /// 拖动开始：只有"我的回合 + 己方棋子"才抬起拖动，其余忽略。
  void _handleDragStart(int square, Offset fingerPos) {
    if (!_canInteract) return;
    final board = _board;
    if (board == null) return;
    if (board.pieceColorAt(square) != board.sideToMove) return;
    setState(() {
      // 顺带选中（合法目标圆点/吃子圈随拖动显示），拖动/点选两种模式共用选中态。
      _selectedSquare = square;
      _draggingSquare = square;
      _dragFingerPos = fingerPos;
      _dragHoverSquare = square;
    });
  }

  /// 拖动移动：手指位置 + 悬停格实时更新（浮起棋子跟手 + 目标点放大）。
  void _handleDragUpdate(int? square, Offset fingerPos) {
    if (_draggingSquare == null) return;
    setState(() {
      _dragFingerPos = fingerPos;
      _dragHoverSquare = square;
    });
  }

  /// 拖动结束：合法目标 → 提交走法（升变 → 弹面板）；非法/棋盘外 → 弹回
  /// 并保持选中（规范 §2.3：退到"已选中"等待二次点击，不直接清空）。
  void _handleDragEnd(int? square, Offset fingerPos) {
    final from = _draggingSquare;
    if (from == null) return;
    setState(() {
      _draggingSquare = null;
      _dragFingerPos = null;
      _dragHoverSquare = null;
    });
    // 棋盘外 / 原地松手 → 保持选中（再点目标或再拖）
    if (square == null || square == from) return;
    if (!_legalTargets.contains(square)) return; // 非法目标 → 弹回
    _tryMove(from, square);
  }

  /// 尝试提交 from → to（已确认 to 在合法目标内）。
  /// 升变候选存在 → 暂停弹 [PromotionPanel]；否则直接乐观走子 + 发送。
  void _tryMove(int from, int to) {
    final board = _board;
    if (board == null) return;
    final moves = widget.engine
        .generateLegalMoves(board)
        .where((m) => m.from == from && m.to == to)
        .toList();
    if (moves.isEmpty) return;
    final promotionMoves = moves.where((m) => m.promotion != null).toList();
    if (promotionMoves.isNotEmpty) {
      // 升变候选存在 → 暂停，等玩家选 Q/R/B/N（拖到底线同弹面板，选完提交）。
      setState(() => _pendingPromotion = (from: from, to: to));
      return;
    }
    _commitMove(moves.first);
  }

  /// 玩家在升变面板选好类型 → 构造升变走法 → 乐观应用 + 发送。
  void _resolvePromotion(PieceType type) {
    final board = _board;
    final pending = _pendingPromotion;
    if (board == null || pending == null) return;
    final moves = widget.engine
        .generateLegalMoves(board)
        .where((m) =>
            m.from == pending.from &&
            m.to == pending.to &&
            m.promotion == type)
        .toList();
    if (moves.isEmpty) {
      // 状态异常（不应发生）：清 pending。
      setState(() => _pendingPromotion = null);
      return;
    }
    _commitMove(moves.first);
  }

  /// 取消升变 → 面板消失，回到未选状态。
  void _cancelPromotion() {
    setState(() => _pendingPromotion = null);
  }

  /// 应用合法走法 + 发送 MOVE action（乐观推进 + 服务端调和）。
  Future<void> _commitMove(Move move) async {
    final board = _board;
    if (board == null) return;
    final newState = applyMove(board, move).nextState;
    // 预计算新局面的 FEN，给 [_applySnapshot] 做 echo 识别（避免重复响）。
    final newFen = FenCodec.toFen(newState);
    // 乐观推进：本地先走，等服务端快照调和。
    setState(() {
      _board = newState;
      _selectedSquare = null;
      _lastMove = move;
      _pendingPromotion = null;
      _draggingSquare = null;
      _dragFingerPos = null;
      _dragHoverSquare = null;
      _myTurn = false; // 乐观锁：发送期间不响应本地输入
      _sendLock = true;
      _pendingLocalFen = newFen; // 标记本次 echo —— _applySnapshot 会拿来比对
    });
    // 自己的走子立刻响（不等服务端调和，零延迟反馈）—— 回放中没有 commit 路径可达。
    PieceSound.instance.play();
    await _sendMove(move, newState);
  }

  /// 发送 MOVE action（uci + fen + ts）。
  ///
  /// 协议（v6.2 校验 fence）：MOVE **不携带** status —— 终局由走子方
  /// 另行发 CLAIM_END（见 [_claimEnd]）。服务端对 uci 做结构校验、
  /// 对 fen 做结构 + sideToMove 反证，防 FEN 造假 / 任意终局声明。
  Future<void> _sendMove(Move move, BoardState newState) async {
    try {
      await widget.handle.applyAction(
        type: 'MOVE',
        params: {
          'uci': move.toUci(),
          'fen': FenCodec.toFen(newState),
          'ts': DateTime.now().millisecondsSinceEpoch,
        },
      );
      // 走子已落地 → 若引擎判定将杀 / 僵局，走子方补发终局声明。
      // （幂等：服务端 ended 后 CLAIM_END 会被拒，无害）
      if (widget.engine.getStatus(newState).isGameOver) {
        await _claimEnd(newState);
      }
      // 成功：applyAction 内部已更新 latest + 推送 snapshot；
      // 快照回调会整体重建棋盘（服务端调和），这里只解锁。
      if (mounted) {
        setState(() => _sendLock = false);
      }
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        // CAS 版本不匹配 → 拉最新快照（服务端状态优先）。
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('状态已过期，同步中…')),
        );
        // 409 reconcile：fetchSnapshot 走带 UI 反馈的版本（顶部进度条）。
        await _fetchSnapshotWithFeedback();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: ${e.statusCode} ${e.body}')),
        );
      }
      if (mounted) {
        setState(() => _sendLock = false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
      if (mounted) {
        setState(() => _sendLock = false);
      }
    }
  }

  /// 走子方上报终局（checkmate / stalemate）。
  ///
  /// 服务端只接受"刚走完的一方"的声明（moves 奇偶校验），checkmate 赢家 =
  /// 声明者本人；stalemate 无赢家。重复声明幂等（ended 后被拒）。
  Future<void> _claimEnd(BoardState newState) async {
    final status = widget.engine.getStatus(newState).name;
    final reason = status == 'checkmate' ? 'checkmate' : 'stalemate';
    try {
      await widget.handle.applyAction(
        type: 'CLAIM_END',
        params: {'reason': reason},
      );
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      if (e.statusCode != 409) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('终局声明失败: ${e.statusCode} ${e.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('终局声明失败: $e')),
      );
    }
  }

  // ─────────────────────────── 动作：准备 / 开始（READY 门） ───────────────────────────

  /// 准备 ACK：lobby 阶段点"准备好了"——立即本地置 _ackedLocally（按钮变"已准备 ✓"）
  /// 再发 ACK；服务端 ACK 回写后清 _ackedLocally。幂等（已点再点忽略）。
  Future<void> _ack() async {
    if (_ackedLocally) return;
    setState(() => _ackedLocally = true);
    try {
      await _room?.ack();
    } catch (_) {
      if (mounted) setState(() => _ackedLocally = false);
    }
  }

  /// host 点"开始游戏"（DEAL）—— 把 ready 推 playing。
  /// START 是 DEAL 的别名（向后兼容），这里优先 DEAL。
  Future<void> _deal() async {
    if (_dealLock || !_isHost) return;
    setState(() => _dealLock = true);
    try {
      await _room?.deal();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('开局失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _dealLock = false);
      }
    }
  }

  // ─────────────────────────── 动作：投降 / 和棋（offer → accept/decline） ───────────────────────────

  Future<void> _resign() async {
    if (_sendLock) return;
    setState(() => _sendLock = true);
    try {
      await widget.handle.applyAction(type: 'RESIGN', params: {});
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: ${e.statusCode} ${e.body}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _sendLock = false);
      }
    }
  }

  /// 对方是否已挂起和棋 offer（context['draw_offers'] 含对方 device_id）。
  bool get _opponentOffered {
    final snap = _snapshot;
    final myColor = _myColor;
    if (snap == null || myColor == null) return false;
    final offers = snap.context['draw_offers'];
    if (offers is! Map) return false;
    final oppId = myColor == PieceColor.white ? snap.context['guest_id'] : snap.context['host_id'];
    if (oppId == null) return false;
    return offers[oppId.toString()] == true;
  }

  /// 我方是否已挂起 offer（等待对方回应）。
  bool get _iOffered {
    final snap = _snapshot;
    if (snap == null) return false;
    final offers = snap.context['draw_offers'];
    if (offers is! Map) return false;
    return offers[widget.handle.transport.deviceId] == true;
  }

  // ─────────────────────────── 悔棋（undo → accept/decline） ───────────────────────────

  /// 对方是否已挂起悔棋 offer（context['undo_offers'] 含对方 device_id）。
  bool get _opponentUndoOffered {
    final snap = _snapshot;
    final myColor = _myColor;
    if (snap == null || myColor == null) return false;
    final offers = snap.context['undo_offers'];
    if (offers is! Map) return false;
    final oppId = myColor == PieceColor.white
        ? snap.context['guest_id']
        : snap.context['host_id'];
    if (oppId == null) return false;
    return offers[oppId.toString()] == true;
  }

  /// 我方是否已挂起悔棋 offer（等待对方回应）。
  bool get _iUndoOffered {
    final snap = _snapshot;
    if (snap == null) return false;
    final offers = snap.context['undo_offers'];
    if (offers is! Map) return false;
    return offers[widget.handle.transport.deviceId] == true;
  }

  /// 我能否请求悔棋：对局中 + 自己至少走过一手
  /// （host=白 → moves ≥ 1；guest=黑 → moves ≥ 2。与服务端 UNDO_OFFER 门一致）。
  bool get _canRequestUndo {
    final snap = _snapshot;
    if (snap == null || snap.state != 'playing') return false;
    final n = ChessRoom.moves(snap).length;
    return _isHost ? n >= 1 : n >= 2;
  }

  /// 点"议和"：无对方 offer → 发 DRAW_OFFER（只挂申请，等对方接受）；
  /// 对方已 offer → 直接发 DRAW_ACCEPT 接受 → 和棋。
  Future<void> _drawOffer() async {
    if (_sendLock) return;
    setState(() => _sendLock = true);
    try {
      await widget.handle.applyAction(
        type: _opponentOffered ? 'DRAW_ACCEPT' : 'DRAW_OFFER',
        params: {},
      );
      if (!_opponentOffered && mounted) {
        // 只发了 offer（对方尚未回）→ 提示"已发送议和请求，等待对方回应"。
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已发送议和请求，等待对方回应')),
        );
      }
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: ${e.statusCode} ${e.body}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _sendLock = false);
      }
    }
  }

  /// 对方 offer 时点"拒绝" → DRAW_DECLINE（清掉对方申请，回到正常对局）。
  Future<void> _drawDecline() async {
    if (_sendLock) return;
    setState(() => _sendLock = true);
    try {
      await widget.handle.applyAction(type: 'DRAW_DECLINE', params: {});
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: ${e.statusCode} ${e.body}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _sendLock = false);
      }
    }
  }

  /// 点"悔棋"：无对方 offer → 发 UNDO_OFFER（只挂申请，等对方接受）；
  /// 对方已 offer → 直接发 UNDO_ACCEPT → 服务端 pop 1~2 手回退棋盘。
  /// 悔棋生效后快照 fen/moves 变化 → [_applySnapshot] 自动重建棋盘 + 轮次。
  Future<void> _undoRequest() async {
    if (_sendLock) return;
    // 发送前存决策值（await 后读 getter 可能已被新快照翻转）。
    final accepting = _opponentUndoOffered;
    setState(() => _sendLock = true);
    try {
      await widget.handle.applyAction(
        type: accepting ? 'UNDO_ACCEPT' : 'UNDO_OFFER',
        params: {},
      );
      if (!accepting && mounted) {
        // 只发了 offer（对方尚未回）→ 提示"已发送悔棋请求，等待对方回应"。
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已发送悔棋请求，等待对方回应')),
        );
      }
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        // CAS 版本不匹配 → 拉最新快照（服务端状态优先）。
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('状态已过期，同步中…')),
        );
        await _fetchSnapshotWithFeedback();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: ${e.statusCode} ${e.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _sendLock = false);
      }
    }
  }

  /// 对方悔棋 offer 时点"拒绝" → UNDO_DECLINE（清掉对方申请，回到正常对局）。
  Future<void> _undoDecline() async {
    if (_sendLock) return;
    setState(() => _sendLock = true);
    try {
      await widget.handle.applyAction(type: 'UNDO_DECLINE', params: {});
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: ${e.statusCode} ${e.body}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _sendLock = false);
      }
    }
  }

  // ─────────────────────────── 动作：重开（host only） ───────────────────────────

  /// 房主发起重开 —— 服务端 RESET 会把 fen/moves/status 重置回新一局并回到
  /// state="playing"。本地状态（选中 / 上一步 / 升变 / 发送锁）在收到
  /// 新快照时由 [_applySnapshot] 清空。
  Future<void> _reset() async {
    if (_sendLock) return;
    setState(() => _sendLock = true);
    try {
      await widget.handle.applyAction(type: 'RESET', params: {});
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重开失败: ${e.statusCode} ${e.body}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重开失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _sendLock = false);
      }
    }
  }

  // ─────────────────────────── 回放（复盘） ───────────────────────────

  /// 服务端棋谱是否有可回放的走法（终局卡片"复盘"按钮的显隐条件：
  /// 立刻投降等零走法对局没有可复盘内容）。
  bool get _hasReplayableMoves {
    final raw = _snapshot?.context['moves'];
    return raw is List && raw.isNotEmpty;
  }

  /// 进入回放：解析最新快照的全部棋谱 → 一次性重演构建局面子序列 →
  /// 从终局开始（玩家先退步复盘 —— 标准复盘 UX）。
  ///
  /// 起点 = 服务端 initial_fen（残局房间从残局局面起演；标准房 null →
  /// BoardState.initial()）。每手 UCI 与引擎合法走法匹配（from/to/promotion
  /// 相同者）：匹配拿到的 Move 自带正确 flag（易位 / 吃过路兵 / capturedSquare），
  /// applyMove 依赖 flag 才能正确搬车 / 移除过路兵 —— 直接 Move.fromUci
  /// 的裸 flag 会把王车易位走成"王飞两格、车不动"。
  /// 匹配失败（畸形 / 与局面脱节的棋谱）→ 防御截断，只回放到此之前。
  void _enterReplay() {
    final snap = _snapshot;
    if (snap == null) return;
    final rawMoves = snap.context['moves'];
    if (rawMoves is! List || rawMoves.isEmpty) return;

    // 回放起点：残局房间从 initial_fen 起演（黑先残局亦同）；
    // 解析失败（畸形 FEN）→ 回退标准开局（防御）。
    BoardState start;
    final rawInitial = ChessRoom.initialFen(snap);
    if (rawInitial != null) {
      try {
        start = FenCodec.fromFen(rawInitial);
      } on Object {
        start = BoardState.initial();
      }
    } else {
      start = BoardState.initial();
    }

    final moves = <Move>[];
    final states = <BoardState>[start];
    var cur = states.first;
    for (final entry in rawMoves) {
      if (entry is! Map) break;
      final uci = entry['uci']?.toString();
      if (uci == null || uci.length < 4) break;
      final Move parsed;
      try {
        parsed = Move.fromUci(uci);
      } on ArgumentError {
        break; // 畸形 uci —— 防御：只回放到此之前。
      }
      Move? matched;
      for (final m in widget.engine.generateLegalMoves(cur)) {
        if (m.from == parsed.from &&
            m.to == parsed.to &&
            m.promotion == parsed.promotion) {
          matched = m;
          break;
        }
      }
      if (matched == null) break; // 棋谱与局面脱节 → 截断。
      cur = applyMove(cur, matched).nextState;
      moves.add(matched);
      states.add(cur);
    }
    if (moves.isEmpty) return; // 一手都没解析出来 → 不进回放。

    setState(() {
      _replayMoves = moves;
      _replayStates = states;
      _replayIndex = moves.length; // 从终局开始。
      _replayPlaying = false;
      _replayMode = true;
      _selectedSquare = null; // 顺带清交互残留（防御）。
    });
  }

  /// 导出当前回放局面为残局快照（ChessReplayBar 保存按钮）：
  ///   fen = 重演局面子序列在当前 index 的 FEN
  ///   lineage.moves = 初始局面走到当前 index 的 UCI 序列
  ///   id = eg-<房间号>-m<N>（同 (房间, 手数) 幂等 —— 重复导出提示已保存）
  /// 保存到 <documents>/chess_endgames/ → SnackBar 提供分享入口。
  Future<void> _exportCurrentReplayPosition() async {
    if (!_replayMode) return;
    final snap = _snapshot;
    if (snap == null) return;
    final index = _replayIndex;
    final fen = FenCodec.toFen(_replayStates[index]);
    final uciMoves = <String>[
      for (var i = 0; i < index; i++) _replayMoves[i].toUci(),
    ];
    final code = snap.roomCode;
    final id = 'eg-$code-m$index';
    final title = index == 0 ? '残局·初始局面' : '残局·第 $index 手';
    final endgame = ChessEndgame(
      id: id,
      title: title,
      description: '房间 $code 回放导出'
          '${(widget.initialEndgame?.label != null) ? ' · 源：${widget.initialEndgame!.label}' : ''}',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      source: ChessEndgameSource.replay,
      snapshots: [
        ChessEndgameSnapshot(
          label: index == 0 ? '初始局面' : '第 $index 手后',
          fen: fen,
          lineageMoves: uciMoves,
          lineageMoveIndex: index,
        ),
      ],
    );
    final store = ChessEndgameStore();
    try {
      final existed = await store.existsLocal(id);
      await store.save(endgame);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existed ? '残局已更新：$title' : '已保存到残局库：$title'),
          action: SnackBarAction(
            label: '分享',
            onPressed: () async {
              try {
                await store.exportAndShare(endgame);
              } on Object {
                // 分享失败静默（文件已落盘，用户可从残局库重试）。
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  /// 退出回放：回到终局覆盖层（返回 / 再来一局 / 复盘）。
  void _exitReplay() {
    if (!_replayMode) return;
    setState(_clearReplay);
  }

  /// 清空回放本地态（纯字段重置，不 setState —— 供 setState 回调 /
  /// [_applySnapshot] 内复用，避免嵌套 setState）。
  void _clearReplay() {
    _replayTimer?.cancel();
    _replayTimer = null;
    _replayMode = false;
    _replayPlaying = false;
    _replayIndex = 0;
    _replayMoves = const [];
    _replayStates = const [];
  }

  /// 跳到指定步（0 = 初始局面，moves.length = 终局）。
  /// 拖动进度条 / 步进 / 首尾跳共用入口。
  void _seekReplay(int index) {
    if (!_replayMode) return;
    final clamped = index.clamp(0, _replayMoves.length);
    if (clamped == _replayIndex) return;
    // 自动播放中拖到终局 → 停播（播放键复位 ▶）。
    if (_replayPlaying && clamped >= _replayMoves.length) {
      _replayTimer?.cancel();
      _replayTimer = null;
      setState(() {
        _replayIndex = clamped;
        _replayPlaying = false;
      });
      return;
    }
    setState(() => _replayIndex = clamped);
  }

  /// 步进（delta = -1 后退 / +1 前进；边界由 clamp 兜底 + 按钮禁用）。
  void _stepReplay(int delta) => _seekReplay(_replayIndex + delta);

  /// 自动播放开关：▶ 起播（已在终局 → 从头重放）/ ⏸ 暂停。
  void _toggleReplayPlay() {
    if (!_replayMode) return;
    if (_replayPlaying) {
      _replayTimer?.cancel();
      _replayTimer = null;
      setState(() => _replayPlaying = false);
      return;
    }
    // 已在终局按 ▶ → 回到开局重放（标准复盘 UX）。
    final start = _replayIndex >= _replayMoves.length ? 0 : _replayIndex;
    setState(() {
      _replayIndex = start;
      _replayPlaying = true;
    });
    _replayTimer = Timer.periodic(_kReplayTickInterval, (_) => _replayTick());
  }

  /// 自动播放 tick：前进一步；到终局自动停播。
  void _replayTick() {
    if (!mounted || !_replayMode) return;
    final next = _replayIndex + 1;
    if (next >= _replayMoves.length) {
      _replayTimer?.cancel();
      _replayTimer = null;
      setState(() {
        _replayIndex = _replayMoves.length;
        _replayPlaying = false;
      });
      return;
    }
    setState(() => _replayIndex = next);
  }

  // ─────────────────────────── 手动刷新（fetchSnapshot UI 反馈） ───────────────────────────

  /// 带 UI 反馈的 fetchSnapshot —— 顶部 LinearProgressIndicator + 按钮 spinner。
  ///
  /// 用法：
  ///   · 409 reconcile（服务端 CAS 版本不匹配）→ 同走这里，让用户知道在同步
  ///   · AppBar 手动刷新按钮 → 用户主动拉的路径
  /// 失败时弹 snackbar；成功时 fetchSnapshot 内部已 emit snapshot，[_applySnapshot]
  /// 自动更新本地态（无需手动 setState）。
  Future<void> _fetchSnapshotWithFeedback() async {
    if (_fetching) return; // 防双击
    setState(() => _fetching = true);
    try {
      await widget.handle.fetchSnapshot();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刷新失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  /// AppBar 上的"手动刷新"按钮 — 强制拉一次最新快照。
  ///
  /// 心跳（[RoomHandle] 内部的 20s 周期 fetchSnapshot）已经在后台运行；
  /// 这里只暴露给"玩家怀疑自己卡了"的应急按钮。
  Future<void> _manualRefresh() => _fetchSnapshotWithFeedback();

  // ─────────────────────────── 离开 ───────────────────────────

  Future<void> _leaveAndPop() async {
    final nav = Navigator.of(context);
    final onLeave = widget.onLeave;
    await widget.handle.leave();
    if (!mounted) return;
    nav.pop();
    onLeave?.call();
  }

  // ─────────────────────────── UI ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    if (snap == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('对弈房间')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // 优先本地皮肤（离线可用）；未本地化回退注册表（RemoteChessSkin / unicode）。
    final skin = widget.localSkin ?? ChessSkinBundle.byId(widget.skinId);

    final state = snap.state;

    // 阶段派发：
    //   lobby / ready → 准备卡片（共用 _buildLobbyReady）
    //   playing       → 棋盘 + 走子
    //   ended         → 棋盘背景 + 终局覆盖层（existing _GameOverCard）
    final Widget body;
    if (state == 'lobby' || state == 'ready') {
      body = _buildLobbyReady(skin);
    } else {
      final board = _board;
      if (board == null) {
        // playing 阶段但服务端 FEN 尚未到达（极少见）→ loading
        return Scaffold(
          appBar: AppBar(title: Text('房间 ${snap.roomCode}')),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      body = _buildPlaying(skin, board);
    }

    // 断线 / 短暂 WS 断开 → overlay 浮在内容之上。
    return Scaffold(
      appBar: AppBar(
        // 徽标（圆点 + 文字 + 重连 spinner）需要比默认 48 宽的 leading 槽。
        leadingWidth: 86,
        leading: ChessConnectionStatusBadge(handle: widget.handle),
        title: Text('房间 ${snap.roomCode}'),
        actions: [
          // 手动刷新按钮：强制拉一次最新快照（带 UI 反馈）。心跳已经在跑，
          // 这里只暴露给"我怀疑卡了"的应急场景。
          IconButton(
            icon: _fetching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _fetching ? null : _manualRefresh,
            tooltip: '刷新快照',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _leaveAndPop,
            tooltip: '断开',
          ),
        ],
      ),
      body: Stack(
        children: [
          // 顶部 fetching 进度条（拉取快照时显示）。
          if (_fetching)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          body,
          if (_wsOffline) _buildWsOfflineOverlay(),
          if (_isMeDisconnected && state == 'playing') _buildMeOfflineBanner(),
        ],
      ),
    );
  }

  // ── lobby / ready 卡片（共用，按 phase 切按钮态）──

  Widget _buildLobbyReady(ChessSkin skin) {
    final snap = _snapshot!;
    final colors = context.chessColors;
    final code = snap.roomCode;
    final hostId = ChessRoom.hostId(snap);
    final players = ChessRoom.players(snap);
    final readyMap = ChessRoom.readyMap(snap);
    final myId = widget.handle.transport.deviceId;
    final phase = snap.state;
    final bothReady = phase == 'ready';
    final iAmReady =
        bothReady || _ackedLocally || readyMap[myId] == true;
    final canDeal = bothReady && _isHost;
    final canAck = !bothReady && players.length >= 2;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.gridLine.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    bothReady ? '双方已就绪' : '等待对手',
                    style: TextStyle(
                      color: colors.coordinateLabel,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(width: 24, height: 2, color: colors.gridLine),
                  const SizedBox(height: 18),

                  // 房间号 chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.lightSquare.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                          color: colors.gridLine.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      code,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 8,
                        color: colors.coordinateLabel,
                      ),
                    ),
                  ),
                  // 残局房间：残局名 chip（建房 initial_fen 注入时显示）
                  if (_endgameTitle != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.extension_outlined,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _endgameTitle!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color:
                                    Theme.of(context).colorScheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),

                  // 玩家头像列表
                  ...players.entries.map((e) {
                    final isMe = e.key == myId;
                    final isReady = readyMap[e.key] == true;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isReady
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.12)
                                : colors.lightSquare.withValues(alpha: 0.5),
                            border: Border.all(
                              color: isReady
                                  ? Theme.of(context).colorScheme.primary
                                  : colors.gridLine.withValues(alpha: 0.4),
                              width: isReady ? 2.4 : 1.6,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: isReady
                              ? Icon(Icons.check_rounded,
                                  size: 22,
                                  color: Theme.of(context).colorScheme.primary)
                              : Text(
                                  e.value.isNotEmpty
                                      ? e.value[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color: colors.coordinateLabel,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            '${e.value}${isMe ? "  (我)" : ""}'
                            '${e.key == hostId ? " · $_colorLabelHost" : " · $_colorLabelGuest"}',
                            style: TextStyle(
                              color: colors.coordinateLabel,
                              fontSize: 15,
                              fontWeight:
                                  isMe ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isReady
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.12)
                                : colors.lightSquare.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isReady ? '已准备 ✓' : '未准备',
                            style: TextStyle(
                              color: isReady
                                  ? Theme.of(context).colorScheme.primary
                                  : colors.coordinateLabel
                                      .withValues(alpha: 0.7),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ]),
                    );
                  }),

                  if (players.length < 2) ...[
                    const SizedBox(height: 16),
                    Text(
                      '把房间号发给朋友',
                      style: TextStyle(
                        color: colors.coordinateLabel.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],

                  if (players.length >= 2) ...[
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: bothReady
                          ? (canDeal
                              ? FilledButton(
                                  onPressed: _dealLock ? null : _deal,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: colors.gridLine,
                                    foregroundColor: colors.lightSquare,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text('开始游戏 ▸',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 2,
                                      )),
                                )
                              : Center(
                                  child: Text(
                                    '等待房主开始…',
                                    style: TextStyle(
                                      color: colors.coordinateLabel
                                          .withValues(alpha: 0.7),
                                      fontSize: 13,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ))
                          : (iAmReady
                              ? FilledButton(
                                  onPressed: null,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: colors.gridLine
                                        .withValues(alpha: 0.4),
                                    foregroundColor: colors.lightSquare,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text('已准备 ✓',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 2,
                                      )),
                                )
                              : OutlinedButton(
                                  onPressed: canAck ? _ack : null,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    side: BorderSide(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      width: 1.6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: const Text('准备好了',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 2,
                                      )),
                                )),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 短暂 WS 断开 overlay（不退出页面，等 reconnect 自动清）。
  Widget _buildWsOfflineOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.55),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                '连接断开，正在重连…',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 自己掉线 banner（服务端 c.disconnected[myId] = true，房间 alive）。
  Widget _buildMeOfflineBanner() {
    final colors = context.chessColors;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.85),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '你已掉线 · 正在重连（棋盘已冻结）',
              style: TextStyle(
                color: colors.checkmateOverlay,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// playing / ended 阶段：棋盘 + 走子 / 终局覆盖层（v1 同款 UI 拆出来）。
  Widget _buildPlaying(ChessSkin skin, BoardState board) {
    final colors = context.chessColors;
    final myColor = _myColor;
    final gameOver = _snapshot!.state == 'ended';
    final pending = _pendingPromotion;
    // 视角由角色驱动、整局稳定：我方黑 → 翻转到黑方视角（黑在底）。
    final flipped = myColor == PieceColor.black;
    // 回放中：棋盘渲染局面子序列缓存（states[index]），上一步高亮 =
    // 当前步的前一手（index 0 = 初始局面，无高亮）。
    final replayOn = _replayMode;
    final displayBoard = replayOn ? _replayStates[_replayIndex] : board;
    final displayLastMove = replayOn
        ? (_replayIndex > 0 ? _replayMoves[_replayIndex - 1] : null)
        : _lastMove;

    return Stack(
      children: [
        Column(
          children: [
            // 阵营 / 轮次状态条
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  if (myColor != null)
                    Text(
                      myColor == PieceColor.white ? '你执白' : '你执黑',
                      style: TextStyle(
                        fontSize: 14,
                        color: myColor == PieceColor.white
                            ? colors.coordinateLabel
                            : colors.gridLine,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    _statusLabel(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _status == 'check'
                          ? colors.checkWarning
                          : colors.coordinateLabel,
                    ),
                  ),
                ],
              ),
            ),
            // 棋盘（占满剩余空间）
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ChessBoard(
                  // 回放中渲染缓存局面子序列；平时渲染实况棋盘（快照 fen）。
                  state: displayBoard,
                  skin: skin,
                  sideToMove: displayBoard.sideToMove,
                  flipped: flipped,
                  // 回放中棋盘只读：选中 / 合法目标清空 + 输入回调全部
                  // 断开（tap 与拖动手势层都不挂载）。
                  selectedSquare: replayOn ? null : _selectedSquare,
                  legalTargets: replayOn ? const <int>{} : _legalTargets,
                  lastMove: displayLastMove,
                  onSquareTap: replayOn ? null : _handleTap,
                  onDragSquareStart: replayOn ? null : _handleDragStart,
                  onDragSquareUpdate: replayOn ? null : _handleDragUpdate,
                  onDragSquareEnd: replayOn ? null : _handleDragEnd,
                  draggingSquare: replayOn ? null : _draggingSquare,
                  dragFingerPos: replayOn ? null : _dragFingerPos,
                  dragHoverSquare: replayOn ? null : _dragHoverSquare,
                  // 用户自定义棋盘配色（null = 跟随主题）
                  boardPalette: widget.boardPalette,
                ),
              ),
            ),
            // 操作条：回放中 → 回放控制条（步进 / 自动播放 / 进度条 / 退出）；
            // 平时 → 投降 / 悔棋 / 和棋（offer → accept/decline）。
            // 悔棋 offer 优先于议和 offer 显示（悔棋有行动性；拒绝悔棋后
            // 议和 offer 仍在 context 里，自然回到议和的接受/拒绝显示）。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: replayOn
                  ? ChessReplayBar(
                      index: _replayIndex,
                      total: _replayMoves.length,
                      playing: _replayPlaying,
                      onToStart: () => _seekReplay(0),
                      onStepBack: () => _stepReplay(-1),
                      onTogglePlay: _toggleReplayPlay,
                      onStepForward: () => _stepReplay(1),
                      onToEnd: () => _seekReplay(_replayMoves.length),
                      onSeek: _seekReplay,
                      onExit: _exitReplay,
                      onExport: _exportCurrentReplayPosition,
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_opponentUndoOffered && !gameOver) ...[
                          // 对方挂起悔棋：接受 / 拒绝 两按钮；投降入口保留
                          // （防对方反复挂 offer 时我方无法投降）。
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _sendLock ? null : _undoRequest,
                                icon: const Icon(Icons.undo, size: 18),
                                label: const Text('接受悔棋'),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: _sendLock ? null : _undoDecline,
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text('拒绝'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _resign,
                            icon: const Icon(Icons.flag, size: 18),
                            label: const Text('投降'),
                          ),
                        ] else if (_opponentOffered && !gameOver) ...[
                          // 对方挂起议和：接受 / 拒绝 两按钮；悔棋入口保留。
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _sendLock ? null : _drawOffer,
                                icon: const Icon(Icons.handshake, size: 18),
                                label: const Text('接受议和'),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: _sendLock ? null : _drawDecline,
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text('拒绝'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _undoEntryButton(gameOver: gameOver),
                        ] else
                          // 平时：投降 / 悔棋 / 议和。
                          // Wrap 布局：窄屏自动换行，不写死宽度（防按钮文字截断）。
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: gameOver ? null : _resign,
                                icon: const Icon(Icons.flag, size: 18),
                                label: const Text('投降'),
                              ),
                              _undoEntryButton(gameOver: gameOver),
                              OutlinedButton.icon(
                                onPressed: gameOver ? null : _drawOffer,
                                icon: const Icon(Icons.handshake, size: 18),
                                label: Text(_iOffered ? '等待对方回应' : '议和'),
                              ),
                            ],
                          ),
                      ],
                    ),
            ),
          ],
        ),
        // 升变面板
        if (pending != null)
          Positioned.fill(
            child: PromotionPanel(
              skin: skin,
              promotingColor: _myColor ?? board.sideToMove,
              onSelected: _resolvePromotion,
              onCancel: _cancelPromotion,
            ),
          ),
        // 终局覆盖层（回放中隐藏 —— 回放条接管底部；退出回放重新显示）。
        if (gameOver && !replayOn)
          Positioned.fill(
            child: Container(
              color: colors.checkmateOverlay.withValues(alpha: 0.75),
              alignment: Alignment.center,
              child: _GameOverCard(
                title: _gameOverTitle(),
                subtitle: _gameOverSubtitle(),
                colors: colors,
                isHost: _isHost,
                onReset: _reset,
                onLeave: _leaveAndPop,
                // 复盘入口：棋谱非空才显示（立刻投降等零走法对局无回放内容）。
                onReplay: _hasReplayableMoves ? _enterReplay : null,
              ),
            ),
          ),
      ],
    );
  }

  /// 悔棋入口按钮（平时操作条 / 对方议和 offer 时第二行共用）。
  ///
  /// 禁用条件：终局（gameOver）/ 自己一手未走（[_canRequestUndo]，
  /// 与服务端 UNDO_OFFER 的 n 门一致 —— 白方 moves ≥ 1、黑方 moves ≥ 2）/
  /// 已挂起自己的悔棋 offer（等待对方回应，防重复发）。
  Widget _undoEntryButton({required bool gameOver}) {
    final waiting = _iUndoOffered;
    return OutlinedButton.icon(
      onPressed: (gameOver || waiting || !_canRequestUndo) ? null : _undoRequest,
      icon: const Icon(Icons.undo, size: 18),
      label: Text(waiting ? '等待对方回应' : '悔棋'),
    );
  }

  /// 轮次 / 状态文案。
  String _statusLabel() {
    // 回放中：状态条显示复盘提示（轮次文案对只读棋盘无意义）。
    if (_replayMode) return '回放中';
    if (_myTurn) {
      return _status == 'check' ? '你的回合 · 将军' : '你的回合';
    }
    if (_status == 'check') return '等待对方 · 将军';
    return '等待对方…';
  }

  /// 终局标题。
  String _gameOverTitle() {
    switch (_status) {
      case 'checkmate':
        return '将杀';
      case 'stalemate':
        return '僵局';
      case 'resigned':
        return '认输';
      case 'draw':
        return '和棋';
      default:
        return '对局结束';
    }
  }

  /// 终局副标题（胜负判定）。
  String _gameOverSubtitle() {
    final myColor = _myColor;
    if (myColor == null) return '';
    switch (_status) {
      case 'checkmate':
      case 'resigned':
        final snapshot = _snapshot;
        final winner = snapshot?.context['winner']?.toString();
        if (winner == null) return '对局结束';
        final iWin = winner == widget.handle.transport.deviceId;
        return iWin ? '你赢了' : '你输了';
      case 'stalemate':
      case 'draw':
        return '平局';
      default:
        return '';
    }
  }
}

/// 终局卡片（结果文本 + 再来一局[房主] + 返回按钮）。
class _GameOverCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final ChessColorStrategy colors;

  /// 本地是否为房主 —— 仅房主可见"再来一局"（服务端 RESET 仅 host 可调）。
  final bool isHost;

  /// 房主点击"再来一局" → 发 RESET action。
  final VoidCallback onReset;

  /// 点击"复盘" → 进入回放模式（null = 本局无走法，按钮不显示）。
  final VoidCallback? onReplay;

  final VoidCallback onLeave;

  const _GameOverCard({
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.isHost,
    required this.onReset,
    this.onReplay,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      decoration: BoxDecoration(
        color: colors.promotionOverlay,
        border: Border.all(color: colors.promotionBorder, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(fontSize: 16, color: colors.coordinateLabel),
          ),
          const SizedBox(height: 20),
          // 再来一局：仅房主可见（服务端 RESET 仅 host 可调）
          if (isHost) ...[
            FilledButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.replay, size: 18),
              label: const Text('再来一局'),
            ),
            const SizedBox(height: 12),
          ],
          // 复盘：回放整局（步进 / 自动播放 / 进度条）—— 双方都可用。
          if (onReplay != null) ...[
            OutlinedButton.icon(
              onPressed: onReplay,
              icon: const Icon(Icons.history_edu, size: 18),
              label: const Text('复盘'),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton(
            onPressed: onLeave,
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }
}
