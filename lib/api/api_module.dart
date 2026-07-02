/// API 模块 — 所有后端请求的统一入口。
///
/// 子目录即子模块，同级排列：
/// - `goframe/` — 小豆子 GoFrame 后端：KV、文件、APK 下载、文章编辑
/// - `github/`  — GitHub REST API：Actions、Issues
/// - `minimax/` — MiniMax TTS：配置 + 模型定义
/// - `notion/`  — Notion REST API：Database / Page / File Upload（图床）
library;

export 'api_config.dart';
export 'api_client.dart';
export 'api_response.dart';

export 'token/token_manager.dart';
export 'token/token_storage.dart';

export 'interceptors/auth_interceptor.dart';
export 'interceptors/logging_interceptor.dart';
export 'interceptors/retry_interceptor.dart';

export 'goframe/goframe.dart';
export 'github/github.dart';
export 'minimax/minimax.dart';
export 'notion/notion.dart';

export 'providers/api_providers.dart';
