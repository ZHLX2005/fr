# fr (小豆子)

Flutter 多功能应用，专注时间管理、AI 对话、数据追踪与实验性功能探索。

## 功能特性

### 核心功能
- **番茄钟** - 专注计时器，支持统计记录与科目管理
- **AI 聊天** - AI 助手与智能体对话（Supabase 后端）
- **课程表** - 课程时间表管理（Hive 本地存储，支持循环周）
- **局域网发现** - LocalNet 设备发现与通信（开发中占位）
- **相册管理** - 媒体资源管理与浏览（开发中占位）

### 实验性 Demo (Lab)
通过 IoC 容器注册管理，包含 35 个实验性页面：

| Demo | 说明 |
|------|------|
| Grid Dashboard | 仪表盘布局 |
| Notebook AI Proto | AI 笔记本原型 |
| Clock Demo | 时钟/计时器 UI |
| Network Demo | 网络功能演示 |
| Network Env Demo | 网络环境检测 |
| Game 2048 | 2048 游戏 |
| Free Canvas | 自由画布 |
| Drag Reorder | 拖拽排序网格 |
| Web Bookmark | 书签管理器 |
| Storage Analyze | 存储分析 |
| Hexagon Panel | 六边形面板 |
| Snake Game | 贪吃蛇游戏 |
| API Test | API 测试工具 |
| Calendar | 日历组件 |
| My Diary Header | 日记头部 |
| Water Capsule | 水胶囊 UI |
| Speech Synthesis | 语音合成 |
| Line Demo | 音游（节奏线） |
| Torch Demo | 手电筒控制 |
| Sensor Demo | 传感器数据 |
| Word Drag | 单词拖拽分类 |
| Overlay Demo | 悬浮窗（Android） |
| Body Map | 人体部位地图 |
| Localnet Demo | 局域网功能演示 |
| Gallery Demo | 相册功能演示 |
| Schema Demo | Schema 导航演示 |
| Color Palette | 调色板工具 |
| GitHub Demo | GitHub Actions/Issues |
| QR Demo | 二维码扫描与生成 |
| DoubleTime | 双时间轴可视化 |
| Notification Demo | 本地通知演示 |
| Novel Reader | 小说阅读器原型 |
| Arc Selector | 圆弧选择器 |
| Demo Laboratory | Rive 动画实验室 |
| Volume Decay | 音量衰减曲线 |
| Rive Pendulum | Rive 钟摆动画 |

## 技术栈

- **框架**: Flutter (Dart SDK ^3.11.1)
- **状态管理**: Provider + Riverpod
- **本地存储**: Hive + SharedPreferences
- **后端服务**: Supabase
- **HTTP**: http + web_socket_channel
- **原生桥接**: MethodChannel + Overlay Window
- **游戏引擎**: Flame
- **动画**: Rive

## 依赖项

| 分类 | 依赖 |
|------|------|
| 状态管理 | provider, flutter_riverpod |
| 存储 | hive, hive_flutter, shared_preferences, path_provider |
| 数据模型 | json_annotation, json_serializable, build_runner, uuid |
| 网络 | http, web_socket_channel, network_info_plus, supabase_flutter |
| 媒体 | just_audio, audioplayers, video_player, chewie, record, image_picker, image_cropper, photo_manager, file_picker, cached_network_image |
| UI组件 | cupertino_icons, flutter_markdown, markdown, flutter_widget_from_html, emoji_picker_flutter, flutter_reorderable_grid_view, flutter_card_swiper |
| 设备 | flutter_blue_plus, sensors_plus, permission_handler, app_settings, torch_light, screen_brightness, wakelock_plus, flutter_overlay_window |
| 功能 | url_launcher, webview_flutter, intl, home_widget, flutter_local_notifications, mobile_scanner, qr_flutter, open_filex, share_plus, flame |
| 构建 | flutter_lints, flutter_launcher_icons |

## 项目结构

