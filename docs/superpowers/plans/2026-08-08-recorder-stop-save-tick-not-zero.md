# recorder stop+save 时间不归零修复计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Lab → 录音机页面 "停止录音 + 保存" 后,大字号计时器不归零的问题(始终显示停止时刻的累计时长)。

**Architecture:** `RecorderController` 的 `_ElapsedDisplay` widget 只通过 `tickListenable`(`_tickNotifier` 的 ValueListenable 暴露)订阅时长 —— 它不订阅 `ChangeNotifier.notifyListeners()`。`commitSave()` / `discard()` 当前只重置内部 `_elapsed = Duration.zero` + 调 `_safeNotify()`,**没有同步把 `_tickNotifier.value` 写零**,ValueListenable 不通知,UI 卡在旧值。修复 = 这两个出口末尾加 `_tickNotifier.value = _elapsed;`(此时 `_elapsed` 已是 zero)。

**Tech Stack:** Flutter / ChangeNotifier / ValueListenable / `record` 6.x / `lib/lab/demos/recorder/`。

## Global Constraints

- **不运行 `flutter run`**。最低成本编译检查 = 根目录 `flutter analyze`(必须无 error)。
- 改完文件若没被 import,靠 analyze 孤儿文件检测兜底。
- commit message 风格沿用仓库:`fix(scope): 中文说明`。
- 提交前先 `git status` 确认归属,只 `git add` 本任务改动的文件,**禁止 `add .` / `commit .`**。
- 不破坏既有交互:stop 后时长仍正确累计、save/discard 后回到 idle、可重新 start。
- 不动公共 API / 不动 `_tickNotifier` 的字段名、不动 ticker(1Hz)逻辑、不动 list 页播放相关。
- 本仓库的现有测试 `test/` 不覆盖 RecorderController,本次不补单元测试(轻改一行,analyze 即可)。

---

## Task 1: commitSave / discard 末尾同步 tickNotifier 归零

**Files:**
- Modify: `lib/lab/demos/recorder/recorder_controller.dart` — `commitSave()`(:272-281) 与 `discard()`(:253-268) 各加一行 `_tickNotifier.value = _elapsed;`(放在 `_safeNotify()` 之前或之后均可,放之前更清晰表达"先同步 UI 状态,再通知其他 listener")。

**Interfaces:**
- 不新增 / 不修改任何对外 API。
- 复用既有字段:`_tickNotifier`(:427)、`_elapsed`(:57)。

- [ ] **Step 1: 改 `commitSave()`,在 `_safeNotify()` 之前加一行**

`lib/lab/demos/recorder/recorder_controller.dart` :272-281 改为:

```dart
/// 用户保存录音(目前 v1 仅暴露 lastSavedPath,不另存到 MediaStore)。
/// 返回最终保存的文件路径(供 UI 弹 SnackBar)。
String? commitSave() {
  final p = _lastSavedPath;
  _lastSavedPath = null;
  _lastFileSize = 0;
  _elapsed = Duration.zero;
  // tickNotifier 必须同步写零:ElapsedDisplay 只订阅 tickListenable,
  // 不订阅 ChangeNotifier,这里必须主动推一次零。
  _tickNotifier.value = _elapsed;
  _state = RecorderState.idle;
  _stopAmplitude();
  _safeNotify();
  return p;
}
```

- [ ] **Step 2: 改 `discard()`,在 `_safeNotify()` 之前加一行**

`lib/lab/demos/recorder/recorder_controller.dart` :253-268 改为:

```dart
/// 放弃录音(stop 后调用),删除文件,回到 idle。
Future<void> discard() async {
  final p = _lastSavedPath;
  _lastSavedPath = null;
  _lastFileSize = 0;
  _elapsed = Duration.zero;
  // 同步 tickNotifier,理由同 commitSave。
  _tickNotifier.value = _elapsed;
  _state = RecorderState.idle;
  _stopAmplitude();
  _safeNotify();
  if (p == null) return;
  try {
    final f = File(p);
    if (await f.exists()) await f.delete();
  } catch (_) {
    // 文件删除失败不阻塞 UI(临时文件,系统回收即可)
  }
}
```

- [ ] **Step 3: `flutter analyze` 校验**

```bash
flutter analyze lib/lab/demos/recorder/recorder_controller.dart
```

Expected: `No issues found!`

- [ ] **Step 4: 代码层验证行为不变**

- `_ElapsedDisplay`(`recorder_page.dart:289-307`)通过 `controller.tickListenable` 订阅,ValueListenableBuilder 收到 value=zero → 立即重建显示 `00:00`。
- `start()`(`:159-194`)中 `_elapsed = Duration.zero` 与 `_startTicker` 在 ticker 第一帧前都跑过,新一次录音从零开始。
- `stop()`(`:226-250`)不变:stop 时长不归零是正确的(用户看到的是 stop 时刻的累计时长)。归零时机仍在 save/discard。
- 既有 `dispose()`(`:492-512`)仍调 `_stopTicker()` + `_tickNotifier.dispose()`,save/discard 的额外一行不影响生命周期。

- [ ] **Step 5: Commit + Push**

```bash
git add lib/lab/demos/recorder/recorder_controller.dart
git status   # 确认只有本任务文件被 add
git commit -m "fix(recorder): stop+save/discard 同步 tickNotifier 归零时长

- commitSave / discard 只重置 _elapsed 内部字段但未同步 _tickNotifier.value
- ElapsedDisplay 只订阅 tickListenable(ValueListenable),不订阅 ChangeNotifier
- save/discard 后 ticker 不再推,UI 卡在 stop 时刻的累计值
- 在 _safeNotify 之前推 _tickNotifier.value = Duration.zero,UI 立即归零
- analyze 干净,行为不变:stop 时长仍显示累计、start 新一轮从零起"
git push
```

---

## 自检(写入前)

1. **Spec 覆盖**:"录音功能 record,当停止录音并保存,时间不会归零"——本计划让 save + discard 都把 `_tickNotifier` 写零,UI 立即重建 = ✅ 覆盖。
2. **占位符**:无 "TBD / TODO / 适当处理" 字样。
3. **类型一致性**:`_tickNotifier.value = _elapsed;`(`_tickNotifier` 是 `ValueNotifier<Duration>`,`_elapsed` 是 `Duration`)→ 类型匹配。

## 已知非目标

- 不补 widget / 单元测试(本仓库的 `test/` 目录对 RecorderController 无现成测试脚手架,轻改一行 analyze 即可)。
- 不改 `_startTicker` / `_stopTicker` / `_tickNotifier` 的字段名。
- 不动播放相关(列表页 play/seek/setSpeed)。
- 不动权限 / 振幅 / dBFS 相关。
- 不动 recorder 列表页 / 已存录音文件结构。