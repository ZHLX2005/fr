// RemoteType 本地偏好：可编排快捷键（含序列宏）+ 历史输入 + 手柄按钮摆位。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'rt_constants.dart';

const _kShortcutsKeyV1 = 'rt_shortcuts_v1';
const _kShortcutsKeyV2 = 'rt_shortcuts_v2';
const _kHistoryKey = 'rt_input_history_v1';
const _kBarDisplayKey = 'rt_bar_display_v1';
const _kEnterModeKey = 'rt_enter_mode_v1';
const _kTouchpadSensitivityKey = 'rt_touchpad_sensitivity_v1';
const _kCanvasLayoutKey = 'rt_canvas_layout_v1';
const _kCanvasLayoutsKey = 'rt_canvas_layouts_v1';
const _kCanvasBuiltinFactoryRevKey = 'rt_canvas_builtin_factory_rev';

/// 内置预设 id（持久化键，禁止改动——改了等于丢用户当前布局）。
const String kRtCanvasPresetGame = 'game';

/// 轮盘布局（八向 dir8）；与 [kRtCanvasPresetGame] 方向键布局成对拆分。
const String kRtCanvasPresetGameWheel = 'game-wheel';
const String kRtCanvasPresetKeyboard = 'keyboard';
const String kRtCanvasPresetTouchpad = 'touchpad';

/// 内置预设：写字页（kind=writer，固定死不可编辑）。竖屏默认入口——
/// 连接后落到熟悉的打字页，横竖屏共用同一会话。
const String kRtCanvasPresetWriter = 'writer';

/// 已退役内置 id（旧盘可能仍出现；[rtEnsureBuiltinPresets] 会剔除）。
const String kRtCanvasPresetDefault = 'default';
const String kRtCanvasPresetTouchpadN = 'touchpad-n';

/// 已退役内置 id：输入页（连接后落到的打字页曾经做成画布里的满屏模块）。
/// 现在竖屏入口由固定死的「写字」布局接管——见 kRtCanvasPresetWriter。
const String kRtCanvasPresetInputPage = 'input-page';

/// 布局朝向（持久化字段，禁止改动取值）。横竖屏布局是两个隔离的集合：
/// 各有各的列表展示与激活位，互不串台。旧数据缺省按横屏读。
const String kRtCanvasOrientLandscape = 'landscape';
const String kRtCanvasOrientPortrait = 'portrait';

/// 模块 id（布局持久化的键，禁止改动——改了等于丢用户布局）。
const String kRtCanvasModuleTouchpad = 'touchpad';
const String kRtCanvasModuleInput = 'input';

/// 虚拟键盘（键盘布局主体：5 行 QWERTY + Fn 折叠，按键即发 hotkey）。
const String kRtCanvasModuleKb = 'kb';

/// 输入页（连接后落到的打字页整体：工具行 + 快捷键托盘 + composer）。
/// 竖屏默认布局的唯一模块；也可作为模块放进任意布局。
const String kRtCanvasModuleComposer = 'composer';

/// 方向轮盘（游戏布局的左手区：vpad_dpad 四向 + none 回中；可选八向补斜向）。
const String kRtCanvasModuleDpad = 'dpad';

/// 模拟摇杆（左 / 右）——补齐协议已支持（vpad_axis lx/ly/rx/ry）而手机端
/// 此前没有的能力：4 向轮盘只能「先上再右」，斜向走位的动作游戏多数不认。
const String kRtCanvasModuleStickL = 'stick-l';
const String kRtCanvasModuleStickR = 'stick-r';

/// 虚拟手柄键区（ABXY 面键 + LB/RB 肩键 + LT/RT 扳机，固定布局的模块）。
const String kRtCanvasModuleVpad = 'vpad';

/// 画布按钮形状：pill = 圆角胶囊（常规快捷键）；circle = 圆形（手柄键）。
enum RtCanvasButtonShape { pill, circle }

/// 布局种类：决定这一条布局由哪套渲染器接管。
///
/// RT 的所有布局都是「可插拔」的——页面按当前激活布局的 kind 选渲染路径，
/// 不再靠页面级布尔态（过去的 _canvasMode）切两套写死的页面：
///   · writer —— 写字页（固定形态，不做模块化编排；竖屏专属）
///   · canvas —— 画布（模块锚点 + 按钮位编排）
enum RtLayoutKind {
  writer,
  canvas;

  /// 持久化取值（禁止改动——改了等于丢用户布局）。
  String get id => switch (this) {
    RtLayoutKind.writer => 'writer',
    RtLayoutKind.canvas => 'canvas',
  };

