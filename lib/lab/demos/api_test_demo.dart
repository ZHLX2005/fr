import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../lab_container.dart';
import '../../services/api_client.dart';
import 'api_download_manager.dart';

/// API 测试 Demo
class ApiTestDemo extends DemoPage {
  @override
  String get title => 'API 测试';

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
  // KV 状态
  final _keyController = TextEditingController();
  final _valueController = TextEditingController();
  List<_KvItem> _kvList = [];
  String? _kvMessage;
  bool _isLoading = false;

  // 文件状态
  File? _selectedFile;
  String? _uploadResult;
  String? _downloadResult;
  final _downloadIdController = TextEditingController();

  // APK 下载管理器
  final _apkManager = ApkDownloadManager();

  @override
  void initState() {
    super.initState();
    _loadKvList();
    _apkManager.loadSavedState();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    _downloadIdController.dispose();
    super.dispose();
  }

  // ===== KV 操作 =====
  Future<void> _loadKvList() async {
    setState(() => _isLoading = true);
    final items = await ApiService.listKv(limit: 20);
    setState(() {
      _kvList =
          items
              ?.map(
                (e) => _KvItem(
                  key: e.key ?? '',
                  value: e.value ?? '',
                  expiresAt: e.expiresAt,
                ),
              )
              .toList() ??
          [];
      _isLoading = false;
    });
  }

  Future<void> _setKv() async {
    if (_keyController.text.isEmpty || _valueController.text.isEmpty) return;

    setState(() => _isLoading = true);
    final success = await ApiService.setKv(
      _keyController.text,
      _valueController.text,
    );
    setState(() {
      _kvMessage = success ? '设置成功' : '设置失败';
      _isLoading = false;
    });
    _keyController.clear();
    _valueController.clear();
    _loadKvList();
  }

  Future<void> _getKv() async {
    if (_keyController.text.isEmpty) return;

    final result = await ApiService.getKv(_keyController.text);
    setState(() {
      if (result != null) {
        _kvMessage = '值: ${result.value ?? ""}';
        _valueController.text = result.value ?? '';
      } else {
        _kvMessage = 'key不存在';
      }
    });
  }

  Future<void> _deleteKv(String key) async {
    final success = await ApiService.deleteKv(key);
    setState(() {
      _kvMessage = success ? '删除成功' : '删除失败';
    });
    _loadKvList();
  }

