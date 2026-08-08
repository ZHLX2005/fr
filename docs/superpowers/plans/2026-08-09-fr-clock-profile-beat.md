# fr 三簇修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 fr 项目 kvcli todo `fr` topic 的 4 条待办——profile banner 切换闪屏(#3)、beat 冷启动默认声(#2)、clock demo 中文化+删除守卫+zen 主题(#1,#4)。

**Architecture:** 三簇相互独立，按 C→B→A 顺序实现，每簇独立 commit+push 并回填对应 `kvcli todo done`。C 用 banner 路径 app 级预热消除 State 重建占位帧；B 把 metronome 声音槽还原下沉到 app 启动路径（accent 槽默认木鱼 + 还原用户 prefs 配置）；A 全 demo 文案中译 + `record.completed` 删除守卫 + ZenColors 套用漏网组件。

**Tech Stack:** Flutter (Dart), provider, shared_preferences, Oboe FFI metronome 单例, zen_theme 静态设计系统, EmphasisButton。

## Global Constraints

- 每簇完成后 `flutter analyze` 必须 **0 新增 error/warning**（基线：当前 master 干净）。
- 每簇 analyze 干净后立即 `git add/commit/push`（[[feedback_autocommit_on_fix]]）。
- 每簇完成后 `kvcli todo done <id> --result "..."` 回填（id 以 `kvcli todo list --topic fr` 的 open 为准，当前 #1#2#3#4；簇 C→#3、B→#2、A→#1+#4）。
- 文案中译；**不译**单位记号：`bpm`/`BPM`、滚轮 `h`/`m`/`s`、拍号 `1/4`·`2/4`。
- 遵循现有 `zen_theme`（静态 `ZenColors`，须显式引用）/`EmphasisButton.borderEmphasis` 模式，不改设计系统语义。
- 颜色常量：`ZenColors.sage`(主绿 0xFF7A9A7E)、`mutedRed`(破坏色)、`surface`(卡面 0xFFFBF8F1)、`bg`(米色 0xFFF4F1EA)。
- Flutter 命令在仓库根 `D:\code\a_dart\prj\fr` 执行。

---

# Part C — profile banner 切换闪屏（#3）

**根因（已读码确认）：** `lib/main.dart:251-284` 传送带切换，`_pages` 是 const 列表，动画时同一页挂到树的不同位置 → `canUpdate` 失败 → 离场页 State 销毁、新建。新 State `_bannerPath=null`（`profile_page.dart:85-96` 异步 `_loadBanner`），切走时离场的全新 State 露出 `_buildDefaultBanner` 占位 = 用户看到的"切出退化"。

**修法：** banner 路径 app 级预热，`ProfilePage` 建建时同步可取，消除 null 占位帧。不动切换动画、不影响另两个 tab。

## Task C1: 新增 banner 路径预热缓存 + 单测

**Files:**
- Modify: `lib/screens/profile/profile_page.dart`（顶部加 `HomeBannerCache` 类）
- Test: `test/screens/home_banner_cache_test.dart`（新建）

**Interfaces:**
- Produces: `HomeBannerCache.warmUp() -> Future<void>`、`HomeBannerCache.path -> String?`、`HomeBannerCache.ready -> bool`、`HomeBannerCache.refresh(String?) -> void`

- [ ] **Step 1: 写失败测试**

