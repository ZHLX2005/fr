// lib/core/chess/p2p/chess_room_config_page.dart
//
// 国际象棋房间规则面板（v7）—— 准备阶段由房主配置执子色 / 残局先手。
//
// ## 流程（v7）
//
// 单入口「进入对局」→ tryJoinOrCreate（先到 = 房主）→ ChessRoomPage 准备卡
// → 房主在本面板改规则 → SET_RULES → 双方重新准备 → DEAL 开局。
//
// 旧版「创建房间前 push 全屏配置页」已废弃；本文件保留 ChessRoomConfig
// 数据类 + 可嵌入的 ChessRoomRulesPanel。

import 'package:flutter/material.dart';

import '../endgame/chess_endgame.dart';

/// 房间规则结果 —— 映射到 SET_RULES / 历史 initialParams。
@immutable
class ChessRoomConfig {
  /// 'w' / 'b' / 'random'。'random' 时服务端掷筛后写 c.host_color。
  final String hostColor;

  /// 'w' / 'b' / null。null 当且仅当 hostColor == 'random'。
  final String? guestColor;

  /// 'w' / 'b'。标准开局 = 'w'；残局 = UI 显式选择。
  final String firstMover;

  const ChessRoomConfig({
    required this.hostColor,
    required this.guestColor,
    required this.firstMover,
  });

  @override
  String toString() =>
      'ChessRoomConfig(host: $hostColor, guest: $guestColor, first: $firstMover)';
}

/// host/guest 配色选择。
enum ChessColorChoice { hostWhite, hostBlack, random }

/// 残局 first_mover 二选一。
enum ChessFirstMoverChoice { blackFirst, whiteFirst }

/// 准备阶段规则面板 —— 可嵌入 lobby/ready 卡片。
///
/// [editable]=true（房主）时点选即 [onChanged]；guest 只读展示当前规则。
class ChessRoomRulesPanel extends StatelessWidget {
  const ChessRoomRulesPanel({
    super.key,
    required this.editable,
    required this.hostColor,
    required this.firstMover,
    required this.isEndgame,
    this.endgameLabel,
    this.onChanged,
    this.onPickEndgame,
    this.onClearEndgame,
  });

  /// 房主可改；guest 只读。
  final bool editable;

  /// 当前服务端权威 host 执子色（'w' / 'b'；random 已在服务端解析）。
  final String hostColor;

  /// 当前 first_mover（'w' / 'b'）。
  final String firstMover;

  /// 是否残局房。
  final bool isEndgame;

  /// 残局显示名。
  final String? endgameLabel;

  /// 房主改执子色 / first_mover 时回调。
  final ValueChanged<ChessRoomConfig>? onChanged;

  /// 房主打开残局库。
  final VoidCallback? onPickEndgame;

  /// 房主清除残局 → 标准开局。
  final VoidCallback? onClearEndgame;

  ChessColorChoice get _colorChoice {
    if (hostColor == 'b') return ChessColorChoice.hostBlack;
    return ChessColorChoice.hostWhite;
  }

  ChessFirstMoverChoice get _firstChoice => firstMover == 'b'
      ? ChessFirstMoverChoice.blackFirst
      : ChessFirstMoverChoice.whiteFirst;

  ChessRoomConfig _configFor(ChessColorChoice color, ChessFirstMoverChoice first) {
    final hostGuest = switch (color) {
      ChessColorChoice.hostWhite => ('w', 'b'),
      ChessColorChoice.hostBlack => ('b', 'w'),
      ChessColorChoice.random => ('random', null as String?),
    };
    return ChessRoomConfig(
      hostColor: hostGuest.$1,
      guestColor: hostGuest.$2,
      firstMover: isEndgame
          ? (first == ChessFirstMoverChoice.blackFirst ? 'b' : 'w')
          : 'w',
    );
  }

  void _emitColor(ChessColorChoice color) {
    if (!editable || onChanged == null) return;
    onChanged!(_configFor(color, _firstChoice));
  }

