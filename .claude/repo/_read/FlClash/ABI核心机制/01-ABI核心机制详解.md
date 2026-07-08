# ABI 核心机制详解——指针是怎么在跨语言栈里跑起来的

> ABI 是 "Application Binary Interface"。它把"一个函数是怎么从一行代码变成 CPU 指令"这件事**完整契约化**——参数怎么放、返回值在哪、谁负责清理、栈多大、struct 怎么排内存、对齐规则、虚拟表结构、调用方能不能 inline 函数……一旦两段二进制都用同一套 ABI，它们的指针和函数就能互相调用。
>
> 这份文档针对"ABI 是怎么**操纵指针**"做完整拆解。读到最后一节你应该能看着 `core/bride.h` 想象出每个表函数被调用时寄存器、栈、内存的实际状态。

---

## 一、为什么 "ABI" 这个词那么容易被理解错？

| 误解 | 真相 |
|---|---|
| ABI = 函数签名 | 函数签名只是 ABI 的一个 side effect |
| ABI = 调用约定 | 调用约定只是 ABI 的一小部分（calling convention） |
| ABI 就是 string | ABI 是**机器级**的，描述的是机器码层面 + 链接器层面 + 加载器层面的契约 |
| ABI 用相同语言决定的 | ABI 是**跨语言**的，因为不同编译器产出不同 ABI |

🔑 **最精确的一句话**：ABI 是一组**让两个二进制模块能正确地互相调用的全部规则**。它管的不是"代码长啥样"，而是"生成的二进制在内存里怎样放，CPU 怎么执行"。

> **任何语言到任何语言的 FFI 调用，底层都需要 ABI 一致** —— 这是为什么几乎所有 FFI 框架最终**收敛到 C ABI**：因为它是最稳定的、唯一能在所有平台上达成共识的 ABI。

---

## 二、ABI 的 7 大组成模块（按"ABI 控制指针"的方式排）

```
┌────────────────────────────────────────────────────────────────┐
│                  完整一个 ABI 协议栈                             │
│                                                                │
│   ┌─────────────┐  1. 类型映射 (Type Layout)                   │
│   ├─────────────┤  2. 调用约定 (Calling Convention)             │
│   ├─────────────┤  3. 寄存器分配 (Register Allocation)          │
│   ├─────────────┤  4. 函数链接 (Name Mangling / Linking)        │
│   ├─────────────┤  5. 函数指针表 / vtable                      │
│   ├─────────────┤  6. 内存对齐与 struct padding                │
│   └─────────────┤  7. 调用方/被调用方责任划分 (Caller/Callee) │
└────────────────────────────────────────────────────────────────┘
```

下面逐个拆。每节都先讲原理，再回到 FlClash。

---

## 三、第 1 块：类型映射 —— ABI 怎么决定一个字节怎么放？

### 3.1 基本类型尺寸对照表

| C 类型 | x86_64 Linux | x86_64 Windows | arm64 iOS/macOS | 备注 |
|---|---|---|---|---|
| `char` | 1 | 1 | 1 | - |
| `short` | 2 | 2 | 2 | - |
| `int` | 4 | 4 | 4 | **C 规定**："自然"长度，至少 16 bit |
| `long` | 8 | 4 | 8 | **陷阱 1**：Windows long = int |
| `long long` | 8 | 8 | 8 | - |
| `float` | 4 | 4 | 4 | - |
| `double` | 8 | 8 | 8 | - |
| `void *` | 8 | 8 | 8 | 全 64-bit ABI 都是 8 |
| `size_t` | 8 (LP64) | 8 (LLP64) | 8 (LP64) | 都 8，但 LP64/LLP64 仍不一样 |

🔑 **陷阱 1** 就是 Windows `long` = 4 字节 —— 不同平台 C 类型大小不一致，所以 FFI **推荐一律 `<stdint.h>` 类型**：`int32_t`/`uint64_t`/`intptr_t` 这些。

### 3.2 FlClash 怎么做的？

```go
// core/lib.go
fd C.int                                        // ← int 就是 int32_t（4 bytes）
stackChar, addressChar, dnsChar *C.char        // ← char = 1B
```

```dart
// lib/core/lib.dart
class CoreLib extends CoreHandlerInterface {    // 通过 dart:ffi 自动处理
  static final DynamicLibrary _lib = ...;
  final Pointer<NativeFunction<...>> invokeAction =
      _lib.lookup<NativeFunction<...>>('invokeAction').asFunction();
}
```

`C.int` 在 Go cgo 是 **`_Ctype_int = int32`**，跨平台稳定。

### 3.3 类型内存示意（一个 point2d）

```c
struct Point2D {
    double  x;     // offset 0, 8 bytes
    double  y;     // offset 8, 8 bytes
    char    label; // offset 16, 1 byte
    // 7 bytes padding (struct alignment = 8)
}; // total size = 24 bytes
```