```dart
// test/screens/home_banner_cache_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/screens/profile/profile_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HomeBannerCache.resetForTest();
  });

  test('warmUp 读 home_banner_path 填 path 并置 ready', () async {
    SharedPreferences.setMockInitialValues({'home_banner_path': '/x/banner.jpg'});
    await HomeBannerCache.warmUp();
    expect(HomeBannerCache.path, '/x/banner.jpg');
    expect(HomeBannerCache.ready, isTrue);
  });

  test('warmUp 无值时 path=null 但 ready=true', () async {
    await HomeBannerCache.warmUp();
    expect(HomeBannerCache.path, isNull);
    expect(HomeBannerCache.ready, isTrue);
  });

  test('warmUp 幂等，二次不重读', () async {
    SharedPreferences.setMockInitialValues({'home_banner_path': '/a'});
    await HomeBannerCache.warmUp();
    SharedPreferences.setMockInitialValues({'home_banner_path': '/b'}); // 改了也不该变
    await HomeBannerCache.warmUp();
    expect(HomeBannerCache.path, '/a');
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/screens/home_banner_cache_test.dart`
Expected: FAIL — `HomeBannerCache` 未定义。

- [ ] **Step 3: 实现 HomeBannerCache**

在 `lib/screens/profile/profile_page.dart` 文件级（class 外，建议放 import 后、`ProfilePage` class 前）加：

```dart
/// App 级 banner 路径缓存。
///
/// 为何需要：首页传送带切换（main.dart）会让 ProfilePage 的 State 销毁重建，
/// 新 State 的 `_bannerPath` 要异步读 SharedPreferences，期间露出占位渐变 =
/// 切换闪屏。这里在 app 启动时预热一次，State 建建时同步可取，消除占位帧。
class HomeBannerCache {
  HomeBannerCache._();

  static const String key = 'home_banner_path';

  static String? path;
  static bool ready = false;

  /// 启动时调一次（幂等）。从 SharedPreferences 读 banner 路径填入 [path]。
  static Future<void> warmUp() async {
    if (ready) return;
    final prefs = await SharedPreferences.getInstance();
    path = prefs.getString(key);
    ready = true;
  }

  /// 用户设置/更换 banner 后调，同步更新缓存。
  static void refresh(String? newPath) {
    path = newPath;
    ready = true;
  }

  /// 测试专用：重置缓存。
  @visibleForTesting
  static void resetForTest() {
    path = null;
    ready = false;
  }
}
```

需确保文件顶部已 `import 'package:flutter/foundation.dart';`（`@visibleForTesting`）；若未 import 则加。

- [ ] **Step 4: 运行测试，确认通过**

Run: `flutter test test/screens/home_banner_cache_test.dart`
Expected: PASS（3 用例）。

## Task C2: ProfilePage.initState 接入缓存

**Files:**
- Modify: `lib/screens/profile/profile_page.dart:85-96`（`initState` + `_loadBanner`）+ `_saveBanner` 等写入处调 `refresh`

**Interfaces:**
- Consumes: `HomeBannerCache`（C1 产出）

- [ ] **Step 1: 改 initState 同步取缓存**

把 `_ProfilePageState.initState`（约 85-89 行）改为：

```dart
@override
void initState() {
  super.initState();
  // 同步取预热值（消除切换 State 重建的占位帧）；预热未完成则等其完成再刷新。
  _bannerPath = HomeBannerCache.path;
  if (!HomeBannerCache.ready) {
    HomeBannerCache.warmUp().then((_) {
      if (mounted) setState(() => _bannerPath = HomeBannerCache.path);
    });
  }
}
```

- [ ] **Step 2: `_loadBanner` 保留为兜底，写入缓存**

`_loadBanner`（约 91-96 行）保留（设置 banner 后的刷新路径仍可用），但把读到的值同步进缓存：

```dart
Future<void> _loadBanner() async {
  await HomeBannerCache.warmUp();
  if (!mounted) return;
  setState(() {
    _bannerPath = HomeBannerCache.path;
  });
}
```

- [ ] **Step 3: 所有写入 banner path 的地方调 `HomeBannerCache.refresh`**

grep 出 `prefs.setString(_bannerKey` 或 `_bannerPath =` 的赋值点（`_saveBanner` 及裁剪页回传处），在 `prefs.setString` 成功后加 `HomeBannerCache.refresh(path);`，保证缓存与 prefs 一致。（若 `banner_crop_page` 等它处也写 `home_banner_path`，同样补 `refresh`，或在 ProfilePage 重新可见时 `warmUp` 兜底——以 grep 实际为准。）

