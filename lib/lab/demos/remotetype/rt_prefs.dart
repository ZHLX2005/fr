// RemoteType 本地偏好：可编排快捷键（含序列宏）+ 历史输入 + 手柄按钮摆位。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'rt_constants.dart';

const _kShortcutsKeyV1 = 'rt_shortcuts_v1';
const _kShortcutsKeyV2 = 'rt_shortcuts_v2';
const _kHistoryKey = 'rt_input_history_v1';
const _kBarDisplayKey = 'rt_bar_display_v1';
const _kTouchpadSensitivityKey = 'rt_touchpad_sensitivity_v1';
const _kCanvasLayoutKey = 'rt_canvas_layout_v1';
const _kCanvasLayoutsKey = 'rt_canvas_layouts_v1';

/// 内置预设 id（持久化键，禁止改动——改了等于丢用户当前布局）。
const String kRtCanvasPresetDefault = 'default';
const String kRtCanvasPresetGame = 'game';
const String kRtCanvasPresetKeyboard = 'keyboard';
const String kRtCanvasPresetTouchpad = 'touchpad';

/// 模块 id（布局持久化的键，禁止改动——改了等于丢用户布局）。
const String kRtCanvasModuleTouchpad = 'touchpad';
const String kRtCanvasModuleInput = 'input';

/// 模块「未指定宽高时」的兜底规格（内置预设 / 画布渲染 / sheet 缩略图
/// 三处共用的单一事实源；与原画布默认值一致）。
const double kRtCanvasPadDefW = 0.54, kRtCanvasPadDefH = 0.84;
const double kRtCanvasInputDefW = 0.46, kRtCanvasInputDefH = 0.18;
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

/// 横屏画布模块锚点：显隐 + 归一化中心（0..1）+ 归一化宽高。
class RtCanvasAnchor {
  const RtCanvasAnchor({
    required this.visible,
    required this.x,
    required this.y,
    this.w,
    this.h,
  });

  final bool visible;
  final double x;
  final double y;

  /// 归一化宽高（相对画布，0..1）；null = 用模块内置默认（旧数据兼容）。
  final double? w;
  final double? h;

  Map<String, dynamic> toJson() => {
        'v': visible,
        'x': x,
        'y': y,
        if (w != null) 'w': w,
        if (h != null) 'h': h,
      };

  factory RtCanvasAnchor.fromJson(Map<String, dynamic> j) => RtCanvasAnchor(
        // 坐标异常一律钳回画布内（拖动越界的旧数据自愈），不丢整条。
        visible: j['v'] == true,
        x: (j['x'] is num ? (j['x'] as num).toDouble() : 0.5)
            .clamp(0.0, 1.0)
            .toDouble(),
        y: (j['y'] is num ? (j['y'] as num).toDouble() : 0.5)
            .clamp(0.0, 1.0)
            .toDouble(),
        w: _clampFraction(j['w']),
        h: _clampFraction(j['h']),
      );

  static double? _clampFraction(dynamic v) =>
      v is num ? v.toDouble().clamp(0.05, 1.0).toDouble() : null;
}

/// 画布按钮尺寸倍率上下限（编辑拖动与持久化读入同一处钳制——单一事实源）。
const double kRtCanvasBtnScaleMin = 0.6;
const double kRtCanvasBtnScaleMax = 2.2;

/// 画布按钮位：归一化中心 + 尺寸倍率 + 画布内可见性。
/// （快捷键的「有哪些」归打字页编辑器，「显示哪些」归这里的 v。）
class RtCanvasButtonPos {
  const RtCanvasButtonPos({
    required this.x,
    required this.y,
    this.s = 1.0,
    this.v = true,
  });

  final double x;
  final double y;

  /// 尺寸倍率（乘在按钮基准规格上）。
  final double s;

  /// 画布内可见性（编辑态以幽灵呈现可点回，使用态不渲染）。
  final bool v;

