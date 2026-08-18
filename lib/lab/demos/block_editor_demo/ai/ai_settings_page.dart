import 'package:flutter/material.dart';
import '../../../../widgets/context_colors.dart';

import '../state.dart';
import 'ai_settings_store.dart';

/// AI 配置独立页 — 配置 apiKey / 模型 / Base URL。
///
/// 从 block_editor AppBar 齿轮按钮 push 进入。保存后同步到
/// [EditorState.updateAiSettings] 并持久化到 [AiSettingsStore]。
class AiSettingsPage extends StatefulWidget {
  final EditorState editorState;

  const AiSettingsPage({super.key, required this.editorState});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final _store = AiSettingsStore();
  late final TextEditingController _apiKeyCtl;
  late final TextEditingController _modelCtl;
  late final TextEditingController _baseUrlCtl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _apiKeyCtl = TextEditingController();
    _modelCtl = TextEditingController();
    _baseUrlCtl = TextEditingController();
    _store.load().then((s) {
      if (!mounted) return;
      _apiKeyCtl.text = s.apiKey;
      _modelCtl.text = s.model;
      _baseUrlCtl.text = s.baseUrl;
      setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _apiKeyCtl.dispose();
    _modelCtl.dispose();
    _baseUrlCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final settings = AiSettings(
      apiKey: _apiKeyCtl.text.trim(),
      model: _modelCtl.text.trim(),
      baseUrl: _baseUrlCtl.text.trim(),
    );
    await _store.save(settings);
    widget.editorState.updateAiSettings(settings);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 配置')),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _apiKeyCtl,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      helperText: '后端创建 ChatModel 用',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: _modelCtl,
                    decoration: const InputDecoration(
                      labelText: '模型名（可选）',
                      hintText: '如 glm-4.7',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: _baseUrlCtl,
                    decoration: const InputDecoration(
                      labelText: 'Base URL（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _save,
                    icon: Icon(Icons.save),
                    label: Text('保存'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.accent,
                      side: BorderSide(
                        color: context.colors.accent.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
