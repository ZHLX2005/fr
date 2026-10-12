// test/lab/remotetype/rt_shortcut_item_v2_test.dart
//
// RtShortcutItem v2 数据迁移 / 序列化测试：
//   * v2 → v2 往返（chords + intervalMs）
//   * v1 → v2 兼容读：旧 JSON 用 `keys: List<String>` 描述单 chord，迁上来后
//     应是 chords.length==1 且 intervalMs==0
//   * 单 chord 紧凑判定用的常量阈值
//   * 空 / 非法 JSON 容错

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/remotetype/rt_constants.dart';
import 'package:xiaodouzi_fr/lab/demos/remotetype/rt_prefs.dart';

void main() {
  group('v2 → v2 往返', () {
    test('单 chord + 0 间隔', () {
      final item = RtShortcutItem.single(
        id: 'a',
        label: 'Win+R',
        keys: const ['win', 'r'],
      );
      final back = RtShortcutItem.fromJson(jsonDecode(jsonEncode(item.toJson()))
          as Map<String, dynamic>);
      expect(back.id, 'a');
      expect(back.label, 'Win+R');
      expect(back.chords.length, 1);
      expect(back.chords.first.keys, const ['win', 'r']);
      expect(back.intervalMs, 0);
    });

    test('多 chord + 间隔', () {
      final item = RtShortcutItem(
        id: 'm1',
        label: '保存宏',
        chords: const [
          RtChord(keys: ['win', 'r']),
          RtChord(keys: ['ctrl', 'l']),
          RtChord(keys: ['f5']),
        ],
        intervalMs: 80,
      );
      final raw = jsonEncode(item.toJson());
      final back = RtShortcutItem.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      expect(back.chords.length, 3);
      expect(back.intervalMs, 80);
      expect(back.chords.map((c) => c.keys).toList(), [
        const ['win', 'r'],
        const ['ctrl', 'l'],
        const ['f5'],
      ]);
    });

    test('isValid 拒绝空 chords', () {
      expect(
        RtShortcutItem(id: 'x', label: 'x', chords: const [], intervalMs: 0)
            .isValid,
        isFalse,
      );
      expect(
        RtShortcutItem.single(id: 'y', label: 'y', keys: const ['f5']).isValid,
        isTrue,
      );
    });
  });

  group('v1 → v2 兼容（不丢数据）', () {
    test('旧 keys[] 解析为单 chord', () {
      // 这是上一版存进 SharedPreferences 的 JSON 形状（_kShortcutsKeyV1）。
      const legacyJson = '''
        {"id":"old_1","label":"Win+R","keys":["win","r"]}
      ''';
      final item = RtShortcutItem.fromJson(
        jsonDecode(legacyJson) as Map<String, dynamic>,
      );
      expect(item.id, 'old_1');
      expect(item.label, 'Win+R');
      expect(item.chords.length, 1);
      expect(item.chords.first.keys, const ['win', 'r']);
      expect(item.intervalMs, 0);
      expect(item.isValid, isTrue);
    });

    test('v1 后再写出仍是 v2 形状（不再回写 keys[]）', () {
      const legacyJson = '{"id":"a","label":"x","keys":["f5"]}';
      final item = RtShortcutItem.fromJson(
        jsonDecode(legacyJson) as Map<String, dynamic>,
      );
      final raw = jsonEncode(item.toJson());
      expect(jsonDecode(raw), {
        'id': 'a',
        'label': 'x',
        'chords': [
          {'keys': ['f5']},
        ],
        'intervalMs': 0,
      });
    });
  });

  group('容错', () {
    test('空 keys 数组 → isValid==false', () {
      final item = RtShortcutItem.fromJson(
        jsonDecode('{"id":"a","label":"x","chords":[{"keys":[]}]}')
            as Map<String, dynamic>,
      );
      expect(item.chords, isEmpty);
      expect(item.isValid, isFalse);
    });

    test('缺字段（无 chords 也无 keys） → fallback 空', () {
      final item = RtShortcutItem.fromJson(
        jsonDecode('{"id":"a","label":"x"}') as Map<String, dynamic>,
      );
      expect(item.chords, isEmpty);
      expect(item.isValid, isFalse);
    });
  });

  group('紧凑外观阈值', () {
    test('chords<=1 && intervalMs==0 → 显示走单组紧凑分支', () {
      expect(kRtShortcutCompactChordCap, 1);
      final compact = RtShortcutItem.single(
        id: 'c', label: 'x', keys: const ['f5'],
      );
      expect(compact.chords.length <= kRtShortcutCompactChordCap && compact.intervalMs == 0,
          isTrue);
    });
  });
}
