import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../interfaces/interfaces.dart';
import '../factory/factory.dart';
import '../panel/panel.dart';
import '../data/card_manager_message_data.dart';
import '../data/login_message_data.dart';

/// Strategy for rendering Card Manager messages.
///
/// 卡片本身不含交互态——按钮直接调用全局 [MessagePanelController]，
/// 把其它类型的卡片追加到面板，演示「任意按钮唤醒卡片」。
/// 上半部分追加 mock 卡片；下半部分是「登录 / 注册」真实交互入口。
class CardManagerMessageWidgetStrategy
    extends MessageWidgetStrategy<CardManagerMessageData> {
  @override
  Widget build(BuildContext context, CardManagerMessageData data) {
    return _CardManagerContent(data: data);
  }

  @override
  CardManagerMessageData createMockData() => const CardManagerMessageData();
}

class _CardManagerContent extends StatelessWidget {
  final CardManagerMessageData data;

  const _CardManagerContent({required this.data});

  /// 可追加的 mock 卡片按钮：复用 MessageWidgetFactory 已注册的 mock 数据
  static const _buttons = <_CardKind>[
    _CardKind(icon: Icons.short_text, label: '文本卡', type: 'text'),
    _CardKind(icon: Icons.edit_note, label: 'Ask 卡', type: 'ask'),
    _CardKind(icon: Icons.checklist, label: '选择卡', type: 'selection'),
    _CardKind(icon: Icons.code, label: 'Markdown', type: 'markdown'),
    _CardKind(icon: Icons.water_drop_outlined, label: '水位卡', type: 'water'),
  ];

  void _appendCard(String type) {
    final panel = GetIt.instance<MessagePanelController>();
    final factory = GetIt.instance<MessageWidgetFactory>();
    panel.append(factory.getMockData(type));
  }

  void _appendLogin() {
    GetIt.instance<MessagePanelController>().append(const LoginMessageData());
  }

  void _startRegister() {
    GetIt.instance<RegisterFlowController>().start();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.tertiary.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.dashboard_customize,
                  size: 18, color: theme.colorScheme.tertiary),
              const SizedBox(width: 6),
              Text(
                data.title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '点按钮追加卡片到面板（经全局 MessagePanelController）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _buttons
                .map((b) => ActionChip(
                      avatar: Icon(b.icon, size: 16),
                      label: Text(b.label),
                      onPressed: () => _appendCard(b.type),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _appendLogin,
                  icon: const Icon(Icons.login, size: 18),
                  label: const Text('登录卡'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _startRegister,
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('开始注册'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardKind {
  final IconData icon;
  final String label;
  final String type;

  const _CardKind({
    required this.icon,
    required this.label,
    required this.type,
  });
}