  RtCanvasButtonPos copyWith({double? x, double? y, double? s, bool? v}) =>
      RtCanvasButtonPos(
        x: x ?? this.x,
        y: y ?? this.y,
        s: s ?? this.s,
        v: v ?? this.v,
      );

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 's': s, 'v': v};

  factory RtCanvasButtonPos.fromJson(Map<String, dynamic> j) =>
      RtCanvasButtonPos(
        x: (j['x'] is num ? (j['x'] as num).toDouble() : 0.5)
            .clamp(0.0, 1.0)
            .toDouble(),
        y: (j['y'] is num ? (j['y'] as num).toDouble() : 0.5)
            .clamp(0.0, 1.0)
            .toDouble(),
        // 旧形状（只有 x/y）兼容读：s/v 缺省即默认；倍率钳到编辑限位
        // （与拖动缩放同一对常量，存的和调的不会是两套范围）。
        s: (j['s'] is num ? (j['s'] as num).toDouble() : 1.0)
            .clamp(kRtCanvasBtnScaleMin, kRtCanvasBtnScaleMax)
            .toDouble(),
        v: j['v'] != false,
      );
}

/// 横屏画布命名布局。
class RtCanvasNamedLayout {
  const RtCanvasNamedLayout({
    required this.id,
    required this.name,
    required this.builtIn,
    required this.data,
  });
  final String id;
  final String name;
  final bool builtIn;
  final RtCanvasLayout data;
  RtCanvasNamedLayout copyWith({String? name, bool? builtIn, RtCanvasLayout? data}) =>
      RtCanvasNamedLayout(
        id: id,
        name: name ?? this.name,
        builtIn: builtIn ?? this.builtIn,
        data: data ?? this.data,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'builtIn': builtIn,
        'data': data.toJson(),
      };
  factory RtCanvasNamedLayout.fromJson(Map<String, dynamic> j) => RtCanvasNamedLayout(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    builtIn: j['builtIn'] == true,
    data: RtCanvasLayout.fromJson(
      j['data'] is Map
          ? (j['data'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{},
    ),
  );
}

/// 画布布局集：列表 + 当前激活 id。空表 = 首跑由页面铺内置。
class RtCanvasLayouts {
  const RtCanvasLayouts({
    this.list = const [],
    this.activeId = kRtCanvasPresetDefault,
  });
  final List<RtCanvasNamedLayout> list;
  final String activeId;
  RtCanvasNamedLayout? get active {
    for (final p in list) {
      if (p.id == activeId) return p;
    }
    return list.isNotEmpty ? list.first : null;
  }
  RtCanvasLayout get activeData => active?.data ?? const RtCanvasLayout();
  RtCanvasLayouts withActive(String id) =>
      RtCanvasLayouts(list: list, activeId: id);
  RtCanvasLayouts withList(List<RtCanvasNamedLayout> list) =>
      RtCanvasLayouts(list: list, activeId: activeId);
  RtCanvasLayouts withUpdatedActive(RtCanvasLayout data) {
    final next = <RtCanvasNamedLayout>[];
    var replaced = false;
    for (final p in list) {
      if (!replaced && p.id == activeId) {
        next.add(p.copyWith(data: data));
        replaced = true;
      } else {
        next.add(p);
      }
    }
    return RtCanvasLayouts(list: next, activeId: activeId);
  }

  /// 重命名指定布局（不可变更新；id 不存在时原样返回）。
  RtCanvasLayouts withRenamed(String id, String name) {
    final next = <RtCanvasNamedLayout>[];
    var hit = false;
    for (final p in list) {
      if (p.id == id) {
        next.add(p.copyWith(name: name));
        hit = true;
      } else {
        next.add(p);
      }
    }
    return hit ? RtCanvasLayouts(list: next, activeId: activeId) : this;
  }
  String nextCustomId() {
    var n = 1;
    final ids = list.map((p) => p.id).toSet();
    while (ids.contains('custom-$n')) {
      n += 1;
    }
    return 'custom-$n';
  }
  Map<String, dynamic> toJson() => {
        'list': [for (final p in list) p.toJson()],
        'activeId': activeId,
      };
  factory RtCanvasLayouts.fromJson(Map<String, dynamic> j) {
    final rawList = j['list'];
    final list = <RtCanvasNamedLayout>[];
    if (rawList is List) {
      for (final e in rawList.whereType<Map>()) {
        final entry =
            RtCanvasNamedLayout.fromJson(e.cast<String, dynamic>());
        if (entry.id.isEmpty || entry.name.isEmpty) continue;
        list.add(entry);
      }
    }
    final rawActive = j['activeId']?.toString() ?? '';
    final activeId = list.any((p) => p.id == rawActive)
        ? rawActive
        : kRtCanvasPresetDefault;
    return RtCanvasLayouts(list: list, activeId: activeId);
  }
}

/// 横屏画布布局：模块（触摸板 / 输入框）锚点 + 按钮位（含倍率/显隐）。
/// 空表 = 首跑，画布用内置默认布局。删掉的按钮残位无害（同 id 回归原位）。
class RtCanvasLayout {
  const RtCanvasLayout({this.modules = const {}, this.buttons = const {}});

  final Map<String, RtCanvasAnchor> modules;
  final Map<String, RtCanvasButtonPos> buttons;

  RtCanvasLayout withModule(String id, RtCanvasAnchor anchor) => RtCanvasLayout(
        modules: Map.of(modules)..[id] = anchor,
        buttons: buttons,
      );

  RtCanvasLayout withButton(String id, RtCanvasButtonPos pos) => RtCanvasLayout(
        modules: modules,
        buttons: Map.of(buttons)..[id] = pos,
      );

  Map<String, dynamic> toJson() => {
        'modules': {for (final e in modules.entries) e.key: e.value.toJson()},
        'buttons': {for (final e in buttons.entries) e.key: e.value.toJson()},
      };

  factory RtCanvasLayout.fromJson(Map<String, dynamic> j) {
    // 坏条目只丢自己（is 判型而非 as 强转——强转抛错会把整表兜底掉）。
    final modules = <String, RtCanvasAnchor>{};
    final rawModules = j['modules'];
    if (rawModules is Map) {
      for (final e in rawModules.entries) {
        if (e.value is! Map) continue;
        final jm = (e.value as Map).cast<String, dynamic>();
        // 坐标坏形（类型不对）整条丢弃——缺省可兜底，坏形兜底会凭空挪模块。
        if (jm['x'] is! num || jm['y'] is! num) continue;
        modules[e.key.toString()] = RtCanvasAnchor.fromJson(jm);
      }
    }
    final buttons = <String, RtCanvasButtonPos>{};
    final rawButtons = j['buttons'];
    if (rawButtons is Map) {
      for (final e in rawButtons.entries) {
        if (e.value is! Map) continue;
        final jb = (e.value as Map).cast<String, dynamic>();
        if (jb['x'] is! num || jb['y'] is! num) continue; // 同上：坏形整条丢弃
        buttons[e.key.toString()] = RtCanvasButtonPos.fromJson(jb);
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

  /// 横屏画布布局集（多套 + 当前激活）。坏 JSON 整表兜底为空；旧版
  /// `rt_canvas_layout_v1` 数据自动迁为「导入布局」并激活（旧 key 保留
  /// 只读，便于万一回退）。
  static Future<RtCanvasLayouts> loadCanvasLayouts() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kCanvasLayoutsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        return RtCanvasLayouts.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // 坏形落入迁移分支（旧 key 可能仍有效）。
      }
    }
    final oldRaw = p.getString(_kCanvasLayoutKey);
    if (oldRaw != null && oldRaw.isNotEmpty) {
      try {
        final old = RtCanvasLayout.fromJson(
            jsonDecode(oldRaw) as Map<String, dynamic>);
        final migrated = RtCanvasLayouts(
          list: [
            RtCanvasNamedLayout(
                id: 'imported',
                name: '导入布局',
                builtIn: false,
                data: old),
          ],
          activeId: 'imported',
        );
        await p.setString(
            _kCanvasLayoutsKey, jsonEncode(migrated.toJson()));
        return migrated;
      } catch (_) {}
    }
    return const RtCanvasLayouts();
  }

  static Future<void> saveCanvasLayouts(RtCanvasLayouts layouts) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCanvasLayoutsKey, jsonEncode(layouts.toJson()));
  }
}
