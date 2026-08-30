import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

/// 测试替身：覆盖 connect() 为 no-op（fake 时钟环境承载不了真实 socket），
/// 记录调用次数以验证"心跳 fetch 顺带触发重连"的兜底逻辑。
class _NoConnectHandle extends RoomHandle {
  int connectCalls = 0;
  _NoConnectHandle({
    required super.transport,
    required super.code,
    required super.wsUrl,
    super.initial,
  }) : super.testCreate();

  @override
  Future<void> connect() async {
    connectCalls++;
  }
}

void main() {
  group('Snapshot.fromJson', () {
    test('parses backend wire shape', () {
      final j = {
        'room_code': '123456',
        'script_hash': 'abc',
        'script_src': 'return { on_init = function(c,p) return c end }',
        'context': {'n': 1, 'players': {'d1': 'alice'}},
        'state': 'waiting',
        'version': 7,
        'created_at': '2026-07-25T10:00:00Z',
        'updated_at': '2026-07-25T10:00:00Z',
        'history': [
          {
            'type': 'action_CHAT',
            'params': {'text': 'hi'},
            'from_state': 'waiting',
            'to_state': 'waiting',
            'at': '2026-07-25T10:00:00Z',
            'version': 7,
          },
        ],
      };
      final s = Snapshot.fromJson(j);
      expect(s.roomCode, '123456');
      expect(s.version, 7);
      expect(s.state, 'waiting');
      expect(s.context['n'], 1);
      expect(s.history.length, 1);
      expect(s.history.first.type, 'action_CHAT');
    });
  });

  group('RelayV3Transport HTTP', () {
    test('createRoom POSTs script and returns RoomHandle', () async {
      final mock = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/api/v3/relay/rooms');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['script'], contains('on_init'));
        expect(body['device_id'], 'd1');
        return http.Response(jsonEncode({
          'room_code': '111111',
          'ws_url': 'ws://x/ws3/111111',
          'snapshot': {
            'room_code': '111111',
            'script_hash': 'h',
            'script_src': '...',
            'context': {},
            'state': '',
            'version': 1,
            'created_at': '2026-07-25T10:00:00Z',
            'updated_at': '2026-07-25T10:00:00Z',
            'history': [],
          },
        }), 201);
      });
      final t = RelayV3Transport(
        relayUrl: 'http://x',
        alias: 'a',
        deviceId: 'd1',
        httpClient: mock,
      );
      final h = await t.createRoom(
        script: 'return { on_init = function(c,p) return c end }',
        initialParams: {},
      );
      expect(h.code, '111111');
      expect(h.latest?.version, 1);
    });

    test('joinRoom hits /join endpoint', () async {
      final mock = MockClient((req) async {
        expect(req.url.path, '/api/v3/relay/rooms/222222/join');
        return http.Response(jsonEncode({
          'ws_url': 'ws://x/ws3/222222',
          'snapshot': _emptySnap('222222'),
        }), 200);
      });
      final t = RelayV3Transport(
        relayUrl: 'http://x',
        alias: 'b',
        deviceId: 'd2',
        httpClient: mock,
      );
      final h = await t.joinRoom(code: '222222');
      expect(h.code, '222222');
    });

    test('_applyAction hits /actions and parses snapshot', () async {
      final mock = MockClient((req) async {
        expect(req.url.path, '/api/v3/relay/rooms/333333/actions');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['type'], 'CHAT');
        expect(body['source_device_id'], 'd1');
        return http.Response(jsonEncode({
          'snapshot': {
            ..._emptySnap('333333'),
            'version': 5,
            'context': {'n': 3},
          },
        }), 200);
      });
      final t = RelayV3Transport(
        relayUrl: 'http://x',
        alias: 'a',
        deviceId: 'd1',
        httpClient: mock,
      );
      final snap = await t.testApplyAction(
        code: '333333',
        type: 'CHAT',
        params: {},
        sourceDeviceId: 'd1',
      );
      expect(snap.version, 5);
      expect(snap.context['n'], 3);
    });
  });

  group('RoomHandle', () {
    test('initial snapshot is available on snapshots stream', () async {
      final t = RelayV3Transport(
        relayUrl: 'http://x',
        alias: 'a',
        deviceId: 'd1',
        httpClient: MockClient((_) async =>
            http.Response(jsonEncode({'ok': true}), 200)),
      );
      final handle = RoomHandle.testCreate(
        transport: t,
        code: '111111',
        wsUrl: 'ws://x/ws3/111111',
        initial: Snapshot.fromJson({
          'room_code': '111111',
          'script_hash': '',
          'script_src': '',
          'context': {'n': 0},
          'state': '',
          'version': 1,
          'created_at': '2026-07-25T10:00:00Z',
          'updated_at': '2026-07-25T10:00:00Z',
          'history': [],
        }),
      );
      final received = <Snapshot>[];
      final sub = handle.snapshots.listen(received.add);
      await Future<void>.delayed(Duration.zero);

      expect(handle.latest?.version, 1);
      expect(handle.latest?.context['n'], 0);

      await sub.cancel();
      await handle.dispose();
    });

    test('dispose() is idempotent (no StateError on double-call)', () async {
      final t = RelayV3Transport(
        relayUrl: 'http://x',
        alias: 'a',
        deviceId: 'd1',
        httpClient: MockClient((_) async =>
            http.Response(jsonEncode({'ok': true}), 200)),
      );
      final handle = RoomHandle.testCreate(
        transport: t,
        code: 'id-2',
        wsUrl: 'ws://127.0.0.1:1/never',
        initial: Snapshot.fromJson(_emptySnap('id-2')),
      );
      await handle.dispose();
      await handle.dispose();
    });

    testWidgets('heartbeat：20s 周期 fetchSnapshot 兜底刷新 + fetch 顺带触发重连 + dispose 停止', (tester) async {
      var snapshotGets = 0;
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/snapshot')) {
          snapshotGets++;
          return http.Response(jsonEncode({
            'data': {'snapshot': _emptySnap('hb-1')},
          }), 200);
        }
        return http.Response(jsonEncode({'ok': true}), 200);
      });
      final t = RelayV3Transport(
        relayUrl: 'http://x',
        alias: 'a',
        deviceId: 'd1',
        httpClient: mock,
      );
      final handle = _NoConnectHandle(
        transport: t,
        code: 'hb-1',
        wsUrl: 'ws://x/ws3/hb-1',
        initial: Snapshot.fromJson(_emptySnap('hb-1')),
      );

      expect(snapshotGets, 0, reason: '未启动心跳时不拉快照');
      handle.debugStartHeartbeat();

      // 20s 周期：t=20 / t=40 两次，t=41 时不触发第三次。
      // （tester.pump(duration) 推进 fake 时钟并触发其中的 Timer。）
      await tester.pump(const Duration(seconds: 41));
      expect(snapshotGets, 2, reason: '20s 周期 fetchSnapshot 兜底刷新快照');
      // 每次心跳 fetch 时 _connected=false → fetchSnapshot 内部顺带 connect()
      // （心跳兼作重连保险）。
      expect(handle.connectCalls, 2,
          reason: '心跳 fetch 在断连态顺带触发立即重连');

      // 停止心跳（dispose 路径）→ 不再拉取。
      await handle.dispose();
      final before = snapshotGets;
      await tester.pump(const Duration(seconds: 60));
      expect(snapshotGets, before, reason: 'dispose 后 heartbeat 停止');
    });
  });
}

Map<String, dynamic> _emptySnap(String code) => {
      'room_code': code,
      'script_hash': '',
      'script_src': '',
      'context': {},
      'state': '',
      'version': 1,
      'created_at': '2026-07-25T10:00:00Z',
      'updated_at': '2026-07-25T10:00:00Z',
      'history': [],
    };
