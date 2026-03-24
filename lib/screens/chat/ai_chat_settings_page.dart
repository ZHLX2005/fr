import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/ai_chat_message.dart';
import '../../providers/ai_chat_provider.dart';

/// AI 聊天设置页面
class AIChatSettingsPage extends StatefulWidget {
  const AIChatSettingsPage({super.key});

  @override
  State<AIChatSettingsPage> createState() => _AIChatSettingsPageState();
}

class _AIChatSettingsPageState extends State<AIChatSettingsPage> {
  late TextEditingController _apiKeyController;
  late TextEditingController _modelController;
  late TextEditingController _baseURLController;
  // 数据库配置
  late TextEditingController _dbHostController;
  late TextEditingController _dbPortController;
  late TextEditingController _dbNameController;
  late TextEditingController _dbUserController;
  late TextEditingController _dbPasswordController;
  String _selectedType = 'claude';
  bool _isSaving = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final settings = context.read<AIChatProvider>().settings;
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _modelController = TextEditingController(text: settings.model);
    _baseURLController = TextEditingController(text: settings.baseURL);
    _dbHostController = TextEditingController(text: settings.dbHost);
    _dbPortController = TextEditingController(text: settings.dbPort);
    _dbNameController = TextEditingController(text: settings.dbName);
    _dbUserController = TextEditingController(text: settings.dbUser);
    _dbPasswordController = TextEditingController(text: settings.dbPassword);
    _selectedType = settings.type;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _baseURLController.dispose();
    _dbHostController.dispose();
    _dbPortController.dispose();
    _dbNameController.dispose();
    _dbUserController.dispose();
    _dbPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    final settings = AISettings(
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      baseURL: _baseURLController.text.trim(),
      type: _selectedType,
      dbHost: _dbHostController.text.trim(),
      dbPort: _dbPortController.text.trim(),
      dbName: _dbNameController.text.trim(),
      dbUser: _dbUserController.text.trim(),
      dbPassword: _dbPasswordController.text.trim(),
    );

    await context.read<AIChatProvider>().updateSettings(settings);

    if (mounted) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('设置已保存'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _testConnection() async {
    if (_apiKeyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入 API Key')),
      );
      return;
    }

    // 临时保存设置用于测试
    final tempSettings = AISettings(
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      baseURL: _baseURLController.text.trim(),
      type: _selectedType,
      dbHost: _dbHostController.text.trim(),
      dbPort: _dbPortController.text.trim(),
      dbName: _dbNameController.text.trim(),
      dbUser: _dbUserController.text.trim(),
      dbPassword: _dbPasswordController.text.trim(),
    );

    // 显示测试中提示
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('测试连接中...'),
          ],
        ),
      ),
    );

    // 创建一个临时 Provider 测试连接
    final tempProvider = AIChatProvider();
    await tempProvider.updateSettings(tempSettings);
    await tempProvider.sendMessage('你好');
    final error = tempProvider.error;
    tempProvider.dispose();

    // 关闭测试对话框
    if (mounted) {
      Navigator.pop(context);

      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连接成功!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接失败: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 聊天设置'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveSettings,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: Consumer<AIChatProvider>(
        builder: (context, provider, _) {
          // 等待设置加载完成
          if (provider.isLoadingSettings && !_isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }

          // 初始化控制器（仅在首次加载完成时）
          if (!_isInitialized) {
            _isInitialized = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final settings = provider.settings;
              _apiKeyController.text = settings.apiKey;
              _modelController.text = settings.model;
              _baseURLController.text = settings.baseURL;
              _dbHostController.text = settings.dbHost;
              _dbPortController.text = settings.dbPort;
              _dbNameController.text = settings.dbName;
              _dbUserController.text = settings.dbUser;
              _dbPasswordController.text = settings.dbPassword;
              setState(() {
                _selectedType = settings.type;
              });
            });
          }

          return _buildSettingsContent();
        },
      ),
    );
  }

  Widget _buildSettingsContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        final horizontalPadding = isWide ? constraints.maxWidth * 0.1 : 16.0;

        return ListView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 16,
          ),
          children: [
            // API Key
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key *',
                hintText: '请输入您的 API Key',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),

            // 模型类型
            DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: const InputDecoration(
                labelText: '模型类型',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.model_training),
              ),
              items: const [
                DropdownMenuItem(value: 'claude', child: Text('Claude')),
                DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedType = value ?? 'claude';
                });
              },
            ),
            const SizedBox(height: 16),

            // Model
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: '模型名称 (可选)',
                hintText: '如: claude-3-5-sonnet-20241022',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.psychology),
              ),
            ),
            const SizedBox(height: 16),

            // Base URL
            TextField(
              controller: _baseURLController,
              decoration: const InputDecoration(
                labelText: '自定义 Base URL (可选)',
                hintText: '如: https://api.anthropic.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 24),

            // 数据库配置标题
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.storage, color: Colors.green[700]),
                  const SizedBox(width: 8),
                  Text(
                    '数据库配置 (Agent)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 数据库 Host
            TextField(
              controller: _dbHostController,
              decoration: const InputDecoration(
                labelText: '数据库 Host',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.dns),
              ),
            ),
            const SizedBox(height: 12),

            // 数据库 Port 和 Database 并排 (自适应布局)
            _buildResponsiveRow([
              Expanded(
                child: TextField(
                  controller: _dbPortController,
                  decoration: const InputDecoration(
                    labelText: '端口',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.numbers),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _dbNameController,
                  decoration: const InputDecoration(
                    labelText: '数据库名',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.storage),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),

            // 数据库用户名
            TextField(
              controller: _dbUserController,
              decoration: const InputDecoration(
                labelText: '数据库用户',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),

            // 数据库密码
            TextField(
              controller: _dbPasswordController,
              decoration: const InputDecoration(
                labelText: '数据库密码',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),

            // 测试连接按钮
            OutlinedButton.icon(
              onPressed: _testConnection,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('测试连接'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 32),

            // 说明
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        '使用说明',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTip('1. 请输入有效的 API Key'),
                  _buildTip('2. 模型类型默认为 Claude'),
                  _buildTip('3. 模型名称和 Base URL 为可选配置'),
                  _buildTip('4. 点击"测试连接"验证配置'),
                  _buildTip('5. 保存设置后可开始 AI 聊天'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResponsiveRow(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 400) {
          // 窄屏：垂直排列
          return Column(
            children: children.map((child) {
              if (child is Expanded) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: child,
                );
              }
              return child;
            }).toList(),
          );
        }
        // 宽屏：水平排列
        return Row(children: children);
      },
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: Colors.black87),
      ),
    );
  }
}
