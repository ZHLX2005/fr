// lib/core/chess/p2p/chess_room_config_page.dart
//
// 国际象棋建房配置页（v6）—— 创建房间前的角色与残局首手方显式配置。
//
// ## 流程
//
// lobby page（ChessLobbyPage）输入昵称 + 房间号 →
// 用户点 "创建房间" → push 本页 →
// 用户显式选择 host/guest 配色（执白/执黑/随机）与残局 first_moker（黑先/白先）→
// 点 "创建房间" → onSubmit(ChessRoomConfig) → Navigator.pop(cfg) →
// lobby page 拿到 cfg 后调 tryJoinOrCreate(initialParams={host_color, first_mover, ...})
//
// ## 与 chess_lobby_page 的分工
//
// · lobby page: 输入昵称 + 房间号，提供 "创建房间" / "加入房间" 两个按钮
// · 本页: 只承担"我是房主"的子流程（角色 + first_moker）；guest 路径根本不进本页
// · chess_room_page: 拿到 snapshot 后渲染对局 UI（lobby card / playing board / ended card）
//
// ## ChessRoomConfig 字段语义
//
//   hostColor  = 'w' / 'b' / 'random'
//   guestColor = 'w' / 'b' / null（random 时 null：服务端掷筛后写 c.host_color，
//                                      guest 与 host 执子色相反）
//   firstMover = 'w' / 'b'
//                标准开局永远 'w'（白方先走是棋规）；残局模式用户在 UI 显式选
//
// 服务端契约：ChessRoomConfig 三字段都映射到 initialParams（host_color, guest_color, first_mover）。
// 服务端 Lua 读取 host_color → c.host_color；first_mover（v6 新增）→ c.initial_side 覆盖。

import 'package:flutter/material.dart';

import '../../net_engine/relay_v3/relay_v3_transport.dart';
import '../endgame/chess_endgame.dart';

/// 建房配置结果 —— 由 ChessRoomConfigPage 提交时通过 onSubmit / Navigator.pop 返回。
@immutable
class ChessRoomConfig {
  /// 'w' / 'b' / 'random'。'random' 时服务端掷筛后写 c.host_color。
  final String hostColor;

  /// 'w' / 'b' / null。null 当且仅当 hostColor == 'random'（服务端掷筛决定）。
  final String? guestColor;

  /// 'w' / 'b'。标准开局 = 'w'（白方先走，棋规）；残局 = UI 显式选择。
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

/// 建房配置页 —— 单组二选一 chip 选 host/guest 配色，残局模式额外选 first_moker。
class ChessRoomConfigPage extends StatefulWidget {
  const ChessRoomConfigPage({
    super.key,
    required this.alias,
    required this.code,
    required this.endgame,
    required this.relayUrl,
    required this.onSubmit,
    this.transportBuilder,
  });

  /// 昵称（lobby 已填好）。
  final String alias;

  /// 房间号（4-6 位大写字母数字）。
  final String code;

  /// 残局快照（非 null → 显示 first_moker 二选一 chip）。
  final ChessEndgameSnapshot? endgame;

  /// Relay URL（透传给 transport，不在 config 页内联）。
  final String relayUrl;

  /// 提交回调：用户在 config 页按"创建房间" → onSubmit(ChessRoomConfig) →
  /// 上层（lobby page）拿到 cfg 后调 tryJoinOrCreate。
  final void Function(ChessRoomConfig onSubmit) onSubmit;

  /// 测试注入：自定义 transport 构造。
  final RelayV3Transport Function(String alias, String deviceId)?
      transportBuilder;

  @override
  State<ChessRoomConfigPage> createState() => _ChessRoomConfigPageState();
}

/// host/guest 配色选择。
enum _ColorChoice { hostWhite, hostBlack, random }

/// 残局 first_moker 二选一（标准开局棋规白先，不暴露此 enum）。
enum _FirstMoverChoice { blackFirst, whiteFirst }

class _ChessRoomConfigPageState extends State<ChessRoomConfigPage> {
  // host/guest 配色：单组二选一 chip，互斥。
  _ColorChoice _colorChoice = _ColorChoice.hostWhite;

  // 残局 first_moker：默认黑先（多数 puzzles 是黑先和棋类；用户在 UI 可改白先）。
  _FirstMoverChoice _firstMover = _FirstMoverChoice.blackFirst;