ABI 决定：
- **offset**：每个字段相对结构体开头多长
- **alignment**：最大成员的 alignment（这里是 8），整结构体的最后要 pad 到 8 倍数

🔑 **真实 ABI 文档**：System V ABI（Linux/macOS x86-64）、ARM AAPCS（arm iOS）、MS ABI（Windows x64）。

---

## 四、第 2 块：调用约定 —— 函数被调用时实际发生什么

调用约定 = ABI 的"现场规约"。**它直接决定指针怎么走**。

### 4.1 SysV x86_64（Linux/macOS x86_64）

| 项 | 规则 |
|---|---|
| **整数/指针参数** | RDI, RSI, RDX, RCX, R8, R9（6 个内联寄存器） |
| **浮点参数** | XMM0..XMM7（8 个 SSE 寄存器） |
| **返回值** | RAX（整型/指针）/ XMM0（float/double）/ 多个值用 indirect return |
| **调用者保存** | RAX, RCX, RDX, RSI, RDI, R8-R11, XMM0-XMM15 |
| **被调用者保存** | RBX, RBP, R12-R15 |
| **栈对齐** | 16 byte 对齐（call 时 rsp%16 == 0） |
| **栈清理** | 调用方负责（cdecl），不需要 callee 做 ret n |

一个简单函数：

```c
int add(int a, int b, int c) { return a + b + c; }
```

ABI 行为：

1. caller 把 `a, b, c` 分别放进 RDI, RSI, RDX 三个寄存器
2. caller 跑 `call add` 指令，把 return address 压栈
3. callee 读 RDI, RSI, RDX，相加
4. callee 把结果写 RAX
5. callee `ret`，控制权回 caller

### 4.2 Windows x64 ABI（Microsoft x64）

| 项 | 规则 |
|---|---|
| **整数参数** | RCX, RDX, R8, R9（4 个，**少一个**） |
| **浮点** | XMM0..XMM3（**也是 4 个**） |
| **第 5 个开始** | 走栈（**Linux 还是走栈**） |
| **调用者保存** | 比 SysV 多（多套几个） |

🔑 **SysV vs MS ABI 的差异**：

- Microsoft x64 调用约定**更严格**（少 2 个寄存器，多保存几个），但 Windows 靠"运行同一个 ABI 不容易切换"成垄断
- 函数指针在两个 ABI 之间**不可直接转换**

### 4.3 AAPCS（ARM 64 位 iOS/macOS）

```
x0..x7   整型/指针参数
x8       indirect result（多返回值地址）
x9..x15  临时
x16, x17 别用
x18      platform register (苹果保留)
x19..x28 callee-saved
x29=FP, x30=LR

v0..v7   浮点参数
```

### 4.4 调用约定示意（一个递归指针调用）

```c
struct List {
    int value;
    struct List *next;   // ★ 指针就是 8B，刚好放一个寄存器
};

int sum(struct List *head) {
    if (!head) return 0;
    return head->value + sum(head->next);  // ★ RDI 装 head
}
```

`sum(head)` 在 SysV ABI 下：

```
RDI = head
CALL sum
  RDI = head->next      // 重新装到第一个参寄存器
  CALL sum                // 又一次 push return address
    RDI = next->next
    ...
  RET                 // pop retaddr, jump
RET
```

`head->next` 是指针，加载 `next` 就是 `*(&head + offset_of_next)` → 它把 8 字节指针放进 RDI。这就是"通过 ABI 调用递归处理指针"的实操。

### 4.5 FlClash 怎么桥过的？

`core/bride.go:9-11`：

```go
func protect(callback unsafe.Pointer, fd int) {
    C.protect(callback, C.int(fd))
}
```

- `callback` 走 RDI（第一个参数）
- `fd` 转 `C.int` 放 RSI
- C 端 `void protect(void *tun_interface, int fd)` 读 RDI, RSI 即可

**完全符合 SysV** —— Go 的 CGO 强制 `import "C"` 调用都按当前平台的 C ABI 走，**Go 不暴露自己 goroutine 调用栈**，一律当 C 函数。

---

## 五、第 3 块：寄存器分配 ——"指针走到哪个 CPU 寄存器"

**ABI 是编译器生成的，不存在"ABI 选哪个寄存器"这个动作**。ABI 是**约定**，编译器按约定自动决定：
- 哪个参数放哪个寄存器
- 哪些寄存器是被调函数可以随便用（caller-saved）
- 哪些必须保存（callee-saved）

### 5.1 一个 register allocation 例子

```c
long add_three_ptrs(long *a, long *b, long *c) {
    long x = *a, y = *b, z = *c;
    return x + y + z;
}
```

SysV 编译后（伪汇编）：

```asm
add_three_ptrs:
    mov rax, [rdi]      ; x = *a
    add rax, [rsi]      ; x += *b
    add rax, [rdx]      ; x += *c
    ret
```

