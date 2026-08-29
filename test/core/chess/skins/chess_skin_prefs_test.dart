// test/core/chess/skins/chess_skin_prefs_test.dart
//
// 换肤偏好（ChessSkinPrefs）单元测试 —— SharedPreferences mock。
//
// 遵循 shared_preferences 官方 mock 模式：
//   TestWidgetsFlutterBinding.ensureInitialized() + SharedPreferences.setMockInitialValues。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChessSkinPrefs', () {
    test('无记录时 read 回退 catalog 第一套（\'1\'）', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await ChessSkinPrefs.read(), kChessSkinsCatalog.first.id);
    });

    test('write 后 read 返回写入的 id', () async {
      SharedPreferences.setMockInitialValues({});
      await ChessSkinPrefs.write('3');
      expect(await ChessSkinPrefs.read(), '3');
    });

    test('持久化跨 read 调用一致（mock 栈内保留写入）', () async {
      SharedPreferences.setMockInitialValues({});
      await ChessSkinPrefs.write('7');
      expect(await ChessSkinPrefs.read(), '7');
      // 再次 read 验证不丢
      expect(await ChessSkinPrefs.read(), '7');
    });
  });
}
