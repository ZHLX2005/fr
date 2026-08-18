// APK 自动更新宿主 —— 隐藏组件，挂在主屏（MainScreen）Stack 里。
//
// 挂载条件：ApkDownloadManager.state.autoDownloadOnUpdate == true
// （开关开启才创建；关闭即时销毁，生命周期观察者随之注销）。
//
// 职责（标准 auto-check 模式的"组件宿主"形态）：
//   1. 挂载即检查：maybeAutoCheck()（15min 节流；冷启动钩子已 force
//      检查过会被节流挡掉，钩子失败时这里是兜底）
//   2. App 回前台 → maybeAutoCheck()（节流）
//   3. 下载执行在 ApkDownloadManager 单例（Android 走 Foreground
//      Service），组件销毁不中断进行中的下载
//
// 为什么用隐藏组件而不是 main.dart 的 observer：
//   - 开关状态可感知（开→挂载，关→卸载），一处内聚
//   - DevTools widget 树里可见，易于调试
//   - 不污染 main.dart / MyApp

import 'dart:async';
import 'package:flutter/material.dart';
import '../lab/demos/api_test/api_download_manager.dart';

/// 条件挂载点：开关开启 → 挂载隐藏宿主；关闭 → 0x0 占位。
/// ValueListenableBuilder 响应开关变化，即时创建/销毁宿主。
class ApkAutoUpdateMount extends StatelessWidget {
  const ApkAutoUpdateMount({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ApkDownloadState>(
      valueListenable: ApkDownloadManager().state,
      builder: (context, s, _) {
        if (!s.autoDownloadOnUpdate) return const SizedBox.shrink();
        return const ApkAutoUpdateHost();
      },
    );
  }
}

/// 隐藏宿主本体：不可见（SizedBox.shrink），只承载生命周期逻辑。
class ApkAutoUpdateHost extends StatefulWidget {
  const ApkAutoUpdateHost({super.key});

  @override
  State<ApkAutoUpdateHost> createState() => _ApkAutoUpdateHostState();
}

class _ApkAutoUpdateHostState extends State<ApkAutoUpdateHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 挂载即检查（非 force：冷启动钩子已检查过则被 15min 节流挡掉）
    unawaited(ApkDownloadManager().maybeAutoCheck());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 双触发点之二：回前台（之二是冷启动钩子）
    if (state == AppLifecycleState.resumed) {
      unawaited(ApkDownloadManager().maybeAutoCheck());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}