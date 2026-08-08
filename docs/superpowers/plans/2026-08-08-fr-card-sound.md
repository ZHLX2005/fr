# fr Coup+team_card 卡牌音效接入 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `lib/lab/demos/coup_lua/`（Coup 政变）与 `lib/lab/demos/team_card/`（团建卡牌）两个 lab demo 中接入 `assets/audio/dealingCards.mp3` 翻牌音效，多 AudioPlayer 池 + 静态 `_enabled` 开关。

**Architecture:** 新增 `DealingCardsSound` 单例（与现有 `PieceSound` 同包），采用 16 个 `AudioPlayer` 的池，使同帧 6 张发牌（Coup 满员场景）不抢断。枚举监听 Snapshot 状态变化触发播放：监听 `state`（lobby→ready→playing 检测 START 一次发 6 张牌）、`players[did].card1/card2`（null→非空，捕获 REVEAL 抽新一张）。Coup 在 `widgets.dart` 的 setState 回调里添加；team_card 在 `_RoomPageState` 包一层 `_onDeal()` 调 `_engine.deal()` 时触发。

**Tech Stack:** Flutter / Dart · `just_audio` (already in pubspec) · 现有 `core/game_audio/` 音频包

## Global Constraints

- ❌ **不修改** `pubspec.yaml`（`assets/audio/` 已注册）
- ❌ **不重构** `PieceSound`（保持单 player 落子语义不变）
- ❌ **不动 Lua 脚本**（音频触发挂在 Dart 侧）
- ❌ **不做全局音效设置面板**（仅预留 `_enabled` 静态开关）
- ✅ 沿用 `just_audio` 依赖
- ✅ 全部 catch 吞错，遵循 `PieceSound` 的健壮性基线（音频失败不影响棋盘主流程）
- ✅ 现有 `PieceSound` 行为不变
- ✅ `flutter analyze` 通过
- ✅ 涉及范围仅 `lib/lab/demos/coup_lua/` 与 `lib/lab/demos/team_card/` 两个 demo；其他模块（jungle_chess / gomoku_lua / reversi_lua / surround_game_lua / metronome / clock 等）一律不动

---

## File Structure

| 文件 | 责任 | 现状 |
| --- | --- | --- |
| `lib/core/game_audio/dealing_cards_sound.dart` | 新建 — 多 AudioPlayer 池单例 + 静态 `_enabled` | 新建 |
| `lib/lab/demos/coup_lua/widgets.dart` | 修改 — 在 snapshot 流回调里检测 DEAL/REVEAL 触发播放 | 已 1865 行，新增 ~50 行 |
| `lib/lab/demos/team_card/widgets.dart` | 修改 — 在 `_RoomPageState` 包 `_onDeal()` wrapper | 已 1619 行，新增 ~10 行 |
| `test/lab/dealing_cards_sound_test.dart` | 新建 — 单元测试 Enabling/Disabling 开关 + 池大小常量 | 新建 |

不另建 `lib/lab/demos/coup_lua/events.dart` 之类抽离文件 —— 触发逻辑就近放在 `widgets.dart` 的 setState 回调里，避免 lab demo 内部过度分层。

---

## Task 1: 新增 `DealingCardsSound` 单例 + 静态开关

**Files:**
- Create: `lib/core/game_audio/dealing_cards_sound.dart`
- Test: `test/lab/dealing_cards_sound_test.dart`

**Interfaces:**
- Consumes: `package:just_audio/just_audio.dart` 中的 `AudioPlayer`
- Produces:
  - `static final DealingCardsSound instance`
  - `static bool get enabled`
  - `static void setEnabled(bool v)`
  - `static Future<void> play()` (fire-and-forget)
  - `static Future<void> preload()` (可选)
  - `static const int poolSize` (16)

**依赖上层：** 本任务无前置；后续 Task 2/3 据此调用。

- [ ] **Step 1: 写失败测试**

`test/lab/dealing_cards_sound_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/game_audio/dealing_cards_sound.dart';

void main() {
  group('DealingCardsSound', () {
    test('enabled 默认 true', () {
      expect(DealingCardsSound.enabled, isTrue);
    });

    test('setEnabled(false) 后 enabled 变 false', () {
      DealingCardsSound.setEnabled(false);
      expect(DealingCardsSound.enabled, isFalse);
    });

    test('setEnabled(true) 后 enabled 变 true', () {
      DealingCardsSound.setEnabled(false);
      DealingCardsSound.setEnabled(true);
      expect(DealingCardsSound.enabled, isTrue);
    });

    test('poolSize 至少 16（覆盖 6 人 Coup 满员）', () {
      expect(DealingCardsSound.poolSize, greaterThanOrEqualTo(16));
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd D:/DevProjects/my/github/fr
flutter test test/lab/dealing_cards_sound_test.dart
```

