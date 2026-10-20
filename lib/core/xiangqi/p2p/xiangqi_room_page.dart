// lib/core/xiangqi/p2p/xiangqi_room_page.dart
//
// 中国象棋对局房页：准备 / 对战 / 终局三态。
//
// ## 流程
//
//   lobby（双方 ACK）→ ready（host DEAL）→ playing → ended（CLAIM_END / RESIGN / DRAW）
//   终局后 host 可 RESET 回 lobby 再来一局。
//
// ## 准备卡（lobby / ready）
//
//   对齐 chess / draughts 的 game_ready_style 模板：标题 + 房间号胶囊 +
//   房间规则面板（执子色，host SET_RULES，改完清 ready 回 lobby）+
//   玩家行（头像 / 就绪徽章 / 执子标签）+ CTA 三态。
//   准备态不显示棋盘（同 chess / draughts）。
//
// ## 交互（playing）
//
//   点选中己方子 → 高亮该子全部合法落点 → 点落点执行该手。
//   走法合法性由本地引擎判定（走后自己将不被攻击，含将帅照面）——
//   **不需要二次确认**（象棋落子不可逆但可悔棋，与 draughts 同款直落）。
//
//   被将军时：轮到走的一方的将/帅画红环，操作条提示「将军」。
//
// ## 操作条（playing，对齐 chess / draughts 模式）
//
//   AppBar：手动刷新（fetchSnapshot + spinner 反馈）/ 退出。
//   底部操作条：认输 / 悔棋 / 求和三按钮；对方挂起悔棋（求和）offer 时
//   切换为「接受 + 拒绝」双按钮行。悔棋 offer 流 UNDO_OFFER → 对方
//   UNDO_ACCEPT（服务端 pop 1~2 手）/ UNDO_DECLINE。
//
// ## 音效（PieceSound 单例）
//
//   initState 预加载；自己走子即时响；对手走子按快照 fen diff 响，
//   _pendingLocalFen 标记吃掉自己的 echo 防重响。
//
// ## 终局复盘（ended，对齐 chess / draughts 回放模式）
//
//   终局卡「复盘」进入（棋谱非空才显示）：一次性预计算 states[0..n] +
//   每步起止点，步进 O(1)；回放条（XiangqiReplayBar）接管底部、终局卡隐藏、
//   棋盘只读；非 ended 快照（RESET 重开）自动退出回放；返回键一次退回放。
//
// ## 对话（BoardChatOverlay：chatRing + emojiRing，对齐 chess / draughts）
//
//   Lua 脚本已拼入共享 chat / emoji 段（RESET 时一并清理）；页面在棋盘区
//   挂 BoardChatOverlay 左上角浮层（💬 入口 + 最新消息预览 + composer 双 tab）。
//   表情包走 EmojiBundle.forGame('xiangqi')（common 作用域兜底）；
//   回放中隐藏，掉线 / 终局禁发。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../api/goframe/goframe_config.dart';
import '../../game_audio/piece_sound.dart';
import '../../game_kit/chat/board_chat_overlay.dart';
import '../../game_kit/chat/chat_event.dart';
import '../../game_kit/emoji/emoji_bundle.dart';
import '../../game_kit/lobby/game_ready_style.dart';
import '../../game_kit/skin/file_resolver.dart';
import '../../net_engine/relay_v3/relay_connection_status_badge.dart';
import '../constants/xiangqi_constants.dart';
import '../engine/fen_codec.dart';
import '../engine/make_move.dart';
import '../engine/move_generator.dart';
import '../engine/xiangqi_engine.dart';
import '../models/board_state.dart';
import '../models/game_status.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../widgets/xiangqi_board.dart';
import '../widgets/xiangqi_replay_bar.dart';
import 'xiangqi_room.dart';
import 'widgets/xiangqi_room_rules_panel.dart';

class XiangqiRoomPage extends StatefulWidget {
  const XiangqiRoomPage({
    super.key,
    required this.handle,
    required this.onLeave,
  });

  final RoomHandle handle;
  final Future<void> Function() onLeave;

  @override
  State<XiangqiRoomPage> createState() => _XiangqiRoomPageState();
}

class _XiangqiRoomPageState extends State<XiangqiRoomPage> {
  StreamSubscription<Snapshot>? _sub;
  StreamSubscription<WSCloseEvent>? _closeSub;
  late final XiangqiRoom _room;

  Snapshot? _snap;
  List<XiangqiMoveRecord> _history = const [];
  XiangqiBoardState _board = XiangqiBoardState.initial();

