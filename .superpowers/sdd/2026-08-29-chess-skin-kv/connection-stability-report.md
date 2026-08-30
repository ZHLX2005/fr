# Connection-Stability Report：WS 连接稳定性五件套（heartbeat + 状态条 + fetch 反馈 + 游戏中重建 + 唯一 ID 重入保护）

日期：2026-08-29
分支：master（push upstream master）
范围：**仅 Flutter 客户端改动，未改任何后端 / Go / relay-v3-server / Lua 行为**（除验证已存在的同 device_id 重连分支）。

## 一、按特性的改动

### 特性 1：WS 心跳健康检查（20s 周期 fetchSnapshot）
**位置：`lib/core/net_engine/relay_v3/relay_v3_transport.dart`（RoomHandle）**
- 新增 `Timer? _heartbeat` + `static const heartbeatInterval = Duration(seconds: 20)`。
- `connect()` 成功 → `_startHeartbeat()`；`_onWSDone()` / `disconnectWS()` / `dispose()` → `_stopHeartbeat()`。
- heartbeat 复用现有 `fetchSnapshot()`（HTTP GET /snapshot）做三件事：
  1. 客户端心跳（HTTP 最便宜，后端无需响应自定义 ping 帧，无需后端改动）；
  2. 快照刷新保险（lobby 等房 / 长考时 WS 推送可能被 NAT 静默截断，20s 内必有新快照）；
  3. 重连保险（`fetchSnapshot()` 内部在 `!_connected` 时取消挂起的 backoff 定时器 + `unawaited(connect())` 立即重连）。
- 注：WebSocketChannel 不暴露 close code（transport 层未知），`_onWSDone()` 统一发 code=0 事件，由各游戏 UI 消费；本特性不改变该语义。
- 源码注释完整记录了设计取舍（为什么没有自定义 WS ping 帧）。

### 特性 2：ConnectionStatusBadge（AppBar 连接状态徽标）
**新增：`lib/core/chess/widgets/chess_connection_status.dart`（≤ 80 LOC）**
- `ChessConnectionStatusBadge`：StatefulWidget，自带订阅 `closeEvents`（瞬断 → 橙 + 重连 spinner）与 `snapshots`（任意新快照 → 回绿）。
- 三态：已连接（绿点）/ 重连中…（橙点 + 10px spinner）/ disposed（widget tree 移除自动清）。
- 不写死 `Color(0xFF...)`，全部走 `theme.colorScheme`（primary / error）。
- `FittedBox(scaleDown)` 防 AppBar leading 槽溢出。
- **接入：`chess_room_page.dart`** AppBar `leading: ChessConnectionStatusBadge(handle: widget.handle)` + `leadingWidth: 86`。
- 与底部 28px `RelayConnectionBar` 并存（后者继续提供"拉取最新快照"按钮）。

### 特性 3：fetchSnapshot 的 UI 反馈
**位置：`chess_room_page.dart`**
- 新增 `_fetching` 状态 + `_fetchSnapshotWithFeedback()`（`setState(_fetching=true)` + `try/finally { _fetching=false }`，防双击）：
  - 409 reconcile 路径（原 line ~623 的裸 `fetchSnapshot()`）改为走 `_fetchSnapshotWithFeedback()`；
  - 新增 AppBar 手动刷新 `IconButton(Icons.refresh)`（`tooltip: '刷新快照'`）→ `_manualRefresh()`；
- UI：`_fetching=true` 时顶部 `LinearProgressIndicator(minHeight: 2)` + 刷新按钮变 18px spinner + `onPressed: null`（防双击）。
- RoomHandle 内部 20s heartbeat 不走反馈（后台静默）。

### 特性 4：游戏中瞬断 rejoin 稳定
**验证 + 测试覆盖（无代码改动需要）**
- 现有 `_reconnectTimer`（500ms→30s 封顶退避）+ `_wsOffline` overlay（"连接断开，正在重连…"）+ `_applySnapshot` 收到任意快照自动清 overlay —— 已符合要求。
- 测试断言：close(0) → overlay 出现 + 页面不 pop + 本地乐观棋盘保留；快照恢复 → overlay 消失 + 棋盘按权威快照重建。

