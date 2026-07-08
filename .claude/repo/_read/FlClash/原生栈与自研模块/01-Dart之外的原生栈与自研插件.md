# FlClash 的非 Dart 部分：原生栈、FFI 桥、自研插件与构建系统

> 本仓库 `lib/` 之外的栈非常稠密 —— Go ClashMeta 内核（含 CGO 与 C 桥接）、Rust 后台 helper、cargokit + flutter_rust_bridge 跨语言绑定、CMake/Gradle/Podspec 多平台构建钩子、以及一批自研 FFI 插件（tray/wifi_ssid/window_ext/rust_api/setup/proxy）。本文按"语言层"分类，逐项给出源码证据。

---

## 1. Go 内核层（`core/` + 子模块 `core/Clash.Meta/`）

### 1.1 整套 Go 项目作为外部子模块引入

`FlClash/.gitmodules` 把 Clash.Meta 的 Go fork 拉进来：

```ini
[submodule "core/Clash.Meta"]
    path = core/Clash.Meta
    url = git@github.com:chen08209/Clash.Meta.git
    branch = FlClash
```

证据：`.gitmodules`

Dart 这边根本不会编译 Go —— Go 是独立构建，只把产物（`libclash.so` 或独立可执行）扔给 Flutter 链接。

### 1.2 一个 Go 包同时出两种产物（c-shared + 子进程）

`core/main.go`（无 cgo 路径）走子进程模式：

```go
// core/main.go:1-17
//go:build !cgo
package main

func main() {
    args := os.Args
    if len(args) <= 1 {
        fmt.Println("Arguments error")
        os.Exit(1)
    }
    startServer(args[1])
}
```

`core/main_cgo.go`（有 cgo 路径）的 `main()` 是空的 —— 因为走 `libclash.so` 模式不会有 main()：

```go
// core/main_cgo.go:1-8
//go:build cgo
package main
import "C"
func main() {
}
```

也就是说 `package main` 被有意复用，依靠 `//go:build` 标签切两套入口。

### 1.3 CGO 导出（C ABI → Dart FFI）

Android 路径用 CGO 把核心导出成 C 符号供 Flutter FFI 调用：

```go
// core/lib.go:184-282（节选）
//export invokeAction
func invokeAction(callback unsafe.Pointer, paramsChar *C.char) { ... }
//export startTUN
func startTUN(callback unsafe.Pointer, fd C.int, stackChar, addressChar, dnsChar *C.char) bool { ... }
//export quickSetup
func quickSetup(callback unsafe.Pointer, initParamsChar *C.char, setupParamsChar *C.char) { ... }
//export setEventListener
//export getTotalTraffic
//export getTraffic
//export stopTun
//export suspend
//export forceGC
//export updateDns
```

注意：参数里既有 `unsafe.Pointer`（Dart 端 `Pointer<Void>`），也有 `*C.char`，还有 `C.int` —— 这是典型的 CGO + Dart FFI 透明对穿，把 Dart 的 `Function`/`Pointer<Utf8>` 暴露成 C 函数指针。

### 1.4 C ↔ Go 桥接层（`bride.c` / `bride.h` / `bride.go`）

为了不把 C 函数指针硬编码进 Go，C 端用**函数指针表**做间接跳转，Go 端负责赋值：

```c
// core/bride.h:5-13
extern void (*release_object_func)(void *obj);
extern void (*free_string_func)(char *data);
extern void (*protect_func)(void *tun_interface, int fd);
extern char* (*resolve_process_func)(...);
extern void (*result_func)(void *invoke_Interface, const char *data);
```

```c
// core/bride.c:1-31
void (*release_object_func)(void *obj);
void (*free_string_func)(char *data);
...
void protect(void *tun_interface, int fd) { protect_func(tun_interface, fd); }
```

