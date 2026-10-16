import 'package:flutter_test/flutter_test.dart';

import 'package:xiaodouzi_fr/core/novel_reader/novel_reader_catalog.dart';
import 'package:xiaodouzi_fr/core/novel_reader/novel_reader_constants.dart';
import 'package:xiaodouzi_fr/core/novel_reader/novel_reader_models.dart';

void main() {
  group('parseNovelCatalog', () {
    test('parses built-in entries and forces builtIn source', () {
      const raw = '''
[
  {
    "id": "builtin_seven_day",
    "title": "Seven Day",
    "fileName": "sevenDay.txt",
    "source": "imported",
    "remoteUrl": "https://example.com/sevenDay.txt"
  }
]
''';
      final books = parseNovelCatalog(raw);
      expect(books, hasLength(1));
      expect(books.first.id, NovelReaderConstants.builtInBookId);
      expect(books.first.source, NovelBookSource.builtIn);
      expect(books.first.remoteUrl, 'https://example.com/sevenDay.txt');
    });

    test('returns empty on invalid json', () {
      expect(parseNovelCatalog('not-json'), isEmpty);
      expect(parseNovelCatalog(null), isEmpty);
    });
  });

  test('novelFallbackBuiltIn matches constants', () {
    final book = novelFallbackBuiltIn();
    expect(book.id, NovelReaderConstants.builtInBookId);
    expect(book.remoteUrl, NovelReaderConstants.remoteUrl);
  });
}
