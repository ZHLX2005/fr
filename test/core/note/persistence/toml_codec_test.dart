import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/note/persistence/toml_codec.dart';

/// 真实 BlockCodec 输出的 Map 形状（content 是 spans table，data 是 table，
/// children 是 array of maps）—— 用这个验证 TOML 能无损 roundtrip。
Map<String, dynamic> _sampleBlockMap() => {
      'id': 'blk-1',
      'type': 'heading',
      'data': {'level': 2},
      'content': {
        'spans': [
          {'text': '标题'},
          {'text': '加粗', 'format': {'type': 'bold'}},
        ],
      },
      'children': [
        {
          'id': 'blk-1-1',
          'type': 'paragraph',
          'data': {},
          'content': {'spans': [{'text': '子段落'}]},
          'children': <Map<String, dynamic>>[],
          'properties': <String, dynamic>{},
          'created_at': 1700000000000,
          'updated_at': 1700003600000,
        },
      ],
      'properties': <String, dynamic>{'tag': 'draft'},
      'created_at': 1700000000000,
      'updated_at': 1700003600000,
    };

void main() {
  late TomlCodec codec;

  setUp(() {
    codec = TomlCodec();
  });

  test('encode then decode returns an equivalent Map (deep roundtrip)', () {
    final original = _sampleBlockMap();
    final tomlString = codec.encode(original);
    final decoded = codec.decode(tomlString);

    expect(decoded['id'], 'blk-1');
    expect(decoded['type'], 'heading');
    expect(decoded['data'], {'level': 2});
    final content = decoded['content'] as Map;
    expect(content.containsKey('spans'), isTrue);
    final spans = content['spans'] as List;
    expect(spans.length, 2);
    expect((spans[0] as Map)['text'], '标题');
    final children = decoded['children'] as List;
    expect(children.length, 1);
    expect((children[0] as Map)['type'], 'paragraph');
    expect(decoded['properties'], {'tag': 'draft'});
    expect(decoded['created_at'], 1700000000000);
  });

  test('encode handles empty data table and empty children', () {
    final map = {
      'id': 'p',
      'type': 'paragraph',
      'data': <String, dynamic>{},
      'content': {'spans': <Map<String, dynamic>>[]},
      'children': <Map<String, dynamic>>[],
      'properties': <String, dynamic>{},
      'created_at': 1,
      'updated_at': 2,
    };
    final decoded = codec.decode(codec.encode(map));
    expect(decoded['type'], 'paragraph');
    expect((decoded['content'] as Map)['spans'] as List, isEmpty);
  });

  test('decode of a hand-written TOML string parses correctly', () {
    const toml = '''
id = "x"
type = "paragraph"
data = {}
content = { spans = [{ text = "hi" }] }
children = []
properties = {}
created_at = 10
updated_at = 20
''';
    final decoded = codec.decode(toml);
    expect(decoded['id'], 'x');
    expect(decoded['type'], 'paragraph');
    expect(
      ((decoded['content'] as Map)['spans'] as List)[0],
      {'text': 'hi'},
    );
  });

  test('encode output contains a [[blocks]]-like table for array-of-maps', () {
    final doc = {
      'blocks': [_sampleBlockMap()],
    };
    final out = codec.encode(doc);
    // The `toml` package serializes array-of-maps as TOML table-array
    // syntax (`[[blocks]]`); string values use single quotes, so we assert
    // the structural marker and the id value in a quote-style-agnostic way.
    expect(out, contains('[[blocks]]'));
    expect(out, contains('blk-1'));
  });
}
