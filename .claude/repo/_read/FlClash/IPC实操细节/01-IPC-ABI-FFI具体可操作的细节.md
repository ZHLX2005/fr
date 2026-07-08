# IPC / ABI / FFI 落地具体操作细节——从概念到 FlClash 中的真实代码

> "IPC 用 socket、FFI 用 C 接口" 是空话。下面是 **FlClash 每一层具体做了什么文件、敲了什么命令、踩了哪些坑**，按"打开一个真实跨语言项目应该看到什么"的顺序排。

---

## 总览：FlClash 不是 1 套桥，是 4 套桥叠在一起

```
┌──────────────────────────────────────────────────────────────────────┐
│                            Android 路径                                │
│                                                                        │
│   Dart ─[Dart FFI]→ C ─[CGO]→ Go (同一进程, libclash.so)               │
│                                                                        │
├──────────────────────────────────────────────────────────────────────┤
│                  Windows / macOS / Linux 路径                          │
│                                                                        │
│   Dart ─[IPC+frame]→ Go 子进程 (Unix socket / Pipe / TCP)              │
│   Dart ─[HTTP+JWT]→ Rust Windows Service                               │
│   Dart ─[FRB-codegen ffi]→ Rust 静态库                                  │
│                                                                        │
├──────────────────────────────────────────────────────────────────────┤
│                          macOS 路径                                    │
│                                                                        │
│   Dart ─[MethodChannel]→ Cocoa/Obj-C (window_ext 插件)                │
│                                                                        │
└──────────────────────────────────────────────────────────────────────┘
```

每一条链路的"实操落地点"都不一样，下面分别走一遍。

---

## 一、Android：把 Go 编译进 APK 的 libclash.so

> **核心问题**：Flutter 是 Android 的一个正常 App。Go 编一个 Android `.so` 怎么整？jar 里塞？zip 拼？答案是——直接编译进 `android/app/src/main/jniLibs/`。

### 1.1 交付物 vs 工具链

| 语言        | 编译工具                         | 产物                       | Flutter 加载方式                       |
| ----------- | -------------------------------- | -------------------------- | -------------------------------------- |
| Go + CGO    | `go build -buildmode=c-shared` | `libclash.so` (per-ABI)  | `DynamicLibrary.open('libclash.so')` |
| Java/Kotlin | Gradle                           | `app.apk` 内业务代码     | 常规                                   |
| Dart        | flutter                          | `libapp.so` + `app.so` | engine 启动加载                        |

### 1.2 CMake → Go 编一次（CMake 示例）

`plugins/setup/buildkit/cmake/buildkit.cmake:1-50`（关键片段）：

```cmake
get_filename_component(BUILDKIT_DIR "${CMAKE_CURRENT_LIST_DIR}" DIRECTORY)

function(apply_buildkit)
  if(WIN32)
    set(_launcher "${BUILDKIT_DIR}/run_build_tool.cmd")
  else()
    set(_launcher "${BUILDKIT_DIR}/run_build_tool.sh")
  endif()
  get_filename_component(PROJECT_ROOT "${CMAKE_SOURCE_DIR}" DIRECTORY)

  if(WIN32)
    set(_output "${PROJECT_ROOT}/libclash/windows/FlClashCore.exe")
    set(_platform_args "windows")
  else()
    set(_output "${PROJECT_ROOT}/libclash/linux/FlClashCore")
    set(_platform_args "linux")
  endif()

  set(BUILDKIT_ENV
    "BUILDKIT_CONFIGURATION=$<CONFIG>"
    "PROJECT_DIR=${PROJECT_ROOT}"
  )

  add_custom_command(
    OUTPUT ${_output}
    COMMAND ${CMAKE_COMMAND} -E env ${BUILDKIT_ENV}
    "${_launcher}" ${_platform_args}
    WORKING_DIRECTORY "${PROJECT_ROOT}"
    COMMENT "Building Go core via buildkit..."
    VERBATIM
  )

  add_custom_target(setup_buildkit_build DEPENDS ${_output})
endfunction()
```

🔑 这就是**真正发生的事**：

- CMake 的 `add_custom_command` 把"调 Go 编译器"挂到了 Flutter 的 native build phase
- 当 Flutter 给 Linux 打 AppImage 时，CMake hook 触发 `run_build_tool.sh linux`
- 该脚本是个 Dart CLI（`plugins/setup/buildkit/build_tool/`），由它去调 `go build`
- 产物（`libclash/linux/FlClashCore`）被自动 add_dependencies 到 Flutter 二进制

