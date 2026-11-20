import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/ai_chat/ai_chat_provider.dart';
import '../../services/ai_chat/agent_chat_provider.dart';
import '../../services/ai_chat/ai_chat_models.dart';
import '../ui/global/notification/main.dart';
import '../ui/global/button/main.dart';
import '../ui/global/settings/main.dart';

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
        AppNotification.show(context, '设置已保存',
            type: AppNotificationType.success);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 设置页骨架配方（SettingsPageScaffold 家族，灰底画布 + 卡面 surface）。
    return SettingsPageScaffold(
      title: 'AI 聊天设置',
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
      body: Consumer<AIChatProvider>(
        builder: (context, provider, _) {
          if (provider.isLoadingSettings) {
            return const Center(child: CircularProgressIndicator());
          }

          _initControllers(provider);

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              // ── 模型 ──
              const SettingsSectionHeader('模型'),
              SettingsCard(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                  const SizedBox(height: 12),

                  // 模型类型
                  DropdownButtonFormField<String>(
                    key: ValueKey(_selectedType),
                    initialValue: _selectedType,
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
                  const SizedBox(height: 12),

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
                  const SizedBox(height: 12),

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
                ],
              ),

              // ── 数据库（Agent）──
              const SettingsSectionHeader('数据库（Agent）'),
              SettingsCard(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                children: [
                  TextField(
                    controller: _dbHostController,
                    decoration: const InputDecoration(
                      labelText: '数据库 Host',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.dns),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _dbPortController,
                    decoration: const InputDecoration(
                      labelText: '端口',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.numbers),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _dbNameController,
                    decoration: const InputDecoration(
                      labelText: '数据库名',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.storage),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _dbUserController,
                    decoration: const InputDecoration(
                      labelText: '数据库用户名',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _dbPasswordController,
                    decoration: const InputDecoration(
                      labelText: '数据库密码',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                    ),
                    obscureText: true,
                  ),
                ],
              ),

              // ── 说明 ──
              const SettingsSectionHeader('说明'),
              SettingsCard(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('1. 点击右上角保存或下方按钮保存设置',
                      style: TextStyle(fontSize: 13)),
                  const Text('2. 模型类型默认为 Claude',
                      style: TextStyle(fontSize: 13)),
                  const Text('3. 数据库配置用于 Agent 功能',
                      style: TextStyle(fontSize: 13)),
                  const Text('4. 保存后返回 Agent 页面即可使用',
                      style: TextStyle(fontSize: 13)),
                ],
              ),

              // 保存按钮（页尾动作，画布级排版对齐卡片外距）
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _saveSettings,
                  icon: _isSaving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.tertiary,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? '保存中...' : '保存设置'),
                  style: EmphasisButton.borderEmphasis(
                    context,
                    color: scheme.tertiary,
                  ).copyWith(
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
