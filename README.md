# fr (小豆子)

Flutter 应用，专注时间管理与数据追踪。

## 功能特性

### 核心功能
- **番茄钟** - 专注计时器，支持统计记录
- **聊天功能** - AI 助手与智能体对话
- **相册管理** - 媒体资源管理与浏览
- **局域网发现** - LocalNet 设备发现与连接
- **课程表** - 课程时间表管理

### 实验性 Demo (Lab)
通过 IoC 容器注册管理，包含 20+ 实验性页面：

| Demo | 说明 |
|------|------|
| Grid Dashboard | 仪表盘布局 |
| Notebook AI Proto | AI 笔记本原型 |
| Clock Demo | 时钟/计时器 UI |
| Network Demo | 网络功能演示 |
| Game 2048 | 2048 游戏 |
| Free Canvas | 自由画布 |
| Drag Reorder | 拖拽排序网格 |
| Web Bookmark | 书签管理器 |
| Storage Analyze | 存储分析 |
| Hexagon Panel | 六边形面板 |
| Typewriter | 打字机效果 |
| Snake Game | 贪吃蛇游戏 |
| API Test | API 测试工具 |
| Calendar | 日历组件 |
| My Diary Header | 日记头部 |
| Water Capsule | 水胶囊 UI |
| Speech Synthesis | 语音合成 |
| Line Demo | 折线图 |
| Torch Demo | 手电筒控制 |

## 技术栈

- **框架**: Flutter 3.x
- **状态管理**: Provider + Riverpod
- **本地存储**: Hive + SharedPreferences
- **HTTP**: http + web_socket_channel
- **原生桥接**: MethodChannel

## 依赖项

| 分类 | 依赖 |
|------|------|
| UI | cupertino_icons, cached_network_image, flutter_markdown, flutter_widget_from_html, emoji_picker_flutter |
| 存储 | hive, hive_flutter, shared_preferences, path_provider |
| 媒体 | just_audio, audioplayers, video_player, chewie, record, image_picker, photo_manager |
| 网络 | http, web_socket_channel |
| 设备 | flutter_blue_plus, sensors_plus, permission_handler |
| 功能 | url_launcher, webview_flutter, app_settings, image_cropper, flutter_reorderable_grid_view, home_widget, flutter_local_notifications |
| 构建 | json_serializable, build_runner, flutter_launcher_icons |

## 项目结构

```
lib/
├── main.dart                    # 应用入口
├── core/                        # 核心功能模块
│   ├── focus/                   # 番茄钟
│   ├── localnet/                # 局域网发现
│   ├── storage/                 # 存储管理
│   ├── theme/                   # 主题配置
│   └── timetable/               # 课程表
├── lab/                         # 实验性 Demo
│   ├── demos/                   # Demo 页面
│   ├── models/                  # 数据模型
│   ├── providers/               # 状态管理
│   ├── utils/                   # 工具函数
│   ├── widgets/                 # 通用组件
│   └── lab_container.dart       # IoC 容器
├── models/                      # 共享数据模型
├── providers/                   # 全局状态管理
├── screens/                     # 页面
│   ├── chat/                    # 聊天
│   ├── gallery/                 # 相册
│   ├── home/                    # 首页
│   ├── lab/                     # Lab 入口
│   ├── native_controller/       # 原生控制器
│   ├── profile/                 # 个人中心
│   └── theme/                   # 主题设置
├── services/                    # 业务服务
├── utils/                       # 工具函数
├── widgets/                     # 通用组件
├── home_widget/                 # 首页组件
└── generated/                  # 生成代码
```

## 开发指南

### 环境要求
- Flutter SDK
- 无需本地 Java/Android 环境
- 所有调试通过 Web 构建完成

### 构建命令

```bash
# 获取依赖
flutter pub get

# Web release 构建（主要验证方式）
flutter build web --release

# 代码分析
flutter analyze
```

### 工作流程
1. 完成代码修改后，执行 `flutter build web --release` 验证编译
2. 编译通过后，单独 add 和 commit 变更的文件
3. 推送到 GitHub，触发 CI/CD 流水线构建 APK

## 应用导航

底部导航栏（5 个标签页）：

0. **ProfilePage** - 个人中心
1. **HomePage** - 聊天首页
2. **FocusHomePage** - 专注计时器
3. **LocalnetDiscoverPage** - 局域网发现
4. **GalleryManagePage** - 相册管理

## 许可

MIT
