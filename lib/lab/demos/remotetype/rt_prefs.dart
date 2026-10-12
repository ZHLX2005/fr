// RemoteType 本地偏好：可编排快捷键（含序列宏）+ 历史输入。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'rt_constants.dart';

const _kShortcutsKeyV1 = 'rt_shortcuts_v1';
const _kShortcutsKeyV2 = 'rt_shortcuts_v2';
const _kHistoryKey = 'rt_input_history_v1';
const _kMaxHistory = 40;

/// 一组按键（末位主键、其余修饰键）。与原协议层 `hotkey` 字段形状一一对应。
class RtChord {
  const RtChord({required this.keys});
  final List<String> keys;

  /// 与原 RtShortcutItem.keys 兼容。
  RtChord.fromLegacy(List<String> legacy)
    : keys = List<String>.of(legacy);

  Map<String, dynamic> toJson() => {'keys': keys};

  factory RtChord.fromJson(Map<String, dynamic> j) {
    final raw = j['keys'];
    return RtChord(keys: raw is List ? raw.map((e) => e.toString()).toList() : const []);
  }
}

/// 一条序列宏（1..N 个 chord + 共同的毫秒间隔）。
///
/// v2 模型；兼容读 v1（每条 RtShortcutItem = 单 chord + intervalMs=0）。写入
/// 全部走 v2 键，原 v1 键保留只读（不擦，避免突然清空用户数据，但也不再向
/// v1 回写）。
class RtShortcutItem {
  const RtShortcutItem({
    required this.id,
    required this.label,
    required this.chords,
    required this.intervalMs,
  });

  final String id;
  final String label;
  final List<RtChord> chords;
  final int intervalMs;

  /// v1 兼容构造：单 chord、无间隔。
  factory RtShortcutItem.single({
    required String id,
    required String label,
    required List<String> keys,
  }) {
    return RtShortcutItem(
      id: id,
      label: label,
      chords: [RtChord(keys: List<String>.of(keys))],
      intervalMs: 0,
    );
  }

  /// 序列长度为 0 是非法（防御性，正常流程不会构造出来）。
  bool get isValid => chords.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'chords': [for (final c in chords) c.toJson()],
    'intervalMs': intervalMs,
  };

  factory RtShortcutItem.fromJson(Map<String, dynamic> j) {
    final id = j['id']?.toString() ?? '';
    final label = j['label']?.toString() ?? '';
    final intervalMs = (j['intervalMs'] as num?)?.toInt() ?? 0;
    // v2 形状
    final rawChords = j['chords'];
    if (rawChords is List && rawChords.isNotEmpty) {
      final chords = <RtChord>[];
      for (final c in rawChords.whereType<Map>()) {
        final chord = RtChord.fromJson(c.cast<String, dynamic>());
        if (chord.keys.isNotEmpty) chords.add(chord);
      }
      if (chords.isNotEmpty) {
        return RtShortcutItem(
          id: id,
          label: label,
          chords: chords,
          intervalMs: intervalMs,
        );
      }
    }
    // v1 形状：单 keys 数组 → 包成 1 个 chord
    final rawKeys = j['keys'];
    if (rawKeys is List && rawKeys.isNotEmpty) {
      final keys = rawKeys.map((e) => e.toString()).toList();
      return RtShortcutItem.single(id: id, label: label, keys: keys);
    }
    return RtShortcutItem(id: id, label: label, chords: const [], intervalMs: 0);
  }
}

/// 默认快捷键（与 [kShortcutPresets] / [kShortcutLabels] 对齐）。
List<RtShortcutItem> kDefaultRtShortcuts() {
  final n = kShortcutPresets.length;
  return [
    for (var i = 0; i < n; i++)
      RtShortcutItem.single(
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
    // 优先读 v2；落空再读 v1（升上来的数据不强行回写，让用户改一次再落 v2）。
    final v2 = p.getString(_kShortcutsKeyV2);
    if (v2 != null && v2.isNotEmpty) {
      final parsed = _decodeShortcuts(v2);
      if (parsed.isNotEmpty) return parsed;
    }
    final v1 = p.getString(_kShortcutsKeyV1);
    if (v1 != null && v1.isNotEmpty) {
      final parsed = _decodeShortcuts(v1);
      if (parsed.isNotEmpty) return parsed;
    }
    return kDefaultRtShortcuts();
  }

  static List<RtShortcutItem> _decodeShortcuts(String raw) {
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => RtShortcutItem.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.isValid)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveShortcuts(List<RtShortcutItem> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kShortcutsKeyV2,
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
