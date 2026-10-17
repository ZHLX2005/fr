// lib/core/draughts/p2p/draughts_room_page.dart
//
// 国际跳棋对局房页：准备 / 对战 / 终局三态。
//
// ## 流程
//
//   lobby（双方 ACK）→ ready（host DEAL）→ playing → ended（CLAIM_END / RESIGN / DRAW）
//   终局后 host 可 RESET 回 lobby 再来一局。
//
// ## 准备卡（lobby / ready）
//
//   对齐 chess / sudoku 的 game_ready_style 模板：标题 + 房间号胶囊 +
//   房间规则面板（执子色，host SET_RULES，改完清 ready 回 lobby）+
//   玩家行（头像 / 就绪徽章 / 执子标签）+ CTA 三态。
//   准备态不显示棋盘（同 chess）。
//
// ## 进入对局过渡
//
//   GameEnterTransition v2 时机规范：准备态首次切 playing 时刷子盖屏
//   （每份快照后 update；RESET 回 lobby 后重新武装，再开一局再播）。
//
// ## 交互（playing）
//
//   点选中己方子 → 高亮该子全部合法落点 → 点落点执行该手。
//   吃子时引擎已做最长吃子裁决，落点即"最终落点"；同落点多条链时取第一条
//   （确定性，且实战中同起终点异路径极少）。
//
// ## 操作条（playing，对齐 chess 模式）
//
//   AppBar：手动刷新（fetchSnapshot + spinner 反馈）/ 退出。
//   底部操作条：投降 / 悔棋 / 议和三按钮；对方挂起悔棋（议和）offer 时
//   切换为「接受 + 拒绝」双按钮行。悔棋 offer 流 UNDO_OFFER → 对方
//   UNDO_ACCEPT（服务端 pop 1~2 手）/ UNDO_DECLINE。
//
// ## 音效（PieceSound 单例）
//
//   initState 预加载；自己走子即时响（吃子手换 capture.wav）；
//   对手走子按快照 fen diff 响，_pendingLocalFen 标记吃掉自己的 echo 防重响。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../game_audio/piece_sound.dart';
import '../../game_kit/lobby/game_enter_transition.dart';
import '../../game_kit/lobby/game_ready_style.dart';
import '../engine/draughts_engine.dart';
import '../engine/make_move.dart';
import '../engine/pdn_codec.dart';
import '../models/board_state.dart';
import '../models/game_status.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../widgets/draughts_board.dart';
import 'draughts_room.dart';
import 'widgets/draughts_room_rules_panel.dart';

class DraughtsRoomPage extends StatefulWidget {
  const DraughtsRoomPage({
    super.key,
    required this.handle,
    required this.onLeave,
  });

  final RoomHandle handle;
  final Future<void> Function() onLeave;

  @override
  State<DraughtsRoomPage> createState() => _DraughtsRoomPageState();
}

class _DraughtsRoomPageState extends State<DraughtsRoomPage> {
  StreamSubscription<Snapshot>? _sub;
  late final DraughtsRoom _room;

  /// 进入对局过渡：准备态（lobby/ready）→ playing 首次切入 → 刷子盖屏。
  final GameEnterTransition _enterFx = GameEnterTransition();

  Snapshot? _snap;
  List<DraughtsMoveRecord> _history = const [];
  DraughtsBoardState _board = DraughtsBoardState.initial();

  int? _selected;
  Set<int> _targets = const {};
  Set<int> _lastPath = const {};

  bool _ackedLocally = false;
  bool _endDeclared = false;
  bool _setRulesLock = false;
  bool _dealLock = false;

  /// 动作发送锁（走子 / 投降 / 悔棋 / 议和 / 重开 / 刷新共用，防双击）。
  bool _sendLock = false;

  /// 手动拉取快照进行中（AppBar 刷新按钮 spinner）。
  bool _fetching = false;

  /// 上一份快照的 fen —— 对手走子音的差分基准（首份快照 null 不响）。
  String? _prevFen;

  /// 自己刚走的走后 fen —— 快照 echo 识别（已在本地响过，防重响）。
  String? _pendingLocalFen;

