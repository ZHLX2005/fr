# Intent: 房间生命周期状态机（room-lifecycle-state-machine）

> **Date:** 2026-09-02
> **Topic:** room-lifecycle-state-machine
> **类型:** intent doc（原始意图）
> **来源:** team_card 团建卡牌 demo 重构过程中的连环 bug 讨论沉淀

## 背景与动机

team_card（团建卡牌，relay-v3 Lua 状态机房间业务）在重构过程中踩了一串互相纠缠的 bug：

1. **二次创建房间**：`SetupPage._create()` 再次调 `tryJoinOrCreate`，用新随机 code 创建了第二个房间——房主配置的房间和实际游戏的房间分离。
2. **玩家区人数设置失效**：join 不改 `player_slots`，房主在 stepper 里改的人数从未真正作用到房间。
3. **房间号被随机码覆盖**：用户在入口选的房间号被 `SetupPage._generateCode()` 的随机 6 位数字顶掉。
4. **玩家提前进入**：房主还没配置完，其他用户就能 join 进来，看到错误的（默认值）房间配置。

这些 bug 的**共同根源**是：没有把"房间"当成一个有生命周期的状态机来设计。房间创建后立即可加入、配置和加入并发进行、配置靠"再建一个房间"实现——全是对状态机语义的违背。

用户的核心洞察（原话）：

> 房间是房间呀，整个状态自己维护。在房主设置房间配置的时候，房间是一个状态；创建之后是可用的状态，然后其他人可以进入。如果房间创建但不是在 running 阶段，其他用户应该暂时不进入。就是一个状态机呀。只有最开始创建房间的时候需要后端的系统级别 API，其他都是自己 Lua 脚本定义状态机逻辑。

## 目标

- 房间有明确的生命周期状态：`setup`（房主配置中）→ `lobby`（开放可加入）→ `playing`（游戏中），转换全部由 Lua 状态机自治
- 房间只创建一次（`CreateRoom` 是唯一一次后端系统级 API 调用），之后一切变化都是对同一房间的 action
- 房主配置（身份池、玩家区人数）通过 action 直接修改本房间，不再"重建"
- setup 阶段其他用户可以加入但**排队等待**（waiting），房间开放（OPEN）时自动入座——不是 409 拒之门外
- 消灭上述四个 bug 的整个成因链

## 约束与边界

- **零 Go 代码改动**：全部靠 Lua 脚本 + 现有 relay-v3 协议（action + snapshot 广播 + zones/rejected_join 语义）
- **术语铁律**（本次 bug 反复踩的点，见术语对照表）：玩家区人数（`player_slots`，业务设置）≠ 房间总人数（`max_players`，后端系统上限 8）
- waiting 等待区不占三区任何席位（否则房主改 `player_slots` 又会被"当前已坐人数"卡死）
- UI 保持现状（LobbyEntryPage → 房主配置页 → PlayingView 三段流程），只改语义不改结构

## 关键决策

| 决策点 | 结论 | 理由 |
| --- | --- | --- |
| setup → lobby 转换 | 房主手动点「开放房间」（OPEN action） | 房主主动控制权；自动开放可能在没准备好时放人进来 |
| setup 阶段非房主 join | 排队等待（`zones="waiting"`），不拒绝 | 体验更好（挂着自动进 vs 反复重试）；且 waiting 不占席位，房主改 player_slots 无死锁 |
| lobby 阶段改配置 | 允许，带保护（新玩家区容量 ≥ 当前玩家区已坐人数） | 灵活；保护防止丢人 |
| playing → RESET 回哪 | 回 lobby（连续开局） | 团建场景连打多局，玩家不用退房重进 |
| 玩家区人数与房间人数 | 严格区分：`player_slots`（业务）与 `max_players`（后端 8）分属两层 | 历史上多次搞混导致显示错、设置失效 |

## 待定问题

- 等待页的具体视觉（转圈 + 文案"房主正在配置中"为最小实现；是否加"第 N 位等待"排队序号展示）
- 房主 OPEN 时如果 waiting 人数超过 `player_slots`，溢出进旁观区——先到先得的顺序按 join 时间还是按 `players` map 序（Lua map 无序，可能需要显式 `join_seq` 计数器）

## 相关文档

- 设计稿：`intent/room-lifecycle-state-machine-2026-09-02-v1-design.md`
