import 'package:flutter/material.dart';

import '../../../api/mnws/mnws.dart';
import 'nxkv/nxkv_page.dart';
import 'nxnx/nxnx_page.dart';

// `MnWsAppTarget`（哪台 PC 上的哪个应用）在 `api/mnws/mnws_models.dart` ——
// 它不带任何 widget 知识，而 `api/` 下的应用客户端要用它。留在这里会让
// api → UI 反向依赖（nx-kv 的 controller 搬去 api 层时撞到过）。
// 这里只留「fr 认得哪些应用、各自给什么页面」这张表 —— 那是 UI 层的知识。

/// 一个 **fr 认得的应用**：它是什么、点开给什么页面。
///
/// mn-ws 自己不认识任何服务（它只按标识路由）；「这个标识是 nx-nx、
/// 该给它模板列表」是 **fr** 的知识。
///
/// 往后接新应用：接口客户端与它的编排/解析放 `lib/api/mnws/<应用>/`，
/// **页面只放** `lib/lab/demos/mnws/<应用>/`，然后在这里加一条。
class MnWsAppView {
  /// 路由标识（与目录里的 `app` 一致）。
  final String app;

  /// 显示名。
  final String title;

  /// 一句话说明这个应用是干什么的。
  final String description;

  /// 造出这个应用的整页。
  final Widget Function(BuildContext context, MnWsAppTarget target) builder;

  const MnWsAppView({
    required this.app,
    required this.title,
    required this.description,
    required this.builder,
  });
}

/// fr 认识的应用（应用识别表）。
const List<MnWsAppView> kMnWsAppViews = <MnWsAppView>[
  MnWsAppView(
    app: 'nx-nx',
    title: 'nx-nx 项目生成器',
    description: '按模板生成项目：新建项目 / 模板 / 脚本（原生界面）',
    builder: _nxNxBuilder,
  ),
  MnWsAppView(
    app: 'nx-kv',
    title: 'nx-kv 任务队列',
    description: '本机任务队列：领活 / 看正文 / 交反馈（原生界面，协议由契约生成）',
    builder: _nxKvBuilder,
  ),
];

Widget _nxNxBuilder(BuildContext context, MnWsAppTarget target) =>
    NxNxPage(target: target);

Widget _nxKvBuilder(BuildContext context, MnWsAppTarget target) =>
    NxKvPage(target: target);

/// 按路由标识找应用；**找不到返回 null** —— 那说明 fr 不认得它，
/// 得走通用请求台，而不是假装认得。
MnWsAppView? appViewOf(String app) {
  final key = app.trim();
  for (final v in kMnWsAppViews) {
    if (v.app == key) return v;
  }
  return null;
}
