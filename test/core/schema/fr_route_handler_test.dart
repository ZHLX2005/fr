import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/schema/fr_route_handler.dart';
import 'package:xiaodouzi_fr/core/schema/fr_uri.dart';

void main() {
  FrRouteMatch make(String url) {
    return FrRouteMatch(FrUri.tryParse(url)!);
  }

  group('FrRouteMatch.authority / path', () {
    test('authority exposes full path between fr:// and ?', () {
      final m = make('fr://lab/demo/clock');
      expect(m.authority, 'lab/demo/clock');
      expect(m.path, 'demo/clock');
    });

    test('authority and path for leaf URL', () {
      final m = make('fr://lab');
      expect(m.authority, 'lab');
      expect(m.path, '');
    });
  });

  group('FrRouteMatch.queryString', () {
    test('returns value when key exists', () {
      final m = make('fr://x?a=hello');
      expect(m.queryString('a'), 'hello');
    });

    test('returns null when key missing', () {
      final m = make('fr://x?a=1');
      expect(m.queryString('b'), isNull);
    });
  });

  group('FrRouteMatch.queryBool', () {
    test('"true" → true', () {
      expect(make('fr://x?a=true').queryBool('a'), isTrue);
    });

    test('"1" → true', () {
      expect(make('fr://x?a=1').queryBool('a'), isTrue);
    });

    test('"false" → false', () {
      expect(make('fr://x?a=false').queryBool('a'), isFalse);
    });

    test('missing key returns defaultValue=false', () {
      expect(make('fr://x').queryBool('a'), isFalse);
    });

    test('missing key returns defaultValue=true when given', () {
      expect(make('fr://x').queryBool('a', defaultValue: true), isTrue);
    });
  });

  group('FrRouteMatch.pathSegment', () {
    test('returns first segment of multi-segment path', () {
      // fr://lab/demo/clock → path='demo/clock'，第一个段是 'demo'
      expect(make('fr://lab/demo/clock').pathSegment(0), 'demo');
    });

    test('returns middle segment', () {
      expect(make('fr://lab/demo/clock').pathSegment(1), 'clock');
    });

    test('returns first segment of single-segment path', () {
      expect(make('fr://notion/image-host').pathSegment(0), 'image-host');
    });

    test('throws on out-of-range', () {
      expect(
        () => make('fr://lab/demo').pathSegment(5),
        throwsA(isA<RangeError>()),
      );
    });

    test('throws when path is empty', () {
      expect(
        () => make('fr://lab').pathSegment(0),
        throwsA(isA<RangeError>()),
      );
    });
  });
}
