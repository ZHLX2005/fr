# Demo 运行时 Scope 审计与登记

> 审计范围：`lib/lab/demos/**`（48 个 DemoPage 子类）
> 审计日期：2026-10-12
> 设计全文：`docs/superpowers/specs/2026-10-12-demo-scope-design.md`
> 托管设施：`lib/lab/demo_session_host.dart`（`DemoSessionHost` / `HostedSession`）

## 1. 结论摘要

当前 scope 分组：**session ×1（remotetype，P1 已落地）· global ×0 · page ×47（默认）**。

```text
用户离开页面那一刻的预期：
  「它应该还在」→ session   「我用完了」→ page   「全 app 都在用」→ 该毕业出 lab，不是升 global
```

## 2. Session/Global 登记表（唯一需要逐条维护的表）

| slug | scope | 状态 | 托管对象 | 登记理由 | 落地 commit |
| --- | --- | --- | --- | --- | --- |
| `remotetype` | session | ✅ 已落地 | `RtSession`（WS + e2e 加密） | 用户离开页面时预期连接还在；pop 不断连、回前台自动重连 | `be1561ff` / `18a93506` |

**迁移候选**（按优先级，动手前先在此登记）：

| 候选 | 理由 | 备注 |
| --- | --- | --- |
| 联机游戏 ×10（`*-lua` / `chess-online`） | 房间连接住在页面 State，pop 即掉线 | 依赖 net_p2p / relay_v3 的会话对象，迁前先确认其是否已可脱离页面存活 |
| `recorder` / `metronome` | 长计时/录音「离开页面还在跑」的边界案例 | P2 后再判 |

**global 暂无合格者**：transport/discovery 等事实全局服务已住 `lib/services` 与 `core/net_engine`，
不借 demo 通道。规则：demo 想升 global → 先问它是不是该毕业出 lab。

## 3. Page scope 概况（默认值，不需逐条登记）

47 个 demo 维持默认 `DemoScope.page`，分组见 game center（`kGameMeta`）与
`DemoType`（game ×15 / tool ×2 / util ×31，含 timePage ×3）。**出现以下情况必须迁 session：**
单机 demo 里出现长连接、后台任务或跨页面共享的可变运行态。

## 4. 契约守卫（不读 ref 也记住）

- `DemoSessionHost.attach` 有 assert：**page scope 的 demo 挂托管当场炸**——
  「行为迁了、声明没跟」在编码阶段拦截，不经审计阶段。
- 反向（声明 session 但未托管）目前无运行时守卫，靠本表 + 调试面板人工核对。
- slug 必须单一来源：注册与托管共用常量（先例 `kRemoteTypeDemoSlug`），
  两处字面量 = 托管静默失联。

## 5. 已知边角（登记在案，未修）

| 边角 | 影响 | 处置 |
| --- | --- | --- |
| 同一 demo「钉选底栏 + push」双实例在场，顶页 pop 的 detach 会误标 detached | 15min 后空闲回收可能误伤底栏实例的活会话 | reattach 自愈；后续可做 attach/detach 引用计数（P2+） |
| detached 期间 socket 死亡不会自动重连 | 回前台翻转时由 host 广播补连；若翻转后仍死，需重进页面触发 | 设计使然（无 UI 无交互场景不空转重连） |
| 进程被杀会话全灭 | 冷启动无会话 | P3 快照恢复（rt_prefs 存最近目标，配对页一键重连） |

## 6. 审计维护规则

新增/迁移 scope 时必须：

1. `DemoPage` 子类 override `scope`（session/global）并在 §2 登记一行；
2. 托管对象实现幂等 `dispose`，页面 `dispose` 只 `detach`、显式停止才 `drop`；
3. 调试面板（Lab「会话托管监视」）核对 detached 时长与回收状态；
4. 复扫命令：

```powershell
rg -n "DemoScope get scope" lib/lab/demos
rg -n "demoSessionHost\.(attach|detach|drop|get)" lib/lab/demos
```