  int? _selected;
  Set<int> _targets = const {};

  /// 上一手的起点 / 终点（棋盘高亮）。
  int? _lastFrom;
  int? _lastTo;

  bool _ackedLocally = false;
  bool _endDeclared = false;
  bool _setRulesLock = false;
  bool _dealLock = false;

  /// 动作发送锁（走子 / 认输 / 悔棋 / 求和 / 重开 / 刷新共用，防双击）。
  bool _sendLock = false;

  /// 手动拉取快照进行中（AppBar 刷新按钮 spinner）。
  bool _fetching = false;

  /// 上一份快照的 fen —— 对手走子音的差分基准（首份快照 null 不响）。
  String? _prevFen;

  /// 自己刚走的走后 fen —— 快照 echo 识别（已在本地响过，防重响）。
  String? _pendingLocalFen;

  /// true = 收到 WS 瞬断事件（code 0）→ 全屏重连 overlay；下一份快照清除。
  bool _wsOffline = false;

  /// true = 服务端 disconnected 表含自己 → 顶部红 banner + 冻结棋盘输入。
  bool _isMeDisconnected = false;

  // ── 终局复盘（对齐 chess / draughts 回放模式：父层持状态，条只渲染）──

  /// 自动播放步进间隔（chess 同款 800ms）。
  static const Duration _kReplayTickInterval = Duration(milliseconds: 800);

  bool _replayMode = false;
  int _replayIndex = 0;
  bool _replayPlaying = false;
  Timer? _replayTimer;

  /// 预计算的局面子序列（states[0] = 初始局面，states[n] = 终局）与
  /// 每步的起止点（paths[i] = 通向 states[i] 那一手的 from/to）。
  List<XiangqiBoardState> _replayStates = const [];
  List<(int?, int?)> _replayPaths = const [];

  // ── 对话（BoardChatOverlay：chatRing + emojiRing，对齐 chess / draughts）──
  EmojiBundle _emojiBundle = EmojiBundle.empty();
  final FileResolver _emojiFileResolver =
      const PublicFileResolver(baseUrl: GoframeConfig.baseUrl);
  bool _emojiBundleLoading = false;
  bool _emojiBundleLoaded = false;

  List<ChatEvent> get _chatEvents {
    final snap = _snap;
    if (snap == null) return const [];
    return mergedChatEventsFromSnapshot(snap.context);
  }

  /// 懒加载表情包：common + xiangqi 两作用域合并（无专属包时 common 兜底）。
  Future<void> _ensureEmojiBundle() async {
    if (_emojiBundleLoading || _emojiBundleLoaded) return;
    _emojiBundleLoading = true;
    try {
      final b = await EmojiBundle.forGame(
        'xiangqi',
        defaultBaseUrl: GoframeConfig.baseUrl,
        fileResolver: _emojiFileResolver,
      );
      if (!mounted) return;
      setState(() {
        _emojiBundle = b;
        _emojiBundleLoaded = true;
      });
      // 后台预取图片，面板/预览优先走本地缓存。
      unawaited(b.prefetchToCache(
        resolver: _emojiFileResolver,
        baseUrl: GoframeConfig.baseUrl,
      ));
    } finally {
      _emojiBundleLoading = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _room = XiangqiRoom(widget.handle);
    _snap = widget.handle.latest;
    _applySnapshot(_snap);
    _sub = widget.handle.snapshots.listen(_onSnapshot);
    // WS 瞬断 / 终端关闭事件（对齐 chess / draughts 断线三件套）。
    _closeSub = widget.handle.closeEvents.listen(_onCloseEvent);
    // 懒加载表情包（对话浮层用）。
    _ensureEmojiBundle();
    // 预加载落子音，消除首次落子的加载延迟（PieceSound 单例跨页复用）。
    PieceSound.instance.preload();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _closeSub?.cancel();
    _replayTimer?.cancel();
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
    setState(() => _applySnapshot(s));
    // 快照仍处于 lobby/ready：本地乐观 ACK 已无意义（服务端 ready 表是权威，
    // SET_RULES / RESET 会清空 ready），清掉本地标记 —— 对齐 chess / draughts。
    if ((s.state == 'lobby' || s.state == 'ready') && _ackedLocally) {
      setState(() => _ackedLocally = false);
    }
    if (s.state == 'lobby') _endDeclared = false;
    _maybeDeclareEnd();
  }

  /// WS 关闭事件（对齐 chess / draughts）：瞬断（code 0）→ 全屏重连 overlay，
  /// 下一份快照清除；终端关闭（被踢 / 房间过期 / 慢消费）→ 提示 + 退出入口。
  void _onCloseEvent(WSCloseEvent event) {
    if (!mounted) return;
    if (event.code == 0) {
      setState(() => _wsOffline = true);
      return;
    }
    setState(() => _wsOffline = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(WSCloseCode.describe(event.code)),
      action: SnackBarAction(label: '退出', onPressed: _leaveAndPop),
    ));
  }

