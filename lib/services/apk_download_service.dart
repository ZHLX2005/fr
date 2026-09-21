/// APK 下载后台 Foreground Service
///
/// 使用 flutter_background_service 在独立 Dart isolate 中运行下载，
/// 通过 Android Foreground Service 保活进程，App 关闭后下载不被中断。
///
/// 架构：
///   ┌─ 主 isolate ────────────────────────┐
///   │  ApkDownloadService (singleton)      │
///   │   - startService / stopService       │
///   │   - sendCommand (→ bg)              │
///   │   - dataStream (来自 bg)            │
///   └──────┬───────────────────────────────┘
///          │ invoke / on
///   ┌──────▼───────────────────────────────┐
///   │ 背景 isolate                         │
///   │  apkDownloadServiceHandler          │
///   │   - HTTP 流式下载                    │
///   │   - setForegroundNotificationInfo   │
///   │   - invoke('data', ...) → main      │
///   └──────────────────────────────────────┘
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// ═══════════════════════════════════════════════════════
// 主 isolate 端 — 后台服务控制器
// ═══════════════════════════════════════════════════════

/// APK 下载后台 Foreground Service 控制器
///
/// 在主 isolate 中使用，负责启动/停止服务、发送指令、接收进度。
class ApkDownloadService {
  ApkDownloadService._();
  static final ApkDownloadService _instance = ApkDownloadService._();
  factory ApkDownloadService() => _instance;

  bool _initialized = false;

  /// 初始化后台服务（仅一次）
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: apkDownloadServiceHandler,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        initialNotificationTitle: 'APK 下载',
        initialNotificationContent: '准备下载...',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: (_) {},
        onBackground: _onIosBackground,
      ),
    );
  }

  /// 启动 Foreground Service
  Future<void> startService() async {
    await initialize();
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
    }
  }

  /// 停止 Foreground Service
  void stopService() {
    FlutterBackgroundService().invoke('download_command', {'action': 'stop'});
  }

  /// 向后台 isolate 发送下载控制指令
  void sendCommand(String action, {Map<String, dynamic>? data}) {
    FlutterBackgroundService().invoke(
      'download_command',
      {'action': action, if (data != null) ...data},
    );
  }

  /// 接收后台 isolate 发来的数据（进度/状态）
  Stream<Map<String, dynamic>?> get dataStream =>
      FlutterBackgroundService().on('data');

  /// 是否正在运行
  Future<bool> isRunning() => FlutterBackgroundService().isRunning();

  @pragma('vm:entry-point')
  static bool _onIosBackground(ServiceInstance service) {
    return true;
  }
}

// ═══════════════════════════════════════════════════════
// 后台 isolate 端 — 下载逻辑
// ═══════════════════════════════════════════════════════

/// 后台 isolate 中的下载控制标志
///
/// 与 api_client.dart / download_controller.dart 中的
/// DownloadController 功能相同，但作为全局变量存在于后台 isolate。
class _BgController {
  bool cancelled = false;
  bool paused = false;
  bool get shouldStop => cancelled || paused;
  void cancel() => cancelled = true;
  void pause() => paused = true;
  void reset() {
    cancelled = false;
    paused = false;
  }
}

_BackgroundState? _bgState;

/// 后台 isolate 中持有下载状态和引用
class _BackgroundState {
  final _BgController controller = _BgController();
}

/// 终态兜底：正常情况下主 isolate 收到 'completed'/'error'/'cancelled' 后会自己
/// 调 `stopService()`，但主 isolate 可能已经死了，没人收尾 —— 那样前台服务
/// 和常驻通知会一直挂着，被系统记成后台耗电。
///
/// 稍等一会儿再退场，让上面的 `invoke` 先送达（重复 `stopSelf()` 是幂等的）。
void _stopSelfSoon(AndroidServiceInstance service) {
  Future.delayed(const Duration(seconds: 2), () {
    try {
      service.stopSelf();
    } catch (_) {
      // ignore: 服务可能已被主 isolate 停掉
    }
  });
}

/// 后台 isolate 入口函数（必须为顶级或静态函数）
@pragma('vm:entry-point')
void apkDownloadServiceHandler(ServiceInstance service) {
  if (service is! AndroidServiceInstance) return;

  _bgState = _BackgroundState();

  // 看门狗：服务可能被系统以 START_STICKY 重启，而重启后这里只会注册监听、
  // 不会自动开始下载 —— 不退场就是一个挂着通知空转的前台服务。
  // 60s 内没收到任何指令就自行了断。
  Timer? startupWatchdog = Timer(const Duration(seconds: 60), () {
    service.stopSelf();
  });

  // 暂停后若用户不再恢复，不该无限期占着前台服务。
  Timer? pauseWatchdog;

  service.on('download_command').listen((event) async {
    final action = event?['action'] as String?;
    final ctrl = _bgState!.controller;

    // 收到任何指令都说明服务确实在被使用，撤掉两个看门狗（各自按需重设）
    startupWatchdog?.cancel();
    startupWatchdog = null;
    pauseWatchdog?.cancel();
    pauseWatchdog = null;

    switch (action) {
      case 'start':
        ctrl.reset();
        await _runDownload(service, ctrl);
      case 'pause':
        ctrl.pause();
        await service.setForegroundNotificationInfo(
          title: 'APK 下载',
          content: '下载已暂停',
        );
        service.invoke('data', {'type': 'paused'});
        pauseWatchdog = Timer(
          const Duration(minutes: 30),
          () => service.stopSelf(),
        );
      case 'cancel':
        ctrl.cancel();
      case 'stop':
        await service.stopSelf();
    }
  });
}