- [ ] **Step 4: flutter analyze + test**

Run: `flutter analyze lib/screens/profile/profile_page.dart test/screens/home_banner_cache_test.dart && flutter test test/screens/home_banner_cache_test.dart`
Expected: analyze 0 issues；test PASS。

## Task C3: main.dart 启动接入预热

**Files:**
- Modify: `lib/main.dart`（`_MainScreenState.initState`，约 199-219 行）+ 顶部 import

- [ ] **Step 1: import**

在 `main.dart` 顶部 import 区加：

```dart
import 'screens/profile/profile_page.dart';
```

（若已存在则跳过；注意只 import 需要的 `HomeBannerCache`，profile_page.dart 若有副作用按现有依赖处理。）

- [ ] **Step 2: initState 调 warmUp**

在 `_MainScreenState.initState`（约 200 行 `super.initState();` 之后）加 fire-and-forget 预热：

```dart
HomeBannerCache.warmUp(); // 预热 banner 路径，消除首页切换闪屏
```

放在 `AnimationController` 创建之前或之后均可（异步、不阻塞）。

- [ ] **Step 3: 全量 analyze**

Run: `flutter analyze`
Expected: 0 新增 issue。

## Task C4: 真机验证 + commit + todo done

- [ ] **Step 1: 真机/模拟器验证（交给用户）**

冷启动 → 进首页 profile（banner 正常）→ 切到 time → 切回 profile：**不应再出现 banner 退化占位帧**。设置新 banner 后切换同样不闪。

- [ ] **Step 2: commit + push**

```bash
git add lib/main.dart lib/screens/profile/profile_page.dart test/screens/home_banner_cache_test.dart
git commit -m "fix(profile): banner 路径 app 级预热消除切换闪屏

传送带切换销毁重建 ProfilePage State，新 State banner 异步加载露占位。
新增 HomeBannerCache 启动预热，initState 同步取值。3 单测。
kvcli fr #3."
git push
```

- [ ] **Step 3: 回填 todo**

```bash
kvcli todo done 3 --result "banner 闪屏修复: HomeBannerCache 启动预热(main.dart initState), ProfilePage initState 同步取值消除切换占位帧, 3 单测过, analyze 干净。需真机验证切换不闪。commit <hash>"
```

---

# Part B — beat 冷启动默认声（#2）

**根因（已读码确认）：** `LabClockProvider` 构造（`lab_clock_provider.dart:34`）只 `MetronomeService.instance.ensureReady()` init Oboe 流，**未挂采样**，3 槽空 → beat 经共享单例命中 C++ 合成 click。木鱼挂载只在 metronome 页 `metronome_demo.dart:70-80 _restoreSoundSlots`（读 `metronome_slot_$level`）发生。`SampleLoader.mountDefaults()`（挂 accent 木鱼）是写好却无人调用的死代码。

**修法（用户拍板：还原用户全部 3 槽 + 默认 accent 木鱼）：** 给 `SampleLoader` 加 `restoreAtStartup()`——读 prefs `metronome_slot_0/1/2`，`1`=木鱼则挂载、`0`/null 则按默认（accent 槽默认木鱼，weak/medium 默认合成）处理。LabClockProvider 构造 ensureReady 后 fire-and-forget 调用。

## Task B1: SampleLoader.restoreAtStartup + 单测

**Files:**
- Modify: `lib/lab/demos/metronome/sample_loader.dart`（加 `restoreAtStartup` + 纯函数 `resolveSoundId`/`slotDefault`）
- Test: `test/lab/sample_loader_restore_test.dart`（新建）

**Interfaces:**
- Produces: `SampleLoader.restoreAtStartup() -> Future<void>`、`SampleLoader.slotDefault(int level) -> int`、`SampleLoader.resolveSoundId(int? saved, int level) -> int`

