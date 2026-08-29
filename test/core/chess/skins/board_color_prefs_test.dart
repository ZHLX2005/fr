// test/core/chess/skins/board_color_prefs_test.dart
//
// 自定义棋盘配色偏好（BoardColorPrefs）单元测试 —— SharedPreferences mock。
//
// 遵循 chess_skin_prefs_test.dart 的官方 mock 模式：
//   TestWidgetsFlutterBinding.ensureInitialized() + SharedPreferences.setMockInitialValues。
//
// 优先级语义验证：
//   · 无记录 / custom=false → read() == null（跟随主题）
//   · write(palette) → read() 返回两主格色（用户自定义 > 主题）
//   · clear() → read() == null

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/board_color_prefs.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/board_palette.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoardColorPrefs', () {
    test('无记录 → read 返回 null（跟随主题）', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await BoardColorPrefs.read(), isNull);
    });

    test('write 两色 → read 返回相同的 light/dark', () async {
      SharedPreferences.setMockInitialValues({});
      const palette = BoardPalette(
        lightSquare: Color(0xFFF0D9B5),
        darkSquare: Color(0xFFB58863),
      );
      await BoardColorPrefs.write(palette);

      final read = await BoardColorPrefs.read();
      expect(read, isNotNull);
      expect(read!.lightSquare, const Color(0xFFF0D9B5));
      expect(read.darkSquare, const Color(0xFFB58863));
      // 只 round-trip 两主格色，其余角色保持 null（主题默认）
      expect(read.gridLine, isNull);
    });

    test('write 只含浅色格 → read 只含浅色格（深色 null）', () async {
      SharedPreferences.setMockInitialValues({});
      const palette = BoardPalette(lightSquare: Color(0xFFAAD751));
      await BoardColorPrefs.write(palette);

      final read = await BoardColorPrefs.read();
      expect(read, isNotNull);
      expect(read!.lightSquare, const Color(0xFFAAD751));
      expect(read.darkSquare, isNull, reason: '未写入的深色格不虚构，回退主题');
    });

    test('带 alpha 的颜色 round-trip 不失真（ARGB 完整保留）', () async {
      SharedPreferences.setMockInitialValues({});
      const palette = BoardPalette(
        lightSquare: Color(0x80EBE5D6),
        darkSquare: Color(0xCC3D3127),
      );
      await BoardColorPrefs.write(palette);

      final read = await BoardColorPrefs.read();
      expect(read!.lightSquare, const Color(0x80EBE5D6));
      expect(read.darkSquare, const Color(0xCC3D3127));
    });

    test('write 后 clear → read 返回 null（清除自定义）', () async {
      SharedPreferences.setMockInitialValues({});
      await BoardColorPrefs.write(
        const BoardPalette(
          lightSquare: Color(0xFFF0D9B5),
          darkSquare: Color(0xFFB58863),
        ),
      );
      expect(await BoardColorPrefs.read(), isNotNull);

      await BoardColorPrefs.clear();
      expect(await BoardColorPrefs.read(), isNull, reason: 'clear 后回退主题');
    });

    test('custom=false 但残留颜色值 → read 返回 null（开关优先）', () async {
      // 模拟"曾开过后又关掉，但旧颜色值还在"的历史数据。
      SharedPreferences.setMockInitialValues({
        'chess_board_custom': false,
        'chess_board_light': 0xFFF0D9B5,
        'chess_board_dark': 0xFFB58863,
      });
      expect(
        await BoardColorPrefs.read(),
        isNull,
        reason: '自定义开关关闭时忽略残留颜色值',
      );
    });

    test('read 持久化跨调用一致（mock 栈内保留写入）', () async {
      SharedPreferences.setMockInitialValues({});
      const palette = BoardPalette(
        lightSquare: Color(0xFF8CA2AD),
        darkSquare: Color(0xFF7B9467),
      );
      await BoardColorPrefs.write(palette);
      expect((await BoardColorPrefs.read())!.lightSquare, palette.lightSquare);
      expect((await BoardColorPrefs.read())!.darkSquare, palette.darkSquare);
    });
  });
}
