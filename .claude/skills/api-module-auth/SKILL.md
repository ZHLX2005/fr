---
name: api-module-auth
description: Flutter 项目中分离 API 模块、统一管理后端请求、全局 token 拦截器 / 中间件的规范
---

# 小豆子 FR — API 模块与全局 Token 拦截器规范

## 当前现状分析

### 目录分析

| 文件 | 行数 | 职责 | 问题 |
|------|------|------|------|
| `lib/services/api_client.dart` | 439 | 包装 OpenAPI 生成的 KV/File 接口 + 流式 APK 下载 | 440 行，混入下载控制、断点续传、平台判断 |
| `lib/generated/api_client.dart` | 371 | OpenAPI 生成的底层 HTTP 调用 | 不可修改，无拦截器，无 token 管理 |
| `lib/generated/auth/http_bearer_auth.dart` | 53 | OpenAPI 生成的 Bearer Auth 类 | 未在项目中使用 |
| `lib/core/github/github_actions_service.dart` | 76 | GitHub Actions API | 自己管理 token，`_checkError` 与 issues 服务重复 |
| `lib/core/github/github_issues_service.dart` | 90 | GitHub Issues API | 同上，`_headers` 重复构造 |
| `lib/services/minimax_speech_service.dart` | 442 | MiniMax TTS API | 内联 API Key，无统一拦截器 |
| `lib/core/line/io/supabase_config.dart` | 14 | Supabase 初始化 | 使用 Supabase SDK，不走统一 HTTP 模块 |

### 依赖矩阵

```dart
// 当前 HTTP 调用分散方式
api_client.dart  → generated/api_client.dart (OpenAPI)
                 → http.Client (直连下载)
                 → http.MultipartRequest (文件上传绕过 generated)
github_*.dart    → http package (直连，自己拼 headers)
minimax_*.dart   → http package (直连，自己拼 headers)
```

### 关键问题

1. ❌ **无统一拦截器** — 每个服务自己拼 `Authorization` header，无全局 token 刷新/过期处理
2. ❌ **无统一错误处理** — `_checkError` 方法在 github 服务中重复了两次
3. ❌ **无统一超时/重试** — 所有请求裸调用，无重试逻辑
4. ❌ **baseUrl 硬编码** — `api_client.dart:56` 写死 `http://47.110.80.47:8988`
5. ❌ **token 手动传入** — 每个需要 token 的服务通过构造函数参数传入

---

## 目标架构

```
lib/
├── api/                           ← 新建：统一 API 模块
│   ├── api_module.dart            ← barrel export
│   ├── api_config.dart            ← baseUrl, timeout, 环境切换
│   ├── api_client.dart            ← 核心 HTTP 客户端（拦截器链）
│   ├── interceptors/
│   │   ├── auth_interceptor.dart  ← 全局 Bearer Token 拦截器
│   │   ├── logging_interceptor.dart ← 请求/响应日志
│   │   └── retry_interceptor.dart ← 自动重试 + 指数退避
│   ├── token/
│   │   ├── token_manager.dart     ← token 获取/刷新/持久化
│   │   └── token_storage.dart     ← SharedPreferences 封装
│   └── endpoints/                 ← 业务端点分组
│       ├── kv_endpoint.dart       ← KV 操作
│       ├── file_endpoint.dart     ← 文件上传/下载
│       └── auth_endpoint.dart     ← 登录/注册/refresh
├── services/
│   └── api_client.dart            ← [删除] 迁移到 api/ 目录
└── core/github/                   ← [改造] 接入统一客户端
```

### 职责边界

| 层级 | 职责 | 禁止混入 |
|------|------|---------|
| `api/api_client.dart` | 统一的 HTTP 客户端实例，拦截器链编排 | 业务逻辑、具体 API 路径 |
| `api/interceptors/` | 拦截器：每个只做一件事 | 业务判断、状态管理 |
| `api/token/` | Token 生命周期：获取、缓存、刷新、持久化 | HTTP 请求细节 |
| `api/endpoints/` | 具体 API 端点：拼 URL、发请求、解析响应 | 拦截器逻辑、UI 状态 |
| `api/api_config.dart` | 配置常量：baseUrl、timeout、环境标识 | 任何运行时代码 |

---

## 规范细则

### 1. 客户端层 — `api_client.dart`

使用 `package:http` 的 `Client` 包装拦截器链，**不引入 dio**（项目已在用 http，保持一致）。

