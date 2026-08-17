// APK 自动下载启动期钩子 —— 在 main() 中 fire-and-forget 调用，
// 不阻塞冷启动同步链。结果通过 ApkDownloadManager.state 流回 UI。
//
// 流程:
//   1) ApkDownloadManager().loadSavedState() — 从 SharedPreferences 读取
//      lastSeenUploadTime / autoDownloadOnUpdate
//   2) autoCheckAndDownloadOnStartup() — 开关开启时调 checkUpdate()，
//      与 lastSeenUploadTime 比对；不同则自动调 startDownload()。
//
// 调试日志：每步都有 print，便于定位"自动检查没生效"类问题。

import 'package:flutter/foundation.dart';
import '../lab/demos/api_test/api_download_manager.dart';

/// APK 自动下载启动期检查（fire-and-forget，不阻塞 main）
Future<void> runApkAutoDownloadOnStartup() async {
  try {
    final mgr = ApkDownloadManager();
    // ignore: avoid_print
    print('[apk-auto] 1/3 loadSavedState begin');
    await mgr.loadSavedState();
    final enabled = mgr.state.value.autoDownloadOnUpdate;
    // ignore: avoid_print
    print('[apk-auto] 2/3 loadSavedState done, autoDownloadOnUpdate=$enabled');
    await mgr.autoCheckAndDownloadOnStartup();
    // ignore: avoid_print
    print('[apk-auto] 3/3 autoCheckAndDownloadOnStartup done');
  } catch (e, st) {
    // 不再静默：记录到 debugPrint 便于排查
    debugPrint('[apk-auto] startup hook FAILED: $e\n$st');
  }
}