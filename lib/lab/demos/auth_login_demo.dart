import 'package:flutter/material.dart';

import '../lab_container.dart';
import 'auth_login/const_auth_login.dart';
import 'auth_login/qr_approve_panel.dart';
import 'auth_login/self_test_panel.dart';
import 'auth_login/unified_login_panel.dart';

/// 统一登录 / 扫码批准 Lab。
///
/// 三个 Tab 各自对应一件需要分开验证的事：
///   1. 统一登录 —— 能不能拿到认证中心身份（WebView + PKCE 授权码）
///   2. 扫码批准 —— 真机拿相机扫 PC 的码并批准
///   3. 本机自测 —— 不依赖相机，一台设备跑完闭环并验证防转发性质
///
/// 第 3 个 Tab 不是冗余。没有它，"扫码登录"这件事在只有一台手机的环境下
/// 完全无法验证，而前两个 Tab 全绿也只能证明"能连上认证中心"，
/// 证明不了状态机与 qr_ctx 绑定是对的。
///
/// 文件按项目规范拆分：demo 本体保持扁平，辅助面板放同名子目录，
/// 常量集中在 const_auth_login.dart。
class AuthLoginDemo extends DemoPage {
  @override
  String get title => AuthLoginConst.title;

  @override
  String get description => AuthLoginConst.description;

  @override
  String get slug => 'auth-login';

  /// 三个面板各自是完整的交互界面（含自己的 AppBar 需求与相机预览），
  /// 外层 DemoDetailPage 的包装条在这里是多余的。
  @override
  bool get preferFullScreen => false;

  @override
  Widget buildPage(BuildContext context) => const _AuthLoginPage();
}

class _AuthLoginPage extends StatefulWidget {
  const _AuthLoginPage();

  @override
  State<_AuthLoginPage> createState() => _AuthLoginPageState();
}

class _AuthLoginPageState extends State<_AuthLoginPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 用 TabBarView 而不是滚动堆叠三个面板：相机预览需要占满剩余高度，
    // 堆在一起会让 MobileScanner 被压成一条看不懂的窄带。
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final label in AuthLoginConst.tabLabels)
              Tab(text: label, height: 44),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              UnifiedLoginPanel(),
              QrApprovePanel(),
              SelfTestPanel(),
            ],
          ),
        ),
      ],
    );
  }
}

void registerAuthLoginDemo() {
  demoRegistry.register(AuthLoginDemo());
}
