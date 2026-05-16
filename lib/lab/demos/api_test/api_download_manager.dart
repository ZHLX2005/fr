import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/api_client.dart';

/// APK 下载状态
class ApkDownloadState {
  final bool isCheckingUpdate;
  final bool isDownloading;
  final double progress;
  final String? statusMessage;
  final String? apkMetadata;
  final String? apkUpdateTime;
  final String? downloadedPath;
  final int? downloadedSize;

  const ApkDownloadState({
    this.isCheckingUpdate = false,
    this.isDownloading = false,
    this.progress = 0.0,
    this.statusMessage,
    this.apkMetadata,
    this.apkUpdateTime,
    this.downloadedPath,
    this.downloadedSize,
  });

  ApkDownloadState copyWith({
    bool? isCheckingUpdate,
    bool? isDownloading,
    double? progress,
    String? statusMessage,
    String? apkMetadata,
    String? apkUpdateTime,
    String? downloadedPath,
    int? downloadedSize,
  }) {
    return ApkDownloadState(
      isCheckingUpdate: isCheckingUpdate ?? this.isCheckingUpdate,
      isDownloading: isDownloading ?? this.isDownloading,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      apkMetadata: apkMetadata ?? this.apkMetadata,
      apkUpdateTime: apkUpdateTime ?? this.apkUpdateTime,
      downloadedPath: downloadedPath ?? this.downloadedPath,
      downloadedSize: downloadedSize ?? this.downloadedSize,
    );
  }
}

/// APK 下载管理器 - 全局单例，支持后台下载
/// 页面离开后下载继续，再次进入可查看进度
class ApkDownloadManager {
  static final ApkDownloadManager _instance = ApkDownloadManager._internal();
  factory ApkDownloadManager() => _instance;
  ApkDownloadManager._internal();

  final ValueNotifier<ApkDownloadState> state =
      ValueNotifier(const ApkDownloadState());

  DownloadController? _downloadController;

  static const _kDownloadedApkPathKey = 'downloaded_apk_path';
  static const _kDownloadedApkSizeKey = 'downloaded_apk_size';
  static const _kApkMetadataKey = 'apk_metadata';
  static const _kApkUpdateTimeKey = 'apk_update_time';

  /// 从本地加载已保存的状态
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

  /// 开始下载 APK
  Future<void> startDownload() async {
    if (state.value.isDownloading) return;

    state.value = state.value.copyWith(
      isDownloading: true,
      progress: 0.0,
      statusMessage: '开始下载...',
    );

    _downloadController = DownloadController();

    try {
      final filePath = await ApiService.downloadApkToLocal(
        onProgress: (received, total) {
          if (total > 0 &&
              _downloadController != null &&
              !_downloadController!.isCancelled) {
            final progress = received / total;
            state.value = state.value.copyWith(
              progress: progress,
              statusMessage: '下载中: ${(progress * 100).toStringAsFixed(1)}%',
            );
          }
        },
        controller: _downloadController,
      );

      if (_downloadController != null && _downloadController!.isCancelled) {
        state.value = state.value.copyWith(
          statusMessage: '已取消下载',
          isDownloading: false,
        );
        return;
      }

      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) {
          final size = await file.length();
          await _saveDownloadedApk(filePath, size);
          state.value = state.value.copyWith(
            statusMessage: '下载完成',
            isDownloading: false,
            downloadedPath: filePath,
            downloadedSize: size,
          );
        } else {
          state.value = state.value.copyWith(
            statusMessage: '文件访问出错，请重新下载',
            isDownloading: false,
          );
        }
      } else {
        state.value = state.value.copyWith(
          statusMessage: '下载失败，请重试',
          isDownloading: false,
        );
      }
    } catch (e) {
      state.value = state.value.copyWith(
        statusMessage: '下载出错: $e',
        isDownloading: false,
      );
    } finally {
      _downloadController = null;
    }
  }

  /// 取消下载
  Future<void> cancelDownload() async {
    if (_downloadController != null) {
      _downloadController!.cancel();
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