/// 后台 isolate 中的实际下载逻辑
Future<void> _runDownload(
  AndroidServiceInstance service,
  _BgController ctrl,
) async {
  const fileKey = 'fr_latest_apk';
  const url = 'http://47.110.80.47:8988/files/by-key/$fileKey';

  try {
    final dir = await getApplicationDocumentsDirectory();
    final tempFile = File('${dir.path}/download_$fileKey.tmp');
    final outputFile = File('${dir.path}/$fileKey.apk');

    // 续传: 检查已下载的临时文件
    int existingLength = 0;
    if (await tempFile.exists()) existingLength = await tempFile.length();

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      if (existingLength > 0) {
        request.headers['Range'] = 'bytes=$existingLength-';
      }
      final streamedResponse = await client.send(request);
      if (streamedResponse.statusCode != 200 &&
          streamedResponse.statusCode != 206) {
        service.invoke('data', {
          'type': 'error',
          'message': '服务器返回 ${streamedResponse.statusCode}',
        });
        _stopSelfSoon(service);
        return;
      }

      // 计算总大小
      int totalSize = existingLength;
      final contentLength = streamedResponse.headers['content-length'];
      if (contentLength != null && contentLength.isNotEmpty) {
        totalSize = existingLength + int.parse(contentLength);
      } else {
        final contentRange = streamedResponse.headers['content-range'];
        if (contentRange != null) {
          final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
          if (match != null) totalSize = int.parse(match.group(1)!);
        }
      }

      // 边收边写
      final raf = await tempFile.open(
        mode: existingLength > 0 ? FileMode.append : FileMode.write,
      );
      int received = existingLength;
      int lastNotifyPercent = -1; // 防频繁刷新通知

      await for (final chunk in streamedResponse.stream) {
        if (ctrl.cancelled) {
          await raf.close();
          if (await tempFile.exists()) await tempFile.delete();
          await service.setForegroundNotificationInfo(
            title: 'APK 下载',
            content: '下载已取消',
          );
          service.invoke('data', {'type': 'cancelled'});
          // 取消是终态：必须退场，否则前台服务 + 常驻通知永不消失
          _stopSelfSoon(service);
          return;
        }

        if (ctrl.paused) {
          await raf.close();
          service.invoke('data', {'type': 'paused'});
          return; // 保留 tempFile，等待续传
        }

        await raf.writeFrom(chunk);
        received += chunk.length;

        if (totalSize > 0) {
          final progress = received / totalSize;
          final percent = (progress * 100).toInt();

          // 每 5% 或首次/最后 1% 才刷新通知，减少 bat 写入
          if (percent - lastNotifyPercent >= 5 ||
              percent >= 99 ||
              received <= existingLength + 4096) {
            lastNotifyPercent = percent;
            await service.setForegroundNotificationInfo(
              title: 'APK 下载',
              content: '$percent%  (${_fmtSize(received)} / ${_fmtSize(totalSize)})',
            );
          }

          service.invoke('data', {
            'type': 'progress',
            'progress': progress,
            'received': received,
            'total': totalSize,
          });
        }
      }
      await raf.close();

      // 下载完成 → 重命名为正式文件
      if (await tempFile.exists()) {
        if (await outputFile.exists()) await outputFile.delete();
        final bytes = await tempFile.readAsBytes();
        await outputFile.writeAsBytes(bytes);
        await tempFile.delete();
      }

      if (await outputFile.exists()) {
        final size = await outputFile.length();
        await service.setForegroundNotificationInfo(
          title: 'APK 下载',
          content: '下载完成',
        );
        service.invoke('data', {
          'type': 'completed',
          'path': outputFile.path,
          'size': size,
        });
      } else {
        service.invoke('data', {
          'type': 'error',
          'message': '文件保存失败',
        });
      }
      // 下载流程结束（成功或失败）都是终态：退场，不留空转的前台服务
      _stopSelfSoon(service);
    } finally {
      client.close();
    }
  } catch (e) {
    service.invoke('data', {
      'type': 'error',
      'message': '$e',
    });
    _stopSelfSoon(service);
  }
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
