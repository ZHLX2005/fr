import 'package:shared_preferences/shared_preferences.dart';

/// 课表设置页 / 教务导入的轻量持久化（学号、密码、学期）。
///
/// 放在 SharedPreferences 而非 Hive，因为：
/// - 字段少（3 个），用 KV 最简单
/// - 不需要跨设备同步，KV 足够
/// - 与既有 `timetable_config`（Hive）解耦
class TimetablePrefs {
  static const _kUserId = 'sicau_user_id';
  static const _kPassword = 'sicau_password';
  static const _kSemester = 'sicau_semester';

  /// 学期默认值：2026-2027 学年第 1 学期
  static const String defaultSemester = '2026-2027-1';

  /// 加载 SICAU 教务导入的持久化字段
  /// 返回 (userId, password, semester)，密码为空字符串时上层视为未填。
  static Future<({String userId, String password, String semester})>
      loadSicauCreds() async {
    final p = await SharedPreferences.getInstance();
    return (
      userId: p.getString(_kUserId) ?? '',
      password: p.getString(_kPassword) ?? '',
      semester: p.getString(_kSemester) ?? defaultSemester,
    );
  }

  /// 保存 SICAU 教务导入的持久化字段。password 留空则不写（避免误清空）。
  static Future<void> saveSicauCreds({
    required String userId,
    required String password,
    required String semester,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUserId, userId);
    if (password.isNotEmpty) {
      await p.setString(_kPassword, password);
    }
    await p.setString(_kSemester, semester);
  }
}