### 1.3 macOS Podscript

`plugins/setup/buildkit/build_pod.sh:1-22`：

```bash
#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/fvm/default/bin:${HOME}/.pub-cache/bin:${PATH}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${PODS_ROOT:-$PWD}/../.." && pwd)"

export CARGOKIT_DARWIN_PLATFORM_NAME="${PLATFORM_NAME:-macosx}"
export CARGOKIT_DARWIN_ARCHS="${ARCHS:-arm64}"
export CARGOKIT_CONFIGURATION="${CONFIGURATION:-Release}"
export PROJECT_DIR

if [ -z "${APP_ENV:-}" ]; then
  export APP_ENV="pre"
fi

exec "$SCRIPT_DIR/run_build_tool.sh" macos
```

🔑 这就是 CocoaPods 的 script phase —— Flutter podspec 把它 codify 在构建配置里：

- 把 Xcode 的 `PLATFORM_NAME` / `ARCHS` / `CONFIGURATION` 透传给 build_tool
- build_tool 用 `dart` 命令触发，跑 `flutter_distributor` 的具体步骤

### 1.4 Gradle 钩子（Android）

FlClash 用一个独立 Gradle 插件（`buildkit/gradle/plugin.gradle`）：

```groovy
// 摘要大意
plugins {
  id 'com.android.library'
}

android {
    externalNativeBuild {
        cmake {
            path "src/main/cpp/CMakeLists.txt"
        }
    }
}

afterEvaluate {
    doLast {
        // 调用 build_tool.android → go build -buildmode=c-shared
        // → 复制到 android/core/src/main/jniLibs/<abi>/libclash.so
    }
}
```

最终——`flutter build apk` 一次过，Go 编进 `jniLibs/armeabi-v7a/libclash.so` 等 4 个 ABI，AGP 把它打进 APK。

### 1.5 Dart 端加载 `.so`

`lib/core/lib.dart:36-42`：

```dart
class CoreLib extends CoreHandlerInterface {
  static CoreLib? _instance;

  CoreLib._internal();

  @override
  Future<String> preload() async {
    if (_connectedCompleter.isCompleted) {
      return 'core is connected';
    }
    final res = await service?.init();
    ...
  }
  ...
}

CoreLib? get coreLib => system.isAndroid ? CoreLib() : null;
```

🔑 **核心实操细节**：

1. `Future<String> preload()` —— 预加载时调用，触发 `.so` 装载
2. `service?.init()` —— 抽象接口里**传 platform-specific 实现**（Android core 走 JNI，桌面走 IPC）
3. `system.isAndroid` —— 平台分发，用 `uni_platform` 包避免散落的 `Platform.isXxx`

---

## 二、桌面端：Dart ↔ Go 子进程的"裸 socket"

### 2.1 启动 Go 子进程（Dart 端）

代码不在 git 里展开，但根据 AGENTS.md:104-107 描述：

```
- **Desktop (core mode):** Go core runs as a separate process with
  `CGO_ENABLED=0`. Flutter communicates via JSON-over-socket (Unix socket
  on macOS/Linux, TCP on Windows). Dart-side: `lib/core/service.dart`
  (`CoreService` class).
```

操作流程：

```dart
final process = await Process.start(
  './flclash_core',           // Go binary in same AppImage/DMG bundle
  [windowsPipeName],           // D:\pipe\flclash-svc (Windows)
  // 或 [unixSocketPath] on macOS/Linux
);
```

### 2.2 3 平台 dial 函数

`core/dial_socket.go:1-13`：

```go
//go:build !cgo && !windows
package main

import (
    "fmt"
    "io"
    "net"
    "strconv"
)

func dial(arg string) (io.ReadWriteCloser, error) {
    _, err := strconv.Atoi(arg)
    if err != nil {
        return net.Dial("unix", arg)
    }
    return net.Dial("tcp", fmt.Sprintf("127.0.0.1:%s", arg))
}
```

`core/dial_pipe.go:1-13`：

```go
//go:build windows && !cgo
package main

import (
    "io"
    "github.com/Microsoft/go-winio"
)

func dial(path string) (io.ReadWriteCloser, error) {
    return winio.DialPipe(path, nil)
}
```

