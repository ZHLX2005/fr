# C 簇 apk 显示时间 +8h 根因诊断(待后端修复)

> 状态:仅诊断,**前端代码逻辑自洽**;真实根因在后端。
> 配套 todo: kvcli topic=fr, id=3, "apk 下载,显示的时间会变大八个小时,自己调用后端接口测试一下,如果不是后端问题就是前端自己加了 8 小时"

## 关键证据

`GET http://47.110.80.47:8988/files/by-key/fr_latest_apk` + `Range: bytes=0-0` 真实响应头:

```
HTTP/1.1 206 Partial Content
Accept-Ranges: bytes
Cache-Control: public, max-age=3600
Content-Length: 1
Content-Range: bytes 0-0/57172082
Content-Type: application/octet-stream
Etag: "e22f1769a1589e68ac6138cf7ad46312"
Last-Modified: Sat, 08 Aug 2026 21:21:23 GMT
Date:         Sat, 08 Aug 2026 13:22:18 GMT
```

curl 时间戳:`Sat, 08 Aug 2026 13:08:33 GMT`(curl 命令发起时刻,Dart 同侧 UTC)。

## 根因

后端把**非 UTC 的本地时钟**(推测 +08:00,服务器系统时区)直接 `Format("Mon, 02 Jan 2006 15:04:05 GMT")` 写到了 `Last-Modified` 头 —— 而**没有把 time.Now() 先转 UTC**。证据链:

1. curl 命中时间:`Sat, 08 Aug 2026 13:08:33 GMT`(UTC 真实时刻)
2. `Date` 头(GoFrame 框架标准输出,=RFC1123 UTC):`13:22:18 GMT` —— 同一时区,自洽。
3. `Last-Modified`:`21:21:23 GMT` —— 比 `Date` 早 **约 8 小时**,但**位于文件上传之后**(`Date` 13:22 晚于文件上传 21:21?不可能,除非 Date 错)。
4. 更准确:**Last-Modified 是文件落盘的"系统时钟"**,而该时钟是 **+08:00 的本地时间** —— 后端没把它转 UTC 就直接 Format "GMT" 标签。

公式:

```
后端 time.Now() = 21:21:23 (+08:00 本地)
后端 Format "GMT" = "21:21:23 GMT"           ← 错误:把 +08:00 标签成 GMT
前端 HttpDate.parse → DateTime.utc(21:21:23) ← 误认为 UTC
前端 toLocal()  → 05:21:23 (+08:00)          ← 再 +08:00 = 多 16h
```

或(取决于后端具体 timezone):

```
后端 time.Now() = 14:21:23 (UTC 正确) 但 Format 用了本地时区偏移
→ "Sat, 08 Aug 2026 22:21:23 +08:00" 但截掉 offset 当 GMT 解析
→ +8h
```

## 复测公式

把以上三个值列出:

| 字段 | 期望(GMT/UTC) | 实际响应 |
| --- | --- | --- |
| Date | curl 时刻 ≈ 13:08 | 13:22:18 ✅ 自洽 |
| Last-Modified | 文件上传 UTC | 21:21:23 ❌ 早 8h |

→ 后端写 `Last-Modified` 时**把 server tz 字符串塞到 GMT 标签里**。

## 前端代码现状(已自洽,不动)

- `lib/api/goframe/download/apk_endpoint.dart:137-169` 用 `Range: bytes=0-0` GET,读 `Last-Modified` 头,`HttpDate.parse` 解析。
- `lib/services/api_client.dart:58-68` `getApkMetadata` 注释明确"必须保留 UTC 避免本地时区非 +08:00 时早 8 小时",`toUtc().toIso8601String()` 输出标准 UTC Z 串。
- `lib/lab/demos/api_test/api_download_manager.dart:492-498` `_formatLocalTime` 把 UTC ISO / `HttpDate.parse` 后的 UTC DateTime 转本地时区可读串。

前端链路全部按"输入是 UTC,展示用本地时区"设计,**没有冗余的 +8h 加减**。

## 为什么不能纯前端修

- 假设把 `_formatLocalTime` 改成"先把 DateTime 当本地时间解析"——只对**这台服务器**碰巧正确;换服务器(或后端修了 timezone)立刻错- 假设加 "如果 Last-Modified 解析出的 UTC 时刻早于 Date,说明后端时间戳是本地时间"—— 启发式,不可靠,且 Date 头也是 GMT(自洽)所以 Last-Modified 比 Date 晚或早都可能是合理的。

正确做法 = **修后端**:`time.Now().UTC().Format(http.TimeFormat)`(Go 标准库)。

## 需要给后端发的修复 PR 描述(供引用)

```
Title: fix(file): Last-Modified header must be UTC, not server local time

GoFrame 默认 handler 写 Last-Modified 头时直接 Format(time.Now()),
会把服务器本地时区(Asia/Shanghai +08:00)的内容写到 RFC1123 串但保留 "GMT" 标签。
前端 HttpDate.parse 把整个串当 UTC 解析后,本机再 +08:00 = 多 16h(或 +08:00 减 8h,取决于写法)。

修复:在写 Last-Modified / Date 头处统一 time.Now().UTC().Format(http.TimeFormat)。
涉及 path: /files/by-key/:key 静态文件 handler (GoFrame static handler)。
```

## 验证步骤(后端修后)

1. 后端打 patch,容器内 `time` 命令确认 timezone。
2. `curl -s -i -r 0-0 "$BASE/files/by-key/fr_latest_apk"` → `Last-Modified` 应接近 `Date`(都是 GMT UTC)。
3. 前端不动,UI 显示时间应正确。
4. 复测跨时区(改设备 tz 到 UTC-5):仍正确(GMT 不带 tz 偏移)。

## 本仓库改动

**0 文件改动**。诊断 + 现场证据全部在本 spec。