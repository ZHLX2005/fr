# IPC / ABI / FFI 前置知识基础 ——读 FlClash 跨语言栈应该先知道什么

> 你想看懂 IPC/ABI/FFI 在真实项目里怎么落地，先得知道这些前置概念。这份文档**不引用 FlClash 一行代码**，只解释术语 + 配套的全套工具链，**但每节最后都标了"在 FlClash 哪里可以看到"**作为钩子，让你能立即去 3 篇前序文档里验证。

---

## 一、最重要的前置：内存、调用约定、ABI 这三个概念是同一件事的不同切面

| 切面 | 问题 | 答案示例（FlClash 里的 4 种情况） |
|---|---|---|
| **内存** | 一段 100 字节从哪开始，到哪结束，归谁所有？ | Dart GC 管 / C malloc / Go heap / Rust Box |
| **调用约定 (Calling Convention)** | 函数调用时参数怎么放（栈？寄存器？哪几个？），谁来清栈，返回值在哪？ | Go CGO 默认用 C 的 cdecl / iOS arm64 用 AAPCS / Windows x64 Microsoft x64 |
| **ABI** | 把"内存布局"+"调用约定"+"类型映射"+"符号命名"打包成一个二进制兼容规范 | Go CGO 嵌入 `extern "C"` / Rust `extern "C" fn` / dart:ffi 显式查表 |

🔑 **核心结论**：当别人说"FlClash 里 Go 和 Dart 是 ABI 兼容的"时，意思就是：

1. 双方对"一个参数 long 怎么压在哪个寄存器"达成共识
2. 双方对"struct XY 在内存里展开成什么形状"达成共识
3. 双方对"malloc 的内存 free 不需要告诉对方具体类型"达成共识

—— 这三条满足就够跨语言跑，缺一不可。

**在 FlClash 哪里可以看到**：
- `core/bride.h` 5 个函数指针表 → ABI 声明
- `core/lib.go:184-282` `//export` 函数 → Go 把 C ABI 函数导出
- `plugins/rust_api/lib/src/rust/frb_generated.io.dart` → Dart 查表 + ABI 包装

---

## 二、底层概念层（按"想理解 FFI 需要什么"的顺序）

### 2.1 进程、线程、goroutine、Future

| 概念 | 一句话 | 跨语言陷阱 |
|---|---|---|
| **进程 (process)** | 操作系统分配资源（fd、内存）的最小单位 | 进程间**不能直接**用指针，必须用 IPC |
| **线程 (thread)** | OS 调度单位，共享进程内存 | 不同语言 runtime 的线程要互相同步（mutex/condvar） |
| **goroutine (Go)** | Go runtime 调度的协程，**< 4KB stack** | goroutine 内调 CGO 时 P 被 pin 死，整个 goroutine 都被阻塞 |
| **async/await (Dart/Rust)** | 用户态协程，事件循环驱 | FFI 调用是同步的，所以阻塞的 C 调用会让整个 async loop 卡住 |
| **Future/Promise** | async 的占位 | FFI 不返回 Future（同步），需要 wrap 到 `Future.value(result)` |

🔑 **FlClash 里的痕迹**：
- `core/lib.go:198`：`go handleAction(action, result)` —— 把 CGO 回调扔到 goroutine
- `core/action.go:198`：`result.success(value)` —— 异步回调写在另一线程安全返回
- `lib/core/transport.dart:23`：`Completer<void>` —— Dart 端桥接异步 IPC 的典型

### 2.2 函数指针 / closure / callback

**最重要的概念**：跨语言时**函数指针**是双向通道，但**引用语义完全不同**。

| 语言 | 函数表示 | 如何跨语言传 |
|---|---|---|
| C | `void (*fn)(int)` 裸指针 | 直接传指针，调用时按 ABI 跳 |
| Go | `func(int)` 闭包 | 包成 `unsafe.Pointer` 给 C，C 跳；C 调回时 Go runtime 知道要"恢复栈" |
| Rust | `fn(int)` fn pointer / `Fn` closure | `Box::into_raw`，FFI 必须 `extern "C"` + repr(C) 兼容 |
| Dart | `void Function(int)` typed function | 编译器把 Dart 闭包包成一个**Identity Function**，FFI 拿到的是它的 trampoline pointer |

