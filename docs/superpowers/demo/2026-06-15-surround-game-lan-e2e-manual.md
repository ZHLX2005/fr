# Surround Game LAN 模式手动 E2E Demo

> 本文档是 Task 19 集成测试的**降级方案**。
> 由于 `LanFramework` 当前是单例（`LanFramework.instance`），本轮不修改 framework，
> 所以无法在单进程内启 2 个 framework 实例做自动化集成测试。
>
> 跨进程手动 demo 需在两台真机/模拟器/同一台机器两个窗口分别跑。

## 前置条件

- 两台 Android 设备/模拟器（或一台模拟器 + 一台真机）
- 同一局域网（设备互相能 ping）
- 关闭系统防火墙（Android 模拟器默认允许）

## 步骤 1: 启动 Host 端

在 A 设备上：
1. 启动应用 `flutter run --release`
2. 从主页进入"围追堵截" Lab
3. 选择"局域网对局"
4. 弹窗输入本机名称 `Host-Alice` → 确定
5. AppBar 显示"局域网对局" + 状态栏显示"已连接"
6. **点"创建房间"按钮** → 进 LanRoomPage
7. **记下房间 ID**（AppBar 显示）
8. **等 Client 端加入** — 状态栏会显示"对手: <名字>"

## 步骤 2: 启动 Client 端

在 B 设备上：
1. 启动应用
2. 进入"围追堵截" Lab
3. 选择"局域网对局"
4. 弹窗输入 `Client-Bob` → 确定
5. **等待房间列表出现**（约 5-15 秒，因 broadcast timer）
6. **点击"Host-Alice 的房间"** → 进 LanRoomPage
7. 等待"玩家已加入"显示在 Host 端

## 步骤 3: 开始游戏

Host 端：
1. 看到"对手: Client-Bob"
2. **点"开始游戏"按钮**
3. 倒计时 3 → 2 → 1 → 0
4. 自动跳进 LanHostGamePage
5. **棋盘显示翻转**（Host 端是 top player，但视觉在下方）

Client 端：
1. 收到 join accept → 立即跳进 LanClientGamePage
2. **棋盘显示不翻转**（Client 端是 bottom player，视觉在下方）

## 步骤 4: 落子同步验证

**Host 落子**（Host 端 top player）：
- 在棋盘上点一个合法 cell → LanBoardStack 进入 confirming 状态
- 按"确定"按钮 → 棋盘更新
- **Client 端棋盘应同步更新**（约 0.5-2s 延迟）
- 轮次切换：轮到 Client

**Client 落子**：
- 同上，但点 cell → Client 棋盘更新 → Host 端棋盘应同步更新
- 轮次切换：轮到 Host

**放墙同步**：
- 切换到"放墙"模式（按面板按钮）
- 在 grid line 上点合法位置 → 确认
- 双方棋盘应同步显示新墙

## 步骤 5: deviceLost 验证

**手动触发**：
- 在 Client 端"杀进程"（或断网）
- Host 端应在数秒内（UDP 心跳超时 = 15s）进入 HostError 状态
- **当前 bug**：LanHostGamePage.build 的 switch 把 HostError 落到 `_buildIdleScreen`（显示"开始游戏"按钮），**没有错误提示** — 已知 UX 空白，PR 描述 follow-up

**手动重连**（本轮 YAGNI，不实现）：
- 重新进 LanRoomPage 即可

## 已知问题

1. **HostError UI 空白**：LanHostGamePage 未处理 HostError 状态，会落到默认"开始游戏"页面
2. **单 host 假设**：watchGameState 不按 hostDeviceId 过滤，多 host 场景不工作
3. **未实现重连**：掉线后只能退出重进 LanRoomPage
4. **未实现倒计时同步**：Host 端本地倒计时结束就跳 GamePage，Client 端收到 join accept 立即跳 — 双方可能错开数百毫秒

## 通过标准

- 双方成功建/加房
- Host 能看到"对手已加入"
- 一局完整对局（落子 + 放墙）能正常进行
- deviceLost 能被检测到（即使 UI 不提示）

## 自动化测试的待办

待 `LanFramework` 暴露多实例 API 后，可写：
- `integration_test/lan_session_integration_test.dart`：同进程 2 个 LanFramework 实例
- 模拟建房 → join → 落子 → 同步 → deviceLost
