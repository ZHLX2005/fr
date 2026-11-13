import 'package:flutter/material.dart';

import '../../../api/mnws/mnws.dart';
import 'nxnx/nxnx_page.dart';

/// 一次「点某个应用」的上下文。
///
/// 为什么要有它：多台 PC 同时接入时，同一个应用可能出现在好几台机器上
/// （两台都跑 nx-nx）。点开时必须知道**点的是哪台上的那一个** ——
/// 请求要带上那台 PC 的 bridgeId，否则会打到路由表指向的那台去。
class MnWsAppTarget {
  /// 这台 PC 在目录里的分组。
  final MnWsPcGroup pc;

  /// 这台 PC 上的这个应用。
  final MnWsPcApp pcApp;

  const MnWsAppTarget({required this.pc, required this.pcApp});

  /// 路由标识。
  String get app => pcApp.app;

  /// 电脑名。
  String get pcName => pc.name;

  /// 目标 PC 的 bridgeId（请求时带上）。
  String get bridgeId => pc.bridgeId;
}

/// 一个 **fr 认得的应用**：它是什么、点开给什么页面。
///
/// mn-ws 自己不认识任何服务（它只按标识路由）；「这个标识是 nx-nx、
/// 该给它模板列表」是 **fr** 的知识。
///
/// 往后接新应用：接口客户端放 `lib/api/mnws/<应用>/`，
/// 页面放 `lib/lab/demos/mnws/<应用>/`，然后在这里加一条。
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
    description: '按模板生成项目：列模板、看说明、预览要生成的文件',
    builder: _nxNxBuilder,
  ),
];

Widget _nxNxBuilder(BuildContext context, MnWsAppTarget target) =>
    NxNxPage(target: target);

/// 按路由标识找应用；**找不到返回 null** —— 那说明 fr 不认得它，
/// 得走通用请求台，而不是假装认得。
MnWsAppView? appViewOf(String app) {
  final key = app.trim();
  for (final v in kMnWsAppViews) {
    if (v.app == key) return v;
  }
  return null;
}