```dart
// ✅ good_eg — 统一的 Client 工厂
class ApiClient {
  late final http.Client _inner;
  late final List<Interceptor> _interceptors;

  ApiClient({required ApiConfig config}) {
    _inner = http.Client();
    _interceptors = [
      AuthInterceptor(tokenManager: config.tokenManager),
      LoggingInterceptor(),
      RetryInterceptor(maxRetries: config.maxRetries),
    ];
  }

  Future<ApiResponse<T>> request<T>({
    required String method,
    required String path,
    Map<String, String>? headers,
    Object? body,
    T Function(Map<String, dynamic>)? fromJson,
  }) async {
    var chain = _buildChain(method, path, headers, body);
    for (final interceptor in _interceptors) {
      chain = interceptor.intercept(chain);
    }
    return chain.execute();
  }
}
```

```dart
// ❌ bad_example — 在业务代码中直接裸调 http.get
class GithubActionsService {
  Future<List<WorkflowRunModel>> listLatestWorkflowRuns() async {
    final uri = Uri.parse('$_apiBase/actions/runs');
    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',  // ❌ 手动拼 token
      'Accept': 'application/vnd.github+json',
    });
    _checkError(response);  // ❌ 重复的错误处理
    // ...
  }
}
```

### 2. Token 管理层 — `token_manager.dart`

统一管理 token 的获取、缓存、刷新、持久化。支持两种模式：

- **静态 token**（如 GitHub PAT）：用户输入后持久化，手动失效
- **动态 token**（如登录 JWT）：自动 refresh，过期时静默续期

```dart
// ✅ good_eg — TokenManager 单例
class TokenManager {
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  final TokenStorage _storage;

  TokenManager({required TokenStorage storage}) : _storage = storage;

  Future<String?> get accessToken async {
    // 1. 内存缓存优先
    if (_accessToken != null && !_isExpired) return _accessToken;
    // 2. 尝试从持久化恢复
    await _hydrate();
    if (_accessToken != null && !_isExpired) return _accessToken;
    // 3. 尝试 refresh
    if (_refreshToken != null) await _tryRefresh();
    return _accessToken;
  }

  Future<void> setTokens({
    required String accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _expiresAt = expiresAt;
    await _storage.save(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt);
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    await _storage.clear();
  }
}
```

```dart
// ❌ bad_example — token 散落在各业务代码中
class GithubIssuesService {
  final String token;  // ❌ 每个服务自己存 token
  
  GithubIssuesService({required this.token});  // ❌ 构造函数传入

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',  // ❌ 重复拼装
  };
}

class GithubActionsService {
  final String token;  // ❌ 重复
  GithubActionsService({required this.token});
  Map<String, String> get _headers => { /* 同上的代码 */ };
}
```

### 3. 拦截器层 — `auth_interceptor.dart`

拦截器模式：每个拦截器处理横切关注点，组合成链。

```dart
// ✅ good_eg — AuthInterceptor 用抽象 Interceptor 接口
abstract class Interceptor {
  Future<ApiResponse<T>> intercept<T>(ApiChain<T> chain);
}

class AuthInterceptor implements Interceptor {
  final TokenManager tokenManager;

  AuthInterceptor({required this.tokenManager});

  @override
  Future<ApiResponse<T>> intercept<T>(ApiChain<T> chain) async {
    final token = await tokenManager.accessToken;
    if (token != null) {
      chain.headers['Authorization'] = 'Bearer $token';
    }
    final response = await chain.proceed();

    // 401 → 尝试 refresh → 重试
    if (response.code == 401 && await tokenManager.tryRefresh()) {
      final refreshed = await tokenManager.accessToken;
      if (refreshed != null) {
        chain.headers['Authorization'] = 'Bearer $refreshed';
        return chain.proceed();  // 静默重试一次
      }
    }
    return response;
  }
}
```

```dart
// ❌ bad_example — 在业务方法内处理 401 重试
Future<IssueModel> createIssue(CreateIssueRequest request) async {
  var response = await http.post(uri, headers: _headers, body: body);
  if (response.statusCode == 401) {  // ❌ 业务代码处理认证重试
    await _refreshToken();
    _headers['Authorization'] = 'Bearer $_newToken';
    response = await http.post(uri, headers: _headers, body: body);
  }
  _checkError(response);  // ❌ 业务代码处理错误
  // ...
}
```

### 4. 端点层 — 业务 API

```dart
// ✅ good_eg — endpoint 只关注接口语义
class KvEndpoint {
  final ApiClient _client;

  KvEndpoint(this._client);

  Future<ApiResponse<KvItem?>> get(String key) {
    return _client.request(
      method: 'GET',
      path: '/api/v1/kv/$key',
      fromJson: (json) => KvItem.fromJson(json),
    );
  }

  Future<ApiResponse<bool>> set(String key, String value, {int? ttl}) {
    return _client.request(
      method: 'POST',
      path: '/api/v1/kv',
      body: {'key': key, 'value': value, 'ttl': ttl},
    );
  }
}
```

