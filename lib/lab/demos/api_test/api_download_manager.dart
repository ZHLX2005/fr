import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/ai_chat/system_messages/system_events_controller.dart';
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

  /// 是否启用"自动下载新版本"（持久化到 SharedPreferences）
  final bool autoDownloadOnUpdate;

  /// 最近一次"已成功下载/已见过"的服务器上传时间（UTC ISO 串）。
  /// 与 [apkUpdateTime] 的区别：apkUpdateTime 是服务器最新值（每次 checkUpdate 刷新），
  /// lastSeenUploadTime 是"已经处理过"的值，用于判断是否需要再次触发自动下载。
  final String? lastSeenUploadTime;

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
    this.autoDownloadOnUpdate = false,
    this.lastSeenUploadTime,
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
    bool? autoDownloadOnUpdate,
    String? lastSeenUploadTime,
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
      autoDownloadOnUpdate: autoDownloadOnUpdate ?? this.autoDownloadOnUpdate,
      lastSeenUploadTime: lastSeenUploadTime ?? this.lastSeenUploadTime,
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

  /// 自动下载开关：true → 应用启动时自动 checkUpdate，发现新版本自动下载
  static const _kAutoDownloadEnabledKey = 'apk_auto_download_enabled';

  /// 已成功下载/已见过的服务器上传时间（UTC ISO 串）。用于和下次 checkUpdate
  /// 的 apkUpdateTime 比较，若不同则触发自动下载。
  static const _kLastSeenUploadTimeKey = 'apk_last_seen_upload_time';

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
                '下载中: ${(((data['progress'] as num?)?.toDouble() ?? 0.0) * 100).toStringAsFixed(1)}%',
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
            _markLatestVersionSeen();
            state.value = state.value.copyWith(
              isDownloading: false,
              isPaused: false,
              progress: 1.0,
              statusMessage: '下载完成',
              downloadedPath: path,
              downloadedSize: size,
            );
            _emitSystemEvent(
              eventType: 'auto_apk_download_completed',
              title: 'APK 自动下载完成',
              detail:
                  '文件大小：${_formatFileSize(size)}\n路径：${path.split('/').last}',
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
          _emitSystemEvent(
            eventType: 'auto_apk_download_failed',
            title: '后台下载失败',
            detail: '${data['message'] ?? "未知错误"}',
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
      // 持久化的是 UTC 串，读回时同样要转本地时区，否则重启后仍差 8 小时。
      apkUpdateTime: _formatLocalTime(prefs.getString(_kApkUpdateTimeKey)),
      autoDownloadOnUpdate: prefs.getBool(_kAutoDownloadEnabledKey) ?? false,
      // 与 apkUpdateTime 同源：SP 存 UTC 串，读回必须转本地，否则重启后差 8h
      lastSeenUploadTime:
          _formatLocalTime(prefs.getString(_kLastSeenUploadTimeKey)),
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
  ///
  /// 额外职责：若 [ApkDownloadState.autoDownloadOnUpdate] = true 且服务器
  /// uploadTime 与 [ApkDownloadState.lastSeenUploadTime] 不同，会自动调用
  /// [startDownload] 启动下载，无需用户手动操作。下载完成后由
  /// `_markLatestVersionSeen()` 记录已见版本。
  Future<void> checkUpdate() async {
    state.value = state.value.copyWith(
      isCheckingUpdate: true,
      statusMessage: '正在检查更新...',
    );

    final metadata = await ApiService.getApkMetadata();
    if (metadata != null) {
      final sizeStr = _formatFileSize(metadata.size ?? 0);
      final updateTime = metadata.uploadTime;
      // uploadTime 是统一 UTC ISO 串（如 "2026-08-03T14:29:40.000Z"），
      // 直接截串会固定显示 UTC 时间，导致本地时区（+08:00）差 8 小时。
      // 先转设备本地时区再截取。
      final timeStr = _formatLocalTime(updateTime);
      final dateStr = timeStr.length >= 10 ? timeStr.substring(0, 10) : '';
      final status = '发现新版本 ($dateStr)';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kApkMetadataKey, sizeStr);
      await prefs.setString(_kApkUpdateTimeKey, updateTime ?? '');

      state.value = state.value.copyWith(
        isCheckingUpdate: false,
        apkMetadata: sizeStr,
        apkUpdateTime: timeStr.isNotEmpty ? timeStr : updateTime,
        statusMessage: status,
      );

      // 自动下载：开关开启 + 还没有下载过这个版本 + 当前没有正在进行的下载
      // 注意：updateTime 是服务器返回的原始 UTC 串（如 "2026-08-16T14:29:40.000Z"），
      // state.lastSeenUploadTime 是转过本地时区的显示用串，格式不同无法直接比较。
      // 所以从 SP 读原始 UTC 串做版本比对。
      // 不再检查 downloadedPath == null：若用户已有旧版 APK 但服务器有新版本，
      // 仍应自动下载（旧版会被覆盖）。
      final rawLastSeenUtc = prefs.getString(_kLastSeenUploadTimeKey) ?? '';
      final s = state.value;
      final shouldAuto = s.autoDownloadOnUpdate &&
          updateTime != null &&
          updateTime.isNotEmpty &&
          updateTime != rawLastSeenUtc &&
          !s.isDownloading &&
          !s.isPaused;
      // ignore: avoid_print
      print(
        '[apk-auto] shouldAuto=$shouldAuto | server=$updateTime | '
        'lastSeen=$rawLastSeenUtc | isDownloading=${s.isDownloading} | '
        'isPaused=${s.isPaused} | downloadedPath=${s.downloadedPath != null ? "YES" : "NO"}',
      );
      if (shouldAuto) {
        _emitSystemEvent(
          eventType: 'auto_apk_download_started',
          title: '检测到新版本，启动自动下载',
          detail: '服务器上传时间：${_formatLocalTime(updateTime)}',
        );
        // 不 await：让 UI 立即恢复，避免阻塞 checkUpdate 的状态更新
        unawaited(startDownload());
      } else if (s.autoDownloadOnUpdate &&
          updateTime != null &&
          updateTime == rawLastSeenUtc) {
        // 开关开启但版本号没变 → 显式记录一条"已是最新"
        _emitSystemEvent(
          eventType: 'auto_apk_check_no_update',
          title: '已是最新版本',
          detail: '上次下载版本：${_formatLocalTime(updateTime)}',
        );
      } else if (s.autoDownloadOnUpdate) {
        // 开关开启、版本不一致、但不满足 shouldAuto（如正在暂停中）
        // 记录一条信息，避免用户以为自动检查没工作
        _emitSystemEvent(
          eventType: 'auto_apk_check_started',
          title: '检查完成，暂未触发下载',
          detail:
              'server=$updateTime\nlastSeen=$rawLastSeenUtc\n'
              'isDownloading=${s.isDownloading} isPaused=${s.isPaused}',
        );
      }
    } else {
      state.value = state.value.copyWith(
        isCheckingUpdate: false,
        statusMessage: '未找到APK或服务器错误',
      );
      if (state.value.autoDownloadOnUpdate) {
        _emitSystemEvent(
          eventType: 'auto_apk_download_failed',
          title: '检查更新失败',
          detail: '服务器未返回 APK 元数据',
        );
      }
    }
  }

  /// 自动检查入口 —— 冷启动、App 回前台、进入 Demo 页时统一调用。
  ///
  /// 业界标准 auto-check 模式（本项目实现）：
  /// 1. 双触发点：main() 冷启动 + WidgetsBindingObserver.resumed 回前台
  /// 2. 节流：[_kAutoCheckMinInterval] 内不重复发请求（防频繁切前后台打爆服务器）
  /// 3. 单点决策：**是否下载只由 [checkUpdate] 内部的 shouldAuto 决定**，
  ///    本方法不做版本判断——之前入口层重复判断 downloadedPath 导致
  ///    有旧 APK 时永远不触发 checkUpdate 的 bug 就是这么来的。
  /// 4. fire-and-forget + 静默失败：异常只发系统消息，不抛给调用方
  DateTime _lastAutoCheckAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _kAutoCheckMinInterval = Duration(minutes: 15);

  Future<void> maybeAutoCheck({bool force = false}) async {
    if (!state.value.autoDownloadOnUpdate) return;
    // 节流：force=true（冷启动/手动开关）跳过
    final now = DateTime.now();
    if (!force && now.difference(_lastAutoCheckAt) < _kAutoCheckMinInterval) {
      return;
    }
    _lastAutoCheckAt = now;
    // 并发保护：正在下载/暂停中不做检查（暂停中的 temp 文件走 Range 续传，
    // 换版本会拼接出损坏 APK）
    if (state.value.isDownloading || state.value.isPaused) return;

    _emitSystemEvent(
      eventType: 'auto_apk_check_started',
      title: '自动检查 APK 更新',
      detail: '开关已开启，正在请求服务器元数据…',
    );
    try {
      await checkUpdate();
    } catch (e) {
      _emitSystemEvent(
        eventType: 'auto_apk_download_failed',
        title: '自动检查失败',
        detail: '$e',
      );
    }
  }

  /// 兼容旧启动钩子的入口（apk_startup_hook.dart 调用）。
  /// 冷启动时 throttle 一定是过期的（单例新建），等价 force=true。
  Future<void> autoCheckAndDownloadOnStartup() => maybeAutoCheck(force: true);

  /// 设置自动下载开关（持久化）。
  ///
  /// 若用户在当前会话开启开关，立即触发一次 checkUpdate（无需等到下次冷启动）。
  /// checkUpdate 内部的 shouldAuto 逻辑会自动判断是否需要启动下载。
  Future<void> setAutoDownloadEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoDownloadEnabledKey, enabled);
    state.value = state.value.copyWith(autoDownloadOnUpdate: enabled);

    // 立即触发一次检查，不等下次冷启动
    if (enabled) {
      emitSystemMessage(
        eventType: 'auto_apk_check_started',
        title: '已开启自动下载',
        detail: '正在检查服务器是否有新版本…',
      );
      unawaited(checkUpdate());
    }
  }

  /// 把当前服务器 uploadTime 标记为"已见过"。
  /// - bgService 'completed' 回调中调用（成功路径）
  /// - 原生下载成功后调用（成功路径）
  /// 不在 checkUpdate 中调用：checkUpdate 只是发现版本，下载成功才是真正"处理过"
  Future<void> _markLatestVersionSeen() async {
    final uploadTime = state.value.apkUpdateTime;
    // 注意：state.apkUpdateTime 已经是本地化字符串，不能直接当 key 使用，
    // 所以用 SharedPreferences 里持久化的 UTC 串（_kApkUpdateTimeKey）。
    final prefs = await SharedPreferences.getInstance();
    final utc = prefs.getString(_kApkUpdateTimeKey);
    if (utc == null || utc.isEmpty) return;
    await prefs.setString(_kLastSeenUploadTimeKey, utc);
    state.value = state.value.copyWith(
      lastSeenUploadTime: _formatLocalTime(utc),
    );
    // uploadTime 仅用于抑制 lint
    assert(uploadTime != null);
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
          await _markLatestVersionSeen();
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_kApkPausedTotalKey);
          state.value = state.value.copyWith(
            statusMessage: '下载完成',
            isDownloading: false,
            isPaused: false,
            downloadedPath: filePath,
            downloadedSize: size,
          );
          if (state.value.autoDownloadOnUpdate) {
            _emitSystemEvent(
              eventType: 'auto_apk_download_completed',
              title: 'APK 自动下载完成',
              detail: '文件大小：${_formatFileSize(size)}',
            );
          }
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
      if (state.value.autoDownloadOnUpdate) {
        _emitSystemEvent(
          eventType: 'auto_apk_download_failed',
          title: '下载异常',
          detail: '$e',
        );
      }
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

  /// 把统一 UTC ISO 串（"2026-08-03T14:29:40.000Z"）转为设备本地时区的
  /// 可读时间串（"2026-08-03T22:29"）。空值返回空串，解析失败原样返回。
  String _formatLocalTime(String? utcTime) {
    if (utcTime == null || utcTime.isEmpty) return '';
    final utc = DateTime.tryParse(utcTime);
    if (utc == null) return utcTime;
    final local = utc.toLocal().toIso8601String();
    return local.length >= 16 ? local.substring(0, 16) : local;
  }

  /// 统一事件发射：减少重复样板。任何后台事件都走这里。
  /// 实际工作交给 `emitSystemMessage()`（lib/core/ai_chat/system_messages/），
  /// 这里只是个 thin wrapper 保持类内调用风格不变。
  void _emitSystemEvent({
    required String eventType,
    required String title,
    String? detail,
  }) {
    emitSystemMessage(
      eventType: eventType,
      title: title,
      detail: detail,
    );
  }
}
