# FR

一个功能丰富的 Flutter 跨平台应用，集成了即时通讯、文件管理、KV 存储、多媒体处理、蓝牙交互、小游戏等多种能力。

## ✨ 功能特性

### 🔌 后端服务集成
- **KV 存储** — 支持键值对的增删改查，可设置 TTL 过期时间
- **文件服务** — 文件上传、下载、删除及元数据查询，支持自动过期
- **WebSocket 实时通讯** — 支持房间机制、消息广播、连接状态统计

### 📱 客户端能力
- **蓝牙** — 基于 `flutter_blue_plus` 的蓝牙设备扫描与交互
- **多媒体** — 图片拍摄/选择/裁剪、视频播放（Chewie）、音频录制与播放
- **文件管理** — 文件选择、相册管理（photo_manager）
- **传感器** — 加速度传感器，支持摇一摇检测
- **Markdown** — 内置 Markdown 渲染与编辑
- **小游戏** — 基于 Flame 游戏引擎的小游戏模块
- **桌面小组件** — Home Widget 支持，含本地通知
- **Emoji 选择器** — 内置表情选择面板
- **拖拽排序** — 可拖拽重排的网格视图

## 🏗️ 项目架构

```
lib/
├── core/          # 核心基础设施
├── models/        # 数据模型（JSON 序列化）
├── providers/     # 状态管理（Provider）
├── screens/       # 页面视图
├── services/      # 业务服务层
├── utils/         # 工具函数
├── widgets/       # 可复用组件
├── home_widget/   # 桌面小组件
├── lab/           # 实验性功能
├── generated/     # 自动生成代码（OpenAPI 等）
└── main.dart      # 应用入口
```

## 🛠️ 技术栈

| 层级 | 技术选型 |
|------|---------|
| 框架 | Flutter (Dart) |
| 状态管理 | Provider |
| 网络请求 | http |
| 本地存储 | SharedPreferences |
| 数据序列化 | json_annotation + json_serializable |
| 实时通讯 | WebSocket |
| 视频播放 | video_player + Chewie |
| 音频 | audioplayers + record |
| 游戏引擎 | Flame |
| 蓝牙 | flutter_blue_plus |
| 代码生成 | build_runner + OpenAPI Generator |

## 🚀 快速开始

### 环境要求

- Flutter SDK `^3.11.1`
- Dart SDK（随 Flutter 附带）

### 安装与运行

```bash
# 克隆仓库
git clone https://github.com/ZHLX2005/fr.git
cd fr

# 安装依赖
flutter pub get

# 生成序列化代码
flutter pub run build_runner build --delete-conflicting-outputs

# 运行应用
flutter run
```

### 支持平台

- ✅ Android
- ✅ iOS
- ✅ Web
- ✅ macOS
- ✅ Linux
- ✅ Windows

## 📡 API 概览

项目对接的后端服务提供以下接口：

### KV 存储
| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/kv` | 列表查询 |
| POST | `/api/v1/kv` | 设置键值对 |
| GET | `/api/v1/kv/:key` | 获取指定 Key |
| DELETE | `/api/v1/kv/:key` | 删除指定 Key |

### 文件服务
| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/v1/upload` | 上传文件 |
| GET | `/api/v1/download/:id` | 下载文件 |
| GET | `/api/v1/file/:id/metadata` | 获取文件元数据 |
| DELETE | `/api/v1/file/:id` | 删除文件 |

### WebSocket
| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/ws` | 建立 WebSocket 连接 |
| POST | `/api/v1/ws/broadcast` | 广播消息 |
| GET | `/api/v1/ws/rooms` | 获取房间列表 |
| GET | `/api/v1/ws/stats` | 连接统计 |

## 📄 License

Private project — All rights reserved.
