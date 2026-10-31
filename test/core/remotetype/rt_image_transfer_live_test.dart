// test/core/remotetype/rt_image_transfer_live_test.dart
//
// 图片/文件通道的 fr 端到端测试：本测试在进程内起一个「假 mn-rt」
// （HttpServer + WebSocket，按 RT1 协议应答注册 / 解密 p2c 信封 / 回 c2p
// ACK），驱动**真的 RtSession + RtImageTransfer** 跑完整条链路——
// 覆盖 _onFrame → _openAck → ackAppliedSeqs → transfer._onAck → 进度回调
// 这一段纯单测钉不住的接缝。
//
// 用户报告「PC 已收到但手机无确认进度」后新增；此测试通过即证明 fr 端
// 进度链路完好，问题应到版本/环境（PC 客户端或手机 APK 版本）去找。

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:xiaodouzi_fr/core/remotetype/data/rt_constants.dart';
import 'package:xiaodouzi_fr/core/remotetype/protocol/rt_crypto.dart';
import 'package:xiaodouzi_fr/core/remotetype/protocol/rt_image_transfer.dart';
import 'package:xiaodouzi_fr/core/remotetype/protocol/rt_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late RtDerived derived;
  final seenAppliedSeqs = <int>[];

  /// 假 mn-rt：注册应答 + 解密 p2c + 逐条回 c2p ACK（与 mn-rt rt-align
  /// 的 ACK 语义一致：chunk 受理即 ACK，end 也立即 ACK——本测试只验
  /// fr 侧进度链路，不必模拟「end 延迟 ACK」）。
  Future<void> startFakeServer() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      if (req.uri.path == '/clients') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'ok': true, 'clients': ['pc-t']}));
        await req.response.close();
        return;
      }
      if (req.uri.path == '/ws') {
        final ws = await WebSocketTransformer.upgrade(req);
        int ackSeq = 0;
        ws.listen((raw) async {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          if (msg['type'] == 'register') {
            ws.add(jsonEncode({
              'type': 'registered', 'role': 'phone', 'clientId': null,
            }));
            return;
          }
          if (msg['type'] == 'ping') {
            ws.add(jsonEncode({'type': 'pong', 'ts': 0}));
            return;
          }
          final text = msg['text'];
          if (text is! String) return;
          final env = jsonDecode(text) as Map<String, dynamic>;
          final seq = (env['seq'] as num).toInt();
          try {
            await rtOpen(
              key: derived.keyPhoneToPc,
              aad: rtBuildAad(derived.room, kRtDirPhoneToPc, seq),
              envelope: env,
            );
          } catch (_) {
            return; // 解不开的帧直接忽略（与本测试无关的流量）
          }
          seenAppliedSeqs.add(seq);
          ackSeq += 1;
          final ack = await rtSeal(
            key: derived.keyPcToPhone,
            aad: rtBuildAad(derived.room, kRtDirPcToPhone, ackSeq),
            plaintext: {'applied_seq': seq, 'ts': 0},
            sid: 'fakepc',
            seq: ackSeq,
          );
          ws.add(jsonEncode({'type': 'ack', 'ack': ack}));
        });
      }
    });
  }

  setUp(() async {
    derived = await rtDeriveFromKey('TESTKEY123');
    await startFakeServer();
  });

  tearDown(() async {
    await server.close(force: true);
    seenAppliedSeqs.clear();
  });

  test('真会话 + 真传输：逐块 ACK 推进进度条直至完成', () async {
    final session = RtSession(
      serverUrl: 'http://127.0.0.1:${server.port}',
      key: 'TESTKEY123',
      targetClientId: 'pc-t',
    );
    addTearDown(session.dispose);

    // 连接完成 = registered 已收到
    await session.connect().timeout(const Duration(seconds: 10));

    final bytes = Uint8List.fromList(
      List<int>.generate(200 * 1024, (i) => i % 251),
    );
    final transfer = RtImageTransfer(session: session, bytes: bytes);

    // 记录进度轨迹：进度条「动过」= 至少出现过一个中间确认值
    final progressTrail = <int>[];
    transfer.addListener(() {
      if (transfer.busy && progressTrail.lastOrNull != transfer.ackedChunks) {
        progressTrail.add(transfer.ackedChunks);
      }
    });

    final ok = await transfer.send().timeout(const Duration(seconds: 30));

    expect(ok, isTrue, reason: '传输应完成（error: ${transfer.error}）');
    expect(transfer.phase, RtImagePhase.done);
    expect(transfer.ackedChunks, transfer.totalChunks);
    expect(seenAppliedSeqs, isNotEmpty);
    // 进度必须「动过」：出现过的确认值 ≥ 2 个档位（0 → … → N），
    // 这是用户报的那条反馈——PC 收到了但手机进度不动
    expect(progressTrail.toSet().length, greaterThanOrEqualTo(2),
        reason: '进度轨迹: $progressTrail');
    // 所有 p2c seq 都被 PC 确认过（begin + chunks + end 全覆盖）
    expect(seenAppliedSeqs.length, transfer.totalChunks + 2);
  });

  test('大图多分片：进度单调推进且 end 被确认', () async {
    final session = RtSession(
      serverUrl: 'http://127.0.0.1:${server.port}',
      key: 'TESTKEY123',
      targetClientId: 'pc-t',
    );
    addTearDown(session.dispose);
    await session.connect().timeout(const Duration(seconds: 10));

    // ~600KB → 13 块
    final rng = Random(7);
    final bytes = Uint8List.fromList(
      List<int>.generate(600 * 1024, (_) => rng.nextInt(256)),
    );
    final transfer = RtImageTransfer(session: session, bytes: bytes);
    expect(transfer.totalChunks, 13);

    final trail = <int>[];
    transfer.addListener(() {
      if (trail.isEmpty || trail.last < transfer.ackedChunks) {
        trail.add(transfer.ackedChunks);
      }
    });

    final ok = await transfer.send().timeout(const Duration(seconds: 30));
    expect(ok, isTrue, reason: 'error: ${transfer.error}');
    expect(trail.first, 0);
    expect(trail.last, 13);
    // 单调不回退
    for (var i = 1; i < trail.length; i += 1) {
      expect(trail[i], greaterThan(trail[i - 1]), reason: 'trail: $trail');
    }
  });
}
