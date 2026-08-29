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
//
// 本页拥有棋盘状态（Option A）—— 不复用 ChessController（它自带内部 BoardState），
// 直接渲染无状态 ChessBoard + 自己实现选中 / 合法目标 / 升变状态机。
//
// 颜色走 context.chessColors（v6.2.1 第 6 strategy 通道），不写死 Color(0xFF...)。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../widgets/context_chess_colors.dart';
import '../../net_engine/relay_v3/relay_v3_transport.dart';
import '../../theme/colors/strategy/chess_color_strategy/chess_color_strategy.dart'
    show ChessColorStrategy;
import '../engine/chess_engine.dart';
import '../engine/fen_codec.dart';
import '../engine/make_move.dart';
import '../models/board_state.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../skins/chess_skin.dart';
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

  const ChessRoomPage({
    super.key,
    required this.handle,
    this.onLeave,
    this.engine = const ChessEngine(),
    this.skinId = '1',
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
  PieceColor? _myColor;

  /// 当前选中格（1D index）。
  int? _selectedSquare;

  /// 上一步走法（from/to 高亮）。
  Move? _lastMove;

  /// 升变待决（兵到底线时暂停走法，等玩家选 Q/R/B/N）。
  ({int from, int to})? _pendingPromotion;

  /// 是否轮到本地走（由快照 sideToMove == _myColor 推出）。
  bool _myTurn = false;

  /// 服务端 status（"playing"/"check"/"checkmate"/"stalemate"/"resigned"/"draw"）。
  String _status = 'playing';

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
        // 服务端调和：本地已选中的格子在权威局面下失效，清选。
        _selectedSquare = null;
        _pendingPromotion = null;
      } on ArgumentError {
        // 畸形 FEN —— 保持上一份棋盘不动（防御）。
      }
    }

    // 2. 阵营：host = 白方，guest = 黑方（只判一次）。
    _myColor ??= _resolveMyColor(snap);

    // 3. 轮次：快照 sideToMove == 本地颜色 → 轮到我。
    final board = _board;
    if (board != null && _myColor != null) {
      _myTurn = board.sideToMove == _myColor;
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

  void _handleTap(int square) {
    final board = _board;
    if (board == null) return;
    // 轮次 / 发送锁 / 状态门：不是我的回合或已乐观发送 → 忽略。
    if (!_myTurn || _sendLock) return;
    if (_status != 'playing' && _status != 'check') return;

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
    final targets = _legalTargets;
    if (targets.contains(square)) {
      final moves = widget.engine
          .generateLegalMoves(board)
          .where((m) => m.from == sel && m.to == square)
          .toList();
      if (moves.isNotEmpty) {
        final promotionMoves =
            moves.where((m) => m.promotion != null).toList();
        if (promotionMoves.isNotEmpty) {
          // 升变候选存在 → 暂停，等玩家选 Q/R/B/N。
          setState(() => _pendingPromotion = (from: sel, to: square));
          return;
        }
        _commitMove(moves.first);
        return;
      }
    }

    // 情况 5：其它（非法目标）→ 清选。
    setState(() => _selectedSquare = null);
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
      _myTurn = false; // 乐观锁：发送期间不响应本地输入
      _sendLock = true;
    });
    await _sendMove(move, newState);
  }

  /// 发送 MOVE action（uci + fen + status + ts）。
  Future<void> _sendMove(Move move, BoardState newState) async {
    // 升变时 toUci 带 promotion 字符（如 e7e8q）。
    final status = widget.engine.getStatus(newState).name;
    try {
      await widget.handle.applyAction(
        type: 'MOVE',
        params: {
          'uci': move.toUci(promotingColor: _myColor ?? PieceColor.white),
          'fen': FenCodec.toFen(newState),
          'status': status,
          'ts': DateTime.now().millisecondsSinceEpoch,
        },
      );
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

  // ─────────────────────────── 动作：投降 / 和棋 ───────────────────────────

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

  Future<void> _drawAgree() async {
    if (_sendLock) return;
    setState(() => _sendLock = true);
    try {
      await widget.handle.applyAction(type: 'DRAW_AGREE', params: {});
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
    final skin = ChessSkinBundle.byId(widget.skinId);
    final myColor = _myColor;
    final gameOver = snap.state == 'ended';
    final pending = _pendingPromotion;

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
                    selectedSquare: _selectedSquare,
                    legalTargets: _legalTargets,
                    lastMove: _lastMove,
                    onSquareTap: _handleTap,
                  ),
                ),
              ),
              // 操作条：投降 / 和棋
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: gameOver ? null : _resign,
                      icon: const Icon(Icons.flag, size: 18),
                      label: const Text('投降'),
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      onPressed: gameOver ? null : _drawAgree,
                      icon: const Icon(Icons.handshake, size: 18),
                      label: const Text('协议和棋'),
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

/// 终局卡片（结果文本 + 返回按钮）。
class _GameOverCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final ChessColorStrategy colors;
  final VoidCallback onLeave;

  const _GameOverCard({
    required this.title,
    required this.subtitle,
    required this.colors,
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
          FilledButton(
            onPressed: onLeave,
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }
}
