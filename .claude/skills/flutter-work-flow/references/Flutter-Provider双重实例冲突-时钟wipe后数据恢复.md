---
name: Flutter-Provider双重实例冲突-时钟wipe后数据恢复
description: Provider ChangeNotifier 在 app 根级和页面级各创建一份时，各自独立 timer + 各自写同一份 SharedPreferences。清空后全局实例的 timer 回写旧数据，导致 wipe 瞬时生效后快照恢复。创建页面 Consumer 时需确认 provider 是否已被上层 create。~
---

# Flutter Provider 双重实例冲突 — 时钟 wipe 后数据被全局实例覆盖

## 问题现象

- 旧版本 Clock 页面打开 AppBar 的 "Wipe all clock data" 按钮 → 数据被清空
- 关掉页面再打开 → 旧的 clock 数据又回来了（快照恢复）
- **根因不是 SharedPreferences**：SP 确实被清了，但内存里另一个 `LabClockProvider` 实例的 timer 回写了旧数据

## 架构复盘

```
main.dart (app root)
  └─ ChangeNotifierProvider(
        lazy: false,
        create: (_) => LabClockProvider(),   // ← 实例A
     )
       │
       └─ ClockDemo.buildPage (demo 页面入口)
            └─ MultiProvider(
                  providers: [
                    ChangeNotifierProvider(
                      create: (_) => LabClockProvider(),   // ← 实例B（bug）
                    ),
                  ...
```

**实例A**：main 根级创建，`lazy: false`，冷启动即执行 `loadClocks()`，然后 `_startTimer()` 每 1 秒 tick 写 SP。

**实例B**：ClockDemo 页面内创建了 **另一个** `LabClockProvider`（开发者以为"页面需要自己的 provider"）。

### 冲突链路

1. 用户在页面内点 Wipe → `context.read<LabClockProvider>()` 拿到的是 **实例B**（页面级）
2. 实例B 停掉自己的 timer、清内存、清 SP 所有 key、通知 UI 刷新 → **页面看起来干净了**
3. 但 **实例A（根级）的 timer 还在跑**，下一秒 tick 检测 `isRunning == true && startTime != null` → 更新时间 → `_saveClocks()` → 把旧数据写回 SP
4. 用户再打开 ClockDemo → 实例B 销毁 → 新实例B' 从 `loadClocks()` 读到刚刚被实例A 写回去的旧数据 → 快照恢复

### 更隐蔽的后果

连 `wipeAllData` 这种核弹都失效：

```dart
Future<void> wipeAllData() async {
    _timer?.cancel();      // 只取消了实例B 的 timer
    // 清 SP ...
    // 清内存 ...
    _startTimer();          // 重启了实例B 的 timer
}
```

执行完 wipe 后，**两个实例都被重启了 timer**（一个在 wipe 里，一个一直没停过）。SP 再次被两个 timer 同时写。

## 修复方案

```dart
// clock_demo.dart — 不要再 create 一个新的 LabClockProvider
return ChangeNotifierProvider(
    // 只创建 LabTrackProvider（main 没有注册它）
    create: (_) => LabTrackProvider()..loadTracks(),
    child: const _ClockShell(),
);
// LabClockProvider 通过 Consumer/context.read 从 main 的 MultiProvider 继承
```

**关键决策**：哪些 provider 放在 app 根级，哪些放在页面级？

| 标准 | 放根级 | 放页面级 |
|------|--------|---------|
| 冷启动就要有的数据 | 需要（桌面小组件、全局状态） | 不需要 |
| 多个页面共享 | 需要 | 不需要 |
| 生命周期等于 app | 需要 | 不需要 |
| 生命周期等于页面 | 不需要 | 需要 |

## 同类风险

类似双实例问题也可能出现在：

| 场景 | 检查点 |
|------|--------|
| 桌面 widget 同步 | 负责同步的 provider 只能有一份在跑 timer，否则互相覆盖 widget 状态 |
| 定时写 SP 的 Provider（日历、计时、计数器） | 多实例 = 多 timer = 互相覆盖。`lazy: false` 的根级实例 + 页面级 create 是经典重灾区 |
| Riverpod `ProviderScope` | 嵌套 scope 覆盖父 scope 的 provider 时逻辑类似 |

## 排查方法

```bash
# 1. grep 所有 create: (_) => YourProvider 确认出现几次
grep -rn "Create:.*LabClockProvider\|create:.*LabClockProvider" lib/

# 2. 检查 main.dart 的 MultiProvider providers 列表
grep -A20 "MultiProvider\|ChangeNotifierProvider" lib/main.dart | grep "lazy: false\|create:"

# 3. 检查各页面 buildPage 里是否又 create 了跟 main 相同的 provider
grep -B2 -A2 "ChangeNotifierProvider" lib/lab/demos/*.dart

# 4. Provider 内部是否有 Timer / Stream subscription 定期写持久层
grep "Timer\.periodic\|Timer\." lib/**/providers/*.dart
```

## 预防措施

- **新 Provider 注册准则**：先在 `main.dart` 搜一遍有没有同名 provider。如果有，页面内直接用 context.read 继承，不要 create。
- **定时操作**：一个 Provider 的 `_startTimer` 必须搭配 `dispose` 内的 `_timer?.cancel()`。但如果有多实例，dispose 只停当前实例 —— 所以**最好的预防是只有一份实例**。
- **Wipe API**：如果真的需要双实例（某些场景不可避免），wipe 时不能只清当前实例。需要用某种方式通知另一个实例 reload（比如用 `EventBus`、`SharedPreferences` 的 `setString` 被所有 Provider 监听、或用 `NavigatorKey` 找到根级实例）。
