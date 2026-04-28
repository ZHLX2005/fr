import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/ai_chat_provider.dart';
import '../../../providers/agent_chat_provider.dart';
import '../../../models/ai_chat_message.dart';

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
  late TextEditingController _dbHostController;
  late TextEditingController _dbPortController;
  late TextEditingController _dbNameController;
  late TextEditingController _dbUserController;
  late TextEditingController _dbPasswordController;

  bool _isInit = false;
  bool _isSaving = false;

  // 本地状态，跟踪当前选择
  String _selectedType = 'claude';

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

  void _initControllers(AIChatProvider provider) {
    if (_isInit) return;
    _isInit = true;

    final s = provider.settings;
    _apiKeyController = TextEditingController(text: s.apiKey);
    _modelController = TextEditingController(text: s.model);
    _baseURLController = TextEditingController(text: s.baseURL);
    _dbHostController = TextEditingController(text: s.dbHost);
    _dbPortController = TextEditingController(text: s.dbPort);
    _dbNameController = TextEditingController(text: s.dbName);
    _dbUserController = TextEditingController(text: s.dbUser);
    _dbPasswordController = TextEditingController(text: s.dbPassword);
    _selectedType = s.type.isNotEmpty ? s.type : 'claude';
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final provider = context.read<AIChatProvider>();
      final newSettings = AISettings(
        apiKey: _apiKeyController.text,
        model: _modelController.text,
        baseURL: _baseURLController.text,
        type: _selectedType,
        dbHost: _dbHostController.text,
        dbPort: _dbPortController.text,
        dbName: _dbNameController.text,
        dbUser: _dbUserController.text,
        dbPassword: _dbPasswordController.text,
      );

      await provider.updateSettings(newSettings);

      // 通知 AgentChatProvider 刷新设置
      if (mounted) {
        context.read<AgentChatProvider>().refreshSettings();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('设置已保存'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
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
          TextButton.icon(
            onPressed: _isSaving ? null : _saveSettings,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_isSaving ? '保存中...' : '保存'),
          ),
        ],
      ),
      body: Consumer<AIChatProvider>(
        builder: (context, provider, _) {
          if (provider.isLoadingSettings) {
            return const Center(child: CircularProgressIndicator());
          }

          _initControllers(provider);

          return ListView(
            padding: const EdgeInsets.all(16),
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
                  if (value != null) {
                    setState(() => _selectedType = value);
                  }
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

              // 数据库 Port
              TextField(
                controller: _dbPortController,
                decoration: const InputDecoration(
                  labelText: '端口',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.numbers),
                ),
              ),
              const SizedBox(height: 12),

              // 数据库名
              TextField(
                controller: _dbNameController,
                decoration: const InputDecoration(
                  labelText: '数据库名',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.storage),
                ),
              ),
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
              const SizedBox(height: 32),

              // 保存按钮
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveSettings,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? '保存中...' : '保存设置'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 24),

              // 说明
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                    SizedBox(height: 12),
                    Text('1. 点击右上角保存或底部按钮保存设置', style: TextStyle(fontSize: 13)),
                    Text('2. 模型类型默认为 Claude', style: TextStyle(fontSize: 13)),
                    Text('3. 数据库配置用于 Agent 功能', style: TextStyle(fontSize: 13)),
                    Text(
                      '4. 保存后返回 Agent 页面即可使用',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
