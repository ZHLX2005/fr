// RemoteType 本地偏好：可编排快捷键（含序列宏）+ 历史输入 + 手柄按钮摆位。

import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:shared_preferences/shared_preferences.dart';

import 'rt_constants.dart';

const _kShortcutsKeyV1 = 'rt_shortcuts_v1';
const _kShortcutsKeyV2 = 'rt_shortcuts_v2';
const _kHistoryKey = 'rt_input_history_v1';
const _kBarDisplayKey = 'rt_bar_display_v1';
const _kTouchpadSensitivityKey = 'rt_touchpad_sensitivity_v1';
const _kCanvasLayoutKey = 'rt_canvas_layout_v1';
const _kMaxHistory = 40;

/// 快捷键托盘的显示配置（与快捷键数据分离——只是外观，不影响发送内容）。
class RtBarDisplay {
  const RtBarDisplay({required this.showDetail, required this.rows});

  /// true：序列 chip 显示 ×N·ms 与逐条 chord 预览；false：只显示名字。
  final bool showDetail;

  /// 托盘行数：1 = 单行横向滑动；2 = 双行（各占一半，仍横向滑动）。
  /// 更多行会让托盘吃掉半个输入页——不做。
  final int rows;

  static const RtBarDisplay defaults = RtBarDisplay(showDetail: false, rows: 1);

  RtBarDisplay copyWith({bool? showDetail, int? rows}) => RtBarDisplay(
        showDetail: showDetail ?? this.showDetail,
        rows: rows ?? this.rows,
      );

  Map<String, dynamic> toJson() => {'showDetail': showDetail, 'rows': rows};

  factory RtBarDisplay.fromJson(Map<String, dynamic> j) => RtBarDisplay(
        showDetail: j['showDetail'] == true,
        rows: j['rows'] == 2 ? 2 : 1,
      );
}

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

/// 横屏画布模块锚点：显隐 + 归一化中心（0..1）。
class RtCanvasAnchor {
  const RtCanvasAnchor({
    required this.visible,
    required this.x,
    required this.y,
  });

  final bool visible;
  final double x;
  final double y;

  Map<String, dynamic> toJson() => {'v': visible, 'x': x, 'y': y};

  factory RtCanvasAnchor.fromJson(Map<String, dynamic> j) => RtCanvasAnchor(
        // 坐标异常一律钳回画布内（拖动越界的旧数据自愈），不丢整条。
        visible: j['v'] == true,
        x: (j['x'] is num ? (j['x'] as num).toDouble() : 0.5)
            .clamp(0.0, 1.0)
            .toDouble(),
        y: (j['y'] is num ? (j['y'] as num).toDouble() : 0.5)
            .clamp(0.0, 1.0)
            .toDouble(),
      );
}

/// 横屏画布布局：模块（触摸板 / 输入框）锚点 + 按钮归一化中心。
/// 空表 = 首跑，画布用内置默认布局。删掉的按钮残位无害（同 id 回归原位）。
class RtCanvasLayout {
  const RtCanvasLayout({this.modules = const {}, this.buttons = const {}});

  final Map<String, RtCanvasAnchor> modules;
  final Map<String, Offset> buttons;

  RtCanvasLayout withModule(String id, RtCanvasAnchor anchor) => RtCanvasLayout(
        modules: Map.of(modules)..[id] = anchor,
        buttons: buttons,
      );

  RtCanvasLayout withButton(String id, Offset pos) => RtCanvasLayout(
        modules: modules,
        buttons: Map.of(buttons)..[id] = pos,
      );

  Map<String, dynamic> toJson() => {
        'modules': {for (final e in modules.entries) e.key: e.value.toJson()},
        'buttons': {
          for (final e in buttons.entries)
            e.key: {'x': e.value.dx, 'y': e.value.dy},
        },
      };

  factory RtCanvasLayout.fromJson(Map<String, dynamic> j) {
    // 坏条目只丢自己（is 判型而非 as 强转——强转抛错会把整表兜底掉）。
    final modules = <String, RtCanvasAnchor>{};
    final rawModules = j['modules'];
    if (rawModules is Map) {
      for (final e in rawModules.entries) {
        if (e.value is Map) {
          modules[e.key.toString()] =
              RtCanvasAnchor.fromJson((e.value as Map).cast<String, dynamic>());
        }
      }
    }
    final buttons = <String, Offset>{};
    final rawButtons = j['buttons'];
    if (rawButtons is Map) {
      for (final e in rawButtons.entries) {
        if (e.value is! Map) continue;
        final jb = (e.value as Map).cast<String, dynamic>();
        final jx = jb['x'];
        final jy = jb['y'];
        if (jx is! num || jy is! num) continue;
        buttons[e.key.toString()] = Offset(
          jx.toDouble().clamp(0.0, 1.0).toDouble(),
          jy.toDouble().clamp(0.0, 1.0).toDouble(),
        );
      }
    }
    return RtCanvasLayout(modules: modules, buttons: buttons);
  }
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

  static Future<RtBarDisplay> loadBarDisplay() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kBarDisplayKey);
    if (raw == null || raw.isEmpty) return RtBarDisplay.defaults;
    try {
      return RtBarDisplay.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return RtBarDisplay.defaults;
    }
  }

  static Future<void> saveBarDisplay(RtBarDisplay d) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBarDisplayKey, jsonEncode(d.toJson()));
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

  /// 触摸板灵敏度（乘在加速度系数上）。落盘值异常一律回缺省，不抛错。
  static Future<double> loadTouchpadSensitivity() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getDouble(_kTouchpadSensitivityKey);
    if (v == null) return kRtPadSensitivityDefault;
    return v.clamp(kRtPadSensitivityMin, kRtPadSensitivityMax).toDouble();
  }

  static Future<void> saveTouchpadSensitivity(double value) async {
    final p = await SharedPreferences.getInstance();
    final v = value.clamp(kRtPadSensitivityMin, kRtPadSensitivityMax).toDouble();
    await p.setDouble(_kTouchpadSensitivityKey, v);
  }

  /// 横屏画布布局（模块锚点 + 按钮摆位）。JSON 坏形整表兜底为空（画布回
  /// 内置默认），条目级坏形在 RtCanvasLayout.fromJson 内只丢自己。
  static Future<RtCanvasLayout> loadCanvasLayout() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kCanvasLayoutKey);
    if (raw == null || raw.isEmpty) return const RtCanvasLayout();
    try {
      return RtCanvasLayout.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const RtCanvasLayout();
    }
  }

  static Future<void> saveCanvasLayout(RtCanvasLayout layout) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCanvasLayoutKey, jsonEncode(layout.toJson()));
  }
}