🔑 **FlClash 里的痕迹**：
- `core/bride.h:9-13` —— C 端用 `void (*fn)(...)` 暴露函数指针给 Go 设
- `core/bride.c:1-13` —— 5 个 `(*xxx_func)(...)` 是「可由外部代码注入的回调」
- `core/lib.go:184`：`invokeAction(callback unsafe.Pointer, paramsChar *C.char)` —— callback 是从 Dart 来的

### 2.3 内存所有权 / 堆 vs 栈

| 内存类型 | 归谁 | 跨语言怎么传 |
|---|---|---|
| **栈 (stack)** | 调用者（生命周期 = 函数返回前） | 不要跨语言传 |
| **堆 (heap)** | malloc 的，归具体语言 runtime | 必须显式约定谁分配谁释放 |
| **静态 / 全局** | 程序生命周期内存在 | 不算跨语言问题，但要避免 GC 把它回收掉 |

🔑 **FlClash 里的痕迹**：
- `core/bride.go:33-35` `takeCString` —— 拿 C 字符串进 Go string，**复制内容**
- `core/lib.go:30` `var eventListener unsafe.Pointer` —— 全局保留 callback 防 GC

### 2.4 类型映射（C ↔ 各语言）

> 这是 FFI 时最常碰壁的地方。

| C 类型 | Dart (dart:ffi) | Go (cgo) | Rust (FFI) | 备注 |
|---|---|---|---|---|
| `void` | `Void` | (无返回值) | `()` | - |
| `int` | `Int32` | `C.int` (int32) | `i32` / `c_int` | 注意 long 在 Windows 是 32bit，Linux 是 64bit |
| `long` | `Int32 / Int64` | `C.long` (平台相关) | `i32 / i64 / c_long` | 混乱之源 |
| `long long` | `Int64` | `C.longlong` | `i64` | - |
| `size_t` | `UintPtr` | `C.size_t` | `usize` | - |
| `char *` | `Pointer<Utf8>` 或 `Pointer<Int8>` | `*C.char` | `*mut c_char` / `CString` | 必查编码：UTF-8 / ANSI？ |
| `void *` | `Pointer<Void>` | `unsafe.Pointer` | `*mut c_void` | 通用句柄，最强大 |
| `T *` | `Pointer<T>` | `*T` | `*mut T` | - |
| `struct {int; char[16]}` | 自定义 class | 嵌入结构体 | `#[repr(C)]` struct | 字段顺序必须是 C 一致 |
| `enum` | int 常量 | `type E int` | `#[repr(i32)] enum E` | C enum 默认 int |
| 函数指针 | `Pointer<NativeFunction<...>>` | `func(...)` 包 `unsafe.Pointer` | `extern "C" fn(...)` 包 raw |

🔑 **FlClash 里的痕迹**：
- `core/lib.go:202-204` —— `startTUN(callback unsafe.Pointer, fd C.int, stackChar, addressChar, dnsChar *C.char)`
- `core/lib.go:280-282` `updateDns(s *C.char)` —— 字符串走 C.char
- `core/bride.c:17-19` —— `resolve_process(... int protocol ...)` 用 int 跨语言

### 2.5 字符串编码

C 字符串默认是 **ASCII 透明 / Locale 决定**。FlClash 全程用 **UTF-8**：

| 方向 | 怎么保证 |
|---|---|
| Dart → C | `utf8.encode(s)` → `Pointer<Utf8>.toCString()` |
| C → Dart | `Pointer<Utf8>.toDartString()` 强制 UTF-8 解码 |
| Go (CGO) | `C.CString(s)` 默认按 UTF-8 编码 / `C.GoString(cstr)` |
| Rust (FFI) | `CStr::from_ptr` + `to_string_lossy()` |

