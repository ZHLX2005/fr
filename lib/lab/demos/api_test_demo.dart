import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/design/emphasis_button.dart';
import '../lab_container.dart';
import 'api_test/api_download_manager.dart';
import 'api_test/api_speech_tab.dart';

/// API 测试 Demo
class ApiTestDemo extends DemoPage {
  @override
  String get title => 'API 测试';

  @override
  String get slug => 'api-test';

  @override
  String get description => '测试后端API接口';

  @override
  Widget buildPage(BuildContext context) {
    return const _ApiTestPage();
  }
}

class _ApiTestPage extends StatefulWidget {
  const _ApiTestPage();

  @override
  State<_ApiTestPage> createState() => _ApiTestPageState();
}

class _ApiTestPageState extends State<_ApiTestPage> {
  // APK 下载管理器
  final _apkManager = ApkDownloadManager();

  @override
  void initState() {
    super.initState();
    // 先 hydrate 状态（从 SP 读取已下载路径/开关/上次版本）
    _apkManager.loadSavedState().then((_) {
      // 若开关已开启，触发一次自动检查（与冷启动钩子互为安全网：
      // 两者都会执行，checkUpdate 内部幂等，不会重复下载）
      if (_apkManager.state.value.autoDownloadOnUpdate) {
        _apkManager.checkUpdate();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ===== APK 操作 =====
  Future<void> _checkApkUpdate() async {
    await _apkManager.checkUpdate();
  }

  Future<void> _downloadApkInternal() async {
    await _apkManager.startDownload();
  }

  Future<void> _pauseDownload() async {
    await _apkManager.pauseDownload();
  }

  Future<void> _resumeDownload() async {
    await _apkManager.resumeDownload();
  }

  Future<void> _cancelDownload() async {
    await _apkManager.cancelDownload();
  }

  Future<void> _downloadApkWithBrowser() async {
    const url = 'http://47.110.80.47:8988/files/by-key/fr_latest_apk';
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开浏览器失败: $e')));
      }
    }
  }

  Future<void> _openApk() async {
    final path = _apkManager.state.value.downloadedPath;
    if (path == null) return;
    try {
      final file = XFile(path);
      await Share.shareXFiles([file], text: 'FR APK 安装包');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开失败: $e')));
      }
    }
  }

  Future<void> _openApkInstall() async {
    final path = _apkManager.state.value.downloadedPath;
    if (path == null) return;

    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('APK 文件不存在')));
      }
      return;
    }

    try {
      final result = await OpenFilex.open(path);
      if (mounted) {
        if (result.type == ResultType.noAppToOpen) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('没有找到可安装的应用')));
        } else if (result.type != ResultType.done) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('唤起失败: ${result.message}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('唤起异常: $e')));
      }
    }
  }

  Future<void> _clearDownloadedApk() async {
    await _apkManager.clearDownloaded();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已清除下载记录')));
    }
  }

  /// 切换自动下载开关
  Future<void> _toggleAutoDownload(bool enabled) async {
    await _apkManager.setAutoDownloadEnabled(enabled);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? '已开启自动下载：启动 App 时自动检查新版本'
                : '已关闭自动下载',
          ),
        ),
      );
    }
  }

  /// 把 APK 上传时间格式化成"YYYY-MM-DD HH:MM"短串。空值返回占位符。
  String _fmtTime(String? s) {
    if (s == null || s.isEmpty) return '—';
    return s.length >= 16 ? s.substring(0, 16) : s;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 进度条下方的文字：百分比 + 已下载/总大小（若可知）
  String _buildProgressText(ApkDownloadState apkState) {
    final pct = (apkState.progress * 100).toStringAsFixed(1);
    if (apkState.totalBytes > 0) {
      final received = _formatFileSize(apkState.receivedBytes);
      final total = _formatFileSize(apkState.totalBytes);
      return '$pct%  ($received / $total)';
    }
    return '$pct%';
  }

  /// 边框强调式按钮样式：浅 tint + 描边 + 同色文字/icon，用功能色区分不同操作。
  /// color 为该操作的功能色（green=主操作/成功、blue=查询/接收、
  /// orange=暂停/警示、red=危险、indigo/teal/deepPurple=差异化操作）。
  ButtonStyle _outlinedBtnStyle(Color color) {
    return EmphasisButton.borderEmphasis(context, color: color);
  }

  // ===== Build =====
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
              ),
              child: Row(
                children: [
                  const Text(
                    'API 测试',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  ValueListenableBuilder<ApkDownloadState>(
                    valueListenable: _apkManager.state,
                    builder: (context, apkState, child) {
                      final isBusy = apkState.isCheckingUpdate;
                      if (!isBusy) return const SizedBox.shrink();
                      return const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Tab栏 - APK更新放在第一位
            const TabBar(
              tabs: [
                Tab(text: 'APK 更新'),
                Tab(text: '语音合成'),
              ],
            ),
            // Tab内容
            Expanded(
              child: TabBarView(
                children: [
                  // APK 更新
                  _buildApkTab(),
                  // 语音合成
                  const ApiSpeechTabPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- APK 更新 Tab ---
  Widget _buildApkTab() {
    return ValueListenableBuilder<ApkDownloadState>(
      valueListenable: _apkManager.state,
      builder: (context, apkState, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // APK 更新卡片
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.update, size: 32, color: Colors.blue),
                          SizedBox(width: 12),
                          Text(
                            'FR 最新版 APK',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // APK 信息
                      if (apkState.apkMetadata != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.grey.withValues(alpha: 0.35),
                                width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('文件大小: ${apkState.apkMetadata}'),
                              if (apkState.apkUpdateTime != null)
                                Text('上传时间: ${apkState.apkUpdateTime}'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // 自动下载设置 + 版本槽位
                      _buildAutoDownloadCard(apkState),
                      const SizedBox(height: 16),
                      // 状态信息
                      if (apkState.statusMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: apkState.statusMessage!.contains('完成')
                                ? Colors.green[50]
                                : Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            apkState.statusMessage!,
                            style: TextStyle(
                              color: apkState.statusMessage!.contains('完成')
                                  ? Colors.green[700]
                                  : Colors.blue[700],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // 下载进度条（下载中或已暂停都显示，便于查看续传进度）
                      if (apkState.isDownloading || apkState.isPaused) ...[
                        LinearProgressIndicator(value: apkState.progress),
                        const SizedBox(height: 8),
                        Text(
                          _buildProgressText(apkState),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                      ],
                      // 操作按钮
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed:
                                apkState.isCheckingUpdate ? null : _checkApkUpdate,
                            icon: apkState.isCheckingUpdate
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.indigo,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                            label: const Text('检查更新'),
                            style: _outlinedBtnStyle(Colors.indigo),
                          ),
                          OutlinedButton.icon(
                            onPressed: _downloadApkWithBrowser,
                            icon: const Icon(Icons.open_in_browser),
                            label: const Text('浏览器下载'),
                            style: _outlinedBtnStyle(Colors.deepPurple),
                          ),
                          // 三态主操作：内部下载 / 暂停 / 继续
                          if (apkState.isDownloading)
                            OutlinedButton.icon(
                              onPressed: _pauseDownload,
                              icon: const Icon(Icons.pause),
                              label: const Text('暂停'),
                              style: _outlinedBtnStyle(Colors.orange),
                            )
                          else if (apkState.isPaused)
                            OutlinedButton.icon(
                              onPressed: _resumeDownload,
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('继续下载'),
                              style: _outlinedBtnStyle(Colors.teal),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: _downloadApkInternal,
                              icon: const Icon(Icons.download_for_offline),
                              label: const Text('内部下载'),
                              style: _outlinedBtnStyle(Colors.blue),
                            ),
                          // 取消按钮：下载中或暂停时都可用
                          if (apkState.isDownloading || apkState.isPaused)
                            OutlinedButton.icon(
                              onPressed: _cancelDownload,
                              icon: const Icon(Icons.cancel),
                              label: const Text('取消'),
                              style: _outlinedBtnStyle(Colors.red),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // 已下载的 APK 文件卡片
                      if (apkState.downloadedPath != null) ...[
                        _buildApkFileCard(apkState),
                        const SizedBox(height: 12),
                      ],
                      // 下载地址信息
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.35),
                              width: 1.5),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '下载地址:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 4),
                            SelectableText(
                              'http://47.110.80.47:8988/files/by-key/fr_latest_apk',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                                fontFamily: 'monospace',
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Key: fr_latest_apk (覆盖更新) | 永不过期',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 安装说明
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 20, color: Colors.blue),
                          SizedBox(width: 8),
                          Text(
                            '安装步骤',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '1. 点击"内部下载"下载 APK\n'
                        '2. 下载完成后点击绿色卡片的"安装"按钮\n'
                        '3. 系统弹出应用选择面板，选择 APK 安装器\n'
                        '4. 如遇问题，点击"分享"按钮用其他方式打开',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 自动下载设置卡：Switch 切换开关 + 显示"已记录的最新上传时间"和"已见过的版本"
  Widget _buildAutoDownloadCard(ApkDownloadState apkState) {
    final isOn = apkState.autoDownloadOnUpdate;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isOn
            ? Colors.teal.withValues(alpha: 0.08)
            : Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOn
              ? Colors.teal.withValues(alpha: 0.45)
              : Colors.grey.withValues(alpha: 0.30),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部：Switch + 标题 + 说明
          Row(
            children: [
              Icon(
                isOn ? Icons.bolt : Icons.power_settings_new,
                size: 20,
                color: isOn ? Colors.teal : Colors.grey[600],
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '自动下载新版本',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              Switch(
                value: isOn,
                onChanged: apkState.isDownloading || apkState.isPaused
                    ? null
                    : _toggleAutoDownload,
                activeThumbColor: Colors.teal,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              isOn
                  ? '下次启动 App 时自动检查，发现新版本立即下载'
                  : '关闭后只在手动点击"检查更新"时触发',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 10),
          // 槽位：服务器最新上传时间（已记录）
          Row(
            children: [
              const Icon(Icons.schedule, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              const Text(
                '服务器最新版本',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.35),
                      width: 1),
                ),
                child: Text(
                  _fmtTime(apkState.apkUpdateTime),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 槽位：已下载/已见过的版本时间
          Row(
            children: [
              const Icon(Icons.history, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              const Text(
                '本地已处理版本',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: apkState.lastSeenUploadTime != null
                      ? Colors.green.withValues(alpha: 0.10)
                      : Colors.grey.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: apkState.lastSeenUploadTime != null
                        ? Colors.green.withValues(alpha: 0.35)
                        : Colors.grey.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Text(
                  apkState.lastSeenUploadTime != null
                      ? _fmtTime(apkState.lastSeenUploadTime)
                      : '尚未下载',
                  style: TextStyle(
                    fontSize: 12,
                    color: apkState.lastSeenUploadTime != null
                        ? Colors.green[700]
                        : Colors.grey[600],
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildApkFileCard(ApkDownloadState apkState) {
    final path = apkState.downloadedPath!;
    final name = path.split('/').last.split('\\').last;
    final sizeStr =
        apkState.downloadedSize != null
            ? _formatFileSize(apkState.downloadedSize!)
            : '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: Colors.green.withValues(alpha: 0.35), width: 1.5),
          ),
          child: const Icon(Icons.android, color: Colors.green),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$sizeStr\n$path',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: _openApkInstall,
              style: EmphasisButton.borderEmphasis(
                context,
                color: Colors.green,
              ),
              child: const Text('安装'),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _openApk,
              icon: const Icon(Icons.share),
              tooltip: '分享',
              color: Colors.blue,
            ),
            IconButton(
              onPressed: _clearDownloadedApk,
              icon: const Icon(Icons.delete_outline),
              tooltip: '清除',
              color: Colors.red,
            ),
          ],
        ),
      ),
    );
  }
}

void registerApiTestDemo() {
  demoRegistry.register(ApiTestDemo());
}