  /// 读侧兜底：未知/缺省一律按画布（旧数据全是画布布局）。
  static RtLayoutKind fromId(String? raw) =>
      raw == 'writer' ? RtLayoutKind.writer : RtLayoutKind.canvas;
}

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
  RtChord.fromLegacy(List<String> legacy) : keys = List<String>.of(legacy);

  Map<String, dynamic> toJson() => {'keys': keys};

  factory RtChord.fromJson(Map<String, dynamic> j) {
    final raw = j['keys'];
    return RtChord(
      keys: raw is List ? raw.map((e) => e.toString()).toList() : const [],
    );
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
    return RtShortcutItem(
      id: id,
      label: label,
      chords: const [],
      intervalMs: 0,
    );
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
    this.dir8 = false,
  });

  final bool visible;
  final double x;
  final double y;

  /// 归一化宽高（相对画布，0..1）；null = 用模块内置默认（旧数据兼容）。
  final double? w;
  final double? h;

  /// 方向模式（仅轮盘模块有意义）：false = 四向（默认）；true = 八向补斜向。
  /// 稀疏持久化——四向不落字段，旧数据读入按缺省兜底。
  final bool dir8;

  RtCanvasAnchor copyWith({
    bool? visible,
    double? x,
    double? y,
    double? w,
    double? h,
    bool? dir8,
  }) => RtCanvasAnchor(
    visible: visible ?? this.visible,
    x: x ?? this.x,
    y: y ?? this.y,
    w: w ?? this.w,
    h: h ?? this.h,
    dir8: dir8 ?? this.dir8,
  );

  Map<String, dynamic> toJson() => {
    'v': visible,
    'x': x,
    'y': y,
    if (w != null) 'w': w,
    if (h != null) 'h': h,
    if (dir8) 'd8': true,
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
    dir8: j['d8'] == true,
  );

  static double? _clampFraction(dynamic v) =>
      v is num ? v.toDouble().clamp(0.05, 1.0).toDouble() : null;
}

/// 画布按钮尺寸倍率上下限（编辑拖动与持久化读入同一处钳制——单一事实源）。
const double kRtCanvasBtnScaleMin = 0.6;
const double kRtCanvasBtnScaleMax = 2.2;

/// 画布按钮位：归一化中心 + 尺寸倍率 + 画布内可见性 + 形状。
/// （快捷键的「有哪些」归打字页编辑器，「显示哪些」归这里的 v。）
class RtCanvasButtonPos {
  const RtCanvasButtonPos({
    required this.x,
    required this.y,
    this.s = 1.0,
    this.v = true,
    this.shape = RtCanvasButtonShape.pill,
  });

  final double x;
  final double y;

  /// 尺寸倍率（乘在按钮基准规格上）。
  final double s;

  /// 画布内可见性。仅当 id 已写入布局 buttons 时才参与渲染：
  /// v=true 使用态显示；v=false 编辑态幽灵可点回；未收录 = 任何形态都
  /// 不出现（编辑态也不出幽灵，收录入口在编辑工具面板「快捷键按钮」区）。
  final bool v;

  /// 形状：圆形（手柄键，短键名居中）/ 胶囊（默认，完整标签）。
  final RtCanvasButtonShape shape;

  RtCanvasButtonPos copyWith({
    double? x,
    double? y,
    double? s,
    bool? v,
    RtCanvasButtonShape? shape,
  }) => RtCanvasButtonPos(
    x: x ?? this.x,
    y: y ?? this.y,
    s: s ?? this.s,
    v: v ?? this.v,
    shape: shape ?? this.shape,
  );

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    's': s,
    'v': v,
    // 旧形状（胶囊）不写——旧版本读到未知 shape 字段也能按缺省兜底。
    if (shape == RtCanvasButtonShape.circle) 'shape': 'circle',
  };

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
        shape: j['shape'] == 'circle'
            ? RtCanvasButtonShape.circle
            : RtCanvasButtonShape.pill,
      );
}

/// 横屏画布命名布局。[orientation] 把布局钉在某一朝向：横竖屏是两个隔离
/// 的集合（各自展示、各自激活），自定义创建时二选一。
class RtCanvasNamedLayout {
  const RtCanvasNamedLayout({
    required this.id,
    required this.name,
    required this.builtIn,
    required this.data,
    this.orientation = kRtCanvasOrientLandscape,
    this.kind = RtLayoutKind.canvas,
    this.editable = true,
  });
  final String id;
  final String name;
  final bool builtIn;

  /// 横屏 / 竖屏（kRtCanvasOrient*）。旧数据缺省横屏。
  final String orientation;

  /// 这一条布局的渲染形态（画布 / 写字页）。
  final RtLayoutKind kind;

