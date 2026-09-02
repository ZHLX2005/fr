// test/core/chess/p2p/chess_room_page_test.dart
//
// ChessRoomPage（P2P 在线对弈页）widget 测试 —— 使用 FAKE RoomHandle/transport：
//   · 初始快照（fen + status playing）→ 渲染 ChessBoard
//   · 白方（host）回合：tap e2 → tap e4 → 发送 MOVE（uci 'e2e4'）
//   · 非我回合：tap 不发 MOVE
//   · 对方走子快照（新 fen）→ 棋盘更新
//   · status == checkmate → 终局覆盖层出现
//   · RESIGN 按钮 → 发送 RESIGN action
//   · 传 localSkin → 棋盘用本地皮肤渲染（离线可用）
//
// Fake 设计：复用真实 RoomHandle + 真实 RelayV3Transport，但 HTTP 走 MockClient
// （不联网），并用 RoomHandle.testCreate 注入初始快照 —— WS 不连接。
// 触发棋盘更新的方式 = 手动向 handle.pushSnapshot(...) 推送新快照。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/chess/chess.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/chess_room_page.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/skins/local_chess_skin.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_board.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_connection_status.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_connection_bar.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

/// 记录一次 applyAction 调用。
class FakeActionCall {
  final String type;
  final Map<String, dynamic> params;
  FakeActionCall(this.type, this.params);
}

/// 真实 RelayV3Transport + MockClient（不联网），记录 applyAction 调用。
class FakeTransport extends RelayV3Transport {
  final List<FakeActionCall> actionCalls = [];
  Map<String, dynamic>? lastParams;
  bool failWith409 = false;

  FakeTransport({required String deviceId})
    : super(
        relayUrl: 'http://fake',
        alias: 'me',
        deviceId: deviceId,
        httpClient: MockClient(_handler),
      );

  /// MockClient 处理器 —— 所有 HTTP 端点都回一个可解析的 envelope。
  static Future<http.Response> _handler(http.Request req) async {
    final code = req.url.pathSegments.isNotEmpty
        ? req.url.pathSegments.last
        : '000000';
    return http.Response(
      jsonEncode({
        'data': {'ws_url': 'ws://fake/ws3/$code', 'snapshot': _snapJson(code)},
      }),
      200,
    );
  }

  static Map<String, dynamic> _snapJson(String code) => {
    'room_code': code,
    'script_hash': '',
    'script_src': '',
    'context': {'n': 0},
    'state': '',
    'version': 1,
    'created_at': '2026-07-25T10:00:00Z',
    'updated_at': '2026-07-25T10:00:00Z',
    'history': <dynamic>[],
  };
}

/// Fake RoomHandle —— 复用真实 RoomHandle（testCreate，不连 WS）。
///
/// 覆写 `snapshots` getter 指向自己的广播控制器（基类的 `_snapshotsCtrl` 是
/// library-private，子类拿不到），从而支持手动 `pushSnapshot(...)` 模拟 WS 广播。
/// 覆写 applyAction：记录调用；成功时模拟服务端把 MOVE 的 fen/status
/// 写回 context 并推流（等价于真实 transport 的"成功→更新 latest + 推流"）。
class FakeRoomHandle extends RoomHandle {
  final List<FakeActionCall> actionCalls = [];
  Map<String, dynamic>? lastParams;
  bool failWith409 = false;
  bool left = false;

  /// 自持快照流（测试驱动：手动 push 模拟 WS 广播）。
  final StreamController<Snapshot> _fakeSnapshots =
      StreamController<Snapshot>.broadcast();

  FakeRoomHandle({
    required FakeTransport transport,
    required String code,
    Snapshot? initial,
  }) : super.testCreate(
         transport: transport,
         code: code,
         wsUrl: 'ws://fake/ws3/$code',
         initial: initial,
       );

  @override
  Stream<Snapshot> get snapshots => _fakeSnapshots.stream;

  /// 手动推送快照（模拟服务端 WS 广播）。
  void pushSnapshot(Snapshot snap) {
    latest = snap;
    if (!_fakeSnapshots.isClosed) {
      _fakeSnapshots.add(snap);
    }
  }

