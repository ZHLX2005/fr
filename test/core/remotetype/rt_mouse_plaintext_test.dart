// test/core/remotetype/rt_mouse_plaintext_test.dart
//
// 鼠标事件明文形状测试（v0.6.0+ 触摸板协议）。
// 契约：与 mn-rt client/lib/rt-align.js 的 mouse 分支对齐——
//   * plaintext 带 mouse 对象（move/button/scroll 三种形状）、不带 text 字段；
//   * PC 端 mouse 分支在 seq 去重之前（事件语义），且**不回 ACK**；
//   * phoneId 透传（ACK 反向路由字段，对 mouse 而言仅是元数据惯例）。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:xiaodouzi_fr/core/remotetype/protocol/rt_session.dart';

void main() {
  group('rtMousePlaintext 明文形状', () {
    test('move 形状：只带 mouse/ts/phoneId，不带 text / hotkey', () {
      final plain = rtMousePlaintext(
        {'a': 'move', 'dx': 12, 'dy': -5},
        1700000000000,
        'phone-abc',
      );
      expect(plain['mouse'], {'a': 'move', 'dx': 12, 'dy': -5});
      expect(plain['ts'], 1700000000000);
      expect(plain['phoneId'], 'phone-abc');
      expect(plain.containsKey('text'), isFalse, reason: 'mouse 是事件不是快照');
      expect(plain.containsKey('hotkey'), isFalse);
      expect(
        jsonEncode(plain),
        contains('"mouse"'),
        reason: 'PC 端按 plain.mouse 识别事件分支',
      );
    });

    test('button / scroll 形状可表达全部动作', () {
      expect(
        rtMousePlaintext(
          {'a': 'button', 'button': 'right', 'kind': 'click'},
          1,
          'p',
        )['mouse'],
        {'a': 'button', 'button': 'right', 'kind': 'click'},
      );
      expect(
        rtMousePlaintext({'a': 'scroll', 'dx': 0, 'dy': 3}, 1, 'p')['mouse'],
        {'a': 'scroll', 'dx': 0, 'dy': 3},
      );
    });

    test('mouse 是拷贝不是引用——外部改动不漏进明文', () {
      final mouse = {'a': 'move', 'dx': 1, 'dy': 2};
      final plain = rtMousePlaintext(mouse, 1, 'p');
      mouse['dx'] = 999;
      expect((plain['mouse'] as Map)['dx'], 1);
    });
  });
}