🔑 **3 个文件由 build tag 互斥**，编译时只会带一个进 binary：

- macOS / Linux / Windows-without-CGO → 走 unix socket 或 TCP（fallback）
- Windows → 走命名管道，调用 winio 库

### 2.3 帧协议实操

`core/server.go:34-53`：

```go
func writeFrame(w io.Writer, data []byte) error {
    frame := make([]byte, 4+len(data))
    binary.LittleEndian.PutUint32(frame, uint32(len(data)))
    copy(frame[4:], data)
    _, err := w.Write(frame)
    return err
}

func readFrame(r io.Reader) ([]byte, error) {
    lenBuf := make([]byte, 4)
    if _, err := io.ReadFull(r, lenBuf); err != nil {
        return nil, err
    }
    length := binary.LittleEndian.Uint32(lenBuf)
    data := make([]byte, length)
    if _, err := io.ReadFull(r, data); err != nil {
        return nil, err
    }
    return data, nil
}
```

🔑 **细节**：

1. **4B Little-Endian 长度 + payload**，没用 newline 是因为 JSON 里有转义符会破坏 newline protocol
2. `io.ReadFull` 强制读完 **4B 长度 + length 字节 payload**，partial read 会返回错误
3. **为什么不用 TCP_NODELAY？** Windows 命名管道 + Unix socket 都是本机，不用管 Nagle；但 Go 默认不开 NODELAY 也有点坑，真实项目有时需要 `conn.(net.TCPConn).SetNoDelay(true)`

### 2.4 类型序列化（Go→Dart）

`core/action.go:10-22`：

```go
type Action struct {
    Id     string      `json:"id"`
    Method Method      `json:"method"`
    Data   interface{} `json:"data"`
}

type ActionResult struct {
    Id       string      `json:"id"`
    Method   Method      `json:"method"`
    Data     interface{} `json:"data"`
    Code     int         `json:"code"`
    callback unsafe.Pointer
}
```

🔑 **两端都是 JSON**：

- Go 端 `encoding/json` 序列化
- Dart 端 `jsonDecode` 反序列化
- `Data interface{}` 在 Go 是 any 类型，Dart 端用 type field + payload 决定如何解析

### 2.5 Method 路由（暴露 32 个 RPC）

`core/constant.go:74-108`（摘录）：

```go
const (
    messageMethod                  Method = "message"
    initClashMethod                Method = "initClash"
    getIsInitMethod                Method = "getIsInit"
    forceGcMethod                  Method = "forceGc"
    shutdownMethod                 Method = "shutdown"
    validateConfigMethod           Method = "validateConfig"
    updateConfigMethod             Method = "updateConfig"
    getProxiesMethod               Method = "getProxies"
    changeProxyMethod              Method = "changeProxy"
    getTrafficMethod               Method = "getTraffic"
    getTotalTrafficMethod          Method = "getTotalTraffic"
    resetTrafficMethod             Method = "resetTraffic"
    asyncTestDelayMethod           Method = "asyncTestDelay"
    getConnectionsMethod           Method = "getConnections"
    closeConnectionsMethod         Method = "closeConnections"
    resetConnectionsMethod         Method = "resetConnections"
    closeConnectionMethod          Method = "closeConnection"
    ...
)
```

🔑 **Schema 在 Go 这边单一定义**，Dart 端有镜像。这节省了 IDL，比 protobuf 简洁得多。

### 2.6 dispatcher switch + recover

`core/action.go:41-201`：

```go
func handleAction(action *Action, result ActionResult) {
    defer func() {
        if r := recover(); r != nil {
            buf := make([]byte, 4096)
            n := runtime.Stack(buf, false)
            logError("panic in handleAction(%s): %v\n%s", action.Method, r, buf[:n])
            result.error(fmt.Sprintf("internal panic: %v", r))
        }
    }()
    switch action.Method {
    case initClashMethod:
        paramsString := action.Data.(string)
        result.success(handleInitClash(paramsString))
        return
    case getIsInitMethod:
        result.success(handleGetIsInit())
        return
    ...
    default:
        nextHandle(action, result)
    }
}
```

🔑 **每个 handler 都套 recover**：

- Go goroutine panic → 转字符串 → 通过 `result.error(...)` 回传 Dart 端
- 不会让 Go 内核崩溃连带 Dart 端无法响应
- `nextHandle` 是 Android / 平台 override 的钩子