  @override
  void initState() {
    super.initState();
    _room = DraughtsRoom(widget.handle);
    _snap = widget.handle.latest;
    _applySnapshot(_snap);
    _sub = widget.handle.snapshots.listen(_onSnapshot);
    // 预加载落子音，消除首次落子的加载延迟（PieceSound 单例跨页复用）。
    PieceSound.instance.preload();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── 快照 ──

  void _onSnapshot(Snapshot s) {
    if (!mounted) return;
    final prev = _snap?.state;
    // RESET 合法推进：ended → lobby（房主「再来一局」）。
    // isStateRegression 把任何 ended→非 ended 都当回退，这里显式放行。
    final isResetRematch = prev == 'ended' && s.state == 'lobby';
    if (_snap != null &&
        !isResetRematch &&
        RoomHandle.isStateRegression(prev, s.state)) {
      return; // 服务端快照端点回退 → 忽略
    }
    // 准备态 → playing 首次切入 → 刷子过渡盖屏（GameEnterTransition v2）。
    _enterFx.update(context, s.state == 'playing');
    setState(() => _applySnapshot(s));
    // 快照仍处于 lobby/ready：本地乐观 ACK 已无意义（服务端 ready 表是权威，
    // SET_RULES / RESET 会清空 ready），清掉本地标记 —— 对齐 chess / sudoku。
    if ((s.state == 'lobby' || s.state == 'ready') && _ackedLocally) {
      setState(() => _ackedLocally = false);
    }
    if (s.state == 'lobby') _endDeclared = false;
    _maybeDeclareEnd();
  }

  void _applySnapshot(Snapshot? s) {
    _snap = s;
    _history = DraughtsRoom.rebuildHistory(s);
    // 落子音（对齐 chess 的差分模板）：
    //   · 首份快照（_prevFen == null）→ 页面刚进，不响。
    //   · fen 未变（同状态重推）→ 不响。
    //   · fen == _pendingLocalFen → 自己走子的服务端 echo（本地已响）→ 不响。
    //   · 其余 = 对手走子 / 悔棋回退 → 响；吃子手换 capture.wav。
    final fen = DraughtsRoom.fen(s);
    if (fen != null && fen.isNotEmpty && _prevFen != null && fen != _prevFen) {
      if (fen != _pendingLocalFen) {
        final lastIsCapture =
            _history.isNotEmpty && _history.last.pdn.contains('x');
        if (lastIsCapture) {
          PieceSound.instance.playCapture();
        } else {
          PieceSound.instance.play();
        }
      }
    }
    if (fen != null && fen.isNotEmpty) _prevFen = fen;
    _pendingLocalFen = null; // 每次快照清一次（echo 已消费 / 其它情况丢弃）。
    _board = DraughtsRoom.rebuildBoard(_history, initialFen: DraughtsRoom.initialFen(s));
    _selected = null;
    _targets = const {};
    _lastPath = _history.isEmpty
        ? const {}
        : _pathOfLastMove(_history.last);
  }

  Set<int> _pathOfLastMove(DraughtsMoveRecord rec) {
    // 用"上一手之前的局面"解析 PDN 路径（取 path 的格索引）
    final before = DraughtsRoom.rebuildBoard(
      _history.sublist(0, _history.length - 1),
      initialFen: DraughtsRoom.initialFen(_snap),
    );
    final m = pdnMoveToMove(before, rec.pdn);
    if (m == null) return const {};
    return m.path.toSet();
  }

  // ── 角色 ──

  String get _me => widget.handle.transport.deviceId;
  DraughtsColor get _myColor => DraughtsRoom.myColor(widget.handle, _snap);
  bool get _isHost => _me == DraughtsRoom.hostId(_snap);
  bool get _isPlaying => _snap?.state == 'playing';
  bool get _isMyTurn =>
      _isPlaying && _board.sideToMove == _myColor && !_endDeclared;

  List<DraughtsMove> get _myLegalMoves => _isMyTurn
      ? kDefaultDraughtsEngine.legalMoves(_board)
      : const [];

  // ── 终局上报 ──

  void _maybeDeclareEnd() {
    if (_endDeclared || !_isPlaying) return;
    final keys = DraughtsRoom.rebuildPositionHistory(
      _history,
      initialFen: DraughtsRoom.initialFen(_snap),
    );
    final st = kDefaultDraughtsEngine.status(_board, positionHistory: keys);
    if (!st.isOver) return;
    _endDeclared = true;
    // 只有"刚走完的一方"能声明（= 非当前走子方）
    final claimerIsMe = _board.sideToMove != _myColor;
    if (!claimerIsMe) return;
    // 双方同时判定终局时后发方会被服务端拒（state 已 ended）→ 409 静默
    // （幂等语义，对齐 chess _claimEnd）；其余错误提示但不回滚判定。
    _room.declareEnd(_reasonName(st.reason)).catchError((Object e) {
      if (e is RelayV3Exception && e.statusCode == 409) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('终局上报失败: $e')),
        );
      }
      return;
    });
  }

  String _reasonName(DraughtsEndReason r) {
    switch (r) {
      case DraughtsEndReason.noPieces:
        return 'noPieces';
      case DraughtsEndReason.noMoves:
        return 'noMoves';
      case DraughtsEndReason.threefoldRepetition:
        return 'threefold';
      case DraughtsEndReason.kingVsKing:
        return 'kingVsKing';
      case DraughtsEndReason.kingMoveLimit:
        return 'kingMoveLimit';
      default:
        return 'noMoves';
    }
  }

  // ── 交互 ──

  void _onTapSquare(int index) {
    if (!_isMyTurn) return;
    final piece = _board.pieceAt(index);

    // 点自己的子 → 选中并显示落点
    if (piece != null && piece.color == _myColor) {
      final mine = _myLegalMoves.where((m) => m.from == index).toList();
      setState(() {
        _selected = index;
        _targets = mine.map((m) => m.to).toSet();
      });
      return;
    }

    // 点落点 → 执行
    if (_selected != null && _targets.contains(index)) {
      final candidates =
          _myLegalMoves.where((m) => m.from == _selected && m.to == index);
      if (candidates.isEmpty) return;
      final move = candidates.first;
      _playMove(move);
      return;
    }

    setState(() {
      _selected = null;
      _targets = const {};
    });
  }

  Future<void> _playMove(DraughtsMove move) async {
    final next = applyMoveSimple(_board, move);
    // 预计算走后 FEN，给 [_applySnapshot] 做 echo 识别（避免重复响）。
    final nextFen = fenFromBoardState(next);
    setState(() {
      _selected = null;
      _targets = const {};
      _lastPath = move.path.toSet();
      _sendLock = true; // 发送期间不响应本地输入
      _pendingLocalFen = nextFen;
    });
    // 自己的走子立刻响（不等服务端调和，零延迟反馈）；吃子手换吃子音。
    if (move.isCapture) {
      PieceSound.instance.playCapture();
    } else {
      PieceSound.instance.play();
    }
    try {
      await _room.move(move, next);
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        // CAS 版本不匹配 → 拉最新快照（服务端状态优先，本地乐观局面被覆盖）。
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
      if (mounted) setState(() => _sendLock = false);
    }
  }

  // ── 动作 ──

  /// 准备 ACK：立即本地置 _ackedLocally（按钮变"已准备 ✓"）再发；
  /// 快照回写后由 lobby/ready 分支清标记。幂等（已点再点忽略）。
  Future<void> _ack() async {
    if (_ackedLocally) return;
    setState(() => _ackedLocally = true);
    try {
      await _room.ack();
    } catch (_) {
      if (mounted) setState(() => _ackedLocally = false);
    }
  }

  /// host 点「开始对局」（DEAL）—— 把 ready 推 playing。
  Future<void> _deal() async {
    if (_dealLock || !_isHost) return;
    setState(() => _dealLock = true);
    try {
      await _room.deal();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('开局失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _dealLock = false);
    }
  }

  /// 房主改执子色（SET_RULES）—— 服务端清 ready、回 lobby。
  Future<void> _applyColorRules(DraughtsColorChoice choice) async {
    if (_setRulesLock || !_isHost) return;
    final raw = switch (choice) {
      DraughtsColorChoice.hostWhite => 'w',
      DraughtsColorChoice.hostBlack => 'b',
      DraughtsColorChoice.random => 'random',
    };
    // random 在服务端即时解析，无法本地比对，总是发送。
    final current = DraughtsRoom.hostColor(_snap);
    final currentRaw = current == DraughtsColor.black ? 'b' : 'w';
    if (choice != DraughtsColorChoice.random && raw == currentRaw) return;

    setState(() {
      _setRulesLock = true;
      _ackedLocally = false;
    });
    try {
      await _room.setRules(hostColor: raw);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('改规则失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _setRulesLock = false);
    }
  }

  /// 房主「再来一局」（RESET）—— sendLock + 失败 snackbar（对齐 chess _reset）。
  Future<void> _reset() async {
    if (_sendLock || !_isHost) return;
    setState(() => _sendLock = true);
    try {
      await _room.reset();
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
      if (mounted) setState(() => _sendLock = false);
    }
  }

  /// 认输：AlertDialog 二次确认（draughts 比 chess 多一层保护，保留），
  /// 确认后 sendLock + 失败 snackbar（对齐 chess _resign）。
  Future<void> _confirmResign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('认输'),
        content: const Text('确定要认输吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('认输'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_sendLock) return;
    setState(() => _sendLock = true);
    try {
      await _room.resign();
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
      if (mounted) setState(() => _sendLock = false);
    }
  }

  // ── 议和（DRAW offer → accept/decline，对齐 chess）──

  /// 对方是否已挂起议和 offer（对手 id 按角色 host↔guest 推，不按颜色推）。
  bool get _opponentOffered {
    final snap = _snap;
    if (snap == null) return false;
    final oppId = _isHost ? DraughtsRoom.guestId(snap) : DraughtsRoom.hostId(snap);
    if (oppId == null) return false;
    return DraughtsRoom.drawOffers(snap)[oppId] == true;
  }

  /// 我方是否已挂起议和 offer（等待对方回应）。
  bool get _iOffered =>
      DraughtsRoom.drawOffers(_snap)[widget.handle.transport.deviceId] == true;

  /// 点「议和」：无对方 offer → 发 DRAW_OFFER；对方已 offer → 直接接受。
  Future<void> _drawOffer() => _sendGuardedAction(
        type: _opponentOffered ? 'DRAW_ACCEPT' : 'DRAW_OFFER',
        waitingHint: _opponentOffered
            ? null
            : const SnackBar(content: Text('已发送议和请求，等待对方回应')),
      );

  /// 对方议和 offer 时点「拒绝」→ DRAW_DECLINE。
  Future<void> _drawDecline() =>
      _sendGuardedAction(type: 'DRAW_DECLINE');

  // ── 悔棋（UNDO offer → accept/decline，对齐 chess）──

  /// 对方是否已挂起悔棋 offer（对手 id 按角色 host↔guest 推）。
  bool get _opponentUndoOffered {
    final snap = _snap;
    if (snap == null) return false;
    final oppId = _isHost ? DraughtsRoom.guestId(snap) : DraughtsRoom.hostId(snap);
    if (oppId == null) return false;
    return DraughtsRoom.undoOffers(snap)[oppId] == true;
  }

  /// 我方是否已挂起悔棋 offer（等待对方回应）。
  bool get _iUndoOffered =>
      DraughtsRoom.undoOffers(_snap)[widget.handle.transport.deviceId] == true;

  /// 我能否请求悔棋：对局中 + 自己至少走过一手
  /// （先手方 moves ≥ 1；后手方 moves ≥ 2。与服务端 UNDO_OFFER 门一致。
  /// 先手方 = host_color == initial_side 的一方 —— host 未必先手）。
  bool get _canRequestUndo {
    final snap = _snap;
    if (snap == null || snap.state != 'playing' || _endDeclared) return false;
    final n = _history.length;
    final iAmFirst = _isHost ==
        (DraughtsRoom.hostColor(snap) == DraughtsRoom.initialSide(snap));
    return iAmFirst ? n >= 1 : n >= 2;
  }

  /// 点「悔棋」：无对方 offer → 发 UNDO_OFFER；对方已 offer → 接受
  /// （服务端 pop 1~2 手，快照回来自动重放回退棋盘）。409 → 调和。
  Future<void> _undoRequest() => _sendGuardedAction(
        type: _opponentUndoOffered ? 'UNDO_ACCEPT' : 'UNDO_OFFER',
        waitingHint: _opponentUndoOffered
            ? null
            : const SnackBar(content: Text('已发送悔棋请求，等待对方回应')),
        reconcileOn409: true,
      );

  /// 对方悔棋 offer 时点「拒绝」→ UNDO_DECLINE。
  Future<void> _undoDecline() => _sendGuardedAction(type: 'UNDO_DECLINE');

  // ── 动作发送模板（chess 同款）：sendLock + 双 catch + snackbar ──

  /// [waitingHint] 非 null 且发送的不是"接受对方 offer"时提示等待；
  /// [reconcileOn409] 时 409 → 拉最新快照调和（悔棋/走子这类期望回退的场景）。
  Future<void> _sendGuardedAction({
    required String type,
    SnackBar? waitingHint,
    bool reconcileOn409 = false,
  }) async {
    if (_sendLock) return;
    // 发送前存决策值（await 后读 getter 可能已被新快照翻转）。
    final isAccept = type.endsWith('_ACCEPT');
    setState(() => _sendLock = true);
    try {
      await _room.handle.applyAction(type: type, params: const {});
      if (!isAccept && waitingHint != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(waitingHint);
      }
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409 && reconcileOn409) {
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
      if (mounted) setState(() => _sendLock = false);
    }
  }

  // ── 手动刷新（fetchSnapshot UI 反馈，对齐 chess）──

  /// 带 UI 反馈的 fetchSnapshot —— AppBar 按钮 spinner 化。
  /// 心跳（RoomHandle 内部 20s 周期）已在跑；这里暴露给"怀疑卡了"的应急场景。
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

  /// 离开房间并 pop 回大厅（对齐 ChessRoomPage._leaveAndPop）。
  Future<void> _leaveAndPop() async {
    final nav = Navigator.of(context);
    await widget.onLeave();
    if (!mounted) return;
    if (nav.canPop()) nav.pop();
  }

  // ── 渲染 ──

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    if (snap == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('国际跳棋（联机）')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final state = snap.state;
    final isLobbyReady = state == 'lobby' || state == 'ready';
    final scheme = Theme.of(context).colorScheme;

    // 拦截 AppBar 返回 / 系统返回：必须先 leave 再 pop，避免幽灵座位。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _leaveAndPop();
      },
      child: Scaffold(
        // 准备态跟壳层浅底（同 chess / sudoku）；对局中保持默认（棋盘主导）。
        backgroundColor: isLobbyReady ? scheme.surfaceContainerLowest : null,
        appBar: AppBar(
          backgroundColor: isLobbyReady ? scheme.surfaceContainerLowest : null,
          elevation: 0,
          title: Text('房间 ${snap.roomCode}'),
          actions: [
            // 手动刷新按钮：强制拉一次最新快照（带 UI 反馈）。心跳已经在跑，
            // 这里只暴露给"我怀疑卡了"的应急场景（对齐 chess）。
            IconButton(
              icon: _fetching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _fetching ? null : _fetchSnapshotWithFeedback,
              tooltip: '刷新快照',
            ),
            IconButton(
              tooltip: '退出',
              icon: const Icon(Icons.logout),
              onPressed: _leaveAndPop,
            ),
          ],
        ),
        body: SafeArea(
          // 阶段派发：lobby/ready → 准备卡；playing → 棋盘；ended → 棋盘 + 浮卡。
          child: isLobbyReady
              ? _buildLobbyReady()
              : Stack(
                  children: [
                    Column(
                      children: [
                        _statusBar(context),
                        Expanded(child: _boardArea()),
                        if (state == 'playing') _playingBar(context),
                      ],
                    ),
                    if (state == 'ended') _endedOverlay(context),
                  ],
                ),
        ),
      ),
    );
  }

  // ── lobby / ready 准备卡（对齐 game_ready_style 模板，同 chess / sudoku）──

  Widget _buildLobbyReady() {
    final snap = _snap!;
    final scheme = Theme.of(context).colorScheme;
    final code = snap.roomCode;
    final hostId = DraughtsRoom.hostId(snap);
    final players = DraughtsRoom.players(snap);
    final readyMap = DraughtsRoom.readyMap(snap);
    final myId = widget.handle.transport.deviceId;
    final phase = snap.state;
    final bothReady = phase == 'ready';
    final hostIsWhite = DraughtsRoom.hostColor(snap) == DraughtsColor.white;
    final iAmReady = bothReady || _ackedLocally || readyMap[myId] == true;
    final canAck = !bothReady && players.length >= 2;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: GameReadyFloatCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                bothReady ? '双方已就绪' : '等待对手',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              const GameReadyTitleRule(),
              const SizedBox(height: 16),
              GameReadyRoomCodeChip(code: code),
              const SizedBox(height: 20),

              // 房间规则：host 可改执子色；guest 只读。改规则会清 ready。
              DraughtsRoomRulesPanel(
                editable: _isHost && !_setRulesLock,
                hostColor: hostIsWhite ? 'w' : 'b',
                onChanged: _isHost ? _applyColorRules : null,
              ),
              const SizedBox(height: 12),

              ...players.entries.map((e) {
                final isMe = e.key == myId;
                final isReady = bothReady || readyMap[e.key] == true;
                final isHostSide = e.key == hostId;
                final sideIsWhite = isHostSide ? hostIsWhite : !hostIsWhite;
                final label =
                    '${e.value}${isMe ? "  (我)" : ""} · ${isHostSide ? "房主" : "对手"} · ${sideIsWhite ? "执白" : "执黑"}';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    GameReadyAvatar(label: e.value, isReady: isReady),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 15,
                          fontWeight:
                              isMe ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                    GameReadyStatusBadge(isReady: isReady),
                  ]),
                );
              }),

              if (players.length < 2) ...[
                const SizedBox(height: 16),
                Text(
                  '把房间号发给朋友',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],

              if (players.length >= 2) ...[
                const SizedBox(height: 22),
                if (bothReady)
                  _isHost
                      ? FilledButton(
                          onPressed: _dealLock ? null : _deal,
                          style: GameReadyCtaStyle.filled(scheme),
                          child: const Text(
                            '开始游戏 ▸',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                            ),
                          ),
                        )
                      : Text(
                          '等待房主开始…',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                            letterSpacing: 1,
                          ),
                        )
                else if (iAmReady)
                  FilledButton(
                    onPressed: null,
                    style: GameReadyCtaStyle.filled(scheme),
                    child: const Text(
                      '已准备 ✓',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                  )
                else
                  OutlinedButton(
                    onPressed: canAck ? _ack : null,
                    style: GameReadyCtaStyle.outlined(scheme),
                    child: const Text(
                      '准备好了',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBar(BuildContext context) {
    final players = DraughtsRoom.players(_snap);
    final meName = players[_me] ?? '我';
    final oppId = _isHost ? DraughtsRoom.guestId(_snap) : DraughtsRoom.hostId(_snap);
    final oppName = oppId == null ? '等待加入…' : (players[oppId] ?? '对手');
    final disconnected = DraughtsRoom.disconnectedPlayers(_snap);
    final oppOffline = oppId != null && disconnected[oppId] == true;

    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: [
          _colorDot(_myColor),
          const SizedBox(width: 6),
          Text('$meName（我）', style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          if (oppOffline)
            Text('对手已离线',
                style: TextStyle(color: scheme.error, fontSize: 12)),
          const SizedBox(width: 8),
          Text(oppName, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: 6),
          _colorDot(draughtsOpposite(_myColor)),
        ],
      ),
    );
  }

  Widget _colorDot(DraughtsColor c) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c == DraughtsColor.white
              ? const Color(0xFFF7F3E8)
              : const Color(0xFF2A2A2E),
          border: Border.all(color: const Color(0xFF8A7B5C)),
        ),
      );

  Widget _boardArea() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: DraughtsBoard(
            state: _board,
            flipped: _myColor == DraughtsColor.black,
            selectedSquare: _selected,
            legalTargets: _targets,
            lastMovePath: _lastPath,
            interactive: _isMyTurn && !_sendLock,
            onTapSquare: _onTapSquare,
          ),
        ),
      ),
    );
  }

  // ── playing 操作条（轮次 / 强制吃子提示 / 投降·悔棋·议和三按钮）──

  Widget _playingBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dt = Theme.of(context).textTheme;
    final turnText = _isMyTurn ? '轮到你走' : '等待对手…';
    final mustCapture = _isMyTurn &&
        kDefaultDraughtsEngine.legalMoves(_board).any((m) => m.isCapture);
    // 本地引擎已判终局但服务端快照未切 ended 的窗口期 → 按钮全禁用。
    final gameOver = _endDeclared;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(turnText, style: dt.titleMedium),
          if (mustCapture)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('有吃子，必须吃（最长吃子）',
                  style: dt.bodySmall?.copyWith(color: scheme.error)),
            ),
          const SizedBox(height: 10),
          _actionButtons(context, gameOver: gameOver),
        ],
      ),
    );
  }

  /// 操作条三分支（对齐 chess）：对方悔棋 offer → 接受/拒绝行 + 投降；
  /// 对方议和 offer → 接受/拒绝行 + 悔棋入口；平时 → 投降/悔棋/议和 Wrap。
  Widget _actionButtons(BuildContext context, {required bool gameOver}) {
    if (_opponentUndoOffered) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
            onPressed: gameOver ? null : _confirmResign,
            icon: const Icon(Icons.flag, size: 18),
            label: const Text('投降'),
          ),
        ],
      );
    }
    if (_opponentOffered) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
        ],
      );
    }
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: gameOver ? null : _confirmResign,
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
    );
  }

  /// 悔棋入口按钮（平时操作条 / 对方议和 offer 时第二行共用）。
  ///
  /// 禁用条件：本地已判终局 / 自己一手未走（[_canRequestUndo]，与服务端
  /// UNDO_OFFER 门一致）/ 已挂起自己的悔棋 offer（防重复发）。
  Widget _undoEntryButton({required bool gameOver}) {
    final waiting = _iUndoOffered;
    return OutlinedButton.icon(
      onPressed: (gameOver || waiting || !_canRequestUndo) ? null : _undoRequest,
      icon: const Icon(Icons.undo, size: 18),
      label: Text(waiting ? '等待对方回应' : '悔棋'),
    );
  }

  // ── ended 覆盖层：棋盘保留 + 居中浮卡（对齐 chess 终局组合方式）──

  Widget _endedOverlay(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (title, subtitle) = _resultTexts();
    return Positioned.fill(
      child: Container(
        color: scheme.surface.withValues(alpha: 0.75),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: GameReadyFloatCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 15,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                if (_isHost)
                  FilledButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('再来一局'),
                    style: GameReadyCtaStyle.filled(scheme),
                  )
                else
                  Text(
                    '等待房主重开…',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                  ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _leaveAndPop,
                  style: GameReadyCtaStyle.outlined(scheme),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 终局（标题，副标题）：副标题为终局原因的视角中立描述。
  (String, String) _resultTexts() {
    final status = DraughtsRoom.status(_snap);
    final winner = DraughtsRoom.winner(_snap);
    final reason = DraughtsRoom.endReason(_snap);
    final reasonText = switch (reason) {
      'kingVsKing' => '王对王',
      'threefold' => '三次重复局面',
      'agreement' => '双方同意',
      'noPieces' => '无子可动',
      'noMoves' => '无棋可走',
      'kingMoveLimit' => '王步数超限',
      _ => '',
    };
    if (status == 'draw') return ('和棋', reasonText);
    if (status == 'resigned') {
      return winner == _me ? ('你赢了', '对手认输') : ('你认输了', '对手获胜');
    }
    if (status == 'win') {
      if (winner == _me) return ('你赢了！', reasonText);
      if (winner == null) return ('对局结束', '');
      return ('对手获胜', reasonText);
    }
    return ('对局结束', '');
  }
}
