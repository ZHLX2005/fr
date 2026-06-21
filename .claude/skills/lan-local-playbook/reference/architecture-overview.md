# 三层架构详解

## 模块依赖图

```
surround_game/ (53 files)           ← Game Layer: 纯业务
    │
    ├── lan/service/lan_service_adapter.dart  ← 唯一 LAN 边界
    │       │
    │       v  (import localnet)
    │
    ├── local/          ← 不依赖 localnet
    ├── engine/         ← 不依赖 localnet
    ├── models/         ← 不依赖 localnet
    ├── widgets/        ← 不依赖 localnet
    └── replay/         ← 不依赖 localnet
```

```
localnet_biz/ (14 files, @Deprecated) ← Biz Layer: 业务封装
    │
    └── localnet_service.dart ← 已废弃，使用 LanFramework.instance 替代
```

```
localnet/ (28 files)                ← Framework Layer: 基础设施
    │
    ├── transport/     ← UDP + HTTP
    ├── device/        ← 发现 + 注册
    ├── channel/       ← 消息路由
    ├── session/       ← 状态同步
    ├── event_bus/     ← 事件总线
    └── framework/     ← LanFramework 门面
```

## Layer 3: Framework — `lib/core/localnet/`

**文件数**：28 文件 | **依赖**：无项目内依赖

| 子模块 | 核心文件 | 职责 |
|--------|---------|------|
| `framework/` | `lan_framework.dart`, `framework_core.dart`, `framework_config.dart` | 单例门面，启动/停止/配置 |
| `transport/` | `udp_transport.dart`, `http_transport.dart` | UDP 多播发现 + HTTP 点对点 |
| `device/` | `device.dart`, `device_manager.dart`, `device_registry.dart` | 设备发现、心跳、管理 |
| `channel/` | `channel_manager.dart`, `channel_message.dart` | 消息通道、路由、发送 |
| `session/` | `session.dart`, `session_manager.dart`, `state_serializer.dart` | 状态同步机制 |
| `event_bus/` | `event_bus.dart`, `lan_event.dart` | 事件总线（broadcast stream） |

**设计约束**：LanFramework 是"唯一门面"（facade pattern），业务层只应该通过它交互。

## Layer 2: Biz — `lib/core/localnet_biz/`

**文件数**：14 文件 | **状态**：`@Deprecated`（仅作参考）

| 文件 | 说明 |
|------|------|
| `localnet_service.dart` | 旧封装，已废弃 |
| `services/device_id_service.dart` | deviceId 持久化参考实现 |
| `services/config_service.dart` | 配置持久化参考实现 |
| `services/debug_log_service.dart` | 调试日志参考 |
| `pages/localnet_discover_page.dart` | 发现页面参考 |
| `models/localnet_message.dart` | 消息模型参考 |

**注意**：新代码应走 `LanServiceAdapter`（surround_game/lan/service/）或直接使用 `LanFramework.instance`。

## Layer 1: Game — `lib/core/surround_game/`

**文件数**：53 文件 | **本地模式 vs LAN 模式共用部分**：engine/ models/ widgets/ replay/

### 共用组件

| 目录 | 核心文件 | 职责 |
|------|---------|------|
| `engine/` | `game_engine.dart`, `bfs_pathfinder.dart` | 全静态纯函数引擎 |
| `models/` | `game_state.dart`, `game_event.dart` | 不可变值对象 |
| `widgets/` | `touch_controller.dart`, `chess_board.dart`, `chess_player.dart`, `chess_wall.dart`, `player_panel.dart`, `confirm_actions.dart` | UI 组件 |
| `replay/` | `replay_controller.dart`, `replay_page.dart` | 棋谱回放 |

### 本地模式特有

| 文件 | 角色 |
|------|------|
| `local/local_match_state.dart` | 状态密封类 |
| `local/local_match_event.dart` | 事件密封类 |
| `local/local_view_model.dart` | ViewModel + reducer |
| `local/local_game_page.dart` | 游戏页面（943 行，最大文件） |
| `local/widgets/touch_controller_factory.dart` | 标准 TouchController |

### LAN 模式特有

| 文件 | 角色 |
|------|------|
| `lan/service/lan_service_adapter.dart` | LAN 边界，唯一导入 localnet |
| `lan/protocol/lan_messages.dart` | 协议消息 sealed class |
| `lan/protocol/lan_channels.dart` | channel 常量 |
| `lan/lan_host_view_model.dart` | Host 状态机 |
| `lan/lan_client_view_model.dart` | Client 状态机 |
| `lan/lan_host_protocol_bridge.dart` | 协议事件 → Host 状态迁移 |
| `lan/lan_client_protocol_bridge.dart` | 协议事件 → Client 状态迁移 |
| `lan/serializer/game_state_serializer.dart` | Session 序列化器 |
| `lan/lan_lobby_page.dart` | 大厅页（发现+建房间） |
| `lan/lan_room_page.dart` | 房间等待页 |
| `lan/lan_host_game_page.dart` | Host 游戏页 |
| `lan/lan_client_game_page.dart` | Client 游戏页 |

## 添加新游戏的标准流程

1. **定义 State 和 Event**（参见 `local/local_match_state.dart` 和 `local/local_match_event.dart`）
2. **实现 ViewModel**（参见 `local/local_view_model.dart`）
3. **现有 UI 组件复用**（棋子、棋盘、墙壁、触控等 widgets/）
4. **如需 LAN 模式**，参考 `lan/` 下的 Adapter/Protocol/StateMachine 整套模式
