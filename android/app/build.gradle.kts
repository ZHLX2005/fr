plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ===== 构建变体开关（默认小豆子；CI 微豆子链向 android/gradle.properties 追加 appVariant=weidouzi）=====
// 微豆子：独立签名（android/app/weidouzi.keystore ← secrets.WEIDOUZI_KEYSTORE_BASE64）、
// 包名 io.github.xiaodouzi.fr.wdz、应用名/小组件 label 切「微豆子」。
// 两套配置纯新增互不覆盖：不带该属性时下列分支全部取默认值，与历史构建一致。
// Dart 侧对应 --dart-define=APP_VARIANT=weidouzi（见 lib/core/const_app_variant.dart）。
val appVariant = (project.findProperty("appVariant") as String?) ?: "xiaodouzi"
val isWeidouzi = appVariant == "weidouzi"

android {
    namespace = "io.github.xiaodouzi.fr"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // 启用核心库脱糖，支持Java 8+ API
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.xiaodouzi.fr"
        // 微豆子变体：包名加 .wdz 后缀与 小豆子 并存（默认不加，原包名不变）
        if (isWeidouzi) applicationIdSuffix = ".wdz"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion  // 设置最低SDK版本为21以支持更多功能
        targetSdk = 35  // 显式设置避免 Flutter 默认值过高导致权限问题
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 支持向量图
        vectorDrawables.useSupportLibrary = true

        // 多dex支持
        multiDexEnabled = true

        // 只打 arm64：ndk.abiFilters 是 dev.flutter.flutter-gradle-plugin 在
        // project-level 注入的 val（[armeabi-v7a, arm64-v8a, x86_64]），这里 += 实际
        // 是 no-op（arm64-v8a 已在 FGP 列表里）。要真正 arm64-only 需 fork FGP 或换
        // plugin 集；当前 APK 仍含 3 个 ABI 的 native 库（Oboe/MLKit/Rive），约 73MB。
        ndk {
            abiFilters += listOf("arm64-v8a")
        }

        // 应用名 / 桌面小组件 label —— AndroidManifest.xml 用 ${appLabel} 等占位符引用。
        // 默认值与原硬编码一致；微豆子变体整体切「微豆子」。
        manifestPlaceholders["appLabel"] = if (isWeidouzi) "微豆子" else "小豆子"
        manifestPlaceholders["widgetLabelClock"] = if (isWeidouzi) "微豆子 · 时钟" else "小豆子 · 时钟"
        manifestPlaceholders["widgetLabelTimetable"] = if (isWeidouzi) "微豆子 · 课表" else "小豆子 · 课表"
        manifestPlaceholders["widgetLabelNotion"] = if (isWeidouzi) "微豆子 · 拍照" else "小豆子 · 拍照"
        manifestPlaceholders["widgetLabelRecorder"] = if (isWeidouzi) "微豆子 · 录音" else "小豆子 · 录音"
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildFeatures {
        prefab = true
    }

    // 签名配置
    signingConfigs {
        create("release") {
            storeFile = file("release.keystore")
            storePassword = "android"
            keyAlias = "release"
            keyPassword = "android"
        }

        // 微豆子独立签名（新增，不覆盖 release）：keystore 由 CI 从
        // secrets.WEIDOUZI_KEYSTORE_BASE64 落地到 android/app/weidouzi.keystore。
        // PKCS12 格式要求 store/key 同口令。
        create("weidouzi") {
            storeFile = file("weidouzi.keystore")
            storePassword = "android"
            keyAlias = "weidouzi"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            // 小豆子默认走 release 签名（原行为）；appVariant=weidouzi 时切微豆子独立签名
            signingConfig = signingConfigs.getByName(if (isWeidouzi) "weidouzi" else "release")

            // 启用代码压缩和混淆
            isMinifyEnabled = true
            isShrinkResources = true

            // ProGuard规则
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isDebuggable = true
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }

    // 打包选项
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    // Java编译选项
    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }
}

flutter {
    source = "../.."
}

allprojects {
    repositories {
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}

dependencies {
    // 核心库脱糖
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Multidex支持
    implementation("androidx.multidex:multidex:2.0.1")

    // CameraX核心库（如果需要高级相机功能）
    implementation("androidx.camera:camera-core:1.3.0")
    implementation("androidx.camera:camera-camera2:1.3.0")
    implementation("androidx.camera:camera-lifecycle:1.3.0")
    implementation("androidx.camera:camera-view:1.3.0")

    // 其他必要的AndroidX库
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.activity:activity:1.8.0")

    // Oboe: 节拍器 C++ 实时音频
    implementation("com.google.oboe:oboe:1.10.0")
}
