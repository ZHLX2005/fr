import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../api/providers/api_providers.dart';
import '../../../core/note/note_root_scope.dart';
import '../../../services/media_service.dart';
import '../../../lab/lab_container.dart';
import 'state.dart';
import 'card.dart';
import 'note_panel.dart';
import 'ai/ai_settings_page.dart';
import 'ai/ai_settings_store.dart';
import 'ai/article_edit_service.dart';
import 'ai/ai_chat_service.dart';


/// 块编辑器 Demo（持久化版）
class BlockEditorDemo extends StatefulWidget {
  const BlockEditorDemo({super.key});

  @override
  State<BlockEditorDemo> createState() => _BlockEditorDemoState();
}

class _BlockEditorDemoState extends State<BlockEditorDemo> {
  late EditorState _editorState;
  bool _editorStateReady = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_editorStateReady) {
      _editorState = EditorState(
        noteFactory: NoteRootScope.of(context).noteRoot,
      );
      _editorStateReady = true;
      // 注入 ArticleEditService（通过 riverpod 拿 endpoint）
      final container = ProviderScope.containerOf(context);
      final endpoint = container.read(articleEndpointProvider);
      _editorState.setArticleEditService(
        ArticleEditService.forEndpoint(endpoint, _editorState.noteFactorySafe),
      );
      // 注入 AiChatService（对话小窗用）
      _editorState.setAiChatService(
        AiChatService.forEndpoint(container.read(aiEndpointProvider)),
      );
      // 加载 AI 配置
      AiSettingsStore().load().then((s) {
        if (mounted) _editorState.updateAiSettings(s);
      });
      _editorState.toolbarFactory.setImportCallbacks(
        onImportMdFile: _importMdFile,
        onImportMdText: _showImportMdTextDialog,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _editorState.init();
      });
    }
  }

  @override
  void initState() {
    super.initState();
  }

  Future<void> _importMdFile() async {
    final result = await MediaService.pickFile(
      type: FileType.custom,
      allowedExtensions: ['md'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    String source;
    if (file.bytes != null) {
      source = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      source = await File(file.path!).readAsString();
    } else {
      return;
    }

    _editorState.importMd(source);
  }

  void _openAiSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiSettingsPage(editorState: _editorState),
      ),
    );
  }

  Future<void> _showImportMdTextDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入 Markdown'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '粘贴 Markdown 文本...',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      _editorState.importMd(result);
    }
  }

  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
          ),
          child: child,
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_editorState, _editorState.toolbarFactory]),
      builder: (context, _) {
        final blocks = _editorState.blocks;
        final selectedId = _editorState.selectedId;
        final colorScheme = Theme.of(context).colorScheme;

        return ScrollbarTheme(
          data: ScrollbarThemeData(
            thumbVisibility: WidgetStateProperty.all(true),
            thickness: WidgetStateProperty.all(8),
            radius: const Radius.circular(4),
            thumbColor: WidgetStateColor.resolveWith((states) {
              if (states.contains(WidgetState.dragged)) {
                return colorScheme.primary.withValues(alpha: 0.95);
              }
              if (states.contains(WidgetState.hovered)) {
                return colorScheme.primary.withValues(alpha: 0.85);
              }
              return colorScheme.primary.withValues(alpha: 0.6);
            }),
          ),
          child: Scaffold(
          appBar: AppBar(
            title: const Text('块编辑器'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'AI 配置',
                onPressed: _openAiSettings,
              ),
              IconButton(
                icon: const Icon(Icons.menu_open),
                onPressed: () {
                  _scaffoldKey.currentState?.openEndDrawer();
                },
                tooltip: '笔记列表',
              ),
            ],
          ),
          key: _scaffoldKey,
          endDrawer: NotePanel(editorState: _editorState),
          bottomNavigationBar: _editorState.toolbarFactory.build(
            context,
            _editorState,
          ),
          // AI 修改后顶部出现的固定条（仅在有 pending 修改时显示）
          persistentFooterButtons: _editorState.hasPendingDiffs
              ? [
                  _AiPendingBar(
                    changeCount: _editorState.pendingChangeCount,
                    onAccept: _editorState.acceptAllPendingDiffs,
                    onReject: _editorState.rejectAllPendingDiffs,
                  ),
                ]
              : null,
          body: blocks.isEmpty
              ? const Center(child: Text('暂无内容，点击 ☰ 新建笔记'))
              : Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ReorderableListView.builder(
                    scrollController: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: blocks.length + 1,
                    onReorder: (oldIndex, newIndex) {
                      if (oldIndex == blocks.length || newIndex == blocks.length) return;
                      _editorState.moveBlock(oldIndex, newIndex);
                    },
                    proxyDecorator: _proxyDecorator,
                    itemBuilder: (context, index) {
                      if (index == blocks.length) {
                        return GestureDetector(
                          key: const ValueKey('__add_block__'),
                          onTap: () => _editorState.addBlock(),
                          behavior: HitTestBehavior.translucent,
                          child: const SizedBox(height: 60),
                        );
                      }
                      final block = blocks[index];
                      return BlockCard(
                        key: ValueKey(block.id),
                        block: block,
                        isSelected: block.id == selectedId,
                        editorState: _editorState,
                      );
                    },
                  ),
                ),
        ),
        );
      },
    );
  }
}

class BlockEditorDemoPage extends DemoPage {
  @override
  String get title => '块编辑器';

  @override
  String get slug => 'block-editor';

  @override
  String get description => '结构化块树笔记编辑器 — 持久化存储';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) => const BlockEditorDemo();
}

void registerBlockEditorDemo() {
  demoRegistry.register(BlockEditorDemoPage());
}

/// AI 修改待确认的顶部条 — 显示变更数 + 接受/拒绝按钮。
class _AiPendingBar extends StatelessWidget {
  final int changeCount;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _AiPendingBar({
    required this.changeCount,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: colorScheme.onPrimaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'AI 修改了 $changeCount 处 — 红色=删除 绿色=新增',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onReject,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('拒绝'),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: onAccept,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('应用'),
            ),
          ],
        ),
      ),
    );
  }
}