### 特性 5：唯一 deviceId + 重入保护（5s grace）
**`chess_script.dart` 的 Lua —— 验证已实现，无需改动**
- `on_join` 首分支 `if c.players[p.device_id] ~= nil then c.disconnected[p.device_id] = nil; return c`：同 device_id 重连 → 复用原槽位 + 清 disconnected，不动 host/guest 槽，不重置 fen/moves（5s grace 重入保护核心）。
- 满员第三者 → `c.rejected_join` → 服务端 409（客户端 `RelayV3Exception(409)`）。
- `chess_room_page.dart` 补了"5s grace 重连 UX 不变量"注释（身份稳定 / 页面不退出 / 自动重连 + heartbeat 三保证）。

## 二、测试

### 新增：`test/core/chess/p2p/chess_connection_stability_test.dart`（13 用例）
- F2：徽标初始"已连接" / close(0)→"重连中…"+不 pop / 快照→回"已连接" / 4403 终端码→snackbar 但不 pop。
- F3：刷新按钮存在；点击→fetchSnapshot+进度条+按钮 spinner；进行中防双击；失败→snackbar+复位；409 reconcile 同样带 fetch 反馈。
- F4：close(0)→overlay+本地乐观棋盘不丢→快照恢复重建（高亮跟随权威棋谱）；版本回退防御。
- F5：guest 掉线→"你已掉线"banner；同 device_id 重连快照（fen/moves 保留）→banner 清+棋局延续；`kChessScript` 静态守卫（同 device_id 分支 / rejected_join / disconnected 保留）；rejected_join 满员 409 映射。

### 新增：`test/core/net_engine/relay_v3_transport_test.dart` +1 用例
- heartbeat：20s 周期 fetchSnapshot 兜底刷新（fake 时钟 t=20/t=40 两次）+ 断连态顺带触发 connect + dispose 后停止。

### 全量结果
- `flutter test test/core/chess/ test/api/user/ test/lab/ test/core/net_engine/` → **380 passed / 1 failed**。
- 唯一失败 `relay_v3_integration_test.dart`（端到端需真实 relay 服务器 127.0.0.1:8000，环境 404）—— 经 `git stash` 验证为 **baseline 既有失败**，与本次改动无关。

## 三、Analyze / Build
- `flutter analyze lib/core/chess/ lib/lab/demos/chess_online_demo.dart lib/core/net_engine/relay_v3/` → **0 新问题**（仅 1 个 pre-existing info：relay_v3_widget.dart:390 花括号，lobby widget 按约束不改）。
- `flutter analyze` 两个新增测试文件 → No issues found。
- `flutter build apk --debug` → **√ Built**（build\app\outputs\flutter-apk\app-debug.apk）。

## 四、提交
- Commit: `feat(chess): 连接稳定性五件套 — heartbeat + 状态条 + fetch 反馈 + 游戏中重建 + 唯一 ID 重入保护`
- 已 push upstream master。

## 五、关注点
1. **heartbeat 频率 20s**：与 reconnect backoff（500ms→30s）互不冲突 —— heartbeat 只在 `_connected=true` 期间（`_onWSDone` 即停）；断连态下 heartbeat tick 恰好充当"加速首次重连探测"。
2. **leadingWidth 86 + FittedBox**：徽标在窄屏 AppBar 上不会溢出；`FittedBox(scaleDown)` 兜底任何 locale 长文本。
3. **rejected_join 语义**：满员 409 由服务端抛出，客户端弹 snackbar 提示；本特性验证映射，未改 UI 文案（属于入口侧 UX，另一任务范围）。
4. **Lua 零改动**：`on_join` 同 device_id 早退分支本就有（rejoin-fix 时期加固），本次只加静态守卫测试 + 文档注释，防未来误删。
5. **测试用 fake**：`StableFakeHandle.fetchSnapshot` 用 Completer 闸门使 fetch 的"进行中"断言确定化；几何 `cellCenter`/`tapAt` 替代 GDS 索引 `tapCell`（AppBar 新增 widget 会漂移 detector 顺序）。