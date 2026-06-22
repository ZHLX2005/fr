import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/api_client.dart';
import '../../../services/apk_download_service.dart';

/// APK 下载状态
class ApkDownloadState {
  final bool isCheckingUpdate;
  final bool isDownloading;
  final bool isPaused;
  final double progress;
  final int receivedBytes;
  final int totalBytes;
  final String? statusMessage;
  final String? apkMetadata;
  final String? apkUpdateTime;
  final String? downloadedPath;
  final int? downloadedSize;

  const ApkDownloadState({
    this.isCheckingUpdate = false,
    this.isDownloading = false,
    this.isPaused = false,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.statusMessage,
    this.apkMetadata,
    this.apkUpdateTime,
    this.downloadedPath,
    this.downloadedSize,
  });

  /// 是否处于"忙碌"状态（下载中或暂停中），用于在 UI 上保留进度条
  bool get hasProgress => isDownloading || isPaused;

  ApkDownloadState copyWith({
    bool? isCheckingUpdate,
    bool? isDownloading,
    bool? isPaused,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    String? statusMessage,
    String? apkMetadata,
    String? apkUpdateTime,
    String? downloadedPath,
    int? downloadedSize,
  }) {
    return ApkDownloadState(
      isCheckingUpdate: isCheckingUpdate ?? this.isCheckingUpdate,
      isDownloading: isDownloading ?? this.isDownloading,
      isPaused: isPaused ?? this.isPaused,
      progress: progress ?? this.progress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      statusMessage: statusMessage ?? this.statusMessage,
      apkMetadata: apkMetadata ?? this.apkMetadata,
      apkUpdateTime: apkUpdateTime ?? this.apkUpdateTime,
      downloadedPath: downloadedPath ?? this.downloadedPath,
      downloadedSize: downloadedSize ?? this.downloadedSize,
    );
  }
}

/// APK 下载管理器 - 全局单例，支持后台下载、主动暂停与续传
/// 页面离开后下载继续，再次进入可查看进度
class ApkDownloadManager {
  static final ApkDownloadManager _instance = ApkDownloadManager._internal();
  factory ApkDownloadManager() => _instance;
  ApkDownloadManager._internal();

  final ValueNotifier<ApkDownloadState> state =
      ValueNotifier(const ApkDownloadState());

  DownloadController? _downloadController;

  // 后台服务支持
  final ApkDownloadService _bgService = ApkDownloadService();
  StreamSubscription<Map<String, dynamic>?>? _bgSubscription;
  bool _bgMode = false;

  static const _kDownloadedApkPathKey = 'downloaded_apk_path';
  static const _kDownloadedApkSizeKey = 'downloaded_apk_size';
  static const _kApkMetadataKey = 'apk_metadata';
  static const _kApkUpdateTimeKey = 'apk_update_time';
  static const _kApkPausedTotalKey = 'apk_paused_total_bytes';

  /// 是否使用 Android Foreground Service 后台下载
  bool _useBgMode() => Platform.isAndroid;

  /// 监听后台 isolate 发来的数据（进度/暂停/完成/错误）
  void _initBgListener() {
    _bgSubscription?.cancel();
    _bgSubscription = _bgService.dataStream.listen((data) {
      if (data == null) return;
      final type = data['type'] as String?;

      switch (type) {
        case 'progress':
          state.value = state.value.copyWith(
            isDownloading: true,
            isPaused: false,
            progress: (data['progress'] as num?)?.toDouble() ?? 0.0,
            receivedBytes: (data['received'] as num?)?.toInt() ?? 0,
            totalBytes: (data['total'] as num?)?.toInt() ?? 0,
            statusMessage:
                '下载中: ${((data['progress'] as num?)?.toDouble() ?? 0) * 100}%',
          );
          break;
        case 'paused':
          state.value = state.value.copyWith(
            isDownloading: false,
            isPaused: true,
            statusMessage: '下载已暂停',
          );
          break;
        case 'cancelled':
          state.value = state.value.copyWith(
            isDownloading: false,
            isPaused: false,
            progress: 0.0,
            receivedBytes: 0,
            totalBytes: 0,
            statusMessage: '已取消下载',
          );
          break;
        case 'completed':
          final path = data['path'] as String?;
          final size = (data['size'] as num?)?.toInt();
          if (path != null && size != null) {
            _saveDownloadedApk(path, size);
            state.value = state.value.copyWith(
              isDownloading: false,
              isPaused: false,
              progress: 1.0,
              statusMessage: '下载完成',
              downloadedPath: path,
              downloadedSize: size,
            );
          }
          _bgService.stopService();
          break;
        case 'error':
          state.value = state.value.copyWith(
            isDownloading: false,
            isPaused: false,
            statusMessage: '下载出错: ${data['message'] ?? ""}',
          );
          _bgService.stopService();
          break;
      }
    });
  }