🔑 **FlClash 里的痕迹**：
- `lib/core/transport.dart:91-92`：`sendIpcMessage(data: utf8.encode(message))`
- `core/bride.go:32-36` —— Go 端 C.GoString 默认 UTF-8
- 全部协议都是 `CString` → GoString → JSON → Dart jsonDecode

### 2.6 同步 vs 异步

| 模式 | 实现 | 优点 | 缺点 |
|---|---|---|---|
| **同步调用** | FFI 直接函数调用，`T result = f()` | 简单、栈式 | 阻塞，会 block event loop |
| **Future/Promise** | Dart side async，runtime 进 microtask queue | 不 block UI | 错误处理复杂 |
| **Callback** | 把函数作参数传，调用方持 | 不阻塞 caller | 谁持所有权？ |
| **Event Sink** | 一边发 EventStream，一边订阅 | 多 channel，长生命周期 | 需要 manual cleanup |

🔑 **FlClash 里的痕迹**：
- Sync：FFI lookup 直接拿到 NativeResult
- Async：`core/action.go:98-111` async-testDelay 用 callback
- Event：`core/lib.go:227-234` `setEventListener` —— 一次设，长用
- Stream：Dart `lib/core/transport.dart` —— `StreamController<Uint8List>` 收 socket 帧

---

## 三、IPC 层面的前置

### 3.1 IPC 是什么 → 跨进程通信的 5 种形态

| IPC 形态 | 场景 | 优点 | 缺点 |
|---|---|---|---|
| **socket (Unix domain)** | 同机任意语言 | 文件系统路径，稳定 | Linux/macOS only |
| **named pipe (FIFO)** | 同机/父子进程 | 简单 | Windows 跟 Unix 命名 / API 不一样 |
| **TCP loopback** | 跨平台 | 普适 | 慢一点点，开 /proc/.../dead |
| **shared memory + signal** | 高性能 | 最快 | 同步复杂，进程崩了 Memory 残废 |
| **HTTP** | 跨进程 / 跨容器 | 易调试，标准化 | 多了 HTTP 解析开销 |

🔑 **FlClash 里的痕迹**：
- `core/dial_socket.go:1-13` —— Unix socket & TCP loopback 兼用
- `core/dial_pipe.go:1-13` —— Windows named pipe
- `services/helper/Cargo.toml:13` —— warp = HTTP server，给 Windows helper 用

### 3.2 帧协议 vs 流协议

> 跨进程时，原始字节流不能直接当 message 用，必须自己分包。

| 设计 | 思路 | 问题 |
|---|---|---|
| **Newline-delimited** | 一行一个 JSON | 内含转义符会乱 |
| **Length-prefix** | 4 字节长度头 + payload | 简单，但 partial read 要管 |
| **Type-Length-Value** | 类型字节 + 长度 + payload | FlClash Transport 用 |
| **Self-describing (protobuf)** | 字节流自带 schema | 性能 / 包大小 |

🔑 **FlClash 里的痕迹**：
- 桌面 Go 子进程：`core/server.go:34-53` —— Length-prefixed 4B LE
- Rust helper：`lib/core/transport.dart:9-15` —— Type-Length-Value
- 共有的：都做了 `io.ReadFull` 防 partial read

### 3.3 序列化方案对比

| 方案 | 优势 | FlClash 选择 |
|---|---|---|
| JSON | 易调试，可读 | ✅ 主用 |
| protobuf | compact, schema 化 | ❌ 没用 |
| FlatBuffers | zero-copy | ❌ 没用 |
| MessagePack | binary + 自描述 | ❌ 没用 |
| 裸 byts + manual | 最快 | ❌ 没用 |

**为什么 FlClash 选 JSON？**
- 32 个 method 总数不多
- 团队维护 Go & Dart，不需要 IDL 编译器
- 调试可以直 tail 二进制 / tcpdump

---

## 四、ABI 层面的前置

