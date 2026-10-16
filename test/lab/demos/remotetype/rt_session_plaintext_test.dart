// RT1 快照明文构造测试：enterMode 字段的可选携带语义。
//
// 契约（与 mn-rt client/lib/rt-align.js 对齐）：
//   * 明文 {text, ts, phoneId} 基础上可选携带 enterMode；
//   * 只在用户显式选择时携带（'enter' | 'shift_enter'），
//     空/未选择 = 不带字段 = PC 端走本地配置兜底（老手机零回归）；
//   * 老版本 PC 解析 JSON 时忽略未知字段，双向兼容。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/remotetype/rt_session.dart';

void main() {
  group('rtSyncPlaintext — enterMode 可选携带', () {
    test('携带 enterMode 时序列化后包含该字段', () {
      final plain = rtSyncPlaintext('第一行\n第二行', 0, 'phone-x', enterMode: 'shift_enter');
      expect(plain['enterMode'], 'shift_enter');
      final decoded = jsonDecode(jsonEncode(plain)) as Map<String, dynamic>;
      expect(decoded['enterMode'], 'shift_enter');
    });

    test('enterMode=null 时不携带字段（老协议形状）', () {
      final plain = rtSyncPlaintext('你好', 0, 'phone-x');
      expect(plain.containsKey('enterMode'), isFalse);
      final decoded = jsonDecode(jsonEncode(plain)) as Map<String, dynamic>;
      expect(decoded.containsKey('enterMode'), isFalse);
    });

    test('空串视为未选择：不携带字段', () {
      final plain = rtSyncPlaintext('你好', 0, 'phone-x', enterMode: '');
      expect(plain.containsKey('enterMode'), isFalse);
    });

    test('基础字段不变：text/ts/phoneId 原样', () {
      final plain = rtSyncPlaintext('你好', 1234, 'phone-x', enterMode: 'enter');
      expect(plain['text'], '你好');
      expect(plain['ts'], 1234);
      expect(plain['phoneId'], 'phone-x');
    });
  });
}
