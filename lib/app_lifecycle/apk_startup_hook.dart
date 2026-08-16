// APK 自动下载启动期钩子 —— 在 main() 中 fire-and-forget 调用，
// 不阻塞冷启动同步链。结果通过 ApkDownloadManager.state 流回 UI。
//
// 流程:
//   1) ApkDownloadManager().loadSavedState() — 从 SharedPreferences 读取
//      lastSeenUploadTime / autoDownloadOnUpdate
//   2) autoCheckAndDownloadOnStartup() — 开关开启时调 checkUpdate()，
//      与 lastSeenUploadTime 比对；不同则自动调 startDownload()。
//
// 失败被 catch（无网/服务器异常都不应阻塞启动）。

import '../lab/demos/api_test/api_download_manager.dart';

/// APK 自动下载启动期检查（fire-and-forget，不阻塞 main）
Future<void> runApkAutoDownloadOnStartup() async {
  try {
    final mgr = ApkDownloadManager();
    await mgr.loadSavedState();
    await mgr.autoCheckAndDownloadOnStartup();
  } catch (_) {
    // 启动期检查静默失败，不抛、不日志阻塞
  }
}