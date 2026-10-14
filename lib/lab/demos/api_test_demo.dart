import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api/api_config.dart';
import '../../api/goframe/download/apk_endpoint.dart';
import '../../api/goframe/download/download_controller.dart';
import '../../core/const_app_variant.dart';
import '../../core/design/emphasis_button.dart';
import '../../widgets/quick_nav_bottom_bar.dart';
import '../lab_container.dart';
import 'api_test/api_download_manager.dart';

/// APK 下载管理 —— 同一页面支持下载/安装小豆子（FR）和微豆子（兄弟 app）两个 APK。
///
/// 在小豆子 app 内可一键拉取微豆子最新构建并安装（与本 app 并存）；
/// 在微豆子 app 内也可反过来拉小豆子最新。两个 APK 的 file key、上传地址、签名都不同，
/// 但下载/检查更新/安装流程完全一致。
class ApiTestDemo extends DemoPage {
  @override
  String get title => 'APK 下载管理';

  @override
  String get slug => 'api-test';

  @override
  String get description => '下载/安装小豆子与微豆子 APK';

  @override
  Widget buildPage(BuildContext context) {
    return const _ApiTestPage();
  }
}

class _ApiTestPage extends StatelessWidget {
  const _ApiTestPage();

  @override
  Widget build(BuildContext context) {
    final bottomPad = QuickNavBottomBar.bodyBottomReserve(context);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
          children: const [
            _ApkDownloadCard(
              title: 'FR 最新版 APK',
              subtitle: '小豆子（FR / xiaodouzi）',
              fileKey: 'fr_latest_apk',
              iconData: Icons.android,
              tint: Colors.blue,
              // 自动下载功能仅「本 app 的自更新」有意义：
              //   - 在小豆子 app 内，FR 卡就是本 app 自更新 → 显示开关
              //   - 在微豆子 app 内，FR 卡是兄弟 app → 不显示（且微豆子本身不支持自动下载）
              showAutoDownload: !kIsWeidouzi,
            ),
            SizedBox(height: 16),
            _ApkDownloadCard(
              title: '微豆子 最新版',
              subtitle: '兄弟 app（weidouzi），可与本 app 并存',
              fileKey: 'wdz_latest_apk',
              iconData: Icons.android_outlined,
              tint: Colors.teal,
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个 APK 下载卡 —— 自管理 metadata + 下载状态（不依赖 ApkDownloadManager），
/// 用参数化的 ApkDownloadEndpoint 拉取任意 file key。
class _ApkDownloadCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String fileKey;
  final IconData iconData;
  final Color tint;

  /// 是否显示「自动下载设置」开关（仅 self-update 卡打开；微豆子卡与兄弟 app 卡不开）
  final bool showAutoDownload;

  const _ApkDownloadCard({
    required this.title,
    required this.subtitle,
    required this.fileKey,
    required this.iconData,
    required this.tint,
    this.showAutoDownload = false,
  });

  @override
  State<_ApkDownloadCard> createState() => _ApkDownloadCardState();
}

class _ApkDownloadCardState extends State<_ApkDownloadCard> {
  late final ApkDownloadEndpoint _endpoint;

  // 元数据
  ApkMetadataResult? _metadata;
  bool _isChecking = false;

  // 下载状态
  bool _isDownloading = false;
  bool _isPaused = false;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _downloadedPath;
  DownloadController? _controller;
  http.Client? _activeClient;

  @override
  void initState() {
    super.initState();
    _endpoint = ApkDownloadEndpoint(ApiConfig.production(), fileKey: widget.fileKey);
    _hydrateDownloadedPath();
  }

  Future<void> _hydrateDownloadedPath() async {
    final path = await _endpoint.getDownloadedPath();
    if (!mounted) return;
    setState(() => _downloadedPath = path);
  }

  // ===== 元数据 =====
  Future<void> _checkUpdate() async {
    setState(() {
      _isChecking = true;
    });
    final meta = await _endpoint.metadata();
    if (!mounted) return;
    setState(() {
      _metadata = meta;
      _isChecking = false;
    });
  }

  // ===== 下载 =====
  Future<void> _browserDownload() async {
    final uri = Uri.parse('${ApiConfig.production().baseUrl}/files/by-key/${widget.fileKey}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开浏览器失败: $e')),
        );
      }
    }
  }

  Future<void> _startDownload() async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
      _isPaused = false;
      _progress = 0.0;
      _receivedBytes = 0;
      _totalBytes = 0;
    });
    _controller = DownloadController();
    _activeClient = http.Client();
    try {
      final path = await _endpoint.downloadToLocal(
        controller: _controller,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            _totalBytes = total;
            _progress = total > 0 ? received / total : 0.0;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _downloadedPath = path;
        _isDownloading = false;
        _isPaused = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _isPaused = false;
      });
    } finally {
      _activeClient?.close();
      _activeClient = null;
    }
  }

  Future<void> _pauseDownload() async {
    _controller?.pause();
    if (!mounted) return;
    setState(() => _isPaused = true);
  }

  Future<void> _resumeDownload() async {
    // 续传 = 新 controller + 复用 temp 偏移（downloadToLocal 自动从 existingLength 继续）
    setState(() => _isPaused = false);
    await _startDownload();
  }

  Future<void> _cancelDownload() async {
    _controller?.cancel();
    _activeClient?.close();
    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      _isPaused = false;
      _progress = 0.0;
    });
  }

  Future<void> _clearDownloaded() async {
    if (_downloadedPath == null) return;
    final file = File(_downloadedPath!);
    if (await file.exists()) {
      await file.delete();
    }
    await _endpoint.clearTempFile();
    if (!mounted) return;
    setState(() {
      _downloadedPath = null;
      _progress = 0.0;
      _receivedBytes = 0;
      _totalBytes = 0;
    });
  }

  Future<void> _openInstall() async {
    final path = _downloadedPath;
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('APK 文件不存在')),
        );
      }
      return;
    }
    try {
      final result = await OpenFilex.open(path);
      if (!mounted) return;
      if (result.type == ResultType.noAppToOpen) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有找到可安装的应用')),
        );
      } else if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('唤起失败: ${result.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('唤起异常: $e')),
        );
      }
    }
  }

  Future<void> _share() async {
    final path = _downloadedPath;
    if (path == null) return;
    try {
      final file = XFile(path);
      await Share.shareXFiles([file], text: '${widget.title} 安装包');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e')),
        );
      }
    }
  }

  /// 自动下载开关（仅 self-update 卡启用）
  Future<void> _toggleAutoDownload(bool enabled) async {
    await ApkDownloadManager().setAutoDownloadEnabled(enabled);
    if (!mounted) return;
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

  // ===== UI helpers =====
  String _fmtTime(String? s) => (s == null || s.isEmpty) ? '—' : (s.length >= 16 ? s.substring(0, 16) : s);

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _buildProgressText() {
    final pct = (_progress * 100).toStringAsFixed(1);
    if (_totalBytes > 0) {
      return '$pct%  (${_formatFileSize(_receivedBytes)} / ${_formatFileSize(_totalBytes)})';
    }
    return '$pct%';
  }

  // ===== Build =====
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部
            Row(
              children: [
                Icon(widget.iconData, size: 32, color: widget.tint),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.subtitle,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 元数据
            if (_metadata != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.35), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('文件大小: ${_formatFileSize(_metadata!.size ?? 0)}'),
                    if (_metadata!.uploadTime != null)
                      Text('上传时间: ${_fmtTime(_metadata!.uploadTime!.toUtc().toIso8601String())}'),
                  ],
                ),
              ),
            if (_metadata != null) const SizedBox(height: 16),
            // 进度
            if (_isDownloading || _isPaused) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(
                _buildProgressText(),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
            // 自动下载设置卡（仅 self-update 卡；微豆子与兄弟 app 卡不显示）
            if (widget.showAutoDownload) ...[
              _buildAutoDownloadCard(),
              const SizedBox(height: 16),
            ],
            // 操作按钮
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _isChecking ? null : _checkUpdate,
                  icon: _isChecking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('检查更新'),
                  style: EmphasisButton.borderEmphasis(context, color: Colors.indigo),
                ),
                OutlinedButton.icon(
                  onPressed: _browserDownload,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('浏览器下载'),
                  style: EmphasisButton.borderEmphasis(context, color: Colors.deepPurple),
                ),
                if (_isDownloading)
                  OutlinedButton.icon(
                    onPressed: _pauseDownload,
                    icon: const Icon(Icons.pause),
                    label: const Text('暂停'),
                    style: EmphasisButton.borderEmphasis(context, color: Colors.orange),
                  )
                else if (_isPaused)
                  OutlinedButton.icon(
                    onPressed: _resumeDownload,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('继续下载'),
                    style: EmphasisButton.borderEmphasis(context, color: Colors.teal),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _startDownload,
                    icon: const Icon(Icons.download_for_offline),
                    label: const Text('内部下载'),
                    style: EmphasisButton.borderEmphasis(context, color: Colors.blue),
                  ),
                if (_isDownloading || _isPaused)
                  OutlinedButton.icon(
                    onPressed: _cancelDownload,
                    icon: const Icon(Icons.cancel),
                    label: const Text('取消'),
                    style: EmphasisButton.borderEmphasis(context, color: Colors.red),
                  ),
              ],
            ),
            // 已下载文件操作
            if (_downloadedPath != null) ...[
              const SizedBox(height: 12),
              _buildDownloadedFileCard(),
            ],
            const SizedBox(height: 12),
            // 下载地址
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.tint.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.tint.withValues(alpha: 0.35), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('下载地址:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  SelectableText(
                    '${ApiConfig.production().baseUrl}/files/by-key/${widget.fileKey}',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Key: ${widget.fileKey} (覆盖更新) | 永不过期',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 自动下载设置卡：Switch 切换 + 服务器最新版本 / 本地已处理版本两个槽位。
  Widget _buildAutoDownloadCard() {
    return ValueListenableBuilder<ApkDownloadState>(
      valueListenable: ApkDownloadManager().state,
      builder: (context, s, _) {
        final isOn = s.autoDownloadOnUpdate;
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
                    onChanged: _isDownloading || _isPaused ? null : _toggleAutoDownload,
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
              _autoSlot(
                icon: Icons.schedule,
                label: '服务器最新版本',
                value: _fmtTime(s.apkUpdateTime),
                color: Colors.blue,
              ),
              const SizedBox(height: 6),
              _autoSlot(
                icon: Icons.history,
                label: '本地已处理版本',
                value: s.lastSeenUploadTime != null ? _fmtTime(s.lastSeenUploadTime) : '尚未下载',
                color: s.lastSeenUploadTime != null ? Colors.green : Colors.grey,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _autoSlot({required IconData icon, required String label, required String value, required Color color}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
          ),
          child: Text(
            value,
            style: TextStyle(fontSize: 12, color: color, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadedFileCard() {
    final path = _downloadedPath!;
    final name = path.split('/').last.split('\\').last;
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
            border: Border.all(color: Colors.green.withValues(alpha: 0.35), width: 1.5),
          ),
          child: const Icon(Icons.android, color: Colors.green),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(path, style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: _openInstall,
              style: EmphasisButton.borderEmphasis(context, color: Colors.green),
              child: const Text('安装'),
            ),
            const SizedBox(width: 4),
            IconButton(onPressed: _share, icon: const Icon(Icons.share), tooltip: '分享', color: Colors.blue),
            IconButton(onPressed: _clearDownloaded, icon: const Icon(Icons.delete_outline), tooltip: '清除', color: Colors.red),
          ],
        ),
      ),
    );
  }
}

void registerApiTestDemo() {
  demoRegistry.register(ApiTestDemo());
}