  /// 从本地加载已保存的状态：
  /// 1. 已下载完成的 APK（绿色卡片）
  /// 2. 后台服务正在下载中 → 同步进度
  /// 3. 已暂停未完成的下载（恢复 isPaused + 进度）
  Future<void> loadSavedState() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_kDownloadedApkPathKey);
    String? validPath;
    int? validSize;

    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        validPath = path;
        validSize = prefs.getInt(_kDownloadedApkSizeKey);
      }
    }

    state.value = state.value.copyWith(
      downloadedPath: validPath,
      downloadedSize: validSize,
      apkMetadata: prefs.getString(_kApkMetadataKey),
      apkUpdateTime: prefs.getString(_kApkUpdateTimeKey),
    );

    // Android + 临时文件存在 → 检测后台服务是否正在运行
    if (_useBgMode() && validPath == null) {
      _initBgListener();
      try {
        final running = await _bgService.isRunning();
        if (running) {
          // 后台服务仍在运行，下载进行中
          _bgMode = true;
          final tempInfo = await ApiService.getApkTempFileInfo();
          if (tempInfo != null) {
            final savedTotal = prefs.getInt(_kApkPausedTotalKey) ?? 0;
            state.value = state.value.copyWith(
              isDownloading: true,
              isPaused: false,
              receivedBytes: tempInfo.size,
              totalBytes: savedTotal > 0 ? savedTotal : tempInfo.size,
              progress: savedTotal > 0
                  ? (tempInfo.size / savedTotal).clamp(0.0, 1.0)
                  : 0.0,
              statusMessage: '正在恢复下载进度...',
            );
          } else {
            state.value = state.value.copyWith(
              isDownloading: true,
              statusMessage: '正在下载...',
            );
          }
          return;
        }
      } catch (_) {
        // isRunning 可能因为引擎刚启动而失败，忽略
      }
    }

    // 若没有已完成的 APK，检测是否存在被暂停的临时文件
    if (validPath == null) {
      final tempInfo = await ApiService.getApkTempFileInfo();
      if (tempInfo != null) {
        final savedTotal = prefs.getInt(_kApkPausedTotalKey) ?? 0;
        final progress =
            savedTotal > 0 ? tempInfo.size / savedTotal : 0.0;
        state.value = state.value.copyWith(
          isPaused: true,
          receivedBytes: tempInfo.size,
          totalBytes: savedTotal,
          progress: progress.clamp(0.0, 1.0),
          statusMessage: savedTotal > 0
              ? '已暂停 ${(progress * 100).toStringAsFixed(1)}% '
                  '(${_formatFileSize(tempInfo.size)} / '
                  '${_formatFileSize(savedTotal)})'
              : '已暂停 (${_formatFileSize(tempInfo.size)} 已下载)',
        );
      }
    }
  }

  /// 检查 APK 更新
  Future<void> checkUpdate() async {
    state.value = state.value.copyWith(
      isCheckingUpdate: true,
      statusMessage: '正在检查更新...',
    );

    final metadata = await ApiService.getApkMetadata();
    if (metadata != null) {
      final sizeStr = _formatFileSize(metadata.size ?? 0);
      final updateTime = metadata.uploadTime;
      final status = '发现新版本 (${updateTime?.substring(0, 10) ?? ""})';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kApkMetadataKey, sizeStr);
      await prefs.setString(_kApkUpdateTimeKey, updateTime ?? '');

      state.value = state.value.copyWith(
        isCheckingUpdate: false,
        apkMetadata: sizeStr,
        apkUpdateTime: updateTime,
        statusMessage: status,
      );
    } else {
      state.value = state.value.copyWith(
        isCheckingUpdate: false,
        statusMessage: '未找到APK或服务器错误',
      );
    }
  }

  /// 开始/继续下载 APK
  /// - Android: 通过 Foreground Service 后台下载，App 关闭后继续
  /// - 其他平台：Flutter 原生下载
  /// - 若存在临时文件，自动通过 HTTP Range 续传
  Future<void> startDownload() async {
    // Android → 使用 Foreground Service 后台下载
    if (_useBgMode()) {
      await _startBgDownload();
      return;
    }

    // 其他平台 → 使用现有 Flutter 原生下载
    if (state.value.isDownloading) return;

    final wasPaused = state.value.isPaused;
    state.value = state.value.copyWith(
      isDownloading: true,
      isPaused: false,
      statusMessage: wasPaused ? '继续下载...' : '开始下载...',
    );

    _downloadController = DownloadController();
    final controller = _downloadController!;

    try {
      final filePath = await ApiService.downloadApkToLocal(
        onProgress: (received, total) {
          if (controller.shouldStop) return;
          final progress = total > 0 ? received / total : 0.0;
          state.value = state.value.copyWith(
            progress: progress,
            receivedBytes: received,
            totalBytes: total,
            statusMessage: '下载中: ${(progress * 100).toStringAsFixed(1)}%',
          );
        },
        controller: controller,
      );

      // 优先识别"暂停"
      if (controller.isPaused) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_kApkPausedTotalKey, state.value.totalBytes);
        state.value = state.value.copyWith(
          isDownloading: false,
          isPaused: true,
          statusMessage:
              '已暂停 ${(state.value.progress * 100).toStringAsFixed(1)}%',
        );
        return;
      }

      // 取消
      if (controller.isCancelled) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kApkPausedTotalKey);
        state.value = state.value.copyWith(
          isDownloading: false,
          isPaused: false,
          progress: 0.0,
          receivedBytes: 0,
          totalBytes: 0,
          statusMessage: '已取消下载',
        );
        return;
      }

      // 正常完成
      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) {
          final size = await file.length();
          await _saveDownloadedApk(filePath, size);
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_kApkPausedTotalKey);
          state.value = state.value.copyWith(
            statusMessage: '下载完成',
            isDownloading: false,
            isPaused: false,
            downloadedPath: filePath,
            downloadedSize: size,
          );
        } else {
          state.value = state.value.copyWith(
            statusMessage: '文件访问出错，请重新下载',
            isDownloading: false,
            isPaused: false,
          );
        }
      } else {
        state.value = state.value.copyWith(
          statusMessage: '下载失败，请重试',
          isDownloading: false,
          isPaused: false,
        );
      }
    } catch (e) {
      state.value = state.value.copyWith(
        statusMessage: '下载出错: $e',
        isDownloading: false,
        isPaused: false,
      );
    } finally {
      _downloadController = null;
    }
  }

  /// Android Foreground Service 后台下载入口
  Future<void> _startBgDownload() async {
    if (state.value.isDownloading) return;

    final wasPaused = state.value.isPaused;
    state.value = state.value.copyWith(
      isDownloading: true,
      isPaused: false,
      statusMessage: wasPaused ? '继续下载...' : '开始下载...',
    );

    _initBgListener();
    _bgMode = true;

    try {
      await _bgService.startService();
      _bgService.sendCommand('start');
    } catch (e) {
      _bgMode = false;
      state.value = state.value.copyWith(
        statusMessage: '启动后台服务失败: $e',
        isDownloading: false,
        isPaused: false,
      );
    }
  }

  /// 主动暂停下载（保留已下载部分，下次可续传）
  Future<void> pauseDownload() async {
    if (_bgMode) {
      _bgService.sendCommand('pause');
      return;
    }
    if (_downloadController != null && state.value.isDownloading) {
      _downloadController!.pause();
    }
  }

  /// 继续下载（基于 HTTP Range 续传）
  Future<void> resumeDownload() async {
    if (state.value.isDownloading) return;
    await startDownload();
  }

  /// 取消下载（删除已下载的临时文件）
  /// - 下载中：通知 controller 或后台服务取消
  /// - 已暂停：直接清理 tempFile 与持久化状态
  Future<void> cancelDownload() async {
    if (_bgMode) {
      _bgService.sendCommand('cancel');
      // 后台 isolate 负责删除 tempFile
      return;
    }
    if (_downloadController != null) {
      _downloadController!.cancel();
      return;
    }
    if (state.value.isPaused) {
      await ApiService.clearApkTempFile();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kApkPausedTotalKey);
      state.value = state.value.copyWith(
        isPaused: false,
        progress: 0.0,
        receivedBytes: 0,
        totalBytes: 0,
        statusMessage: '已取消下载',
      );
    }
  }

  /// 清除已下载的 APK
  Future<void> clearDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDownloadedApkPathKey);
    await prefs.remove(_kDownloadedApkSizeKey);

    if (state.value.downloadedPath != null) {
      try {
        final file = File(state.value.downloadedPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    state.value = state.value.copyWith(
      downloadedPath: null,
      downloadedSize: null,
    );
  }

  Future<void> _saveDownloadedApk(String path, int size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDownloadedApkPathKey, path);
    await prefs.setInt(_kDownloadedApkSizeKey, size);
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