- [ ] **Step 1: 写失败测试（纯逻辑，不碰 FFI）**

```dart
// test/lab/sample_loader_restore_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/metronome/sample_loader.dart';

void main() {
  group('slot 默认值', () {
    test('weak/medium 默认合成(0)，accent 默认木鱼(1)', () {
      expect(SampleLoader.slotDefault(0), 0);
      expect(SampleLoader.slotDefault(1), 0);
      expect(SampleLoader.slotDefault(2), 1);
    });
  });

  group('resolveSoundId', () {
    test('用户存了木鱼(1) → 1', () {
      expect(SampleLoader.resolveSoundId(1, 0), 1);
    });
    test('用户存了合成(0) → 0（尊重用户显式选择）', () {
      expect(SampleLoader.resolveSoundId(0, 2), 0);
    });
    test('没存过 → 用默认（accent=1，其余=0）', () {
      expect(SampleLoader.resolveSoundId(null, 2), 1);
      expect(SampleLoader.resolveSoundId(null, 0), 0);
    });
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/lab/sample_loader_restore_test.dart`
Expected: FAIL — `slotDefault`/`resolveSoundId` 未定义。

- [ ] **Step 3: 实现纯函数 + restoreAtStartup**

在 `sample_loader.dart` import 区加 `import 'package:shared_preferences/shared_preferences.dart';`。

在 `SampleLoader` 类内（`mountAssetTo` 之后、`resetForTest` 之前）加：

```dart
// ==================== 启动期声音还原（修 beat 冷启动默认声 bug）====================

/// 各 accent 槽的默认 soundId：weak=合成, medium=合成, accent=木鱼。
/// 为何 accent 默认木鱼：clock 的 beat 强拍在 accent 槽，冷启动直进 clock→beat
/// 必须有木鱼（任务 #2），即使用户从没进过 metronome。
static const List<int> _slotDefaults = [0, 0, 1];

/// 某槽的默认 soundId。
static int slotDefault(int level) =>
    level >= 0 && level < _slotDefaults.length ? _slotDefaults[level] : 0;

/// 结合用户 SharedPreferences 存值与默认，得到该槽应使用的 soundId。
/// saved=null（没存过）→ 用默认；saved!=null → 尊重用户显式选择。
static int resolveSoundId(int? saved, int level) =>
    saved ?? slotDefault(level);

static const String _slotKeyPrefix = 'metronome_slot_';

/// App 启动时调一次（幂等）。把用户在 metronome 页配过的声音槽还原到
/// 共享 FFI 单例，等价于"自动进过一次 metronome"，冷启动直进 clock→beat
/// 也能听到正确音色。accent 槽默认木鱼，无需用户配置。
static Future<void> restoreAtStartup() async {
  if (_startupRestored) return;
  _startupRestored = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    for (var level = 0; level < 3; level++) {
      final saved = prefs.getInt('$_slotKeyPrefix$level');
      final soundId = resolveSoundId(saved, level);
      if (soundId == 1) {
        final path = await materializeAsset('assets/audio/woodfish.wav');
        MetronomeFFI.loadSample(level, path);
      } else {
        MetronomeFFI.clearSample(level);
      }
    }
  } catch (_) {
    // 失败回退：允许下次重试（如进入 metronome 页时）。
    _startupRestored = false;
  }
}

static bool _startupRestored = false;
```

在 `resetForTest` 里追加 `_startupRestored = false;`：

