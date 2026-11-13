import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../api/mnws/mnws.dart';
import '../../../../api/mnws/nxnx/nxnx_api.dart';
import '../../../../api/mnws/nxnx/nxnx_models.dart';
import '../../../../core/ui/global/nav/main.dart';
import '../mnws_app_views.dart';
import 'nxnx_create_view.dart';
import 'nxnx_scripts_view.dart';
import 'nxnx_templates_view.dart';

/// nx-nx 的**原生面板**（在 fr 里）。
///
/// ## 与 nx-nx 自己的面板等价
///
/// 三个视图对它的三个视图，一个不少：
///
///   | nx-nx 自己的面板 | 这里 |
///   |---|---|
///   | 新建项目 `create` | [NxNxCreateView] |
///   | 模板 `templates` | [NxNxTemplatesView] |
///   | 脚本 `scripts` | [NxNxScriptsView] |
///
/// 底下是同一套 API（21 条路由全在 [NxNxApi] 里），
/// 区别只在于**界面是 App 自己的 Widget** —— 不在手机上再开个 WebView
/// 去渲染对端的前端。
class NxNxPage extends ConsumerStatefulWidget {
  final MnWsAppTarget target;

  const NxNxPage({super.key, required this.target});

  @override
  ConsumerState<NxNxPage> createState() => _NxNxPageState();
}

class _NxNxPageState extends ConsumerState<NxNxPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  /// **命令表**（bootstrap 下发的）。
  ///
  /// 底下每个视图的「这个按钮的 CLI 等价是什么」都由它派生 ——
  /// 不手写字符串，命令一改提示不会悄悄过期。
  List<NxNxCommand> _commands = const [];

  /// 连接信息：走的是哪台 PC 的哪个应用。
  String get _where => '${widget.target.pcName} · ${widget.target.app}';

  @override
  void initState() {
    super.initState();
    _loadCommands();
  }

  Future<void> _loadCommands() async {
    try {
      final api = nxNxApiOf(widget.target);
      final b = await api.bootstrap(ref.read(mnWsEndpointProvider));
      if (!mounted) return;
      setState(() => _commands = b.commands);
    } on MnWsException {
      // 拉不到命令表不影响主流程 —— 只是底下少一行提示
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = QuickNavBottomBar.bodyBottomReserve(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('nx-nx 项目生成器'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: cs.primary,
          unselectedLabelColor: cs.outline,
          indicatorColor: cs.primary,
          tabs: const [
            Tab(text: '新建项目'),
            Tab(text: '模板'),
            Tab(text: '脚本'),
          ],
        ),
      ),
      body: Column(
        children: [
          // 层次的第一层：这页连的是哪台机器
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
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                NxNxCreateView(target: widget.target, commands: _commands),
                NxNxTemplatesView(target: widget.target, commands: _commands),
                NxNxScriptsView(target: widget.target, commands: _commands),
              ],
            ),
          ),
          SizedBox(height: bottomPad),
        ],
      ),
    );
  }
}

/// 视图共用的「取接口客户端」helper。
///
/// 目标 PC 的 bridgeId 一定要带上 —— 两台机器都跑 nx-nx 时，
/// 不带就打到路由表当前指向的那台去了。
NxNxApi nxNxApiOf(MnWsAppTarget target) => NxNxApi(pc: target.bridgeId);