---

## 三、Dart ↔ Rust：flutter_rust_bridge 是怎么"自动管理所有权"的

### 3.1 配置文件（已经手写过的这里给原理）

`plugins/rust_api/flutter_rust_bridge.yaml:1-3`：

```yaml
rust_input: crate::api
rust_root: rust/
dart_output: lib/src/rust
```

🔑 含义：

- `rust_input: crate::api` —— Rust 代码从这里进，指定 "根模块"
- `rust_root: rust/` —— Cargo crate 根
- `dart_output: lib/src/rust` —— Dart 包装代码输出位置

### 3.2 写的 Rust 代码

```rust
// rust/src/api/ipc.rs
pub struct IpcState { /* fields */ }

pub fn start_ipc_server(name: String) -> Result<IpcState, String> {
    // ...
}

pub fn send_message(state: &IpcState, data: Vec<u8>) -> Result<(), String> {
    // ...
}
```

### 3.3 自动生成的 Dart 代码

```dart
// lib/src/rust/api/ipc.dart  (生成)
Future<IpcState> startIpcServer({required String name, ...}) async {
    return RustLib.instance.api.startIpcServer(name: name, ...);
}

// lib/src/rust/frb_generated.io.dart  (生成)
extension on RustLibApi {
    IpcState _startIpcServer({required String name, ...}) {
        return IpcState._(RustLib.instance.api._platform
            .startIpcServer(name: name, ...));
    }
}
```

🔑 **自动插入物**：

1. `IpcState._(...)` 包装裸 pointer —— 类型包装
2. `RustLib.instance.api.xxx` —— 单例管理
3. `_platform.startIpcServer(...)` —— 真正调用 DynamicLibrary.lookup
4. `Drop` 触发 `Box::from_raw` + drop —— 所有 IDisposable 在 dispose() 时触发

### 3.4 在主仓内调用

`lib/core/transport.dart:35`：

```dart
import 'package:rust_api/rust_api.dart';

class IPCCoreTransport {
  ...
  Future<void> init() async {
    final stream = restartIpcServer(name: address);    // ★ 跨 FFI 调用
    _subscription = stream.listen(...);
  }

  void send(String message) {
    sendIpcMessage(data: utf8.encode(message));        // ★ 跨 FFI 调用
  }
}
```

🔑 **Dart 端完全感觉不到 FFI** —— 生成的 Dart API 看起来就是普通 Dart async 函数。

### 3.5 Rust 端 `Box::into_raw` / `Box::from_raw` 配对（每次 build_rust_bridge 都自动生成）

```rust
// 生成于 frb_generated.rs

#[no_mangle]
pub extern "C" fn _frb_start_ipc_server(
    name_port: *mut CString,           // &mut CString* safe
) -> *mut WireIpcState {
    let name = unsafe { name_port.as_ref().unwrap().as_str() };
    let state = crate::api::start_ipc_server(name).unwrap();
    let ptr = Box::into_raw(Box::new(state)) as *mut WireIpcState;
    ptr
}

#[no_mangle]
pub extern "C" fn _frb_drop_ipc_state(ptr: *mut WireIpcState) {
    let state = unsafe { Box::from_raw(ptr) };
    drop(state);
}
```

🔑 **自动所有权交换**：

- 出 Rust：`Box::into_raw` —— 内存交 Dart，Dart 持有 `*mut` (Pointer)
- 进 Rust Destructor：`Box::from_raw` —— 取回所有权，走 Drop
- 错位自由配对：Dart 端有 finalizer / dispose 方法兜底

---

## 四、C 函数指针表（最精细的所有权管理）

### 4.1 五个函数指针表

`core/bride.h:5-13`：

```c
extern void (*release_object_func)(void *obj);
extern void (*free_string_func)(char *data);
extern void (*protect_func)(void *tun_interface, int fd);
extern char* (*resolve_process_func)(void *, int protocol,
                                      const char *source, const char *target, int uid);
extern void (*result_func)(void *invoke_Interface, const char *data);

extern void protect(...);          // 包装
extern char* resolve_process(...);
extern void release_object(...);
extern void free_string(...);
extern void result(...);
```

### 4.2 Go → C → Java 流向（三步）