- `a, b, c` 已被 caller 装进 RDI, RSI, RDX
- 使用 RAX 作为累加
- 不用栈，4 条指令完成

如果调换：

```c
long add_seven_ptrs(long *p1, ..., long *p7) {  // 7 个指针参数
    long sum = 0;
    for (...) sum += *p_n;
    return sum;
}
```

SysV 只有 6 个寄存器，超出的第 7 个就**push 到栈上**：

| 位置 | 寄放 |
|---|---|
| RDI | p1 |
| RSI | p2 |
| RDX | p3 |
| RCX | p4 |
| R8 | p5 |
| R9 | p6 |
| **栈（call 上方）** | p7 |

🔑 **ABI 的存在**是为了：
1. caller 知道放在哪里 callee 能找到
2. callee 知道自己责任范围（保存哪些、释放哪些）
3. 编译器不用记录"对方怎么用"就能编出能链起来的对象文件

### 5.2 FlClash 里怎么样的？

Dart FFI 调用 Go export `startTUN(callback, fd, stack, address, dns)` —— 5 个参数：

```go
//export startTUN
func startTUN(callback unsafe.Pointer, fd C.int, stackChar, addressChar, dnsChar *C.char) bool {
    handleStartTun(callback, int(fd), takeCString(stackChar), takeCString(addressChar), takeCString(dnsChar))
    ...
}
```

按 SysV：
- `RDI = callback` (8B pointer)
- `RSI = fd` (4B int)
- `RDX = stackChar` (8B pointer to stack-string)
- `RCX = addressChar`
- `R8 = dnsChar`

Dart 端 `Pointer<NativeFunction<Uint8 Function(Pointer<Void>, Int32, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)>>` 直接按 C ABI 跳，Dart VM 自带的 trampoline 帮你 load 参数到正确位置。

---

## 六、第 4 块：函数链接 —— 符号怎么找到对方

### 6.1 C ABI 的核心约定：Name mangling = 不加修饰

```c
int add(int a, int b);    // C
```

被 `gcc` 编译后，**生成的符号就叫 `add`**。没有任何前缀/后缀/类型加密：

```bash
$ nm add.o
00000000 T add
```

为什么这是 ABI 大杀器：
- C 程序和 Rust `extern "C" fn add` 出来的符号一致 → **RUST 可以 call C 程序**
- C 程序和 Go CGO `//export add` 出来的符号一致 → **GO 可以 call C，反之亦然**
- 不需要 RTTI、不需要 namespace、不需要 vtable

### 6.2 C++ ABI 的"反例"（为什么 C++ 难 FFI）

```cpp
namespace math {
    int add(int a, int b);
}
```

`g++` 会按 **Itanium C++ ABI** (Itanium mangling) 装饰成：

```
_ZN4math3addEii
```

这是 ZN + namespace + 名 + 参 type。结果：Rust 想调 C++ `math::add`，**也得知道 Itanium mangling 算法**。

🔑 **C ABI 没 mangling** → 用 Symbol 名就能 resolve → FFI 时只需 string lookup。

### 6.3 FlClash 的 link path

| 调用方向 | 符号名 | 怎么 resolved |
|---|---|---|
| Dart lookup | `'startTUN'` | `DynamicLibrary.open('libclash.so').lookup('startTUN')` |
| Go CGO export | `startTUN` | `//export startTUN` 让 cgo 生成同名 `.h` 符号 |
| Rust FFI | `startTUN` | `#[no_mangle] pub extern "C" fn startTUN(...)` |

三端都用 `'startTUN'` 这个字符串。**ABI 通过"name mangling 不变"保证它们相互找到**。

`frb_generated.io.dart` 里写的：

```dart
final ptr = _lib.lookup<NativeFunction<...>>('start_ipc_server');
final func = ptr.asFunction<...>();
```

`start_ipc_server` 这个字符串 literal **必须**与 Rust 端 `#[no_mangle] pub fn start_ipc_server(...)` 的名字一致。ABI 不替它们协商，**它们俩**协商好了，ABI 只是允许这场协商。

---

## 七、第 5 块：函数指针表 / vtable —— ABI 层面的"指针的指针"

### 7.1 C 函数指针 = ABI 原生支持的"Dart Function"

```c
typedef void (*EventCallback)(void *user, int event);

struct EventSource {
    int fd;
    EventCallback on_event;  // ★ 函数指针，C ABI 表达
    void *user;              // ★ 用户态指针（C ABI 通用）
};
```

一个 `EventSource` 实例：

```
struct EventSource ┐
                   ├── offset 0: fd = 4 bytes (int)
                   ├── offset 4: on_event = 8 bytes (function pointer)
                   └── offset 12: user = 8 bytes (void *)
```

调用时机器码：