  void _applySnapshot(Snapshot? s) {
    _snap = s;
    // 回放中收到非 ended 快照（host RESET 重开 / 状态回退）→ 自动退出回放
    // 回实况：复盘针对已结束的那一局，新对局优先（对齐 chess / draughts）。
    if (_replayMode && s?.state != 'ended') _clearReplay();
    _history = XiangqiRoom.rebuildHistory(s);
    // 断线状态同步（对齐 chess / draughts）：服务端 disconnected 表是权威；
    // 收到任意快照 = WS 已恢复 → 清瞬断 overlay。
    _isMeDisconnected =
        XiangqiRoom.disconnectedPlayers(s)[widget.handle.transport.deviceId] ==
            true;
    if (_wsOffline) _wsOffline = false;
    // 落子音（对齐 chess / draughts 的差分模板，多一道对局态门）：
    //   · 首份快照（_prevFen == null）→ 页面刚进，不响。
    //   · fen 未变（同状态重推）→ 不响。
    //   · fen == _pendingLocalFen → 自己走子的服务端 echo（本地已响）→ 不响。
    //   · 非对局态（RESET 回 lobby / 终局快照）→ 不响（防准备态凭空响一声；
    //     悔棋回退 state 仍 playing，不受影响）。
    final fen = XiangqiRoom.fen(s);
    if (s != null &&
        s.state == 'playing' &&
        fen != null &&
        fen.isNotEmpty &&
        _prevFen != null &&
        fen != _prevFen) {
      if (fen != _pendingLocalFen) {
        // 对手走子：靠 FEN 棋子数差分判断是否吃子（服务端只存记号 + FEN，
        // 重放出来的 move.captured 恒为 null，无法直接读）。
        if (_pieceCountOfFen(fen) < _pieceCountOfFen(_prevFen!)) {
          PieceSound.instance.playCapture();
        } else {
          PieceSound.instance.play();
        }
      }
    }
    if (fen != null && fen.isNotEmpty) _prevFen = fen;
    _pendingLocalFen = null; // 每次快照清一次（echo 已消费 / 其它情况丢弃）。
    _board = XiangqiRoom.rebuildBoard(
      _history,
      initialFen: XiangqiRoom.initialFen(s),
    );
    _selected = null;
    _targets = const {};
    if (_history.isEmpty) {
      _lastFrom = null;
      _lastTo = null;
    } else {
      final last = _history.last;
      final m = XiangqiMove.fromUci(last.uci);
      _lastFrom = m?.from;
      _lastTo = m?.to;
    }
  }

  // ── 角色 ──

  String get _me => widget.handle.transport.deviceId;
  XiangqiColor get _myColor => XiangqiRoom.myColor(widget.handle, _snap);
  bool get _isHost => _me == XiangqiRoom.hostId(_snap);
  bool get _isPlaying => _snap?.state == 'playing';
  bool get _isMyTurn =>
      _isPlaying && _board.sideToMove == _myColor && !_endDeclared;

  /// 我能不能发这个 action？
  ///
  /// 权限表来自服务端（Lua `c.action_permissions`）—— 客户端按钮的可点性
  /// **一律走这里**，零特判代码（对齐 gomoku / reversi / jungle / chess 同款 helper，
  /// 见 relay-lua-state-machine skill 的 A03 ref）。
  bool _canPerform(String action) =>
      XiangqiRoom.canPerform(action, _snap, isHost: _isHost);

  List<XiangqiMove> get _myLegalMoves => _isMyTurn
      ? kDefaultXiangqiEngine.legalMoves(_board)
      : const [];

  /// 被将军的将/帅所在交点（轮到走的一方被将军才有）。
  int? get _checkSquare {
    if (!_isPlaying) return null;
    final side = _board.sideToMove;
    if (!xiangqiIsInCheck(_board, side)) return null;
    return _board.generalSquareOf(side);
  }