```go
// core/bride.go（节选）—— Android 专用桥
func protect(callback unsafe.Pointer, fd int)            { C.protect(callback, C.int(fd)) }
func resolveProcess(...) string                            { ... C.resolve_process(...) }
func invokeResult(callback unsafe.Pointer, data string)   { ... C.result(callback, s) }
func releaseObject(callback unsafe.Pointer)               { C.release_object(callback) }
```

这是 `//go:build android && cgo`（见 `core/bride.go:1-7`）的 Android 专属块 —— Dart 端的包保护、uid 解析、回调释放都走这套表。

### 1.5 平台特定 guard：Android vs. 桌面走完全不同的连接方式

```go
// core/dial_pipe.go:1-13
//go:build windows && !cgo
func dial(path string) (io.ReadWriteCloser, error) {
    return winio.DialPipe(path, nil)
}
```

Windows 桌面用 `Microsoft/go-winio` 命名管道；macOS/Linux 走 Unix socket；Android 走 CGO + socket server —— Flutter 端只换 `lib/core/service.dart` 一个文件。

### 1.6 自己解析 `/proc/net/{tcp,udp}` 拿 socket 归属 uid

```go
// core/platform/procfs.go:1-30（节选）
//go:build linux
package platform
func QuerySocketUidFromProcFs(source, _ net.Addr) int {
    if netIndexOfLocal < 0 || netIndexOfUid < 0 {
        return -1
    }
    network := source.Network()
    if strings.HasSuffix(network, "4") || strings.HasSuffix(network, "6") {
        network = network[:len(network)-1]
    }
    ...
}
```

这是 Linux 上**不依赖 procps/systemd** 的纯 Go socket 元数据查询 —— 用于实现 Android 兼容的"按 uid 解析进程"。当 `version < 29` 时被 lib.go 调用做回退路径：

```go
// core/lib.go:96-100
if version < 29 {
    uid = platform.QuerySocketUidFromProcFs(source, target)
}
```

### 1.7 直接 hook mihomo 的 socket 钩子做 TUN 保护

```go
// core/lib.go:104-125
func (th *TunHandler) initHook() {
    dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error { ... }
    process.DefaultPackageNameResolver = func(metadata *constant.Metadata) (string, error) { ... }
}
```

即在 Go 内核内把上游库的全局钩子替换成 FlClash 自己版本的实现 —— 这是给 Android 上"每个 App 走独立代理"做底层支撑的。

### 1.8 自己用 `sing-tun` 起 TUN 设备（不走系统 VpnService）

```go
// core/tun/tun.go:17-71
func Start(fd int, stack string, address, dns string) *sing_tun.Listener {
    ...
    options := LC.Tun{
        Enable:              true,
        Device:              "FlClash",
        Stack:               tunStack,
        DNSHijack:           dnsHijack,
        AutoRoute:           false,
        AutoDetectInterface: false,
        Inet4Address:        prefix4,
        Inet6Address:        prefix6,
        MTU:                 9000,
        FileDescriptor:      fd,
    }
    listener, err := sing_tun.New(options, tunnel.Tunnel)
    return listener
}
```

接管 fd 表示 TUN 设备是 Java 侧（Android `VpnService.protect()` 后）已有的 fd —— Go 侧只负责协议栈。

---

## 2. Rust 后台 helper（`services/helper/`）

Windows 专用，受 **`windows-service`** crate 编译成真正的 Windows Service（不是普通进程），用来给 Go 内核提权启动 + 管理 TUN：

```toml
# services/helper/Cargo.toml
[package]
name = "helper"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "helper"
path = "src/main.rs"

[dependencies]
windows-service = { version = "0.7.0", optional = true }
tokio = { version = "1", features = ["full"] }
anyhow = "1.0.93"
warp = "0.3.7"            # 用 warp 当 IPC HTTP 服务
serde  = { version = "1.0.215", features = ["derive"] }
once_cell = "1.20.2"
sha2   = "0.10.8"         # 与 Flutter 端做 token 校验

[profile.release]
panic = "abort"
codegen-units = 1
lto = true
opt-level = "s"
```

