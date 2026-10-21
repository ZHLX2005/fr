// test/core/remotetype/rt_hotkey_plaintext_test.dart
//
// 快捷键指令明文形状测试（v0.5.4+ 两端协议）。
// 契约：与 mn-rt client/lib/rt-align.js 的 hotkey 分支对齐——
//   * plaintext 带 hotkey 数组（末位主键、其余修饰键）、不带 text 字段；
//   * PC 端 hotkey 分支在 seq 去重之前，带旧 seq 也放行；
//   * phoneId 参与 ACK 反向路由，必须透传。
// 加密层（rtSeal/rtOpen/AAD）由 rt1_vectors_test.dart 对拍钉死，这里不重复。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/remotetype/rt_crypto.dart';
import 'package:xiaodouzi_fr/core/remotetype/rt_constants.dart';
import 'package:xiaodouzi_fr/core/remotetype/rt_session.dart';

void main() {
  group('rtHotkeyPlaintext 明文形状', () {
    test('Win+R：hotkey 数组 + ts + phoneId，无 text 字段', () {
      final plain = rtHotkeyPlaintext(
        const ['win', 'r'],
        1730000000000,
        'phone-abc',
      );
      expect(plain['hotkey'], const ['win', 'r']);
      expect(plain['ts'], 1730000000000);
      expect(plain['phoneId'], 'phone-abc');
      expect(
        plain.containsKey('text'),
        isFalse,
        reason:
            'hotkey 指令不带 text：老 PC 收到无 text 明文会按 duplicate 丢弃，'
            '这正是「老版本 PC 不响应快捷键」的兼容行为',
      );
    });

    test('多修饰键顺序保持（ctrl,shift,t 不得被重排）', () {
      final plain = rtHotkeyPlaintext(const ['ctrl', 'shift', 't'], 1, 'p');
      expect(plain['hotkey'], const ['ctrl', 'shift', 't']);
    });

    test('纯主键（F5）无修饰键', () {
      final plain = rtHotkeyPlaintext(const ['f5'], 1, 'p');
      expect(plain['hotkey'], const ['f5']);
    });

    test('keys 拷贝隔离：改原列表不影响已生成的明文', () {
      final keys = ['win', 'r'];
      final plain = rtHotkeyPlaintext(keys, 1, 'p');
      keys.clear();
      expect(plain['hotkey'], const ['win', 'r']);
    });
  });

  group('快捷键信封端到端（seal → open 往返，模拟 PC 端解密视角）', () {
    test('hotkey 信封能被 RT1 密钥解开，hotkey 字段完整还原', () async {
      final derived = await rtDeriveFromKey('RT1TESTKEYAB12');
      const sid = 'abcd1234';
      const seq = 42;
      const phoneId = 'phone-e2e';
      final ts = DateTime.now().millisecondsSinceEpoch;

      // 手机端：seal（与 RtSession.syncHotkey 同参数形状）
      final envelope = await rtSeal(
        key: derived.keyPhoneToPc,
        aad: rtBuildAad(derived.room, kRtDirPhoneToPc, seq),
        plaintext: rtHotkeyPlaintext(const ['win', 'v'], ts, phoneId),
        sid: sid,
        seq: seq,
      );

      // PC 端：open（与 mn-rt rt-align.js _handleEnvelope 同视角）
      final plain = await rtOpen(
        key: derived.keyPhoneToPc,
        aad: rtBuildAad(derived.room, kRtDirPhoneToPc, seq),
        envelope: envelope,
      );

      expect((plain['hotkey'] as List).cast<String>(), const ['win', 'v']);
      expect(plain['phoneId'], phoneId);
      // PC 端解构约定：末位主键、其余修饰键
      final keys = (plain['hotkey'] as List).cast<String>();
      expect(keys.last, 'v');
      expect(keys.sublist(0, keys.length - 1), const ['win']);
      // JSON 序列化往返（WS 传输路径）后形状不变
      final reparsed = jsonDecode(jsonEncode(plain)) as Map<String, dynamic>;
      expect(reparsed['hotkey'], isA<List>());
    });
  });

  group('预设清单自洽', () {
    test('kShortcutLabels 与 kShortcutPresets 一一对应', () {
      expect(kShortcutLabels.length, kShortcutPresets.length);
    });

    test('预设不含空数组（空 hotkey 会被 PC 端当非指令丢弃）', () {
      for (final preset in kShortcutPresets) {
        expect(preset, isNotEmpty, reason: '$preset 不应为空');
      }
    });

    test('修饰键 / 主键都在 mn-rt 白名单内（防 UI 发出 PC 拒收的名字）', () {
      // mn-rt parse_modifier_name 接受的修饰键（含别名）
      const mods = {
        'shift',
        'ctrl',
        'control',
        'alt',
        'option',
        'meta',
        'cmd',
        'win',
        'super',
      };
      // parse_key_name 接受的主键类别（覆盖本清单用到的：单字符 / f1-f12 / 命名键）
      final namedKeys = RegExp(
        r'^(return|enter|tab|escape|esc|backspace|delete|del|space|home|end|pageup|pagedown|up|down|left|right|f([1-9]|1[0-2])|[!-~])$',
      );
      for (final preset in kShortcutPresets) {
        for (var i = 0; i < preset.length; i++) {
          final name = preset[i];
          final isLast = i == preset.length - 1;
          if (isLast) {
            expect(
              namedKeys.hasMatch(name),
              isTrue,
              reason: '主键 $name 应被 mn-rt parse_key_name 接受',
            );
          } else {
            expect(
              mods.contains(name),
              isTrue,
              reason: '修饰键 $name 应被 mn-rt parse_modifier_name 接受',
            );
          }
        }
      }
    });
  });
}