```asm
mov rdi, [rbx + 12]       ; load user pointer
mov esi, [rbx + 4]        ; load fd
mov rax, [rbx + 8]        ; load function pointer (?? wait let me re-check)
call rax
```

(实际 off 是 `on_event` 在 fd 之后 padding 4 字节)

**关键**：
- 函数指针是 8 bytes（x64），就是 1 个 CPU 寄存器能装下
- void * 也是 8 bytes
- `call rax` 跳到 RAX 寄存器里装的地址

### 7.2 这就是 FlClash `core/bride.h` 在做的事

```c
// core/bride.h:5-13
extern void (*release_object_func)(void *obj);
extern void (*free_string_func)(char *data);
extern void (*protect_func)(void *tun_interface, int fd);
extern char* (*resolve_process_func)(...);
extern void (*result_func)(void *invoke_Interface, const char *data);
```

5 个函数指针 / `void *` 在 C ABI 看来就是**全是 8 bytes 的 pointer**。`protect_func`：

```c
// core/bride.c:13-15
void protect(void *tun_interface, int fd) {
    protect_func(tun_interface, fd);
}
```

底层步骤：

1. Go 端 `core/bride.go:9-11`：
   ```go
   func protect(callback unsafe.Pointer, fd int) {
       C.protect(callback, C.int(fd))
   }
   ```
   - Go 编译时，编译器看到 `import "C"` + C symbol，调编译器把 C 函数 `protect` 当 C ABI 函数 trampoline
   - Go 把 `callback` 装 RDI（第一个参数）
   - Go 把 `C.int(fd)` 装 RSI
   - Go 执行 `call protect`，跳过去

2. C 端 `bride.c:13-15`：
   ```c
   void protect(void *tun_interface, int fd) {
       protect_func(tun_interface, fd);
   }
   ```
   - C `protect` 函数体先读参数 (RDI, RSI)
   - C 把参数重新搬到固定格式（SystemV 跟 Go 完全一致）
   - C `call` 指令跳转到 `protect_func` 寄存器里的地址（这里 `protect_func` 本身也是 8B 全局变量）
   - 跳转到 Java 端 JNI 装的 callback

3. Java 端：
   ```java
   // Java_com_follow_clash_core_Core_nativeProtect
   private static native void nativeProtect(int fd);
   ```
   - JNI 装了 trampoline 跳回 Java method
   - Java 端 `nativeProtect(fd)` 是普通 Java method

🔑 **ABI 完整闭环**：

```
Go (core/bride.go)
    │ CGO 生成的 trampoline
    ▼  ABI align: RDI=ptr RSI=fd
C  (core/bride.c::protect)
    │ 直接 call protect_func 全局地址
    ▼  ABI align: 同样 RDI=ptr RSI=fd
Java JNI (com_follow_clash_core_Core_nativeProtect)
    │ JNI 跳回虚拟机
    ▼
Java 实例方法
```

每个箭头都是 1 次"ABI 对齐"。**ABI 错一处**：

- 参数寄存器错 → 参数错位，函数读取到错误地址 → SIGSEGV
- 函数指针错 → jump 到 wild address → SIGSEGV
- 全局变量错位 → JNI 找不到 trampoline → UnsatisfiedLinkError

### 7.3 同样 `_callback` unsafe.Pointer 在 Go 内存里长啥样？

```go
// core/lib.go:30
var eventListener unsafe.Pointer
```

Go 的 `unsafe.Pointer` 在 64-bit 系统上 = 8 bytes。它代表的是**一个不会 move 的指针**。当 Go GC 想搬动对象，会"假装"这个 pointer 是 GC root，**钉住不动**。

```go
// core/lib.go:227-234
//export setEventListener
func setEventListener(listener unsafe.Pointer) {
    if eventListener != nil || listener == nil {
        releaseObject(eventListener)
    }
    eventListener = listener
}
```

`listener` 参数从 RDI 传入，类型 `unsafe.Pointer` —— 底层就是 8B 的 raw pointer，编译器不解释它指向什么类型，纯粹保留"指向某段机器码 trampoline"。

---

## 八、第 6 块：内存对齐 —— ABI 怎么控制 struct 布局

### 8.1 alignof / sizeof

```c
struct Example {
    char  a;       // offset 0, 1B
    int   b;       // offset 4 (after 3B padding), 4B
    char  c;       // offset 8, 1B
    short d;       // offset 10 (after 1B padding), 2B
    // struct alignment = 4
}; // total size = 12 (next multiple of 4 after 10)
```

🔑 **ABI 规定的对齐规则**：

| 字段类型 | 自然对齐 (alignof) |
|---|---|
| char | 1 |
| short | 2 |
| int | 4 |
| long (Linux) | 8 |
| float | 4 |
| double | 8 |
| void * | 8 |

