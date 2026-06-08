---
name: api-module-auth
description: 小豆子 FR 的 lib/api/ 模块规范 — 目录即后端、深目录轻文件、全局拦截器链
---

# 小豆子 FR — API 模块规范

## 实际目录结构

```
lib/api/                                 33 files / 1424 lines
├── api_module.dart        (24行)  ← barrel export
├── api_config.dart        (30行)  ← baseUrl + timeout
├── api_client.dart        (197行) ← 拦截器链 + HTTP 核心
├── api_response.dart      (38行)  ← ApiResponse / ApiException
│
├── token/                              ← Token 生命周期
│   ├── token_storage.dart   (66行)    ← SharedPreferences 实现
│   └── token_manager.dart   (63行)    ← 获取/缓存/refresh
│
├── interceptors/                        ← 拦截器链
│   ├── auth_interceptor.dart   (37行)  ← Bearer 注入 + 401 refresh
│   ├── logging_interceptor.dart (30行) ← 请求/响应日志
│   └── retry_interceptor.dart   (39行) ← 5xx 指数退避重试
│
├── goframe/                            ── 小豆子 GoFrame 后端
│   ├── goframe.dart          (10行)    ← barrel
│   ├── goframe_config.dart    (6行)    ← baseUrl 常量
│   ├── kv/
│   │   ├── kv.dart            (1行)    ← barrel
│   │   └── kv_endpoint.dart   (67行)   ← get/set/delete/list
│   ├── file/
│   │   ├── file.dart          (1行)    ← barrel
│   │   └── file_endpoint.dart  (103行) ← upload/metadata/delete
│   ├── download/
│   │   ├── download.dart      (2行)    ← barrel
│   │   ├── download_controller.dart (16行) ← cancel/pause/resume
│   │   └── apk_endpoint.dart   (131行) ← 流式下载 + 断点续传
│   └── article/
│       ├── article.dart       (1行)    ← barrel
│       └── article_endpoint.dart (51行) ← AI 文章编辑
│
├── github/                             ── GitHub REST API
│   ├── github.dart            (13行)   ← barrel
│   ├── github_config.dart      (8行)   ← baseUrl / version 常量
│   ├── github_exception.dart   (12行)  ← GithubApiException
│   ├── actions/
│   │   ├── actions.dart        (2行)   ← barrel
│   │   ├── actions_endpoint.dart (87行) ← listRuns / listJobs
│   │   └── actions_models.dart (86行)  ← WorkflowRunModel / WorkflowJobModel
│   └── issues/
│       ├── issues.dart         (2行)   ← barrel
│       ├── issues_endpoint.dart (101行)← CRUD + close/reopen
│       └── issues_models.dart  (63行)  ← IssueModel / CreateIssueRequest
│
├── minimax/                            ── MiniMax TTS
│   ├── minimax.dart           (8行)    ← barrel
│   ├── minimax_config.dart    (13行)   ← WS URL / 默认音色
│   └── models/
│       └── tts_models.dart    (67行)   ← SynthesisParams / TaskState
│
└── providers/
    └── api_providers.dart     (49行)   ← Riverpod 注入全部 endpoint
```

## 模块依赖矩阵