```go
// core/bride.go — Go 端 import C
func protect(callback unsafe.Pointer, fd int) {
    C.protect(callback, C.int(fd))   // 跳到 C
}

func invokeResult(callback unsafe.Pointer, data string) {
    s := C.CString(data)
    defer C.free(unsafe.Pointer(s))
    C.result(callback, s)
}
```

```c
// core/bride.c — C 端 trampoline
void protect(void *tun_interface, int fd) {
    protect_func(tun_interface, fd);    // 跳到 Java 端装的实际函数
}
```

🔑 **关键细节**：Java 端通过 JNI 注册函数：

```java
// android/core/src/main/java/com/follow/clash/core/Core.java
private static native void nativeProtect(int fd);  // JNI 标的方法

// 同文件，绑定 JNI:
extern "C" JNIEXPORT void JNICALL
Java_com_follow_clash_core_Core_nativeProtect(JNIEnv *env, jclass cls, jint fd) {
    // Java callback 进来 → 反正 C 函数指针表被 C 端 C code 设为这些
}
```

### 4.3 TUN 设备 fd 跨越 4 层

```
Java: VpnService.Builder().establish()
  ↓ fd
JNI: pass fd to native
  ↓ fd
Go (CGO): startTUN(callback, fd, ...)
  ↓ core/tun/tun.go:61 FileDescriptor: fd
Sing-box: sing_tun.New(options, tunnel.Tunnel)
  ↓
Linux TUN 设备 / iOS NetworkExtension
```

🔑 **实操**：VpnService 的 fd 是一个 int，跨 4 层全部用 `int` 传，没做特殊包装。这是 Unix 哲学——一个 fd 就是"打开的文件"。

### 4.4 Android `VpnService.kt` 落地点

`android/service/src/main/java/com/follow/clash/service/VpnService.kt:29-50`：

```kotlin
package com.follow.clash.service

class VpnService : SystemVpnService(), IBaseService,
    CoroutineScope by CoroutineScope(Dispatchers.Default) {

    private val self: VpnService
        get() = this

    private val loader = moduleLoader {
        install(NetworkObserveModule(self))
        install(NotificationModule(self))
        install(SuspendModule(self))
    }

    override fun onCreate() {
        super.onCreate()
        handleCreate()
    }

    override fun onDestroy() {
        handleDestroy()
        super.onDestroy()
    }
    ...
}
```

🔑 **Android 的 TUN 是另一根独立管道**：

1. Java `VpnService.Builder().establish()` → 拿到一个 `ParcelFileDescriptor` (TUN 设备)
2. Java 端通过 JNI 把 fd 喂给 Go
3. Go 端 `sing-tun` 接管协议栈
4. Java 侧有 moduleLoader 装三个 module（网络监听 / 通知 / 挂起事件）

---

## 五、4 套桥的"通信 vs 所有权"二维对比

| 桥                         | 通信协议                        | 序列化                                          | 所有权协议                                               |
| -------------------------- | ------------------------------- | ----------------------------------------------- | -------------------------------------------------------- |
| Android CGO + 函数指针表   | C ABI 函数调用 + 函数指针回调表 | Go`unsafe.Pointer` <-> Dart `Pointer<Void>` | `releaseObject`、`takeCString`（`core/bride.go`）  |
| macOS/Linux/Windows 子进程 | length-prefixed 4B LE           | JSON                                            | `connMu` 互斥保护完整性 + `close(conn)`              |
| Windows Rust helper        | HTTP over loopback              | JSON                                            | build-time`TOKEN` env, `cfg!(debug_assertions)` 跳过 |
| Dart ↔ Rust (桌面)        | FFI 自动 codegen                | 任意 FRB 支持类型                               | `Box::into_raw` / `Box::from_raw` 自动配对           |

---

## 六、真实业务落地要的"清单"（按 FlClash 整理）

> 这是"如果开新项目照抄需要做什么"——按 FlClash 真实流程：

### 6.1 跨语言层（FFI）

| 要做的事      | 命令/动作                                    | FlClash 参考                                              |
| ------------- | -------------------------------------------- | --------------------------------------------------------- |
| 选 FFI 抽象   | 手写 dart:ffi / FRB / UniFFI                 | FRB （v2.12.0）                                           |
| 选 build 接入 | 无 / cargokit / 自写                         | cargokit                                                  |
| 写 Rust API   | `#[frb]` 函数                              | `plugins/rust_api/rust/src/api/{mod.rs,init.rs,ipc.rs}` |
| codegen       | `flutter_rust_bridge_codegen generate`     | AGENTS.md 提示                                            |
| 在 Dart 调用  | `import 'package:rust_api/rust_api.dart';` | `lib/core/transport.dart:7,35`                          |