```dart
static void resetForTest() {
  _extractedCache.clear();
  _defaultsMounted = false;
  _startupRestored = false;
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `flutter test test/lab/sample_loader_restore_test.dart`
Expected: PASS（5 用例）。

## Task B2: LabClockProvider 构造接入

**Files:**
- Modify: `lib/lab/demos/clock/providers/lab_clock_provider.dart:28-45`

- [ ] **Step 1: import**

文件已 import `metronome_service.dart`；补 import（若未存在）：

```dart
import '../../metronome/sample_loader.dart';
```

- [ ] **Step 2: 构造里 ensureReady 后调 restoreAtStartup**

在构造函数 `MetronomeService.instance.ensureReady();`（第 34 行）之后加：

```dart
// 冷启动即还原用户声音槽到共享 FFI 单例，这样不先进 metronome 页、
// 直进 clock→beat 也能听到木鱼（修 beat 默认声 bug，fr #2）。
SampleLoader.restoreAtStartup();
```

（fire-and-forget，不 await——构造函数不能 await，且不阻塞 UI。）

- [ ] **Step 3: analyze + test**

Run: `flutter analyze lib/lab/demos && flutter test test/lab/sample_loader_restore_test.dart`
Expected: analyze 0 issues；test PASS。

## Task B3: 真机验证 + commit + todo done

- [ ] **Step 1: 真机验证（交给用户）**

清除 app 数据（或确保 `metronome_slot_*` 无值）→ 冷启动 → **直接进 clock → 启动一个 clock 的 beat**：强拍应听到**木鱼**（非系统合成 click）。再进 metronome 把弱拍设成木鱼 → 杀进程冷启动 → 直进 clock→beat：弱拍也应有木鱼。

- [ ] **Step 2: commit + push**

```bash
git add lib/lab/demos/metronome/sample_loader.dart lib/lab/demos/clock/providers/lab_clock_provider.dart test/lab/sample_loader_restore_test.dart
git commit -m "fix(clock): beat 冷启动还原声音槽到共享 FFI 单例