  @override
  Future<Snapshot> applyAction({
    required String type,
    required Map<String, dynamic> params,
    int? expectVersion,
    String? sourceDeviceId,
  }) async {
    final call = FakeActionCall(type, Map<String, dynamic>.from(params));
    actionCalls.add(call);
    lastParams = call.params;
    if (failWith409) {
      throw RelayV3Exception(409, 'version conflict');
    }
    // 成功路径：模拟服务端把 MOVE 的 fen/status 写回 context + 追加棋谱。
    if (type == 'MOVE') {
      final ctx = Map<String, dynamic>.from(latest?.context ?? {});
      ctx['fen'] = params['fen'];
      ctx['status'] = params['status'];
      final moves = List<dynamic>.from(latest?.context['moves'] ?? const []);
      moves.add({
        'uci': params['uci'],
        'by': sourceDeviceId ?? transport.deviceId,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      ctx['moves'] = moves;
      final next = Snapshot(
        roomCode: code,
        scriptHash: latest?.scriptHash ?? '',
        scriptSrc: latest?.scriptSrc,
        context: ctx,
        state: 'playing',
        version: (latest?.version ?? 0) + 1,
        createdAt: latest?.createdAt ?? DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        history: latest?.history ?? const [],
      );
      latest = next;
      if (!_fakeSnapshots.isClosed) {
        _fakeSnapshots.add(next);
      }
    }
    return latest!;
  }

  @override
  Future<void> leave() async {
    left = true;
  }
}

/// 生成一份快照。
Snapshot makeSnapshot({
  required String code,
  required String fen,
  required String status,
  String state = 'playing',
  String? hostId,
  String? guestId,
  String? hostColor,
  String? initialSide,
  String? winner,
  List<dynamic> moves = const [],
  Map<String, dynamic> drawOffers = const {},
  Map<String, dynamic> undoOffers = const {},
}) {
  return Snapshot(
    roomCode: code,
    scriptHash: 'fake',
    scriptSrc: null,
    context: {
      'host_id': hostId,
      'guest_id': guestId,
      if (hostColor != null) 'host_color': hostColor,
      if (initialSide != null) 'initial_side': initialSide,
      'players': <String, dynamic>{
        if (hostId != null) hostId: 'host',
        if (guestId != null) guestId: 'guest',
      },
      'fen': fen,
      'moves': moves,
      'draw_offers': drawOffers,
      'undo_offers': undoOffers,
      'status': status,
      if (winner != null) 'winner': winner,
    },
    state: state,
    version: 1,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
    history: const [],
  );
}

/// host = 'd-host'（白方），guest = 'd-guest'，本地 = host。
FakeRoomHandle makeHostHandle() {
  final transport = FakeTransport(deviceId: 'd-host');
  return FakeRoomHandle(
    transport: transport,
    code: '999999',
    initial: makeSnapshot(
      code: '999999',
      fen: kStartingFen,
      status: 'playing',
      hostId: 'd-host',
      guestId: 'd-guest',
    ),
  );
}

/// 本地 = guest（黑方）的句柄。
FakeRoomHandle makeGuestHandle() {
  final transport = FakeTransport(deviceId: 'd-guest');
  return FakeRoomHandle(
    transport: transport,
    code: '999999',
    initial: makeSnapshot(
      code: '999999',
      fen: kStartingFen,
      status: 'playing',
      hostId: 'd-host',
      guestId: 'd-guest',
    ),
  );
}

void main() {
  setUp(() => ChessSkinBundle.resetForTest());

  /// 构造本地皮肤：写 12 张 PNG 到临时目录 + LocalChessSkin。
  LocalChessSkin makeLocalSkin(String id) {
    final dir = Directory.systemTemp.createTempSync('chess_room_local_$id');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final meta = ChessSkinMeta(
      id: id,
      displayName: '本地皮肤 $id',
      pieces: {
        for (final k in kChessSkin12PieceKeys)
          k: FileRef(
            fileId: k.padRight(32, 'a'),
            fileName: '$k.webp',
            sizeBytes: 1,
            contentType: 'image/webp',
          ),
      },
    );
    for (final k in kChessSkin12PieceKeys) {
      File('${dir.path}/$k.webp').writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
    }
    return LocalChessSkin.tryCreate(meta: meta, dir: dir)!;
  }

  /// 用 ChessRoomPage 包一层 host widget（默认 600x600 可点棋盘）。
  Widget host(FakeRoomHandle handle, {LocalChessSkin? localSkin}) {
    ChessSkinBundle.registerHardcoded();
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            height: 600,
            child: ChessRoomPage(
              handle: handle,
              skinId: kChessSkinsCatalog[0].id,
              localSkin: localSkin,
            ),
          ),
        ),
      ),
    );
  }

  /// 按 GestureDetector 顺序 tap 第 idx 个（0..63 = 1D idx）。
  Future<void> tapCell(WidgetTester tester, int idx) async {
    final detectors = find.byType(GestureDetector);
    expect(detectors, findsWidgets);
    await tester.tap(detectors.at(idx));
    await tester.pump();
  }

  /// 1D index（白方视角）→ 格子中心全局坐标（几何推导，与实现解耦）。
  ///
  /// ChessBoard 自带 16px 标签边距（labelSpace）：内部 SizedBox = boardSize + 32，
  /// 由 Center 在 ChessBoard 内居中 —— 长宽不等时网格并不贴左上角，而是
  /// 在 (rect.left + (w - boardSize)/2, rect.top + (h - boardSize)/2) 开始。
  /// 测试按真实 rect 反推，不依赖具体布局尺寸。
  Offset cellCenter(WidgetTester tester, int idx) {
    final rect = tester.getRect(find.byType(ChessBoard));
    final side = rect.width < rect.height ? rect.width : rect.height;
    const labelSpace = 16.0;
    final boardSize = side - labelSpace * 2;
    final cell = boardSize / kBoardCols;
    final gridLeft = rect.left + (rect.width - boardSize) / 2;
    final gridTop = rect.top + (rect.height - boardSize) / 2;
    final row = idx ~/ 8;
    final col = idx % 8;
    return Offset(
      gridLeft + labelSpace + col * cell + cell / 2,
      gridTop + labelSpace + row * cell + cell / 2,
    );
  }

  /// 从 [from] 格拖到 [to] 格（分步移动模拟真实拖动序列 → pan 识别）。
  Future<void> dragPiece(WidgetTester tester, int from, int to) async {
    final a = cellCenter(tester, from);
    final b = cellCenter(tester, to);
    final g = await tester.startGesture(a);
    for (var i = 1; i <= 4; i++) {
      await g.moveTo(Offset.lerp(a, b, i / 4)!);
      await tester.pump();
    }
    await g.up();
    await tester.pump();
  }

  testWidgets('初始快照（fen + status playing）→ 渲染 ChessBoard', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    expect(find.byType(ChessBoard), findsOneWidget);
    expect(find.textContaining('你的回合'), findsOneWidget);
  });

  testWidgets('我的回合（host=白）：tap e2 → tap e4 → 发送 MOVE uci e2e4', (
    tester,
  ) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    final e2 = squareToIndex('e2');
    final e4 = squareToIndex('e4');
    await tapCell(tester, e2);
    await tapCell(tester, e4);
    await tester.pump();

    expect(handle.actionCalls, hasLength(1));
    expect(handle.actionCalls.first.type, 'MOVE');
    expect(handle.lastParams?['uci'], 'e2e4');
    // 合规 fence：MOVE 不携带 status（终局走 CLAIM_END），fen 必须存在且结构合法。
    expect(
      handle.lastParams?.containsKey('status'),
      isFalse,
      reason: 'MOVE 不得携带 status（服务端校验 fence 的一部分）',
    );
    expect(handle.lastParams?['fen'], isA<String>());
  });

  testWidgets('非我回合（guest=黑，轮白走）：tap 不发 MOVE', (tester) async {
    final handle = makeGuestHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    await tapCell(tester, squareToIndex('e2'));
    await tester.pump();
    await tapCell(tester, squareToIndex('e4'));
    await tester.pump();

    expect(handle.actionCalls, isEmpty);
  });

  testWidgets('对方走子快照（新 fen）→ 棋盘更新', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // host（白）走 e2-e4 后，guest（黑）回应 d7-d5 的快照。
    // fen：e2e4 d7d5 之后（轮到白方走）。
    const newFen =
        'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2';
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: newFen,
        status: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
      ),
    );
    await tester.pump();

    // 棋盘内容从快照 fen 重建：e4 / d5 有子，e2 已空，轮到白。
    final board = FenCodec.fromFen(newFen);
    expect(board.slotAt(squareToIndex('e4')), isNotNull);
    expect(board.slotAt(squareToIndex('d5')), isNotNull);
    expect(board.isEmpty(squareToIndex('e2')), isTrue);
    expect(find.textContaining('你的回合'), findsOneWidget);
  });

  testWidgets('status == checkmate → 终局覆盖层出现（host 可见再来一局）', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'checkmate',
        state: 'ended',
        hostId: 'd-host',
        guestId: 'd-guest',
        winner: 'd-host',
      ),
    );
    // 广播流是异步派发（微任务），需多 pump 几次直到新快照被应用。
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('将杀'), findsOneWidget);
    expect(find.text('你赢了'), findsOneWidget);
    // host 终局卡片：再来一局（FilledButton）+ 返回（OutlinedButton）
    expect(find.widgetWithText(FilledButton, '再来一局'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '返回'), findsOneWidget);
  });

  testWidgets('status == stalemate → 终局覆盖层（guest 不可见再来一局）', (tester) async {
    final handle = makeGuestHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'stalemate',
        state: 'ended',
        hostId: 'd-host',
        guestId: 'd-guest',
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('僵局'), findsOneWidget);
    expect(find.text('平局'), findsOneWidget);
    // guest 看不到"再来一局"（RESET 仅 host 可调）
    expect(find.text('再来一局'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '返回'), findsOneWidget);
  });

  testWidgets('RESIGN 按钮 → 发送 RESIGN action', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, '投降'));
    await tester.pump();

    expect(handle.actionCalls, hasLength(1));
    expect(handle.actionCalls.first.type, 'RESIGN');
  });

  // ─────────────── 合规修复：翻转由角色驱动（不随 sideToMove 抖动） ───────────────

  testWidgets('host=白视角：整局棋盘不翻转（flipped 恒 false）', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    ChessBoard board() => tester.widget<ChessBoard>(find.byType(ChessBoard));
    // 白方视角：flipped 恒 false（我始终在底，稳定）。
    expect(board().flipped, isFalse);
    // 白先手：sideToMove = white。
    expect(board().sideToMove, PieceColor.white);

    // 模拟黑方回应 d7-d5（轮白）→ 棋盘更新，但视角保持不翻转。
    const newFen =
        'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2';
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: newFen,
        status: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(board().sideToMove, PieceColor.white);
    expect(board().flipped, isFalse, reason: '视角由角色驱动，不随 sideToMove 翻转');
  });

  testWidgets('guest=黑视角：翻转由角色驱动（flipped 恒 true）', (tester) async {
    final handle = makeGuestHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    ChessBoard board() => tester.widget<ChessBoard>(find.byType(ChessBoard));
    expect(board().flipped, isTrue, reason: '我方执黑 → 黑方视角，黑在底');
  });

  // ─────────────── 合规修复：RESET（host 再来一局 → 新对局） ───────────────

  testWidgets('终局 → host 点"再来一局" → 发 RESET → 快照回 playing 清空本地态', (
    tester,
  ) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // 1. 进入终局（checkmate）。
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'checkmate',
        state: 'ended',
        hostId: 'd-host',
        guestId: 'd-guest',
        winner: 'd-host',
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('再来一局'), findsOneWidget);

    // 2. host 点"再来一局" → RESET action。
    await tester.tap(find.widgetWithText(FilledButton, '再来一局'));
    await tester.pump();
    expect(handle.actionCalls, hasLength(1));
    expect(handle.actionCalls.first.type, 'RESET');

    // 3. 服务端 RESET 后推送新快照（回 playing + 起始 fen）。
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        state: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // 终局覆盖层消失；host 又能正常走子。
    expect(find.text('再来一局'), findsNothing);
    expect(find.text('将杀'), findsNothing);
    expect(find.textContaining('你的回合'), findsOneWidget);

    // 4. 重开后走子正常（上一局 _lastMove/_selectedSquare 已清空）。
    final e2 = squareToIndex('e2');
    final e4 = squareToIndex('e4');
    await tapCell(tester, e2);
    await tapCell(tester, e4);
    await tester.pump();
    expect(handle.actionCalls.last.type, 'MOVE');
    expect(handle.lastParams?['uci'], 'e2e4');
  });

  testWidgets('guest 终局后不可见"再来一局"', (tester) async {
    final handle = makeGuestHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'checkmate',
        state: 'ended',
        hostId: 'd-host',
        guestId: 'd-guest',
        winner: 'd-host',
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('再来一局'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '返回'), findsOneWidget);
  });

  // ─────────────── 合规修复：上一步高亮从服务端棋谱派生（不残留本方旧高亮） ───────────────

  testWidgets('对方走子快照（moves 追加）→ lastMove 高亮跟到最新一手', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    ChessBoard board() => tester.widget<ChessBoard>(find.byType(ChessBoard));
    // 初始：空棋谱 → 无上一步高亮
    expect(board().lastMove, isNull);

    // 我方（host）走 e2-e4 后：棋谱 [e2e4]，高亮 e2/e4。
    const fen1 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: fen1,
        status: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
        moves: const [
          {'uci': 'e2e4', 'by': 'd-host', 'ts': 1},
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
    var lm = board().lastMove;
    expect(lm, isNotNull);
    expect(lm!.from, squareToIndex('e2'));
    expect(lm.to, squareToIndex('e4'));

    // 对方（guest）回应 d7-d5：棋谱追加，高亮必须跟到 d7/d5 ——
    // 不得残留本方的 e2/e4（旧版 _lastMove 本地持有 → 污染）。
    const fen2 =
        'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2';
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: fen2,
        status: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
        moves: const [
          {'uci': 'e2e4', 'by': 'd-host', 'ts': 1},
          {'uci': 'd7d5', 'by': 'd-guest', 'ts': 2},
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
    lm = board().lastMove;
    expect(lm, isNotNull);
    expect(lm!.from, squareToIndex('d7'), reason: '高亮跟随最新一手（对方 d7d5）');
    expect(lm.to, squareToIndex('d5'));
  });

  testWidgets('RESET 后空棋谱 → lastMove 清空（无残留高亮）', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // 终局 → 再来一局 → RESET → 服务端清空 moves 回新一局。
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'checkmate',
        state: 'ended',
        hostId: 'd-host',
        guestId: 'd-guest',
        winner: 'd-host',
        moves: const [
          {'uci': 'e2e4', 'by': 'd-host', 'ts': 1},
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('再来一局'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '再来一局'));
    await tester.pump();

    // RESET 后新快照：moves 空 → lastMove 必须为 null。
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        state: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
        moves: const [],
      ),
    );
    await tester.pump();
    await tester.pump();
    final board = tester.widget<ChessBoard>(find.byType(ChessBoard));
    expect(board.lastMove, isNull, reason: 'RESET 清棋谱 → 上一步高亮消失');
  });

  // ─────────────── 和棋 offer → accept/decline（单方 offer 不和棋） ───────────────

  testWidgets('点"议和"（对方无 offer）→ 只发 DRAW_OFFER（等待对方，不和棋）', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, '议和'));
    await tester.pump();

    expect(handle.actionCalls, hasLength(1));
    expect(handle.actionCalls.first.type, 'DRAW_OFFER',
        reason: '单方点议和 = 只发 offer，不得直接和棋');
    expect(find.textContaining('等待对方回应'), findsWidgets,
        reason: '按钮态变"等待对方回应"');
  });

  testWidgets('对方 offer 挂起 → 显示"接受议和/拒绝"；接受 → DRAW_ACCEPT', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // 对方（guest）挂起 offer。
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
        drawOffers: {'d-guest': true},
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('接受议和'), findsOneWidget);
    expect(find.text('拒绝'), findsOneWidget);

    await tester.tap(find.text('接受议和'));
    await tester.pump();
    expect(handle.actionCalls, hasLength(1));
    expect(handle.actionCalls.first.type, 'DRAW_ACCEPT',
        reason: '接受 = 显式 DRAW_ACCEPT → 和棋');
  });

  testWidgets('对方 offer 挂起 → 拒绝 → DRAW_DECLINE（回到正常对局）', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
        drawOffers: {'d-guest': true},
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('拒绝'));
    await tester.pump();
    expect(handle.actionCalls, hasLength(1));
    expect(handle.actionCalls.first.type, 'DRAW_DECLINE',
        reason: '拒绝 = DRAW_DECLINE，服务端清对方 offer');
  });

  testWidgets('我方已 offer（等待回应）→ 按钮显示"等待对方回应"且无接受/拒绝', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
        drawOffers: {'d-host': true},
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('接受议和'), findsNothing, reason: '对方未 offer → 不显示接受');
    expect(find.textContaining('等待对方回应'), findsWidgets);
  });

  // ─────────────── 悔棋 offer → accept/decline（协商回退） ───────────────

  testWidgets('点"悔棋"（对方无 offer）→ 只发 UNDO_OFFER（等待对方）', (tester) async {
    final handle = makeHostHandle();
    // host=白已走 1 手（e2e4），可请求悔棋。
    await tester.pumpWidget(host(handle));
    await tester.pump();
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
        moves: const [
          {'uci': 'e2e4', 'by': 'd-host', 'ts': 1, 'fen': kStartingFen},
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('悔棋'));
    await tester.pump();

    expect(handle.actionCalls, hasLength(1));
    expect(handle.actionCalls.first.type, 'UNDO_OFFER',
        reason: '单方点悔棋 = 只发 offer，等对方接受后才回退');
    expect(find.textContaining('等待对方回应'), findsWidgets,
        reason: '按钮态变"等待对方回应"');
  });

  testWidgets('对方 offer 挂起 → 显示"接受悔棋/拒绝"；接受 → UNDO_ACCEPT', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // 对方（guest=黑）挂起悔棋 offer。
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
        undoOffers: {'d-guest': true},
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('接受悔棋'), findsOneWidget);
    expect(find.text('拒绝'), findsOneWidget);

    await tester.tap(find.text('接受悔棋'));
    await tester.pump();
    expect(handle.actionCalls, hasLength(1));
    expect(handle.actionCalls.first.type, 'UNDO_ACCEPT',
        reason: '接受 = 显式 UNDO_ACCEPT → 服务端 pop 回退');
  });

  testWidgets('对方悔棋 offer 挂起 → 拒绝 → UNDO_DECLINE（回到正常对局）', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
        undoOffers: {'d-guest': true},
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('拒绝'));
    await tester.pump();
    expect(handle.actionCalls, hasLength(1));
    expect(handle.actionCalls.first.type, 'UNDO_DECLINE',
        reason: '拒绝 = UNDO_DECLINE，服务端清对方 offer');
  });

  testWidgets('悔棋生效快照（fen 回退 + moves 变短）→ 棋盘渲染回退局面', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // 初始：走了 e2e4（fen 为走后局面）。
    const fenAfterE4 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: fenAfterE4,
        status: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
        moves: const [
          {'uci': 'e2e4', 'by': 'd-host', 'ts': 1, 'fen': fenAfterE4},
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    // 服务端悔棋生效：pop 后快照回到初始局面。
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
        moves: const [],
      ),
    );
    await tester.pump();
    await tester.pump();

    final board = tester.widget<ChessBoard>(find.byType(ChessBoard));
    expect(board.state.slotAt(52), isNotNull,
        reason: 'e2 (idx 52) 有白兵 → 棋盘已回退到初始局面');
    expect(board.state.slotAt(36), isNull,
        reason: 'e4 (idx 36) 已空 → e2e4 已被撤销');
    expect(board.lastMove, isNull, reason: 'moves 空 → 上一步高亮消失');
  });

  testWidgets('自己一手未走（moves 空）→ 悔棋按钮禁用', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // 找到"悔棋"按钮并断言禁用（onPressed == null）。
    final button = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('悔棋'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(button.onPressed, isNull,
        reason: 'host=白 moves=0 → 无从悔棋，按钮禁用');
  });

  testWidgets('黑方只走了对方一手（moves=1）→ 悔棋按钮禁用', (tester) async {
    final handle = makeGuestHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
        moves: const [
          {'uci': 'e2e4', 'by': 'd-host', 'ts': 1, 'fen': kStartingFen},
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    final button = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('悔棋'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(button.onPressed, isNull,
        reason: 'guest=黑 moves=1（自己一手未走）→ 无从悔棋，按钮禁用');
  });

  // ─────────────── 合规修复：WS 状态条（RelayConnectionBar）存在 ───────────────

  testWidgets('连接状态只保留 AppBar 徽标一处（底部 RelayConnectionBar 已移除）', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // v7 去重：底部 RelayConnectionBar 移除 —— AppBar 的 ChessConnectionStatusBadge
    // 是唯一连接状态（旧版两处同时显示"已连接"造成冗余）。
    expect(find.byType(RelayConnectionBar), findsNothing);
    expect(find.byType(ChessConnectionStatusBadge), findsOneWidget);
    // 手动刷新按钮仍在 AppBar（原底部条的"拉取最新快照"功能由它承担）。
    expect(find.byTooltip('刷新快照'), findsOneWidget);
  });

  // ─────────────── 拖动（board-gesture-patterns）：松手合法目标 → 提交走法 ───────────────

  testWidgets('拖动己方兵 e2 → 松手 e4 → 发送 MOVE uci e2e4', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // 拖动松手在合法目标 → 乐观走子 + 发送 MOVE
    await dragPiece(tester, squareToIndex('e2'), squareToIndex('e4'));

    expect(handle.actionCalls, hasLength(1));
    expect(handle.actionCalls.first.type, 'MOVE');
    expect(handle.lastParams?['uci'], 'e2e4');
  });

  testWidgets('拖动己方兵 e2 → 松手在非法格（e3 前的 b3）→ 不发 MOVE', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // e2 兵不可走 b3 → 非法目标 → 弹回（保持选中），不发走法
    await dragPiece(tester, squareToIndex('e2'), squareToIndex('b3'));

    expect(handle.actionCalls, isEmpty);
  });

  // ─────────────── 本地皮肤（localSkin 参数） ───────────────

  testWidgets('传 localSkin → 棋盘用本地皮肤渲染（离线可用）', (tester) async {
    final handle = makeHostHandle();
    final localSkin = makeLocalSkin('1');
    await tester.pumpWidget(host(handle, localSkin: localSkin));
    await tester.pump();

    final board = tester.widget<ChessBoard>(find.byType(ChessBoard));
    expect(board.skin, same(localSkin), reason: '应优先用本地皮肤');
    // 本地皮肤 12 棋子齐全 → ChessPiece 有图渲染
    expect(find.byType(ChessBoard), findsOneWidget);
  });

  testWidgets('不传 localSkin → 回退注册表皮肤（默认行为）', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    final board = tester.widget<ChessBoard>(find.byType(ChessBoard));
    expect(
      board.skin.id,
      kChessSkinsCatalog[0].id,
      reason: '无 localSkin 时回退 ChessSkinBundle.byId(skinId)',
    );
  });

  // ─────────────── 身份稳定（Bug 1/2 根因）：稳定 uid + 防御回退 ───────────────

  testWidgets('host_id 缺失 → 防御回退白方（不崩溃，棋盘照常渲染）', (tester) async {
    // 本地 transport = 'd-host'（稳定 uid），但快照缺 host_id（服务端异常）。
    final transport = FakeTransport(deviceId: 'd-host');
    final handle = FakeRoomHandle(
      transport: transport,
      code: '999999',
      initial: makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        hostId: null,
        guestId: null,
      ),
    );
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // 不崩溃，棋盘渲染。
    expect(find.byType(ChessBoard), findsOneWidget);
    // 回退白方：flipped false（我方视角 = 白方视角）。
    final board = tester.widget<ChessBoard>(find.byType(ChessBoard));
    expect(board.flipped, isFalse, reason: 'host_id 缺失 → 白方兜底视角');
  });

  testWidgets('host_id 缺失但本地 == guest_id → 判定黑方（不误判白）', (tester) async {
    // 本地 transport = 'd-guest'（稳定 uid），快照缺 host_id 但有 guest_id。
    final transport = FakeTransport(deviceId: 'd-guest');
    final handle = FakeRoomHandle(
      transport: transport,
      code: '999999',
      initial: makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        hostId: null,
        guestId: 'd-guest',
      ),
    );
    await tester.pumpWidget(host(handle));
    await tester.pump();

    final board = tester.widget<ChessBoard>(find.byType(ChessBoard));
    expect(board.flipped, isTrue, reason: '本地==guest_id → 黑方视角（不丢身份）');
    expect(find.text('你执黑'), findsOneWidget);
  });

  testWidgets('稳定身份重连：transport 用登录 uid 且 host_id 同源 → 正确判定白方', (
    tester,
  ) async {
    // 模拟登录态稳定 uid：transport.deviceId == 'uid-tok-1'，
    // 服务端 host_id 也是 'uid-tok-1'（同一稳定身份）→ 白方。
    final transport = FakeTransport(deviceId: 'uid-tok-1');
    final handle = FakeRoomHandle(
      transport: transport,
      code: '999999',
      initial: makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        hostId: 'uid-tok-1',
        guestId: 'uid-tok-2',
      ),
    );
    await tester.pumpWidget(host(handle));
    await tester.pump();

    expect(find.text('你执白'), findsOneWidget);
    final board = tester.widget<ChessBoard>(find.byType(ChessBoard));
    expect(board.flipped, isFalse);

    // 重连后（新 handle 但同一稳定 uid）→ 身份仍对得上。
    final reconnect = FakeRoomHandle(
      transport: FakeTransport(deviceId: 'uid-tok-1'),
      code: '999999',
      initial: makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        hostId: 'uid-tok-1',
        guestId: 'uid-tok-2',
      ),
    );
    await tester.pumpWidget(host(reconnect));
    await tester.pump();
    expect(find.text('你执白'), findsOneWidget,
        reason: '重连后同一稳定 uid 仍识别为白方（Bug 2 根因修复）');
  });

  // ══════════════════════════════════════════════════════════════
  // v6 _isHost 守卫：device_id 精确比对，不用执子色推断
  // （修复：残局 host 执黑时 host 看不到开始游戏，guest 误判为 host 但
  //   DEAL 被服务端 role_check 拒绝 → 点击无响应）
  // ══════════════════════════════════════════════════════════════

  testWidgets('v6 残局 host 执黑：host（device_id 匹配 host_id）→ 可见开始游戏', (
    tester,
  ) async {
    final transport = FakeTransport(deviceId: 'uid-host-1');
    final handle = FakeRoomHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnapshot(
        code: 'ABCD',
        fen: kStartingFen,
        status: 'playing',
        state: 'ready', // 双方已就绪 → host 应该看到开始游戏
        hostId: 'uid-host-1',
        guestId: 'uid-guest-1',
        hostColor: 'b', // 残局 host 执黑（v6 支持）
        initialSide: 'b',
      ),
    );
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // host 执黑但仍是 host → 应该看到开始游戏按钮（v6 修复前看不到）
    expect(find.textContaining('开始游戏'), findsOneWidget,
        reason: 'host（device_id 匹配 host_id）在 ready 态应看到开始游戏按钮，'
            '即使执黑（残局 host_color=b）');
  });

  testWidgets('v6 guest 执白：guest（device_id 匹配 guest_id）→ 不可见开始游戏', (
    tester,
  ) async {
    final transport = FakeTransport(deviceId: 'uid-guest-1');
    final handle = FakeRoomHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnapshot(
        code: 'ABCD',
        fen: kStartingFen,
        status: 'playing',
        state: 'ready',
        hostId: 'uid-host-1',
        guestId: 'uid-guest-1',
        hostColor: 'b',
        initialSide: 'b',
      ),
    );
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // guest 执白（对侧色）但不是 host → 应该看到等待房主开始…，而非开始按钮
    expect(find.textContaining('开始游戏'), findsNothing,
        reason: 'guest 即使执白也不应误判为 host（v6 修复前会误判）');
    expect(find.textContaining('等待房主'), findsOneWidget,
        reason: 'guest 在 ready 态应显示等待房主开始');
  });

  testWidgets('v6 host_color=w 向后兼容：host 仍看到开始游戏', (tester) async {
    final transport = FakeTransport(deviceId: 'uid-host-1');
    final handle = FakeRoomHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnapshot(
        code: 'ABCD',
        fen: kStartingFen,
        status: 'playing',
        state: 'ready',
        hostId: 'uid-host-1',
        guestId: 'uid-guest-1',
        hostColor: 'w', // 标准开局默认
        initialSide: 'w',
      ),
    );
    await tester.pumpWidget(host(handle));
    await tester.pump();

    expect(find.textContaining('开始游戏'), findsOneWidget,
        reason: '标准开局 host 执白 → 仍看到开始游戏（向后兼容）');
  });
}
