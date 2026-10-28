import 'package:flutter/material.dart';

import 'ai_gallery_settings.dart';

/// AI 图库独立配置页。
///
/// 与 AI 中心的 ai_chat 设置页完全独立（本 demo 自带协议/baseUrl/key/model/
/// 提示词/扫描数/并发/自动扫描）。返回时通过 `Navigator.pop(context, settings)`
/// 把最新配置交回画廊主页。
class AiGallerySettingsPage extends StatefulWidget {
  final AiGallerySettings initial;

  const AiGallerySettingsPage({super.key, this.initial = const AiGallerySettings()});

  @override
  State<AiGallerySettingsPage> createState() => _AiGallerySettingsPageState();
}

class _AiGallerySettingsPageState extends State<AiGallerySettingsPage> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _promptCtrl;
  late String _protocolId;
  late double _scanCount;
  late double _maxConcurrency;
  late bool _autoScan;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _protocolId = s.protocolId;
    _baseUrlCtrl = TextEditingController(text: s.baseUrl);
    _apiKeyCtrl = TextEditingController(text: s.apiKey);
    _modelCtrl = TextEditingController(text: s.model);
    _promptCtrl = TextEditingController(text: s.prompt);
    _scanCount = s.scanCount.toDouble();
    _maxConcurrency = s.maxConcurrency.toDouble();
    _autoScan = s.autoScan;
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  AiGallerySettings _current() => AiGallerySettings(
        protocolId: _protocolId,
        baseUrl: _baseUrlCtrl.text.trim(),
        apiKey: _apiKeyCtrl.text.trim(),
        model: _modelCtrl.text.trim(),
        prompt: _promptCtrl.text.trim().isNotEmpty
            ? _promptCtrl.text.trim()
            : kDefaultGalleryPrompt,
        scanCount: _scanCount.round(),
        maxConcurrency: _maxConcurrency.round(),
        autoScan: _autoScan,
      );

  void _save() {
    Navigator.of(context).pop(_current());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 图库配置'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── 协议 ──
          _SectionLabel('协议'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'openai',
                icon: Icon(Icons.bolt_rounded),
                label: Text('OpenAI'),
              ),
              ButtonSegment(
                value: 'anthropic',
                icon: Icon(Icons.auto_awesome_rounded),
                label: Text('Anthropic'),
              ),
            ],
            selected: {_protocolId},
            onSelectionChanged: (s) => setState(() => _protocolId = s.first),
          ),
          const SizedBox(height: 4),
          Text(
            _protocolId == 'openai'
                ? 'Bearer 鉴权 · POST {baseURL}/v1/chat/completions · 图片走 image_url data URL'
                : 'x-api-key 鉴权 · POST {baseURL}/v1/messages · 图片走 base64 source',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),

          // ── 连接 ──
          _SectionLabel('服务地址'),
          TextField(
            controller: _baseUrlCtrl,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: _protocolId == 'openai'
                  ? 'https://api.openai.com'
                  : 'https://api.anthropic.com',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          _SectionLabel('API Key'),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              hintText: 'sk-…',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionLabel('模型'),
          TextField(
            controller: _modelCtrl,
            decoration: InputDecoration(
              hintText: _protocolId == 'openai'
                  ? 'gpt-4o-mini'
                  : 'claude-sonnet-4-6',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),

          // ── 提示词 ──
          _SectionLabel('扫描提示词（要求输出 JSON）'),
          TextField(
            controller: _promptCtrl,
            maxLines: 8,
            style: theme.textTheme.bodySmall,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () =>
                  setState(() => _promptCtrl.text = kDefaultGalleryPrompt),
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: const Text('恢复默认'),
            ),
          ),

          // ── 扫描数量 X ──
          _SectionLabel('扫描最新图片数量：${_scanCount.round()} 张'),
          Slider(
            value: _scanCount,
            min: 3,
            max: 60,
            divisions: 19,
            label: '${_scanCount.round()}',
            onChanged: (v) => setState(() => _scanCount = v),
          ),

          // ── 最大并发 ──
          _SectionLabel('最大并发请求：${_maxConcurrency.round()}'),
          Slider(
            value: _maxConcurrency,
            min: 1,
            max: 8,
            divisions: 7,
            label: _maxConcurrency.round() == 1 ? '1（串行）' : '${_maxConcurrency.round()}',
            onChanged: (v) => setState(() => _maxConcurrency = v),
          ),
          Text(
            _maxConcurrency.round() == 1
                ? '串行逐张请求，最稳但最慢'
                : '同时发起 ${_maxConcurrency.round()} 个请求，注意供应商限流',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),

          // ── 自动扫描 ──
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('进入页面自动扫描'),
            subtitle: const Text('配置完整且有相册权限时生效'),
            value: _autoScan,
            onChanged: (v) => setState(() => _autoScan = v),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}
