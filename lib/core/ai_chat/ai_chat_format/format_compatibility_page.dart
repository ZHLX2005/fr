import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../services/message_strategy/interfaces/interfaces.dart';
import '../../../services/message_strategy/factory/factory.dart';
import '../../../services/message_strategy/panel/panel.dart';

/// 格式兼容性 / 消息策略聚合测试页。
///
/// 监听全局 [MessagePanelController]，统一渲染所有消息卡片：
/// - 输入 type 或点 chip → 追加对应 mock 卡
/// - card_manager 卡本身也是一张普通卡（输入 `card_manager` 唤出），
///   唤出后可作为调度入口，点其按钮追加其它卡或启动登录/注册流程
///
/// 面板不预置任何卡片 —— 所有卡片（含 card_manager）一律通过底部输入唤出，
/// 不 pin 任何一张，保证面板初始为空、内容完全由用户驱动。
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
    // 不预置任何卡片：card_manager 与其它卡一视同仁，由底部输入唤出
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

  /// 重置 = 清空面板（不回填 card_manager，保持"全部由输入唤出"）
  void _reset() {
    _panel.clear();
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
                  return _buildEmptyHint();
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

  /// 空面板提示 —— 面板初始为空是正常状态，引导用户从底部唤出卡片。
  Widget _buildEmptyHint() {
    final theme = Theme.of(context);
    final hintColor = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 44,
              color: hintColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              '面板为空',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: hintColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '在底部输入 type 或点下方胶囊唤出卡片\n'
              '输入 card_manager 可唤出卡片管理器',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: hintColor.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
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
                  // §0.1：输入框 fillColor 用 lerp 浅主题色
                  fillColor: Color.lerp(
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).colorScheme.primaryContainer,
                    0.2,
                  ),
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
            _SendButton(
              onPressed: () => _handleSend(_inputController.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// 发送按钮 — 边框强调式圆形图标按钮
class _SendButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _SendButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    return Container(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        shape: BoxShape.circle,
        border: Border.all(
          color: accent.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: IconButton(
        onPressed: onPressed,
        tooltip: '发送',
        icon: Icon(Icons.send, color: accent),
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
