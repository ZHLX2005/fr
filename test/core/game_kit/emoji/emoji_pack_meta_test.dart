import 'package:flutter_test/flutter_test.dart';

import 'package:xiaodouzi_fr/core/game_kit/emoji/emoji_pack_meta.dart';

void main() {
  test('parseList accepts admin flat open-set format', () {
    const json = '''
[
  {
    "id": "happy",
    "displayName": "开心",
    "file": {
      "fileId": "15474cb19c31277f47280b109f972813",
      "fileName": "happy.webp",
      "sizeBytes": 135761,
      "contentType": "image/png"
    },
    "version": 1
  },
  {
    "id": "island_02",
    "file": {
      "fileId": "a2667bdbdecb643fddf837ea7fda0cc3",
      "fileName": "island_02.webp",
      "sizeBytes": 144830,
      "contentType": "image/png"
    }
  }
]
''';
    final packs = EmojiPackMeta.parseList(json);
    expect(packs, hasLength(1));
    expect(packs.first.id, 'default');
    expect(packs.first.emojis.keys.toSet(), {'happy', 'island_02'});
    expect(
      packs.first.emojis['happy']!.fileId,
      '15474cb19c31277f47280b109f972813',
    );
  });

  test('parseList still accepts nested pack format', () {
    const json = '''
[
  {
    "id": "pack-a",
    "displayName": "Pack A",
    "emojis": {
      "wave": {
        "fileId": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "fileName": "wave.webp",
        "sizeBytes": 10,
        "contentType": "image/webp"
      }
    }
  }
]
''';
    final packs = EmojiPackMeta.parseList(json);
    expect(packs, hasLength(1));
    expect(packs.first.id, 'pack-a');
    expect(packs.first.emojis.keys, ['wave']);
  });
}
