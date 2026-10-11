// RemoteType 本地偏好：可编排快捷键 + 历史输入。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'rt_constants.dart';

const _kShortcutsKey = 'rt_shortcuts_v1';
const _kHistoryKey = 'rt_input_history_v1';
const _kMaxHistory = 40;

/// 一条可发送的快捷键（末位主键、其余修饰键）。
class RtShortcutItem {
  const RtShortcutItem({
    required this.id,
    required this.label,
    required this.keys,
  });

  final String id;
  final String label;
  final List<String> keys;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'keys': keys,
      };

  factory RtShortcutItem.fromJson(Map<String, dynamic> j) {
    final rawKeys = j['keys'];
    return RtShortcutItem(
      id: j['id']?.toString() ?? '',
      label: j['label']?.toString() ?? '',
      keys: rawKeys is List
          ? rawKeys.map((e) => e.toString()).toList()
          : const [],
    );
  }

  RtShortcutItem copyWith({String? label, List<String>? keys}) =>
      RtShortcutItem(
        id: id,
        label: label ?? this.label,
        keys: keys ?? this.keys,
      );
}

/// 默认快捷键（与 [kShortcutPresets] / [kShortcutLabels] 对齐）。
List<RtShortcutItem> kDefaultRtShortcuts() {
  final n = kShortcutPresets.length;
  return [
    for (var i = 0; i < n; i++)
      RtShortcutItem(
        id: 'default_$i',
        label: kShortcutLabels[i],
        keys: List<String>.of(kShortcutPresets[i]),
      ),
  ];
}

class RtPrefs {
  RtPrefs._();

  static Future<List<RtShortcutItem>> loadShortcuts() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kShortcutsKey);
    // 未写过 → 默认库；显式存过 `[]` → 空列表（用户清空后应保留）。
    if (raw == null) return kDefaultRtShortcuts();
    if (raw.isEmpty) return kDefaultRtShortcuts();
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => RtShortcutItem.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.id.isNotEmpty && e.keys.isNotEmpty)
          .toList();
    } catch (_) {
      return kDefaultRtShortcuts();
    }
  }

  static Future<void> saveShortcuts(List<RtShortcutItem> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kShortcutsKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  static Future<List<String>> loadHistory() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_kHistoryKey) ?? const [];
  }

  /// 新记录插到最前；去重（同文提到最前）；上限 [_kMaxHistory]。
  static Future<List<String>> pushHistory(String text) async {
    final t = text.trim();
    if (t.isEmpty) return loadHistory();
    final p = await SharedPreferences.getInstance();
    final cur = p.getStringList(_kHistoryKey) ?? <String>[];
    cur.remove(t);
    cur.insert(0, t);
    if (cur.length > _kMaxHistory) {
      cur.removeRange(_kMaxHistory, cur.length);
    }
    await p.setStringList(_kHistoryKey, cur);
    return cur;
  }

  static Future<void> clearHistory() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kHistoryKey);
  }
}
