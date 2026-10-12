# Demo 运行时 Scope 设计文档（demo-scope）

> 版本：2026-10-12（v1.1：P0/P1 已落地，P2 落地中；活登记表见
> `docs/architecture/demo-scope-audit.md`）
> 定位：给 70 个 lab demo 定义**运行时归属**——page / session / global 三分组 + 唯一托管者
> `DemoSessionHost`，把生命周期从「打开方式的偶然结果」变成「声明属性」。
> 首租户：remotetype（远程输入）——已接入，pop 不断连 + 回前台自动重连。

## 1. 问题定性：断连不是 bug，是所有权错位

三个事实（2026-10-12 现状）：

1. 所有 demo 经 `MaterialPageRoute → DemoDetailPage(demo.buildPage())` 打开
   （`lib/screens/profile/lab/lab_page.dart:227`），pop 即 State 销毁；
2. `lib/lab/demos/remotetype/rt_page.dart` 的 `dispose()` 里 `_session?.dispose()`
   —— **页面退出 = 主动掐断连接**，这是所有权模型决定的，不是疏漏；
3. `rt_page.dart` 没有 `WidgetsBindingObserver` —— 切 APP 后 Android 冻结/回收
   socket，回前台无人触发已有的 `_reconnect(keepTypingUi: true)`，UI 停在死连接
   上等用户手点「重连」。

另有一处**入口不一致**：钉在快捷底栏的页面走 MainScreen 的 IndexedStack 缓存
（切 tab 不销毁），push 打开的 pop 即死——同一个 demo 现在有两种生命周期，取决于
从哪进。

而 `lib/app_lifecycle/app_foreground.dart` 的注释已预言正确方向：项目里存在
「**非 widget 的常驻服务**」（net_engine transport / discovery）。缺的是一个介于
「页面 State」和「应用全局服务」之间的托管层。

## 2. 核心设计：scope 三分组 + 一条正交轴

### 2.1 `DemoScope` —— 声明运行时归属

```dart
enum DemoScope {
  page,    // 页面级（默认）：状态随 demo 页面生灭。单机 demo，行为与现状完全一致。
  session, // 会话级：核心运行态由 host 托管，离开页面不销毁，重进可 reattach。
  global,  // 应用级：进程生命周期常驻（逃生舱，见 §5——想升 global 先问该不该毕业出 lab）。
}
```

声明方式对齐现有元数据惯例（`slug` / `type` / `timePage` / `navIcon` 全是
co-located getter override，零构造函数改动）：

```dart
abstract class DemoPage {
  DemoScope get scope => DemoScope.page;  // 默认不变 → 70 个 demo 零迁移
}
```

### 2.2 正交轴：后台策略做成 session 钩子，不进 enum

「后台挂起 / 回来自动重连 / 后台继续跑」是**每类 session 自己的业务决定**，
host 不枚举策略，只转发事件：

```dart
class HostedSession {
  final String slug;                          // 稳定身份 = demo slug，一 demo 一会话
  final Object state;                         // RtSession、房间对象、计时器…任意纯 Dart 对象
  final Future<void> Function() onDispose;    // 唯一销毁入口
  final Future<void> Function()? onAppBackground; // 可选钩子
  final Future<void> Function()? onAppForeground; // 可选钩子：健康检查 + 自动重连
  DateTime detachedAt;                        // 空闲回收计时起点
}
```

### 2.3 `DemoSessionHost` —— 托管者（一个普通单例，get_it 注册）

```dart
class DemoSessionHost {
  T attach<T>(String slug, T Function() create, {hooks...}); // 有则复用（reattach），无则创建
  void drop(String slug);                 // 显式「断开/停止」→ onDispose
  Map<String, HostedSession> get active;  // 调试/审计用
}
```

不引入任何新状态管理框架。`RtSession` 类注释自称「纯数据控制层（无 UI）」
（`rt_session.dart`）——天然可托管。

## 3. 生命周期规则表（方案的心脏）

| 事件 | page scope | session scope | global scope |
|---|---|---|---|
| 进入 demo 页 | 创建 State（现状） | host 无则 start；**有则 reattach**（页面接管 UI，绝不重建） | 直接消费服务 |
| pop 退出页面 | State 销毁，一切终止 | State 销毁，**session 留在 host**（detached） | 无影响 |
| 切 APP 后台 | 随页面挂起 | `onAppBackground` 钩子（RT：暂停轮询；socket 死了标记 degraded） | AppForeground 挂起周期工作（现状） |
| 回 APP 前台 | — | host 统一广播 → `onAppForeground` → **自动重连/恢复** | 恢复周期工作（现状） |
| 重进页面 | 全新 | reattach + 展示重连进度（复用既有 `keepTypingUi` 不闪回配对页） | — |
| 用户显式断开 | — | `host.drop(slug)` → 真正 dispose | — |
| 空闲回收 | — | **detached 超 15 min 自动回收**（安全阀，防 70 个 demo 堆僵尸连接） | 不可回收 |
| 进程被杀 | 蒸发 | 蒸发（P3 快照恢复兜底，见 §8） | 重新 bootstrap |

