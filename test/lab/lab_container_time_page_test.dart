// Exercises the new timePage field + filterByTimePage extension
// on DemoPage. Defaults to false; an override flips it; the extension
// returns only entries whose demo.timePage is true.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/lab_container.dart';

class _NotTimePage extends DemoPage {
  @override
  String get title => 'NotTime';
  @override
  String get slug => 'not-time';
  @override
  String get description => 'x';
  @override
  Widget buildPage(BuildContext context) => const SizedBox();
}

class _TimePage extends DemoPage {
  @override
  String get title => 'Time';
  @override
  String get slug => 'time';
  @override
  String get description => 'x';
  @override
  bool get timePage => true;
  @override
  Widget buildPage(BuildContext context) => const SizedBox();
}

void main() {
  group('DemoPage.timePage', () {
    test('defaults to false', () {
      expect(_NotTimePage().timePage, isFalse);
    });

    test('override flips to true', () {
      expect(_TimePage().timePage, isTrue);
    });
  });

  group('filterByTimePage', () {
    test('keeps only entries whose demo.timePage is true', () {
      final entries = <MapEntry<String, DemoPage>>[
        MapEntry('not-time', _NotTimePage()),
        MapEntry('time', _TimePage()),
      ];
      final picked = entries.filterByTimePage().map((e) => e.key).toList();
      expect(picked, ['time']);
    });

    test('empty input → empty output', () {
      expect(<MapEntry<String, DemoPage>>[].filterByTimePage(), isEmpty);
    });
  });
}