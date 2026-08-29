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
// 颜色走 context.chessColors（v6.2.1 第 6 strategy 通道），不写死 Color(0xFF...)。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../widgets/context_chess_colors.dart';
import '../../net_engine/relay_v3/relay_connection_bar.dart';
import '../../net_engine/relay_v3/relay_v3_transport.dart';
import '../../theme/colors/strategy/chess_color_strategy/chess_color_strategy.dart'
    show ChessColorStrategy;
import '../engine/chess_engine.dart';
import '../engine/fen_codec.dart';
import '../engine/make_move.dart';
import '../models/board_state.dart';
import '../models/game_status.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../skins/chess_skin.dart';
import '../skins/local_chess_skin.dart';
import '../widgets/board_palette.dart';
import '../widgets/chess_board.dart';
import '../widgets/promotion_panel.dart';

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

  const ChessRoomPage({
    super.key,
    required this.handle,
    this.onLeave,
    this.engine = const ChessEngine(),
    this.skinId = '1',
    this.localSkin,
    this.boardPalette,
  });

  @override
  State<ChessRoomPage> createState() => _ChessRoomPageState();
}

class _ChessRoomPageState extends State<ChessRoomPage> {
  StreamSubscription<Snapshot>? _snapSub;
  StreamSubscription<WSCloseEvent>? _closeSub;

  /// 最新服务端快照（null = 尚未收到）。
  Snapshot? _snapshot;

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

  @override
  void initState() {
    super.initState();
    final snap = widget.handle.latest;
    if (snap != null) {
      _applySnapshot(snap);
    }
    // RoomHandle 构造时已自动 connect WS（createRoom / joinRoom 路径）。
    // 这里只需订阅 snapshot 流。
    _snapSub = widget.handle.snapshots.listen(_onSnapshot);
    // 监听 WS 关闭事件（断线 / 被踢 / 房间过期等）。
    _closeSub = widget.handle.closeEvents.listen(_onCloseEvent);
  }

  @override
  void dispose() {
    _snapSub?.cancel();
    _closeSub?.cancel();
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

    // 2. 阵营：host = 白方，guest = 黑方（每次快照重算）。
    final myColor = _resolveMyColor(snap);
    _myColor = myColor;
    _isHost = myColor == PieceColor.white && snap.context['host_id'] != null;

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

    // 6. 服务端 RESET 后（ended → playing）：清掉本局本地状态（发送锁）。
    //    上一步高亮由 [._latestMoveFrom] 从新棋谱派生（RESET 清空 moves → null）。
    if (_prevState == 'ended' && snap.state != 'ended') {
      _sendLock = false;
    }
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

  /// 判定本地棋子颜色：host = 白，guest = 黑。
  PieceColor? _resolveMyColor(Snapshot snap) {
    final myDeviceId = widget.handle.transport.deviceId;
    final hostId = snap.context['host_id']?.toString();
    if (myDeviceId.isNotEmpty && myDeviceId == hostId) {
      return PieceColor.white;
    }
    if (hostId != null && hostId.isNotEmpty && myDeviceId != hostId) {
      return PieceColor.black;
    }
    return null;
  }

  void _onCloseEvent(WSCloseEvent event) {
    if (!mounted) return;
    if (event.code != 0) {
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

  /// 交互门：我的回合 + 未在乐观发送 + 对局进行中（playing/check）。
  /// tap 与拖动共用同一道门。
  bool get _canInteract =>
      _myTurn && !_sendLock && (_status == 'playing' || _status == 'check');

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
    });
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
          'uci': move.toUci(promotingColor: _myColor ?? PieceColor.white),
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
        try {
          await widget.handle.fetchSnapshot();
        } catch (_) {
          // best-effort；WS 下次推送时 reconcile。
        }
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
    final board = _board;
    if (snap == null || board == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('对弈房间')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final colors = context.chessColors;
    // 优先本地皮肤（离线可用）；未本地化回退注册表（RemoteChessSkin / unicode）。
    final skin = widget.localSkin ?? ChessSkinBundle.byId(widget.skinId);
    final myColor = _myColor;
    final gameOver = snap.state == 'ended';
    final pending = _pendingPromotion;
    // 视角由角色驱动、整局稳定：我方黑 → 翻转到黑方视角（黑在底）。
    final flipped = myColor == PieceColor.black;

    return Scaffold(
      appBar: AppBar(
        title: Text('房间 ${snap.roomCode}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _leaveAndPop,
            tooltip: '断开',
          ),
        ],
      ),
      body: Stack(
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
                    state: board,
                    skin: skin,
                    sideToMove: board.sideToMove,
                    flipped: flipped,
                    selectedSquare: _selectedSquare,
                    legalTargets: _legalTargets,
                    lastMove: _lastMove,
                    onSquareTap: _handleTap,
                    // 拖动（规范 board-gesture-patterns）：跟手浮起 + 悬停放大 +
                    // 松手合法目标提交；门控（我的回合/状态）在回调内判定。
                    onDragSquareStart: _handleDragStart,
                    onDragSquareUpdate: _handleDragUpdate,
                    onDragSquareEnd: _handleDragEnd,
                    draggingSquare: _draggingSquare,
                    dragFingerPos: _dragFingerPos,
                    dragHoverSquare: _dragHoverSquare,
                    // 用户自定义棋盘配色（null = 跟随主题）
                    boardPalette: widget.boardPalette,
                  ),
                ),
              ),
              // 操作条：投降 / 和棋（offer → accept/decline）
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_opponentOffered && !gameOver) ...[
                      // 对方挂起议和：接受 / 拒绝 两按钮。
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
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: gameOver ? null : _resign,
                            icon: const Icon(Icons.flag, size: 18),
                            label: const Text('投降'),
                          ),
                          const SizedBox(width: 16),
                          OutlinedButton.icon(
                            onPressed: gameOver ? null : _drawOffer,
                            icon: const Icon(Icons.handshake, size: 18),
                            label: Text(_iOffered ? '等待对方回应' : '议和'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // WS 连接状态条（模板 §3.5 通用增强）：断线可见 + 手动拉取快照
              RelayConnectionBar(handle: widget.handle),
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
          // 终局覆盖层
          if (gameOver)
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
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 轮次 / 状态文案。
  String _statusLabel() {
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

  final VoidCallback onLeave;

  const _GameOverCard({
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.isHost,
    required this.onReset,
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
          OutlinedButton(
            onPressed: onLeave,
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }
}
