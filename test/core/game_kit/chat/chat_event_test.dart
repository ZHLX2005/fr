import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/script/chess_script.dart';
import 'package:xiaodouzi_fr/core/game_kit/chat/chat_event.dart';
import 'package:xiaodouzi_fr/core/game_kit/chat/chat_script.dart';

void main() {
  group('chatRing parse', () {
    test('reads chatRing text events', () {
      final events = chatTextsFromSnapshot({
        'chatRing': [
          {
            'id': 'c1',
            'text': '加油！',
            'from': 'dev-a',
            'seq': 1,
            'ts': 1000,
          },
        ],
      });
      expect(events, hasLength(1));
      expect(events.first.text, '加油！');
      expect(events.first.kind, ChatKind.text);
      expect(events.first.from, 'dev-a');
    });

    test('mergedChatEventsFromSnapshot sorts by ts', () {
      final merged = mergedChatEventsFromSnapshot({
        'chatRing': [
          {'id': 'c2', 'text': '后', 'from': 'a', 'seq': 2, 'ts': 200},
        ],
        'emojiRing': [
          {
            'id': 'smile',
            'emoji_id': 'smile',
            'from': 'b',
            'seq': 1,
            'ts': 100,
          },
        ],
      });
      expect(merged, hasLength(2));
      expect(merged.first.kind, ChatKind.emoji);
      expect(merged.last.kind, ChatKind.text);
    });
  });

  group('chess script chat segment', () {
    test('kChatScriptSegment defines on_action_CHAT', () {
      expect(kChatScriptSegment, contains('on_action_CHAT'));
      expect(kChatScriptSegment, contains('chatRing'));
    });

    test('kChessScript exports CHAT and clears chat on RESET', () {
      expect(kChessScript, contains('on_action_CHAT'));
      expect(kChessScript, contains('c.chatRing = {}'));
      expect(kChessScript, contains('on_action_EMOJI'));
    });
  });
}
