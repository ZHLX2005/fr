import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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

  @override
  void initState() {
    super.initState();
    _loadKvList();
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
                  if (_isLoading)
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
