import 'package:flutter/material.dart';

import 'ai_gallery_log.dart';
import 'ai_gallery_log_page.dart';
import 'ai_gallery_settings.dart';

/// AI 图库独立配置页。
///
/// 与 AI 中心的 ai_chat 设置页完全独立（本 demo 自带协议/baseUrl/key/model/
/// 提示词/扫描数/并发/重试/日志）。入口必须传 [initial]（主页把当前配置带
/// 进来），点「保存」时**自己落盘**再把新配置 pop 回主页 —— 早先版本主页
/// 没把 initial 传进来、也没人写盘，导致退出重进后 apiKey/模型全变回空值。
class AiGallerySettingsPage extends StatefulWidget {
  final AiGallerySettings initial;

  const AiGallerySettingsPage({
    super.key,
    this.initial = const AiGallerySettings(),
  });

  @override
  State<AiGallerySettingsPage> createState() => _AiGallerySettingsPageState();
}

class _AiGallerySettingsPageState extends State<AiGallerySettingsPage> {
  final AiGallerySettingsStore _store = AiGallerySettingsStore();

  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _promptCtrl;
  late String _protocolId;
  late double _scanCount;
  late double _maxConcurrency;
  late double _retryCount;
  late bool _autoScan;
  late bool _logEnabled;
  late double _logMaxEntries;
  late double _logMaxChars;
  bool _obscureKey = true;
  bool _saving = false;

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
    _retryCount = s.retryCount.toDouble();
    _autoScan = s.autoScan;
    _logEnabled = s.logEnabled;
    _logMaxEntries = s.logMaxEntries.toDouble();
    _logMaxChars = s.logMaxChars.toDouble();
    // 进设置页就按当前配置同步一次，保证「查看日志」里的容量显示是对的
    _applyLogConfig();
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
    retryCount: _retryCount.round(),
    logEnabled: _logEnabled,
    logMaxEntries: _logMaxEntries.round(),
    logMaxChars: _logMaxChars.round(),
  );

  /// 日志开关/长度改动立刻生效（要调试时不用先保存再退出）。
  void _applyLogConfig() {
    AiGalleryLog.instance.configure(
      enabled: _logEnabled,
      maxEntries: _logMaxEntries.round(),
      maxChars: _logMaxChars.round(),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final s = _current();
    s.applyLogConfig();
    final ok = await _store.save(s);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
      return;
    }
    Navigator.of(context).pop(s);
  }

  Future<void> _openLog() async {
    // 进去之前先把当前草稿配置写进日志缓冲，看到的就是「现在这套参数」
    _applyLogConfig();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AiGalleryLogPage()),
    );
    if (mounted) {
      setState(() {}); // 回来刷新日志条数
    }
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
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
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
            style: ButtonStyle(
              // 选中只做淡底 + 主色描边，避免整页出现第二个实心色块
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? scheme.primary.withValues(alpha: 0.08)
                    : Colors.transparent,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
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
              helperText: '保存在本机（SharedPreferences），退出重进不会丢',
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
            label: _maxConcurrency.round() == 1
                ? '1（串行）'
                : '${_maxConcurrency.round()}',
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

          // ── 失败重试 ──
          _SectionLabel(
            '失败重试：${_retryCount.round()} 次${_retryCount.round() == 0 ? '（不重试）' : ''}',
          ),
          Slider(
            value: _retryCount,
            min: 0,
            max: 4,
            divisions: 4,
            label: '${_retryCount.round()}',
            onChanged: (v) => setState(() => _retryCount = v),
          ),
          Text(
            '单张失败后会重试。JSON 解析失败时不是原样重发 —— 会把解析器的'
            '错误和上一次的原始回复拼进提示词再请求，让它照着错误改。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
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

          const Divider(height: 32),

          // ── 日志模式 ──
          _SectionLabel('日志模式（调试用）'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('开启运行日志'),
            subtitle: const Text('记录每次请求的提示词、原始回复、解析错误与重试过程'),
            value: _logEnabled,
            onChanged: (v) {
              setState(() => _logEnabled = v);
              _applyLogConfig();
            },
          ),
          const SizedBox(height: 4),
          _SectionLabel('保留条数：${_logMaxEntries.round()} 条'),
          Slider(
            value: _logMaxEntries,
            min: 20,
            max: 2000,
            divisions: 33,
            label: '${_logMaxEntries.round()}',
            onChanged: (v) {
              setState(() => _logMaxEntries = v);
              _applyLogConfig();
            },
          ),
          Text(
            '超出后自动丢弃最旧的日志',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _SectionLabel('单条最大长度：${_logMaxChars.round()} 字'),
          Slider(
            value: _logMaxChars,
            min: 200,
            max: 4000,
            divisions: 19,
            label: '${_logMaxChars.round()}',
            onChanged: (v) {
              setState(() => _logMaxChars = v);
              _applyLogConfig();
            },
          ),
          Text(
            '超长的提示词/模型回复按这个长度截断（太短可能看不到出错位置，'
            '太长会占内存）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: AiGalleryLog.instance,
            builder: (context, _) {
              final log = AiGalleryLog.instance;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('查看运行日志'),
                subtitle: Text(
                  '当前 ${log.entries.length} 条 · ${log.errorCount} 条错误',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: log.errorCount > 0
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _openLog,
              );
            },
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
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}