显著特征：

- 它含 `service/...` 子目录 + `build.rs` + 专门的 Service 入口 —— 这是常规 Rust 项目中**少见**的双形态（CLI binary + Windows Service 同 crate）。
- 用 SHA-256 token 与 Flutter 端做"白名单握手"（详见 `AGENTS.md:192-197`）。
- debug 模式下 `cfg!(debug_assertions)` 跳过 token 校验，方便 flutter run 调试。

---

## 3. Dart ↔ Rust：cargokit + flutter_rust_bridge 体系（`plugins/rust_api/`）

### 3.1 用 cargokit 替代 gRPC/UniFFI

不像一般 Flutter 项目用 FFI 手写或 uniFFI，这里用 `flutter_rust_bridge`：

```yaml
# plugins/rust_api/flutter_rust_bridge.yaml
rust_input: crate::api
rust_root: rust/
dart_output: lib/src/rust
```

```yaml
# plugins/rust_api/pubspec.yaml（片段，省略部分）
ffiPlugin: true
```

`plugins/rust_api/cargokit/` 自带 —— 是 `cargokit`（`https://github.com/bundle-exe/cargokit`），可让 Flutter 在 iOS/Android/Linux/Windows 各家构建系统（Gradle / Pod / CMake）内调 Cargo。

### 3.2 Rust 源码只用一份，自动 codegen 出 Dart、`.io.dart`、`.web.dart` 三套

```
Rust source                Generated Dart            Public Dart API
─────────────────────      ─────────────────────     ─────────────────
rust/src/api/              lib/src/rust/api/          lib/rust_api.dart
  mod.rs ──► init.rs         (init has no Dart file)
  named_pipe.rs              named_pipe.dart
                           lib/src/rust/
                             frb_generated.dart       (re-exports RustLib)
                             frb_generated.io.dart    (FFI for native)
                             frb_generated.web.dart   (stub for web)
```

（来源：`plugins/rust_api/CLAUDE.md:24-32`）

也就是说，所有平台差异都收敛在 `frb_generated.io.dart` 一个文件 —— 三端只生成一份 Rust + 三份 Dart stub。

---

## 4. 桌面构建自研 Dart CLI（`plugins/setup/buildkit/`）

`setup.dart`（103 行，仓库根）只做"壳子"调度；真正运行 Go 编译的是 `plugins/setup/buildkit/build_tool/` —— 一个独立的 Dart CLI：

```dart
// setup.dart:7-25
const _allTargets = <String, String>{
  'android': 'apk',
  'linux': 'deb',
  'macos': 'dmg',
  'windows': 'exe,zip',
};

const _androidFlutterTarget = {
  'arm': 'android-arm',
  'arm64': 'android-arm64',
  'amd64': 'android-x64',
};
```

各平台的 Flutter 构建**自带钩子**触发它：

- **macOS**：podspec script phase → `build_pod.sh` → `build_tool macos`
- **Linux**：CMake include → `buildkit/cmake/buildkit.cmake` → `build_tool linux`
- **Windows**：CMake include → `buildkit/cmake/buildkit.cmake` → `build_tool windows`（debug: `--dev` 由 `CMAKE_BUILD_TYPE` 决定）
- **Android**：Gradle include → `buildkit/gradle/plugin.gradle` → `build_tool android`

（来源：`AGENTS.md:188-200`）

这意味着这是个**用 CMake + Gradle + Podspec 把 Cargo 与 Go 都编译进 Flutter App** 的多 polyglot 构建链。

---

## 5. 自研 FFI 插件清单（`plugins/` 下 7 个）

