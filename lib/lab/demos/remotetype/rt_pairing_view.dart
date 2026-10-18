// lib/lab/demos/remotetype/rt_pairing_view.dart
//
// 配对页 UI（纯展示）：统一登录「我名下的电脑，点一下即连」+ 服务端没开
// 统一登录时的「选 PC + 填配对 key」兜底，两态由 unified 决定。
// 状态与连接编排都在 rt_page，这里只收 props 和回调。

import 'package:flutter/material.dart';

import '../../../api/remotetype/remotetype.dart';
import '../../../core/theme/colors/strategy/color_strategy/color_strategy.dart';
import '../../../services/remotetype/remotetype_service.dart';
import '../../../core/theme/context/colors.dart';
import 'rt_constants.dart';

/// 配对页（两态）。
class RtPairingView extends StatelessWidget {
  const RtPairingView({
    super.key,
    required this.unified,
    required this.readiness,
    required this.error,
    required this.connecting,
    required this.clientsLoading,
    required this.clients,
    required this.computers,
    required this.selectedClient,
    required this.keyController,
    required this.onRefresh,
    required this.onSelectClient,
    required this.onConnect,
  });

  /// 统一登录是否可用；null = 还没探完，UI 不预设任何一条路径。
  final bool? unified;
  final RemoteTypeReadiness? readiness;
  final String? error;
  final bool connecting;
  final bool clientsLoading;
  final List<String> clients;
  final List<RtComputer> computers;
  final String? selectedClient;
  final TextEditingController keyController;

  /// 刷新电脑/PC 列表（unified 态在 loading 期间禁用，兜底态不禁——对齐原行为）。
  final VoidCallback onRefresh;
  final ValueChanged<String> onSelectClient;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    // Scaffold 已关 resizeToAvoidBottomInset：这里用 viewInsets 把整块内容
    // 抬到键盘上方，SingleChildScrollView 保证极小屏仍可滚动
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.keyboard_alt_outlined, size: 56, color: c.text),
              const SizedBox(height: 12),
              Text(
                '把手机变成电脑的输入设备',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 24),
              if (unified == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (unified!)
              // ── 统一登录：我名下的电脑，点一下即连（无显式连接按钮）──
              ...[
                _sectionHead(
                  context,
                  title: '我的电脑',
                  onRefresh: clientsLoading ? null : onRefresh,
                ),
                if (computers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      clientsLoading
                          ? '正在获取你的电脑…'
                          : '还没有登记在你名下的电脑。\n'
                                '电脑删执行执行 npx nx-rt 即可。',
                      style: TextStyle(color: c.textMuted),
                    ),
                  )
                else
                  ...computers.map((c) => _buildComputerTile(context, c)),
              ] else
              // ── 兜底：服务端没开统一登录，回到手工配对 key ───────────────
              ...[
                if (readiness != null && readiness!.reason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      readiness!.reason,
                      style: TextStyle(fontSize: 12, color: c.textMuted),
                    ),
                  ),
                _sectionHead(context, title: '① 选择电脑', onRefresh: onRefresh),
                if (clients.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      clientsLoading
                          ? '正在获取在线 PC…'
                          : '暂无 PC 上线——请先在电脑上运行 remotetype serve --align',
                      style: TextStyle(color: c.textMuted),
                    ),
                  )
                else
                  ...clients.map(
                    (cid) => _ClientTile(
                      clientId: cid,
                      selected: cid == selectedClient,
                      colors: c,
                      onTap: () => onSelectClient(cid),
                    ),
                  ),
                const SizedBox(height: 8),
                Text('② 配对 key', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: keyController,
                  cursorColor: cs.primary,
                  decoration: InputDecoration(
                    hintText: '电脑端 remotetype serve --align 打印的 key',
                    filled: true,
                    fillColor: c.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: connecting ? null : onConnect,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(connecting ? '连接中…' : '实时同步连接'),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: TextStyle(color: cs.error)),
              ],
              const SizedBox(height: 28),
              Text(
                unified == true
                    ? '同一账号自动配对 · 端到端加密\n无需复制 key'
                    : '端到端加密：文本在手机加密、电脑解密，中转服务器只经手密文。\n'
                          'key 即凭据，请勿外传。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: c.textMuted,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHead(
    BuildContext context, {
    required String title,
    VoidCallback? onRefresh,
  }) {
    final c = context.colors;
    final cs = c.scheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
            ),
          ),
          const Spacer(),
          Material(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onRefresh,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Text(
                  '刷新',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 一台我名下的电脑。整行可点即连——无显式「连接」按钮（对齐原型 .pc）。
  Widget _buildComputerTile(BuildContext context, RtComputer c) {
    final colors = context.colors;
    final cs = colors.scheme;
    final online = c.online;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: online ? 1 : 0.5,
        child: Material(
          color: colors.surface,
          elevation: 1,
          shadowColor: cs.shadow.withValues(alpha: 0.06),
          surfaceTintColor: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: online && !connecting
                ? () {
                    onSelectClient(c.clientId);
                    onConnect();
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          online
                              ? Icons.desktop_windows
                              : Icons.desktop_access_disabled,
                          size: 22,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      if (online)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.surface,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colors.text,
                          ),
                        ),
                        Text(
                          c.clientId,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    online ? '在线 · 点击连接' : '不在线',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.textMuted,
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

/// 兜底态的一台在线 PC（单选行）。
class _ClientTile extends StatelessWidget {
  const _ClientTile({
    required this.clientId,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String clientId;
  final bool selected;
  final ColorStrategy colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final cs = c.scheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.surface,
        elevation: 1,
        shadowColor: cs.shadow.withValues(alpha: 0.06),
        surfaceTintColor: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: selected ? cs.primary : c.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    clientId,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                Text(
                  selected ? '已选' : '在线',
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