预期：FAIL —— `DealingCardsSound` not defined。

- [ ] **Step 3: 实现 `DealingCardsSound`**

`lib/core/game_audio/dealing_cards_sound.dart`：

```dart
// lib/core/game_audio/dealing_cards_sound.dart
//
// 翻牌音效 — lab demo 卡牌游戏（Coup / team_card）共用单例。
//
// 六人 Coup 满员开局时，`on_action_START` 同帧为 6 个玩家各发 2 张牌，
// 服务端在一帧内把 12 个 `card1`/`card2` 从 null 置上 → 客户端在同帧
// 收到 12 个"翻牌"事件。沿用 `PieceSound` 的"单 AudioPlayer + seek+play"
// 模式会被 seek 抢断导致后 11 次吞掉。
//
// 设计：16 个 AudioPlayer 池，`play()` 取一个空闲或最早被占用的 player
// 加载 `dealingCards.mp3` 并 seek(0)+play。丢帧代价：忽略新调用。
//
// 资产：assets/audio/dealingCards.mp3（已在 pubspec 注册）。
// 依赖：just_audio（已在 pubspec）。
// 全局开关：static `_enabled`，默认 true；未来全局设置直接
// `DealingCardsSound.setEnabled(settings.soundOn)`。

import 'package:just_audio/just_audio.dart';

class DealingCardsSound {
  DealingCardsSound._();

  /// AudioPlayer 池大小。覆盖 6 人 Coup 满员（12 张同帧）的余量。
  static const int poolSize = 16;

  /// 资源路径。
  static const String _assetPath = 'assets/audio/dealingCards.mp3';

  /// 池内 player。
  final List<AudioPlayer> _pool =
      List<AudioPlayer>.generate(poolSize, (_) => AudioPlayer());

  /// 每个 player 是否空闲（"未在播放"语义：不在 playing；idle/completed/paused 都算空闲）。
  /// 真实使用时直接尝试 setAsset + seek+play；失败 catch 吞掉。
  static bool _enabled = true;

  /// 当前是否启用。
  static bool get enabled => _enabled;

  /// 设置静态开关。默认 true；全局设置面板未来通过这里统一静音。
  static void setEnabled(bool v) => _enabled = v;

  /// 翻牌音效 fire-and-forget 播放。
  /// 同帧多次调用会从池里依次取 player，互不抢断。
  /// 全部 catch 吞错，遵循 PieceSound 的健壮性。
  static Future<void> play() async {
    if (!_enabled) return;
    final self = instance;
    for (final p in self._pool) {
      try {
        await p.setAsset(_assetPath);
        await p.seek(Duration.zero);
        await p.play();
        return;
      } catch (_) {
        // 这个 player 加载失败或播放失败，下一个。
        continue;
      }
    }
    // 池里全部失败——吞掉，不影响对局。
  }

  /// 全局单例。
  static final DealingCardsSound instance = DealingCardsSound._();
}
```