LabClockProvider 构造 ensureReady 后调 SampleLoader.restoreAtStartup,
读 metronome_slot_0/1/2 还原用户配置, accent 槽默认木鱼。
冷启动直进 clock→beat 不再播合成默认声。5 单测过。
kvcli fr #2."
git push
```

- [ ] **Step 3: 回填 todo**

```bash
kvcli todo done 2 --result "beat 冷启动默认声修复: SampleLoader.restoreAtStartup (读 metronome_slot_N 还原+accent默认木鱼), LabClockProvider 构造接入。冷启动直进 clock→beat 听木鱼。5 单测过, analyze 干净。commit <hash>"
```

---

# Part A — clock demo 中文化 + 删除守卫 + zen 主题（#1, #4）

## Task A1: clock demo 全量中文化（#1 前半）

**Files (按 subagent 行号清单逐文件替换):**
- `lib/lab/demos/clock_demo.dart`
- `lib/lab/demos/clock/widgets/clocks_tab.dart`
- `lib/lab/demos/clock/widgets/clock_editor_sheet.dart`
- `lib/lab/demos/clock/widgets/tracks_tab.dart`
- `lib/lab/demos/clock/widgets/track_runner_page.dart`
- `lib/lab/demos/clock/widgets/track_editor_page.dart`
- `lib/lab/demos/clock/widgets/track_records_page.dart`
- `lib/lab/demos/clock/widgets/dashboard_tab.dart`

**映射要点（代表项，执行时按 grep 实际行号全替，保持中文自然）：**

| 英文 | 中文 |
|---|---|
| `Clock` / `Clocks` / `Tracks` / `Dashboard` | 时钟 / 时钟 / 编排 / 仪表盘 |
| `Wipe all clock data` / `Wipe` / `All clock data wiped.` | 清空所有时钟数据 / 清空 / 已清空所有时钟数据。 |
| `Records` / `No records yet.` / `No clocks yet` / `Add clock` | 记录 / 暂无记录 / 暂无时钟 / 添加时钟 |
| `Delete clock` / `Delete "X"?` / `Delete` / `Create` | 删除时钟 / 删除"X"？ / 删除 / 新建 |
| `Rename record` / `Cancel` / `Save` | 重命名记录 / 取消 / 保存 |
| `Enter rounds and duration` / `all strong` / `strong-weak` | 输入轮数和时长 / 全强拍 / 强-弱拍 |
| `Add clock` / `Edit clock` / `New clock` / `Add` / `Save` / `Cancel` | 添加时钟 / 编辑时钟 / 新时钟 / 添加 / 保存 / 取消 |
| `Title` / `Description` / `Duration` / `Color` / `Beat` / `Total rounds` / `Mode` | 标题 / 描述 / 时长 / 颜色 / 节拍 / 总轮数 / 模式 |
| `1 beat / round` / `all strong (inhale)` / `2 beats / round` / `strong-weak (inhale-exhale)` | 每轮 1 拍 / 全强拍（吸气）/ 每轮 2 拍 / 强弱拍（吸-呼） |
| `1beat` / `2beat` | 单拍 / 双拍 |
| `No tracks yet` / `Run` / `Edit` / `Delete track` | 暂无编排 / 开始 / 编辑 / 删除编排 |
| `Track` / `Empty track` / `Segment N of M` / `Segment` / `Total remaining: ...` / `Resume` / `Pause` / `Skip` / `Stop` | 编排 / 空编排 / 第 N 段（共 M 段）/ 段 / 剩余总时长：… / 继续 / 暂停 / 跳过 / 停止 |
| `New track` / `Edit track` / `Source` / `No clocks — add some first.` / `Sequence` / `Tap a clock above to add to the track` / `Move up` / `Move down` / `Remove` / `Total` | 新建编排 / 编辑编排 / 来源 / 暂无时钟——先添加一个。 / 序列 / 点上方时钟加入编排 / 上移 / 下移 / 移除 / 合计 |
| `Track records` / `Clear` / `No track records yet` / `Clear track records` / `Clear all track records? This cannot be undone.` / `Rename record` | 编排记录 / 清空 / 暂无编排记录 / 清空编排记录 / 清空所有编排记录？此操作不可撤销。 / 重命名记录 |
| `Today` / `Clocks done` / `Tracks done` / `Recent` / `actual ...` | 今天 / 完成时钟 / 完成编排 / 最近 / 实际 … |

**不译：** `bpm`/`BPM`、滚轮 `h`/`m`/`s`、拍号 `1/4`·`2/4`、preview 模板里的 `s/beat`、`rounds`、`BPM` 单位片段。

- [ ] **Step 1: 逐文件 grep 英文并替换**

按上表 + `grep -nE "'[A-Za-z]"` 扫每个文件，把 UI 可见英文文案改中文。preview 拼接模板（如 `$_rounds rounds · $bpm BPM · ${secondsPerBeat}s/beat · $rhythm`）改成中文："$_rounds 轮 · $bpm BPM · ${secondsPerBeat}秒/拍 · $rhythm"。

- [ ] **Step 2: flutter analyze**

Run: `flutter analyze lib/lab/demos/clock lib/lab/demos/clock_demo.dart`
Expected: 0 issues。

- [ ] **Step 3: 真机目视（交给用户）**

进 clock demo → Clocks / Tracks / Dashboard 三个 tab + 新建/编辑 Sheet + Runner 全路径：无残留英文（单位记号除外）。

## Task A2: 记录删除守卫 — 运行中/暂停禁删（#1 后半）

**Files:**
- Modify: `lib/lab/demos/clock/widgets/clocks_tab.dart:382-396`（记录 swipe Delete）
- Modify: `lib/lab/demos/clock/widgets/track_records_page.dart:98-102`（track 记录删除）
- Modify: `lib/lab/demos/clock/providers/lab_clock_provider.dart`（加 `canDeleteRecord` 纯函数便于复用+测试）

**Interfaces:**
- Produces: `LabClockProvider.canDeleteRecord(LabClockRecord r) -> bool`（= `r.completed`）

- [ ] **Step 1: 写失败测试**

```dart
// test/lab/clock_delete_guard_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock_record.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';

