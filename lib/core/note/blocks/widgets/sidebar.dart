import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../models/ai_chat_message.dart' show AISettings;
import '../../workspace/workspace_provider.dart';
import '../../workspace/page_model.dart';

/// 侧边栏 —— 页面列表 + 新建按钮 + AI 配置
class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final workspace = WorkspaceProvider.of(context, listen: true);
    final pages = workspace.pages;
    final activeId = workspace.activePageId;

    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Row(
              children: [
                Text('页面', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: '新建页面',
                  onPressed: () {
                    workspace.createPage();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),

          // 页面列表
          Expanded(
            child: pages.isEmpty
                ? const Center(child: Text('暂无页面'))
                : ListView.builder(
                    itemCount: pages.length,
                    itemBuilder: (context, index) {
                      final page = pages[index];
                      final isActive = page.id == activeId;
                      return ListTile(
                        selected: isActive,
                        selectedTileColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.3),
                        leading: Icon(
                          Icons.description_outlined,
                          color: isActive
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(page.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: '删除',
                          onPressed: () => _confirmDelete(context, workspace, page),
                        ),
                        onTap: () {
                          workspace.switchPage(page.id);
                          Navigator.pop(context);
                        },
                        onLongPress: () => _renamePage(context, workspace, page),
                      );
                    },
                  ),
          ),

          // 底部：AI 配置入口
          const Divider(height: 1),
          SafeArea(
            child: ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('AI 设置'),
              onTap: () {
                Navigator.pop(context);
                _showAiConfigDialog(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── AI 配置对话框 ────────────

  void _showAiConfigDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _AiConfigDialog(),
    );
  }

  // ──────────── 页面操作 ────────────

  void _confirmDelete(BuildContext context, WorkspaceProvider workspace, PageModel page) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除页面'),
        content: Text('确定要删除「${page.title}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              workspace.deletePage(page.id);
              Navigator.pop(ctx);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _renamePage(BuildContext context, WorkspaceProvider workspace, PageModel page) {
    final controller = TextEditingController(text: page.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新标题'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                workspace.renamePage(page.id, controller.text.trim());
              }
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

/// AI 配置对话框
class _AiConfigDialog extends StatefulWidget {
  @override
  State<_AiConfigDialog> createState() => _AiConfigDialogState();
}

class _AiConfigDialogState extends State<_AiConfigDialog> {
  static const _settingsKey = 'ai_chat_settings';

  final _apiKeyCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_settingsKey);
    if (json != null && json.isNotEmpty) {
      final settings = AISettings.decode(json);
      _apiKeyCtrl.text = settings.apiKey;
      _baseUrlCtrl.text = settings.baseURL;
      _modelCtrl.text = settings.model;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final settings = AISettings(
      apiKey: _apiKeyCtrl.text.trim(),
      baseURL: _baseUrlCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      type: 'other', // 用 OpenAI 兼容格式直连
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, AISettings.encode(settings));
    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 配置已保存'), duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI 设置'),
      content: _loading
          ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
          : SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('配置 LLM API 后，AI 助手才能工作。', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _apiKeyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        hintText: '输入 API Key',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _baseUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'API URL（可选）',
                        hintText: 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _modelCtrl,
                      decoration: const InputDecoration(
                        labelText: '模型（可选）',
                        hintText: 'glm-4v-flash',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('默认使用智谱 GLM。支持 OpenAI 兼容格式的 API。', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('保存'),
        ),
      ],
    );
  }
}

/// 在 BuildContext 上快速获取 WorkspaceProvider 的扩展方法
extension WorkspaceProviderExtension on BuildContext {
  WorkspaceProvider get workspace => WorkspaceProvider.of(this);
}