**ABI 规则**：
- 字段的 `offset = align(current_position, alignof(field))`
- struct 的整体 `size = align(largest_field, sizeof(struct))`

### 8.2 FlClash 怎么绕开 struct ABI？

**不导出 struct 跨语言**。所有跨界数据都是 **JSON string**：

```go
// core/constant.go:10-22
type Action struct {
    Id     string      `json:"id"`
    Method Method      `json:"method"`
    Data   interface{} `json:"data"`
}
```

字符串在 C ABI 是 `char *`，即 `intptr_t`-aligned 8 bytes —— 无 padding 问题。

**避免 ABI 陷阱的最简单方法就是把 struct 压缩成 byte array**。Flutter Inspector / protobuf / flatbuffers 都是这么干的。

---

## 九、第 7 块：调用者/被调用者责任划分 —— ABI 的"谁负责清理栈"

### 9.1 cdecl (C declaration) vs stdcall

| 约定 | 谁负责 pop 参数 | 谁负责 set return val | 备注 |
|---|---|---|---|
| **cdecl** | caller | callee | Linux/macOS 默认 |
| **stdcall** | callee (`ret 8`) | callee | Windows Win32 API |
| **fastcall** | callee (前 2 arg 走寄存器) | callee | Windows x64 (MS x64) |
| **thiscall** | callee | callee | C++ member function |

🔑 **"谁清理栈"是为了函数指针通用性**：
- 如果是 stdcall，调 `releaseObjectFunc(指针)` 不知道参数多少字节，callee 必须 `ret 8` 自己清理
- cdecl 必须靠 caller，编译器在 `call ret` 之间 emit 一条 `add rsp, N` 清栈

FlClash bridge 全用 cdecl 风格 —— Go CGO 编译时强制 cdecl：

```go
// Dart FFI 调 startTUN 5 个参数 → C 端也按 cdecl
```

### 9.2 callee-saved 寄存器

责任划分另一个体现：
- callee 看到 caller 把 R12 装了个值，callee **必须** 用完 R12 时还原
- callee 用 RAX 是合法的，因为 caller 自己负责保留

Go runtime 怎么兼容？**Go 用 cgo 时通过 `runtime.cgocall`**，它把 goroutine 栈切换到 g0 栈，让 C 函数在 fixed stack 上跑、avoid GCing on g0：

```go
// go 在 cgo 时的工作：
// 1. 拨开 P，让本 M 进入 _G0
// 2. 跑 C 函数（不受 goroutine 调度影响）
// 3. C 函数 ret
// 4. 重新抢 P，继续跑 goroutine
```

C 函数内部随便用哪些寄存器，因为 Go 端根本不会碰这套寄存器。

🔑 **ABI 责任划分**让 Go 可以"假装"自己没在跑 C：

```
Dart call --[ABI transfer]--> Dart VM trampoline
                              │
                              ▼
                       Go FFI invoker
                              │
                              ▼
                       Go cgo wrapper
                              │
                              ▼                    ←── C runs here
                       [C function body]              isolated, no GC
                              │
                              ▼
                       Go cgo wrapper
                              │
                              ▼
                       return to Go
                              │
                              ▼
                       return to Dart
```

---

## 十、ABI 的"完整指挥链"—— 用 FlClash 的 `setEventListener` 跑一遍

源码（`core/lib.go:227-234`）：

```go
//export setEventListener
func setEventListener(listener unsafe.Pointer) {
    if eventListener != nil || listener == nil {
        releaseObject(eventListener)
    }
    eventListener = listener
}
```

### 10.1 用 ABI 视角读这一段

**1. Dart 端触发：**

```dart
lib.setEventListener(nativeFunction);
```

Dart 这边的 `nativeFunction` 是 `Pointer<Void>`，但实际指向一个 Dart-VM-managed trampoline —— 这个 trampoline 内部把 closure 转换成 C 可跳的 `void (void*)` 函数指针。

**2. Dart VM 创建 trampoline：** 这个 trampoline 知道怎么在另一线程调用 Dart function（Dart VM 单 isolate 单线程，跨 isolate 跳需要抢占事件循环）。

**3. ABI 准备参数：**

```c
void setEventListener(void *listener);
```

按 SysV ABI：
- `RDI = listener`（8 字节指针）

**4. Dart VM 写 `RDI = listener`，执行 `call setEventListener`：**

Dart VM 是个 native 进程（带 GC），它的 native 调用栈就是它的真实 CPU 栈，符合 SysV 16B 对齐。

**5. Go cgo 跳到 `setEventListener`：**

Go 编译器为 `//export setEventListener` 生成的 wrapper：
- 把 Dart 传过来的 `RDI` 转成 Go 的 `unsafe.Pointer` 类型
- 调 Go 函数体

**6. Go 函数体执行：**

```go
if eventListener != nil || listener == nil {
    releaseObject(eventListener)
}
eventListener = listener
```

