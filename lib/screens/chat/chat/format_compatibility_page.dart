import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../services/message_strategy/interfaces/interfaces.dart';
import '../../../services/message_strategy/factory/factory.dart';
import '../../../services/message_strategy/panel/panel.dart';
import '../../../services/message_strategy/data/card_manager_message_data.dart';

/// 格式兼容性 / 消息策略聚合测试页。
///
/// 监听全局 [MessagePanelController]，统一渲染所有消息卡片：
/// - 输入 type 或点 chip → 追加对应 mock 卡
/// - card_manager 卡作为调度入口，点其按钮可追加其它卡或启动登录/注册流程
///
/// 登录、注册等交互卡片都 append 到同一个全局控制器，在此页统一展示，
/// 不再为它们单独建页面。
class FormatCompatibilityPage extends StatefulWidget {
  const FormatCompatibilityPage({super.key});

  @override
  State<FormatCompatibilityPage> createState() =>
      _FormatCompatibilityPageState();
}

class _FormatCompatibilityPageState extends State<FormatCompatibilityPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();

  late final MessagePanelController _panel;
  late final MessageWidgetFactory _factory;
  late final List<String> _supportedTypes;

  @override
  void initState() {
    super.initState();
    _panel = GetIt.instance<MessagePanelController>();
    _factory = GetIt.instance<MessageWidgetFactory>();
    _supportedTypes = _factory.supportedTypes;
    // 进入时若面板为空，放一张 card_manager 卡作为调度入口
    if (_panel.isEmpty) {
      _panel.append(const CardManagerMessageData());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
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

  void _handleSend(String type) {
    final t = type.trim().toLowerCase();
    if (t.isEmpty) return;
    if (!_supportedTypes.contains(t)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('不支持的 type: $t，支持: ${_supportedTypes.join(", ")}'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    _inputController.clear();
    _panel.append(_factory.getMockData(t));
  }

  void _reset() {
    _panel.clear();
    _panel.append(const CardManagerMessageData());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Icon(
                Icons.format_align_left,
                size: 18,
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Format 测试', style: TextStyle(fontSize: 16)),
                  Text(
                    '消息策略聚合（含登录/注册）',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reset,
            tooltip: '重置',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: _panel,
              builder: (context, _) {
                final messages = _panel.messages;
                _scrollToBottom();
                if (messages.isEmpty) {
                  return const Center(child: Text('面板为空'));
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index];
                    return _FormatMessageBubble(
                      key: ValueKey(m.id),
                      typeName: m.data.type,
                      factory: _factory,
                      data: m.data,
                    );
                  },
                );
              },
            ),
          ),
          _TypeChipStrip(
            types: _supportedTypes,
            onTap: (type) {
              _inputController.text = type;
              _inputController.selection = TextSelection.collapsed(
                offset: type.length,
              );
            },
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                decoration: InputDecoration(
                  hintText: '输入 type (text/login/register/card_manager)...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                maxLines: 1,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (value) => _handleSend(value),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: () => _handleSend(_inputController.text),
                icon: const Icon(Icons.send, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatMessageBubble extends StatelessWidget {
  final String typeName;
  final MessageWidgetFactory factory;
  final IMessageData data;

  const _FormatMessageBubble({
    super.key,
    required this.typeName,
    required this.factory,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.95,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                typeName.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.zero,
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: factory.create(context, data),
            ),
          ],
        ),
      ),
    );
  }
}

/// 可左右滑动的 type 胶囊行 — 点击填入输入框
class _TypeChipStrip extends StatelessWidget {
  final List<String> types;
  final ValueChanged<String> onTap;

  const _TypeChipStrip({required this.types, required this.onTap});

  static IconData _iconFor(String type) {
    switch (type) {
      case 'text':
        return Icons.short_text;
      case 'markdown':
        return Icons.code;
      case 'html':
        return Icons.html;
      case 'login':
        return Icons.login;
      case 'register':
        return Icons.person_add;
      case 'card_manager':
        return Icons.dashboard_customize;
      default:
        return Icons.chat_bubble_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: types.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = types[index];
          return Center(
            child: ActionChip(
              avatar: Icon(_iconFor(type), size: 16),
              label: Text(type),
              onPressed: () => onTap(type),
            ),
          );
        },
      ),
    );
  }
}
