# API 代码生成指南

本文档说明如何根据 OpenAPI 文档生成 Dart/Flutter 客户端代码，以及后续如何维护同步。

## 1. 准备工作

### 1.1 安装代码生成器

```bash
npm install -g @openapitools/openapi-generator-cli
```

### 1.2 获取 API 文档

```bash
curl -s "http://47.110.80.47:8988/api.json" -o api_spec.json
```

> 注：每次 API 文档更新后，重新执行此步骤获取最新文档。

## 2. 生成代码

### 2.1 生成 Dart 客户端

```bash
openapi-generator-cli generate \
  -i api_spec.json \
  -g dart \
  -o generated_temp \
  --additional-properties=pubName=hello_api
```

### 2.2 复制到项目

```bash
# 复制生成的 lib 目录到 lib/generated
cp -r generated_temp/lib/* lib/generated/
```

### 2.3 修复生成代码（可选）

某些生成的代码可能需要手动修复：

```dart
// 修改 api_client.dart 中的默认 basePath
ApiClient({this.basePath = 'http://47.110.80.47:8988', ...});

// 修复 MultipartFile.fromJson 问题 (dev_ctr_hello_api_file_v1_file_upload_req.dart)
file: null, // MultipartFile cannot be created from JSON
```

## 3. 创建服务包装

在 `lib/services/` 下创建 API 包装类，简化调用：

```dart
// lib/services/api_client.dart
class ApiService {
  static const String baseUrl = 'http://47.110.80.47:8988';

  static final gen.ApiClient _client = gen.ApiClient(basePath: baseUrl);

  // KV 操作示例
  static Future<gen.DevCtrHelloApiKvV1KvGetRes?> getKv(String key) async {
    return await gen.KVApi(_client).apiV1KvKeyGet(key: key);
  }
}
```

## 4. 后续同步维护流程

当 API 文档发生更新时，按以下步骤同步：

### 4.1 更新 API 文档

```bash
curl -s "http://47.110.80.47:8988/api.json" -o api_spec.json
```

### 4.2 重新生成代码

```bash
# 删除旧的生成目录（如果存在）
rm -rf generated_temp

# 重新生成
openapi-generator-cli generate \
  -i api_spec.json \
  -g dart \
  -o generated_temp \
  --additional-properties=pubName=hello_api
```

### 4.3 更新 lib/generated

```bash
# 备份当前的 lib/generated
cp -r lib/generated lib/generated_backup

# 复制新生成的代码
cp -r generated_temp/lib/* lib/generated/

# 重新应用修复（见 2.3）
# - 修改 basePath
# - 修复 MultipartFile.fromJson
# - 修复路径参数替换 (重要!)
```

### 4.4 修复路径参数问题

生成器会把 `:key`、`:id` 等路径参数错误地放入 queryParams，需要手动修复：

```dart
// kv_api.dart - GET /api/v1/kv/:key
var path = r'/api/v1/kv/:key';
if (key != null) {
  path = path.replaceAll(':key', key);  // 替换为路径参数
}

// file_api.dart - 同理修复 :id
var path = r'/api/v1/file/:id';
if (id != null) {
  path = path.replaceAll(':id', id);
}
```

### 4.4 编译验证

```bash
flutter build web --release
```

### 4.5 测试

运行应用程序测试 API 功能是否正常。

## 5. 目录结构

```
lib/
├── generated/           # 自动生成的 API 代码（从 OpenAPI 生成）
│   ├── api/
│   ├── model/
│   └── api_client.dart
├── services/
│   └── api_client.dart # API 服务包装（手写）
└── lab/
    └── demos/
        └── api_test_demo.dart  # API 测试页面
```

## 6. 注意事项

1. **不要修改 `lib/generated/` 目录下的代码** - 这些是自动生成的，每次重新生成会被覆盖
2. **所有自定义代码放在 `lib/services/`** - 便于维护和更新
3. **及时处理 nullable 问题** - 生成代码可能产生 `String?` 类型，需要在调用处处理
4. **Web 上传限制** - 文件上传在 Web 平台可能有限制，真机测试更准确

## 7. 常用命令速查

| 操作 | 命令 |
|------|------|
| 更新 API 文档 | `curl -s "http://47.110.80.47:8988/api.json" -o api_spec.json` |
| 生成代码 | `openapi-generator-cli generate -i api_spec.json -g dart -o generated_temp` |
| 复制代码 | `cp -r generated_temp/lib/* lib/generated/` |
| 编译测试 | `flutter build web --release` |

## 8. 当前支持的 API

- **KV 存储**: GET/POST/DELETE `/api/v1/kv`
- **文件上传**: POST `/api/v1/upload`
- **文件下载**: GET `/api/v1/download/:id`
- **文件删除**: DELETE `/api/v1/file/:id`
- **文件元数据**: GET `/api/v1/file/:id/metadata`
- **WebSocket**: (暂不支持)
