import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

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

    test('applyAction hits /actions and parses snapshot', () async {
      final mock = MockClient((req) async {
        expect(req.url.path, '/api/v3/relay/rooms/333333/actions');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['type'], 'CHAT');
        // source_device_id is a request-side field, not a response field.
        // Verify it's correctly sent in the request body.
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
      final snap = await t.applyActionPublic(
        code: '333333',
        type: 'CHAT',
        params: {},
        sourceDeviceId: 'd1',
      );
      // Verify the returned snapshot (not the request body).
      expect(snap.version, 5);
      expect(snap.context['n'], 3);
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