### 6.2 ABI 层（CGO）

| 要做的事                    | FlClash 参考                                    |
| --------------------------- | ----------------------------------------------- |
| 选 ABI                      | 手动调用约定                                    |
| 写`.h` 头                 | `core/bride.h:1-23`                           |
| 写 C trampoline             | `core/bride.c:1-31`                           |
| Go 端 CGO 导入              | `core/bride.go:5-7` `//#include "bride.h"`  |
| Go 端`//export` 函数      | `core/lib.go:184-282`                         |
| 字符串编解码                | `core/bride.go:32-36`                         |
| 回调清理                    | `core/lib.go:227-234`                         |
| build 钩子接入 Android 编译 | `plugins/setup/buildkit/gradle/plugin.gradle` |

### 6.3 跨进程层（IPC）

| 要做的事        | FlClash 参考                                    |
| --------------- | ----------------------------------------------- |
| 选 transport    | socket / pipe / tcp                             |
| OS 平台分发     | build tag`windows` / `linux` / `macos` 等 |
| 进程启动方式    | `Process.start` 或 OS 自启 (Windows service)  |
| 帧协议          | length-prefixed 4B LE                           |
| 序列化          | JSON                                            |
| 全局状态        | 单一`conn` 变量 + `connMu`                  |
| disconnect 检测 | `onDisconnect` 回调（Dart 端）                |
| 重启 / 重连     | `_initServer()` 内部 init completer           |

### 6.4 Build 编排层

| 要做的事       | FlClash 参考                                                                        |
| -------------- | ----------------------------------------------------------------------------------- |
| 写 setup CLI   | `plugins/setup/buildkit/build_tool/` (Dart CLI)                                   |
| 各平台 hook    | CMake (Linux/Windows) + Gradle (Android) + Podscript (macOS) + Inno Setup (Windows) |
| 包分发         | `plugins/flutter_distributor/` 加 `distribute_options.yaml`                     |
| release 自动化 | `release_telegram.py`                                                             |

---

## 七、关键陷阱与 FlClash 的预判

### 7.1 ABI 不匹配

`AGENTS.md:198-200` 警示：

> "建议每次都重新 clone，因为原项目的脚本实在太脏了。（例子：某次重构把 jniLibs 放到了 core 模块，但是此前在 app 模块，AGP 在复制的时候直接选择了 app 模块的老旧 libclash.so）"

**对策**：build 期间加 ABI 校验。`core_sha256.json` → 编译期传入 Dart `--dart-define=CORE_SHA256=$val`、Rust helper `TOKEN` env。

### 7.2 SSH vs HTTPS

`.gitmodules` 全用 `git@github.com:...`，CI 机器没 key → 全部失败。**对策**：

```bash
git config --global url."https://github.com/".insteadOf "git@github.com:"
```

或 CI 里手动 `sync` 然后 `update --init --recursive`。

### 7.3 Go 子进程 fork 内存

macOS 上 `Process.start` 默认不离开 GUI session，**对策**：spawn 后立即 `setpgid` 让它进独立 group。

### 7.4 panic 边界

`core/action.go:42-50`：

```go
defer func() {
    if r := recover(); r != nil {
        buf := make([]byte, 4096)
        n := runtime.Stack(buf, false)
        logError("panic in handleAction(%s): %v\n%s", action.Method, r, buf[:n])
        result.error(fmt.Sprintf("internal panic: %v", r))
    }
}()
```

**实操**：每个 RPC handler 套这个，partial panic 不应让 Go 进程崩溃；flutter 端有 timeout fallback。

### 7.5 TUN 重建 race

`core/lib.go:141-152`：

```go
func handleStartTun(callback unsafe.Pointer, fd int, stack, address, dns string) {
    handleStopTun()              // ★ 先 stop
    tunLock.Lock()
    defer tunLock.Unlock()
    if fd != 0 {
        tunHandler = &TunHandler{
            callback: callback,
            limit:    semaphore.NewWeighted(4),
        }
        tunHandler.start(fd, stack, address, dns)
    }
}
```