  ChessRoomConfig _buildConfig() {
    final hostGuest = switch (_colorChoice) {
      _ColorChoice.hostWhite => ('w', 'b'),
      _ColorChoice.hostBlack => ('b', 'w'),
      _ColorChoice.random => ('random', null as String?),
    };
    final firstMover = widget.endgame != null
        ? (_firstMover == _FirstMoverChoice.blackFirst ? 'b' : 'w')
        : 'w'; // 标准开局棋规：白方永远先走
    return ChessRoomConfig(
      hostColor: hostGuest.$1,
      guestColor: hostGuest.$2,
      firstMover: firstMover,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEndgame = widget.endgame != null;
    final endgame = widget.endgame;
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
            padding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. 房间信息条（残局时显示）
                  if (isEndgame) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.3),
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
                              '残局：${endgame!.label ?? '快照'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 2. host/guest 配色
                  Text(
                    '执子角色',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: [
                      _colorRow(
                        value: _ColorChoice.hostWhite,
                        icon: Icons.circle_outlined,
                        label: '我执白，他执黑',
                        sublabel: '（我先手）',
                      ),
                      const SizedBox(height: 6),
                      _colorRow(
                        value: _ColorChoice.hostBlack,
                        icon: Icons.lens_outlined,
                        label: '我执黑，他执白',
                        sublabel: '（我后手）',
                      ),
                      const SizedBox(height: 6),
                      _colorRow(
                        value: _ColorChoice.random,
                        icon: Icons.shuffle,
                        label: '随机掷筛',
                        sublabel: '（建房瞬间决定）',
                      ),
                    ],
                  ),

                  // 3. 残局模式额外：first_moker 二选一
                  if (isEndgame) ...[
                    const SizedBox(height: 20),
                    Text(
                      '下一步棋（first_mover）',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _firstMoverButton(
                            value: _FirstMoverChoice.blackFirst,
                            label: '黑先',
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _firstMoverButton(
                            value: _FirstMoverChoice.whiteFirst,
                            label: '白先',
                          ),
                        ),
                      ],
                    ),
                  ],

                  // 4. 规则提示
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            '◐',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _hintText(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.75),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 5. 创建按钮
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _submit,
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

  /// 单选 chip 行：host/guest 配色。
  Widget _colorRow({
    required _ColorChoice value,
    required IconData icon,
    required String label,
    required String sublabel,
  }) {
    final theme = Theme.of(context);
    final selected = _colorChoice == value;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _colorChoice = value),
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

  /// first_moker 单选按钮：残局模式强制二选一。
  Widget _firstMoverButton({
    required _FirstMoverChoice value,
    required String label,
  }) {
    final theme = Theme.of(context);
    final selected = _firstMover == value;
    return OutlinedButton(
      onPressed: () => setState(() => _firstMover = value),
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

  /// 规则提示文案（动态）：根据 host/guest + first_mover。
  String _hintText() {
    final isEndgame = widget.endgame != null;
    final firstMover = isEndgame
        ? (_firstMover == _FirstMoverChoice.blackFirst ? '黑' : '白')
        : '白'; // 标准开局棋规白先
    switch (_colorChoice) {
      case _ColorChoice.hostWhite:
        if (isEndgame) {
          return '你执白（${firstMover == '白' ? '先手' : '后手'}），对方执黑（${firstMover == '黑' ? '先手' : '后手'}）。'
              '残局从$firstMover 方先走 —— 你选执白时若残局是黑先，对方（执黑）走第一步。';
        }
        return '你执白（先手），对方执黑（后手）。白方棋规先走。';
      case _ColorChoice.hostBlack:
        if (isEndgame) {
          return '你执黑（${firstMover == '黑' ? '先手' : '后手'}），对方执白（${firstMover == '白' ? '先手' : '后手'}）。'
              '残局从$firstMover 方先走 —— 你选执黑时若残局是白先，对方（执白）走第一步。';
        }
        return '你执黑（后手），对方执白（先手）。白方棋规先走。';
      case _ColorChoice.random:
        if (isEndgame) {
          return '建房瞬间服务端掷筛决定你的执子颜色。'
              '残局从$firstMover 方先走 —— 若掷筛后你执${firstMover == '黑' ? '黑' : '白'}，你走第一步。';
        }
        return '建房瞬间服务端掷筛决定你的执子颜色。白方棋规先走。';
    }
  }

  void _submit() {
    widget.onSubmit(_buildConfig());
  }
}
