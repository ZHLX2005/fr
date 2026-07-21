// lib/lab/demos/team_card/const_team_card.dart
// 团建卡牌模块常量 + 别名持久化

import 'package:shared_preferences/shared_preferences.dart';

/// 后端 relay 地址
const kRelayUrl = 'http://47.110.80.47:8988';

/// 别名持久化（SharedPreferences）
class AliasPrefs {
  static const _kAlias = 'team_card.alias';

  static Future<String> load() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kAlias) ?? '';
  }

  static Future<void> save(String alias) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAlias, alias);
  }
}
