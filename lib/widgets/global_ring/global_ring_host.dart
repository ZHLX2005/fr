// 全局圆环宿主 —— 挂在 MaterialApp.builder 上，位于 Navigator 之上。
//
// 为什么是 builder 而不是某个页面的 Stack：
//   MaterialApp 的 builder 拿到的 child 就是 Navigator（见 flutter
//   material/app.dart 的 _materialBuilder），把它包进 Stack 就等于高于
//   所有 route —— tab 页、push 出去的全屏页、showDialog、bottom sheet
//   全都在圆环下面。放在 MainScreen 的 Stack 里只能盖住 tab 之间，
//   push 出去的路由就盖不住了。
//
// builder 的 context 里有 Theme / MediaQuery / Directionality /
// ScaffoldMessenger，唯独没有 Navigator 和 Scaffold —— 所以弹面板要用
// 传进来的 navigatorKey 取一个带 Navigator 的 context。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ring_bubble.dart';
import 'ring_enabled_provider.dart';
import 'ring_submit_sheet.dart';

class GlobalRingHost extends ConsumerStatefulWidget {
  const GlobalRingHost({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  /// MaterialApp.builder 传进来的 Navigator。
  final Widget child;

  /// 根 Navigator 的 key，用来取"带 Navigator 的 context"弹提交面板。
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  ConsumerState<GlobalRingHost> createState() => _GlobalRingHostState();
}

class _GlobalRingHostState extends ConsumerState<GlobalRingHost> {
  /// 面板已打开。圆环浮在 Navigator 之上，面板弹起后圆环依然可点，
  /// 不挡一下会叠出第二个面板。
  bool _sheetOpen = false;

  Future<void> _openSubmit() async {
    if (_sheetOpen) return;
    final navContext = widget.navigatorKey.currentContext;
    if (navContext == null) return;

    _sheetOpen = true;
    bool submitted;
    try {
      submitted = await showRingSubmitSheet(navContext);
    } finally {
      _sheetOpen = false;
    }

    // SnackBar 挂在 MaterialApp 的 ScaffoldMessenger 上（它在 builder 之上），
    // 所以这里用宿主自己的 context 就能弹，且会渲染在当前页的 Scaffold 里。
    if (!submitted || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已提交到 KV 清单'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(ringEnabledProvider);

    return Stack(
      // 显式声明：builder 层虽然有 Directionality，但这里没必要依赖它，
      // 写死 LTR 让圆环的定位语义在任何语言环境下都一致。
      textDirection: TextDirection.ltr,
      // 用默认的 StackFit.loose 即可：Navigator 内部的 Overlay 在
      // constraints.biggest 有限时直接 size = constraints.biggest
      // （见 flutter widgets/overlay.dart 的 _RenderTheatre.performLayout），
      // 所以非定位子节点照样撑满全屏，页面布局不受这层 Stack 影响。
      children: [
        widget.child,
        if (enabled) RingBubble(onTap: _openSubmit),
      ],
    );
  }
}