```dart
// ❌ bad_example — 端点和客户端逻辑混合
// api_client.dart 里同时做了：
// - 创建 HTTP client
// - 拼 URL 路径
// - JSON 解析
// - 错误处理
// - 断点续传
// - 文件操作
// → 440 行，单一职责被违反
```

### 5. API Config — 环境配置

```dart
// ✅ good_eg — 可配置的 ApiConfig
class ApiConfig {
  final String baseUrl;
  final Duration timeout;
  final int maxRetries;
  final TokenManager tokenManager;

  ApiConfig({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    required this.tokenManager,
  });

  // 预置生产环境
  static ApiConfig production(TokenManager tm) => ApiConfig(
    baseUrl: 'http://47.110.80.47:8988',
    tokenManager: tm,
  );
}
```

```dart
// ❌ bad_example — baseUrl 硬编码在服务中
// api_client.dart:56
static const String baseUrl = 'http://47.110.80.47:8988';
// github_actions_service.dart:19 又写了一个
String get _apiBase => 'https://api.github.com/repos/$owner/$repo';
```

---

## 项目集成方式

由于项目使用 **Provider + Riverpod** 混合状态管理，**不引入 get_it**（已在 pubspec 但未使用），API 模块推荐以下集成方式：

### Riverpod Provider（推荐）

```dart
// ✅ good_eg — 用 Riverpod Provider 管理 API 客户端生命周期
// lib/api/api_module.dart
final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return SharedPrefsTokenStorage();
});

final tokenManagerProvider = Provider<TokenManager>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  return TokenManager(storage: storage);
});

final apiConfigProvider = Provider<ApiConfig>((ref) {
  final tm = ref.watch(tokenManagerProvider);
  return ApiConfig.production(tm);
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(apiConfigProvider);
  return ApiClient(config: config);
});

// 业务端点
final kvEndpointProvider = Provider<KvEndpoint>((ref) {
  return KvEndpoint(ref.watch(apiClientProvider));
});
```

```dart
// ❌ bad_example — 在 main.dart 中手动 new 并全局传递
void main() async {
  // ❌ 全局变量
  final tokenStorage = SharedPrefsTokenStorage();
  final tokenManager = TokenManager(storage: tokenStorage);
  final apiClient = ApiClient(ApiConfig.production(tokenManager));

  // ❌ 作为参数传到各个页面
  runApp(MyApp(apiClient: apiClient));
}
```

---

## 迁移路线

| 阶段 | 内容 | 兼容性 |
|------|------|--------|
| **Phase 1** | 创建 `lib/api/` 目录结构，实现 `ApiClient` + `AuthInterceptor` + `TokenManager` | 不影响现有代码 |
| **Phase 2** | 将 `lib/services/api_client.dart` 的 KV/File 端点迁移到 `api/endpoints/` | 旧 `ApiService` 保持不动，新 endpoint 并行运行 |
| **Phase 3** | 改造 `lib/core/github/` 服务使用统一客户端 | 去掉重复的 `_checkError` 和 `_headers` |
| **Phase 4** | 迁移 `lib/services/minimax_speech_service.dart` | 验证拦截器链对第三方 API 的兼容性 |
| **Phase 5** | 删除旧 `lib/services/api_client.dart` | 确保所有调用方已迁移 |

---

## 反正面案例总结

| 维度 | ❌ bad_example | ✅ good_eg |
|------|---------------|-----------|
| Token 传递 | 每个服务构造函数传入，自己拼 header | `TokenManager` 单例，拦截器自动注入 |
| 错误处理 | 每个服务写 `_checkError` 重复代码 | 拦截器统一处理，端点只关心成功路径 |
| 401 重试 | 业务代码中 `if (401)` 然后手动刷新 | `AuthInterceptor` 自动检测 → refresh → 重试 |
| baseUrl | 散落在各文件中硬编码 | `ApiConfig` 集中管理，支持环境切换 |
| 客户端创建 | 每个服务 `new http.Client()` | 统一 `ApiClient` 工厂，生命周期由 DI 管理 |
| 请求日志 | 无 / 每个服务自行 `print` | `LoggingInterceptor` 统一记录 |
| 超时/重试 | 无 | `RetryInterceptor` 指数退避 |

---

## 代码异味检测命令

```bash
# 检测手工拼装 Authorization header 的代码
grep -rn "'Authorization'" lib/ --include="*.dart" --exclude-dir=generated

# 检测重复的 _checkError 方法
grep -rn "statusCode >= 400\|_checkError" lib/ --include="*.dart"

# 检测重复的 Map<String, String> headers 构造
grep -rn "get _headers" lib/ --include="*.dart"

# 检测硬编码的 baseUrl/API 地址
grep -rn "http://\|https://" lib/ --include="*.dart" --exclude-dir=generated
```