| 文件 | 导入 | 行数 | 角色 |
|------|------|------|------|
| `api_client.dart` | api_config, api_response, interceptors/*, token/token_manager | 197 | **核心** — 拦截器链编排 |
| `api_config.dart` | — | 30 | 配置常量 |
| `api_response.dart` | — | 38 | 响应模型 |
| `token/token_manager.dart` | token_storage | 63 | Token 生命周期 |
| `token/token_storage.dart` | shared_preferences | 66 | 持久化 |
| `interceptors/*` | api_client, api_response, token_manager | 30-39 | 拦截器，每个 1 职责 |
| `goframe/*/kv_endpoint.dart` | api_client, api_response | 67 | **端点** |
| `goframe/*/file_endpoint.dart` | api_client, api_response | 103 | **端点** |
| `goframe/*/apk_endpoint.dart` | api_config, download_controller, http, path_provider, io | 131 | **端点**（流式，直连 http） |
| `goframe/*/article_endpoint.dart` | api_client, api_response | 51 | **端点** |
| `github/*/actions_endpoint.dart` | github_config, github_exception, actions_models, http | 87 | **端点**（独立 baseUrl，自持 http） |
| `github/*/issues_endpoint.dart` | github_config, github_exception, issues_models, http | 101 | **端点** |
| `minimax/models/*` | — | 67 | **纯模型** |
| `providers/api_providers.dart` | 全部 goframe endpoint + api_client + token | 49 | DI 组装 |

## 模块职责边界

| 模块 | 职责 | 禁止混入 |
|------|------|---------|
| `api_client.dart` | 拦截器链 + HTTP 核心 + `ApiResponse` 解析 | 业务 URL、业务模型 |
| `api_config.dart` | baseUrl、timeout 配置 | 任何运行时代码 |
| `api_response.dart` | `ApiResponse<T>`、`ApiException` 定义 | 业务字段 |
| `interceptors/` | 横切关注点：auth / log / retry | 业务逻辑、状态管理 |
| `token/` | Token 生命周期：缓存、持久化、refresh | HTTP 细节 |
| `goframe/` | 小豆子 GoFrame 后端 (47.110.80.47:8988) | 其他后端逻辑 |
| `github/` | GitHub REST API (api.github.com) | GoFrame/Minimax 逻辑 |
| `minimax/` | MiniMax TTS 配置 + 模型定义 | HTTP 请求细节 |
| `providers/` | Riverpod DI 组装 | 任何业务逻辑 |

## 架构原则

### 1. 子目录 = 后端名称，同级排列

```
lib/api/goframe/   ← 自己后端的 API
lib/api/github/    ← GitHub 的 API
lib/api/minimax/   ← MiniMax 的 API
```

不看代码就知道依赖了哪些远端服务。新增后端直接加同级目录。

### 2. 深目录、轻文件

每个端点（kv、file、download、article）各自是一个子目录，哪怕是 1 个 API 也占 1 个目录。文件控制在 200 行以内。

```
goframe/download/
├── download.dart              (2行)   ← barrel
├── download_controller.dart   (16行)  ← 工具类
└── apk_endpoint.dart          (131行) ← 业务端点
```

barrel 文件只做 `export`，不含业务逻辑。

### 3. 共享基础设施，不共享 baseUrl

| 后端 | baseUrl | HTTP 方式 |
|------|---------|----------|
| goframe/ | 走 `api_client.dart`（统一拦截器链） | `ApiClient.request()` |
| github/ | 自持 `http.Client`（不同 baseUrl/header 规范） | `_client.get/post/patch` |
| minimax/ | 纯模型 + 配置（WS 会话在 service 层管理） | 不发起 HTTP |

不同 baseUrl 的后端不强行套同一拦截器链，避免拦截器污染。

---

## 反正面案例

### bad_example — 层级混乱

```dart
// ❌ core/ + endpoints/ 两个抽象层，分不清哪个属于哪个后端
lib/api/
├── core/                   // "core" 是什么后端？
├── endpoints/              // "endpoints" 是什么维度？
└── minimax/                // 突然冒出个具体后端名
```

### good_eg — 目录 = 后端

```dart
// ✅ 每个目录代表一个后端，一视同仁同级排列
lib/api/
├── goframe/                // 小豆子后端
├── github/                 // GitHub API
└── minimax/                // MiniMax TTS
```

### bad_example — 大文件违反单一职责

```dart
// ❌ 旧 services/api_client.dart (439行)
// 同时处理：HTTP 客户端 + KV 调用 + 文件上传 + 流式下载 + 平台判断
class ApiService {
  static const String baseUrl = 'http://47.110.80.47:8988';  // 配置
  static Future<bool> setKv(...) { ... }                     // KV 业务
  static Future<String?> downloadApkToLocal(...) { ... }      // 流式下载
  // ... 440 行
}
```

### good_eg — 每个文件只做一件事

```dart
// ✅ goframe/kv/kv_endpoint.dart (67行) — 只做 KV 请求
class KvEndpoint {
  final ApiClient _client;
  KvEndpoint(this._client);

  Future<ApiResponse<KvItem?>> get(String key) => _client.request<KvItem>(
    method: 'GET',
    path: '/api/v1/kv/$key',
    fromJson: (json) => KvItem.fromJson(json),
  );
  // set() / delete() / list() ...
}

// ✅ goframe/download/download_controller.dart (16行) — 只做下载控制
class DownloadController { ... }

// ✅ goframe/download/apk_endpoint.dart (131行) — 只做 APK 流式下载
class ApkDownloadEndpoint { ... }
```

### bad_example — 后端间用错 baseUrl

```dart
// ❌ GitHub 端点走了 GoFrame 的拦截器链
final response = await _apiClient.request(
  method: 'GET',
  path: 'https://api.github.com/repos/owner/repo/actions/runs',
  // 拦截器会注入 'Authorization: Bearer <goframe-token>'，但 GitHub 需要自己的 token
);
```

### good_eg — 不同后端各走各的 HTTP

```dart
// ✅ goframe: 走统一拦截器链（共享 auth/log/retry）
class KvEndpoint {
  final ApiClient _client;  // 拦截器链处理 token + log + retry
}

// ✅ github: 自持 http.Client（不同 baseUrl + 不同 auth）
class GithubActionsEndpoint {
  final String token;           // GitHub PAT
  final http.Client _client;    // 自持 client
  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
  };
}
```

---

## 未来扩展

新增后端 API 时：

```bash
# 1. 创建目录
mkdir -p lib/api/xxx/
echo "export 'xxx_endpoint.dart';" > lib/api/xxx/xxx.dart

# 2. 写端点
cat > lib/api/xxx/xxx_endpoint.dart <<EOF
import '../api_client.dart';
import '../api_response.dart';

class XxxEndpoint {
  final ApiClient _client;
  XxxEndpoint(this._client);
  // ...
}
EOF

# 3. 注册 barrel
echo "export 'xxx/xxx.dart';" >> lib/api/api_module.dart

# 4. 注入 provider (如果用 Riverpod)
# 在 providers/api_providers.dart 加一行 Provider<XxxEndpoint>
```

## 代码异味检测命令

```bash
# 检查超 200 行的文件
find lib/api -name "*.dart" -exec wc -l {} + | sort -rn | awk '$1 > 200'

# 检查 barrel 文件是否混入业务逻辑
grep -rn "class \|Future\|import 'package:" lib/api --include="*dart" | grep -E "/(goframe|github|minimax)/[a-z]+\.dart:" | grep -v "_endpoint\|_models\|_config\|_exception\|_controller"
```
