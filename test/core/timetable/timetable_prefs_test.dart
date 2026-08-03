// TimetablePrefs 持久化 round-trip 测试
// 学号 / 密码 / 学期通过 SharedPreferences 持久化，下次自动填。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/timetable/service/config/timetable_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('TimetablePrefs.loadSicauCreds', () {
    test('首次加载 → 全空 + 学期用默认值', () async {
      final c = await TimetablePrefs.loadSicauCreds();
      expect(c.userId, '');
      expect(c.password, '');
      expect(c.semester, '2026-2027-1');
    });

    test('保存学号+学期+密码 → 重新加载全部一致', () async {
      await TimetablePrefs.saveSicauCreds(
        userId: '20231001',
        password: 'secret',
        semester: '2026-2027-1',
      );
      final c = await TimetablePrefs.loadSicauCreds();
      expect(c.userId, '20231001');
      expect(c.password, 'secret');
      expect(c.semester, '2026-2027-1');
    });

    test('saveSicauCreds 不传 password → 不覆盖原密码', () async {
      await TimetablePrefs.saveSicauCreds(
        userId: '20231001',
        password: 'secret',
        semester: '2026-2027-1',
      );
      // 第二次只更新学期（password 留空）
      await TimetablePrefs.saveSicauCreds(
        userId: '20231001',
        password: '',
        semester: '2026-2027-2',
      );
      final c = await TimetablePrefs.loadSicauCreds();
      expect(c.password, 'secret'); // 保留
      expect(c.semester, '2026-2027-2'); // 更新
    });

    test('defaultSemester 常量正确', () {
      expect(TimetablePrefs.defaultSemester, '2026-2027-1');
    });
  });
}