### 4.1 C ABI 是 FFI 的"通用语"

> **关键洞察**：所有跨语言 FFI 几乎都收敛到 C ABI，因为它拥有：固定调用约定 / 简单类型 / 不需要名字 mangling。

为什么 C ABI 是 universal：

1. **没有 name mangling** —— `extern "C" fn my_rust_func()` 出来的符号就叫 `my_rust_func`，不会变成 `_ZN4core...`
2. **栈传参规则明确** —— 不同平台都有"how to call C functions"规范
3. **size_t / void * 大小有保障** —— void * 在 32b 是 4B、64b 是 8B
4. **没有异常穿透** —— C 没有 exceptions，越界 C 不会 throw

🔑 **FlClash 里的痕迹**：
- `core/lib.go:5-7`：`import "C"` + `//#include "bride.h"` —— Go 的 CGO 通过 C ABI 暴露
- `plugins/rust_api/`：FRB 强制要求 `#[repr(C)]` 或 `extern "C"`
- Dart `frb_generated.io.dart`：通过 `DynamicLibrary.lookup` 拿的 `Pointer<NativeFunction>` 按 C ABI 跳

### 4.2 平台 ABI 差异

| 平台 | 调用约定 | 整数大小 | 函数指针大小 |
|---|---|---|---|
| x86 Linux | cdecl | int 32b long 64b | 8 |
| x86 Windows | stdcall (win32) / fastcall | int 32b long 32b | 4 |
| ARM64 iOS | AAPCS | int 32b / long 32b | 8 |
| macOS aarch64 | AAPCS | int 64b (LP64) | 8 |
| Android (Linux) | AAPCS | int 32b long 64b | 8 |

🔑 **FlClash 怎么处理的？**
- 用 **C 标准类型**（`size_t`、`int32_t`、`uint32_t`、`char *`）而非 `int`、`long`
- 不依赖结构体 layout，全部 interface IO 用 string（JSON）
- 通过 build tag / `cfg!(...)` 配平台特殊路径（如 `cfg!(windows)`、`cfg(target_os="android")`）

### 4.3 字节序与对齐

> C struct 的内存布局跟 ABI 强绑定。

```
struct {
  char    a;       // offset 0, 1 byte
  // 3 bytes padding
  int32_t b;       // offset 4, 4 bytes
  char    c;       // offset 8, 1 byte
  // 3 bytes padding (struct alignment 4)
}
```

🔑 **FlClash 怎么避免中招？**
- 不让任何 ABI struct 跨语言边界
- 一律 JSON（JSON 不关心 padding）
- 必须传结构体的用 `#[repr(C)]` (Rust) / `struct { ... }` (Go cgo import C struct)

---

## 五、FFI 框架的概念

### 5.1 主流 FFI 框架对比

| 框架 | 方向 | FlClash 选用？ |
|---|---|---|
| **dart:ffi** (官方) | Dart ↔ C | 部分（Android CGO 路径） |
| **flutter_rust_bridge (FRB)** | Dart ↔ Rust | ✅ 用了 |
| **UniFFI** | 多语 ↔ Rust | ❌ 没用 |
| **gRPC** | 跨进程任意语 | ❌ 没用（嫌重） |
| **cargokit** | Cargo ↔ Flutter 各家 build | ✅ 用了 |
| **Flutter MethodChannel** | Dart ↔ Kotlin/Swift | Flutter 标准 |
| **CGO** | Go ↔ C | ✅ 用了（Android） |

### 5.2 FRB 的内部构成

```
                         ┌─────────────────────┐
                         │ Rust source          │
                         │ (#[frb] functions)   │
                         └──────────┬───────────┘
                                    │ cargo build
                                    ↓
                         ┌─────────────────────┐
                         │ lib<name>.so/.dylib │
                         └──────────┬───────────┘
                                    │ build_pod.sh / gradle / cmake
                                    ↓
                         ┌─────────────────────┐
                         │ Flutter Plugin      │
                         │ (loads dylib)        │
                         └──────────┬───────────┘
                                    │ Dart call site
                                    ↓
                         ┌─────────────────────┐
                         │ frb_generated.dart  │  ←── flutter_rust_bridge_codegen produce
                         └─────────────────────┘
```

