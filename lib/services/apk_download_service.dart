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
  // 供暂停/取消通知展示最后一次进度使用
  double lastProgress = 0.0;
  int lastReceived = 0;
  int lastTotal = 0;
}

/// 后台 isolate 入口函数（必须为顶级或静态函数）
@pragma('vm:entry-point')
void apkDownloadServiceHandler(ServiceInstance service) {
  if (service is! AndroidServiceInstance) return;

  _bgState = _BackgroundState();

  service.on('download_command').listen((event) async {
    final action = event?['action'] as String?;
    final ctrl = _bgState!.controller;

    switch (action) {
      case 'start':
        ctrl.reset();
        await _runDownload(service, ctrl);
      case 'pause':
        ctrl.pause();
        final s = _bgState!;
        final p = s.lastProgress;
        final pInt = (p * 100).toInt();
        await service.setForegroundNotificationInfo(
          title: 'APK 下载',
          content: '已暂停  $pInt%  ${_fmtBar(p)}  '
              '${_fmtSize(s.lastReceived)} / ${_fmtSize(s.lastTotal)}',
        );
        service.invoke('data', {'type': 'paused'});
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
  const url = 'http://47.110.80.47:8988/api/v1/file/$fileKey';

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
            content: '下载已取消  ░░░░░░░░░░ 0%',
          );
          service.invoke('data', {'type': 'cancelled'});
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

          // 同步最后一次进度，供暂停/取消通知使用
          final bg = _bgState!;
          bg.lastProgress = progress;
          bg.lastReceived = received;
          bg.lastTotal = totalSize;

          // 每 5% 或首次/最后 1% 才刷新通知，减少 bat 写入
          if (percent - lastNotifyPercent >= 5 ||
              percent >= 99 ||
              received <= existingLength + 4096) {
            lastNotifyPercent = percent;
            await service.setForegroundNotificationInfo(
              title: 'APK 下载',
              content: '$percent%  ${_fmtBar(progress)}  '
                  '${_fmtSize(received)} / ${_fmtSize(totalSize)}',
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
          content: '下载完成  ██████████ 100%  ${_fmtSize(size)}',
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
    } finally {
      client.close();
    }
  } catch (e) {
    service.invoke('data', {
      'type': 'error',
      'message': '$e',
    });
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

/// 把 0~1 的进度渲染成 10 格 Unicode 简易进度条
/// 例: 0.34 → "███▌       "（全角字符在 Android 系统字体中均能正常渲染）
String _fmtBar(double p) {
  final clamped = p.clamp(0.0, 1.0);
  final filled = (clamped * 10).round(); // 0..10
  return '█' * filled + '░' * (10 - filled);
}
