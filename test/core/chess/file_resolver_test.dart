import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/skins/file_resolver.dart';

void main() {
  group('PublicFileResolver', () {
    test('url(id) = baseUrl + /files/ + id', () {
      const r = PublicFileResolver(baseUrl: 'http://example.com:1234');
      expect(
        r.url('abc123def456'),
        'http://example.com:1234/files/abc123def456',
      );
    });

    test('保留 baseUrl 末尾斜杠（不重复加）', () {
      const r = PublicFileResolver(baseUrl: 'http://example.com/');
      expect(r.url('xyz'), 'http://example.com/files/xyz');
    });
  });
}