  /// 是否允许编排编辑。false = 固定死的默认布局（出厂代码即最终形态，
  /// 持久化里的改动一律忽略，用户也不能重命名/删除/改摆放）。
  final bool editable;

  final RtCanvasLayout data;
  RtCanvasNamedLayout copyWith({
    String? name,
    bool? builtIn,
    RtCanvasLayout? data,
    String? orientation,
    RtLayoutKind? kind,
    bool? editable,
  }) => RtCanvasNamedLayout(
    id: id,
    name: name ?? this.name,
    builtIn: builtIn ?? this.builtIn,
    data: data ?? this.data,
    orientation: orientation ?? this.orientation,
    kind: kind ?? this.kind,
    editable: editable ?? this.editable,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'builtIn': builtIn,
    // 横屏不落字段（旧版本读到未知 orientation 也能按缺省兜底）。
    if (orientation != kRtCanvasOrientLandscape) 'or': orientation,
    // 非画布布局才落 kind（画布是缺省值，省字段保兼容）。
    if (kind != RtLayoutKind.canvas) 'k': kind.id,
    // 可编辑是缺省值；只有固定死的布局才落 false。
    if (!editable) 'ed': false,
    'data': data.toJson(),
  };
  factory RtCanvasNamedLayout.fromJson(Map<String, dynamic> j) =>
      RtCanvasNamedLayout(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        builtIn: j['builtIn'] == true,
        orientation: j['or'] == kRtCanvasOrientPortrait
            ? kRtCanvasOrientPortrait
            : kRtCanvasOrientLandscape,
        kind: RtLayoutKind.fromId(j['k']?.toString()),
        editable: j['ed'] != false,
        data: RtCanvasLayout.fromJson(
          j['data'] is Map
              ? (j['data'] as Map).cast<String, dynamic>()
              : const <String, dynamic>{},
        ),
      );
}

/// 画布布局集：列表 + 分朝向激活 id。横竖屏各自记激活（隔离）；空表 =
/// 首跑由页面铺内置。
class RtCanvasLayouts {
  const RtCanvasLayouts({
    this.list = const [],
    this.activeId = kRtCanvasPresetTouchpad,
    this.activeIdPortrait = '',
  });
  final List<RtCanvasNamedLayout> list;

  /// 横屏激活布局 id。
  final String activeId;

  /// 竖屏激活布局 id。空 = 由 [activeFor] 兜底（真竖屏自定义 → 双朝向触控屏）。
  final String activeIdPortrait;

  /// 指定朝向的激活布局：横屏看 [activeId]，竖屏看 [activeIdPortrait]。
  /// 竖屏兜底顺序：真竖屏布局（内置输入页）→ 双朝向横屏布局（不锁横屏，
  /// 如触控屏）→ null；横屏兜底优先横屏条目（不落到竖屏布局）。
  RtCanvasNamedLayout? activeFor(String orientation) {
    final wantPortrait = orientation == kRtCanvasOrientPortrait;
    final id = wantPortrait ? activeIdPortrait : activeId;
    if (id.isNotEmpty) {
      for (final p in list) {
        if (p.id == id && rtCanvasLayoutUsableIn(orientation, p)) return p;
      }
    }
    if (wantPortrait) {
      for (final p in list) {
        if (p.orientation == kRtCanvasOrientPortrait) return p;
      }
      for (final p in list) {
        if (rtCanvasLayoutUsableIn(kRtCanvasOrientPortrait, p)) return p;
      }
      return null;
    }
    for (final p in list) {
      if (p.orientation == kRtCanvasOrientLandscape && p.kind != RtLayoutKind.writer) {
        return p;
      }
    }
    // 兜底也跳过写字页（横屏无写字形态）——否则横屏会落到一张写字页。
    for (final p in list) {
      if (p.kind != RtLayoutKind.writer) return p;
    }
    return null;
  }

  RtCanvasNamedLayout? get active => activeFor(kRtCanvasOrientLandscape);
  RtCanvasLayout get activeData => active?.data ?? const RtCanvasLayout();

  /// 该 id 对应布局所属朝向（查不到回横屏）。
  String orientationOf(String id) {
    for (final p in list) {
      if (p.id == id) return p.orientation;
    }
    return kRtCanvasOrientLandscape;
  }

  RtCanvasLayouts withActive(String id) => withActiveFor(orientationOf(id), id);

