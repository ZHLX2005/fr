// 构建变体常量 —— 同一份代码产出两个可并存安装的 app（小豆子 / 微豆子）。
//
// CI（build-apk-v2.yml 的 app=weidouzi 链）通过 `--dart-define=APP_VARIANT=weidouzi`
// 注入；默认构建不带该 define，全部取小豆子值，行为与历史版本完全一致。
// Gradle 侧的对应开关是 android/gradle.properties 的 `appVariant=weidouzi`
// （CI 构建时临时追加，不提交），映射见 android/app/build.gradle.kts 顶部。
//
// 桌面名 / 小组件 label 走 Android manifestPlaceholders（build.gradle.kts），
// 这里只管应用内文案与更新源。

/// 当前构建变体：xiaodouzi（小豆子，默认）| weidouzi（微豆子）
const String kAppVariant = String.fromEnvironment(
  'APP_VARIANT',
  defaultValue: 'xiaodouzi',
);

/// 是否微豆子变体（独立签名 / 包名 io.github.xiaodouzi.fr.wdz / 独立更新源）
const bool kIsWeidouzi = kAppVariant == 'weidouzi';

/// 应用显示名 —— MaterialApp.title、profile 页、分享提示等应用内文案
const String kAppDisplayName = kIsWeidouzi ? '微豆子' : '小豆子';

/// APK 更新源 file key —— 微豆子必须独立于 fr_latest_apk：
/// 包名+签名不同，下到小豆子的包无法覆盖安装。
const String kApkFileKey = kIsWeidouzi ? 'wdz_latest_apk' : 'fr_latest_apk';

/// 文件服务器 by-key 直链（浏览器下载 / 页面展示用）
const String kApkByNameUrl =
    'http://47.110.80.47:8988/files/by-key/$kApkFileKey';