**关键不变式：host 是唯一真相。** 同一 demo 从 lab 网格、游戏中心、钉选底栏、
`fr://` 深链、时间页五个入口进，session 行为完全一致——入口决定不了生命周期。
这也顺带修复「钉选 vs push 两种生命周期」的入口不一致。

## 4. remotetype 案例走查（接入后的行为）

三个断连源逐一消除：

| 断连源 | 现状 | 方案后 |
|---|---|---|
| pop 离开页面 | State.dispose 掐断 | session 留 host；重进 reattach，连接还在，正文不丢 |
| 切 APP 回来 | 死连接无处理，手点重连 | 回前台 → host 广播 → `onAppForeground` → 健康检查 → 走现成的 `_reconnect(keepTypingUi: true)` 原地重连 |
| 进程被杀 | 全部蒸发 | （P3）rt_prefs 存最近目标，冷启动配对页顶部「一键重连」 |

**归属切割**（迁移 rt_page 的全部改动量）：

- `RtSession`（连接、加密、seq/ack）→ 升入 host，session scope；
- `_textController` / `_selectedClient` / 各计时器 / `_pollTimer` → 留 page State
  （UI 态跟页面走，符合直觉）；
- `_eventSub` 改为订阅 + dispose 时只 `cancel` 不 `session.dispose()`——
  一行语义差别，就是整个方案的差别。

## 5. 现有结构的对齐关系（不另起炉灶）

| 已存在 | 方案怎么用它 |
|---|---|
| `AppForeground`（前后台信号，只认 paused/resumed） | host 订阅它，向各 session 转发钩子——正好落在其注释预言的用途上，口径不新增 |
| `DemoPage` getter 元数据惯例 | `scope` getter 一行接入 |
| `RtSession`「纯数据控制层」 | 直接成为第一个托管对象 |
| net_engine / net_p2p 全局服务 | 就是事实上的 global scope，方案**承认**它们，不迁移不重构 |
| get_it + riverpod 双栈 | host 用 get_it 注册一个普通单例即可 |

## 6. 分组判据（给未来每个新 demo 用）

判据不是「技术上能不能保活」，是**用户离开页面那一刻的预期**：

- 「它应该还在」→ **session**。远端输入、联机房间、录音/长计时、下载；
- 「我用完了」→ **page**。2048、时钟、画布——绝大多数；
- 「全 app 都在用，demo 只是入口」→ **global**。目前真正够格的（transport/
  discovery、音频）早已住进 `lib/services` / `core/net_engine`。
  **规则：global 是逃生舱不是目标——一个 demo 想升 global，先问它是不是该毕业出 lab。**

## 7. 边界（明确不做）

1. **不强制迁移**：默认 page scope，70 个 demo 行为零变化；
2. **不做 Android 前台服务保活**（detach-with-FGS）：native 层另一个工程，音乐/
   下载类真需要时单独立项；
3. **不做跨 session 通信总线**：host 只管生死，不管 session 互调；
4. **进程级死亡不在 host 能力内**：Android 低内存杀进程是系统行为，兜底靠 P3
   快照恢复，不靠硬扛。

## 8. 实施路线（评审通过后）

| 阶段 | 内容 | 验收 | 状态 |
|---|---|---|---|
| P0 契约 | `DemoScope` + `scope` getter + `DemoSessionHost` 骨架 + 单测 | 零行为变化，analyze 绿 | ✅ `1e1f357c` |
| P1 首租户 | RtSession 接入 host；rt_page 改 reattach；前台自动重连 | pop 重进不断 / 切 APP 回来自动重连 / 显式断开才断 | ✅ `be1561ff`+`18a93506`（真机行为待人工验收） |
| P2 治理 | detached 空闲回收 + host 调试面板 + 审计文档登记 scope 分组清单 | 每个已迁移 demo 在审计文档登记归属 | ✅ 维护协程+面板「会话托管监视」+ `demo-scope-audit.md` |
| P3 可选 | 进程死亡快照恢复（rt_prefs 已有基础） | 杀进程冷启动可一键回到上次会话 | 未启动 |

## 9. 待确认项（v1 落地时按默认值决议）

1. ~~空闲回收阈值~~ → **15 min 固定**（`kSessionIdleReapTimeout`，检查周期 5 min）；
2. ~~detached 全局可见入口~~ → v1 不做溢出 sheet badge，调试走 Lab「会话托管监视」面板；
3. ~~下个迁租户~~ → 联机游戏 ×10（依赖确认 net_p2p/relay_v3 会话可脱离页面存活）。