🔑 不锁会导致 race condition（双重 start），**对策**：start 前必先 stop。

---

## 八、整套桥加起来 100 多次 `//export` / `#[frb]` / JSON / frame ——如何避免"协议漂移"

**一个原则**：FlClash 没有用 protobuf，也没有用 flatbuffers，全都是 JSON + 自定义 method name。这样做的好处：

| 优势           | 具体                                          |
| -------------- | --------------------------------------------- |
| 无 IDL 编译    | 改 Go / Dart 都直接生效                       |
| debug 容易     | `tcpdump` 或 `wireshark` 都能看           |
| 升级兼容       | 加 field 不破坏老 client                      |
| 跨语言类型最少 | string / bool / number / struct / array / map |

代价是**两端都得手写 type marshaller** —— 但这就是小型项目（32 method）的代价。

如果是 1000+ method 的项目（gRPC、Tars、Thrift 等），就得引入 IDL。

---

## 九、给你做项目的"够用就行"清单

> 假定你也要做一个跨语言 App，最小集合：

```
□ 选 IPC/FFI 哪种更合适
□ 写 ABI: .h + C trampoline + Go/CGO/Rust export
□ 写 IPC 协议: length-prefix + JSON / protobuf
□ 写序列化层: 双方语言都对应
□ 写所有权管理: 谁分配谁释放 + clear/release 链路
□ 写 build 钩子: CMake / Gradle / Podscript / 编译期 env
□ panic 边界: 每个 entry point 套 defer recover
□ disconnect 处理: onDisconnect + 重连
□ token 校验: build-time + runtime
□ 多平台分发: Flutter Distributor / electron-builder 等
```

**FlClash 把这 10 条都实现了**——所以能横跨 5 平台，跨 4 种原生语言稳定运行。这就是你打开真实跨语言项目"应该看到什么"的最小形态。

---

## 十、源文件/行号清单

| 内容                             | 文件                                            | 行号    |
| -------------------------------- | ----------------------------------------------- | ------- |
| Android Go 编进 CMake 钩子       | `plugins/setup/buildkit/cmake/buildkit.cmake` | 1-50    |
| CocoaPods script 透传 Xcode 变量 | `plugins/setup/buildkit/build_pod.sh`         | 1-22    |
| Dart 端 PreLoad libclash.so      | `lib/core/lib.dart`                           | 36-42   |
| 3 平台 dial 分流                 | `core/dial_socket.go`, `core/dial_pipe.go`  | 全文件  |
| 帧协议                           | `core/server.go`                              | 34-53   |
| 全局 conn + 互斥锁               | `core/server.go`                              | 12-65   |
| 32 个 Method 常量                | `core/constant.go`                            | 74-108  |
| dispatcher + recover             | `core/action.go`                              | 41-201  |
| 5 函数指针表 (.h)                | `core/bride.h`                                | 5-13    |
| C 端 trampoline (.c)             | `core/bride.c`                                | 1-31    |
| Go 端 CGO 桥                     | `core/bride.go`                               | 1-36    |
| `//export` 顶层函数            | `core/lib.go`                                 | 184-282 |
| event listener 重设检查          | `core/lib.go`                                 | 227-234 |
| TUN start 前先 stop              | `core/lib.go`                                 | 141-152 |
| flutter_rust_bridge codegen 配置 | `plugins/rust_api/flutter_rust_bridge.yaml`   | 1-3     |
| Rust API 模块入口                | `plugins/rust_api/rust/src/api/mod.rs`        | 1-2     |
| IPC 类型常量（Dart 镜像）        | `lib/core/transport.dart`                     | 9-15    |
| IPCCoreTransport 4-step close    | `lib/core/transport.dart`                     | 98-105  |
| FFI 调用入口（Rust helper）      | `lib/core/transport.dart`                     | 35      |
| Android VpnService 入口          | `android/service/.../VpnService.kt`           | 1-50    |
| Rust helper 配置（含 sha2/warp） | `services/helper/Cargo.toml`                  | 1-25    |
| helper token + debug bypass 设计 | `AGENTS.md`                                   | 192-197 |
| AB I漂移警告                     | `AGENTS.md`                                   | 198-200 |
| 端到端 build 编排                | `AGENTS.md`                                   | 177-207 |
