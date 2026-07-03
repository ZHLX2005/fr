import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/schema/schema_text.dart';

/// Schema 链接功能演示
class SchemaDemo extends DemoPage {
  @override
  String get title => 'Schema链接';

  @override
  String get description => '内部链接协议，支持文本内嵌可跳转链接';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const _SchemaDemoPage();
  }
}

class _SchemaDemoPage extends StatefulWidget {
  const _SchemaDemoPage();

  @override
  State<_SchemaDemoPage> createState() => _SchemaDemoPageState();
}

class _SchemaDemoPageState extends State<_SchemaDemoPage> {
  final TextEditingController _inputController = TextEditingController();
  String _previewText = '';
  bool _autoLink = false;

  @override
  void initState() {
    super.initState();
    _inputController.text = '这是一个测试文本，尝试输入 [悬浮截屏] 或 [时钟] 看能否自动识别';
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _updatePreview() {
    setState(() {
      _previewText = _inputController.text;
    });
  }

  /// 自动把 demo 标题转换为 [title](fr://lab/demo/key) 链接
  static String _convertAutoLinks(String text) {
    final allDemos = demoRegistry.getAll();
    // 按标题长度降序排列，避免短标题先匹配
    final titles = allDemos.map((e) => (e.key, e.value.title)).toList()
      ..sort((a, b) => b.$2.length.compareTo(a.$2.length));

    final matches = <_MatchInfo>[];
    for (final (key, title) in titles) {
      final pattern = RegExp(RegExp.escape(title));
      for (final m in pattern.allMatches(text)) {
        matches.add(_MatchInfo(m.start, m.end, title, 'fr://lab/demo/$key'));
      }
    }

    matches.sort((a, b) => a.start.compareTo(b.start));

    final buf = StringBuffer();
    int lastEnd = 0;
    int? lastEndRange;
    for (final m in matches) {
      if (lastEndRange != null && m.start < lastEndRange) continue; // overlap
      buf.write(text.substring(lastEnd, m.start));
      buf.write('[${m.displayText}](${m.schema})');
      lastEnd = m.end;
      lastEndRange = m.end;
    }
    buf.write(text.substring(lastEnd));
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDemos = demoRegistry.getAll();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schema 链接演示'),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 说明卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('使用说明', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text(
                      '在文本中使用 [显示文字](fr://lab/demo/Key) 格式创建可点击链接。\n'
                      '支持的 Demo:',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: allDemos.take(6).map((entry) {
                        return ActionChip(
                          avatar: const Icon(Icons.apps, size: 16),
                          label: Text(entry.value.title),
                          onPressed: () => _insertDemoLink(
                            entry.key,
                            entry.value.title,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 输入区域
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('输入文本', style: theme.textTheme.titleMedium),
                        const Spacer(),
                        Row(
                          children: [
                            const Text('自动识别'),
                            Switch(
                              value: _autoLink,
                              onChanged: (v) => setState(() => _autoLink = v),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _inputController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: '输入文本，支持 [文字](fr://lab/demo/key) 格式',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _updatePreview(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 预览区域
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('预览效果', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _previewText.isEmpty
                          ? Text(
                              '在上方输入文本预览效果',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            )
                          : SchemaText(
                              _autoLink
                                  ? _convertAutoLinks(_previewText)
                                  : _previewText,
                              style: theme.textTheme.bodyMedium,
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 协议格式说明
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('协议格式', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _buildFormatRow(
                      context,
                      '[文字](fr://lab/demo/Key)',
                      '跳转到指定 Demo',
                    ),
                    _buildFormatRow(
                      context,
                      'fr://lab/demo/悬浮截屏',
                      '跳转到悬浮截屏 Demo',
                    ),
                    _buildFormatRow(context, 'fr://lab/demo/时钟', '跳转到时钟 Demo'),
                    _buildFormatRow(context, 'fr://lab', '跳转到 Lab 首页'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 快速插入
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('快速插入', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: allDemos.map((entry) {
                        return ActionChip(
                          avatar: const Icon(Icons.apps, size: 16),
                          label: Text(entry.value.title),
                          onPressed: () => _insertDemoLink(
                            entry.key,
                            entry.value.title,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _insertDemoLink(String key, String title) {
    final schema = 'fr://lab/demo/$key';
    final link = '[$title]($schema)';
    final text = _inputController.text;
    final selection = _inputController.selection;

    if (selection.isValid) {
      final newText = text.replaceRange(selection.start, selection.end, link);
      _inputController.text = newText;
      _inputController.selection = TextSelection.collapsed(
        offset: selection.start + link.length,
      );
    } else {
      _inputController.text = text + link;
    }
    _updatePreview();
  }

  Widget _buildFormatRow(BuildContext context, String format, String desc) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              format,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(desc, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _MatchInfo {
  final int start;
  final int end;
  final String displayText;
  final String schema;

  const _MatchInfo(this.start, this.end, this.displayText, this.schema);
}

/// 注册 Schema Demo
void registerSchemaDemo() {
  demoRegistry.register(SchemaDemo());
}