  void _emitFirst(ChessFirstMoverChoice first) {
    if (!editable || onChanged == null) return;
    onChanged!(_configFor(_colorChoice, first));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          editable ? '房间规则（仅房主可改）' : '房间规则',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        if (isEndgame) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.extension_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '残局：${endgameLabel ?? '快照'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (editable && onClearEndgame != null)
                  GestureDetector(
                    onTap: onClearEndgame,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (editable) ...[
          _colorRow(
            context,
            value: ChessColorChoice.hostWhite,
            icon: Icons.circle_outlined,
            label: '我执白，他执黑',
            sublabel: isEndgame ? '' : '（我先手）',
          ),
          const SizedBox(height: 6),
          _colorRow(
            context,
            value: ChessColorChoice.hostBlack,
            icon: Icons.lens_outlined,
            label: '我执黑，他执白',
            sublabel: isEndgame ? '' : '（我后手）',
          ),
          const SizedBox(height: 6),
          _colorRow(
            context,
            value: ChessColorChoice.random,
            icon: Icons.shuffle,
            label: '随机掷筛',
            sublabel: '（立即决定）',
            forceUnselected: true,
          ),
          if (isEndgame) ...[
            const SizedBox(height: 12),
            Text(
              '下一步棋',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _firstMoverButton(
                    context,
                    value: ChessFirstMoverChoice.blackFirst,
                    label: '黑先',
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _firstMoverButton(
                    context,
                    value: ChessFirstMoverChoice.whiteFirst,
                    label: '白先',
                  ),
                ),
              ],
            ),
          ],
          if (onPickEndgame != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onPickEndgame,
              icon: const Icon(Icons.extension_outlined, size: 18),
              label: Text(isEndgame ? '更换残局' : '选择残局'),
            ),
          ],
        ] else ...[
          Text(
            _guestSummary(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  String _guestSummary() {
    final hostSide = hostColor == 'b' ? '黑' : '白';
    final first = firstMover == 'b' ? '黑' : '白';
    if (isEndgame) {
      return '房主执$hostSide；残局「${endgameLabel ?? '快照'}」由$first方先走。';
    }
    return '房主执$hostSide；标准开局，白方先走。';
  }

  Widget _colorRow(
    BuildContext context, {
    required ChessColorChoice value,
    required IconData icon,
    required String label,
    required String sublabel,
    bool forceUnselected = false,
  }) {
    final theme = Theme.of(context);
    final selected = !forceUnselected && _colorChoice == value;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: editable ? () => _emitColor(value) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    TextSpan(
                      text: label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    if (sublabel.isNotEmpty)
                      TextSpan(
                        text: '  $sublabel',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (selected)
              Icon(
                Icons.check_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _firstMoverButton(
    BuildContext context, {
    required ChessFirstMoverChoice value,
    required String label,
  }) {
    final theme = Theme.of(context);
    final selected = _firstChoice == value;
    return OutlinedButton(
      onPressed: editable ? () => _emitFirst(value) : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        minimumSize: const Size(0, 44),
        backgroundColor: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : null,
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: selected ? 1.6 : 1.0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// 兼容旧测试 / 全屏编辑入口 —— 内嵌 [ChessRoomRulesPanel] + 提交按钮。
class ChessRoomConfigPage extends StatefulWidget {
  const ChessRoomConfigPage({
    super.key,
    required this.alias,
    required this.code,
    required this.endgame,
    required this.onSubmit,
    this.relayUrl = '',
  });

  final String alias;
  final String code;
  final ChessEndgameSnapshot? endgame;
  final void Function(ChessRoomConfig onSubmit) onSubmit;
  final String relayUrl;

  @override
  State<ChessRoomConfigPage> createState() => _ChessRoomConfigPageState();
}

class _ChessRoomConfigPageState extends State<ChessRoomConfigPage> {
  late String _hostColor;
  late String _firstMover;

  @override
  void initState() {
    super.initState();
    _hostColor = 'w';
    _firstMover = widget.endgame != null ? 'b' : 'w';
  }

  ChessRoomConfig get _config {
    final guest = _hostColor == 'random'
        ? null
        : (_hostColor == 'w' ? 'b' : 'w');
    return ChessRoomConfig(
      hostColor: _hostColor,
      guestColor: guest,
      firstMover: widget.endgame != null ? _firstMover : 'w',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '房间 ${widget.code}',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              '创建者：${widget.alias}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ChessRoomRulesPanel(
                    editable: true,
                    hostColor: _hostColor == 'random' ? 'w' : _hostColor,
                    firstMover: _firstMover,
                    isEndgame: widget.endgame != null,
                    endgameLabel: widget.endgame?.label,
                    onChanged: (cfg) {
                      setState(() {
                        _hostColor = cfg.hostColor;
                        _firstMover = cfg.firstMover;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => widget.onSubmit(_config),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '创建房间',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