void main() {
  group('canDeleteRecord', () {
    test('已完成的记录可删', () {
      final r = LabClockRecord(id: 'a', endTime: DateTime(2026), completed: true);
      expect(LabClockProvider.canDeleteRecord(r), isTrue);
    });
    test('运行中/暂停（未完成）的记录不可删', () {
      final r = LabClockRecord(id: 'a', endTime: null, completed: false);
      expect(LabClockProvider.canDeleteRecord(r), isFalse);
    });
    test('提前结算未完成的记录不可删', () {
      final r = LabClockRecord(id: 'a', endTime: DateTime(2026), completed: false);
      expect(LabClockProvider.canDeleteRecord(r), isFalse);
    });
  });
}
```

> 执行时先 `Read` `lab_clock_record.dart` 确认 `LabClockRecord` 构造参数名/默认值，按实际补齐字段（上面是占位字段名，须以真实模型为准）。

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/lab/clock_delete_guard_test.dart`
Expected: FAIL — `canDeleteRecord` 未定义 / 构造参数不匹配。

- [ ] **Step 3: provider 加 canDeleteRecord**

在 `LabClockProvider`（`lab_clock_provider.dart`）加静态方法（不依赖实例，便于测试）：

```dart
/// 只有已完成的记录允许删除；运行中/暂停/提前结算未完成的都禁止。
/// 详见 fr #1：clock 记录删除守卫。
static bool canDeleteRecord(LabClockRecord r) => r.completed;
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `flutter test test/lab/clock_delete_guard_test.dart`
Expected: PASS。

- [ ] **Step 5: clocks_tab.dart Delete onTap 加守卫**

`clocks_tab.dart:382-396` 的记录 swipe Delete `onTap`，在 `p.deleteRecord(record.id);` 前加守卫：

```dart
onTap: () {
  setState(() { _offsetX = 0; _isExpanded = false; });
  if (!p.canDeleteRecord(record)) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('运行中或暂停的记录不可删除，请先完成')));
    return;
  }
  p.deleteRecord(record.id);
},
```

- [ ] **Step 6: track_records_page.dart 删除加守卫**

`track_records_page.dart:98-102` track 记录删除入口同样加守卫（track 记录也是 `completed` 字段，复用 `LabClockProvider.canDeleteRecord` 或对应 track provider 的等价判定；以实际 provider 为准，若 track 用独立 `LabTrackRecord` 则加 `canDeleteTrackRecord`）。提示文案同上。

- [ ] **Step 7: flutter analyze**

Run: `flutter analyze lib/lab/demos/clock`
Expected: 0 issues。

- [ ] **Step 8: 真机验证（交给用户）**

clock：运行中的记录左滑 Delete → 弹"运行中…不可删除"且不删；已完成记录正常删。track 记录同理。

## Task A3: zen 主题漏网组件（#4）

**Files:**
- Modify: `lib/lab/demos/clock/clock_demo.dart:184-193`（FAB 颜色）
- Modify: `lib/widgets/theme/zen_theme.dart:413-447`（ZenConfirmDialog 背景 + Cancel 色）
- Modify: `lib/lab/demos/clock/widgets/track_records_page.dart:111-128`（Rename 裸 AlertDialog）
- Modify: `lib/lab/demos/clock/widgets/clocks_tab.dart:434-451`（Rename 裸 AlertDialog）

- [ ] **Step 1: clock_demo FAB 改 sage**

`clock_demo.dart:184-193`，FAB 的 `EmphasisButton.borderEmphasis` 的 `color` 由 `Theme.of(context).colorScheme.primary` 改为 `ZenColors.sage`：

```dart
style: EmphasisButton.borderEmphasis(
  context,
  color: ZenColors.sage,
),
```

确认文件已 import `zen_theme.dart` 的 `ZenColors`（同文件其它处已用 zen，应已 import）。

- [ ] **Step 2: ZenConfirmDialog 套 zen 色**

`zen_theme.dart:413-447` 的内部 `AlertDialog` 加 `backgroundColor: ZenColors.surface`；Cancel 的 `TextButton` 文字色设为 `ZenColors.secondary`（或 zen 惯用的弱化色）。确认按钮已用 `ZenColors.mutedRed`，保留。示例：

```dart
AlertDialog(
  backgroundColor: ZenColors.surface,
  // ...
  actions: [
    TextButton(
      onPressed: onCancel,
      child: Text(cancelLabel, style: TextStyle(color: ZenColors.secondary)),
    ),
    TextButton(
      onPressed: onConfirm,
      child: Text(confirmLabel, style: TextStyle(color: ZenColors.mutedRed)),
    ),
  ],
)
```

（以实际 ZenConfirmDialog 结构为准，保留其现有参数/语义。）

- [ ] **Step 3: 2 处 Rename 对话框 zen 化**

`track_records_page.dart:111-128` 与 `clocks_tab.dart:434-451` 的裸 `AlertDialog`：加 `backgroundColor: ZenColors.surface`，按钮文字色用 `ZenColors.secondary`(取消)/`ZenColors.sage`(保存)，标题/输入框配色靠拢 zen。或若项目有通用 zen 输入对话框工厂则改用之（grep 确认）。

- [ ] **Step 4: flutter analyze + 真机**

Run: `flutter analyze`
Expected: 0 issues。真机：clock demo FAB（+）为 sage 绿描边；删除确认/Rename 对话框为暖米面（非冷白）。

## Task A4: commit + todo done（#1 + #4）

- [ ] **Step 1: commit + push**

```bash
git add lib/lab/demos/clock lib/lab/demos/clock_demo.dart lib/widgets/theme/zen_theme.dart test/lab/clock_delete_guard_test.dart
git commit -m "feat(clock): demo 全量中文化+记录删除守卫+zen 主题细节

