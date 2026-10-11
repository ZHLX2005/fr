import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 认证中心授权页（App 内嵌 WebView）。
///
/// 返回用户完成授权后浏览器会去的那个回调地址（含 `code` 与 `state`），
/// 取消则返回 null。调用方拿它去 [UnifiedAuthService.completeSignIn]。
///
/// ── 为什么在 App 内拦 302，而不是真起一个 loopback 监听 ──────────────────
///
/// 授权回调地址形如 `http://127.0.0.1:<port>/callback`，能过认证中心的
/// 回环端口通配白名单。传统做法是 App 真在该端口起一个 HTTP 服务收这一发，
/// 但在 Android 上这条路有三个坑：进程被系统回收时监听就断了、
/// 部分 ROM 的省电策略会掐后台 socket、以及要处理"用户授权期间 App 被切到
/// 后台"的时序。而授权本来就发生在本 App 打开的 WebView 里 ——
/// 在 `onNavigationRequest` 里认出回调地址、直接从 URL 取走 code 并 prevent 掉这次导航，
/// 一个包都不用发出去。白名单要的是"地址形状合法"，不是"真有人在听"。
///
/// ── 为什么这个 WebView 不注入任何凭据 ────────────────────────────────────
///
/// 它只加载认证中心的授权页，用户名密码由用户亲手在那个页面输入。
/// 不预置 Cookie、不注入 JS、不代理请求。一旦为了"免登录"把 App 持有的
/// token 注进这个 WebView，就等于把凭据交给了一远程页面的执行环境。
class AuthWebViewPage extends StatefulWidget {
  final String authorizeUrl;

  /// 回调地址前缀。导航命中它即视为授权完成并拦下。
  final String redirectUri;

  /// 页面标题里显示的认证中心主机，让用户知道自己在往哪儿输密码。
  final String identityHost;

  const AuthWebViewPage({
    super.key,
    required this.authorizeUrl,
    required this.redirectUri,
    this.identityHost = '统一认证中心',
  });

  @override
  State<AuthWebViewPage> createState() => _AuthWebViewPageState();
}

class _AuthWebViewPageState extends State<AuthWebViewPage> {
  final Completer<String?> _result = Completer<String?>();
  late final WebViewController _controller;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (p >= 95 && mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (req) {
            if (req.url.startsWith(widget.redirectUri)) {
              // 授权完成：取走 code 并阻止这次导航（没有服务在听，放过去会白屏）
              _finish(req.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (e) {
            // 只在还没拿到结果时暴露错误：授权完成后 WebView 可能仍在加载别的资源，
            // 那时再 setState 会把一个已成功的流程显示成失败。
            if (!_result.isCompleted && mounted) {
              setState(() {
                _error = '加载认证中心失败：${e.description}';
                _loading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authorizeUrl));
  }

  void _finish(String url) {
    if (!_result.isCompleted) _result.complete(url);
    if (mounted) Navigator.of(context).pop(url);
  }

  void _cancel() {
    if (!_result.isCompleted) _result.complete(null);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      // 物理返回键走 _cancel 而不是直接 pop：
      // 直接 pop 会让 _result 永远不 complete，调用方 await 卡死。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('统一登录'),
              Text(
                widget.identityHost,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: '取消登录',
            onPressed: _cancel,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新加载',
              onPressed: () {
                if (!mounted) return;
                setState(() {
                  _error = null;
                  _loading = true;
                });
                _controller.loadRequest(Uri.parse(widget.authorizeUrl));
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off, size: 40, color: scheme.error),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: () =>
                            _controller.loadRequest(Uri.parse(widget.authorizeUrl)),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