🔑 **关键**：
- 同一个 Rust crate 编译成 **cdylib** (动态) 和 **staticlib**（静态）—— FlClash 用：

```toml
# plugins/rust_api/rust/Cargo.toml
[lib]
crate-type = ["cdylib", "staticlib"]
```

- `cdylib` → iOS/macOS App 静态链接
- `staticlib` → Android 直接编译进 APK

🔑 **FlClash 里的痕迹**：
- `plugins/rust_api/rust/Cargo.toml:5-7` `crate-type = ["cdylib", "staticlib"]`
- `plugins/rust_api/cargokit/cmake/` —— CMake 钩子
- `plugins/rust_api/cargokit/gradle/` —— Gradle 钩子
- `plugins/rust_api/cargokit/build_pod.sh` —— CocoaPods 钩子

### 5.3 FFI 的三大陷阱

| 陷阱 | 后果 | 对策 |
|---|---|---|
| **指针被 GC** | callback 还在但所指内存被回收 → SIGSEGV | Dart 端 `Pointer<Void>` 不能被 GC，否则传 null；Global `unsafe.Pointer` 保留 callback 身份 |
| **结构体对齐** | 不同语言 struct layout 不一致导致字段错位 | `#[repr(C)]` / `struct { ... }` 强制按 C 序 |
| **字符串编码** | 默认 ANSI 出中文乱码 | 一律 UTF-8：`CString → to_string_lossy → String` |

🔑 **FlClash 怎么绕开的？**
- 通过不让 ABI struct 跨界、全程 JSON —— 一刀切规避
- 全局 callback 引用通过 `unsafe.Pointer` 钉住，结束时 `releaseObject` 显式释放

---

## 六、GPIO: Flutter 工程脚手架相关

### 6.1 Flutter plugin 全家桶

| 类型 | 用途 | FlClash 例 |
|---|---|---|
| MethodChannel plugin | Dart ↔ Kotlin/Swift | (Flutter 默认) |
| FFI plugin | Dart ↔ C ABI | `service` 插件加载 libclash.so |
| FFI + Rust plugin | Dart ↔ Rust | `rust_api` |
| Pure Dart plugin | 跨平台 helper | `proxy` (设置系统代理) |
| View plugin | embed platform-specific view | - |

### 6.2 `pubspec.yaml` 的 `path:` vs `git:` vs pub.dev

| 来源 | 含义 | FlClash 用法 |
|---|---|---|
| `:`pub.dev: | 从 pub.dev | `^xx.x.x` |
| `git:` | 从 git 仓库 (特定 ref) | `chen08209/flutter_js` 等 |
| `path:` | 主仓库内子包 | `plugins/proxy`、`plugins/rust_api` 等 |
| `path:` + git modules | 主仓子仓库 | 通过 `.gitmodules` 拉 |

### 6.3 Flutter ↔ 原生编译系统的接入点

| 平台 | Flutter 用什么 | 怎么注入 native code |
|---|---|---|
| Android | Gradle | `externalNativeBuild { cmake {} }` |
| iOS | CocoaPods | `podspec` script phase |
| macOS | CMake / CocoaPods | CMakeLists + podspec |
| Windows | CMake | CMakeLists |
| Linux | CMake | CMakeLists |

🔑 **FlClash 的"四 hook 一 cli"**：
- 一个 Dart CLI：`plugins/setup/buildkit/build_tool/`
- 四个 hook：CMake / Gradle / podscript / run_build_tool.sh
- 一次 run_build_tool.sh 内部串起来 Go + Rust 两种编译

---

## 七、进阶：为什么 FlClash 要把 5 平台、4 语言搞成 4 套不同的桥？

> 这是个**架构决策问题**，不是技术问题。