  /// 切换指定朝向的激活布局（id 须在该朝向可用——含双朝向触控屏）。
  RtCanvasLayouts withActiveFor(String orientation, String id) {
    final hit = list.any(
      (p) => p.id == id && rtCanvasLayoutUsableIn(orientation, p),
    );
    if (!hit) return this;
    if (orientation == kRtCanvasOrientPortrait) {
      if (activeIdPortrait == id) return this;
      return RtCanvasLayouts(
        list: list,
        activeId: activeId,
        activeIdPortrait: id,
      );
    }
    if (activeId == id) return this;
    return RtCanvasLayouts(
      list: list,
      activeId: id,
      activeIdPortrait: activeIdPortrait,
    );
  }

  RtCanvasLayouts withList(List<RtCanvasNamedLayout> list) => RtCanvasLayouts(
    list: list,
    activeId: activeId,
    activeIdPortrait: activeIdPortrait,
  );

  /// 更新指定朝向当前激活布局的数据。
  RtCanvasLayouts withUpdatedActiveFor(
    String orientation,
    RtCanvasLayout data,
  ) {
    final cur = activeFor(orientation);
    if (cur == null) return this;
    final next = <RtCanvasNamedLayout>[];
    var replaced = false;
    for (final p in list) {
      if (!replaced && p.id == cur.id) {
        next.add(p.copyWith(data: data));
        replaced = true;
      } else {
        next.add(p);
      }
    }
    return RtCanvasLayouts(
      list: next,
      activeId: activeId,
      activeIdPortrait: activeIdPortrait,
    );
  }

  RtCanvasLayouts withUpdatedActive(RtCanvasLayout data) =>
      withUpdatedActiveFor(kRtCanvasOrientLandscape, data);

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
    return hit
        ? RtCanvasLayouts(
            list: next,
            activeId: activeId,
            activeIdPortrait: activeIdPortrait,
          )
        : this;
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
    if (activeIdPortrait.isNotEmpty) 'activeN': activeIdPortrait,
  };
  factory RtCanvasLayouts.fromJson(Map<String, dynamic> j) {
    final rawList = j['list'];
    final list = <RtCanvasNamedLayout>[];
    if (rawList is List) {
      for (final e in rawList.whereType<Map>()) {
        final entry = RtCanvasNamedLayout.fromJson(e.cast<String, dynamic>());
        if (entry.id.isEmpty || entry.name.isEmpty) continue;
        list.add(entry);
      }
    }
    final rawActive = j['activeId']?.toString() ?? '';
    final activeId = list.any((p) => p.id == rawActive)
        ? rawActive
        : kRtCanvasPresetTouchpad;
    // 竖屏激活：存盘值在竖屏可用（真竖屏或双朝向触控屏）才用；否则
    // 兜底第一条竖屏可用（再没有就留空，读侧 activeFor 继续兜）。
    final rawActiveN = j['activeN']?.toString() ?? '';
    var activeIdPortrait = '';
    if (rawActiveN.isNotEmpty) {
      for (final p in list) {
        if (p.id == rawActiveN &&
            rtCanvasLayoutUsableIn(kRtCanvasOrientPortrait, p)) {
          activeIdPortrait = rawActiveN;
          break;
        }
      }
    }
    if (activeIdPortrait.isEmpty) {
      // 优先真竖屏条目，再退到双朝向（触控屏）——与 activeFor 兜底顺序一致。
      for (final p in list) {
        if (p.orientation == kRtCanvasOrientPortrait) {
          activeIdPortrait = p.id;
          break;
        }
      }
    }
    if (activeIdPortrait.isEmpty) {
      for (final p in list) {
        if (rtCanvasLayoutUsableIn(kRtCanvasOrientPortrait, p)) {
          activeIdPortrait = p.id;
          break;
        }
      }
    }
    return RtCanvasLayouts(
      list: list,
      activeId: activeId,
      activeIdPortrait: activeIdPortrait,
    );
  }
}

/// 横屏画布布局：模块（触摸板 / 输入框 / 键盘 / 轮盘 / 手柄键区）锚点 + 按钮位。
/// 空表 = 首跑，画布用内置默认布局。删掉的按钮残位无害（同 id 回归原位）。
class RtCanvasLayout {
  const RtCanvasLayout({
    this.modules = const {},
    this.buttons = const {},
    this.hideShortcuts = false,
  });

  final Map<String, RtCanvasAnchor> modules;
  final Map<String, RtCanvasButtonPos> buttons;

  /// true = 此布局不渲染快捷键按钮（游戏布局 = 纯手柄，按钮区归 vpad 模块）。
  final bool hideShortcuts;

  RtCanvasLayout withModule(String id, RtCanvasAnchor anchor) => RtCanvasLayout(
    modules: Map.of(modules)..[id] = anchor,
    buttons: buttons,
    hideShortcuts: hideShortcuts,
  );

