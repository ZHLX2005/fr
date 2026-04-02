import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('音频文件保存测试', () {
    test('保存 MP3 文件', () async {
      // 模拟一些音频数据（实际使用时是真实的音频数据）
      final audioData = Uint8List.fromList([
        0xFF, 0xFB, 0x90, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ]);

      // 保存到文件
      final outputFile = File('output_tts_test.mp3');
      await outputFile.writeAsBytes(audioData);

      // 验证文件存在
      expect(await outputFile.exists(), true, reason: '文件应该存在');

      // 验证文件内容
      final savedData = await outputFile.readAsBytes();
      expect(savedData.length, audioData.length, reason: '文件大小应该一致');
      expect(savedData, audioData, reason: '文件内容应该一致');

      print('音频已保存到: ${outputFile.path}');
      print('文件大小: ${savedData.length} bytes');

      // 清理
      await outputFile.delete();
      expect(await outputFile.exists(), false, reason: '文件应该已删除');
    });

    test('十六进制字符串转字节列表', () {
      // 测试十六进制解析
      final hex = 'ffd8ffe000104a46494600010100000100010000';
      final bytes = _hexToBytes(hex);

      expect(bytes.length, hex.length ~/ 2, reason: '字节长度应该是十六进制长度的一半');
      expect(bytes[0], 0xff, reason: '第一个字节应该是 0xff');
      expect(bytes[1], 0xd8, reason: '第二个字节应该是 0xd8');

      print('十六进制解析测试通过: $hex -> ${bytes.length} bytes');
    });

    test('合并多个音频块', () {
      final chunks = <List<int>>[
        [0x01, 0x02, 0x03],
        [0x04, 0x05],
        [0x06, 0x07, 0x08, 0x09],
      ];

      final merged = <int>[];
      for (final chunk in chunks) {
        merged.addAll(chunk);
      }

      expect(merged.length, 9, reason: '合并后应该有9个字节');
      expect(merged, [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09]);

      print('音频块合并测试通过');
    });
  });
}

/// 十六进制字符串转字节列表
List<int> _hexToBytes(String hex) {
  final result = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    result.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return result;
}