| 插件                    | 路径                             | 类型                       | 作用                                                     | 是否原生           |
| ----------------------- | -------------------------------- | -------------------------- | -------------------------------------------------------- | ------------------ |
| `setup`               | `plugins/setup/`               | FFI（无 Dart API）         | 仅做构建钩子（podspec/CMake/Gradle 触发 Go + Rust 编译） | ✗ 纯构建 harness  |
| `proxy`               | `plugins/proxy/`               | Dart（含平台 channels）    | 改系统代理                                               | ✓ 平台 channel    |
| `rust_api`            | `plugins/rust_api/`            | FFI（Flutter Rust Bridge） | 命名管道 / 本地 socket                                   | ✓ Rust + cargokit |
| `tray_manager`        | `plugins/tray_manager/`        | FFI                        | 系统托盘 ——**已 fork** 自上游                    | ✓                 |
| `wifi_ssid`           | `plugins/wifi_ssid/`           | Dart（method channel）     | 读当前 Wi-Fi SSID                                        | ✓                 |
| `window_ext`          | `plugins/window_ext/`          | Dart（method channel）     | 窗口扩展功能                                             | ✓                 |
| `flutter_distributor` | `plugins/flutter_distributor/` | Dart（工具）               | 打包发布（DEB / DMG / EXE）                              | ✗ 工具链          |

### 5.1 多个插件是仓库作者 fork 自上游的 git 路径

```yaml
# pubspec.yaml:17-21
window_manager:
  git:
    url: https://github.com/chen08209/window_manager
    ref: main
    path: packages/window_manager

# pubspec.yaml:48-52
re_editor:
  git:
    url: https://github.com/chen08209/re-editor
    ref: main

# pubspec.yaml:65-69
flutter_js:
  git:
    url: https://github.com/chen08209/flutter_js
    ref: master

# pubspec.yaml:72-75
yaml_writer:
  git:
    url: https://github.com/chen08209/yaml_writer
    ref: master
```

注意 `flutter_js` —— 它是一个"在 Flutter 里跑 JavaScript" 的引擎。

### 5.2 `window_ext` 是个"只有 macOS / Windows" 的 FFI 插件

```bash
$ ls plugins/window_ext/
analysis_options.yaml  CHANGELOG.md  lib  LICENSE  macos  pubspec.yaml  README.md  windows
```

没有 `android/` / `linux/` / `ios/` —— 说明这个插件只服务于桌面窗口子系统。

### 5.3 `wifi_ssid` 仅 Android 实装 + Linux/Windows 占位

```bash
$ ls plugins/wifi_ssid/
analysis_options.yaml  android  lib  linux  macos  pubspec.yaml  windows
```

(iOS 也不存在 —— 显然 iOS 不允许读 SSID)

---

## 6. Dart 里也跑 JS 引擎（`flutter_js`）

```yaml
# pubspec.yaml:65-69
flutter_js:
  git:
    url: https://github.com/chen08209/flutter_js
    ref: master
```

`/pub.dev/packages/flutter_js` 上游已经小众；这里作者 fork 自维护。配合 `lib/core/service.dart` 的"配置里可写 JS 函数做分流"功能 —— 是少数还在 Flutter 里塞 JS runtime 的代理客户端。

---

## 7. 其他在 lib 之外的"小亮点"

### 7.1 `setup.dart` 自己写 publisher

```dart
// setup.dart:1-12
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

const _allTargets = <String, String>{
  'android': 'apk',
  'linux': 'deb',
  'macos': 'dmg',
  'windows': 'exe,zip',
};
```

外加 `release_telegram.py` —— 上传到 Telegram 频道 / 自动 release。

### 7.2 `release_telegram.py`

```bash
$ cat release_telegram.py | head -5
```

（独立 Python 脚本：搭配 `distribute_options.yaml` 用于自动发布）

### 7.3 `services/` 下还有个 `helper/` 是 Windows 特化的双形态二进制

```bash
$ ls services/helper/
build.rs  Cargo.lock  Cargo.toml  src
$ ls services/helper/src
main.rs  service
```