- `eventListener` 是 Go 全局 `unsafe.Pointer = 8B`
- `releaseObject(callback)` 把 old pointer 还给 Dart
- `eventListener = listener` 把新 pointer 存进 Go 全局
- `gc.KeepAlive` / 写全局变量 = 有意让 GC 把 listener 当 root

**7. return：**

Go 函数 `ret`：
- ABI 要求 RAX = 0（`true` 没有 ... 等等，setEventListener 没返回值）
- 实际：setEventListener 的 signature 是 `func(unsafe.Pointer)`，按 ABI 是 void
- Go 生成 `ret` 把控制权返给 caller
- Go cgo wrapper 通知 `runtime.cgocall` 重新抢 P
- Go 把 RAX 放 Go 返回值（void = empty）
- 返回到 Dart VM 的 native call 位置

**8. Dart VM：**

恢复 Dart frame，继续跑 Dart 后续代码。

🔑 **实际跑完一次 setEventListener 涉及**：
- 1 次 ABI 函数调用（Dart VM → Go）
- 1 次 ABI 函数调用（Go → releaseObject wrapper → Dart）
- 2 个 ABI 参数对齐操作
- 1 个 Go 全局变量写（隐含 GC 行为）
- 1 个 Dart VM 事件循环事件（如果有 release 的话）

---

## 十一、ABI vs API vs ISA 三组词

> 新手最容易混淆 ABI / API / ISA。

| 缩写 | 全称 | 描述范围 | FlClash 例 |
|---|---|---|---|
| **ISA** | Instruction Set Architecture | CPU 指令集层面 | x86_64 / arm64 / RISC-V |
| **ABI** | Application Binary Interface | 同一 ISA 下，二进制模块互相调用的约定 | SysV AMD64 / AAPCS / MS x64 |
| **API** | Application Programming Interface | 同一语言 / 进程内，函数 / 类的接口 | `Future<String> preload()` |

> **ABI 是"链接时"层**。源码已经"通过"了 ABI 这一关：编译时就算错了。
>
> **API 是"源码"层**。源码写对了 API 才能用。

🔑 **"Go 调用 C 函数"打破了 API（语言边界），但仍遵守 ABI（机器边界）**。
Dart 调 Go 不只是 API 兼容，**所有 7 个 ABI 组成规则都一致**，调用才不崩。

---

## 十二、"ABI 控制指针"的关键心智模型

下面对**每一个**跨语言"指针"操作用 ABI 心智模型拆开：

### 12.1 把 Go 函数传到 C（暴露给 C 用）

```rust
#[no_mangle]
pub extern "C" fn my_func(a: i32) -> *mut c_void { ... }
```

ABI 一致点：
1. **name mangling**：`#[no_mangle]` 禁止 mangling，所以符号叫 `my_func`
2. **calling convention**：`extern "C"` 强制 C ABI
3. **parameter layout**：第 1 个整型参数走 RDI（SysV）/ RCX（Win）
4. **return**：`*mut c_void` 是 8B pointer，ret 走 RAX

### 12.2 C 函数指针存到 Go 全局

```go
var protect_func *func(unsafe.Pointer, int)  // 错！Go 不让持有 C 函数指针类型
```

正确写法：

```go
var protectFunc unsafe.Pointer
// 调时用：(unsafe.Pointer → 通过 dart/trampoline → 真实调用)
```

ABI 一致点：
- C 端写 `protect_func = resolve_protect;` 编译器把 `resolve_protect` 函数地址转成 8B 写进 `.data` 段
- Go 端加载 `.so`，定位符号 `protect_func`，读到 8B 装进 `var protectFunc unsafe.Pointer`
- 之后调时 `call [protectFunc]`（间接跳转）

### 12.3 跨语言传 string

```c
char *dup_str(const char *s);
```

ABI 视角（接收方）：
1. caller 把 `s` 装 RDI（C ABI 第 1 参数）
2. callee 读 RDI 是有效指针（不 NULL）
3. callee 假设 `s` 是 NUL 终止
4. callee `malloc(len+1)` 拿新内存，`memcpy` 拷贝
5. callee 把新指针写 RAX 返回

跨语言 recv：

```rust
extern "C" {
    fn dup_str(s: *const c_char) -> *mut c_char;
}

let owned = unsafe {
    let c_str = CStr::from_ptr(dup_str(c_input.as_ptr()));
    c_str.to_string_lossy().into_owned()
};
```

ABI 一致点：
1. 编译后的符号名匹配
2. 整型参数寄存器一致
3. 返回值在 RAX
4. **内存所有权约定一致**（这一段不在 ABI 里，**它是文档**）—— 谁 free

### 12.4 FlClash `bride.go` 里的 `*C.char` 全程

```go
// core/bride.go:9-30
func invokeResult(callback unsafe.Pointer, data string) {
    s := C.CString(data)
    defer C.free(unsafe.Pointer(s))
    C.result(callback, s)
}
```