| 平台 | 现有约束 | FlClash 决策 | 原因 |
|---|---|---|---|
| **Android** | 已有 Java VpnService、有 JNI | Go 编 .so + CGO + dart:ffi 直调 | 不浪费 Java/已有 fd |
| **macOS / Linux** | 无 Java，可执行 spawn | Go 子进程 + Unix socket | CGO 麻烦，IPC 简单 |
| **Windows** | 多层权限 | Go 子进程 + named pipe + Rust helper（提权） | 名字管道比 Unix socket 干净 |
| **iOS**（Flutter 默认能跑）| 应用沙箱、网络扩展必须有 NEAppRules | 本项目 git modules 提示**没有 iOS 支持**，所有桥都回避 iOS | App Store 政策阻止装 Go 内核（业余开发者不能编译 JIT） |

🔑 **这就是设计** —— FlClash 显式放弃 iOS 来避免 Go 端编译复杂度。

---

## 八、最后一张表：每条 FlClash 源码对应到哪个"前置概念"

| 概念 | FlClash 源码 / 文件 / 行号 |
|---|---|
| **C ABI** | `core/bride.h`, `core/bride.c`, `core/lib.go //export fn` |
| **CGO** | `core/bride.go:5-7`  `import "C"` |
| **dart:ffi** | `lib/core/lib.dart:36-42` `preload()` |
| **flutter_rust_bridge** | `plugins/rust_api/flutter_rust_bridge.yaml` |
| **cargokit** | `plugins/rust_api/cargokit/{cmake,gradle,build_pod.sh}/` |
| **Frame protocol** | `core/server.go:34-53` length-prefix + `lib/core/transport.dart:9-15` TLV |
| **Socket variants** | `core/dial_socket.go`, `core/dial_pipe.go` |
| **Process shutdown** | `core/server.go:67-102` `startServer` defer Close |
| **Callback ownership** | `core/bride.{h,c,go}`, `core/lib.go:60-70` `clear()` |
| **String copy** | `core/bride.go:32-36` `C.GoString` + defer C.free |
| **Global static** | `core/lib.go:30 var eventListener unsafe.Pointer` |
| **panic recovery** | `core/action.go:42-50` defer recover |
| **TUN file descriptor 跨 4 层** | `core/lib.go:202-204`, `core/tun/tun.go:50-61` |
| **Rust helper with HTTP** | `services/helper/Cargo.toml:13-17` |
| **build-time token** | `AGENTS.md:192-197` |
| **Flutter plugin types** | `pubspec.yaml` 全文件 |
| **Build system** | `plugins/setup/buildkit/{cmake,gradle}/` |

---

## 九、一句话总结

> 跨语言桥接本质就是 **3 件事**：
> 1. **ABI** = 双方对"参数怎么传、struct 怎么排、调用约定怎样"达成共识（最常用的是 C ABI）；
> 2. **IPC** = 跨进程时把消息打包成 self-describing 字节流（JSON + 帧协议是最简方案）；
> 3. **所有权** = 跨语言传任何对象前**必须先复制或显式约定 release**，否则悬空指针 = SIGSEGV。
>
> 看完 FlClash 这套栈，你应该能看懂：每一个 "//export"、"#[frb]"、"Pointer<Void>"、"unsafe.Pointer"，都是这 3 件事的具体表达。

---

## 十、附：完整阅读路径

如果你想继续深入：

| 文档 | 主题 |
|---|---|
| **前置知识基础**（本篇） | 术语 + 工具链总览 |
| **`IPC实操细节`** | 4 套桥的工程实操怎么搞 |
| **`桥接内存管理`** | 4 套桥各自的所有权与防泄露机制 |
| **`跨语言桥接原理与跨平台稳定性`** | 顶层原理解释 |
| **`原生栈与自研模块`** | 整个 FlClash 的原生栈图谱 |

按"前置知识 → 实操细节 → 内存管理 → 跨语言原理 → 原生栈图谱"的顺序读下来，就能复现作者的整套思考链。
