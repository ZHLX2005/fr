// 设置页骨架家族——「无边框色块」配方（灰底画布 + 卡面 surface，明度分层）。
//
// 规范样板 = 远程输入设置页（RtSettingsPage）；配方出处 = App 设置页
// _GeneralCard 的做法（App 自身设置不消费本家族，本家族服务 demo 模块的
// 设置页）。层次全靠明度差：画布 surfaceContainerHighest、卡面 surface，
// 不用投影、不用描边。
//
// 组成（一类一职责）：
// - SettingsPageScaffold   页面壳：灰底画布 + AppNavBar.standard + ListView
// - SettingsSectionHeader  分区标题（卡外，缩进 20，上 18 下 6）
// - SettingsCard           偏好白卡（圆角 16；ListTile 行直接放，表单页传 padding）
// - SettingsCardSeparator  卡内行分隔（缩进 16 细线）
//
// 用法：壳 children = [Header, Card, Header, Card, …]（rows 自带内边距，
// 行间插 Separator）；自管滚动的页面传 body 而不是 children（二选一）。
// 色源：context.colors（ColorStrategy），本家族不允许主题豁免。
// 页面不要自 reserve 底栏高度——本家族的页面都是 push 进来的路由，
// 主壳底栏不覆盖 push 路由。

import 'package:flutter/material.dart';

import '../../../theme/context/colors.dart';
import '../nav/main.dart';

/// 设置页壳：灰底画布 + AppNavBar.standard + 列表。
///
/// [children] 与 [body] 二选一：常规设置页给 children（壳负责 ListView，
/// 底部留 24）；自带滚动结构的页面（如复用既有 body builder）给 body。
class SettingsPageScaffold extends StatelessWidget {
  const SettingsPageScaffold({
    super.key,
    required this.title,
    this.actions,
    this.children,
    this.body,
  }) : assert(
          (children == null) != (body == null),
          'children 与 body 必须二选一',
        );

  final String title;

  /// 传给 AppNavBar.standard 的顶部动作（如保存按钮）。
  final List<Widget>? actions;

  /// 分区序列（Header / Card / 行）。
  final List<Widget>? children;

  /// 自管滚动的页面主体（壳不再包 ListView）。
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 灰底画布：与卡面 surface 靠明度分层（对齐 app 设置页配方，不用投影）。
      backgroundColor: context.colors.scheme.surfaceContainerHighest,
      appBar: AppNavBar.standard(title: title, actions: actions),
      body: body ??
          ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: children ?? const <Widget>[],
          ),
    );
  }
}

/// 分区标题（卡外）：小号加重、弱色，与模块页同款观感。
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: c.textMuted,
        ),
      ),
    );
  }
}

/// 偏好白卡：卡面 surface、圆角 16、无投影无描边；水平 12 外距、底部 4。
///
/// [children] 直接放行级件（ListTile 等，自带内边距），行间插
/// [SettingsCardSeparator]；表单页/滑杆页传 [padding] 给内容留内边距。
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children, this.padding});

  final List<Widget> children;

  /// 内容内边距：缺省为 0（children 是 ListTile 等自排版行）；
  /// 表单/滑杆等裸内容传如 `EdgeInsets.symmetric(horizontal: 16, vertical: 12)`。
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors.scheme;
    final column = Column(mainAxisSize: MainAxisSize.min, children: children);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: padding != null
            ? Padding(padding: padding!, child: column)
            : column,
      ),
    );
  }
}

/// 卡内行分隔：左右缩进 16 的 1px 细线（画布色，弱于卡面）。
class SettingsCardSeparator extends StatelessWidget {
  const SettingsCardSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.colors.scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(
        height: 1,
        thickness: 1,
        color: cs.surfaceContainerHighest,
      ),
    );
  }
}
