import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../lab_container.dart';
import '../../services/api_client.dart';

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

  // APK 更新状态
  String? _apkMetadata;
  String? _apkUpdateTime;
  bool _isCheckingUpdate = false;
  String? _downloadStatus;
  double _downloadProgress = 0.0; // 下载进度 0.0-1.0
  bool _isDownloading = false;

  // 已下载的 APK 文件信息
  String? _downloadedApkPath;
  int? _downloadedApkSize;

  static const _kDownloadedApkPathKey = 'downloaded_apk_path';
  static const _kDownloadedApkSizeKey = 'downloaded_apk_size';

  @override
  void initState() {
    super.initState();
    _loadKvList();
    _loadDownloadedApk();
  }

  Future<void> _loadDownloadedApk() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_kDownloadedApkPathKey);
    if (path != null) {
      final file = File(path);
      final exists = await file.exists();
      setState(() {
        _downloadedApkPath = exists ? path : null;
        _downloadedApkSize = exists ? prefs.getInt(_kDownloadedApkSizeKey) : null;
      });
    }
  }

  Future<void> _saveDownloadedApk(String path, int size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDownloadedApkPathKey, path);
    await prefs.setInt(_kDownloadedApkSizeKey, size);
  }

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  // 加载KV列表
  Future<void> _loadKvList() async {
    setState(() => _isLoading = true);
    final items = await ApiService.listKv(limit: 20);
    setState(() {
      _kvList = items?.map((e) => _KvItem(
        key: e.key ?? '',
        value: e.value ?? '',
        expiresAt: e.expiresAt,
      )).toList() ?? [];
      _isLoading = false;
    });
  }

  // 设置KV
  Future<void> _setKv() async {
    if (_keyController.text.isEmpty || _valueController.text.isEmpty) return;

    setState(() => _isLoading = true);
    final success = await ApiService.setKv(_keyController.text, _valueController.text);
    setState(() {
      _kvMessage = success ? '设置成功' : '设置失败';
      _isLoading = false;
    });
    _keyController.clear();
    _valueController.clear();
    _loadKvList();
  }

  // 获取KV
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

  // 删除KV
  Future<void> _deleteKv(String key) async {
    final success = await ApiService.deleteKv(key);
    setState(() {
      _kvMessage = success ? '删除成功' : '删除失败';
    });
    _loadKvList();
  }

  // 选择文件
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

  // 上传文件
  Future<void> _uploadFile() async {
    if (_selectedFile == null) return;

    setState(() => _isLoading = true);
    final result = await ApiService.uploadFile(_selectedFile!);
    setState(() {
      if (result != null) {
        _uploadResult = '上传成功!\nID: ${result.id ?? ""}\nURL: ${result.downloadUrl ?? ""}';
      } else {
        _uploadResult = '上传失败';
      }
      _isLoading = false;
    });
  }

  // 下载文件
  final _downloadIdController = TextEditingController();

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

  // 删除文件
  Future<void> _deleteFile() async {
    if (_downloadIdController.text.isEmpty) return;

    setState(() => _isLoading = true);
    final success = await ApiService.deleteFile(_downloadIdController.text);
    setState(() {
      _downloadResult = success ? '删除成功' : '删除失败';
      _isLoading = false;
    });
  }

  // 检查APK更新
  Future<void> _checkApkUpdate() async {
    setState(() {
      _isCheckingUpdate = true;
      _downloadStatus = '正在检查更新...';
    });

    final metadata = await ApiService.getApkMetadata();
    setState(() {
      _isCheckingUpdate = false;
      if (metadata != null) {
        _apkMetadata = '大小: ${_formatFileSize(metadata.size ?? 0)}';
        _apkUpdateTime = metadata.uploadTime;
        _downloadStatus = '发现新版本 (${metadata.uploadTime?.substring(0, 10) ?? ""})';
      } else {
        _downloadStatus = '未找到APK或服务器错误';
      }
    });
  }

  // 用浏览器下载APK
  Future<void> _downloadApkWithBrowser() async {
    const url = 'http://47.110.80.47:8988/api/v1/file/fr_latest_apk';
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      setState(() {
        _downloadStatus = '请在浏览器下载面板查看进度';
      });
    } catch (e) {
      setState(() {
        _downloadStatus = '打开浏览器失败: $e';
      });
    }
  }

  // 内部下载APK（支持断点续传）
  Future<void> _downloadApkInternal() async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = '开始下载...';
    });

    try {
      final filePath = await ApiService.downloadApkToLocal(
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() {
              _downloadProgress = received / total;
              _downloadStatus = '下载中: ${(_downloadProgress * 100).toStringAsFixed(1)}%';
            });
          }
        },
      );

      if (filePath != null && mounted) {
        final file = File(filePath);
        final size = await file.length();
        await _saveDownloadedApk(filePath, size);
        setState(() {
          _downloadStatus = '下载完成';
          _isDownloading = false;
          _downloadedApkPath = filePath;
          _downloadedApkSize = size;
        });
      } else if (mounted) {
        setState(() {
          _downloadStatus = '下载失败，回退到浏览器下载';
          _isDownloading = false;
        });
        await _downloadApkWithBrowser();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadStatus = '下载出错: $e，回退到浏览器下载';
          _isDownloading = false;
        });
        // 回退到浏览器下载
        await _downloadApkWithBrowser();
      }
    }
  }

  // 显示安装对话框
  void _showInstallDialog(String filePath) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下载完成'),
        content: Text('APK 已下载到:\n$filePath\n\n是否立即安装？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _installApk(filePath);
            },
            child: const Text('安装'),
          ),
        ],
      ),
    );
  }

  // 安装APK
  Future<void> _installApk(String filePath) async {
    try {
      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
      if (mounted) {
        if (result.type == ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('安装器已启动')),
          );
        } else if (result.type == ResultType.noAppToOpen) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到可打开的应用')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('打开失败: ${result.message}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开安装器: $e')),
        );
      }
    }
  }

  // 用系统方式打开文件（弹出"用其他应用打开"）
  Future<void> _openApk() async {
    if (_downloadedApkPath == null) return;
    try {
      final result = await OpenFilex.open(_downloadedApkPath!);
      if (mounted) {
        if (result.type == ResultType.done) {
          // 成功唤起，不做提示
        } else if (result.type == ResultType.noAppToOpen) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有可处理此文件的应用')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('打开失败: ${result.message}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败: $e')),
        );
      }
    }
  }

  // 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

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
                  if (_isLoading || _isCheckingUpdate)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            // Tab栏
            const TabBar(
              tabs: [
                Tab(text: 'KV 存储'),
                Tab(text: '文件管理'),
                Tab(text: 'APK 更新'),
              ],
            ),
            // Tab内容
            Expanded(
              child: TabBarView(
                children: [
                  // KV 存储
                  _buildKvTab(),
                  // 文件管理
                  _buildFileTab(),
                  // APK 更新
                  _buildApkTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKvTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 输入区域
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
                    Text(_kvMessage!, style: const TextStyle(color: Colors.green)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // KV 列表
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('KV 列表', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
            ..._kvList.map((item) => Card(
              child: ListTile(
                title: Text(item.key),
                subtitle: Text(item.value),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteKv(item.key),
                ),
              ),
            )),
        ],
      ),
    );
  }

  Widget _buildFileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 上传区域
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('文件上传', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                    Text(_uploadResult!, style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 下载/删除区域
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('文件下载/删除', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        ),
                      ),
                    ],
                  ),
                  if (_downloadResult != null) ...[
                    const SizedBox(height: 8),
                    Text(_downloadResult!, style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApkTab() {
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
                  if (_apkMetadata != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('文件大小: $_apkMetadata'),
                          if (_apkUpdateTime != null)
                            Text('上传时间: $_apkUpdateTime'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // 状态信息
                  if (_downloadStatus != null) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _downloadStatus!.contains('完成')
                            ? Colors.green[50]
                            : Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _downloadStatus!,
                        style: TextStyle(
                          color: _downloadStatus!.contains('完成')
                              ? Colors.green[700]
                              : Colors.blue[700],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // 操作按钮
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isCheckingUpdate ? null : _checkApkUpdate,
                          icon: _isCheckingUpdate
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                          label: const Text('检查更新'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _downloadApkWithBrowser,
                          icon: const Icon(Icons.download),
                          label: const Text('浏览器下载'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isDownloading ? null : _downloadApkInternal,
                          icon: _isDownloading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    value: _downloadProgress > 0 ? _downloadProgress : null,
                                  ),
                                )
                              : const Icon(Icons.download_for_offline),
                          label: Text(_isDownloading ? '下载中...' : '内部下载'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 显示下载进度条
                  if (_isDownloading) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _downloadProgress),
                  ],
                  const SizedBox(height: 12),
                  // 已下载的 APK 文件卡片
                  if (_downloadedApkPath != null) ...[
                    _buildApkFileCard(),
                    const SizedBox(height: 12),
                  ],
                  // 下载地址信息
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '下载地址:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          'http://47.110.80.47:8988/api/v1/file/fr_latest_apk',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Key: fr_latest_apk (覆盖更新) | TTL: 30天',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
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
                  const SizedBox(height: 8),
                  const Text(
                    '1. 点击"浏览器下载"唤起系统浏览器\n'
                    '2. 在浏览器下载面板查看下载进度\n'
                    '3. 下载完成后点击APK进行安装\n'
                    '4. 如遇安装问题，请先卸载旧版本',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  // 已下载 APK 文件卡片
  Widget _buildApkFileCard() {
    final name = _downloadedApkPath!.split('/').last.split('\\').last;
    final sizeStr = _downloadedApkSize != null ? _formatFileSize(_downloadedApkSize!) : '';

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
          '$sizeStr\n$_downloadedApkPath',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: FilledButton(
          onPressed: _openApk,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: const Text('打开'),
        ),
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
