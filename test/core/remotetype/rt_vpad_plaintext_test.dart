// test/core/remotetype/rt_vpad_plaintext_test.dart
//
// 虚拟手柄指令明文形状测试（v0.7.0+ vpad_* 协议）。
// 契约：与 mn-rt client/lib/rt-align.js 的 vpad 分支（normalizeVpadOp）
// 对齐——
//   * plaintext 带 vpad 对象（action + 字段）、不带 text / hotkey 字段；
//   * PC 端 vpad 分支与 mouse 同属事件层：seq 去重之前处理、不回 ACK；
//   * 键名/动作名允许大小写混写（PC 端网关归一为小写），rust vpad.rs 的
//     parse_* 也 to_ascii_lowercase——手机端统一小写是主路径，形状测试锁定
//     「字段名与文档表格一致」，大小写兼容由 PC 端保证。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:xiaodouzi_fr/core/remotetype/protocol/rt_session.dart';

void main() {
  group('rtVpadPlaintext 明文形状', () {
    test('button 形状：action/vpad_handle/vpad_button/vpad_value_bool', () {
      final plain = rtVpadPlaintext(
        {
          'action': 'vpad_button',
          'vpad_handle': 'pad1',
          'vpad_button': 'a',
          'vpad_value_bool': true,
        },
        1700000000000,
        'phone-abc',
      );
      expect(plain['vpad'], {
        'action': 'vpad_button',
        'vpad_handle': 'pad1',
        'vpad_button': 'a',
        'vpad_value_bool': true,
      });
      expect(plain['ts'], 1700000000000);
      expect(plain['phoneId'], 'phone-abc');
      expect(plain.containsKey('text'), isFalse);
      expect(plain.containsKey('hotkey'), isFalse);
      expect(plain.containsKey('mouse'), isFalse);
    });

    test('dpad 形状：vpad_dir（含回中 none）', () {
      final plain = rtVpadPlaintext(
        {'action': 'vpad_dpad', 'vpad_handle': 'pad1', 'vpad_dir': 'none'},
        1,
        'p',
      );
      expect(plain['vpad'], {
        'action': 'vpad_dpad',
        'vpad_handle': 'pad1',
        'vpad_dir': 'none',
      });
      // 整条明文可 JSON 往返（密封前的形状不得含非 JSON 值）
      final back = jsonDecode(jsonEncode(plain)) as Map<String, dynamic>;
      expect(back['vpad']['vpad_dir'], 'none');
    });

    test('trigger 形状：vpad_trigger + 0..1 vpad_value（按压=1.0 / 松开=0.0）', () {
      final press = rtVpadPlaintext(
        {
          'action': 'vpad_trigger',
          'vpad_handle': 'pad1',
          'vpad_trigger': 'lt',
          'vpad_value': 1.0,
        },
        1,
        'p',
      );
      final release = rtVpadPlaintext(
        {
          'action': 'vpad_trigger',
          'vpad_handle': 'pad1',
          'vpad_trigger': 'lt',
          'vpad_value': 0.0,
        },
        2,
        'p',
      );
      expect((press['vpad'] as Map)['vpad_value'], 1.0);
      expect((release['vpad'] as Map)['vpad_value'], 0.0);
    });

    test('axis 形状：vpad_axis + -1..1 vpad_value（摇杆，预留）', () {
      final plain = rtVpadPlaintext(
        {
          'action': 'vpad_axis',
          'vpad_handle': 'pad1',
          'vpad_axis': 'lx',
          'vpad_value': -0.5,
        },
        1,
        'p',
      );
      expect((plain['vpad'] as Map)['vpad_axis'], 'lx');
      expect((plain['vpad'] as Map)['vpad_value'], -0.5);
    });

    test('生命周期形状：init 带 vpad_slot；release/release_all 不带 handle', () {
      final init = rtVpadPlaintext(
        {'action': 'vpad_init', 'vpad_slot': 1},
        1,
        'p',
      );
      expect((init['vpad'] as Map)['vpad_slot'], 1);
      final rel = rtVpadPlaintext(
        {'action': 'vpad_release', 'vpad_handle': 'pad1'},
        2,
        'p',
      );
      expect((rel['vpad'] as Map)['vpad_handle'], 'pad1');
      final all = rtVpadPlaintext({'action': 'vpad_release_all'}, 3, 'p');
      expect((all['vpad'] as Map).containsKey('vpad_handle'), isFalse);
    });
  });
}