  // ===== 文件操作 =====
  Future<void> _pickFile() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedFile = File(image.path);
        _uploadResult = '已选择: ${image.name}';
      });
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null) return;

    setState(() => _isLoading = true);
    final result = await ApiService.uploadFile(_selectedFile!);
    setState(() {
      if (result != null) {
        _uploadResult =
            '上传成功!\nID: ${result.id ?? ""}\nURL: ${result.downloadUrl ?? ""}';
      } else {
        _uploadResult = '上传失败';
      }
      _isLoading = false;
    });
  }

  Future<void> _downloadFile() async {
    if (_downloadIdController.text.isEmpty) return;

    setState(() => _isLoading = true);
    final response = await ApiService.downloadFile(_downloadIdController.text);
    setState(() {
      if (response != null && response.statusCode == 200) {
        _downloadResult = '下载成功! 状态码: ${response.statusCode}';
      } else {
        _downloadResult = '下载失败';
      }
      _isLoading = false;
    });
  }

  Future<void> _deleteFile() async {
    if (_downloadIdController.text.isEmpty) return;

    setState(() => _isLoading = true);
    final success = await ApiService.deleteFile(_downloadIdController.text);
    setState(() {
      _downloadResult = success ? '删除成功' : '删除失败';
      _isLoading = false;
    });
  }

  // ===== APK 操作 =====
  Future<void> _checkApkUpdate() async {
    await _apkManager.checkUpdate();
  }

  Future<void> _downloadApkInternal() async {
    await _apkManager.startDownload();
  }

  Future<void> _cancelDownload() async {
    await _apkManager.cancelDownload();
  }

  Future<void> _downloadApkWithBrowser() async {
    const url = 'http://47.110.80.47:8988/api/v1/file/fr_latest_apk';
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // ===== Build =====
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: DefaultTabController(
        length: 3,
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
                      final isBusy = _isLoading || apkState.isCheckingUpdate;
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
                Tab(text: 'KV 存储'),
                Tab(text: '文件管理'),
              ],
            ),
            // Tab内容
            Expanded(
              child: TabBarView(
                children: [
                  // APK 更新
                  _buildApkTab(),
                  // KV 存储
                  _buildKvTab(),
                  // 文件管理
                  _buildFileTab(),
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
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
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
                      // 下载进度条
                      if (apkState.isDownloading) ...[
                        LinearProgressIndicator(value: apkState.progress),
                        const SizedBox(height: 8),
                        Text(
                          '${(apkState.progress * 100).toStringAsFixed(1)}%',
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
                          ElevatedButton.icon(
                            onPressed:
                                apkState.isCheckingUpdate ? null : _checkApkUpdate,
                            icon: apkState.isCheckingUpdate
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                            label: const Text('检查更新'),
                          ),
                          ElevatedButton.icon(
                            onPressed: _downloadApkWithBrowser,
                            icon: const Icon(Icons.open_in_browser),
                            label: const Text('浏览器下载'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: apkState.isDownloading
                                ? _cancelDownload
                                : _downloadApkInternal,
                            icon: apkState.isDownloading
                                ? const Icon(Icons.cancel)
                                : const Icon(Icons.download_for_offline),
                            label: Text(
                                apkState.isDownloading ? '取消下载' : '内部下载'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: apkState.isDownloading
                                  ? Colors.orange
                                  : Colors.green,
                              foregroundColor: Colors.white,
                            ),
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
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
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
                              'http://47.110.80.47:8988/api/v1/file/fr_latest_apk',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                                fontFamily: 'monospace',
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Key: fr_latest_apk (覆盖更新) | TTL: 30天',
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
            color: Colors.green.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
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
            FilledButton(
              onPressed: _openApkInstall,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
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

  // --- KV 存储 Tab ---
  Widget _buildKvTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _keyController,
                    decoration: const InputDecoration(
                      labelText: 'Key',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _valueController,
                    decoration: const InputDecoration(
                      labelText: 'Value',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _setKv,
                          icon: const Icon(Icons.add),
                          label: const Text('设置'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _getKv,
                          icon: const Icon(Icons.search),
                          label: const Text('获取'),
                        ),
                      ),
                    ],
                  ),
                  if (_kvMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _kvMessage!,
                      style: const TextStyle(color: Colors.green),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'KV 列表',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadKvList,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_kvList.isEmpty)
            const Center(child: Text('暂无数据'))
          else
            ..._kvList.map(
              (item) => Card(
                child: ListTile(
                  title: Text(item.key),
                  subtitle: Text(item.value),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteKv(item.key),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- 文件管理 Tab ---
  Widget _buildFileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    '文件上传',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('选择图片'),
                  ),
                  if (_selectedFile != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: FileImage(_selectedFile!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _uploadFile,
                    icon: const Icon(Icons.upload),
                    label: const Text('上传'),
                  ),
                  if (_uploadResult != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _uploadResult!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    '文件下载/删除',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _downloadIdController,
                    decoration: const InputDecoration(
                      labelText: '文件ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _downloadFile,
                          icon: const Icon(Icons.download),
                          label: const Text('下载'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _deleteFile,
                          icon: const Icon(Icons.delete),
                          label: const Text('删除'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_downloadResult != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _downloadResult!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KvItem {
  final String key;
  final String value;
  final String? expiresAt;

  _KvItem({required this.key, required this.value, this.expiresAt});
}

void registerApiTestDemo() {
  demoRegistry.register(ApiTestDemo());
}