`src/service/...` 二级目录提示它有第二种 entry point（Service-mode 安装），这是 `windows-service` crate 推荐的布局。

---

## 8. 总览：在 lib/ 之外的"自编码 / 自链接"列表

| 类别                              | 文件 / 路径                                                                                       | 说明                                          |
| --------------------------------- | ------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| Go 内核主包                       | `core/*.go`（含 `action.go` `hub.go` `lib.go` `server.go` `main.go` `main_cgo.go`） | 处理跨 ABI dispatch                           |
| Go 内核子模块                     | `core/Clash.Meta/`（`.gitmodules` 引用）                                                      | mihomo 上游 fork                              |
| C 桥头                            | `core/bride.{c,h}`                                                                              | 函数指针表，Android-only                      |
| CGO 桥                            | `core/bride.go`, `core/tun/tun.go`                                                            | Go ↔ C ↔ Java                               |
| Linux 平台层                      | `core/platform/{procfs,limit}.go`                                                               | `/proc/net/*` 直接解析 + RLIMIT_NOFILE 探测 |
| 自研 FFI 插件                     | `plugins/{proxy,rust_api,tray_manager,wifi_ssid,window_ext,setup}`                              | 6 个插件均仓库内                              |
| Rust helper                       | `services/helper/`                                                                              | Windows Service + warp HTTP/SHA-256 token     |
| 自研 Rust FFI（Dart ↔ Rust）     | `plugins/rust_api/{rust/,lib/}` + `cargokit/`                                                 | flutter_rust_bridge 生成                      |
| 自研 Dart CLI                     | `plugins/setup/buildkit/build_tool/` + `setup.dart`                                           | 一处入口触发 Go/Rust 编译 + 打包              |
| 自研 CMake 钩子                   | `plugins/setup/buildkit/cmake/buildkit.cmake`                                                   | 嵌入 Linux/Windows Flutter 构建               |
| 自研 Gradle 钩子                  | `plugins/setup/buildkit/gradle/plugin.gradle`                                                   | 嵌入 Android Flutter 构建                     |
| 自研 Podspec 钩子                 | `plugins/setup/buildkit/macos/build_pod.sh`                                                     | 嵌入 macOS Flutter 构建                       |
| Flutter 内 JS 引擎（fork 自上游） | `pubspec.yaml: flutter_js` (`chen08209/flutter_js`)                                           | 在 Dart 上下文跑 JS 脚本做分流                |
| Release 工具                      | `release_telegram.py`                                                                           | Python 上传 Telegram                          |
| 配置 / 分发引擎                   | `distribute_options.yaml`, `build.yaml`, `analysis_options.yaml`, `arb/*.arb`             | 多语言 + 自定义构建配置                       |

---

## 9. 一句话总结

FlClash ≠ Flutter 项目。它在 `lib/` 之外**自编码或自集成**的至少有：

- **一份 Go 主程序** + **mihomo 上游 Go fork 作为子模块**；
- **C 桥接层**（函数指针表式 bride）与 **CGO 调用**；
- **一份 Rust Windows Service** 后台（提权 + SHA256 token）；
- **一份 Rust ↔ Dart 跨语言绑定**（cargokit + flutter_rust_bridge 自维护 fork）；
- **一组自定义 CMake / Gradle / Podspec 钩子**（`plugins/setup/buildkit/`）让 Flutter 构建期内联 Go + Cargo 编译；
- **6 个仓库内 FFI 插件**（含一个被作者 fork 的 tray_manager）；
- 一个 Dart 内 **JavaScript 引擎**（fork 自上游 `chen08209/flutter_js`）；
- 以及一个简单的 release_telegram.py Python 脚本用于自动发布。

这堆"lib/ 之外的东西"才是这个项目真正复杂的地方 —— 它不是"Flutter 包了个 Web 客户端"，而是 Flutter 仅作为 UI + FFI dispatcher，跨 Go/C/Rust 三种系统级语言拼起来的多端代理栈。