ABI 视角：
1. `C.CString(data)` -> Go 编译时通过 cgo → **malloc(len+1)**，写入 UTF-8 bytes + NUL → 8B 指针
2. `s` 装进 RDI
3. defer 释放：C.free 调 free(3) 释放 C heap
4. `C.result(callback, s)` - callback 进 RDI，s 进 RSI（按 SysV）
5. C 端 `result` 实际跳到 dart_function 跳板，Dart 端 `Pointer<Utf8>.toDartString()` 拷内容

---

## 十三、ABI 决定的事 vs ABI 没决定的事

| ABI **决定** | ABI **不管** |
|---|---|
| 调用约定（参数寄存器顺序） | 内存所有权归谁 |
| struct alignment | 字符串编码（默认是什么） |
| name mangling | 异常 / error 怎么处理 |
| stack alignment | 谁负责 free 跨语言对象 |
| callee/caller 寄存器保存 | GC 行为 |
| 间接函数指针跳转规则 | 同步 vs 异步 |

🔑 **ABI 是"兼容"的最低限度**——满足 ABI 跨语言就能调起来；
**ABI 不管"ownership / GC / error / sync"** 这些更高层协议——这些必须另外约定。

这就是为什么 FlClash `core/bride.go` 里"defer C.free"和"`releaseObject`"都**不是** ABI 行为，只是 ownership 约定。

---

## 十四、ABI 习语速查（程序员日常会读到的）

| 习语 | 含义 |
|---|---|
| **AAPCS64** | ARM 64-bit Procedure Call Standard |
| **SysV AMD64 ABI** | System V x86_64 ABI（Linux/macOS 默认） |
| **MS x64 / Win64** | Microsoft x64 ABI |
| **i386 cdecl / stdcall / fastcall / thiscall** | 32-bit 各种调用约定 |
| **Itanium C++ ABI** | C++ name mangling 标准 |
| **LP64 / LLP64 / ILP32** | long/pointer 大小约定（LP64 = Linux/macOS, LLP64 = Windows） |
| **CDECL / STDCALL** | 调用约定 cdecl / stdcall 名称 |
| **`-mabi=sysv`** | GCC 强制 SysV ABI 编译 |
| **RELEASE / ACQUIRE** | C++11 memory model，不是 ABI，但是 ABI 上面的协议 |
| **extern "C"** | C++ 让符号不进 mangling |

---

## 十五、FlClash 中 ABI 的 4 个实际例子

### 15.1 CGO 暴露 `startTUN`

```go
//export startTUN
func startTUN(callback unsafe.Pointer, fd C.int, stackChar, addressChar, dnsChar *C.char) bool {
    ...
}
```

按 SysV AMD64 ABI：
- `RDI = callback` (intptr-sized)
- `RSI = fd` (int32)
- `RDX = stackChar` (intptr)
- `RCX = addressChar`
- `R8 = dnsChar`
- 返回 RAX (bool → 8B 但只读 low 1 bit)

### 15.2 Rust helper warp 起 HTTP

```toml
warp = "0.3.7"
tokio = { version = "1", features = ["full"] }
```

`warp` 用 `tokio` 起异步，**底层 ABI 还是 Linux TCP**：
- `/proc/<pid>/net/tcp` 里看得到 socket ABI
- 浏览器 dart:io HttpClient 走 BSD socket → Tokio → warp → handler

### 15.3 IPC 的 `length-prefix` 是 ABI 吗？

**不是** —— IPC 的 binary frame protocol 是比 ABI 更高的协议层，**建立在 ABI 之上**。`writeFrame` 拿到 `io.Writer` 后做的事：

```go
func writeFrame(w io.Writer, data []byte) error {
    frame := make([]byte, 4+len(data))
    binary.LittleEndian.PutUint32(frame, uint32(len(data)))
    copy(frame[4:], data)
    _, err := w.Write(frame)
    return err
}
```

- `binary.LittleEndian.PutUint32`：这是 **endianness**，与 ABI 同级
- `make + copy + Write`：Go 内部 ABI（call conv + struct layout）

但"先写 4 字节长度、再写 payload"是 **协议层（IPC 层）约定，不是 ABI**。

### 15.4 `unsafe.Pointer` 在 Go runtime 里的"假装 root"

```go
// core/lib.go:30
var eventListener unsafe.Pointer
```

Go GC 把这个全局当成 GC root —— **只要 `eventListener` 不被释放，就钉住原 Dart 函数指针的 trampoline 不被回收**。这是 GC 行为，不是 ABI 行为。

但 **Go GC 怎么处理 `unsafe.Pointer`**？这是个 ABI 模糊地带：
- 编译器没法知道 unsafe.Pointer 指向什么类型
- 所以 GC **保守扫描**——读 unsafe.Pointer 指向的内存当对象头
- 这就要求 unsafe.Pointer 指向的必须是合法 Go 内存（或用户明确告诉 runtime）

