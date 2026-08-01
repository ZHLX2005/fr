import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../services/message_strategy/factory/factory.dart';
import '../../../services/message_strategy/panel/panel.dart';
import '../../../services/message_strategy/data/card_manager_message_data.dart';

/// CardManager 面板演示页。
///
/// 监听全局 [MessagePanelController]，把控制器里的消息渲染成卡片流。
/// 初始放入一张 [CardManagerMessageData] 作为「调度中枢」，点它的按钮
/// 即可经全局控制器追加其它卡片 —— 验证「全局对象操作整个面板」。
class CardManagerPanelPage extends StatefulWidget {
  const CardManagerPanelPage({super.key});

  @override
  State<CardManagerPanelPage> createState() => _CardManagerPanelPageState();
}

class _CardManagerPanelPageState extends State<CardManagerPanelPage> {
  final ScrollController _scrollController = ScrollController();
  late final MessagePanelController _panel;
  late final MessageWidgetFactory _factory;

  @override
  void initState() {
    super.initState();
    _panel = GetIt.instance<MessagePanelController>();
    _factory = GetIt.instance<MessageWidgetFactory>();
    // 进入页面时若面板为空，先放一张 card_manager 卡作为调度中枢
    if (_panel.isEmpty) {
      _panel.append(const CardManagerMessageData());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (pos.maxScrollExtent.isFinite) {
        _scrollController.animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _reset() {
    _panel.clear();
    _panel.append(const CardManagerMessageData());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CardManager 面板'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: '重置',
            onPressed: _reset,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _panel,
        builder: (context, _) {
          final messages = _panel.messages;
          _scrollToBottom();

          if (messages.isEmpty) {
            return const Center(child: Text('面板为空'));
          }

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final m = messages[index];
              return Padding(
                key: ValueKey(m.id),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _PanelBubble(child: _factory.create(context, m.data)),
              );
            },
          );
        },
      ),
    );
  }
}

class _PanelBubble extends StatelessWidget {
  final Widget child;

  const _PanelBubble({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
        ),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.zero,
            bottomRight: Radius.circular(16),
          ),
        ),
        child: child,
      ),
    );
  }
}