```
lib/
├── main.dart                    # 应用入口（Supabase + Hive 初始化）
├── core/                        # 核心功能模块
│   ├── body/                    # 人体部位地图（记录/可视化）
│   │   ├── models/              # 数据模型
│   │   ├── pages/               # 页面
│   │   ├── painters/            # 自定义绘制
│   │   └── widgets/             # 组件
│   ├── color/                   # 调色板工具
│   │   └── theme/               # 应用主题配置
│   ├── doubletime/              # 双时间轴可视化
│   ├── focus/                   # 番茄钟（计时/统计/科目）
│   │   ├── models/
│   │   └── providers/
│   ├── github/                  # GitHub Actions & Issues 集成
│   ├── line/                    # 音游（节奏线游戏）
│   │   ├── models/
│   │   ├── pages/
│   │   ├── repository/
│   │   ├── settings/
│   │   └── widgets/
│   ├── localnet/                # 局域网发现与通信
│   │   ├── models/
│   │   ├── pages/
│   │   └── services/
│   ├── schema/                  # Schema 导航与解析
│   ├── storage/                 # 存储管理
│   ├── timetable/               # 课程表（DDD 架构）
│   │   ├── data/                # 数据层（Hive 仓库）
│   │   ├── domain/              # 领域模型
│   │   └── presentation/        # 展示层
│   └── word_drag/               # 单词拖拽分类
│       ├── models/
│       ├── providers/
│       └── widgets/
├── lab/                         # 实验性 Demo
│   ├── demos/                   # 31 个 Demo 页面
│   ├── models/                  # 数据模型
│   ├── providers/               # 状态管理
│   ├── utils/                   # 工具函数
│   ├── widgets/                 # 通用组件
│   ├── lab_container.dart       # IoC 容器
│   └── lab_bootstrap.dart       # Demo 注册引导
├── models/                      # 共享数据模型
├── native/                      # 原生桥接
│   ├── home_widget/             # 桌面小组件
│   └── overlay/                 # 悬浮窗服务
├── providers/                   # 全局状态管理
├── screens/                     # 页面
│   ├── chat/                    # AI 聊天 & Agent 聊天
│   ├── gallery/                 # 相册管理
│   ├── home/                    # 首页
│   ├── lab/                     # Lab 入口页
│   ├── native_controller/       # 原生控制器（媒体/通知/系统）
│   ├── profile/                 # 个人中心
│   └── theme/                   # 主题设置
├── services/                    # 业务服务（API/音频/图库/消息等）
├── utils/                       # 工具函数
├── widgets/                     # 通用组件（聊天气泡/Markdown/表情等）
└── generated/                   # OpenAPI 自动生成代码
    ├── api/                     # API 客户端
    ├── auth/                    # 认证模块
    └── model/                   # 数据模型
```

## 应用导航

底部导航栏（XiaoDouZiBottomBar，5 个位置 + 中央 "+" 按钮）：

| 索引 | 页面 | 说明 |
|------|------|------|
| 0 | **ProfilePage** | 个人中心（默认页） |
| 1 | **HomePage** | 聊天首页 |
| 2 | **FocusHomePage** | 番茄钟（中央 "+" 按钮直达） |
| 3 | **Placeholder** | 局域网发现（开发中） |
| 4 | **Placeholder** | 相册管理（开发中） |

- 支持深层链接 `fr://lab` 直接打开 Lab 页面
- 通过 MethodChannel 与 Android 原生通信

## 开发指南

### 环境要求
- Dart SDK ^3.11.1
- 无需本地 Java/Android 环境
- 所有调试通过 Web 构建完成

### 构建命令

```bash
# 获取依赖
flutter pub get

# Web release 构建（主要验证方式）
flutter build web --release

# 代码分析（检查错误和孤儿文件）
flutter analyze

# JSON 序列化代码生成
dart run build_runner build
```

### 工作流程
1. 完成代码修改后，执行 `flutter analyze | grep error` 验证无编译错误
2. 编译通过后，单独 `add` 和 `commit` 变更的文件（禁止 `add .`）
3. 推送到 GitHub，触发 CI/CD 流水线构建 APK

## 许可

MIT