  RtCanvasLayout withButton(String id, RtCanvasButtonPos pos) => RtCanvasLayout(
    modules: modules,
    buttons: Map.of(buttons)..[id] = pos,
    hideShortcuts: hideShortcuts,
  );

  Map<String, dynamic> toJson() => {
    'modules': {for (final e in modules.entries) e.key: e.value.toJson()},
    'buttons': {for (final e in buttons.entries) e.key: e.value.toJson()},
    if (hideShortcuts) 'hs': true,
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
    return RtCanvasLayout(
      modules: modules,
      buttons: buttons,
      hideShortcuts: j['hs'] == true,
    );
  }
}

/// 该布局是否「锁定横屏」（竖屏下不可用，旋转过去要弹提示层而不是静默
/// 切换）：判定 = 含任何可见的横屏专用操作模块（轮盘 / 手柄键区 / 虚拟
/// 键盘——这些模块的键位排布以横屏双手拇指位为前提）。触摸板 / 输入框 /
/// 快捷按钮布局旋转时静默切对侧激活。纯函数，规则改动须同步单测。
bool rtCanvasLayoutLocksLandscape(RtCanvasLayout data) {
  const lockedModules = {
    kRtCanvasModuleDpad,
    kRtCanvasModuleVpad,
    kRtCanvasModuleKb,
  };
  for (final e in data.modules.entries) {
    if (lockedModules.contains(e.key) && e.value.visible) return true;
  }
  return false;
}

/// 布局在指定朝向是否可用：同朝向条目；或竖屏下「不锁横屏」的横屏条目
/// （原型触控屏双朝向）。写字页（kind=writer）只属竖屏——横屏下不可用。
/// 纯函数，规则改动须同步单测。
bool rtCanvasLayoutUsableIn(String orientation, RtCanvasNamedLayout entry) {
  // 写字页固定竖屏：横屏没有写字页形态（横屏只有画布）。
  if (entry.kind == RtLayoutKind.writer) {
    return orientation == kRtCanvasOrientPortrait;
  }
  if (entry.orientation == orientation) return true;
  return orientation == kRtCanvasOrientPortrait &&
      entry.orientation == kRtCanvasOrientLandscape &&
      !rtCanvasLayoutLocksLandscape(entry.data);
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
      return RtBarDisplay.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return RtBarDisplay.defaults;
    }
  }

  static Future<void> saveBarDisplay(RtBarDisplay d) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBarDisplayKey, jsonEncode(d.toJson()));
  }

  /// 回车注入方式：'enter' = 发送 / 'shift_enter' = 换行。
  ///
  /// 这对开关原是写字页工具行上的两颗小按钮（页面级内存态，切走即丢）。
  /// 现在归到 RT 设置里持久化——换行/发送是「我在哪个 App 里打字」的偏好，
  /// 不该每次进页面重选。
  static Future<String> loadEnterMode() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kEnterModeKey);
    return raw == 'shift_enter' ? 'shift_enter' : 'enter';
  }

  static Future<void> saveEnterMode(String mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kEnterModeKey, mode == 'shift_enter' ? 'shift_enter' : 'enter');
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
    final v = value
        .clamp(kRtPadSensitivityMin, kRtPadSensitivityMax)
        .toDouble();
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
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        // 坏形落入迁移分支（旧 key 可能仍有效）。
      }
    }
    final oldRaw = p.getString(_kCanvasLayoutKey);
    if (oldRaw != null && oldRaw.isNotEmpty) {
      try {
        final old = RtCanvasLayout.fromJson(
          jsonDecode(oldRaw) as Map<String, dynamic>,
        );
        final migrated = RtCanvasLayouts(
          list: [
            RtCanvasNamedLayout(
              id: 'imported',
              name: '导入布局',
              builtIn: false,
              data: old,
            ),
          ],
          activeId: 'imported',
        );
        await p.setString(_kCanvasLayoutsKey, jsonEncode(migrated.toJson()));
        return migrated;
      } catch (_) {}
    }
    return const RtCanvasLayouts();
  }

  static Future<void> saveCanvasLayouts(RtCanvasLayouts layouts) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCanvasLayoutsKey, jsonEncode(layouts.toJson()));
  }

  /// 内置出厂锚点修订号（缺省 0 = 从未对齐过原型 LAYOUTS）。
  static Future<int> loadCanvasBuiltinFactoryRev() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kCanvasBuiltinFactoryRevKey) ?? 0;
  }

  static Future<void> saveCanvasBuiltinFactoryRev(int rev) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kCanvasBuiltinFactoryRevKey, rev);
  }
}
