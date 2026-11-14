import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../api/mnws/mnws.dart';
import '../../../../core/ui/global/nav/main.dart';
import '../mnws_app_views.dart';
import 'nxkv_contract_view.dart';
import 'nxkv_controller.dart';
import 'nxkv_queue_view.dart';
import 'nxkv_topics_view.dart';

/// nx-kv 的**原生面板**（在 fr 里）。
///
/// ## 与 nx-kv 自己的面板对位
///
///   | nx-kv 面板 | 这里 |
///   |---|---|
///   | 任务页（主题 + 队列） | [NxKvQueueView] / [NxKvTopicsView] |
///   | 契约与能力 | [NxKvContractView] |
///
/// 底下全是同一份**生成出来的**客户端（`package:nx_kv_client`），
/// 页面里没有一行手写 HTTP：nx-kv 加一条 action，端侧 `pub upgrade` 就能用。
/// 这正是「fr 只维护 UI」的字面意思。
///
/// ## 为什么第一屏是队列而不是主题总览
///
/// 手机上打开这个页面的人，八成是「想知道现在有什么活、领一条看看」。
/// 主题总览是配置视角，放第二个 tab，不抢第一屏。
class NxKvPage extends ConsumerStatefulWidget {
  const NxKvPage({super.key, required this.target});

  final MnWsAppTarget target;

  @override
  ConsumerState<NxKvPage> createState() => _NxKvPageState();
}

class _NxKvPageState extends ConsumerState<NxKvPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  NxKvController? _controller;

  /// 连接信息：走的是哪台 PC 的哪个应用。
  String get _where => '${widget.target.pcName} · ${widget.target.app}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 端点要从 riverpod 拿，所以不能在 initState 里建
    if (_controller != null) return;
    final c = NxKvController(
      target: widget.target,
      endpoint: ref.read(mnWsEndpointProvider),
    );
    _controller = c;
    c.bootstrap();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();
    final bottomPad = QuickNavBottomBar.bodyBottomReserve(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('nx-kv 任务队列'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: c.bootstrap,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: cs.primary,
          unselectedLabelColor: cs.outline,
          indicatorColor: cs.primary,
          tabs: const [
            Tab(text: '队列'),
            Tab(text: '主题'),
            Tab(text: '契约'),
          ],
        ),
      ),
      body: Column(
        children: [
          // 层次的第一层：这页连的是哪台机器；顺手把「契约是否过期」摆在明面上
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(Icons.computer_outlined, size: 14, color: cs.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '经 $_where  ·  ${widget.target.bridgeId}',
                    style: TextStyle(fontSize: 11, color: cs.outline),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 契约胶囊：对不上就会变红并可点，点进「契约」页看差在哪
                AnimatedBuilder(
                  animation: c,
                  builder: (_, _) {
                    final drift = c.drift != null;
                    return InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => _tabs.animateTo(2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          border: Border.all(color: drift ? cs.error : cs.outlineVariant),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          drift ? '契约过期' : '契约 ${c.localHash}',
                          style: TextStyle(fontSize: 9, color: drift ? cs.error : cs.outline),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                // 队列页自己监听 controller（它要顺带重拉清单），别再套一层
                NxKvQueueView(controller: c),
                AnimatedBuilder(
                  animation: c,
                  builder: (_, _) => NxKvTopicsView(
                    controller: c,
                    onOpen: (key) {
                      c.select(key);
                      _tabs.animateTo(0);
                    },
                  ),
                ),
                AnimatedBuilder(animation: c, builder: (_, _) => NxKvContractView(controller: c)),
              ],
            ),
          ),
          SizedBox(height: bottomPad),
        ],
      ),
    );
  }
}
