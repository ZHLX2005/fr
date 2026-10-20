---
name: android-native-c-setup
description: Flutter Android 项目里如何接入原生 C/C++ 代码 — CMake/Gradle 配置、ABI 多架构编译、库加载机制、FFI vs JNI 选型、C++ 标准选择。读完主 SKILL.md 的 SOP 后、对 Android 原生层不熟时加载。
---

# Android 原生 C 编码原理

## 1. 工具链全景

```
Dart 代码 (lib/*.dart)
       │ dart:ffi
       ↓
.so 库 (libmetronome.so)
       │ NDK 编译
       ↑
C++ 代码 (android/app/src/main/cpp/*.cpp)
       │ CMake
       ↑
Gradle 配置 (android/app/build.gradle.kts)
       │ Android Gradle Plugin
       ↑
Android.mk / CMakeLists.txt
```

**NDK（Native Development Kit）** = 一套用来在 Android 项目里编译 C/C++ 的工具链。

## 2. CMakeLists.txt 详解

```cmake
cmake_minimum_required(VERSION 3.22.1)   # CMake 最低版本
project(metronome)                         # 项目名（任意）

# 把 cpp 源文件编译成共享库
add_library(
    metronome                              # 库名 → 输出 libmetronome.so
    SHARED                                 # 类型：共享库 (.so) 而不是静态库 (.a)
    metronome.cpp                          # 源文件列表
    metronome.h
)

# 链接外部依赖
find_package(oboe REQUIRED CONFIG)         # 找 Oboe 库（用 prefab）
target_link_libraries(
    metronome                              # 给哪个目标链接
    oboe::oboe                             # Oboe 库（prefab 提供的 CMake target）
    log                                    # Android 日志库 (LOGD/LOGI/LOGE)
)
```

**为什么 `SHARED`？** Flutter FFI 只能加载 `.so`（动态库），不能用 `.a`（静态库）。

**为什么 `oboe::oboe` 双冒号？** Oboe 通过 prefab 暴露 CMake target，命名空间是包名。

## 3. Gradle 接入 cmake

```kotlin
android {
    defaultConfig {
        externalNativeBuild {
            cmake {
                arguments("-DANDROID_STL=c++_shared")  // C++ 标准库动态链接
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")  // CMake 文件位置
            version = "3.22.1"                            // 用 Android SDK 自带的 CMake 版本
        }
    }

    buildFeatures {
        prefab = true  // 让 Gradle 能消费预编译的 AAR（如 oboe）
    }
}

dependencies {
    implementation("com.google.oboe:oboe:1.10.0")  // 从 Maven 拉 Oboe
}
```

**关键点**：
- `buildFeatures.prefab = true` 必须开，否则 `find_package(oboe)` 找不到
- `-DANDROID_STL=c++_shared` 让 C++ 标准库也变成 .so（避免静态链接导致 app 变大）
- `path = file(...)` 指向 `android/app/src/main/cpp/CMakeLists.txt`，相对路径是 module 根

## 4. ABI 多架构

Android 手机 CPU 架构多种多样：

| ABI | 典型设备 | 大小 |
|-----|----------|------|
| `armeabi-v7a` | 32 位老手机 | 小 |
| `arm64-v8a` | 64 位现代手机（绝大多数） | 中 |
| `x86` | 32 位模拟器 | 极少 |
| `x86_64` | 64 位模拟器 | 调试用 |

**默认 Gradle 给所有 ABI 编译**——慢且包大。优化：

```kotlin
android {
    defaultConfig {
        ndk {
            // 只编 64 位（现代市场 95%+）
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }
}
```

调试时如果想看模拟器效果，必须保留 `x86_64`。

## 5. FFI vs JNI 选型

| 维度 | FFI (`dart:ffi`) | JNI (Java Native Interface) |
|------|-------------------|----------------------------|
| **调用路径** | Dart → C/C++ | Dart → Java/Kotlin → JNI → C/C++ |
| **性能** | 直接调用，无中间层 | 多一层 MethodChannel 序列化开销 |
| **跨平台** | Dart 一套代码，iOS/macOS/Windows 也用 `dart:ffi` | Android only |
| **学习成本** | 中（要会 C ABI） | 高（要会 Kotlin + JNI 签名） |
| **数据传递** | 直接传 `Pointer<Struct>` | `ByteBuffer` 序列化 |
| **适用场景** | 高频调用（音频/渲染/计算） | 偶尔调一次（系统 API 封装） |

**结论**：节拍器等高频音频场景必须用 FFI。JNI 留给偶尔调一次的原生 API 封装。

## 6. 库加载机制

Dart 端：

```dart
static final DynamicLibrary _lib = Platform.isAndroid
    ? DynamicLibrary.open("libmetronome.so")  // ← 关键
    : throw UnsupportedError("Only Android is supported");
```

**Android 上的库加载路径**：