`unsafe.Pointer` 给 Go 一些"ABI 之外"的灵活性 —— 但**带来 GC 风险**。

---

## 十六、ABI 陷阱案例（你写跨语言代码会踩的）

### 16.1 调用约定错配 → 灾难

```c
// C 端 cdecl
int __cdecl cfunc(int a, int b);

// Rust 端错误地标 stdcall
extern "stdcall" {
    fn cfunc(a: i32, b: i32) -> i32;
}
```

后果：
- 调用方 Rust 把 a → ECX, b → EDX（MS x64 ABI）
- 被调方 C 期望 a → RCX, b → RDX（一样）
- 单看结果对，但如调用多个函数嵌套，callee 清理栈假设不一致 → 栈破坏

### 16.2 size 错配 → 灾难

```c
struct Foo {
    int a;
    long b;       // Linux 8B / Windows 4B
};
```

Rust 端：

```rust
#[repr(C)]
struct Foo { a: i32, b: i64 }  // 错误！Linux 才匹配，Windows 不匹配
```

Windows 下 `b: i64` 但 C 端 `long` = 4B，结构体大小差异，访问 b 字段会读错地址。

🔑 **对策**：永远用 `<stdint.h>` 类型 (`int32_t`, `int64_t`)，不用 `long`。

### 16.3 name mangling 错配 → 找不到符号

```rust
fn my_func() {}  // mangling: _ZN7my_func... 
```

```bash
$ nm my.o
00000000 T _ZN7my_func...
```

C 端找 `my_func` 找不到。必须 `#[no_mangle] pub extern "C" fn my_func() {}`。

### 16.4 平台 switch 错配

```c
#ifdef _WIN32
    return win_func(...);    // Windows 约定
#else
    return posix_func(...);  // POSIX 约定
#endif
```

ABI 不保护你 —— 平台代码自己承担平台差异。FlClash 用 `//go:build` tags 显式标记，跟 C `#ifdef` 同理。

---

## 十七、ABI 学习的最小阅读路径

1. **C 编译原理**：拿一份 C 代码 `gcc -S` 看汇编，了解 cdecl
2. **System V ABI 文档**：搜 "System V ABI AMD64"，读前 100 行就懂
3. **可执行格式**：了解 ELF / Mach-O / PE 文件结构，看 `.dynsym` 段
4. **FFI 实战**：写一份 Dart / Go / Rust 三个端互相调用的 demo，触发 ABI 错误再回头找根因

---

## 十八、源文件/行号

| ABI 概念 | FlClash 证据 |
|---|---|
| C ABI 函数指针表 | `core/bride.h:5-13` 5 个 extern fn pointer |
| C ABI trampoline | `core/bride.c:1-31` |
| CGO import "C" + //export | `core/bride.go:5-7`、`core/lib.go:184+` |
| `unsafe.Pointer` 8B 全局 | `core/lib.go:30` |
| type layout (`C.int` = int32) | `core/lib.go:202` |
| name mangling 协商（"startTUN" 同字符串跨三方）| `core/lib.go:201` |
| name mangling 协商（"restartIpcServer" 同名字符串）| `lib/core/transport.dart:35` 调 Rust |
| Rust crate-type cdylib/staticlib | `plugins/rust_api/rust/Cargo.toml:5-7` |
| Go cgo 字符串转换 | `core/bride.go:32-36` |
| Rust 跨 ABI 通信 | `plugins/rust_api/` 全套 |
| `frb_generated.io.dart` 真实查找函数指针 | fl_rust_bridge codegen 产出 |
| build tag 平台分发 | `core/dial_*.go`, `core/tun/tun.go`, `core/main*.go` |

---

## 十九、一句话总结

> **ABI = "二进制模块互相调用对方时机器层面怎么对齐"**。
> 它通过 7 大规则（类型映射 / 调用约定 / 寄存器分配 / 名称修饰 / 函数指针表 / 内存对齐 / 责任划分）让跨语言指针安全跳转。
> **ABI 决定"两个函数能不能互相 call"**；**ABI 不决定"调用之后谁负责清理内存"**——后者是文档约定。
> FlClash 整套 CGO bridge 的 5 个 `void (*xxx_func)(...)` 指针表，就是 ABI 操纵指针的最直接表达：5 个 8B 寄存器大小的 raw pointer 跨语言传递 + 跳板 trampoline + 全局变量保留，**直到 owner 显式 release**。

读懂 ABI 再看 FlClash 的 `core/bride.{h,c,go}` 那 3 个文件，应该能想象出每个函数被调用时 RDI/RSI/RDX/RAX 的动作，以及 trampoline 怎么把指针一跳一跳送到 Java 端。
