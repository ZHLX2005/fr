// kTimePageMeta 必须是 demo slug → 展示元数据 的映射（与 kGameMeta 模式一致）。
// 保证 Focus 主页的精选大卡、网格卡能用一个 slug 查到 label/icon/color/featured。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/focus/time_tools/const_time_pages.dart';

void main() {
  group('kTimePageMeta', () {
    test('covers the 3 expected time-page demo slugs', () {
      expect(kTimePageMeta.keys.toSet(),
          containsAll(<String>['clock', 'calendar', 'metronome']));
    });

    test('exactly 3 entries (no accidental growth)', () {
      expect(kTimePageMeta.length, 3);
    });

    test('clock is featured; calendar & metronome are not', () {
      expect(timePageMetaOf('clock').featured, isTrue);
      expect(timePageMetaOf('calendar').featured, isFalse);
      expect(timePageMetaOf('metronome').featured, isFalse);
    });

    test('every meta has a non-empty Chinese label and a non-null icon/color', () {
      for (final entry in kTimePageMeta.entries) {
        final m = entry.value;
        expect(m.label.trim(), isNotEmpty,
            reason: '${entry.key}.label 不能为空');
        expect(m.icon, isA<IconData>(),
            reason: '${entry.key}.icon 必须是 IconData');
        expect(m.color, isA<Color>(),
            reason: '${entry.key}.color 必须是 Color');
      }
    });

    test('timePageMetaOf(unknown) returns a non-null fallback-shaped meta', () {
      final m = timePageMetaOf('does-not-exist');
      expect(m.label, isNotEmpty);
      expect(m.icon, isA<IconData>());
      expect(m.color, isA<Color>());
      expect(m.featured, isFalse);
    });
  });
}