1. APK 安装时，`libmetronome.so` 被解压到 `/data/app/<package>/lib/<abi>/`
2. Dart FFI 调用 `DynamicLibrary.open("libmetronome.so")`
3. 系统 `dlopen("libmetronome.so")` 加载到进程空间
4. Dart 调用 `lookupFunction<NativeSig, DartSig>("function_name")` 拿到函数指针
5. 后续 Dart 调用就像普通函数一样（但走的是 C ABI）

**为什么不用绝对路径？** APK 安装位置每次升级都可能变。用 `libmetronome.so` 让系统从应用沙箱里找。

## 7. C++ 标准选择

```cmake
# CMakeLists.txt 里默认可以用 C++17
# 如果想升级到 C++20：
set(CMAKE_CXX_STANDARD 20)
```

**建议**：C++17 足够。Oboe 1.10 + 标准库 `std::optional` / `std::variant` 都有。

**不要用 C++20 除非**：
- 需要 `std::format`
- 需要 `concept` / `range`

**不要用 C++14 或更老**：Oboe API 需要 C++17。

## 8. extern "C" 的作用

```cpp
// metronome.h
extern "C" {
    void init_audio(double bpm);  // C 链接约定
}

class Metronome : public AudioStreamCallback {  // C++ 类，C++ 链接
    // ...
};
```

**为什么 `extern "C"`？** Dart FFI 不知道 C++ 的 name mangling（命名修饰，如 `_ZN10MetronomeC1Ev`）。`extern "C"` 强制编译器用 C 命名约定（`init_audio` 而不是 `_Z10init_audiomP`），FFI 才能 lookup 到。

**注意**：C++ 类实现必须在 `extern "C"` 块**外面**——块内不能写 C++ 类。

## 9. NativeCallable 时序问题

```dart
// 正确顺序
_tickCallable = NativeCallable<_NativeTick>.listener(_onNativeTick);  // 1. 创建
_lib.lookupFunction<...>('set_tick_callback')(
    _tickCallable.nativeFunction);                                       // 2. 注入

// 错误顺序（拿不到函数指针崩）
_lib.lookupFunction<...>('set_tick_callback')(???);   // 拿啥传？
_tickCallable = NativeCallable<...>.listener(_onNativeTick);  // 太晚
```

## 10. 调试技巧

### CMake 编译失败

```bash
# 看详细错误
cd android
./gradlew :app:assembleDebug --info 2>&1 | grep -A 3 "metronome"
```

### APK 里有没有 .so

```bash
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep "\.so"
```

应该看到：
```
lib/arm64-v8a/libmetronome.so
lib/arm64-v8a/liboboe.so
lib/arm64-v8a/libflutter.so
```

### 运行时库加载失败

启动 app 后 `adb logcat | grep -i "metronome"`，看是否有：
```
dlopen failed: library "libmetronome.so" not found
```

可能原因：CMake 没编进 APK / abi 不匹配 / minSdkVersion 太低（Oboe 要求 API 16+）

### ABI 不匹配

如果只编了 arm64，但你在 x86 模拟器上跑：
```
dlopen failed: "libmetronome.so" not found
```

加 `x86_64` 到 `abiFilters`。

## 11. 完整最小项目骨架

```
android/app/src/main/cpp/
├── CMakeLists.txt
├── metronome.cpp
└── metronome.h

android/app/build.gradle.kts        # 加 externalNativeBuild + oboe 依赖
lib/<feature>/ffi_bindings.dart      # Dart 端 FFI 绑定
```

最少文件数 = 4 个（不含 Flutter 项目原有的 MainActivity.kt / AndroidManifest.xml）。

## 12. 与 iOS / Web 对比

| 平台 | 原生音频方案 |
|------|--------------|
| Android | Oboe (C++，本文档) |
| iOS | AudioUnit (C/Objective-C++) + Swift 桥 |
| Web | Web Audio API `AudioContext` + AudioWorklet (JavaScript) |
| macOS | CoreAudio (C) |
| Windows | WASAPI (C++) |

跨平台统一方案：自建 Dart 包 + conditional imports（`audio_android.dart` / `audio_ios.dart` / `audio_web.dart`），但本 skill 只覆盖 Android。

## 13. 常见错误排查清单

| 错误 | 检查项 |
|------|--------|
| `undefined reference to 'init_audio'` | `extern "C"` 是否加；C++ 类是否在 extern 块外 |
| `oboe::oboe not found` | `prefab = true` 是否开；`oboe:1.10.0` 依赖是否加 |
| `c++_shared not found` | `arguments("-DANDROID_STL=c++_shared")` 是否加 |
| APK 里没有 libmetronome.so | externalNativeBuild path 是否对；CMakeLists.txt 里 `add_library` 是否对 |
| Dart 端 `lookupFunction` 返回 null | 函数名是否拼写一致；C 端是否 `extern "C"` |
| `MinGW / Visual Studio` 错误 | 不要在 Windows 上用 VS 编译——交给 Android NDK |
| `incremental builds stale` | `cd android && ./gradlew clean` 重编 |
| `R8 minify 删了 Native 方法` | 在 proguard-rules.pro 加 `-keep class com.your.app.** { native <methods>; }` |