#1: 全 demo 文案中译(Clocks/Tracks/Dashboard/编辑器/Runner), 单位记号不译;
    记录删除加 completed 守卫,运行中/暂停弹提示不删(clock+track)。
#4: FAB 改 ZenColors.sage, ZenConfirmDialog 套 surface 背景+Cancel zen 色,
    2 处 Rename 裸 AlertDialog zen 化。
3 单测过(canDeleteRecord), analyze 干净。
kvcli fr #1 #4."
git push
```

- [ ] **Step 2: 回填 todo**

```bash
kvcli todo done 1 --result "clock 中文化+删除守卫完成: 全 demo 文案中译, 记录删除加 completed 守卫弹提示(clock+track, canDeleteRecord 3 单测)。analyze 干净。commit <hash>"
kvcli todo done 4 --result "clock zen 主题细节完成: FAB→ZenColors.sage, ZenConfirmDialog→surface 背景+Cancel zen 色, 2 处 Rename 对话框 zen 化。analyze 干净。commit <hash>"
```

---

## Self-Review

- **Spec 覆盖**：意图文档 3 簇 → Part C(#3)/B(#2)/A(#1+#4) 全覆盖。中文化范围=全 demo（用户拍板）；删除守卫=弹提示+含 track（用户拍板）；beat=还原 3 槽+accent 默认木鱼（用户拍板 Q4 + 任务原文）；banner=路径预热（用户拍板）。
- **占位符扫描**：LabClockRecord 构造字段在 A2 Step1 已注明"以真实模型为准"——执行时先 Read 模型文件再定测试字段，非占位。其余步骤均含实际代码。
- **类型一致**：`HomeBannerCache.path/ready/warmUp/refresh/resetForTest`（C1-C3）、`SampleLoader.restoreAtStartup/slotDefault/resolveSoundId`（B1-B2）、`LabClockProvider.canDeleteRecord`（A2）命名跨任务一致。