  /// 操作条是否提示「将军」（对手被将军）。
  bool get _opponentInCheck {
    if (!_isPlaying) return false;
    final side = _board.sideToMove;
    if (side == _myColor) return false;
    return xiangqiIsInCheck(_board, side);
  }

  // ── 终局上报 ──

  /// FEN 局面串里的棋子数（用于对手走子的吃子音判定）。
  ///
  /// 中国象棋 FEN 的局面段只含棋子字母与空格数字（`KABNRCPkabnrcp`），
  /// 因此统计这些字母即可得到存活棋子数。
  static int _pieceCountOfFen(String fen) {
    final position = fen.split(' ').first;
    var n = 0;
    for (final ch in position.split('')) {
      if ('KABNRCPkabnrcp'.contains(ch)) n++;
    }
    return n;
  }

  void _maybeDeclareEnd() {
    if (_endDeclared || !_isPlaying) return;
    final keys = XiangqiRoom.rebuildPositionHistory(
      _history,
      initialFen: XiangqiRoom.initialFen(_snap),
    );
    final st = XiangqiRoom.checkStatus(_board, keys);
    if (!st.isOver) return;
    _endDeclared = true;
    // 只有"刚走完的一方"能声明（= 非当前走子方）
    final claimerIsMe = _board.sideToMove != _myColor;
    if (!claimerIsMe) return;
    // 双方同时判定终局时后发方会被服务端拒（state 已 ended）→ 409 静默
    // （幂等语义，对齐 chess / draughts _claimEnd）；其余错误提示但不回滚判定。
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

  String _reasonName(XiangqiEndReason r) {
    switch (r) {
      case XiangqiEndReason.checkmate:
        return 'checkmate';
      case XiangqiEndReason.stalemate:
        return 'stalemate';
      default:
        return 'checkmate';
    }
  }

  // ── 交互 ──

  void _onTapPoint(int index) {
    if (!_isMyTurn || _isMeDisconnected || _sendLock) return;
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
      _playMove(candidates.first);
      return;
    }

    setState(() {
      _selected = null;
      _targets = const {};
    });
  }

