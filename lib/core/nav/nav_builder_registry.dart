// 打破 nav_catalog ↔ 页面 的循环依赖：
// 需要引用具体 Page 的 builder 在 main / bootstrap 里 register，
// catalog 只通过 id 查找。

import 'package:flutter/widgets.dart';

typedef NavPageBuilder = Widget Function(BuildContext context);

final Map<String, NavPageBuilder> _builders = {};

void registerNavBuilder(String id, NavPageBuilder builder) {
  _builders[id] = builder;
}

NavPageBuilder? navBuilderOf(String id) => _builders[id];

Widget buildRegisteredNavPage(String id, BuildContext context) {
  final b = _builders[id];
  if (b == null) {
    return const Center(child: Text('入口未注册'));
  }
  return b(context);
}
