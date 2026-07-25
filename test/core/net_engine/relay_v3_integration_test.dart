import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

const _script = '''
on_init = function(c, p) c.messages = {}; return c end
on_join = function(c, p) return c end
on_leave = function(c, p) return c end
on_action_CHAT = function(c, p) table.insert(c.messages, p); return c end
return {
  definition = { functions = { "on_init", "on_join", "on_leave", "on_action_CHAT" } },
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_CHAT = on_action_CHAT,
}
''';

void main() {
  test('end-to-end create + action + snapshot via real server', () async {
    final relayUrl = const String.fromEnvironment('RELAY_URL',
        defaultValue: 'http://127.0.0.1:8000');
    final t = RelayV3Transport(
      relayUrl: relayUrl,
      alias: 'alice',
      deviceId: 'integ-${DateTime.now().microsecondsSinceEpoch}',
    );

    final h = await t.createRoom(script: _script, initialParams: {});
    expect(h.code.length, 6);
    expect(h.latest?.version, 1);

    await h.connect();

    // Wait for initial WS frame (already in latest from createRoom, so no wait needed
    // for the first one — but allow the WS to establish before applyAction).
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final newSnap = await h.applyAction(type: 'CHAT', params: {'text': 'hi', 'alias': 'alice'});
    expect(newSnap.version, 2);
    final msgs = (newSnap.context['messages'] as List).cast<Map>();
    expect(msgs.length, 1);
    expect(msgs.first['text'], 'hi');

    await h.dispose();
  }, timeout: const Timeout(Duration(seconds: 10)));
}