  Future<void> _playMove(XiangqiMove move) async {
    final next = applyXiangqiMove(_board, move).nextState;
    // 预计算走后 FEN，给 [_applySnapshot] 做 echo 识别（避免重复响）。
    final nextFen = fenFromBoardState(next);
    setState(() {
      _selected = null;
      _targets = const {};
      _lastFrom = move.from;
      _lastTo = move.to;
      _sendLock = true; // 发送期间不响应本地输入
      _pendingLocalFen = nextFen;
    });
    // 自己的走子立刻响（不等服务端调和，零延迟反馈）。
    // 象棋吃子高频（车/炮/马/兵）—— 吃子手换吃子音（走法生成器已填 captured）。
    if (move.captured != null) {
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
    if (_dealLock || !_canPerform('DEAL')) return;
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
  Future<void> _applyColorRules(XiangqiColorChoice choice) async {
    if (_setRulesLock || !_canPerform('SET_RULES')) return;
    final raw = switch (choice) {
      XiangqiColorChoice.hostRed => 'r',
      XiangqiColorChoice.hostBlack => 'b',
      XiangqiColorChoice.random => 'random',
    };
    // random 在服务端即时解析，无法本地比对，总是发送。
    final current = XiangqiRoom.hostColor(_snap);
    final currentRaw = current == XiangqiColor.black ? 'b' : 'r';
    if (choice != XiangqiColorChoice.random && raw == currentRaw) return;

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

  /// 房主「再来一局」（RESET）—— sendLock + 失败 snackbar（对齐 chess / draughts _reset）。
  Future<void> _reset() async {
    if (_sendLock || !_canPerform('RESET')) return;
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

  /// 认输：AlertDialog 二次确认，确认后 sendLock + 失败 snackbar
  /// （对齐 draughts _confirmResign）。
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

  // ── 求和（DRAW offer → accept/decline，对齐 chess / draughts）──

  /// 对方是否已挂起求和 offer（对手 id 按角色 host↔guest 推，不按颜色推）。
  bool get _opponentOffered {
    final snap = _snap;
    if (snap == null) return false;
    final oppId = _isHost ? XiangqiRoom.guestId(snap) : XiangqiRoom.hostId(snap);
    if (oppId == null) return false;
    return XiangqiRoom.drawOffers(snap)[oppId] == true;
  }

  /// 我方是否已挂起求和 offer（等待对方回应）。
  bool get _iOffered =>
      XiangqiRoom.drawOffers(_snap)[widget.handle.transport.deviceId] == true;

  /// 点「求和」：无对方 offer → 发 DRAW_OFFER；对方已 offer → 直接接受。
  Future<void> _drawOffer() => _sendGuardedAction(
        type: _opponentOffered ? 'DRAW_ACCEPT' : 'DRAW_OFFER',
        waitingHint: _opponentOffered
            ? null
            : const SnackBar(content: Text('已发送求和请求，等待对方回应')),
      );

  /// 对方求和 offer 时点「拒绝」→ DRAW_DECLINE。
  Future<void> _drawDecline() =>
      _sendGuardedAction(type: 'DRAW_DECLINE');

  // ── 悔棋（UNDO offer → accept/decline，对齐 chess / draughts）──

  /// 对方是否已挂起悔棋 offer（对手 id 按角色 host↔guest 推）。
  bool get _opponentUndoOffered {
    final snap = _snap;
    if (snap == null) return false;
    final oppId = _isHost ? XiangqiRoom.guestId(snap) : XiangqiRoom.hostId(snap);
    if (oppId == null) return false;
    return XiangqiRoom.undoOffers(snap)[oppId] == true;
  }

  /// 我方是否已挂起悔棋 offer（等待对方回应）。
  bool get _iUndoOffered =>
      XiangqiRoom.undoOffers(_snap)[widget.handle.transport.deviceId] == true;

  /// 我能否请求悔棋：对局中 + 棋谱够长
  /// （先手方 moves ≥ 1；后手方 moves ≥ 2。与服务端 UNDO_OFFER 门一致。
  /// 先手方 = host_color == initial_side 的一方 —— host 未必先手）。
  bool get _canRequestUndo {
    final snap = _snap;
    if (snap == null || snap.state != 'playing' || _endDeclared) return false;
    final n = _history.length;
    final iAmFirst = _isHost ==
        (XiangqiRoom.hostColor(snap) == XiangqiRoom.initialSide(snap));
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

  // ── 动作发送模板（chess / draughts 同款）：sendLock + 双 catch + snackbar ──

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

  // ── 对话动作（BoardChatOverlay；仅网络层，toast 由浮层处理，对齐 chess / draughts）──

  /// 发送文字（CHAT action）。
  Future<void> _handleSendText(String text) async {
    try {
      await widget.handle.applyAction(
        type: 'CHAT',
        params: {
          'text': text,
          'alias': widget.handle.transport.alias,
        },
      );
    } on RelayV3Exception catch (e) {
      debugPrint('xiangqi_room_page: CHAT send failed: ${e.statusCode} ${e.body}');
      rethrow;
    }
  }

  /// 发送 emoji（EMOJI action）。
  Future<void> _handleSendEmoji(String emojiId) async {
    if (_emojiBundle.byId[emojiId] == null) return;
    try {
      await widget.handle.applyAction(
        type: 'EMOJI',
        params: {'emoji_id': emojiId},
      );
    } on RelayV3Exception catch (e) {
      debugPrint(
          'xiangqi_room_page: EMOJI send failed: ${e.statusCode} ${e.body}');
      rethrow;
    }
  }

  // ── 手动刷新（fetchSnapshot UI 反馈，对齐 chess / draughts）──

  /// 带 UI 反馈的 fetchSnapshot —— AppBar 按钮 spinner 化。
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
        appBar: AppBar(title: const Text('中国象棋（联机）')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final state = snap.state;
    final isLobbyReady = state == 'lobby' || state == 'ready';
    final scheme = Theme.of(context).colorScheme;

    // 拦截 AppBar 返回 / 系统返回：必须先 leave 再 pop，避免幽灵座位。
    // 回放中按返回：一次返回退回放、二次返回退房（对齐 chess 回放优先级）。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_replayMode) {
          _exitReplay();
          return;
        }
        await _leaveAndPop();
      },
      child: Scaffold(
        // 键盘不得挤 body：对话 composer 是棋盘区 absolute 浮层（对齐 chess / draughts）。
        resizeToAvoidBottomInset: false,
        // 准备态跟壳层浅底（同 chess / draughts / sudoku）；对局中保持默认（棋盘主导）。
        backgroundColor: isLobbyReady ? scheme.surfaceContainerLowest : null,
        appBar: AppBar(
          backgroundColor: isLobbyReady ? scheme.surfaceContainerLowest : null,
          elevation: 0,
          // 连接徽标（圆点 + 文字 + 重连 spinner）需要比默认 48 宽的 leading 槽。
          leadingWidth: 86,
          leading: RelayConnectionStatusBadge(handle: widget.handle),
          title: Text('房间 ${snap.roomCode}'),
          actions: [
            // 手动刷新按钮：强制拉一次最新快照（带 UI 反馈）。心跳已经在跑，
            // 这里只暴露给"我怀疑卡了"的应急场景（对齐 chess / draughts）。
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
          // 最外层 Stack 挂断线可见层（重连 overlay / 掉线 banner，对齐 chess / draughts）。
          child: Stack(
            children: [
              Positioned.fill(
                child: isLobbyReady
                    ? _buildLobbyReady()
                    : Stack(
                        children: [
                          Column(
                            children: [
                              _statusBar(context),
                              Expanded(
                                child: Stack(
                                  children: [
                                    Positioned.fill(child: _boardArea()),
                                    // 棋盘对话浮层（左上角 pill + composer；
                                    // 回放中隐藏，对齐 chess / draughts）
                                    if (!_replayMode)
                                      Positioned.fill(
                                        child: BoardChatOverlay(
                                          events: _chatEvents,
                                          myDeviceId:
                                              widget.handle.transport.deviceId,
                                          emojiBundle: _emojiBundle,
                                          fileResolver: _emojiFileResolver,
                                          enabled: _snap?.state == 'playing' &&
                                              !_isMeDisconnected,
                                          onSendEmoji: _handleSendEmoji,
                                          onSendText: _handleSendText,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (state == 'playing') _playingBar(context),
                              // 回放条接管底部（对局条在 ended 态本就不渲染）
                              if (state == 'ended' && _replayMode)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 4, 16, 16),
                                  child: XiangqiReplayBar(
                                    index: _replayIndex,
                                    total: _history.length,
                                    playing: _replayPlaying,
                                    onToStart: () => _seekReplay(0),
                                    onStepBack: () => _stepReplay(-1),
                                    onTogglePlay: _toggleReplayPlay,
                                    onStepForward: () => _stepReplay(1),
                                    onToEnd: () => _seekReplay(_history.length),
                                    onSeek: _seekReplay,
                                    onExit: _exitReplay,
                                  ),
                                ),
                            ],
                          ),
                          // 回放中隐藏终局卡（对齐 chess / draughts：回放条接管交互）
                          if (state == 'ended' && !_replayMode)
                            _endedOverlay(context),
                        ],
                      ),
              ),
              if (_wsOffline) _buildWsOfflineOverlay(context),
              if (_isMeDisconnected && state == 'playing')
                _buildMeOfflineBanner(context),
            ],
          ),
        ),
      ),
    );
  }

  // ── lobby / ready 准备卡（对齐 game_ready_style 模板，同 chess / draughts）──

  Widget _buildLobbyReady() {
    final snap = _snap!;
    final scheme = Theme.of(context).colorScheme;
    final code = snap.roomCode;
    final hostId = XiangqiRoom.hostId(snap);
    final players = XiangqiRoom.players(snap);
    final readyMap = XiangqiRoom.readyMap(snap);
    final myId = widget.handle.transport.deviceId;
    final phase = snap.state;
    final bothReady = phase == 'ready';
    final hostIsRed = XiangqiRoom.hostColor(snap) == XiangqiColor.red;
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
              XiangqiRoomRulesPanel(
                editable: _canPerform('SET_RULES') && !_setRulesLock,
                hostColor: hostIsRed ? 'r' : 'b',
                onChanged: _canPerform('SET_RULES') ? _applyColorRules : null,
              ),
              const SizedBox(height: 12),

              ...players.entries.map((e) {
                final isMe = e.key == myId;
                final isReady = bothReady || readyMap[e.key] == true;
                final isHostSide = e.key == hostId;
                final sideIsRed = isHostSide ? hostIsRed : !hostIsRed;
                final label =
                    '${e.value}${isMe ? "  (我)" : ""} · ${isHostSide ? "房主" : "对手"} · ${sideIsRed ? "执红" : "执黑"}';
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
                  _canPerform('DEAL')
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
                    onPressed:
                        canAck && _canPerform('ACK') ? _ack : null,
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
    final players = XiangqiRoom.players(_snap);
    final meName = players[_me] ?? '我';
    final oppId = _isHost ? XiangqiRoom.guestId(_snap) : XiangqiRoom.hostId(_snap);
    final oppName = oppId == null ? '等待加入…' : (players[oppId] ?? '对手');
    final disconnected = XiangqiRoom.disconnectedPlayers(_snap);
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
          _colorDot(xiangqiOpposite(_myColor)),
        ],
      ),
    );
  }

  Widget _colorDot(XiangqiColor c) {
    // 棋子配色走棋盘 palette（唯一真相源，同 draughts 的 DraughtsBoardPalette.light）。
    final piece = XiangqiBoardPalette.light.pieceOf(c);
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: piece.disc,
        border: Border.all(color: piece.ring, width: 1.6),
      ),
    );
  }

  /// 全屏「连接断开，正在重连…」overlay —— WS 瞬断期间盖住内容，
  /// 任一快照到达即清（对齐 chess / draughts）。
  Widget _buildWsOfflineOverlay(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: ColoredBox(
        color: scheme.scrim.withValues(alpha: 0.55),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                '连接断开，正在重连…',
                // scrim 近黑，onPrimary 深色主题下是暗色调 → 固定白字保对比
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 「你已掉线」顶部 banner —— 数据源 = 服务端 disconnected 表（权威），
  /// 棋盘输入冻结由 interactive / _onTapPoint 的门承担。
  Widget _buildMeOfflineBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: scheme.error.withValues(alpha: 0.85),
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
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 终局复盘（ended；对齐 chess / draughts 回放模式）──

  /// 进入复盘：一次性构建局面子序列（states[0..n]）+ 每步起止点，步进 O(1)。
  /// 畸形 initial_fen 回退标准开局。
  void _enterReplay() {
    if (_history.isEmpty || _snap == null) return;
    XiangqiBoardState state;
    try {
      state = boardStateFromFen(XiangqiRoom.initialFen(_snap));
    } on FormatException {
      state = boardStateFromFen(kXiangqiStartingFen);
    }
    final states = <XiangqiBoardState>[state];
    final paths = <(int?, int?)>[(null, null)];
    for (final rec in _history) {
      final m = XiangqiMove.fromUci(rec.uci);
      if (m != null) {
        try {
          state = applyXiangqiMoveSimple(state, m);
        } catch (_) {
          // 坏记录：局面不变，只记起止点
        }
      }
      states.add(state);
      paths.add((m?.from, m?.to));
    }
    setState(() {
      _replayStates = states;
      _replayPaths = paths;
      _replayIndex = _history.length; // 从终局开始往回看
      _replayMode = true;
      _selected = null;
      _targets = const {};
    });
  }

  /// 退出复盘（纯字段重置不 setState —— 供 [_applySnapshot] 的快照路径复用，
  /// 对齐 chess / draughts _clearReplay）。
  void _clearReplay() {
    _replayTimer?.cancel();
    _replayTimer = null;
    _replayMode = false;
    _replayPlaying = false;
    _replayIndex = 0;
    _replayStates = const [];
    _replayPaths = const [];
  }

  /// 手动退出复放（UI 入口：回放条退出键 / 返回键）。
  void _exitReplay() {
    _clearReplay();
    setState(() {});
  }

  void _seekReplay(int i) =>
      setState(() => _replayIndex = i.clamp(0, _replayStates.length - 1));

  void _stepReplay(int delta) => _seekReplay(_replayIndex + delta);

  /// ▶/⏸ 自动播放：终局按 ▶ 从头重放（标准复盘 UX，chess 同款）。
  void _toggleReplayPlay() {
    if (_replayPlaying) {
      _replayTimer?.cancel();
      _replayTimer = null;
      setState(() => _replayPlaying = false);
      return;
    }
    if (_replayIndex >= _history.length) _seekReplay(0);
    setState(() => _replayPlaying = true);
    _replayTimer = Timer.periodic(_kReplayTickInterval, (_) => _replayTick());
  }

  void _replayTick() {
    if (!mounted) {
      _replayTimer?.cancel();
      _replayTimer = null;
      return;
    }
    if (_replayIndex >= _history.length) {
      // 播到终局：停播、播放键复位 ▶（对齐 chess / draughts）。
      _replayTimer?.cancel();
      _replayTimer = null;
      setState(() => _replayPlaying = false);
      return;
    }
    _stepReplay(1);
  }

  Widget _boardArea() {
    // 吃子视觉：选中子的落点里，可吃子的用醒目色（captureTarget）。
    final moves = _myLegalMoves;
    final captureTo = <int>{};
    for (final m in moves) {
      if (m.from == _selected && m.isCapture) captureTo.add(m.to);
    }
    final replayIndex = _replayIndex.clamp(0, _replayStates.length - 1);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          // 象棋盘 9×10（高比宽大 1 格）→ 宽上限比跳棋小一圈，
          // 避免在竖屏上顶掉操作条（对齐 chess / draughts 的排版约束）。
          constraints: const BoxConstraints(maxWidth: 460),
          child: AspectRatio(
            aspectRatio: kXiangqiBoardAspectRatio,
            child: XiangqiBoard(
              // 回放中显示层整体切换到预计算局面；实况字段（_board/_history/
              // _lastFrom/_lastTo）不动 —— 退出回放即回实况（chess 同模式）。
              state: _replayMode ? _replayStates[replayIndex] : _board,
              flipped: _myColor == XiangqiColor.black,
              selectedIndex: _selected,
              legalTargets: _targets,
              captureTargets: captureTo,
              lastMoveFrom: _replayMode ? _replayPaths[replayIndex].$1 : _lastFrom,
              lastMoveTo: _replayMode ? _replayPaths[replayIndex].$2 : _lastTo,
              checkSquare: _replayMode ? null : _checkSquare,
              interactive: _isMyTurn && !_sendLock && !_isMeDisconnected,
              onTapPoint: _onTapPoint,
            ),
          ),
        ),
      ),
    );
  }

  // ── playing 操作条（轮次 / 将军提示 / 认输·悔棋·求和三按钮）──

  Widget _playingBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dt = Theme.of(context).textTheme;
    final turnText = _isMyTurn ? '轮到你走' : '等待对手…';
    // 本地引擎已判终局但服务端快照未切 ended 的窗口期 → 按钮全禁用。
    final gameOver = _endDeclared;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(turnText, style: dt.titleMedium),
          if (_opponentInCheck)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('将军！对手须应将',
                  style: dt.bodySmall?.copyWith(color: scheme.error)),
            ),
          const SizedBox(height: 10),
          _actionButtons(context, gameOver: gameOver),
        ],
      ),
    );
  }

  /// 操作条三分支（对齐 chess / draughts）：对方悔棋 offer → 接受/拒绝行 + 认输；
  /// 对方求和 offer → 接受/拒绝行 + 悔棋入口；平时 → 认输/悔棋/求和 Wrap。
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
            label: const Text('认输'),
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
                label: const Text('接受求和'),
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
          label: const Text('认输'),
        ),
        _undoEntryButton(gameOver: gameOver),
        OutlinedButton.icon(
          onPressed: gameOver ? null : _drawOffer,
          icon: const Icon(Icons.handshake, size: 18),
          label: Text(_iOffered ? '等待对方回应' : '求和'),
        ),
      ],
    );
  }

  /// 悔棋入口按钮（平时操作条 / 对方求和 offer 时第二行共用）。
  ///
  /// 禁用条件：本地已判终局 / 棋谱不够长（[_canRequestUndo]，与服务端
  /// UNDO_OFFER 门一致）/ 已挂起自己的悔棋 offer（防重复发）。
  Widget _undoEntryButton({required bool gameOver}) {
    final waiting = _iUndoOffered;
    return OutlinedButton.icon(
      onPressed: (gameOver || waiting || !_canRequestUndo) ? null : _undoRequest,
      icon: const Icon(Icons.undo, size: 18),
      label: Text(waiting ? '等待对方回应' : '悔棋'),
    );
  }

  // ── ended 覆盖层：棋盘保留 + 居中浮卡（对齐 chess / draughts 终局组合方式）──

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
                if (_canPerform('RESET'))
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
                // 复盘入口：棋谱非空才显示（零走法对局无回放内容，同 chess / draughts）
                if (_history.isNotEmpty) ...[
                  OutlinedButton.icon(
                    onPressed: _enterReplay,
                    icon: const Icon(Icons.movie_outlined, size: 18),
                    label: const Text('复盘'),
                    style: GameReadyCtaStyle.outlined(scheme),
                  ),
                  const SizedBox(height: 12),
                ],
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
    final status = XiangqiRoom.status(_snap);
    final winner = XiangqiRoom.winner(_snap);
    final reason = XiangqiRoom.endReason(_snap);
    final reasonText = switch (reason) {
      'checkmate' => '将死',
      'stalemate' => '困毙（无子可动）',
      'agreement' => '双方同意',
      'resign' => '',
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

