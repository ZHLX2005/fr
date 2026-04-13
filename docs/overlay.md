  Kotlin 全权负责：
    ├── 悬浮窗管理（显示/隐藏）
    ├── 截屏（MediaProjection + ImageReader 常驻）
    ├── 区域选择 + ChatOverlayView
    ├── AI API 调用（发送请求、解析 SSE）
    ├── 流式答案写入原生 UI
    └── Flutter 只做：
          ├── 启动/停止悬浮窗服务
          ├── 权限跳转
          └── AI 配置存取（SharedPreferences）