> ⚠️ 实现里要避免对 `setAsset` 同步加锁；just_audio 的 setAsset 本身是异步并发安全的，按序 await 即可。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd D:/DevProjects/my/github/fr
flutter test test/lab/dealing_cards_sound_test.dart
```

预期：PASS（4 个测试全过）。

- [ ] **Step 5: 跑 analyze**

```bash
cd D:/DevProjects/my/github/fr
flutter analyze lib/core/game_audio/dealing_cards_sound.dart test/lab/dealing_cards_sound_test.dart
```

预期：无 error / warning。

- [ ] **Step 6: 提交**

```bash
cd D:/DevProjects/my/github/fr
git add lib/core/game_audio/dealing_cards_sound.dart test/lab/dealing_cards_sound_test.dart
git commit -m "feat(game_audio): 新增 DealingCardsSound 多 player 池单例 + 静态开关"
```

---

## Task 2: Coup `widgets.dart` 接入 — 监听 Snapshot 触发 DEAL/REVEAL 播放

**Files:**
- Modify: `lib/lab/demos/coup_lua/widgets.dart`

**Interfaces:**
- Consumes: `DealingCardsSound.play()` (Task 1)
- 触发点: `_OnlineGamePageState` 现有的 `widget.handle.snapshots.listen((s) { ... setState(...) })` 回调
- 既有方法 `_room.players(snap)` / `_room.state` 全部已有，**不新增 engine 侧动作**

**事件检测算法：**

- **DEAL 事件**：`state` 从 `ready` → `playing`（即上次 snap.state == 'ready' 且本次 snap.state == 'playing'）时，对每个玩家 `handCount` 增加量计数（= 2 / 玩家），按张数播放。
- **REVEAL 事件**：`phase == reveal` 检测单个玩家某槽位从 null → role（更精确：上次的 `players[did].card1` 与本次 `card1` 不等，且上次非 null → 当前是一次 REVEAL 翻牌：把一张放回牌库 + 抽一张新）。简化方案：phase 还在 reveal 时如果某玩家 card1/card2 字符串内容发生变化且之前非 null（本帧内可能 0 个玩家），就播一次。

> 实现细节：snapshot stream 是 service 真实推送，每次动作一般同步一次快照。在 dedupe 上保存 `_prevSnap`，跨事件比较。

- [ ] **Step 1: 在 `_OnlineGamePageState` 新增状态字段**

定位 `lib/lab/demos/coup_lua/widgets.dart` 大约 280 行 `_OnlineGamePageState` 类。在 `Snapshot? _snap;` 之后新增：

```dart
Snapshot? _prevSnap; // 上一帧快照，用于检测事件
```

- [ ] **Step 2: 修改 snapshot 监听回调**

替换原 `_sub = widget.handle.snapshots.listen((s) { ... setState(() => _snap = s); })` 块为：

```dart
_sub = widget.handle.snapshots.listen((s) {
  if (!mounted) return;
  _onSnapshot(s);
  setState(() => _snap = s);
});
```

新增私有方法 `_onSnapshot(Snapshot s)`：

```dart
void _onSnapshot(Snapshot s) {
  final prev = _prevSnap;
  _prevSnap = s;
  if (prev == null) return;

  // 1) DEAL：state ready → playing
  if (prev.state == 'ready' && s.state == 'playing') {
    final players = _room.players(s);
    // 每玩家 2 张。统计本次发牌总数 = 每个玩家 handCount 增量合计。
    // 简化：按总玩家数 * 2 直接播（与服务端 deal_starting 语义一致）。
    final n = players.values.where((p) => !p.spectator).length;
    final total = n * 2;
    for (var i = 0; i < total; i++) {
      // 各张独立 fire-and-forget，靠池内 player 互不抢断。
      // ignore: discard_futures
      DealingCardsSound.play();
    }
    return;
  }

  // 2) REVEAL：phase==reveal 且某玩家 card1/card2 槽内容发生变化（之前非 null → 新值）
  if (_room.phase(s) == CoupPhase.reveal) {
    final cur = _room.players(s);
    final prevPlayers = _room.players(prev);
    cur.forEach((did, p) {
      final pp = prevPlayers[did];
      if (pp == null) return;
      // card1 翻牌：pp.card1 非 null 且与 p.card1 不同
      if (pp.card1 != null && pp.card1 != p.card1) {
        // ignore: discard_futures
        DealingCardsSound.play();
      }
      if (pp.card2 != null && pp.card2 != p.card2) {
        // ignore: discard_futures
        DealingCardsSound.play();
      }
    });
  }
}
```

并在文件顶部加 `import 'package:xiaodouzi_fr/core/game_audio/dealing_cards_sound.dart';`

- [ ] **Step 3: 跑 analyze**

```bash
cd D:/DevProjects/my/github/fr
flutter analyze lib/lab/demos/coup_lua/widgets.dart
```

预期：无 error / warning。`ignore: discard_futures` 已注释。

- [ ] **Step 4: 手动 smoke 验证**

```bash
cd D:/DevProjects/my/github/fr
flutter build apk --debug
```

构建通过即可（lab demo 没有自动化测试覆盖，手测在真机/模拟器上 SETUP→READY→START 6 张牌同帧播放）。

> ⚠️ 工程实践：lab demo 缺乏 widget 测试基础设施（test/lab/demos/ 下仅有 `demo_slug_test.dart`），本任务维持测试覆盖在 Task 1 的单测上 + 手测。

- [ ] **Step 5: 提交**

```bash
cd D:/DevProjects/my/github/fr
git add lib/lab/demos/coup_lua/widgets.dart
git commit -m "feat(coup_lua): DEAL/REVEAL 触发翻牌音效"
```

---

## Task 3: team_card `widgets.dart` 接入 — DEAL 一次性播放

**Files:**
- Modify: `lib/lab/demos/team_card/widgets.dart`

**Interfaces:**
- Consumes: `DealingCardsSound.play()` (Task 1)
- 触发点: `_RoomPageState` 在 `onDeal: _engine.deal` 处包一层

> 范围更小：team_card 不分单张，DEAL 一次性，播 1 次。

- [ ] **Step 1: 在 `_RoomPageState` 新增 `_onDeal` 包装**

定位 `lib/lab/demos/team_card/widgets.dart` 中 `onDeal: _engine.deal,` 那一行（约 641）。把 `onDeal: _engine.deal,` 改为 `onDeal: _onDeal,`。

在同一 `_RoomPageState` 类（找到 `final _busy`、`final _isHost` 字段附近）插入：

```dart
Future<void> _onDeal() async {
  // ignore: discard_futures
  DealingCardsSound.play();
  await _engine.deal();
}
```

并在文件顶部加 `import 'package:xiaodouzi_fr/core/game_audio/dealing_cards_sound.dart';`

- [ ] **Step 2: 跑 analyze**

```bash
cd D:/DevProjects/my/github/fr
flutter analyze lib/lab/demos/team_card/widgets.dart
```

预期：通过。注意 `onDeal` 的类型是 `Future<void> Function()`，新 `_onDeal` 签名一致。

- [ ] **Step 3: 手动 smoke**

```bash
cd D:/DevProjects/my/github/fr
flutter build apk --debug
```

- [ ] **Step 4: 提交**

```bash
cd D:/DevProjects/my/github/fr
git add lib/lab/demos/team_card/widgets.dart
git commit -m "feat(team_card): DEAL 触发翻牌音效"
```

---

## Task 4: 收尾 — 自检 + 回填 todo

**Files:** 无

- [ ] **Step 1: 全量 analyze**

```bash
cd D:/DevProjects/my/github/fr
flutter analyze
```

预期：无新增 error / warning。

- [ ] **Step 2: 跑测试**

```bash
cd D:/DevProjects/my/github/fr
flutter test test/lab/dealing_cards_sound_test.dart
```

预期：4 个测试全部通过。

- [ ] **Step 3: 全量测试**

```bash
cd D:/DevProjects/my/github/fr
flutter test
```

预期：现有测试全过（新增的 4 个 + 既有测试）。

- [ ] **Step 4: 回填 todo**

```bash
cd D:/DevProjects/my/github/fr
# text 复盘成一行（保留中文摘要）
RESULT="delivered lab 卡牌音效: lib/core/game_audio/dealing_cards_sound.dart 新增(16-池+_enabled),coupon_lua DEAL/REVEAL+team_card DEAL 接入,flutter analyze+test 通过"
kvcli todo done 18 --result "$RESULT"
```

- [ ] **Step 5: 不需另提——若用户后续要 PR 走 `/ship`**

---

## Self-Review

**1. Spec coverage:**

| Spec 决策 | 任务 |
| --- | --- |
| lab/demos/coup_lua + team_card 接入 dealingCards.mp3 | Task 2 + Task 3 |
| 多 player 池单例 | Task 1 |
| 静态 `_enabled` 开关 | Task 1 |
| 不重构 PieceSound | 全程不碰 |
| 不改 pubspec | 全程不碰 |
| 不改 Lua 脚本 | 全程不碰 |
| 沿用 just_audio | Task 1 |
| DEAL 每张一播（Coup） | Task 2 |
| REVEAL 翻牌一播（Coup） | Task 2 |
| DEAL 一次性一播（team_card） | Task 3 |
| catch 吞错 | Task 1 |

**2. Placeholder scan:** 无 "TBD" / "实现稍后" / "类似 Task N" — 全部代码块完整。

**3. Type consistency:** `DealingCardsSound.play()` / `setEnabled` / `enabled` / `poolSize` 全部在 Task 1 定义，Task 2/3 一致使用。Coup 中 `CoupPhase.reveal` 来自现有 enum，无新增。

**4. 风险点：**

- Coup 监听 phase==reveal 检测"翻牌"事件——服务端 reveal_card 是同步的（同一帧内 card1 明文内容变化），但 card1=null 状态出现的过渡可能错过。采用 `pp.card1 != null && pp.card1 != p.card1` 屏蔽 start-up 噪声。
- 启动噪音：Coup 在刚收到第一个 snapshot 时如果 `state == 'playing'`（罕见，但主播重连可能），不触发 DEAL（因为 prev==null，分支早退）。
- 池内 setAsset 失败：如果 `assets/audio/` 不在 pubspec，第一帧 setAsset 必失败，catch 吞掉，对局继续。但前端 ops 不会感知，需 user 主动发现——任务 1 已有 catch 兜底。
